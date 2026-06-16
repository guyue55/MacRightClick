import Foundation
import Darwin

/// FinderSync 扩展写入、宿主 App 消费的右键动作事件。
public struct SharedActionEvent: Codable, Equatable, Identifiable {
    public let id: String
    public let createdAt: TimeInterval
    public let actionId: String
    public let paths: [String]
}

/// dispatcher 消费一个 PendingAction 时拿到的「租约」凭证（P1-2 事务化）：
/// - `event` 是真正要执行的动作；
/// - `inFlightURL` 指向已被搬到 InFlightActions/<pid>/ 的实体文件；
/// - 跑完动作后必须调用 `SharedStorageManager.acknowledge(_:)` 删除 InFlight 文件，
///   否则进程崩溃后会被 `reclaimAbandonedInFlightActions` 复活重跑。
/// `inFlightURL == nil` 仅用于旧版兼容路径（pending_action.json）。
public struct PendingActionLease: Equatable {
    public let event: SharedActionEvent
    public let inFlightURL: URL?

    public init(event: SharedActionEvent, inFlightURL: URL?) {
        self.event = event
        self.inFlightURL = inFlightURL
    }
}

/// 共享日志级别。生产环境默认只记录必要信息，调试日志需要用户显式开启。
public enum SharedLogLevel {
    case info
    case debug
    case error
}

/// 共享存储管理器，作为宿主主程序与插件扩展之间的数据交换与配置共享层。
/// 集中处理宿主主程序与 FinderSync 扩展之间的配置、队列和诊断数据。
public final class SharedStorageManager {
    public static let shared = SharedStorageManager()

    public enum Keys {
        public static let enableDebugLogging = "enable_debug_logging"
        public static let favoriteActionIds = "favorite_action_ids"
        public static let watchedDirectoryPaths = "watched_directory_paths"
    }
    
    private let appGroupIdentifier = "group.guyue.RightClickAssistant"
    private let extensionBundleIdentifier = "guyue.RightClickAssistant.Extension"
    private let configQueue = DispatchQueue(label: "guyue.RightClickAssistant.config")

    /// 仅供测试注入：每次 `getBool(forKey:)` 被调用都会先回调此 closure。
    /// 用于验证菜单渲染主路径是否真的命中了 ActionConfigCache，没有穿透到底层 IO。
    /// 生产代码不要依赖此属性。
    public var observeGetBoolForTesting: ((String) -> Void)?

    private init() {}
    
    /// 获取真实的物理 Home 目录。
    private func getRealHomeDirectory() -> String {
        let pw = getpwuid(getuid())
        if let home = pw?.pointee.pw_dir {
            return FileManager.default.string(withFileSystemRepresentation: home, length: Int(strlen(home)))
        }
        return NSHomeDirectory()
    }
    
    /// 获取当前进程是否是在 Extension (FinderSync) 沙盒进程中运行
    public var isRunningInExtension: Bool {
        let bid = Bundle.main.bundleIdentifier ?? ""
        return bid.contains("Extension")
    }
    
    /// 核心共享容器目录定位器。
    /// 行为由 `Distribution` 编译期常量决定：
    /// - MAS 路线：必须走 App Group 容器；若不可写视为配置错误，记 error 并兜底到主 App 自身 NSHomeDirectory
    /// - website 路线：直接走 Extension Container（~/Library/Containers/<extBundle>/Data），主 App 非 sandbox 时可正常读写
    public var sharedContainerURL: URL {
        if Distribution.usesAppGroup {
            if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
                let testDir = appGroupURL.appendingPathComponent(".test_write")
                do {
                    try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true, attributes: nil)
                    try FileManager.default.removeItem(at: testDir)
                    return appGroupURL
                } catch {
                    AppLog.error("App Group 容器不可写，分发路线 = \(Distribution.route.rawValue)", category: .storage)
                    // 不静默降级到 Extension Container：MAS 沙盒下读不到，会再次失败。
                    // 兜底到主 App 自身 home，至少避免空指针；此路径下队列与配置不会跨进程互通，调用方应通过日志发现配置错。
                    return URL(fileURLWithPath: NSHomeDirectory())
                }
            }
            AppLog.error("App Group containerURL 返回 nil，分发路线 = \(Distribution.route.rawValue)", category: .storage)
            return URL(fileURLWithPath: NSHomeDirectory())
        }

        guard Distribution.allowsCrossContainerExchange else {
            AppLog.error("当前分发路线既不允许 App Group 也不允许跨 Container 交换", category: .storage)
            return URL(fileURLWithPath: NSHomeDirectory())
        }

        // website 路线：跨 Container 读 Extension 沙盒目录。
        let path: String
        if isRunningInExtension {
            path = NSHomeDirectory()
        } else {
            let realHome = getRealHomeDirectory()
            path = (realHome as NSString).appendingPathComponent("Library/Containers/\(extensionBundleIdentifier)/Data")
        }

        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }
    
    /// 共享的 pending_action.json 交换文件 URL，用于多进程数据负载传输
    /// 保留旧路径仅用于兼容旧版本扩展或历史测试工具。新链路使用 pendingActionsDirectoryURL 队列。
    public var pendingActionURL: URL {
        return sharedContainerURL.appendingPathComponent("pending_action.json")
    }

    /// 共享动作队列目录。每次右键点击写入独立 UUID JSON 文件，避免连续点击覆盖单一 pending 文件。
    public var pendingActionsDirectoryURL: URL {
        let url = sharedContainerURL.appendingPathComponent("PendingActions", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }
    
    /// 无法解析的失败队列事件隔离目录，便于诊断不丢数据。
    public var failedActionsDirectoryURL: URL {
        let url = sharedContainerURL.appendingPathComponent("FailedActions", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    /// 「已被某进程 lease、但还没确认完成」的事件目录。每个进程独占一个 PID 子目录，
    /// 这样多实例（极端情况下）互不踩，并且 reclaim 时只搬「不是当前进程的」目录。
    /// 设计目标（P1-2）：
    /// - 旧实现 decode 之后立即 unconditional 删除，dispatcher 中途崩溃就丢事件；
    /// - 改成「PendingActions/X.json → InFlightActions/<pid>/X.json」的原子 rename，
    ///   dispatcher 跑完才 ack 删除 InFlight 文件；
    /// - 启动时调用 `reclaimAbandonedInFlightActions`：把不属于当前进程的 InFlight
    ///   文件搬回 PendingActions，再清理空 PID 目录。
    public var inFlightActionsDirectoryURL: URL {
        let url = sharedContainerURL.appendingPathComponent("InFlightActions", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    /// 当前进程独占的 InFlight 子目录。
    private var currentProcessInFlightDirectoryURL: URL {
        let pid = ProcessInfo.processInfo.processIdentifier
        let url = inFlightActionsDirectoryURL.appendingPathComponent(String(pid), isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    /// 共享的 config.json 配置交换文件 URL。
    public var configURL: URL {
        return sharedContainerURL.appendingPathComponent("config.json")
    }
    
    public var pendingActionCount: Int {
        return (try? FileManager.default.contentsOfDirectory(atPath: pendingActionsDirectoryURL.path))?
            .filter { $0.hasSuffix(".json") }.count ?? 0
    }

    public var failedActionCount: Int {
        return (try? FileManager.default.contentsOfDirectory(atPath: failedActionsDirectoryURL.path))?
            .filter { $0.hasSuffix(".json") }.count ?? 0
    }

    /// 共享日志文件 URL。
    public var logFileURL: URL {
        let logsDir = sharedContainerURL.appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: nil)
        return logsDir.appendingPathComponent("extension.log")
    }
    
    // MARK: - 统一日志写入接口
    /// 详细调试日志开关。默认关闭，避免生产环境持续记录用户路径与菜单渲染细节。
    public var isDebugLoggingEnabled: Bool {
        return getBool(forKey: Keys.enableDebugLogging, defaultValue: false)
    }

    /// 默认监听的 Finder 常用目录。不会创建不存在的目录。
    public static func defaultWatchedDirectoryPaths(
        homePath: String,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [String] {
        return ["Desktop", "Downloads", "Documents"]
            .map { (homePath as NSString).appendingPathComponent($0) }
            .filter(fileExists)
    }

    public var watchedDirectoryURLs: [URL] {
        let defaultPaths = Self.defaultWatchedDirectoryPaths(homePath: getRealHomeDirectory())
        let paths = getStringArray(forKey: Keys.watchedDirectoryPaths, defaultValue: defaultPaths)
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// 将运行日志追加写入共享日志文件，方便后续排查。
    public func writeLog(_ message: String, level: SharedLogLevel = .info) {
        if level == .debug && !isDebugLoggingEnabled {
            return
        }
        // 切换到 OSLog：subsystem=guyue.RightClickAssistant, category=storage。
        // 旧的 extension.log 文件不再追加（logFileURL 仍保留，仅用于「导出旧日志」按钮的只读访问）。
        switch level {
        case .info:  AppLog.info(message, category: .storage)
        case .debug: AppLog.debug(message, category: .storage)
        case .error: AppLog.error(message, category: .storage)
        }
    }

    public func writeDebugLog(_ message: String) {
        writeLog(message, level: .debug)
    }

    // MARK: - 动作队列管理

    /// 将一个右键动作加入共享队列。
    @discardableResult
    public func enqueueAction(actionId: String, paths: [String]) throws -> URL {
        let event = SharedActionEvent(
            id: UUID().uuidString,
            createdAt: Date().timeIntervalSince1970,
            actionId: actionId,
            paths: paths
        )

        let timestamp = Int64(event.createdAt * 1000)
        let fileName = "\(timestamp)-\(event.id).json"
        let url = pendingActionsDirectoryURL.appendingPathComponent(fileName)
        let data = try JSONEncoder().encode(event)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 消费队列中所有待处理动作的 lease 形式（P1-2 事务化）：
    /// 1. 把 PendingActions/*.json 原子 rename 到 InFlightActions/<pid>/，
    ///    避免「decode 成功 → 立即删除 → dispatcher 崩溃」之间丢事件；
    /// 2. dispatcher 跑完后必须显式 `acknowledge`，否则下次启动 `reclaimAbandonedInFlightActions`
    ///    会把它搬回 PendingActions 重跑（at-least-once）；
    /// 3. decode 失败的文件直接搬到 FailedActions 隔离，不阻塞队列。
    public func consumePendingActionLeases() -> [PendingActionLease] {
        var leases: [PendingActionLease] = []
        let directoryURL = pendingActionsDirectoryURL

        let queuedURLs = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let sortedURLs = queuedURLs
            .filter { $0.pathExtension == "json" }
            .sorted { left, right in
                let leftCreated = (try? left.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rightCreated = (try? right.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                if leftCreated == rightCreated {
                    return left.lastPathComponent < right.lastPathComponent
                }
                return leftCreated < rightCreated
            }

        let inFlightDir = currentProcessInFlightDirectoryURL

        for url in sortedURLs {
            // Step 1: 原子 rename 到 InFlight。极小概率同名时附加 UUID 前缀。
            var inFlightURL = inFlightDir.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: inFlightURL.path) {
                inFlightURL = inFlightDir.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
            }
            do {
                try FileManager.default.moveItem(at: url, to: inFlightURL)
            } catch {
                writeLog("[SharedStorage] 队列文件搬入 InFlight 失败，跳过本轮: \(url.lastPathComponent), error: \(error.localizedDescription)", level: .error)
                continue
            }

            // Step 2: decode；失败搬到 FailedActions，不进 lease。
            do {
                let data = try Data(contentsOf: inFlightURL)
                let event = try JSONDecoder().decode(SharedActionEvent.self, from: data)
                leases.append(PendingActionLease(event: event, inFlightURL: inFlightURL))
            } catch {
                writeLog("[SharedStorage] 无法解析队列动作文件，已隔离至 FailedActions: \(inFlightURL.lastPathComponent), error: \(error.localizedDescription)", level: .error)
                let failedURL = failedActionsDirectoryURL.appendingPathComponent(inFlightURL.lastPathComponent)
                try? FileManager.default.moveItem(at: inFlightURL, to: failedURL)
            }
        }

        // 兼容旧 pending_action.json 单文件路径：直接消费（无事务），保持向后兼容。
        // 新版扩展不会再写此文件，留下来仅为升级残留。
        if let legacyEvent = consumeLegacyPendingActionEvent() {
            leases.append(PendingActionLease(event: legacyEvent, inFlightURL: nil))
        }

        return leases.sorted {
            if $0.event.createdAt == $1.event.createdAt {
                return $0.event.id < $1.event.id
            }
            return $0.event.createdAt < $1.event.createdAt
        }
    }

    /// 标记 lease 已被 dispatcher 安全消费完毕，可以删除 InFlight 文件。
    /// 必须在 dispatcher 返回后调用，否则进程崩溃会让事件被 reclaim 重跑。
    public func acknowledge(_ lease: PendingActionLease) {
        guard let url = lease.inFlightURL else { return }  // legacy 路径无 InFlight 文件
        try? FileManager.default.removeItem(at: url)
    }

    /// 把不属于当前进程的 InFlight 文件搬回 PendingActions，让下一轮消费循环重新处理。
    /// 应在 AppDelegate.applicationDidFinishLaunching 启动消费循环之前调用一次。
    /// 不会动当前进程目录（避免和正在跑的 dispatcher 抢文件）。
    public func reclaimAbandonedInFlightActions() {
        let parent = inFlightActionsDirectoryURL
        let currentPID = String(ProcessInfo.processInfo.processIdentifier)

        let pidDirs = (try? FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for pidDir in pidDirs {
            if pidDir.lastPathComponent == currentPID { continue }
            let isDir = (try? pidDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }

            let orphanFiles = (try? FileManager.default.contentsOfDirectory(
                at: pidDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for orphan in orphanFiles where orphan.pathExtension == "json" {
                let target = pendingActionsDirectoryURL.appendingPathComponent(orphan.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                do {
                    try FileManager.default.moveItem(at: orphan, to: target)
                    writeLog("[SharedStorage] reclaim 把孤儿 InFlight 事件搬回 PendingActions: \(orphan.lastPathComponent)", level: .info)
                } catch {
                    writeLog("[SharedStorage] reclaim 搬回失败: \(orphan.lastPathComponent), error: \(error.localizedDescription)", level: .error)
                }
            }

            // 清空 PID 目录后清理（保持 InFlight 树整洁）。
            try? FileManager.default.removeItem(at: pidDir)
        }
    }

    /// 旧 API：tin shell，内部走 lease 路径并立即 ack。
    /// 不再推荐使用，仅为已有调用点（测试 / 旧版本工具）做兼容。
    /// 注意：立即 ack 等于"无事务"，调用方必须自己保证 dispatcher 不会崩。
    @available(*, deprecated, message: "改用 consumePendingActionLeases + acknowledge 以获得崩溃安全语义")
    public func consumePendingActionEvents() -> [SharedActionEvent] {
        let leases = consumePendingActionLeases()
        leases.forEach { acknowledge($0) }
        return leases.map { $0.event }
    }

    private func consumeLegacyPendingActionEvent() -> SharedActionEvent? {
        let legacyURL = pendingActionURL
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return nil
        }

        defer { try? FileManager.default.removeItem(at: legacyURL) }

        guard let data = try? Data(contentsOf: legacyURL),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let actionId = jsonObject["actionId"] as? String,
              let paths = jsonObject["paths"] as? [String] else {
            writeLog("[SharedStorage] 旧 pending_action.json 结构无效，已丢弃")
            return nil
        }

        return SharedActionEvent(
            id: "legacy-\(UUID().uuidString)",
            createdAt: Date().timeIntervalSince1970,
            actionId: actionId,
            paths: paths
        )
    }
    
    // MARK: - 统一配置管理转换接口（双写机制与多级兜底）
    
    /// 加载共享的 JSON 配置文件
    private func loadConfig() -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return [:]
        }
        return json
    }
    
    /// 写入共享的 JSON 配置文件。通过串行队列保护并发写入，避免 load-modify-save 竞态。
    private func saveConfig(_ config: [String: Any]) {
        configQueue.sync {
            if let data = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) {
                try? data.write(to: configURL, options: .atomic)
            }
        }
    }
    
    /// 获取指定菜单项是否启用
    /// 优先从 App Group UserDefaults 中读取配置，当不可用时无缝降级读取 config.json 共享配置，最后回退至默认值
    public func getBool(forKey key: String, defaultValue: Bool = true) -> Bool {
        observeGetBoolForTesting?(key)
        // A. 优先尝试从官方原生的 App Group UserDefaults 读取
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
           sharedDefaults.object(forKey: key) != nil {
            return sharedDefaults.bool(forKey: key)
        }
        
        // B. 降级：从 config.json 文件中读取
        let config = loadConfig()
        if let val = config[key] as? Bool {
            return val
        }
        return defaultValue
    }

    public func getStringArray(forKey key: String, defaultValue: [String] = []) -> [String] {
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
           let values = sharedDefaults.stringArray(forKey: key) {
            return values
        }

        let config = loadConfig()
        if let values = config[key] as? [String] {
            return values
        }
        return defaultValue
    }

    /// 按动作自身默认值和共享配置判断是否启用，供 Finder 菜单与托盘菜单共用。
    public func isActionEnabled(_ action: MenuAction) -> Bool {
        return getBool(forKey: "enable_action_\(action.actionId)", defaultValue: action.isEnabledByDefault)
    }

    public var favoriteActionIds: [String] {
        return getStringArray(forKey: Keys.favoriteActionIds)
    }

    public func isFavoriteAction(_ action: MenuAction) -> Bool {
        return favoriteActionIds.contains(action.actionId)
    }
    
    /// 写入指定菜单项的启用状态（在宿主设置界面变更配置时调用）
    /// 同时双写到 App Group UserDefaults 以及 config.json，确保在任何签名沙盒策略下都必定穿透
    public func setBool(_ value: Bool, forKey key: String) {
        // A. 写入 App Group UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.set(value, forKey: key)
            sharedDefaults.synchronize()
        }
        
        // B. 双写至 config.json 文件中
        var config = loadConfig()
        config[key] = value
        saveConfig(config)
    }

    public func setStringArray(_ values: [String], forKey key: String) {
        let uniqueValues = Array(NSOrderedSet(array: values)).compactMap { $0 as? String }

        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.set(uniqueValues, forKey: key)
            sharedDefaults.synchronize()
        }

        var config = loadConfig()
        config[key] = uniqueValues
        saveConfig(config)
    }

    public func setAction(_ action: MenuAction, favorite: Bool) {
        var ids = favoriteActionIds
        if favorite {
            if !ids.contains(action.actionId) {
                ids.append(action.actionId)
            }
        } else {
            ids.removeAll { $0 == action.actionId }
        }
        setStringArray(ids, forKey: Keys.favoriteActionIds)
    }

    /// 移除指定配置值，让后续读取回到默认值。用于恢复默认设置和测试隔离。
    public func removeValue(forKey key: String) {
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.removeObject(forKey: key)
            sharedDefaults.synchronize()
        }

        var config = loadConfig()
        config.removeValue(forKey: key)
        saveConfig(config)
    }
}

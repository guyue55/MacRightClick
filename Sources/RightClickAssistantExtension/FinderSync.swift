import Cocoa
import FinderSync
import Darwin

// MARK: - FinderSync 主插件
@objc(FinderSync)
class FinderSync: FIFinderSync {
    private static let cutStateChangedNotification = Notification.Name("guyue.RightClickAssistant.cutStateChanged")
    
    // MARK: - ActionTagMapper (双向唯一整数 Tag 映射表)
    // 使用稳定的整数 tag 传递菜单动作标识，避免依赖 representedObject。
    private struct MenuSelection: Equatable {
        let actionId: String
        let invocationKind: ActionInvocationKind
    }

    private static var tagToSelection: [Int: MenuSelection] = [:]
    private static var nextTag: Int = 1000
    private var lastCutBadgePaths: Set<String> = []
    private var currentObservedPathCount = 0
    private lazy var heartbeatStore = ExtensionHeartbeatStore(
        fileURL: SharedStorageManager.shared.extensionHeartbeatURL
    )
    
    private static func getTag(
        for actionId: String,
        invocationKind: ActionInvocationKind
    ) -> Int {
        let selection = MenuSelection(actionId: actionId, invocationKind: invocationKind)
        if let existingTag = tagToSelection.first(where: { $0.value == selection })?.key {
            return existingTag
        }
        let assignedTag = nextTag
        tagToSelection[assignedTag] = selection
        nextTag += 1
        return assignedTag
    }
    
    private static func getSelection(for tag: Int) -> MenuSelection? {
        return tagToSelection[tag]
    }
    
    /// 当用户点击菜单项时的回调函数。
    @objc func actionMenuItemSelected(_ sender: NSMenuItem) {
        let tag = sender.tag
        logToSharedContainer("[FinderSync] [actionMenuItemSelected] 收到菜单点击事件，Tag: \(tag)", level: .debug)
        
        guard let selection = FinderSync.getSelection(for: tag) else {
            logToSharedContainer("[FinderSync] [actionMenuItemSelected] 错误: 无法根据 Tag \(tag) 映射出动作 ID")
            return
        }

        let actionId = selection.actionId
        // 实时获取当前选中的文件/目录路径，避免使用创建菜单时的静态路径数据。
        let controller = FIFinderSyncController.default()
        let targets: [URL]
        switch selection.invocationKind {
        case .items:
            targets = controller.selectedItemURLs() ?? []
        case .container:
            targets = controller.targetedURL().map { [$0] } ?? []
        }
        
        guard !targets.isEmpty else {
            logToSharedContainer("[FinderSync] [actionMenuItemSelected] 错误: 系统返回选中的物理路径为空")
            return
        }
        
        logToSharedContainer("[FinderSync] [actionMenuItemSelected] 解析动作成功: \(actionId), 目标路径总数: \(targets.count)", level: .debug)
        
        // 1. 写入中介共享动作队列文件
        let paths = targets.map { $0.path }

        do {
            let eventURL = try SharedStorageManager.shared.enqueueAction(
                actionId: actionId,
                paths: paths,
                invocationKind: selection.invocationKind
            )
            logToSharedContainer("[FinderSync] [actionMenuItemSelected] 成功向中介队列写入动作参数: \(eventURL.lastPathComponent)", level: .debug)
        } catch {
            logToSharedContainer("[FinderSync] [actionMenuItemSelected] 错误: 写入共享动作队列失败: \(error.localizedDescription)")
            return
        }
        
        // 2. 发送分布式空信号，通知宿主消费队列。
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("guyue.RightClickAssistant.triggerActionSignal"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        
        logToSharedContainer("[FinderSync] [actionMenuItemSelected] 已发出动作触发信号", level: .debug)
        
        // 3. 仅在宿主 App 未运行时才拉起；已运行时 DistributedNotification 已足够唤醒消费队列。
        Self.ensureHostRunning()
    }
    
    override init() {
        super.init()
        
        logToSharedContainer("[FinderSync] 插件初始化启动...")
        
        // 1. 注册原生 'cut' 角标图像
        if let badgeImage = NSImage(systemSymbolName: "scissors", accessibilityDescription: "已剪切") {
            FIFinderSyncController.default().setBadgeImage(badgeImage, label: "已剪切", forBadgeIdentifier: "cut")
            logToSharedContainer("[FinderSync] 成功注册 'cut' 原生角标图像 (scissors)", level: .debug)
        } else {
            logToSharedContainer("[FinderSync] 警告: 无法加载 SF Symbol 'scissors'")
        }
        
        // 2. 设置并应用我们需要监控的访达路径目录
        updateObservedDirectories()
        
        // 3. 监听来自主程序的共享配置变更通知，以便及时刷新右键与角标
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(configChanged),
            name: Notification.Name("guyue.RightClickAssistant.configChanged"),
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(cutStateChanged),
            name: Self.cutStateChangedNotification,
            object: nil
        )
        
        // 4. 在插件进程中也初始化默认动作集，以便直接在插件中分发执行
        DefaultActionRegistry.registerAll()

        // 5. 预热进程内缓存：把启用/收藏配置一次性读入，避免菜单渲染主路径同步穿透到 UserDefaults / config.json。
        //    同时把所有依赖 Launch Services 的 bundleId 一次性解析，避免 menu(for:) 阶段同步查询 NSWorkspace。
        ActionConfigCache.shared.preheat()
        let bundleIds = ActionDispatcher.shared.allActions.compactMap { $0.associatedBundleIdentifier }
        InstalledAppRegistry.shared.preheat(bundleIds)

        // 6. 主 App 是状态栏图标与设置面板的唯一宿主。
        //    用户若曾强退主 App，菜单栏图标会消失；这里在 Extension 初始化时拉一次，
        //    让"重启 Finder / 重新进入受监控目录"就能把图标找回来，
        //    无需用户手动去 Launchpad 启动。
        Self.ensureHostRunning()
    }

    /// 检查并按需拉起主 App（状态栏图标 + 设置面板宿主）。
    /// 已在跑则什么都不做，依赖 Launch Services 的进程级去重。
    static func ensureHostRunning() {
        let hostBundleID = "guyue.RightClickAssistant"
        let isHostRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == hostBundleID
        }
        guard !isHostRunning else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: hostBundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.addsToRecentItems = false
        // activates 默认为 true 会抢焦点；主 App 是 .accessory，不会有窗口跳出，但还是显式关掉更稳。
        configuration.activates = false
        configuration.arguments = [LaunchPresentationPolicy.backgroundLaunchArgument]
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }
    
    @objc private func configChanged() {
        logToSharedContainer("[FinderSync] 收到配置变更，同步刷新内存缓存、监听路径与角标状态")
        updateObservedDirectories()
        refreshCutBadges()
        
        // 强行刷新监控目录以立即触发生效/清除角标
        let currentURLs = FIFinderSyncController.default().directoryURLs
        FIFinderSyncController.default().directoryURLs = currentURLs
    }

    @objc private func cutStateChanged() {
        logToSharedContainer("[FinderSync] 收到剪切状态变更，刷新 Finder 角标")
        refreshCutBadges()
    }

    private func refreshCutBadges() {
        let currentPaths = Set(FileCutClipboard.shared.cutURLs.map { $0.standardizedFileURL.path })
        let controller = FIFinderSyncController.default()

        for path in lastCutBadgePaths.subtracting(currentPaths) {
            controller.setBadgeIdentifier("", for: URL(fileURLWithPath: path))
        }

        for path in currentPaths {
            controller.setBadgeIdentifier("cut", for: URL(fileURLWithPath: path))
        }

        lastCutBadgePaths = currentPaths
    }
    
    override func requestBadgeIdentifier(for url: URL) {
        let cutPaths = Set(FileCutClipboard.shared.cutURLs.map { $0.standardizedFileURL.path })
        let currentPath = url.standardizedFileURL.path
        if cutPaths.contains(currentPath) {
            FIFinderSyncController.default().setBadgeIdentifier("cut", for: url)
            logToSharedContainer("[FinderSync] 成功在 \(url.lastPathComponent) 上渲染已剪切 'cut' 状态角标", level: .debug)
        } else {
            FIFinderSyncController.default().setBadgeIdentifier("", for: url)
        }
    }
    
    /// 获取沙盒外的真实用户 Home 目录
    private func getRealHomeDirectory() -> String {
        let pw = getpwuid(getuid())
        if let home = pw?.pointee.pw_dir {
            return FileManager.default.string(withFileSystemRepresentation: home, length: Int(strlen(home)))
        }
        return NSHomeDirectory()
    }
    
    /// 将日志写入统一 OSLog。调试日志默认不持久化，避免生产环境记录菜单渲染细节。
    private func logToSharedContainer(_ message: String, level: SharedLogLevel = .info) {
        switch level {
        case .info:  AppLog.info(message, category: .ext)
        case .debug: AppLog.debug(message, category: .ext)
        case .error: AppLog.error(message, category: .ext)
        }
    }
    
    /// 动态探测并应用需要监控的访达路径。
    private func updateObservedDirectories() {
        var observedURLs: Set<URL> = []
        let homePath = getRealHomeDirectory()
        
        // Finder 菜单范围与扩展的文件读取权限是两个边界。不能用 fileExists 过滤：
        // 受保护目录可能暂时不可读，但 Finder 仍可根据 directoryURLs 提供菜单。
        for folderURL in SharedStorageManager.shared.watchedDirectoryURLs {
            observedURLs.insert(folderURL.standardizedFileURL)
            logToSharedContainer("[FinderSync] 激活工作区监控: \(folderURL.path)", level: .debug)
        }
        
        let shouldEnableCloudCompat = SharedStorageManager.shared.isCloudCompatibilityEnabled
        
        if shouldEnableCloudCompat {
            logToSharedContainer("[FinderSync] 云盘特殊兼容已启用，正在激活云端监听...", level: .debug)
            
            for path in SharedStorageManager.cloudCompatibleDirectoryPaths(homePath: homePath) {
                observedURLs.insert(URL(fileURLWithPath: path, isDirectory: true))
                logToSharedContainer("[FinderSync] 激活云盘监控: \(path)", level: .debug)
            }
        }
        
        FIFinderSyncController.default().directoryURLs = observedURLs
        currentObservedPathCount = observedURLs.count
        writeHeartbeat(force: true)
        logToSharedContainer("[FinderSync] 监控目录注册成功，当前激活数量: \(observedURLs.count)")
    }

    private func writeHeartbeat(force: Bool) {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        heartbeatStore.record(
            observedPathCount: currentObservedPathCount,
            version: version,
            processID: ProcessInfo.processInfo.processIdentifier,
            force: force
        )
    }
    
    // MARK: - 核心：动态渲染右键菜单
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems
                || menuKind == .contextualMenuForContainer else {
            return nil
        }
        writeHeartbeat(force: false)

        // 获取当前选中项目或当前所在空项目容器路径
        let targetURLs: [URL]
        if menuKind == .contextualMenuForItems {
            targetURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        } else if menuKind == .contextualMenuForContainer {
            if let containerURL = FIFinderSyncController.default().targetedURL() {
                targetURLs = [containerURL]
            } else {
                targetURLs = []
            }
        } else { return nil }
        
        guard !targetURLs.isEmpty else { return nil }
        
        logToSharedContainer("[FinderSync] 右键菜单触发渲染, 类型: \(menuKind == .contextualMenuForItems ? "Items" : "Container"), 目标路径: \(targetURLs.map { $0.path })", level: .debug)
        
        let invocationKind: ActionInvocationKind = menuKind == .contextualMenuForContainer
            ? .container
            : .items
        let isContainer = invocationKind == .container
        
        let menu = NSMenu(title: "开源右键助手")
        
        // 从共享存储中加载需要显示的动作列表
        let dispatcher = ActionDispatcher.shared
        // 注：menu(for:) 主热路径不再直接读 SharedStorageManager；启用/收藏判定全部走 ActionConfigCache，
        // 已安装应用查询走 InstalledAppRegistry，避免在用户右键的瞬间触发同步 IO。

        // 打印当前 dispatcher 中注册的所有 actions，确保在当前进程内真的有注册动作
        let registeredAll = dispatcher.allActions
        logToSharedContainer("[FinderSync] 当前 ActionDispatcher 中注册的所有动作总数: \(registeredAll.count)", level: .debug)
        for action in registeredAll {
            logToSharedContainer("[FinderSync] 已注册 Action: ID = \(action.actionId), Title = \(action.localizedTitle), Category = \(action.category.rawValue)", level: .debug)
        }
        
        let cache = ActionConfigCache.shared
        let sections = FinderMenuLayoutBuilder.build(
            actions: dispatcher.allActions,
            mode: cache.menuLayoutMode,
            isEnabled: { action in
                cache.isEnabled(action.actionId, default: action.isEnabledByDefault)
            },
            isFavorite: { action in
                cache.isFavorite(action.actionId)
            },
            isAvailable: { action in
                let isAvail = action.isAvailable(for: targetURLs, isContainer: isContainer)
                logToSharedContainer("[FinderSync] 过滤 Action [\(action.localizedTitle)] (\(action.actionId)): avail=\(isAvail)", level: .debug)
                return isAvail
            }
        )

        render(
            sections: sections,
            into: menu,
            dispatcher: dispatcher,
            invocationKind: invocationKind
        )
        
        logToSharedContainer("[FinderSync] 菜单渲染完毕，主菜单 Items 数量: \(menu.items.count)", level: .debug)
        // 若全部为空则不展示任何项
        return menu.items.isEmpty ? nil : menu
    }

    private func makeMenuItem(
        for action: MenuAction,
        invocationKind: ActionInvocationKind
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: action.localizedTitle,
            action: #selector(actionMenuItemSelected(_:)),
            keyEquivalent: ""
        )
        item.tag = FinderSync.getTag(for: action.actionId, invocationKind: invocationKind)
        item.target = self

        if let iconName = action.iconName {
            item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        }

        return item
    }

    private func render(
        sections: [FinderMenuLayoutSection],
        into menu: NSMenu,
        dispatcher: ActionDispatcher,
        invocationKind: ActionInvocationKind
    ) {
        for section in sections {
            switch section {
            case .directItems(let actionIds):
                for actionId in actionIds {
                    guard let action = dispatcher.action(forId: actionId) else { continue }
                    menu.addItem(makeMenuItem(for: action, invocationKind: invocationKind))
                    logToSharedContainer("[FinderSync] 成功添加一级菜单项: [\(action.localizedTitle)]", level: .debug)
                }
            case .submenu(let title, let actionIds):
                let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: title)
                for actionId in actionIds {
                    guard let action = dispatcher.action(forId: actionId) else { continue }
                    submenu.addItem(makeMenuItem(for: action, invocationKind: invocationKind))
                    logToSharedContainer("[FinderSync] 成功添加子菜单项: [\(action.localizedTitle)]", level: .debug)
                }
                if !submenu.items.isEmpty {
                    parent.submenu = submenu
                    menu.addItem(parent)
                }
            case .separator:
                if !menu.items.isEmpty {
                    menu.addItem(.separator())
                }
            }
        }
    }
    
}

// MARK: - 插件进程生命周期入口
@main
struct ExtensionMain {
    static func main() {
        _ = NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

@_silgen_name("NSExtensionMain")
@discardableResult
func NSExtensionMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

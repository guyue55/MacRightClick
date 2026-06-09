import Cocoa
import FinderSync
import Darwin

// MARK: - FinderSync 主插件
@objc(FinderSync)
class FinderSync: FIFinderSync {
    
    private let sharedDefaults = UserDefaults(suiteName: "group.guyue.RightClickAssistant")
    
    // MARK: - ActionTagMapper (双向唯一整数 Tag 映射表)
    // 彻底摒弃不稳定的 representedObject 机制，采用 100% 跨 XPC 穿透的标量 tag (注2)
    private static var tagToActionId: [Int: String] = [:]
    private static var nextTag: Int = 1000
    
    private static func getTag(for actionId: String) -> Int {
        if let existingTag = tagToActionId.first(where: { $0.value == actionId })?.key {
            return existingTag
        }
        let assignedTag = nextTag
        tagToActionId[assignedTag] = actionId
        nextTag += 1
        return assignedTag
    }
    
    private static func getActionId(for tag: Int) -> String? {
        return tagToActionId[tag]
    }
    
    /// 当用户点击菜单项时的回调函数（回归 Principal 插件类本身，完美解决 Obj-C XPC 派发寻址失败的大坑）
    @objc func actionMenuItemSelected(_ sender: NSMenuItem) {
        let tag = sender.tag
        logToSharedContainer("[FinderSync] [actionMenuItemSelected] 收到菜单点击事件，Tag: \(tag)")
        
        guard let actionId = FinderSync.getActionId(for: tag) else {
            logToSharedContainer("[FinderSync] [actionMenuItemSelected] 错误: 无法根据 Tag \(tag) 映射出动作 ID")
            return
        }
        
        // 动态以最权威、最原生的方式实时获取当前选中的物理文件/目录路径，弃用 representedObject 自带的静态路径数据
        var targets = FIFinderSyncController.default().selectedItemURLs() ?? []
        if targets.isEmpty {
            if let targetedURL = FIFinderSyncController.default().targetedURL() {
                targets = [targetedURL]
            }
        }
        
        guard !targets.isEmpty else {
            logToSharedContainer("[FinderSync] [actionMenuItemSelected] 错误: 系统返回选中的物理路径为空")
            return
        }
        
        logToSharedContainer("[FinderSync] [actionMenuItemSelected] 解析动作成功: \(actionId), 目标路径总数: \(targets.count)")
        
        // 1. 写入中介共享 JSON 交换文件
        let pendingActionURL = SharedStorageManager.shared.pendingActionURL
        let paths = targets.map { $0.path }
        
        let actionData: [String: Any] = [
            "actionId": actionId,
            "paths": paths
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: actionData, options: .prettyPrinted) {
            do {
                try jsonData.write(to: pendingActionURL, options: .atomic)
                logToSharedContainer("[FinderSync] [actionMenuItemSelected] 成功向中介写入 pending_action.json 动作参数")
            } catch {
                logToSharedContainer("[FinderSync] [actionMenuItemSelected] 错误: 写入共享 JSON 失败: \(error.localizedDescription)")
            }
        }
        
        // 2. 发送分布式空信号（系统 100% 允许跨沙盒自由传导）
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("guyue.RightClickAssistant.triggerActionSignal"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        
        logToSharedContainer("[FinderSync] [actionMenuItemSelected] 成功跨沙盒发出分布式空信号")
        
        // 3. 智能拉起并有针对性地前台激活/静默唤醒宿主主程序
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "guyue.RightClickAssistant") {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.addsToRecentItems = false
            
            // 如果此动作涉及弹窗、选择框或警示框，必须强制唤醒至前台（Bring to Front）并赋予系统物理焦点，否则会导致后台弹窗卡死或被覆盖
            let needsUI = [
                "guyue.action.filemanage.delete",
                "guyue.action.filemanage.moveTo",
                "guyue.action.filemanage.copyTo",
                "guyue.action.utility.calculateMD5",
                "guyue.action.utility.calculateSHA256",
                "guyue.action.utility.textToQRCode"
            ].contains(actionId)
            
            configuration.activates = needsUI
            
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error = error {
                    self.logToSharedContainer("[FinderSync] [actionMenuItemSelected] 激活宿主 App 失败: \(error.localizedDescription), needsUI: \(needsUI)")
                } else {
                    self.logToSharedContainer("[FinderSync] [actionMenuItemSelected] 宿主 App 状态更新成功, needsUI: \(needsUI)")
                }
            }
        }
    }
    
    override init() {
        super.init()
        
        logToSharedContainer("[FinderSync] 插件初始化启动...")
        
        // 1. 设置并应用我们需要监控的访达路径目录
        updateObservedDirectories()
        
        // 2. 监听来自主程序的共享配置变更通知，以便及时刷新右键
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(configChanged),
            name: Notification.Name("guyue.RightClickAssistant.configChanged"),
            object: nil
        )
        
        // 3. 在插件进程中也初始化默认动作集，以便直接在插件中分发执行
        registerDefaultActionsInExtension()
    }
    
    @objc private func configChanged() {
        logToSharedContainer("[FinderSync] 收到配置变更，已同步刷新内存缓存和监听路径")
        updateObservedDirectories()
    }
    
    /// 获取沙盒外的真实用户 Home 目录
    private func getRealHomeDirectory() -> String {
        let pw = getpwuid(getuid())
        if let home = pw?.pointee.pw_dir {
            return FileManager.default.string(withFileSystemRepresentation: home, length: Int(strlen(home)))
        }
        return NSHomeDirectory()
    }
    
    /// 将日志安全写入到共享的日志文件，提供黑盒运行期可观测性
    private func logToSharedContainer(_ message: String) {
        SharedStorageManager.shared.writeLog(message)
    }
    
    /// 动态探测并应用需要监控的访达路径（完美支持子目录、iCloud/OneDrive 云同步特殊目录）
    private func updateObservedDirectories() {
        var observedURLs: Set<URL> = []
        let homePath = getRealHomeDirectory()
        
        // 【关键安全重构】：macOS 14/15 强沙盒与 TCC 限制下，FinderSync 注册整个 Home 根目录会因为隐私限制而被系统底层直接挂起或拒绝加载。
        // 业界最佳实践是精准注册并观察用户最高频交互 of 常用子工作区，从而百分百获得系统授权并展现右键菜单。
        let subfolders = ["Desktop", "Downloads", "Documents", "GitProject"]
        for subfolder in subfolders {
            let folderURL = URL(fileURLWithPath: homePath).appendingPathComponent(subfolder)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                observedURLs.insert(folderURL)
                logToSharedContainer("[FinderSync] 激活工作区监控: \(folderURL.path)")
            } else {
                // 如果没有 GitProject 目录，我们可以动态创建它，或者直接跳过
                if subfolder == "GitProject" {
                    try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                    observedURLs.insert(folderURL)
                    logToSharedContainer("[FinderSync] 动态初始化并激活监控: \(folderURL.path)")
                }
            }
        }
        
        let shouldEnableCloudCompat = sharedDefaults?.bool(forKey: "shouldEnableiCloudMenu") ?? false
        
        if shouldEnableCloudCompat {
            logToSharedContainer("[FinderSync] 云盘特殊兼容已启用，正在激活云端监听...")
            
            // A. iCloud Drive 的标准本地路径：~/Library/Mobile Documents
            let iCloudURL = URL(fileURLWithPath: homePath).appendingPathComponent("Library/Mobile Documents")
            if FileManager.default.fileExists(atPath: iCloudURL.path) {
                observedURLs.insert(iCloudURL)
                logToSharedContainer("[FinderSync] 激活 iCloud Drive 监控: \(iCloudURL.path)")
            }
            
            // B. OneDrive / Dropbox 等第三方同步客户端在 macOS 上统一由 FileProvider 托管的宿主根路径
            let cloudStorageURL = URL(fileURLWithPath: homePath).appendingPathComponent("Library/CloudStorage")
            if FileManager.default.fileExists(atPath: cloudStorageURL.path) {
                observedURLs.insert(cloudStorageURL)
                logToSharedContainer("[FinderSync] 激活 CloudStorage (OneDrive/Dropbox) 监控: \(cloudStorageURL.path)")
            }
            
            // C. 备用检测：经典的本地 OneDrive 根目录
            let legacyOneDriveURL = URL(fileURLWithPath: homePath).appendingPathComponent("OneDrive")
            if FileManager.default.fileExists(atPath: legacyOneDriveURL.path) {
                observedURLs.insert(legacyOneDriveURL)
                logToSharedContainer("[FinderSync] 激活 Legacy OneDrive 监控: \(legacyOneDriveURL.path)")
            }
        }
        
        FIFinderSyncController.default().directoryURLs = observedURLs
        logToSharedContainer("[FinderSync] 监控目录注册成功，当前激活数量: \(observedURLs.count)")
    }
    
    // MARK: - 核心：动态渲染右键菜单
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
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
        } else {
            return nil
        }
        
        guard !targetURLs.isEmpty else { return nil }
        
        logToSharedContainer("[FinderSync] 右键菜单触发渲染, 类型: \(menuKind == .contextualMenuForItems ? "Items" : "Container"), 目标路径: \(targetURLs.map { $0.path })")
        
        let menu = NSMenu(title: "开源右键助手")
        
        // 从共享的 AppGroup 存储中加载需要显示的动作列表
        let dispatcher = ActionDispatcher.shared
        
        // 打印当前 dispatcher 中注册的所有 actions，确保在当前进程内真的有注册动作
        let registeredAll = dispatcher.allActions
        logToSharedContainer("[FinderSync] 当前 ActionDispatcher 中注册的所有动作总数: \(registeredAll.count)")
        for action in registeredAll {
            logToSharedContainer("[FinderSync] 已注册 Action: ID = \(action.actionId), Title = \(action.localizedTitle), Category = \(action.category.rawValue)")
        }
        
        // 我们在右键菜单中建立结构化的二级子菜单，使菜单看起来极为干净利落（对标 Windows 的层级设计）
        let categories = ActionCategory.allCases
        logToSharedContainer("[FinderSync] 开始遍历分类渲染菜单, 分类总数: \(categories.count)")
        
        for category in categories {
            let actions = dispatcher.actions(in: category)
            logToSharedContainer("[FinderSync] 分类 [\(category.localizedName)] (\(category.rawValue)) 下共有 actions: \(actions.count) 个")
            
            let enabledActions = actions.filter { action in
                // 检查用户是否在主 App 中启用了这个选项，通过 SharedStorageManager 自动实现多级兜底同步
                let key = "enable_action_\(action.actionId)"
                let isEnabled = SharedStorageManager.shared.getBool(forKey: key)
                let isAvail = action.isAvailable(for: targetURLs)
                logToSharedContainer("[FinderSync] 过滤检查 Action [\(action.localizedTitle)] (\(action.actionId)): isEnabled(配置) = \(isEnabled), isAvailable(状态) = \(isAvail)")
                return isEnabled && isAvail
            }
            logToSharedContainer("[FinderSync] 分类 [\(category.localizedName)] 过滤后生效的 actions 数量: \(enabledActions.count)")
            
            // 只有当该子分类下有启用且可用的菜单项时，才渲染该分类的子菜单
            if !enabledActions.isEmpty {
                let categoryItem = NSMenuItem(title: category.localizedName, action: nil, keyEquivalent: "")
                let subMenu = NSMenu(title: category.localizedName)
                
                for action in enabledActions {
                    let item = NSMenuItem(
                        title: action.localizedTitle,
                        action: #selector(actionMenuItemSelected(_:)),
                        keyEquivalent: ""
                    )
                    // 使用静态双向 Mapper 生成并绑定 100% 跨 XPC 无损穿透的标量 tag
                    item.tag = FinderSync.getTag(for: action.actionId)
                    item.target = self
                    
                    if let iconName = action.iconName {
                        item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
                    }
                    
                    subMenu.addItem(item)
                    logToSharedContainer("[FinderSync] 成功添加子菜单项: [\(action.localizedTitle)] (Tag: \(item.tag))")
                }
                
                categoryItem.submenu = subMenu
                menu.addItem(categoryItem)
                logToSharedContainer("[FinderSync] 成功向主菜单挂载分类: [\(category.localizedName)]")
            }
        }
        
        logToSharedContainer("[FinderSync] 菜单渲染完毕，主菜单 Items 数量: \(menu.items.count)")
        // 若全部为空则不展示任何项
        return menu.items.isEmpty ? nil : menu
    }
    
    /// 在 Extension 的独立沙盒进程中注册默认支持的一套右键操作
    private func registerDefaultActionsInExtension() {
        let dispatcher = ActionDispatcher.shared
        
        // A. 新建文件类
        dispatcher.register(action: NewFileAction(fileType: .txt))
        dispatcher.register(action: NewFileAction(fileType: .md))
        dispatcher.register(action: NewFileAction(fileType: .json))
        dispatcher.register(action: NewFileAction(fileType: .csv))
        dispatcher.register(action: NewFileAction(fileType: .docx))
        dispatcher.register(action: NewFileAction(fileType: .xlsx))
        dispatcher.register(action: NewFileAction(fileType: .pptx))
        
        // B. 文件管理类
        dispatcher.register(action: FileManageAction(type: .cut))
        dispatcher.register(action: FileManageAction(type: .paste))
        dispatcher.register(action: FileManageAction(type: .permanentDelete))
        dispatcher.register(action: FileManageAction(type: .copyPath))
        dispatcher.register(action: FileManageAction(type: .copyName))
        dispatcher.register(action: FileManageAction(type: .copyTo))
        dispatcher.register(action: FileManageAction(type: .moveTo))
        
        // C. 终端/编辑器类
        dispatcher.register(action: TerminalOpenAction(type: .terminal))
        dispatcher.register(action: TerminalOpenAction(type: .iterm2))
        dispatcher.register(action: TerminalOpenAction(type: .warp))
        dispatcher.register(action: TerminalOpenAction(type: .vscode))
        dispatcher.register(action: TerminalOpenAction(type: .sublime))
        dispatcher.register(action: TerminalOpenAction(type: .cursor))
        
        // D. 实用小工具
        dispatcher.register(action: UtilityAction(type: .calculateMD5))
        dispatcher.register(action: UtilityAction(type: .calculateSHA256))
        dispatcher.register(action: UtilityAction(type: .toggleHiddenFiles))
        dispatcher.register(action: UtilityAction(type: .textToQRCode))
        dispatcher.register(action: UtilityAction(type: .convertToPNG))
        dispatcher.register(action: UtilityAction(type: .convertToJPEG))
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

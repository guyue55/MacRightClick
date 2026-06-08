import Cocoa
import FinderSync

class FinderSync: FIFinderSync {
    
    private let sharedDefaults = UserDefaults(suiteName: "group.org.antigravity.RightClickAssistant")
    
    override init() {
        super.init()
        
        print("[FinderSync] 插件进程正在启动...")
        
        // 1. 设置我们需要监控的访达路径目录
        // 为了对全盘生效，通常监控用户的家目录，也可以根据用户配置动态监控
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory())
        FIFinderSyncController.default().directoryURLs = [homeDirectory]
        
        // 2. 监听来自主程序的共享配置变更通知，以便及时刷新右键
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(configChanged),
            name: Notification.Name("org.antigravity.RightClickAssistant.configChanged"),
            object: nil
        )
        
        // 3. 在插件进程中也初始化默认动作集，以便直接在插件中分发执行
        registerDefaultActionsInExtension()
    }
    
    @objc private func configChanged() {
        print("[FinderSync] 收到配置变更，已同步刷新内存缓存")
    }
    
    // MARK: - 核心：动态渲染右键菜单
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "开源右键助手")
        
        // 获取当前选中项目或当前所在空项目容器路径
        let targetURLs: [URL]
        if menuKind == .contextMenuForItems {
            targetURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        } else if menuKind == .contextMenuForContainer {
            if let containerURL = FIFinderSyncController.default().targetedURL() {
                targetURLs = [containerURL]
            } else {
                targetURLs = []
            }
        } else {
            return nil
        }
        
        guard !targetURLs.isEmpty else { return nil }
        
        // 从共享的 AppGroup 存储中加载需要显示的动作列表
        let dispatcher = ActionDispatcher.shared
        
        // 我们在右键菜单中建立结构化的二级子菜单，使菜单看起来极为干净利落（对标 Windows 的层级设计）
        let categories = ActionCategory.allCases
        
        for category in categories {
            let actions = dispatcher.actions(in: category)
            let enabledActions = actions.filter { action in
                // 检查用户是否在主 App 中启用了这个选项
                let key = "enable_action_\(action.actionId)"
                let isEnabled = sharedDefaults?.object(forKey: key) == nil ? true : (sharedDefaults?.bool(forKey: key) ?? true)
                return isEnabled && action.isAvailable(for: targetURLs)
            }
            
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
                    // 存储 Action ID 到 menuItem 中，以便在点击时分发
                    item.representedObject = [
                        "actionId": action.actionId,
                        "targets": targetURLs
                    ]
                    item.target = self
                    
                    if let iconName = action.iconName {
                        item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
                    }
                    
                    subMenu.addItem(item)
                }
                
                categoryItem.submenu = subMenu
                menu.addItem(categoryItem)
            }
        }
        
        // 若全部为空则不展示任何项
        return menu.items.isEmpty ? nil : menu
    }
    
    /// 当用户点击菜单项时的回调函数
    @objc private func actionMenuItemSelected(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? [String: Any],
              let actionId = payload["actionId"] as? String,
              let targets = payload["targets"] as? [URL] else {
            return
        }
        
        // 调用统一的 ActionDispatcher 分发动作执行
        let success = ActionDispatcher.shared.dispatch(actionId: actionId, targetURLs: targets)
        print("[FinderSync] 动作执行结果: \(success ? "成功" : "失败") (Action ID: \(actionId))")
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

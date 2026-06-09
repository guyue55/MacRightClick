import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    
    fileprivate static var instance: AppDelegate?

    var window: NSWindow!
    private var folderMonitor: SharedFolderMonitor?
    private var activityToken: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. 初始化并注册系统自带的右键菜单动作
        registerDefaultActions()
        
        // 2. 监听来自 Extension 的纯信号通知（双保险机制一：分布式空信号通知，强制指定 suspensionBehavior: .deliverImmediately）
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExtensionActionSignal(_:)),
            name: Notification.Name("guyue.RightClickAssistant.triggerActionSignal"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        
        // 3. 挂载内核级 DispatchSource 物理共享目录监听服务（双保险机制二：BSD kqueue 穿透监听，完美防挂起、丢包与沙盒拦截）
        let sharedContainerURL = SharedStorageManager.shared.sharedContainerURL
        let monitor = SharedFolderMonitor(folderURL: sharedContainerURL)
        monitor.onFolderChanged = { [weak self] in
            guard let self = self else { return }
            self.processPendingAction()
        }
        monitor.start()
        self.folderMonitor = monitor
        
        // 【关键修复】：启动后立刻检查并消费一次可能早已落盘的中介动作，彻底根治冷启动下拉起主程序却丢失首次点击事件的 Bug！
        self.processPendingAction()
        
        // 4. 创建 SwiftUI 主设置视图并托管在 NSWindow 中
        let contentView = ContentView()
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "开源右键助手 (RightClickAssistant)"
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        // 保证应用图标显示在 Dock 栏
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        print("[App] 右键助手宿主程序启动并初始化完成 (双保险中介链路就绪)")
        
        // 增加系统级保活机制，100% 阻止 App Nap 冻结我们的后台监控与通知消费
        self.activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: "Keep background folder monitor active for RightClickAssistant"
        )
        SharedStorageManager.shared.writeLog("[App] 系统级保活机制启动，App Nap 豁免激活成功")
        
        // 【生产分发屏蔽】：仿真自检仅作为本地开发自检使用。为了避免用户在正常安装运行时，其 Downloads 目录下莫名凭空产生 txt 测试文件，生产包中默认关闭此仿真调用。
        // self.runLaunchSelfTest()
    }
    
    @objc private func handleExtensionActionSignal(_ notification: Notification) {
        print("[App] 收到 Extension 代理执行信号通知 (分布式信号渠道触发)")
        processPendingAction()
    }
    
    /// 原子消费处理 pending_action.json 中介动作数据包（双保险统一消费入口，多重互斥锁保护）
    private func processPendingAction() {
        let pendingActionURL = SharedStorageManager.shared.pendingActionURL
        
        // 使用同步保护，防止分布式通知与 BSD 目录监听在极短毫秒内并发调用引起的文件系统竞争
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        
        guard FileManager.default.fileExists(atPath: pendingActionURL.path) else {
            // 已被消费并安全删除，静默退出
            return
        }
        
        SharedStorageManager.shared.writeLog("[App] [processPendingAction] 开始消费中介物理动作数据包...")
        
        guard let jsonData = try? Data(contentsOf: pendingActionURL) else {
            SharedStorageManager.shared.writeLog("[App] [processPendingAction] 错误: 无法读取共享 JSON 交换文件数据")
            return
        }
        
        guard let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
              let actionId = jsonObject["actionId"] as? String,
              let paths = jsonObject["paths"] as? [String] else {
            SharedStorageManager.shared.writeLog("[App] [processPendingAction] 错误: 解析共享 JSON 交换文件结构失败")
            return
        }
        
        // 立即物理删除该 JSON 交换文件，防止二次消费（高内聚、高安全性）
        try? FileManager.default.removeItem(at: pendingActionURL)
        
        SharedStorageManager.shared.writeLog("[App] [processPendingAction] 成功解析动作: \(actionId), 目标路径总数: \(paths.count)")
        
        let urls = paths.map { URL(fileURLWithPath: $0) }
        
        // 【线程性能优化】：移除外层强制主线程分发，直接在 SharedFolderMonitor 的高特权后台并发队列中同步执行 I/O 和计算。
        // 这彻底释放了主线程，消除 UI 线程卡顿引起的动作延迟。涉及到 UI 的悬浮 HUD 和二维码窗口在 UtilityAction 内部已安全包装了 DispatchQueue.main.async。
        SharedStorageManager.shared.writeLog("[App] [processPendingAction] 即将由 ActionDispatcher 分发动作 \(actionId)...")
        let success = ActionDispatcher.shared.dispatch(actionId: actionId, targetURLs: urls)
        SharedStorageManager.shared.writeLog("[App] [processPendingAction] 动作 \(actionId) 代理执行结果: \(success ? "成功" : "失败")")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        folderMonitor?.stop()
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
            SharedStorageManager.shared.writeLog("[App] 保活机制已安全结束释放")
        }
    }
    
    /// 注册默认的一套右键快捷操作
    private func registerDefaultActions() {
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
        
        print("[App] 已成功注册 \(dispatcher.allActions.count) 个核心右键动作")
    }
    
    /// 【全自动仿真自检】在电脑上真实触发并调用验证整个跨沙盒多进程通信链路
    private func runLaunchSelfTest() {
        print("[App] [SelfTest] 自检将在 30 秒后全自动触发...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            print("[App] [SelfTest] 正在模拟 Extension 写入中介共享并触发右键点击信号...")
            
            let pendingActionURL = SharedStorageManager.shared.pendingActionURL
            
            // 仿真自检目标：在当前用户的 Downloads 文件夹下模拟新建一个文本文档
            let homeDir = NSHomeDirectory()
            let downloadsPath = (homeDir as NSString).appendingPathComponent("Downloads")
            
            print("[App] [SelfTest] 目标工作区: \(downloadsPath)")
            
            let mockData: [String: Any] = [
                "actionId": "guyue.action.newfile.txt",
                "paths": [downloadsPath]
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: mockData, options: .prettyPrinted) {
                do {
                    try jsonData.write(to: pendingActionURL, options: .atomic)
                    print("[App] [SelfTest] 1. 成功向中介共享写入 pending_action.json 动作参数: \(pendingActionURL.path)")
                } catch {
                    print("[App] [SelfTest] 错误: 写入 JSON 失败: \(error.localizedDescription)")
                    return
                }
            }
            
            // 3. 通过 DistributedNotificationCenter 发送不带 userInfo 的纯分布式通知信号
            print("[App] [SelfTest] 2. 正在发送跨进程空信号 guyue.RightClickAssistant.triggerActionSignal...")
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("guyue.RightClickAssistant.triggerActionSignal"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            print("[App] [SelfTest] 3. 信号发送完毕，等待 AppDelegate 接收执行！")
        }
    }
}

// MARK: - 纯代码 AppKit 生命周期终极托管入口
@main
struct AppMain {
    static func main() {
        print("[AppMain] 纯代码自定义入口启动...")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.instance = delegate
        app.delegate = delegate
        print("[AppMain] 手动绑定 Delegate 成功，即将通过 app.run() 启动事件循环...")
        app.run()
    }
}


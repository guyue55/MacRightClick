import Cocoa
import SwiftUI
import os.lock

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    
    fileprivate static var instance: AppDelegate?

    var window: NSWindow!
    private var folderMonitor: SharedFolderMonitor?
    private var activityToken: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    /// 替换旧的 objc_sync_enter(self)：
    /// - 旧实现把锁加在 NSObject self 上，和 AppKit 内部隐式锁高度耦合，
    ///   debug 时一旦死锁，spindump 几乎看不到哪一处先持有；
    /// - os_unfair_lock 是 Apple 推荐的纯互斥，不参与 runloop，
    ///   语义只覆盖"PendingActions 消费循环的 critical section"。
    private var pendingActionLock = os_unfair_lock()
    
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
        
        // 3. 挂载 DispatchSource 动作队列监听服务。
        let pendingActionsURL = SharedStorageManager.shared.pendingActionsDirectoryURL
        let monitor = SharedFolderMonitor(folderURL: pendingActionsURL)
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
        
        window.delegate = self // 【关键修复】：指定 Window 代理，使 windowShouldClose 方法能被正确触发
        window.title = "开源右键助手 (RightClickAssistant)"
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.contentView = NSHostingView(rootView: contentView)
        window.orderOut(nil) // 【关键体验优化】：确保主设置窗口初始状态绝对不可见
        
        // 【关键体验优化】：主程序启动时，默认保持极其安静的托盘挂载状态 (.accessory)
        // 只有在需要显示 UI 的模态或用户双击图标重开时，才将策略调为 .regular，彻底根治触发右键菜单时强弹出主配置窗口的流氓体验。
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        
        print("[App] 右键助手宿主程序启动并初始化完成 (双保险中介链路就绪)")
        
        // 增加系统级保活机制，降低后台监控与通知消费被 App Nap 影响的概率。
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
    
    /// 原子消费处理 PendingActions 队列动作数据包（双保险统一消费入口，多重互斥锁保护）
    private func processPendingAction() {
        // 防止分布式通知与 kqueue 在毫秒内同时调用造成事件重复消费。
        // try_lock 而非 lock：若已经有一个消费循环在跑，新的回调直接退出，
        // 因为 consumePendingActionEvents 内部自带原子文件 rename，
        // 跑完一轮后任何遗漏事件都会在下一次 kqueue write 事件里再次进入这里。
        guard os_unfair_lock_trylock(&pendingActionLock) else { return }
        defer { os_unfair_lock_unlock(&pendingActionLock) }
        
        let events = SharedStorageManager.shared.consumePendingActionEvents()
        guard !events.isEmpty else { return }

        SharedStorageManager.shared.writeLog("[App] [processPendingAction] 开始消费动作队列，事件数: \(events.count)")

        for event in events {
            SharedStorageManager.shared.writeLog("[App] [processPendingAction] 成功解析动作: \(event.actionId), 目标路径总数: \(event.paths.count), eventId: \(event.id)")

            let urls = event.paths.map { URL(fileURLWithPath: $0) }

            // 【线程性能优化】：移除外层强制主线程分发，直接在 SharedFolderMonitor 的高特权后台并发队列中同步执行 I/O 和计算。
            // 这彻底释放了主线程，消除 UI 线程卡顿引起的动作延迟。涉及到 UI 的悬浮 HUD 和二维码窗口在 UtilityAction 内部已安全包装了 DispatchQueue.main.async。
            SharedStorageManager.shared.writeLog("[App] [processPendingAction] 即将由 ActionDispatcher 分发动作 \(event.actionId)...")
            let success = ActionDispatcher.shared.dispatch(actionId: event.actionId, targetURLs: urls)
            SharedStorageManager.shared.writeLog("[App] [processPendingAction] 动作 \(event.actionId) 代理执行结果: \(success ? "成功" : "失败")")
        }
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
        dispatcher.register(action: NewFileAction(fileType: .html))
        dispatcher.register(action: NewFileAction(fileType: .docx))
        dispatcher.register(action: NewFileAction(fileType: .xlsx))
        dispatcher.register(action: NewFileAction(fileType: .pptx))
        dispatcher.register(action: NewFileAction(fileType: .pdf))
        
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
            
            // 仿真自检目标：在当前用户的 Downloads 文件夹下模拟新建一个文本文档
            let homeDir = NSHomeDirectory()
            let downloadsPath = (homeDir as NSString).appendingPathComponent("Downloads")
            
            print("[App] [SelfTest] 目标工作区: \(downloadsPath)")
            
            do {
                let eventURL = try SharedStorageManager.shared.enqueueAction(
                    actionId: "guyue.action.newfile.txt",
                    paths: [downloadsPath]
                )
                print("[App] [SelfTest] 1. 成功向中介共享写入队列动作参数: \(eventURL.path)")
            } catch {
                print("[App] [SelfTest] 错误: 写入队列动作失败: \(error.localizedDescription)")
                return
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
    
    // MARK: - 系统菜单栏托盘管理
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        
        // 采用 SF Symbols 原生图标渲染，带 macOS 版本兼容降级。
        // contextualmenu 需要 macOS 14+，旧版本回退到 line.3.horizontal。
        let symbolName: String
        if #available(macOS 14.0, *) {
            symbolName = "contextualmenu"
        } else {
            symbolName = "line.3.horizontal"
        }
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "开源右键助手") {
            image.isTemplate = true // 跟随系统深/浅色菜单栏渲染
            button.image = image
        }
        // 兜底：若 SF Symbol 拉取失败（旧系统、缺资源、降级路径），
        // 让 statusItem 至少有 1 个汉字宽度，避免变成 0 宽不可见。
        if button.image == nil {
            button.title = "右"
        }
        
        let menu = NSMenu(title: "开源右键助手")
        menu.delegate = self
        rebuildStatusMenu(menu)
        statusItem?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let settingsItem = NSMenuItem(title: "显示右键助手设置", action: #selector(showSettingsWindow), keyEquivalent: "s")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: "关于右键助手", action: #selector(showAboutDialog), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(terminateApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func showSettingsWindow() {
        // 保持在 accessory 模式（无 Dock 图标），仅将窗口前置。
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc private func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "关于右键助手"
        
        // 从 Bundle 动态拉取当前最新的全局单源版本号
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        alert.informativeText = """
        开源右键助手 (RightClickAssistant)
        版本: v\(version)
        
        一款免费开源的 macOS 右键菜单增强工具。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        
        alert.window.level = .modalPanel
        alert.window.orderFrontRegardless()
        alert.runModal()
    }
    
    @objc private func terminateApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - NSWindowDelegate (常驻后台静默运行生命周期拦截)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 1. 物理隐藏偏好设置窗口，避免被彻底销毁
        window.orderOut(nil)
        
        // 2. 保持 .accessory 模式，仅隐藏窗口。
        
        SharedStorageManager.shared.writeLog("[App] 偏好设置窗口已被关闭，宿主程序自动降级为 .accessory 常驻后台静默运行中...")
        
        // 3. 返回 false 拦截窗口的实际销毁与主程序自动退出
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
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

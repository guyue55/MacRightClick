import Cocoa
import SwiftUI
import os.lock

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    
    fileprivate static var instance: AppDelegate?

    var window: NSWindow!
    private var folderMonitor: SharedFolderMonitor?
    private var statusItem: NSStatusItem?
    /// 替换旧的 objc_sync_enter(self)：
    /// - 旧实现把锁加在 NSObject self 上，和 AppKit 内部隐式锁高度耦合，
    ///   debug 时一旦死锁，spindump 几乎看不到哪一处先持有；
    /// - os_unfair_lock 是 Apple 推荐的纯互斥，不参与 runloop，
    ///   语义只覆盖"PendingActions 消费循环的 critical section"。
    private var pendingActionLock = os_unfair_lock()

    /// 专用串行队列：所有 processPendingAction 的真实工作都跑在这里。
    /// 必须用串行队列（不是 .global）：
    /// - 与 pendingActionLock 配合保证消费循环的 critical section 串行；
    /// - 同名右键动作短时间内突发 N 次时，按 FIFO 顺序消费，避免 ActionConfigCache /
    ///   NSPasteboard / HUD 在并发 dispatch 路径上互相踩踏；
    /// - 不挂主线程：避免 applicationDidFinishLaunching 阶段第一笔 dispatch
    ///   触发 cfprefsd XPC 同步等待时把 main runloop 锁死（压测捕获的 P0 死锁）。
    private let pendingActionDispatchQueue = DispatchQueue(
        label: "guyue.RightClickAssistant.pending-dispatch",
        qos: .userInitiated
    )
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. 初始化并注册系统自带的右键菜单动作
        registerDefaultActions()
        NSApp.servicesProvider = FinderServicesProvider.shared
        
        // 2. 监听来自 Extension 的纯信号通知（双保险机制一：分布式空信号通知，强制指定 suspensionBehavior: .deliverImmediately）
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExtensionActionSignal(_:)),
            name: Notification.Name("guyue.RightClickAssistant.triggerActionSignal"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        // P1-2：先把上次进程崩溃前未 ack 的 InFlight 孤儿事件搬回 PendingActions，
        // 再启动 folder-monitor。这样 reclaim 出来的事件会被本轮 processPendingAction 自然消费。
        SharedStorageManager.shared.reclaimAbandonedInFlightActions()
        
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
        
        // 主程序默认保持安静的菜单栏形态；是否展示设置页由启动来源决定。
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        showSettingsWindowIfNeededForLaunch()
        handlePermissionRefreshLaunchIfNeeded()
        
        print("[App] 右键助手宿主程序启动并初始化完成 (双保险中介链路就绪)")
        
        // 【生产分发屏蔽】：仿真自检仅作为本地开发自检使用。为了避免用户在正常安装运行时，其 Downloads 目录下莫名凭空产生 txt 测试文件，生产包中默认关闭此仿真调用。
        // self.runLaunchSelfTest()
    }
    
    @objc private func handleExtensionActionSignal(_ notification: Notification) {
        print("[App] 收到 Extension 代理执行信号通知 (分布式信号渠道触发)")
        processPendingAction()
    }
    
    /// PendingActions 消费的对外入口。任何线程都可以调用，立即返回，
    /// 不会阻塞调用者（applicationDidFinishLaunching、kqueue 回调、分布式通知都是合法入口）。
    ///
    /// 设计原因（压测捕获的 P0 死锁复盘）：
    /// - 旧实现：在 applicationDidFinishLaunching 主线程上同步消费 PendingActions；
    ///   reclaim 把孤儿搬回 Pending 后，第一笔 dispatch 一旦走到 SharedHUDManager.show
    ///   → SharedStorageManager.getBool → cfprefsd XPC 同步等待，main runloop 还没起来，
    ///   cfprefsd 的回应没人接，进程永久 __ulock_wait 死锁；
    /// - 修复：消费循环全部下沉到 pendingActionDispatchQueue，主线程 0 阻塞。
    private func processPendingAction() {
        pendingActionDispatchQueue.async { [weak self] in
            self?.drainPendingActions()
        }
    }

    /// 真正的消费循环（pendingActionDispatchQueue 上跑）。
    /// 用 trylock 防止两条 async 任务同时进入；新到的回调若发现已有循环在跑直接返回，
    /// 因为 consumePendingActionLeases 内部自带原子 rename，下一次 FSEvents/通知会自然回来。
    private func drainPendingActions() {
        guard os_unfair_lock_trylock(&pendingActionLock) else { return }
        defer { os_unfair_lock_unlock(&pendingActionLock) }
        
        // P1-2：lease 形式拿事件——文件已搬到 InFlight/<pid>/，dispatcher 跑完才 ack 删除。
        // 中途崩溃/强退都会被下次启动的 reclaim 救回。
        let leases = SharedStorageManager.shared.consumePendingActionLeases()
        guard !leases.isEmpty else { return }

        SharedStorageManager.shared.writeLog("[App] [processPendingAction] 开始消费动作队列，事件数: \(leases.count)")

        for lease in leases {
            let event = lease.event
            SharedStorageManager.shared.writeLog("[App] [processPendingAction] 成功解析动作: \(event.actionId), 目标路径总数: \(event.paths.count), eventId: \(event.id)")

            let urls = event.paths.map { URL(fileURLWithPath: $0) }

            // 【线程性能优化】：移除外层强制主线程分发，直接在 SharedFolderMonitor 的高特权后台并发队列中同步执行 I/O 和计算。
            // 这彻底释放了主线程，消除 UI 线程卡顿引起的动作延迟。涉及到 UI 的悬浮 HUD 和二维码窗口在 UtilityAction 内部已安全包装了 DispatchQueue.main.async。
            SharedStorageManager.shared.writeLog("[App] [processPendingAction] 即将由 ActionDispatcher 分发动作 \(event.actionId)...")
            let submission = ActionDispatcher.shared.submit(
                actionId: event.actionId,
                targetURLs: urls,
                invocationKind: event.invocationKind
            ) { status in
                SharedStorageManager.shared.writeLog(
                    "[App] [processPendingAction] 动作 \(event.actionId) 到达终态: \(String(describing: status))"
                )
                SharedStorageManager.shared.acknowledge(lease)
            }
            if submission == .rejected {
                SharedStorageManager.shared.writeLog(
                    "[App] [processPendingAction] 动作 \(event.actionId) 未被接管，已按失败终态确认",
                    level: .error
                )
            }
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        folderMonitor?.stop()
    }
    
    /// 注册默认的一套右键快捷操作
    private func registerDefaultActions() {
        let actions = DefaultActionRegistry.registerAll()
        SharedStorageManager.shared.migrateSettingsIfNeeded(actions: actions)
        ActionConfigCache.shared.preheat()
        print("[App] 已成功注册 \(actions.count) 个核心右键动作")
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

        let settingsItem = NSMenuItem(title: "打开设置…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: "关于右键助手", action: #selector(showAboutDialog), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let silentLaunchItem = NSMenuItem(
            title: "静默启动",
            action: #selector(toggleSilentLaunch(_:)),
            keyEquivalent: ""
        )
        silentLaunchItem.target = self
        silentLaunchItem.state = isSilentLaunchEnabled ? .on : .off
        menu.addItem(silentLaunchItem)

        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出", action: #selector(terminateApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private var isSilentLaunchEnabled: Bool {
        SharedStorageManager.shared.getBool(
            forKey: LaunchPresentationPolicy.silentLaunchKey,
            defaultValue: true
        )
    }

    private func showSettingsWindowIfNeededForLaunch() {
        evaluateLaunchPresentation()

        // LSUIElement app 在 didFinishLaunching 时可能还没来得及成为 active/frontmost。
        // 延迟做一次二次判断，避免用户从启动台/Applications 主动打开却看不到窗口。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.evaluateLaunchPresentation()
        }
    }

    private func evaluateLaunchPresentation() {
        guard !window.isVisible else { return }

        let context = LaunchPresentationPolicy.context(
            arguments: CommandLine.arguments,
            appIsActive: NSApp.isActive,
            frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        )

        if LaunchPresentationPolicy.shouldShowSettingsWindowOnLaunch(
            silentLaunchEnabled: isSilentLaunchEnabled,
            context: context
        ) {
            showSettingsWindow()
        }
    }

    private func handlePermissionRefreshLaunchIfNeeded() {
        guard CommandLine.arguments.contains(LaunchPresentationPolicy.permissionRefreshArgument) else {
            return
        }

        SystemReloader.postConfigChanged()
        SharedHUDManager.show(
            title: "正在刷新 Finder",
            content: "已重新打开右键助手，正在让 Finder 按新权限加载右键菜单",
            isSuccess: true
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let result = SystemReloader.restartFinder()
            DispatchQueue.main.async {
                guard !result.isSuccess else { return }
                SharedHUDManager.show(
                    title: "Finder 重启失败",
                    content: result.errorDescription ?? "请手动重启 Finder 或重新登录后再试",
                    isSuccess: false
                )
            }
        }
    }
    
    @objc private func showSettingsWindow() {
        // 保持在 accessory 模式（无 Dock 图标），仅将窗口前置。
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleSilentLaunch(_ sender: NSMenuItem) {
        let newValue = !isSilentLaunchEnabled
        guard SharedStorageManager.shared.setBool(
            newValue,
            forKey: LaunchPresentationPolicy.silentLaunchKey
        ) else {
            sender.state = isSilentLaunchEnabled ? .on : .off
            SharedHUDManager.show(
                title: "设置保存失败",
                content: "无法写入静默启动设置，请检查共享目录权限后重试。",
                isSuccess: false
            )
            return
        }
        sender.state = newValue ? .on : .off
        SharedHUDManager.show(
            title: newValue ? "静默启动已启用" : "静默启动已关闭",
            content: newValue ? "后台拉起时仅保留菜单栏图标" : "下次启动会直接显示设置窗口",
            iconName: newValue ? "moon.fill" : "macwindow",
            isSuccess: true
        )
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

import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. 初始化并注册系统自带的右键菜单动作
        registerDefaultActions()
        
        // 2. 创建 SwiftUI 主设置视图并托管在 NSWindow 中
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
        
        print("[App] 右键助手宿主程序启动并初始化完成")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // 清理行为
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
}

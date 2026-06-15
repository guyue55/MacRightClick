import Foundation
import AppKit

/// 支持的终端或编辑器类型
public enum TerminalEditorType: String, Codable, CaseIterable {
    case terminal = "terminal"
    case iterm2 = "iterm2"
    case warp = "warp"
    case vscode = "vscode"
    case sublime = "sublime"
    case cursor = "cursor"
    
    public var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm2: return "com.googlecode.iterm2"
        case .warp: return "dev.warp.Warp-Stable"
        case .vscode: return "com.microsoft.VSCode"
        case .sublime: return "com.sublimetext.3" // 支持 Sublime Text 3/4
        case .cursor: return "com.todesktop.230313mptvbe7of" // Cursor's custom bundle ID
        }
    }
    
    public var displayName: String {
        switch self {
        case .terminal: return "系统终端 (Terminal)"
        case .iterm2: return "iTerm2"
        case .warp: return "Warp 终端"
        case .vscode: return "Visual Studio Code"
        case .sublime: return "Sublime Text"
        case .cursor: return "Cursor"
        }
    }
}

public final class TerminalOpenAction: MenuAction {
    public let actionId: String
    public let localizedTitle: String
    public let iconName: String?
    public let category: ActionCategory = .terminal
    
    public let appType: TerminalEditorType
    
    public var associatedBundleIdentifier: String? {
        return appType.bundleIdentifier
    }

    public var isEnabledByDefault: Bool {
        return appType == .terminal
    }
    
    public init(type: TerminalEditorType) {
        self.appType = type
        self.actionId = "guyue.action.terminal.\(type.rawValue)"
        self.localizedTitle = "在 \(type.displayName) 中打开"
        
        switch type {
        case .terminal: self.iconName = "terminal"
        case .iterm2: self.iconName = "terminal.fill"
        case .warp: self.iconName = "terminal.fill"
        case .vscode: self.iconName = "chevron.left.forwardslash.chevron.right"
        case .sublime: self.iconName = "doc.plaintext"
        case .cursor: self.iconName = "sparkles"
        }
    }
    
    public func isAvailable(for targetURLs: [URL]) -> Bool {
        // 只有当安装了对应的软件，此右键菜单项才应该被启用并显示给用户
        guard let _ = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appType.bundleIdentifier) else {
            return false
        }
        return !targetURLs.isEmpty
    }
    
    public func execute(targetURLs: [URL]) -> Bool {
        guard let targetURL = targetURLs.first else { return false }
        
        // 确定需要打开的文件夹路径
        let pathURL = getDirectoryURL(for: targetURL)
        
        // VS Code、Cursor、Sublime、Warp、Terminal 和 iTerm2 均通过 NSWorkspace 传递目录 URL 打开。
        // 该方式避免额外的 AppleScript 自动化权限请求。
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appType.bundleIdentifier) else {
            print("[TerminalAction] 错误: 找不到应用: \(appType.displayName)")
            return false
        }
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [pathURL.path]
        
        
        // 异步拉起目标应用，避免 DispatchGroup.wait() 阻塞调用线程（尤其是主线程）导致 UI 卡死。
        // NSWorkspace.open 回调在后台队列执行，HUD 展示内部已切换到主线程。
        NSWorkspace.shared.open([pathURL], withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error = error {
                print("[TerminalAction] 拉起 \(self.appType.displayName) 失败: \(error.localizedDescription)")
                SharedHUDManager.show(
                    title: "拉起失败",
                    content: "无法启动 \(self.appType.displayName)",
                    isSuccess: false
                )
            } else {
                SharedHUDManager.show(
                    title: "拉起成功",
                    content: "已在 \(self.appType.displayName) 中打开目录",
                    isSuccess: true
                )
            }
        }
        
        // 立即返回，不等待异步结果。HUD 会在回调中展示成功/失败。
        // 调用方 ActionDispatcher 不依赖返回值做关键路径决策。
        return true
    }
    
    private func getDirectoryURL(for url: URL) -> URL {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }
}

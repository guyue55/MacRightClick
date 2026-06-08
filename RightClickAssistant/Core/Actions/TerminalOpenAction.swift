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
    
    public init(type: TerminalEditorType) {
        self.appType = type
        self.actionId = "org.antigravity.action.terminal.\(type.rawValue)"
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
        
        // 根据不同应用采用最现代化的拉起方式
        switch appType {
        case .terminal:
            return runAppleScript(source: """
            tell application "Terminal"
                do script "cd " & quoted form of "\(pathURL.path)"
                activate
            end tell
            """)
            
        case .iterm2:
            return runAppleScript(source: """
            tell application "iTerm"
                if not (exists window 1) then
                    create window with default profile
                else
                    tell current window
                        create tab with default profile
                    end tell
                end if
                tell current session of current window
                    write text "cd " & quoted form of "\(pathURL.path)"
                end tell
                activate
            end tell
            """)
            
        case .warp, .vscode, .sublime, .cursor:
            // VS Code, Cursor, Sublime, Warp 完美支持直接通过 NSWorkspace 传递文件夹 URL 唤醒打开
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appType.bundleIdentifier) else {
                print("[TerminalAction] 错误: 找不到应用: \(appType.displayName)")
                return false
            }
            
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = [pathURL.path]
            
            let group = DispatchGroup()
            group.enter()
            var success = false
            
            NSWorkspace.shared.open([pathURL], withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error = error {
                    print("[TerminalAction] 拉起 \(self.appType.displayName) 失败: \(error.localizedDescription)")
                } else {
                    success = true
                }
                group.leave()
            }
            
            _ = group.wait(timeout: .now() + 3.0)
            return success
        }
    }
    
    private func getDirectoryURL(for url: URL) -> URL {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }
    
    private func runAppleScript(source: String) -> Bool {
        guard let appleScript = NSAppleScript(source: source) else {
            print("[TerminalAction] 编译 AppleScript 失败")
            return false
        }
        
        var errorInfo: NSDictionary? = nil
        appleScript.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            print("[TerminalAction] 执行 AppleScript 报错: \(error)")
            return false
        }
        return true
    }
}

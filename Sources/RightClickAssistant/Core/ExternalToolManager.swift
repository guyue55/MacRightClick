import Foundation

public enum ManagedExternalTool: String, CaseIterable, Identifiable, Equatable {
    case iterm2
    case warp
    case visualStudioCode
    case sublimeText
    case cursor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .iterm2: return "iTerm2"
        case .warp: return "Warp"
        case .visualStudioCode: return "Visual Studio Code"
        case .sublimeText: return "Sublime Text"
        case .cursor: return "Cursor"
        }
    }

    public var caskName: String {
        switch self {
        case .iterm2: return "iterm2"
        case .warp: return "warp"
        case .visualStudioCode: return "visual-studio-code"
        case .sublimeText: return "sublime-text"
        case .cursor: return "cursor"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .iterm2: return TerminalEditorType.iterm2.bundleIdentifier
        case .warp: return TerminalEditorType.warp.bundleIdentifier
        case .visualStudioCode: return TerminalEditorType.vscode.bundleIdentifier
        case .sublimeText: return TerminalEditorType.sublime.bundleIdentifier
        case .cursor: return TerminalEditorType.cursor.bundleIdentifier
        }
    }
}

public enum ExternalToolOperation: Equatable {
    case install
    case update

    public var title: String {
        switch self {
        case .install: return "安装"
        case .update: return "更新"
        }
    }
}

public struct ExternalToolCommand: Equatable {
    public let executablePath: String
    public let arguments: [String]
}

public struct ExternalToolOperationOutcome: Equatable {
    public let operation: ExternalToolOperation
    public let tool: ManagedExternalTool
    public let commandResult: SystemCommandResult

    public var isSuccess: Bool {
        commandResult.isSuccess
    }
}

public enum ExternalToolManager {
    public static let defaultHomebrewExecutablePaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew"
    ]

    public static let homebrewWebsiteURL = URL(string: "https://brew.sh")!
    public static let homebrewInstallCommand = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    public static func homebrewExecutablePath(
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String? {
        defaultHomebrewExecutablePaths.first(where: fileExists)
    }

    public static func command(
        for operation: ExternalToolOperation,
        tool: ManagedExternalTool,
        brewExecutablePath: String
    ) -> ExternalToolCommand {
        let subcommand: String
        switch operation {
        case .install:
            subcommand = "install"
        case .update:
            subcommand = "upgrade"
        }

        return ExternalToolCommand(
            executablePath: brewExecutablePath,
            arguments: [subcommand, "--cask", tool.caskName]
        )
    }

    public static func isInstalled(
        _ tool: ManagedExternalTool,
        registry: InstalledAppRegistry = .shared
    ) -> Bool {
        registry.isInstalled(tool.bundleIdentifier)
    }

    public static func perform(
        operation: ExternalToolOperation,
        tool: ManagedExternalTool,
        brewExecutablePath: String,
        timeoutSeconds: TimeInterval = 1_200
    ) -> ExternalToolOperationOutcome {
        let command = command(
            for: operation,
            tool: tool,
            brewExecutablePath: brewExecutablePath
        )
        let result = SystemReloader.runCommand(
            executablePath: command.executablePath,
            arguments: command.arguments,
            timeoutSeconds: timeoutSeconds
        )

        if result.isSuccess {
            InstalledAppRegistry.shared.invalidate(bundleId: tool.bundleIdentifier)
        }

        return ExternalToolOperationOutcome(
            operation: operation,
            tool: tool,
            commandResult: result
        )
    }
}

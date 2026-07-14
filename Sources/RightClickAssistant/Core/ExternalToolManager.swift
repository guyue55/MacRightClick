import Foundation

public enum ManagedExternalTool: String, CaseIterable, Identifiable, Hashable, Sendable {
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

public enum ExternalToolOperation: Equatable, Sendable {
    case install
    case update
    case repair

    public var title: String {
        switch self {
        case .install: return "安装"
        case .update: return "更新"
        case .repair: return "修复"
        }
    }
}

public enum ExternalToolInstallationState: Equatable, Sendable {
    case notInstalled
    case installedOutsideHomebrew
    case managedByHomebrew
    case managedByHomebrewMissingApp

    public var recommendedOperation: ExternalToolOperation? {
        switch self {
        case .notInstalled: return .install
        case .installedOutsideHomebrew: return nil
        case .managedByHomebrew: return .update
        case .managedByHomebrewMissingApp: return .repair
        }
    }
}

public struct ExternalToolCommand: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]
}

public struct ExternalToolOperationOutcome: Equatable, Sendable {
    public let operation: ExternalToolOperation
    public let tool: ManagedExternalTool
    public let commandResult: SystemCommandResult

    public var isSuccess: Bool {
        commandResult.isSuccess
    }
}

public struct ExternalToolInventory: Equatable, Sendable {
    public let states: [ManagedExternalTool: ExternalToolInstallationState]
    public let commandResult: SystemCommandResult

    public var isReliable: Bool { commandResult.isSuccess }
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
        let arguments: [String]
        switch operation {
        case .install:
            arguments = ["install", "--cask", tool.caskName]
        case .update:
            arguments = ["upgrade", "--cask", "--greedy", tool.caskName]
        case .repair:
            arguments = ["reinstall", "--cask", tool.caskName]
        }

        return ExternalToolCommand(
            executablePath: brewExecutablePath,
            arguments: arguments
        )
    }

    public static func isInstalled(
        _ tool: ManagedExternalTool,
        registry: InstalledAppRegistry = .shared
    ) -> Bool {
        registry.isInstalled(tool.bundleIdentifier)
    }

    public static func installedCaskNames(from output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline).compactMap { line in
            line.split(whereSeparator: \.isWhitespace).first.map(String.init)
        })
    }

    public static func installationState(
        for tool: ManagedExternalTool,
        appInstalled: Bool,
        managedCaskNames: Set<String>
    ) -> ExternalToolInstallationState {
        let isManagedByHomebrew = managedCaskNames.contains(tool.caskName)
        switch (appInstalled, isManagedByHomebrew) {
        case (false, false): return .notInstalled
        case (true, false): return .installedOutsideHomebrew
        case (true, true): return .managedByHomebrew
        case (false, true): return .managedByHomebrewMissingApp
        }
    }

    public static func canPerform(
        _ operation: ExternalToolOperation,
        for state: ExternalToolInstallationState
    ) -> Bool {
        state.recommendedOperation == operation
    }

    public static func loadInventory(
        brewExecutablePath: String,
        appInstalledByTool: [ManagedExternalTool: Bool],
        timeoutSeconds: TimeInterval = 30
    ) -> ExternalToolInventory {
        let result = SystemReloader.runCommand(
            executablePath: brewExecutablePath,
            arguments: ["list", "--cask", "--versions"],
            timeoutSeconds: timeoutSeconds
        )
        let managedCaskNames = result.isSuccess
            ? installedCaskNames(from: result.standardOutput)
            : []
        let states = Dictionary(uniqueKeysWithValues: ManagedExternalTool.allCases.map { tool in
            (
                tool,
                installationState(
                    for: tool,
                    appInstalled: appInstalledByTool[tool] ?? false,
                    managedCaskNames: managedCaskNames
                )
            )
        })
        return ExternalToolInventory(states: states, commandResult: result)
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
        let appInstalledByTool = Dictionary(
            uniqueKeysWithValues: ManagedExternalTool.allCases.map { candidate in
                (candidate, isInstalled(candidate))
            }
        )
        let inventory = loadInventory(
            brewExecutablePath: brewExecutablePath,
            appInstalledByTool: appInstalledByTool,
            timeoutSeconds: min(timeoutSeconds, 30)
        )
        guard inventory.isReliable else {
            return ExternalToolOperationOutcome(
                operation: operation,
                tool: tool,
                commandResult: inventory.commandResult
            )
        }

        let currentState = inventory.states[tool] ?? .notInstalled
        guard canPerform(operation, for: currentState) else {
            let errorDescription: String
            if currentState == .installedOutsideHomebrew {
                errorDescription = "\(tool.displayName) 已安装，但不是由 Homebrew 管理，请使用应用内更新"
            } else {
                errorDescription = "\(tool.displayName) 的安装状态已变化，请重新检测后再试"
            }
            return ExternalToolOperationOutcome(
                operation: operation,
                tool: tool,
                commandResult: SystemCommandResult(
                    executablePath: command.executablePath,
                    arguments: command.arguments,
                    terminationStatus: nil,
                    errorDescription: errorDescription
                )
            )
        }

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

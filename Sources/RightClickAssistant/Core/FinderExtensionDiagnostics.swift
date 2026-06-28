import Foundation

public enum FullDiskAccessState: Equatable {
    case granted
    case denied
}

public enum FinderExtensionRegistrationState: Equatable {
    case enabled
    case registeredButNotEnabled
    case notRegistered
    case unknown
}

public enum RecommendedRepairAction: Equatable {
    case none
    case openFullDiskAccessSettings
    case registerExtension
    case restartFinder
    case relaunchAppAndRestartFinder
}

public enum RightClickMenuHealthLevel: Equatable {
    case healthy
    case warning
    case critical
}

public struct RightClickMenuHealthSnapshot: Equatable {
    public let fullDiskAccessState: FullDiskAccessState
    public let finderExtensionState: FinderExtensionRegistrationState
    public let finderSyncControllerEnabled: Bool
    public let watchScope: WatchScope
    public let observedPathCount: Int
    public let pendingActionCount: Int
    public let failedActionCount: Int
    public let recommendedRepairAction: RecommendedRepairAction

    public var healthLevel: RightClickMenuHealthLevel {
        switch recommendedRepairAction {
        case .none:
            return failedActionCount > 0 ? .warning : .healthy
        case .restartFinder, .relaunchAppAndRestartFinder:
            return .warning
        case .openFullDiskAccessSettings, .registerExtension:
            return .critical
        }
    }
}

public enum FinderExtensionDiagnostics {
    public static let defaultExtensionBundleIdentifier = "guyue.RightClickAssistant.Extension"

    public static func registrationState(
        pluginKitOutput: String,
        commandSucceeded: Bool,
        bundleIdentifier: String = defaultExtensionBundleIdentifier
    ) -> FinderExtensionRegistrationState {
        guard commandSucceeded else { return .unknown }

        let matchingLine = pluginKitOutput
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.contains(bundleIdentifier) }

        guard let line = matchingLine else { return .notRegistered }
        return line.trimmingCharacters(in: .whitespaces).hasPrefix("+")
            ? .enabled
            : .registeredButNotEnabled
    }

    public static func makeSnapshot(
        fullDiskAccessGranted: Bool,
        finderSyncControllerEnabled: Bool,
        pluginKitState: FinderExtensionRegistrationState,
        watchScope: WatchScope,
        observedPathCount: Int,
        pendingActionCount: Int,
        failedActionCount: Int
    ) -> RightClickMenuHealthSnapshot {
        let fullDiskAccessState: FullDiskAccessState = fullDiskAccessGranted ? .granted : .denied
        let repairAction = recommendedRepairAction(
            fullDiskAccessState: fullDiskAccessState,
            finderSyncControllerEnabled: finderSyncControllerEnabled,
            finderExtensionState: pluginKitState,
            observedPathCount: observedPathCount
        )

        return RightClickMenuHealthSnapshot(
            fullDiskAccessState: fullDiskAccessState,
            finderExtensionState: pluginKitState,
            finderSyncControllerEnabled: finderSyncControllerEnabled,
            watchScope: watchScope,
            observedPathCount: observedPathCount,
            pendingActionCount: pendingActionCount,
            failedActionCount: failedActionCount,
            recommendedRepairAction: repairAction
        )
    }

    private static func recommendedRepairAction(
        fullDiskAccessState: FullDiskAccessState,
        finderSyncControllerEnabled: Bool,
        finderExtensionState: FinderExtensionRegistrationState,
        observedPathCount: Int
    ) -> RecommendedRepairAction {
        if fullDiskAccessState == .denied {
            return .openFullDiskAccessSettings
        }

        switch finderExtensionState {
        case .notRegistered, .registeredButNotEnabled, .unknown:
            return .registerExtension
        case .enabled:
            if !finderSyncControllerEnabled || observedPathCount == 0 {
                return .restartFinder
            }
            return .none
        }
    }
}

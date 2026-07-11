import Foundation

public enum FullDiskAccessState: Equatable, Sendable {
    case granted
    case denied
}

public enum FinderExtensionRegistrationState: Equatable, Sendable {
    case enabled
    case registeredButNotEnabled
    case notRegistered
    case unknown
}

public enum RecommendedRepairAction: Equatable, Sendable {
    case none
    case openFullDiskAccessSettings
    case registerExtension
    case restartFinder
    case relaunchAppAndRestartFinder
}

public enum RightClickMenuHealthLevel: Equatable, Sendable {
    case healthy
    case warning
    case critical
}

public enum RightClickMenuServiceLevel: Equatable, Sendable {
    case healthy
    case unverified
    case unavailable
}

public struct RightClickMenuHealthSnapshot: Equatable, Sendable {
    public let fullDiskAccessState: FullDiskAccessState
    public let finderExtensionState: FinderExtensionRegistrationState
    public let finderSyncControllerEnabled: Bool
    public let watchScope: WatchScope
    public let heartbeatState: ExtensionHeartbeatState
    public let observedPathCount: Int
    public let pendingActionCount: Int
    public let oldestPendingAge: TimeInterval?
    public let failedActionCount: Int
    public let recommendedRepairAction: RecommendedRepairAction

    public var menuServiceLevel: RightClickMenuServiceLevel {
        if !finderSyncControllerEnabled {
            return .unavailable
        }
        switch finderExtensionState {
        case .notRegistered, .registeredButNotEnabled:
            return .unavailable
        case .enabled, .unknown:
            break
        }
        switch heartbeatState {
        case .recent(let observedPathCount):
            return observedPathCount > 0 ? .healthy : .unavailable
        case .stale, .missing:
            return .unverified
        }
    }

    public var healthLevel: RightClickMenuHealthLevel {
        switch menuServiceLevel {
        case .unavailable:
            return .critical
        case .unverified:
            return .warning
        case .healthy:
            break
        }
        if fullDiskAccessState == .denied
            || failedActionCount > 0
            || oldestPendingAge.map({ $0 >= 60 }) == true {
            return .warning
        }
        return .healthy
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
        heartbeatState: ExtensionHeartbeatState,
        watchScope: WatchScope,
        pendingActionCount: Int,
        oldestPendingAge: TimeInterval?,
        failedActionCount: Int
    ) -> RightClickMenuHealthSnapshot {
        let fullDiskAccessState: FullDiskAccessState = fullDiskAccessGranted ? .granted : .denied
        let observedPathCount: Int
        if case .recent(let count) = heartbeatState {
            observedPathCount = count
        } else {
            observedPathCount = 0
        }
        let repairAction = recommendedRepairAction(
            fullDiskAccessState: fullDiskAccessState,
            finderSyncControllerEnabled: finderSyncControllerEnabled,
            finderExtensionState: pluginKitState,
            heartbeatState: heartbeatState
        )

        return RightClickMenuHealthSnapshot(
            fullDiskAccessState: fullDiskAccessState,
            finderExtensionState: pluginKitState,
            finderSyncControllerEnabled: finderSyncControllerEnabled,
            watchScope: watchScope,
            heartbeatState: heartbeatState,
            observedPathCount: observedPathCount,
            pendingActionCount: pendingActionCount,
            oldestPendingAge: oldestPendingAge,
            failedActionCount: failedActionCount,
            recommendedRepairAction: repairAction
        )
    }

    /// 旧调用点兼容适配：明确传入的 observedPathCount 视为已取得最近心跳。
    public static func makeSnapshot(
        fullDiskAccessGranted: Bool,
        finderSyncControllerEnabled: Bool,
        pluginKitState: FinderExtensionRegistrationState,
        watchScope: WatchScope,
        observedPathCount: Int,
        pendingActionCount: Int,
        failedActionCount: Int
    ) -> RightClickMenuHealthSnapshot {
        makeSnapshot(
            fullDiskAccessGranted: fullDiskAccessGranted,
            finderSyncControllerEnabled: finderSyncControllerEnabled,
            pluginKitState: pluginKitState,
            heartbeatState: .recent(observedPathCount: observedPathCount),
            watchScope: watchScope,
            pendingActionCount: pendingActionCount,
            oldestPendingAge: nil,
            failedActionCount: failedActionCount
        )
    }

    private static func recommendedRepairAction(
        fullDiskAccessState: FullDiskAccessState,
        finderSyncControllerEnabled: Bool,
        finderExtensionState: FinderExtensionRegistrationState,
        heartbeatState: ExtensionHeartbeatState
    ) -> RecommendedRepairAction {
        switch finderExtensionState {
        case .notRegistered, .registeredButNotEnabled:
            return .registerExtension
        case .unknown:
            if case .recent(let count) = heartbeatState, count > 0 { break }
            return .registerExtension
        case .enabled:
            break
        }

        if !finderSyncControllerEnabled {
            return .restartFinder
        }
        switch heartbeatState {
        case .recent(let observedPathCount) where observedPathCount > 0:
            break
        case .recent, .stale, .missing:
            return .restartFinder
        }

        if fullDiskAccessState == .denied {
            return .openFullDiskAccessSettings
        }

        return .none
    }
}

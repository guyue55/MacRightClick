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
    public let cloudCompatibilityEnabled: Bool
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

    /// 隐私安全的支持报告：只包含版本、枚举状态、计数与时长，不包含用户路径。
    public func diagnosticSummary(appVersion: String) -> String {
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        let heartbeat: String
        switch heartbeatState {
        case .recent(let count): heartbeat = "recent(\(count))"
        case .stale: heartbeat = "stale"
        case .missing: heartbeat = "missing"
        }
        let oldestAge = oldestPendingAge.map { String(Int($0)) } ?? "none"

        return [
            "RightClickAssistant Diagnostics",
            "App Version: \(appVersion)",
            "macOS: \(operatingSystem)",
            "Menu Service: \(menuServiceLevel.summaryValue)",
            "Full Disk Access: \(fullDiskAccessState.summaryValue)",
            "Extension Registration: \(finderExtensionState.summaryValue)",
            "Finder Controller Enabled: \(finderSyncControllerEnabled)",
            "Heartbeat: \(heartbeat)",
            "Watch Scope: \(watchScope.rawValue)",
            "Cloud Compatibility: \(cloudCompatibilityEnabled)",
            "Observed Paths: \(observedPathCount)",
            "Pending: \(pendingActionCount)",
            "Oldest Pending Seconds: \(oldestAge)",
            "Failed: \(failedActionCount)",
            "Recommended Repair: \(recommendedRepairAction.summaryValue)"
        ].joined(separator: "\n")
    }
}

private extension RightClickMenuServiceLevel {
    var summaryValue: String {
        switch self {
        case .healthy: return "healthy"
        case .unverified: return "unverified"
        case .unavailable: return "unavailable"
        }
    }
}

private extension FullDiskAccessState {
    var summaryValue: String {
        switch self {
        case .granted: return "granted"
        case .denied: return "denied"
        }
    }
}

private extension FinderExtensionRegistrationState {
    var summaryValue: String {
        switch self {
        case .enabled: return "enabled"
        case .registeredButNotEnabled: return "registered-but-disabled"
        case .notRegistered: return "not-registered"
        case .unknown: return "unknown"
        }
    }
}

private extension RecommendedRepairAction {
    var summaryValue: String {
        switch self {
        case .none: return "none"
        case .openFullDiskAccessSettings: return "open-full-disk-access"
        case .registerExtension: return "register-extension"
        case .restartFinder: return "restart-finder"
        case .relaunchAppAndRestartFinder: return "relaunch-app-and-finder"
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
        heartbeatState: ExtensionHeartbeatState,
        watchScope: WatchScope,
        cloudCompatibilityEnabled: Bool = true,
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
            cloudCompatibilityEnabled: cloudCompatibilityEnabled,
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
        cloudCompatibilityEnabled: Bool = true,
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
            cloudCompatibilityEnabled: cloudCompatibilityEnabled,
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

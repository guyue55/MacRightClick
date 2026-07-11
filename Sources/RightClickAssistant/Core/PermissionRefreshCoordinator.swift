import Foundation

/// Coordinates the post-Full-Disk-Access refresh flow.
///
/// Full Disk Access is owned by macOS TCC. Existing host/FinderSync processes
/// may keep old permission state, so the best UX is to offer an explicit,
/// repeatable reload path instead of implying that a hot permission change is
/// always enough.
public enum PermissionRefreshCoordinator {
    public enum ReloadChoice: Equatable, Sendable {
        case relaunchAppAndRestartFinder
        case restartFinderOnly
        case later
    }

    public struct ReloadOutcome: Equatable, Sendable {
        public let choice: ReloadChoice
        public let relaunchResult: SystemCommandResult?
        public let restartFinderResult: SystemCommandResult?

        public var isSuccess: Bool {
            switch choice {
            case .relaunchAppAndRestartFinder:
                // Finder 由携带 permission-refresh 参数的新进程在完成初始化后重启。
                // 旧进程只能确认新实例是否成功拉起，不能伪造新进程的最终刷新结果。
                return relaunchResult?.isSuccess == true
            case .restartFinderOnly:
                return restartFinderResult?.isSuccess == true
            case .later:
                return true
            }
        }
    }

    public static func shouldPromptAfterGrant(
        previous: Bool,
        current: Bool,
        hasLoadedInitialState: Bool,
        didPrompt: Bool
    ) -> Bool {
        hasLoadedInitialState && !previous && current && !didPrompt
    }

    public static func shouldOfferManualRelaunchFallback(currentFullDiskAccess: Bool) -> Bool {
        !currentFullDiskAccess
    }

    public static let permissionRefreshRelaunchArguments = [
        LaunchPresentationPolicy.permissionRefreshArgument,
        LaunchPresentationPolicy.userOpenArgument
    ]

    @discardableResult
    public static func restartFinderOnly() -> SystemCommandResult {
        SystemReloader.postConfigChanged()
        return SystemReloader.restartFinder()
    }

    @discardableResult
    private static func relaunchAppForPermissionRefresh(bundleURL: URL) -> SystemCommandResult {
        SystemReloader.postConfigChanged()
        return SystemReloader.relaunchApp(
            bundleURL: bundleURL,
            arguments: permissionRefreshRelaunchArguments
        )
    }

    public static func performReload(
        choice: ReloadChoice,
        bundleURL: URL,
        completion: @escaping @MainActor @Sendable (ReloadOutcome) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: ReloadOutcome
            switch choice {
            case .relaunchAppAndRestartFinder:
                let relaunchResult = relaunchAppForPermissionRefresh(bundleURL: bundleURL)
                outcome = ReloadOutcome(
                    choice: choice,
                    relaunchResult: relaunchResult,
                    restartFinderResult: nil
                )
            case .restartFinderOnly:
                outcome = ReloadOutcome(
                    choice: choice,
                    relaunchResult: nil,
                    restartFinderResult: restartFinderOnly()
                )
            case .later:
                outcome = ReloadOutcome(
                    choice: choice,
                    relaunchResult: nil,
                    restartFinderResult: nil
                )
            }

            Task { @MainActor in
                completion(outcome)
            }
        }
    }
}

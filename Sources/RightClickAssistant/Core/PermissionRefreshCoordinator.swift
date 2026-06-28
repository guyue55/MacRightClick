import Foundation

/// Coordinates the post-Full-Disk-Access refresh flow.
///
/// Full Disk Access is owned by macOS TCC. Existing host/FinderSync processes
/// may keep old permission state, so the best UX is to offer an explicit,
/// repeatable reload path instead of implying that a hot permission change is
/// always enough.
public enum PermissionRefreshCoordinator {
    public enum ReloadChoice: Equatable {
        case relaunchAppAndRestartFinder
        case restartFinderOnly
        case later
    }

    public struct ReloadOutcome: Equatable {
        public let choice: ReloadChoice
        public let relaunchResult: SystemCommandResult?
        public let restartFinderResult: SystemCommandResult?

        public var isSuccess: Bool {
            switch choice {
            case .relaunchAppAndRestartFinder:
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

    @discardableResult
    public static func restartFinderOnly() -> SystemCommandResult {
        SystemReloader.postConfigChanged()
        return SystemReloader.restartFinder()
    }

    @discardableResult
    public static func relaunchAppAndRestartFinder(bundleURL: URL) -> SystemCommandResult {
        SystemReloader.postConfigChanged()
        return SystemReloader.relaunchApp(
            bundleURL: bundleURL,
            arguments: [
                LaunchPresentationPolicy.userOpenArgument,
                LaunchPresentationPolicy.permissionRefreshArgument
            ]
        )
    }

    public static func performReload(
        choice: ReloadChoice,
        bundleURL: URL,
        completion: @escaping (ReloadOutcome) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: ReloadOutcome
            switch choice {
            case .relaunchAppAndRestartFinder:
                outcome = ReloadOutcome(
                    choice: choice,
                    relaunchResult: relaunchAppAndRestartFinder(bundleURL: bundleURL),
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

            DispatchQueue.main.async {
                completion(outcome)
            }
        }
    }
}

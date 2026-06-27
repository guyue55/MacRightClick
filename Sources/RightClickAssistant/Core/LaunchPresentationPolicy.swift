import Foundation

/// Decides whether the settings window should be shown during app launch.
///
/// The host can be started in three different ways: explicitly by the user,
/// quietly by FinderSync, or by the system login item. Keeping this logic in a
/// small pure type makes the AppKit lifecycle easier to reason about and test.
public enum LaunchPresentationPolicy {
    public static let backgroundLaunchArgument = "--rightclickassistant-background"
    public static let silentLaunchKey = "silent_launch_enabled"

    public struct Context: Equatable {
        public let isBackgroundRequest: Bool
        public let appIsActive: Bool
        public let appIsFrontmost: Bool

        public init(isBackgroundRequest: Bool, appIsActive: Bool, appIsFrontmost: Bool) {
            self.isBackgroundRequest = isBackgroundRequest
            self.appIsActive = appIsActive
            self.appIsFrontmost = appIsFrontmost
        }
    }

    public static func context(
        arguments: [String],
        appIsActive: Bool,
        frontmostBundleIdentifier: String?,
        ownBundleIdentifier: String?
    ) -> Context {
        Context(
            isBackgroundRequest: arguments.contains(backgroundLaunchArgument),
            appIsActive: appIsActive,
            appIsFrontmost: ownBundleIdentifier != nil && frontmostBundleIdentifier == ownBundleIdentifier
        )
    }

    public static func shouldShowSettingsWindowOnLaunch(
        silentLaunchEnabled: Bool,
        context: Context
    ) -> Bool {
        if context.isBackgroundRequest {
            return false
        }
        if !silentLaunchEnabled {
            return true
        }
        return context.appIsActive || context.appIsFrontmost
    }
}

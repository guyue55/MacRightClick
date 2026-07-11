import Foundation

/// Decides whether the settings window should be shown during app launch.
///
/// The host can be started in three different ways: explicitly by the user,
/// quietly by FinderSync, or by the system login item. Keeping this logic in a
/// small pure type makes the AppKit lifecycle easier to reason about and test.
public enum LaunchPresentationPolicy {
    public static let backgroundLaunchArgument = "--rightclickassistant-background"
    public static let userOpenArgument = "--rightclickassistant-user-open"
    public static let permissionRefreshArgument = "--rightclickassistant-permission-refresh"
    public static let silentLaunchKey = "silent_launch_enabled"

    public struct Context: Equatable, Sendable {
        public let isBackgroundRequest: Bool
        public let isUserOpenRequest: Bool
        public let isPermissionRefreshRequest: Bool
        public let appIsActive: Bool
        public let appIsFrontmost: Bool

        public init(
            isBackgroundRequest: Bool,
            isUserOpenRequest: Bool = false,
            isPermissionRefreshRequest: Bool = false,
            appIsActive: Bool,
            appIsFrontmost: Bool
        ) {
            self.isBackgroundRequest = isBackgroundRequest
            self.isUserOpenRequest = isUserOpenRequest
            self.isPermissionRefreshRequest = isPermissionRefreshRequest
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
            isUserOpenRequest: arguments.contains(userOpenArgument),
            isPermissionRefreshRequest: arguments.contains(permissionRefreshArgument),
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
        if context.isUserOpenRequest || context.isPermissionRefreshRequest {
            return true
        }
        if !silentLaunchEnabled {
            return true
        }
        return context.appIsActive || context.appIsFrontmost
    }
}

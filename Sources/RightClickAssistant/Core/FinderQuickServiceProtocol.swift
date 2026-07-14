import Foundation

/// 动态服务 helper 与 Host 之间的最小稳定协议。
public enum FinderQuickServiceProtocol {
    public static let bundleIdentifier = "guyue.RightClickAssistant.QuickServices"
    public static let bundleDirectoryName = "RightClickAssistantQuickActions.service"
    public static let executableName = "RightClickAssistantQuickService"
    public static let providerPortName = "RightClickAssistantQuickActions"
    public static let forwardedActionPasteboardType = "guyue.RightClickAssistant.direct-action-id"
    public static let hostPaletteMenuTitle = "右键助手…"
}

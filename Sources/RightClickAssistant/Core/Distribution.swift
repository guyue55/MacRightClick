import Foundation

/// 分发路线枚举。决定运行时的存储策略与 entitlements 模板。
public enum DistributionRoute: String {
    case websiteDev      // Ad-hoc 签名本地开发
    case websiteRelease  // Developer ID + hardened runtime + notarization
    case macAppStore     // 真沙盒 + App Group + security-scoped bookmark（本轮不构建）
}

/// 单一来源的分发路线常量。
///
/// build.sh 通过 `-D WEBSITE_DEV / WEBSITE_RELEASE / MAC_APP_STORE` 注入；
/// Swift 端只读编译期常量，避免运行时探测产生分支歧义。
public enum Distribution {
    public static var route: DistributionRoute {
        #if MAC_APP_STORE
        return .macAppStore
        #elseif WEBSITE_RELEASE
        return .websiteRelease
        #else
        return .websiteDev
        #endif
    }

    /// 是否走 App Group 共享容器。MAS 路线必须为 true，其它为 false。
    public static var usesAppGroup: Bool {
        #if MAC_APP_STORE
        return true
        #else
        return false
        #endif
    }

    /// 是否允许主 App 跨 Container 读 Extension 沙盒目录。
    /// website 路线下主 App 非 sandbox 才有效，MAS 路线必须为 false。
    public static var allowsCrossContainerExchange: Bool {
        #if MAC_APP_STORE
        return false
        #else
        return true
        #endif
    }
}

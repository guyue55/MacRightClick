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

    /// 是否走 App Group 共享容器。MAS 路线必须为 true。
    ///
    /// website 路线当前返回 false：c4a37e3 修复后主 App 仍签 sandbox + App Group 模板，
    /// 但 SharedStorageManager 实际走的是「cross-container 物理路径」分支
    /// （allowsCrossContainerExchange=true），保持与历史用户数据兼容。
    /// 切换到 `usesAppGroup=true` 物理路径会变（Library/Group Containers/...），
    /// 属于运行时行为变更，需要单独的数据迁移评估，不在本轮 scope 内。
    public static var usesAppGroup: Bool {
        #if MAC_APP_STORE
        return true
        #else
        return false
        #endif
    }

    /// 是否允许主 App 跨 Container 读 Extension 沙盒目录。MAS 路线必须为 false。
    ///
    /// website 路线返回 true：与 SharedStorageManager 现有"读 ~/Library/Containers/
    /// <extBundle>/Data"路径分支配合。该路径在主 App sandbox + 同一 App Group 下被允许。
    public static var allowsCrossContainerExchange: Bool {
        #if MAC_APP_STORE
        return false
        #else
        return true
        #endif
    }
}

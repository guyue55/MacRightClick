import Foundation

/// 系统服务动作面板使用的只读展示模型。
/// UI 只消费该模型，不直接读取动作开关或判断上下文权限。
public struct FinderServiceActionItem: Equatable, Identifiable, Sendable {
    public let actionID: String
    public let title: String
    public let iconName: String?
    public let category: ActionCategory
    public let isFavorite: Bool
    public let isHighRisk: Bool

    public var id: String { actionID }

    public init(
        actionID: String,
        title: String,
        iconName: String?,
        category: ActionCategory,
        isFavorite: Bool,
        isHighRisk: Bool
    ) {
        self.actionID = actionID
        self.title = title
        self.iconName = iconName
        self.category = category
        self.isFavorite = isFavorite
        self.isHighRisk = isHighRisk
    }
}

/// FinderSync 在 File Provider 托管目录中可能被 Finder 抑制。
/// 系统服务以单一入口打开动作面板，并由这里统一决定动作显隐。
public enum FinderServiceCatalog {
    public static let menuTitle = "右键助手…"
    public static let serviceUserData = "guyue.service.openActionPalette"

    public static func accepts(userData: String) -> Bool {
        userData == serviceUserData
    }

    public static func resolveItems(
        actions: [MenuAction],
        targetURLs: [URL],
        isEnabled: (MenuAction) -> Bool,
        isFavorite: (MenuAction) -> Bool,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [FinderServiceActionItem] {
        guard !targetURLs.isEmpty else { return [] }

        let resolved = actions.compactMap { action -> FinderServiceActionItem? in
            guard isEnabled(action) else { return nil }

            let availableTargets: [URL]
            if action.requiresExistingTargets {
                availableTargets = targetURLs.filter(fileExists)
                guard !availableTargets.isEmpty else { return nil }
            } else {
                availableTargets = targetURLs
            }

            guard action.isAvailable(for: availableTargets, isContainer: false) else {
                return nil
            }

            return FinderServiceActionItem(
                actionID: action.actionId,
                title: action.localizedTitle,
                iconName: action.iconName,
                category: action.category,
                isFavorite: isFavorite(action),
                isHighRisk: action.isHighRisk
            )
        }

        return resolved.sorted(by: comesBefore)
    }

    public static func filter(
        items: [FinderServiceActionItem],
        query: String
    ) -> [FinderServiceActionItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return items }

        return items.filter { item in
            item.title.localizedCaseInsensitiveContains(normalizedQuery)
                || item.actionID.localizedCaseInsensitiveContains(normalizedQuery)
                || item.category.localizedName.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    public static func normalizedSelectionPaths(
        fileURLStrings: [String],
        legacyPaths: [String]
    ) -> [String] {
        let fileURLPaths = fileURLStrings.compactMap { value -> String? in
            guard let url = URL(string: value), url.isFileURL else { return nil }
            return url.standardizedFileURL.path
        }
        let normalizedLegacyPaths = legacyPaths.compactMap { path -> String? in
            guard !path.isEmpty, (path as NSString).isAbsolutePath else { return nil }
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }

        var seen = Set<String>()
        return (fileURLPaths + normalizedLegacyPaths).filter { seen.insert($0).inserted }
    }

    private static func comesBefore(
        _ lhs: FinderServiceActionItem,
        _ rhs: FinderServiceActionItem
    ) -> Bool {
        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite
        }
        if lhs.category != rhs.category {
            return categoryIndex(lhs.category) < categoryIndex(rhs.category)
        }
        let titleOrder = lhs.title.localizedCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.actionID < rhs.actionID
    }

    private static func categoryIndex(_ category: ActionCategory) -> Int {
        ActionCategory.allCases.firstIndex(of: category) ?? ActionCategory.allCases.count
    }
}

import Foundation

/// “服务”菜单中的直达动作策略。收藏顺序、推荐动作和安全边界只在这里维护。
public enum FinderQuickActionPolicy {
    public static let maximumDirectActionCount = 8

    public static let recommendedActionIDs = [
        "guyue.action.filemanage.cut",
        "guyue.action.filemanage.copyPath",
        "guyue.action.filemanage.copyName",
        "guyue.action.terminal.terminal",
        "guyue.action.utility.calculateSHA256"
    ]

    private static let recommendedActionIDSet = Set(recommendedActionIDs)

    public static func isRecommended(actionID: String) -> Bool {
        recommendedActionIDSet.contains(actionID)
    }

    public static func resolveDirectItems(
        actions: [MenuAction],
        favoriteActionIDs: [String],
        isEnabled: (MenuAction) -> Bool,
        isExternalAppAvailable: (String) -> Bool
    ) -> [FinderServiceActionItem] {
        var actionsByID: [String: MenuAction] = [:]
        for action in actions where actionsByID[action.actionId] == nil {
            actionsByID[action.actionId] = action
        }

        func eligibleAction(for actionID: String) -> MenuAction? {
            guard let action = actionsByID[actionID],
                  isEnabled(action),
                  !action.isHighRisk else {
                return nil
            }
            if let bundleIdentifier = action.associatedBundleIdentifier,
               !isExternalAppAvailable(bundleIdentifier) {
                return nil
            }
            return action
        }

        var result: [FinderServiceActionItem] = []
        var includedIDs = Set<String>()

        func append(_ actionID: String, isFavorite: Bool, favoriteRank: Int?) {
            guard result.count < maximumDirectActionCount,
                  !includedIDs.contains(actionID),
                  let action = eligibleAction(for: actionID) else {
                return
            }
            includedIDs.insert(actionID)
            result.append(
                FinderServiceActionItem(
                    actionID: action.actionId,
                    title: action.localizedTitle,
                    iconName: action.iconName,
                    category: action.category,
                    isFavorite: isFavorite,
                    isHighRisk: action.isHighRisk,
                    isRecommended: isRecommended(actionID: action.actionId),
                    favoriteRank: favoriteRank
                )
            )
        }

        for (rank, actionID) in favoriteActionIDs.enumerated() {
            append(actionID, isFavorite: true, favoriteRank: rank)
        }
        for actionID in recommendedActionIDs {
            append(actionID, isFavorite: false, favoriteRank: nil)
        }
        return result
    }
}

public enum FinderServicePaletteScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case common
    case newFile
    case fileManage
    case terminal
    case utility

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .all: return "全部"
        case .common: return "常用"
        case .newFile: return "新建"
        case .fileManage: return "文件"
        case .terminal: return "终端"
        case .utility: return "工具"
        }
    }

    fileprivate var category: ActionCategory? {
        switch self {
        case .all, .common: return nil
        case .newFile: return .newFile
        case .fileManage: return .fileManage
        case .terminal: return .terminal
        case .utility: return .utility
        }
    }
}

public struct FinderServicePaletteSection: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let items: [FinderServiceActionItem]

    public init(id: String, title: String, items: [FinderServiceActionItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// 把已通过后端可用性校验的动作转换为面板分区，UI 不再重复权限与去重规则。
public enum FinderServicePaletteBuilder {
    public static func sections(
        items: [FinderServiceActionItem],
        scope: FinderServicePaletteScope,
        query: String
    ) -> [FinderServicePaletteSection] {
        let filtered = uniqueItems(FinderServiceCatalog.filter(items: items, query: query))

        switch scope {
        case .all:
            return allSections(items: filtered)
        case .common:
            let common = filtered.filter { $0.isFavorite || $0.isRecommended }
            return common.isEmpty ? [] : [
                FinderServicePaletteSection(id: "common", title: "常用", items: common)
            ]
        case .newFile, .fileManage, .terminal, .utility:
            guard let category = scope.category else { return [] }
            let categoryItems = filtered.filter { $0.category == category }
            return categoryItems.isEmpty ? [] : [
                FinderServicePaletteSection(
                    id: category.rawValue,
                    title: category.localizedName,
                    items: categoryItems
                )
            ]
        }
    }

    private static func allSections(
        items: [FinderServiceActionItem]
    ) -> [FinderServicePaletteSection] {
        var sections: [FinderServicePaletteSection] = []
        let favorites = items.filter(\.isFavorite)
        if !favorites.isEmpty {
            sections.append(
                FinderServicePaletteSection(id: "favorites", title: "已收藏", items: favorites)
            )
        }

        let recommendations = items.filter { !$0.isFavorite && $0.isRecommended }
        if !recommendations.isEmpty {
            sections.append(
                FinderServicePaletteSection(
                    id: "recommendations",
                    title: "常用推荐",
                    items: recommendations
                )
            )
        }

        for category in ActionCategory.allCases {
            let categoryItems = items.filter {
                !$0.isFavorite && !$0.isRecommended && $0.category == category
            }
            if !categoryItems.isEmpty {
                sections.append(
                    FinderServicePaletteSection(
                        id: category.rawValue,
                        title: category.localizedName,
                        items: categoryItems
                    )
                )
            }
        }
        return sections
    }

    private static func uniqueItems(
        _ items: [FinderServiceActionItem]
    ) -> [FinderServiceActionItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.actionID).inserted }
    }
}

public enum FinderQuickServiceManifest {
    public static func encodedData(
        items: [FinderServiceActionItem],
        appVersion: String
    ) throws -> Data {
        let services: [[String: Any]] = items.map { item in
            [
                "NSMenuItem": ["default": "右键助手 · \(item.title)"],
                "NSMessage": "performFinderService",
                "NSPortName": FinderQuickServiceProtocol.providerPortName,
                "NSRequiredContext": ["NSTextContent": "FilePath"],
                "NSUserData": item.actionID,
                "NSSendTypes": ["NSFilenamesPboardType"]
            ]
        }
        let propertyList: [String: Any] = [
            "CFBundleIdentifier": FinderQuickServiceProtocol.bundleIdentifier,
            "CFBundleName": FinderQuickServiceProtocol.providerPortName,
            "CFBundleDisplayName": "右键助手快捷动作",
            "CFBundleExecutable": FinderQuickServiceProtocol.executableName,
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": appVersion,
            "CFBundleVersion": "1",
            "LSUIElement": true,
            "NSPrincipalClass": "NSApplication",
            "NSServices": services
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
    }
}

/// 动态服务 bundle 的最小文件系统边界，支持内容比较、原子写入和幂等删除。
public struct FinderQuickServiceBundleStore: Sendable {
    public let servicesDirectoryURL: URL

    public init(servicesDirectoryURL: URL) {
        self.servicesDirectoryURL = servicesDirectoryURL
    }

    public var bundleURL: URL {
        servicesDirectoryURL.appendingPathComponent(
            FinderQuickServiceProtocol.bundleDirectoryName,
            isDirectory: true
        )
    }

    public var infoPlistURL: URL {
        bundleURL.appendingPathComponent("Contents/Info.plist")
    }

    public var executableURL: URL {
        bundleURL.appendingPathComponent(
            "Contents/MacOS/\(FinderQuickServiceProtocol.executableName)"
        )
    }

    @discardableResult
    public func synchronize(manifestData: Data?, executableData: Data?) throws -> Bool {
        let fileManager = FileManager.default
        guard let manifestData else {
            guard fileManager.fileExists(atPath: bundleURL.path) else { return false }
            try fileManager.removeItem(at: bundleURL)
            return true
        }

        guard let executableData else {
            throw CocoaError(.fileNoSuchFile)
        }
        let manifestMatches = (try? Data(contentsOf: infoPlistURL)) == manifestData
        let executableMatches = (try? Data(contentsOf: executableURL)) == executableData
        if manifestMatches && executableMatches {
            return false
        }

        try fileManager.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !executableMatches {
            try executableData.write(to: executableURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executableURL.path
            )
        }
        if !manifestMatches {
            try manifestData.write(to: infoPlistURL, options: .atomic)
        }
        return true
    }
}

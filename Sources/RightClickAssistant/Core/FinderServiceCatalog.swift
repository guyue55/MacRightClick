import Foundation

/// FinderSync 在 File Provider 托管目录中可能被 Finder 抑制。
/// 系统服务作为保守的降级通道，只暴露默认启用且低风险的选中项动作。
public enum FinderServiceCatalog {
    public struct Definition: Equatable, Sendable {
        public let title: String
        public let actionID: String

        public init(title: String, actionID: String) {
            self.title = title
            self.actionID = actionID
        }
    }

    public static let definitions: [Definition] = [
        Definition(title: "剪切", actionID: "guyue.action.filemanage.cut"),
        Definition(title: "拷贝完整路径", actionID: "guyue.action.filemanage.copyPath"),
        Definition(title: "拷贝文件名", actionID: "guyue.action.filemanage.copyName"),
        Definition(title: "在系统终端中打开", actionID: "guyue.action.terminal.terminal"),
        Definition(title: "获取 SHA256", actionID: "guyue.action.utility.calculateSHA256")
    ]

    private static let actionIDs = Set(definitions.map(\.actionID))

    public static func actionID(for userData: String) -> String? {
        actionIDs.contains(userData) ? userData : nil
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
}

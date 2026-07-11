import Foundation

public enum PathCopyService {
    /// 生成可直接粘贴到 POSIX shell 命令后的参数列表。
    public static func shellEscapedArguments(_ urls: [URL]) -> String {
        urls
            .map { url in
                let escapedPath = url.path.replacingOccurrences(of: "'", with: "'\\''")
                return "'\(escapedPath)'"
            }
            .joined(separator: " ")
    }

    /// 为每个目标查找最近的 Git 根目录，并按原选择顺序返回仓库相对路径。
    /// 任一目标不在 Git 仓库内时返回 nil，避免复制一组含义不一致的结果。
    public static func gitRelativePaths(
        _ urls: [URL],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [String]? {
        guard !urls.isEmpty else { return nil }

        var paths: [String] = []
        paths.reserveCapacity(urls.count)
        for url in urls {
            let target = url.standardizedFileURL
            guard let root = nearestGitRoot(for: target, fileExists: fileExists),
                  let path = relativePath(from: root, to: target) else { return nil }
            paths.append(path)
        }
        return paths
    }

    private static func nearestGitRoot(
        for target: URL,
        fileExists: (String) -> Bool
    ) -> URL? {
        var candidate = target
        while true {
            let gitMarker = candidate.appendingPathComponent(".git")
            if fileExists(gitMarker.path) {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
    }

    private static func relativePath(from root: URL, to target: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        guard targetComponents.count >= rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }

        let relativeComponents = targetComponents.dropFirst(rootComponents.count)
        return relativeComponents.isEmpty ? "." : relativeComponents.joined(separator: "/")
    }
}

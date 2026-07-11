import Foundation
import AppKit

public enum PathCopyKind: String, Sendable {
    case shellEscaped
    case gitRelative
}

public final class PathCopyAction: MenuAction, @unchecked Sendable {
    public let kind: PathCopyKind

    public init(kind: PathCopyKind) {
        self.kind = kind
    }

    public var actionId: String {
        "guyue.action.pathcopy.\(kind.rawValue)"
    }

    public var localizedTitle: String {
        switch kind {
        case .shellEscaped: return "复制 Shell 安全路径"
        case .gitRelative: return "复制 Git 相对路径"
        }
    }

    public var iconName: String? {
        switch kind {
        case .shellEscaped: return "terminal"
        case .gitRelative: return "arrow.triangle.branch"
        }
    }

    public let category: ActionCategory = .fileManage
    public let tier: ActionTier = .professional
    public let isEnabledByDefault = false

    public func isAvailable(for targetURLs: [URL]) -> Bool {
        isAvailable(for: targetURLs, isContainer: false)
    }

    public func isAvailable(for targetURLs: [URL], isContainer: Bool) -> Bool {
        guard !isContainer, !targetURLs.isEmpty else { return false }
        switch kind {
        case .shellEscaped:
            return true
        case .gitRelative:
            return PathCopyService.gitRelativePaths(targetURLs) != nil
        }
    }

    public func execute(targetURLs: [URL]) -> Bool {
        submit(targetURLs: targetURLs, completion: { _ in }) == .accepted
    }

    public func submit(
        targetURLs: [URL],
        completion: @escaping @Sendable (ActionCompletionStatus) -> Void
    ) -> ActionSubmission {
        guard let value = pasteboardValue(for: targetURLs) else { return .rejected }
        let title = localizedTitle
        let itemCount = targetURLs.count

        DispatchQueue.main.async {
            NSPasteboard.general.clearContents()
            let succeeded = NSPasteboard.general.setString(value, forType: .string)
            SharedHUDManager.show(
                title: succeeded ? title : "复制失败",
                content: succeeded ? "已复制 \(itemCount) 个路径" : "无法写入系统剪贴板",
                isSuccess: succeeded
            )
            completion(succeeded ? .succeeded : .failed)
        }
        return .accepted
    }

    private func pasteboardValue(for targetURLs: [URL]) -> String? {
        switch kind {
        case .shellEscaped:
            guard !targetURLs.isEmpty else { return nil }
            return PathCopyService.shellEscapedArguments(targetURLs)
        case .gitRelative:
            return PathCopyService.gitRelativePaths(targetURLs)?.joined(separator: "\n")
        }
    }
}

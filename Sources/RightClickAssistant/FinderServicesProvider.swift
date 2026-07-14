import AppKit
import Foundation

/// 为 iCloud Drive 等 File Provider 目录提供 FinderSync 之外的系统服务入口。
/// 真实执行仍通过共享事务队列进入 ActionDispatcher。
final class FinderServicesProvider: NSObject {
    static let shared = FinderServicesProvider()

    private static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private static let fileURLType = NSPasteboard.PasteboardType("public.file-url")
    private static let actionSignal = Notification.Name(
        "guyue.RightClickAssistant.triggerActionSignal"
    )

    @objc(performFinderService:userData:error:)
    func performFinderService(
        _ pasteboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let actionID = FinderServiceCatalog.actionID(for: userData) else {
            errorPointer.pointee = "未知的右键助手服务" as NSString
            return
        }

        let paths = Self.selectionPaths(from: pasteboard)
        guard !paths.isEmpty else {
            errorPointer.pointee = "请先在 Finder 中选择文件或文件夹" as NSString
            return
        }

        guard let action = ActionDispatcher.shared.action(forId: actionID),
              SharedStorageManager.shared.isActionEnabled(action) else {
            errorPointer.pointee = "该动作已在右键助手设置中关闭" as NSString
            return
        }

        let targetURLs = paths.map { URL(fileURLWithPath: $0) }
        guard action.isAvailable(for: targetURLs, isContainer: false) else {
            errorPointer.pointee = "该动作不适用于当前选中项" as NSString
            return
        }

        do {
            try SharedStorageManager.shared.enqueueAction(
                actionId: actionID,
                paths: paths,
                invocationKind: .items
            )
            DistributedNotificationCenter.default().postNotificationName(
                Self.actionSignal,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        } catch {
            AppLog.error("Finder 服务入队失败：\(error.localizedDescription)", category: .storage)
            errorPointer.pointee = "无法提交操作：\(error.localizedDescription)" as NSString
        }
    }

    private static func selectionPaths(from pasteboard: NSPasteboard) -> [String] {
        let fileURLStrings = (pasteboard.pasteboardItems ?? []).compactMap {
            $0.string(forType: fileURLType)
        }
        let legacyPaths = pasteboard.propertyList(forType: legacyFilenamesType) as? [String] ?? []
        return FinderServiceCatalog.normalizedSelectionPaths(
            fileURLStrings: fileURLStrings,
            legacyPaths: legacyPaths
        )
    }
}

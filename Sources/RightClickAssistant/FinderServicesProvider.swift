import AppKit
import Foundation

/// 为 iCloud Drive 等 File Provider 目录提供 FinderSync 之外的系统服务入口。
/// 面板仅展示核心层解析结果，真实执行仍通过共享事务队列进入 ActionDispatcher。
final class FinderServicesProvider: NSObject {
    static let shared = FinderServicesProvider()

    private static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private static let fileURLType = NSPasteboard.PasteboardType("public.file-url")
    private static let actionSignal = Notification.Name(
        "guyue.RightClickAssistant.triggerActionSignal"
    )

    @MainActor
    @objc(performFinderService:userData:error:)
    func performFinderService(
        _ pasteboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard FinderServiceCatalog.accepts(userData: userData) else {
            errorPointer.pointee = "未知的右键助手服务" as NSString
            return
        }

        let paths = Self.selectionPaths(from: pasteboard)
        guard !paths.isEmpty else {
            errorPointer.pointee = "请先在 Finder 中选择文件或文件夹" as NSString
            return
        }

        let targetURLs = paths.map { URL(fileURLWithPath: $0) }
        let cache = ActionConfigCache.shared
        let items = FinderServiceCatalog.resolveItems(
            actions: ActionDispatcher.shared.allActions,
            targetURLs: targetURLs,
            isEnabled: {
                cache.isEnabled($0.actionId, default: $0.isEnabledByDefault)
            },
            isFavorite: { cache.isFavorite($0.actionId) }
        )
        guard !items.isEmpty else {
            errorPointer.pointee = "当前选中项没有已启用且可用的动作" as NSString
            return
        }

        errorPointer.pointee = nil
        FinderServicePaletteController.shared.show(
            items: items,
            selectedPaths: paths,
            onSelect: { [weak self] actionID in
                self?.submit(actionID: actionID, paths: paths)
            }
        )
    }

    @MainActor
    private func submit(actionID: String, paths: [String]) {
        let targetURLs = paths.map { URL(fileURLWithPath: $0) }
        guard let action = ActionDispatcher.shared.action(forId: actionID) else {
            showFailure("动作已不存在，请重新打开右键助手")
            return
        }

        let eligible = FinderServiceCatalog.resolveItems(
            actions: [action],
            targetURLs: targetURLs,
            isEnabled: { SharedStorageManager.shared.isActionEnabled($0) },
            isFavorite: { _ in false }
        )
        guard eligible.first?.actionID == actionID else {
            showFailure("动作已关闭、目标已变化或当前不可用")
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
            showFailure("无法提交操作：\(error.localizedDescription)")
        }
    }

    private func showFailure(_ message: String) {
        SharedHUDManager.show(title: "操作未提交", content: message, isSuccess: false)
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

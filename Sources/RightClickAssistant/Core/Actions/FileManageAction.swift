import Foundation
import AppKit

// 注：破坏性确认弹窗与并发裁决已抽到独立模块：
// - `ConfirmationPresenter` / `MainThreadAlertPresenter`：弹窗呈现
// - `DeletionRequestCoordinator`：并发裁决 + 后台 IO
// 这里只剩"接到事件 → 委托 Coordinator"的薄壳，
// 彻底切断 folder-monitor 队列 main.sync 弹窗带来的死锁链。

public struct CutClipboardSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public let urls: [URL]

    public init(id: UUID = UUID(), urls: [URL]) {
        self.id = id
        self.urls = urls
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case paths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let paths = try container.decode([String].self, forKey: .paths)
        urls = paths.map { URL(fileURLWithPath: $0) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(urls.map(\.path), forKey: .paths)
    }
}

/// 持久化文件剪切状态。快照 ID 提供 compare-and-replace 语义，防止旧粘贴任务
/// 完成时清除用户随后创建的新剪切状态。
public final class FileCutClipboard: @unchecked Sendable {
    public static let shared = FileCutClipboard()

    private let queue = DispatchQueue(label: "guyue.cutboard")
    private let storageManager: SharedStorageManager

    public init(storageManager: SharedStorageManager = .shared) {
        self.storageManager = storageManager
    }
    
    private var clipboardURL: URL {
        storageManager.sharedContainerURL.appendingPathComponent("clipboard.json")
    }

    public var snapshot: CutClipboardSnapshot? {
        queue.sync { loadSnapshotUnlocked() }
    }
    
    public var cutURLs: [URL] {
        get { snapshot?.urls ?? [] }
        set { _ = setCutURLs(newValue) }
    }

    @discardableResult
    public func setCutURLs(_ urls: [URL]) -> Bool {
        queue.sync {
            if urls.isEmpty {
                return removeSnapshotUnlocked()
            }
            return writeSnapshotUnlocked(CutClipboardSnapshot(urls: urls))
        }
    }

    /// 仅当当前剪切状态仍是调用方拍下的版本时才替换。
    @discardableResult
    public func replace(snapshotID: UUID, remainingURLs: [URL]) -> Bool {
        queue.sync {
            guard let current = loadSnapshotUnlocked(), current.id == snapshotID else {
                return false
            }
            if remainingURLs.isEmpty {
                return removeSnapshotUnlocked()
            }
            return writeSnapshotUnlocked(CutClipboardSnapshot(id: snapshotID, urls: remainingURLs))
        }
    }
    
    public func clear() {
        queue.sync { _ = removeSnapshotUnlocked() }
    }

    private func loadSnapshotUnlocked() -> CutClipboardSnapshot? {
        guard let data = try? Data(contentsOf: clipboardURL) else { return nil }
        if let snapshot = try? JSONDecoder().decode(CutClipboardSnapshot.self, from: data) {
            return snapshot
        }

        // v1.1 兼容：旧格式是裸路径数组。首次读取时立即迁移为带 ID 的对象，
        // 保证随后 compare-and-replace 使用稳定版本号。
        guard let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        let migrated = CutClipboardSnapshot(urls: paths.map { URL(fileURLWithPath: $0) })
        return writeSnapshotUnlocked(migrated) ? migrated : nil
    }

    private func writeSnapshotUnlocked(_ snapshot: CutClipboardSnapshot) -> Bool {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: clipboardURL, options: .atomic)
            return true
        } catch {
            AppLog.error("剪切状态写入失败：\(error.localizedDescription)", category: .storage)
            return false
        }
    }

    private func removeSnapshotUnlocked() -> Bool {
        guard FileManager.default.fileExists(atPath: clipboardURL.path) else { return true }
        do {
            try FileManager.default.removeItem(at: clipboardURL)
            return true
        } catch {
            AppLog.error("剪切状态清理失败：\(error.localizedDescription)", category: .storage)
            return false
        }
    }
}

/// 支持的右键文件管理动作子类型
public enum FileManageType: String, Codable, Sendable {
    case cut = "cut"                  // 剪切
    case paste = "paste"              // 粘贴（执行移动）
    case permanentDelete = "delete"   // 彻底删除
    case copyPath = "copyPath"        // 拷贝完整路径
    case copyName = "copyName"        // 拷贝文件名
    case moveTo = "moveTo"            // 移动到...
    case copyTo = "copyTo"            // 复制到...
}

public final class FileManageAction: MenuAction, @unchecked Sendable {
    public let actionId: String
    public let localizedTitle: String
    public let iconName: String?
    public let category: ActionCategory = .fileManage
    
    public let manageType: FileManageType
    private let customTargetPath: URL? // 针对特定复制到/移动到文件夹的预设路径

    public var tier: ActionTier {
        switch manageType {
        case .cut, .paste, .copyPath, .copyName:
            return .essential
        case .permanentDelete, .moveTo, .copyTo:
            return .advanced
        }
    }

    public var isHighRisk: Bool {
        return tier == .advanced
    }

    public var isEnabledByDefault: Bool {
        return !isHighRisk
    }

    public var riskDescription: String? {
        switch manageType {
        case .permanentDelete:
            return "绕过废纸篓直接删除文件，无法撤销。"
        case .moveTo:
            return "会将选中项目移动到其他目录，跨磁盘卷时会执行复制后删除原件。"
        case .copyTo:
            return "会将选中项目复制到其他目录，可能产生大量副本。"
        case .cut, .paste, .copyPath, .copyName:
            return nil
        }
    }
    
    public init(type: FileManageType, customTargetPath: URL? = nil, customTitle: String? = nil) {
        self.manageType = type
        self.customTargetPath = customTargetPath
        self.actionId = "guyue.action.filemanage.\(type.rawValue)"
        
        if let title = customTitle {
            self.localizedTitle = title
        } else {
            switch type {
            case .cut: self.localizedTitle = "剪切"
            case .paste: self.localizedTitle = "粘贴"
            case .permanentDelete: self.localizedTitle = "彻底删除"
            case .copyPath: self.localizedTitle = "拷贝完整路径"
            case .copyName: self.localizedTitle = "拷贝文件名"
            case .moveTo: self.localizedTitle = "移动到..."
            case .copyTo: self.localizedTitle = "复制到..."
            }
        }
        
        switch type {
        case .cut: self.iconName = "scissors"
        case .paste: self.iconName = "doc.on.clipboard"
        case .permanentDelete: self.iconName = "trash.slash"
        case .copyPath: self.iconName = "link"
        case .copyName: self.iconName = "pencil.and.outline"
        case .moveTo: self.iconName = "arrow.right.doc.on.clipboard"
        case .copyTo: self.iconName = "doc.on.doc"
        }
    }
    
    // 旧的 runOnMainThread/confirmHighRiskOperation 已经移除：
    // moveTo/copyTo 走 transferRunner，permanentDelete 走 DeletionRequestCoordinator，
    // 任何后台 → 主线程同步的死锁路径都不再保留。
    
    public func isAvailable(for targetURLs: [URL]) -> Bool {
        return isAvailable(for: targetURLs, isContainer: false)
    }
    
    public func isAvailable(for targetURLs: [URL], isContainer: Bool) -> Bool {
        if isContainer {
            // 右键空白背景 (Container) 时：只有“粘贴”操作可能可用（前提是剪切板内有被剪切的文件）
            // 此时 cut, permanentDelete, copyPath, copyName, moveTo, copyTo 等针对特定选中项目的动作全部隐藏
            return manageType == .paste && !FileCutClipboard.shared.cutURLs.isEmpty
        } else {
            // 正常选中项目 (Items) 时：
            switch manageType {
            case .paste:
                // 粘贴必须建立在已经剪切了文件，且当前选中了目录（或选中的项目是目录）的前提下
                return !FileCutClipboard.shared.cutURLs.isEmpty && !targetURLs.isEmpty
            case .cut, .permanentDelete, .copyPath, .copyName, .moveTo, .copyTo:
                // 这些操作都需要选中至少一个目标文件或文件夹
                return !targetURLs.isEmpty
            }
        }
    }
    
    public func execute(targetURLs: [URL]) -> Bool {
        guard !targetURLs.isEmpty else { return false }
        
        switch manageType {
        case .cut:
            guard FileCutClipboard.shared.setCutURLs(targetURLs) else {
                SharedHUDManager.show(
                    title: "剪切失败",
                    content: "无法保存剪切状态，请检查共享目录权限后重试",
                    isSuccess: false
                )
                return false
            }
            print("[FileManage] 剪切了 \(targetURLs.count) 个文件。")
            SharedHUDManager.show(
                title: "剪切成功",
                content: "已将 \(targetURLs.count) 个项目加入剪切板，请在目标文件夹右键粘贴",
                isSuccess: true
            )
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("guyue.RightClickAssistant.configChanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("guyue.RightClickAssistant.cutStateChanged"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            return true
            
        case .paste:
            guard let cutSnapshot = FileCutClipboard.shared.snapshot,
                  !cutSnapshot.urls.isEmpty else { return false }

            // 确定粘贴的目的文件夹（在调用线程拍快照即可，FileManager.fileExists 是廉价 stat，
            // 真正的重 IO（moveItem / crossVolumeMove）必须搬到 BackgroundActionRunner 的私有队列上跑，
            // 否则跨盘大文件会让 folder-monitor 串行队列长期持锁，引发 P1-1 卡顿/死锁残余风险）。
            let destinationDir = getDestinationDirectory(from: targetURLs.first!)
            FileManageAction.pasteRunner.submit {
                _ = FileManageAction.executePaste(
                    snapshot: cutSnapshot,
                    destinationDir: destinationDir
                )
            }
            // 事件已异步接管：folder-monitor 队列立刻返回，UI 不再卡。
            // 真正的成功/失败计数通过 HUD 异步反馈给用户。
            return true
            
        case .permanentDelete:
            // 真正的弹窗 + IO 全部委托给 DeletionRequestCoordinator，
            // 让 folder-monitor 串行队列**立刻**返回，不再阻塞主线程。
            // accepted 与否对调用方都是"事件已被接受"，
            // 用户感知的成功/失败通过 HUD 异步给出。
            let outcome = DeletionRequestCoordinator.shared.requestDeletion(targets: targetURLs)
            return outcome == .accepted
            
        case .copyPath:
            let paths = targetURLs.map { $0.path }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths, forType: .string)
            print("[FileManage] 已成功拷贝 \(targetURLs.count) 个路径到系统剪贴板。")
            let pathContent: String
            if targetURLs.count == 1, let first = targetURLs.first {
                pathContent = first.path
            } else {
                pathContent = "已拷贝 \(targetURLs.count) 个路径"
            }
            SharedHUDManager.show(
                title: "路径已拷贝",
                content: pathContent,
                isSuccess: true
            )
            return true
            
        case .copyName:
            let names = targetURLs.map { $0.lastPathComponent }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(names, forType: .string)
            print("[FileManage] 已成功拷贝 \(targetURLs.count) 个文件名到系统剪贴板。")
            let nameContent: String
            if targetURLs.count == 1, let first = targetURLs.first {
                nameContent = first.lastPathComponent
            } else {
                nameContent = "已拷贝 \(targetURLs.count) 个文件名"
            }
            SharedHUDManager.show(
                title: "名称已拷贝",
                content: nameContent,
                isSuccess: true
            )
            return true
            
        case .moveTo, .copyTo:
            // moveTo / copyTo 走通用 InteractiveActionRunner：
            // - prompt 在主线程：选目录 + 二次确认。
            // - perform 在后台串行队列：跨卷 copy-then-delete 这种重 IO 不再阻塞 folder-monitor 队列。
            // - 全局闸门保证 modal 期间再触发任何交互动作都被合并丢弃，
            //   与上一轮 DeletionRequestCoordinator 同款斩断死锁链。
            let op: TransferOp = (manageType == .copyTo) ? .copy : .move
            let snapshotTargets = targetURLs  // 闭包安全：捕获快照
            let preset = customTargetPath
            let outcome = FileManageAction.transferRunner.run(
                prompt: { () -> URL? in
                    if let preset = preset { return preset }
                    return FileManageAction.chooseDestinationDirectory()
                        .flatMap { url in
                            // 与旧逻辑一致：选完目录还要做一次「确认 X 操作」的二次确认。
                            let ok = FileManageAction.confirmTransfer(
                                op: op,
                                count: snapshotTargets.count,
                                destination: url
                            )
                            return ok ? url : nil
                        }
                },
                perform: { destinationDir in
                    _ = FileManageAction.executeTransfer(
                        op: op,
                        targets: snapshotTargets,
                        destination: destinationDir
                    )
                }
            )
            return outcome == .accepted
        }
    }

    public func submit(
        targetURLs: [URL],
        completion: @escaping @Sendable (ActionCompletionStatus) -> Void
    ) -> ActionSubmission {
        guard !targetURLs.isEmpty else {
            completion(.failed)
            return .rejected
        }

        switch manageType {
        case .paste:
            guard let cutSnapshot = FileCutClipboard.shared.snapshot,
                  !cutSnapshot.urls.isEmpty else {
                completion(.failed)
                return .rejected
            }
            let destinationDir = getDestinationDirectory(from: targetURLs[0])
            FileManageAction.pasteRunner.submit({
                FileManageAction.executePaste(
                    snapshot: cutSnapshot,
                    destinationDir: destinationDir
                )
            }, completion: completion)
            return .accepted

        case .permanentDelete:
            let outcome = DeletionRequestCoordinator.shared.requestDeletion(
                targets: targetURLs,
                completion: completion
            )
            return outcome == .accepted ? .accepted : .rejected

        case .moveTo, .copyTo:
            let op: TransferOp = manageType == .copyTo ? .copy : .move
            let snapshotTargets = targetURLs
            let preset = customTargetPath
            let outcome = FileManageAction.transferRunner.run(
                prompt: { () -> URL? in
                    if let preset { return preset }
                    return FileManageAction.chooseDestinationDirectory().flatMap { url in
                        FileManageAction.confirmTransfer(
                            op: op,
                            count: snapshotTargets.count,
                            destination: url
                        ) ? url : nil
                    }
                },
                perform: { destinationDir in
                    FileManageAction.executeTransfer(
                        op: op,
                        targets: snapshotTargets,
                        destination: destinationDir
                    )
                },
                completion: completion
            )
            return outcome == .accepted ? .accepted : .rejected

        case .copyPath, .copyName:
            DispatchQueue.main.async { [self] in
                completion(execute(targetURLs: targetURLs) ? .succeeded : .failed)
            }
            return .accepted

        case .cut:
            completion(execute(targetURLs: targetURLs) ? .succeeded : .failed)
            return .accepted
        }
    }
    
    private func getDestinationDirectory(from url: URL) -> URL {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }
}

// MARK: - moveTo/copyTo 公共支持（InteractiveActionRunner 拆出的纯函数）
extension FileManageAction {

    /// 转移操作语义。把 if/else 都集中在这里，避免 case 分支再次散落。
    enum TransferOp: Sendable {
        case copy
        case move

        var verb: String { self == .copy ? "复制" : "移动" }
    }

    /// 所有 moveTo/copyTo 共享一个 Runner，
    /// 一来后台 IO 自然串行（前一次没跑完，下一次排队不抢卷头），
    /// 二来与 toggleHidden Runner 通过 InteractiveActionGate 共享 modal 互斥。
    public static let transferRunner = InteractiveActionRunner(
        actionLabel: "fileManage.transfer",
        ioQueueLabel: "guyue.RightClickAssistant.filemanage-transfer-io"
    )

    /// paste 没有自身弹窗，但跨盘大文件会让 moveItem/crossVolumeMove 长期阻塞队列。
    /// 用 BackgroundActionRunner 把 IO 投到私有串行队列，folder-monitor 队列立刻返回。
    /// 不抢 InteractiveActionGate：paste 与 modal 互斥不在同一层面，不该相互阻塞。
    static let pasteRunner = BackgroundActionRunner(
        actionLabel: "fileManage.paste",
        ioQueueLabel: "guyue.RightClickAssistant.filemanage-paste-io"
    )

    /// 后台串行队列：批量执行粘贴 + HUD 反馈。
    /// 跨卷 move 会自动降级走 `crossVolumeMove`（copy-then-delete 事务）。
    static func executePaste(
        snapshot: CutClipboardSnapshot,
        destinationDir: URL
    ) -> ActionCompletionStatus {
        var successCount = 0
        var failedURLs: [URL] = []
        for fileURL in snapshot.urls {
            let destURL = destinationDir.appendingPathComponent(fileURL.lastPathComponent)

            // 同名规避：用「Name N.ext」递增重命名，永不覆盖目标文件。
            var finalDestURL = destURL
            var counter = 1
            let nameWithoutExtension = fileURL.deletingPathExtension().lastPathComponent
            let fileExtension = fileURL.pathExtension
            while FileManager.default.fileExists(atPath: finalDestURL.path) {
                let newName = fileExtension.isEmpty
                    ? "\(nameWithoutExtension) \(counter)"
                    : "\(nameWithoutExtension) \(counter).\(fileExtension)"
                finalDestURL = destinationDir.appendingPathComponent(newName)
                counter += 1
            }

            do {
                try FileManager.default.moveItem(at: fileURL, to: finalDestURL)
                successCount += 1
            } catch {
                AppLog.error(
                    "moveItem 直接失败，触发跨卷事务化降级: \(error.localizedDescription)",
                    category: .action
                )
                if FileManageAction.crossVolumeMove(from: fileURL, to: finalDestURL) {
                    successCount += 1
                } else {
                    failedURLs.append(fileURL)
                }
            }
        }

        AppLog.info("[FileManage] 成功粘贴/移动了 \(successCount) 个文件。", category: .action)
        let replaced = FileCutClipboard.shared.replace(
            snapshotID: snapshot.id,
            remainingURLs: failedURLs
        )
        if replaced {
            postCutStateChanged()
        }

        if failedURLs.isEmpty {
            SharedHUDManager.show(
                title: "粘贴成功",
                content: "已成功移动并粘贴了 \(successCount) 个项目",
                isSuccess: true
            )
        } else if successCount > 0 {
            SharedHUDManager.show(
                title: "粘贴部分成功",
                content: "成功 \(successCount) 个，失败 \(failedURLs.count) 个；失败项仍保留在剪切板",
                isSuccess: false
            )
        } else {
            SharedHUDManager.show(
                title: "粘贴失败",
                content: replaced
                    ? "失败项目已保留，请检查目标目录写入权限后重试"
                    : "请检查目标目录写入权限；新的剪切状态未被本次任务覆盖",
                isSuccess: false
            )
        }
        return failedURLs.isEmpty ? .succeeded : .failed
    }

    private static func postCutStateChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("guyue.RightClickAssistant.configChanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("guyue.RightClickAssistant.cutStateChanged"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    /// 主线程：弹 NSOpenPanel 让用户选目标目录。
    @MainActor
    static func chooseDestinationDirectory() -> URL? {
        dispatchPrecondition(condition: .onQueue(.main))
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择目标文件夹"
        panel.level = .modalPanel
        panel.orderFrontRegardless()
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 主线程：操作前的"二次确认 + 路径预览"弹窗。
    @MainActor
    static func confirmTransfer(op: TransferOp, count: Int, destination: URL) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        let alert = NSAlert()
        alert.messageText = "确认\(op.verb)到其他目录？"
        alert.informativeText = "将\(op.verb) \(count) 个项目到:\n\(destination.path)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确认\(op.verb)")
        alert.addButton(withTitle: "取消")
        alert.window.level = .modalPanel
        alert.window.orderFrontRegardless()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 后台串行队列：真正搬运/复制 + HUD 反馈。
    /// 跨卷 move 会自动降级走 `crossVolumeMove`。
    static func executeTransfer(
        op: TransferOp,
        targets: [URL],
        destination destinationDir: URL
    ) -> ActionCompletionStatus {
        var successCount = 0
        for fileURL in targets {
            let destURL = destinationDir.appendingPathComponent(fileURL.lastPathComponent)
            var finalDestURL = destURL
            var counter = 1
            let nameWithoutExtension = fileURL.deletingPathExtension().lastPathComponent
            let fileExtension = fileURL.pathExtension
            while FileManager.default.fileExists(atPath: finalDestURL.path) {
                let newName = "\(nameWithoutExtension) \(counter).\(fileExtension)"
                finalDestURL = destinationDir.appendingPathComponent(newName)
                counter += 1
            }

            do {
                switch op {
                case .copy:
                    try FileManager.default.copyItem(at: fileURL, to: finalDestURL)
                    successCount += 1
                case .move:
                    do {
                        try FileManager.default.moveItem(at: fileURL, to: finalDestURL)
                        successCount += 1
                    } catch {
                        AppLog.error(
                            "moveItem 直接失败（跨卷），触发事务化降级: \(error.localizedDescription)",
                            category: .action
                        )
                        if FileManageAction.crossVolumeMove(from: fileURL, to: finalDestURL) {
                            successCount += 1
                        }
                    }
                }
            } catch {
                AppLog.error(
                    "\(op.verb) 操作彻底失败: \(error.localizedDescription)",
                    category: .action
                )
            }
        }

        if successCount > 0 {
            SharedHUDManager.show(
                title: op == .copy ? "复制成功" : "移动成功",
                content: "已成功\(op.verb) \(successCount) 个项目到目标目录",
                isSuccess: true
            )
        } else {
            SharedHUDManager.show(
                title: op == .copy ? "复制失败" : "移动失败",
                content: "项目转移过程中权限不足或被系统拦截",
                isSuccess: false
            )
        }
        return successCount == targets.count ? .succeeded : .failed
    }
}

// MARK: - 跨卷移动事务化
public extension FileManageAction {
    /// 跨卷 Copy-Then-Delete 的事务化封装。
    /// - 任一步骤失败立即 cleanup 残留 dest，不再让用户看到「半个文件 + 完整原件」
    /// - 成功返回 true；失败返回 false 并在 AppLog 留痕
    static func crossVolumeMove(from src: URL, to dest: URL) -> Bool {
        return crossVolumeMove(
            from: src,
            to: dest,
            copy: { from, to in try FileManager.default.copyItem(at: from, to: to) },
            sanityCheck: { url in try defaultSanityCheck(url) }
        )
    }

    /// 注入式版本，仅供单测。生产路径不要直接调用。
    static func crossVolumeMove(
        from src: URL,
        to dest: URL,
        copy: (URL, URL) throws -> Void,
        sanityCheck: (URL) throws -> Void
    ) -> Bool {
        do {
            try copy(src, dest)
            try sanityCheck(dest)
            try FileManager.default.removeItem(at: src)
            return true
        } catch {
            // 关键：cleanup 残留 dest，避免「目标半个 + 源完整」并存
            try? FileManager.default.removeItem(at: dest)
            AppLog.error("跨卷移动失败已 cleanup: \(src.path) -> \(error.localizedDescription)", category: .action)
            return false
        }
    }

    private static func defaultSanityCheck(_ dest: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dest.path, isDirectory: &isDir) else {
            throw NSError(domain: "guyue.FileManage", code: 510, userInfo: [NSLocalizedDescriptionKey: "目标文件不存在"])
        }
        if !isDir.boolValue {
            let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
            if let size = attrs[.size] as? Int, size <= 0 {
                throw NSError(domain: "guyue.FileManage", code: 511, userInfo: [NSLocalizedDescriptionKey: "目标文件 size 为 0"])
            }
        }
    }
}

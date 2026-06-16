import Foundation
import AppKit
import os.lock

// MARK: - DeletionRequestCoordinator
///
/// 永久删除流程的并发裁决中心。把"是否弹窗 / 何时弹 / 谁来跑 IO"集中到一个模块。
///
/// 设计目标（基于真机死锁复盘）：
/// - 任何线程都可以提交删除请求；调用方立刻拿到 accepted/rejected，**不阻塞 folder-monitor 队列**。
/// - 同一时刻只允许 1 个 in-flight 弹窗。后续请求在 modal 关闭前直接拒绝并 HUD 提示，
///   彻底切断 "modal 期间堆积事件 → 重启后再次弹窗" 的复发链。
/// - 弹窗结果在主线程拿到后，**真正的删除/移到废纸篓 IO 切回后台串行队列**，主线程立刻空闲。
/// - 所有共享状态用 `os_unfair_lock` 保护，避免 `objc_sync_enter(self)` 与 AppKit 内部隐式锁混淆。
///
/// 与 `FileManageAction` 的协作：
/// - `FileManageAction.permanentDelete` 不再自己跑 modal，只把 targets 交给本类。
/// - 本类负责出弹窗、出 HUD、做 IO、写日志。`FileManageAction` 调完即 return，
///   高内聚低耦合，方便测试。
public final class DeletionRequestCoordinator: @unchecked Sendable {
    public nonisolated(unsafe) static let shared = DeletionRequestCoordinator(
        presenter: MainThreadAlertPresenter()
    )

    private let presenter: ConfirmationPresenter
    private var unfairLock = os_unfair_lock()
    private var isPresenting = false
    /// 用于 IO 执行的串行后台队列。和 folder-monitor 解耦，避免任何反向 main.sync。
    private let ioQueue = DispatchQueue(
        label: "guyue.RightClickAssistant.deletion-io",
        qos: .userInitiated
    )

    /// 注入式构造：方便单测替换 presenter。
    public init(presenter: ConfirmationPresenter) {
        self.presenter = presenter
    }

    /// 提交一次永久删除请求。任何线程都可以调用。
    /// - Returns: `accepted` 表示已接管；`rejected` 表示当前有 in-flight 弹窗，请求被合并丢弃。
    @discardableResult
    public func requestDeletion(targets: [URL]) -> Outcome {
        guard !targets.isEmpty else { return .rejected(reason: .emptyTargets) }

        // 1. 在锁内决定是否接管，避免双弹窗。
        os_unfair_lock_lock(&unfairLock)
        if isPresenting {
            os_unfair_lock_unlock(&unfairLock)
            // 关键 UX 决策：不排队，直接告诉用户"先处理上一个"，
            // 因为排队会让用户在不知情时连续承担破坏性确认。
            DispatchQueue.main.async {
                SharedHUDManager.show(
                    title: "请先处理上一个删除确认",
                    content: "彻底删除一次只能确认一项，请关闭当前对话框后再试。",
                    isSuccess: false
                )
            }
            return .rejected(reason: .alreadyPresenting)
        }
        isPresenting = true
        os_unfair_lock_unlock(&unfairLock)

        // 2. modal 必须在主线程，IO 必须不在主线程。
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.presenter.present(targets: targets) { choice in
                // present 内部保证 completion 在主线程。
                self.handleChoice(choice, targets: targets)
            }
        }
        return .accepted
    }

    /// 弹窗结果回调：清理 in-flight 标志，并把 IO 派发到后台串行队列。
    private func handleChoice(_ choice: DestructiveChoice, targets: [URL]) {
        // 清标志要在 IO 派发之前，让"用户连点取消再点删除"的下一轮请求立刻可被接管。
        os_unfair_lock_lock(&unfairLock)
        isPresenting = false
        os_unfair_lock_unlock(&unfairLock)

        switch choice {
        case .cancel:
            AppLog.info("[Deletion] 用户取消彻底删除：\(targets.count) 项", category: .action)
            return
        case .recoverable:
            ioQueue.async { Self.performTrash(targets: targets) }
        case .destructive:
            ioQueue.async { Self.performPermanentDelete(targets: targets) }
        }
    }

    // MARK: - IO（在后台队列执行）

    private static func performTrash(targets: [URL]) {
        var successCount = 0
        for url in targets {
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
                successCount += 1
            } catch {
                AppLog.error(
                    "移到废纸篓失败: \(url.path) -> \(error.localizedDescription)",
                    category: .action
                )
            }
        }
        SharedHUDManager.show(
            title: successCount > 0 ? "已移到废纸篓" : "操作失败",
            content: successCount > 0
                ? "已处理 \(successCount) 项，可在废纸篓中恢复"
                : "请检查系统权限或文件是否被锁定",
            isSuccess: successCount > 0
        )
    }

    private static func performPermanentDelete(targets: [URL]) {
        var successCount = 0
        for url in targets {
            do {
                try FileManager.default.removeItem(at: url)
                successCount += 1
            } catch {
                AppLog.error(
                    "彻底删除失败: \(url.path) -> \(error.localizedDescription)",
                    category: .action
                )
            }
        }
        SharedHUDManager.show(
            title: successCount > 0 ? "已彻底删除" : "删除失败",
            content: successCount > 0
                ? "已彻底从磁盘抹除 \(successCount) 项，无法恢复"
                : "请检查系统权限或文件是否被锁定",
            isSuccess: successCount > 0
        )
    }

    // MARK: - Outcome

    public enum Outcome: Equatable {
        case accepted
        case rejected(reason: RejectionReason)
    }

    public enum RejectionReason: Equatable {
        case emptyTargets
        case alreadyPresenting
    }
}

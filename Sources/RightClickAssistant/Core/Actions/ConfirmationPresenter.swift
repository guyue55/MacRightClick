import Foundation
import AppKit

// MARK: - DestructiveChoice
/// 破坏性确认的三态结果。`fileprivate` 不再合适——
/// `DeletionRequestCoordinator` 与未来的单测都需要可见，所以提升为 public。
public enum DestructiveChoice {
    case cancel
    case recoverable
    case destructive
}

// MARK: - ConfirmationPresenter
/// 破坏性动作弹窗的展示协议。
///
/// 目的：让"如何呈现弹窗"与"何时弹、谁来管"解耦。
/// 生产环境用 `MainThreadAlertPresenter`，单测可以注入假的实现，
/// 既能覆盖 `DeletionRequestCoordinator` 的并发逻辑，又不必拉起 AppKit 主循环。
///
/// 约定：`present` 必须在主线程上调用，结果通过 `completion` 异步回调到主线程。
public protocol ConfirmationPresenter {
    /// 弹出破坏性确认对话框。
    /// - Parameters:
    ///   - targets: 受影响的文件/目录列表（仅用于摘要展示）。
    ///   - completion: 用户做出选择后回调，必定在主线程。
    @MainActor
    func present(targets: [URL], completion: @escaping (DestructiveChoice) -> Void)
}

// MARK: - MainThreadAlertPresenter
/// 生产环境实现：使用 `NSAlert` + `.critical` 样式，符合 HIG。
/// 与之前 `DestructiveActionConfirmer` 同构，区别仅在于：
/// - 不再用 `runModal()`，改用 `beginSheetModal` 或在主线程内同步 runModal 后立即回调，
///   由调用方决定何时把工作切回后台。
public final class MainThreadAlertPresenter: ConfirmationPresenter {
    public init() {}

    /// 仅构造 NSAlert，便于断言配置。
    public static func makeAlert(targets: [URL]) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "确认永久删除？"

        let names = targets.prefix(5).map { $0.lastPathComponent }
        var summary = names.joined(separator: "、")
        if targets.count > 5 {
            summary += " 等共 \(targets.count) 项"
        } else if names.isEmpty {
            summary = "（无目标）"
        }
        alert.informativeText = "将处理:\(summary)\n永久删除会绕过废纸篓且无法撤销，建议优先选择「移到废纸篓」。"

        // 第一个按钮承接 Return，让默认行为永远是「取消」。
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "永久删除")
        alert.buttons[2].keyEquivalent = ""
        return alert
    }

    @MainActor
    public func present(targets: [URL], completion: @escaping (DestructiveChoice) -> Void) {
        // 强约束：必须主线程调用。Coordinator 已保证；这里多一道断言防止误用。
        dispatchPrecondition(condition: .onQueue(.main))

        let alert = MainThreadAlertPresenter.makeAlert(targets: targets)
        alert.window.level = .modalPanel
        alert.window.orderFrontRegardless()

        // 仍用 runModal()：NSAlert 自身就在主线程 modal session 中运行，
        // 我们在 Coordinator 一侧保证：
        //   1. 同一时刻只有一个 in-flight 弹窗（不会再发生递归 modal）；
        //   2. 主线程不会被任何后台 main.sync 反向等待（删除 IO 全在后台 async）。
        let response = alert.runModal()
        let choice: DestructiveChoice
        switch response {
        case .alertFirstButtonReturn:  choice = .cancel
        case .alertSecondButtonReturn: choice = .recoverable
        case .alertThirdButtonReturn:  choice = .destructive
        default:                       choice = .cancel
        }
        // 回调统一异步派发，避免调用方在 modal 解套瞬间再次同步入栈。
        DispatchQueue.main.async { completion(choice) }
    }
}

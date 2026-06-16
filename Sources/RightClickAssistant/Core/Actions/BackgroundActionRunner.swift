import Foundation

// MARK: - BackgroundActionRunner
///
/// "无弹窗后台 IO + HUD 异步反馈" 型动作的最小骨架。
///
/// 设计动机（来自 P1-1 paste 复盘）：
/// - paste 没有自身弹窗，但跨盘大文件会让 `FileManager.moveItem` /
///   `crossVolumeMove` 在 folder-monitor 串行队列上同步阻塞，
///   期间任何同源事件（再次 paste / 彻底删除）都得排队，UI 卡顿。
/// - 这类动作不应该抢 `InteractiveActionGate` 全局闸门：
///   它没有 modal，本来就允许并行交互，跟 modal 互斥逻辑不在一个层面。
///
/// 与 `InteractiveActionRunner` 的关系（高内聚低耦合）：
/// - InteractiveActionRunner = 主线程 prompt + 后台 IO + 全局 modal 互斥；
/// - BackgroundActionRunner   = 仅后台 IO，私有串行队列，不抢闸门。
///
/// 不变量：
/// - 调用方任意线程（含 folder-monitor 串行队列）调用 `submit` 都不会阻塞；
/// - 同一 Runner 的多次提交在私有 IO 队列上 FIFO 串行执行；
/// - 不同 Runner 之间互不影响。
public final class BackgroundActionRunner {
    /// 标识本 Runner，仅用于日志归类。
    public let actionLabel: String

    /// 私有串行队列：同一类动作 FIFO，不同 Runner 互不阻塞。
    private let ioQueue: DispatchQueue

    public init(actionLabel: String, ioQueueLabel: String) {
        self.actionLabel = actionLabel
        self.ioQueue = DispatchQueue(label: ioQueueLabel, qos: .userInitiated)
    }

    /// 提交一次后台动作。立即返回，不阻塞调用者。
    /// - Parameter perform: 在私有串行队列上执行真正 IO；
    ///                     不应再回主线程做长任务。
    public func submit(_ perform: @escaping () -> Void) {
        ioQueue.async {
            perform()
        }
    }
}

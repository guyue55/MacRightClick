import Foundation
import AppKit
import os.lock

// MARK: - InteractiveActionRunner
///
/// "主线程交互 + 后台 IO + 全局互斥"的通用骨架。
///
/// 设计动机（来自 P0-1 moveTo/copyTo、P0-2 toggleHiddenFiles 复盘）：
/// - folder-monitor 串行队列若同步等主线程 modal（runModal / Process.waitUntilExit），
///   一旦 modal 期间再触发同源事件，就会形成 main.sync × 串行队列循环死锁。
/// - 旧实现散落在每个 Action 内部各写一套 runOnMainThread + NSAlert，
///   既难复测，也无法做"同时只允许 1 个交互对话"的全局裁决。
///
/// 设计目标（高内聚低耦合）：
/// - prompt 必定在主线程 async 跑（NSAlert / NSOpenPanel / Process control）；
/// - perform 必定在私有后台串行队列跑（IO、osascript、跨盘复制）；
/// - **全局** 同一时刻仅 1 个 prompt 在飞行（所有 Runner 共享同一锁），
///   第 2 个请求立刻 HUD 提示并丢弃，与 DeletionRequestCoordinator 行为一致。
///
/// 与 `DeletionRequestCoordinator` 的关系：
/// 后者是本骨架的早期特化版本，保留它以维持当前接口稳定；
/// 新增 Action（moveTo/copyTo/toggleHidden 等）一律走本类。
public final class InteractiveActionRunner {
    /// 标识本次交互所属的动作，用于 HUD 提示与日志归类。
    public let actionLabel: String

    /// 后台 IO 队列：每个 Runner 一条串行队列，
    /// 保证同一类动作的多次 perform 顺序执行；不同 Runner 之间互不阻塞。
    private let ioQueue: DispatchQueue

    /// 仅做 IO 路径标签；prompt 互斥由全局锁覆盖。
    public init(actionLabel: String, ioQueueLabel: String) {
        self.actionLabel = actionLabel
        self.ioQueue = DispatchQueue(label: ioQueueLabel, qos: .userInitiated)
    }

    /// 提交一次交互式动作。任何线程都可以调用，**不会阻塞调用者**。
    /// - Parameters:
    ///   - prompt: 主线程上构造并展示对话框（NSAlert/NSOpenPanel/确认链 ...）。
    ///            返回 `nil` 表示用户取消，整条流程结束。返回值会原样传给 perform。
    ///   - perform: 后台串行队列上执行真正 IO，不应再回主线程做长任务。
    /// - Returns: `.accepted` 表示已接管；`.rejected` 表示有别的交互在进行，请求被丢弃。
    @discardableResult
    public func run<Prompt>(
        prompt: @escaping () -> Prompt?,
        perform: @escaping (Prompt) -> Void
    ) -> Outcome {
        guard InteractiveActionGate.shared.tryAcquire(label: actionLabel) else {
            // 拒绝路径：HUD 必须切主线程。
            DispatchQueue.main.async {
                SharedHUDManager.show(
                    title: "请先处理上一个交互对话",
                    content: "一次只能进行 1 个右键交互对话框，请关闭当前对话后再试。",
                    isSuccess: false
                )
            }
            return .rejected(reason: .alreadyInteracting)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                InteractiveActionGate.shared.release()
                return
            }
            // prompt 完成 == modal 已关闭。这一刻立刻释放全局闸门，
            // 让后续右键动作可以马上进入新一轮交互，不用等 IO 跑完。
            let result: Prompt? = prompt()
            InteractiveActionGate.shared.release()

            guard let value = result else {
                AppLog.info("[Interactive] \(self.actionLabel) 用户取消", category: .action)
                return
            }
            self.ioQueue.async {
                perform(value)
            }
        }
        return .accepted
    }

    public enum Outcome: Equatable {
        case accepted
        case rejected(reason: RejectionReason)
    }

    public enum RejectionReason: Equatable {
        case alreadyInteracting
    }
}

// MARK: - InteractiveActionGate
/// 全局闸门：跨 Runner 共享，确保任何时刻只有 1 个交互对话。
/// 与 `DeletionRequestCoordinator` 的内部锁是并列关系，可以渐进迁移。
public final class InteractiveActionGate {
    public nonisolated(unsafe) static let shared = InteractiveActionGate()

    private var lock = os_unfair_lock()
    private var inflightLabel: String?

    public init() {}

    /// 尝试占用闸门；true 表示成功占用，false 表示已有别的交互在进行。
    public func tryAcquire(label: String) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard inflightLabel == nil else { return false }
        inflightLabel = label
        return true
    }

    /// 释放闸门。
    public func release() {
        os_unfair_lock_lock(&lock)
        inflightLabel = nil
        os_unfair_lock_unlock(&lock)
    }

    /// 仅用于测试：查询当前持有者。
    public var currentLabel: String? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return inflightLabel
    }
}

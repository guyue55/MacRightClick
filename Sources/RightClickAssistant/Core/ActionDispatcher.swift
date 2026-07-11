import Foundation

/// 动作派发器，用于解耦菜单显示和业务执行。
/// 所有的右键增强操作必须在此注册，由派发器统一分发。
public final class ActionDispatcher: @unchecked Sendable {
    public static let shared = ActionDispatcher()
    
    private let queue = DispatchQueue(label: "guyue.RightClickAssistant.dispatcher", qos: .userInitiated)
    private var registeredActions: [String: MenuAction] = [:]
    private let isActionEnabled: @Sendable (MenuAction) -> Bool
    
    public init(
        isActionEnabled: @escaping @Sendable (MenuAction) -> Bool = {
            SharedStorageManager.shared.isActionEnabled($0)
        }
    ) {
        self.isActionEnabled = isActionEnabled
    }
    
    /// 注册一个右键动作
    /// - Parameter action: 实现了 MenuAction 协议的动作实例
    public func register(action: MenuAction) {
        queue.sync {
            registeredActions[action.actionId] = action
        }
    }
    
    /// 获取所有注册的动作
    public var allActions: [MenuAction] {
        queue.sync {
            Array(registeredActions.values)
        }
    }
    
    /// 获取特定分类下的所有动作
    /// - Parameter category: 目标动作分类
    public func actions(in category: ActionCategory) -> [MenuAction] {
        queue.sync {
            registeredActions.values.filter { $0.category == category }
        }
    }
    
    /// 根据 Action ID 检索动作
    /// - Parameter actionId: 动作唯一 ID
    public func action(forId actionId: String) -> MenuAction? {
        queue.sync {
            registeredActions[actionId]
        }
    }
    
    /// 分发并执行特定动作
    /// - Parameters:
    ///   - actionId: 目标动作的唯一 ID
    ///   - targetURLs: 右键触发时选中的文件或目录 URL 列表
    /// - Returns: 动作执行是否成功
    public func dispatch(
        actionId: String,
        targetURLs: [URL],
        invocationKind: ActionInvocationKind = .items
    ) -> Bool {
        guard let prepared = prepare(
            actionId: actionId,
            targetURLs: targetURLs,
            invocationKind: invocationKind
        ) else { return false }

        print("[Dispatcher] 执行动作: \(prepared.action.localizedTitle) (ID: \(actionId)) 对目标: \(prepared.targetURLs.map { $0.lastPathComponent })")

        // 2. 物理防崩安全屏障：通过上方 targetURLs 精密健康度过滤完成大部分 IO 防护后，
        // 直接执行核心动作，并保持调度入口简单可预测。
        return prepared.action.execute(targetURLs: prepared.targetURLs)
    }

    /// 提交动作。completion 对成功、失败、取消和拒绝路径均最多触发一次。
    @discardableResult
    public func submit(
        actionId: String,
        targetURLs: [URL],
        invocationKind: ActionInvocationKind = .items,
        completion: @escaping @Sendable (ActionCompletionStatus) -> Void
    ) -> ActionSubmission {
        let completionOnce = ActionCompletionOnce(completion)
        guard let prepared = prepare(
            actionId: actionId,
            targetURLs: targetURLs,
            invocationKind: invocationKind
        ) else {
            completionOnce.call(.failed)
            return .rejected
        }

        let submission = prepared.action.submit(
            targetURLs: prepared.targetURLs,
            completion: { status in completionOnce.call(status) }
        )
        if submission == .rejected {
            completionOnce.call(.failed)
        }
        return submission
    }

    private func prepare(
        actionId: String,
        targetURLs: [URL],
        invocationKind: ActionInvocationKind
    ) -> (action: MenuAction, targetURLs: [URL])? {
        guard let action = action(forId: actionId) else {
            print("[Dispatcher] 错误: 动作 ID '\(actionId)' 未注册")
            return nil
        }

        guard isActionEnabled(action) else {
            print("[Dispatcher] 拒绝执行已禁用动作: \(actionId)")
            return nil
        }

        let healthyURLs = targetURLs.filter { url in
            FileManager.default.fileExists(atPath: url.path)
        }
        if action.requiresExistingTargets && healthyURLs.isEmpty {
            print("[Dispatcher] 错误: 动作需要的目标路径已不存在")
            SharedHUDManager.show(title: "操作无效", content: "目标项目在磁盘上已不存在", isSuccess: false)
            return nil
        }

        let finalURLs = action.requiresExistingTargets ? healthyURLs : targetURLs
        guard action.isAvailable(
            for: finalURLs,
            isContainer: invocationKind == .container
        ) else {
            print("[Dispatcher] 警告: 动作 '\(action.localizedTitle)' 不适用于当前右键上下文")
            return nil
        }
        return (action, finalURLs)
    }
}

private final class ActionCompletionOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (ActionCompletionStatus) -> Void)?

    init(_ completion: @escaping @Sendable (ActionCompletionStatus) -> Void) {
        self.completion = completion
    }

    func call(_ status: ActionCompletionStatus) {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(status)
    }
}

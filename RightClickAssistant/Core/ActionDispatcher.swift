import Foundation

/// 动作派发器，用于解耦菜单显示和业务执行。
/// 所有的右键增强操作必须在此注册，由派发器统一分发。
public final class ActionDispatcher {
    public static let shared = ActionDispatcher()
    
    private let queue = DispatchQueue(label: "org.antigravity.RightClickAssistant.dispatcher", qos: .userInitiated)
    private var registeredActions: [String: MenuAction] = [:]
    
    private init() {}
    
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
    public func dispatch(actionId: String, targetURLs: [URL]) -> Bool {
        guard let action = action(forId: actionId) else {
            print("[Dispatcher] 错误: 动作 ID '\(actionId)' 未注册")
            return false
        }
        
        guard action.isAvailable(for: targetURLs) else {
            print("[Dispatcher] 警告: 动作 '\(action.localizedTitle)' 对当前选中的资源不可用")
            return false
        }
        
        print("[Dispatcher] 执行动作: \(action.localizedTitle) (ID: \(actionId)) 对目标: \(targetURLs.map { $0.lastPathComponent })")
        
        // 核心动作通常涉及文件系统，在主线程外异步执行或同步保护
        return action.execute(targetURLs: targetURLs)
    }
}

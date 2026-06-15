import Foundation

/// 动作配置进程内缓存。
///
/// FinderSync 扩展的 `menu(for:)` 是右键菜单弹出主热路径，每次会针对 30+ 个 action
/// 调用 `isActionEnabled` 与 `isFavoriteAction`。原实现每次都走 UserDefaults + config.json
/// 双读，会让首次右键明显延迟。
///
/// 本缓存：
/// - 进程启动时 `preheat()` 把 favoriteActionIds 一次性读入；enable_action_* 按需懒加载
/// - 收到 `configChanged` 分布式通知或主 App 写配置后，调用 `invalidate()`
/// - 读路径全部 O(1) 内存查询
public final class ActionConfigCache {
    public static let shared = ActionConfigCache()

    private let queue = DispatchQueue(label: "guyue.ActionConfigCache", attributes: .concurrent)
    private var enableMap: [String: Bool] = [:]
    private var favoriteSet: Set<String> = []

    private init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("guyue.RightClickAssistant.configChanged"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.invalidate()
        }
    }

    /// 一次性预热：清空懒加载表，重读 favoriteActionIds。供进程启动时调用。
    public func preheat() {
        queue.async(flags: .barrier) {
            self.enableMap.removeAll(keepingCapacity: true)
            self.favoriteSet = Set(SharedStorageManager.shared.favoriteActionIds)
        }
    }

    /// 失效全部缓存。下一次读取时按需重新从 SharedStorageManager 拉。
    public func invalidate() {
        queue.async(flags: .barrier) {
            self.enableMap.removeAll(keepingCapacity: true)
            self.favoriteSet = Set(SharedStorageManager.shared.favoriteActionIds)
        }
    }

    /// 查询 action 启用状态。miss 时回源 SharedStorageManager 并填入缓存。
    public func isEnabled(_ actionId: String, default defaultValue: Bool) -> Bool {
        if let cached = queue.sync(execute: { enableMap[actionId] }) {
            return cached
        }
        let v = SharedStorageManager.shared.getBool(forKey: "enable_action_\(actionId)", defaultValue: defaultValue)
        queue.async(flags: .barrier) { self.enableMap[actionId] = v }
        return v
    }

    /// 查询 action 是否在收藏集中。
    public func isFavorite(_ actionId: String) -> Bool {
        return queue.sync { favoriteSet.contains(actionId) }
    }
}

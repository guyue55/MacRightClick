import Foundation
import AppKit

/// bundleId → 可执行 URL 的进程内缓存。
///
/// FinderSync 渲染右键菜单时，TerminalOpenAction.isAvailable / ContentView 的「未检测到应用」标签
/// 都会查询多个 bundleId。原实现每次都同步走 NSWorkspace.urlForApplication，是 Launch Services 系统调用。
///
/// 本注册表：
/// - 缓存 30 秒 TTL，单 bundle 命中即返回
/// - 监听 NSWorkspace.didLaunchApplication / didTerminateApplication 自动失效
/// - `overrideResolverForTesting` 用于单测桩
public final class InstalledAppRegistry {
    public nonisolated(unsafe) static let shared = InstalledAppRegistry()

    private struct Entry {
        let url: URL?
        let resolvedAt: Date
    }

    private let queue = DispatchQueue(label: "guyue.InstalledAppRegistry", attributes: .concurrent)
    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 30

    /// 单测桩：返回非 nil 时直接绕过 NSWorkspace。生产代码不应设置。
    public var overrideResolverForTesting: ((String) -> URL?)?

    private init() {
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               let bid = app.bundleIdentifier {
                self?.invalidate(bundleId: bid)
            }
        }
        center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               let bid = app.bundleIdentifier {
                self?.invalidate(bundleId: bid)
            }
        }
    }

    /// 取得安装路径。命中 TTL 内缓存直接返回；miss 时查询并写入缓存。
    public func url(for bundleId: String) -> URL? {
        // 1. 命中检查
        let hit: Entry? = queue.sync {
            guard let entry = cache[bundleId],
                  Date().timeIntervalSince(entry.resolvedAt) < ttl else {
                return nil
            }
            return entry
        }
        if let entry = hit {
            return entry.url
        }

        // 2. miss：查询并回填
        let resolver = overrideResolverForTesting ?? { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        }
        let resolved = resolver(bundleId)
        queue.async(flags: .barrier) {
            self.cache[bundleId] = Entry(url: resolved, resolvedAt: Date())
        }
        return resolved
    }

    public func isInstalled(_ bundleId: String) -> Bool {
        return url(for: bundleId) != nil
    }

    /// 一次性预热常用 bundleId 列表。无返回值，仅触发 cache 填充。
    public func preheat(_ bundleIds: [String]) {
        for id in bundleIds {
            _ = url(for: id)
        }
    }

    public func invalidate(bundleId: String) {
        queue.async(flags: .barrier) {
            self.cache.removeValue(forKey: bundleId)
        }
    }

    public func invalidateAll() {
        queue.async(flags: .barrier) {
            self.cache.removeAll(keepingCapacity: true)
        }
    }
}

# UX 强化与分发路线收敛 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 14 项二次审查缺陷按设计稿 docs/superpowers/specs/2026-06-15-ux-hardening-design.md 落地，使 MacRightClick 在 website-dev/release 路线上具备发版水准（安全、可读性能、单一引导路径、OSLog 化日志），并为 MAS 路线在代码层让路。

**Architecture:** 在共享层新增 4 个低耦合模块（AppLog / Distribution / InstalledAppRegistry / ActionConfigCache），把横切关注点从视图层与动作层归位；改造现有 Actions 与 Views 仅触达单一职责的 API；构建脚本按 DISTRIBUTION_ROUTE 分叉 entitlements 与编译优化。

**Tech Stack:** Swift 6, AppKit, SwiftUI, FinderSync, os.Logger (OSLog), XCTest, swiftc + lipo + codesign（脚本式构建）。

---

## 全局约束

- 保持中文 commit message，参考 baseline 风格
- 每个 Task 完成后跑 `bash Scripts/build.sh`，失败即 stop fix
- 测试文件统一加到 Tests/RightClickAssistantTests.swift；新模块若不能通过 SPM 测试驱动，至少给出独立可运行的 Process 桩
- 每个 Task 都自成一次 commit
- 涉及构建脚本与 entitlements 的 Task 必须验证 DMG/zip 产物字节级正常

## File Structure

新增：
- Sources/RightClickAssistant/Core/Logging/AppLog.swift               — os.Logger 包装
- Sources/RightClickAssistant/Core/Distribution.swift                 — 分发路线编译期常量
- Sources/RightClickAssistant/Core/InstalledAppRegistry.swift         — bundleId → URL? 进程内缓存
- Sources/RightClickAssistant/Core/ActionConfigCache.swift            — enable_action_* / favoriteActionIds 进程内缓存
- Resources/Templates/blank.docx                                      — 最小可双击 Word 骨架
- Resources/Templates/blank.xlsx                                      — 最小可双击 Excel 骨架
- Resources/Templates/blank.pptx                                      — 最小可双击 PowerPoint 骨架
- entitlements/website.host.entitlements                              — website-dev/release 主 App
- entitlements/mas.host.entitlements                                  — mac-app-store 主 App（暂不构建）
- entitlements/extension.entitlements                                 — 共用 Extension entitlements

修改：
- Sources/RightClickAssistant/Core/SharedStorageManager.swift          — 删 forceLocalSandboxExchange，引 Distribution / AppLog
- Sources/RightClickAssistant/Core/SharedHUDManager.swift              — 屏幕选择 + 点击/Esc 关闭
- Sources/RightClickAssistant/Core/Actions/FileManageAction.swift      — DestructiveActionConfirmer + 跨卷事务化
- Sources/RightClickAssistant/Core/Actions/UtilityAction.swift         — osascript 优雅退出 + QRCodePanelController
- Sources/RightClickAssistant/Core/Actions/NewFileAction.swift         — Office 模板从 Bundle 读
- Sources/RightClickAssistant/AppDelegate.swift                        — 状态栏移除高风险入口
- Sources/RightClickAssistantExtension/FinderSync.swift                — 主路径走 cache + AppLog
- Sources/RightClickAssistant/Views/ContentView.swift                  — Banner/Box 单一入口、恢复默认拆分、删死分支、Permissions 改事件驱动
- Scripts/build.sh                                                     — entitlements 分叉 + -O 优化 + Templates 拷贝
- Tests/RightClickAssistantTests.swift                                 — 新增/替换若干测试
- README.md / README_EN.md                                             — 日志诊断指引同步 OSLog

## Tasks


### Task 1: 新增 AppLog 模块（OSLog 包装）

**Files:**
- Create: Sources/RightClickAssistant/Core/Logging/AppLog.swift
- Test: Tests/RightClickAssistantTests.swift（追加 testAppLogCategoriesAreDistinct）

- [ ] 步骤 1：写一个失败测试（验证不同 category 的 logger 不共享）

```swift
func testAppLogCategoriesAreEmittedAndDistinct() {
    // os.Logger 是 struct，不能比指针；改为通过 OSLogStore 验证两条 category 都能落到统一日志。
    AppLog.info("ping-host", category: .host)
    AppLog.info("ping-extension", category: .`extension`)
    let store = try? OSLogStore(scope: .currentProcessIdentifier)
    let entries = (try? store?.getEntries(at: store?.position(timeIntervalSinceLatestBoot: 0))) ?? AnySequence([])
    let messages = entries.compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
    XCTAssertTrue(messages.contains("ping-host"))
    XCTAssertTrue(messages.contains("ping-extension"))
}
```

> 注：`os.Logger` 是值类型，不能用 `ObjectIdentifier` 比指针，故改为通过 `OSLogStore` 验证两条 category 都能落到日志。

- [ ] 步骤 2：跑测试确认失败

Run: `swift test --filter testAppLogCategoriesAreDistinct`
Expected: 编译失败，AppLog 未定义。

- [ ] 步骤 3：实现 AppLog.swift

```swift
import Foundation
import os

public enum AppLogCategory: String {
    case host
    case `extension`
    case storage
    case action
    case ui
}

public enum AppLog {
    public static let subsystem = "guyue.RightClickAssistant"

    private static var loggers: [String: Logger] = [:]
    private static let queue = DispatchQueue(label: "guyue.AppLog.registry")

    public static func logger(for category: AppLogCategory) -> Logger {
        return queue.sync {
            if let existing = loggers[category.rawValue] { return existing }
            let l = Logger(subsystem: subsystem, category: category.rawValue)
            loggers[category.rawValue] = l
            return l
        }
    }

    public static func info(_ message: String, category: AppLogCategory = .host) {
        logger(for: category).info("\(message, privacy: .public)")
    }

    public static func debug(_ message: String, category: AppLogCategory = .host) {
        logger(for: category).debug("\(message, privacy: .public)")
    }

    public static func error(_ message: String, category: AppLogCategory = .host) {
        logger(for: category).error("\(message, privacy: .public)")
    }
}
```

- [ ] 步骤 4：将 AppLog.swift 加入 Scripts/build.sh 的 HOST_SOURCES 与 EXT_SOURCES 列表

```bash
# Scripts/build.sh，HOST_SOURCES 中追加：
#     Sources/RightClickAssistant/Core/Logging/AppLog.swift \
# 同步加到 EXT_SOURCES
```

- [ ] 步骤 5：跑测试确认通过

Run: `bash Scripts/build.sh` 看到 🎉 即通过；XCTest 视项目 Package.swift 现状决定，若没有 SPM target 则改成 swiftc -parse 单文件确认无语法错。

- [ ] 步骤 6：commit

```bash
git add Sources/RightClickAssistant/Core/Logging/AppLog.swift Tests/RightClickAssistantTests.swift Scripts/build.sh
git commit -m "feat(logging): 新增 AppLog 模块，统一 os.Logger 入口"
```


### Task 2: Distribution 模块 + 删除 forceLocalSandboxExchange

**Files:**
- Create: Sources/RightClickAssistant/Core/Distribution.swift
- Modify: Sources/RightClickAssistant/Core/SharedStorageManager.swift（删 forceLocalSandboxExchange，引 Distribution）
- Test: Tests/RightClickAssistantTests.swift（追加 testDistributionRouteConstantsAreConsistent）

- [ ] 步骤 1：写测试断言常量在 MAS / WEBSITE 路线下互斥

```swift
func testDistributionRouteConstantsAreConsistent() {
    if Distribution.usesAppGroup {
        XCTAssertFalse(Distribution.allowsCrossContainerExchange,
                       "MAS 路线必须只走 App Group，不能再读 Extension Container")
    } else {
        XCTAssertTrue(Distribution.allowsCrossContainerExchange,
                      "website 路线必须允许主 App 读 Extension Container")
    }
}
```

- [ ] 步骤 2：跑测试确认失败（Distribution 未定义）

- [ ] 步骤 3：实现 Distribution.swift

```swift
import Foundation

public enum DistributionRoute: String {
    case websiteDev
    case websiteRelease
    case macAppStore
}

public enum Distribution {
    public static var route: DistributionRoute {
        #if MAC_APP_STORE
        return .macAppStore
        #elseif WEBSITE_RELEASE
        return .websiteRelease
        #else
        return .websiteDev
        #endif
    }

    public static var usesAppGroup: Bool {
        #if MAC_APP_STORE
        return true
        #else
        return false
        #endif
    }

    public static var allowsCrossContainerExchange: Bool {
        #if MAC_APP_STORE
        return false
        #else
        return true
        #endif
    }
}
```

- [ ] 步骤 4：改 SharedStorageManager.sharedContainerURL

```swift
// 删除：
// private let forceLocalSandboxExchange = true
//
// 旧 if !forceLocalSandboxExchange { ... } 改为：
public var sharedContainerURL: URL {
    if Distribution.usesAppGroup,
       let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
        let testDir = appGroupURL.appendingPathComponent(".test_write")
        do {
            try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.removeItem(at: testDir)
            return appGroupURL
        } catch {
            AppLog.error("App Group containerURL 不可写，fail-fast 阻断", category: .storage)
            // 在 MAS 路线下不应出现，触发即说明 entitlements 配置有问题
        }
    }

    guard Distribution.allowsCrossContainerExchange else {
        AppLog.error("当前分发路线既不允许 App Group 也不允许跨 Container 交换", category: .storage)
        // 兜底返回主 App 自身 Container（不会跨进程互通，但避免崩溃）
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    let path: String
    if isRunningInExtension {
        path = NSHomeDirectory()
    } else {
        let realHome = getRealHomeDirectory()
        path = (realHome as NSString).appendingPathComponent("Library/Containers/\(extensionBundleIdentifier)/Data")
    }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    return url
}
```

- [ ] 步骤 5：build.sh 在 swiftc 调用末尾按 DISTRIBUTION_ROUTE 注入 -D 宏

```bash
# Scripts/build.sh，COMMON_FLAGS 之后追加：
case "$DISTRIBUTION_ROUTE" in
    website-dev)     ROUTE_DEFINES="-D WEBSITE_DEV" ;;
    website-release) ROUTE_DEFINES="-D WEBSITE_RELEASE" ;;
    mac-app-store)   ROUTE_DEFINES="-D MAC_APP_STORE" ;;
esac
COMMON_FLAGS="$COMMON_FLAGS $ROUTE_DEFINES"
```

并把 Distribution.swift 加到 HOST_SOURCES 与 EXT_SOURCES。

- [ ] 步骤 6：bash Scripts/build.sh 确认产物正常，commit

```bash
git add Sources/RightClickAssistant/Core/Distribution.swift Sources/RightClickAssistant/Core/SharedStorageManager.swift Scripts/build.sh Tests/RightClickAssistantTests.swift
git commit -m "feat(distribution): 引入分发路线编译期常量并下沉跨 Container 交换决策"
```


### Task 3: ActionConfigCache（进程内启用/收藏缓存）

**Files:**
- Create: Sources/RightClickAssistant/Core/ActionConfigCache.swift
- Test: Tests/RightClickAssistantTests.swift（追加 testActionConfigCacheInvalidation）

- [ ] 步骤 1：测试

```swift
func testActionConfigCacheInvalidation() {
    let storage = SharedStorageManager.shared
    let cache = ActionConfigCache.shared
    let actionId = "guyue.action.test.cache"

    storage.setBool(false, forKey: "enable_action_\(actionId)")
    cache.preheat()
    XCTAssertEqual(cache.isEnabled(actionId, default: true), false)

    storage.setBool(true, forKey: "enable_action_\(actionId)")
    cache.invalidate()
    XCTAssertEqual(cache.isEnabled(actionId, default: false), true)

    storage.removeValue(forKey: "enable_action_\(actionId)")
}
```

- [ ] 步骤 2：跑测试确认失败

- [ ] 步骤 3：实现 ActionConfigCache.swift

```swift
import Foundation

public final class ActionConfigCache {
    public static let shared = ActionConfigCache()

    private let queue = DispatchQueue(label: "guyue.ActionConfigCache", attributes: .concurrent)
    private var enableMap: [String: Bool] = [:]
    private var favoriteSet: Set<String> = []
    private var preheated = false

    private init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("guyue.RightClickAssistant.configChanged"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.invalidate()
        }
    }

    public func preheat() {
        queue.async(flags: .barrier) {
            self.enableMap.removeAll(keepingCapacity: true)
            self.favoriteSet = Set(SharedStorageManager.shared.favoriteActionIds)
            self.preheated = true
        }
    }

    public func invalidate() {
        queue.async(flags: .barrier) {
            self.enableMap.removeAll(keepingCapacity: true)
            self.favoriteSet = Set(SharedStorageManager.shared.favoriteActionIds)
        }
    }

    public func isEnabled(_ actionId: String, default defaultValue: Bool) -> Bool {
        return queue.sync {
            if let cached = enableMap[actionId] { return cached }
            let v = SharedStorageManager.shared.getBool(forKey: "enable_action_\(actionId)", defaultValue: defaultValue)
            queue.async(flags: .barrier) { self.enableMap[actionId] = v }
            return v
        }
    }

    public func isFavorite(_ actionId: String) -> Bool {
        return queue.sync { favoriteSet.contains(actionId) }
    }
}
```

- [ ] 步骤 4：build.sh 把 ActionConfigCache.swift 加入 HOST_SOURCES 与 EXT_SOURCES

- [ ] 步骤 5：跑测试 + bash Scripts/build.sh

- [ ] 步骤 6：commit

```bash
git add Sources/RightClickAssistant/Core/ActionConfigCache.swift Scripts/build.sh Tests/RightClickAssistantTests.swift
git commit -m "feat(cache): 新增 ActionConfigCache，菜单渲染主路径走进程内缓存"
```


### Task 4: InstalledAppRegistry（应用安装状态缓存）

**Files:**
- Create: Sources/RightClickAssistant/Core/InstalledAppRegistry.swift
- Modify: Sources/RightClickAssistant/Core/Actions/TerminalOpenAction.swift（isAvailable 改走 registry）
- Modify: Sources/RightClickAssistant/Views/ContentView.swift（ActionRowView "未检测到应用" 标签改走 registry）
- Test: Tests/RightClickAssistantTests.swift（追加 testInstalledAppRegistryTTL）

- [ ] 步骤 1：测试

```swift
func testInstalledAppRegistryTTL() {
    let registry = InstalledAppRegistry.shared
    var queryCount = 0
    registry.overrideResolverForTesting = { bundleId in
        queryCount += 1
        return URL(fileURLWithPath: "/Applications/Mock-\(bundleId).app")
    }
    _ = registry.url(for: "com.example.mock")
    _ = registry.url(for: "com.example.mock")
    _ = registry.url(for: "com.example.mock")
    XCTAssertEqual(queryCount, 1, "TTL 内应只查询一次")
    registry.overrideResolverForTesting = nil
}
```

- [ ] 步骤 2：跑测试确认失败

- [ ] 步骤 3：实现 InstalledAppRegistry.swift

```swift
import Foundation
import AppKit

public final class InstalledAppRegistry {
    public static let shared = InstalledAppRegistry()

    private struct Entry {
        let url: URL?
        let resolvedAt: Date
    }

    private let queue = DispatchQueue(label: "guyue.InstalledAppRegistry", attributes: .concurrent)
    private var cache: [String: Entry] = [:]
    private let ttl: TimeInterval = 30
    public var overrideResolverForTesting: ((String) -> URL?)?

    private init() {
        let workspace = NSWorkspace.shared
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: workspace,
            queue: nil
        ) { [weak self] note in
            if let bid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier {
                self?.invalidate(bundleId: bid)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: workspace,
            queue: nil
        ) { [weak self] note in
            if let bid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier {
                self?.invalidate(bundleId: bid)
            }
        }
    }

    public func url(for bundleId: String) -> URL? {
        queue.sync {
            if let entry = cache[bundleId], Date().timeIntervalSince(entry.resolvedAt) < ttl {
                return entry.url
            }
            let resolver = overrideResolverForTesting ?? { id in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            }
            let resolved = resolver(bundleId)
            queue.async(flags: .barrier) {
                self.cache[bundleId] = Entry(url: resolved, resolvedAt: Date())
            }
            return resolved
        }
    }

    public func isInstalled(_ bundleId: String) -> Bool {
        return url(for: bundleId) != nil
    }

    public func preheat(_ bundleIds: [String]) {
        for id in bundleIds { _ = url(for: id) }
    }

    public func invalidate(bundleId: String) {
        queue.async(flags: .barrier) { self.cache.removeValue(forKey: bundleId) }
    }
}
```

- [ ] 步骤 4：改 TerminalOpenAction.isAvailable 与 execute 用 registry

```swift
public func isAvailable(for targetURLs: [URL]) -> Bool {
    guard InstalledAppRegistry.shared.isInstalled(appType.bundleIdentifier) else {
        return false
    }
    return !targetURLs.isEmpty
}

// execute 中：
guard let appURL = InstalledAppRegistry.shared.url(for: appType.bundleIdentifier) else {
    AppLog.error("找不到应用: \(appType.displayName)", category: .action)
    return false
}
```

- [ ] 步骤 5：改 ContentView.swift 中 ActionRowView 「未检测到应用」标签

把：

```swift
if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) == nil { ... }
```

改为：

```swift
if !InstalledAppRegistry.shared.isInstalled(bundleId) { ... }
```

- [ ] 步骤 6：build.sh 加入 InstalledAppRegistry.swift；跑测试与编译

- [ ] 步骤 7：commit

```bash
git add Sources/RightClickAssistant/Core/InstalledAppRegistry.swift Sources/RightClickAssistant/Core/Actions/TerminalOpenAction.swift Sources/RightClickAssistant/Views/ContentView.swift Scripts/build.sh Tests/RightClickAssistantTests.swift
git commit -m "feat(cache): 新增 InstalledAppRegistry，避免菜单渲染时同步查询 Launch Services"
```


### Task 5: 永久删除 HIG 化（DestructiveActionConfirmer）

**Files:**
- Modify: Sources/RightClickAssistant/Core/Actions/FileManageAction.swift
- Test: Tests/RightClickAssistantTests.swift（追加 testDestructiveDeleteAlertConfiguration、testTrashFallback）

- [ ] 步骤 1：测试 alert 配置

```swift
func testDestructiveDeleteAlertConfiguration() {
    let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
    let alert = DestructiveActionConfirmer.makeAlert(for: .permanentDelete, targets: urls)
    XCTAssertEqual(alert.alertStyle, .critical)
    XCTAssertEqual(alert.buttons.count, 3)
    XCTAssertEqual(alert.buttons[0].title, "取消")
    XCTAssertEqual(alert.buttons[1].title, "移到废纸篓")
    XCTAssertEqual(alert.buttons[2].title, "永久删除")
    // NSAlert 默认 keyEquivalent 是 \r 表示 Return 命中。
    XCTAssertEqual(alert.buttons[0].keyEquivalent, "\r")
    XCTAssertNotEqual(alert.buttons[2].keyEquivalent, "\r")
}
```

- [ ] 步骤 2：测试 trash 兜底

```swift
func testTrashFallback() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("trash-test-\(UUID().uuidString).txt")
    try Data("hello".utf8).write(to: tmp)
    XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))

    var resulting: NSURL?
    try (FileManager.default as NSFileManager).trashItem(at: tmp, resultingItemURL: &resulting)
    XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
}
```

- [ ] 步骤 3：跑测试确认失败（DestructiveActionConfirmer 未定义）

- [ ] 步骤 4：在 FileManageAction.swift 内 fileprivate 实现 DestructiveActionConfirmer

```swift
fileprivate enum DestructiveChoice {
    case cancel
    case recoverable
    case destructive
}

fileprivate enum DestructiveActionConfirmer {
    static func makeAlert(for type: FileManageType, targets: [URL]) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "确认永久删除？"

        let names = targets.prefix(5).map { $0.lastPathComponent }
        var summary = names.joined(separator: "、")
        if targets.count > 5 {
            summary += " 等共 \(targets.count) 项"
        }
        alert.informativeText = "将处理：\(summary)\n永久删除会绕过废纸篓且无法撤销。"

        // 第一个按钮在 NSAlert 中默认就是 default（keyEquivalent = "\r"）。
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "永久删除")
        // 让「永久删除」不要被 Return 误命中：清空它的 keyEquivalent。
        alert.buttons[2].keyEquivalent = ""
        return alert
    }

    static func confirm(for type: FileManageType, targets: [URL]) -> DestructiveChoice {
        let alert = makeAlert(for: type, targets: targets)
        alert.window.level = .modalPanel
        alert.window.orderFrontRegardless()
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .cancel
        case .alertSecondButtonReturn: return .recoverable
        case .alertThirdButtonReturn:  return .destructive
        default: return .cancel
        }
    }
}
```

- [ ] 步骤 5：替换 FileManageAction permanentDelete 分支

```swift
case .permanentDelete:
    let choice = runOnMainThread { DestructiveActionConfirmer.confirm(for: .permanentDelete, targets: targetURLs) }
    switch choice {
    case .cancel:
        return false
    case .recoverable:
        var success = 0
        for fileURL in targetURLs {
            do {
                var resulting: NSURL?
                try (FileManager.default as NSFileManager).trashItem(at: fileURL, resultingItemURL: &resulting)
                success += 1
            } catch {
                AppLog.error("移到废纸篓失败: \(fileURL.path) -> \(error.localizedDescription)", category: .action)
            }
        }
        SharedHUDManager.show(title: success > 0 ? "已移到废纸篓" : "操作失败",
                              content: "已处理 \(success) 项",
                              isSuccess: success > 0)
        return success > 0
    case .destructive:
        var success = 0
        for fileURL in targetURLs {
            do {
                try FileManager.default.removeItem(at: fileURL)
                success += 1
            } catch {
                AppLog.error("彻底删除失败: \(fileURL.path) -> \(error.localizedDescription)", category: .action)
            }
        }
        SharedHUDManager.show(title: success > 0 ? "已彻底删除" : "删除失败",
                              content: "已处理 \(success) 项",
                              isSuccess: success > 0)
        return success > 0
    }
```

- [ ] 步骤 6：跑测试 + bash Scripts/build.sh

- [ ] 步骤 7：commit

```bash
git add Sources/RightClickAssistant/Core/Actions/FileManageAction.swift Tests/RightClickAssistantTests.swift
git commit -m "feat(filemanage): 永久删除走 HIG critical 样式三按钮，新增移到废纸篓中间档"
```


### Task 6: 跨卷 Copy-Then-Delete 事务化

**Files:**
- Modify: Sources/RightClickAssistant/Core/Actions/FileManageAction.swift（paste 与 moveTo 分支）
- Test: Tests/RightClickAssistantTests.swift（追加 testCrossVolumeMoveCleanupOnFailure）

- [ ] 步骤 1：测试

```swift
func testCrossVolumeMoveCleanupOnFailure() throws {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("xv-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

    let src = tmpDir.appendingPathComponent("src.txt")
    let dest = tmpDir.appendingPathComponent("dest.txt")
    try Data("hello".utf8).write(to: src)

    let result = FileManageAction.crossVolumeMoveForTesting(
        from: src,
        to: dest,
        copy: { from, to in try FileManager.default.copyItem(at: from, to: to) },
        sanityCheck: { _ in throw NSError(domain: "test", code: 1) }
    )

    XCTAssertFalse(result, "sanityCheck 抛错时应当 cleanup")
    XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path), "失败后 dest 残留必须被清理")
    XCTAssertTrue(FileManager.default.fileExists(atPath: src.path), "src 不应被删")

    try FileManager.default.removeItem(at: tmpDir)
}
```

- [ ] 步骤 2：跑测试确认失败

- [ ] 步骤 3：在 FileManageAction 中抽出 crossVolumeMove

```swift
public extension FileManageAction {
    /// 注：仅用于单测注入桩。生产路径走 fileprivate 版本。
    static func crossVolumeMoveForTesting(
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
            try? FileManager.default.removeItem(at: dest)
            return false
        }
    }
}

fileprivate func crossVolumeMove(from src: URL, to dest: URL) -> Bool {
    do {
        try FileManager.default.copyItem(at: src, to: dest)
        try defaultSanityCheck(dest)
        try FileManager.default.removeItem(at: src)
        return true
    } catch {
        try? FileManager.default.removeItem(at: dest)
        AppLog.error("跨卷移动失败已 cleanup: \(src.path) -> \(error.localizedDescription)", category: .action)
        return false
    }
}

fileprivate func defaultSanityCheck(_ dest: URL) throws {
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
```

- [ ] 步骤 4：替换 paste 与 moveTo 分支中老的 do/catch（直接调 crossVolumeMove）

```swift
// paste / moveTo 分支中 catch 跨卷的部分：
do {
    try FileManager.default.moveItem(at: fileURL, to: finalDestURL)
    successCount += 1
} catch {
    if crossVolumeMove(from: fileURL, to: finalDestURL) {
        successCount += 1
    }
}
```

- [ ] 步骤 5：跑测试 + bash Scripts/build.sh

- [ ] 步骤 6：commit

```bash
git add Sources/RightClickAssistant/Core/Actions/FileManageAction.swift Tests/RightClickAssistantTests.swift
git commit -m "feat(filemanage): 跨卷 Copy-Then-Delete 事务化，失败时 cleanup 残留"
```


### Task 7: Office 三件套最小骨架 + 改 NewFileAction 从 Bundle 读取

**Files:**
- Create: Resources/Templates/blank.docx
- Create: Resources/Templates/blank.xlsx
- Create: Resources/Templates/blank.pptx
- Modify: Sources/RightClickAssistant/Core/Actions/NewFileAction.swift（defaultEmptyBytes 改读 Bundle Templates 目录）
- Modify: Scripts/build.sh（拷贝 Resources/Templates 到 .app/Contents/Resources/Templates）
- Test: Tests/RightClickAssistantTests.swift（替换 testOfficeFileTemplateBytes 为 testOfficeTemplatesAreOpenable，新增 testPDFTemplateIsParseable）

- [ ] 步骤 1：用 python3 zipfile 一次性生成最小可双击的 Office 骨架（生成脚本，跑一次后产物 commit）

```bash
mkdir -p Resources/Templates
python3 - <<'PY'
import zipfile, os

CT = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
{overrides}
</Types>"""

RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="{target}"/>
</Relationships>"""

DOCX_DOC = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body><w:p/></w:body>
</w:document>"""

XLSX_WB = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
</workbook>"""

XLSX_WB_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>"""

XLSX_SHEET = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>"""

PPTX_PRES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>
</p:presentation>"""

PPTX_PRES_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/>
</Relationships>"""

PPTX_SLIDE = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:cSld><p:spTree/></p:cSld>
</p:sld>"""

def make_zip(path, files):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            z.writestr(name, data)

# .docx
make_zip("Resources/Templates/blank.docx", {
    "[Content_Types].xml": CT.format(overrides=
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'),
    "_rels/.rels": RELS.format(target="word/document.xml"),
    "word/document.xml": DOCX_DOC,
})

# .xlsx
make_zip("Resources/Templates/blank.xlsx", {
    "[Content_Types].xml": CT.format(overrides=
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'),
    "_rels/.rels": RELS.format(target="xl/workbook.xml"),
    "xl/workbook.xml": XLSX_WB,
    "xl/_rels/workbook.xml.rels": XLSX_WB_RELS,
    "xl/worksheets/sheet1.xml": XLSX_SHEET,
})

# .pptx
make_zip("Resources/Templates/blank.pptx", {
    "[Content_Types].xml": CT.format(overrides=
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'),
    "_rels/.rels": RELS.format(target="ppt/presentation.xml"),
    "ppt/presentation.xml": PPTX_PRES,
    "ppt/_rels/presentation.xml.rels": PPTX_PRES_RELS,
    "ppt/slides/slide1.xml": PPTX_SLIDE,
})

print("OK")
PY
ls -la Resources/Templates
```

- [ ] 步骤 2：测试

```swift
func testOfficeTemplatesAreOpenable() throws {
    for ext in ["docx", "xlsx", "pptx"] {
        let url = Bundle(for: type(of: self)).url(forResource: "blank", withExtension: ext, subdirectory: "Templates")
            ?? URL(fileURLWithPath: "Resources/Templates/blank.\(ext)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "缺少 blank.\(ext) 模板")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]), "ZIP 魔数")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-l", url.path]
        let pipe = Pipe(); proc.standardOutput = pipe
        try proc.run(); proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(out.contains("[Content_Types].xml"), "blank.\(ext) 必须含 [Content_Types].xml")
    }
}

func testPDFTemplateIsParseable() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("blank-\(UUID().uuidString).pdf")
    try Data(NewFileAction(fileType: .pdf).defaultEmptyBytesForTesting).write(to: tmp)
    let doc = PDFDocument(url: tmp)
    XCTAssertNotNil(doc)
    XCTAssertEqual(doc?.pageCount, 1)
    try? FileManager.default.removeItem(at: tmp)
}
```

- [ ] 步骤 3：跑测试确认失败

- [ ] 步骤 4：改 NewFileAction.defaultEmptyBytes 与 execute

```swift
public var defaultEmptyBytes: Data {
    switch self {
    case .docx, .xlsx, .pptx:
        if let url = Bundle.main.url(forResource: "blank", withExtension: rawValue, subdirectory: "Templates"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        AppLog.error("缺少 Templates/blank.\(rawValue)，回退空 ZIP", category: .action)
        return Data(base64Encoded: "UEsFBgAAAAAAAAAAAAAAAAAAAAAAAA==") ?? Data()
    case .pdf:
        return Self.minimalPDFBytes
    case .html:
        return Self.minimalHTMLBytes
    default:
        return Data()
    }
}

extension NewFileAction {
    var defaultEmptyBytesForTesting: Data { fileType.defaultEmptyBytes }
}
```

把现在的 PDF / HTML 内联 String 改抽到 SupportedFileType 的 static 上，改个名字而已。

- [ ] 步骤 5：build.sh 增加 Templates 拷贝

```bash
# 在「转换并打包 AppIcon」附近加：
if [ -d "Resources/Templates" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Resources/Templates"
    cp -R Resources/Templates/* "$APP_BUNDLE/Contents/Resources/Templates/"
    echo "📄 [Build] 已拷贝 Office 模板到 .app/Contents/Resources/Templates/"
fi
```

- [ ] 步骤 6：跑测试 + bash Scripts/build.sh + 双击产物里 .docx/.xlsx/.pptx 确认能开

- [ ] 步骤 7：commit

```bash
git add Resources/Templates Sources/RightClickAssistant/Core/Actions/NewFileAction.swift Scripts/build.sh Tests/RightClickAssistantTests.swift
git commit -m "feat(newfile): Office 三件套改读 Bundle Templates 最小骨架，可双击直开"
```


### Task 8: 状态栏托盘移除「切换隐藏文件」+ killall→AppleScript

**Files:**
- Modify: Sources/RightClickAssistant/AppDelegate.swift（rebuildStatusMenu 移除 toggleHiddenFiles 项与 toggleHiddenFilesFromMenu）
- Modify: Sources/RightClickAssistant/Core/Actions/UtilityAction.swift（toggleHiddenSystemFiles 用 osascript quit）
- Test: Tests/RightClickAssistantTests.swift（更新 testHighRiskStatusMenuActionRequiresExplicitEnablement）

- [ ] 步骤 1：测试托盘菜单不再含切换隐藏文件项

```swift
func testStatusMenuHasNoToggleHiddenFiles() {
    let menu = NSMenu()
    AppDelegate.rebuildStatusMenuForTesting(menu)
    let titles = menu.items.map { $0.title }
    XCTAssertFalse(titles.contains("切换 Finder 隐藏文件"))
    XCTAssertTrue(titles.contains("显示右键助手设置"))
    XCTAssertTrue(titles.contains("退出"))
}
```

- [ ] 步骤 2：跑测试确认失败

- [ ] 步骤 3：改 AppDelegate

```swift
private func rebuildStatusMenu(_ menu: NSMenu) {
    menu.removeAllItems()

    let settingsItem = NSMenuItem(title: "显示右键助手设置", action: #selector(showSettingsWindow), keyEquivalent: "s")
    settingsItem.target = self
    menu.addItem(settingsItem)

    menu.addItem(NSMenuItem.separator())

    let aboutItem = NSMenuItem(title: "关于右键助手", action: #selector(showAboutDialog), keyEquivalent: "")
    aboutItem.target = self
    menu.addItem(aboutItem)

    let quitItem = NSMenuItem(title: "退出", action: #selector(terminateApp), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)
}

// 删除 toggleHiddenFilesFromMenu

// 增加测试入口：
static func rebuildStatusMenuForTesting(_ menu: NSMenu) {
    let delegate = AppDelegate()
    delegate.rebuildStatusMenu(menu)
}
```

- [ ] 步骤 4：改 UtilityAction.toggleHiddenSystemFiles 中 killall 替换

```swift
// 旧：
// let killProcess = Process()
// killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
// killProcess.arguments = ["Finder"]
// try killProcess.run(); killProcess.waitUntilExit()

// 新：
let osa = Process()
osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
osa.arguments = ["-e", "tell application \"Finder\" to quit"]
try osa.run()
osa.waitUntilExit()
// 等 Finder 退出后系统会自动重启它；保险起见显式拉起：
Thread.sleep(forTimeInterval: 0.5)
let relaunch = Process()
relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
relaunch.arguments = ["-a", "Finder"]
try relaunch.run()
```

- [ ] 步骤 5：跑测试 + bash Scripts/build.sh

- [ ] 步骤 6：commit

```bash
git add Sources/RightClickAssistant/AppDelegate.swift Sources/RightClickAssistant/Core/Actions/UtilityAction.swift Tests/RightClickAssistantTests.swift
git commit -m "feat(safety): 状态栏托盘移除切换隐藏文件入口，killall Finder 改 AppleScript 优雅退出"
```


### Task 9: HUD 跟随鼠标屏幕 + 点击/Esc 关闭

**Files:**
- Modify: Sources/RightClickAssistant/Core/SharedHUDManager.swift
- Test: Tests/RightClickAssistantTests.swift（追加 testSharedHUDPicksMouseScreen）

- [ ] 步骤 1：测试

```swift
func testSharedHUDPicksMouseScreen() {
    let primary = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    let secondary = NSRect(x: 1920, y: 0, width: 1280, height: 800)
    let chosen = SharedHUDManager.screenFrame(
        screens: [primary, secondary],
        mouseLocation: NSPoint(x: 2300, y: 200),
        fallback: primary
    )
    XCTAssertEqual(chosen, secondary)
}
```

- [ ] 步骤 2：跑测试确认失败

- [ ] 步骤 3：实现纯函数版 screenFrame，再让 show 内部调用

```swift
extension SharedHUDManager {
    public static func screenFrame(
        screens: [NSRect],
        mouseLocation: NSPoint,
        fallback: NSRect
    ) -> NSRect {
        return screens.first { $0.contains(mouseLocation) } ?? fallback
    }
}
```

- [ ] 步骤 4：改 show 中 screenRect 的获取

```swift
let primary = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
let allFrames = NSScreen.screens.map { $0.visibleFrame }
let screenRect = SharedHUDManager.screenFrame(
    screens: allFrames,
    mouseLocation: NSEvent.mouseLocation,
    fallback: primary
)
```

- [ ] 步骤 5：加点击与 Esc 关闭

```swift
// 在 panel.contentView 设置完毕后追加：
let click = NSClickGestureRecognizer(target: panel, action: #selector(NSWindow.close))
visualEffectView.addGestureRecognizer(click)

var keyMonitor: Any?
keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
    if event.keyCode == 53 { // Esc
        panel.close()
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        return nil
    }
    return event
}

// 在 panel 自动淡出回调中也移除 monitor，避免泄漏：
// 在 close 前：if let m = keyMonitor { NSEvent.removeMonitor(m) }
```

- [ ] 步骤 6：跑测试 + bash Scripts/build.sh + 手动双屏验证

- [ ] 步骤 7：commit

```bash
git add Sources/RightClickAssistant/Core/SharedHUDManager.swift Tests/RightClickAssistantTests.swift
git commit -m "feat(hud): HUD 跟随鼠标所在屏幕，支持点击/Esc 立即关闭"
```


### Task 10: FinderSync 主路径走缓存 + AppLog

**Files:**
- Modify: Sources/RightClickAssistantExtension/FinderSync.swift（menu(for:) 主路径换缓存；logToSharedContainer 转 AppLog）
- Modify: Sources/RightClickAssistant/Core/SharedStorageManager.swift（writeLog 改 AppLog；保留 logFileURL 仅作只读导出）
- Modify: Sources/RightClickAssistant/Views/ContentView.swift（DiagnosticsSettingsView 加「导出旧日志」按钮）
- Test: Tests/RightClickAssistantTests.swift（追加 testFinderSyncUsesCacheNoSyncIO，stub 验证 SharedStorageManager.getBool 在 menu(for:) 主路径未被同步调用）

- [ ] 步骤 1：测试 (设计为接口级)

```swift
func testFinderSyncUsesCacheNoSyncIO() {
    let cache = ActionConfigCache.shared
    cache.preheat()
    SharedStorageManager.shared.setBool(true, forKey: "enable_action_guyue.action.newfile.txt")
    cache.invalidate()

    var ioHits = 0
    SharedStorageManager.shared.observeGetBoolForTesting = { _ in ioHits += 1 }
    _ = cache.isEnabled("guyue.action.newfile.txt", default: false)
    _ = cache.isEnabled("guyue.action.newfile.txt", default: false)
    _ = cache.isEnabled("guyue.action.newfile.txt", default: false)
    XCTAssertEqual(ioHits, 1, "首次 miss 后应命中缓存，不再走 SharedStorageManager.getBool")
    SharedStorageManager.shared.observeGetBoolForTesting = nil
}
```

- [ ] 步骤 2：跑测试确认失败

- [ ] 步骤 3：在 SharedStorageManager.getBool 顶部加可注入观察钩子

```swift
public var observeGetBoolForTesting: ((String) -> Void)?

public func getBool(forKey key: String, defaultValue: Bool = true) -> Bool {
    observeGetBoolForTesting?(key)
    // ... 原逻辑
}
```

- [ ] 步骤 4：改 FinderSync.menu(for:) 把 storage.isActionEnabled / isFavoriteAction 替换为 cache

```swift
let cache = ActionConfigCache.shared
let registry = InstalledAppRegistry.shared

// 在 init() 中：
cache.preheat()
let bundleIds = registeredAll.compactMap { $0.associatedBundleIdentifier }
registry.preheat(bundleIds)

// 在 menu(for:) 内：
let favoriteActions = dispatcher.allActions.filter { action in
    cache.isFavorite(action.actionId)
        && cache.isEnabled(action.actionId, default: action.isEnabledByDefault)
        && action.isAvailable(for: targetURLs, isContainer: isContainer)
}

// 同样改：分类循环中 storage.isActionEnabled → cache.isEnabled
```

- [ ] 步骤 5：批量替换 FinderSync 与 SharedStorageManager 中的 print/writeLog 为 AppLog

```swift
// FinderSync.logToSharedContainer 改为：
private func logToSharedContainer(_ message: String, level: SharedLogLevel = .info) {
    switch level {
    case .info: AppLog.info(message, category: .ext)
    case .debug: AppLog.debug(message, category: .ext)
    case .error: AppLog.error(message, category: .ext)
    }
}

// SharedStorageManager.writeLog 内的 fileHandle.write 整段删除，改为：
public func writeLog(_ message: String, level: SharedLogLevel = .info) {
    if level == .debug && !isDebugLoggingEnabled { return }
    switch level {
    case .info: AppLog.info(message, category: .storage)
    case .debug: AppLog.debug(message, category: .storage)
    case .error: AppLog.error(message, category: .storage)
    }
}
```

- [ ] 步骤 6：DiagnosticsSettingsView 增加「导出旧日志」按钮

```swift
Button("导出旧日志（如有）") {
    let url = SharedStorageManager.shared.logFileURL
    if FileManager.default.fileExists(atPath: url.path) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
        SharedHUDManager.show(title: "无旧日志", content: "OSLog 已生效，旧 extension.log 未追加", isSuccess: true)
    }
}
.buttonStyle(.bordered)
```

- [ ] 步骤 7：跑测试 + bash Scripts/build.sh

- [ ] 步骤 8：commit

```bash
git add Sources/RightClickAssistantExtension/FinderSync.swift Sources/RightClickAssistant/Core/SharedStorageManager.swift Sources/RightClickAssistant/Views/ContentView.swift Tests/RightClickAssistantTests.swift
git commit -m "feat(perf+log): FinderSync 主路径走 ActionConfigCache，全局日志切 OSLog"
```


### Task 11: 概览页单一引导 + 恢复默认拆分 + 删死分支 + Permissions 改事件驱动

**Files:**
- Modify: Sources/RightClickAssistant/Views/ContentView.swift

- [ ] 步骤 1：测试（视图层无法直接 unit 测，改用文档级断言：在 commit 前手动跑下面 grep）

```bash
# 期望：扩展启用与未启用两条路径只在「已启用」分支才出现 ExtensionRegistrationBox
grep -nE "ExtensionRegistrationBox|isEnabled" Sources/RightClickAssistant/Views/ContentView.swift | head
```

- [ ] 步骤 2：改 OverviewSettingsView：把 ExtensionRegistrationBox 移入 ExtensionStatusBanner 内的「已启用」分支

```swift
// OverviewSettingsView.body：
ExtensionStatusBanner()
    .padding(.horizontal, -16)
    .padding(.top, -16)

// 删除原本始终显示的 ExtensionRegistrationBox()

// 在 ExtensionStatusBanner.isEnabled == true 分支内（已启用 banner 之后）增加：
ExtensionRegistrationBox()  // 文案改为「重新注册扩展（修复入口）」
```

并修改 ExtensionRegistrationBox 文案：
```swift
Text("如果右键菜单出现异常，可点击下方按钮重新注册 Finder 扩展。")
```

- [ ] 步骤 3：改 AdvancedSettingsView 拆两按钮

```swift
GroupBox(label: Label("恢复", systemImage: "arrow.counterclockwise")) {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("仅恢复动作启用状态").font(.body)
                Text("移除所有动作启用状态配置，恢复内置默认值。").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("恢复") { resetActionDefaults() }.buttonStyle(.bordered)
        }
        Divider()
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("恢复全部默认设置").font(.body)
                Text("清空收藏、监听目录、提示开关与调试日志开关。").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("全部恢复") { resetAllDefaults() }.buttonStyle(.borderedProminent).tint(.orange)
        }
    }
    .padding(.vertical, 8)
}

private func resetAllDefaults() {
    resetActionDefaults()
    SharedStorageManager.shared.setStringArray([], forKey: SharedStorageManager.Keys.favoriteActionIds)
    SharedStorageManager.shared.setStringArray(
        SharedStorageManager.defaultWatchedDirectoryPaths(homePath: NSHomeDirectory()),
        forKey: SharedStorageManager.Keys.watchedDirectoryPaths
    )
    SharedStorageManager.shared.removeValue(forKey: "shouldEnableiCloudMenu")
    SharedStorageManager.shared.removeValue(forKey: "enable_success_hud")
    SharedStorageManager.shared.removeValue(forKey: SharedStorageManager.Keys.enableDebugLogging)
    refreshID = UUID()
    SharedHUDManager.show(title: "已恢复全部默认", content: "动作、收藏、监听目录、提示开关均已重置", isSuccess: true)
}
```

- [ ] 步骤 4：删 OnboardingStepsView else 分支

直接把 `if isVenturaOrNewer { ... } else { ... }` 替换为 if 主体内容，删除 else 与 systemVersion 兜底。

- [ ] 步骤 5：PermissionsSettingsView 改事件驱动

```swift
// 删：
// let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
// .onReceive(timer) { _ in refresh() }

// 仅保留：
.onAppear(perform: refresh)
.onReceive(NotificationCenter.default.publisher(for: NSApplication.willBecomeActiveNotification)) { _ in refresh() }
```

并在 GroupBox「完全磁盘访问权限」HStack 中加「重新检测」按钮，对应 refresh()。

- [ ] 步骤 6：bash Scripts/build.sh + 手动验收（启动 App 走概览页/高级页/权限页一遍）

- [ ] 步骤 7：commit

```bash
git add Sources/RightClickAssistant/Views/ContentView.swift
git commit -m "feat(ux): 概览页单一引导入口，高级页恢复默认拆两档，删 macOS<13 死分支，权限页改事件驱动"
```


### Task 12: 二维码窗口加保存/拷贝按钮

**Files:**
- Modify: Sources/RightClickAssistant/Core/Actions/UtilityAction.swift（抽 fileprivate QRCodePanelController）

- [ ] 步骤 1：实现 QRCodePanelController

```swift
fileprivate final class QRCodePanelController: NSObject {
    private let panel: NSPanel
    private let image: NSImage
    private let text: String

    init(image: NSImage, text: String) {
        self.image = image
        self.text = text
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = "文本二维码"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.center()

        let imageView = NSImageView(frame: NSRect(x: 20, y: 100, width: 280, height: 280))
        imageView.image = image
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.white.cgColor
        imageView.layer?.cornerRadius = 6

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 50, width: 280, height: 40))
        scrollView.hasVerticalScroller = true
        let textView = NSTextView(frame: scrollView.bounds)
        textView.string = text
        textView.isEditable = false
        textView.font = .systemFont(ofSize: 11)
        scrollView.documentView = textView

        let saveBtn = NSButton(title: "保存为 PNG", target: self, action: #selector(savePNG))
        saveBtn.frame = NSRect(x: 20, y: 12, width: 130, height: 28)
        let copyBtn = NSButton(title: "拷贝图片", target: self, action: #selector(copyImage))
        copyBtn.frame = NSRect(x: 170, y: 12, width: 130, height: 28)

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 420))
        content.addSubview(imageView)
        content.addSubview(scrollView)
        content.addSubview(saveBtn)
        content.addSubview(copyBtn)
        panel.contentView = content
    }

    func show() { panel.orderFront(nil) }

    @objc private func savePNG() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "qrcode.png"
        savePanel.level = .modalPanel
        savePanel.orderFrontRegardless()
        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                SharedHUDManager.show(title: "已保存", content: url.lastPathComponent, isSuccess: true)
            }
        }
    }

    @objc private func copyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        SharedHUDManager.show(title: "已拷贝图片", content: "可粘贴到聊天或文档", isSuccess: true)
    }
}
```

- [ ] 步骤 2：把 generateQRCodeFromClipboard 末尾的 panel 构造代码替换为：

```swift
let controller = QRCodePanelController(image: nsImage, text: text)
controller.show()
SharedHUDManager.show(title: "二维码已生成", content: "剪贴板内容已转为二维码", isSuccess: true)
```

并把 controller 持有：

```swift
fileprivate var activeQRController: QRCodePanelController?  // 顶层文件作用域
// generateQRCodeFromClipboard 内：
activeQRController = controller
```

- [ ] 步骤 3：bash Scripts/build.sh + 手动测试保存/拷贝

- [ ] 步骤 4：commit

```bash
git add Sources/RightClickAssistant/Core/Actions/UtilityAction.swift
git commit -m "feat(qr): 二维码窗口加保存为 PNG/拷贝图片按钮，长内容滚动文本预览"
```


### Task 13: build.sh 按 DISTRIBUTION_ROUTE 分叉 entitlements + Release 启用 -O

**Files:**
- Create: entitlements/website.host.entitlements
- Create: entitlements/mas.host.entitlements
- Create: entitlements/extension.entitlements
- Modify: Scripts/build.sh

- [ ] 步骤 1：写三份 entitlements 模板

```xml
<!-- entitlements/website.host.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- website 路线主 App 不开 sandbox，可直接读 Extension Container -->
  <!-- Hardened runtime 通过 codesign --options runtime 注入 -->
</dict>
</plist>
```

```xml
<!-- entitlements/mas.host.entitlements 暂不构建，仅占位 -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.guyue.RightClickAssistant</string>
  </array>
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
</dict>
</plist>
```

```xml
<!-- entitlements/extension.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.application-groups</key>
  <array>
    <string>group.guyue.RightClickAssistant</string>
  </array>
</dict>
</plist>
```

- [ ] 步骤 2：改 build.sh

```bash
# 替换原本动态生成 entitlements 的两段，改为：
case "$DISTRIBUTION_ROUTE" in
    website-dev|website-release)
        HOST_ENTITLEMENTS="entitlements/website.host.entitlements"
        ;;
    mac-app-store)
        HOST_ENTITLEMENTS="entitlements/mas.host.entitlements"
        ;;
esac
EXT_ENTITLEMENTS="entitlements/extension.entitlements"

cp "$HOST_ENTITLEMENTS" "$BUILD_DIR/RightClickAssistant.entitlements"
cp "$EXT_ENTITLEMENTS"  "$BUILD_DIR/RightClickAssistantExtension.entitlements"

# COMMON_FLAGS 中按路线追加 -O：
case "$DISTRIBUTION_ROUTE" in
    website-release|mac-app-store)
        COMMON_FLAGS="$COMMON_FLAGS -O"
        ;;
    website-dev)
        COMMON_FLAGS="$COMMON_FLAGS -Onone"
        ;;
esac
```

- [ ] 步骤 3：bash Scripts/build.sh DISTRIBUTION_ROUTE=website-dev → 看到 🎉

- [ ] 步骤 4：DISTRIBUTION_ROUTE=website-release bash Scripts/build.sh（无 Developer ID 应停在 ❌ 提示，不构建产物）

- [ ] 步骤 5：commit

```bash
git add entitlements Scripts/build.sh
git commit -m "build: entitlements 按分发路线分叉，website-release 启用 -O 优化"
```


### Task 14: README 同步 OSLog 诊断方式 + spec/plan 收尾

**Files:**
- Modify: README.md
- Modify: README_EN.md
- Modify: docs/distribution/mac-app-store-architecture.md（追加 Distribution 常量章节）

- [ ] 步骤 1：在 README Q&A 章节把「cat ~/Library/Containers/.../extension.log」替换为：

```
log show --predicate 'subsystem == "guyue.RightClickAssistant"' --last 5m --info
```

- [ ] 步骤 2：英文 README 同步

- [ ] 步骤 3：mac-app-store-architecture.md 追加：

```
## Distribution.swift 常量映射

- WEBSITE_DEV / WEBSITE_RELEASE：usesAppGroup = false，allowsCrossContainerExchange = true
- MAC_APP_STORE：usesAppGroup = true，allowsCrossContainerExchange = false

build.sh 通过 -D 注入 ROUTE_DEFINES，Swift 端只读编译期常量，不再依赖运行时探测。
```

- [ ] 步骤 4：commit

```bash
git add README.md README_EN.md docs/distribution/mac-app-store-architecture.md
git commit -m "docs: 同步 OSLog 诊断指引，补充 Distribution 常量映射"
```

## 最终验收 Gate

- [ ] G1：跑全套单测，全部通过
- [ ] G2：DISTRIBUTION_ROUTE=website-dev bash Scripts/build.sh 成功，产物 build/RightClickAssistant.dmg、.zip 正常
- [ ] G3：手动 14 步验收清单（见 spec §5.2）逐项打勾
- [ ] G4：性能基线（spec §5.3）实测达标，重点 menu(for:) < 30ms 中位数
- [ ] G5：确认 ~/Library/Containers/<extBundle>/Data/Library/Logs/extension.log 在新版本启动后未追加新行
- [ ] G6：在 macOS 13 Ventura 与 macOS 14 Sonoma 至少一台真机各跑一次

## 自检（spec ↔ plan 对齐）

| spec 编号 | 落在 Task | 备注 |
| --- | --- | --- |
| A1 永久删除 HIG | Task 5 | DestructiveActionConfirmer |
| A2 Office 模板 | Task 7 | 仓库直存骨架 |
| A3 托盘移除高风险 + osascript | Task 8 | 拆两段同 commit |
| A4 Entitlements 分叉 | Task 2 + Task 13 | 常量与脚本分两次 |
| B1 概览页单一引导 | Task 11 | OverviewSettingsView |
| B2 HUD 多屏 + 关闭 | Task 9 | screenFrame |
| B3 菜单缓存化 | Task 3 + 4 + 10 | cache 模块与接入 |
| B4 Release -O | Task 13 | build.sh COMMON_FLAGS |
| B5 恢复默认拆分 | Task 11 | resetActionDefaults / resetAllDefaults |
| B6 跨卷事务化 | Task 6 | crossVolumeMove |
| C1 OSLog | Task 1 + 10 | AppLog 模块 + 接入 |
| C2 二维码 | Task 12 | QRCodePanelController |
| C3 删死分支 | Task 11 | OnboardingStepsView |
| C4 Permissions 事件驱动 | Task 11 | 同 commit |

每个 spec 编号都有 Task 落点，无遗漏。

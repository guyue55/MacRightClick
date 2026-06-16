import XCTest
@testable import RightClickAssistantCore

/// 验证 WatchScope（作用范围）开关的语义（最小核心）：
/// 1. 默认是 .everywhere（首次安装即全盘可用，最贴用户预期）；
/// 2. .everywhere 时 watchedDirectoryURLs 包含 "/" —— 这是 FinderSync 把
///    directoryURLs 注册到全盘的唯一通路（FIFinderSyncController 设计强制）；
/// 3. .custom 时只返回用户自定义/默认 3 目录列表；
/// 4. 切换会即时反映，无需重启进程。
final class WatchScopeTests: XCTestCase {

    private let storage = SharedStorageManager.shared

    override func setUp() {
        super.setUp()
        // 清场：每个用例从默认值起步。
        storage.removeValue(forKey: SharedStorageManager.Keys.watchScope)
        storage.removeValue(forKey: SharedStorageManager.Keys.watchedDirectoryPaths)
    }

    func testDefaultScopeIsEverywhere() {
        XCTAssertEqual(storage.watchScope, .everywhere,
                       "默认值改成 .everywhere 是本轮的产品决策；老用户若有自定义会在 setter 里被尊重")
    }

    func testEverywhereYieldsRootURL() {
        storage.watchScope = .everywhere
        let urls = storage.watchedDirectoryURLs
        XCTAssertTrue(urls.contains(URL(fileURLWithPath: "/")),
                      ".everywhere 必须返回 / 让 FinderSync 注册全盘 directoryURLs")
    }

    /// .everywhere 时还要把 Desktop/Downloads/Documents 作为「种子目录」一并注册，
    /// 用来打破 chicken-and-egg：全新设备上 Finder 没看见受监控目录就不会拉起 Extension，
    /// 那么写到 directoryURLs 的 "/" 永远到不了 Finder。
    /// 种子目录里只要其中之一存在，Finder 在用户进入时就能把 Extension 拉起。
    func testEverywhereIncludesSeedDirectoriesWhenPresent() {
        storage.watchScope = .everywhere
        let urls = storage.watchedDirectoryURLs.map(\.path)
        let home = NSHomeDirectory()  // 仅作存在性参考
        let candidates = ["Desktop", "Downloads", "Documents"]
            .map { (home as NSString).appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0) }
        // 种子集合至少要被部分包含（CI 环境里这三个目录可能都不存在）。
        if !candidates.isEmpty {
            XCTAssertFalse(Set(urls).intersection(Set(candidates)).isEmpty,
                           ".everywhere 应当注册 Desktop/Downloads/Documents 中存在的种子目录")
        }
    }

    func testCustomYieldsCustomList() {
        storage.watchScope = .custom
        // custom 模式下走旧逻辑：默认 Desktop/Downloads/Documents 中存在的子集。
        let urls = storage.watchedDirectoryURLs
        // 不强测具体路径（CI 环境 Home 不一定有），仅断言 / 不会出现。
        XCTAssertFalse(urls.contains(URL(fileURLWithPath: "/")),
                       ".custom 不应包含根路径")
    }

    func testScopeSwitchPersists() {
        storage.watchScope = .custom
        XCTAssertEqual(storage.watchScope, .custom)
        storage.watchScope = .everywhere
        XCTAssertEqual(storage.watchScope, .everywhere)
    }
}

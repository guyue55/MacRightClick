import XCTest
@testable import RightClickAssistantCore

/// 验证 WatchScope（作用范围）开关的语义（最小核心）：
/// 1. 默认是 .everywhere（首次安装即全盘可用，最贴用户预期）；
/// 2. .everywhere 时 watchedDirectoryURLs 包含 "/" —— 这是 FinderSync 把
///    directoryURLs 注册到全盘的唯一通路（FIFinderSyncController 设计强制）；
/// 3. .custom 时只返回用户自定义/默认 3 目录列表；
/// 4. 切换会即时反映，无需重启进程。
final class WatchScopeTests: XCTestCase {

    private var storage: SharedStorageManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let testStorage = try TestStorage.make()
        addTeardownBlock {
            try TestStorage.removeIfPresent(testStorage.root)
        }
        storage = testStorage.manager
        // 清场：每个用例从默认值起步。
        storage.removeValue(forKey: SharedStorageManager.Keys.watchScope)
        storage.removeValue(forKey: SharedStorageManager.Keys.watchedDirectoryPaths)
        storage.removeValue(forKey: SharedStorageManager.Keys.cloudCompatibility)
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

    func testEverywhereIncludesHomeDirectoryAsStableFinderSyncRoot() {
        storage.watchScope = .everywhere
        let urls = storage.watchedDirectoryURLs.map(\.standardizedFileURL.path)
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

        XCTAssertTrue(urls.contains(homePath),
                      ".everywhere 除了 / 之外还应注册用户 Home，确保文稿等 Home 下目录稳定出现菜单")
    }

    func testEverywhereStableRootsCoverCommonNonHomeLocations() {
        let paths = SharedStorageManager.everywhereWatchedDirectoryPaths(
            homePath: "/Users/tester",
            mountedVolumePaths: []
        )

        XCTAssertTrue(paths.contains("/Applications"),
                      ".everywhere 应显式覆盖 /Applications，不能只依赖 / 的递归语义")
        XCTAssertTrue(paths.contains("/Volumes"),
                      ".everywhere 应显式覆盖 /Volumes，确保外接盘/挂载卷入口能触发 FinderSync")
        XCTAssertTrue(paths.contains("/Users/tester"),
                      ".everywhere 应显式覆盖用户 Home")
    }

    func testEverywhereIncludesMountedVolumes() {
        let paths = SharedStorageManager.everywhereWatchedDirectoryPaths(
            homePath: "/Users/tester",
            mountedVolumePaths: ["/Volumes/WorkDisk", "/Volumes/WorkDisk"]
        )

        XCTAssertEqual(paths.filter { $0 == "/Volumes/WorkDisk" }.count, 1,
                       "挂载卷应被加入且去重，保证外接卷路径下右键菜单稳定出现")
    }

    func testEverywhereKeepsProtectedSeedDirectoriesWithoutProbingReadAccess() {
        let home = "/Users/tester"
        let paths = SharedStorageManager.everywhereWatchedDirectoryPaths(
            homePath: home,
            mountedVolumePaths: []
        )

        XCTAssertTrue(paths.contains(home + "/Desktop"))
        XCTAssertTrue(paths.contains(home + "/Downloads"))
        XCTAssertTrue(paths.contains(home + "/Documents"),
                      "FinderSync 不能用 fileExists 结果过滤受保护的文稿目录")
    }

    /// .everywhere 时还要把 Desktop/Downloads/Documents 作为「种子目录」一并注册，
    /// 用来打破 chicken-and-egg：全新设备上 Finder 没看见受监控目录就不会拉起 Extension，
    /// 那么写到 directoryURLs 的 "/" 永远到不了 Finder。
    /// 种子目录不做读权限探测，Finder 在用户进入时就能把 Extension 拉起。
    func testEverywhereIncludesSeedDirectories() {
        storage.watchScope = .everywhere
        let urls = storage.watchedDirectoryURLs.map(\.path)
        let home = NSHomeDirectory()
        let candidates = ["Desktop", "Downloads", "Documents"]
            .map { (home as NSString).appendingPathComponent($0) }
        XCTAssertTrue(Set(candidates).isSubset(of: Set(urls)),
                      ".everywhere 必须注册 Desktop/Downloads/Documents，不能被扩展读权限过滤")
    }

    func testCustomYieldsCustomList() {
        storage.watchScope = .custom
        // custom 模式下默认使用 Desktop/Downloads/Documents。
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

    func testCloudCompatibilityDefaultsToEnabled() {
        XCTAssertTrue(
            storage.isCloudCompatibilityEnabled,
            "现代 macOS 的桌面与文稿可能由 iCloud File Provider 托管，首次安装必须默认兼容"
        )
    }

    func testCloudCompatibilityIncludesConcreteICloudDriveRoot() {
        let home = "/Users/tester"
        let mobileDocuments = "/Users/tester/Library/Mobile Documents"
        let cloudDocs = mobileDocuments + "/com~apple~CloudDocs"
        let cloudStorage = "/Users/tester/Library/CloudStorage"
        let paths = SharedStorageManager.cloudCompatibleDirectoryPaths(
            homePath: home,
            fileExists: { [mobileDocuments, cloudDocs, cloudStorage].contains($0) }
        )

        XCTAssertTrue(paths.contains(mobileDocuments))
        XCTAssertTrue(paths.contains(cloudDocs),
                      "Finder 可能使用 iCloud Drive 的真实 File Provider 根，不能只注册其父目录")
        XCTAssertTrue(paths.contains(cloudStorage))
    }

    func testCloudCompatibilityKeepsICloudRootsWhenExtensionCannotProbeThem() {
        let home = "/Users/tester"
        let paths = SharedStorageManager.cloudCompatibleDirectoryPaths(
            homePath: home,
            fileExists: { _ in false }
        )

        XCTAssertTrue(paths.contains(home + "/Library/Mobile Documents"))
        XCTAssertTrue(paths.contains(home + "/Library/Mobile Documents/com~apple~CloudDocs"))
        XCTAssertFalse(paths.contains(home + "/Library/CloudStorage"),
                       "不存在的第三方可选云盘根不应被注册")
    }
}

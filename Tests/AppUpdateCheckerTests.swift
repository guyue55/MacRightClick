import XCTest
@testable import RightClickAssistantCore

final class AppUpdateCheckerTests: XCTestCase {
    func testSemanticVersionOrdersStableVersions() {
        XCTAssertLessThan(SemanticVersion("1.2.9")!, SemanticVersion("1.3.0")!)
        XCTAssertEqual(SemanticVersion("v1.2.0"), SemanticVersion("1.2.0"))
        XCTAssertNil(SemanticVersion("1.2"))
    }

    func testLatestReleaseDecodingReturnsUpdateURL() async throws {
        let releaseURL = URL(
            string: "https://github.com/guyue55/MacRightClick/releases/tag/v1.3.0"
        )!
        let data = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v1.3.0",
            "html_url": releaseURL.absoluteString
        ])
        let checker = AppUpdateChecker(dataLoader: { _ in (data, 200) })

        let result = await checker.check(currentVersion: "1.2.0")

        XCTAssertEqual(
            result,
            .success(.updateAvailable(version: "1.3.0", releaseURL: releaseURL))
        )
    }

    func testHTTPFailureProducesUserFacingError() async {
        let checker = AppUpdateChecker(dataLoader: { _ in (Data(), 503) })

        let result = await checker.check(currentVersion: "1.2.0")

        XCTAssertEqual(result, .failure(.httpStatus(503)))
    }

    func testCheckerDoesNotLoadUntilCheckIsCalled() async {
        let counter = UpdateLoaderCounter()
        let checker = AppUpdateChecker(dataLoader: { _ in
            counter.increment()
            return (Data(), 500)
        })

        XCTAssertEqual(counter.count, 0)
        _ = await checker.check(currentVersion: "1.2.0")
        XCTAssertEqual(counter.count, 1)
    }
}

private final class UpdateLoaderCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.withLock { storedCount }
    }

    func increment() {
        lock.withLock { storedCount += 1 }
    }
}

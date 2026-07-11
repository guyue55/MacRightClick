import XCTest
@testable import RightClickAssistantCore

final class FileCutClipboardTests: XCTestCase {
    private var clipboard: FileCutClipboard!
    private var storage: SharedStorageManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let testStorage = try TestStorage.make()
        addTeardownBlock {
            try TestStorage.removeIfPresent(testStorage.root)
        }
        storage = testStorage.manager
        clipboard = FileCutClipboard(storageManager: testStorage.manager)
    }

    func testOldPasteCompletionDoesNotClearNewCutSnapshot() throws {
        clipboard.cutURLs = [URL(fileURLWithPath: "/tmp/A")]
        let oldSnapshot = try XCTUnwrap(clipboard.snapshot)

        clipboard.cutURLs = [URL(fileURLWithPath: "/tmp/B")]

        XCTAssertFalse(clipboard.replace(snapshotID: oldSnapshot.id, remainingURLs: []))
        XCTAssertEqual(clipboard.cutURLs.map(\.path), ["/tmp/B"])
    }

    func testMatchingPasteCompletionKeepsOnlyFailedURLs() throws {
        let succeeded = URL(fileURLWithPath: "/tmp/succeeded")
        let failed = URL(fileURLWithPath: "/tmp/failed")
        clipboard.cutURLs = [succeeded, failed]
        let snapshot = try XCTUnwrap(clipboard.snapshot)

        XCTAssertTrue(clipboard.replace(snapshotID: snapshot.id, remainingURLs: [failed]))
        XCTAssertEqual(clipboard.snapshot?.id, snapshot.id)
        XCTAssertEqual(clipboard.cutURLs.map(\.path), [failed.path])
    }

    func testLegacyPathArrayIsMigratedToVersionedSnapshot() throws {
        let clipboardURL = storage.sharedContainerURL.appendingPathComponent("clipboard.json")
        let legacyPaths = ["/tmp/legacy-a", "/tmp/legacy-b"]
        try JSONEncoder().encode(legacyPaths).write(to: clipboardURL, options: .atomic)

        let snapshot = try XCTUnwrap(clipboard.snapshot)

        XCTAssertEqual(snapshot.urls.map(\.path), legacyPaths)
        let migratedData = try Data(contentsOf: clipboardURL)
        XCTAssertNoThrow(try JSONDecoder().decode(CutClipboardSnapshot.self, from: migratedData))
    }

    func testCutStateWriteFailureIsReported() throws {
        let clipboardURL = storage.sharedContainerURL.appendingPathComponent("clipboard.json")
        try FileManager.default.createDirectory(at: clipboardURL, withIntermediateDirectories: true)

        XCTAssertFalse(clipboard.setCutURLs([URL(fileURLWithPath: "/tmp/unwritable")]))
        XCTAssertNil(clipboard.snapshot)
    }
}

import XCTest
@testable import RightClickAssistantCore

final class PathCopyServiceTests: XCTestCase {
    func testShellEscapesSingleQuoteAndSpaces() {
        let value = PathCopyService.shellEscapedArguments([
            URL(fileURLWithPath: "/tmp/it's ready.txt")
        ])

        XCTAssertEqual(value, "'/tmp/it'\\''s ready.txt'")
    }

    func testGitRootReturnsDotAndOutsideRepositoryReturnsNil() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(PathCopyService.gitRelativePaths([repository]), ["."])
        XCTAssertNil(PathCopyService.gitRelativePaths([root]))
    }

    func testCrossRepositorySelectionReturnsOneRelativePathPerLine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var files: [URL] = []
        for name in ["one", "two"] {
            let repository = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(
                at: repository.appendingPathComponent(".git", isDirectory: true),
                withIntermediateDirectories: true
            )
            let file = repository.appendingPathComponent("Sources/App.swift")
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: file)
            files.append(file)
        }

        XCTAssertEqual(
            PathCopyService.gitRelativePaths(files),
            ["Sources/App.swift", "Sources/App.swift"]
        )
    }
}

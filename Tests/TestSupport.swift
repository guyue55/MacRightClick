import Foundation
@testable import RightClickAssistantCore

enum TestStorageError: LocalizedError, Equatable {
    case unsafeContainerPath(URL)

    var errorDescription: String? {
        switch self {
        case .unsafeContainerPath(let url):
            return "测试存储目录禁止位于 Library/Containers：\(url.path)"
        }
    }
}

enum TestStorage {
    static func make(
        testCaseName: String = #function,
        baseDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> (manager: SharedStorageManager, root: URL) {
        let candidate = baseDirectory
            .appendingPathComponent("RightClickAssistantTests")
            .appendingPathComponent("\(testCaseName)-\(UUID().uuidString)", isDirectory: true)
        let root = candidate.resolvingSymlinksInPath().standardizedFileURL

        let components = root.pathComponents
        for index in components.indices.dropLast()
            where components[index].caseInsensitiveCompare("Library") == .orderedSame
                && components[index + 1].caseInsensitiveCompare("Containers") == .orderedSame {
            throw TestStorageError.unsafeContainerPath(root)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (SharedStorageManager(sharedContainerURLOverride: root), root)
    }

    static func removeIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}

/// 测试用并发捕获盒。调用方必须保证被包装对象的生命周期覆盖全部并发任务，
/// 并且只调用该对象明确声明为线程安全的接口。
final class TestSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

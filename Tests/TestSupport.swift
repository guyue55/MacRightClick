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
        // 先解析已存在的父目录。若先拼接尚不存在的后代，macOS 26 不会稳定展开
        // 中间 symlink，可能绕过 Library/Containers 的测试隔离守门。
        let resolvedBaseDirectory = baseDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let root = resolvedBaseDirectory
            .appendingPathComponent("RightClickAssistantTests")
            .appendingPathComponent("\(testCaseName)-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL

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

/// 并发测试中的最小锁保护集合，避免把 Foundation 可变集合跨 Sendable 闭包传递。
final class TestLockedSet<Element: Hashable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Set<Element> = []

    func insert(_ element: Element) {
        lock.lock()
        storage.insert(element)
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
}

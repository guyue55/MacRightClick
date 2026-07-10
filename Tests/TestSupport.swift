import Foundation
@testable import RightClickAssistantCore

enum TestStorage {
    static func make(testCaseName: String = #function) throws -> (manager: SharedStorageManager, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightClickAssistantTests")
            .appendingPathComponent("\(testCaseName)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        precondition(!root.path.contains("/Library/Containers/"))
        return (SharedStorageManager(sharedContainerURLOverride: root), root)
    }
}

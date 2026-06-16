import XCTest
@testable import RightClickAssistantCore

/// CI 友好的 PendingAction 压测：覆盖 lease/ack/reclaim 三件套在并发 + 大批量 +
/// 异常输入下的不变量，与 `Scripts/stress/*.py` 的真机端到端压测互为镜像。
///
/// 与真机 harness 的分工：
/// - 真机 harness（python）跑完整 .app 进程，能捕获 cfprefsd / NSWorkspace 一类
///   只在 GUI 主 App 才会暴露的死锁；
/// - 本 XCTest 套件不需要主 App，跑 SharedStorageManager 的纯 IO 契约，
///   CI 上 `swift test` 即可重放。
///
/// 不变量：
/// 1. 大量并发 enqueue 不会丢/重；
/// 2. consume 后 PendingActions 立刻空、InFlight/<pid>/ 与事件数对齐；
/// 3. ack 之后 InFlight 文件被清干净；
/// 4. 不 ack 的 lease 在 reclaim 之后会回到 Pending，可以再消费；
/// 5. malformed JSON 精准搬到 FailedActions，不阻塞 well-formed 事件。
final class PendingActionStressTests: XCTestCase {

    private var manager: SharedStorageManager!
    private var sandboxRoot: URL!

    override func setUp() {
        super.setUp()
        manager = SharedStorageManager.shared
        sandboxRoot = manager.sharedContainerURL
        for sub in ["PendingActions", "InFlightActions", "FailedActions"] {
            let url = sandboxRoot.appendingPathComponent(sub, isDirectory: true)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 200 条事件由多线程并发 enqueue，consume 必须一次性全拿到、不丢不重。
    func testHighConcurrencyEnqueueDoesNotDropEvents() {
        let total = 200
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent.enqueue", attributes: .concurrent)
        let producedIds = NSMutableSet()
        let lock = NSLock()

        for i in 0..<total {
            group.enter()
            queue.async { [weak self] in
                defer { group.leave() }
                guard let self = self else { return }
                let url = try? self.manager.enqueueAction(
                    actionId: "test.stress.\(i % 7)",
                    paths: ["/tmp/stress-\(i)"]
                )
                XCTAssertNotNil(url)
                if let url = url {
                    lock.lock()
                    producedIds.add(url.lastPathComponent)
                    lock.unlock()
                }
            }
        }
        group.wait()
        XCTAssertEqual(producedIds.count, total, "并发 enqueue 不应文件名互踩")

        let leases = manager.consumePendingActionLeases()
        XCTAssertEqual(leases.count, total, "consume 必须 1:1 拿到全部事件")

        let consumedIds = Set(leases.map { $0.event.id })
        XCTAssertEqual(consumedIds.count, total, "lease.event.id 必须互不重复")

        // ack 后 InFlight/<pid>/ 应当清空。
        leases.forEach { manager.acknowledge($0) }
        let inflightLeft = (try? FileManager.default.contentsOfDirectory(
            atPath: manager.inFlightActionsDirectoryURL
                .appendingPathComponent(String(ProcessInfo.processInfo.processIdentifier))
                .path
        )) ?? []
        XCTAssertTrue(inflightLeft.filter { $0.hasSuffix(".json") }.isEmpty)
    }

    /// 没有 ack 的 lease 视作"上一次 dispatch 中途崩溃"。reclaim 之后，那些文件应当
    /// 出现在别的 PID 子目录里，但当前进程的 reclaim 仅会搬"非自己 PID"的目录。
    /// 这里直接构造别的 PID 子目录里的孤儿，验证 reclaim 路径。
    func testReclaimMovesOrphansFromOtherPIDsBackToPending() throws {
        let bogusPID = 91234
        let bogusDir = manager.inFlightActionsDirectoryURL.appendingPathComponent("\(bogusPID)", isDirectory: true)
        try FileManager.default.createDirectory(at: bogusDir, withIntermediateDirectories: true)

        let orphanCount = 50
        for i in 0..<orphanCount {
            let event = SharedActionEvent(
                id: UUID().uuidString,
                createdAt: Date().timeIntervalSince1970,
                actionId: "test.reclaim.\(i)",
                paths: ["/tmp/orphan-\(i)"]
            )
            let data = try JSONEncoder().encode(event)
            let url = bogusDir.appendingPathComponent("\(Int64(event.createdAt*1000))-\(event.id).json")
            try data.write(to: url)
        }

        manager.reclaimAbandonedInFlightActions()

        // bogus PID 子目录被清理。
        XCTAssertFalse(FileManager.default.fileExists(atPath: bogusDir.path))

        let leases = manager.consumePendingActionLeases()
        XCTAssertEqual(leases.count, orphanCount, "reclaim 出来的孤儿应全部进入下一轮 lease")

        leases.forEach { manager.acknowledge($0) }
    }

    /// malformed JSON 与 well-formed 混在一起；前者去 FailedActions，后者正常 lease。
    func testMalformedDoesNotBlockHealthyEvents() throws {
        // 5 条合法事件
        for i in 0..<5 {
            _ = try manager.enqueueAction(actionId: "test.healthy.\(i)", paths: ["/tmp"])
        }
        // 5 条垃圾文件直接写到 PendingActions
        for i in 0..<5 {
            let url = manager.pendingActionsDirectoryURL.appendingPathComponent("malformed-\(i).json")
            try Data("{ this is not json".utf8).write(to: url)
        }

        let leases = manager.consumePendingActionLeases()
        XCTAssertEqual(leases.count, 5, "5 条 well-formed 必须全部 lease")
        leases.forEach { manager.acknowledge($0) }

        XCTAssertEqual(manager.pendingActionCount, 0, "Pending 必须排空")
        XCTAssertEqual(manager.failedActionCount, 5, "5 条 malformed 必须精准 quarantine")
    }
}

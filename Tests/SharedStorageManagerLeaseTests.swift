import XCTest
@testable import RightClickAssistantCore

/// 验证 PendingAction 消费的事务化（P1-2）：
/// 1. 拿到 lease 但没 ack（模拟崩溃）→ 重启后 reclaim 能把孤儿事件搬回 PendingActions；
/// 2. ack 后 InFlight 文件被清理，下一次启动 reclaim 不会复活已完成事件；
/// 3. lease.event 与原始 enqueue 内容一致。
final class SharedStorageManagerLeaseTests: XCTestCase {

    private var manager: SharedStorageManager!
    private var sandboxRoot: URL!

    override func setUp() {
        super.setUp()
        manager = SharedStorageManager.shared
        sandboxRoot = manager.sharedContainerURL
        // 清场：移除可能残留的 PendingActions / InFlightActions / FailedActions 内容，
        // 避免历史用例污染。
        for sub in ["PendingActions", "InFlightActions", "FailedActions"] {
            let url = sandboxRoot.appendingPathComponent(sub, isDirectory: true)
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testLeaseRoundTripAndAckRemovesInFlight() throws {
        let url = try manager.enqueueAction(actionId: "test.lease.simple", paths: ["/tmp/a"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let leases = manager.consumePendingActionLeases()
        XCTAssertEqual(leases.count, 1)
        let lease = leases[0]
        XCTAssertEqual(lease.event.actionId, "test.lease.simple")
        XCTAssertEqual(lease.event.paths, ["/tmp/a"])

        // 拿到 lease 时：原 PendingActions 文件已搬到 InFlight。
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lease.inFlightURL.path))

        manager.acknowledge(lease)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.inFlightURL.path))
    }

    func testReclaimAbandonedInFlightRestoresOrphans() throws {
        // 模拟「上一次进程崩在 dispatcher 中」：lease 拿走但没 ack。
        _ = try manager.enqueueAction(actionId: "test.lease.crash", paths: ["/tmp/b"])
        let leases = manager.consumePendingActionLeases()
        XCTAssertEqual(leases.count, 1)
        // 故意不 ack。文件留在 InFlight/<pid>/ 里。

        // 模拟下一次启动：reclaim 应当把 InFlight/<pid>/ 文件搬回 PendingActions。
        manager.reclaimAbandonedInFlightActions()

        let recovered = manager.consumePendingActionLeases()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].event.actionId, "test.lease.crash")
        manager.acknowledge(recovered[0])
    }

    func testAckPreventsReclaim() throws {
        _ = try manager.enqueueAction(actionId: "test.lease.normal", paths: ["/tmp/c"])
        let leases = manager.consumePendingActionLeases()
        XCTAssertEqual(leases.count, 1)
        manager.acknowledge(leases[0])

        manager.reclaimAbandonedInFlightActions()
        let again = manager.consumePendingActionLeases()
        XCTAssertEqual(again.count, 0, "已 ack 的事件不应被 reclaim 复活")
    }
}

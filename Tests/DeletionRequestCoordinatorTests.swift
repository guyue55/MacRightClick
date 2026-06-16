import XCTest
import AppKit
@testable import RightClickAssistantCore

/// 验证 DeletionRequestCoordinator 的并发裁决正确，
/// 与真机死锁场景一一对应：
/// - 第一次请求被 accepted、确实调用 presenter；
/// - 在 modal 未关闭前的第二次请求被 rejected(.alreadyPresenting)；
/// - modal 关闭后的请求再次被 accepted；
/// - 任意调用线程都不会在 requestDeletion 内部阻塞主线程（不会触发 main.sync）。
final class DeletionRequestCoordinatorTests: XCTestCase {

    /// 假的 presenter：不真的弹 NSAlert，
    /// 而是把 completion 暂存起来，让测试自由决定何时"用户做出选择"。
    final class FakePresenter: ConfirmationPresenter {
        var presentedCount = 0
        private var pendingCompletion: ((DestructiveChoice) -> Void)?

        func present(targets: [URL], completion: @escaping (DestructiveChoice) -> Void) {
            presentedCount += 1
            pendingCompletion = completion
        }

        /// 模拟用户做出选择并触发回调，必须在主线程调用以贴近生产路径。
        func resolve(with choice: DestructiveChoice) {
            let cb = pendingCompletion
            pendingCompletion = nil
            cb?(choice)
        }
    }

    func testFirstRequestAccepted() {
        let presenter = FakePresenter()
        let coordinator = DeletionRequestCoordinator(presenter: presenter)
        let exp = expectation(description: "presenter 被调用")

        let outcome = coordinator.requestDeletion(targets: [URL(fileURLWithPath: "/tmp/a.txt")])
        XCTAssertEqual(outcome, .accepted)

        // requestDeletion 异步派发到主线程；用 main.async 等一拍即可观察 presenter 是否被调到。
        DispatchQueue.main.async {
            XCTAssertEqual(presenter.presentedCount, 1)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func testConcurrentRequestRejectedWhilePresenting() {
        let presenter = FakePresenter()
        let coordinator = DeletionRequestCoordinator(presenter: presenter)

        let first = coordinator.requestDeletion(targets: [URL(fileURLWithPath: "/tmp/a.txt")])
        XCTAssertEqual(first, .accepted)

        // 用 main.async 包一层，确保 first 的 present 已经被调度到主线程。
        let exp = expectation(description: "second rejected with alreadyPresenting")
        DispatchQueue.main.async {
            let second = coordinator.requestDeletion(targets: [URL(fileURLWithPath: "/tmp/b.txt")])
            XCTAssertEqual(second, .rejected(reason: .alreadyPresenting))
            // 只调到了 1 次 presenter，第 2 次被合并丢弃 —— 这正是死锁链断点。
            XCTAssertEqual(presenter.presentedCount, 1)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func testSubsequentRequestAcceptedAfterChoiceResolved() {
        let presenter = FakePresenter()
        let coordinator = DeletionRequestCoordinator(presenter: presenter)

        let outcome = coordinator.requestDeletion(targets: [URL(fileURLWithPath: "/tmp/a.txt")])
        XCTAssertEqual(outcome, .accepted)

        let exp = expectation(description: "resolve 后允许新的请求")
        DispatchQueue.main.async {
            // 模拟用户在弹窗里点了"取消"，coordinator 内部清 in-flight 标志。
            presenter.resolve(with: .cancel)
            // resolve 内部通过 DispatchQueue.main.async 排队，再 async 一拍读到 isPresenting=false
            DispatchQueue.main.async {
                let outcome2 = coordinator.requestDeletion(targets: [URL(fileURLWithPath: "/tmp/c.txt")])
                XCTAssertEqual(outcome2, .accepted)
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 1.0)
    }

    func testEmptyTargetsRejected() {
        let coordinator = DeletionRequestCoordinator(presenter: FakePresenter())
        let outcome = coordinator.requestDeletion(targets: [])
        XCTAssertEqual(outcome, .rejected(reason: .emptyTargets))
    }

    /// 守门测试：保证 requestDeletion 在任意后台线程调用都不会阻塞调用者，
    /// 也不会触发对主线程的同步等待（贴近 folder-monitor 串行队列的真实路径）。
    func testRequestFromBackgroundQueueDoesNotBlock() {
        let presenter = FakePresenter()
        let coordinator = DeletionRequestCoordinator(presenter: presenter)

        let bg = DispatchQueue(label: "test.bg.queue")
        let exp = expectation(description: "后台线程立刻返回")
        bg.async {
            let outcome = coordinator.requestDeletion(targets: [URL(fileURLWithPath: "/tmp/d.txt")])
            XCTAssertEqual(outcome, .accepted)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}

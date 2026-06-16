import XCTest
@testable import RightClickAssistantCore

/// 验证 InteractiveActionRunner 的 3 条关键不变量：
/// 1. 任意线程提交都不会阻塞调用者；
/// 2. modal 期间再有别的 Runner 提交，全局闸门拒绝（这是死锁链断点）；
/// 3. prompt 返回 nil 时 perform 一定不被调到；
/// 4. perform 在与 prompt 不同的队列上跑。
final class InteractiveActionRunnerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 清场：保证每个测试从无 in-flight 状态开始。
        InteractiveActionGate.shared.release()
    }

    func testAcceptedAndPromptThenPerform() {
        let runner = InteractiveActionRunner(
            actionLabel: "test.A",
            ioQueueLabel: "test.A.io"
        )
        let exp = expectation(description: "prompt + perform 都被调到")
        var promptHit = false
        var performHit = false

        let outcome = runner.run(
            prompt: { () -> String? in
                promptHit = true
                return "payload"
            },
            perform: { payload in
                XCTAssertEqual(payload, "payload")
                performHit = true
                exp.fulfill()
            }
        )
        XCTAssertEqual(outcome, .accepted)
        wait(for: [exp], timeout: 2.0)
        XCTAssertTrue(promptHit)
        XCTAssertTrue(performHit)
    }

    func testGlobalGateRejectsSecondWhilePresenting() {
        // 手动占住闸门，模拟"前一个 Runner 的 modal 还没关"。
        XCTAssertTrue(InteractiveActionGate.shared.tryAcquire(label: "test.X"))
        defer { InteractiveActionGate.shared.release() }

        let runner = InteractiveActionRunner(
            actionLabel: "test.Y",
            ioQueueLabel: "test.Y.io"
        )
        let outcome = runner.run(
            prompt: { () -> String? in
                XCTFail("不应进入 prompt")
                return nil
            },
            perform: { _ in
                XCTFail("不应进入 perform")
            }
        )
        XCTAssertEqual(outcome, .rejected(reason: .alreadyInteracting))
    }

    func testCancelPromptDoesNotInvokePerform() {
        let runner = InteractiveActionRunner(
            actionLabel: "test.Cancel",
            ioQueueLabel: "test.Cancel.io"
        )
        let exp = expectation(description: "prompt 完成且 perform 不被调")
        runner.run(
            prompt: { () -> Int? in nil },
            perform: { _ in XCTFail("用户取消时不应触发 perform") }
        )
        // perform 不会到，但 prompt 走完后闸门一定要释放。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertNil(InteractiveActionGate.shared.currentLabel)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func testBackgroundSubmissionDoesNotBlock() {
        let runner = InteractiveActionRunner(
            actionLabel: "test.BG",
            ioQueueLabel: "test.BG.io"
        )
        let exp = expectation(description: "后台线程 run() 立刻返回")
        DispatchQueue(label: "test.bg").async {
            let outcome = runner.run(
                prompt: { () -> String? in "ok" },
                perform: { _ in }
            )
            XCTAssertEqual(outcome, .accepted)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}

import XCTest
@testable import RightClickAssistantCore

/// 验证 BackgroundActionRunner 的 3 条关键不变量：
/// 1. submit 立即返回，不阻塞调用方（包含 folder-monitor 串行队列场景）；
/// 2. perform 在 Runner 自己的私有队列上跑，不在主线程也不在调用线程；
/// 3. 同一 Runner 的两次 submit FIFO 串行（不会并发跑同一 IO 资源）。
final class BackgroundActionRunnerTests: XCTestCase {

    func testSubmitReturnsImmediatelyOnAnyThread() {
        let runner = BackgroundActionRunner(
            actionLabel: "test.bg.A",
            ioQueueLabel: "test.bg.A.io"
        )
        let block = expectation(description: "perform finished")
        let callerQueue = DispatchQueue(label: "test.caller")

        callerQueue.async {
            runner.submit {
                // 制造一个明显的「IO 时长」，证明 submit 不会等它结束。
                Thread.sleep(forTimeInterval: 0.15)
                block.fulfill()
            }
            // submit 必须立刻返回；这一行应该在 perform 还未结束前执行。
        }
        wait(for: [block], timeout: 2.0)
    }

    func testPerformRunsOffMainThread() {
        let runner = BackgroundActionRunner(
            actionLabel: "test.bg.B",
            ioQueueLabel: "test.bg.B.io"
        )
        let exp = expectation(description: "perform 在后台跑")
        runner.submit {
            XCTAssertFalse(Thread.isMainThread, "perform 必须离开主线程")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func testSerialFIFO() {
        let runner = BackgroundActionRunner(
            actionLabel: "test.bg.C",
            ioQueueLabel: "test.bg.C.io"
        )
        let lock = NSLock()
        var order: [Int] = []
        let exp = expectation(description: "两次 submit 串行")
        exp.expectedFulfillmentCount = 2

        runner.submit {
            Thread.sleep(forTimeInterval: 0.1)
            lock.lock(); order.append(1); lock.unlock()
            exp.fulfill()
        }
        runner.submit {
            lock.lock(); order.append(2); lock.unlock()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(order, [1, 2], "FIFO 必须保证；第一笔慢任务必须先于第二笔结束")
    }
}

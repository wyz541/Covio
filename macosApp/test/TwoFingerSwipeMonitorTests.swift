import XCTest
@testable import Covio

@MainActor
final class TwoFingerSwipeMonitorTests: XCTestCase {
    private func frame(y: Double, at timestamp: TimeInterval) -> TouchFrame {
        TouchFrame(
            fingerCount: 2,
            meanNormalizedX: 0,
            meanNormalizedY: y,
            timestamp: timestamp,
            optionKeyDown: true
        )
    }

    func testEmitsOneMainActorCallbackForAValidSwipe() async {
        let source = FakeContactSource(result: .started(deviceCount: 1))
        let triggered = expectation(description: "主线程收到一次触发")
        var triggerCount = 0
        let monitor = TwoFingerSwipeMonitor(source: source) {
            triggerCount += 1
            triggered.fulfill()
        }

        XCTAssertEqual(monitor.start(), .started(deviceCount: 1))
        source.emit(frame(y: 0.45, at: 1.00))
        source.emit(frame(y: 0.20, at: 1.15))

        await fulfillment(of: [triggered], timeout: 1)
        XCTAssertEqual(triggerCount, 1)
        monitor.stop()
        XCTAssertTrue(source.didStop)
    }

    func testDoesNotEmitWithoutOption() async {
        let source = FakeContactSource(result: .started(deviceCount: 1))
        let triggered = expectation(description: "缺少 Option 不触发")
        triggered.isInverted = true
        let monitor = TwoFingerSwipeMonitor(source: source) {
            triggered.fulfill()
        }

        monitor.start()
        source.emit(
            TouchFrame(
                fingerCount: 2,
                meanNormalizedX: 0,
                meanNormalizedY: 0.45,
                timestamp: 1.00
            )
        )
        source.emit(
            TouchFrame(
                fingerCount: 2,
                meanNormalizedX: 0,
                meanNormalizedY: 0.20,
                timestamp: 1.15
            )
        )

        await fulfillment(of: [triggered], timeout: 0.2)
        monitor.stop()
    }

    func testDoesNotEmitForARejectedSwipe() async {
        let source = FakeContactSource(result: .started(deviceCount: 1))
        let triggered = expectation(description: "错误手势不触发")
        triggered.isInverted = true
        let monitor = TwoFingerSwipeMonitor(source: source) {
            triggered.fulfill()
        }

        monitor.start()
        source.emit(
            TouchFrame(
                fingerCount: 3,
                meanNormalizedX: 0,
                meanNormalizedY: 0.20,
                timestamp: 1.00,
                optionKeyDown: true
            )
        )
        source.emit(
            TouchFrame(
                fingerCount: 3,
                meanNormalizedX: 0,
                meanNormalizedY: 0.60,
                timestamp: 1.15,
                optionKeyDown: true
            )
        )

        await fulfillment(of: [triggered], timeout: 0.2)
        monitor.stop()
    }

    func testRepeatedStartReturnsTheCachedResult() {
        let source = FakeContactSource(result: .noDevice)
        let monitor = TwoFingerSwipeMonitor(source: source) {}

        XCTAssertEqual(monitor.start(), .noDevice)
        XCTAssertEqual(monitor.start(), .noDevice)
        XCTAssertEqual(source.startCount, 1)
        monitor.stop()
    }
}

private final class FakeContactSource: MultitouchContactSourceProtocol, @unchecked Sendable {
    private let result: MultitouchStartResult
    private var onFrame: (@Sendable (TouchFrame) -> Void)?
    private(set) var startCount = 0
    private(set) var didStop = false

    init(result: MultitouchStartResult) {
        self.result = result
    }

    func start(onFrame: @escaping @Sendable (TouchFrame) -> Void) -> MultitouchStartResult {
        startCount += 1
        self.onFrame = onFrame
        return result
    }

    func stop() {
        didStop = true
        onFrame = nil
    }

    func emit(_ frame: TouchFrame) {
        onFrame?(frame)
    }
}

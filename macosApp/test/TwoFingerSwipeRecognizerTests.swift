import XCTest
@testable import Covio

final class TwoFingerSwipeRecognizerTests: XCTestCase {
    private func frame(
        _ fingerCount: Int = 2,
        x: Double = 0,
        y: Double,
        optionKeyDown: Bool = true,
        at timestamp: TimeInterval
    ) -> TouchFrame {
        TouchFrame(
            fingerCount: fingerCount,
            meanNormalizedX: x,
            meanNormalizedY: y,
            timestamp: timestamp,
            optionKeyDown: optionKeyDown
        )
    }

    func testRecognizesOneFastVerticalSwipeDown() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(y: 0.45, at: 1.00)))
        XCTAssertTrue(recognizer.process(frame(y: 0.20, at: 1.15)))
    }

    func testOneContinuousContactTriggersOnlyOnce() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(y: 0.45, at: 1.00)))
        XCTAssertTrue(recognizer.process(frame(y: 0.20, at: 1.15)))
        XCTAssertFalse(recognizer.process(frame(y: 0.00, at: 1.25)))
    }

    func testTwoFingerSwipeWithoutOptionDoesNotTrigger() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(y: 0.45, optionKeyDown: false, at: 1.00)))
        XCTAssertFalse(recognizer.process(frame(y: 0.20, optionKeyDown: false, at: 1.15)))
    }

    func testUpwardMotionDoesNotTrigger() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(y: 0.20, at: 1.00)))
        XCTAssertFalse(recognizer.process(frame(y: 0.70, at: 1.15)))
    }

    func testSlightlyAngledSwipeStillTriggers() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(x: 0.20, y: 0.45, at: 1.00)))
        XCTAssertTrue(recognizer.process(frame(x: 0.32, y: 0.20, at: 1.15)))
    }

    func testHorizontalMotionDoesNotTrigger() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(x: 0.20, y: 0.45, at: 1.00)))
        XCTAssertFalse(recognizer.process(frame(x: 0.40, y: 0.20, at: 1.15)))
    }

    func testOrdinaryDownwardScrollDoesNotTrigger() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(y: 0.45, at: 1.00)))
        XCTAssertFalse(recognizer.process(frame(y: 0.41, at: 1.35)))
    }

    func testThreeFingerMotionDoesNotTrigger() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(3, y: 0.60, at: 1.00)))
        XCTAssertFalse(recognizer.process(frame(3, y: 0.20, at: 1.15)))
    }

    func testSlowMotionDoesNotTrigger() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(y: 0.45, at: 1.00)))
        XCTAssertFalse(recognizer.process(frame(y: 0.20, at: 1.60)))
    }

    func testCooldownDoesNotQueueARejectedGesture() {
        let configuration = TwoFingerSwipeConfiguration(cooldown: 0.60)
        var recognizer = TwoFingerSwipeRecognizer(configuration: configuration)

        XCTAssertFalse(recognizer.process(frame(y: 0.45, at: 1.00)))
        XCTAssertTrue(recognizer.process(frame(y: 0.20, at: 1.15)))
        XCTAssertFalse(recognizer.process(frame(0, y: 0, at: 1.20)))

        XCTAssertFalse(recognizer.process(frame(y: 0.45, at: 1.30)))
        XCTAssertFalse(recognizer.process(frame(y: 0.20, at: 1.45)))
        XCTAssertFalse(recognizer.process(frame(y: 0.00, at: 1.70)))
    }

    func testNewContactAfterCooldownCanTrigger() {
        let configuration = TwoFingerSwipeConfiguration(cooldown: 0.60)
        var recognizer = TwoFingerSwipeRecognizer(configuration: configuration)

        XCTAssertFalse(recognizer.process(frame(y: 0.45, at: 1.00)))
        XCTAssertTrue(recognizer.process(frame(y: 0.20, at: 1.15)))
        XCTAssertFalse(recognizer.process(frame(0, y: 0, at: 1.20)))

        XCTAssertFalse(recognizer.process(frame(y: 0.45, at: 1.80)))
        XCTAssertTrue(recognizer.process(frame(y: 0.20, at: 1.95)))
    }

    func testMatchRecordsTheCalibratedMetrics() {
        var recognizer = TwoFingerSwipeRecognizer()
        XCTAssertFalse(recognizer.process(frame(x: 0.40, y: 0.45, at: 1.00)))
        XCTAssertTrue(recognizer.process(frame(x: 0.42, y: 0.20, at: 1.15)))

        let match = recognizer.lastMatch
        XCTAssertEqual(match?.downwardTravel ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(match?.horizontalDeviation ?? 0, 0.02, accuracy: 0.0001)
        XCTAssertEqual(match?.duration ?? 0, 0.15, accuracy: 0.0001)
        XCTAssertEqual(match?.velocity ?? 0, 1.6667, accuracy: 0.0001)
    }

    func testTenRecordedBuiltInSwipeSamplesTrigger() {
        let samples: [(startX: Double, endX: Double, startY: Double, endY: Double, duration: Double)] = [
            (0.4642, 0.4682, 0.5425, 0.3281, 0.184),
            (0.4560, 0.4601, 0.5541, 0.3467, 0.200),
            (0.4516, 0.4534, 0.5431, 0.3065, 0.216),
            (0.4529, 0.4549, 0.5481, 0.2799, 0.216),
            (0.4560, 0.4704, 0.5465, 0.2934, 0.176),
            (0.4524, 0.4475, 0.5524, 0.2781, 0.216),
            (0.4577, 0.4702, 0.5877, 0.2587, 0.224),
            (0.4422, 0.4506, 0.5833, 0.2487, 0.304),
            (0.4272, 0.4378, 0.6009, 0.2989, 0.312),
            (0.4211, 0.4255, 0.6049, 0.3003, 0.336),
        ]

        for sample in samples {
            var recognizer = TwoFingerSwipeRecognizer()
            XCTAssertFalse(
                recognizer.process(
                    frame(x: sample.startX, y: sample.startY, at: 1.00)
                )
            )
            XCTAssertTrue(
                recognizer.process(
                    frame(
                        x: sample.endX,
                        y: sample.endY,
                        at: 1.00 + sample.duration
                    )
                )
            )
        }
    }

    func testRecordedUpwardSamplesDoNotTrigger() {
        let samples: [(startX: Double, endX: Double, startY: Double, endY: Double, duration: Double)] = [
            (0.4077, 0.3755, 0.2034, 0.3717, 0.144),
            (0.4604, 0.3332, 0.1936, 0.4823, 0.136),
            (0.4955, 0.4597, 0.1674, 0.3823, 0.144),
            (0.4796, 0.4722, 0.3319, 0.3714, 0.944),
        ]

        for sample in samples {
            var recognizer = TwoFingerSwipeRecognizer()
            XCTAssertFalse(
                recognizer.process(
                    frame(x: sample.startX, y: sample.startY, at: 1.00)
                )
            )
            XCTAssertFalse(
                recognizer.process(
                    frame(
                        x: sample.endX,
                        y: sample.endY,
                        at: 1.00 + sample.duration
                    )
                )
            )
        }
    }

    func testSmallRecordedScrollSamplesDoNotTrigger() {
        let samples: [(startX: Double, endX: Double, startY: Double, endY: Double, duration: Double)] = [
            (0.5482, 0.5522, 0.4460, 0.3962, 0.040),
            (0.6176, 0.6179, 0.1624, 0.1365, 0.432),
            (0.6100, 0.6162, 0.2336, 0.1909, 0.040),
            (0.4445, 0.4451, 0.3788, 0.3767, 0.024),
        ]

        for sample in samples {
            var recognizer = TwoFingerSwipeRecognizer()
            XCTAssertFalse(
                recognizer.process(
                    frame(x: sample.startX, y: sample.startY, at: 1.00)
                )
            )
            XCTAssertFalse(
                recognizer.process(
                    frame(
                        x: sample.endX,
                        y: sample.endY,
                        at: 1.00 + sample.duration
                    )
                )
            )
        }
    }

    func testParsesNormalizedCoordinatesAndOptionState() {
        var bytes = [UInt8](repeating: 0, count: TouchFrame.bytesPerTouch * 2)
        bytes.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(
                of: Float(0.20),
                toByteOffset: TouchFrame.normalizedXOffset,
                as: Float.self
            )
            buffer.storeBytes(
                of: Float(0.30),
                toByteOffset: TouchFrame.normalizedYOffset,
                as: Float.self
            )
            let second = TouchFrame.bytesPerTouch
            buffer.storeBytes(
                of: Float(0.40),
                toByteOffset: second + TouchFrame.normalizedXOffset,
                as: Float.self
            )
            buffer.storeBytes(
                of: Float(0.50),
                toByteOffset: second + TouchFrame.normalizedYOffset,
                as: Float.self
            )
        }

        let frame = bytes.withUnsafeBytes { buffer in
            TouchFrame.parse(
                touches: buffer.baseAddress,
                count: 2,
                timestamp: 12.5,
                optionKeyDown: true
            )
        }

        XCTAssertEqual(frame.fingerCount, 2)
        XCTAssertEqual(frame.meanNormalizedX, 0.30, accuracy: 0.0001)
        XCTAssertEqual(frame.meanNormalizedY, 0.40, accuracy: 0.0001)
        XCTAssertEqual(frame.timestamp, 12.5)
        XCTAssertTrue(frame.optionKeyDown)
    }

    func testInvalidTouchCountResetsTheFrame() {
        var bytes = [UInt8](repeating: 0, count: TouchFrame.bytesPerTouch)
        let frame = bytes.withUnsafeMutableBytes { buffer in
            TouchFrame.parse(
                touches: buffer.baseAddress,
                count: Int32(TouchFrame.maximumTouches + 1),
                timestamp: 12.5
            )
        }

        XCTAssertEqual(frame.fingerCount, 0)
    }
}

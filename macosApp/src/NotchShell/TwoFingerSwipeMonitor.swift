import Foundation

/// 把触控板接触帧转换成一次主线程回调。
@MainActor
final class TwoFingerSwipeMonitor {
    private let source: any MultitouchContactSourceProtocol
    private let onSwipe: @MainActor @Sendable () -> Void
    private let recognizer: SwipeRecognizerBox
    private(set) var startResult: MultitouchStartResult?

    init(
        source: any MultitouchContactSourceProtocol = MultitouchContactSource(),
        configuration: TwoFingerSwipeConfiguration = .init(),
        onSwipe: @escaping @MainActor @Sendable () -> Void
    ) {
        self.source = source
        self.onSwipe = onSwipe
        recognizer = SwipeRecognizerBox(configuration: configuration)
    }

    @discardableResult
    func start() -> MultitouchStartResult {
        if let startResult {
            return startResult
        }

        let recognizer = recognizer
        let onSwipe = onSwipe
        let result = source.start { frame in
            guard let match = recognizer.process(frame) else { return }
            NSLog(
                "Option + 双指下滑识别成功：distance=%.3f horizontal=%.3f duration=%.3f velocity=%.3f",
                match.downwardTravel,
                match.horizontalDeviation,
                match.duration,
                match.velocity
            )
            Task { @MainActor in
                onSwipe()
            }
        }
        startResult = result
        return result
    }

    func stop() {
        source.stop()
        startResult = nil
    }
}

/// 给后台接触回调使用的识别器状态。
private final class SwipeRecognizerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var recognizer: TwoFingerSwipeRecognizer

    init(configuration: TwoFingerSwipeConfiguration) {
        recognizer = TwoFingerSwipeRecognizer(configuration: configuration)
    }

    func process(_ frame: TouchFrame) -> TwoFingerSwipeMatch? {
        lock.withLock {
            guard recognizer.process(frame) else { return nil }
            return recognizer.lastMatch
        }
    }
}

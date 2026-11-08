import Foundation

/// 一帧触控板接触数据。
///
/// 坐标来自私有框架的归一化坐标。\n/// 真机标定显示，从触控板上边缘滑到下边缘时，纵坐标减少。
struct TouchFrame: Equatable, Sendable {
    let fingerCount: Int
    let meanNormalizedX: Double
    let meanNormalizedY: Double
    let timestamp: TimeInterval
    let optionKeyDown: Bool

    init(
        fingerCount: Int,
        meanNormalizedX: Double,
        meanNormalizedY: Double,
        timestamp: TimeInterval,
        optionKeyDown: Bool = false
    ) {
        self.fingerCount = fingerCount
        self.meanNormalizedX = meanNormalizedX
        self.meanNormalizedY = meanNormalizedY
        self.timestamp = timestamp
        self.optionKeyDown = optionKeyDown
    }

    static let bytesPerTouch = 96
    static let normalizedXOffset = 32
    static let normalizedYOffset = 36
    static let maximumTouches = 16

    /// 从私有框架的 `MTTouch` 数组构造一帧。
    ///
    /// `MTTouch` 的公开逆向布局在本机是 96 字节。
    /// 这里只读取 `normalized.pos.x/y`，不调用会崩溃的设备属性访问器。
    static func parse(
        touches: UnsafeRawPointer?,
        count: Int32,
        timestamp: TimeInterval,
        optionKeyDown: Bool = false
    ) -> TouchFrame {
        let fingerCount = Int(count)
        guard fingerCount >= 0,
              fingerCount <= maximumTouches,
              fingerCount > 0,
              let touches
        else {
            return TouchFrame(
                fingerCount: 0,
                meanNormalizedX: 0,
                meanNormalizedY: 0,
                timestamp: timestamp,
                optionKeyDown: optionKeyDown
            )
        }

        var sumX = 0.0
        var sumY = 0.0
        for index in 0..<fingerCount {
            let base = index * bytesPerTouch
            let x = touches.load(fromByteOffset: base + normalizedXOffset, as: Float.self)
            let y = touches.load(fromByteOffset: base + normalizedYOffset, as: Float.self)
            guard x.isFinite, y.isFinite else {
                return TouchFrame(
                    fingerCount: 0,
                    meanNormalizedX: 0,
                    meanNormalizedY: 0,
                    timestamp: timestamp,
                    optionKeyDown: optionKeyDown
                )
            }
            sumX += Double(x)
            sumY += Double(y)
        }

        return TouchFrame(
            fingerCount: fingerCount,
            meanNormalizedX: sumX / Double(fingerCount),
            meanNormalizedY: sumY / Double(fingerCount),
            timestamp: timestamp,
            optionKeyDown: optionKeyDown
        )
    }
}

/// Option + 双指下滑的识别门槛。
///
/// 这些值是可测试的起点，不等于真机标定结果。
/// 真机结果由 issue #407 回填，并据此调整。
struct TwoFingerSwipeConfiguration: Equatable, Sendable {
    var minimumVerticalTravel = 0.15
    var maximumHorizontalTravel = 0.15
    var minimumDuration: TimeInterval = 0.03
    var maximumDuration: TimeInterval = 0.45
    var minimumVelocity = 0.70
    var cooldown: TimeInterval = 0.60
}

/// 一次有效下滑的触发指标。用于真机标定日志。
struct TwoFingerSwipeMatch: Equatable, Sendable {
    let downwardTravel: Double
    let horizontalDeviation: Double
    let duration: TimeInterval
    let velocity: Double
}

/// Option + 双指下滑识别器。
///
/// 识别器是纯值类型。接触回调线程只在锁内调用 `process`。
/// 一次接触段最多产生一个触发结果。
struct TwoFingerSwipeRecognizer: Sendable {
    let configuration: TwoFingerSwipeConfiguration

    private var startX = 0.0
    private var startY = 0.0
    private var startTimestamp: TimeInterval = 0
    private var maximumHorizontalDeviation = 0.0
    private var isTracking = false
    private var isRejected = false
    private var didTrigger = false
    private var lastTriggerTimestamp = -Double.infinity
    private(set) var lastMatch: TwoFingerSwipeMatch?

    init(configuration: TwoFingerSwipeConfiguration = .init()) {
        self.configuration = configuration
    }

    /// 处理一帧，并在识别到一次有效下滑时返回 true。
    mutating func process(_ frame: TouchFrame) -> Bool {
        guard frame.fingerCount == 2,
              frame.optionKeyDown,
              frame.timestamp.isFinite
        else {
            resetContact()
            return false
        }

        if !isTracking {
            isTracking = true
            startX = frame.meanNormalizedX
            startY = frame.meanNormalizedY
            startTimestamp = frame.timestamp
            maximumHorizontalDeviation = 0
            isRejected = false
            didTrigger = false
        }

        let elapsed = frame.timestamp - startTimestamp
        guard elapsed >= 0, elapsed <= configuration.maximumDuration else {
            isRejected = true
            return false
        }

        let horizontalDeviation = abs(frame.meanNormalizedX - startX)
        maximumHorizontalDeviation = max(maximumHorizontalDeviation, horizontalDeviation)
        guard maximumHorizontalDeviation <= configuration.maximumHorizontalTravel else {
            isRejected = true
            return false
        }

        let downwardTravel = startY - frame.meanNormalizedY
        guard elapsed >= configuration.minimumDuration,
              downwardTravel >= configuration.minimumVerticalTravel,
              !isRejected,
              !didTrigger
        else {
            return false
        }

        guard frame.timestamp >= lastTriggerTimestamp + configuration.cooldown else {
            // 冷却期里的新手势不能排队。等用户松手后再开始下一次接触段。
            isRejected = true
            return false
        }

        let velocity = downwardTravel / elapsed
        guard velocity >= configuration.minimumVelocity else {
            return false
        }

        didTrigger = true
        lastTriggerTimestamp = frame.timestamp
        lastMatch = TwoFingerSwipeMatch(
            downwardTravel: downwardTravel,
            horizontalDeviation: maximumHorizontalDeviation,
            duration: elapsed,
            velocity: velocity
        )
        return true
    }

    private mutating func resetContact() {
        isTracking = false
        isRejected = false
        didTrigger = false
        maximumHorizontalDeviation = 0
    }
}

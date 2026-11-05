import XCTest
@testable import Covio

/// `IdleSleepTimeoutCache` 的 C ABI 导出断言。
///
/// 实现只有一份，在 Rust core 里。这个文件是导出冒烟测试：
/// 确认可选整数出得来、共享 TTL 常量读得到。
///
/// `pmset -g` 要几十毫秒，`Engine.tick()` 每次调用都会问，所以缓存 60 秒。
/// 四条断言都同时看结果和读取次数：只看结果分不出「命中缓存」和「又读了一次」。
final class SleepControllerTests: XCTestCase {
    private let ttl = IdleSleepTimeoutCache.companion.DEFAULT_TTL_MILLIS

    func testCacheReusesTheTimeoutInsideTheTTL() {
        var now: Int64 = 10_000
        var reads = 0
        let cache = IdleSleepTimeoutCache(
            clock: { now },
            timeoutReader: {
                reads += 1
                return 120
            },
            ttlMillis: ttl
        )

        XCTAssertEqual(cache.get()?.int64Value, 120)
        now += 59_999
        XCTAssertEqual(cache.get()?.int64Value, 120)
        XCTAssertEqual(reads, 1)
    }

    func testCacheReadsAgainAfterTheTTL() {
        var now: Int64 = 10_000
        var reads = 0
        let cache = IdleSleepTimeoutCache(
            clock: { now },
            timeoutReader: {
                reads += 1
                return reads == 1 ? 120 : 300
            },
            ttlMillis: ttl
        )

        XCTAssertEqual(cache.get()?.int64Value, 120)
        now += 60_000
        XCTAssertEqual(cache.get()?.int64Value, 300)
        XCTAssertEqual(reads, 2)
    }

    func testInvalidateForcesTheNextRead() {
        var reads = 0
        let cache = IdleSleepTimeoutCache(
            clock: { 0 },
            timeoutReader: {
                reads += 1
                return Int64(reads * 60)
            },
            ttlMillis: ttl
        )

        XCTAssertEqual(cache.get()?.int64Value, 60)
        XCTAssertEqual(cache.get()?.int64Value, 60)
        cache.invalidate()
        XCTAssertEqual(cache.get()?.int64Value, 120)
        XCTAssertEqual(reads, 2)
    }

    /// 系统与屏幕使用不同断言。每一步都回读，退出时释放。
    func testSystemAndDisplayAssertionsRoundTripThroughIOKit() {
        let controller = MacSleepController(
            clock: { 0 },
            timeoutReader: { 600 }
        )
        defer { _ = controller.applyIdleSleepPrevention(prevention: .none) }

        let system = controller.applyIdleSleepPrevention(prevention: .system)
        XCTAssertTrue(system.success, system.error ?? "")
        XCTAssertEqual(system.actual, .system)
        XCTAssertEqual(controller.readIdleSleepPrevention(), .system)
        XCTAssertNil(controller.systemIdleSleepTimeoutSeconds())

        let display = controller.applyIdleSleepPrevention(prevention: .systemAndDisplay)
        XCTAssertTrue(display.success, display.error ?? "")
        XCTAssertEqual(display.actual, .systemAndDisplay)
        XCTAssertEqual(controller.readIdleSleepPrevention(), .systemAndDisplay)

        let released = controller.applyIdleSleepPrevention(prevention: .none)
        XCTAssertTrue(released.success, released.error ?? "")
        XCTAssertEqual(released.actual, .none)
        XCTAssertEqual(controller.readIdleSleepPrevention(), .none)
        XCTAssertEqual(controller.systemIdleSleepTimeoutSeconds()?.int64Value, 600)
    }

    /// `pmset` 读不到时是 `nil`，不是异常。
    /// `nil` 也要缓存，否则每次 `tick()` 都会再起一个进程去撞同一个失败。
    func testUnavailableTimeoutIsCachedAsUnavailable() {
        var reads = 0
        let cache = IdleSleepTimeoutCache(
            clock: { 0 },
            timeoutReader: {
                reads += 1
                return nil
            },
            ttlMillis: ttl
        )

        XCTAssertNil(cache.get())
        XCTAssertNil(cache.get())
        XCTAssertEqual(reads, 1)
    }

    /// TTL 的默认值不导出（ADR-001 实测 18），Swift 侧必须显式传。
    /// 这条断言守住「显式传的那个值就是 60 秒」。
    func testTheDefaultTTLIsSixtySeconds() {
        XCTAssertEqual(ttl, 60_000)
    }
}

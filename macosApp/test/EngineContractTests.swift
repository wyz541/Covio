import XCTest
@testable import Covio

/// 引擎行为基线。
///
/// 这是 Rust core engine 行为的 Swift 边界镜像。
/// Engine 只有一份 Rust 实现。
/// 这里证明从 Swift 调用时行为不变。
@MainActor
final class EngineContractTests: XCTestCase {

    // MARK: - 唤醒日志

    /// 对应 `start scans wake log and updates dark wake status`。
    func testStartScansWakeLogAndUpdatesDarkWakeStatus() {
        let event = WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "RTC")
        let store = WakeLogStore(WakeLogSnapshot(events: [event], darkWakeCount24h: 1))
        let fixture = Fixture(wakeLogReader: store)
        fixture.power.value = BatteryStatus(percent: 80, state: .discharging, remainingSeconds: nil)
        fixture.engine.start()

        XCTAssertEqual(store.reads, 1)
        let status = fixture.engine.currentState.darkWake
        XCTAssertTrue(status.available)
        XCTAssertEqual(status.lastAtEpochSeconds?.int64Value, 1_000)
        XCTAssertEqual(status.lastKind, .dark)
        XCTAssertEqual(status.lastReason, "RTC")
        XCTAssertEqual(status.count24h, 1)
    }

    /// 对应 `dark wake does not restore sleep now restrictions`。
    func testDarkWakeDoesNotRestoreSleepNowRestrictions() {
        let store = WakeLogStore(
            WakeLogSnapshot(events: [WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "Initial")], darkWakeCount24h: 1)
        )
        let fixture = Fixture(wakeLogReader: store)
        fixture.privileged.match = true
        fixture.power.value = BatteryStatus(percent: 80, state: .discharging, remainingSeconds: nil)
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(available: false)
        _ = fixture.engine.setLidSleepAvailable(available: false)
        fixture.engine.sleepNow()
        XCTAssertTrue(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)

        store.snapshot = WakeLogSnapshot(
            events: [WakeEvent(kind: .dark, atEpochSeconds: 2_000, reason: "RTC")],
            darkWakeCount24h: 2
        )
        fixture.watcher.wake()

        XCTAssertTrue(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)
        XCTAssertEqual(fixture.engine.currentState.darkWake.lastAtEpochSeconds?.int64Value, 2_000)
    }

    /// 对应 `full wake restores sleep now restrictions`。
    func testFullWakeRestoresSleepNowRestrictions() {
        let store = WakeLogStore(
            WakeLogSnapshot(events: [WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "Initial")], darkWakeCount24h: 1)
        )
        let fixture = Fixture(wakeLogReader: store)
        fixture.privileged.match = true
        fixture.power.value = BatteryStatus(percent: 80, state: .discharging, remainingSeconds: nil)
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(available: false)
        _ = fixture.engine.setLidSleepAvailable(available: false)
        fixture.engine.sleepNow()

        store.snapshot = WakeLogSnapshot(
            events: [WakeEvent(kind: .full, atEpochSeconds: 2_000, reason: "UserActivity")],
            darkWakeCount24h: 1
        )
        fixture.watcher.wake()

        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertFalse(fixture.engine.currentState.lidSleepAvailable)
    }

    /// 对应 `overlapping wake signals share one log scan`。
    func testOverlappingWakeSignalsShareOneLogScan() {
        let store = WakeLogStore(
            WakeLogSnapshot(events: [WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "Initial")], darkWakeCount24h: 1)
        )
        let queued = QueuedExecutor()
        let fixture = Fixture(wakeLogReader: store, wakeScanExecutor: queued.executor)
        fixture.engine.start()
        XCTAssertEqual(queued.count, 1)
        queued.runNext()
        XCTAssertEqual(store.reads, 1)

        store.snapshot = WakeLogSnapshot(
            events: [WakeEvent(kind: .dark, atEpochSeconds: 2_000, reason: "RTC")],
            darkWakeCount24h: 2
        )
        fixture.watcher.wake()
        fixture.watcher.wake()

        XCTAssertEqual(queued.count, 1)
        queued.runNext()
        XCTAssertEqual(store.reads, 2)
    }

    /// 状态读取不能在唤醒日志扫描持有引擎时等待。
    func testCurrentStateDoesNotWaitForTheWakeLogScan() {
        let reader = BlockingWakeLogReader()
        let queued = QueuedExecutor()
        let fixture = Fixture(
            wakeLogReader: reader,
            wakeScanExecutor: queued.executor
        )
        let scanFinished = expectation(description: "wake scan finished")
        fixture.engine.start()
        DispatchQueue.global(qos: .userInteractive).async {
            queued.runNext()
            scanFinished.fulfill()
        }
        XCTAssertEqual(reader.readStarted.wait(timeout: .now() + 2), .success)

        let startedAt = Date()
        let state = fixture.engine.currentState
        let elapsed = Date().timeIntervalSince(startedAt)
        reader.release.signal()
        wait(for: [scanFinished], timeout: 2)

        XCTAssertTrue(state.darkWake.scanning)
        XCTAssertLessThan(elapsed, 0.5)
    }

    /// 唤醒日志扫描占用引擎时，周期 tick 必须让出本轮。
    func testTickSkipsWhileTheWakeLogScanOwnsTheEngine() {
        let reader = BlockingWakeLogReader()
        let queued = QueuedExecutor()
        let fixture = Fixture(
            wakeLogReader: reader,
            wakeScanExecutor: queued.executor
        )
        let scanFinished = expectation(description: "wake scan finished")
        fixture.engine.start()
        DispatchQueue.global(qos: .userInteractive).async {
            queued.runNext()
            scanFinished.fulfill()
        }
        XCTAssertEqual(reader.readStarted.wait(timeout: .now() + 2), .success)

        let startedAt = Date()
        let ran = fixture.engine.tick(nowMillis: fixture.nowMillis())
        let elapsed = Date().timeIntervalSince(startedAt)
        reader.release.signal()
        wait(for: [scanFinished], timeout: 2)

        XCTAssertFalse(ran)
        XCTAssertLessThan(elapsed, 0.5)
    }

    /// 对应 `wake scan retries an unchanged log snapshot`。
    func testWakeScanRetriesAnUnchangedLogSnapshot() {
        let initial = WakeLogSnapshot(
            events: [WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "Initial")],
            darkWakeCount24h: 1
        )
        let updated = WakeLogSnapshot(
            events: [WakeEvent(kind: .dark, atEpochSeconds: 2_000, reason: "RTC")],
            darkWakeCount24h: 2
        )
        var reads = 0
        let store = WakeLogStore()
        store.provider = { _ in
            reads += 1
            return reads <= 2 ? initial : updated
        }
        let fixture = Fixture(wakeLogReader: store, wakeDelay: { _ in store.delays += 1 })
        fixture.engine.start()
        fixture.watcher.wake()

        XCTAssertEqual(store.reads, 3)
        XCTAssertEqual(store.delays, 2)
        XCTAssertEqual(fixture.engine.currentState.darkWake.lastAtEpochSeconds?.int64Value, 2_000)
    }

    /// 对应 `wake log failure restores sleep now restrictions and marks status unavailable`。
    func testWakeLogFailureRestoresSleepNowRestrictionsAndMarksStatusUnavailable() {
        let store = WakeLogStore(
            WakeLogSnapshot(events: [WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "Initial")], darkWakeCount24h: 1)
        )
        let fixture = Fixture(wakeLogReader: store)
        fixture.privileged.match = true
        fixture.power.value = BatteryStatus(percent: 80, state: .discharging, remainingSeconds: nil)
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(available: false)
        _ = fixture.engine.setLidSleepAvailable(available: false)
        fixture.engine.sleepNow()

        store.snapshot = nil
        fixture.watcher.wake()

        XCTAssertFalse(fixture.engine.currentState.darkWake.available)
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertFalse(fixture.engine.currentState.lidSleepAvailable)
        XCTAssertTrue(fixture.logger.messages.contains { $0.contains("Wake log parsing failed") })
    }

    /// 对应 `wake log refresh is cached for 60 seconds`。
    func testWakeLogRefreshIsCachedForSixtySeconds() {
        var nowMillis: Int64 = 1_000_000
        let store = WakeLogStore(
            WakeLogSnapshot(events: [WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "Initial")], darkWakeCount24h: 1)
        )
        let fixture = Fixture(wakeLogReader: store, wakeCacheNowMillis: { nowMillis })
        fixture.power.value = BatteryStatus(percent: 80, state: .discharging, remainingSeconds: nil)
        fixture.engine.start()
        XCTAssertEqual(store.reads, 1)

        fixture.engine.stop()
        store.snapshot = WakeLogSnapshot(
            events: [WakeEvent(kind: .dark, atEpochSeconds: 2_000, reason: "RTC")],
            darkWakeCount24h: 2
        )
        nowMillis += 61_000
        fixture.engine.start()

        XCTAssertEqual(store.reads, 2)
        XCTAssertEqual(fixture.engine.currentState.darkWake.lastAtEpochSeconds?.int64Value, 2_000)
    }

    /// 对应 `new wake event bypasses the cache`。
    func testNewWakeEventBypassesTheCache() {
        let store = WakeLogStore(
            WakeLogSnapshot(events: [WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "Initial")], darkWakeCount24h: 1)
        )
        let fixture = Fixture(wakeLogReader: store)
        fixture.power.value = BatteryStatus(percent: 80, state: .discharging, remainingSeconds: nil)
        fixture.engine.start()

        store.snapshot = WakeLogSnapshot(
            events: [
                WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "Initial"),
                WakeEvent(kind: .full, atEpochSeconds: 2_000, reason: "UserActivity"),
            ],
            darkWakeCount24h: 1
        )
        fixture.watcher.wake()

        XCTAssertEqual(fixture.engine.currentState.darkWake.lastAtEpochSeconds?.int64Value, 2_000)
        XCTAssertEqual(fixture.engine.currentState.darkWake.lastReason, "UserActivity")
    }

    /// 对应 `wake log failure keeps the previous status data`。
    func testWakeLogFailureKeepsThePreviousStatusData() {
        let store = WakeLogStore(
            WakeLogSnapshot(events: [WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "RTC")], darkWakeCount24h: 1)
        )
        let fixture = Fixture(wakeLogReader: store)
        fixture.power.value = BatteryStatus(percent: 80, state: .discharging, remainingSeconds: nil)
        fixture.engine.start()

        store.snapshot = nil
        fixture.watcher.wake()

        let status = fixture.engine.currentState.darkWake
        XCTAssertFalse(status.available)
        XCTAssertEqual(status.lastAtEpochSeconds?.int64Value, 1_000)
        XCTAssertEqual(status.lastReason, "RTC")
        XCTAssertEqual(status.count24h, 1)
    }

    // MARK: - 电池与合盖策略

    /// PowerRuntime 通过独立通道请求合盖保持。
    func testPowerRuntimeHoldsLidSleep() {
        let fixture = Fixture(
            config: AppConfigs.make(lidSleepImmediateOnClose: false)
        )
        fixture.privileged.match = true
        fixture.power.value = BatteryStatus(percent: 80, state: .discharging, remainingSeconds: 3_600)
        fixture.engine.start()

        XCTAssertTrue(fixture.engine.setPowerLidHold(required: true))
        XCTAssertFalse(fixture.engine.currentState.lidSleepAvailable)
        XCTAssertTrue(fixture.privileged.disableSleepValues.contains(true))
    }

    /// 对应 `manual lid hold is released on request`。
    func testManualLidHoldIsReleasedOnRequest() {
        let fixture = Fixture(config: AppConfigs.make(lidSleepImmediateOnClose: false))
        fixture.privileged.match = true
        fixture.power.value = BatteryStatus(percent: 80, state: .discharging, remainingSeconds: 3_600)
        fixture.engine.start()

        fixture.engine.setManualLidSleepAvailable(available: false)
        XCTAssertFalse(fixture.engine.currentState.lidSleepAvailable)

        fixture.engine.setManualLidSleepAvailable(available: true)
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)
    }

    /// 对应 `low battery policy overrides battery lid hold`。
    func testLowBatteryPolicyOverridesBatteryLidHold() {
        let fixture = Fixture(
            config: AppConfigs.make(
                lowBatteryCapacity: 10,
                disableLidSleepOnBattery: true,
                lidSleepImmediateOnClose: false
            )
        )
        fixture.privileged.match = true
        fixture.power.value = BatteryStatus(percent: 5, state: .discharging, remainingSeconds: 3_600)
        fixture.engine.start()

        XCTAssertEqual(fixture.sleep.sleepCalls, 1)
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)
        XCTAssertFalse(fixture.privileged.disableSleepValues.contains(true))
    }

    /// 合盖写入失败时保持睡眠可用并返回失败。
    func testHelperFailureKeepsLidSleepAvailable() {
        let fixture = Fixture(config: AppConfigs.make(lidSleepImmediateOnClose: false))
        fixture.privileged.match = true
        fixture.privileged.disableSleepResult = false
        fixture.power.value = BatteryStatus(percent: 80, state: .discharging, remainingSeconds: 3_600)
        fixture.engine.start()

        XCTAssertFalse(fixture.engine.setPowerLidHold(required: true))
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)
    }

    /// 对应 `low battery capacity triggers sleep only while discharging`。
    func testLowBatteryCapacityTriggersSleepOnlyWhileDischarging() {
        let fixture = Fixture(config: AppConfigs.make(lowBatteryCapacity: 6))
        fixture.power.value = BatteryStatus(percent: 6, state: .discharging, remainingSeconds: nil)
        fixture.engine.start()
        XCTAssertEqual(fixture.sleep.sleepCalls, 1)
        fixture.power.value = BatteryStatus(percent: 5, state: .charging, remainingSeconds: nil)
        fixture.power.emit()
        XCTAssertEqual(fixture.sleep.sleepCalls, 1)
    }

    /// 对应 `low remaining time triggers sleep`。
    func testLowRemainingTimeTriggersSleep() {
        let fixture = Fixture(config: AppConfigs.make(lowTimeRemainingMinutes: 10))
        fixture.power.value = BatteryStatus(percent: 50, state: .discharging, remainingSeconds: 600)
        fixture.engine.start()
        XCTAssertEqual(fixture.sleep.sleepCalls, 1)
    }

    /// 充电规则只管理空闲睡眠。合盖策略由 PowerRuntime 管理。
    func testChargingRulePreventsAndRestoresIdleSleep() {
        let fixture = Fixture(
            config: AppConfigs.make(disableIdleSleepInCharging: true)
        )
        fixture.power.value = BatteryStatus(percent: 80, state: .charging, remainingSeconds: nil)
        fixture.engine.start()
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)

        fixture.power.value = BatteryStatus(percent: 75, state: .discharging, remainingSeconds: 3_600)
        fixture.power.emit()
        XCTAssertTrue(fixture.engine.currentState.idleSleepAvailable)
    }

    /// Helper 不可用时，PowerRuntime 的合盖请求被拒绝。
    func testPowerLidHoldIsSkippedWhenHelperIsNotInstalled() {
        let fixture = Fixture()
        fixture.privileged.match = false
        fixture.power.value = BatteryStatus(percent: 80, state: .charging, remainingSeconds: nil)
        fixture.engine.start()

        XCTAssertFalse(fixture.engine.setPowerLidHold(required: true))
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)
        XCTAssertTrue(fixture.privileged.disableSleepValues.isEmpty)
    }

    /// 对应 `start does not touch disablesleep when the helper is not installed`。
    func testStartDoesNotTouchDisableSleepWhenHelperIsNotInstalled() {
        let fixture = Fixture()
        fixture.power.value = BatteryStatus(percent: 90, state: .discharging, remainingSeconds: nil)
        fixture.privileged.match = false
        fixture.engine.start()
        XCTAssertTrue(fixture.privileged.disableSleepValues.isEmpty)
    }

    // MARK: - 合盖与空闲

    /// 对应 `lid close sleeps immediately when available`。
    func testLidCloseSleepsImmediatelyWhenAvailable() {
        let fixture = Fixture(config: AppConfigs.make(lidSleepImmediateOnClose: true))
        fixture.power.value = BatteryStatus(percent: 80, state: .discharging, remainingSeconds: nil)
        fixture.engine.start()
        fixture.lid.state = .closed
        fixture.lid.emit(.closed)
        XCTAssertEqual(fixture.sleep.sleepCalls, 1)
    }

    /// 对应 `lid close only turns display off while sleep is prevented`。
    func testLidCloseOnlyTurnsDisplayOffWhileSleepIsPrevented() {
        let fixture = Fixture(config: AppConfigs.make(lidSleepImmediateOnClose: false))
        fixture.privileged.match = true
        fixture.power.value = BatteryStatus(percent: 80, state: .charging, remainingSeconds: nil)
        fixture.engine.start()
        _ = fixture.engine.setLidSleepAvailable(available: false)
        fixture.lid.emit(.closed)
        XCTAssertEqual(fixture.sleep.displayCalls, 1)
        XCTAssertEqual(fixture.sleep.sleepCalls, 0)
    }

    func testExperimentalDisplayPathCanSuppressThePublicLidDisplayOff() {
        let fixture = Fixture(config: AppConfigs.make(lidSleepImmediateOnClose: false))
        fixture.privileged.match = true
        fixture.power.value = BatteryStatus(percent: 80, state: .charging, remainingSeconds: nil)
        fixture.engine.start()
        _ = fixture.engine.setLidSleepAvailable(available: false)
        fixture.engine.setPowerLidDisplayOffEnabled(enabled: false)

        fixture.lid.emit(.closed)

        XCTAssertEqual(fixture.sleep.displayCalls, 0)
        XCTAssertEqual(fixture.sleep.sleepCalls, 0)
    }

    func testHelperSafeModeBlocksEveryDisableSleepWrite() {
        let fixture = Fixture()
        fixture.privileged.statusValue = .identityMismatch

        XCTAssertFalse(fixture.engine.setLidSleepAvailable(available: false))
        XCTAssertFalse(fixture.engine.setLidSleepAvailable(available: true))
        XCTAssertTrue(fixture.privileged.disableSleepValues.isEmpty)
    }

    /// 对应 `idle compensation sleeps after system timeout`。
    func testIdleCompensationSleepsAfterSystemTimeout() {
        let fixture = Fixture(config: AppConfigs.make(lidSleepImmediateOnClose: false))
        fixture.privileged.match = true
        fixture.power.value = BatteryStatus(percent: 80, state: .charging, remainingSeconds: nil)
        fixture.engine.start()
        _ = fixture.engine.setLidSleepAvailable(available: false)
        fixture.sleep.timeoutSeconds = 60
        fixture.idle.seconds = 61
        fixture.engine.tick(nowMillis: fixture.nowMillis())
        XCTAssertEqual(fixture.sleep.sleepCalls, 1)
    }

    /// 对应 `cancel timer restores idle availability`。
    func testCancelTimerRestoresIdleAvailability() {
        var now: Int64 = 1_000
        let fixture = Fixture(clock: { now })
        fixture.engine.scheduleCancelIdle(afterSeconds: 300)
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        now += 301_000
        fixture.engine.tick(nowMillis: now)
        XCTAssertTrue(fixture.engine.currentState.idleSleepAvailable)
    }

    /// 对应 `display idle hold exposes the readback level`。
    func testDisplayIdleHoldExposesTheReadbackLevel() {
        let fixture = Fixture()
        fixture.engine.start()

        XCTAssertTrue(fixture.engine.setIdleSleepPrevention(prevention: .systemAndDisplay))

        let state = fixture.engine.currentState
        XCTAssertFalse(state.idleSleepAvailable)
        XCTAssertEqual(state.idleSleepPrevention, .systemAndDisplay)
        XCTAssertEqual(fixture.sleep.prevention, .systemAndDisplay)
    }

    /// 对应 `assertion failure leaves the real state available and records the error`。
    func testAssertionFailureLeavesTheRealStateAvailableAndRecordsTheError() {
        let fixture = Fixture()
        fixture.engine.start()
        fixture.sleep.failAssertion = true

        XCTAssertFalse(fixture.engine.setIdleSleepPrevention(prevention: .system))

        let state = fixture.engine.currentState
        XCTAssertTrue(state.idleSleepAvailable)
        XCTAssertEqual(state.idleSleepPrevention, .none)
        XCTAssertEqual(state.lastError, "assertion failure")
    }

    /// 对应 `idle timer expiry keeps a separate manual hold`。
    func testIdleTimerExpiryKeepsASeparateManualHold() {
        var now: Int64 = 1_000
        let fixture = Fixture(clock: { now })
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(available: false)
        fixture.engine.scheduleCancelIdle(afterSeconds: 300)

        now += 301_000
        fixture.engine.tick(nowMillis: now)

        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertEqual(fixture.engine.currentState.idleSleepPrevention, .system)
    }

    /// 对应 `manual idle off leaves the charging rule active`。
    func testManualIdleOffLeavesTheChargingRuleActive() {
        let fixture = Fixture(config: AppConfigs.make(disableIdleSleepInCharging: true))
        fixture.power.value = BatteryStatus(percent: 80, state: .charging, remainingSeconds: nil)
        fixture.engine.start()
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)

        fixture.engine.setIdleSleepAvailable(available: false)
        fixture.engine.setIdleSleepAvailable(available: true)

        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertEqual(fixture.engine.currentState.idleSleepPrevention, .system)
    }

    /// 对应 `sleep now temporarily restores restrictions and wake restores them`。
    func testSleepNowTemporarilyRestoresRestrictionsAndWakeRestoresThem() {
        let fixture = Fixture()
        fixture.privileged.match = true
        fixture.power.value = BatteryStatus(percent: 90, state: .charging, remainingSeconds: nil)
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(available: false)
        _ = fixture.engine.setLidSleepAvailable(available: false)
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)

        fixture.engine.sleepNow()
        XCTAssertEqual(fixture.sleep.sleepCalls, 1)
        XCTAssertTrue(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)

        fixture.watcher.wake()
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertFalse(fixture.engine.currentState.lidSleepAvailable)
    }

    func testPowerLidHoldFailsWhenSleepProtectionIsOff() {
        let fixture = Fixture(config: AppConfigs.make(enabled: false))
        fixture.privileged.match = true
        fixture.engine.start()

        XCTAssertFalse(fixture.engine.setPowerLidHold(required: true))
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)
        XCTAssertFalse(fixture.privileged.sleepDisabled)
    }

    func testPowerLidHoldFailsWhenTheHelperDoesNotApplyTheSystemState() {
        let fixture = Fixture()
        fixture.privileged.match = true
        fixture.privileged.appliesDisableSleepState = false
        fixture.engine.start()

        XCTAssertFalse(fixture.engine.setPowerLidHold(required: true))
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)
        XCTAssertFalse(fixture.privileged.sleepDisabled)
    }

    func testPowerLidHoldReverifiesAnExistingClaim() {
        let fixture = Fixture()
        fixture.privileged.match = true
        fixture.engine.start()
        XCTAssertTrue(fixture.engine.setPowerLidHold(required: true))
        XCTAssertFalse(fixture.engine.currentState.lidSleepAvailable)

        fixture.privileged.sleepDisabled = false
        fixture.privileged.covioOwned = false

        XCTAssertFalse(fixture.engine.setPowerLidHold(required: true))
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)
    }

    /// 对应 `helper lease expiry updates lid availability`。
    func testHelperLeaseExpiryUpdatesLidAvailability() {
        var now: Int64 = 1_000
        let fixture = Fixture(clock: { now })
        fixture.privileged.match = true
        fixture.engine.start()
        _ = fixture.engine.setLidSleepAvailable(available: false)
        XCTAssertFalse(fixture.engine.currentState.lidSleepAvailable)

        fixture.privileged.sleepDisabled = false
        now += 5_000
        fixture.engine.tick(nowMillis: now)

        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)
        XCTAssertEqual(fixture.engine.currentState.lidLeaseStatus.activeLeaseCount, 0)
    }

    /// 对应 `cancel timer restores lid availability`。
    func testCancelTimerRestoresLidAvailability() {
        var now: Int64 = 5_000
        let fixture = Fixture(clock: { now })
        fixture.privileged.match = true
        fixture.engine.scheduleCancelLid(afterSeconds: 600)
        XCTAssertFalse(fixture.engine.currentState.lidSleepAvailable)
        now += 601_000
        fixture.engine.tick(nowMillis: now)
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)
    }

    // MARK: - 停止

    /// 对应 `stop restores sleep availability and clears disablesleep`。
    func testStopRestoresSleepAvailabilityAndClearsDisableSleep() {
        let fixture = Fixture(config: AppConfigs.make(lidSleepImmediateOnClose: false))
        fixture.privileged.match = true
        fixture.power.value = BatteryStatus(percent: 90, state: .charging, remainingSeconds: nil)
        fixture.engine.start()
        fixture.engine.setIdleSleepAvailable(available: false)
        _ = fixture.engine.setLidSleepAvailable(available: false)
        XCTAssertTrue(fixture.privileged.disableSleepValues.contains(true))

        fixture.engine.stop()
        XCTAssertTrue(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertTrue(fixture.engine.currentState.lidSleepAvailable)
        XCTAssertFalse(fixture.sleep.prevented)
        XCTAssertEqual(fixture.privileged.disableSleepValues.last, false)
    }

    /// 对应 `start removes stale disablesleep flag when no charging policy needs it`。
    func testStartRemovesStaleDisableSleepFlagWhenNoChargingPolicyNeedsIt() {
        let fixture = Fixture()
        fixture.power.value = BatteryStatus(percent: 90, state: .discharging, remainingSeconds: nil)
        fixture.privileged.match = true
        fixture.engine.start()
        XCTAssertTrue(fixture.privileged.disableSleepValues.contains(false))
    }
}

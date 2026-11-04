import XCTest
@testable import Covio

@MainActor
final class PowerRuntimeTests: XCTestCase {
    private var fixture: Fixture!
    private var observation: FakePowerObservationSource!
    private var runtime: PowerRuntime!
    private var historyDirectory: URL!
    private var historyStore: PowerHistoryStore!
    private var brightnessBackend: FakeClosedLidBrightnessBackend!
    private var brightnessStore: FakeClosedLidBrightnessRecoveryStore!

    override func setUp() {
        super.setUp()
        historyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-power-history-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        historyStore = PowerHistoryStore.companion.create(
            path: historyDirectory.appendingPathComponent("history.json").path
        )
        brightnessBackend = FakeClosedLidBrightnessBackend(brightness: 0.6)
        brightnessStore = FakeClosedLidBrightnessRecoveryStore()
        fixture = Fixture()
        fixture.privileged.match = false
        fixture.engine.start()
        observation = FakePowerObservationSource()
    }

    override func tearDown() {
        runtime?.stop()
        fixture?.engine.stop()
        runtime = nil
        observation = nil
        fixture = nil
        if let historyDirectory {
            try? FileManager.default.removeItem(at: historyDirectory)
        }
        historyDirectory = nil
        historyStore = nil
        brightnessBackend = nil
        brightnessStore = nil
        super.tearDown()
    }

    func testAdapterRuleCreatesAnActualIdleAssertion() {
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig(keepAwakeOnAdapter: true))

        runtime.start()

        XCTAssertTrue(runtime.decision.automaticRuleApplied)
        XCTAssertTrue(runtime.decision.preventUserIdleSystemSleep)
        XCTAssertEqual(fixture.sleep.prevention, .system)
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertTrue(runtime.recentHistory.contains { $0.kind == .holdStarted })
    }

    func testAdapterClosedLidPolicyCreatesAnAutomaticLidLease() {
        fixture.privileged.match = true
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(
            config: makeConfig(),
            displayConfig: makeDisplayConfig(policy: .adapter)
        )

        runtime.start()

        XCTAssertTrue(runtime.decision.preventLidSleep)
        XCTAssertTrue(fixture.privileged.sleepDisabled)
        XCTAssertTrue(runtime.leases.contains { $0.source == .rule && $0.level == .closedLid })

        observation.value = makeObservation(powerState: .discharging, batteryPercent: 70, hasBattery: true)
        runtime.refresh()

        XCTAssertFalse(runtime.decision.preventLidSleep)
        XCTAssertFalse(fixture.privileged.sleepDisabled)
    }

    func testBlackScreenClosedLidPolicyCreatesLidAndDisplayWakeLeases() {
        fixture.privileged.match = true
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime = makeRuntime(
            config: makeConfig(closedLidZeroBrightness: true),
            displayConfig: makeDisplayConfig(policy: .adapter)
        )

        runtime.start()

        XCTAssertTrue(runtime.decision.preventLidSleep)
        XCTAssertTrue(runtime.decision.preventUserIdleDisplaySleep)
        XCTAssertTrue(fixture.privileged.sleepDisabled)
        XCTAssertTrue(runtime.leases.contains { $0.level == .closedLid })
        XCTAssertTrue(runtime.leases.contains { $0.level == .systemAndDisplay })
        XCTAssertEqual(fixture.sleep.prevention, .systemAndDisplay)
    }

    func testDisplayOffClosedLidPolicyDoesNotPreventDisplaySleep() {
        fixture.privileged.match = true
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime = makeRuntime(
            config: makeConfig(closedLidZeroBrightness: false),
            displayConfig: makeDisplayConfig(policy: .adapter, mode: .displayOff)
        )

        runtime.start()

        XCTAssertTrue(runtime.decision.preventLidSleep)
        XCTAssertFalse(runtime.decision.preventUserIdleDisplaySleep)
        XCTAssertTrue(runtime.leases.contains { $0.level == .closedLid })
        XCTAssertFalse(runtime.leases.contains { $0.level == .systemAndDisplay })
        XCTAssertEqual(fixture.sleep.prevention, .system)
    }

    func testBatteryClosedLidPolicyHoldsOnBatteryPower() {
        fixture.privileged.match = true
        observation.value = makeObservation(powerState: .discharging, batteryPercent: 70, hasBattery: true)
        runtime = makeRuntime(
            config: makeConfig(),
            displayConfig: makeDisplayConfig(policy: .battery)
        )

        runtime.start()

        XCTAssertTrue(runtime.decision.preventLidSleep)
        XCTAssertTrue(fixture.privileged.sleepDisabled)
    }

    func testExternalDisplayPausesAutomaticClosedLidLease() {
        fixture.privileged.match = true
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed,
            externalDisplayCount: 1
        )
        runtime = makeRuntime(
            config: makeConfig(),
            displayConfig: makeDisplayConfig(policy: .adapter, pauseWithExternalDisplay: true)
        )

        runtime.start()

        XCTAssertFalse(runtime.decision.preventLidSleep)
        XCTAssertFalse(runtime.decision.preventUserIdleDisplaySleep)
        XCTAssertFalse(fixture.privileged.sleepDisabled)
        XCTAssertTrue(runtime.leases.isEmpty)
    }

    func testSleepPolicyDoesNotCreateAClosedLidLease() {
        fixture.privileged.match = true
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(
            config: makeConfig(),
            displayConfig: makeDisplayConfig(policy: .sleep)
        )

        runtime.start()

        XCTAssertFalse(runtime.decision.preventLidSleep)
        XCTAssertFalse(fixture.privileged.sleepDisabled)
        XCTAssertFalse(runtime.leases.contains { $0.level == .closedLid })
    }

    func testExternalDisplayReleasesAndRestoresTheAutomaticClosedLidLease() {
        fixture.privileged.match = true
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime = makeRuntime(
            config: makeConfig(closedLidZeroBrightness: true),
            displayConfig: makeDisplayConfig(policy: .adapter, pauseWithExternalDisplay: true)
        )
        runtime.start()
        XCTAssertTrue(runtime.decision.preventLidSleep)
        XCTAssertTrue(runtime.decision.preventUserIdleDisplaySleep)

        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed,
            externalDisplayCount: 1
        )
        runtime.refresh()
        XCTAssertFalse(runtime.decision.preventLidSleep)
        XCTAssertFalse(runtime.decision.preventUserIdleDisplaySleep)
        XCTAssertFalse(fixture.privileged.sleepDisabled)

        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime.refresh()
        XCTAssertTrue(runtime.decision.preventLidSleep)
        XCTAssertTrue(runtime.decision.preventUserIdleDisplaySleep)
        XCTAssertTrue(fixture.privileged.sleepDisabled)
    }

    func testOpeningLidReleasesOnlyTheBlackScreenDisplayLease() {
        fixture.privileged.match = true
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime = makeRuntime(
            config: makeConfig(closedLidZeroBrightness: true),
            displayConfig: makeDisplayConfig(policy: .adapter)
        )
        runtime.start()
        XCTAssertTrue(runtime.decision.preventUserIdleDisplaySleep)

        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime.refresh()

        XCTAssertTrue(runtime.decision.preventLidSleep)
        XCTAssertFalse(runtime.decision.preventUserIdleDisplaySleep)
        XCTAssertTrue(runtime.leases.contains { $0.level == .closedLid })
        XCTAssertFalse(runtime.leases.contains { $0.level == .systemAndDisplay })
    }

    func testBlackScreenLeasesExpireAtTheClosedLidTimeCap() {
        var now: Int64 = 1_000
        fixture.privileged.match = true
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime = makeRuntime(
            config: makeConfig(closedLidTimeCapMinutes: 30, closedLidZeroBrightness: true),
            displayConfig: makeDisplayConfig(policy: .adapter),
            nowEpochSeconds: { now }
        )
        runtime.start()
        XCTAssertTrue(runtime.decision.preventLidSleep)
        XCTAssertTrue(runtime.decision.preventUserIdleDisplaySleep)

        now = 2_801
        runtime.refresh()

        XCTAssertFalse(runtime.decision.preventLidSleep)
        XCTAssertFalse(runtime.decision.preventUserIdleDisplaySleep)
        XCTAssertFalse(fixture.privileged.sleepDisabled)
        XCTAssertFalse(runtime.leases.contains { $0.source == .rule && $0.reason == "Closed-lid policy" })
    }

    func testChangingTheClosedLidPolicyReleasesTheAutomaticLease() {
        fixture.privileged.match = true
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime = makeRuntime(
            config: makeConfig(closedLidZeroBrightness: true),
            displayConfig: makeDisplayConfig(policy: .adapter)
        )
        runtime.start()
        XCTAssertTrue(runtime.decision.preventLidSleep)
        XCTAssertTrue(runtime.decision.preventUserIdleDisplaySleep)

        runtime.updateConfig(
            makeConfig(),
            displayConfig: makeDisplayConfig(policy: .sleep),
            sleepProtectionEnabled: true
        )

        XCTAssertFalse(runtime.decision.preventLidSleep)
        XCTAssertFalse(runtime.decision.preventUserIdleDisplaySleep)
        XCTAssertFalse(fixture.privileged.sleepDisabled)
        XCTAssertFalse(runtime.leases.contains { $0.level == .closedLid })
        XCTAssertFalse(runtime.leases.contains { $0.level == .systemAndDisplay })
    }

    func testBatteryGuardReleasesTheAutomaticClosedLidLease() {
        fixture.privileged.match = true
        observation.value = makeObservation(
            powerState: .discharging,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime = makeRuntime(
            config: makeConfig(batteryFloorPercent: 15, closedLidZeroBrightness: true),
            displayConfig: makeDisplayConfig(policy: .battery)
        )
        runtime.start()
        XCTAssertTrue(runtime.decision.preventLidSleep)
        XCTAssertTrue(runtime.decision.preventUserIdleDisplaySleep)

        observation.value = makeObservation(
            powerState: .discharging,
            batteryPercent: 10,
            hasBattery: true,
            lidState: .closed
        )
        runtime.refresh()

        XCTAssertFalse(runtime.decision.preventLidSleep)
        XCTAssertFalse(runtime.decision.preventUserIdleDisplaySleep)
        XCTAssertFalse(fixture.privileged.sleepDisabled)
        XCTAssertTrue(runtime.decision.safetyVetoes.contains(.batteryFloor))
    }

    func testHelperLossReleasesTheAutomaticClosedLidLease() {
        fixture.privileged.match = true
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime = makeRuntime(
            config: makeConfig(closedLidZeroBrightness: true),
            displayConfig: makeDisplayConfig(policy: .adapter)
        )
        runtime.start()
        XCTAssertTrue(runtime.decision.preventLidSleep)
        XCTAssertTrue(runtime.decision.preventUserIdleDisplaySleep)

        fixture.privileged.match = false
        runtime.refreshHelperStatusNow()

        XCTAssertEqual(runtime.helperStatus, .missing)
        XCTAssertFalse(runtime.decision.preventLidSleep)
        XCTAssertFalse(runtime.decision.preventUserIdleDisplaySleep)
        XCTAssertFalse(runtime.leases.contains { $0.level == .closedLid })
        XCTAssertFalse(runtime.leases.contains { $0.level == .systemAndDisplay })
        XCTAssertEqual(runtime.executionError, "helper-unavailable")
    }

    func testAdapterTransitionsAndSleepEventsArePersisted() {
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()
        observation.value = makeObservation(powerState: .discharging, batteryPercent: 70, hasBattery: true)
        runtime.refresh()
        runtime.recordSystemSleep()

        let state = historyStore.load(nowEpochSeconds: 1_000)
        XCTAssertTrue(state.events.contains { $0.kind == .adapterDisconnected })
        XCTAssertTrue(state.events.contains { $0.kind == .slept })
        XCTAssertTrue(runtime.recentHistory.contains { $0.kind == .adapterDisconnected })
    }

    func testHistoryWriteFailureDoesNotBlockThePolicy() throws {
        let blocker = historyDirectory.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        historyStore = PowerHistoryStore.companion.create(
            path: blocker.appendingPathComponent("history.json").path
        )
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig(keepAwakeOnAdapter: true))

        runtime.start()

        XCTAssertTrue(runtime.decision.automaticRuleApplied)
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertTrue(runtime.recentHistory.isEmpty)
    }

    func testExternalSleepDisabledConflictIsRecorded() {
        fixture.privileged.match = true
        fixture.privileged.sleepDisabled = true
        fixture.privileged.covioOwned = false
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()

        XCTAssertTrue(runtime.recentHistory.contains { $0.kind == .externalConflict })
        XCTAssertTrue(runtime.snapshot.sleepDisabled?.boolValue == true)

        fixture.privileged.sleepDisabled = false
        fixture.privileged.covioOwned = nil
        runtime.refreshHelperStatusNow()

        XCTAssertTrue(runtime.recentHistory.contains { $0.kind == .externalConflictCleared })
    }

    func testDarkWakeFromTheWakeLogIsRecorded() {
        let initial = WakeEvent(kind: .full, atEpochSeconds: 900, reason: "Initial")
        let wakes = WakeLogStore(WakeLogSnapshot(events: [initial], darkWakeCount24h: 0))
        let wakeFixture = Fixture(wakeLogReader: wakes)
        wakeFixture.engine.start()
        let wakeObservation = FakePowerObservationSource(
            value: makeObservation(powerState: .discharging, batteryPercent: 80, hasBattery: true)
        )
        let wakeRuntime = makeRuntime(
            config: makeConfig(),
            fixture: wakeFixture,
            observationSource: wakeObservation
        )
        wakeRuntime.start()
        wakes.snapshot = WakeLogSnapshot(
            events: [WakeEvent(kind: .dark, atEpochSeconds: 1_000, reason: "RTC")],
            darkWakeCount24h: 1
        )

        wakeFixture.watcher.wake()
        wakeRuntime.refresh()

        XCTAssertTrue(wakeRuntime.recentHistory.contains {
            $0.kind == .darkWake && $0.detail == "RTC"
        })
        wakeRuntime.stop()
        wakeFixture.engine.stop()
    }

    func testFullWakeFromTheWakeLogIsRecorded() {
        let initial = WakeEvent(kind: .dark, atEpochSeconds: 900, reason: "Initial")
        let wakes = WakeLogStore(WakeLogSnapshot(events: [initial], darkWakeCount24h: 1))
        let wakeFixture = Fixture(wakeLogReader: wakes)
        wakeFixture.engine.start()
        let wakeObservation = FakePowerObservationSource(
            value: makeObservation(powerState: .discharging, batteryPercent: 80, hasBattery: true)
        )
        let wakeRuntime = makeRuntime(
            config: makeConfig(),
            fixture: wakeFixture,
            observationSource: wakeObservation
        )
        wakeRuntime.start()
        wakes.snapshot = WakeLogSnapshot(
            events: [WakeEvent(kind: .full, atEpochSeconds: 1_000, reason: "UserActivity")],
            darkWakeCount24h: 1
        )

        wakeFixture.watcher.wake()
        wakeRuntime.refresh()

        XCTAssertTrue(wakeRuntime.recentHistory.contains { $0.kind == .fullWake })
        wakeRuntime.stop()
        wakeFixture.engine.stop()
    }

    func testClosedLidCapReleasesTheSessionAndRecordsTheGuard() {
        var now: Int64 = 1_000
        fixture.privileged.match = true
        fixture.privileged.sleepDisabled = false
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(
            config: makeConfig(allowClosedLid: true, closedLidTimeCapMinutes: 30),
            nowEpochSeconds: { now }
        )
        runtime.start()
        XCTAssertTrue(runtime.startSession(mode: .lid, duration: .untilOff))

        now = 2_800
        runtime.refresh()

        XCTAssertFalse(runtime.hasManualSession)
        XCTAssertEqual(runtime.leases.count, 0)
        XCTAssertTrue(runtime.recentHistory.contains {
            $0.kind == .guardReleased && $0.detail == "closed-lid-time-cap"
        })
    }

    func testEndingSessionKeepsLeasesFromOtherSources() {
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()
        fixture.engine.setIdleSleepAvailable(available: false)

        XCTAssertTrue(runtime.startSession(mode: .display, duration: .oneHour))
        XCTAssertEqual(runtime.decision.appliedLeaseLevel, .systemAndDisplay)
        runtime.endSession()

        XCTAssertFalse(runtime.hasManualSession)
        XCTAssertFalse(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertEqual(fixture.engine.currentState.idleSleepPrevention, .system)
    }

    func testClosedLidPowerSessionTurnsDisplayOffAfterTheLidCloses() {
        fixture.privileged.match = true
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()

        XCTAssertTrue(runtime.startSession(mode: .lid, duration: .oneHour))
        XCTAssertTrue(fixture.privileged.sleepDisabled)
        XCTAssertEqual(runtime.executionError, nil)
        XCTAssertTrue(runtime.snapshot.sleepDisabled?.boolValue == true)
        XCTAssertTrue(runtime.snapshot.covioOwnsSleepDisabled?.boolValue == true)

        fixture.lid.emit(.closed)

        XCTAssertEqual(fixture.sleep.displayCalls, 1)
        XCTAssertEqual(fixture.sleep.sleepCalls, 0)
    }

    func testClosedLidSessionRefusesWhenHelperIsMissing() {
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()

        XCTAssertFalse(runtime.startSession(mode: .lid, duration: .oneHour))
        XCTAssertEqual(runtime.executionError, "helper-unavailable")
        XCTAssertFalse(runtime.hasManualSession)
    }

    func testClosedLidSessionRefusesWhenSleepProtectionIsOff() {
        fixture.privileged.match = true
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(
            config: makeConfig(enabled: true),
            sleepProtectionEnabled: false
        )
        runtime.start()

        XCTAssertFalse(runtime.startSession(mode: .lid, duration: .oneHour))
        XCTAssertEqual(runtime.executionError, "sleep-protection-disabled")
        XCTAssertFalse(runtime.hasManualSession)
        XCTAssertFalse(fixture.privileged.sleepDisabled)
    }

    func testClosedLidSessionFailsWhenTheHelperDoesNotApplySleepDisabled() {
        fixture.privileged.match = true
        fixture.privileged.appliesDisableSleepState = false
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig())
        runtime.start()

        XCTAssertFalse(runtime.startSession(mode: .lid, duration: .oneHour))
        XCTAssertEqual(runtime.executionError, "lid-hold-not-applied")
        XCTAssertFalse(runtime.hasManualSession)
        XCTAssertFalse(fixture.privileged.sleepDisabled)
    }

    func testClosedLidSessionRetriesAfterAHelperFailure() {
        fixture.privileged.match = true
        fixture.privileged.disableSleepResults = [false, true]
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(
            config: makeConfig(),
            displayConfig: makeDisplayConfig(policy: .sleep)
        )
        runtime.start()

        XCTAssertFalse(runtime.startSession(mode: .lid, duration: .oneHour))
        XCTAssertFalse(runtime.hasManualSession)

        XCTAssertTrue(runtime.startSession(mode: .lid, duration: .oneHour))
        XCTAssertTrue(runtime.hasManualSession)
        XCTAssertTrue(fixture.privileged.sleepDisabled)
    }

    func testExperimentalClosedLidPathOwnsBrightnessAndSuppressesPublicDisplayOff() {
        fixture.privileged.match = true
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig(closedLidZeroBrightness: true))
        runtime.start()

        XCTAssertTrue(runtime.startSession(mode: .lid, duration: .oneHour))
        fixture.lid.emit(.closed)
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime.refresh()

        XCTAssertEqual(brightnessBackend.brightness, 0)
        XCTAssertEqual(runtime.closedLidZeroBrightnessPhase, .active)
        XCTAssertEqual(fixture.sleep.displayCalls, 0)

        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime.refresh()

        XCTAssertEqual(brightnessBackend.brightness, 0.6, accuracy: 0.001)
        XCTAssertEqual(runtime.closedLidZeroBrightnessPhase, .ready)
        XCTAssertNil(brightnessStore.record)
    }

    func testExperimentalBrightnessFailureFallsBackToPublicDisplayOff() {
        fixture.privileged.match = true
        brightnessBackend.failingSetValues = [0]
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig(closedLidZeroBrightness: true))
        runtime.start()

        XCTAssertTrue(runtime.startSession(mode: .lid, duration: .oneHour))
        fixture.lid.emit(.closed)
        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            lidState: .closed
        )
        runtime.refresh()

        XCTAssertEqual(runtime.closedLidZeroBrightnessPhase, .failed)
        XCTAssertEqual(brightnessBackend.brightness, 0.6, accuracy: 0.001)
        XCTAssertEqual(fixture.sleep.displayCalls, 1)

        runtime.refresh()
        XCTAssertEqual(fixture.sleep.displayCalls, 1)
    }

    func testCriticalThermalStateReleasesEveryPowerLease() {
        observation.value = makeObservation(powerState: .acPower, batteryPercent: 80, hasBattery: true)
        runtime = makeRuntime(config: makeConfig(keepAwakeOnAdapter: true))
        runtime.start()
        XCTAssertTrue(runtime.startSession(mode: .system, duration: .oneHour))

        observation.value = makeObservation(
            powerState: .acPower,
            batteryPercent: 80,
            hasBattery: true,
            thermalState: .critical
        )
        runtime.refresh()

        XCTAssertTrue(runtime.leases.isEmpty)
        XCTAssertTrue(runtime.decision.safetyVetoes.contains(.thermalCritical))
        XCTAssertTrue(fixture.engine.currentState.idleSleepAvailable)
        XCTAssertEqual(fixture.sleep.prevention, .none)
        XCTAssertTrue(runtime.recentHistory.contains { $0.kind == .guardReleased })
    }

    func testUnknownObservationDoesNotFabricateAValueOrAHold() {
        runtime = makeRuntime(config: makeConfig(keepAwakeOnAdapter: true, keepAwakeOnBattery: true))
        runtime.start()

        XCTAssertNil(runtime.observation.batteryPercent)
        XCTAssertNil(runtime.observation.hasBattery)
        XCTAssertNil(runtime.observation.externalDisplayCount)
        XCTAssertNil(runtime.observation.lowPowerModeEnabled)
        XCTAssertEqual(runtime.observation.powerState, .unknown)
        XCTAssertEqual(runtime.observation.thermalState, .unknown)
        XCTAssertFalse(runtime.isHolding)
        XCTAssertFalse(runtime.decision.automaticRuleApplied)
        XCTAssertTrue(runtime.recentHistory.isEmpty)
    }

    private func makeRuntime(
        config: PowerConfig,
        fixture: Fixture? = nil,
        observationSource: FakePowerObservationSource? = nil,
        brightnessBackend: FakeClosedLidBrightnessBackend? = nil,
        brightnessStore: FakeClosedLidBrightnessRecoveryStore? = nil,
        displayConfig: DisplayConfig? = nil,
        sleepProtectionEnabled: Bool = true,
        nowEpochSeconds: @escaping () -> Int64 = { 1_000 }
    ) -> PowerRuntime {
        PowerRuntime(
            engine: (fixture ?? self.fixture).engine,
            privileged: (fixture ?? self.fixture).privileged,
            observationSource: observationSource ?? observation,
            historyStore: historyStore,
            config: config,
            displayConfig: displayConfig,
            sleepProtectionEnabled: sleepProtectionEnabled,
            closedLidBrightnessBackend: brightnessBackend ?? self.brightnessBackend,
            closedLidBrightnessStore: brightnessStore ?? self.brightnessStore,
            nowEpochSeconds: nowEpochSeconds
        )
    }

    private func makeObservation(
        powerState: PowerState,
        batteryPercent: Int,
        hasBattery: Bool,
        thermalState: ThermalState = .nominal,
        lidState: LidState = .open,
        externalDisplayCount: Int = 0
    ) -> PowerObservation {
        PowerObservation(
            batteryPercent: Int32(batteryPercent),
            hasBattery: hasBattery,
            powerState: powerState,
            externalDisplayCount: Int32(externalDisplayCount),
            lidState: lidState,
            thermalState: thermalState,
            lowPowerModeEnabled: false
        )
    }

    private func makeDisplayConfig(
        policy: ClosedLidPowerPolicy,
        mode: ClosedLidDisplayMode? = nil,
        pauseWithExternalDisplay: Bool = true
    ) -> DisplayConfig {
        DisplayConfig(
            schemaVersion: 2,
            keepAwakeWhenLidClosed: policy.keepsAwake,
            closedLidPowerPolicy: policy,
            closedLidDisplayMode: mode ?? (policy.keepsAwake ? .blackScreenPipeline : .system),
            pauseWhenExternalDisplayConnected: pauseWithExternalDisplay
        )
    }

    private func makeConfig(
        enabled: Bool = true,
        keepAwakeOnAdapter: Bool = false,
        keepAwakeOnBattery: Bool = false,
        allowClosedLid: Bool = true,
        pauseClosedLidWithExternalDisplay: Bool = true,
        batteryFloorPercent: Int32 = 15,
        batteryFloorRecoveryPercent: Int32 = 20,
        yieldOnLowPowerMode: Bool = true,
        heatGuardEnabled: Bool = true,
        closedLidTimeCapMinutes: Int32 = 240,
        closedLidZeroBrightness: Bool = false
    ) -> PowerConfig {
        PowerConfig(
            enabled: enabled,
            keepAwakeOnAdapter: keepAwakeOnAdapter,
            keepAwakeOnBattery: keepAwakeOnBattery,
            allowClosedLid: allowClosedLid,
            pauseClosedLidWithExternalDisplay: pauseClosedLidWithExternalDisplay,
            batteryFloorPercent: batteryFloorPercent,
            batteryFloorRecoveryPercent: batteryFloorRecoveryPercent,
            yieldOnLowPowerMode: yieldOnLowPowerMode,
            heatGuardEnabled: heatGuardEnabled,
            closedLidTimeCapMinutes: closedLidTimeCapMinutes,
            closedLidZeroBrightness: closedLidZeroBrightness
        )
    }
}

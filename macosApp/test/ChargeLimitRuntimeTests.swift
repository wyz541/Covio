import XCTest
@testable import Covio

final class ChargeLimitRuntimeTests: XCTestCase {
    private var directory: URL!
    private var stateStore: ChargeLimitRuntimeStateStore!
    private var activeDischargePort: FakeChargeLimitActiveDischarge!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-charge-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateStore = ChargeLimitRuntimeStateStore(
            url: directory.appendingPathComponent("charge-limit/runtime.json")
        )
        activeDischargePort = FakeChargeLimitActiveDischarge()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testConfigureStartsChargingAndPersistsTheUserLimit() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 79))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 85).get()
        let configured = try runtime.evaluateNow().get()
        let settled = try runtime.evaluateNow().get()

        XCTAssertEqual(configured.userLimitPercent, 85)
        XCTAssertEqual(configured.effectiveTargetPercent, 85)
        XCTAssertTrue(configured.chargingLatch)
        XCTAssertEqual(settled.phase, "charging")
        XCTAssertEqual(backend.appliedTargets, [85])
        XCTAssertEqual(try stateStore.load()?.userLimitPercent, 85)
    }

    func testFivePercentSailingCycle() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 79))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }
        _ = runtime.configure(userLimitPercent: 85)
        _ = runtime.evaluateNow()

        reader.reading = reading(current: 85)
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "holding")
        XCTAssertFalse(try runtime.status().get().chargingLatch)

        reader.reading = reading(current: 82)
        _ = runtime.evaluateNow()
        XCTAssertEqual(backend.appliedTargets, [85, 82])
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "sailing")

        reader.reading = reading(current: 80)
        _ = runtime.evaluateNow()
        XCTAssertEqual(backend.appliedTargets, [85, 82, 85])
        XCTAssertTrue(try runtime.status().get().chargingLatch)
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "charging")
    }

    func testAboveTheLimitHoldsTheCurrentLevel() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 90))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 85).get()
        let status = try runtime.evaluateNow().get()

        XCTAssertEqual(status.phase, "aboveLimit")
        XCTAssertEqual(status.effectiveTargetPercent, 90)
        XCTAssertEqual(backend.appliedTargets, [90])
    }

    func testSeventyPercentHoldsTheCurrentLevelWithoutDraining() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 75))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 70).get()
        let status = try runtime.evaluateNow().get()

        XCTAssertEqual(status.phase, "aboveLimit")
        XCTAssertEqual(status.effectiveTargetPercent, 75)
        XCTAssertEqual(backend.appliedTargets, [75])
    }

    func testActiveDischargeTargetsTheUpperLimit() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 75))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(
            userLimitPercent: 70,
            activeDischargeEnabled: true
        ).get()
        let status = try runtime.evaluateNow().get()

        XCTAssertEqual(status.phase, "discharging")
        XCTAssertEqual(status.effectiveTargetPercent, 70)
        XCTAssertTrue(status.activeDischargeEnabled)
        XCTAssertTrue(status.activeDischargeSupported)
        XCTAssertEqual(backend.appliedTargets, [70])
        XCTAssertTrue(activeDischargePort.engaged)

        reader.reading = reading(current: 70)
        let holding = try runtime.evaluateNow().get()
        XCTAssertEqual(holding.phase, "holding")
        XCTAssertEqual(holding.effectiveTargetPercent, 70)
        XCTAssertFalse(activeDischargePort.engaged)

        reader.reading = reading(current: 65)
        let charging = try runtime.evaluateNow().get()
        XCTAssertEqual(charging.phase, "charging")
        XCTAssertTrue(charging.chargingLatch)
        XCTAssertEqual(charging.effectiveTargetPercent, 70)

        reader.reading = reading(current: 80, activelyDischarging: true)
        _ = try runtime.configure(
            userLimitPercent: 70,
            activeDischargeEnabled: false
        ).get()
        XCTAssertFalse(activeDischargePort.engaged)
        let stopping = try runtime.evaluateNow().get()
        XCTAssertEqual(stopping.phase, "stoppingDischarge")

        reader.reading = reading(current: 80)
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "aboveLimit")
    }

    func testEngagedChieKeepsActiveDischargeDespiteAdapterVisibility() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 79))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(
            userLimitPercent: 70,
            activeDischargeEnabled: true
        ).get()
        XCTAssertTrue(activeDischargePort.engaged)

        reader.reading = reading(
            current: 79,
            adapter: false,
            activelyDischarging: true
        )
        let status = try runtime.evaluateNow().get()

        XCTAssertEqual(status.phase, "discharging")
        XCTAssertTrue(activeDischargePort.engaged)
    }

    func testActiveDischargeNudgesWhenPowerdDropsTheTarget() throws {
        let backend = FakeChargeLimitBackend()
        backend.observedTargetOverride = 70
        let reader = FakeChargeLimitPowerReader(
            reading: reading(current: 79, activelyDischarging: true)
        )
        let runtime = makeRuntime(
            backend: backend,
            reader: reader,
            activeDischargeNudgeDelaySeconds: 0.05,
            activeDischargeNudgeCooldownSeconds: 1
        )
        defer { _ = runtime.restore() }

        _ = try runtime.configure(
            userLimitPercent: 70,
            activeDischargeEnabled: true
        ).get()
        backend.observedTargetOverride = 80

        XCTAssertEqual(try runtime.evaluateNow().get().phase, "applying")
        XCTAssertEqual(backend.appliedTargets, [70])

        let settled = expectation(description: "mismatch window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1)
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "applying")
        XCTAssertEqual(backend.appliedTargets, [70, 71])

        let completed = expectation(description: "nudge completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(backend.appliedTargets, [70, 71, 70])
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
    }

    func testActiveDischargeRepairsTargetWhileCharging() throws {
        let backend = FakeChargeLimitBackend()
        backend.observedTargetOverride = 70
        let reader = FakeChargeLimitPowerReader(
            reading: reading(current: 79, isCharging: true)
        )
        let runtime = makeRuntime(
            backend: backend,
            reader: reader,
            activeDischargeNudgeDelaySeconds: 0.05,
            activeDischargeNudgeCooldownSeconds: 1
        )
        defer { _ = runtime.restore() }

        _ = try runtime.configure(
            userLimitPercent: 70,
            activeDischargeEnabled: true
        ).get()
        backend.observedTargetOverride = 80

        XCTAssertEqual(try runtime.evaluateNow().get().phase, "applying")
        XCTAssertEqual(backend.appliedTargets, [70])

        let settled = expectation(description: "mismatch window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1)
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "applying")
        XCTAssertEqual(backend.appliedTargets, [70, 71])
    }

    func testAtLimitReleasesChieBeforeTargetRepair() throws {
        let backend = FakeChargeLimitBackend()
        backend.observedTargetOverride = 70
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 80))
        let runtime = makeRuntime(
            backend: backend,
            reader: reader,
            activeDischargeNudgeDelaySeconds: 0.05,
            activeDischargeNudgeCooldownSeconds: 1
        )
        defer { _ = runtime.restore() }

        _ = try runtime.configure(
            userLimitPercent: 70,
            activeDischargeEnabled: true
        ).get()
        XCTAssertTrue(activeDischargePort.engaged)

        backend.observedTargetOverride = 80
        reader.reading = reading(current: 70, activelyDischarging: true)
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "applying")
        XCTAssertFalse(activeDischargePort.engaged)

        let mismatchWindow = expectation(description: "mismatch window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            mismatchWindow.fulfill()
        }
        wait(for: [mismatchWindow], timeout: 1)
        _ = try runtime.evaluateNow().get()

        let completed = expectation(description: "at-limit nudge completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(backend.appliedTargets, [70, 71, 70])
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)

        backend.observedTargetOverride = 70
        let holding = try runtime.evaluateNow().get()
        XCTAssertEqual(holding.phase, "holding")
        XCTAssertFalse(activeDischargePort.engaged)
    }

    func testStatusReportsTheObservedSystemTarget() throws {
        let backend = FakeChargeLimitBackend()
        backend.observedTargetOverride = 80
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 75))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        let status = try runtime.configure(
            userLimitPercent: 70,
            activeDischargeEnabled: true
        ).get()

        XCTAssertEqual(status.effectiveTargetPercent, 80)
    }

    func testAtLimitReengagesChieWhenChargingStartsBeforeRepair() throws {
        let backend = FakeChargeLimitBackend()
        backend.observedTargetOverride = 70
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 80))
        let runtime = makeRuntime(
            backend: backend,
            reader: reader,
            activeDischargeNudgeDelaySeconds: 10,
            activeDischargeNudgeCooldownSeconds: 0
        )
        defer { _ = runtime.restore() }

        _ = try runtime.configure(
            userLimitPercent: 70,
            activeDischargeEnabled: true
        ).get()
        activeDischargePort.engaged = false
        backend.observedTargetOverride = 80
        reader.reading = reading(current: 70, isCharging: true)

        XCTAssertEqual(try runtime.evaluateNow().get().phase, "applying")
        XCTAssertTrue(activeDischargePort.engaged)
    }

    func testActiveDischargeRequiresChieSupport() {
        activeDischargePort.supported = false
        let backend = FakeChargeLimitBackend()
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 80))
        )

        XCTAssertEqual(
            runtime.configure(userLimitPercent: 70, activeDischargeEnabled: true),
            .failure(.readbackFailed("CHIE active discharge support"))
        )
        XCTAssertTrue(backend.appliedTargets.isEmpty)
    }

    func testActiveDischargeRefillsWhenStartedBelowTheLimit() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 69))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(
            userLimitPercent: 70,
            activeDischargeEnabled: true
        ).get()
        let status = try runtime.evaluateNow().get()

        XCTAssertEqual(status.phase, "charging")
        XCTAssertTrue(status.chargingLatch)
        XCTAssertEqual(status.effectiveTargetPercent, 70)
    }

    func testFirstConfigurePersistsAMatchingObservedTarget() throws {
        let backend = FakeChargeLimitBackend()
        backend.observedTargetOverride = 75
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 75))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 70).get()

        XCTAssertEqual(backend.appliedTargets, [75])
        XCTAssertEqual(backend.state?.targetPercent, 75)
        XCTAssertEqual(try runtime.status().get().effectiveTargetPercent, 75)
    }

    func testPendingTargetWaitsForPowerdWithoutBecomingConflict() throws {
        let backend = FakeChargeLimitBackend()
        backend.observedTargetOverride = 80
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 66))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        let pending = try runtime.configure(userLimitPercent: 70).get()

        XCTAssertEqual(pending.phase, "applying")
        XCTAssertEqual(pending.effectiveTargetPercent, 80)
        XCTAssertEqual(backend.appliedTargets, [66])

        backend.observedTargetOverride = 66
        let settled = try runtime.evaluateNow().get()

        XCTAssertEqual(settled.phase, "sailing")
        XCTAssertEqual(settled.effectiveTargetPercent, 66)
    }

    func testOneHundredPercentReleasesMclOnlyOnce() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 90))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 85).get()
        _ = try runtime.configure(userLimitPercent: 100).get()
        _ = try runtime.evaluateNow().get()

        XCTAssertEqual(backend.appliedTargets, [90, 100])
        XCTAssertNil(try runtime.status().get().effectiveTargetPercent)
        XCTAssertEqual(try runtime.status().get().phase, "charging")
    }

    func testCalibrationAndProtectionDoNotWrite() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(
            reading: reading(current: 85, calibrationActive: true)
        )
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 85).get()
        XCTAssertEqual(try runtime.status().get().phase, "calibration")
        XCTAssertTrue(backend.appliedTargets.isEmpty)

        reader.reading = reading(current: 85, protectionActive: true)
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "systemProtection")
        XCTAssertTrue(backend.appliedTargets.isEmpty)
    }

    func testCalibrationEndReappliesTheUserLimit() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 80))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 85).get()
        XCTAssertEqual(backend.appliedTargets, [85])

        backend.observedTargetOverride = 100
        reader.reading = reading(current: 80, calibrationActive: true)
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "calibration")
        XCTAssertEqual(backend.appliedTargets, [85])

        reader.reading = reading(current: 80)
        let reapplied = try runtime.evaluateNow().get()

        XCTAssertEqual(reapplied.phase, "applying")
        XCTAssertEqual(backend.appliedTargets, [85, 85])
    }

    func testExternalTargetChangeAfterCalibrationStaysConflict() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 80))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 85).get()
        backend.observedTargetOverride = 100
        reader.reading = reading(current: 80, calibrationActive: true)
        _ = try runtime.evaluateNow().get()

        backend.observedTargetOverride = 95
        reader.reading = reading(current: 80)
        let conflicted = try runtime.evaluateNow().get()

        XCTAssertEqual(conflicted.phase, "conflict")
        XCTAssertEqual(backend.appliedTargets, [85])
    }

    func testUnsupportedDeviceDoesNotWrite() throws {
        let backend = FakeChargeLimitBackend()
        backend.capabilityValue = .unsupported
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 85))
        )
        defer { _ = runtime.restore() }

        XCTAssertEqual(try runtime.configure(userLimitPercent: 85).get().phase, "unsupported")
        XCTAssertTrue(backend.appliedTargets.isEmpty)
    }

    func testFailedFirstConfigurationRollsBackTheRuntimeState() throws {
        let backend = FakeChargeLimitBackend()
        backend.applyFailure = .readbackFailed("target")
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 79))
        )

        XCTAssertEqual(
            runtime.configure(userLimitPercent: 85),
            .failure(.readbackFailed("target"))
        )
        XCTAssertNil(try stateStore.load())
        XCTAssertTrue(backend.restoreCalled)
        XCTAssertEqual(try runtime.status().get().phase, "off")
    }

    func testFailedLimitChangeRestoresTheSystemAndClearsTheIntent() throws {
        let backend = FakeChargeLimitBackend()
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 79))
        )
        defer { _ = runtime.restore() }
        _ = try runtime.configure(userLimitPercent: 85).get()

        backend.applyFailure = .readbackFailed("target")
        XCTAssertEqual(
            runtime.configure(userLimitPercent: 90),
            .failure(.readbackFailed("target"))
        )
        XCTAssertNil(try stateStore.load())
        XCTAssertTrue(backend.restoreCalled)
        XCTAssertEqual(try runtime.status().get().phase, "off")
    }

    func testExternalTargetChangeStopsWritesAndReportsConflict() throws {
        let backend = FakeChargeLimitBackend()
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 79))
        )
        defer { _ = runtime.restore() }
        _ = try runtime.configure(userLimitPercent: 85).get()

        backend.observedTargetOverride = 95
        let conflicted = try runtime.evaluateNow().get()

        XCTAssertEqual(conflicted.phase, "conflict")
        XCTAssertEqual(backend.appliedTargets, [85])
    }

    func testExplicitConfigureOverridesAnExternalTargetConflict() throws {
        let backend = FakeChargeLimitBackend()
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 79))
        )
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 85).get()
        backend.observedTargetOverride = 95
        XCTAssertEqual(try runtime.evaluateNow().get().phase, "conflict")

        let reapplied = try runtime.configure(userLimitPercent: 85).get()

        XCTAssertEqual(reapplied.phase, "applying")
        XCTAssertEqual(backend.appliedTargets, [85, 85])
    }

    func testBypassEvidenceIsExposedWhileHolding() throws {
        let backend = FakeChargeLimitBackend()
        let reader = FakeChargeLimitPowerReader(
            reading: reading(current: 85, bypassEngaged: true)
        )
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        _ = try runtime.configure(userLimitPercent: 85).get()
        let configured = try runtime.evaluateNow().get()

        XCTAssertEqual(configured.phase, "holding")
        XCTAssertTrue(configured.bypassEngaged)
    }

    func testResumeOnStartupReappliesThePolicy() throws {
        try stateStore.save(
            ChargeLimitRuntimeState(
                userLimitPercent: 85,
                chargingLatch: false,
                lastPhase: "unplugged"
            )
        )
        let backend = FakeChargeLimitBackend()
        backend.state = ChargeLimitPersistentState(
            targetPercent: 85,
            original: ChargeLimitOriginals(
                optimizedChargingEnabled: nil,
                featureState: 1,
                limitPercent: 80
            )
        )
        backend.hideObservedTarget = true
        let reader = FakeChargeLimitPowerReader(reading: reading(current: 80))
        let runtime = makeRuntime(backend: backend, reader: reader)
        defer { _ = runtime.restore() }

        XCTAssertNoThrow(try runtime.resumeOnStartup().get())
        XCTAssertEqual(backend.appliedTargets, [85])
        XCTAssertTrue(try runtime.status().get().chargingLatch)
    }

    func testLegacyRuntimeStateWithoutCalibrationTargetStillLoads() throws {
        let url = directory.appendingPathComponent("charge-limit/runtime.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"schemaVersion":1,"userLimitPercent":85,"chargingLatch":false,"lastPhase":"charging"}"#.utf8)
            .write(to: url)

        let loaded = try XCTUnwrap(stateStore.load())

        XCTAssertEqual(loaded.userLimitPercent, 85)
        XCTAssertNil(loaded.calibrationTargetPercent)
    }

    func testInvalidLimitsAreRejectedBeforeAnyWrite() {
        let backend = FakeChargeLimitBackend()
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 85))
        )

        XCTAssertEqual(runtime.configure(userLimitPercent: 39), .failure(.invalidTarget(39)))
        XCTAssertEqual(runtime.configure(userLimitPercent: 79), .failure(.invalidTarget(79)))
        XCTAssertTrue(backend.appliedTargets.isEmpty)
    }

    func testRestoreStopsThePolicyAndRestoresTheBackend() throws {
        let backend = FakeChargeLimitBackend()
        let runtime = makeRuntime(
            backend: backend,
            reader: FakeChargeLimitPowerReader(reading: reading(current: 79))
        )
        _ = runtime.configure(userLimitPercent: 85)

        XCTAssertNoThrow(try runtime.restore().get())

        XCTAssertTrue(backend.restoreCalled)
        XCTAssertNil(try stateStore.load())
    }

    private func makeRuntime(
        backend: FakeChargeLimitBackend,
        reader: FakeChargeLimitPowerReader,
        activeDischargeNudgeDelaySeconds: TimeInterval = 0.05,
        activeDischargeNudgeCooldownSeconds: TimeInterval = 0
    ) -> ChargeLimitRuntimeController {
        ChargeLimitRuntimeController(
            backend: backend,
            powerReader: reader,
            stateStore: stateStore,
            activeDischargePort: activeDischargePort,
            intervalSeconds: 3_600,
            activeDischargeNudgeDelaySeconds: activeDischargeNudgeDelaySeconds,
            activeDischargeNudgeCooldownSeconds: activeDischargeNudgeCooldownSeconds
        )
    }

    private func reading(
        current: Int?,
        adapter: Bool = true,
        charged: Bool = false,
        calibrationActive: Bool = false,
        protectionActive: Bool = false,
        bypassEngaged: Bool = false,
        activelyDischarging: Bool = false,
        isCharging: Bool = false
    ) -> ChargeLimitPowerReading {
        ChargeLimitPowerReading(
            adapterConnected: adapter,
            batteryPresent: current != nil,
            currentPercent: current,
            isCharged: charged,
            calibrationActive: calibrationActive,
            systemProtectionActive: protectionActive,
            bypassEngaged: bypassEngaged,
            activelyDischarging: activelyDischarging,
            isCharging: isCharging
        )
    }
}

private final class FakeChargeLimitPowerReader: ChargeLimitPowerReadingSource, @unchecked Sendable {
    var reading: ChargeLimitPowerReading?

    init(reading: ChargeLimitPowerReading?) {
        self.reading = reading
    }

    func read() -> ChargeLimitPowerReading? { reading }
}

private final class FakeChargeLimitBackend: ChargeLimitBackend, @unchecked Sendable {
    var state: ChargeLimitPersistentState?
    var appliedTargets: [Int] = []
    var restoreCalled = false
    var capabilityValue: ChargeLimitSupport = .supported
    var applyFailure: ChargeLimitMCLFailure?
    var observedTargetOverride: Int?
    var hideObservedTarget = false

    func capability() -> ChargeLimitSupport { capabilityValue }
    func observedTargetPercent() -> Int? {
        if hideObservedTarget { return nil }
        if let observedTargetOverride { return observedTargetOverride }
        guard let target = state?.targetPercent, target < 100 else { return nil }
        return target
    }

    func loadState() -> Result<ChargeLimitPersistentState?, ChargeLimitMCLFailure> {
        .success(state)
    }

    func apply(targetPercent: Int) -> Result<ChargeLimitPersistentState, ChargeLimitMCLFailure> {
        appliedTargets.append(targetPercent)
        if let applyFailure { return .failure(applyFailure) }
        let updated = ChargeLimitPersistentState(
            targetPercent: targetPercent,
            original: state?.original ?? ChargeLimitOriginals(
                optimizedChargingEnabled: true,
                featureState: 0,
                limitPercent: 80
            )
        )
        state = updated
        return .success(updated)
    }

    func restore() -> Result<Void, ChargeLimitMCLFailure> {
        restoreCalled = true
        state = nil
        return .success(())
    }
}

private final class FakeChargeLimitActiveDischarge: ChargeLimitActiveDischargePort, @unchecked Sendable {
    var supported = true
    var engaged = false
    var engageResult = true
    var releaseResult = true

    func capability() -> Bool { supported }
    func isEngaged() -> Bool? { engaged }
    func engage() -> Bool {
        guard supported, engageResult else { return false }
        engaged = true
        return true
    }
    func release() -> Bool {
        guard releaseResult else { return false }
        engaged = false
        return true
    }
}

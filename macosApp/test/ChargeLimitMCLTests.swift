import XCTest
@testable import Covio

final class ChargeLimitMCLTests: XCTestCase {
    private var directory: URL!
    private var stateURL: URL!
    private var stateStore: ChargeLimitStateStore!
    private var powerUI: FakePowerUIChargeReading!
    private var preferences: FakeChargeLimitPreferences!
    private var systemTarget: FakeChargeLimitSystemTarget!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-mcl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateURL = directory.appendingPathComponent("charge-limit/state.json")
        stateStore = ChargeLimitStateStore(url: stateURL)
        let powerUI = FakePowerUIChargeReading()
        self.powerUI = powerUI
        preferences = FakeChargeLimitPreferences()
        let preferences = self.preferences!
        systemTarget = FakeChargeLimitSystemTarget { powerUI.currentPercent }
        preferences.ints[DirectMCLPreference.keyFeatureState] = 1
        preferences.ints[DirectMCLPreference.keyLimitValue] = 80
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testApplyUsesPowerUIAndPersistsOriginals() throws {
        powerUI.enabled = true
        powerUI.currentPercent = 80
        let controller = makeController()

        let result = controller.apply(targetPercent: 85)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.targetPercent, 85)
        XCTAssertEqual(state.original.featureState, 1)
        XCTAssertEqual(state.original.limitPercent, 80)
        XCTAssertNil(state.original.optimizedChargingEnabled)
        XCTAssertEqual(powerUI.appliedLimits, [85])
        XCTAssertEqual(powerUI.currentPercent, 85)
        XCTAssertTrue(powerUI.enabled == true)
    }

    func testApplyAtOneHundredReleasesMcl() throws {
        powerUI.enabled = true
        powerUI.currentPercent = 85
        let controller = makeController()

        let result = controller.apply(targetPercent: 100)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.targetPercent, 100)
        XCTAssertEqual(powerUI.disableCalls, 1)
        XCTAssertFalse(powerUI.enabled == true)
    }

    func testApplyBelowEightyUsesTheDirectPreferencePath() throws {
        preferences.ints[DirectMCLPreference.keyCheckpoint] = 1
        preferences.ints[DirectMCLPreference.keyCurrentState] = 1
        preferences.onNotify = { [weak self] in
            self?.powerUI.enabled = true
            self?.powerUI.currentPercent = 70
        }
        let controller = makeController()

        let result = controller.apply(targetPercent: 70)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.targetPercent, 70)
        XCTAssertEqual(preferences.writeCounts[DirectMCLPreference.keyFeatureState], 1)
        XCTAssertEqual(preferences.writeCounts[DirectMCLPreference.keyLimitValue], 1)
        XCTAssertEqual(preferences.writeCounts[DirectMCLPreference.keyOptimizedChargingEnabled], 1)
        XCTAssertEqual(preferences.bools[DirectMCLPreference.keyOptimizedChargingEnabled], false)
        XCTAssertEqual(preferences.ints[DirectMCLPreference.keyLimitValue], 70)
        XCTAssertEqual(preferences.ints[DirectMCLPreference.keyFeatureState], 1)
        XCTAssertTrue(preferences.removedKeys.contains(DirectMCLPreference.keyCheckpoint))
        XCTAssertTrue(preferences.removedKeys.contains(DirectMCLPreference.keyCurrentState))
        XCTAssertEqual(preferences.notifications, 1)
        XCTAssertTrue(powerUI.appliedLimits.isEmpty)
        XCTAssertEqual(powerUI.currentPercent, 70)
        XCTAssertEqual(controller.observedTargetPercent(), 70)
    }

    func testDirectPathEnablesMclWhenItWasOff() {
        powerUI.enabled = false
        preferences.onNotify = { [weak self] in
            self?.powerUI.enabled = true
            self?.powerUI.currentPercent = 70
        }
        let controller = makeController()

        XCTAssertNotNil(successState(controller.apply(targetPercent: 70)))
        XCTAssertEqual(powerUI.appliedLimits, [80])
        XCTAssertEqual(powerUI.currentPercent, 70)
    }

    func testApplyAcceptsTheCurrentLevelBetweenFivePointSteps() throws {
        powerUI.enabled = true
        powerUI.currentPercent = 76
        let controller = makeController()

        let result = controller.apply(targetPercent: 76)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.targetPercent, 76)
        XCTAssertEqual(preferences.ints[DirectMCLPreference.keyLimitValue], 76)
        XCTAssertEqual(powerUI.currentPercent, 76)
    }

    func testDirectPathFailsWhenPowerUIKeepsTheOldTarget() {
        let controller = makeController(directReadbackTimeout: 0.01)

        let result = controller.apply(targetPercent: 70)

        XCTAssertEqual(result, .failure(.readbackFailed("MCL target")))
        XCTAssertEqual(powerUI.appliedLimits, [80])
        XCTAssertEqual(powerUI.currentPercent, 80)
    }

    func testDirectPathAcceptsStoredTargetBeforePowerdCatchesUp() throws {
        preferences.onNotify = { [weak self] in
            self?.powerUI.enabled = true
            self?.powerUI.currentPercent = 70
        }
        systemTarget.overridePercent = 80
        let controller = makeController(directReadbackTimeout: 0.01)

        let result = controller.apply(targetPercent: 70)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.targetPercent, 70)
        XCTAssertEqual(powerUI.currentPercent, 70)
        XCTAssertEqual(controller.observedTargetPercent(), 80)
    }

    func testRestoreReappliesTheOriginalNativeLimit() throws {
        powerUI.enabled = true
        powerUI.currentPercent = 80
        preferences.bools[DirectMCLPreference.keyOptimizedChargingEnabled] = true
        let controller = makeController()
        _ = controller.apply(targetPercent: 85)

        XCTAssertNoThrow(try controller.restore().get())

        XCTAssertEqual(powerUI.appliedLimits, [85, 80])
        XCTAssertEqual(powerUI.currentPercent, 80)
        XCTAssertTrue(powerUI.enabled == true)
        XCTAssertEqual(powerUI.disableCalls, 1)
        XCTAssertEqual(preferences.bools[DirectMCLPreference.keyOptimizedChargingEnabled], true)
        XCTAssertNil(try stateStore.load())
    }

    func testRestoreReappliesTheOriginalDirectLimit() throws {
        powerUI.enabled = true
        powerUI.currentPercent = 70
        preferences.ints[DirectMCLPreference.keyLimitValue] = 70
        preferences.onNotify = { [weak self] in
            guard let self else { return }
            self.powerUI.enabled = true
            self.powerUI.currentPercent = self.preferences
                .ints[DirectMCLPreference.keyLimitValue]
        }
        let controller = makeController()
        _ = controller.apply(targetPercent: 65)

        XCTAssertNoThrow(try controller.restore().get())

        XCTAssertEqual(powerUI.currentPercent, 70)
        XCTAssertTrue(powerUI.appliedLimits.isEmpty)
        XCTAssertNil(try stateStore.load())
    }

    func testRestoreKeepsOriginallyDisabledMclDisabled() throws {
        preferences.ints[DirectMCLPreference.keyFeatureState] = 0
        powerUI.enabled = false
        powerUI.currentPercent = 80
        let controller = makeController()
        _ = controller.apply(targetPercent: 85)

        XCTAssertNoThrow(try controller.restore().get())

        XCTAssertFalse(powerUI.enabled == true)
        XCTAssertEqual(powerUI.disableCalls, 1)
        XCTAssertNil(try stateStore.load())
    }

    func testRestoreDoesNothingWhenNoStateExists() {
        let controller = makeController()

        XCTAssertNoThrow(try controller.restore().get())
        XCTAssertTrue(powerUI.appliedLimits.isEmpty)
        XCTAssertEqual(powerUI.disableCalls, 0)
    }

    func testChangingTargetKeepsTheFirstOriginalSnapshot() throws {
        powerUI.enabled = true
        powerUI.currentPercent = 80
        let controller = makeController()

        _ = controller.apply(targetPercent: 85)
        let result = controller.apply(targetPercent: 90)

        let state = try XCTUnwrap(successState(result))
        XCTAssertEqual(state.original.featureState, 1)
        XCTAssertEqual(state.original.limitPercent, 80)
        XCTAssertEqual(powerUI.appliedLimits, [85, 90])
    }

    func testApplyFailureLeavesTheStateFileForRuntimeRollback() {
        powerUI.applyResult = false
        let controller = makeController()

        let result = controller.apply(targetPercent: 85)

        XCTAssertEqual(result, .failure(.readbackFailed("MCL target")))
        XCTAssertNoThrow(try XCTUnwrap(stateStore.load()))
    }

    func testCorruptStateBlocksWrites() throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: stateURL)
        let controller = makeController()

        XCTAssertEqual(controller.apply(targetPercent: 85), .failure(.stateUnreadable))
        XCTAssertTrue(powerUI.appliedLimits.isEmpty)
    }

    func testInvalidTargetsAreRejected() {
        let controller = makeController()

        for target in [0, 19, 101, 105] {
            XCTAssertEqual(controller.apply(targetPercent: target), .failure(.invalidTarget(target)))
        }
    }

    func testStateFileIsRootReadWriteOnly() throws {
        let controller = makeController()
        _ = controller.apply(targetPercent: 85)

        let attributes = try FileManager.default.attributesOfItem(atPath: stateURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testCapabilityComesFromPowerUIProbe() {
        let controller = makeController()

        powerUI.capabilityValue = .supported
        XCTAssertEqual(controller.capability(), .supported)

        powerUI.capabilityValue = .unsupported
        XCTAssertEqual(controller.capability(), .unsupported)
    }

    func testObservedTargetComesFromMclState() {
        let controller = makeController()

        powerUI.enabled = true
        powerUI.currentPercent = 85
        XCTAssertEqual(controller.observedTargetPercent(), 85)

        powerUI.enabled = false
        XCTAssertNil(controller.observedTargetPercent())
    }

    func testBypassStateUsesOnlyTheLatestTimelineEvent() {
        let ended: [String: Any] = [
            "Timeline": [
                ["date": "20", "event": "BypassEngaged"],
                ["date": "30", "event": "Engaged"],
            ],
        ]
        XCTAssertFalse(SystemPowerUIChargeClient.isBypassEngaged(status: ended))

        let active: [String: Any] = [
            "Timeline": [
                ["date": "20", "event": "Engaged"],
                ["date": "30", "event": "BypassEngaged"],
                ["date": "40", "event": "EligibleForIdle"],
            ],
        ]
        XCTAssertTrue(SystemPowerUIChargeClient.isBypassEngaged(status: active))
        XCTAssertFalse(SystemPowerUIChargeClient.isBypassEngaged(status: ["Timeline": []]))
    }

    func testPmsetTargetParsingUsesChargeSocLimit() {
        let output = """
        Battery level limits:
        (
                {
                chargeSocLimitReason = manualChargeLimit;
                chargeSocLimitSoc = 70;
            }
        )
        """

        XCTAssertEqual(PmsetChargeLimitSystemTargetReader.parseTargetPercent(from: output), 70)
        XCTAssertNil(PmsetChargeLimitSystemTargetReader.parseTargetPercent(
            from: "No battery level limits set"
        ))
    }

    private func makeController(directReadbackTimeout: TimeInterval = 2) -> ChargeLimitMCLController {
        ChargeLimitMCLController(
            preferences: preferences,
            stateStore: stateStore,
            powerUI: powerUI,
            systemTarget: systemTarget,
            directReadbackTimeout: directReadbackTimeout
        )
    }

    private func successState(
        _ result: Result<ChargeLimitPersistentState, ChargeLimitMCLFailure>
    ) -> ChargeLimitPersistentState? {
        guard case .success(let state) = result else { return nil }
        return state
    }
}

private final class FakeChargeLimitPreferences: ChargeLimitPreferenceStore, @unchecked Sendable {
    var ints: [String: Int] = [:]
    var bools: [String: Bool] = [:]
    var writeCounts: [String: Int] = [:]
    var removedKeys: [String] = []
    var syncResult = true
    var notifications = 0
    var onNotify: (() -> Void)?

    func readInt(_ key: String) -> Int? { ints[key] }
    func readBool(_ key: String) -> Bool? { bools[key] }

    func writeInt(_ key: String, value: Int) {
        ints[key] = value
        writeCounts[key, default: 0] += 1
    }

    func writeBool(_ key: String, value: Bool) {
        bools[key] = value
        writeCounts[key, default: 0] += 1
    }

    func remove(_ key: String) {
        removedKeys.append(key)
        ints.removeValue(forKey: key)
        bools.removeValue(forKey: key)
    }
    func synchronize() -> Bool { syncResult }
    func notifyChanged() {
        notifications += 1
        onNotify?()
    }
}

private final class FakePowerUIChargeReading: PowerUIChargeReading, @unchecked Sendable {
    let minimumSupportedPercent = 80
    var capabilityValue: PowerUICapability = .supported
    var enabled: Bool? = true
    var currentPercent: Int? = 80
    var applyResult = true
    var appliedLimits: [Int] = []
    var disableResult = true
    var disableCalls = 0

    func capability() -> PowerUICapability { capabilityValue }
    func isMCLEnabled() -> Bool? { enabled }
    func currentLimit() -> Int? { currentPercent }

    func applyLimit(_ percent: Int) -> Bool {
        appliedLimits.append(percent)
        guard applyResult else { return false }
        enabled = true
        currentPercent = percent
        return true
    }

    func bypassEngaged() -> Bool { false }

    func disableMCL() -> Bool {
        disableCalls += 1
        guard disableResult else { return false }
        enabled = false
        return true
    }
}

private final class FakeChargeLimitSystemTarget: ChargeLimitSystemTargetReading, @unchecked Sendable {
    private let source: @Sendable () -> Int?
    var overridePercent: Int?

    init(source: @escaping @Sendable () -> Int?) {
        self.source = source
    }

    func readTargetPercent() -> Int? { overridePercent ?? source() }
}

import Foundation
@testable import Covio

/// `AppConfig` 的构造助手。
///
/// 桥接层不向 Swift 导出默认参数，`AppConfig` 的全部字段都要写。
/// 这里不抄默认值：默认值由 Rust core 在空目录加载时生成，见 `DefaultConfig`。
/// 抄写会漂移，而漂移的默认值会让产品写出不同的 `config.json`。
enum AppConfigs {
    /// Rust core 的 `AppConfig` 默认值。
    ///
    /// 做法：让 `ConfigStore` 在一个空目录里 `load()`。
    /// 文件不存在时它写出一份默认配置并返回；再读一次拿到的是
    /// 经过 `normalized()` 的那份，与真实启动路径一致。
    // 桥接层对 Swift 只暴露只读字段。
    nonisolated(unsafe) static let defaults: AppConfig = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-config-defaults-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ConfigStore.companion.create(
            path: directory.appendingPathComponent("config.json").path
        )
        _ = store.load()
        return store.load()
    }()

    /// 从 [from] 出发，改掉列出的字段。没列出的保持原值。
    static func make(
        from base: AppConfig = AppConfigs.defaults,
        lowBatteryCapacity: Int32? = nil,
        lowBatteryCapacitySleep: Bool? = nil,
        lowTimeRemainingMinutes: Int32? = nil,
        disableIdleSleepInCharging: Bool? = nil,
        disableLidSleepInCharging: Bool? = nil,
        disableLidSleepOnBattery: Bool? = nil,
        darkWakeAwarenessEnabled: Bool? = nil,
        lidSleepImmediateOnClose: Bool? = nil,
        enabled: Bool? = nil,
        power: PowerConfig? = nil,
        display: DisplayConfig? = nil,
        chargeLimitEnabled: Bool? = nil,
        chargeLimitPercent: Int32? = nil,
        chargeLimitActiveDischarge: Bool? = nil
    ) -> AppConfig {
        base.doCopy(
            schemaVersion: base.schemaVersion,
            language: base.language,
            enabled: enabled ?? base.enabled,
            launchAtLogin: base.launchAtLogin,
            lowBatteryCapacitySleep: lowBatteryCapacitySleep ?? base.lowBatteryCapacitySleep,
            lowBatteryCapacity: lowBatteryCapacity ?? base.lowBatteryCapacity,
            lowTimeRemainingMinutes: lowTimeRemainingMinutes ?? base.lowTimeRemainingMinutes,
            disableIdleSleepInCharging: disableIdleSleepInCharging ?? base.disableIdleSleepInCharging,
            disableLidSleepInCharging: disableLidSleepInCharging ?? base.disableLidSleepInCharging,
            disableLidSleepOnBattery: disableLidSleepOnBattery ?? base.disableLidSleepOnBattery,
            darkWakeAwarenessEnabled: darkWakeAwarenessEnabled ?? base.darkWakeAwarenessEnabled,
            lidSleepImmediateOnClose: lidSleepImmediateOnClose ?? base.lidSleepImmediateOnClose,
            notificationsEnabled: base.notificationsEnabled,
            updateCheckEnabled: base.updateCheckEnabled,
            updateCheckIntervalHours: base.updateCheckIntervalHours,
            lastUpdateCheckEpochSeconds: base.lastUpdateCheckEpochSeconds,
            hibernateMode: base.hibernateMode,
            firstRun: base.firstRun,
            shelfEnabled: base.shelfEnabled,
            screenshotInboxEnabled: base.screenshotInboxEnabled,
            shelfSoundsEnabled: base.shelfSoundsEnabled,
            clipboardEnabled: base.clipboardEnabled,
            clipboardPasteStackHotKey: base.clipboardPasteStackHotKey,
            clipboardCaptureHotKey: base.clipboardCaptureHotKey,
            power: power ?? base.power,
            display: display ?? (power == nil ? base.display : nil),
            chargeLimitEnabled: chargeLimitEnabled ?? base.chargeLimitEnabled,
            chargeLimitPercent: chargeLimitPercent ?? base.chargeLimitPercent,
            chargeLimitActiveDischarge: chargeLimitActiveDischarge ?? base.chargeLimitActiveDischarge,
            fileNaming: base.fileNaming
        )
    }
}

/// 被测引擎加一组假端口。
///
final class Fixture {
    let power = FakePower()
    let lid = FakeLid()
    let idle = FakeIdle()
    let sleep = FakeSleepController()
    let watcher = FakeSleepWatcher()
    let privileged = FakePrivilegedOps()
    let logger = MemoryLogger()
    let engine: Engine

    init(
        config: AppConfig = AppConfigs.defaults,
        clock: @escaping () -> Int64 = Fixture.systemNowMillis,
        wakeLogReader: WakeLogReader = WakeLogStore(nil),
        wakeScanExecutor: @escaping (@escaping () -> Void) -> Void = { $0() },
        wakeDelay: @escaping (Int64) -> Void = { _ in },
        wakeCacheNowMillis: @escaping () -> Int64 = Fixture.systemNowMillis
    ) {
        engine = Engine(
            initialConfig: config,
            power: power,
            lid: lid,
            idle: idle,
            sleepController: sleep,
            sleepWatcher: watcher,
            privileged: privileged,
            logger: logger,
            wakeLogReader: wakeLogReader,
            clock: { clock() },
            stateListener: NoopStateListener(),
            wakeScanExecutor: wakeScanExecutor,
            wakeDelay: { wakeDelay($0) },
            wakeRetryDelayMillis: 1_000,
            wakeRetryCount: 3,
            wakeCacheNowMillis: { wakeCacheNowMillis() }
        )
    }

    func nowMillis() -> Int64 { Fixture.systemNowMillis() }

    /// Rust core 使用的当前时间毫秒值。
    static func systemNowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
}

/// 唤醒日志的假读取器。
final class WakeLogStore: NSObject, WakeLogReader {
    /// 固定快照。每次读取都返回它。换成别的值可以模拟日志更新。
    var snapshot: WakeLogSnapshot?
    /// 按读取次数返回不同结果，次数从 1 开始。设了就忽略 `snapshot`。
    var provider: ((Int) -> WakeLogSnapshot?)?
    /// 被读取的次数。
    private(set) var reads = 0
    /// `wakeDelay` 被调用的次数。留给测试自己加。
    var delays = 0

    init(_ snapshot: WakeLogSnapshot? = nil) {
        self.snapshot = snapshot
        super.init()
    }

    func read() -> WakeLogSnapshot? {
        reads += 1
        if let provider { return provider(reads) }
        return snapshot
    }
}

/// 模拟 `pmset -g log` 长时间不返回。
final class BlockingWakeLogReader: NSObject, WakeLogReader {
    let readStarted = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    func read() -> WakeLogSnapshot? {
        readStarted.signal()
        _ = release.wait(timeout: .now() + 5)
        return nil
    }
}

/// 把交给 `wakeScanExecutor` 的任务排队，由测试决定何时执行。
///
/// 用来证明「同时到达的唤醒信号只扫一次日志」。
final class QueuedExecutor {
    private var queued: [() -> Void] = []

    var count: Int { queued.count }

    func executor(_ block: @escaping () -> Void) {
        queued.append(block)
    }

    func runNext() {
        guard !queued.isEmpty else { return }
        _ = queued.removeFirst()()
    }
}

final class NoopStateListener: NSObject, StateListener {
    func onState(state: AppState) {}
}

final class FakePower: NSObject, PowerSource {
    var value: BatteryStatus?
    private var listener: (() -> Void)?

    init(value: BatteryStatus? = nil) {
        self.value = value
        super.init()
    }

    func read() -> BatteryStatus? { value }

    func subscribe(listener_: @escaping () -> Void) { listener = listener_ }

    func stop() { listener = nil }

    func emit() { listener?() }
}

/// 假的电源观察源。测试不能读真实电池、热状态或显示器。
final class FakePowerObservationSource: NSObject, PowerObservationSource {
    var value: PowerObservation
    private var listener: (() -> Void)?
    private(set) var reads = 0

    init(value: PowerObservation = PowerObservation(
        batteryPercent: nil,
        hasBattery: nil,
        powerState: .unknown,
        externalDisplayCount: nil,
        lidState: .unknown,
        thermalState: .unknown,
        lowPowerModeEnabled: nil
    )) {
        self.value = value
        super.init()
    }

    func read() -> PowerObservation {
        reads += 1
        return value
    }

    func subscribe(listener_: @escaping () -> Void) {
        listener = listener_
    }

    func stop() {
        listener = nil
    }

    func emit() {
        listener?()
    }
}

final class FakeLid: NSObject, LidSensor {
    var state: LidState
    private var listener: ((LidState) -> Void)?

    init(state: LidState = .open) {
        self.state = state
        super.init()
    }

    func read() -> LidState { state }

    func subscribe(listener: @escaping (LidState) -> Void) { self.listener = listener }

    func stop() { listener = nil }

    func emit(_ value: LidState) {
        state = value
        listener?(value)
    }
}

final class FakeIdle: NSObject, IdleSensor {
    var seconds: Int64 = 0

    func idleSeconds() -> Int64 { seconds }
}

final class FakeSleepController: NSObject, SleepController {
    var sleepCalls = 0
    var displayCalls = 0
    var prevention: IdleSleepPrevention = .none
    var failAssertion = false
    var appliedPrevention: [IdleSleepPrevention] = []
    var timeoutSeconds: Int64? = 600

    var prevented: Bool {
        prevention == .system || prevention == .systemAndDisplay
    }

    func sleep() { sleepCalls += 1 }

    func displaySleep() { displayCalls += 1 }

    func applyIdleSleepPrevention(prevention requested: IdleSleepPrevention) -> IdleSleepAssertionResult {
        appliedPrevention.append(requested)
        if failAssertion {
            return IdleSleepAssertionResult(
                requested: requested,
                actual: prevention,
                success: false,
                error: "assertion failure"
            )
        }
        prevention = requested
        return IdleSleepAssertionResult(requested: requested, actual: requested, success: true, error: nil)
    }

    func readIdleSleepPrevention() -> IdleSleepPrevention { prevention }

    func systemIdleSleepTimeoutSeconds() -> Int64? { timeoutSeconds }
}

final class FakeSleepWatcher: NSObject, SleepWatcher {
    private var listener: ((SleepEvent) -> Void)?

    func subscribe(listener__: @escaping (SleepEvent) -> Void) { listener = listener__ }

    func stop() { listener = nil }

    func willSleep() { listener?(.willsleep) }

    func wake() { listener?(.wakesignal) }
}

final class FakePrivilegedOps: NSObject, PrivilegedOps {
    var statusValue: HelperStatus = .missing
    var match: Bool {
        get { statusValue == .match }
        set { statusValue = newValue ? .match : .missing }
    }
    var disableSleepResult = true
    var disableSleepResults: [Bool] = []
    var appliesDisableSleepState = true
    var installResult = true
    var sleepDisabled = false
    var covioOwned: Bool?
    var disableSleepValues: [Bool] = []

    func isInstalled() -> Bool { statusValue != .missing }

    func status() -> HelperStatus { statusValue }

    func helperVersion() -> String? { CovioReleaseIdentity.APP_VERSION }

    func install() -> Bool { installResult }

    func uninstall() -> Bool { true }

    func hibernateMode() -> Int32? { nil }

    func setHibernateMode(mode: Int32) -> Bool { true }

    func setDisableSleep(disabled: Bool) -> Bool {
        disableSleepValues.append(disabled)
        let accepted = disableSleepResults.isEmpty
            ? disableSleepResult
            : disableSleepResults.removeFirst()
        if accepted, appliesDisableSleepState {
            sleepDisabled = disabled
        }
        return accepted
    }

    func lidLeaseStatus() -> LidLeaseStatus {
        LidLeaseStatus(
            available: match,
            protocolVersion: match ? HelperProtocol.protocolVersion : nil,
            sleepDisabled: sleepDisabled,
            covioOwned: covioOwned ?? sleepDisabled,
            activeLeaseCount: sleepDisabled ? 1 : 0,
            expiresAtEpochSeconds: sleepDisabled ? Int64.max : nil,
            error: nil
        )
    }
}

/// 只把消息记在内存里的日志器。断言用它检查引擎写了什么。
final class MemoryLogger: NSObject, AppLogger {
    private(set) var messages: [String] = []

    func info(message: String) { messages.append(message) }

    func warn(message: String, error: Error?) { messages.append(message) }

    func error(message: String, error: Error?) { messages.append(message) }

    func logFile() -> String { "" }
}

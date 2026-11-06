import CovioFFI
import Foundation

/// Swift owner for the Rust power engine and its bounded capability callbacks.
///
/// Business state and policy stay in Rust. This type only wires macOS ports to
/// the C ABI and keeps the legacy host-facing method names stable.
final class Engine: @unchecked Sendable {
    private let handle: OpaquePointer
    private let callbacks: EngineCallbackBridge
    private let wakeScanExecutor: (@escaping () -> Void) -> Void
    private let callLock = NSLock()
    private let lifecycleLock = NSLock()
    private let stateLock = NSLock()
    private var cachedState = AppState()
    private var started = false

    init(
        initialConfig: AppConfig,
        power: PowerSource,
        lid: LidSensor,
        idle: IdleSensor,
        sleepController: SleepController,
        sleepWatcher: SleepWatcher,
        privileged: PrivilegedOps,
        logger: AppLogger,
        wakeLogReader: WakeLogReader,
        clock: @escaping () -> Int64,
        stateListener: StateListener,
        wakeScanExecutor: @escaping (@escaping () -> Void) -> Void,
        wakeDelay: @escaping (Int64) -> Void,
        wakeRetryDelayMillis: Int64,
        wakeRetryCount: Int32,
        wakeCacheNowMillis: @escaping () -> Int64
    ) {
        _ = wakeRetryDelayMillis
        _ = wakeRetryCount
        let callbacks = EngineCallbackBridge(
            power: power,
            lid: lid,
            idle: idle,
            sleepController: sleepController,
            sleepWatcher: sleepWatcher,
            privileged: privileged,
            logger: logger,
            wakeLogReader: wakeLogReader,
            clock: clock,
            wakeCacheNowMillis: wakeCacheNowMillis,
            wakeDelay: wakeDelay
        )
        self.callbacks = callbacks
        self.wakeScanExecutor = wakeScanExecutor
        self.cachedState = AppState()

        let configData: Data
        do {
            configData = try JSONEncoder().encode(initialConfig)
        } catch {
            fatalError("Cannot encode the Rust engine configuration: \(error)")
        }

        var ffiError = EngineFfi.emptyError()
        let created = configData.withUnsafeBytes { configBuffer in
            covio_engine_create(
                configBuffer.bindMemory(to: UInt8.self).baseAddress,
                configData.count,
                covioEngineCapabilityCallback,
                Unmanaged.passUnretained(callbacks).toOpaque(),
                &ffiError
            )
        }
        guard let created else {
            fatalError("Cannot create the Rust engine: \(EngineFfi.errorMessage(ffiError))")
        }
        handle = created
        callbacks.engine = self
        callbacks.stateListener = stateListener
    }

    deinit {
        covio_engine_release(handle)
    }

    /// 引擎空闲时读取 Rust 实时状态，忙碌时读取最近发布的状态。
    ///
    /// 唤醒日志扫描可能持有引擎调用锁直到 `pmset` 超时。
    /// UI 读取不能等待这个扫描。
    var currentState: AppState {
        if callLock.try() {
            let result: Any?
            do {
                result = try call("currentState", payload: [:], nowMillis: nil)
            } catch {
                callbacks.logger.error(
                    message: "Rust engine command currentState failed",
                    error: error
                )
                result = nil
            }
            callLock.unlock()
            drainPendingWakeScans()
            if let root = result as? [String: Any],
               let state = try? coreDecode(AppState.self, from: root["state"] ?? [:]) {
                return state
            }
        }
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedState
    }

    func start() {
        lifecycleLock.lock()
        if started {
            lifecycleLock.unlock()
            return
        }
        started = true
        lifecycleLock.unlock()

        callbacks.power.subscribe { [weak self] in self?.onPowerChanged() }
        callbacks.lid.subscribe { [weak self] state in self?.onLidChanged(state) }
        callbacks.sleepWatcher.subscribe { [weak self] event in self?.onSleepEvent(event) }
        _ = perform("start")
    }

    func stop() {
        lifecycleLock.lock()
        let wasStarted = started
        started = false
        lifecycleLock.unlock()
        guard wasStarted else { return }
        _ = perform("stop")
        callbacks.power.stop()
        callbacks.lid.stop()
        callbacks.sleepWatcher.stop()
    }

    /// 只有后台命令未占用引擎时才运行周期 tick。
    ///
    /// 唤醒扫描仍在读取 `pmset -g log` 时返回 `false`。
    @discardableResult
    func tick(nowMillis: Int64) -> Bool {
        guard callLock.try() else { return false }
        let result: Any?
        do {
            result = try call(
                "tick",
                payload: ["nowMillis": nowMillis],
                nowMillis: nowMillis
            )
        } catch {
            callbacks.logger.error(
                message: "Rust engine command tick failed",
                error: error
            )
            result = nil
        }
        callLock.unlock()
        drainPendingWakeScans()
        return result != nil
    }

    @discardableResult
    func updateConfig(newConfig: AppConfig) -> Bool {
        guard let config = try? coreEncode(newConfig) else { return false }
        return boolResult(perform("updateConfig", payload: ["config": config]))
    }

    @discardableResult
    func setEnabled(enabled: Bool) -> Bool {
        boolResult(perform("setEnabled", payload: ["enabled": enabled]))
    }

    func setIdleSleepAvailable(available: Bool) {
        _ = perform("setIdleSleepAvailable", payload: ["available": available])
    }

    @discardableResult
    func setIdleSleepPrevention(prevention: IdleSleepPrevention) -> Bool {
        guard let value = try? coreEncode(prevention) else { return false }
        return boolResult(perform("setIdleSleepPrevention", payload: ["prevention": value]))
    }

    @discardableResult
    func setLidSleepAvailable(available: Bool) -> Bool {
        boolResult(perform("setLidSleepAvailable", payload: ["available": available]))
    }

    @discardableResult
    func replacePowerLeases(leases: [HoldLease]) -> Bool {
        guard let value = try? coreEncode(leases) else { return false }
        return boolResult(perform("replacePowerLeases", payload: ["leases": value]))
    }

    @discardableResult
    func setPowerLidHold(required: Bool) -> Bool {
        boolResult(perform("setPowerLidHold", payload: ["required": required]))
    }

    func setPowerLidDisplayOffEnabled(enabled: Bool) {
        _ = perform("setPowerLidDisplayOffEnabled", payload: ["enabled": enabled])
    }

    func setManualLidSleepAvailable(available: Bool) {
        _ = perform("setManualLidSleepAvailable", payload: ["available": available])
    }

    func scheduleCancelIdle(afterSeconds: Int64) {
        _ = perform("scheduleCancelIdle", payload: ["seconds": afterSeconds])
    }

    func scheduleCancelLid(afterSeconds: Int64) {
        _ = perform("scheduleCancelLid", payload: ["seconds": afterSeconds])
    }

    func sleepNow() {
        _ = perform("sleepNow")
    }

    func displaySleepNow() {
        _ = perform("displaySleepNow")
    }

    func onPowerChanged() {
        _ = perform("onPowerChanged")
    }

    func onLidChanged(_ state: LidState) {
        guard let value = try? coreEncode(state) else { return }
        _ = perform("onLidChanged", payload: ["state": value])
    }

    func onSleepEvent(_ event: SleepEvent) {
        guard let value = try? coreEncode(event) else { return }
        _ = perform("onSleepEvent", payload: ["event": value])
    }

    private func perform(
        _ command: String,
        payload: [String: Any] = [:],
        nowMillis: Int64? = nil
    ) -> Any? {
        callLock.lock()
        let result: Any?
        do {
            result = try call(command, payload: payload, nowMillis: nowMillis)
        } catch {
            callbacks.logger.error(
                message: "Rust engine command \(command) failed",
                error: error
            )
            result = nil
        }
        callLock.unlock()
        drainPendingWakeScans()
        return result
    }

    private func call(
        _ command: String,
        payload: [String: Any],
        nowMillis: Int64?
    ) throws -> Any {
        let commandBytes = Array(command.utf8)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        var output = EngineFfi.emptyBytes()
        var error = EngineFfi.emptyError()
        let nowSeconds = (nowMillis ?? callbacks.clock()) / 1_000

        let status = commandBytes.withUnsafeBufferPointer { commandBuffer in
            payloadData.withUnsafeBytes { payloadBuffer in
                covio_engine_call(
                    handle,
                    commandBuffer.baseAddress,
                    commandBuffer.count,
                    payloadBuffer.bindMemory(to: UInt8.self).baseAddress,
                    payloadData.count,
                    nowSeconds,
                    &output,
                    &error
                )
            }
        }
        defer { covio_owned_bytes_free(&output) }
        guard status == 0 else {
            throw CovioCoreError(code: status, message: EngineFfi.errorMessage(error))
        }
        guard output.len > 0, let data = output.data else { return [:] }
        return try JSONSerialization.jsonObject(
            with: Data(bytes: data, count: output.len),
            options: [.fragmentsAllowed]
        )
    }

    private func drainPendingWakeScans() {
        let pending = callbacks.takePendingWakeScans()
        for initial in pending {
            let block: () -> Void = { [weak self] in
                guard let self else { return }
                _ = self.perform("runWakeScan", payload: ["initial": initial])
            }
            wakeScanExecutor(block)
        }
    }

    private func boolResult(_ value: Any?) -> Bool {
        (value as? [String: Any])?["result"] as? Bool ?? false
    }

    fileprivate func receiveState(_ state: AppState) {
        stateLock.lock()
        cachedState = state
        stateLock.unlock()
        callbacks.stateListener?.onState(state: state)
    }
}

private final class EngineCallbackBridge: @unchecked Sendable {
    let power: PowerSource
    let lid: LidSensor
    let idle: IdleSensor
    let sleepController: SleepController
    let sleepWatcher: SleepWatcher
    let privileged: PrivilegedOps
    let logger: AppLogger
    let wakeLogReader: WakeLogReader
    let clock: () -> Int64
    let wakeCacheNowMillis: () -> Int64
    let wakeDelay: (Int64) -> Void
    weak var engine: Engine?
    weak var stateListener: StateListener?

    private let wakeLock = NSLock()
    private var pendingWakeScans: [Bool] = []

    init(
        power: PowerSource,
        lid: LidSensor,
        idle: IdleSensor,
        sleepController: SleepController,
        sleepWatcher: SleepWatcher,
        privileged: PrivilegedOps,
        logger: AppLogger,
        wakeLogReader: WakeLogReader,
        clock: @escaping () -> Int64,
        wakeCacheNowMillis: @escaping () -> Int64,
        wakeDelay: @escaping (Int64) -> Void
    ) {
        self.power = power
        self.lid = lid
        self.idle = idle
        self.sleepController = sleepController
        self.sleepWatcher = sleepWatcher
        self.privileged = privileged
        self.logger = logger
        self.wakeLogReader = wakeLogReader
        self.clock = clock
        self.wakeCacheNowMillis = wakeCacheNowMillis
        self.wakeDelay = wakeDelay
    }

    func handle(request: Any) throws -> Any {
        guard let envelope = request as? [String: Any],
              let operation = envelope["op"] as? String else {
            throw EngineCallbackError("Capability request is malformed")
        }
        let payload = envelope["payload"] as? [String: Any] ?? [:]

        switch operation {
        case "power.read":
            let battery = power.read()
            return ["battery": try battery.map(encode) ?? NSNull()]
        case "lid.read":
            return ["state": try encode(lid.read())]
        case "idle.seconds":
            return ["seconds": idle.idleSeconds()]
        case "sleep.request":
            sleepController.sleep()
            return [:]
        case "displaySleep.request":
            sleepController.displaySleep()
            return [:]
        case "assertion.apply":
            let prevention: IdleSleepPrevention = try decode(payload, "prevention")
            return try encode(sleepController.applyIdleSleepPrevention(prevention: prevention))
        case "assertion.read":
            return ["prevention": try encode(sleepController.readIdleSleepPrevention())]
        case "assertion.timeout":
            return ["seconds": sleepController.systemIdleSleepTimeoutSeconds().map { $0 as Any } ?? NSNull()]
        case "privileged.isInstalled":
            return ["installed": privileged.isInstalled()]
        case "privileged.status":
            return ["status": try encode(privileged.status())]
        case "privileged.helperVersion":
            return ["version": privileged.helperVersion().map { $0 as Any } ?? NSNull()]
        case "privileged.install":
            return ["result": privileged.install()]
        case "privileged.uninstall":
            return ["result": privileged.uninstall()]
        case "privileged.setDisableSleep":
            let disabled = payload["disabled"] as? Bool ?? false
            return ["result": privileged.setDisableSleep(disabled: disabled)]
        case "privileged.lidLeaseStatus":
            return ["status": try encode(privileged.lidLeaseStatus())]
        case "privileged.hibernateMode":
            return ["mode": privileged.hibernateMode().map { $0 as Any } ?? NSNull()]
        case "privileged.setHibernateMode":
            let mode = (payload["mode"] as? NSNumber)?.int32Value ?? 0
            return ["result": privileged.setHibernateMode(mode: mode)]
        case "wake.read":
            return ["snapshot": try wakeLogReader.read().map(encode) ?? NSNull()]
        case "clock.nowMillis":
            return ["millis": clock()]
        case "clock.wakeCacheNowMillis":
            return ["millis": wakeCacheNowMillis()]
        case "wake.delay":
            let millis = (payload["millis"] as? NSNumber)?.int64Value ?? 0
            wakeDelay(millis)
            return [:]
        case "wake.schedule":
            let initial = payload["initial"] as? Bool ?? false
            wakeLock.lock()
            pendingWakeScans.append(initial)
            wakeLock.unlock()
            return [:]
        case "log":
            let level = payload["level"] as? String ?? "info"
            let message = payload["message"] as? String ?? ""
            switch level {
            case "warn": logger.warn(message: message, error: nil)
            case "error": logger.error(message: message, error: nil)
            default: logger.info(message: message)
            }
            return [:]
        case "state.changed":
            let state: AppState = try decode(payload)
            engine?.receiveState(state)
            return [:]
        default:
            throw EngineCallbackError("Unknown capability operation: \(operation)")
        }
    }

    func takePendingWakeScans() -> [Bool] {
        wakeLock.lock()
        let pending = pendingWakeScans
        pendingWakeScans.removeAll(keepingCapacity: true)
        wakeLock.unlock()
        return pending
    }

    private func encode<T: Encodable>(_ value: T) throws -> Any {
        try coreEncode(value)
    }

    private func decode<T: Decodable>(_ payload: [String: Any], _ key: String) throws -> T {
        guard let value = payload[key] else {
            throw EngineCallbackError("\(key) is missing")
        }
        return try coreDecode(T.self, from: value)
    }

    private func decode<T: Decodable>(_ value: Any) throws -> T {
        try coreDecode(T.self, from: value)
    }
}

private struct EngineCallbackError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private enum EngineFfi {
    static func emptyBytes() -> CovioOwnedBytes {
        CovioOwnedBytes(data: nil, len: 0, capacity: 0)
    }

    static func emptyError() -> CovioError {
        CovioError(code: 0, message: emptyBytes())
    }

    static func errorMessage(_ error: CovioError) -> String {
        guard let data = error.message.data, error.message.len > 0 else {
            return "Covio engine request failed"
        }
        return String(
            decoding: UnsafeBufferPointer(start: data, count: error.message.len),
            as: UTF8.self
        )
    }

    static func ownedBytes(_ data: Data) -> CovioOwnedBytes {
        data.withUnsafeBytes { buffer in
            covio_owned_bytes_copy(
                buffer.bindMemory(to: UInt8.self).baseAddress,
                data.count
            )
        }
    }
}

private func covioEngineCapabilityCallback(
    context: UnsafeMutableRawPointer?,
    request: UnsafePointer<UInt8>?,
    requestLen: Int,
    ffiError: UnsafeMutablePointer<CovioError>?
) -> CovioOwnedBytes {
    guard let context else {
        return engineCallbackFailure(
            "Capability callback context is missing",
            error: ffiError
        )
    }
    let bridge = Unmanaged<EngineCallbackBridge>
        .fromOpaque(context)
        .takeUnretainedValue()
    do {
        let requestData: Data
        if let request, requestLen > 0 {
            requestData = Data(bytes: request, count: requestLen)
        } else {
            requestData = Data()
        }
        let envelope = try JSONSerialization.jsonObject(with: requestData)
        let result = try bridge.handle(request: envelope)
        let response = try JSONSerialization.data(
            withJSONObject: ["ok": true, "data": result]
        )
        return EngineFfi.ownedBytes(response)
    } catch {
        return engineCallbackFailure(error.localizedDescription, error: ffiError)
    }
}

private func engineCallbackFailure(
    _ message: String,
    error: UnsafeMutablePointer<CovioError>?
) -> CovioOwnedBytes {
    let payload = (try? JSONSerialization.data(
        withJSONObject: ["ok": false, "error": message]
    )) ?? Data("{\"ok\":false}".utf8)
    if let error {
        error.pointee.code = 16
        error.pointee.message = EngineFfi.ownedBytes(Data(message.utf8))
    }
    return EngineFfi.ownedBytes(payload)
}

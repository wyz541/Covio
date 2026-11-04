import Foundation

/// 一次电量读取。OS 读取留在生产实现，测试替换这个端口。
struct ChargeLimitPowerReading: Equatable, Sendable {
    let adapterConnected: Bool
    let batteryPresent: Bool
    let currentPercent: Int?
    let isCharged: Bool
    let calibrationActive: Bool
    let systemProtectionActive: Bool
    let bypassEngaged: Bool
    var activelyDischarging: Bool = false
    var isCharging: Bool = false
}

protocol ChargeLimitPowerReadingSource: Sendable {
    func read() -> ChargeLimitPowerReading?
}

/// 运行时持久化的用户意图。
struct ChargeLimitRuntimeState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var userLimitPercent: Int
    var chargingLatch = false
    /// 校准开始时看到的系统目标。校准结束后只恢复匹配此值的临时覆盖。
    var calibrationTargetPercent: Int? = nil
    /// 已写入 PowerUI，但 powerd 尚未确认的目标。
    var pendingTargetPercent: Int? = nil
    var lastPhase = "off"
    var activeDischargeEnabled: Bool? = nil
}

/// runtime 状态文件。与根偏好状态分开，避免把用户上限和 MCL 执行目标混在一起。
final class ChargeLimitRuntimeStateStore {
    private let url: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func load() throws -> ChargeLimitRuntimeState? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ChargeLimitMCLFailure.stateUnreadable
        }
        guard let state = try? decoder.decode(ChargeLimitRuntimeState.self, from: data),
              state.schemaVersion == ChargeLimitRuntimeState.currentSchemaVersion
        else {
            throw ChargeLimitMCLFailure.stateUnreadable
        }
        return state
    }

    func save(_ state: ChargeLimitRuntimeState) throws {
        do {
            try prepareDirectory()
            let data = try encoder.encode(state)
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw ChargeLimitMCLFailure.stateWriteFailed
        }
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw ChargeLimitMCLFailure.stateWriteFailed
        }
    }

    private func prepareDirectory() throws {
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
}

/// helper 对状态命令返回的完整状态。
struct ChargeLimitRuntimeStatus: Equatable, Sendable {
    let userLimitPercent: Int
    let effectiveTargetPercent: Int?
    let chargingLatch: Bool
    let phase: String
    let bypassEngaged: Bool
    let original: ChargeLimitOriginals?
    var activeDischargeEnabled: Bool = false
    var activeDischargeSupported: Bool = false
}

protocol ChargeLimitRuntimeControlling: Sendable {
    func status() -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure>
    func configure(
        userLimitPercent: Int,
        activeDischargeEnabled: Bool
    ) -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure>
    func restore() -> Result<Void, ChargeLimitMCLFailure>
}

extension ChargeLimitRuntimeController {
    func configure(userLimitPercent: Int) -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure> {
        configure(userLimitPercent: userLimitPercent, activeDischargeEnabled: false)
    }
}

/// 持续执行 5% 回差策略的 helper 运行时。
///
/// 策略函数仍在共享层。这个类只负责读取系统、执行动作和持久化用户意图。
final class ChargeLimitRuntimeController: ChargeLimitRuntimeControlling, @unchecked Sendable {
    private let queueKey = DispatchSpecificKey<Void>()

    private let backend: ChargeLimitBackend
    private let powerReader: ChargeLimitPowerReadingSource
    private let stateStore: ChargeLimitRuntimeStateStore
    private let activeDischargePort: any ChargeLimitActiveDischargePort
    private let intervalSeconds: TimeInterval
    private let activeDischargeNudgeDelaySeconds: TimeInterval
    private let activeDischargeNudgeCooldownSeconds: TimeInterval
    private let queue = DispatchQueue(label: "com.wyz.covio.charge-limit-runtime")
    private var timer: DispatchSourceTimer?
    private var bypassEngaged = false
    private var activeDischargeNudgePending = false
    private var lastActiveDischargeNudgeAt: Date?
    private var targetMismatchSince: Date?

    init(
        backend: ChargeLimitBackend,
        powerReader: ChargeLimitPowerReadingSource,
        stateStore: ChargeLimitRuntimeStateStore,
        activeDischargePort: any ChargeLimitActiveDischargePort,
        intervalSeconds: TimeInterval = 5,
        activeDischargeNudgeDelaySeconds: TimeInterval = 8,
        activeDischargeNudgeCooldownSeconds: TimeInterval = 120
    ) {
        self.backend = backend
        self.powerReader = powerReader
        self.stateStore = stateStore
        self.activeDischargePort = activeDischargePort
        self.intervalSeconds = max(0.1, intervalSeconds)
        self.activeDischargeNudgeDelaySeconds = max(0, activeDischargeNudgeDelaySeconds)
        self.activeDischargeNudgeCooldownSeconds = max(0, activeDischargeNudgeCooldownSeconds)
        queue.setSpecific(key: queueKey, value: ())
    }

    /// helper 启动后恢复上次配置。
    func resumeOnStartup() -> Result<Void, ChargeLimitMCLFailure> {
        syncOnQueue {
            do {
                guard try stateStore.load() != nil else {
                    _ = activeDischargePort.release()
                    return .success(())
                }
            } catch let failure as ChargeLimitMCLFailure {
                _ = activeDischargePort.release()
                return .failure(failure)
            } catch {
                _ = activeDischargePort.release()
                return .failure(.stateUnreadable)
            }
            startTimerLocked()
            switch evaluateLocked(recoveringFromStartup: true) {
            case .success:
                return .success(())
            case .failure(let failure):
                return .failure(failure)
            }
        }
    }

    func status() -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure> {
        syncOnQueue { statusLocked() }
    }

    func configure(
        userLimitPercent: Int,
        activeDischargeEnabled: Bool
    ) -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure> {
        guard ChargeLimitPolicy.shared.isValidUpperLimit(percent: Int32(userLimitPercent)) else {
            return .failure(.invalidTarget(userLimitPercent))
        }
        if activeDischargeEnabled, !activeDischargePort.capability() {
            return .failure(.readbackFailed("CHIE active discharge support"))
        }
        return syncOnQueue {
            targetMismatchSince = nil
            let state = ChargeLimitRuntimeState(
                userLimitPercent: userLimitPercent,
                chargingLatch: activeDischargeEnabled,
                lastPhase: "applying",
                activeDischargeEnabled: activeDischargeEnabled
            )
            do {
                try stateStore.save(state)
            } catch let failure as ChargeLimitMCLFailure {
                return .failure(failure)
            } catch {
                return .failure(.stateWriteFailed)
            }
            startTimerLocked()
            switch evaluateLocked(explicitUserRequest: true) {
            case .success:
                return statusLocked()
            case .failure(let failure):
                _ = rollbackConfigurationLocked()
                return .failure(failure)
            }
        }
    }

    func restore() -> Result<Void, ChargeLimitMCLFailure> {
        syncOnQueue {
            activeDischargeNudgePending = false
            targetMismatchSince = nil
            stopTimerLocked()
            guard activeDischargePort.release() else {
                return .failure(.readbackFailed("CHIE release"))
            }
            let restored = backend.restore()
            guard case .success = restored else { return restored }
            do {
                try stateStore.clear()
            } catch let failure as ChargeLimitMCLFailure {
                return .failure(failure)
            } catch {
                return .failure(.stateWriteFailed)
            }
            bypassEngaged = false
            return .success(())
        }
    }

    /// helper 退出时只释放临时旁路，保留 macOS 执行的 MCL 上限。
    func prepareForExit() {
        syncOnQueue {
            activeDischargeNudgePending = false
            stopTimerLocked()
            _ = activeDischargePort.release()
        }
    }

    /// 测试和电源事件使用。调用方不需要等待下一个定时器。
    @discardableResult
    func evaluateNow() -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure> {
        syncOnQueue {
            switch evaluateLocked() {
            case .success:
                return statusLocked()
            case .failure(let failure):
                return .failure(failure)
            }
        }
    }

    private func startTimerLocked() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
        timer.setEventHandler { [weak self] in
            _ = self?.evaluateLocked()
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimerLocked() {
        timer?.cancel()
        timer = nil
    }

    private func evaluateLocked(
        recoveringFromStartup: Bool = false,
        explicitUserRequest: Bool = false
    ) -> Result<Void, ChargeLimitMCLFailure> {
        guard !activeDischargeNudgePending else { return .success(()) }
        let state: ChargeLimitRuntimeState
        do {
            guard let loaded = try stateStore.load() else { return .success(()) }
            state = loaded
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateUnreadable)
        }
        guard let reading = powerReader.read() else {
            return .failure(.readbackFailed("battery power source"))
        }
        let backendState: ChargeLimitPersistentState?
        switch backend.loadState() {
        case .success(let loaded):
            backendState = loaded
        case .failure(let failure):
            return .failure(failure)
        }
        let observedTarget = backend.observedTargetPercent()
        let alreadyEngaged = activeDischargePort.isEngaged() ?? false
        let currentPercent = reading.currentPercent ?? Int.min
        let targetNeedsRepair = state.activeDischargeEnabled == true &&
            observedTarget != state.userLimitPercent
        let keepChieWhileChargingAtLimit = targetNeedsRepair &&
            currentPercent == state.userLimitPercent &&
            reading.isCharging
        let wantsActiveDischarge = state.activeDischargeEnabled == true && (
            (currentPercent > state.userLimitPercent && (reading.adapterConnected || alreadyEngaged)) ||
                keepChieWhileChargingAtLimit
        )
        let releasedActiveDischarge = state.activeDischargeEnabled == true &&
            alreadyEngaged &&
            !wantsActiveDischarge
        if wantsActiveDischarge {
            if !alreadyEngaged, !activeDischargePort.engage() {
                return .failure(.readbackFailed("CHIE active discharge"))
            }
        } else if alreadyEngaged, !activeDischargePort.release() {
            return .failure(.readbackFailed("CHIE release"))
        }
        let effectiveAdapterConnected = reading.adapterConnected || wantsActiveDischarge
        let expectedTarget = effectiveTarget(backendState?.targetPercent)
        let pendingTarget = state.pendingTargetPercent
        let pendingMatchesBackend = pendingTarget != nil && backendState?.targetPercent == pendingTarget
        let pendingSettled = pendingMatchesBackend && observedTarget == pendingTarget
        let hasPendingTarget = pendingMatchesBackend && !pendingSettled
        let returningFromCalibration = state.lastPhase == "calibration" &&
            !reading.calibrationActive &&
            state.calibrationTargetPercent == observedTarget
        let targetWriteMayBeReplaced = recoveringFromStartup ||
            returningFromCalibration ||
            explicitUserRequest
        let targetMayBeReplaced = targetWriteMayBeReplaced || hasPendingTarget
        let resumeThreshold = Int(
            ChargeLimitPolicy.shared.resumeThreshold(
                upperLimitPercent: Int32(state.userLimitPercent)
            )
        )
        let shouldMaintainActiveDischargeTarget =
            currentPercent == state.userLimitPercent ||
            currentPercent > state.userLimitPercent ||
            (currentPercent < state.userLimitPercent &&
                (state.chargingLatch || currentPercent <= resumeThreshold))
        let targetMismatch = state.activeDischargeEnabled == true &&
            shouldMaintainActiveDischargeTarget &&
            reading.batteryPresent &&
            !reading.calibrationActive &&
            !reading.systemProtectionActive &&
            effectiveAdapterConnected &&
            observedTarget != state.userLimitPercent &&
            !targetWriteMayBeReplaced
        if targetMismatch {
            let now = Date()
            if targetMismatchSince == nil {
                targetMismatchSince = now
            }
            let mismatchAge = now.timeIntervalSince(targetMismatchSince ?? now)
            if mismatchAge < activeDischargeNudgeDelaySeconds {
                return saveApplyingStateLocked(
                    state: state,
                    pendingTargetPercent: nil
                )
            }
            if let last = lastActiveDischargeNudgeAt,
               now.timeIntervalSince(last) < activeDischargeNudgeCooldownSeconds {
                return saveApplyingStateLocked(
                    state: state,
                    pendingTargetPercent: nil
                )
            }
            return beginActiveDischargeNudgeLocked(state: state)
        }
        targetMismatchSince = nil
        let observation = ChargeLimitObservation(
            enabled: true,
            upperLimitPercent: Int32(state.userLimitPercent),
            adapterConnected: effectiveAdapterConnected,
            currentPercent: reading.currentPercent.map { Int32($0) },
            helperInstalled: true,
            support: backend.capability(),
            batteryPresent: reading.batteryPresent,
            isCharged: reading.isCharged,
            calibrationActive: reading.calibrationActive,
            systemProtectionActive: reading.systemProtectionActive,
            conflict: backendState != nil && observedTarget != expectedTarget && !targetMayBeReplaced,
            errorMessage: nil,
            observedTargetPercent: observedTarget.map { Int32($0) },
            writePending: hasPendingTarget,
            bypassEngaged: reading.bypassEngaged,
            activeDischargeEnabled: state.activeDischargeEnabled ?? false,
            activelyDischarging: reading.activelyDischarging
        )
        let decision = ChargeLimitPolicy.shared.evaluate(
            observation: observation,
            previous: ChargeLimitPolicyState(
                chargingLatch: state.chargingLatch || releasedActiveDischarge
            )
        )
        bypassEngaged = decision.bypassEngaged
        let updated = ChargeLimitRuntimeState(
            userLimitPercent: state.userLimitPercent,
            chargingLatch: decision.chargingLatch,
            calibrationTargetPercent: reading.calibrationActive ? observedTarget : nil,
            pendingTargetPercent: hasPendingTarget ? pendingTarget : nil,
            lastPhase: phaseName(decision.phase),
            activeDischargeEnabled: state.activeDischargeEnabled
        )
        do {
            try stateStore.save(updated)
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateWriteFailed)
        }

        if decision.action == .setTarget, let target = decision.targetPercent {
            switch backend.apply(targetPercent: Int(target)) {
            case .success:
                return markPendingIfNeededLocked(
                    state: updated,
                    targetPercent: Int(target)
                )
            case .failure(let failure):
                return .failure(failure)
            }
        }
        if decision.action == .releaseTarget {
            switch backend.apply(targetPercent: 100) {
            case .success:
                return .success(())
            case .failure(let failure):
                return .failure(failure)
            }
        }
        if backendState == nil,
           decision.action == .none,
           let target = decision.targetPercent {
            switch backend.apply(targetPercent: Int(target)) {
            case .success:
                return markPendingIfNeededLocked(
                    state: updated,
                    targetPercent: Int(target)
                )
            case .failure(let failure):
                return .failure(failure)
            }
        }
        return .success(())
    }

    private func markPendingIfNeededLocked(
        state: ChargeLimitRuntimeState,
        targetPercent: Int
    ) -> Result<Void, ChargeLimitMCLFailure> {
        if backend.observedTargetPercent() == targetPercent {
            return .success(())
        }
        let pending = ChargeLimitRuntimeState(
            userLimitPercent: state.userLimitPercent,
            chargingLatch: state.chargingLatch,
            calibrationTargetPercent: state.calibrationTargetPercent,
            pendingTargetPercent: targetPercent,
            lastPhase: "applying",
            activeDischargeEnabled: state.activeDischargeEnabled
        )
        do {
            try stateStore.save(pending)
            return .success(())
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateWriteFailed)
        }
    }

    private func beginActiveDischargeNudgeLocked(
        state: ChargeLimitRuntimeState
    ) -> Result<Void, ChargeLimitMCLFailure> {
        let intermediate = min(100, state.userLimitPercent + 1)
        guard intermediate > state.userLimitPercent else {
            return saveApplyingStateLocked(state: state, pendingTargetPercent: state.userLimitPercent)
        }
        switch backend.apply(targetPercent: intermediate) {
        case .success:
            activeDischargeNudgePending = true
            lastActiveDischargeNudgeAt = Date()
            let result = saveApplyingStateLocked(state: state, pendingTargetPercent: nil)
            guard case .success = result else {
                activeDischargeNudgePending = false
                return result
            }
            queue.asyncAfter(deadline: .now() + activeDischargeNudgeDelaySeconds) { [weak self] in
                self?.finishActiveDischargeNudge()
            }
            return .success(())
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private func finishActiveDischargeNudge() {
        activeDischargeNudgePending = false
        let state: ChargeLimitRuntimeState
        do {
            guard let loaded = try stateStore.load() else { return }
            state = loaded
        } catch {
            return
        }
        guard state.activeDischargeEnabled == true else {
            _ = evaluateLocked()
            return
        }
        switch backend.apply(targetPercent: state.userLimitPercent) {
        case .success:
            guard case .success = saveApplyingStateLocked(
                state: state,
                pendingTargetPercent: state.userLimitPercent
            ) else { return }
            _ = evaluateLocked()
        case .failure:
            return
        }
    }

    private func saveApplyingStateLocked(
        state: ChargeLimitRuntimeState,
        pendingTargetPercent: Int?
    ) -> Result<Void, ChargeLimitMCLFailure> {
        let applying = ChargeLimitRuntimeState(
            userLimitPercent: state.userLimitPercent,
            chargingLatch: state.chargingLatch,
            calibrationTargetPercent: state.calibrationTargetPercent,
            pendingTargetPercent: pendingTargetPercent,
            lastPhase: "applying",
            activeDischargeEnabled: state.activeDischargeEnabled
        )
        do {
            try stateStore.save(applying)
            return .success(())
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateWriteFailed)
        }
    }

    /// 新设置失败时停止自动重试，并清除用户意图。后端会恢复首次覆盖前的状态。
    private func rollbackConfigurationLocked() -> ChargeLimitMCLFailure? {
        activeDischargeNudgePending = false
        stopTimerLocked()
        _ = activeDischargePort.release()
        let restored = backend.restore()
        guard case .success = restored else {
            if case .failure(let failure) = restored { return failure }
            return .stateWriteFailed
        }
        do {
            try stateStore.clear()
        } catch let failure as ChargeLimitMCLFailure {
            return failure
        } catch {
            return .stateWriteFailed
        }
        bypassEngaged = false
        return nil
    }

    private func statusLocked() -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure> {
        let state: ChargeLimitRuntimeState?
        do {
            state = try stateStore.load()
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateUnreadable)
        }
        guard let state else {
            return .success(
                ChargeLimitRuntimeStatus(
                    userLimitPercent: 0,
                    effectiveTargetPercent: nil,
                    chargingLatch: false,
                    phase: "off",
                    bypassEngaged: false,
                    original: nil,
                    activeDischargeSupported: activeDischargePort.capability()
                )
            )
        }
        let backendState: ChargeLimitPersistentState?
        switch backend.loadState() {
        case .success(let loaded):
            backendState = loaded
        case .failure(let failure):
            return .failure(failure)
        }
        let observedTarget = backend.observedTargetPercent()
        return .success(
            ChargeLimitRuntimeStatus(
                userLimitPercent: state.userLimitPercent,
                effectiveTargetPercent: effectiveTarget(observedTarget),
                chargingLatch: state.chargingLatch,
                phase: state.lastPhase,
                bypassEngaged: bypassEngaged,
                original: backendState?.original,
                activeDischargeEnabled: state.activeDischargeEnabled ?? false,
                activeDischargeSupported: activeDischargePort.capability()
            )
        )
    }

    /// 后端用 100 表示已经释放 MCL；对策略而言这是“没有目标”。
    private func effectiveTarget(_ target: Int?) -> Int? {
        guard let target, target < 100 else { return nil }
        return target
    }

    private func phaseName(_ phase: ChargeLimitPhase) -> String {
        switch phase {
        case .off: "off"
        case .noBattery: "noBattery"
        case .unplugged: "unplugged"
        case .applying: "applying"
        case .discharging: "discharging"
        case .stoppingDischarge: "stoppingDischarge"
        case .charging: "charging"
        case .sailing: "sailing"
        case .holding: "holding"
        case .aboveLimit: "aboveLimit"
        case .full: "full"
        case .calibration: "calibration"
        case .systemProtection: "systemProtection"
        case .conflict: "conflict"
        case .error: "error"
        case .unsupported: "unsupported"
        case .helperMissing: "helperMissing"
        default: "unknown"
        }
    }

    private func syncOnQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return body()
        }
        return queue.sync(execute: body)
    }
}

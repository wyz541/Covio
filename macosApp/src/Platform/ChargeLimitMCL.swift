import CoreFoundation
import Foundation

enum DirectMCLPreference {
    static let domain = "com.apple.smartcharging.topoffprotection"
    static let keyOptimizedChargingEnabled = "enabled"
    static let keyFeatureState = "MCLFeatureState"
    static let keyLimitValue = "mclLimitValue"
    static let keyCheckpoint = "checkpoint"
    static let keyCurrentState = "currentState"
    static let changedNotification = "com.apple.smartcharging.defaultschanged"
}

/// 直接偏好端口。`80%` 以下使用与真机验证一致的值写入路径。
protocol ChargeLimitPreferenceStore: Sendable {
    func readInt(_ key: String) -> Int?
    func readBool(_ key: String) -> Bool?
    func writeInt(_ key: String, value: Int)
    func writeBool(_ key: String, value: Bool)
    func remove(_ key: String)
    func synchronize() -> Bool
    func notifyChanged()
}

/// helper 以 root 写 CFPreferences。显式同步可避免 `defaults` 子进程与 cfprefsd
/// 的内存缓存不同步，随后再通知 PowerUIAgent 重读。
final class CFPreferencesChargeLimitPreferenceStore: ChargeLimitPreferenceStore, @unchecked Sendable {
    private let domain = DirectMCLPreference.domain as CFString

    func readInt(_ key: String) -> Int? {
        (read(key) as? NSNumber)?.intValue
    }

    func readBool(_ key: String) -> Bool? {
        (read(key) as? NSNumber)?.boolValue
    }

    func writeInt(_ key: String, value: Int) {
        write(key, value: NSNumber(value: value))
    }

    func writeBool(_ key: String, value: Bool) {
        write(key, value: NSNumber(value: value))
    }

    func remove(_ key: String) {
        write(key, value: nil)
    }

    func synchronize() -> Bool {
        CFPreferencesSynchronize(
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }

    func notifyChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(DirectMCLPreference.changedNotification as CFString),
            nil,
            nil,
            true
        )
    }

    private func read(_ key: String) -> CFPropertyList? {
        CFPreferencesCopyValue(
            key as CFString,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }

    private func write(_ key: String, value: CFPropertyList?) {
        CFPreferencesSetValue(
            key as CFString,
            value,
            domain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }
}

/// `pmset` 中 powerd 实际接受的充电目标。PowerUI 先返回新值不代表已经生效。
protocol ChargeLimitSystemTargetReading: Sendable {
    func readTargetPercent() -> Int?
}

final class PmsetChargeLimitSystemTargetReader: ChargeLimitSystemTargetReading, Sendable {
    func readTargetPercent() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "battlimit"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return Self.parseTargetPercent(from: output)
    }

    static func parseTargetPercent(from output: String) -> Int? {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            let rawValue = parts.count == 2
                ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            let normalizedValue = rawValue.hasSuffix(";")
                ? String(rawValue.dropLast())
                : rawValue
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare("chargeSocLimitSoc") == .orderedSame,
                  let value = Int(normalizedValue)
            else {
                continue
            }
            return value
        }
        return nil
    }
}

/// 第一次覆盖前的原值。`nil` 表示键原本不存在，恢复时必须删除。
struct ChargeLimitOriginals: Codable, Equatable {
    var optimizedChargingEnabled: Bool?
    var featureState: Int?
    var limitPercent: Int?
}

/// helper 持久化的策略状态。
struct ChargeLimitPersistentState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var enabled = true
    var targetPercent: Int
    var original: ChargeLimitOriginals
}

enum ChargeLimitMCLFailure: Error, Equatable, CustomStringConvertible {
    case invalidTarget(Int)
    case stateUnreadable
    case stateWriteFailed
    case readbackFailed(String)

    var description: String {
        switch self {
        case .invalidTarget(let value):
            "Invalid charge limit: \(value)"
        case .stateUnreadable:
            "Charge limit state is unreadable"
        case .stateWriteFailed:
            "Charge limit state could not be saved"
        case .readbackFailed(let key):
            "Charge limit preference readback failed: \(key)"
        }
    }
}

/// 只允许 root 读写、原子替换的状态文件。
final class ChargeLimitStateStore {
    private let url: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        url: URL,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    /// 文件不存在返回 nil。文件存在但损坏时抛错，绝不把损坏状态当成首次运行。
    func load() throws -> ChargeLimitPersistentState? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ChargeLimitMCLFailure.stateUnreadable
        }
        guard let state = try? decoder.decode(ChargeLimitPersistentState.self, from: data),
              state.schemaVersion == ChargeLimitPersistentState.currentSchemaVersion
        else {
            throw ChargeLimitMCLFailure.stateUnreadable
        }
        return state
    }

    func save(_ state: ChargeLimitPersistentState) throws {
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

/// helper 使用的 MCL 后端端口。测试注入假实现，不需要 root。
protocol ChargeLimitBackend: Sendable {
    func capability() -> ChargeLimitSupport
    func observedTargetPercent() -> Int?
    func loadState() -> Result<ChargeLimitPersistentState?, ChargeLimitMCLFailure>
    func apply(targetPercent: Int) -> Result<ChargeLimitPersistentState, ChargeLimitMCLFailure>
    func restore() -> Result<Void, ChargeLimitMCLFailure>
}

/// MCL 后端。只做根偏好与状态文件，不接 socket，也不执行当前真机验证。
final class ChargeLimitMCLController: ChargeLimitBackend, @unchecked Sendable {
    private let preferences: ChargeLimitPreferenceStore
    private let stateStore: ChargeLimitStateStore
    private let powerUI: PowerUIChargeReading
    private let systemTarget: ChargeLimitSystemTargetReading
    private let lock = NSLock()
    private let supportedTargetPercent = 40...100
    private let powerUIMinimum = 80
    private let directReadbackTimeout: TimeInterval

    init(
        preferences: ChargeLimitPreferenceStore = CFPreferencesChargeLimitPreferenceStore(),
        stateStore: ChargeLimitStateStore,
        powerUI: PowerUIChargeReading = SystemPowerUIChargeClient(),
        systemTarget: ChargeLimitSystemTargetReading = PmsetChargeLimitSystemTargetReader(),
        directReadbackTimeout: TimeInterval = 4
    ) {
        self.preferences = preferences
        self.stateStore = stateStore
        self.powerUI = powerUI
        self.systemTarget = systemTarget
        self.directReadbackTimeout = max(0, directReadbackTimeout)
    }

    /// 运行时探测系统接口。接口缺失或报告不支持时，策略不得写入。
    func capability() -> ChargeLimitSupport {
        switch powerUI.capability() {
        case .supported: .supported
        case .unsupported: .unsupported
        }
    }

    /// 读取系统当前登记的目标。外部修改由策略转成冲突态，不静默覆盖。
    func observedTargetPercent() -> Int? {
        lock.withLock {
            if powerUI.isMCLEnabled() == false { return nil }
            return systemTarget.readTargetPercent()
        }
    }

    /// 读取上次保存的策略状态。状态文件损坏时明确失败。
    func loadState() -> Result<ChargeLimitPersistentState?, ChargeLimitMCLFailure> {
        lock.withLock { loadStateLocked() }
    }

    /// `targetPercent == 100` 表示 `100%` 模式：释放 MCL，让系统充满。
    func apply(targetPercent: Int) -> Result<ChargeLimitPersistentState, ChargeLimitMCLFailure> {
        lock.withLock { applyLocked(targetPercent: targetPercent) }
    }

    /// 恢复第一次覆盖前的状态。重复调用是成功的空操作。
    func restore() -> Result<Void, ChargeLimitMCLFailure> {
        lock.withLock { restoreLocked() }
    }

    private func loadStateLocked() -> Result<ChargeLimitPersistentState?, ChargeLimitMCLFailure> {
        do {
            return .success(try stateStore.load())
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateUnreadable)
        }
    }

    private func applyLocked(targetPercent: Int) -> Result<ChargeLimitPersistentState, ChargeLimitMCLFailure> {
        guard supportedTargetPercent.contains(targetPercent) else {
            return .failure(.invalidTarget(targetPercent))
        }

        let existing: ChargeLimitPersistentState?
        do {
            existing = try stateStore.load()
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateUnreadable)
        }

        let original = existing?.original ?? captureOriginals()
        let staged = ChargeLimitPersistentState(
            enabled: true,
            targetPercent: targetPercent,
            original: original
        )
        do {
            try stateStore.save(staged)
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateWriteFailed)
        }

        if targetPercent == 100 {
            guard powerUI.disableMCL(), powerUI.isMCLEnabled() == false else {
                _ = restoreLocked()
                return .failure(.readbackFailed("MCL release"))
            }
        } else if targetPercent >= powerUIMinimum {
            guard applyWithPowerUI(targetPercent) else {
                _ = restoreLocked()
                return .failure(.readbackFailed("MCL target"))
            }
        } else {
            guard applyDirect(targetPercent) else {
                _ = restoreLocked()
                return .failure(.readbackFailed("MCL target"))
            }
        }
        return .success(staged)
    }

    private func restoreLocked() -> Result<Void, ChargeLimitMCLFailure> {
        let state: ChargeLimitPersistentState?
        do {
            state = try stateStore.load()
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateUnreadable)
        }
        guard let state else { return .success(()) }

        if state.original.featureState == 1,
           let originalLimit = state.original.limitPercent,
           originalLimit >= powerUIMinimum {
            guard restoreDirectPreferences(state.original) else {
                return .failure(.readbackFailed("original preferences"))
            }
            _ = powerUI.disableMCL()
            guard applyWithPowerUI(originalLimit) else {
                return .failure(.readbackFailed("original MCL target"))
            }
        } else if state.original.featureState == 1,
                  let originalLimit = state.original.limitPercent,
                  supportedTargetPercent.contains(originalLimit) {
            guard applyDirect(originalLimit) else {
                return .failure(.readbackFailed("original MCL target"))
            }
            guard restoreOptimizedCharging(state.original.optimizedChargingEnabled) else {
                return .failure(.readbackFailed("original optimized charging"))
            }
        } else {
            guard restoreDirectPreferences(state.original) else {
                return .failure(.readbackFailed("original preferences"))
            }
            guard powerUI.disableMCL(), powerUI.isMCLEnabled() == false else {
                return .failure(.readbackFailed("MCL release"))
            }
        }
        do {
            try stateStore.clear()
        } catch let failure as ChargeLimitMCLFailure {
            return .failure(failure)
        } catch {
            return .failure(.stateWriteFailed)
        }
        return .success(())
    }

    private func captureOriginals() -> ChargeLimitOriginals {
        let enabled = powerUI.isMCLEnabled()
        let featureState = enabled.map { $0 ? 1 : 0 }
            ?? preferences.readInt(DirectMCLPreference.keyFeatureState)
        return ChargeLimitOriginals(
            optimizedChargingEnabled: preferences.readBool(
                DirectMCLPreference.keyOptimizedChargingEnabled
            ),
            featureState: featureState,
            limitPercent: enabled == true
                ? powerUI.currentLimit()
                : preferences.readInt(DirectMCLPreference.keyLimitValue)
        )
    }

    private func applyWithPowerUI(_ targetPercent: Int) -> Bool {
        guard powerUI.applyLimit(targetPercent) else { return false }
        return waitForPowerUITarget(targetPercent)
    }

    private func applyDirect(_ targetPercent: Int) -> Bool {
        // PowerUI enables MCL and registers the system state. The defaults write then
        // lowers the target. notifyutil makes powerd reread the changed preference.
        if powerUI.isMCLEnabled() != true {
            guard applyWithPowerUI(powerUIMinimum) else { return false }
        }
        preferences.writeBool(DirectMCLPreference.keyOptimizedChargingEnabled, value: false)
        preferences.writeInt(DirectMCLPreference.keyFeatureState, value: 1)
        preferences.writeInt(DirectMCLPreference.keyLimitValue, value: targetPercent)
        preferences.remove(DirectMCLPreference.keyCheckpoint)
        preferences.remove(DirectMCLPreference.keyCurrentState)
        guard preferences.synchronize() else { return false }
        preferences.notifyChanged()
        guard preferences.readBool(DirectMCLPreference.keyOptimizedChargingEnabled) == false,
              preferences.readInt(DirectMCLPreference.keyFeatureState) == 1,
              preferences.readInt(DirectMCLPreference.keyLimitValue) == targetPercent
        else {
            return false
        }

        return waitForPowerUITarget(targetPercent)
    }

    /// PowerUI 先确认写入。powerd 可能等到下一个 1% 步进才执行。
    private func waitForPowerUITarget(_ targetPercent: Int) -> Bool {
        let deadline = Date().addingTimeInterval(directReadbackTimeout)
        repeat {
            if powerUI.isMCLEnabled() == true,
               powerUI.currentLimit() == targetPercent {
                return true
            }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.05)
        } while true
    }

    /// 恢复第一次覆盖前的直接偏好。`nil` 表示原键不存在，必须删除。
    private func restoreDirectPreferences(_ original: ChargeLimitOriginals) -> Bool {
        restoreInt(DirectMCLPreference.keyFeatureState, value: original.featureState)
        restoreInt(DirectMCLPreference.keyLimitValue, value: original.limitPercent)
        restoreBool(
            DirectMCLPreference.keyOptimizedChargingEnabled,
            value: original.optimizedChargingEnabled
        )
        preferences.remove(DirectMCLPreference.keyCheckpoint)
        preferences.remove(DirectMCLPreference.keyCurrentState)
        guard preferences.synchronize() else { return false }
        preferences.notifyChanged()
        return preferences.readInt(DirectMCLPreference.keyFeatureState) == original.featureState &&
            preferences.readInt(DirectMCLPreference.keyLimitValue) == original.limitPercent &&
            preferences.readBool(DirectMCLPreference.keyOptimizedChargingEnabled) ==
                original.optimizedChargingEnabled
    }

    private func restoreOptimizedCharging(_ value: Bool?) -> Bool {
        restoreBool(DirectMCLPreference.keyOptimizedChargingEnabled, value: value)
        guard preferences.synchronize() else { return false }
        preferences.notifyChanged()
        return preferences.readBool(DirectMCLPreference.keyOptimizedChargingEnabled) == value
    }

    private func restoreInt(_ key: String, value: Int?) {
        if let value {
            preferences.writeInt(key, value: value)
        } else {
            preferences.remove(key)
        }
    }

    private func restoreBool(_ key: String, value: Bool?) {
        if let value {
            preferences.writeBool(key, value: value)
        } else {
            preferences.remove(key)
        }
    }
}

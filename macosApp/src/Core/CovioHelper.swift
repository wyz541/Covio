import Foundation

struct HelperReleaseIdentity: Codable, Equatable, Sendable {
    var releaseId: String
    var clientVersion: String
    var productVersion: String
    var buildNumber: String
    var gitCommit: String
    var protocolVersion: String
    var helperSHA256: String
    var channel: String

    enum CodingKeys: String, CodingKey {
        case releaseId
        case clientVersion
        case productVersion
        case buildNumber
        case gitCommit
        case protocolVersion
        case helperSHA256 = "helperSha256"
        case channel
    }

    var resultMap: [String: String] {
        [
            "releaseId": releaseId,
            "clientVersion": clientVersion,
            "productVersion": productVersion,
            "buildNumber": buildNumber,
            "gitCommit": gitCommit,
            "protocolVersion": protocolVersion,
            "helperSHA256": helperSHA256,
            "channel": channel,
        ]
    }
}

final class HelperReleaseHandshake: @unchecked Sendable {
    static let shared = HelperReleaseHandshake()

    func parse(result: [String: String]) -> HelperReleaseIdentity? {
        do {
            let value = try CovioCoreRuntime.shared.call(
                "helper.release.parse",
                payload: ["result": result]
            )
            guard let root = value as? [String: Any],
                  let identity = root["identity"], !(identity is NSNull) else {
                return nil
            }
            return try coreDecode(HelperReleaseIdentity.self, from: identity)
        } catch { return nil }
    }

    func hasIdentityFields(result: [String: String]) -> Bool {
        guard let value = try? CovioCoreRuntime.shared.call(
            "helper.release.hasIdentityFields",
            payload: ["result": result]
        ) as? [String: Any] else {
            return false
        }
        return value["result"] as? Bool ?? false
    }

    func classify(
        expected: HelperReleaseIdentity,
        observed: HelperReleaseIdentity,
        signatureTrusted: Bool
    ) -> HelperStatus {
        do {
            let payload: [String: Any] = [
                "expected": try coreEncode(expected),
                "observed": try coreEncode(observed),
                "signatureTrusted": signatureTrusted,
            ]
            let value = try CovioCoreRuntime.shared.call(
                "helper.release.classify",
                payload: payload
            ) as? [String: Any]
            guard let raw = value?["status"] as? String else { return .untrusted }
            return HelperStatus(rawValue: raw) ?? .untrusted
        } catch { return .untrusted }
    }
}

struct HelperLeaseSnapshot: Codable, Equatable, Sendable {
    var activeLeaseIds: [String] = []
    var expiresAtEpochSeconds: Int64?
    var activeCount: Int { activeLeaseIds.count }
    var hasActiveLease: Bool { !activeLeaseIds.isEmpty }
}

final class HelperLeaseBook: @unchecked Sendable {
    private var leases: [String: Int64] = [:]
    private let lock = NSLock()

    func upsert(
        leaseId: String,
        nowEpochSeconds: Int64,
        expiresAtEpochSeconds: Int64
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let normalized = leaseId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        _ = pruneLocked(now: nowEpochSeconds)
        if leases[normalized] == nil, leases.count >= HelperConstants.shared.leaseMaxActive {
            return false
        }
        if expiresAtEpochSeconds <= nowEpochSeconds {
            leases.removeValue(forKey: normalized)
        } else {
            leases[normalized] = expiresAtEpochSeconds
        }
        return true
    }

    func release(leaseId: String, nowEpochSeconds: Int64) -> HelperLeaseSnapshot {
        lock.lock()
        defer { lock.unlock() }
        _ = pruneLocked(now: nowEpochSeconds)
        leases.removeValue(forKey: leaseId)
        return snapshotLocked()
    }

    func prune(nowEpochSeconds: Int64) -> HelperLeaseSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return pruneLocked(now: nowEpochSeconds)
    }

    func clear() -> HelperLeaseSnapshot {
        lock.lock()
        defer { lock.unlock() }
        leases.removeAll()
        return snapshotLocked()
    }

    func snapshot() -> HelperLeaseSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotLocked()
    }

    private func pruneLocked(now: Int64) -> HelperLeaseSnapshot {
        leases = leases.filter { $0.value > now }
        return snapshotLocked()
    }

    private func snapshotLocked() -> HelperLeaseSnapshot {
        HelperLeaseSnapshot(
            activeLeaseIds: leases.keys.sorted(),
            expiresAtEpochSeconds: leases.values.min()
        )
    }
}

enum HelperStatusPolling {
    static let TIMEOUT_MILLIS: Int64 = 5_000
    static let POLL_INTERVAL_MILLIS: Int64 = 200
}

struct HelperCommandNames: Sendable {
    var version: String
    var setDisableSleep: String
    var setHibernateMode: String
    var lidLeaseAcquire: String
    var lidLeaseRenew: String
    var lidLeaseRelease: String
    var lidLeaseStatus: String
    var chargeLimitStatus: String
    var chargeLimitConfigure: String
    var chargeLimitRestore: String
    var fanControlStatus: String
    var fanControlConfigure: String
    var fanControlKeepAlive: String
    var fanControlRestore: String
    var prepareInstallTransaction: String
}

struct HelperConstants: Sendable {
    static let shared = HelperConstants()

    let protocolVersion: String
    let maxRequestBytes: Int64
    let maxReplyBytes: Int64
    let socketPermissions: Int32
    let leaseIdMaxLength: Int32
    let leaseMaxActive: Int
    let leaseDurationSeconds: Int64
    let leaseRenewSeconds: Int64
    let allowedCommands: Set<String>
    let commands: HelperCommandNames
    let helperArgument: String
    let helperExecutableName: String
    let helperExecutableBundlePath: String
    let daemonPlistName: String
    let xpcServiceName: String
    let socketPath: String
    let helperDirectory: String
    let binaryDirectory: String
    let helperBinaryPath: String
    let chargeLimitDirectory: String
    let chargeLimitStatePath: String
    let chargeLimitRuntimePath: String
    let allowedUidPath: String
    let clientRequirementPath: String
    let versionPath: String
    let appPathFile: String
    let sleepOwnerPath: String
    let sleepOwnerValue: String
    let logPath: String
    let plistPath: String
    let launchDaemonLabel: String

    private init() {
        let value = (try? CovioCoreRuntime.shared.call("helper.constants") as? [String: Any]) ?? [:]
        func string(_ key: String) -> String { value[key] as? String ?? "" }
        func int64(_ key: String) -> Int64 { (value[key] as? NSNumber)?.int64Value ?? 0 }
        let commands = value["commands"] as? [String: String] ?? [:]
        self.protocolVersion = string("protocolVersion")
        self.maxRequestBytes = int64("maxRequestBytes")
        self.maxReplyBytes = int64("maxReplyBytes")
        self.socketPermissions = Int32(int64("socketPermissions"))
        self.leaseIdMaxLength = Int32(int64("leaseIdMaxLength"))
        self.leaseMaxActive = Int(int64("leaseMaxActive"))
        self.leaseDurationSeconds = int64("leaseDurationSeconds")
        self.leaseRenewSeconds = int64("leaseRenewSeconds")
        self.allowedCommands = Set(value["allowedCommands"] as? [String] ?? [])
        self.commands = HelperCommandNames(
            version: commands["version"] ?? "version",
            setDisableSleep: commands["setDisableSleep"] ?? "setDisableSleep",
            setHibernateMode: commands["setHibernateMode"] ?? "setHibernateMode",
            lidLeaseAcquire: commands["lidLeaseAcquire"] ?? "lidLeaseAcquire",
            lidLeaseRenew: commands["lidLeaseRenew"] ?? "lidLeaseRenew",
            lidLeaseRelease: commands["lidLeaseRelease"] ?? "lidLeaseRelease",
            lidLeaseStatus: commands["lidLeaseStatus"] ?? "lidLeaseStatus",
            chargeLimitStatus: commands["chargeLimitStatus"] ?? "chargeLimitStatus",
            chargeLimitConfigure: commands["chargeLimitConfigure"] ?? "chargeLimitConfigure",
            chargeLimitRestore: commands["chargeLimitRestore"] ?? "chargeLimitRestore",
            fanControlStatus: commands["fanControlStatus"] ?? "fanControlStatus",
            fanControlConfigure: commands["fanControlConfigure"] ?? "fanControlConfigure",
            fanControlKeepAlive: commands["fanControlKeepAlive"] ?? "fanControlKeepAlive",
            fanControlRestore: commands["fanControlRestore"] ?? "fanControlRestore",
            prepareInstallTransaction: commands["prepareInstallTransaction"] ?? "prepareInstallTransaction"
        )
        self.helperArgument = string("helperArgument")
        self.helperExecutableName = string("helperExecutableName")
        self.helperExecutableBundlePath = string("helperExecutableBundlePath")
        self.daemonPlistName = string("daemonPlistName")
        self.xpcServiceName = string("xpcServiceName")
        self.socketPath = string("socketPath")
        self.helperDirectory = string("helperDirectory")
        self.binaryDirectory = string("binaryDirectory")
        self.helperBinaryPath = string("helperBinaryPath")
        self.chargeLimitDirectory = string("chargeLimitDirectory")
        self.chargeLimitStatePath = string("chargeLimitStatePath")
        self.chargeLimitRuntimePath = string("chargeLimitRuntimePath")
        self.allowedUidPath = string("allowedUidPath")
        self.clientRequirementPath = string("clientRequirementPath")
        self.versionPath = string("versionPath")
        self.appPathFile = string("appPathFile")
        self.sleepOwnerPath = string("sleepOwnerPath")
        self.sleepOwnerValue = string("sleepOwnerValue")
        self.logPath = string("logPath")
        self.plistPath = string("plistPath")
        self.launchDaemonLabel = string("launchDaemonLabel")
    }
}

enum CovioHelperContract {
    static var HELPER_PROTOCOL_VERSION: String { HelperConstants.shared.protocolVersion }
    static var HELPER_ARGUMENT: String { HelperConstants.shared.helperArgument }
    static var HELPER_EXECUTABLE_NAME: String { HelperConstants.shared.helperExecutableName }
    static var HELPER_EXECUTABLE_BUNDLE_PATH: String { HelperConstants.shared.helperExecutableBundlePath }
    static var HELPER_DAEMON_PLIST_NAME: String { HelperConstants.shared.daemonPlistName }
    static var HELPER_XPC_SERVICE_NAME: String { HelperConstants.shared.xpcServiceName }
    static var HELPER_SOCKET_PATH: String { HelperConstants.shared.socketPath }
    static var HELPER_DIRECTORY: String { HelperConstants.shared.helperDirectory }
    static var HELPER_BINARY_DIRECTORY: String { HelperConstants.shared.binaryDirectory }
    static var HELPER_BINARY_PATH: String { HelperConstants.shared.helperBinaryPath }
    static var HELPER_CHARGE_LIMIT_DIRECTORY: String { HelperConstants.shared.chargeLimitDirectory }
    static var HELPER_CHARGE_LIMIT_STATE_PATH: String { HelperConstants.shared.chargeLimitStatePath }
    static var HELPER_CHARGE_LIMIT_RUNTIME_PATH: String { HelperConstants.shared.chargeLimitRuntimePath }
    static var HELPER_ALLOWED_UID_PATH: String { HelperConstants.shared.allowedUidPath }
    static var HELPER_CLIENT_REQUIREMENT_PATH: String { HelperConstants.shared.clientRequirementPath }
    static var HELPER_VERSION_PATH: String { HelperConstants.shared.versionPath }
    static var HELPER_APP_PATH_FILE: String { HelperConstants.shared.appPathFile }
    static var HELPER_SLEEP_OWNER_PATH: String { HelperConstants.shared.sleepOwnerPath }
    static var HELPER_SLEEP_OWNER_VALUE: String { HelperConstants.shared.sleepOwnerValue }
    static var HELPER_LEASE_DURATION_SECONDS: Int64 { HelperConstants.shared.leaseDurationSeconds }
    static var HELPER_LEASE_RENEW_SECONDS: Int64 { HelperConstants.shared.leaseRenewSeconds }
    static var HELPER_LEASE_ID_MAX_LENGTH: Int32 { HelperConstants.shared.leaseIdMaxLength }
    static var HELPER_LEASE_MAX_ACTIVE: Int32 { Int32(HelperConstants.shared.leaseMaxActive) }
    static var HELPER_LOG_PATH: String { HelperConstants.shared.logPath }
    static var HELPER_PLIST_PATH: String { HelperConstants.shared.plistPath }
    static var HELPER_LAUNCH_DAEMON_LABEL: String { HelperConstants.shared.launchDaemonLabel }
    static var HELPER_ALLOWED_COMMANDS: Set<String> { HelperConstants.shared.allowedCommands }
}

enum CovioRuntimeConstants {
    static var SUPPORTED_HIBERNATE_MODES: Set<Int32> {
        Set([Int32(0), 3, 25])
    }
}

enum CovioReleaseIdentity {
    static let APP_VERSION = GeneratedReleaseIdentity.clientVersion
    static let APP_PRODUCT_VERSION = GeneratedReleaseIdentity.productVersion
    static let APP_BUILD_NUMBER = Int64(GeneratedReleaseIdentity.buildNumber)
    static let APP_RELEASE_CHANNEL = GeneratedReleaseIdentity.channel
}

final class HelperWire: @unchecked Sendable {
    static let shared = HelperWire()

    var MAX_REQUEST_BYTES: Int64 { HelperConstants.shared.maxRequestBytes }
    var MAX_REPLY_BYTES: Int64 { HelperConstants.shared.maxReplyBytes }
    var SOCKET_PERMISSIONS: Int32 { HelperConstants.shared.socketPermissions }
    var COMMAND_VERSION: String { HelperConstants.shared.commands.version }
    var COMMAND_SET_DISABLE_SLEEP: String { HelperConstants.shared.commands.setDisableSleep }
    var COMMAND_SET_HIBERNATE_MODE: String { HelperConstants.shared.commands.setHibernateMode }
    var COMMAND_LID_LEASE_ACQUIRE: String { HelperConstants.shared.commands.lidLeaseAcquire }
    var COMMAND_LID_LEASE_RENEW: String { HelperConstants.shared.commands.lidLeaseRenew }
    var COMMAND_LID_LEASE_RELEASE: String { HelperConstants.shared.commands.lidLeaseRelease }
    var COMMAND_LID_LEASE_STATUS: String { HelperConstants.shared.commands.lidLeaseStatus }
    var COMMAND_CHARGE_LIMIT_STATUS: String { HelperConstants.shared.commands.chargeLimitStatus }
    var COMMAND_CHARGE_LIMIT_CONFIGURE: String { HelperConstants.shared.commands.chargeLimitConfigure }
    var COMMAND_CHARGE_LIMIT_RESTORE: String { HelperConstants.shared.commands.chargeLimitRestore }
    var COMMAND_FAN_CONTROL_STATUS: String { HelperConstants.shared.commands.fanControlStatus }
    var COMMAND_FAN_CONTROL_CONFIGURE: String { HelperConstants.shared.commands.fanControlConfigure }
    var COMMAND_FAN_CONTROL_KEEP_ALIVE: String { HelperConstants.shared.commands.fanControlKeepAlive }
    var COMMAND_FAN_CONTROL_RESTORE: String { HelperConstants.shared.commands.fanControlRestore }
    var COMMAND_PREPARE_INSTALL_TRANSACTION: String { HelperConstants.shared.commands.prepareInstallTransaction }
    var ERROR_UNSUPPORTED_PROTOCOL: String { "Unsupported protocol version" }
    var ERROR_EXTERNAL_DISPLAY: String { "Closed lid lease is blocked while an external display is connected" }
    var ERROR_CANNOT_READ_EXTERNAL_DISPLAY: String { "Cannot read external display count" }
    var ERROR_EXTERNAL_SLEEP_CONFLICT: String { "SleepDisabled is owned by an external tool" }
    var ERROR_CANNOT_READ_SLEEP_DISABLED: String { "Cannot read SleepDisabled" }
    var ERROR_CANNOT_WRITE_SLEEP_DISABLED: String { "Cannot write SleepDisabled" }
    var ERROR_CANNOT_READ_OWNERSHIP: String { "Cannot read SleepDisabled ownership" }
    var ERROR_TOO_MANY_LEASES: String { "Too many active lid leases" }

    func encodeRequest(request: HelperRequest) -> String {
        if let sourceLine = request.sourceLine {
            guard let value = try? CovioCoreRuntime.shared.call(
                "helper.reencodeRequest",
                payload: ["line": sourceLine]
            ) as? [String: Any] else { return "" }
            return value["line"] as? String ?? ""
        }
        do {
            let value = try CovioCoreRuntime.shared.call(
                "helper.encodeRequest",
                payload: ["request": try coreEncode(request)]
            ) as? [String: Any]
            return value?["line"] as? String ?? ""
        } catch { return "" }
    }

    func decodeRequest(line: String) -> HelperRequest? {
        guard let value = try? CovioCoreRuntime.shared.call(
            "helper.decodeRequest",
            payload: ["line": line]
        ) as? [String: Any],
              let request = value["request"], !(request is NSNull) else { return nil }
        guard var decoded = try? coreDecode(HelperRequest.self, from: request) else { return nil }
        decoded.sourceLine = line
        return decoded
    }

    func encodeReply(reply: HelperReply) -> String {
        if let sourceLine = reply.sourceLine { return sourceLine }
        do {
            let value = try CovioCoreRuntime.shared.call(
                "helper.encodeReply",
                payload: ["reply": try coreEncode(reply)]
            ) as? [String: Any]
            return value?["line"] as? String ?? ""
        } catch { return "" }
    }

    func decodeReply(line: String) -> HelperReply? {
        guard let value = try? CovioCoreRuntime.shared.call(
            "helper.decodeReply",
            payload: ["line": line]
        ) as? [String: Any],
              let reply = value["reply"], !(reply is NSNull) else { return nil }
        return try? coreDecode(HelperReply.self, from: reply)
    }

    func success(requestId: String, result: [String: String] = [:]) -> HelperReply {
        do {
            let value = try CovioCoreRuntime.shared.call(
                "helper.success",
                payload: ["requestId": requestId, "result": result]
            ) as? [String: Any]
            return try coreDecode(HelperReply.self, from: value?["reply"] ?? [:])
        } catch {
            return HelperReply(version: HelperProtocol.protocolVersion, requestId: requestId, ok: false, result: nil, error: "Internal error")
        }
    }

    func failure(requestId: String, message: String) -> HelperReply {
        do {
            let value = try CovioCoreRuntime.shared.call(
                "helper.failure",
                payload: ["requestId": requestId, "message": message]
            ) as? [String: Any]
            return try coreDecode(HelperReply.self, from: value?["reply"] ?? [:])
        } catch {
            return HelperReply(version: HelperProtocol.protocolVersion, requestId: requestId, ok: false, result: nil, error: message)
        }
    }

    func versionReply(requestId: String) -> HelperReply {
        do {
            let value = try CovioCoreRuntime.shared.call(
                "helper.versionReply",
                payload: [
                    "requestId": requestId,
                    "appVersion": CovioReleaseIdentity.APP_VERSION,
                ]
            ) as? [String: Any]
            var reply = try coreDecode(HelperReply.self, from: value?["reply"] ?? [:])
            reply.sourceLine = value?["line"] as? String
            return reply
        } catch {
            return HelperReply(
                version: HelperProtocol.protocolVersion,
                requestId: requestId,
                ok: false,
                result: nil,
                error: "Internal error"
            )
        }
    }

    func versionReply(requestId: String, identity: HelperReleaseIdentity) -> HelperReply {
        success(requestId: requestId, result: identity.resultMap)
    }

    func leaseStatusReply(
        requestId: String,
        sleepDisabled: Bool?,
        covioOwned: Bool?,
        activeLeaseCount: Int32,
        expiresAtEpochSeconds: Int64?
    ) -> HelperReply {
        var result = [
            "activeLeaseCount": String(max(0, activeLeaseCount)),
            "sleepDisabled": sleepDisabled.map(String.init) ?? "unknown",
            "covioOwned": covioOwned.map(String.init) ?? "unknown",
        ]
        if let expiresAtEpochSeconds {
            result["expiresAtEpochSeconds"] = String(expiresAtEpochSeconds)
        }
        return success(requestId: requestId, result: result)
    }

    func validate(request: HelperRequest) -> String? {
        guard let value = try? CovioCoreRuntime.shared.call(
            "helper.validate",
            payload: ["request": (try? coreEncode(request)) ?? [:]]
        ) as? [String: Any] else { return "Internal error" }
        return value["error"] as? String
    }

    func pmsetArguments(request: HelperRequest) -> [String]? {
        guard let value = try? CovioCoreRuntime.shared.call(
            "helper.pmsetArguments",
            payload: ["request": (try? coreEncode(request)) ?? [:]]
        ) as? [String: Any],
              let arguments = value["arguments"], !(arguments is NSNull) else { return nil }
        return arguments as? [String]
    }

    func disableSleepArguments(disabled: Bool) -> [String] {
        guard let value = try? CovioCoreRuntime.shared.call(
            "helper.disableSleepArguments",
            payload: ["disabled": disabled]
        ) as? [String: Any] else { return ["-a", "disablesleep", disabled ? "1" : "0"] }
        return value["arguments"] as? [String] ?? []
    }

    func pmsetReply(requestId: String, exitCode: Int32, output: String) -> HelperReply {
        do {
            let value = try CovioCoreRuntime.shared.call(
                "helper.pmsetReply",
                payload: ["requestId": requestId, "exitCode": exitCode, "output": output]
            ) as? [String: Any]
            return try coreDecode(HelperReply.self, from: value?["reply"] ?? [:])
        } catch {
            return failure(requestId: requestId, message: "pmset reply failed")
        }
    }

    func isChargeLimitCommand(command: String) -> Bool {
        [COMMAND_CHARGE_LIMIT_STATUS, COMMAND_CHARGE_LIMIT_CONFIGURE, COMMAND_CHARGE_LIMIT_RESTORE].contains(command)
    }

    func isFanControlCommand(command: String) -> Bool {
        [COMMAND_FAN_CONTROL_STATUS, COMMAND_FAN_CONTROL_CONFIGURE,
         COMMAND_FAN_CONTROL_KEEP_ALIVE, COMMAND_FAN_CONTROL_RESTORE].contains(command)
    }

    func requiresClientSignature(command: String) -> Bool {
        isChargeLimitCommand(command: command) || isFanControlCommand(command: command) || command == COMMAND_PREPARE_INSTALL_TRANSACTION
    }
}

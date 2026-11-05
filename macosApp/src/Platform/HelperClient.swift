import AppKit
import Foundation

/// 特权 helper 客户端。
///
/// 新服务通过 XPC 通信；检测到 legacy helper 时回退到 Unix socket。
/// 两条 transport 使用同一套共享层线协议。
/// 对外语义一致：超时或失败返回 nil，不抛异常。
///
/// 线上格式与校验在共享层的 `HelperWire`，两端的客户端发同样的字节。
final class HelperClient: @unchecked Sendable {
    private enum Transport {
        case socket(String)
        case xpc(HelperXPCClient)
        case automatic(socketPath: String, xpc: HelperXPCClient)
    }

    /// helper 的 socket 路径。`PrivilegedOps` 用它判断「装没装」，
    /// 测试也用它指向一个临时的假 helper。
    let socketPath: String
    private let timeout: TimeInterval
    private let transport: Transport

    var canReachHelper: Bool {
        usesXPC || FileManager.default.fileExists(atPath: socketPath)
    }

    init() {
        socketPath = HelperProtocol.socketPath
        timeout = 2
        transport = .automatic(
            socketPath: HelperProtocol.socketPath,
            xpc: HelperXPCClient(serviceName: HelperProtocol.xpcServiceName)
        )
    }

    init(socketPath: String, timeoutMillis: Int = 2_000) {
        self.socketPath = socketPath
        self.timeout = TimeInterval(timeoutMillis) / 1_000
        transport = .socket(socketPath)
    }

    init(xpcServiceName: String, timeoutMillis: Int = 2_000) {
        socketPath = HelperProtocol.socketPath
        timeout = TimeInterval(timeoutMillis) / 1_000
        transport = .xpc(HelperXPCClient(serviceName: xpcServiceName))
    }

    func request(
        command: String,
        payload: [String: String] = [:],
        protocolVersion: String = HelperProtocol.protocolVersion,
        timeoutMillis: Int? = nil
    ) -> HelperReply? {
        let requestTimeout = timeoutMillis.map { TimeInterval($0) / 1_000 } ?? timeout
        guard requestTimeout > 0 else { return nil }

        let request = HelperRequest(
            version: protocolVersion,
            requestId: UUID().uuidString,
            command: command,
            payload: payload
        )
        return transact(
            HelperWire.shared.encodeRequest(request: request) + "\n",
            timeout: requestTimeout
        )?.reply
    }

    /// 使用 v1 `version` 探测 helper，并保留 socket 对端 PID 供签名校验。
    func versionProbe() -> HelperVersionProbe? {
        let request = HelperRequest(
            version: "1",
            requestId: UUID().uuidString,
            command: HelperWire.shared.COMMAND_VERSION,
            payload: [:]
        )
        guard let transaction = transact(
            HelperWire.shared.encodeRequest(request: request) + "\n",
            timeout: timeout
        ), transaction.reply.ok
        else {
            return nil
        }
        return HelperVersionProbe(
            result: transaction.reply.result ?? [:],
            peerPID: transaction.peerPID,
            transportTrusted: transaction.transportTrusted
        )
    }

    /// 使用 v1 `version` 探测旧 helper。新 helper 保留这一条只读兼容路径。
    func versionInfo() -> HelperVersionInfo? {
        guard let probe = versionProbe(), let version = probe.result["version"] else {
            return nil
        }
        return HelperVersionInfo(
            version: version,
            protocolVersion: probe.result["protocolVersion"]
        )
    }

    func version() -> String? { versionInfo()?.version }

    func acquireLidLease(leaseId: String, externalDisplayCount: Int) -> LidLeaseStatus {
        leaseRequest(
            command: HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE,
            leaseId: leaseId,
            externalDisplayCount: externalDisplayCount
        )
    }

    func renewLidLease(leaseId: String, externalDisplayCount: Int) -> LidLeaseStatus {
        leaseRequest(
            command: HelperWire.shared.COMMAND_LID_LEASE_RENEW,
            leaseId: leaseId,
            externalDisplayCount: externalDisplayCount
        )
    }

    func releaseLidLease(leaseId: String) -> LidLeaseStatus {
        lidLeaseStatus(from: request(
            command: HelperWire.shared.COMMAND_LID_LEASE_RELEASE,
            payload: ["leaseId": leaseId]
        ))
    }

    func lidLeaseStatus() -> LidLeaseStatus {
        lidLeaseStatus(from: request(command: HelperWire.shared.COMMAND_LID_LEASE_STATUS))
    }

    func setHibernateMode(mode: Int) -> Bool {
        request(command: "setHibernateMode", payload: ["mode": String(mode)])?.ok == true
    }

    func setDisableSleep(disabled: Bool) -> Bool {
        request(command: "setDisableSleep", payload: ["disabled": disabled ? "true" : "false"])?.ok == true
    }

    private func leaseRequest(
        command: String,
        leaseId: String,
        externalDisplayCount: Int
    ) -> LidLeaseStatus {
        lidLeaseStatus(from: request(
            command: command,
            payload: [
                "leaseId": leaseId,
                "externalDisplayCount": String(externalDisplayCount),
            ]
        ))
    }

    private func lidLeaseStatus(from reply: HelperReply?) -> LidLeaseStatus {
        guard let reply else {
            return LidLeaseStatus(
                available: FileManager.default.fileExists(atPath: socketPath),
                protocolVersion: HelperProtocol.protocolVersion,
                sleepDisabled: nil,
                covioOwned: nil,
                activeLeaseCount: 0,
                expiresAtEpochSeconds: nil,
                error: "Helper did not respond"
            )
        }
        guard reply.ok else {
            return LidLeaseStatus(
                available: true,
                protocolVersion: HelperProtocol.protocolVersion,
                sleepDisabled: nil,
                covioOwned: nil,
                activeLeaseCount: 0,
                expiresAtEpochSeconds: nil,
                error: reply.error
            )
        }
        let result = reply.result ?? [:]
        return LidLeaseStatus(
            available: true,
            protocolVersion: result["protocolVersion"] ?? HelperProtocol.protocolVersion,
            sleepDisabled: boolValue(result["sleepDisabled"]),
            covioOwned: boolValue(result["covioOwned"]),
            activeLeaseCount: Int32(result["activeLeaseCount"] ?? "0") ?? 0,
            expiresAtEpochSeconds: Int64(result["expiresAtEpochSeconds"] ?? ""),
            error: nil
        )
    }

    private func boolValue(_ value: String?) -> Bool? {
        switch value {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    func chargeLimitStatus() -> ChargeLimitHelperStatus? {
        guard let reply = request(command: "chargeLimitStatus", timeoutMillis: 3_000), reply.ok,
              let enabled = reply.result?["enabled"].flatMap(Bool.init)
        else {
            return nil
        }
        return ChargeLimitHelperStatus(
            enabled: enabled,
            userLimitPercent: reply.result?["userLimitPercent"].flatMap(Int.init),
            targetPercent: reply.result?["targetPercent"].flatMap(Int.init),
            chargingLatch: reply.result?["chargingLatch"].flatMap(Bool.init) ?? false,
            phase: reply.result?["phase"] ?? "unknown",
            bypassEngaged: reply.result?["bypassEngaged"].flatMap(Bool.init) ?? false,
            originalFeatureState: reply.result?["originalFeatureState"].flatMap(Int.init),
            originalLimitPercent: reply.result?["originalLimitPercent"].flatMap(Int.init),
            originalOptimizedChargingEnabled: reply.result?["originalOptimizedChargingEnabled"]
                .flatMap(Bool.init),
            activeDischargeEnabled: reply.result?["activeDischarge"].flatMap(Bool.init) ?? false,
            activeDischargeSupported: reply.result?["activeDischargeSupported"]
                .flatMap(Bool.init) ?? false
        )
    }

    func setChargeLimit(percent: Int, activeDischarge: Bool) -> Bool {
        request(
            command: "chargeLimitConfigure",
            payload: [
                "percent": String(percent),
                "activeDischarge": activeDischarge ? "true" : "false",
            ],
            timeoutMillis: 20_000
        )?.ok == true
    }

    func setChargeLimit(percent: Int) -> Bool {
        setChargeLimit(percent: percent, activeDischarge: false)
    }

    func restoreChargeLimit() -> Bool {
        request(command: "chargeLimitRestore", timeoutMillis: 20_000)?.ok == true
    }

    /// 升级前让 helper 恢复风扇、充电上限和合盖租约。
    func prepareInstallTransaction() -> Bool {
        request(
            command: HelperWire.shared.COMMAND_PREPARE_INSTALL_TRANSACTION,
            timeoutMillis: 30_000
        )?.ok == true
    }

    // MARK: - 私有

    private func transact(_ line: String, timeout: TimeInterval) -> HelperTransaction? {
        if usesXPC {
            guard let reply = xpcClient.transact(line, timeout: timeout) else { return nil }
            return HelperTransaction(reply: reply, peerPID: nil, transportTrusted: true)
        }
        let descriptor = connect(timeout: timeout)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        let peerPID = HelperSignature.peerPID(of: descriptor)

        guard UnixSocketIO.writeAll(descriptor, line) else { return nil }
        guard let response = UnixSocketIO.readLine(
            descriptor,
            limit: Int(HelperWire.shared.MAX_REPLY_BYTES)
        ) else { return nil }
        guard let reply = HelperWire.shared.decodeReply(line: response) else { return nil }
        return HelperTransaction(reply: reply, peerPID: peerPID, transportTrusted: false)
    }

    private var usesXPC: Bool {
        switch transport {
        case .xpc:
            true
        case .socket:
            false
        case .automatic:
            SMAppHelperServiceManager.shared.state.allowsXPC
        }
    }

    private var xpcClient: HelperXPCClient {
        switch transport {
        case .xpc(let client), .automatic(_, let client):
            client
        case .socket:
            preconditionFailure("XPC client is unavailable for a socket-only HelperClient")
        }
    }

    private func connect(timeout: TimeInterval) -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return -1 }

        var noSigPipe: Int32 = 1
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )

        // 秒与微秒分开设，内核到点就返回，不需要自己算 deadline。
        var limit = timeval(
            tv_sec: Int(timeout),
            tv_usec: suseconds_t((timeout - Double(Int(timeout))) * 1_000_000)
        )
        let limitSize = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &limit, limitSize)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, limitSize)

        guard let address = UnixSocketAddress(path: socketPath) else {
            close(descriptor)
            return -1
        }
        let result = address.withSockaddr { pointer, length in
            Darwin.connect(descriptor, pointer, length)
        }
        guard result == 0 else {
            close(descriptor)
            return -1
        }
        return descriptor
    }
}

protocol FanControlLeaseClient: AnyObject {
    var allowsFanControlWrites: Bool { get }
    func keepAliveFanControl() -> FanControlHelperStatus?
    func configureFanControl(_ configuration: MonitorFanConfiguration) -> FanControlCommandResult
    func restoreFanControl() -> FanControlCommandResult
}

extension HelperClient: FanControlLeaseClient {
    var allowsFanControlWrites: Bool {
        HelperReleaseInspector.inspect(client: self).allowsPrivilegedWrites
    }
}

private struct HelperTransaction {
    let reply: HelperReply
    let peerPID: pid_t?
    let transportTrusted: Bool
}

struct HelperVersionInfo {
    let version: String
    let protocolVersion: String?
}

struct HelperVersionProbe {
    let result: [String: String]
    let peerPID: pid_t?
    let transportTrusted: Bool
}

/// 充电上限 helper 客户端端口。测试替换这个端口，避免连接真实 helper。
protocol ChargeLimitClientProtocol: Sendable {
    func chargeLimitStatus() -> ChargeLimitHelperStatus?
    func setChargeLimit(percent: Int, activeDischarge: Bool) -> Bool
    func restoreChargeLimit() -> Bool
}

extension HelperClient: ChargeLimitClientProtocol {}

/// `HelperClient.chargeLimitStatus()` 解析后的结果。
struct ChargeLimitHelperStatus: Equatable, Sendable {
    let enabled: Bool
    let userLimitPercent: Int?
    let targetPercent: Int?
    let chargingLatch: Bool
    let phase: String
    let bypassEngaged: Bool
    let originalFeatureState: Int?
    let originalLimitPercent: Int?
    let originalOptimizedChargingEnabled: Bool?
    var activeDischargeEnabled: Bool = false
    var activeDischargeSupported: Bool = false
}

// MARK: - Fan control

struct FanControlHelperStatus: Equatable, Sendable {
    let active: Bool
    let mode: String
    let controlTemperature: Double?
    let leaseRemainingSeconds: Int
    let error: String?
    var sourceTemperatures: [String: Double] = [:]
}

struct FanControlCommandResult: Equatable, Sendable {
    let ok: Bool
    let message: String?
    let status: FanControlHelperStatus?
}

extension HelperClient {
    func fanControlStatus() -> FanControlHelperStatus? {
        guard let reply = request(
            command: HelperWire.shared.COMMAND_FAN_CONTROL_STATUS,
            timeoutMillis: 2_000
        ), reply.ok else { return nil }
        return Self.fanControlStatus(from: reply.result ?? [:])
    }

    func configureFanControl(_ configuration: MonitorFanConfiguration) -> FanControlCommandResult {
        let reply = request(
            command: HelperWire.shared.COMMAND_FAN_CONTROL_CONFIGURE,
            payload: configuration.helperPayload(),
            timeoutMillis: 30_000
        )
        return FanControlCommandResult(
            ok: reply?.ok == true,
            message: reply?.error,
            status: reply?.result.map(Self.fanControlStatus)
        )
    }

    func keepAliveFanControl() -> FanControlHelperStatus? {
        guard let reply = request(
            command: HelperWire.shared.COMMAND_FAN_CONTROL_KEEP_ALIVE,
            timeoutMillis: 2_000
        ), reply.ok else { return nil }
        return Self.fanControlStatus(from: reply.result ?? [:])
    }

    func restoreFanControl() -> FanControlCommandResult {
        let reply = request(
            command: HelperWire.shared.COMMAND_FAN_CONTROL_RESTORE,
            timeoutMillis: 5_000
        )
        return FanControlCommandResult(
            ok: reply?.ok == true,
            message: reply?.error,
            status: reply?.result.map(Self.fanControlStatus)
        )
    }

    private static func fanControlStatus(from result: [String: String]) -> FanControlHelperStatus {
        let sourceTemperatures = result["sourceTemperatures"]
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) }
            ?? [:]
        return FanControlHelperStatus(
            active: result["active"] == "true",
            mode: result["mode"] ?? "system",
            controlTemperature: result["controlTemperature"].flatMap(Double.init),
            leaseRemainingSeconds: result["leaseRemainingSeconds"].flatMap(Int.init) ?? 0,
            error: result["error"],
            sourceTemperatures: sourceTemperatures
        )
    }
}

/// Keeps the helper lease alive while Covio is running.
/// The helper restores system control by itself if this process stops.
final class FanControlLeaseKeeper: @unchecked Sendable {
    static let shared = FanControlLeaseKeeper()

    private let queue = DispatchQueue(label: "com.wyz.covio.fan-control-lease")
    private let client: any FanControlLeaseClient
    private let notificationCenter: NotificationCenter
    private let wakeDelay: TimeInterval
    private var sleepPolicy = FanControlSleepPolicy()
    private var timer: DispatchSourceTimer?
    private var wakeTask: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init(
        client: any FanControlLeaseClient = HelperClient(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        wakeDelay: TimeInterval = 3,
        observeSleepWake: Bool = true
    ) {
        self.client = client
        self.notificationCenter = notificationCenter
        self.wakeDelay = wakeDelay
        if observeSleepWake {
            observers.append(notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.systemWillSleep()
            })
            observers.append(notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.systemDidWake()
            })
        }
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    func start(configuration: MonitorFanConfiguration) {
        queue.async { [weak self] in
            guard let self else { return }
            self.sleepPolicy.start(configuration)
            self.startTimerLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.sleepPolicy.stop()
            self.wakeTask?.cancel()
            self.wakeTask = nil
            self.timer?.cancel()
            self.timer = nil
        }
    }

    /// Called on normal app termination. A crash is covered by the helper lease.
    func stopAndRestore() {
        queue.sync {
            sleepPolicy.stop()
            wakeTask?.cancel()
            wakeTask = nil
            timer?.cancel()
            timer = nil
            _ = client.restoreFanControl()
        }
    }

    func systemWillSleep() {
        queue.async { [weak self] in
            guard let self, self.sleepPolicy.willSleep() != nil else { return }
            self.timer?.cancel()
            self.timer = nil
            _ = self.client.restoreFanControl()
        }
    }

    func systemDidWake() {
        queue.async { [weak self] in
            guard let self, let configuration = self.sleepPolicy.didWake() else { return }
            self.wakeTask?.cancel()
            let task = DispatchWorkItem { [weak self] in
                guard let self, self.sleepPolicy.activeConfiguration != nil else { return }
                let result = self.client.configureFanControl(configuration)
                if result.ok {
                    self.startTimerLocked()
                }
            }
            self.wakeTask = task
            self.queue.asyncAfter(deadline: .now() + self.wakeDelay, execute: task)
        }
    }

    private func startTimerLocked() {
        guard sleepPolicy.activeConfiguration != nil, timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + .seconds(Int(MonitorFanPolicy.heartbeatSeconds)),
            repeating: .seconds(Int(MonitorFanPolicy.heartbeatSeconds))
        )
        source.setEventHandler { [weak self] in
            guard let self, self.client.allowsFanControlWrites else { return }
            _ = self.client.keepAliveFanControl()
        }
        source.resume()
        timer = source
    }
}

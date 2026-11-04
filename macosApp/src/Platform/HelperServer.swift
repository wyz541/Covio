import Foundation

/// 特权 helper 的请求处理器。
///
/// 新 `CovioHelper` 通过 XPC 调用 [process]；legacy `Covio --helper` 继续处理
/// Unix socket，供一次迁移使用。两条 transport 共用同一套校验和命令白名单。
/// 现有设置命令交给 `/usr/bin/pmset`，充电命令交给 MCL 后端。
/// 套接字是 OS 调用，所以这一层在两端各有一份，这是规范允许的重复。
enum HelperServer {
    private static let peerAuthorizer: HelperPeerAuthorizing = CodeSignaturePeerAuthorizer()
    private static let chargeLimitRuntime = ChargeLimitRuntimeController(
        backend: ChargeLimitMCLController(
            stateStore: ChargeLimitStateStore(
                url: URL(fileURLWithPath: HelperProtocol.chargeLimitStatePath)
            )
        ),
        powerReader: MacChargeLimitPowerReader(),
        stateStore: ChargeLimitRuntimeStateStore(
            url: URL(fileURLWithPath: HelperProtocol.chargeLimitRuntimePath)
        ),
        activeDischargePort: SMCChargeLimitActiveDischarge()
    )
    private static let chargeLimitHandler = ChargeLimitHelperCommandHandler(
        runtime: chargeLimitRuntime
    )

    /// 阻塞运行，直到进程被信号终止。返回进程退出码。
    static func run() -> Int32 {
        // 启动时立即冻结身份。若 app 随后被覆盖，旧 helper 不能从磁盘读到新身份。
        _ = HelperReleaseIdentitySource.daemonIdentity
        // 客户端超时后会关闭 socket。写入关闭的连接不能终止整个 root helper。
        signal(SIGPIPE, SIG_IGN)
        let log = HelperLog()
        let fanControlRuntime = FanControlRuntime(log: log)
        defer { fanControlRuntime.shutdown() }
        resumeSharedChargeLimitRuntime(log: log)
        var terminationSources: [DispatchSourceSignal] = []
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                // 充电状态跨越 helper 重启。卸载路径会先显式恢复原策略，
                // 通用 SIGTERM 不能清除状态，否则下一次启动无法恢复用户上限。
                prepareSharedChargeLimitForExit()
                // 风扇控制是进程内状态，helper 退出前必须恢复系统控制。
                fanControlRuntime.shutdown()
                exit(0)
            }
            source.resume()
            terminationSources.append(source)
        }
        defer { terminationSources.forEach { $0.cancel() } }
        do {
            try serve(log: log, fanControlRuntime: fanControlRuntime)
            return 0
        } catch {
            log.error("Helper failed", error)
            return 1
        }
    }

    static func resumeSharedChargeLimitRuntime(log: HelperLog) {
        if case .failure(let failure) = chargeLimitRuntime.resumeOnStartup() {
            log.error("Charge limit runtime failed to resume: \(failure)")
        }
    }

    static func prepareSharedChargeLimitForExit() {
        chargeLimitRuntime.prepareForExit()
    }

    private static func serve(log: HelperLog, fanControlRuntime: FanControlRuntime) throws {
        let leaseCoordinator = HelperLeaseCoordinator(log: log)
        leaseCoordinator.restoreStaleState()
        try prepareSocketFile()

        let serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { throw HelperError.socket("socket() failed") }
        defer { close(serverSocket) }

        guard let address = UnixSocketAddress(path: HelperProtocol.socketPath) else {
            throw HelperError.socket("Socket path is too long")
        }
        let bindResult = address.withSockaddr { pointer, length in
            Darwin.bind(serverSocket, pointer, length)
        }
        guard bindResult == 0 else { throw HelperError.socket("bind() failed") }

        guard listen(serverSocket, 16) == 0 else { throw HelperError.socket("listen() failed") }
        // 任意用户可连，uid 在连接后校验。socket 文件本身没有机密内容。
        chmod(HelperProtocol.socketPath, mode_t(HelperWire.shared.SOCKET_PERMISSIONS))
        log.info("Helper listening on \(HelperProtocol.socketPath)")

        while true {
            let client = accept(serverSocket, nil, nil)
            // 被信号打断时 accept 返回负数，继续等下一个连接。
            guard client >= 0 else { continue }
            DispatchQueue.global().async {
                handleClient(
                    client,
                    log: log,
                    leaseCoordinator: leaseCoordinator,
                    fanControlRuntime: fanControlRuntime
                )
            }
        }
    }

    private static func prepareSocketFile() throws {
        let directory = HelperProtocol.helperDirectory
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        // 上次异常退出会留下过期的 socket 文件，先删掉，否则 bind 失败。
        unlink(HelperProtocol.socketPath)
    }

    /// 处理一个连接。会关闭 `client`。
    ///
    /// 协议部分（解码、校验、回复构造、pmset 参数）全部在共享层，
    /// 这里只做三件宿主才能做的事：看 uid、跑进程、写回包。
    static func handleClient(
        _ client: Int32,
        log: HelperLog,
        leaseCoordinator: HelperLeaseCoordinator,
        fanControlRuntime: FanControlRuntime
    ) {
        defer { close(client) }
        var noSigPipe: Int32 = 1
        _ = setsockopt(
            client,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )
        do {
            guard let peerUid = peerUid(of: client) else {
                log.info("Rejected helper request: cannot determine peer uid")
                write(reply: HelperWire.shared.failure(requestId: "", message: "Cannot determine peer uid"), to: client)
                return
            }
            guard let allowed = allowedUid(), peerUid == allowed else {
                log.info("Rejected helper request from uid=\(peerUid)")
                write(reply: HelperWire.shared.failure(requestId: "", message: "Peer uid is not allowed"), to: client)
                return
            }

            guard let line = UnixSocketIO.readLine(
                client,
                limit: Int(HelperWire.shared.MAX_REQUEST_BYTES)
            ) else {
                return
            }
            let reply = process(
                line: line,
                authorizePrivilegedCommand: {
                    peerAuthorizer.isAuthorized(descriptor: client)
                },
                log: log,
                leaseCoordinator: leaseCoordinator,
                fanControlRuntime: fanControlRuntime
            )
            write(reply: reply, to: client)
        }
    }

    /// 解码、校验并执行一条已传输到 helper 的请求。
    ///
    /// legacy socket 通过 `authorizePrivilegedCommand` 检查对端签名。
    /// XPC 在连接阶段已完成同一检查，因此传入始终返回 true 的闭包。
    static func process(
        line: String,
        authorizePrivilegedCommand: () -> Bool,
        log: HelperLog,
        leaseCoordinator: HelperLeaseCoordinator,
        fanControlRuntime: FanControlRuntime
    ) -> HelperReply {
        guard let request = HelperWire.shared.decodeRequest(line: line) else {
            return HelperWire.shared.failure(requestId: "", message: "Invalid JSON request")
        }
        if let validationError = HelperWire.shared.validate(request: request) {
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: validationError
            )
        }

        if HelperWire.shared.requiresClientSignature(command: request.command),
           !authorizePrivilegedCommand() {
            log.info("Rejected privileged command from an unauthorized client")
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: "Peer signature is not allowed"
            )
        }
        if request.command == HelperWire.shared.COMMAND_PREPARE_INSTALL_TRANSACTION {
            let chargeReply = chargeLimitHandler.prepareForInstallTransaction(
                requestId: request.requestId
            )
            guard chargeReply.ok else { return chargeReply }
            let fanReply = fanControlRuntime.prepareForInstallTransaction(
                requestId: request.requestId
            )
            guard fanReply.ok else { return fanReply }
            return leaseCoordinator.prepareForInstallTransaction(
                requestId: request.requestId
            )
        }
        if HelperWire.shared.isChargeLimitCommand(command: request.command),
           let reply = chargeLimitHandler.handle(request) {
            return reply
        }
        if let reply = fanControlRuntime.handle(request) {
            return reply
        }
        if let arguments = HelperWire.shared.pmsetArguments(request: request) {
            return runPmset(requestId: request.requestId, arguments: arguments)
        }
        if request.command == HelperWire.shared.COMMAND_VERSION {
            guard let identity = HelperReleaseIdentitySource.daemonIdentity else {
                log.error("Cannot report helper release identity")
                return HelperWire.shared.failure(
                    requestId: request.requestId,
                    message: "Helper release identity is unavailable"
                )
            }
            return HelperWire.shared.versionReply(
                requestId: request.requestId,
                identity: identity
            )
        }
        if let leaseReply = leaseCoordinator.handle(request) {
            return leaseReply
        }
        // 白名单外的命令在校验那一步就被拒绝了，这里只是兜底。
        return HelperWire.shared.failure(
            requestId: request.requestId,
            message: "Command is not allowed"
        )
    }

    // MARK: - 私有

    private static func peerUid(of descriptor: Int32) -> uid_t? {
        var uid = uid_t(0)
        var gid = gid_t(0)
        guard getpeereid(descriptor, &uid, &gid) == 0 else { return nil }
        return uid
    }

    private static func allowedUid() -> uid_t? {
        guard let text = try? String(contentsOfFile: HelperProtocol.allowedUidPath, encoding: .utf8) else {
            return nil
        }
        guard let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return uid_t(value)
    }

    /// 跑一条 `pmset` 命令。
    ///
    /// 参数与退出码的判定都在共享层。进程启动失败只有本宿主知道原因，
    /// 所以那一句文案留在本地。
    private static func runPmset(requestId: String, arguments: [String]) -> HelperReply {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return HelperWire.shared.failure(requestId: requestId, message: error.localizedDescription)
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return HelperWire.shared.pmsetReply(
            requestId: requestId,
            exitCode: process.terminationStatus,
            output: String(data: output, encoding: .utf8) ?? ""
        )
    }

    private static func write(reply: HelperReply, to descriptor: Int32) {
        UnixSocketIO.writeAll(descriptor, HelperWire.shared.encodeReply(reply: reply) + "\n")
    }
}

enum HelperError: Error {
    case socket(String)
}

/// helper 自己的日志。写到 `/Library/Application Support/Covio/helper.log`。
///
/// 不用 `os.Logger`。app 和 helper 分开写入不同的持久日志，便于用户上报问题。
///
/// 多个连接线程会同时写。`NSLock` 串行化写入，所以标记 `@unchecked Sendable`。
final class HelperLog: @unchecked Sendable {
    private let path: String
    private let lock = NSLock()

    init(path: String = HelperProtocol.logPath) {
        self.path = path
    }

    func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    func error(_ message: String, _ error: Error? = nil) {
        var text = message
        if let error { text += ": \(error)" }
        write(level: "ERROR", message: text)
    }

    private func write(level: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(level) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

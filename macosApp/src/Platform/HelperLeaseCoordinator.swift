import Foundation

/// helper 的合盖租约协调器。
///
/// 所有状态操作走同一条串行队列。
/// 本类型只通过 `pmset` 改 `SleepDisabled`，不执行客户端提供的命令。
final class HelperLeaseCoordinator: @unchecked Sendable {
    struct Environment {
        let nowEpochSeconds: () -> Int64
        let readSleepDisabled: () -> Bool?
        let writeSleepDisabled: (Bool) -> Bool
        let readOwner: () -> String?
        let writeOwner: (String) -> Bool
        let clearOwner: () -> Void
        let externalDisplayCount: () -> Int?
        let schedule: (Int64, @escaping @Sendable () -> Void) -> Void
    }

    private let queue = DispatchQueue(label: "com.wyz.covio.helper.leases")
    private let environment: Environment
    private let log: HelperLog
    private let book = HelperLeaseBook()
    private var expiryGeneration: Int64 = 0

    init(log: HelperLog, environment: Environment? = nil) {
        self.log = log
        self.environment = environment ?? .live(log: log)
    }

    /// helper 启动时只清理 Covio 拥有的状态。
    func restoreStaleState() {
        queue.sync {
            _ = book.clear()
            let disabled = environment.readSleepDisabled()
            let owner = environment.readOwner()
            if disabled == false {
                if owner == HelperProtocol.sleepOwnerValue {
                    environment.clearOwner()
                }
                return
            }
            guard disabled == true, owner == HelperProtocol.sleepOwnerValue else {
                if disabled == true {
                    log.info("SleepDisabled is external; helper left it unchanged")
                }
                return
            }

            let cleared = environment.writeSleepDisabled(false)
            let actual = environment.readSleepDisabled()
            if cleared, actual == false {
                environment.clearOwner()
                log.info("Cleared stale Covio SleepDisabled state")
            } else {
                log.error("Cannot clear stale Covio SleepDisabled state")
            }
        }
    }

    /// 处理一条租约命令。未知命令返回 nil。
    func handle(_ request: HelperRequest) -> HelperReply? {
        queue.sync {
            switch request.command {
            case HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE:
                return acquire(request, renew: false)
            case HelperWire.shared.COMMAND_LID_LEASE_RENEW:
                return acquire(request, renew: true)
            case HelperWire.shared.COMMAND_LID_LEASE_RELEASE:
                return release(request)
            case HelperWire.shared.COMMAND_LID_LEASE_STATUS:
                let before = book.snapshot()
                _ = book.prune(nowEpochSeconds: environment.nowEpochSeconds())
                if before.hasActiveLease, !book.snapshot().hasActiveLease {
                    _ = releaseOwnedSleepIfNeeded()
                }
                return statusReply(request.requestId)
            default:
                return nil
            }
        }
    }

    /// 安装事务只清除 Covio 持有的租约和 SleepDisabled，不覆盖外部状态。
    func prepareForInstallTransaction(requestId: String) -> HelperReply {
        queue.sync { () -> HelperReply in
            _ = book.clear()
            guard let disabled = environment.readSleepDisabled() else {
                return HelperWire.shared.failure(
                    requestId: requestId,
                    message: HelperWire.shared.ERROR_CANNOT_READ_SLEEP_DISABLED
                )
            }
            let owner = environment.readOwner()
            if !disabled {
                if owner == HelperProtocol.sleepOwnerValue {
                    environment.clearOwner()
                }
                return HelperWire.shared.success(requestId: requestId, result: [:])
            }
            guard owner == HelperProtocol.sleepOwnerValue else {
                return HelperWire.shared.success(requestId: requestId, result: [:])
            }
            guard environment.writeSleepDisabled(false),
                  environment.readSleepDisabled() == false
            else {
                return HelperWire.shared.failure(
                    requestId: requestId,
                    message: HelperWire.shared.ERROR_CANNOT_WRITE_SLEEP_DISABLED
                )
            }
            environment.clearOwner()
            log.info("Released Covio SleepDisabled for install transaction")
            return HelperWire.shared.success(requestId: requestId, result: [:])
        }
    }

    private func acquire(_ request: HelperRequest, renew: Bool) -> HelperReply {
        let leaseId = request.payload["leaseId"] ?? ""
        let clientDisplayCount = Int(request.payload["externalDisplayCount"] ?? "") ?? 0
        guard let localDisplayCount = environment.externalDisplayCount() else {
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: HelperWire.shared.ERROR_CANNOT_READ_EXTERNAL_DISPLAY
            )
        }
        if localDisplayCount > 0 || clientDisplayCount > 0 {
            if renew {
                _ = book.release(leaseId: leaseId, nowEpochSeconds: environment.nowEpochSeconds())
                if !book.snapshot().hasActiveLease {
                    _ = releaseOwnedSleepIfNeeded()
                }
            }
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: HelperWire.shared.ERROR_EXTERNAL_DISPLAY
            )
        }

        guard let sleepDisabled = environment.readSleepDisabled() else {
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: HelperWire.shared.ERROR_CANNOT_READ_SLEEP_DISABLED
            )
        }
        let owner = environment.readOwner()
        if sleepDisabled {
            guard owner == HelperProtocol.sleepOwnerValue else {
                log.info("Rejected lid lease because SleepDisabled is external")
                return HelperWire.shared.failure(
                    requestId: request.requestId,
                    message: HelperWire.shared.ERROR_EXTERNAL_SLEEP_CONFLICT
                )
            }
        } else {
            guard owner == nil || owner == HelperProtocol.sleepOwnerValue else {
                return HelperWire.shared.failure(
                    requestId: request.requestId,
                    message: HelperWire.shared.ERROR_CANNOT_READ_OWNERSHIP
                )
            }
            guard environment.writeOwner(HelperProtocol.sleepOwnerValue) else {
                return HelperWire.shared.failure(
                    requestId: request.requestId,
                    message: HelperWire.shared.ERROR_CANNOT_READ_OWNERSHIP
                )
            }
            guard environment.writeSleepDisabled(true) else {
                environment.clearOwner()
                return HelperWire.shared.failure(
                    requestId: request.requestId,
                    message: HelperWire.shared.ERROR_CANNOT_WRITE_SLEEP_DISABLED
                )
            }
            guard environment.readSleepDisabled() == true else {
                _ = environment.writeSleepDisabled(false)
                environment.clearOwner()
                return HelperWire.shared.failure(
                    requestId: request.requestId,
                    message: HelperWire.shared.ERROR_CANNOT_WRITE_SLEEP_DISABLED
                )
            }
        }

        let now = environment.nowEpochSeconds()
        let expiresAt = now + HelperProtocol.leaseDurationSeconds
        guard book.upsert(leaseId: leaseId, nowEpochSeconds: now, expiresAtEpochSeconds: expiresAt) else {
            if owner != HelperProtocol.sleepOwnerValue {
                environment.clearOwner()
                _ = environment.writeSleepDisabled(false)
            }
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: HelperWire.shared.ERROR_TOO_MANY_LEASES
            )
        }
        scheduleExpiry()
        log.info("\(renew ? "Renewed" : "Acquired") lid lease \(leaseId)")
        return statusReply(request.requestId)
    }

    private func release(_ request: HelperRequest) -> HelperReply {
        let leaseId = request.payload["leaseId"] ?? ""
        _ = book.release(leaseId: leaseId, nowEpochSeconds: environment.nowEpochSeconds())
        if book.snapshot().hasActiveLease {
            return statusReply(request.requestId)
        }
        let error = releaseOwnedSleepIfNeeded()
        return statusReply(request.requestId, error: error)
    }

    private func expireLocked() {
        _ = book.prune(nowEpochSeconds: environment.nowEpochSeconds())
        if book.snapshot().hasActiveLease {
            scheduleExpiry()
            return
        }
        _ = releaseOwnedSleepIfNeeded()
    }

    private func releaseOwnedSleepIfNeeded() -> String? {
        guard let disabled = environment.readSleepDisabled() else {
            return HelperWire.shared.ERROR_CANNOT_READ_SLEEP_DISABLED
        }
        let owner = environment.readOwner()
        if !disabled {
            if owner == HelperProtocol.sleepOwnerValue {
                environment.clearOwner()
            }
            return nil
        }
        guard owner == HelperProtocol.sleepOwnerValue else {
            return HelperWire.shared.ERROR_EXTERNAL_SLEEP_CONFLICT
        }
        guard environment.writeSleepDisabled(false) else {
            return HelperWire.shared.ERROR_CANNOT_WRITE_SLEEP_DISABLED
        }
        guard environment.readSleepDisabled() == false else {
            return HelperWire.shared.ERROR_CANNOT_WRITE_SLEEP_DISABLED
        }
        environment.clearOwner()
        log.info("Released Covio SleepDisabled")
        return nil
    }

    private func scheduleExpiry() {
        let current = book.snapshot()
        guard let expiresAt = current.expiresAtEpochSeconds else { return }
        expiryGeneration += 1
        let generation = expiryGeneration
        let delay = max(1, expiresAt - environment.nowEpochSeconds())
        environment.schedule(delay) { [weak self] in
            guard let self else { return }
            self.queue.async {
                guard generation == self.expiryGeneration else { return }
                self.expireLocked()
            }
        }
    }

    private func statusReply(_ requestId: String, error: String? = nil) -> HelperReply {
        _ = book.prune(nowEpochSeconds: environment.nowEpochSeconds())
        let snapshot = book.snapshot()
        let disabled = environment.readSleepDisabled()
        let owner = environment.readOwner()
        let status = HelperWire.shared.leaseStatusReply(
            requestId: requestId,
            sleepDisabled: disabled,
            covioOwned: owner.map { $0 == HelperProtocol.sleepOwnerValue },
            activeLeaseCount: Int32(snapshot.activeCount),
            expiresAtEpochSeconds: snapshot.expiresAtEpochSeconds
        )
        guard let error else { return status }
        return HelperWire.shared.failure(requestId: requestId, message: error)
    }
}

extension HelperLeaseCoordinator.Environment {
    static func live(log: HelperLog) -> HelperLeaseCoordinator.Environment {
        HelperLeaseCoordinator.Environment(
            nowEpochSeconds: { Int64(Date().timeIntervalSince1970) },
            readSleepDisabled: {
                guard let text = PmsetReader.readConfiguration() else { return nil }
                return PmsetConfigParser.sleepDisabled(text: text)
            },
            writeSleepDisabled: { disabled in
                runPmset(HelperWire.shared.disableSleepArguments(disabled: disabled))
            },
            readOwner: {
                try? String(contentsOfFile: HelperProtocol.sleepOwnerPath, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            },
            writeOwner: { value in
                let url = URL(fileURLWithPath: HelperProtocol.sleepOwnerPath)
                do {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data((value + "\n").utf8).write(to: url, options: .atomic)
                    return true
                } catch {
                    log.error("Cannot write SleepDisabled owner", error)
                    return false
                }
            },
            clearOwner: {
                try? FileManager.default.removeItem(atPath: HelperProtocol.sleepOwnerPath)
            },
            externalDisplayCount: {
                ExternalDisplayReader.count()
            },
            schedule: { seconds, block in
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + .seconds(Int(seconds)),
                    execute: block
                )
            }
        )
    }

    private static func runPmset(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            let killDeadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < killDeadline {
                usleep(20_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            return false
        }
        return process.terminationStatus == 0
    }
}

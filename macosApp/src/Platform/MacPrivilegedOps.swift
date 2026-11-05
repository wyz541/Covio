import Foundation

/// `PrivilegedOps` 端口的 macOS 实现。
///
/// 与旧版宿主保持相同行为：
/// - 「已安装」的判据是 socket 文件存在，不是 LaunchDaemon 在跑。
/// - 完整发布身份和签名都匹配才返回 `MATCH`。
/// - 其他状态进入只读安全模式，并只允许 helper 修复入口。
/// - 只有 `pmset` 读操作在本地做，写操作一律走 helper。
///
/// 实现类继承 `NSObject`，以便使用 Objective-C runtime 的 helper 检查。
final class MacPrivilegedOps: NSObject, PrivilegedOps {
    private let logger: AppLogger
    private let executablePath: String
    private let client: HelperClient
    private let externalDisplayCount: () -> Int?
    private let expectedReleaseIdentity: HelperReleaseIdentity?
    private let expectedHelperExecutablePath: String
    private let isHelperTrusted: (pid_t?, String) -> Bool
    private let leaseId = UUID().uuidString
    private let stateLock = NSLock()
    private let leaseOperationLock = NSLock()
    private let localStatusCacheLock = NSLock()
    private var leaseActive = false
    private var renewTimer: DispatchSourceTimer?
    private var localSleepDisabled: Bool?
    private var localSleepDisabledReadAt: TimeInterval?

    init(
        logger: AppLogger,
        executablePath: String = Bundle.main.executablePath ?? "",
        client: HelperClient = HelperClient(),
        expectedReleaseIdentity: HelperReleaseIdentity? = HelperReleaseIdentitySource.expectedAppIdentity,
        expectedHelperExecutablePath: String? = HelperReleaseIdentitySource.installedHelperExecutablePath,
        isHelperTrusted: @escaping (pid_t?, String) -> Bool = {
            HelperCodeTrust.isTrusted(peerPID: $0, expectedExecutablePath: $1)
        },
        externalDisplayCount: @escaping () -> Int? = {
            ExternalDisplayReader.count()
        }
    ) {
        self.logger = logger
        self.executablePath = executablePath
        self.client = client
        self.expectedReleaseIdentity = expectedReleaseIdentity
        self.expectedHelperExecutablePath = expectedHelperExecutablePath ?? executablePath
        self.isHelperTrusted = isHelperTrusted
        self.externalDisplayCount = externalDisplayCount
        super.init()
    }

    /// 「已安装」的判据是 socket 文件存在，不是 LaunchDaemon 在跑。
    /// 这是 0.4.2 的既有语义：daemon 被 launchd 重启的瞬间不该让界面闪成未安装。
    func isInstalled() -> Bool {
        client.canReachHelper
    }

    func status() -> HelperStatus {
        let status = HelperReleaseInspector.inspect(
            client: client,
            expectedIdentity: expectedReleaseIdentity,
            expectedExecutablePath: expectedHelperExecutablePath,
            isTrusted: isHelperTrusted
        )
        if status != .match && status != .missing {
            logger.warn(
                message: "Helper release handshake rejected: status=\(status)",
                error: nil
            )
        }
        return status
    }

    func helperVersion() -> String? {
        client.version()
    }

    func install() -> Bool {
        guard !executablePath.isEmpty else {
            logger.warn(message: "Cannot install the privileged helper: unknown executable path", error: nil)
            return false
        }
        guard prepareForHelperChange() else { return false }
        return HelperInstaller.install(executablePath: executablePath) { [logger] message in
            logger.info(message: message)
        }
    }

    func uninstall() -> Bool {
        guard prepareForHelperChange() else { return false }
        return HelperInstaller.uninstall { [logger] message in
            logger.info(message: message)
        }
    }

    func setDisableSleep(disabled: Bool) -> Bool {
        guard requireMatchedHelper("setDisableSleep") else { return false }
        if disabled {
            guard let externalDisplays = externalDisplayCount() else {
                logger.warn(message: "Cannot read external display count", error: nil)
                return false
            }
            leaseOperationLock.lock()
            defer { leaseOperationLock.unlock() }
            let status = client.acquireLidLease(
                leaseId: leaseId,
                externalDisplayCount: externalDisplays
            )
            guard status.leaseActive, status.sleepDisabled == true else {
                logger.warn(
                    message: "Privileged helper did not acquire the lid lease: \(status.error ?? "unknown error")",
                    error: nil
                )
                return false
            }
            stateLock.withLock { leaseActive = true }
            startRenewTimer()
            return true
        }

        stopRenewTimer()
        leaseOperationLock.lock()
        defer { leaseOperationLock.unlock() }
        stateLock.withLock { leaseActive = false }
        let status = client.releaseLidLease(leaseId: leaseId)
        guard status.error == nil, status.sleepDisabled != true else {
            logger.warn(
                message: "Privileged helper did not release the lid lease: \(status.error ?? "SleepDisabled remains set")",
                error: nil
            )
            return false
        }
        return true
    }

    func lidLeaseStatus() -> LidLeaseStatus {
        let remote = client.lidLeaseStatus()
        guard remote.sleepDisabled == nil, let local = cachedLocalSleepDisabled() else {
            return remote
        }
        return LidLeaseStatus(
            available: remote.available,
            protocolVersion: remote.protocolVersion,
            sleepDisabled: local,
            covioOwned: nil,
            activeLeaseCount: remote.activeLeaseCount,
            expiresAtEpochSeconds: remote.expiresAtEpochSeconds,
            error: remote.error
        )
    }

    private func cachedLocalSleepDisabled() -> Bool? {
        localStatusCacheLock.lock()
        if let readAt = localSleepDisabledReadAt,
           Date().timeIntervalSince1970 - readAt < 30 {
            let cached = localSleepDisabled
            localStatusCacheLock.unlock()
            return cached
        }
        localStatusCacheLock.unlock()

        let actual = PmsetReader.sleepDisabled()
        localStatusCacheLock.lock()
        localSleepDisabled = actual
        localSleepDisabledReadAt = Date().timeIntervalSince1970
        localStatusCacheLock.unlock()
        return actual
    }

    private func startRenewTimer() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard renewTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(
            deadline: .now() + .seconds(Int(HelperProtocol.leaseRenewSeconds)),
            repeating: .seconds(Int(HelperProtocol.leaseRenewSeconds)),
            leeway: .seconds(2)
        )
        timer.setEventHandler { [weak self] in self?.renewLease() }
        renewTimer = timer
        timer.resume()
    }

    private func stopRenewTimer() {
        stateLock.lock()
        let timer = renewTimer
        renewTimer = nil
        stateLock.unlock()
        timer?.cancel()
    }

    private func renewLease() {
        leaseOperationLock.lock()
        defer { leaseOperationLock.unlock() }
        guard stateLock.withLock({ leaseActive }) else { return }
        guard requireMatchedHelper("renewLidLease") else { return }
        guard let externalDisplays = externalDisplayCount() else {
            logger.warn(message: "Cannot renew lid lease: external display count is unknown", error: nil)
            return
        }
        let status = client.renewLidLease(
            leaseId: leaseId,
            externalDisplayCount: externalDisplays
        )
        if status.leaseActive, status.sleepDisabled == true {
            return
        }
        logger.warn(
            message: "Cannot renew lid lease: \(status.error ?? "helper state is not active")",
            error: nil
        )
    }

    deinit {
        stopRenewTimer()
        if status().allowsPrivilegedWrites, stateLock.withLock({ leaseActive }) {
            _ = client.releaseLidLease(leaseId: leaseId)
        }
    }

    func hibernateMode() -> Int32? {
        guard let mode = PmsetReader.hibernateMode() else { return nil }
        guard HelperProtocol.supportedHibernateModes.contains(mode) else { return nil }
        return Int32(mode)
    }

    func setHibernateMode(mode: Int32) -> Bool {
        guard HelperProtocol.supportedHibernateModes.contains(Int(mode)) else { return false }
        guard requireMatchedHelper("setHibernateMode") else { return false }
        guard client.setHibernateMode(mode: Int(mode)) else {
            logger.warn(message: "Privileged helper did not accept setHibernateMode(\(mode))", error: nil)
            return false
        }
        return true
    }

    private func requireMatchedHelper(_ operation: String) -> Bool {
        let current = status()
        guard current.allowsPrivilegedWrites else {
            logger.warn(
                message: "Privileged write blocked by safe mode: operation=\(operation) status=\(current)",
                error: nil
            )
            return false
        }
        return true
    }

    /// 迁移和卸载允许释放本 app 进程持有的租约，即使当前发布身份不匹配。
    func prepareForHelperChange() -> Bool {
        guard stateLock.withLock({ leaseActive }) else { return true }
        stopRenewTimer()
        let status = client.releaseLidLease(leaseId: leaseId)
        guard status.error == nil, status.sleepDisabled != true else {
            logger.warn(
                message: "Cannot release the lid lease before helper change: \(status.error ?? "SleepDisabled remains set")",
                error: nil
            )
            return false
        }
        stateLock.withLock { leaseActive = false }
        return true
    }
}

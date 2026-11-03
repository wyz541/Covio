import Foundation
import kmpDomain

struct HelperStatusSnapshot: @unchecked Sendable {
    let status: HelperStatus
    let lidLeaseStatus: LidLeaseStatus

    static func initial() -> HelperStatusSnapshot {
        HelperStatusSnapshot(status: .missing, lidLeaseStatus: unavailableLidLeaseStatus())
    }

    static func unavailableLidLeaseStatus() -> LidLeaseStatus {
        LidLeaseStatus(
            available: false,
            protocolVersion: nil,
            sleepDisabled: nil,
            covioOwned: nil,
            activeLeaseCount: 0,
            expiresAtEpochSeconds: nil,
            error: nil
        )
    }
}

/// Keeps helper reads off the main actor.
///
/// Periodic callers see the last snapshot immediately.
/// The real XPC probe runs in a detached task.
/// Only one probe can be active at a time.
/// Failed probes back off until the helper becomes trusted again.
final class HelperStatusMonitor: NSObject, PrivilegedOps, @unchecked Sendable {
    private let upstream: KotlinBox<any PrivilegedOps>
    private let clock: @Sendable () -> TimeInterval
    private let lock = NSLock()
    private var snapshot = HelperStatusSnapshot.initial()
    private var activeProbe: Task<HelperStatusSnapshot, Never>?
    private var nextProbeAt: TimeInterval = 0
    private var failureCount = 0
    private var updateHandler: (@Sendable (HelperStatusSnapshot) -> Void)?

    init(
        upstream: PrivilegedOps,
        clock: @escaping @Sendable () -> TimeInterval = {
            Date().timeIntervalSince1970
        }
    ) {
        self.upstream = KotlinBox(upstream)
        self.clock = clock
        super.init()
    }

    func setUpdateHandler(_ handler: (@Sendable (HelperStatusSnapshot) -> Void)?) {
        lock.withLock { updateHandler = handler }
    }

    /// Requests a background probe. The current value is returned immediately.
    func isInstalled() -> Bool {
        status() != .missing
    }

    func status() -> HelperStatus {
        requestProbe()
        return lock.withLock { snapshot.status }
    }

    func lidLeaseStatus() -> LidLeaseStatus {
        requestProbe()
        return lock.withLock { snapshot.lidLeaseStatus }
    }

    func helperVersion() -> String? {
        upstream.value.helperVersion()
    }

    func install() -> Bool {
        let installed = upstream.value.install()
        if installed {
            replaceSnapshot(
                status: .untrusted,
                lidLeaseStatus: HelperStatusSnapshot.unavailableLidLeaseStatus(),
                nextProbeAt: clock()
            )
            requestProbe(force: true)
        } else {
            requestProbe(force: true)
        }
        return installed
    }

    func uninstall() -> Bool {
        let removed = upstream.value.uninstall()
        replaceSnapshot(
            status: .missing,
            lidLeaseStatus: HelperStatusSnapshot.unavailableLidLeaseStatus(),
            nextProbeAt: clock()
        )
        return removed
    }

    func setDisableSleep(disabled: Bool) -> Bool {
        let accepted = upstream.value.setDisableSleep(disabled: disabled)
        if accepted {
            refreshLidStatusAfterWrite()
        } else {
            requestProbe(force: true)
        }
        return accepted
    }

    func hibernateMode() -> KotlinInt? {
        upstream.value.hibernateMode()
    }

    func setHibernateMode(mode: Int32) -> Bool {
        upstream.value.setHibernateMode(mode: mode)
    }

    @discardableResult
    func probe(force: Bool = false) async -> HelperStatusSnapshot? {
        let now = clock()
        let task: Task<HelperStatusSnapshot, Never>? = lock.withLock {
            if let activeProbe {
                return activeProbe
            }
            if !force && now < nextProbeAt {
                return nil
            }

            let upstream = upstream
            let task = Task.detached(priority: .utility) { [weak self] in
                let status = upstream.value.status()
                let lidLeaseStatus = status == .match
                    ? upstream.value.lidLeaseStatus()
                    : HelperStatusSnapshot.unavailableLidLeaseStatus()
                let snapshot = HelperStatusSnapshot(
                    status: status,
                    lidLeaseStatus: lidLeaseStatus
                )
                self?.completeProbe(snapshot)
                return snapshot
            }
            activeProbe = task
            return task
        }

        guard let task else { return nil }
        return await task.value
    }

    func requestProbe(force: Bool = false) {
        let now = clock()
        let shouldSchedule = lock.withLock {
            activeProbe == nil && (force || now >= nextProbeAt)
        }
        guard shouldSchedule else { return }
        Task { [weak self] in
            _ = await self?.probe(force: force)
        }
    }

    private func completeProbe(_ result: HelperStatusSnapshot) {
        let now = clock()
        let handler: (@Sendable (HelperStatusSnapshot) -> Void)? = lock.withLock {
            snapshot = result
            activeProbe = nil
            if result.status == .match {
                failureCount = 0
                nextProbeAt = now + 5
                return updateHandler
            }
            failureCount += 1
            let exponent = min(failureCount - 1, 4)
            let delay = min(60, 5 * Double(1 << exponent))
            nextProbeAt = now + delay
            return updateHandler
        }
        handler?(result)
    }

    /// A successful write must update the cached lid status before Engine reads it.
    /// This keeps the existing post-write verification semantics without another
    /// periodic main-thread probe.
    private func refreshLidStatusAfterWrite() {
        let lidLeaseStatus = upstream.value.lidLeaseStatus()
        let now = clock()
        let update: (snapshot: HelperStatusSnapshot, handler: (@Sendable (HelperStatusSnapshot) -> Void)?) = lock.withLock {
            let updated = HelperStatusSnapshot(
                status: snapshot.status,
                lidLeaseStatus: lidLeaseStatus
            )
            snapshot = updated
            nextProbeAt = now + 5
            return (updated, updateHandler)
        }
        update.handler?(update.snapshot)
    }

    private func replaceSnapshot(
        status: HelperStatus,
        lidLeaseStatus: LidLeaseStatus,
        nextProbeAt: TimeInterval
    ) {
        let updated = HelperStatusSnapshot(status: status, lidLeaseStatus: lidLeaseStatus)
        let handler: (@Sendable (HelperStatusSnapshot) -> Void)? = lock.withLock {
            snapshot = updated
            self.nextProbeAt = nextProbeAt
            failureCount = 0
            return updateHandler
        }
        handler?(updated)
    }
}

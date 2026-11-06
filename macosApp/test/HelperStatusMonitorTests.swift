import XCTest
@testable import Covio

@MainActor
final class HelperStatusMonitorTests: XCTestCase {
    func testCachedReadReturnsBeforeBlockedProbeCompletes() async {
        let fake = MonitorPrivilegedOps(status: .match, sleepDisabled: true)
        let gate = DispatchSemaphore(value: 0)
        fake.blockNextStatus(until: gate)
        let monitor = HelperStatusMonitor(upstream: fake)
        let updated = expectation(description: "blocked probe completed")
        monitor.setUpdateHandler { _ in updated.fulfill() }

        let startedAt = Date()
        XCTAssertEqual(monitor.status(), .missing)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
        XCTAssertEqual(fake.statusStarted.wait(timeout: .now() + 1), .success)

        gate.signal()
        await fulfillment(of: [updated], timeout: 1)

        XCTAssertEqual(monitor.status(), .match)
        XCTAssertEqual(monitor.lidLeaseStatus().sleepDisabled?.boolValue, true)
        XCTAssertEqual(fake.statusCalls, 1)
        XCTAssertEqual(fake.lidLeaseCalls, 1)
    }

    func testConcurrentReadersShareOneProbe() async {
        let fake = MonitorPrivilegedOps(status: .match, sleepDisabled: true)
        let gate = DispatchSemaphore(value: 0)
        fake.blockNextStatus(until: gate)
        let monitor = HelperStatusMonitor(upstream: fake)

        monitor.requestProbe(force: true)
        XCTAssertEqual(fake.statusStarted.wait(timeout: .now() + 1), .success)
        for _ in 0..<20 {
            _ = monitor.status()
            _ = monitor.lidLeaseStatus()
        }
        let waitingProbe = Task { await monitor.probe() }

        gate.signal()
        _ = await waitingProbe.value

        XCTAssertEqual(fake.statusCalls, 1)
        XCTAssertEqual(fake.lidLeaseCalls, 1)
    }

    func testFailedProbeUsesBackoffAndSkipsLidProbe() async {
        let clock = MonitorTestClock(now: 100)
        let fake = MonitorPrivilegedOps(status: .untrusted, sleepDisabled: true)
        let monitor = HelperStatusMonitor(upstream: fake, clock: clock.now)

        let first = await monitor.probe(force: true)
        XCTAssertEqual(first?.status, .untrusted)
        XCTAssertEqual(fake.statusCalls, 1)
        XCTAssertEqual(fake.lidLeaseCalls, 0)

        let skippedAtStart = await monitor.probe()
        XCTAssertNil(skippedAtStart)
        clock.advance(by: 4.9)
        let skippedBeforeDeadline = await monitor.probe()
        XCTAssertNil(skippedBeforeDeadline)
        XCTAssertEqual(fake.statusCalls, 1)

        clock.advance(by: 0.1)
        let second = await monitor.probe()
        XCTAssertEqual(second?.status, .untrusted)
        XCTAssertEqual(fake.statusCalls, 2)
        XCTAssertEqual(fake.lidLeaseCalls, 0)

        clock.advance(by: 9.9)
        let skippedBeforeSecondDeadline = await monitor.probe()
        XCTAssertNil(skippedBeforeSecondDeadline)
        clock.advance(by: 0.1)
        _ = await monitor.probe()
        XCTAssertEqual(fake.statusCalls, 3)
    }

    func testTrustedProbeRefreshesLidStatus() async {
        let fake = MonitorPrivilegedOps(status: .match, sleepDisabled: true)
        let monitor = HelperStatusMonitor(upstream: fake)

        let snapshot = await monitor.probe(force: true)

        XCTAssertEqual(snapshot?.status, .match)
        XCTAssertEqual(snapshot?.lidLeaseStatus.sleepDisabled?.boolValue, true)
        XCTAssertEqual(monitor.status(), .match)
        XCTAssertEqual(monitor.lidLeaseStatus().covioOwned?.boolValue, true)
        XCTAssertEqual(fake.statusCalls, 1)
        XCTAssertEqual(fake.lidLeaseCalls, 1)
    }

    func testSuccessfulLidWriteUpdatesTheCachedStatusImmediately() async {
        let fake = MonitorPrivilegedOps(status: .match, sleepDisabled: false)
        let monitor = HelperStatusMonitor(upstream: fake)
        _ = await monitor.probe(force: true)

        XCTAssertTrue(monitor.setDisableSleep(disabled: true))

        XCTAssertEqual(monitor.lidLeaseStatus().sleepDisabled?.boolValue, true)
        XCTAssertEqual(fake.lidLeaseCalls, 2)
    }

    func testProbePublishesTheUpdatedSnapshot() async {
        let fake = MonitorPrivilegedOps(status: .match, sleepDisabled: true)
        let monitor = HelperStatusMonitor(upstream: fake)
        let updated = expectation(description: "helper snapshot updated")
        monitor.setUpdateHandler { snapshot in
            if snapshot.status == .match {
                updated.fulfill()
            }
        }

        _ = await monitor.probe(force: true)
        await fulfillment(of: [updated], timeout: 1)
    }
}

private final class MonitorTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval

    init(now: TimeInterval) {
        value = now
    }

    var now: @Sendable () -> TimeInterval {
        { [weak self] in
            self?.lock.withLock { self?.value ?? 0 } ?? 0
        }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { value += seconds }
    }
}

private final class MonitorPrivilegedOps: NSObject, PrivilegedOps, @unchecked Sendable {
    private let lock = NSLock()
    private var statusValue: HelperStatus
    private var sleepDisabled: Bool
    private var nextStatusGate: DispatchSemaphore?
    private var statusCallCount = 0
    private var lidLeaseCallCount = 0
    let statusStarted = DispatchSemaphore(value: 0)

    init(status: HelperStatus, sleepDisabled: Bool) {
        statusValue = status
        self.sleepDisabled = sleepDisabled
        super.init()
    }

    var statusCalls: Int { lock.withLock { statusCallCount } }
    var lidLeaseCalls: Int { lock.withLock { lidLeaseCallCount } }

    func blockNextStatus(until gate: DispatchSemaphore) {
        lock.withLock { nextStatusGate = gate }
    }

    func isInstalled() -> Bool {
        status() != .missing
    }

    func status() -> HelperStatus {
        let gate = lock.withLock {
            statusCallCount += 1
            let gate = nextStatusGate
            nextStatusGate = nil
            return gate
        }
        statusStarted.signal()
        gate?.wait()
        return lock.withLock { statusValue }
    }

    func helperVersion() -> String? {
        CovioReleaseIdentity.APP_VERSION
    }

    func install() -> Bool { true }

    func uninstall() -> Bool { true }

    func setDisableSleep(disabled: Bool) -> Bool {
        lock.withLock { sleepDisabled = disabled }
        return true
    }

    func hibernateMode() -> Int32? { nil }

    func setHibernateMode(mode: Int32) -> Bool { true }

    func lidLeaseStatus() -> LidLeaseStatus {
        let state = lock.withLock {
            lidLeaseCallCount += 1
            return (statusValue, sleepDisabled)
        }
        return LidLeaseStatus(
            available: state.0 == .match,
            protocolVersion: state.0 == .match ? HelperProtocol.protocolVersion : nil,
            sleepDisabled: state.1,
            covioOwned: state.1,
            activeLeaseCount: state.1 ? 1 : 0,
            expiresAtEpochSeconds: state.1 ? Int64.max : nil,
            error: nil
        )
    }
}

import XCTest
@testable import Covio

/// helper 租约协调器的行为测试。
///
/// 用假时钟、假 pmset 与假所有权文件验证状态机。
/// 真实 `pmset` 写入在 #155 的真机矩阵验证。
final class HelperLeaseCoordinatorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-helper-lease-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAcquireWritesOwnerAndSleepDisabled() throws {
        let system = FakeLeaseSystem()
        let coordinator = coordinator(system)

        let reply = try XCTUnwrap(coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE, leaseId: "lease-a")))
        XCTAssertTrue(reply.ok)
        XCTAssertEqual(reply.result?["sleepDisabled"], "true")
        XCTAssertEqual(reply.result?["covioOwned"], "true")
        XCTAssertEqual(reply.result?["activeLeaseCount"], "1")
        XCTAssertEqual(system.owner, HelperProtocol.sleepOwnerValue)
        XCTAssertTrue(system.disabled)
        XCTAssertEqual(
            system.events,
            [
                "readSleepDisabled",
                "writeOwner",
                "writeSleepDisabled:true",
                "readSleepDisabled",
                "readSleepDisabled",
            ]
        )
    }

    func testExternalSleepDisabledIsNotTakenOver() throws {
        let system = FakeLeaseSystem(disabled: true, owner: nil)
        let coordinator = coordinator(system)

        let reply = try XCTUnwrap(coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE, leaseId: "lease-a")))
        XCTAssertFalse(reply.ok)
        XCTAssertEqual(reply.error, HelperWire.shared.ERROR_EXTERNAL_SLEEP_CONFLICT)
        XCTAssertTrue(system.disabled)
        XCTAssertNil(system.owner)
        XCTAssertFalse(system.events.contains { $0.hasPrefix("write") })
    }

    func testExternalDisplayRejectsLease() throws {
        let system = FakeLeaseSystem(externalDisplayCount: 1)
        let coordinator = coordinator(system)

        let reply = try XCTUnwrap(coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE, leaseId: "lease-a")))
        XCTAssertFalse(reply.ok)
        XCTAssertEqual(reply.error, HelperWire.shared.ERROR_EXTERNAL_DISPLAY)
        XCTAssertFalse(system.disabled)
        XCTAssertNil(system.owner)
    }

    func testRenewReleasesLeaseWhenAnExternalDisplayAppears() throws {
        let system = FakeLeaseSystem(now: 100)
        let coordinator = coordinator(system)
        _ = coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE, leaseId: "lease-a"))

        system.now = 115
        system.externalDisplayCount = 1
        let reply = try XCTUnwrap(
            coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_RENEW, leaseId: "lease-a"))
        )

        XCTAssertFalse(reply.ok)
        XCTAssertEqual(reply.error, HelperWire.shared.ERROR_EXTERNAL_DISPLAY)
        XCTAssertFalse(system.disabled)
        XCTAssertNil(system.owner)
    }

    func testRenewExtendsTheLease() throws {
        let system = FakeLeaseSystem(now: 100)
        let coordinator = coordinator(system)
        _ = coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE, leaseId: "lease-a"))

        system.now = 130
        let reply = try XCTUnwrap(coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_RENEW, leaseId: "lease-a")))
        XCTAssertTrue(reply.ok)
        XCTAssertEqual(reply.result?["expiresAtEpochSeconds"], "190")
        XCTAssertEqual(reply.result?["activeLeaseCount"], "1")
    }

    func testAppCrashExpiryReleasesSleepDisabled() throws {
        let system = FakeLeaseSystem(now: 100)
        let coordinator = coordinator(system)
        _ = coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE, leaseId: "lease-a"))
        let scheduled = try XCTUnwrap(system.scheduled.last)

        let released = expectation(description: "lease expired")
        system.onDisableChanged = { disabled in
            if !disabled { released.fulfill() }
        }
        system.now = 161
        scheduled()
        wait(for: [released], timeout: 2)

        XCTAssertFalse(system.disabled)
        XCTAssertNil(system.owner)
    }

    func testReleasingOneLeaseKeepsAnotherLeaseActive() throws {
        let system = FakeLeaseSystem()
        let coordinator = coordinator(system)
        _ = coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE, leaseId: "lease-a"))
        _ = coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE, leaseId: "lease-b"))

        let reply = try XCTUnwrap(
            coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_RELEASE, leaseId: "lease-a"))
        )

        XCTAssertTrue(reply.ok)
        XCTAssertEqual(reply.result?["activeLeaseCount"], "1")
        XCTAssertTrue(system.disabled)
        XCTAssertEqual(system.owner, HelperProtocol.sleepOwnerValue)
    }

    func testReleaseKeepsExternalStateWhenOwnershipIsAbsent() throws {
        let system = FakeLeaseSystem(disabled: true, owner: nil)
        let coordinator = coordinator(system)

        let reply = try XCTUnwrap(coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_RELEASE, leaseId: "missing")))
        XCTAssertFalse(reply.ok)
        XCTAssertEqual(reply.error, HelperWire.shared.ERROR_EXTERNAL_SLEEP_CONFLICT)
        XCTAssertTrue(system.disabled)
        XCTAssertNil(system.owner)
    }

    func testStartupClearsOnlyOwnedState() {
        let owned = FakeLeaseSystem(disabled: true, owner: HelperProtocol.sleepOwnerValue)
        coordinator(owned).restoreStaleState()
        XCTAssertFalse(owned.disabled)
        XCTAssertNil(owned.owner)

        let external = FakeLeaseSystem(disabled: true, owner: nil)
        coordinator(external).restoreStaleState()
        XCTAssertTrue(external.disabled)
        XCTAssertNil(external.owner)
    }

    func testInstallTransactionReleasesEveryCovioLeaseAndOwnedSleep() throws {
        let system = FakeLeaseSystem()
        let coordinator = coordinator(system)
        _ = coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE, leaseId: "lease-a"))
        _ = coordinator.handle(request(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE, leaseId: "lease-b"))

        let reply = coordinator.prepareForInstallTransaction(requestId: "upgrade")

        XCTAssertTrue(reply.ok)
        XCTAssertFalse(system.disabled)
        XCTAssertNil(system.owner)
    }

    func testInstallTransactionLeavesExternalSleepStateUntouched() {
        let system = FakeLeaseSystem(disabled: true, owner: nil)

        let reply = coordinator(system).prepareForInstallTransaction(requestId: "upgrade")

        XCTAssertTrue(reply.ok)
        XCTAssertTrue(system.disabled)
        XCTAssertNil(system.owner)
        XCTAssertFalse(system.events.contains("writeSleepDisabled:false"))
    }

    private func coordinator(_ system: FakeLeaseSystem) -> HelperLeaseCoordinator {
        HelperLeaseCoordinator(
            log: HelperLog(path: directory.appendingPathComponent("helper.log").path),
            environment: system.environment
        )
    }

    private func request(_ command: String, leaseId: String) -> HelperRequest {
        HelperRequest(
            version: HelperProtocol.protocolVersion,
            requestId: UUID().uuidString,
            command: command,
            payload: [
                "leaseId": leaseId,
                "externalDisplayCount": "0",
            ]
        )
    }
}

private final class FakeLeaseSystem {
    var now: Int64
    var disabled: Bool
    var owner: String?
    var externalDisplayCount: Int?
    var events: [String] = []
    var scheduled: [() -> Void] = []
    var onDisableChanged: ((Bool) -> Void)?

    init(
        now: Int64 = 100,
        disabled: Bool = false,
        owner: String? = nil,
        externalDisplayCount: Int? = 0
    ) {
        self.now = now
        self.disabled = disabled
        self.owner = owner
        self.externalDisplayCount = externalDisplayCount
    }

    var environment: HelperLeaseCoordinator.Environment {
        HelperLeaseCoordinator.Environment(
            nowEpochSeconds: { [self] in now },
            readSleepDisabled: { [self] in
                events.append("readSleepDisabled")
                return disabled
            },
            writeSleepDisabled: { [self] value in
                events.append("writeSleepDisabled:\(value)")
                disabled = value
                onDisableChanged?(value)
                return true
            },
            readOwner: { [self] in owner },
            writeOwner: { [self] value in
                events.append("writeOwner")
                owner = value
                return true
            },
            clearOwner: { [self] in owner = nil },
            externalDisplayCount: { [self] in externalDisplayCount },
            schedule: { [self] _, block in scheduled.append(block) }
        )
    }
}

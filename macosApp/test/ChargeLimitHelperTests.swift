import Darwin
import XCTest
@testable import Covio

final class ChargeLimitHelperTests: XCTestCase {
    func testStatusReturnsDisabledWhenNoStateExists() {
        let handler = ChargeLimitHelperCommandHandler(runtime: FakeChargeLimitRuntime())

        let reply = handler.handle(request("chargeLimitStatus"))

        XCTAssertEqual(reply?.ok, true)
        XCTAssertEqual(reply?.result?["enabled"], "false")
    }

    func testStatusReturnsThePersistedState() {
        let runtime = FakeChargeLimitRuntime()
        runtime.statusValue = ChargeLimitRuntimeStatus(
            userLimitPercent: 85,
            effectiveTargetPercent: 85,
            chargingLatch: true,
            phase: "charging",
            bypassEngaged: false,
            original: ChargeLimitOriginals(
                optimizedChargingEnabled: true,
                featureState: 0,
                limitPercent: 80
            ),
            activeDischargeEnabled: true,
            activeDischargeSupported: true
        )
        let handler = ChargeLimitHelperCommandHandler(runtime: runtime)

        let reply = handler.handle(request("chargeLimitStatus"))

        XCTAssertEqual(reply?.result?["enabled"], "true")
        XCTAssertEqual(reply?.result?["userLimitPercent"], "85")
        XCTAssertEqual(reply?.result?["targetPercent"], "85")
        XCTAssertEqual(reply?.result?["chargingLatch"], "true")
        XCTAssertEqual(reply?.result?["phase"], "charging")
        XCTAssertEqual(reply?.result?["originalFeatureState"], "0")
        XCTAssertEqual(reply?.result?["originalLimitPercent"], "80")
        XCTAssertEqual(reply?.result?["originalOptimizedChargingEnabled"], "true")
        XCTAssertEqual(reply?.result?["activeDischarge"], "true")
        XCTAssertEqual(reply?.result?["activeDischargeSupported"], "true")
    }

    func testConfigurePassesTheTargetToTheBackend() {
        let runtime = FakeChargeLimitRuntime()
        let handler = ChargeLimitHelperCommandHandler(runtime: runtime)

        let reply = handler.handle(request(
            "chargeLimitConfigure",
            payload: ["percent": "85", "activeDischarge": "true"]
        ))

        XCTAssertEqual(reply?.ok, true)
        XCTAssertEqual(runtime.configuredPercent, 85)
        XCTAssertEqual(runtime.configuredActiveDischarge, true)
    }

    func testConfigureReturnsAReadableFailure() {
        let runtime = FakeChargeLimitRuntime()
        runtime.configureFailure = .readbackFailed("MCL target")
        let handler = ChargeLimitHelperCommandHandler(runtime: runtime)

        let reply = handler.handle(request("chargeLimitConfigure", payload: ["percent": "85"]))

        XCTAssertEqual(reply?.ok, false)
        XCTAssertEqual(reply?.error, "Charge limit preference readback failed: MCL target")
    }

    func testRestoreInvokesTheBackend() {
        let runtime = FakeChargeLimitRuntime()
        let handler = ChargeLimitHelperCommandHandler(runtime: runtime)

        let reply = handler.handle(request("chargeLimitRestore"))

        XCTAssertEqual(reply?.ok, true)
        XCTAssertTrue(runtime.restoreCalled)
    }

    func testUninstallRestoresAnActiveChargeLimit() {
        let client = FakeChargeLimitInstallerClient(status: chargeLimitStatus(enabled: true))

        XCTAssertTrue(HelperInstaller.restoreChargeLimitIfNeeded(using: client))
        XCTAssertEqual(client.restoreCalls, 1)
    }

    func testUninstallSkipsRestoreWhenChargeLimitIsInactive() {
        let client = FakeChargeLimitInstallerClient(status: chargeLimitStatus(enabled: false))

        XCTAssertTrue(HelperInstaller.restoreChargeLimitIfNeeded(using: client))
        XCTAssertEqual(client.restoreCalls, 0)
    }

    func testUninstallStopsWhenChargeLimitRestoreFails() {
        let client = FakeChargeLimitInstallerClient(status: chargeLimitStatus(enabled: true))
        client.restoreResult = false

        XCTAssertFalse(HelperInstaller.restoreChargeLimitIfNeeded(using: client))
        XCTAssertEqual(client.restoreCalls, 1)
    }

    func testNonChargeCommandsAreLeftToTheExistingHelper() {
        let handler = ChargeLimitHelperCommandHandler(runtime: FakeChargeLimitRuntime())

        XCTAssertNil(handler.handle(request("version")))
    }

    func testCurrentProcessSatisfiesItsOwnDesignatedRequirement() throws {
        let requirement = try XCTUnwrap(HelperSignature.currentRequirement())
        XCTAssertTrue(
            HelperSignature.isAuthorized(
                pid: getpid(),
                requirementText: requirement
            )
        )
    }

    func testANonsenseRequirementIsRejected() {
        XCTAssertFalse(
            HelperSignature.isAuthorized(
                pid: getpid(),
                requirementText: "identifier \"not-covio\""
            )
        )
    }

    func testPeerPidComesFromTheUnixSocket() throws {
        var pair = [Int32](repeating: 0, count: 2)
        let result = pair.withUnsafeMutableBufferPointer { sockets in
            socketpair(AF_UNIX, SOCK_STREAM, 0, sockets.baseAddress)
        }
        XCTAssertEqual(result, 0)
        defer {
            close(pair[0])
            close(pair[1])
        }

        XCTAssertEqual(HelperSignature.peerPID(of: pair[0]), getpid())
    }

    func testSocketPeerAuthorizerUsesTheStoredRequirement() throws {
        let requirement = try XCTUnwrap(HelperSignature.currentRequirement())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-helper-signature-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let requirementPath = directory.appendingPathComponent("requirement").path
        try requirement.write(toFile: requirementPath, atomically: true, encoding: .utf8)

        var pair = [Int32](repeating: 0, count: 2)
        let result = pair.withUnsafeMutableBufferPointer { sockets in
            socketpair(AF_UNIX, SOCK_STREAM, 0, sockets.baseAddress)
        }
        XCTAssertEqual(result, 0)
        defer {
            close(pair[0])
            close(pair[1])
        }

        let authorizer = CodeSignaturePeerAuthorizer(requirementPath: requirementPath)
        XCTAssertTrue(authorizer.isAuthorized(descriptor: pair[0]))
    }

    private func request(
        _ command: String,
        payload: [String: String] = [:]
    ) -> HelperRequest {
        HelperRequest(
            version: HelperProtocol.protocolVersion,
            requestId: "r",
            command: command,
            payload: payload
        )
    }

    private func chargeLimitStatus(enabled: Bool) -> ChargeLimitHelperStatus {
        ChargeLimitHelperStatus(
            enabled: enabled,
            userLimitPercent: enabled ? 85 : nil,
            targetPercent: enabled ? 85 : nil,
            chargingLatch: false,
            phase: enabled ? "charging" : "off",
            bypassEngaged: false,
            originalFeatureState: enabled ? 1 : nil,
            originalLimitPercent: enabled ? 80 : nil,
            originalOptimizedChargingEnabled: nil
        )
    }
}

private final class FakeChargeLimitRuntime: ChargeLimitRuntimeControlling, @unchecked Sendable {
    var statusValue: ChargeLimitRuntimeStatus?
    var statusFailure: ChargeLimitMCLFailure?
    var configuredPercent: Int?
    var configuredActiveDischarge: Bool?
    var configureFailure: ChargeLimitMCLFailure?
    var restoreCalled = false
    var restoreFailure: ChargeLimitMCLFailure?

    func status() -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure> {
        if let statusFailure { return .failure(statusFailure) }
        return .success(
            statusValue ?? ChargeLimitRuntimeStatus(
                userLimitPercent: 0,
                effectiveTargetPercent: nil,
                chargingLatch: false,
                phase: "off",
                bypassEngaged: false,
                original: nil
            )
        )
    }

    func configure(
        userLimitPercent: Int,
        activeDischargeEnabled: Bool
    ) -> Result<ChargeLimitRuntimeStatus, ChargeLimitMCLFailure> {
        configuredPercent = userLimitPercent
        configuredActiveDischarge = activeDischargeEnabled
        if let configureFailure { return .failure(configureFailure) }
        return status()
    }

    func restore() -> Result<Void, ChargeLimitMCLFailure> {
        restoreCalled = true
        if let restoreFailure { return .failure(restoreFailure) }
        return .success(())
    }
}

private final class FakeChargeLimitInstallerClient: ChargeLimitClientProtocol, @unchecked Sendable {
    let status: ChargeLimitHelperStatus?
    var restoreResult = true
    var restoreCalls = 0

    init(status: ChargeLimitHelperStatus?) {
        self.status = status
    }

    func chargeLimitStatus() -> ChargeLimitHelperStatus? { status }
    func setChargeLimit(percent: Int, activeDischarge: Bool) -> Bool { false }

    func restoreChargeLimit() -> Bool {
        restoreCalls += 1
        return restoreResult
    }
}

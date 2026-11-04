import XCTest
import kmpDomain
@testable import Covio

/// `PrivilegedOps.status()` 的完整发布身份握手。
///
/// 每个状态都要稳定，不能把「连不上」算成 `OUTDATED`。
/// 只有 `MATCH` 可以发送特权写入。
///
/// 这里不碰系统上真正装的 helper：在一个临时路径上起一个假 helper，
/// 让 `HelperClient` 连过去。被测代码走的是真实的 socket 收发路径。
final class HelperStatusTests: XCTestCase {
    private var directory: URL!
    private var socketPath: String!

    private let commit = String(repeating: "a", count: 40)
    private let helperHash = String(repeating: "b", count: 64)

    private var expectedIdentity: HelperReleaseIdentity {
        identity()
    }

    private func identity(
        protocolVersion: String = HelperProtocol.protocolVersion,
        helperHash: String? = nil
    ) -> HelperReleaseIdentity {
        HelperReleaseIdentity(
            releaseId: "0.6.0-internal.23-g\(commit)",
            clientVersion: "0.6.0-internal.23",
            productVersion: "0.6.0",
            buildNumber: "23",
            gitCommit: commit,
            protocolVersion: protocolVersion,
            helperSHA256: helperHash ?? self.helperHash,
            channel: "internal"
        )
    }

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("covio-helper-status-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // socket 路径必须短。`sun_path` 只有 104 字节，而
        // `NSTemporaryDirectory()` 展开后是 `/var/folders/.../T/`，本身就占 50 字节，
        // 再加一层目录名与 UUID 就超了。
        // 所以 socket 直接放在 `/tmp`，只有测试创建的目录放在 `NSTemporaryDirectory()`。
        socketPath = "/tmp/covio-hs-\(UUID().uuidString.prefix(8)).sock"
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func ops(
        expectedIdentity: HelperReleaseIdentity? = nil,
        hasExpectedIdentity: Bool = true,
        trusted: Bool = true
    ) -> MacPrivilegedOps {
        MacPrivilegedOps(
            logger: SilentLogger(),
            executablePath: "/tmp/Covio",
            client: HelperClient(socketPath: socketPath, timeoutMillis: 1_000),
            expectedReleaseIdentity: hasExpectedIdentity ? (expectedIdentity ?? self.expectedIdentity) : nil,
            expectedHelperExecutablePath: "/tmp/Covio",
            isHelperTrusted: { _, _ in trusted },
            externalDisplayCount: { 0 }
        )
    }

    func testNoSocketMeansMissing() {
        XCTAssertEqual(ops().status(), .missing)
        XCTAssertFalse(ops().isInstalled())
    }

    /// helper 应答完整身份，签名可信且所有字段一致 → MATCH。
    func testExactIdentityMeansMatch() throws {
        let helper = try FakeHelper(
            socketPath: socketPath,
            version: expectedIdentity.clientVersion,
            protocolVersion: expectedIdentity.protocolVersion,
            identity: expectedIdentity
        )
        defer { helper.stop() }

        XCTAssertEqual(ops().status(), .match)
        XCTAssertTrue(ops().isInstalled())
        XCTAssertEqual(ops().helperVersion(), expectedIdentity.clientVersion)
    }

    /// helper 能应答但协议不同 → OUTDATED。
    func testDifferentProtocolMeansOutdated() throws {
        let helperIdentity = identity(protocolVersion: "7")
        let helper = try FakeHelper(
            socketPath: socketPath,
            version: helperIdentity.clientVersion,
            protocolVersion: helperIdentity.protocolVersion,
            identity: helperIdentity
        )
        defer { helper.stop() }

        XCTAssertEqual(ops().status(), .outdated)
        XCTAssertTrue(ops().isInstalled(), "socket 在，所以 helper 存在")
        XCTAssertEqual(ops().helperVersion(), helperIdentity.clientVersion)
    }

    /// 旧 helper 即使版本和协议相同，只要缺少完整身份就是 OUTDATED。
    func testLegacyReplyMeansOutdated() throws {
        let helper = try FakeHelper(
            socketPath: socketPath,
            version: GeneratedReleaseIdentityKt.APP_VERSION,
            protocolVersion: HelperProtocol.protocolVersion
        )
        defer { helper.stop() }

        XCTAssertEqual(ops().status(), .outdated)
    }

    /// socket 文件在但没有进程监听 → UNTRUSTED，不是 OUTDATED。
    func testSocketWithoutAListenerMeansUntrusted() throws {
        // 造一个残留的 socket 文件：绑一次再关掉，文件会留下。
        let helper = try FakeHelper(socketPath: socketPath, version: "0.0.1")
        helper.stop()

        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath), "测试前提：socket 文件还在")
        XCTAssertEqual(ops().status(), .untrusted)
    }

    /// 相同版本但 helper 摘要不同 → IDENTITY_MISMATCH。
    func testSameVersionWithDifferentHelperHashMeansIdentityMismatch() throws {
        let helperIdentity = identity(helperHash: String(repeating: "c", count: 64))
        let helper = try FakeHelper(
            socketPath: socketPath,
            version: helperIdentity.clientVersion,
            protocolVersion: helperIdentity.protocolVersion,
            identity: helperIdentity
        )
        defer { helper.stop() }

        XCTAssertEqual(ops().status(), .identityMismatch)
    }

    /// 完整身份一致但签名校验失败 → UNTRUSTED。
    func testUntrustedSignatureMeansUntrusted() throws {
        let helper = try FakeHelper(
            socketPath: socketPath,
            version: expectedIdentity.clientVersion,
            protocolVersion: expectedIdentity.protocolVersion,
            identity: expectedIdentity
        )
        defer { helper.stop() }

        XCTAssertEqual(ops(trusted: false).status(), .untrusted)
    }

    /// app 自身缺少可验证的发布身份时不能开放写入。
    func testMissingExpectedIdentityMeansUntrusted() throws {
        let helper = try FakeHelper(
            socketPath: socketPath,
            version: expectedIdentity.clientVersion,
            protocolVersion: expectedIdentity.protocolVersion,
            identity: expectedIdentity
        )
        defer { helper.stop() }

        XCTAssertEqual(ops(hasExpectedIdentity: false).status(), .untrusted)
    }

    /// 应答带部分身份字段但格式不完整 → UNTRUSTED，不降级成旧 helper。
    func testPartialIdentityMeansUntrusted() throws {
        let helper = try FakeHelper(
            socketPath: socketPath,
            version: expectedIdentity.clientVersion,
            protocolVersion: expectedIdentity.protocolVersion,
            identityResult: [
                "version": expectedIdentity.clientVersion,
                "productVersion": expectedIdentity.productVersion,
                "protocolVersion": expectedIdentity.protocolVersion,
                "releaseId": expectedIdentity.releaseId,
            ]
        )
        defer { helper.stop() }

        XCTAssertEqual(ops().status(), .untrusted)
    }

    /// 身份不一致时连睡眠写入都不能发送。
    func testIdentityMismatchBlocksSleepWrites() throws {
        let helperIdentity = identity(helperHash: String(repeating: "c", count: 64))
        let helper = try FakeHelper(
            socketPath: socketPath,
            version: helperIdentity.clientVersion,
            protocolVersion: helperIdentity.protocolVersion,
            identity: helperIdentity
        )
        defer { helper.stop() }

        XCTAssertFalse(ops().setDisableSleep(disabled: true))
        XCTAssertFalse(ops().setDisableSleep(disabled: false))
        XCTAssertFalse(ops().setHibernateMode(mode: 0))
        XCTAssertFalse(helper.commands.contains(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE))
        XCTAssertFalse(helper.commands.contains(HelperWire.shared.COMMAND_LID_LEASE_RELEASE))
        XCTAssertFalse(helper.commands.contains(HelperWire.shared.COMMAND_SET_HIBERNATE_MODE))
    }

    /// 修复 helper 后，同一个 app 进程重新握手即可恢复，不要求重启。
    func testRepairRestoresMatchWithoutRestartingTheApp() throws {
        let mismatched = identity(helperHash: String(repeating: "c", count: 64))
        let first = try FakeHelper(
            socketPath: socketPath,
            version: mismatched.clientVersion,
            protocolVersion: mismatched.protocolVersion,
            identity: mismatched
        )
        XCTAssertEqual(ops().status(), .identityMismatch)
        first.stop()
        try FileManager.default.removeItem(atPath: socketPath)

        let repaired = try FakeHelper(
            socketPath: socketPath,
            version: expectedIdentity.clientVersion,
            protocolVersion: expectedIdentity.protocolVersion,
            identity: expectedIdentity
        )
        defer { repaired.stop() }

        XCTAssertEqual(ops().status(), .match)
    }

    func testRepairCanReleaseAnActiveLeaseAfterIdentityChanges() throws {
        let helper = try FakeHelper(
            socketPath: socketPath,
            version: expectedIdentity.clientVersion,
            protocolVersion: expectedIdentity.protocolVersion,
            identity: expectedIdentity
        )
        defer { helper.stop() }
        let privileged = ops()

        XCTAssertTrue(privileged.setDisableSleep(disabled: true))
        helper.setIdentity(identity(helperHash: String(repeating: "c", count: 64)))
        XCTAssertEqual(privileged.status(), .identityMismatch)

        XCTAssertTrue(privileged.prepareForHelperChange())
        XCTAssertTrue(helper.commands.contains(HelperWire.shared.COMMAND_LID_LEASE_RELEASE))
    }

    /// 合盖保持只在 helper 确认租约与真实状态时返回 true。
    func testLidLeaseRequiresAnActiveOkReply() throws {
        let helper = try FakeHelper(
            socketPath: socketPath,
            version: expectedIdentity.clientVersion,
            protocolVersion: expectedIdentity.protocolVersion,
            identity: expectedIdentity
        )
        defer { helper.stop() }

        XCTAssertTrue(ops().setDisableSleep(disabled: true))
        XCTAssertTrue(helper.commands.contains(HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE))
    }

    /// helper 不在时不发租约请求，直接失败。
    func testLidLeaseFailsWithoutAHelper() {
        XCTAssertFalse(ops().setDisableSleep(disabled: true))
    }

    func testChargeLimitStatusParsesTheHelperReply() throws {
        let helper = try FakeHelper(socketPath: socketPath, version: GeneratedReleaseIdentityKt.APP_VERSION)
        defer { helper.stop() }

        let client = HelperClient(socketPath: socketPath, timeoutMillis: 1_000)
        let status = try XCTUnwrap(client.chargeLimitStatus())

        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.userLimitPercent, 85)
        XCTAssertEqual(status.targetPercent, 85)
        XCTAssertTrue(status.chargingLatch)
        XCTAssertEqual(status.phase, "charging")
        XCTAssertFalse(status.bypassEngaged)
        XCTAssertEqual(status.originalFeatureState, 0)
        XCTAssertEqual(status.originalLimitPercent, 80)
        XCTAssertTrue(status.activeDischargeEnabled)
        XCTAssertTrue(status.activeDischargeSupported)
        XCTAssertEqual(helper.commands.last, "chargeLimitStatus")
    }

    func testChargeLimitCommandsUseTheWireCommandNames() throws {
        let helper = try FakeHelper(socketPath: socketPath, version: GeneratedReleaseIdentityKt.APP_VERSION)
        defer { helper.stop() }

        let client = HelperClient(socketPath: socketPath, timeoutMillis: 1_000)
        XCTAssertTrue(client.setChargeLimit(percent: 85, activeDischarge: true))
        XCTAssertTrue(client.restoreChargeLimit())

        XCTAssertEqual(
            Array(helper.commands.suffix(2)),
            ["chargeLimitConfigure", "chargeLimitRestore"]
        )
    }

    func testChargeLimitCommandsCanOutliveTheDefaultSocketTimeout() throws {
        let helper = try FakeHelper(
            socketPath: socketPath,
            version: GeneratedReleaseIdentityKt.APP_VERSION,
            responseDelayMilliseconds: 500
        )
        defer { helper.stop() }

        let client = HelperClient(socketPath: socketPath, timeoutMillis: 100)

        XCTAssertTrue(client.setChargeLimit(percent: 85))
        XCTAssertEqual(helper.commands.last, "chargeLimitConfigure")
    }
}

/// 只在测试里存在的假 helper。
///
/// 绑一个 Unix 域 socket，对每个连接读一行 JSON，回一条 `version` 应答。
/// 用真实的 `HelperRequest` / `HelperReply` 编解码，所以格式与真 helper 一致。
private final class FakeHelper {
    private let descriptor: Int32
    private let thread: Thread
    private let port: FakeHelperState

    /// 收到的命令，按顺序。
    var commands: [String] { port.commands }

    init(
        socketPath: String,
        version: String,
        protocolVersion: String? = HelperProtocol.protocolVersion,
        identity: HelperReleaseIdentity? = nil,
        identityResult: [String: String]? = nil,
        responseDelayMilliseconds: Int = 0
    ) throws {
        // 全程用局部变量。在 `thread` 赋值前读 `descriptor` 或 `port`
        // 等于读 `self`，Swift 不允许，闭包捕获更不行。
        // 三个存储属性留到最后一并赋值。
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FakeHelperError.socket("socket() failed") }

        guard let address = UnixSocketAddress(path: socketPath) else {
            close(fd)
            throw FakeHelperError.socket("path too long: \(socketPath)")
        }
        let bound = address.withSockaddr { pointer, length in
            Darwin.bind(fd, pointer, length)
        }
        guard bound == 0 else {
            close(fd)
            throw FakeHelperError.socket("bind() failed: \(String(cString: strerror(errno)))")
        }
        guard listen(fd, 8) == 0 else {
            close(fd)
            throw FakeHelperError.socket("listen() failed")
        }

        let state = FakeHelperState()
        state.version = version
        state.protocolVersion = protocolVersion
        state.identityResult = identityResult ?? identity.map(Self.identityResult)
        state.responseDelayMilliseconds = responseDelayMilliseconds

        descriptor = fd
        port = state
        thread = Thread { FakeHelper.serve(descriptor: fd, port: state) }
        thread.name = "FakeHelper"
        thread.start()
    }

    func stop() {
        port.stopped = true
        shutdown(descriptor, SHUT_RDWR)
        close(descriptor)
    }

    func setIdentity(_ identity: HelperReleaseIdentity) {
        port.identityResult = Self.identityResult(identity)
    }

    deinit { stop() }

    private static func serve(descriptor: Int32, port: FakeHelperState) {
        while !port.stopped {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            defer { close(client) }

            guard let line = UnixSocketIO.readLine(
                client,
                limit: Int(HelperWire.shared.MAX_REQUEST_BYTES)
            ),
                let request = HelperWire.shared.decodeRequest(line: line)
            else { continue }

            port.append(request.command)
            // 用共享层的回复构造器：真 helper 回的字节与它一模一样。
            // `result` 必须显式传：Kotlin 的默认参数值不导出到 Swift。
            let reply: HelperReply
            if request.command == HelperWire.shared.COMMAND_VERSION {
                if let identityResult = port.identityResult {
                    reply = HelperWire.shared.success(
                        requestId: request.requestId,
                        result: identityResult
                    )
                } else {
                    var result = ["version": port.version]
                    if let protocolVersion = port.protocolVersion {
                        result["protocolVersion"] = protocolVersion
                    }
                    reply = HelperWire.shared.success(
                        requestId: request.requestId,
                        result: result
                    )
                }
            } else if request.command == HelperWire.shared.COMMAND_LID_LEASE_ACQUIRE
                || request.command == HelperWire.shared.COMMAND_LID_LEASE_RENEW {
                reply = HelperWire.shared.leaseStatusReply(
                    requestId: request.requestId,
                    sleepDisabled: KotlinBoolean(bool: true),
                    covioOwned: KotlinBoolean(bool: true),
                    activeLeaseCount: 1,
                    expiresAtEpochSeconds: KotlinLong(longLong: 1_000)
                )
            } else if request.command == HelperWire.shared.COMMAND_LID_LEASE_RELEASE {
                reply = HelperWire.shared.leaseStatusReply(
                    requestId: request.requestId,
                    sleepDisabled: KotlinBoolean(bool: false),
                    covioOwned: KotlinBoolean(bool: false),
                    activeLeaseCount: 0,
                    expiresAtEpochSeconds: nil
                )
            } else if request.command == HelperWire.shared.COMMAND_CHARGE_LIMIT_STATUS {
                reply = HelperWire.shared.success(
                    requestId: request.requestId,
                    result: [
                        "enabled": "true",
                        "userLimitPercent": "85",
                        "targetPercent": "85",
                        "chargingLatch": "true",
                        "phase": "charging",
                        "bypassEngaged": "false",
                        "originalFeatureState": "0",
                        "originalLimitPercent": "80",
                        "activeDischarge": "true",
                        "activeDischargeSupported": "true",
                    ]
                )
            } else {
                reply = HelperWire.shared.success(requestId: request.requestId, result: [:])
            }
            if port.responseDelayMilliseconds > 0 {
                Thread.sleep(
                    forTimeInterval: Double(port.responseDelayMilliseconds) / 1_000
                )
            }
            UnixSocketIO.writeAll(client, HelperWire.shared.encodeReply(reply: reply) + "\n")
        }
    }

    private static func identityResult(_ identity: HelperReleaseIdentity) -> [String: String] {
        [
            "version": identity.clientVersion,
            "releaseId": identity.releaseId,
            "clientVersion": identity.clientVersion,
            "productVersion": identity.productVersion,
            "buildNumber": identity.buildNumber,
            "gitCommit": identity.gitCommit,
            "protocolVersion": identity.protocolVersion,
            "helperSHA256": identity.helperSHA256,
            "channel": identity.channel,
        ]
    }
}

/// 跨线程传一次状态。假 helper 的 accept 循环在后台线程上跑。
private final class FakeHelperState: @unchecked Sendable {
    private let lock = NSLock()
    private var versionStorage = ""
    private var protocolVersionStorage: String?
    private var identityResultStorage: [String: String]?
    private var responseDelayMillisecondsStorage = 0
    private var commandsStorage: [String] = []
    private var stoppedStorage = false

    var version: String {
        get { lock.withLock { versionStorage } }
        set { lock.withLock { versionStorage = newValue } }
    }

    var protocolVersion: String? {
        get { lock.withLock { protocolVersionStorage } }
        set { lock.withLock { protocolVersionStorage = newValue } }
    }

    var identityResult: [String: String]? {
        get { lock.withLock { identityResultStorage } }
        set { lock.withLock { identityResultStorage = newValue } }
    }

    var commands: [String] { lock.withLock { commandsStorage } }

    var responseDelayMilliseconds: Int {
        get { lock.withLock { responseDelayMillisecondsStorage } }
        set { lock.withLock { responseDelayMillisecondsStorage = newValue } }
    }

    var stopped: Bool {
        get { lock.withLock { stoppedStorage } }
        set { lock.withLock { stoppedStorage = newValue } }
    }

    func append(_ command: String) { lock.withLock { commandsStorage.append(command) } }
}

private enum FakeHelperError: Error {
    case socket(String)
}

private final class SilentLogger: NSObject, AppLogger {
    func info(message: String) {}
    func warn(message: String, error: KotlinThrowable?) {}
    func error(message: String, error: KotlinThrowable?) {}
    func logFile() -> String { "" }
}

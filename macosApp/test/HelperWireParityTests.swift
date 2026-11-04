import XCTest
@testable import Covio

/// 线上协议的共享语料，在 Swift 侧再跑一遍。
///
/// 语料文件 `kmpDomain/test/fixtures/helper-wire-vectors.json` 两侧共用。
/// Kotlin 侧是 `HelperWireVectorTest`，那边验协议行为；这边多验一件事：
/// 导出的 framework 真的能被 Swift 调用，参数与返回值的形状没有变。
///
/// 所以这个文件同时是导出冒烟测试。Kotlin 侧改了签名而这里没跟上时会红。
final class HelperWireParityTests: XCTestCase {
    private static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("kmpDomain/test/fixtures/helper-wire-vectors.json")

    func testTheCorpusIsWhereTheTestsExpectIt() throws {
        let document = try Self.document()

        XCTAssertGreaterThanOrEqual((document["requests"] as? [Any])?.count ?? 0, 15)
        XCTAssertGreaterThanOrEqual((document["replies"] as? [Any])?.count ?? 0, 5)
        XCTAssertGreaterThanOrEqual((document["constructed"] as? [Any])?.count ?? 0, 5)
    }

    func testEveryRequestVectorBehavesTheSameAsKotlin() throws {
        for vector in try Self.vectors("requests") {
            let name = vector["name"] as? String ?? "\(vector)"
            let line = try XCTUnwrap(vector["line"] as? String, name)
            let decoded = HelperWire.shared.decodeRequest(line: line)

            guard vector["decode"] as? String == "ok" else {
                XCTAssertNil(decoded, "\(name)：这行不该解得出来")
                continue
            }

            let request = try XCTUnwrap(decoded, "\(name)：这行应该解得出来")
            XCTAssertEqual(
                HelperWire.shared.validate(request: request),
                vector["validate"] as? String,
                "\(name)：拒绝原因不同"
            )
            XCTAssertEqual(
                HelperWire.shared.pmsetArguments(request: request),
                vector["pmsetArguments"] as? [String],
                "\(name)：pmset 参数不同"
            )
            XCTAssertEqual(
                HelperWire.shared.encodeRequest(request: request),
                vector["reencoded"] as? String,
                "\(name)：再编码的字节不同"
            )
        }
    }

    func testEveryReplyVectorBehavesTheSameAsKotlin() throws {
        for vector in try Self.vectors("replies") {
            let name = vector["name"] as? String ?? "\(vector)"
            let line = try XCTUnwrap(vector["line"] as? String, name)
            let decoded = HelperWire.shared.decodeReply(line: line)

            guard vector["decode"] as? String == "ok" else {
                XCTAssertNil(decoded, "\(name)：这行不该解得出来")
                continue
            }

            let reply = try XCTUnwrap(decoded, "\(name)：这行应该解得出来")
            XCTAssertEqual(reply.ok, vector["ok"] as? Bool, "\(name)：ok 不同")
            XCTAssertEqual(
                reply.result?["version"],
                vector["resultVersion"] as? String,
                "\(name)：result 不同"
            )
            XCTAssertEqual(reply.error, vector["error"] as? String, "\(name)：error 不同")
            XCTAssertEqual(
                HelperWire.shared.encodeReply(reply: reply),
                vector["reencoded"] as? String,
                "\(name)：再编码的字节不同"
            )
        }
    }

    func testEveryConstructedReplyIsByteForByteTheExpectedOne() throws {
        for vector in try Self.vectors("constructed") {
            let name = vector["name"] as? String ?? "\(vector)"
            let requestId = try XCTUnwrap(vector["requestId"] as? String, name)
            let reply: HelperReply

            switch vector["call"] as? String {
            case "success":
                reply = HelperWire.shared.success(
                    requestId: requestId,
                    result: vector["result"] as? [String: String] ?? [:]
                )
            case "failure":
                reply = HelperWire.shared.failure(
                    requestId: requestId,
                    message: try XCTUnwrap(vector["message"] as? String, name)
                )
            case "pmsetReply":
                reply = HelperWire.shared.pmsetReply(
                    requestId: requestId,
                    exitCode: Int32(try XCTUnwrap(vector["exitCode"] as? Int, name)),
                    output: try XCTUnwrap(vector["output"] as? String, name)
                )
            default:
                XCTFail("\(name)：语料里的 call 认不出来：\(vector["call"] ?? "nil")")
                continue
            }

            XCTAssertEqual(
                HelperWire.shared.encodeReply(reply: reply),
                vector["expected"] as? String,
                name
            )
        }
    }

    /// 版本应答带的是本版的版本号，语料里写死会随版本升级而过期，所以单独测。
    func testTheVersionReplyCarriesTheShippedVersion() {
        let reply = HelperWire.shared.versionReply(requestId: "r")

        XCTAssertTrue(reply.ok)
        XCTAssertEqual(reply.result?["version"], CovioReleaseIdentity.APP_VERSION)
        XCTAssertEqual(reply.result?["protocolVersion"], HelperProtocol.protocolVersion)
        let expected = "{\"version\":\"\(HelperProtocol.protocolVersion)\",\"requestId\":\"r\",\"ok\":true,\"result\":{\"version\":\"\(CovioReleaseIdentity.APP_VERSION)\",\"protocolVersion\":\"\(HelperProtocol.protocolVersion)\"}}"
        XCTAssertEqual(
            HelperWire.shared.encodeReply(reply: reply),
            expected
        )
    }

    func testIdentityVersionReplyKeepsTheLegacyVersionField() {
        let identity = HelperReleaseIdentity(
            releaseId: "0.6.0-internal.24-g0123456789abcdef0123456789abcdef01234567",
            clientVersion: "0.6.0-internal.24",
            productVersion: "0.6.0",
            buildNumber: "24",
            gitCommit: "0123456789abcdef0123456789abcdef01234567",
            protocolVersion: "10",
            helperSHA256: String(repeating: "a", count: 64),
            channel: "internal"
        )

        let reply = HelperWire.shared.versionReply(requestId: "r", identity: identity)

        XCTAssertTrue(reply.ok)
        XCTAssertEqual(reply.result?["version"], identity.clientVersion)
        XCTAssertEqual(reply.result?["clientVersion"], identity.clientVersion)
        XCTAssertEqual(reply.result?["helperSHA256"], identity.helperSHA256)
    }

    /// 字节上限与 socket 权限位也来自共享层，不在这里另写一份。
    func testTheWireLimitsComeFromKotlin() {
        XCTAssertEqual(Int(HelperWire.shared.MAX_REQUEST_BYTES), 64 * 1024)
        XCTAssertEqual(Int(HelperWire.shared.MAX_REPLY_BYTES), 64 * 1024)
        XCTAssertEqual(Int(HelperWire.shared.SOCKET_PERMISSIONS), 0o666)
    }

    private static func document() throws -> [String: Any] {
        let data = try Data(contentsOf: fixture)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "语料不是 JSON 对象：\(fixture.path)"
        )
    }

    private static func vectors(_ key: String) throws -> [[String: Any]] {
        let document = try document()
        return try XCTUnwrap(document[key] as? [[String: Any]], "语料缺 \(key)：\(fixture.path)")
    }
}

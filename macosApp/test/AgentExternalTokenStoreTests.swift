import XCTest
@testable import Covio

final class AgentExternalTokenStoreTests: XCTestCase {
    func testTokenStoreLoadsCreatesRotatesAndDeletesThroughRustKeychain() throws {
        let suffix = UUID().uuidString
        let dataRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-agent-token-test-\(suffix)")
            .path
        let vaultService = "com.wyz.covio.credentials.test.\(suffix)"
        let environment = ProcessInfo.processInfo.environment
        let previousRoot = environment["COVIO_APPLICATION_SUPPORT_ROOT"]
        let previousVaultService = environment["COVIO_AGENT_VAULT_SERVICE"]
        setenv("COVIO_APPLICATION_SUPPORT_ROOT", dataRoot, 1)
        setenv("COVIO_AGENT_VAULT_SERVICE", vaultService, 1)
        defer {
            if let previousRoot {
                setenv("COVIO_APPLICATION_SUPPORT_ROOT", previousRoot, 1)
            } else {
                unsetenv("COVIO_APPLICATION_SUPPORT_ROOT")
            }
            if let previousVaultService {
                setenv("COVIO_AGENT_VAULT_SERVICE", previousVaultService, 1)
            } else {
                unsetenv("COVIO_AGENT_VAULT_SERVICE")
            }
            try? FileManager.default.removeItem(atPath: dataRoot)
        }
        let store = AgentExternalTokenStore(
            service: "com.wyz.covio.agent.external.test.\(suffix)",
            account: "mcp-bearer-token"
        )
        defer {
            try? store.delete()
            try? CovioAgentTokenKeychain.reset()
        }

        let first = try store.loadOrCreate()
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(try store.loadOrCreate(), first)

        let rotated = try store.rotate()
        XCTAssertNotEqual(rotated, first)
        XCTAssertEqual(try store.loadOrCreate(), rotated)

        try store.delete()
        let recreated = try store.loadOrCreate()
        XCTAssertFalse(recreated.isEmpty)
        XCTAssertNotEqual(recreated, rotated)
    }
}

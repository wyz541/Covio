import XCTest
@testable import Covio

final class AgentExternalTokenStoreTests: XCTestCase {
    func testTokenStoreLoadsCreatesRotatesAndDeletesThroughRustKeychain() throws {
        let suffix = UUID().uuidString
        let store = AgentExternalTokenStore(
            service: "com.wyz.covio.agent.external.test.\(suffix)",
            account: "mcp-bearer-token"
        )
        defer { try? store.delete() }

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

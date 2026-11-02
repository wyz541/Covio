import XCTest
@testable import Covio

final class ReleaseIdentityDisplayTests: XCTestCase {
    func testClientVersionIsThePrimaryVersionAndMetadataStaysSeparate() {
        let display = ReleaseIdentityDisplay(
            clientVersion: "0.0.1.6",
            channel: "internal",
            buildNumber: 16,
            gitCommit: "59505ebc1fb1e1bddf3d09afdc2e686015b9d16b",
            helperProtocolVersion: 10
        )

        XCTAssertEqual(display.clientVersion, "0.0.1.6")
        XCTAssertEqual(display.channel, "internal")
        XCTAssertEqual(display.buildNumber, "16")
        XCTAssertEqual(display.gitShortSHA, "59505ebc1fb1")
        XCTAssertEqual(display.helperProtocolVersion, "10")
    }

    func testShortGitIdentityIsBoundedAndKeepsDevelopmentBuildsReadable() {
        XCTAssertEqual(
            ReleaseIdentityDisplay(gitCommit: "abc").gitShortSHA,
            "abc"
        )
        XCTAssertEqual(
            ReleaseIdentityDisplay(gitCommit: "  development  ").gitShortSHA,
            "development"
        )
        XCTAssertEqual(
            ReleaseIdentityDisplay(gitCommit: "   ").gitShortSHA,
            "development"
        )
    }
}

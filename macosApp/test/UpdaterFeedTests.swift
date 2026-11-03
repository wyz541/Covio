import XCTest
@testable import Covio

final class UpdaterFeedTests: XCTestCase {
    func testParserAcceptsOnlyFixedInternalReleaseAssets() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [release(version: "0.0.2.0")]
        )
        let candidates = try GithubUpdaterFeed.parseReleases(data)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.tagName, "v0.0.2.0-internal")
        XCTAssertEqual(candidate.clientVersion, "0.0.2.0")
        XCTAssertEqual(
            candidate.manifestURL.absoluteString,
            "https://github.com/wyz541/kmp-Covio/releases/download/v0.0.2.0-internal/CovioUpdate-0.0.2.0.json"
        )
    }

    func testParserSortsNewestClientVersionFirst() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                release(version: "0.0.1.9"),
                release(version: "0.0.2.0"),
            ]
        )
        let candidates = try GithubUpdaterFeed.parseReleases(data)
        XCTAssertEqual(candidates.map(\.clientVersion), ["0.0.2.0", "0.0.1.9"])
    }

    func testParserRejectsDraftAndNonInternalReleases() throws {
        var draft = release(version: "0.0.2.0")
        draft["draft"] = true
        var publicRelease = release(version: "0.0.2.1")
        publicRelease["tag_name"] = "v0.0.2.1"
        let data = try JSONSerialization.data(withJSONObject: [draft, publicRelease])
        let candidates = try GithubUpdaterFeed.parseReleases(data)
        XCTAssertTrue(candidates.isEmpty)
    }

    func testParserRejectsWrongAssetNameAndURL() throws {
        var wrongName = release(version: "0.0.2.0")
        wrongName["assets"] = [
            asset(name: "CovioUpdate-0.0.2.0.zip", version: "0.0.2.0"),
            asset(name: "CovioUpdate-0.0.2.0.json", version: "0.0.2.0"),
            asset(name: "wrong.sig.json", version: "0.0.2.0"),
        ]
        var wrongHost = release(version: "0.0.2.1")
        wrongHost["assets"] = [
            asset(name: "CovioUpdate-0.0.2.1.zip", version: "0.0.2.1"),
            asset(
                name: "CovioUpdate-0.0.2.1.json",
                version: "0.0.2.1",
                host: "example.com"
            ),
            asset(name: "CovioUpdate-0.0.2.1.sig.json", version: "0.0.2.1"),
        ]
        let data = try JSONSerialization.data(withJSONObject: [wrongName, wrongHost])
        let candidates = try GithubUpdaterFeed.parseReleases(data)
        XCTAssertTrue(candidates.isEmpty)
    }

    func testClientVersionAllowsOnlySingleDigitSegments() {
        XCTAssertEqual(GithubUpdaterFeed.clientVersion(fromInternalTag: "v0.0.2.0-internal"), "0.0.2.0")
        XCTAssertNil(GithubUpdaterFeed.clientVersion(fromInternalTag: "v0.0.2.10-internal"))
        XCTAssertNil(GithubUpdaterFeed.clientVersion(fromInternalTag: "v0.0.2.0"))
    }

    private func release(version: String) -> [String: Any] {
        [
            "tag_name": "v\(version)-internal",
            "draft": false,
            "prerelease": true,
            "published_at": "2026-11-03T00:00:00Z",
            "assets": [
                asset(name: "CovioUpdate-\(version).zip", version: version),
                asset(name: "CovioUpdate-\(version).json", version: version),
                asset(name: "CovioUpdate-\(version).sig.json", version: version),
            ],
        ]
    }

    private func asset(
        name: String,
        version: String,
        host: String = "github.com"
    ) -> [String: Any] {
        [
            "name": name,
            "browser_download_url": "https://\(host)/wyz541/kmp-Covio/releases/download/v\(version)-internal/\(name)",
        ]
    }
}

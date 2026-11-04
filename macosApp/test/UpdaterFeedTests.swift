import XCTest
@testable import Covio

final class UpdaterFeedTests: XCTestCase {
    func testParserAcceptsOnlyFixedInternalReleaseAssets() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [release(version: "0.6.0-internal.20")]
        )
        let candidates = try GithubUpdaterFeed.parseReleases(data)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.tagName, "v0.6.0-internal.20")
        XCTAssertEqual(candidate.clientVersion, "0.6.0-internal.20")
        XCTAssertEqual(
            candidate.manifestURL.absoluteString,
            "https://github.com/wyz541/kmp-Covio/releases/download/v0.6.0-internal.20/CovioUpdate-0.6.0-internal.20.json"
        )
    }

    func testParserSortsNewestSemanticVersionFirst() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                release(version: "0.6.0-internal.9"),
                release(version: "0.6.0-internal.10"),
            ]
        )
        let candidates = try GithubUpdaterFeed.parseReleases(data)
        XCTAssertEqual(
            candidates.map(\.clientVersion),
            ["0.6.0-internal.10", "0.6.0-internal.9"]
        )
    }

    func testParserRejectsDraftAndStableReleases() throws {
        var draft = release(version: "0.6.0-internal.20")
        draft["draft"] = true
        var publicRelease = release(version: "0.6.0-internal.21")
        publicRelease["tag_name"] = "v0.6.0"
        let data = try JSONSerialization.data(withJSONObject: [draft, publicRelease])
        let candidates = try GithubUpdaterFeed.parseReleases(data)
        XCTAssertTrue(candidates.isEmpty)
    }

    func testParserRejectsWrongAssetNameAndURL() throws {
        var wrongName = release(version: "0.6.0-internal.20")
        wrongName["assets"] = [
            asset(name: "CovioUpdate-0.6.0-internal.20.zip", version: "0.6.0-internal.20"),
            asset(name: "CovioUpdate-0.6.0-internal.20.json", version: "0.6.0-internal.20"),
            asset(name: "wrong.sig.json", version: "0.6.0-internal.20"),
        ]
        var wrongHost = release(version: "0.6.0-internal.21")
        wrongHost["assets"] = [
            asset(name: "CovioUpdate-0.6.0-internal.21.zip", version: "0.6.0-internal.21"),
            asset(
                name: "CovioUpdate-0.6.0-internal.21.json",
                version: "0.6.0-internal.21",
                host: "example.com"
            ),
            asset(name: "CovioUpdate-0.6.0-internal.21.sig.json", version: "0.6.0-internal.21"),
        ]
        let data = try JSONSerialization.data(withJSONObject: [wrongName, wrongHost])
        let candidates = try GithubUpdaterFeed.parseReleases(data)
        XCTAssertTrue(candidates.isEmpty)
    }

    func testInternalTagRequiresCanonicalSemanticVersion() {
        XCTAssertEqual(
            GithubUpdaterFeed.clientVersion(fromInternalTag: "v0.6.0-internal.23"),
            "0.6.0-internal.23"
        )
        XCTAssertEqual(
            GithubUpdaterFeed.clientVersion(fromInternalTag: "v0.6.0-internal.10"),
            "0.6.0-internal.10"
        )
        XCTAssertNil(GithubUpdaterFeed.clientVersion(fromInternalTag: "v0.6.0-internal.023"))
        XCTAssertNil(GithubUpdaterFeed.clientVersion(fromInternalTag: "v0.6.0"))
        XCTAssertNil(GithubUpdaterFeed.clientVersion(fromInternalTag: "v0.0.2.0-internal"))
    }

    private func release(version: String) -> [String: Any] {
        [
            "tag_name": "v\(version)",
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
            "browser_download_url": "https://\(host)/wyz541/kmp-Covio/releases/download/v\(version)/\(name)",
        ]
    }
}

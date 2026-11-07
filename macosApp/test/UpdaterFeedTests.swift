import XCTest
@testable import Covio

final class UpdaterFeedTests: XCTestCase {
    func testParserBuildsAssetsFromInternalAtomEntries() throws {
        let data = atom(entries: [
            ("v0.6.0-internal.20", "2026-11-05T00:00:00Z"),
        ])
        let candidates = try GithubUpdaterFeed.parseReleases(data)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.tagName, "v0.6.0-internal.20")
        XCTAssertEqual(candidate.clientVersion, "0.6.0-internal.20")
        XCTAssertEqual(candidate.publishedAt, "2026-11-05T00:00:00Z")
        XCTAssertEqual(
            candidate.manifestURL.absoluteString,
            "https://github.com/wyz541/Covio/releases/download/v0.6.0-internal.20/CovioUpdate-0.6.0-internal.20.json"
        )
        XCTAssertEqual(
            candidate.signatureURL.absoluteString,
            "https://github.com/wyz541/Covio/releases/download/v0.6.0-internal.20/CovioUpdate-0.6.0-internal.20.sig.json"
        )
        XCTAssertEqual(
            candidate.archiveURL.absoluteString,
            "https://github.com/wyz541/Covio/releases/download/v0.6.0-internal.20/CovioUpdate-0.6.0-internal.20.zip"
        )
    }

    func testParserAcceptsLegacyRepositoryLinks() throws {
        let data = atom(
            entries: [("v0.6.0-internal.20", "2026-11-05T00:00:00Z")],
            path: "/wyz541/kmp-Covio/releases/tag"
        )
        let candidate = try XCTUnwrap(try GithubUpdaterFeed.parseReleases(data).first)
        XCTAssertEqual(candidate.tagName, "v0.6.0-internal.20")
        XCTAssertEqual(candidate.clientVersion, "0.6.0-internal.20")
    }

    func testParserSortsNewestSemanticVersionFirst() throws {
        let data = atom(entries: [
            ("v0.6.0-internal.9", "2026-11-03T00:00:00Z"),
            ("v0.6.0-internal.10", "2026-11-04T00:00:00Z"),
        ])
        let candidates = try GithubUpdaterFeed.parseReleases(data)
        XCTAssertEqual(
            candidates.map(\.clientVersion),
            ["0.6.0-internal.10", "0.6.0-internal.9"]
        )
    }

    func testParserRejectsStableAndMalformedEntries() throws {
        let data = atom(entries: [
            ("v0.6.0", "2026-11-05T00:00:00Z"),
            ("v0.0.2.0-internal", "2026-11-05T00:00:00Z"),
            ("v0.6.0-internal.21", "not-a-date"),
        ])
        let candidates = try GithubUpdaterFeed.parseReleases(data)
        XCTAssertTrue(candidates.isEmpty)
    }

    func testParserRejectsLinksOutsideTheReleaseTagRoute() throws {
        let wrongHost = atom(
            entries: [("v0.6.0-internal.20", "2026-11-05T00:00:00Z")],
            host: "example.com"
        )
        let wrongPath = atom(
            entries: [("v0.6.0-internal.21", "2026-11-05T00:00:00Z")],
            path: "/wyz541/other/other"
        )
        XCTAssertTrue(try GithubUpdaterFeed.parseReleases(wrongHost).isEmpty)
        XCTAssertTrue(try GithubUpdaterFeed.parseReleases(wrongPath).isEmpty)
    }

    func testParserRejectsMalformedXML() {
        XCTAssertThrowsError(
            try GithubUpdaterFeed.parseReleases(Data("<feed><entry>".utf8))
        ) { error in
            XCTAssertEqual(error as? UpdaterFeedError, .invalidResponse)
        }
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

    private func atom(
        entries: [(tag: String, updatedAt: String)],
        host: String = "github.com",
        path: String = "/wyz541/Covio/releases/tag"
    ) -> Data {
        let body = entries.map { entry in
            """
            <entry>
              <updated>\(entry.updatedAt)</updated>
              <link rel="alternate" type="text/html" href="https://\(host)\(path)/\(entry.tag)"/>
            </entry>
            """
        }.joined(separator: "\n")
        return Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <feed xmlns="http://www.w3.org/2005/Atom">
            \(body)
            </feed>
            """.utf8
        )
    }
}

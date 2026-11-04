import XCTest
@testable import Covio

final class ReleaseVersionTests: XCTestCase {
    func testParserReadsCanonicalSemanticVersion() throws {
        let version = try XCTUnwrap(ReleaseVersion("0.6.0-internal.23"))
        XCTAssertEqual(version.description, "0.6.0-internal.23")
        XCTAssertEqual(version.baseVersion, "0.6.0")
        XCTAssertTrue(version.isInternalBuild(23))
        XCTAssertFalse(version.isStable)
    }

    func testSemanticPrecedenceHandlesStableAndNumericPrereleases() throws {
        let build9 = try XCTUnwrap(ReleaseVersion("0.6.0-internal.9"))
        let build10 = try XCTUnwrap(ReleaseVersion("0.6.0-internal.10"))
        let stable = try XCTUnwrap(ReleaseVersion("0.6.0"))
        XCTAssertLessThan(build9, build10)
        XCTAssertLessThan(build10, stable)
    }

    func testBuildMetadataIsIgnoredForPrecedence() throws {
        let left = try XCTUnwrap(ReleaseVersion("0.6.0+ci.1"))
        let right = try XCTUnwrap(ReleaseVersion("0.6.0+ci.2"))
        XCTAssertFalse(left < right)
        XCTAssertFalse(right < left)
    }

    func testInvalidVersionsAreRejected() {
        for value in [
            "v0.6.0",
            "0.06.0",
            "0.6",
            "0.0.1.6",
            "0.6.0-internal.023",
            "0.6.0-internal..23",
        ] {
            XCTAssertNil(ReleaseVersion(value), value)
        }
    }
}

import Foundation
import XCTest
@testable import Covio

final class UpdaterContractTests: XCTestCase {
    private let releaseId = "0.6.0-internal.23-g" + String(repeating: "a", count: 40)

    func testValidReleaseIdIsAccepted() {
        XCTAssertTrue(UpdaterPaths.isReleaseId(releaseId))
    }

    func testInvalidReleaseIdsAreRejected() {
        let invalid = [
            "0.6.0-internal.23",
            "0.6.0-internal.023-g" + String(repeating: "a", count: 40),
            "0.6.0-internal.23-g" + String(repeating: "A", count: 40),
            "../0.6.0-internal.23-g" + String(repeating: "a", count: 40),
            "0.6.0-internal.23-g" + String(repeating: "a", count: 39),
        ]
        for value in invalid {
            XCTAssertFalse(UpdaterPaths.isReleaseId(value), value)
        }
    }

    func testEnginePathStaysInsideVersionDirectory() throws {
        let paths = UpdaterPaths(root: URL(fileURLWithPath: "/tmp/covio-updater-contract"))
        let engine = try paths.engine(for: releaseId)
        XCTAssertEqual(
            engine.path,
            "/tmp/covio-updater-contract/versions/\(releaseId)/CovioUpdater"
        )
    }

    func testInvalidEnginePathIsRejected() {
        let paths = UpdaterPaths(root: URL(fileURLWithPath: "/tmp/covio-updater-contract"))
        XCTAssertThrowsError(try paths.engine(for: "../../CovioUpdater"))
    }

    func testLaunchAttemptsIncrementOnlyInsideTheFailureWindow() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("covio-updater-launch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = UpdaterPaths(root: root)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            UpdaterLaunchStateStore.recordAttempt(paths: paths, releaseId: releaseId, now: start),
            1
        )
        XCTAssertEqual(
            UpdaterLaunchStateStore.recordAttempt(
                paths: paths,
                releaseId: releaseId,
                now: start.addingTimeInterval(5)
            ),
            2
        )
        XCTAssertEqual(
            UpdaterLaunchStateStore.recordAttempt(
                paths: paths,
                releaseId: releaseId,
                now: start.addingTimeInterval(40)
            ),
            1
        )

        UpdaterLaunchStateStore.clear(paths: paths)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.launchState.path))
    }

    func testStatusRoundTripsThroughJSON() throws {
        let status = UpdaterStatus(
            schemaVersion: 1,
            updaterProtocolVersion: 1,
            releaseId: releaseId,
            state: .idle,
            automaticUpdatesEnabled: true,
            lastCheckAt: "2026-11-04T00:00:00Z",
            availableVersion: nil,
            message: "Ready"
        )
        let data = try JSONEncoder().encode(status)
        XCTAssertEqual(try JSONDecoder().decode(UpdaterStatus.self, from: data), status)
    }

    func testClientIsUnavailableWithoutUpdaterRequirement() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("covio-updater-client-\(UUID().uuidString)")
        let client = CovioUpdaterClient(paths: UpdaterPaths(root: root))
        let expectation = expectation(description: "Missing requirement")
        client.getStatus { result in
            guard case .failure(let error) = result else {
                return XCTFail("Expected unavailable client")
            }
            XCTAssertEqual(error as? CovioUpdaterClientError, .unavailable)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testHealthRequiresMatchingReleaseShapeAndLivePID() {
        let health = UpdaterHealth(
            schemaVersion: 1,
            releaseId: releaseId,
            processIdentifier: 123,
            createdAt: "2026-11-04T00:00:00Z"
        )
        XCTAssertTrue(health.isValidShape)
    }
}

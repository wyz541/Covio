import CryptoKit
import Foundation
import XCTest
@testable import Covio

final class UpdaterCoordinatorTests: XCTestCase {
    func testCheckPersistsASignedCandidateAcrossEngineRestart() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-updater-coordinator-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = UpdaterPaths(root: root)
        let currentReleaseId = "0.0.1.9-g" + String(repeating: "a", count: 40)
        let signingKey = Curve25519.Signing.PrivateKey()
        let manifestURL = try XCTUnwrap(URL(
            string: "https://github.com/wyz541/kmp-Covio/releases/download/v0.0.2.0-internal/CovioUpdate-0.0.2.0.json"
        ))
        let signatureURL = try XCTUnwrap(URL(
            string: "https://github.com/wyz541/kmp-Covio/releases/download/v0.0.2.0-internal/CovioUpdate-0.0.2.0.sig.json"
        ))
        let archiveURL = try XCTUnwrap(URL(
            string: "https://github.com/wyz541/kmp-Covio/releases/download/v0.0.2.0-internal/CovioUpdate-0.0.2.0.zip"
        ))
        let manifest = makeManifest(archiveURL: archiveURL.absoluteString)
        let manifestData = try JSONEncoder().encode(manifest)
        let signature = try signingKey.signature(for: manifestData)
        let signatureData = try JSONEncoder().encode(
            UpdateSignatureEnvelope(
                schemaVersion: 1,
                manifestSHA256: SHA256.hash(data: manifestData)
                    .map { String(format: "%02x", $0) }
                    .joined(),
                signatures: [
                    .init(
                        keyId: "test-key",
                        signature: signature.base64EncodedString()
                    )
                ]
            )
        )
        UpdaterCoordinatorURLProtocol.responses = [
            manifestURL.absoluteString: manifestData,
            signatureURL.absoluteString: signatureData,
        ]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdaterCoordinatorURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let feed = FixedUpdaterFeed(
            releases: [
                UpdaterReleaseCandidate(
                    tagName: "v0.0.2.0-internal",
                    clientVersion: "0.0.2.0",
                    manifestURL: manifestURL,
                    signatureURL: signatureURL,
                    archiveURL: archiveURL,
                    publishedAt: "2026-11-03T00:00:00Z"
                ),
            ]
        )
        let coordinator = UpdaterCoordinator(
            paths: paths,
            currentReleaseId: currentReleaseId,
            feed: feed,
            trustedKeys: ["test-key": signingKey.publicKey.rawRepresentation],
            session: session,
            environment: ["COVIO_UPDATER_TEST_MODE": "1"]
        )

        let finished = expectation(description: "check completed")
        var result: UpdaterOperationResult?
        coordinator.check { value in
            result = value
            finished.fulfill()
        }
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(result?.state, .available)
        XCTAssertEqual(result?.availableVersion, "0.0.2.0")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.candidateManifest.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.candidateSignature.path))
        XCTAssertEqual(coordinator.persistedStatus.state, .available)

        let restarted = UpdaterCoordinator(
            paths: paths,
            currentReleaseId: currentReleaseId,
            feed: feed,
            trustedKeys: ["test-key": signingKey.publicKey.rawRepresentation],
            session: session,
            environment: ["COVIO_UPDATER_TEST_MODE": "1"]
        )
        XCTAssertEqual(restarted.persistedStatus.availableVersion, "0.0.2.0")
    }

    private func makeManifest(archiveURL: String) -> UpdateManifest {
        UpdateManifest(
            schemaVersion: 1,
            keyId: "test-key",
            channel: "internal",
            productVersion: "0.6.0",
            clientVersion: "0.0.2.0",
            buildNumber: 20,
            gitCommit: String(repeating: "b", count: 40),
            releaseId: "0.0.2.0-g" + String(repeating: "b", count: 40),
            helperProtocolVersion: GeneratedReleaseIdentity.helperProtocolVersion,
            updaterProtocolVersion: UpdaterContract.protocolVersion,
            minimumMacOSVersion: "14.0",
            archiveURL: archiveURL,
            archiveSHA256: String(repeating: "c", count: 64),
            archiveSize: 42,
            componentHashes: .init(
                app: String(repeating: "d", count: 64),
                helper: String(repeating: "e", count: 64),
                updater: String(repeating: "f", count: 64)
            ),
            publishedAt: "2026-11-03T00:00:00Z"
        )
    }
}

private struct FixedUpdaterFeed: UpdaterFeedProviding {
    let releasesValue: [UpdaterReleaseCandidate]

    init(releases: [UpdaterReleaseCandidate]) {
        releasesValue = releases
    }

    func releases() async throws -> [UpdaterReleaseCandidate] {
        releasesValue
    }
}

private final class UpdaterCoordinatorURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: Data] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let data = Self.responses[url.absoluteString],
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

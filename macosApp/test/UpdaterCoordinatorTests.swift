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
        let currentReleaseId = "0.6.0-internal.23-g" + String(repeating: "a", count: 40)
        let nextBuild = GeneratedReleaseIdentity.buildNumber + 1
        let nextClientVersion = "0.6.0-internal.\(nextBuild)"
        let releaseTag = "v\(nextClientVersion)"
        let signingKey = Curve25519.Signing.PrivateKey()
        let manifestURL = try XCTUnwrap(URL(
            string: "https://github.com/wyz541/kmp-Covio/releases/download/\(releaseTag)/CovioUpdate-\(nextClientVersion).json"
        ))
        let signatureURL = try XCTUnwrap(URL(
            string: "https://github.com/wyz541/kmp-Covio/releases/download/\(releaseTag)/CovioUpdate-\(nextClientVersion).sig.json"
        ))
        let archiveURL = try XCTUnwrap(URL(
            string: "https://github.com/wyz541/kmp-Covio/releases/download/\(releaseTag)/CovioUpdate-\(nextClientVersion).zip"
        ))
        let manifest = makeManifest(
            archiveURL: archiveURL.absoluteString,
            clientVersion: nextClientVersion,
            buildNumber: nextBuild
        )
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
                    tagName: releaseTag,
                    clientVersion: nextClientVersion,
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
        XCTAssertEqual(result?.availableVersion, nextClientVersion)
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
        XCTAssertEqual(restarted.persistedStatus.availableVersion, nextClientVersion)
    }

    func testStartupDoesNotRecoverAnActivePKGTransaction() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-updater-pkg-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = UpdaterPaths(root: root.appendingPathComponent("Updater"))
        let marker = root.appendingPathComponent("recovered")
        try writeInstallTransaction(paths: paths, mode: "pkg", recoveryMarker: marker)
        let coordinator = UpdaterCoordinator(
            paths: paths,
            currentReleaseId: "0.6.0-internal.23-g" + String(repeating: "a", count: 40),
            trustedKeys: [:]
        )

        _ = coordinator.startupStatus()

        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testStartupRecoversAnInterruptedAutomaticTransaction() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-updater-auto-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = UpdaterPaths(root: root.appendingPathComponent("Updater"))
        let marker = root.appendingPathComponent("recovered")
        try writeInstallTransaction(paths: paths, mode: "automatic", recoveryMarker: marker)
        let coordinator = UpdaterCoordinator(
            paths: paths,
            currentReleaseId: "0.6.0-internal.23-g" + String(repeating: "a", count: 40),
            trustedKeys: [:]
        )

        _ = coordinator.startupStatus()

        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    private func writeInstallTransaction(
        paths: UpdaterPaths,
        mode: String,
        recoveryMarker: URL
    ) throws {
        let transaction = paths.transactions.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: true)
        try "UPDATE_MODE='\(mode)'\n".write(
            to: transaction.appendingPathComponent("transaction.env"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: paths.currentInstallTransaction.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (transaction.path + "\n").write(
            to: paths.currentInstallTransaction,
            atomically: true,
            encoding: .utf8
        )
        let script = "#!/bin/sh\nprintf recovered > '\(recoveryMarker.path)'\n"
        try script.write(to: paths.recoverInstallScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: paths.recoverInstallScript.path
        )
    }

    private func makeManifest(
        archiveURL: String,
        clientVersion: String,
        buildNumber: Int
    ) -> UpdateManifest {
        UpdateManifest(
            schemaVersion: 2,
            keyId: "test-key",
            channel: "internal",
            productVersion: GeneratedReleaseIdentity.productVersion,
            clientVersion: clientVersion,
            buildNumber: buildNumber,
            gitCommit: String(repeating: "b", count: 40),
            releaseId: "\(clientVersion)-g" + String(repeating: "b", count: 40),
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

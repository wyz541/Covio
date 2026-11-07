import CryptoKit
import XCTest
@testable import Covio

final class UpdateManifestTests: XCTestCase {
    private let keyId = "covio-internal-test"
    private let commit = String(repeating: "a", count: 40)
    private let key = Curve25519.Signing.PrivateKey()

    private var expectations: UpdateManifestExpectations {
        UpdateManifestExpectations(
            currentVersion: "0.6.0-internal.19",
            currentBuildNumber: 19,
            channel: "internal",
            helperProtocolVersion: 10,
            updaterProtocolVersion: 1,
            macOSVersion: "26.1"
        )
    }

    private var trustedKeys: [String: Data] {
        [keyId: key.publicKey.rawRepresentation]
    }

    func testValidManifestIsAccepted() throws {
        let verified = try verify()
        XCTAssertEqual(verified.buildNumber, 20)
        XCTAssertEqual(verified.clientVersion, "0.6.0-internal.20")
        XCTAssertEqual(verified.releaseId, "0.6.0-internal.20-g\(commit)")
    }

    func testManifestByteChangeFailsDigestValidation() throws {
        var signed = try signedManifest()
        signed.manifest.append(0x20)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(error as? UpdateManifestError, .digestMismatch)
        }
    }

    func testInvalidSignatureIsRejected() throws {
        var signed = try signedManifest()
        var envelope = try JSONDecoder().decode(
            UpdateSignatureEnvelope.self,
            from: signed.signature
        )
        var bytes = try XCTUnwrap(Data(base64Encoded: envelope.signatures[0].signature))
        bytes[0] ^= 0xff
        envelope = UpdateSignatureEnvelope(
            schemaVersion: envelope.schemaVersion,
            manifestSHA256: envelope.manifestSHA256,
            signatures: [
                .init(
                    keyId: envelope.signatures[0].keyId,
                    signature: bytes.base64EncodedString()
                )
            ]
        )
        signed.signature = try JSONEncoder().encode(envelope)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(
                error as? UpdateManifestError,
                .invalidSignature(keyId)
            )
        }
    }

    func testUntrustedKeyIsRejected() throws {
        let signed = try signedManifest()
        XCTAssertThrowsError(
            try UpdateManifestVerifier.verify(
                manifestData: signed.manifest,
                signatureData: signed.signature,
                trustedKeys: [:],
                expectations: expectations
            )
        ) { error in
            XCTAssertEqual(
                error as? UpdateManifestError,
                .missingTrustedKey(self.keyId)
            )
        }
    }

    func testWrongChannelIsRejected() throws {
        let manifest = makeManifest(channel: "public")
        let signed = try signedManifest(manifest)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(
                error as? UpdateManifestError,
                .unsupportedChannel("public")
            )
        }
    }

    func testSameVersionAndBuildIsRejected() throws {
        let manifest = makeManifest(
            clientVersion: "0.6.0-internal.19",
            buildNumber: 19
        )
        let signed = try signedManifest(manifest)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(error as? UpdateManifestError, .olderVersion)
        }
    }

    func testClientVersionMustMatchBuildNumber() throws {
        let manifest = makeManifest(clientVersion: "0.6.0-internal.21")
        let signed = try signedManifest(manifest)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(error as? UpdateManifestError, .versionBuildMismatch)
        }
    }

    func testPrereleaseWithLeadingZeroIsRejected() throws {
        let manifest = makeManifest(clientVersion: "0.6.0-internal.020")
        let signed = try signedManifest(manifest)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(error as? UpdateManifestError, .invalidVersion)
        }
    }

    func testReleaseIdMustMatchVersionAndCommit() throws {
        let manifest = makeManifest(
            releaseId: "0.6.0-internal.20-g\(String(repeating: "f", count: 40))"
        )
        let signed = try signedManifest(manifest)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(error as? UpdateManifestError, .invalidReleaseId)
        }
    }

    func testUppercaseArchiveDigestIsRejected() throws {
        let manifest = makeManifest(
            archiveSHA256: String(repeating: "A", count: 64)
        )
        let signed = try signedManifest(manifest)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(error as? UpdateManifestError, .invalidArchiveDigest)
        }
    }

    func testOversizedArchiveIsRejected() throws {
        let manifest = makeManifest(archiveSize: 500_000_001)
        let signed = try signedManifest(manifest)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(error as? UpdateManifestError, .invalidArchiveSize)
        }
    }

    func testArchiveURLMustUseFixedRepositoryAndTag() throws {
        let manifest = makeManifest(
            archiveURL: "https://example.com/CovioUpdate-0.6.0-internal.20.zip"
        )
        let signed = try signedManifest(manifest)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(error as? UpdateManifestError, .invalidArchiveURL)
        }
    }

    func testLegacyRepositoryArchiveURLIsAccepted() throws {
        let manifest = makeManifest(
            archiveURL: (
                "https://github.com/wyz541/kmp-Covio/releases/download/"
                    + "v0.6.0-internal.20/CovioUpdate-0.6.0-internal.20.zip"
            )
        )
        let signed = try signedManifest(manifest)
        XCTAssertNoThrow(try verify(signed))
    }

    func testProtocolMismatchIsRejected() throws {
        let manifest = makeManifest(helperProtocolVersion: 9)
        let signed = try signedManifest(manifest)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(error as? UpdateManifestError, .protocolMismatch)
        }
    }

    func testNewerMinimumOSIsRejected() throws {
        let manifest = makeManifest(minimumMacOSVersion: "27.0")
        let signed = try signedManifest(manifest)
        XCTAssertThrowsError(try verify(signed)) { error in
            XCTAssertEqual(error as? UpdateManifestError, .operatingSystemTooOld)
        }
    }

    private func verify(_ signed: SignedManifest? = nil) throws -> UpdateManifest {
        let value = try signed ?? signedManifest()
        return try UpdateManifestVerifier.verify(
            manifestData: value.manifest,
            signatureData: value.signature,
            trustedKeys: trustedKeys,
            expectations: expectations
        )
    }

    private func makeManifest(
        channel: String = "internal",
        clientVersion: String = "0.6.0-internal.20",
        buildNumber: Int = 20,
        helperProtocolVersion: Int = 10,
        minimumMacOSVersion: String = "26.0",
        archiveURL: String? = nil,
        releaseId: String? = nil,
        archiveSHA256: String = String(repeating: "b", count: 64),
        archiveSize: Int = 42
    ) -> UpdateManifest {
        return UpdateManifest(
            schemaVersion: 2,
            keyId: keyId,
            channel: channel,
            productVersion: "0.6.0",
            clientVersion: clientVersion,
            buildNumber: buildNumber,
            gitCommit: commit,
            releaseId: releaseId ?? "\(clientVersion)-g\(commit)",
            helperProtocolVersion: helperProtocolVersion,
            updaterProtocolVersion: 1,
            minimumMacOSVersion: minimumMacOSVersion,
            archiveURL: archiveURL
                ?? "https://github.com/wyz541/Covio/releases/download/v\(clientVersion)/CovioUpdate-\(clientVersion).zip",
            archiveSHA256: archiveSHA256,
            archiveSize: archiveSize,
            componentHashes: .init(
                app: String(repeating: "c", count: 64),
                helper: String(repeating: "d", count: 64),
                updater: String(repeating: "e", count: 64)
            ),
            publishedAt: "2026-11-04T00:00:00Z"
        )
    }

    private func signedManifest(
        _ value: UpdateManifest? = nil
    ) throws -> SignedManifest {
        let manifest = value ?? makeManifest()
        let manifestData = try JSONEncoder().encode(manifest)
        let signature = try key.signature(for: manifestData)
        let digest = SHA256.hash(data: manifestData)
            .map { String(format: "%02x", $0) }
            .joined()
        let envelope = UpdateSignatureEnvelope(
            schemaVersion: 1,
            manifestSHA256: digest,
            signatures: [
                .init(keyId: keyId, signature: signature.base64EncodedString())
            ]
        )
        return SignedManifest(
            manifest: manifestData,
            signature: try JSONEncoder().encode(envelope)
        )
    }
}

private struct SignedManifest {
    var manifest: Data
    var signature: Data
}

import CryptoKit
import Foundation

struct UpdateManifest: Codable, Equatable, Sendable {
    struct ComponentHashes: Codable, Equatable, Sendable {
        let app: String
        let helper: String
        let updater: String
    }

    let schemaVersion: Int
    let keyId: String
    let channel: String
    let productVersion: String
    let clientVersion: String
    let buildNumber: Int
    let gitCommit: String
    let releaseId: String
    let helperProtocolVersion: Int
    let updaterProtocolVersion: Int
    let minimumMacOSVersion: String
    let archiveURL: String
    let archiveSHA256: String
    let archiveSize: Int
    let componentHashes: ComponentHashes
    let publishedAt: String
}

struct UpdateSignatureEnvelope: Codable, Equatable, Sendable {
    struct Signature: Codable, Equatable, Sendable {
        let keyId: String
        let signature: String
    }

    let schemaVersion: Int
    let manifestSHA256: String
    let signatures: [Signature]
}

struct UpdateManifestExpectations: Equatable, Sendable {
    let currentVersion: String
    let currentBuildNumber: Int
    let channel: String
    let helperProtocolVersion: Int
    let updaterProtocolVersion: Int
    let macOSVersion: String
}

enum UpdateManifestError: Error, Equatable, LocalizedError {
    case invalidEnvelope
    case digestMismatch
    case missingTrustedKey(String)
    case invalidSignature(String)
    case invalidManifest
    case unsupportedSchema
    case unsupportedChannel(String)
    case invalidVersion
    case invalidBuild
    case versionBuildMismatch
    case invalidCommit
    case invalidReleaseId
    case protocolMismatch
    case olderVersion
    case olderBuild
    case invalidArchiveURL
    case invalidArchiveDigest
    case invalidArchiveSize
    case operatingSystemTooOld

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope: "Update signature envelope is invalid"
        case .digestMismatch: "Update manifest digest does not match"
        case .missingTrustedKey(let keyId): "Untrusted update key: \(keyId)"
        case .invalidSignature(let keyId): "Invalid update signature: \(keyId)"
        case .invalidManifest: "Update manifest is invalid"
        case .unsupportedSchema: "Unsupported update manifest schema"
        case .unsupportedChannel(let channel): "Unsupported update channel: \(channel)"
        case .invalidVersion: "Invalid client version"
        case .invalidBuild: "Invalid build number"
        case .versionBuildMismatch: "Client version does not match build number"
        case .invalidCommit: "Invalid Git commit"
        case .invalidReleaseId: "Invalid release ID"
        case .protocolMismatch: "Update protocol mismatch"
        case .olderVersion: "Update version is not newer than the installed version"
        case .olderBuild: "Update is not newer than the installed build"
        case .invalidArchiveURL: "Invalid update archive URL"
        case .invalidArchiveDigest: "Invalid update archive digest"
        case .invalidArchiveSize: "Invalid update archive size"
        case .operatingSystemTooOld: "Update requires a newer macOS version"
        }
    }
}

enum UpdateManifestVerifier {
    static let schemaVersion = 2
    static let signatureEnvelopeSchemaVersion = 1
    static let maximumArchiveBytes = 500_000_000
    static let repository = "wyz541/kmp-Covio"

    static func verify(
        manifestData: Data,
        signatureData: Data,
        trustedKeys: [String: Data],
        expectations: UpdateManifestExpectations
    ) throws -> UpdateManifest {
        let envelope: UpdateSignatureEnvelope
        do {
            envelope = try JSONDecoder().decode(UpdateSignatureEnvelope.self, from: signatureData)
        } catch {
            throw UpdateManifestError.invalidEnvelope
        }

        guard envelope.schemaVersion == signatureEnvelopeSchemaVersion,
              !envelope.signatures.isEmpty,
              envelope.signatures.count <= 8,
              isLowercaseHex(envelope.manifestSHA256, count: 64)
        else {
            throw UpdateManifestError.invalidEnvelope
        }
        guard envelope.manifestSHA256 == sha256Hex(manifestData) else {
            throw UpdateManifestError.digestMismatch
        }

        var seen = Set<String>()
        for signature in envelope.signatures {
            guard seen.insert(signature.keyId).inserted,
                  let publicKeyData = trustedKeys[signature.keyId],
                  publicKeyData.count == 32,
                  let signatureBytes = Data(base64Encoded: signature.signature),
                  signatureBytes.count == 64
            else {
                throw UpdateManifestError.missingTrustedKey(signature.keyId)
            }
            let publicKey: Curve25519.Signing.PublicKey
            do {
                publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
            } catch {
                throw UpdateManifestError.missingTrustedKey(signature.keyId)
            }
            guard publicKey.isValidSignature(signatureBytes, for: manifestData) else {
                throw UpdateManifestError.invalidSignature(signature.keyId)
            }
        }

        let manifest: UpdateManifest
        do {
            manifest = try JSONDecoder().decode(UpdateManifest.self, from: manifestData)
        } catch {
            throw UpdateManifestError.invalidManifest
        }

        try validate(manifest, signatures: envelope.signatures, expectations: expectations)
        return manifest
    }

    private static func validate(
        _ manifest: UpdateManifest,
        signatures: [UpdateSignatureEnvelope.Signature],
        expectations: UpdateManifestExpectations
    ) throws {
        guard manifest.schemaVersion == schemaVersion else {
            throw UpdateManifestError.unsupportedSchema
        }
        guard manifest.channel == "internal",
              manifest.channel == expectations.channel
        else {
            throw UpdateManifestError.unsupportedChannel(manifest.channel)
        }
        guard !manifest.keyId.isEmpty,
              manifest.keyId.count <= 64,
              isProductVersion(manifest.productVersion)
        else {
            throw UpdateManifestError.invalidManifest
        }
        guard let version = ReleaseVersion(manifest.clientVersion),
              version.buildMetadata.isEmpty,
              version.baseVersion == manifest.productVersion
        else {
            throw UpdateManifestError.invalidVersion
        }
        guard (1...9_999).contains(manifest.buildNumber) else {
            throw UpdateManifestError.invalidBuild
        }
        guard version.isInternalBuild(manifest.buildNumber) else {
            throw UpdateManifestError.versionBuildMismatch
        }
        guard let currentVersion = ReleaseVersion(expectations.currentVersion),
              currentVersion.buildMetadata.isEmpty,
              version > currentVersion
        else {
            throw UpdateManifestError.olderVersion
        }
        guard manifest.buildNumber > expectations.currentBuildNumber else {
            throw UpdateManifestError.olderBuild
        }
        guard isLowercaseHex(manifest.gitCommit, count: 40) else {
            throw UpdateManifestError.invalidCommit
        }
        guard manifest.releaseId == "\(manifest.clientVersion)-g\(manifest.gitCommit)" else {
            throw UpdateManifestError.invalidReleaseId
        }
        guard manifest.helperProtocolVersion == expectations.helperProtocolVersion,
              manifest.updaterProtocolVersion == expectations.updaterProtocolVersion
        else {
            throw UpdateManifestError.protocolMismatch
        }
        guard signatures.contains(where: { $0.keyId == manifest.keyId }) else {
            throw UpdateManifestError.invalidEnvelope
        }
        guard isLowercaseHex(manifest.archiveSHA256, count: 64) else {
            throw UpdateManifestError.invalidArchiveDigest
        }
        guard manifest.archiveSize > 0,
              manifest.archiveSize <= maximumArchiveBytes
        else {
            throw UpdateManifestError.invalidArchiveSize
        }
        guard isTrustedArchiveURL(manifest.archiveURL, clientVersion: manifest.clientVersion) else {
            throw UpdateManifestError.invalidArchiveURL
        }
        guard isLowercaseHex(manifest.componentHashes.app, count: 64),
              isLowercaseHex(manifest.componentHashes.helper, count: 64),
              isLowercaseHex(manifest.componentHashes.updater, count: 64)
        else {
            throw UpdateManifestError.invalidArchiveDigest
        }
        guard versionParts(manifest.minimumMacOSVersion) != nil else {
            throw UpdateManifestError.invalidManifest
        }
        guard isVersion(manifest.minimumMacOSVersion, atMost: expectations.macOSVersion) else {
            throw UpdateManifestError.operatingSystemTooOld
        }
        guard ISO8601DateFormatter().date(from: manifest.publishedAt) != nil else {
            throw UpdateManifestError.invalidManifest
        }
    }

    private static func isTrustedArchiveURL(_ value: String, clientVersion: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme == "https",
              components.host == "github.com",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil
        else {
            return false
        }
        let expected = "/\(repository)/releases/download/v\(clientVersion)/CovioUpdate-\(clientVersion).zip"
        return components.percentEncodedPath == expected
    }

    private static func isLowercaseHex(_ value: String, count: Int) -> Bool {
        value.count == count && value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
        }
    }

    private static func isProductVersion(_ value: String) -> Bool {
        guard let version = ReleaseVersion(value) else { return false }
        return version.isStable && version.buildMetadata.isEmpty
    }

    private static func isVersion(_ required: String, atMost current: String) -> Bool {
        guard let requiredParts = versionParts(required),
              let currentParts = versionParts(current)
        else {
            return false
        }
        let count = max(requiredParts.count, currentParts.count)
        for index in 0..<count {
            let lhs = index < requiredParts.count ? requiredParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs < rhs { return true }
            if lhs > rhs { return false }
        }
        return true
    }

    private static func versionParts(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count,
              numbers.allSatisfy({ $0 >= 0 })
        else {
            return nil
        }
        return numbers
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

import CryptoKit
import Darwin
import Foundation
import Security

private struct PrivateKeyFile: Codable {
    let schemaVersion: Int
    let keyId: String
    let seed: String
}

private struct PublicKeyFile: Codable {
    let schemaVersion: Int
    let keyId: String
    let publicKey: String
}

private struct SignatureEnvelope: Codable {
    struct Signature: Codable {
        let keyId: String
        let signature: String
    }

    let schemaVersion: Int
    let manifestSHA256: String
    let signatures: [Signature]
}

private enum ToolError: Error, CustomStringConvertible {
    case usage
    case invalidKey
    case invalidInput

    var description: String {
        switch self {
        case .usage: "Invalid arguments"
        case .invalidKey: "Invalid Ed25519 key file"
        case .invalidInput: "Invalid manifest or signature data"
        }
    }
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

private func argumentValue(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name),
          index + 1 < arguments.count
    else {
        return nil
    }
    return arguments[index + 1]
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func readPrivateKey(_ path: String) throws -> (PrivateKeyFile, Curve25519.Signing.PrivateKey) {
    try parsePrivateKey(Data(contentsOf: URL(fileURLWithPath: path)))
}

private func parsePrivateKey(_ data: Data) throws -> (PrivateKeyFile, Curve25519.Signing.PrivateKey) {
    let file = try JSONDecoder().decode(PrivateKeyFile.self, from: data)
    guard file.schemaVersion == 1,
          !file.keyId.isEmpty,
          let seed = Data(base64Encoded: file.seed),
          seed.count == 32
    else {
        throw ToolError.invalidKey
    }
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    return (file, key)
}

private func readPublicKey(_ path: String) throws -> (PublicKeyFile, Curve25519.Signing.PublicKey) {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let file = try JSONDecoder().decode(PublicKeyFile.self, from: data)
    guard file.schemaVersion == 1,
          !file.keyId.isEmpty,
          let publicKey = Data(base64Encoded: file.publicKey),
          publicKey.count == 32
    else {
        throw ToolError.invalidKey
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    return (file, key)
}

private func readKeychainPrivateKey(
    service: String,
    account: String
) throws -> (PrivateKeyFile, Curve25519.Signing.PrivateKey) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess,
          let data = item as? Data
    else {
        throw ToolError.invalidKey
    }
    let file = try JSONDecoder().decode(PrivateKeyFile.self, from: data)
    guard file.schemaVersion == 1,
          file.keyId == account,
          let seed = Data(base64Encoded: file.seed),
          seed.count == 32
    else {
        throw ToolError.invalidKey
    }
    return (file, try Curve25519.Signing.PrivateKey(rawRepresentation: seed))
}

private func writeJSON<T: Encodable>(_ value: T, to path: String, permissions: Int) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(value)
    data.append(0x0A)
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let temporary = url.appendingPathExtension("tmp-\(UUID().uuidString)")
    if FileManager.default.fileExists(atPath: temporary.path) {
        try FileManager.default.removeItem(at: temporary)
    }
    guard FileManager.default.createFile(
        atPath: temporary.path,
        contents: data,
        attributes: [.posixPermissions: permissions]
    ) else {
        throw ToolError.invalidInput
    }
    if chmod(temporary.path, mode_t(permissions)) != 0 {
        throw ToolError.invalidInput
    }
    if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
    }
    try FileManager.default.moveItem(at: temporary, to: url)
}

private func keygen(_ arguments: [String]) throws {
    guard let keyId = argumentValue("--key-id", in: arguments),
          !keyId.isEmpty,
          let privatePath = argumentValue("--private-key", in: arguments),
          let publicPath = argumentValue("--public-key", in: arguments)
    else {
        throw ToolError.usage
    }
    let key = Curve25519.Signing.PrivateKey()
    let privateFile = PrivateKeyFile(
        schemaVersion: 1,
        keyId: keyId,
        seed: key.rawRepresentation.base64EncodedString()
    )
    let publicFile = PublicKeyFile(
        schemaVersion: 1,
        keyId: keyId,
        publicKey: key.publicKey.rawRepresentation.base64EncodedString()
    )
    try writeJSON(privateFile, to: privatePath, permissions: 0o600)
    try writeJSON(publicFile, to: publicPath, permissions: 0o644)
}

private func signManifest(
    keyFile: PrivateKeyFile,
    key: Curve25519.Signing.PrivateKey,
    manifestPath: String,
    outputPath: String
) throws {
    let manifest = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    let signature = try key.signature(for: manifest)
    let envelope = SignatureEnvelope(
        schemaVersion: 1,
        manifestSHA256: sha256Hex(manifest),
        signatures: [
            .init(keyId: keyFile.keyId, signature: signature.base64EncodedString())
        ]
    )
    try writeJSON(envelope, to: outputPath, permissions: 0o644)
}

private func sign(_ arguments: [String]) throws {
    guard let privatePath = argumentValue("--private-key", in: arguments),
          let manifestPath = argumentValue("--manifest", in: arguments),
          let outputPath = argumentValue("--output", in: arguments)
    else {
        throw ToolError.usage
    }
    let (keyFile, key) = try readPrivateKey(privatePath)
    try signManifest(
        keyFile: keyFile,
        key: key,
        manifestPath: manifestPath,
        outputPath: outputPath
    )
}

private func signKeychain(_ arguments: [String]) throws {
    guard let service = argumentValue("--service", in: arguments),
          let account = argumentValue("--account", in: arguments),
          let manifestPath = argumentValue("--manifest", in: arguments),
          let outputPath = argumentValue("--output", in: arguments)
    else {
        throw ToolError.usage
    }
    let (keyFile, key) = try readKeychainPrivateKey(
        service: service,
        account: account
    )
    try signManifest(
        keyFile: keyFile,
        key: key,
        manifestPath: manifestPath,
        outputPath: outputPath
    )
}

private func privateKeyInput(_ data: Data) throws -> Data {
    let trimmed = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("{") {
        return Data(trimmed.utf8)
    }
    guard trimmed.count.isMultiple(of: 2),
          trimmed.unicodeScalars.allSatisfy({
              ($0.value >= 48 && $0.value <= 57)
                  || ($0.value >= 97 && $0.value <= 102)
                  || ($0.value >= 65 && $0.value <= 70)
          })
    else {
        throw ToolError.invalidKey
    }
    var decoded = Data(capacity: trimmed.count / 2)
    var index = trimmed.startIndex
    while index < trimmed.endIndex {
        let end = trimmed.index(index, offsetBy: 2)
        guard let byte = UInt8(trimmed[index..<end], radix: 16) else {
            throw ToolError.invalidKey
        }
        decoded.append(byte)
        index = end
    }
    return decoded
}

private func signStdin(_ arguments: [String]) throws {
    guard let manifestPath = argumentValue("--manifest", in: arguments),
          let outputPath = argumentValue("--output", in: arguments)
    else {
        throw ToolError.usage
    }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let (keyFile, key) = try parsePrivateKey(privateKeyInput(data))
    try signManifest(
        keyFile: keyFile,
        key: key,
        manifestPath: manifestPath,
        outputPath: outputPath
    )
}

private func verify(_ arguments: [String]) throws {
    guard let publicPath = argumentValue("--public-key", in: arguments),
          let manifestPath = argumentValue("--manifest", in: arguments),
          let signaturePath = argumentValue("--signature", in: arguments)
    else {
        throw ToolError.usage
    }
    let (keyFile, key) = try readPublicKey(publicPath)
    let manifest = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    let signatureData = try Data(contentsOf: URL(fileURLWithPath: signaturePath))
    let envelope = try JSONDecoder().decode(SignatureEnvelope.self, from: signatureData)
    guard envelope.schemaVersion == 1,
          envelope.manifestSHA256 == sha256Hex(manifest),
          let record = envelope.signatures.first(where: { $0.keyId == keyFile.keyId }),
          let signature = Data(base64Encoded: record.signature),
          key.isValidSignature(signature, for: manifest)
    else {
        throw ToolError.invalidInput
    }
}

private func main() -> Int32 {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        fail("Usage: CovioUpdateSigner <keygen|sign|sign-keychain|sign-stdin|verify> ...")
    }
    do {
        switch command {
        case "keygen": try keygen(arguments)
        case "sign": try sign(arguments)
        case "sign-keychain": try signKeychain(arguments)
        case "sign-stdin": try signStdin(arguments)
        case "verify": try verify(arguments)
        default: throw ToolError.usage
        }
        return 0
    } catch {
        fail(error.localizedDescription)
    }
}

exit(main())

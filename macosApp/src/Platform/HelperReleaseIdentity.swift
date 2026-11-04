import CryptoKit
import Foundation

/// 读取当前进程可携带的完整发布身份。
///
/// helper 在进程启动时缓存这个值。app 更新磁盘上的文件后，仍在运行的旧 helper
/// 继续报告启动时的身份，不会把新文件误报成当前进程身份。
enum HelperReleaseIdentitySource {
    // 发布身份在启动后不可变。
    nonisolated(unsafe) static let daemonIdentity: HelperReleaseIdentity? = makeIdentity(
        helperExecutablePath: ownExecutablePath
    )

    nonisolated(unsafe) static let expectedAppIdentity: HelperReleaseIdentity? = makeIdentity(
        helperExecutablePath: bundledHelperExecutablePath
    )

    static var bundledHelperExecutablePath: String? {
        guard let executable = Bundle.main.executablePath else { return nil }
        let candidate = Bundle.main.bundleURL
            .appendingPathComponent(HelperProtocol.helperExecutableBundlePath)
            .path
        return FileManager.default.fileExists(atPath: candidate) ? candidate : executable
    }

    /// 新 Local LaunchDaemon 使用固定 helper 路径。旧安装先回退到当前 bundle。
    static var installedHelperExecutablePath: String {
        let local = HelperProtocol.helperBinaryPath
        if FileManager.default.fileExists(atPath: local) {
            return local
        }
        return bundledHelperExecutablePath ?? local
    }

    private static var ownExecutablePath: String? {
        Bundle.main.executablePath
    }

    private static func makeIdentity(helperExecutablePath: String?) -> HelperReleaseIdentity? {
        guard let helperExecutablePath,
              let sha256 = sha256File(path: helperExecutablePath)
        else {
            return nil
        }
        let info = Bundle.main.infoDictionary ?? [:]
        let gitCommit = (info["CovioGitCommit"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let releaseId = (info["CovioReleaseId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return HelperReleaseHandshake.shared.parse(
            result: [
                "releaseId": releaseId ?? "",
                "clientVersion": GeneratedReleaseIdentity.clientVersion,
                "productVersion": GeneratedReleaseIdentity.productVersion,
                "buildNumber": String(GeneratedReleaseIdentity.buildNumber),
                "gitCommit": gitCommit ?? "",
                "protocolVersion": String(GeneratedReleaseIdentity.helperProtocolVersion),
                "helperSHA256": sha256,
                "channel": GeneratedReleaseIdentity.channel,
            ]
        )
    }

    private static func sha256File(path: String) -> String? {
        guard let file = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? file.close() }
        var hasher = SHA256()
        do {
            while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

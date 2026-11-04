import Darwin
import Foundation
import Security

/// 一次完整握手。调用方只根据返回状态决定是否开放特权写入。
enum HelperReleaseInspector {
    static func inspect(
        client: HelperClient,
        expectedIdentity: HelperReleaseIdentity? = HelperReleaseIdentitySource.expectedAppIdentity,
        expectedExecutablePath: String? = HelperReleaseIdentitySource.installedHelperExecutablePath,
        isTrusted: (pid_t?, String) -> Bool = {
            HelperCodeTrust.isTrusted(peerPID: $0, expectedExecutablePath: $1)
        }
    ) -> HelperStatus {
        guard client.canReachHelper else { return .missing }
        guard let probe = client.versionProbe() else { return .untrusted }
        guard let observed = HelperReleaseHandshake.shared.parse(result: probe.result) else {
            return HelperReleaseHandshake.shared.hasIdentityFields(result: probe.result)
                ? .untrusted
                : .outdated
        }
        guard let expectedIdentity, let expectedExecutablePath else { return .untrusted }
        return HelperReleaseHandshake.shared.classify(
            expected: expectedIdentity,
            observed: observed,
            signatureTrusted: probe.transportTrusted
                || isTrusted(probe.peerPID, expectedExecutablePath)
        )
    }
}

/// 验证 socket 对端确实是当前发布包中的 helper 可执行文件。
enum HelperCodeTrust {
    static func isTrusted(peerPID: pid_t?, expectedExecutablePath: String) -> Bool {
        guard let peerPID, peerPID > 0 else { return false }
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: peerPID)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess,
              let actualPath = executablePath(pid: peerPID)
        else {
            return false
        }
        return canonicalPath(actualPath) == canonicalPath(expectedExecutablePath)
    }

    private static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4_096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

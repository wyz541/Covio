import Foundation
import kmpDomain

@main
enum CovioHelperMain {
    static func main() {
        if CommandLine.arguments.contains("--print-release-identity") {
            exit(printReleaseIdentity())
        }
        if CommandLine.arguments.contains("--print-xpc-requirement") {
            guard let requirement = HelperSignature.mainAppRequirement() else {
                exit(1)
            }
            print(requirement)
            exit(0)
        }
        exit(CovioHelperRuntime.run())
    }

    private static func printReleaseIdentity() -> Int32 {
        guard let identity = HelperReleaseIdentitySource.daemonIdentity,
              let data = try? JSONEncoder().encode(identityDictionary(identity)),
              let text = String(data: data, encoding: .utf8)
        else {
            return 1
        }
        print(text)
        return 0
    }

    private static func identityDictionary(
        _ identity: HelperReleaseIdentity
    ) -> [String: String] {
        [
            "releaseId": identity.releaseId,
            "clientVersion": identity.clientVersion,
            "productVersion": identity.productVersion,
            "buildNumber": identity.buildNumber,
            "gitCommit": identity.gitCommit,
            "protocolVersion": identity.protocolVersion,
            "helperSHA256": identity.helperSHA256,
            "channel": identity.channel,
        ]
    }
}

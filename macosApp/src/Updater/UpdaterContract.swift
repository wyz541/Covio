import Foundation

enum UpdaterContract {
    static let defaultMachServiceName = "com.wyz.covio.updater.xpc"
    static let repository = "wyz541/Covio"
    static let legacyRepository = "wyz541/kmp-Covio"

    static var machServiceName: String {
        let override = ProcessInfo.processInfo.environment["COVIO_UPDATER_XPC_SERVICE_NAME"] ?? ""
        return override.isEmpty ? defaultMachServiceName : override
    }
    static let launchDaemonLabel = "com.wyz.covio.updater"
    static let protocolVersion = 1
    static let launcherIdentifier = "com.wyz.covio.updater.launcher"
    static let engineIdentifier = "com.wyz.covio.updater"

    /// The repository was renamed from `kmp-Covio` to `Covio`.
    /// Existing signed manifests still use the former download URL.
    static let trustedRepositories = [repository, legacyRepository]

    static func releaseTag(from href: String) -> String? {
        guard let url = URL(string: href),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              isTrustedGitHubURL(components)
        else {
            return nil
        }
        for repository in trustedRepositories {
            let prefix = "/\(repository)/releases/tag/"
            guard components.path.hasPrefix(prefix) else { continue }
            let tag = String(components.path.dropFirst(prefix.count))
            return tag.isEmpty || tag.contains("/") ? nil : tag
        }
        return nil
    }

    static func isTrustedArchiveURL(_ value: String, clientVersion: String) -> Bool {
        guard let components = URLComponents(string: value) else {
            return false
        }
        return isTrustedArchiveURL(components, clientVersion: clientVersion)
    }

    static func isTrustedArchiveURL(_ value: URL, clientVersion: String) -> Bool {
        guard let components = URLComponents(url: value, resolvingAgainstBaseURL: false) else {
            return false
        }
        return isTrustedArchiveURL(components, clientVersion: clientVersion)
    }

    private static func isTrustedArchiveURL(
        _ components: URLComponents,
        clientVersion: String
    ) -> Bool {
        guard isTrustedGitHubURL(components) else { return false }
        let suffix = "/releases/download/v\(clientVersion)/CovioUpdate-\(clientVersion).zip"
        return trustedRepositories.contains {
            components.percentEncodedPath == "/\($0)\(suffix)"
        }
    }

    private static func isTrustedGitHubURL(_ components: URLComponents) -> Bool {
        components.scheme == "https"
            && components.host == "github.com"
            && components.user == nil
            && components.password == nil
            && components.port == nil
            && components.query == nil
            && components.fragment == nil
    }
}

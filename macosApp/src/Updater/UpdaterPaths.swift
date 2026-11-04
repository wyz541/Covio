import Foundation

struct UpdaterPaths: Equatable {
    static let defaultRoot = "/Library/Application Support/Covio/Updater"

    let root: URL

    init() {
        self.init(root: URL(fileURLWithPath: Self.defaultRoot, isDirectory: true))
    }

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    init(environment: [String: String]) {
        let override = environment["COVIO_UPDATER_ROOT"] ?? ""
        if override.isEmpty {
            self.init(root: URL(fileURLWithPath: Self.defaultRoot, isDirectory: true))
        } else {
            self.init(root: URL(fileURLWithPath: override, isDirectory: true))
        }
    }

    var binDirectory: URL { root.appendingPathComponent("bin", isDirectory: true) }
    var launcher: URL { binDirectory.appendingPathComponent("CovioUpdaterLauncher") }
    var versions: URL { root.appendingPathComponent("versions", isDirectory: true) }
    var currentPointer: URL { root.appendingPathComponent("current") }
    var previousPointer: URL { root.appendingPathComponent("previous") }
    var health: URL { root.appendingPathComponent("health.json") }
    var clientRequirement: URL { root.appendingPathComponent("updater-client-requirement") }
    var updaterRequirement: URL { root.appendingPathComponent("updater-requirement") }
    var automaticPreferences: URL { root.appendingPathComponent("preferences", isDirectory: true) }
    var transactions: URL { root.appendingPathComponent("transactions", isDirectory: true) }
    var updateState: URL { root.appendingPathComponent("update-state.json") }
    var updateResult: URL { root.appendingPathComponent("update-result.json") }
    var candidateManifest: URL { root.appendingPathComponent("update-candidate.json") }
    var candidateSignature: URL { root.appendingPathComponent("update-candidate.sig.json") }
    var installerRoot: URL { root.deletingLastPathComponent().appendingPathComponent("Installer", isDirectory: true) }
    var currentInstallTransaction: URL { installerRoot.appendingPathComponent("current-transaction") }
    var recoverInstallScript: URL { installerRoot.appendingPathComponent("recover.sh") }
    var installUpdateScript: URL { installerRoot.appendingPathComponent("install-update.sh") }

    func engine(for releaseId: String) throws -> URL {
        guard Self.isReleaseId(releaseId) else {
            throw UpdaterPathError.invalidReleaseId
        }
        return versions
            .appendingPathComponent(releaseId, isDirectory: true)
            .appendingPathComponent("CovioUpdater")
    }

    func preference(for uid: uid_t) -> URL {
        automaticPreferences.appendingPathComponent("\(uid).json")
    }

    static func isReleaseId(_ value: String) -> Bool {
        let components = value.split(separator: "-g", omittingEmptySubsequences: false)
        guard components.count == 2 else { return false }
        let version = String(components[0])
        guard ReleaseVersion(version) != nil || isLegacyClientVersion(version) else {
            return false
        }
        let commit = components[1]
        return commit.count == 40
            && commit.unicodeScalars.allSatisfy {
                ($0.value >= 48 && $0.value <= 57)
                    || ($0.value >= 97 && $0.value <= 102)
            }
    }

    private static func isLegacyClientVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            part.count == 1 && part.unicodeScalars.allSatisfy {
                $0.value >= 48 && $0.value <= 57
            }
        }
    }
}

enum UpdaterPathError: Error, Equatable, LocalizedError {
    case invalidReleaseId
    case missingPointer
    case invalidEnginePath
    case untrustedEngine

    var errorDescription: String? {
        switch self {
        case .invalidReleaseId: "Invalid updater release ID"
        case .missingPointer: "Missing updater engine pointer"
        case .invalidEnginePath: "Invalid updater engine path"
        case .untrustedEngine: "Untrusted updater engine"
        }
    }
}

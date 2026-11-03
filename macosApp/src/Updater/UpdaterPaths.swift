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

    var launcher: URL { root.appendingPathComponent("bin/CovioUpdaterLauncher") }
    var versions: URL { root.appendingPathComponent("versions", isDirectory: true) }
    var currentPointer: URL { root.appendingPathComponent("current") }
    var previousPointer: URL { root.appendingPathComponent("previous") }
    var health: URL { root.appendingPathComponent("health.json") }
    var clientRequirement: URL { root.appendingPathComponent("updater-client-requirement") }
    var updaterRequirement: URL { root.appendingPathComponent("updater-requirement") }
    var automaticPreferences: URL { root.appendingPathComponent("preferences", isDirectory: true) }

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
        let versionParts = components[0].split(separator: ".", omittingEmptySubsequences: false)
        guard versionParts.count == 4,
              versionParts.allSatisfy({ part in
                  part.count == 1 && part.unicodeScalars.allSatisfy {
                      $0.value >= 48 && $0.value <= 57
                  }
              })
        else {
            return false
        }
        let commit = components[1]
        return commit.count == 40
            && commit.unicodeScalars.allSatisfy {
                ($0.value >= 48 && $0.value <= 57)
                    || ($0.value >= 97 && $0.value <= 102)
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

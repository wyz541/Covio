import Foundation

enum UpdaterEngineState: String, Codable, Sendable {
    case notConfigured
    case idle
    case checking
    case available
    case downloading
    case installing
    case restartRequired
    case failed
    case repairRequired
}

struct UpdaterStatus: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let updaterProtocolVersion: Int
    let releaseId: String
    let state: UpdaterEngineState
    let automaticUpdatesEnabled: Bool
    let lastCheckAt: String?
    let availableVersion: String?
    let message: String?
}

struct UpdaterOperationResult: Codable, Equatable, Sendable {
    let ok: Bool
    let state: UpdaterEngineState
    let message: String
    let availableVersion: String?
}

struct UpdaterHealth: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let releaseId: String
    let processIdentifier: Int32
    let createdAt: String

    var isValidShape: Bool {
        schemaVersion == 1
            && processIdentifier > 0
            && UpdaterPaths.isReleaseId(releaseId)
            && ISO8601DateFormatter().date(from: createdAt) != nil
    }
}

struct UpdaterAutomaticPreference: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let automaticUpdatesEnabled: Bool
}

struct UpdaterPersistedState: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let state: UpdaterEngineState
    let lastCheckAt: String?
    let availableVersion: String?
    let targetReleaseId: String?
    let message: String?
}

struct UpdaterTransactionResult: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let state: UpdaterEngineState
    let transactionId: String?
    let targetReleaseId: String
    let previousReleaseId: String?
    let result: String
    let rollbackReason: String?
    let recordedAt: String
}

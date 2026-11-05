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

struct UpdaterLaunchState: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let releaseId: String
    let attempts: Int
    let lastAttemptAt: String
}

enum UpdaterLaunchStateStore {
    static let failureWindow: TimeInterval = 30
    static let stableDelay: TimeInterval = 30

    static func recordAttempt(
        paths: UpdaterPaths,
        releaseId: String,
        now: Date = Date()
    ) -> Int {
        var attempts = 1
        if let data = try? Data(contentsOf: paths.launchState),
           let previous = try? JSONDecoder().decode(UpdaterLaunchState.self, from: data),
           previous.schemaVersion == 1,
           previous.releaseId == releaseId,
           let previousDate = ISO8601DateFormatter().date(from: previous.lastAttemptAt),
           now.timeIntervalSince(previousDate) >= 0,
           now.timeIntervalSince(previousDate) <= failureWindow
        {
            attempts = previous.attempts + 1
        }
        let state = UpdaterLaunchState(
            schemaVersion: 1,
            releaseId: releaseId,
            attempts: attempts,
            lastAttemptAt: ISO8601DateFormatter().string(from: now)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = (try? encoder.encode(state)) ?? Data()
        data.append(0x0A)
        try? FileManager.default.createDirectory(
            at: paths.root,
            withIntermediateDirectories: true
        )
        try? data.write(to: paths.launchState, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: paths.launchState.path
        )
        return attempts
    }

    static func clear(paths: UpdaterPaths) {
        try? FileManager.default.removeItem(at: paths.launchState)
    }
}

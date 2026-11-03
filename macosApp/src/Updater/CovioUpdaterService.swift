import Darwin
import Foundation

@objc final class CovioUpdaterService: NSObject, CovioUpdaterXPCProtocol, @unchecked Sendable {
    typealias CheckHandler = (@escaping (UpdaterOperationResult) -> Void) -> Void
    typealias InstallHandler = (@escaping (UpdaterOperationResult) -> Void) -> Void

    private struct Caller {
        let uid: uid_t
        let processIdentifier: pid_t
        let auditSessionIdentifier: au_asid_t
        let groupIdentifier: gid_t
    }

    private let paths: UpdaterPaths
    private let releaseId: String
    private let checkHandler: CheckHandler?
    private let installHandler: InstallHandler?
    private let stateLock = NSLock()
    private var state: UpdaterEngineState
    private var lastCheckAt: String?
    private var availableVersion: String?
    private var message: String?
    private var lastManualCheckByUid: [uid_t: Date] = [:]

    init(
        paths: UpdaterPaths,
        releaseId: String,
        state: UpdaterEngineState = .notConfigured,
        lastCheckAt: String? = nil,
        availableVersion: String? = nil,
        message: String? = nil,
        checkHandler: CheckHandler? = nil,
        installHandler: InstallHandler? = nil
    ) {
        self.paths = paths
        self.releaseId = releaseId
        self.checkHandler = checkHandler
        self.installHandler = installHandler
        self.state = state
        self.lastCheckAt = lastCheckAt
        self.availableVersion = availableVersion
        self.message = message
        super.init()
    }

    func getStatus(withReply reply: @escaping (Data) -> Void) {
        guard let caller = currentCaller() else {
            reply(encoded(UpdaterOperationResult(
                ok: false,
                state: .repairRequired,
                message: "Missing XPC caller audit context",
                availableVersion: nil
            )))
            return
        }
        reply(encoded(status(for: caller.uid)))
    }

    func checkNow(withReply reply: @escaping (Data) -> Void) {
        guard let caller = currentCaller() else {
            reply(encoded(UpdaterOperationResult(
                ok: false,
                state: .repairRequired,
                message: "Missing XPC caller audit context",
                availableVersion: nil
            )))
            return
        }
        guard allowsManualCheck(uid: caller.uid) else {
            reply(encoded(UpdaterOperationResult(
                ok: false,
                state: .idle,
                message: "Update check requested too frequently",
                availableVersion: nil
            )))
            return
        }

        guard let checkHandler else {
            reply(encoded(UpdaterOperationResult(
                ok: false,
                state: .notConfigured,
                message: "Automatic update trust keys are not configured",
                availableVersion: nil
            )))
            return
        }
        checkHandler { [weak self] result in
            guard let self else { return }
            self.apply(result)
            reply(self.encoded(result))
        }
    }

    func installAvailable(withReply reply: @escaping (Data) -> Void) {
        guard currentCaller() != nil else {
            reply(encoded(UpdaterOperationResult(
                ok: false,
                state: .repairRequired,
                message: "Missing XPC caller audit context",
                availableVersion: nil
            )))
            return
        }
        guard let installHandler else {
            reply(encoded(UpdaterOperationResult(
                ok: false,
                state: .failed,
                message: "The updater transaction is not available in this build",
                availableVersion: nil
            )))
            return
        }
        installHandler { [weak self] result in
            guard let self else { return }
            self.apply(result)
            reply(self.encoded(result))
        }
    }

    func setAutomaticUpdates(_ enabled: Bool, withReply reply: @escaping (Data) -> Void) {
        guard let caller = currentCaller() else {
            reply(encoded(UpdaterOperationResult(
                ok: false,
                state: .repairRequired,
                message: "Missing XPC caller audit context",
                availableVersion: nil
            )))
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: paths.automaticPreferences,
                withIntermediateDirectories: true
            )
            try ensureRootOwnedDirectory(paths.automaticPreferences)
            let preference = UpdaterAutomaticPreference(
                schemaVersion: 1,
                automaticUpdatesEnabled: enabled
            )
            var data = try JSONEncoder().encode(preference)
            data.append(0x0A)
            let destination = paths.preference(for: caller.uid)
            let temporary = destination.appendingPathExtension("tmp-\(UUID().uuidString)")
            try data.write(to: temporary, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: temporary.path
            )
            guard rename(temporary.path, destination.path) == 0 else {
                try? FileManager.default.removeItem(at: temporary)
                throw CocoaError(.fileWriteUnknown)
            }
            reply(encoded(UpdaterOperationResult(
                ok: true,
                state: currentState(),
                message: enabled ? "Automatic updates enabled" : "Automatic updates disabled",
                availableVersion: nil
            )))
        } catch {
            reply(encoded(UpdaterOperationResult(
                ok: false,
                state: .failed,
                message: "Cannot save automatic update preference",
                availableVersion: nil
            )))
        }
    }

    func restartApp(withReply reply: @escaping (Data) -> Void) {
        guard let caller = currentCaller() else {
            reply(encoded(UpdaterOperationResult(
                ok: false,
                state: .repairRequired,
                message: "Missing XPC caller audit context",
                availableVersion: nil
            )))
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [
            "asuser", String(caller.uid),
            "/usr/bin/open", "/Applications/Covio.app",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            reply(encoded(UpdaterOperationResult(
                ok: ok,
                state: ok ? .idle : .failed,
                message: ok ? "Covio restart requested" : "Cannot restart Covio",
                availableVersion: nil
            )))
        } catch {
            reply(encoded(UpdaterOperationResult(
                ok: false,
                state: .failed,
                message: "Cannot restart Covio",
                availableVersion: nil
            )))
        }
    }

    func applyScheduledResult(_ result: UpdaterOperationResult) {
        apply(result)
    }

    func status(for uid: uid_t) -> UpdaterStatus {
        stateLock.lock()
        let snapshot = (state, lastCheckAt, availableVersion, message)
        stateLock.unlock()
        return UpdaterStatus(
            schemaVersion: 1,
            updaterProtocolVersion: UpdaterContract.protocolVersion,
            releaseId: releaseId,
            state: snapshot.0,
            automaticUpdatesEnabled: UpdaterPreferenceStore(
                paths: paths
            ).isAutomaticUpdateEnabled(for: uid),
            lastCheckAt: snapshot.1,
            availableVersion: snapshot.2,
            message: snapshot.3
        )
    }

    private func currentCaller() -> Caller? {
        guard let connection = NSXPCConnection.current() else {
            return nil
        }
        return Caller(
            uid: connection.effectiveUserIdentifier,
            processIdentifier: connection.processIdentifier,
            auditSessionIdentifier: connection.auditSessionIdentifier,
            groupIdentifier: connection.effectiveGroupIdentifier
        )
    }

    private func apply(_ result: UpdaterOperationResult) {
        stateLock.lock()
        state = result.state
        availableVersion = result.availableVersion
        message = result.message
        lastCheckAt = Self.timestamp()
        stateLock.unlock()
    }

    private func currentState() -> UpdaterEngineState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }

    private func allowsManualCheck(uid: uid_t) -> Bool {
        let now = Date()
        stateLock.lock()
        defer { stateLock.unlock() }
        if let previous = lastManualCheckByUid[uid],
           now.timeIntervalSince(previous) < 30
        {
            return false
        }
        lastManualCheckByUid[uid] = now
        return true
    }

    private func ensureRootOwnedDirectory(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
              (attributes[.groupOwnerAccountID] as? NSNumber)?.intValue == 0
        else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard permissions & 0o022 == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }


    private func encoded<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

final class CovioUpdaterListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: CovioUpdaterService

    init(service: CovioUpdaterService) {
        self.service = service
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(
            with: CovioUpdaterXPCProtocol.self
        )
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}

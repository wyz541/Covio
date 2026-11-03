import Darwin
import Foundation

@main
enum CovioUpdaterMain {
    static func main() {
        let arguments = CommandLine.arguments
        let environment = ProcessInfo.processInfo.environment
        let paths = UpdaterPaths(environment: environment)
        let releaseId = environment["COVIO_UPDATER_RELEASE_ID"] ?? ""
        guard UpdaterPaths.isReleaseId(releaseId) else {
            fputs("Missing or invalid COVIO_UPDATER_RELEASE_ID\n", stderr)
            exit(1)
        }

        let service = CovioUpdaterService(
            paths: paths,
            releaseId: releaseId,
            state: .notConfigured
        )
        if arguments.contains("--selftest") {
            do {
                let data = try JSONEncoder().encode(service.status(for: getuid()))
                print(String(decoding: data, as: UTF8.self))
                exit(0)
            } catch {
                fputs("Updater status encoding failed\n", stderr)
                exit(1)
            }
        }

        let listener = NSXPCListener(
            machServiceName: UpdaterContract.machServiceName
        )
        let delegate = CovioUpdaterListenerDelegate(service: service)
        listener.delegate = delegate
        listener.setConnectionCodeSigningRequirement(
            clientRequirement(paths: paths)
        )
        listener.activate()

        do {
            try writeHealth(paths: paths, releaseId: releaseId)
        } catch {
            fputs("Cannot write updater health file\n", stderr)
            exit(1)
        }
        RunLoop.current.run()
    }

    private static func clientRequirement(paths: UpdaterPaths) -> String {
        guard let value = try? String(
            contentsOf: paths.clientRequirement,
            encoding: .utf8
        ) else {
            return "identifier \"com.wyz.covio.never\""
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "identifier \"com.wyz.covio.never\"" : trimmed
    }

    private static func writeHealth(
        paths: UpdaterPaths,
        releaseId: String
    ) throws {
        try FileManager.default.createDirectory(
            at: paths.root,
            withIntermediateDirectories: true
        )
        let health = UpdaterHealth(
            schemaVersion: 1,
            releaseId: releaseId,
            processIdentifier: getpid(),
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(health)
        data.append(0x0A)
        try data.write(to: paths.health, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: paths.health.path
        )
        let descriptor = open(paths.health.path, O_RDONLY)
        if descriptor >= 0 {
            fsync(descriptor)
            close(descriptor)
        }
    }
}

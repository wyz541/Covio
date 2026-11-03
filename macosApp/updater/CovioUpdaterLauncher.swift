import Darwin
import Foundation

@main
enum CovioUpdaterLauncherMain {
    private static let rapidFailureThreshold = 3
    private static let rapidFailureWindow: TimeInterval = 30

    static func main() {
        exit(run())
    }

    private static func run() -> Int32 {
        let environment = ProcessInfo.processInfo.environment
        let paths = UpdaterPaths(environment: environment)
        if CommandLine.arguments.contains("--selftest") {
            return selftest() ? 0 : 1
        }

        let skipValidation = environment["COVIO_UPDATER_TEST_SKIP_VALIDATION"] == "1"
        let exitAfterHealthy =
            environment["COVIO_UPDATER_TEST_EXIT_AFTER_HEALTHY"] == "1"
        let healthTimeout = TimeInterval(
            Double(environment["COVIO_UPDATER_HEALTH_TIMEOUT_MS"] ?? "") ?? 10_000
        ) / 1_000
        var rapidFailures = 0

        while true {
            guard let releaseId = readCurrentRelease(paths: paths) else {
                fputs("CovioUpdaterLauncher has no valid engine pointer\n", stderr)
                return 1
            }
            let engine: URL
            do {
                engine = try paths.engine(for: releaseId)
                try validateEngine(
                    engine,
                    skipValidation: skipValidation
                )
            } catch {
                fputs("CovioUpdater engine validation failed: \(error)\n", stderr)
                if fallback(paths: paths, failedReleaseId: releaseId) {
                    rapidFailures = 0
                    continue
                }
                return 1
            }

            try? FileManager.default.removeItem(at: paths.health)
            let process = Process()
            process.executableURL = engine
            var childEnvironment = environment
            childEnvironment["COVIO_UPDATER_RELEASE_ID"] = releaseId
            childEnvironment["COVIO_UPDATER_ROOT"] = paths.root.path
            process.environment = childEnvironment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                fputs("CovioUpdater engine launch failed: \(error)\n", stderr)
                if fallback(paths: paths, failedReleaseId: releaseId) {
                    rapidFailures = 0
                    continue
                }
                return 1
            }

            let startedAt = Date()
            guard waitForHealthyEngine(
                paths: paths,
                releaseId: releaseId,
                process: process,
                timeout: healthTimeout
            ) else {
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
                fputs("CovioUpdater engine did not report health\n", stderr)
                if fallback(paths: paths, failedReleaseId: releaseId) {
                    rapidFailures = 0
                    continue
                }
                return 1
            }

            if exitAfterHealthy {
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
                return 0
            }

            while process.isRunning {
                Thread.sleep(forTimeInterval: 0.2)
            }
            process.waitUntilExit()
            let uptime = Date().timeIntervalSince(startedAt)
            if uptime < rapidFailureWindow {
                rapidFailures += 1
            } else {
                rapidFailures = 0
            }
            if rapidFailures >= rapidFailureThreshold {
                rapidFailures = 0
                if fallback(paths: paths, failedReleaseId: releaseId) {
                    continue
                }
                return 1
            }
        }
    }

    private static func selftest() -> Bool {
        let valid = "0.0.2.0-g" + String(repeating: "a", count: 40)
        let invalid = [
            "0.0.2.0",
            "0.0.2.10-g" + String(repeating: "a", count: 40),
            "0.0.2.0-g" + String(repeating: "A", count: 40),
            "../0.0.2.0-g" + String(repeating: "a", count: 40),
        ]
        guard UpdaterPaths.isReleaseId(valid),
              invalid.allSatisfy({ !UpdaterPaths.isReleaseId($0) })
        else {
            fputs("Launcher release ID validation failed\n", stderr)
            return false
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-updater-selftest-\(UUID().uuidString)")
        let paths = UpdaterPaths(root: root)
        do {
            let engine = try paths.engine(for: valid)
            guard engine.path.hasPrefix(paths.versions.path + "/") else {
                return false
            }
            try? FileManager.default.removeItem(at: root)
            return true
        } catch {
            return false
        }
    }

    private static func readCurrentRelease(paths: UpdaterPaths) -> String? {
        if let value = readPointer(paths.currentPointer) {
            return value
        }
        if let previous = readPointer(paths.previousPointer) {
            try? writePointer(paths.currentPointer, releaseId: previous)
            return previous
        }
        return nil
    }

    private static func readPointer(_ url: URL) -> String? {
        guard let value = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let releaseId = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdaterPaths.isReleaseId(releaseId) ? releaseId : nil
    }

    private static func writePointer(_ url: URL, releaseId: String) throws {
        guard UpdaterPaths.isReleaseId(releaseId) else {
            throw UpdaterPathError.invalidReleaseId
        }
        let temporary = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        let data = Data((releaseId + "\n").utf8)
        try data.write(to: temporary, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: temporary.path
        )
        let descriptor = open(temporary.path, O_RDONLY)
        if descriptor >= 0 {
            fsync(descriptor)
            close(descriptor)
        }
        guard rename(temporary.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw UpdaterPathError.invalidEnginePath
        }
    }

    private static func fallback(
        paths: UpdaterPaths,
        failedReleaseId: String
    ) -> Bool {
        guard let previous = readPointer(paths.previousPointer),
              previous != failedReleaseId
        else {
            return false
        }
        do {
            try writePointer(paths.currentPointer, releaseId: previous)
            fputs("CovioUpdater rolled back to \(previous)\n", stderr)
            return true
        } catch {
            fputs("CovioUpdater pointer rollback failed: \(error)\n", stderr)
            return false
        }
    }

    private static func validateEngine(
        _ url: URL,
        skipValidation: Bool
    ) throws {
        guard url.isFileURL else {
            throw UpdaterPathError.invalidEnginePath
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw UpdaterPathError.invalidEnginePath
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              FileManager.default.isExecutableFile(atPath: url.path)
        else {
            throw UpdaterPathError.untrustedEngine
        }
        guard !skipValidation else { return }
        guard (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
              (attributes[.groupOwnerAccountID] as? NSNumber)?.intValue == 0
        else {
            throw UpdaterPathError.untrustedEngine
        }
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard permissions & 0o022 == 0 else {
            throw UpdaterPathError.untrustedEngine
        }
        guard runTool(
            "/usr/bin/codesign",
            arguments: ["--verify", "--strict", url.path]
        ) else {
            throw UpdaterPathError.untrustedEngine
        }
        let description = runToolOutput(
            "/usr/bin/codesign",
            arguments: ["-d", "--verbose=2", url.path]
        )
        guard description.contains("Identifier=\(UpdaterContract.engineIdentifier)") else {
            throw UpdaterPathError.untrustedEngine
        }
    }

    private static func waitForHealthyEngine(
        paths: UpdaterPaths,
        releaseId: String,
        process: Process,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard process.isRunning else { return false }
            if let data = try? Data(contentsOf: paths.health),
               let health = try? JSONDecoder().decode(UpdaterHealth.self, from: data),
               health.isValidShape,
               health.releaseId == releaseId,
               health.processIdentifier == process.processIdentifier
            {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private static func runTool(_ executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func runToolOutput(_ executable: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }
}

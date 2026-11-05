import Darwin
import Foundation

@main
enum CovioUpdaterLauncherMain {
    private static let rapidFailureThreshold = 3

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
        let preflightTimeout = TimeInterval(
            Double(environment["COVIO_UPDATER_HEALTH_TIMEOUT_MS"] ?? "") ?? 10_000
        ) / 1_000
        let forwardedArguments = Array(CommandLine.arguments.dropFirst())

        while true {
            guard let releaseId = readCurrentRelease(paths: paths) else {
                fputs("CovioUpdaterLauncher has no valid engine pointer\n", stderr)
                return 1
            }
            let engine: URL
            do {
                engine = try paths.engine(for: releaseId)
                try validateEngine(engine, skipValidation: skipValidation)
            } catch {
                fputs("CovioUpdater engine validation failed: \(error)\n", stderr)
                if fallback(paths: paths, failedReleaseId: releaseId) {
                    continue
                }
                return 1
            }

            let attempts = UpdaterLaunchStateStore.recordAttempt(
                paths: paths,
                releaseId: releaseId
            )
            if attempts >= rapidFailureThreshold {
                UpdaterLaunchStateStore.clear(paths: paths)
                fputs("CovioUpdater engine failed \(attempts) rapid starts\n", stderr)
                if fallback(paths: paths, failedReleaseId: releaseId) {
                    continue
                }
                return 1
            }

            guard preflightEngine(
                engine,
                releaseId: releaseId,
                paths: paths,
                environment: environment,
                timeout: preflightTimeout
            ) else {
                UpdaterLaunchStateStore.clear(paths: paths)
                fputs("CovioUpdater engine preflight failed\n", stderr)
                if fallback(paths: paths, failedReleaseId: releaseId) {
                    continue
                }
                return 1
            }

            // launchd binds the Mach service to this job process. exec preserves
            // that process, so the versioned engine can own the XPC listener.
            setenv("COVIO_UPDATER_RELEASE_ID", releaseId, 1)
            setenv("COVIO_UPDATER_ROOT", paths.root.path, 1)
            let arguments = [engine.path] + forwardedArguments
            var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
            let result = engine.path.withCString { path in
                execv(path, &argv)
            }
            fputs("CovioUpdater engine exec failed: \(String(cString: strerror(errno)))\n", stderr)
            UpdaterLaunchStateStore.clear(paths: paths)
            if fallback(paths: paths, failedReleaseId: releaseId) {
                continue
            }
            return result == -1 ? 1 : 0
        }
    }

    private static func preflightEngine(
        _ engine: URL,
        releaseId: String,
        paths: UpdaterPaths,
        environment: [String: String],
        timeout: TimeInterval
    ) -> Bool {
        let process = Process()
        process.executableURL = engine
        process.arguments = ["--selftest"]
        var childEnvironment = environment
        childEnvironment["COVIO_UPDATER_RELEASE_ID"] = releaseId
        childEnvironment["COVIO_UPDATER_ROOT"] = paths.root.path
        process.environment = childEnvironment
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        do {
            try process.run()
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return false
        }
        process.waitUntilExit()
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = standardError.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let status = try? JSONDecoder().decode(UpdaterStatus.self, from: output)
        else {
            fputs("CovioUpdater preflight output: \(String(decoding: output, as: UTF8.self))\n", stderr)
            fputs("CovioUpdater preflight error: \(String(decoding: errorOutput, as: UTF8.self))\n", stderr)
            return false
        }
        return status.releaseId == releaseId
    }

    private static func selftest() -> Bool {
        let valid = "0.6.0-internal.23-g" + String(repeating: "a", count: 40)
        let invalid = [
            "0.6.0-internal.23",
            "0.6.0-internal.023-g" + String(repeating: "a", count: 40),
            "0.6.0-internal.23-g" + String(repeating: "A", count: 40),
            "../0.6.0-internal.23-g" + String(repeating: "a", count: 40),
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

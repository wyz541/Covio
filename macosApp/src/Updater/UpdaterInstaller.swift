import CryptoKit
import Darwin
import Foundation

enum UpdaterInstaller {
    static func installForAutomaticUpdateAsRoot(
        appBundle: URL = Bundle.main.bundleURL,
        paths: UpdaterPaths = UpdaterPaths(environment: ProcessInfo.processInfo.environment),
        testMode: Bool? = nil,
        skipLaunchctl: Bool? = nil,
        logger: (String) -> Void = { _ in }
    ) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let testMode = testMode ?? (environment["COVIO_UPDATER_TEST_MODE"] == "1")
        let skipLaunchctl = skipLaunchctl
            ?? (environment["COVIO_UPDATER_SKIP_LAUNCHD"] == "1")
        if !testMode && getuid() != 0 {
            logger("Automatic updater engine installation requires root")
            return false
        }
        guard let expectedLauncherSHA256 = environment["COVIO_UPDATER_EXPECTED_LAUNCHER_SHA256"],
              isLowercaseSHA256(expectedLauncherSHA256),
              let expectedEngineSHA256 = environment["COVIO_UPDATER_EXPECTED_SHA256"],
              isLowercaseSHA256(expectedEngineSHA256),
              let previousReleaseId = environment["COVIO_UPDATER_CURRENT_RELEASE_ID"],
              UpdaterPaths.isReleaseId(previousReleaseId)
        else {
            logger("Automatic updater engine identity is missing")
            return false
        }

        let sourceEngine = appBundle.appendingPathComponent("Contents/MacOS/CovioUpdater")
        let infoPath = appBundle.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoPath),
              let releaseId = info["CovioReleaseId"] as? String,
              UpdaterPaths.isReleaseId(releaseId),
              releaseId != previousReleaseId,
              FileManager.default.isExecutableFile(atPath: sourceEngine.path)
        else {
            logger("Bundled updater engine identity is missing")
            return false
        }

        do {
            let engineData = try Data(contentsOf: sourceEngine, options: [.mappedIfSafe])
            guard sha256Hex(engineData) == expectedEngineSHA256 else {
                throw UpdaterInstallError.untrustedEngineDigest
            }
            if !testMode {
                try verifyCodeSignature(
                    sourceEngine,
                    identifier: UpdaterContract.engineIdentifier
                )
            }
            let currentReleaseId = readReleaseId(paths.currentPointer)
            guard currentReleaseId == previousReleaseId else {
                throw UpdaterInstallError.installedIdentityMismatch
            }
            let installedLauncherSHA256 = sha256File(paths.launcher)
            guard installedLauncherSHA256 == expectedLauncherSHA256 else {
                throw UpdaterInstallError.installedIdentityMismatch
            }
            try verifyRootOwnedExecutable(paths.launcher, testMode: testMode)
            if !testMode {
                try verifyCodeSignature(
                    paths.launcher,
                    identifier: UpdaterContract.launcherIdentifier
                )
            }
            try verifyInstalledRecord(
                expectedReleaseId: previousReleaseId,
                launcherSHA256: installedLauncherSHA256,
                paths: paths
            )

            let versionDirectory = try paths.engine(for: releaseId)
                .deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: paths.versions,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: versionDirectory,
                withIntermediateDirectories: true
            )
            try copyFileAtomically(
                sourceEngine,
                to: versionDirectory.appendingPathComponent("CovioUpdater"),
                mode: 0o755,
                testMode: testMode
            )
            try writeText(previousReleaseId, to: paths.previousPointer, testMode: testMode)
            try writeText(releaseId, to: paths.currentPointer, testMode: testMode)
            try setDirectoryPermissions(paths.root, testMode: testMode)
            try setDirectoryPermissions(paths.versions, testMode: testMode)
            try setDirectoryPermissions(versionDirectory, testMode: testMode)

            if skipLaunchctl {
                return true
            }
            try restartUpdaterInPlace(paths: paths, releaseId: releaseId)
            return true
        } catch {
            logger("Automatic updater engine installation failed: \(error)")
            return false
        }
    }

    static func installForInstallTransactionAsRoot(
        appBundle: URL = Bundle.main.bundleURL,
        paths: UpdaterPaths = UpdaterPaths(environment: ProcessInfo.processInfo.environment),
        launchDaemonPath: URL? = nil,
        testMode: Bool? = nil,
        skipLaunchctl: Bool? = nil,
        clientRequirementOverride: String? = nil,
        updaterRequirementOverride: String? = nil,
        logger: (String) -> Void = { _ in }
    ) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let launchDaemonPath = launchDaemonPath ?? URL(
            fileURLWithPath: environment["COVIO_UPDATER_LAUNCHD_PATH"]
                ?? "/Library/LaunchDaemons/com.wyz.covio.updater.plist"
        )
        let testMode = testMode ?? (environment["COVIO_UPDATER_TEST_MODE"] == "1")
        let skipLaunchctl = skipLaunchctl
            ?? (environment["COVIO_UPDATER_SKIP_LAUNCHD"] == "1")
        if !testMode && getuid() != 0 {
            logger("Updater installation requires root")
            return false
        }

        let sourceEngine = appBundle.appendingPathComponent("Contents/MacOS/CovioUpdater")
        let sourceLauncher = appBundle.appendingPathComponent(
            "Contents/MacOS/CovioUpdaterLauncher"
        )
        let sourcePlist = appBundle.appendingPathComponent(
            "Contents/Library/LaunchDaemons/com.wyz.covio.updater.plist"
        )
        let infoPath = appBundle.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoPath),
              let releaseId = info["CovioReleaseId"] as? String,
              UpdaterPaths.isReleaseId(releaseId)
        else {
            logger("Bundled updater release identity is missing")
            return false
        }
        for source in [sourceEngine, sourceLauncher, sourcePlist] {
            guard FileManager.default.fileExists(atPath: source.path) else {
                logger("Bundled updater file is missing: \(source.lastPathComponent)")
                return false
            }
        }
        guard let clientRequirement = clientRequirementOverride
            ?? HelperSignature.currentRequirement(),
              let updaterRequirement = updaterRequirementOverride
            ?? HelperSignature.designatedRequirement(forExecutableAt: sourceEngine.path)
        else {
            logger("Cannot read updater code-signing requirements")
            return false
        }

        do {
            try validateLaunchDaemon(sourcePlist)
            if !testMode {
                try verifyCodeSignature(
                    sourceEngine,
                    identifier: UpdaterContract.engineIdentifier
                )
                try verifyCodeSignature(
                    sourceLauncher,
                    identifier: UpdaterContract.launcherIdentifier
                )
            }
            try FileManager.default.createDirectory(
                at: paths.binDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: paths.versions,
                withIntermediateDirectories: true
            )
            let installedEngine = try paths.engine(for: releaseId)
            try FileManager.default.createDirectory(
                at: installedEngine.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let previousReleaseId = readReleaseId(paths.currentPointer)
            if let previousReleaseId, previousReleaseId != releaseId {
                try writeText(previousReleaseId, to: paths.previousPointer, testMode: testMode)
            }
            try copyFileAtomically(sourceLauncher, to: paths.launcher, mode: 0o755, testMode: testMode)
            try copyFileAtomically(sourceEngine, to: installedEngine, mode: 0o755, testMode: testMode)
            try writeText(clientRequirement, to: paths.clientRequirement, testMode: testMode)
            try writeText(updaterRequirement, to: paths.updaterRequirement, testMode: testMode)
            try writeText(releaseId, to: paths.currentPointer, testMode: testMode)
            try copyFileAtomically(sourcePlist, to: launchDaemonPath, mode: 0o644, testMode: testMode)
            try setDirectoryPermissions(paths.root, testMode: testMode)
            try setDirectoryPermissions(paths.launcher.deletingLastPathComponent(), testMode: testMode)
            try setDirectoryPermissions(paths.versions, testMode: testMode)
            try setDirectoryPermissions(installedEngine.deletingLastPathComponent(), testMode: testMode)

            if skipLaunchctl {
                return true
            }
            try restartUpdater(
                paths: paths,
                launchDaemonPath: launchDaemonPath,
                releaseId: releaseId
            )
            return true
        } catch {
            logger("Updater installation failed: \(error)")
            return false
        }
    }

    private static func validateLaunchDaemon(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
              plist["Label"] as? String == UpdaterContract.launchDaemonLabel,
              plist["RunAtLoad"] as? Bool == true,
              plist["KeepAlive"] as? Bool == true,
              let arguments = plist["ProgramArguments"] as? [String],
              arguments == [
                  "/Library/Application Support/Covio/Updater/bin/CovioUpdaterLauncher"
              ],
              let services = plist["MachServices"] as? [String: Bool],
              services[UpdaterContract.machServiceName] == true
        else {
            throw UpdaterInstallError.invalidDaemonPlist
        }
    }

    private static func verifyCodeSignature(
        _ url: URL,
        identifier: String
    ) throws {
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--strict", url.path]
        verify.standardOutput = FileHandle.nullDevice
        verify.standardError = FileHandle.nullDevice
        try verify.run()
        verify.waitUntilExit()
        guard verify.terminationStatus == 0 else {
            throw UpdaterInstallError.untrustedSignature
        }

        let describe = Process()
        describe.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        describe.arguments = ["-d", "--verbose=2", url.path]
        let pipe = Pipe()
        describe.standardOutput = pipe
        describe.standardError = pipe
        try describe.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        describe.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard describe.terminationStatus == 0,
              output.contains("Identifier=\(identifier)")
        else {
            throw UpdaterInstallError.untrustedSignature
        }
    }

    private static func restartUpdaterInPlace(
        paths: UpdaterPaths,
        releaseId: String
    ) throws {
        guard runLaunchctl(["kickstart", "-k", "system/\(UpdaterContract.launchDaemonLabel)"]) else {
            throw UpdaterInstallError.launchctlFailed
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let data = try? Data(contentsOf: paths.health),
               let health = try? JSONDecoder().decode(UpdaterHealth.self, from: data),
               health.isValidShape,
               health.releaseId == releaseId
            {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw UpdaterInstallError.healthTimeout
    }

    private static func verifyInstalledRecord(
        expectedReleaseId: String,
        launcherSHA256: String,
        paths: UpdaterPaths
    ) throws {
        let recordURL = paths.root.deletingLastPathComponent()
            .appendingPathComponent("installed-release.json")
        let data = try Data(contentsOf: recordURL)
        guard let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (record["schemaVersion"] as? NSNumber)?.intValue == 2,
              record["releaseId"] as? String == expectedReleaseId,
              record["updaterReleaseId"] as? String == expectedReleaseId,
              record["updaterLauncherSHA256"] as? String == launcherSHA256
        else {
            throw UpdaterInstallError.installedIdentityMismatch
        }
    }

    private static func verifyRootOwnedExecutable(
        _ url: URL,
        testMode: Bool
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard (attributes[.type] as? FileAttributeType) == .typeRegular,
              FileManager.default.isExecutableFile(atPath: url.path),
              mode & 0o022 == 0
        else {
            throw UpdaterInstallError.installedIdentityMismatch
        }
        if !testMode {
            guard (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
                  (attributes[.groupOwnerAccountID] as? NSNumber)?.intValue == 0
            else {
                throw UpdaterInstallError.installedIdentityMismatch
            }
        }
    }

    private static func copyFileAtomically(
        _ source: URL,
        to destination: URL,
        mode: Int,
        testMode: Bool
    ) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = destination.appendingPathExtension("tmp-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: temporary)
        try FileManager.default.setAttributes(
            [.posixPermissions: mode],
            ofItemAtPath: temporary.path
        )
        if !testMode {
            setRootOwnership(temporary, testMode: false)
        }
        let descriptor = open(temporary.path, O_RDONLY)
        if descriptor >= 0 {
            fsync(descriptor)
            close(descriptor)
        }
        guard rename(temporary.path, destination.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw UpdaterInstallError.installedIdentityMismatch
        }
    }

    private static func restartUpdater(
        paths: UpdaterPaths,
        launchDaemonPath: URL,
        releaseId: String
    ) throws {
        _ = runLaunchctl(["bootout", "system/\(UpdaterContract.launchDaemonLabel)"])
        guard runLaunchctl(["bootstrap", "system", launchDaemonPath.path]) else {
            throw UpdaterInstallError.launchctlFailed
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let data = try? Data(contentsOf: paths.health),
               let health = try? JSONDecoder().decode(UpdaterHealth.self, from: data),
               health.isValidShape,
               health.releaseId == releaseId
            {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw UpdaterInstallError.healthTimeout
    }

    private static func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
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

    private static func sha256File(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return ""
        }
        return sha256Hex(data)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
        }
    }

    private static func readReleaseId(_ url: URL) -> String? {
        guard let value = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let releaseId = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdaterPaths.isReleaseId(releaseId) ? releaseId : nil
    }

    private static func writeText(
        _ value: String,
        to url: URL,
        testMode: Bool
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var data = Data((value + "\n").utf8)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: url.path
        )
        setRootOwnership(url, testMode: testMode)
    }

    private static func setDirectoryPermissions(_ url: URL, testMode: Bool) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        if !testMode {
            setRootOwnership(url, testMode: false)
        }
    }

    private static func setRootOwnership(_ url: URL, testMode: Bool) {
        guard !testMode else { return }
        try? FileManager.default.setAttributes(
            [
                .ownerAccountID: 0,
                .groupOwnerAccountID: 0,
            ],
            ofItemAtPath: url.path
        )
    }
}

enum UpdaterInstallError: Error, LocalizedError {
    case invalidDaemonPlist
    case untrustedSignature
    case launchctlFailed
    case healthTimeout
    case untrustedEngineDigest
    case installedIdentityMismatch

    var errorDescription: String? {
        switch self {
        case .invalidDaemonPlist: "Invalid updater LaunchDaemon plist"
        case .untrustedSignature: "Untrusted updater code signature"
        case .launchctlFailed: "Cannot start CovioUpdater"
        case .healthTimeout: "CovioUpdater did not report health"
        case .untrustedEngineDigest: "Updater engine digest is invalid"
        case .installedIdentityMismatch: "Installed updater identity is invalid"
        }
    }
}

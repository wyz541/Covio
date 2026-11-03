import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import Covio

final class UpdaterInstallerTests: XCTestCase {
    private let releaseId = "0.0.1.9-g" + String(repeating: "a", count: 40)

    func testInstallWritesRootLayoutAndPointers() throws {
        let root = try makeAppBundle(releaseId: releaseId)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let updaterRoot = root.deletingLastPathComponent()
            .appendingPathComponent("runtime/Updater")
        let plist = root.deletingLastPathComponent()
            .appendingPathComponent("Library/LaunchDaemons/com.wyz.covio.updater.plist")
        let installed = UpdaterInstaller.installForInstallTransactionAsRoot(
            appBundle: root,
            paths: UpdaterPaths(root: updaterRoot),
            launchDaemonPath: plist,
            testMode: true,
            skipLaunchctl: true,
            clientRequirementOverride: "identifier \"com.wyz.covio\"",
            updaterRequirementOverride: "identifier \"com.wyz.covio.updater\""
        )
        XCTAssertTrue(installed)
        XCTAssertEqual(
            try String(contentsOf: updaterRoot.appendingPathComponent("current"))
                .trimmingCharacters(in: .whitespacesAndNewlines),
            releaseId
        )
        XCTAssertTrue(
            FileManager.default.isExecutableFile(
                atPath: updaterRoot
                    .appendingPathComponent("versions/\(releaseId)/CovioUpdater").path
            )
        )
        XCTAssertTrue(
            FileManager.default.isExecutableFile(
                atPath: updaterRoot.appendingPathComponent("bin/CovioUpdaterLauncher").path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: plist.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: updaterRoot.appendingPathComponent("updater-client-requirement").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: updaterRoot.appendingPathComponent("updater-requirement").path
            )
        )
    }

    func testAutomaticEngineInstallKeepsImmutableLauncherAndDaemon() throws {
        let oldReleaseId = "0.0.1.9-g" + String(repeating: "a", count: 40)
        let newReleaseId = "0.0.2.0-g" + String(repeating: "b", count: 40)
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-updater-auto-installer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let oldApp = try makeAppBundle(releaseId: oldReleaseId, base: base, suffix: "old")
        let paths = UpdaterPaths(root: base.appendingPathComponent("runtime/Updater"))
        let plist = base.appendingPathComponent("Library/LaunchDaemons/com.wyz.covio.updater.plist")
        XCTAssertTrue(
            UpdaterInstaller.installForInstallTransactionAsRoot(
                appBundle: oldApp,
                paths: paths,
                launchDaemonPath: plist,
                testMode: true,
                skipLaunchctl: true,
                clientRequirementOverride: "identifier \"com.wyz.covio\"",
                updaterRequirementOverride: "identifier \"com.wyz.covio.updater\""
            )
        )
        let launcherBefore = try Data(contentsOf: paths.launcher)
        let plistBefore = try Data(contentsOf: plist)
        try writeInstalledRecord(
            releaseId: oldReleaseId,
            updaterSHA256: sha256(paths.engine(for: oldReleaseId)),
            launcherSHA256: sha256(paths.launcher),
            root: base.appendingPathComponent("runtime")
        )

        let newApp = try makeAppBundle(
            releaseId: newReleaseId,
            base: base,
            suffix: "new"
        )
        let newEngine = newApp.appendingPathComponent("Contents/MacOS/CovioUpdater")
        try Data("new-updater-engine".utf8).write(to: newEngine)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: newEngine.path
        )
        let newLauncher = newApp.appendingPathComponent("Contents/MacOS/CovioUpdaterLauncher")
        try Data("new-launcher-must-not-install".utf8).write(to: newLauncher)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: newLauncher.path
        )

        let expectedLauncherSHA256 = try sha256(paths.launcher)
        let expectedEngineSHA256 = try sha256(newEngine)
        setenv("COVIO_UPDATER_EXPECTED_LAUNCHER_SHA256", expectedLauncherSHA256, 1)
        setenv("COVIO_UPDATER_EXPECTED_SHA256", expectedEngineSHA256, 1)
        setenv("COVIO_UPDATER_CURRENT_RELEASE_ID", oldReleaseId, 1)
        setenv("COVIO_UPDATER_TEST_MODE", "1", 1)
        defer {
            unsetenv("COVIO_UPDATER_EXPECTED_LAUNCHER_SHA256")
            unsetenv("COVIO_UPDATER_EXPECTED_SHA256")
            unsetenv("COVIO_UPDATER_CURRENT_RELEASE_ID")
            unsetenv("COVIO_UPDATER_TEST_MODE")
        }

        XCTAssertTrue(
            UpdaterInstaller.installForAutomaticUpdateAsRoot(
                appBundle: newApp,
                paths: paths,
                testMode: true,
                skipLaunchctl: true
            )
        )
        XCTAssertEqual(try Data(contentsOf: paths.launcher), launcherBefore)
        XCTAssertEqual(try Data(contentsOf: plist), plistBefore)
        XCTAssertEqual(
            try String(contentsOf: paths.currentPointer).trimmingCharacters(in: .whitespacesAndNewlines),
            newReleaseId
        )
        XCTAssertEqual(
            try String(contentsOf: paths.previousPointer).trimmingCharacters(in: .whitespacesAndNewlines),
            oldReleaseId
        )
        XCTAssertEqual(
            try Data(contentsOf: paths.engine(for: newReleaseId)),
            Data("new-updater-engine".utf8)
        )
    }

    func testInvalidReleaseIdentityIsRejected() throws {
        let root = try makeAppBundle(releaseId: "../invalid")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let installed = UpdaterInstaller.installForInstallTransactionAsRoot(
            appBundle: root,
            paths: UpdaterPaths(root: root.deletingLastPathComponent()),
            launchDaemonPath: root.deletingLastPathComponent()
                .appendingPathComponent("updater.plist"),
            testMode: true,
            skipLaunchctl: true,
            clientRequirementOverride: "client",
            updaterRequirementOverride: "updater"
        )
        XCTAssertFalse(installed)
    }

    private func makeAppBundle(
        releaseId: String,
        base: URL? = nil,
        suffix: String = UUID().uuidString
    ) throws -> URL {
        let root = (base ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("covio-updater-installer-\(suffix)")
        let app = root.appendingPathComponent("Covio.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        let launchDaemons = app.appendingPathComponent("Contents/Library/LaunchDaemons")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: launchDaemons,
            withIntermediateDirectories: true
        )
        for name in ["CovioUpdater", "CovioUpdaterLauncher"] {
            let path = macOS.appendingPathComponent(name)
            try Data("binary".utf8).write(to: path)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: path.path
            )
        }
        let daemon: [String: Any] = [
            "Label": "com.wyz.covio.updater",
            "ProgramArguments": [
                "/Library/Application Support/Covio/Updater/bin/CovioUpdaterLauncher"
            ],
            "MachServices": ["com.wyz.covio.updater.xpc": true],
            "RunAtLoad": true,
            "KeepAlive": true,
        ]
        let daemonData = try PropertyListSerialization.data(
            fromPropertyList: daemon,
            format: .xml,
            options: 0
        )
        try daemonData.write(
            to: launchDaemons.appendingPathComponent("com.wyz.covio.updater.plist")
        )
        let info: [String: Any] = ["CovioReleaseId": releaseId]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    private func writeInstalledRecord(
        releaseId: String,
        updaterSHA256: String,
        launcherSHA256: String,
        root: URL
    ) throws {
        let record: [String: Any] = [
            "schemaVersion": 2,
            "releaseId": releaseId,
            "updaterReleaseId": releaseId,
            "updaterSHA256": updaterSHA256,
            "updaterLauncherSHA256": launcherSHA256,
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try data.write(
            to: root.appendingPathComponent("installed-release.json"),
            options: .atomic
        )
    }

    private func sha256(_ path: URL) throws -> String {
        let data = try Data(contentsOf: path)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

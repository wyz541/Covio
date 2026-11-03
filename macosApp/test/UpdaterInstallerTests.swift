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

    private func makeAppBundle(releaseId: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-updater-installer-\(UUID().uuidString)")
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
}

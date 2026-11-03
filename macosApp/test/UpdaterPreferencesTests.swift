import Foundation
import XCTest
@testable import Covio

final class UpdaterPreferencesTests: XCTestCase {
    func testAutomaticUpdatesDefaultToEnabled() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-updater-preferences-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = UpdaterPreferenceStore(paths: UpdaterPaths(root: root))
        XCTAssertTrue(store.isAutomaticUpdateEnabled(for: 501))
    }

    func testAutomaticUpdatesReadTheCallerPreference() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-updater-preferences-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = UpdaterPaths(root: root)
        try FileManager.default.createDirectory(
            at: paths.automaticPreferences,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(
            UpdaterAutomaticPreference(
                schemaVersion: 1,
                automaticUpdatesEnabled: false
            )
        )
        try data.write(to: paths.preference(for: 501))
        let store = UpdaterPreferenceStore(paths: paths)
        XCTAssertFalse(store.isAutomaticUpdateEnabled(for: 501))
        XCTAssertTrue(store.isAutomaticUpdateEnabled(for: 502))
    }

    func testSchedulerAcceptsAnExplicitConsoleUIDForTests() {
        XCTAssertEqual(
            UpdaterScheduler.consoleUID(
                environment: ["COVIO_UPDATER_CONSOLE_UID": "501"]
            ),
            501
        )
        XCTAssertNil(
            UpdaterScheduler.consoleUID(
                environment: ["COVIO_UPDATER_CONSOLE_UID": "0"]
            )
        )
    }
}

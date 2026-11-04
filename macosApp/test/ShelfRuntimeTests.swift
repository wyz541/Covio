import Foundation
import XCTest
@testable import Covio

@MainActor
final class ShelfRuntimeTests: XCTestCase {
    private var directory: URL!
    private var screenshotDirectory: URL!
    private var store: ShelfStoreClient!
    private var preferences: FakeLegacyScreenshotPreferences!
    private var watcherFactory: FakeScreenshotWatcherFactory!
    private var runtime: ShelfRuntime!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-screenshot-library-\(UUID().uuidString)", isDirectory: true)
        screenshotDirectory = directory.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        store = ShelfStoreClient(path: directory.appendingPathComponent("shelf.json").path)
        preferences = FakeLegacyScreenshotPreferences()
        watcherFactory = FakeScreenshotWatcherFactory()
        let screenshotDirectory = screenshotDirectory!
        runtime = ShelfRuntime(
            store: store,
            preferences: preferences,
            environment: ScreenshotLibraryEnvironment(
                screenshotDirectory: { screenshotDirectory },
                now: { 100 }
            ),
            watcherFactory: watcherFactory.factory
        )
    }

    override func tearDownWithError() throws {
        runtime.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    func testAnExistingScreenshotIndexLoadsBeforeStart() throws {
        let screenshot = screenshotDirectory.appendingPathComponent("persisted.png")
        try Data("png".utf8).write(to: screenshot)
        store.save(
            ShelfStoreState.companion.defaults().doCopy(
                items: [ShelfItem(path: screenshot.path, addedAtEpochSeconds: 42)],
                revealed: true,
                preferenceSnapshot: nil
            )
        )

        let screenshotDirectory = screenshotDirectory!
        let loaded = ShelfRuntime(
            store: store,
            preferences: preferences,
            environment: ScreenshotLibraryEnvironment(
                screenshotDirectory: { screenshotDirectory },
                now: { 100 }
            ),
            watcherFactory: watcherFactory.factory
        )

        XCTAssertEqual(loaded.items.map(\.path), [screenshot.path])
    }

    func testStartWatchesTheConfiguredScreenshotDirectory() {
        runtime.start()

        XCTAssertEqual(watcherFactory.directories, [screenshotDirectory])
        XCTAssertEqual(watcherFactory.requireAttributes, [true])
        XCTAssertEqual(watcherFactory.watchers.first?.startCount, 1)
    }

    func testLegacyTakeoverSnapshotIsRestoredAndCleared() {
        let snapshot = ScreenshotInboxSnapshot(
            location: "/tmp/original",
            locationScreenshot: "/tmp/original-shot",
            showThumbnail: true
        )
        store.save(
            ShelfStoreState.companion.defaults().doCopy(
                items: [],
                revealed: true,
                preferenceSnapshot: snapshot
            )
        )

        runtime.start()

        XCTAssertEqual(preferences.restoredSnapshots, [snapshot])
        XCTAssertNil(store.load().preferenceSnapshot)
    }

    func testNewScreenshotIsPersistedWithoutChangingSystemPreferences() throws {
        runtime.start()
        let screenshot = screenshotDirectory.appendingPathComponent("shot.png")
        try Data("png".utf8).write(to: screenshot)

        watcherFactory.emitNew(screenshot)

        XCTAssertEqual(runtime.items.map(\.path), [screenshot.path])
        XCTAssertEqual(store.load().items.map(\.path), [screenshot.path])
        XCTAssertTrue(preferences.restoredSnapshots.isEmpty)
    }

    func testRemovingAScreenshotKeepsTheFileOnDisk() throws {
        runtime.start()
        let screenshot = screenshotDirectory.appendingPathComponent("shot.png")
        try Data("png".utf8).write(to: screenshot)
        watcherFactory.emitNew(screenshot)

        runtime.removeItem(ShelfItem(path: screenshot.path, addedAtEpochSeconds: 100))

        XCTAssertTrue(runtime.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.path))
    }
}

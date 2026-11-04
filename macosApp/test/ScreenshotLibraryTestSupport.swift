import Foundation
@testable import Covio

final class FakeLegacyScreenshotPreferences: LegacyScreenshotPreferenceRestoring, @unchecked Sendable {
    var restoreResult = true
    private let lock = NSLock()
    private var snapshots: [ScreenshotInboxSnapshot] = []

    var restoredSnapshots: [ScreenshotInboxSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return snapshots
    }

    func restore(snapshot: ScreenshotInboxSnapshot) -> Bool {
        lock.lock()
        snapshots.append(snapshot)
        lock.unlock()
        return restoreResult
    }
}

@MainActor
final class FakeScreenshotWatching: ScreenshotWatching {
    private(set) var startCount = 0
    private(set) var closeCount = 0

    func start() {
        startCount += 1
    }

    func close() {
        closeCount += 1
    }
}

@MainActor
final class FakeScreenshotWatcherFactory {
    private(set) var directories: [URL] = []
    private(set) var dedicatedDirectories: [URL] = []
    private(set) var requireAttributes: [Bool] = []
    private(set) var watchers: [FakeScreenshotWatching] = []
    var onNew: ((URL) -> Void)?
    var onChange: (() -> Void)?

    lazy var factory: ScreenshotWatcherFactory = {
        { [weak self] directory, dedicated, requireAttribute, onNew, onChange in
            guard let self else {
                return FakeScreenshotWatching()
            }
            directories.append(directory)
            dedicatedDirectories.append(dedicated)
            requireAttributes.append(requireAttribute)
            self.onNew = onNew
            self.onChange = onChange
            let watcher = FakeScreenshotWatching()
            watchers.append(watcher)
            return watcher
        }
    }()

    func emitNew(_ url: URL) {
        onNew?(url)
    }
}

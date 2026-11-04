import AppKit
import XCTest
@testable import Covio

/// 截图模块的平台叶子：目录监视、系统偏好和剪贴板。
///
/// 这四个各自都能单独跑，所以分开测。系统偏好那组不跑真的 `defaults`，
/// 命令走注入的假执行器，断言只看命令拼得对不对。
@MainActor
final class ShelfPlatformTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-platform-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    private func makeFile(_ name: String, in folder: URL? = nil) throws -> URL {
        let target = (folder ?? directory).appendingPathComponent(name)
        try Data("x".utf8).write(to: target)
        return target
    }

    // MARK: - 目录监视

    /// 只看专用目录里的图片。别的后缀不收。
    func testTheDedicatedDirectoryAcceptsImagesOnly() throws {
        let dedicated = directory.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dedicated, withIntermediateDirectories: true)
        let watcher = ScreenshotWatcher(
            directory: dedicated,
            dedicatedDirectory: dedicated,
            requireScreenCaptureAttribute: false,
            debounceSeconds: 0,
            attributeReader: { _ in false },
            onNew: { _ in }
        )
        defer { watcher.close() }

        XCTAssertTrue(watcher.isCandidate(try makeFile("a.png", in: dedicated)))
        XCTAssertTrue(watcher.isCandidate(try makeFile("b.HEIC", in: dedicated)))
        XCTAssertFalse(watcher.isCandidate(try makeFile("c.txt", in: dedicated)))
        XCTAssertFalse(watcher.isCandidate(try makeFile("d.pdf", in: dedicated)))
    }

    /// 桌面上的文件要带截图属性才收。普通图片不收。
    func testTheDesktopRequiresTheScreenCaptureAttribute() throws {
        let dedicated = directory.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dedicated, withIntermediateDirectories: true)
        let desktop = directory.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)

        let shot = try makeFile("shot.png", in: desktop)
        let photo = try makeFile("photo.png", in: desktop)
        let watcher = ScreenshotWatcher(
            directory: desktop,
            dedicatedDirectory: dedicated,
            requireScreenCaptureAttribute: true,
            debounceSeconds: 0,
            attributeReader: { $0 == shot.path },
            onNew: { _ in }
        )
        defer { watcher.close() }

        XCTAssertTrue(watcher.isCandidate(shot))
        XCTAssertFalse(watcher.isCandidate(photo))
    }

    /// 扫描只报新出现的文件，同一个文件不报第二次。
    func testScanReportsEachFileOnce() throws {
        let dedicated = directory.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dedicated, withIntermediateDirectories: true)
        var appeared: [String] = []
        let watcher = ScreenshotWatcher(
            directory: dedicated,
            dedicatedDirectory: dedicated,
            requireScreenCaptureAttribute: false,
            debounceSeconds: 0,
            attributeReader: { _ in false },
            onNew: { url in appeared.append(url.lastPathComponent) }
        )
        defer { watcher.close() }

        try makeFile("a.png", in: dedicated)

        watcher.scan()
        watcher.scan()
        let done = expectation(description: "等回调送到主队列")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(appeared, ["a.png"])

        // 再来一个，只报新的那个。
        try makeFile("b.png", in: dedicated)
        watcher.scan()
        let second = expectation(description: "等第二次回调")
        DispatchQueue.main.async { second.fulfill() }
        wait(for: [second], timeout: 1)
        XCTAssertEqual(appeared, ["a.png", "b.png"])
    }

    func testScanRetriesUntilTheScreenshotAttributeExists() throws {
        let dedicated = directory.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dedicated, withIntermediateDirectories: true)
        var hasAttribute = false
        var appeared: [String] = []
        let watcher = ScreenshotWatcher(
            directory: dedicated,
            dedicatedDirectory: directory.appendingPathComponent("Other", isDirectory: true),
            requireScreenCaptureAttribute: true,
            debounceSeconds: 0,
            attributeReader: { _ in hasAttribute },
            onNew: { url in appeared.append(url.lastPathComponent) }
        )
        defer { watcher.close() }

        try makeFile("pending.png", in: dedicated)
        watcher.scan()
        hasAttribute = true
        watcher.scan()
        let callback = expectation(description: "等属性写入后的回调")
        DispatchQueue.main.async { callback.fulfill() }
        wait(for: [callback], timeout: 1)

        XCTAssertEqual(appeared, ["pending.png"])
    }

    func testScanReportsARecreatedFile() throws {
        let dedicated = directory.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dedicated, withIntermediateDirectories: true)
        var appeared: [String] = []
        let watcher = ScreenshotWatcher(
            directory: dedicated,
            dedicatedDirectory: dedicated,
            requireScreenCaptureAttribute: false,
            debounceSeconds: 0,
            attributeReader: { _ in false },
            onNew: { url in appeared.append(url.lastPathComponent) }
        )
        defer { watcher.close() }

        let file = try makeFile("reused.png", in: dedicated)
        watcher.scan()
        try FileManager.default.removeItem(at: file)
        watcher.scan()
        try Data("x".utf8).write(to: file)
        watcher.scan()
        let callback = expectation(description: "等重建文件的回调")
        DispatchQueue.main.async { callback.fulfill() }
        wait(for: [callback], timeout: 1)

        XCTAssertEqual(appeared, ["reused.png", "reused.png"])
    }

    /// 目录不存在时自己建一个。
    /// 目录不存在时自己建一个。
    ///
    /// 建目录在监视器自己的队列上跑（见 `start()`），所以要等它落地。
    func testStartCreatesAMissingDirectory() throws {
        let missing = directory.appendingPathComponent("NotThere", isDirectory: true)
        let watcher = ScreenshotWatcher(
            directory: missing,
            dedicatedDirectory: missing,
            requireScreenCaptureAttribute: false,
            debounceSeconds: 0,
            attributeReader: { _ in false },
            onNew: { _ in }
        )
        defer { watcher.close() }
        watcher.start()

        var isDirectory: ObjCBool = false
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: missing.path, isDirectory: &isDirectory),
              Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: missing.path, isDirectory: &isDirectory)
        )
        XCTAssertTrue(isDirectory.boolValue)
    }

    /// 读不到目录时扫描不崩，也不报东西。
    func testScanToleratesAMissingDirectory() {
        let missing = directory.appendingPathComponent("Gone", isDirectory: true)
        let watcher = ScreenshotWatcher(
            directory: missing,
            dedicatedDirectory: missing,
            requireScreenCaptureAttribute: false,
            debounceSeconds: 0,
            attributeReader: { _ in false },
            onNew: { _ in XCTFail("目录不存在时不该有回调") }
        )
        defer { watcher.close() }
        watcher.scan()
    }

    /// 目录变动通知要送到主队列。
    ///
    /// 事件处理器跑在监视器自己的队列上。直接从那儿回调，调用方就是在
    /// 主 actor 之外碰 SwiftUI 状态，会撞运行时的隔离断言。
    ///
    /// **要一直写文件，写到回调到达为止。** 事件源是在监视器自己的队列上
    /// 建的（见 `start()`），建好那一刻已经存在的文件会被记成「旧文件」。
    /// 固定写几个的话，机器一忙就会全部落在建好之前，回调永远不来。
    func testChangeCallbackArrivesOnTheMainThread() throws {
        let dedicated = directory.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dedicated, withIntermediateDirectories: true)

        let changed = expectation(description: "目录变动回调")
        // 每写一个文件都会来一次通知，多于一次是正常的。
        changed.assertForOverFulfill = false
        let arrived = Flag()
        let watcher = ScreenshotWatcher(
            directory: dedicated,
            dedicatedDirectory: dedicated,
            requireScreenCaptureAttribute: false,
            debounceSeconds: 0,
            attributeReader: { _ in false },
            onNew: { _ in },
            onChange: {
                XCTAssertTrue(Thread.isMainThread, "目录变动回调要在主线程")
                arrived.raise()
                changed.fulfill()
            }
        )
        defer { watcher.close() }
        watcher.start()

        let target = dedicated
        DispatchQueue(label: "covio-test-writer").async {
            let deadline = Date().addingTimeInterval(30)
            var index = 0
            while !arrived.isRaised, Date() < deadline {
                try? Data("x".utf8).write(to: target.appendingPathComponent("later-\(index).png"))
                index += 1
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        wait(for: [changed], timeout: 30)
    }

    // MARK: - 剪贴板

    /// 存下剪贴板原文。存成「类型 → 数据」，恢复时重建条目。
    ///
    /// **不能直接存 `NSPasteboardItem`。** 条目已经属于某个剪贴板，
    /// 再把同一个对象写回剪贴板会抛
    /// 「already associated with another pasteboard」。
    private func snapshotPasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
    }

    /// 按快照恢复剪贴板，别影响用户自己的剪贴板。
    private func restorePasteboard(_ snapshot: [[NSPasteboard.PasteboardType: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        pasteboard.writeObjects(snapshot.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        })
    }

    /// 复制要把文件 URL 和图片两个类型一起写进去。
    ///
    /// 分两次写会互相清空，所以断言两个类型都在。
    /// `writeObjects` 给每个对象建一个粘贴板条目，所以这里是两条。
    func testCopyWritesBothTheFileAndTheImage() throws {
        let url = try makePng("clip.png")

        let saved = snapshotPasteboard()
        XCTAssertTrue(ShelfClipboard.copy(url))
        let items = NSPasteboard.general.pasteboardItems ?? []
        XCTAssertEqual(items.count, 2)

        let allTypes = Set(items.flatMap { $0.types.map(\.rawValue) })
        XCTAssertTrue(allTypes.contains(NSPasteboard.PasteboardType.fileURL.rawValue), "缺文件 URL")
        // `NSImage` 写进去的是 TIFF，新版系统可能同时给 PNG。两个之一即可。
        let imageTypes: Set<String> = [
            NSPasteboard.PasteboardType.tiff.rawValue,
            NSPasteboard.PasteboardType.png.rawValue,
        ]
        XCTAssertFalse(allTypes.isDisjoint(with: imageTypes), "缺图片")

        restorePasteboard(saved)
    }

    /// 写一张 4 × 4 的真 PNG，用来测图片类型。
    private func makePng(_ name: String) throws -> URL {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        let png = try XCTUnwrap(bitmap?.representation(using: .png, properties: [:]))
        let url = directory.appendingPathComponent(name)
        try png.write(to: url)
        return url
    }

    /// 读不出的文件也要能复制，至少文件 URL 那一条要在。
    func testCopyStillWritesTheFileURLWhenTheImageCannotBeRead() throws {
        let url = try makeFile("not-an-image.png")
        let saved = snapshotPasteboard()
        XCTAssertTrue(ShelfClipboard.copy(url))
        let items = NSPasteboard.general.pasteboardItems ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(Set(items[0].types.map(\.rawValue)),
                       [NSPasteboard.PasteboardType.fileURL.rawValue])

        restorePasteboard(saved)
    }

    // MARK: - 系统截图偏好

    /// 读的时候要保留「键不存在」与「值是假」的区别。
    func testReadingKeepsTheMissingKeyDistinct() {
        let recorder = CommandRecorder()
        recorder.outputs = [
            "location": "/Users/someone/Desktop",
            "show-thumbnail": "0",
        ]
        let store = MacScreenshotPreferenceStore(runner: recorder.run)

        let snapshot = store.read()
        XCTAssertEqual(snapshot.location, "/Users/someone/Desktop")
        XCTAssertNil(snapshot.locationScreenshot, "没读到的键要留空，不能编一个值")
        XCTAssertEqual(snapshot.showThumbnail?.boolValue, false)
    }

    /// 布尔键的字面量三种写法都认。
    func testReadingBooleansAcceptsCommonSpellings() {
        for value in ["1", "true", "YES"] {
            let recorder = CommandRecorder()
            recorder.outputs = ["show-thumbnail": value]
            let store = MacScreenshotPreferenceStore(runner: recorder.run)
            XCTAssertEqual(store.read().showThumbnail?.boolValue, true, "\(value) 应当读成真")
        }
        // 认不出来时留空，不猜。
        let recorder = CommandRecorder()
        recorder.outputs = ["show-thumbnail": "maybe"]
        let store = MacScreenshotPreferenceStore(runner: recorder.run)
        XCTAssertNil(store.read().showThumbnail)
    }

    /// 还原：快照里有的键写回去，没有的键删掉。
    func testRestoreWritesPresentKeysAndDeletesAbsentOnes() {
        let recorder = CommandRecorder()
        let store = MacScreenshotPreferenceStore(runner: recorder.run)
        let snapshot = ScreenshotInboxSnapshot(
            location: "/Users/someone/Desktop",
            locationScreenshot: nil,
            showThumbnail: true
        )

        XCTAssertTrue(store.restore(snapshot: snapshot))
        XCTAssertEqual(recorder.commands, [
            ["/usr/bin/defaults", "write", "com.apple.screencapture", "location", "-string", "/Users/someone/Desktop"],
            ["/usr/bin/defaults", "delete", "com.apple.screencapture", "location-screenshot"],
            ["/usr/bin/defaults", "write", "com.apple.screencapture", "show-thumbnail", "-bool", "true"],
        ])
    }

    /// 删一个本来就没有的键，`defaults` 会报错，但还原算成功。
    func testDeletingAMissingKeyStillCountsAsSuccess() {
        let recorder = CommandRecorder()
        recorder.failWhen = { $0.contains("delete") }
        recorder.failureOutput = "The domain/default pair of (com.apple.screencapture, location) does not exist"
        let store = MacScreenshotPreferenceStore(runner: recorder.run)
        let snapshot = ScreenshotInboxSnapshot(
            location: nil, locationScreenshot: nil, showThumbnail: nil
        )

        XCTAssertTrue(store.restore(snapshot: snapshot))
    }

    /// 还原失败要报出来，不能悄悄放过。
    func testRestoreReportsFailure() {
        let recorder = CommandRecorder()
        recorder.failWhen = { _ in true }
        let store = MacScreenshotPreferenceStore(runner: recorder.run)
        let snapshot = ScreenshotInboxSnapshot(
            location: "/tmp", locationScreenshot: "/tmp", showThumbnail: false
        )
        XCTAssertFalse(store.restore(snapshot: snapshot))
    }

    func testScreenshotDirectoryCanUseAnIsolatedCaptureDirectory() {
        let override = directory.appendingPathComponent("native-screenshots", isDirectory: true)
        let store = MacScreenshotPreferenceStore(
            runner: { _ in
                PreferenceCommandResult(exitCode: 1, output: "")
            },
            captureDirectoryOverride: override
        )

        XCTAssertEqual(store.screenshotDirectory(), override.standardizedFileURL)
    }

    func testScreenshotIndexDirectoryCanBeOverridden() {
        let override = directory.appendingPathComponent("screenshot-index", isDirectory: true)

        XCTAssertEqual(
            ShelfPaths.screenshotsDirectory(environment: [
                "COVIO_SCREENSHOT_INDEX_DIR": override.path,
            ]),
            override
        )
    }

    func testScreenshotDirectoryPrefersTheScreenshotKey() {
        let recorder = CommandRecorder()
        recorder.outputs = [
            "location": "/tmp/general",
            "location-screenshot": "/tmp/screenshots",
        ]
        let store = MacScreenshotPreferenceStore(runner: recorder.run)
        XCTAssertEqual(store.screenshotDirectory().path, "/tmp/screenshots")
    }

    func testScreenshotDirectoryFallsBackToLocationThenDesktop() {
        let recorder = CommandRecorder()
        recorder.outputs = ["location": "/tmp/general"]
        let store = MacScreenshotPreferenceStore(runner: recorder.run)
        XCTAssertEqual(store.screenshotDirectory().path, "/tmp/general")

        recorder.outputs = [:]
        XCTAssertEqual(store.screenshotDirectory(), ShelfPaths.desktopDirectory)
    }

    // MARK: - 子进程的上限

    /// 可执行文件不存在时立刻返回失败，不抛异常。
    func testDefaultsRunnerReportsAMissingExecutable() {
        let result = MacScreenshotPreferenceStore.runDefaults(
            ["/usr/bin/definitely-not-here", "read", "com.apple.screencapture"]
        )
        XCTAssertEqual(result.exitCode, -1)
    }

    /// 子进程关掉输出却不肯退出时，五秒后要放弃。
    ///
    /// 这条是回归用例：以前用 `waitUntilExit()` 等退出，它没有上限，
    /// 而且等待期间会转运行循环，把主线程交出去。
    /// 结果启动流程被卡住的 `defaults` 插断，工具栏一直建不起来。
    func testDefaultsRunnerGivesUpWhenTheChildHangs() {
        let started = Date()
        let result = MacScreenshotPreferenceStore.runDefaults(
            ["/bin/sh", "-c", "exec >/dev/null 2>&1; sleep 30"]
        )
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(result.exitCode, -1)
        XCTAssertLessThan(elapsed, 20, "超过上限还没返回，说明又在无限等待")
    }

    /// 子进程一直占着管道不写时也要放弃。
    func testDefaultsRunnerGivesUpWhenThePipeNeverCloses() {
        let started = Date()
        let result = MacScreenshotPreferenceStore.runDefaults(["/bin/sleep", "30"])
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(result.exitCode, -1)
        XCTAssertLessThan(elapsed, 20, "读管道也要有上限")
    }

    /// 正常命令要拿到退出码与输出。
    func testDefaultsRunnerReturnsTheOutput() {
        let result = MacScreenshotPreferenceStore.runDefaults(["/bin/echo", "hello"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }
}

/// 跨线程只读一次的开关。写入方在后台队列上跑，所以取值要加锁。
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    var isRaised: Bool {
        lock.lock()
        defer { lock.unlock() }
        return raised
    }

    func raise() {
        lock.lock()
        raised = true
        lock.unlock()
    }
}

/// 假的 `defaults` 执行器。记下每条命令，按需要让某些命令失败。
private final class CommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    /// 读到这些键时返回的输出。
    var outputs: [String: String] = [:]
    /// 返回真表示这条命令要失败。
    var failWhen: ([String]) -> Bool = { _ in false }
    /// 失败时命令的输出。
    var failureOutput = ""

    var commands: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var run: MacScreenshotPreferenceStore.Runner {
        { [self] command in
            lock.lock()
            recorded.append(command)
            let shouldFail = failWhen(command)
            let key = command.count > 3 ? command[3] : ""
            let output = shouldFail ? failureOutput : (outputs[key] ?? "")
            lock.unlock()
            return PreferenceCommandResult(exitCode: shouldFail ? 1 : 0, output: output)
        }
    }
}

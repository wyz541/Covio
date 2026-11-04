import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Covio

/// 假的快捷键注册表。
///
/// 真的 Carbon 注册表在测试进程里不能用：宿主应用也跑起来了，
/// 已经占住了 ⇧⌘V 与 ⇧⌘C，测试造不出冲突，也造不出改键。
/// 这个假的按组合字符串判断占用，注册与注销都记账。
@MainActor
final class FakeHotKeyRegistrar {
    /// 已被占用的组合。写 `GlobalHotKey.Spec.binding` 那种写法。
    var occupied: Set<String>
    /// 注册成功的组合，按编号索引。
    private(set) var registered: [UInt32: GlobalHotKey.Spec] = [:]
    /// 注销过的组合，按注销顺序。
    private(set) var removed: [GlobalHotKey.Spec] = []

    init(occupied: Set<String> = []) {
        self.occupied = occupied
    }

    /// 交给 `ClipboardRuntime` 的注册表。
    ///
    /// 闭包强引用自己：运行时拿着注册表，注册表要活到运行时释放为止。
    /// 这里不会成环，因为本对象不持有运行时。
    var registrar: HotKeyRegistrar {
        HotKeyRegistrar(
            add: { [self] spec, _ in
                guard !occupied.contains(spec.binding) else { return false }
                registered[spec.id] = spec
                return true
            },
            remove: { [self] spec in
                // 没注册过也要记账：注销的调用本身就是要验证的行为。
                registered.removeValue(forKey: spec.id)
                removed.append(spec)
            }
        )
    }
}

/// 剪切板模块：读剪贴板、写剪贴板、监视器、运行时。
///
/// 全部用私有的 `NSPasteboard` 实例，不碰用户真正的剪贴板。
/// 每次建一个唯一名字的，用完 `releaseGlobally()`。
@MainActor
final class ClipboardTests: XCTestCase {
    private var directory: URL!
    private var pasteboard: NSPasteboard!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-clipboard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.wyz.covio.tests.\(UUID().uuidString)"))
    }

    override func tearDownWithError() throws {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    private var imageDirectory: URL {
        directory.appendingPathComponent("Clipboard", isDirectory: true)
    }

    // MARK: - 读剪贴板

    func testReadingPlainTextClassifiesItAsText() {
        pasteboard.clearContents()
        pasteboard.setString("看这个 https://example.com", forType: .string)

        let payload = ClipboardPayloadReader.read(pasteboard, imageDirectory: imageDirectory)

        XCTAssertEqual(payload?.kind, ClipKind.text)
        XCTAssertEqual(payload?.text, "看这个 https://example.com")
    }

    func testReadingALinkClassifiesItAsALink() {
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/a?b=1", forType: .string)

        XCTAssertEqual(
            ClipboardPayloadReader.read(pasteboard, imageDirectory: imageDirectory)?.kind,
            ClipKind.link
        )
    }

    func testReadingAColourClassifiesItAsAColour() {
        pasteboard.clearContents()
        pasteboard.setString("#ff8800", forType: .string)

        XCTAssertEqual(
            ClipboardPayloadReader.read(pasteboard, imageDirectory: imageDirectory)?.kind,
            ClipKind.color
        )
    }

    /// 从访达复制文件时剪贴板上同时有文件地址与字符串，要按文件收。
    func testReadingAFileURLKeepsThePath() throws {
        let file = try makeFile("note.txt")
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])

        let payload = ClipboardPayloadReader.read(pasteboard, imageDirectory: imageDirectory)

        XCTAssertEqual(payload?.kind, ClipKind.files)
        XCTAssertEqual(payload?.filePath, file.path)
        XCTAssertEqual(payload?.byteSize, 1)
    }

    func testReadingSeveralFilesJoinsThePaths() throws {
        let first = try makeFile("a.txt")
        let second = try makeFile("b.txt")
        pasteboard.clearContents()
        pasteboard.writeObjects([first as NSURL, second as NSURL])

        let payload = ClipboardPayloadReader.read(pasteboard, imageDirectory: imageDirectory)

        XCTAssertEqual(payload?.kind, ClipKind.files)
        XCTAssertEqual(payload?.filePath, first.path, "第一位是第一个文件")
        XCTAssertEqual(payload?.text, "\(first.path)\n\(second.path)", "完整列表按行放在 text 里")
    }

    /// 图片落到磁盘，剪贴板上不留二进制。
    func testReadingAnImageWritesItToDisk() throws {
        let image = try makePNG()
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        let payload = ClipboardPayloadReader.read(pasteboard, imageDirectory: imageDirectory)

        XCTAssertEqual(payload?.kind, ClipKind.image)
        let path = try XCTUnwrap(payload?.filePath)
        XCTAssertTrue(path.hasPrefix(imageDirectory.path), "图片要落在剪切板目录里：\(path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertGreaterThan(payload?.byteSize ?? 0, 0)
    }

    /// 同一张图写两次只占一份空间。
    func testTheSameImageReusesOneFile() throws {
        let writer = ClipboardImageWriter()
        let data = try makePNGData()

        let first = writer.write(data, into: imageDirectory)
        let second = writer.write(data, into: imageDirectory)

        XCTAssertEqual(first, second)
        let files = try FileManager.default.contentsOfDirectory(atPath: imageDirectory.path)
        XCTAssertEqual(files.count, 1, "目录里应当只有一份：\(files)")
    }

    func testFingerprintIsStableAndContentDependent() {
        let one = Data("one".utf8)
        let other = Data("two".utf8)

        XCTAssertEqual(ClipboardImageWriter.fingerprint(one), ClipboardImageWriter.fingerprint(one))
        XCTAssertNotEqual(ClipboardImageWriter.fingerprint(one), ClipboardImageWriter.fingerprint(other))
    }

    func testReadingAnEmptyPasteboardReturnsNothing() {
        pasteboard.clearContents()

        XCTAssertNil(ClipboardPayloadReader.read(pasteboard, imageDirectory: imageDirectory))
    }

    // MARK: - 写剪贴板

    func testWriterRoundTripsText() {
        let item = makeItem(kind: ClipKind.text, text: "hello")

        XCTAssertTrue(ClipboardWriter.write(item, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
    }

    func testWriterRoundTripsFiles() throws {
        let file = try makeFile("note.txt")
        let item = makeItem(kind: ClipKind.files, text: file.path, filePath: file.path)

        XCTAssertTrue(ClipboardWriter.write(item, to: pasteboard))
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(urls?.map(\.path), [file.path])
    }

    /// 图片条目要同时写文件地址与图片。
    ///
    /// 访达的 ⌘V 只接受文件地址。只写图片时，从 Hub 复制图片再粘贴到访达没有反应。
    func testWriterRoundTripsAnImageWithItsFileURL() throws {
        let file = directory.appendingPathComponent("shot.png")
        try makePNGData().write(to: file)
        let item = makeItem(kind: ClipKind.image, filePath: file.path)

        XCTAssertTrue(ClipboardWriter.write(item, to: pasteboard))

        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(urls?.map(\.path), [file.path], "图片条目要带上文件地址，访达才收得下")
        XCTAssertNotNil(pasteboard.data(forType: .tiff), "图片本身也要在")
    }

    /// 图片被外部删掉时写不进去，返回假而不是抛错。
    func testWriterFailsWhenTheImageIsGone() {
        let item = makeItem(kind: ClipKind.image, filePath: directory.appendingPathComponent("gone.png").path)

        XCTAssertFalse(ClipboardWriter.write(item, to: pasteboard))
    }

    // MARK: - 监视器

    func testMonitorReportsAChange() {
        var captured: [ClipboardPayload] = []
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            imageDirectory: imageDirectory,
            interval: 0.05
        ) { captured.append($0) }
        monitor.start()
        defer { monitor.stop() }

        pasteboard.clearContents()
        pasteboard.setString("first", forType: .string)

        XCTAssertTrue(waitUntil { captured.count == 1 }, "没有收到变更")
        XCTAssertEqual(captured.first?.text, "first")
    }

    /// 本应用自己写剪贴板时不能再收一遍，否则从 Hub 复制旧内容会冒出新条目。
    func testMonitorIgnoresTheAppsOwnWrite() {
        var captured: [ClipboardPayload] = []
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            imageDirectory: imageDirectory,
            interval: 0.05
        ) { captured.append($0) }
        monitor.start()
        defer { monitor.stop() }

        pasteboard.clearContents()
        pasteboard.setString("ours", forType: .string)
        monitor.ignoreOwnChange()

        XCTAssertFalse(waitUntil(timeout: 0.4) { !captured.isEmpty }, "自己的写入被收进来了")
    }

    func testMonitorDoesNotReportTheExistingClipboardOnStart() {
        pasteboard.clearContents()
        pasteboard.setString("已经在了", forType: .string)

        var captured: [ClipboardPayload] = []
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            imageDirectory: imageDirectory,
            interval: 0.05
        ) { captured.append($0) }
        monitor.start()
        defer { monitor.stop() }

        XCTAssertFalse(waitUntil(timeout: 0.4) { !captured.isEmpty }, "启动时不该上报已有内容")
    }

    // MARK: - 运行时

    func testRuntimeCapturesAndPersists() {
        let runtime = makeRuntime()

        runtime.capture(ClipboardPayload(kind: ClipKind.link, text: "https://example.com"))

        XCTAssertEqual(runtime.items.count, 1)
        XCTAssertEqual(runtime.items.first?.kind, ClipKind.link)
        // 换一个存储读一遍，证明真的落了盘。
        let reloaded = makeStore().load()
        XCTAssertEqual(reloaded.items.map(\.text), ["https://example.com"])
    }

    /// 同一个内容复制两次只留一条，并且挪到最前。
    func testRuntimeDeduplicatesTheSameContent() {
        let runtime = makeRuntime()
        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "same"))
        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "other"))
        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "same"))

        XCTAssertEqual(runtime.items.map(\.text), ["same", "other"])
    }

    func testRuntimeSkipsCaptureWhilePaused() {
        let runtime = makeRuntime()
        runtime.setPaused(true)

        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "ignored"))

        XCTAssertTrue(runtime.items.isEmpty)
        XCTAssertTrue(runtime.isPaused, "暂停状态要落盘")
        XCTAssertTrue(makeStore().load().paused)
    }

    /// 全部清除时置顶的留着。
    func testClearAllKeepsPinnedItems() {
        let runtime = makeRuntime()
        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "one"))
        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "two"))
        let pinned = runtime.items[0].id
        runtime.togglePin(pinned)

        runtime.clearAll()

        XCTAssertEqual(runtime.items.map(\.id), [pinned])
        XCTAssertTrue(runtime.items[0].pinned)
    }

    func testTogglePinFlipsAndPersists() {
        let runtime = makeRuntime()
        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "one"))
        let id = runtime.items[0].id

        runtime.togglePin(id)
        XCTAssertTrue(runtime.items[0].pinned)
        XCTAssertTrue(makeStore().load().items[0].pinned)

        runtime.togglePin(id)
        XCTAssertFalse(runtime.items[0].pinned)
    }

    /// 粘贴栈按入栈顺序出。取队首时顺带把它摘掉。
    func testPasteStackPopsInOrder() {
        let runtime = makeRuntime()
        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "one"))
        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "two"))
        let ids = runtime.items.map(\.id)
        runtime.pushToStack(ids[0])
        runtime.pushToStack(ids[1])

        XCTAssertEqual(runtime.pasteStack, ids)

        // 没有辅助功能权限时 `paste` 会失败，但队首仍然要往下走。
        _ = runtime.pasteNextFromStack()
        XCTAssertEqual(runtime.pasteStack, [ids[1]])
    }

    /// 删掉一条时，栈里对应的位置也要清掉。
    func testRemoveAlsoDropsTheItemFromThePasteStack() {
        let runtime = makeRuntime()
        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "one"))
        let id = runtime.items[0].id
        runtime.pushToStack(id)

        runtime.remove(id)

        XCTAssertTrue(runtime.pasteStack.isEmpty)
    }

    /// 复制的目标不是自己。Hub 是非激活面板，正常情况下前台应用不变。
    func testCopyWritesTheItemBackToThePasteboard() {
        let runtime = makeRuntime()
        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "hello"))

        XCTAssertTrue(runtime.copyToPasteboard(runtime.items[0].id))
        XCTAssertEqual(pasteboard.string(forType: .string), "hello")
    }

    // MARK: - 文字识别

    /// 图片条目收进来之后补一次识别，结果写回同一条并落盘。
    func testRuntimeWritesRecognizedTextBackIntoTheItem() throws {
        let picture = try makeFile("shot.png")
        var environment = ClipboardEnvironment(isEnabled: { true })
        var recognized: [URL] = []
        environment.recognizeText = { url, completion in
            recognized.append(url)
            completion("识别出来的字")
        }
        let runtime = makeRuntime(environment: environment)

        runtime.capture(ClipboardPayload(kind: ClipKind.image, filePath: picture.path, byteSize: 1))

        XCTAssertEqual(recognized.map(\.path), [picture.path])
        XCTAssertEqual(runtime.items.first?.text, "识别出来的字")
        XCTAssertEqual(makeStore().load().items.first?.text, "识别出来的字", "识别结果要落盘")
    }

    /// 文字条目不做识别。识别很贵，白跑一遍会拖慢复制。
    func testRuntimeSkipsRecognitionForTextItems() {
        var environment = ClipboardEnvironment(isEnabled: { true })
        var recognized = 0
        environment.recognizeText = { _, completion in
            recognized += 1
            completion("不该出现")
        }
        let runtime = makeRuntime(environment: environment)

        runtime.capture(ClipboardPayload(kind: ClipKind.text, text: "hello"))

        XCTAssertEqual(recognized, 0)
        XCTAssertEqual(runtime.items.first?.text, "hello")
    }

    /// 识别结果回来时那条已经被删掉了，不能崩，也不能凭空造一条。
    func testRecognitionResultIsDroppedWhenTheItemIsGone() throws {
        let picture = try makeFile("shot.png")
        var pending: (@MainActor (String) -> Void)?
        var environment = ClipboardEnvironment(isEnabled: { true })
        environment.recognizeText = { _, completion in pending = completion }
        let runtime = makeRuntime(environment: environment)
        runtime.capture(ClipboardPayload(kind: ClipKind.image, filePath: picture.path, byteSize: 1))
        runtime.remove(runtime.items[0].id)

        pending?("迟到的结果")

        XCTAssertTrue(runtime.items.isEmpty)
    }

    /// 真跑一次 Vision。识别不出来就说明这条链路断了。
    func testVisionRecognizesRenderedText() throws {
        let url = directory.appendingPathComponent("text.png")
        try makeTextImage("COVIO").write(to: url)

        let text = ClipboardOCR.recognizeTextSynchronously(in: url)

        XCTAssertTrue(
            text.uppercased().contains("COVIO"),
            "识别结果为「\(text)」，没认出渲染上去的字"
        )
    }

    func testVisionReturnsNothingForAFileThatIsNotAnImage() throws {
        let url = try makeFile("note.txt")

        XCTAssertEqual(ClipboardOCR.recognizeTextSynchronously(in: url), "")
        XCTAssertEqual(ClipboardOCR.recognizeTextSynchronously(in: directory.appendingPathComponent("missing.png")), "")
    }

    // MARK: - 快捷键

    /// 三个快捷键的键码与修饰键要钉住，改错了会静默失效。
    func testHotKeySpecsMatchTheContract() {
        XCTAssertEqual(GlobalHotKey.hubToggle.keyCode, UInt32(kVK_ANSI_T))
        XCTAssertEqual(GlobalHotKey.hubToggle.modifiers, UInt32(controlKey | optionKey))
        XCTAssertEqual(GlobalHotKey.pasteStack.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(GlobalHotKey.pasteStack.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertEqual(GlobalHotKey.captureSelection.keyCode, UInt32(kVK_ANSI_C))
        XCTAssertEqual(GlobalHotKey.captureSelection.modifiers, UInt32(cmdKey | shiftKey))
        // 编号不能撞，否则分派会串。
        let ids = [
            GlobalHotKey.hubToggle.id,
            GlobalHotKey.pasteStack.id,
            GlobalHotKey.captureSelection.id,
        ]
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// 出厂组合写进 `config.json` 再读回来，要是同一个东西。
    func testBindingRoundTrips() {
        for action in ClipboardHotKeyAction.allCases {
            let spec = action.defaultSpec
            XCTAssertEqual(GlobalHotKey.Spec(binding: spec.binding, id: spec.id), spec)
        }
        XCTAssertEqual(GlobalHotKey.pasteStack.binding, "shift+cmd+V")
        XCTAssertEqual(GlobalHotKey.captureSelection.binding, "shift+cmd+C")
    }

    func testBindingAcceptsAliasesAndAnyCase() {
        let spec = GlobalHotKey.Spec(binding: "Ctrl+ALT+v", id: GlobalHotKey.pasteStack.id)

        XCTAssertEqual(spec?.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(spec?.modifiers, UInt32(controlKey | optionKey))
    }

    func testBindingRendersMacSymbols() {
        XCTAssertEqual(GlobalHotKey.pasteStack.displayName, "⇧⌘V")
        XCTAssertEqual(GlobalHotKey.hubToggle.displayName, "⌃⌥T")
    }

    /// 认不出的写法一律拒绝。放过去的话会注册出一个用户没要的组合。
    func testUnusableBindingsAreRejected() {
        XCTAssertNil(GlobalHotKey.Spec(binding: "shift+cmd+", id: 2), "没有键名")
        XCTAssertNil(GlobalHotKey.Spec(binding: "shift+cmd+F5", id: 2), "功能键不支持")
        XCTAssertNil(GlobalHotKey.Spec(binding: "cmd", id: 2), "只有修饰键")
        XCTAssertNil(GlobalHotKey.Spec(binding: "V", id: 2), "没有修饰键会把整个键抢走")
        XCTAssertNil(GlobalHotKey.Spec(binding: "", id: 2))
    }

    /// 配置里写坏了就退回出厂组合，不能注册出一个奇怪的键。
    func testRuntimeFallsBackToTheDefaultSpec() {
        var environment = ClipboardEnvironment(isEnabled: { true })
        environment.hotKeyBinding = { _ in "乱写的" }
        let runtime = makeRuntime(environment: environment)

        XCTAssertEqual(runtime.hotKeySpec(for: .pasteStack), GlobalHotKey.pasteStack)
        XCTAssertEqual(runtime.hotKeySpec(for: .captureSelection), GlobalHotKey.captureSelection)
    }

    /// 编号不能跟着组合一起换：Carbon 按编号分派。
    func testRuntimeKeepsTheIDWhenTheBindingChanges() {
        var environment = ClipboardEnvironment(isEnabled: { true })
        environment.hotKeyBinding = { action in
            action == .pasteStack ? "control+shift+B" : action.candidates[0]
        }
        let runtime = makeRuntime(environment: environment)

        let spec = runtime.hotKeySpec(for: .pasteStack)
        XCTAssertEqual(spec.keyCode, UInt32(kVK_ANSI_B))
        XCTAssertEqual(spec.modifiers, UInt32(controlKey | shiftKey))
        XCTAssertEqual(spec.id, GlobalHotKey.pasteStack.id)
    }

    /// Carbon 与别的应用撞组合时会静默失败。这条要能被设置页看到。
    func testFailedRegistrationIsRecordedAndReported() {
        let registry = FakeHotKeyRegistrar(occupied: ["control+option+K"])
        var environment = ClipboardEnvironment(isEnabled: { true })
        environment.hotKeyBinding = { action in
            action == .pasteStack ? "control+option+K" : action.candidates[0]
        }
        let bridge = ClipboardBridge(config: AppConfigs.defaults)
        var reported: [LocalizedCopy] = []
        bridge.report = { reported.append($0) }
        let runtime = makeRuntime(environment: environment, registry: registry, bridge: bridge)

        runtime.registerHotKeys()

        XCTAssertTrue(runtime.hasHotKeyConflict(.pasteStack), "被占用的那个要记为失败")
        XCTAssertFalse(runtime.hasHotKeyConflict(.captureSelection), "没被占用的那个不受影响")
        XCTAssertNil(registry.registered[GlobalHotKey.pasteStack.id])
        XCTAssertNotNil(registry.registered[GlobalHotKey.captureSelection.id])
        XCTAssertEqual(reported.map { $0.text }, [ContractCopy.copyClipboardErrorHotKey.text])
    }

    /// 改键：换一个组合之后旧的组合要放开，新的要真的生效。
    func testRebindingSwapsTheRegisteredCombination() {
        let registry = FakeHotKeyRegistrar()
        var binding = "control+option+K"
        var environment = ClipboardEnvironment(isEnabled: { true })
        environment.hotKeyBinding = { action in
            action == .pasteStack ? binding : action.candidates[0]
        }
        let runtime = makeRuntime(environment: environment, registry: registry)

        runtime.applyConfiguration()
        defer { runtime.stop() }
        XCTAssertEqual(
            registry.registered[GlobalHotKey.pasteStack.id]?.keyCode,
            UInt32(kVK_ANSI_K),
            "起手用的是配置里的组合"
        )

        binding = "control+option+J"
        runtime.reloadHotKeys()

        XCTAssertEqual(
            registry.registered[GlobalHotKey.pasteStack.id]?.keyCode,
            UInt32(kVK_ANSI_J),
            "改键之后生效的是新组合"
        )
        XCTAssertEqual(registry.removed.count, 2, "旧的组合要先注销掉")
        XCTAssertFalse(runtime.hasHotKeyConflict(.pasteStack))
    }

    /// 新的组合也被占用时，要记为失败，而不是偷偷留着旧的那个。
    func testRebindingToATakenCombinationReportsTheConflict() {
        let registry = FakeHotKeyRegistrar(occupied: ["control+option+J"])
        var binding = "control+option+K"
        var environment = ClipboardEnvironment(isEnabled: { true })
        environment.hotKeyBinding = { action in
            action == .pasteStack ? binding : action.candidates[0]
        }
        let runtime = makeRuntime(environment: environment, registry: registry)
        runtime.applyConfiguration()
        defer { runtime.stop() }

        binding = "control+option+J"
        runtime.reloadHotKeys()

        XCTAssertTrue(runtime.hasHotKeyConflict(.pasteStack))
        XCTAssertNil(registry.registered[GlobalHotKey.pasteStack.id])
    }

    /// 关掉剪切板之后改键不该把快捷键又注册回来。
    func testRebindingDoesNothingWhileRecordingIsOff() {
        let registry = FakeHotKeyRegistrar()
        var environment = ClipboardEnvironment(isEnabled: { false })
        environment.hotKeyBinding = { _ in "control+option+K" }
        let runtime = makeRuntime(environment: environment, registry: registry)

        runtime.applyConfiguration()
        runtime.reloadHotKeys()

        XCTAssertTrue(registry.registered.isEmpty)
    }

    /// 暂停记录同样要注销快捷键：暂停期间按 ⇧⌘V 不该有反应。
    func testPausingUnregistersTheShortcuts() {
        let registry = FakeHotKeyRegistrar()
        let runtime = makeRuntime(registry: registry)
        runtime.applyConfiguration()
        defer { runtime.stop() }
        XCTAssertEqual(registry.registered.count, 2)

        runtime.setPaused(true)

        XCTAssertTrue(registry.registered.isEmpty)
        XCTAssertEqual(registry.removed.count, 2)
    }

    func testUnregisterIsIdempotent() {
        // 这里走真的 Carbon：注册中心是进程级的，只有全应用共用的那一个。
        // 用一个宿主应用不会占用的组合。
        let spec = GlobalHotKey.Spec(
            keyCode: UInt32(kVK_F19),
            modifiers: UInt32(cmdKey | optionKey | controlKey),
            id: 99
        )
        let hotKey = GlobalHotKey(spec: spec) {}

        XCTAssertTrue(hotKey.register())
        XCTAssertTrue(hotKey.isRegistered)
        XCTAssertTrue(hotKey.register(), "重复注册要当成功")
        hotKey.unregister()
        hotKey.unregister()
        XCTAssertFalse(hotKey.isRegistered)
    }

    // MARK: - 辅助

    private func makeRuntime(
        environment: ClipboardEnvironment? = nil,
        registry: FakeHotKeyRegistrar? = nil,
        bridge: ClipboardBridge? = nil
    ) -> ClipboardRuntime {
        let resolvedBridge = bridge ?? ClipboardBridge(config: AppConfigs.defaults)
        if resolvedBridge.report == nil { resolvedBridge.report = { _ in } }
        return ClipboardRuntime(
            store: makeStore(),
            imageDirectory: imageDirectory,
            pasteboard: pasteboard,
            hotKeys: (registry ?? FakeHotKeyRegistrar()).registrar,
            environment: environment ?? ClipboardEnvironment(isEnabled: { true }),
            bridge: resolvedBridge
        )
    }

    private func makeStore() -> ClipboardStore {
        ClipboardStore.companion.create(path: directory.appendingPathComponent("clipboard.json").path)
    }

    private func makeItem(kind: ClipKind, text: String = "", filePath: String = "") -> ClipItem {
        ClipItem(
            id: UUID().uuidString,
            kind: kind,
            text: text,
            filePath: filePath,
            byteSize: 0,
            createdAtEpochSeconds: 0,
            pinned: false,
            sourceBundleId: ""
        )
    }

    @discardableResult
    private func makeFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    /// 造一张 2×2 的图。
    private func makePNG() throws -> NSImage {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2))
        image.unlockFocus()
        return image
    }

    /// 造一张 2×2 的 PNG。
    private func makePNGData() throws -> Data {
        let tiff = try XCTUnwrap(try makePNG().tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// 造一张写着字的 PNG。给 Vision 用。
    private func makeTextImage(_ text: String) throws -> Data {
        let size = NSSize(width: 320, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 64, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.size()
        string.draw(at: NSPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2))
        image.unlockFocus()

        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// 等条件成立。监视器按固定间隔轮询，所以要等。
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }
}

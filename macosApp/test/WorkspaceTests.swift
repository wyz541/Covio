import XCTest
@testable import Covio

/// 文件页与工作区运行时的行为。
///
/// 顺序、淘汰和过期规则在 Rust core 里，由 Rust 测试覆盖。
/// 这里只测 Swift 这一层：放入、提示、置顶、删除、清理，以及页高。
@MainActor
final class WorkspaceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 放入

    /// 放入一个文件之后，条目在列表里，内容在本地。
    func testIntakePutsTheFileInTheWorkspace() throws {
        let source = try makeFile(named: "note.txt", contents: "hello")
        let runtime = makeRuntime()

        XCTAssertEqual(runtime.intake(urls: [source]), 1)
        XCTAssertEqual(runtime.entries.count, 1)
        XCTAssertEqual(runtime.entries.first?.displayName, "note.txt")
        XCTAssertEqual(runtime.entries.first?.kind, WorkspaceKind.text)
        XCTAssertNotNil(runtime.contentURL(runtime.entries[0].entryId))
        XCTAssertEqual(runtime.totalBytes, Int64("hello".utf8.count))
    }

    /// 同一份内容放两次只留一条，并给一条说明。
    func testIntakeReportsTheDuplicate() throws {
        let runtime = makeRuntime()

        XCTAssertEqual(runtime.intake(urls: [try makeFile(named: "a.txt", contents: "same")]), 1)
        XCTAssertEqual(runtime.intake(urls: [try makeFile(named: "b.txt", contents: "same")]), 0)

        XCTAssertEqual(runtime.entries.count, 1)
        XCTAssertNil(runtime.errorMessage)
        XCTAssertEqual(
            runtime.infoMessage?.text,
            ContractCopy.copyHubFilesNoticeDuplicate.text
        )
    }

    /// 认不出的来源给一条失败提示，不留半条数据。
    func testIntakeRefusesSomethingThatIsNotAFile() {
        let runtime = makeRuntime()
        let folder = directory.appendingPathComponent("folder", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertEqual(runtime.intake(urls: [folder]), 0)
        XCTAssertTrue(runtime.entries.isEmpty)
        XCTAssertEqual(
            runtime.errorMessage?.text,
            ContractCopy.copyHubFilesErrorImport.text
        )
    }

    /// 超过单条上限的文件被拒，并给出对应提示。
    func testIntakeRefusesAFileOverTheLimit() throws {
        let runtime = makeRuntime()
        let source = try makeFile(named: "big.bin", contents: String(repeating: "x", count: 4_096))

        XCTAssertEqual(runtime.intake(urls: [source]), 0)
        XCTAssertTrue(runtime.entries.isEmpty)
        XCTAssertEqual(
            runtime.errorMessage?.text,
            ContractCopy.copyHubFilesErrorTooLarge.text
        )
    }

    // MARK: - 置顶与删除

    func testTogglePinFlipsTheFlag() throws {
        let runtime = makeRuntime()
        runtime.intake(urls: [try makeFile(named: "note.txt", contents: "hello")])
        let entryId = runtime.entries[0].entryId

        runtime.togglePin(entryId)

        XCTAssertTrue(runtime.entries[0].pinned)
        // 换一个存储读一遍，证明落了盘。
        XCTAssertTrue(makeClient().load().entries[0].pinned)
    }

    /// 删除条目时内容也要删掉，磁盘上不留副本。
    func testRemoveAlsoDropsTheContent() throws {
        let runtime = makeRuntime()
        runtime.intake(urls: [try makeFile(named: "note.txt", contents: "hello")])
        let entryId = runtime.entries[0].entryId
        let content = try XCTUnwrap(runtime.contentURL(entryId))

        runtime.remove(entryId)

        XCTAssertTrue(runtime.entries.isEmpty)
        XCTAssertEqual(runtime.totalBytes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: content.path), "内容要一起删掉")
    }

    /// 删除留下标记：标记挡住对端把这条重新复制回来。
    func testRemoveLeavesATombstone() throws {
        var now: Int64 = 1_000
        let runtime = makeRuntime(now: { now })
        runtime.intake(urls: [try makeFile(named: "note.txt", contents: "hello")])
        let entryId = runtime.entries[0].entryId

        runtime.remove(entryId)

        let marks = makeClient().store.loadTombstones()
        XCTAssertEqual(marks.map(\.entryId), [entryId])
        XCTAssertEqual(marks.first?.deletedAtEpochSeconds, now)
    }

    /// 清空工作区时标记一起删。留着会拦住用户重新放入同样的内容。
    func testClearAllDropsTheTombstones() throws {
        let runtime = makeRuntime()
        runtime.intake(urls: [try makeFile(named: "note.txt", contents: "hello")])
        let entryId = runtime.entries[0].entryId
        runtime.remove(entryId)

        runtime.clearAll()

        XCTAssertTrue(makeClient().store.loadTombstones().isEmpty)
    }

    // MARK: - 过期

    /// 过期的条目在启动时就被清掉，内容也删掉。
    func testExpiredEntriesAreSweptOnLaunch() throws {
        let source = try makeFile(named: "note.txt", contents: "hello")
        var now: Int64 = 1_000
        let first = makeRuntime(now: { now })
        first.intake(urls: [source])
        let entryId = first.entries[0].entryId
        let content = try XCTUnwrap(first.contentURL(entryId))

        // 走到保留期之后，换一个运行时重新读。
        now += 7 * 24 * 3_600
        let second = makeRuntime(now: { now })

        XCTAssertTrue(second.entries.isEmpty, "过期的条目不该留在列表里")
        XCTAssertFalse(FileManager.default.fileExists(atPath: content.path), "过期内容要删掉")
    }

    /// 手动清理没有可清的东西时不给说明，剩下的条目不受影响。
    func testSweepKeepsLiveEntries() throws {
        var now: Int64 = 1_000
        let runtime = makeRuntime(now: { now })
        runtime.intake(urls: [try makeFile(named: "note.txt", contents: "hello")])
        // 放入自己会给一条说明。先清掉，这一条只看清理的结果。
        runtime.clearMessages()

        now += 3_600
        XCTAssertEqual(runtime.sweep(), 0)
        XCTAssertEqual(runtime.entries.count, 1)
        XCTAssertNil(runtime.infoMessage)
    }

    // MARK: - 提示

    func testClearMessagesDropsBothNotices() throws {
        let runtime = makeRuntime()
        runtime.intake(urls: [try makeFile(named: "note.txt", contents: "hello")])
        runtime.intake(urls: [try makeFile(named: "copy.txt", contents: "hello")])
        XCTAssertNotNil(runtime.infoMessage)

        runtime.clearMessages()

        XCTAssertNil(runtime.infoMessage)
        XCTAssertNil(runtime.errorMessage)
    }

    // MARK: - 从剪切板与截图存入

    /// 存入一段文字：条目进列表，文件名取自正文第一行。
    func testSaveTextRecordsTheEntry() {
        let runtime = makeRuntime()

        XCTAssertTrue(runtime.save(text: "第一行\n第二行"))

        XCTAssertEqual(runtime.entries.count, 1)
        XCTAssertEqual(runtime.entries.first?.displayName, "第一行.txt")
        XCTAssertEqual(runtime.entries.first?.kind, WorkspaceKind.text)
        XCTAssertEqual(
            runtime.infoMessage?.text,
            ContractCopy.copyHubFilesNoticeSaved.text
        )
    }

    /// 只有空白的文字不存，也不给提示。
    func testSaveTextRefusesBlankText() {
        let runtime = makeRuntime()

        XCTAssertFalse(runtime.save(text: "   \n  "))

        XCTAssertTrue(runtime.entries.isEmpty)
        XCTAssertNil(runtime.infoMessage)
        XCTAssertNil(runtime.errorMessage)
    }

    /// 存入一条文字剪切板记录：没有落盘文件，走正文那条路。
    func testSaveClipItemFallsBackToTheText() {
        let runtime = makeRuntime()

        XCTAssertEqual(runtime.save(clipItem: makeItem(kind: .text, text: "剪贴板正文")), 1)

        XCTAssertEqual(runtime.entries.count, 1)
        XCTAssertEqual(runtime.entries.first?.displayName, "剪贴板正文.txt")
    }

    /// 存入一条图片剪切板记录：走它已经落盘的那个文件。
    func testSaveClipItemUsesTheFileBehindTheItem() throws {
        let image = try makeFile(named: "shot.png", contents: "png bytes")
        let runtime = makeRuntime()

        XCTAssertEqual(runtime.save(clipItem: makeItem(kind: .image, filePath: image.path)), 1)

        XCTAssertEqual(runtime.entries.first?.displayName, "shot.png")
        XCTAssertEqual(runtime.totalBytes, Int64("png bytes".utf8.count))
    }

    /// 存入一条文件剪切板记录：多个文件全部存入。
    func testSaveClipItemTakesEveryPath() throws {
        let first = try makeFile(named: "a.txt", contents: "aaa")
        let second = try makeFile(named: "b.txt", contents: "bbb")
        let runtime = makeRuntime()
        let item = makeItem(kind: .files, text: "\(first.path)\n\(second.path)", filePath: first.path)

        XCTAssertEqual(runtime.save(clipItem: item), 2)

        XCTAssertEqual(runtime.entries.count, 2)
    }

    /// 存入一张截图：路径直接给工作区，就是一次普通的放入。
    func testSaveFilesAtAcceptsAScreenshot() throws {
        let shot = try makeFile(named: "shot.png", contents: "png bytes")
        let runtime = makeRuntime()

        XCTAssertEqual(runtime.save(filesAt: [shot.path]), 1)

        XCTAssertEqual(runtime.entries.first?.displayName, "shot.png")
        XCTAssertEqual(
            runtime.infoMessage?.text,
            ContractCopy.copyHubFilesNoticeSaved.text
        )
    }

    /// 空路径被跳过，不会当成失败。
    func testSaveFilesAtSkipsEmptyPaths() {
        let runtime = makeRuntime()

        XCTAssertEqual(runtime.save(filesAt: ["", ""]), 0)

        XCTAssertTrue(runtime.entries.isEmpty)
        XCTAssertNil(runtime.errorMessage)
    }

    // MARK: - 索引写不进去

    /// 内容收下了但索引没落盘：报错，不算成功，列表里也不留这一条。
    func testIntakeReportsAFailedIndexWrite() throws {
        let source = try makeFile(named: "note.txt", contents: "hello")
        let runtime = makeRuntime()
        blockTheIndexWrite()

        XCTAssertEqual(runtime.intake(urls: [source]), 0)

        XCTAssertTrue(runtime.entries.isEmpty, "没落盘的条目不进列表")
        XCTAssertNil(runtime.infoMessage)
        XCTAssertEqual(
            runtime.errorMessage?.text,
            ContractCopy.copyHubFilesErrorSave.text
        )
    }

    /// 存文字时索引写不进去，返回假并报同一句错。
    func testSaveTextReportsAFailedIndexWrite() {
        let runtime = makeRuntime()
        blockTheIndexWrite()

        XCTAssertFalse(runtime.save(text: "hello"))

        XCTAssertTrue(runtime.entries.isEmpty)
        XCTAssertEqual(
            runtime.errorMessage?.text,
            ContractCopy.copyHubFilesErrorSave.text
        )
    }

    /// 索引落盘成功时存文字返回真，并给出说明。
    func testSaveTextReportsASuccessfulWrite() {
        let runtime = makeRuntime()

        XCTAssertTrue(runtime.save(text: "hello"))

        XCTAssertEqual(runtime.entries.count, 1)
        XCTAssertNil(runtime.errorMessage)
        XCTAssertEqual(
            runtime.infoMessage?.text,
            ContractCopy.copyHubFilesNoticeSaved.text
        )
    }

    // MARK: - 页高

    /// 文件区使用合同里的固定高度。内容超出时在区域内滚动。
    func testTheFilesPageUsesTheContractHeight() {
        XCTAssertEqual(HubMetrics.bodyHeight(for: .pane(.files)), FileAreaMetrics.areaHeight)
        XCTAssertEqual(FileAreaMetrics.areaHeight, 538)
        XCTAssertGreaterThan(
            HubMetrics.bodyHeight(for: .pane(.files)),
            HubMetrics.placeholderBodyHeight
        )
    }

    /// 文件页的自然高度放得进固定外壳。
    func testTheFilesCardStaysWithinTheShell() {
        for height in [CGFloat(900), 1_080, 1_200] {
            XCTAssertLessThanOrEqual(
                HubMetrics.naturalContentHeight(for: .pane(.files)),
                HubMetrics.shellContentHeight(screenHeight: height, safeAreaTop: 0),
                "屏幕高 \(height) 时文件页放不下"
            )
        }
    }

    // MARK: - 工具

    /// 让索引写不进磁盘：把临时文件的位置占成一个目录。
    ///
    /// 内容目录照旧，所以内容能落盘，失败的只有索引那一步。
    private func blockTheIndexWrite() {
        try? FileManager.default.createDirectory(
            at: directory.appendingPathComponent("index.json.tmp", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func makeClient() -> WorkspaceStoreClient {
        WorkspaceStoreClient(directory: directory.path)
    }

    /// 运行时。为了测边界，把单条上限压到 1 KB，保留期压到 1 天。
    private func makeRuntime(now: @escaping () -> Int64 = { 1_000 }) -> WorkspaceRuntime {
        var environment = WorkspaceEnvironment()
        environment.now = now
        let policy = WorkspacePolicy.companion.defaults().doCopy(
            maxTotalBytes: 64 * 1_024,
            maxEntryBytes: 1_024,
            retentionDays: 1,
            lazyFetchThresholdBytes: 50 * 1_024 * 1_024
        )
        return WorkspaceRuntime(client: makeClient(), environment: environment, policy: policy)
    }

    @discardableResult
    private func makeFile(named name: String, contents: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 一条剪切板记录。只有测试用到的三项不同，其余给固定值。
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
}

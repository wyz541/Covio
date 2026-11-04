import XCTest
@testable import Covio

/// 文件区短期传输任务与工作区状态的衔接。
@MainActor
final class WorkspaceTransferTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-transfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testStartupClearsOrphanedFetchingEntries() {
        saveEntry(availability: WorkspaceAvailability.fetching, byteSize: 100)
        let workspace = makeWorkspace()
        let transfers = WorkspaceTransferRuntime(
            workspace: workspace,
            environment: environment(available: 1_000)
        )

        XCTAssertEqual(workspace.entries.single?.availability, WorkspaceAvailability.remote)
        XCTAssertTrue(transfers.tasks.isEmpty)
    }

    func testBeginningATransferCreatesOneTaskAndOneProjectionItem() {
        let entry = saveEntry(availability: WorkspaceAvailability.remote, byteSize: 100)
        let workspace = makeWorkspace()
        let transfers = WorkspaceTransferRuntime(
            workspace: workspace,
            environment: environment(available: 1_000)
        )

        XCTAssertTrue(transfers.beginDownload(entry.entryId))
        XCTAssertTrue(transfers.beginDownload(entry.entryId), "重复开始必须复用同一个内容键")

        let task = try? XCTUnwrap(transfers.task(for: entry.entryId))
        XCTAssertEqual(transfers.tasks.count, 1)
        XCTAssertEqual(task?.direction, .download)
        XCTAssertEqual(task?.peerDeviceId, "iPhone")
        XCTAssertEqual(task?.phase, .waiting)
        XCTAssertEqual(workspace.entries.single?.availability, WorkspaceAvailability.fetching)

        let items = FileAreaProjection.shared.build(
            shelfItems: [],
            workspaceEntries: workspace.entries,
            existingScreenshotPaths: []
        )
        XCTAssertEqual(items.count, 1, "任务不能另建一张卡片")
        XCTAssertEqual(FileAreaPresentation.quickAction(for: items[0], task: task), .cancelTransfer)
    }

    func testProgressAndCancelReturnTheEntryToRemote() {
        let entry = saveEntry(availability: WorkspaceAvailability.remote, byteSize: 100)
        let workspace = makeWorkspace()
        let transfers = WorkspaceTransferRuntime(
            workspace: workspace,
            environment: environment(available: 1_000)
        )
        XCTAssertTrue(transfers.beginDownload(entry.entryId))

        transfers.markTransferring(entry.entryId)
        transfers.updateProgress(entry.entryId, transferredBytes: 62)
        let active = try? XCTUnwrap(transfers.task(for: entry.entryId))
        XCTAssertEqual(active?.phase, .transferring)
        XCTAssertEqual(active?.progress ?? 0, 0.62, accuracy: 0.001)
        XCTAssertEqual(transfers.activeCount, 1)

        transfers.cancel(entry.entryId)
        let cancelled = try? XCTUnwrap(transfers.task(for: entry.entryId))
        XCTAssertEqual(cancelled?.phase, .cancelled)
        XCTAssertEqual(cancelled?.progress, 0)
        XCTAssertEqual(transfers.activeCount, 0)
        XCTAssertEqual(workspace.entries.single?.availability, WorkspaceAvailability.remote)
        XCTAssertEqual(FileAreaPresentation.quickAction(for: item(entry), task: cancelled), .retry)
    }

    func testFailureAndRetryReuseTheSameTask() {
        let entry = saveEntry(availability: WorkspaceAvailability.remote, byteSize: 100)
        let workspace = makeWorkspace()
        let transfers = WorkspaceTransferRuntime(
            workspace: workspace,
            environment: environment(available: 1_000)
        )
        XCTAssertTrue(transfers.beginDownload(entry.entryId))
        transfers.fail(entry.entryId, error: .connectionFailed)

        let failed = try? XCTUnwrap(transfers.task(for: entry.entryId))
        XCTAssertEqual(failed?.phase, .failed)
        XCTAssertEqual(failed?.errorCode, "connection_failed")
        XCTAssertEqual(workspace.entries.single?.availability, WorkspaceAvailability.remote)
        XCTAssertEqual(FileAreaPresentation.quickAction(for: item(entry), task: failed), .retry)
        XCTAssertEqual(
            FileAreaPresentation.transferFailureDetail(
                for: failed!,
                language: .simplifiedChinese
            ),
            ContractCopy.copyHubFilesErrorConnection.text(for: .simplifiedChinese)
        )

        XCTAssertTrue(transfers.retry(entry.entryId))
        let retried = try? XCTUnwrap(transfers.task(for: entry.entryId))
        XCTAssertEqual(transfers.tasks.count, 1)
        XCTAssertEqual(retried?.phase, .waiting)
        XCTAssertNil(retried?.failure)
        XCTAssertEqual(workspace.entries.single?.availability, WorkspaceAvailability.fetching)
    }

    func testSpaceShortageFailsBeforeFetching() {
        let entry = saveEntry(availability: WorkspaceAvailability.remote, byteSize: 100)
        let workspace = makeWorkspace()
        let transfers = WorkspaceTransferRuntime(
            workspace: workspace,
            environment: environment(available: 99)
        )

        XCTAssertFalse(transfers.beginDownload(entry.entryId))
        let failed = try? XCTUnwrap(transfers.task(for: entry.entryId))
        XCTAssertEqual(failed?.phase, .failed)
        XCTAssertEqual(failed?.failure, .quotaExceeded)
        XCTAssertEqual(failed?.errorCode, "quota_exceeded")
        XCTAssertEqual(workspace.entries.single?.availability, WorkspaceAvailability.remote)
        XCTAssertEqual(transfers.activeCount, 0)
    }

    func testCompletingATransferRemovesTheTemporaryTask() {
        let entry = saveEntry(availability: WorkspaceAvailability.remote, byteSize: 100)
        let workspace = makeWorkspace()
        let transfers = WorkspaceTransferRuntime(
            workspace: workspace,
            environment: environment(available: 1_000)
        )
        XCTAssertTrue(transfers.beginDownload(entry.entryId))

        transfers.complete(entry.entryId)

        XCTAssertNil(transfers.task(for: entry.entryId))
        XCTAssertTrue(transfers.tasks.isEmpty)
        XCTAssertEqual(workspace.entries.single?.availability, WorkspaceAvailability.local)
    }

    private func makeWorkspace() -> WorkspaceRuntime {
        var context = WorkspaceEnvironment()
        context.now = { 2_000 }
        return WorkspaceRuntime(
            client: makeClient(),
            environment: context,
            policy: policy
        )
    }

    private func environment(available: Int64) -> WorkspaceTransferEnvironment {
        WorkspaceTransferEnvironment(availableBytes: { available })
    }

    @discardableResult
    private func saveEntry(
        availability: WorkspaceAvailability,
        byteSize: Int64
    ) -> WorkspaceEntry {
        let entry = WorkspaceEntry(
            entryId: String(repeating: "a", count: 64),
            kind: WorkspaceKind.pdf,
            displayName: "remote.pdf",
            byteSize: byteSize,
            contentType: "application/pdf",
            createdAtEpochSeconds: 1_000,
            originDeviceId: "iPhone",
            expiresAtEpochSeconds: 0,
            availability: availability,
            pinned: false
        )
        let defaults = WorkspaceState.companion.defaults()
        let state = defaults.doCopy(
            schemaVersion: defaults.schemaVersion,
            entries: [entry],
            policy: policy
        )
        makeClient().save(state)
        return entry
    }

    private func item(_ entry: WorkspaceEntry) -> FileAreaItem {
        let projected = FileAreaProjection.shared.build(
            shelfItems: [],
            workspaceEntries: [entry],
            existingScreenshotPaths: []
        )
        return projected[0]
    }

    private func makeClient() -> WorkspaceStoreClient {
        WorkspaceStoreClient(directory: directory.path)
    }

    private var policy: WorkspacePolicy {
        WorkspacePolicy.companion.defaults().doCopy(
            maxTotalBytes: 64 * 1_024,
            maxEntryBytes: 1_024,
            retentionDays: 1,
            lazyFetchThresholdBytes: 50 * 1_024 * 1_024
        )
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}

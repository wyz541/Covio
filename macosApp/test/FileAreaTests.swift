import XCTest
@testable import Covio

/// 统一文件区的几何、动作顺序和无障碍文案。
@MainActor
final class FileAreaTests: XCTestCase {
    func testTheFileAreaUsesTheApprovedFocusAndQuietGridGeometry() {
        XCTAssertEqual(FileAreaMetrics.areaHeight, 538)
        XCTAssertEqual(FileAreaMetrics.focusHeight, 176)
        XCTAssertEqual(FileAreaMetrics.quietTileHeight, 146)
        XCTAssertEqual(FileAreaMetrics.quietColumns, 4)
        XCTAssertEqual(
            FileAreaMetrics.quietTileWidth(containerWidth: 912),
            217.5,
            accuracy: 0.001
        )
    }

    func testAQuietTileKeepsFourColumnsAtTheMinimumPanelWidth() {
        let compactContentWidth = HubMetrics.minWidth - HubMetrics.panelPadding * 2
        let tileWidth = FileAreaMetrics.quietTileWidth(containerWidth: compactContentWidth)

        XCTAssertEqual(tileWidth, 157.5, accuracy: 0.001)
        XCTAssertGreaterThan(tileWidth, 0)
    }

    func testScreenshotActionsStayOrderedAndDeletionIsLast() {
        let item = makeItem(
            id: "screenshot:/tmp/shot.png",
            origin: FileAreaOrigin.screenshot,
            itemId: "/tmp/shot.png",
            name: "shot.png",
            kind: FileAreaKind.screenshot,
            capabilities: FileAreaCapabilities(
                canOpen: true,
                canCopy: true,
                canCopyText: false,
                canMarkup: true,
                canDragOut: true,
                canSaveToWorkspace: true,
                canReveal: false,
                canPin: false,
                canRemove: true,
                canDownload: false,
                canCancel: false
            )
        )

        XCTAssertEqual(
            FileAreaPresentation.focusActions(for: item),
            [.open, .copy, .markup]
        )
        XCTAssertEqual(FileAreaPresentation.quickAction(for: item), .open)
        XCTAssertEqual(
            FileAreaPresentation.contextActions(for: item),
            [.copy, .open, .markup, .saveToWorkspace, .remove]
        )
        XCTAssertEqual(FileAreaPresentation.contextActions(for: item).last, .remove)
    }

    func testTextUsesCopyTextAndWorkspaceActions() {
        let item = makeItem(
            id: "workspace:digest",
            origin: FileAreaOrigin.workspace,
            itemId: "digest",
            name: "note.txt",
            kind: FileAreaKind.text,
            pinned: true,
            capabilities: FileAreaCapabilities(
                canOpen: true,
                canCopy: false,
                canCopyText: true,
                canMarkup: false,
                canDragOut: true,
                canSaveToWorkspace: false,
                canReveal: true,
                canPin: true,
                canRemove: true,
                canDownload: false,
                canCancel: false
            )
        )

        XCTAssertEqual(FileAreaPresentation.contextActions(for: item).first, .copyText)
        XCTAssertTrue(FileAreaPresentation.contextActions(for: item).contains(.pin(true)))
        XCTAssertEqual(
            FileAreaPresentation.focusActions(for: item),
            [.open, .copyText, .reveal]
        )
    }

    func testRemoteContentOffersDownloadWithoutDuplicatingTheItem() {
        let item = makeItem(
            id: "workspace:remote",
            origin: FileAreaOrigin.workspace,
            itemId: "remote",
            name: "remote.pdf",
            kind: FileAreaKind.pdf,
            availability: FileAreaAvailability.remote,
            capabilities: FileAreaCapabilities(
                canOpen: false,
                canCopy: false,
                canCopyText: false,
                canMarkup: false,
                canDragOut: false,
                canSaveToWorkspace: false,
                canReveal: false,
                canPin: false,
                canRemove: true,
                canDownload: true,
                canCancel: false
            )
        )

        XCTAssertEqual(FileAreaPresentation.quickAction(for: item), .download)
        XCTAssertEqual(
            FileAreaPresentation.contextActions(for: item),
            [.download, .remove]
        )
    }

    func testTransferTaskActionsFollowThePhase() {
        let item = makeItem(
            id: "workspace:remote",
            origin: FileAreaOrigin.workspace,
            itemId: "remote",
            name: "remote.pdf",
            kind: FileAreaKind.pdf,
            availability: FileAreaAvailability.fetching,
            capabilities: FileAreaCapabilities(
                canOpen: false,
                canCopy: false,
                canCopyText: false,
                canMarkup: false,
                canDragOut: false,
                canSaveToWorkspace: false,
                canReveal: false,
                canPin: false,
                canRemove: true,
                canDownload: true,
                canCancel: true
            )
        )
        let waiting = task(item: item, phase: .waiting, transferredBytes: 0)
        let transferring = task(item: item, phase: .transferring, transferredBytes: 50)
        let failed = task(item: item, phase: .failed, transferredBytes: 0, failure: .connectionFailed)
        let cancelled = task(item: item, phase: .cancelled, transferredBytes: 0)

        XCTAssertEqual(FileAreaPresentation.quickAction(for: item, task: waiting), .cancelTransfer)
        XCTAssertEqual(FileAreaPresentation.quickAction(for: item, task: transferring), .cancelTransfer)
        XCTAssertEqual(FileAreaPresentation.quickAction(for: item, task: failed), .retry)
        XCTAssertEqual(FileAreaPresentation.quickAction(for: item, task: cancelled), .retry)
        XCTAssertEqual(
            FileAreaPresentation.statusTitle(for: item, language: .simplifiedChinese, task: waiting),
            ContractCopy.copyHubFilesStateWaiting.text(for: .simplifiedChinese)
        )
        XCTAssertEqual(
            FileAreaPresentation.statusTitle(for: item, language: .simplifiedChinese, task: transferring),
            "正在传输 50%"
        )
        XCTAssertEqual(
            FileAreaPresentation.statusTitle(for: item, language: .simplifiedChinese, task: cancelled),
            ContractCopy.copyHubFilesStateTransferCancelled.text(for: .simplifiedChinese)
        )
        XCTAssertEqual(
            FileAreaPresentation.transferFailureDetail(for: failed, language: .simplifiedChinese),
            ContractCopy.copyHubFilesErrorConnection.text(for: .simplifiedChinese)
        )
    }

    func testStatusIsWrittenAsWellAsColored() {
        let item = makeItem(
            id: "workspace:remote",
            origin: FileAreaOrigin.workspace,
            itemId: "remote",
            name: "remote.pdf",
            kind: FileAreaKind.pdf,
            availability: FileAreaAvailability.remote
        )

        XCTAssertEqual(
            FileAreaPresentation.statusTitle(for: item, language: .simplifiedChinese),
            ContractCopy.copyHubFilesStateOnOtherDevice.text(for: .simplifiedChinese)
        )
        XCTAssertTrue(
            FileAreaPresentation.accessibilityValue(
                for: item,
                url: nil,
                language: .simplifiedChinese
            ).contains(ContractCopy.copyHubFilesStateOnOtherDevice.text(for: .simplifiedChinese))
        )
    }

    func testFilterChoicesMapToTheSharedProjectionFilters() {
        XCTAssertEqual(FileAreaFilterChoice.all.filter, FileAreaFilter.all)
        XCTAssertEqual(FileAreaFilterChoice.screenshots.filter, FileAreaFilter.screenshots)
        XCTAssertEqual(FileAreaFilterChoice.files.filter, FileAreaFilter.files)
        XCTAssertEqual(FileAreaFilterChoice.text.filter, FileAreaFilter.text)
        XCTAssertEqual(FileAreaFilterChoice.transfers.filter, FileAreaFilter.transfers)
    }

    private func task(
        item: FileAreaItem,
        phase: WorkspaceTransferPhase,
        transferredBytes: Int64,
        failure: WorkspaceTransferFailure? = nil
    ) -> WorkspaceTransferTask {
        WorkspaceTransferTask(
            entryId: item.itemId,
            direction: .download,
            peerDeviceId: "iPhone",
            totalBytes: 100,
            phase: phase,
            transferredBytes: transferredBytes,
            failure: failure
        )
    }

    private func makeItem(
        id: String,
        origin: FileAreaOrigin,
        itemId: String,
        name: String,
        kind: FileAreaKind,
        availability: FileAreaAvailability = FileAreaAvailability.local,
        pinned: Bool = false,
        capabilities: FileAreaCapabilities = FileAreaCapabilities(
            canOpen: false,
            canCopy: false,
            canCopyText: false,
            canMarkup: false,
            canDragOut: false,
            canSaveToWorkspace: false,
            canReveal: false,
            canPin: false,
            canRemove: false,
            canDownload: false,
            canCancel: false
        )
    ) -> FileAreaItem {
        FileAreaItem(
            id: id,
            origin: origin,
            itemId: itemId,
            displayName: name,
            kind: kind,
            createdAtEpochSeconds: 0,
            byteSize: 0,
            originDeviceId: "",
            expiresAtEpochSeconds: 0,
            availability: availability,
            pinned: pinned,
            capabilities: capabilities
        )
    }
}

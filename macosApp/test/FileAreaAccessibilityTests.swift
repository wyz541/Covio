import SwiftUI
import XCTest
@testable import Covio

/// 文件区的键盘顺序与 VoiceOver 文案。
@MainActor
final class FileAreaAccessibilityTests: XCTestCase {
    private let order = ["focus", "a", "b", "c", "d", "e", "f", "g", "h"]

    func testTheFocusOrderIsRowFirst() {
        XCTAssertEqual(
            FileAreaKeyboardNavigation.order(
                selectedID: "focus",
                quietIDs: ["a", "b", "c", "d"]
            ),
            ["focus", "a", "b", "c", "d"]
        )
        XCTAssertEqual(
            FileAreaKeyboardNavigation.destination(.right, from: "b", order: order),
            "c"
        )
        XCTAssertEqual(
            FileAreaKeyboardNavigation.destination(.left, from: "e", order: order),
            "d"
        )
    }

    func testVerticalMovementKeepsFourColumnRows() {
        XCTAssertEqual(
            FileAreaKeyboardNavigation.destination(.down, from: "focus", order: order),
            "a"
        )
        XCTAssertEqual(
            FileAreaKeyboardNavigation.destination(.down, from: "a", order: order),
            "e"
        )
        XCTAssertEqual(
            FileAreaKeyboardNavigation.destination(.up, from: "d", order: order),
            "focus"
        )
        XCTAssertEqual(
            FileAreaKeyboardNavigation.destination(.up, from: "f", order: order),
            "b"
        )
    }

    func testRemovingAnItemMovesFocusToItsNeighbour() {
        XCTAssertEqual(
            FileAreaKeyboardNavigation.itemAfterRemoval("b", order: order),
            "c"
        )
        XCTAssertEqual(
            FileAreaKeyboardNavigation.itemAfterRemoval("h", order: order),
            "g"
        )
        XCTAssertNil(FileAreaKeyboardNavigation.itemAfterRemoval("focus", order: ["focus"]))
    }

    func testPromotingAnItemKeepsTheSameIdentityInTheFocusOrder() {
        let quiet = ["shot", "note"]
        let before = FileAreaKeyboardNavigation.order(selectedID: "text", quietIDs: quiet)
        let after = FileAreaKeyboardNavigation.order(selectedID: "shot", quietIDs: ["text", "note"])

        XCTAssertEqual(before.first, "text")
        XCTAssertEqual(after.first, "shot")
        XCTAssertEqual(after[0], "shot", "焦点卡沿用原格子的 id，提升时焦点不换对象")
    }

    func testReducedMotionUsesTheShorterFadeToken() {
        XCTAssertEqual(HubMotion.fileFocusSwitch, 0.12, accuracy: 0.001)
        XCTAssertEqual(HubMotion.fileFocusSwitchReduced, 0.08, accuracy: 0.001)
    }

    func testVoiceOverValueDescribesTypeSourceStatusAndActions() {
        let item = FileAreaItem(
            id: "workspace:remote",
            origin: FileAreaOrigin.workspace,
            itemId: "remote",
            displayName: "remote.pdf",
            kind: FileAreaKind.pdf,
            createdAtEpochSeconds: 0,
            byteSize: 100,
            originDeviceId: "iPhone",
            expiresAtEpochSeconds: 0,
            availability: FileAreaAvailability.fetching,
            pinned: false,
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
        let task = WorkspaceTransferTask(
            entryId: item.itemId,
            direction: .download,
            peerDeviceId: "iPhone",
            totalBytes: 100,
            phase: .transferring,
            transferredBytes: 62,
            failure: nil
        )

        let value = FileAreaPresentation.accessibilityValue(
            for: item,
            url: nil,
            language: .simplifiedChinese,
            task: task
        )

        XCTAssertTrue(value.contains("PDF"))
        XCTAssertTrue(value.contains("iPhone"))
        XCTAssertTrue(value.contains("正在传输 62%"))
        XCTAssertTrue(value.contains(ContractCopy.copyHubFilesActionCancelTransfer.text(for: .simplifiedChinese)))
        XCTAssertTrue(value.contains(ContractCopy.copyHubFilesActionRemove.text(for: .simplifiedChinese)))
    }

    func testTransferFailureStillExposesARecoveryAction() {
        let item = FileAreaItem(
            id: "workspace:failed",
            origin: FileAreaOrigin.workspace,
            itemId: "failed",
            displayName: "failed.pdf",
            kind: FileAreaKind.pdf,
            createdAtEpochSeconds: 0,
            byteSize: 100,
            originDeviceId: "iPhone",
            expiresAtEpochSeconds: 0,
            availability: FileAreaAvailability.remote,
            pinned: false,
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
        let task = WorkspaceTransferTask(
            entryId: item.itemId,
            direction: .download,
            peerDeviceId: "iPhone",
            totalBytes: 100,
            phase: .failed,
            transferredBytes: 0,
            failure: .connectionFailed
        )

        XCTAssertEqual(
            FileAreaPresentation.quickAction(for: item, task: task),
            .retry
        )
        XCTAssertEqual(
            FileAreaPresentation.contextActions(for: item, task: task).last,
            .remove
        )
    }
}

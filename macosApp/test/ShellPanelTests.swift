import AppKit
import XCTest
@testable import Covio

/// `ShellPanel` 系列的窗口配置测试。
///
/// 这些断言把 M1 的 NSPanel 配置表逐条钉住。其中 `level` 那一条最关键：
/// `isFloatingPanel = true` 会把 `level` 静默重置为 `.floating`（3），
/// 旧版宿主的 `FLOATING_WINDOW_LEVEL = 3` 就是踩了这个坑。
/// 见 `docs/adr/adr-0001-macos-ui-swiftui.md` 实测 9。
@MainActor
final class ShellPanelTests: XCTestCase {
    private let testRect = CGRect(x: 100, y: 700, width: 960, height: 352)

    func testHubPanelLevelIsAboveTheMenuBar() {
        let panel = HubPanel(rect: testRect)
        defer { panel.orderOut(nil) }

        // 系统菜单栏是 24。25 刚好高于它。
        XCTAssertEqual(panel.level.rawValue, 25)
        XCTAssertEqual(panel.level, .statusBar)
    }

    func testHubPanelStylingMaskIsNonActivatingAndBorderless() {
        let panel = HubPanel(rect: testRect)
        defer { panel.orderOut(nil) }

        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    }

    func testCollectionBehaviorMatchesTheLegacyHostPlusIgnoresCycle() {
        let panel = HubPanel(rect: testRect)
        defer { panel.orderOut(nil) }

        // 旧版宿主的 PANEL_COLLECTION_BEHAVIOR 是 0x51，
        // 即 canJoinAllSpaces | stationary | fullScreenAuxiliary。这里再加 ignoresCycle。
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
    }

    func testHubPanelDoesNotHideOnDeactivate() {
        let panel = HubPanel(rect: testRect)
        defer { panel.orderOut(nil) }

        // 用户编辑输入或拖动文件时 Hub 不自动收起。
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isMovable)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertFalse(panel.isOpaque)
    }

    /// `.nonactivatingPanel` 加 `canBecomeKey` 是 M4 粘贴回填的前提：
    /// 面板能收键盘，但前台应用不变。
    func testHubPanelCanBecomeKeyButTheHotZoneCannot() {
        let hub = HubPanel(rect: testRect)
        let hotZone = HotZonePanel(rect: CGRect(x: 0, y: 1000, width: 185, height: 32))
        defer {
            hub.orderOut(nil)
            hotZone.orderOut(nil)
        }

        XCTAssertTrue(hub.canBecomeKey)
        XCTAssertFalse(hotZone.canBecomeKey)
    }

    func testBothPanelsAcceptMouseEvents() {
        let hub = HubPanel(rect: testRect)
        let hotZone = HotZonePanel(rect: CGRect(x: 0, y: 1000, width: 185, height: 32))
        defer {
            hub.orderOut(nil)
            hotZone.orderOut(nil)
        }

        // 热区靠自己的 tracking area 报告指针进出，必须能收鼠标事件。
        XCTAssertFalse(hub.ignoresMouseEvents)
        XCTAssertFalse(hotZone.ignoresMouseEvents)
    }

    /// Escape 收起 Hub。
    func testEscapeAsksTheControllerToCollapse() {
        let panel = HubPanel(rect: testRect)
        defer { panel.orderOut(nil) }

        var cancelled = false
        panel.onCancel = { cancelled = true }

        panel.cancelOperation(nil)
        XCTAssertTrue(cancelled)
    }

    /// 键盘上的 Escape 走 `keyDown`，与 `cancelOperation` 是两条入口。
    /// 面板是 `.nonactivatingPanel`，键盘事件只能从这条入口进来。
    func testEscapeKeyDownAsksTheControllerToCollapse() throws {
        let panel = HubPanel(rect: testRect)
        defer { panel.orderOut(nil) }

        var cancelled = false
        panel.onCancel = { cancelled = true }

        panel.keyDown(with: try keyEvent(keyCode: 53))
        XCTAssertTrue(cancelled)
    }

    /// 别的按键不该被当成 Escape。
    func testAnotherKeyDoesNotAskTheControllerToCollapse() throws {
        let panel = HubPanel(rect: testRect)
        defer { panel.orderOut(nil) }

        var cancelled = false
        panel.onCancel = { cancelled = true }

        panel.keyDown(with: try keyEvent(keyCode: 0))
        XCTAssertFalse(cancelled, "只有 Escape 走 onCancel")
    }

    private func keyEvent(keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}

import AppKit
import XCTest
@testable import Covio

/// Covio 使用一个原生菜单栏状态项。
@MainActor
final class StatusItemControllerTests: XCTestCase {
    func testTheNativeStatusItemIsVisible() {
        let controller = StatusItemController(shell: NotchShellController())
        defer { controller.tearDown() }

        XCTAssertTrue(controller.isVisible)
    }

    /// 状态栏菜单中的设置项接到独立窗口入口。
    func testTheStatusMenuWiresSettingsToTheFixedAction() throws {
        let shell = NotchShellController()
        let controller = StatusItemController(shell: shell)
        defer { controller.tearDown() }

        var didOpenSettings = false
        var receivedHit: SettingsSearchHit?
        shell.onOpenSettings = { hit in
            didOpenSettings = true
            receivedHit = hit
        }

        let item = try XCTUnwrap(
            controller.menu.items.first { $0.title == ContractCopy.copyTrayActionSettings.text }
        )
        let action = try XCTUnwrap(item.action)

        XCTAssertTrue(item.target === controller)
        XCTAssertEqual(NSStringFromSelector(action), "openSettings")

        item.target?.perform(action, with: item)
        XCTAssertTrue(didOpenSettings)
        XCTAssertNil(receivedHit)
    }
}

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

    /// 状态栏菜单中的设置项直接接到固定页面入口。
    func testTheStatusMenuWiresSettingsToTheFixedAction() throws {
        let controller = StatusItemController(shell: NotchShellController())
        defer { controller.tearDown() }

        let item = try XCTUnwrap(
            controller.menu.items.first { $0.title == ContractCopy.copyTrayActionSettings.text }
        )
        let action = try XCTUnwrap(item.action)

        XCTAssertTrue(item.target === controller)
        XCTAssertEqual(NSStringFromSelector(action), "openSettings")
    }
}

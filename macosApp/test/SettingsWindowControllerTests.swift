import AppKit
import XCTest
@testable import Covio

/// 独立设置窗口与 Dock 激活策略。
@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    override func tearDown() {
        AppDelegate.current?.settingsWindowController?.window?.orderOut(nil)
    }

    private func controller() throws -> SettingsWindowController {
        let appDelegate = try XCTUnwrap(AppDelegate.current)
        return try XCTUnwrap(appDelegate.settingsWindowController)
    }

    func testBundleAndApplicationUseRegularActivation() {
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertFalse(
            Bundle(for: AppDelegate.self).object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false
        )
    }

    func testClosingTheLastWindowDoesNotTerminateCovio() throws {
        let appDelegate = try XCTUnwrap(AppDelegate.current)
        XCTAssertFalse(appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
    }

    func testShowingSettingsReusesOneStandardWindow() throws {
        let controller = try controller()
        controller.show()
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(controller.isOpen)
        XCTAssertEqual(window.level, .normal)
        let settingsTitles = AppLanguage.allCases.map {
            ContractCopy.copyHubTabSettings.text(for: $0)
        }
        XCTAssertTrue(settingsTitles.contains(window.title))
        XCTAssertFalse(window.title.hasSuffix("…"))
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
        XCTAssertEqual(window.tabbingMode, .disallowed)
        XCTAssertEqual(window.identifier, SettingsWindowController.windowIdentifier)

        controller.show()
        XCTAssertTrue(controller.window === window, "重复打开必须复用同一个设置窗口")
    }

    func testSearchHitSelectsTheMatchingSectionAndRow() throws {
        let controller = try controller()
        let hit = try XCTUnwrap(
            SettingsSearchIndex.search("休眠", language: .simplifiedChinese)
                .first { $0.rowID == SettingsRowID.generalSleepMode }
        )

        controller.show(reveal: hit)
        let deadline = Date().addingTimeInterval(0.1)
        while controller.scrollTarget != hit.rowID, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(controller.selectedSection, hit.section)
        XCTAssertEqual(controller.scrollTarget, hit.rowID)
    }

    func testDockReopenShowsTheWorkbenchWhenNoPrimaryWindowIsOpen() throws {
        let appDelegate = try XCTUnwrap(AppDelegate.current)
        appDelegate.settingsWindowController?.window?.orderOut(nil)
        let hub = try XCTUnwrap(NSApp.windows.compactMap { $0 as? HubPanel }.first)

        XCTAssertTrue(appDelegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        let deadline = Date().addingTimeInterval(1)
        while !hub.isVisible, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertTrue(hub.isVisible)
        hub.orderOut(nil)
    }
}

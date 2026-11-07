import AppKit
import XCTest
@testable import Covio

/// 原生 Settings 场景、工具栏分页与 Dock 激活策略。
@MainActor
final class CovioSettingsViewTests: XCTestCase {
    override func tearDown() {
        AppDelegate.current?.settingsWindow?.orderOut(nil)
    }

    private func appDelegate() throws -> AppDelegate {
        try XCTUnwrap(AppDelegate.current)
    }

    private func openSettings() throws -> NSWindow {
        let appDelegate = try appDelegate()
        appDelegate.settingsChrome.select(.overview)
        XCTAssertTrue(appDelegate.openSettingsFromApplicationMenu())
        waitUntil { appDelegate.settingsWindow?.isVisible == true }
        return try XCTUnwrap(appDelegate.settingsWindow)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    func testBundleAndApplicationUseRegularActivation() {
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertFalse(
            Bundle(for: AppDelegate.self).object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false
        )
    }

    func testClosingTheLastWindowDoesNotTerminateCovio() throws {
        let appDelegate = try appDelegate()
        XCTAssertFalse(appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
    }

    func testSettingsUseTheNativeWindowAndToolbar() throws {
        let appDelegate = try appDelegate()
        let window = try openSettings()
        waitUntil { window.toolbar?.allowsUserCustomization == false }
        let language = try XCTUnwrap(appDelegate.runtime).language

        XCTAssertFalse(window is NSPanel)
        XCTAssertEqual(window.level, .normal)
        XCTAssertEqual(window.identifier, SettingsWindowMetrics.identifier)
        XCTAssertEqual(window.title, ContractCopy.copyPageOverviewTitle.text(for: language))
        XCTAssertTrue(window.toolbar?.isVisible == true)
        XCTAssertFalse(window.toolbar?.allowsUserCustomization ?? true)
        XCTAssertNotEqual(window.standardWindowButton(.miniaturizeButton)?.isEnabled, true)
        XCTAssertNotEqual(window.standardWindowButton(.zoomButton)?.isEnabled, true)
    }

    func testWindowTitleTracksTheSelectedPane() throws {
        let appDelegate = try appDelegate()
        let window = try openSettings()
        let language = try XCTUnwrap(appDelegate.runtime).language
        appDelegate.settingsChrome.select(.battery)
        appDelegate.showSettingsWindow()
        waitUntil {
            window.title == ContractCopy.copyPageBatteryTitle.text(for: language)
        }

        XCTAssertEqual(
            window.title,
            ContractCopy.copyPageBatteryTitle.text(for: language)
        )
    }

    func testSearchHitSelectsTheMatchingSectionAndRow() throws {
        let appDelegate = try appDelegate()
        let hit = try XCTUnwrap(
            SettingsSearchIndex.search("休眠", language: .simplifiedChinese)
                .first { $0.rowID == SettingsRowID.generalSleepMode }
        )

        XCTAssertTrue(appDelegate.showSettingsWindow(reveal: hit))
        waitUntil { appDelegate.settingsChrome.scrollTarget == hit.rowID }

        XCTAssertEqual(appDelegate.settingsChrome.settingsSection, hit.section)
        XCTAssertEqual(appDelegate.settingsChrome.scrollTarget, hit.rowID)
    }

    func testDockReopenShowsTheWorkbenchWhenSettingsIsClosed() throws {
        let appDelegate = try appDelegate()
        appDelegate.settingsWindow?.orderOut(nil)

        XCTAssertTrue(appDelegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        var hub: HubPanel?
        waitUntil {
            hub = NSApp.windows.compactMap { $0 as? HubPanel }.first
            return hub?.isVisible == true
        }

        XCTAssertNotNil(hub)
        XCTAssertEqual(hub?.isVisible, true)
        hub?.orderOut(nil)
    }
}

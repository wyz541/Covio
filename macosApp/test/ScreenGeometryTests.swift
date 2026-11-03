import XCTest
@testable import Covio

/// `ScreenGeometry` 的几何测试。
///
/// 用手写的屏幕数值，不依赖运行测试的机器。
/// 数值取自 M0 在本机内建视网膜屏上的实测：1728 × 1117，顶部安全区 32 点，
/// 刘海占 x 从 771.5 到 956.5。见 `docs/adr/adr-0001-macos-ui-swiftui.md` 实测 8。
final class ScreenGeometryTests: XCTestCase {
    /// 本机实测的刘海屏。
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1085),
        safeAreaTop: 32,
        notch: CGRect(x: 771.5, y: 1085, width: 185, height: 32)
    )

    /// 一台 1920 × 1080 的非刘海屏。
    private let notchless = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
        safeAreaTop: 0,
        notch: nil
    )

    /// 一台 1024 × 768 的非刘海屏。CI 运行器的屏幕就是这个尺寸。
    private let smallNotchless = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1024, height: 768),
        visibleFrame: CGRect(x: 0, y: 0, width: 1024, height: 744),
        safeAreaTop: 0,
        notch: nil
    )

    // MARK: - 刘海屏

    func testNotchedHotZoneIsTheNotchItself() {
        XCTAssertTrue(notched.hasNotch)
        XCTAssertEqual(notched.hotZoneRect, notched.notch)
    }

    func testNotchedPanelHangsFromTheScreenTop() {
        XCTAssertEqual(notched.panelTop, 1117)
        XCTAssertEqual(notched.panelTopInset, 32)
    }

    func testNotchedExpandedRectIsCenteredAndTopAligned() {
        let rect = notched.expandedRect
        XCTAssertEqual(rect.width, 960)
        XCTAssertEqual(rect.maxY, 1117)
        XCTAssertEqual(rect.midX, 864)
        // 高度是顶部安全区加固定外壳内容高度。
        XCTAssertEqual(rect.height, 32 + notched.shellContentHeight, accuracy: 0.001)
    }

    func testNotchedCollapsedRectMatchesTheNotch() {
        let rect = notched.collapsedRect
        XCTAssertEqual(rect.size, notched.hotZoneRect.size)
        XCTAssertEqual(rect.maxY, 1117)
        XCTAssertEqual(rect.midX, 864)
    }

    /// 面板矩形必须完全落在屏幕内，否则窗口会跑到屏幕外面。
    func testExpandedRectStaysInsideTheScreen() {
        for geometry in [notched, notchless] {
            let rect = geometry.expandedRect
            XCTAssertTrue(geometry.frame.contains(rect), "面板矩形超出了屏幕")
        }
    }

    /// 展开矩形只读取固定外壳高度，不读取页面内容。
    func testExpandedRectUsesTheFixedShellHeight() {
        for geometry in [notched, notchless, smallNotchless] {
            XCTAssertEqual(
                geometry.expandedRect.height,
                geometry.panelTopInset + geometry.shellContentHeight,
                accuracy: 0.001
            )
            XCTAssertEqual(
                geometry.shellPlateStackHeight,
                geometry.shellContentHeight - HubMetrics.plateTopInset,
                accuracy: 0.001
            )
        }
    }

    // MARK: - 非刘海屏

    func testNotchlessHotZoneSitsBelowTheMenuBar() {
        XCTAssertFalse(notchless.hasNotch)
        let zone = notchless.hotZoneRect
        XCTAssertEqual(zone.width, HubMetrics.notchlessHotZoneWidth)
        XCTAssertEqual(zone.height, HubMetrics.notchlessHotZoneHeight)
        // 上沿贴菜单栏下沿。
        XCTAssertEqual(zone.maxY, notchless.visibleFrame.maxY)
        XCTAssertEqual(zone.midX, 960)
    }

    func testNotchlessPanelStartsAtTheMenuBarBottom() {
        XCTAssertEqual(notchless.panelTop, 1055)
        XCTAssertEqual(notchless.panelTopInset, 0)
        XCTAssertEqual(notchless.expandedRect.maxY, 1055)
        XCTAssertEqual(notchless.expandedRect.height, notchless.shellContentHeight, accuracy: 0.001)
    }

    // MARK: - 全屏 Space

    func testMenuBarVisibilityDrivesTheHotZoneRule() {
        XCTAssertTrue(notched.isMenuBarVisible)
        XCTAssertTrue(notchless.isMenuBarVisible)

        // 全屏 Space 里菜单栏自动隐藏，可见区等于完整区。此时要隐藏热区。
        let fullScreen = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            safeAreaTop: 0,
            notch: nil
        )
        XCTAssertFalse(fullScreen.isMenuBarVisible)
    }

    // MARK: - 窄屏与非刘海屏的组合

    /// 窄屏上面板比面板宽度窄，取「屏幕宽度减 80」。
    func testSmallScreenNarrowsThePanelBelowTheCardWidth() {
        XCTAssertEqual(smallNotchless.expandedRect.width, 944)
        XCTAssertLessThan(smallNotchless.expandedRect.width, HubMetrics.panelWidth)
    }

    /// 小屏只收缩外壳，不改变固定外壳规则。
    func testSmallScreenClampsTheShellToTheAvailableHeight() {
        XCTAssertEqual(
            smallNotchless.shellContentHeight,
            HubMetrics.hubMaxHeight(screenHeight: smallNotchless.frame.height),
            accuracy: 0.001
        )
    }

    /// 非刘海屏的面板挂在菜单栏下方，所以屏幕顶部中央在面板之外。
    ///
    /// 这条是 CI 的失败根因。运行器是无刘海屏，指针放在屏幕顶部中央时
    /// 落在菜单栏上，不在面板里，于是状态机立刻走 EXIT。
    /// 控制器测试的指针位置因此必须从展开矩形推导，不能写死屏幕坐标。
    func testTheScreenTopCenterIsOutsideANotchlessPanel() {
        let rect = smallNotchless.expandedRect
        let topCenter = CGPoint(x: smallNotchless.frame.midX, y: smallNotchless.frame.maxY - 4)

        XCTAssertFalse(rect.contains(topCenter), "非刘海屏的面板不该盖住屏幕顶部中央")
        XCTAssertGreaterThan(topCenter.y, rect.maxY)
    }

    /// 面板下方要留出屏幕内的空间，指针才能放在面板外。
    func testThePanelLeavesRoomBelowItOnASmallScreen() {
        let rect = smallNotchless.expandedRect
        let below = CGPoint(x: rect.midX, y: rect.minY - 20)

        XCTAssertFalse(rect.contains(below))
        XCTAssertFalse(smallNotchless.hotZoneRect.contains(below), "面板下方不该落在热区里")
        XCTAssertTrue(smallNotchless.frame.contains(below), "面板下方的指针位置要留在屏幕内")
    }

    // MARK: - 宽度限制

    func testHubWidthRespectsMinimumAndMaximum() {
        // 宽屏：用卡片宽度 960。
        XCTAssertEqual(HubMetrics.hubWidth(screenWidth: 1728), 960)
        // 窄屏：屏幕宽度减 80 小于 960，取屏幕宽度减 80。
        XCTAssertEqual(HubMetrics.hubWidth(screenWidth: 900), 820)
        // 极窄屏：不低于最小宽度 720。
        XCTAssertEqual(HubMetrics.hubWidth(screenWidth: 700), 720)
    }

    func testHubMaxHeightLeavesRoomForTheDesktop() {
        XCTAssertEqual(HubMetrics.hubMaxHeight(screenHeight: 1117), 997)
        XCTAssertEqual(HubMetrics.hubMaxHeight(screenHeight: 100), 0)
    }

    // MARK: - 真实屏幕

    /// 真实屏幕上算出的热区必须落在该屏幕内。
    func testLiveScreenGeometryIsSelfConsistent() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let geometry = ScreenGeometry(screen: screen)

        let zone = geometry.hotZoneRect
        XCTAssertTrue(screen.frame.contains(zone), "热区超出了屏幕")
        XCTAssertTrue(screen.frame.contains(geometry.expandedRect), "面板矩形超出了屏幕")
        XCTAssertEqual(geometry.hasNotch, geometry.notch != nil)

        // 把实测值打出来，方便与 M0 的记录比对。
        print("""
        [M1] screen frame=\(screen.frame) visible=\(screen.visibleFrame)
        [M1] safeAreaTop=\(geometry.safeAreaTop) notch=\(String(describing: geometry.notch))
        [M1] hotZone=\(zone) expandedRect=\(geometry.expandedRect)
        [M1] menuBarVisible=\(geometry.isMenuBarVisible)
        """)
    }
}

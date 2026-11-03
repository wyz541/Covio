import AppKit
import XCTest
import kmpDomain
@testable import Covio

/// `NotchShellController` 的端到端状态测试。
///
/// 这些测试跑在真实的 `NSPanel` 上，只把指针位置换成固定值，
/// 所以不需要真的移动用户的鼠标。见 `NotchShellController.init(pointerLocation:)`。
///
/// 注意：面板的 tracking area 仍然接真实的鼠标事件。测试运行期间如果指针
/// 恰好移进或移出热区与面板，会插入额外事件，断言因此可能失败。
/// 跑这个套件时不要动鼠标。
///
/// 指针与期望值都从 `ScreenGeometry` 推导，不写死屏幕坐标。
/// 面板几何随屏幕变化：刘海屏贴顶边，非刘海屏让开菜单栏；窄屏收窄宽度。
/// CI 运行器是 1024 × 768 的无刘海屏，写死坐标的断言在那里会失败。
@MainActor
final class NotchShellControllerTests: XCTestCase {
    /// 展开态 Hub 面板在屏幕坐标里的矩形。
    ///
    /// 指针位置与宽度期望都由它推导，这样断言与实现看的是同一份几何。
    private func hubPanelRect() throws -> CGRect {
        let screen = try XCTUnwrap(NSScreen.main)
        return ScreenGeometry(screen: screen).expandedRect
    }

    /// 指针固定在 Hub 面板内部靠上处。那里一定落在面板矩形内。
    private func controllerWithPointerInsideHub() throws -> NotchShellController {
        let rect = try hubPanelRect()
        let point = CGPoint(x: rect.midX, y: rect.maxY - 4)
        return NotchShellController(pointerLocation: { point })
    }

    /// 指针固定在面板正下方。那里在面板矩形之外，也在热区之外。
    private func controllerWithPointerAway() throws -> NotchShellController {
        let rect = try hubPanelRect()
        let point = CGPoint(x: rect.midX, y: rect.minY - 20)
        return NotchShellController(pointerLocation: { point })
    }

    /// 等到条件成立。
    ///
    /// 不用固定等待。机器被别的编译占满时，动画计时器与等待窗口一起延后，
    /// 固定等待会报出与实现无关的失败，本机已经误报过三次。
    /// 轮询仍然有上限：状态一直不成立时照样失败。
    private func waitUntil(
        _ message: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(condition(), message, file: file, line: line)
    }

    // MARK: - 启动

    func testStartCreatesOneHotZonePerScreenAndKeepsTheHubHidden() throws {
        let controller = try controllerWithPointerAway()
        controller.start()
        defer { controller.stop() }

        XCTAssertEqual(controller.state, .hidden)
        XCTAssertEqual(controller.hotZoneRects.count, NSScreen.screens.count)
        // 面板先按展开矩形建好，但不在屏幕上。
        XCTAssertFalse(controller.isHubPanelOnScreen)
        // 窄屏上面板比 panelWidth 窄，所以比展开矩形，不比 panelWidth。
        let expectedWidth = try hubPanelRect().width
        XCTAssertEqual(controller.hubPanelFrame?.width, expectedWidth)
        XCTAssertLessThanOrEqual(expectedWidth, HubMetrics.panelWidth)
    }

    /// 非刘海屏降级热区：每块屏幕的热区都必须落在该屏幕内，且贴在该屏幕顶部。
    func testHotZonesStayInsideTheirScreens() throws {
        let controller = try controllerWithPointerAway()
        controller.start()
        defer { controller.stop() }

        for (index, rect) in controller.hotZoneRects.enumerated() {
            let screen = NSScreen.screens[index]
            XCTAssertTrue(screen.frame.contains(rect), "第 \(index) 块屏幕的热区超出了屏幕")
            // 热区贴在屏幕顶部：从顶边往下不超过一条菜单栏加一点余量。
            XCTAssertLessThan(screen.frame.maxY - rect.minY, 64, "热区离屏幕顶部太远")
        }
    }

    // MARK: - 展开与收起

    func testHoverOpensTheHubThenBecomesActive() throws {
        let controller = try controllerWithPointerInsideHub()
        controller.start()
        defer { controller.stop() }

        controller.show()
        // 合同路径 HIDDEN → HOVER。
        XCTAssertEqual(controller.state, .hover)
        XCTAssertTrue(controller.isHubPanelOnScreen, "HOVER 时面板就应该在屏幕上")

        // 展开动画结束后进入 OPEN，指针在面板里所以紧接着进入 ACTIVE。
        waitUntil("展开后应该进入 ACTIVE") { controller.state == .active }
    }

    /// 页签和编辑模式只改变内容，不改变固定外壳。
    func testPaneAndEditingChangesKeepThePanelFrame() throws {
        let controller = try controllerWithPointerInsideHub()
        controller.start()
        defer { controller.stop() }

        controller.show()
        waitUntil("展开后应该进入 ACTIVE") { controller.state == .active }
        let frame = try XCTUnwrap(controller.hubPanelFrame)

        controller.workbench.destination = .home
        controller.workbench.performPageAction()
        XCTAssertTrue(controller.workbench.isEditing)
        XCTAssertEqual(controller.hubPanelFrame, frame, "编辑模式不能改变外壳尺寸")

        for tab in HubTab.allCases where controller.workbench.open(tab) {
            XCTAssertEqual(controller.hubPanelFrame, frame, "切到 \(tab.rawValue) 不能改变外壳尺寸")
        }
    }

    /// 每次展开都先禁用导航 hover，面板收起时立即清理保护。
    func testExpansionStartsTheInitialHoverProtection() throws {
        let controller = try controllerWithPointerInsideHub()
        controller.start()
        defer { controller.stop() }

        controller.show()
        XCTAssertTrue(controller.workbench.isInitialHoverProtected)
        waitUntil("展开后应该进入 ACTIVE") { controller.state == .active }
        XCTAssertTrue(controller.workbench.isInitialHoverProtected, "展开完成后还要保留 0.5 秒")

        controller.requestCollapse()
        waitUntil("收起后应该回到 HIDDEN") { controller.state == .hidden }
        XCTAssertFalse(controller.workbench.isInitialHoverProtected)
    }

    /// Popover 打开后，指针移出 Hub 也不启动自动收起。
    func testPopoverKeepsTheHubExpandedPastThePointerExitDelay() throws {
        let rect = try hubPanelRect()
        let inside = CGPoint(x: rect.midX, y: rect.maxY - 4)
        let outside = CGPoint(x: rect.midX, y: rect.minY - 20)
        var pointer = inside
        let controller = NotchShellController(pointerLocation: { pointer })
        controller.start()
        defer { controller.stop() }

        controller.show()
        waitUntil("展开后应该进入 ACTIVE") { controller.state == .active }

        controller.popoverCoordinator.setPresented(true, id: "test-popover")
        pointer = outside
        controller.pointerExitedHub()

        let deadline = Date().addingTimeInterval(HubMotion.pointerExitCollapseDelay + 0.3)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertNotEqual(controller.state, .exit, "Popover 打开时不能自动收起")

        controller.popoverCoordinator.setPresented(false, id: "test-popover")
        waitUntil("关闭 Popover 后应恢复自动收起") { controller.state == .hidden }
    }

    /// 显式收起先关闭 Popover，再开始 Hub 的收起动画。
    func testExplicitCollapseWaitsForThePopoverToClose() throws {
        let controller = try controllerWithPointerInsideHub()
        controller.start()
        defer { controller.stop() }

        controller.show()
        waitUntil("展开后应该进入 ACTIVE") { controller.state == .active }
        controller.popoverCoordinator.setPresented(true, id: "test-popover")

        controller.requestCollapse()
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(controller.popoverCoordinator.dismissalRequest, 1)

        controller.popoverCoordinator.setPresented(false, id: "test-popover")
        waitUntil("Popover 关闭后应执行显式收起") { controller.state == .exit }
        waitUntil("收起动画结束后应回到 HIDDEN") { controller.state == .hidden }
    }

    func testRequestingCollapseReturnsToHidden() throws {
        let controller = try controllerWithPointerInsideHub()
        controller.start()
        defer { controller.stop() }

        controller.show()
        waitUntil("展开后应该进入 ACTIVE") { controller.state == .active }

        controller.requestCollapse()
        XCTAssertEqual(controller.state, .exit)

        waitUntil("收起后应该回到 HIDDEN") { controller.state == .hidden }
        XCTAssertFalse(controller.isHubPanelOnScreen, "收起后面板应该离开屏幕")
    }

    /// Control+Option+T 打开或收起。
    func testToggleOpensAndCloses() throws {
        let controller = try controllerWithPointerInsideHub()
        controller.start()
        defer { controller.stop() }

        controller.toggle()
        XCTAssertEqual(controller.state, .hover)

        controller.toggle()
        XCTAssertEqual(controller.state, .exit)

        waitUntil("收起后应该回到 HIDDEN") { controller.state == .hidden }
    }

    /// 手势打开时指针通常不在面板里。工作台必须保持展开，等用户操作。
    func testGesturePresentationStaysOpenWhilePointerIsOutside() throws {
        let controller = try controllerWithPointerAway()
        controller.start()
        defer { controller.stop() }

        controller.showFromGesture()
        waitUntil("手势打开后应该进入 OPEN") { controller.state == .open }

        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        XCTAssertEqual(controller.state, .open)
        XCTAssertTrue(controller.isHubPanelOnScreen)

        controller.requestCollapse()
        waitUntil("显式收起后应该回到 HIDDEN") { controller.state == .hidden }
    }

    /// 面板出现时指针已经不在面板里，应该立刻收起，不留一个卡住的 Hub。
    func testHubCollapsesWhenThePointerIsOutside() throws {
        let controller = try controllerWithPointerAway()
        controller.start()
        defer { controller.stop() }

        controller.show()
        // 面板出现后立刻自查指针位置，发现不在面板里就走 EXIT。
        XCTAssertEqual(controller.state, .exit)

        waitUntil("收起后应该回到 HIDDEN") { controller.state == .hidden }
        XCTAssertFalse(controller.isHubPanelOnScreen)
    }

    // MARK: - 面板几何

    /// 面板显示在指针所在屏幕，且锚定顶部中央。
    func testPanelLandsOnThePointerScreen() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let controller = try controllerWithPointerInsideHub()
        controller.start()
        defer { controller.stop() }

        controller.show()
        let frame = try XCTUnwrap(controller.hubPanelFrame)
        let expected = ScreenGeometry(screen: screen).expandedRect

        XCTAssertEqual(frame.midX, expected.midX, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, expected.maxY, accuracy: 0.5)
        XCTAssertEqual(frame.width, expected.width, accuracy: 0.5)
    }

    /// 收起后热区面板回到屏幕上，Hub 让位。
    func testHotZoneComesBackAfterCollapse() throws {
        let controller = try controllerWithPointerInsideHub()
        controller.start()
        defer { controller.stop() }

        controller.show()
        waitUntil("展开后应该进入 ACTIVE") { controller.state == .active }
        controller.requestCollapse()
        waitUntil("收起后应该回到 HIDDEN") { controller.state == .hidden }

        // 状态回到 HIDDEN 后热区重新可用。
        XCTAssertTrue(controller.hotZoneRects.count > 0)
    }

    // MARK: - 内容态

    /// 内容区状态与面板状态正交。M1 只驱动到 READY。
    func testOutputStateIsCollapsedWhileHiddenAndReadyWhenActive() throws {
        let controller = try controllerWithPointerInsideHub()
        controller.start()
        defer { controller.stop() }

        XCTAssertEqual(controller.outputState, .collapsed)

        controller.show()
        waitUntil("展开后应该进入 ACTIVE") { controller.state == .active }
        XCTAssertEqual(controller.outputState, .ready)

        controller.requestCollapse()
        XCTAssertEqual(controller.outputState, .collapsed)
    }

    func testSelectingATabDoesNotChangeTheHubState() throws {
        let controller = try controllerWithPointerAway()
        controller.start()
        defer { controller.stop() }

        controller.workbench.select(paneID: PaneKind.files.defaultId)
        XCTAssertEqual(controller.state, .hidden)
    }

    /// 编辑模式里不排收起计时。拖卡片时指针划出面板不算「用户想走」。
    func testEditingKeepsThePanelOpenWhenThePointerLeaves() throws {
        let controller = try controllerWithPointerInsideHub()
        controller.start()
        defer { controller.stop() }

        controller.workbench.isEditing = true
        controller.show()
        waitUntil("展开后应该进入 ACTIVE") { controller.state == .active }

        // 指针离开面板。非编辑态下这里会排一个收起计时。
        controller.pointerExitedHub()
        XCTAssertNotEqual(controller.state, .exit, "编辑模式里不该开始收起")
    }

    /// 编辑模式里第一次请求收起先退出编辑，面板不动。
    func testCollapseRequestLeavesEditingFirst() throws {
        let controller = try controllerWithPointerInsideHub()
        controller.start()
        defer { controller.stop() }

        controller.workbench.isEditing = true
        controller.show()
        waitUntil("展开后应该进入 ACTIVE") { controller.state == .active }

        controller.requestCollapse()
        XCTAssertFalse(controller.workbench.isEditing)
        XCTAssertEqual(controller.state, .active, "第一次请求只退出编辑，不收起面板")

        controller.requestCollapse()
        XCTAssertEqual(controller.state, .exit, "第二次请求才真的收起")
    }

    // MARK: - 热区的假离开

    /// 面板盖住热区时那次「离开」不能上报。
    ///
    /// 这条挂过：面板一展开就盖住热区（面板 960 × 547 包住热区那一条 186 × 32），
    /// 热区收到「离开」，状态机把刚展开的面板收回去，热区重新露出来又收到「进入」。
    /// 指针停着不动，面板每秒开关四次。真机实测 3 秒采样 24 次：开 11 次关 13 次。
    func testTheHotZoneStaysQuietWhileThePanelCoversIt() {
        XCTAssertFalse(
            NotchShellController.shouldReportHotZoneExit(hubVisible: true, pointerInsideHub: true),
            "面板盖着热区，这次「离开」是面板挡出来的，上报会把刚展开的面板收回去"
        )
    }

    /// 面板收起后热区的「离开」是真离开，要上报。
    func testTheHotZoneReportsARealExit() {
        XCTAssertTrue(
            NotchShellController.shouldReportHotZoneExit(hubVisible: false, pointerInsideHub: false),
            "面板不在屏幕上，指针离开热区就是走开了，不上报会留下一个收不掉的挂帘"
        )
    }

    /// 面板可见但指针已经在面板外：这次「离开」要上报。
    func testTheHotZoneReportsAnExitFromOutsideThePanel() {
        XCTAssertTrue(
            NotchShellController.shouldReportHotZoneExit(hubVisible: true, pointerInsideHub: false),
            "指针在面板外，热区报的离开是真的"
        )
    }

    /// 面板没上屏时，矩形盖着热区也不算数。
    ///
    /// 面板窗口建好就一直存在，`orderOut` 只是不显示，矩形照样包含热区那一片。
    /// 只看矩形不看可见性的话，收起态下热区永远不报离开。
    func testTheHotZoneReportsAnExitWhileThePanelIsOffScreen() {
        XCTAssertTrue(
            NotchShellController.shouldReportHotZoneExit(hubVisible: false, pointerInsideHub: true),
            "面板没上屏，矩形盖着热区也不算数"
        )
    }

    // MARK: - 菜单栏状态项

    /// 宿主进程显示一个原生状态项，菜单栏只能有一个 Covio 入口。
    func testHostApplicationShowsOneNativeMenuBarEntry() throws {
        let appDelegate = try XCTUnwrap(AppDelegate.current)
        XCTAssertEqual(appDelegate.statusItemController?.isVisible, true)
    }

    // MARK: - 宿主进程

    /// 测试是跑在被测应用进程里的，`AppDelegate` 已经启动了真正的 shell。
    /// 这条断言验证的是 M1 的装配真的生效，而不只是单元测试里能跑通。
    func testHostApplicationRunsTheShell() throws {
        let hotZones = NSApp.windows.compactMap { $0 as? HotZonePanel }
        let hubs = NSApp.windows.compactMap { $0 as? HubPanel }

        XCTAssertEqual(hotZones.count, NSScreen.screens.count, "宿主进程里每块屏幕应该有一个热区面板")
        XCTAssertEqual(hubs.count, 1, "宿主进程里应该只有一个 Hub 面板")

        for panel in hotZones {
            XCTAssertEqual(panel.level, .statusBar, "热区面板的层级必须高于菜单栏")
        }
        XCTAssertEqual(hubs.first?.level, .statusBar, "Hub 面板的层级必须高于菜单栏")
        // 本用例只验证宿主接线。启动时收起由 testStartCreatesOneHotZonePerScreenAndKeepsTheHubHidden 覆盖；
        // 这里再读可见性会受真实鼠标是否停在胶囊上影响。
    }
}

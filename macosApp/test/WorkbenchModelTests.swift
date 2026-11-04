import XCTest
@testable import Covio

/// 工作台模型：目的地、页签、首页组件与编辑模式。
///
/// 这些断言守着的是「视图读到的值与配置一致」。模型错了的后果是界面显示
/// 一个用户没存过的状态，而落盘的那一份还是旧的。
@MainActor
final class WorkbenchModelTests: XCTestCase {
    private func model() -> WorkbenchModel {
        WorkbenchModel()
    }

    private func spot(_ id: String, in model: WorkbenchModel) -> BentoSpot? {
        BentoPacker.pack(model.homeWidgets, columns: HubMetrics.bentoColumns)
            .first { $0.id == id }
    }

    // MARK: - 初始状态

    /// 初始停在首页，不在编辑模式。
    func testTheModelStartsOnTheHomePage() {
        let model = model()
        XCTAssertEqual(model.destination, .home)
        XCTAssertFalse(model.isEditing)
    }

    /// 默认配置里有六块组件，与打样一致。
    func testTheDefaultConfigHasSixWidgets() {
        XCTAssertEqual(model().homeWidgets.count, 6)
    }

    /// 默认配置保留六个内置工作区，但顶栏只显示四个可切换工作区。
    func testTheDefaultConfigShowsOnlyNavigableBuiltInPanes() {
        let model = model()
        let panes = model.panes(language: CopyLocale.language)
        XCTAssertEqual(panes.count, 4)
        XCTAssertEqual(
            panes.map(\.tab),
            [.now, .clipboard, .files, .devices]
        )
        for pane in panes {
            XCTAssertFalse(pane.title.isEmpty, "\(pane.id) 没有标题")
        }
        XCTAssertFalse(panes.contains { $0.tab == .agent })
        XCTAssertFalse(panes.contains { $0.tab == .settings })
    }

    /// 首页的行数由装箱算出来，不是写死的。
    func testHomeRowsComeFromThePacker() {
        let model = model()
        XCTAssertEqual(
            model.homeRows,
            BentoPacker.rows(BentoPacker.pack(model.homeWidgets, columns: HubMetrics.bentoColumns))
        )
        XCTAssertGreaterThan(model.homeRows, 0)
    }

    // MARK: - 换页

    /// 选中一个工作区就换到那一页。
    func testSelectingAPaneChangesTheDestination() {
        let model = model()
        model.select(paneID: PaneKind.clipboard.defaultId)
        XCTAssertEqual(model.destination, .pane(id: PaneKind.clipboard.defaultId))
        XCTAssertEqual(model.tab(for: model.destination), .clipboard)
    }

    /// The Agent opens only built-in pages and leaves editing first.
    func testOpeningAFixedAgentPageLeavesEditingAndChangesTheDestination() {
        let model = model()
        model.isEditing = true

        XCTAssertTrue(model.open(.files))
        XCTAssertFalse(model.isEditing)
        XCTAssertEqual(model.destination, .pane(id: PaneKind.files.defaultId))
    }

    func testOpeningTheCustomBoardIsRejected() {
        let model = model()
        XCTAssertFalse(model.open(.board))
        XCTAssertEqual(model.destination, .home)
    }

    /// 找不到的工作区停在原地，不崩也不换页。
    func testSelectingAnUnknownPaneDoesNothing() {
        let model = model()
        model.select(paneID: "no-such-pane")
        XCTAssertNotEqual(model.destination, .pane(id: "no-such-pane"))
    }

    /// 设置是固定入口。它不在页签里，但模型仍能直接打开。
    func testSettingsOpensWithoutAWorkbenchTab() {
        let model = model()

        XCTAssertTrue(model.openSettings())
        XCTAssertEqual(model.destination, .pane(id: PaneKind.settings.defaultId))
        XCTAssertFalse(model.panes(language: CopyLocale.language).contains { $0.tab == .settings })
    }

    /// 旧截图入口进入文件区，并携带一次截图筛选。消费后不重复套用。
    func testTheLegacyScreenshotEntryOpensFilesWithAScreenshotFilter() {
        let model = model()
        model.showFileArea(filter: .screenshots)

        XCTAssertEqual(model.destination, .pane(id: PaneKind.files.defaultId))
        XCTAssertEqual(model.pendingFileFilter, .screenshots)

        model.consumeFileFilterRequest()
        XCTAssertNil(model.pendingFileFilter)
    }

    /// 编辑模式里不换页。页签与卡片是两个页面的东西，一起编辑会串。
    func testSelectingAPaneIsIgnoredWhileEditing() {
        let model = model()
        model.isEditing = true
        model.select(paneID: PaneKind.clipboard.defaultId)
        XCTAssertEqual(model.destination, .home)
    }

    /// 换页就退出编辑模式。
    func testChangingThePageLeavesEditingMode() {
        let model = model()
        model.isEditing = true
        model.destination = .pane(id: PaneKind.files.defaultId)
        XCTAssertFalse(model.isEditing)
    }

    // MARK: - 顶栏右端的动作

    /// 首页上是「编辑」，编辑中是「完成」，其余工作区没有右侧动作。
    func testThePageActionFollowsTheDestination() {
        let model = model()
        XCTAssertEqual(model.pageAction?.text(for: .simplifiedChinese), ContractCopy.copyHubActionEdit.text(for: .simplifiedChinese))

        model.isEditing = true
        XCTAssertEqual(model.pageAction?.text(for: .simplifiedChinese), ContractCopy.copyHubActionDone.text(for: .simplifiedChinese))

        model.isEditing = false
        model.destination = .pane(id: PaneKind.settings.defaultId)
        XCTAssertNil(model.pageAction)

        model.destination = .pane(id: PaneKind.files.defaultId)
        XCTAssertNil(model.pageAction)
    }

    /// 首页上按一次进编辑模式，再按一次出来。
    func testThePageActionTogglesEditingOnTheHomePage() {
        let model = model()
        model.performPageAction()
        XCTAssertTrue(model.isEditing)
        model.performPageAction()
        XCTAssertFalse(model.isEditing)
    }

    /// 非首页没有动作按钮。误调动作方法也不改目的地。
    func testThePageActionDoesNothingOutsideTheHomePage() {
        let model = model()
        model.destination = .pane(id: PaneKind.files.defaultId)
        model.performPageAction()
        XCTAssertEqual(model.destination, .pane(id: PaneKind.files.defaultId))
    }

    // MARK: - 页签栏

    /// 每个工作区在页签栏里都有名称。内容区不重复页标题。
    func testEveryPaneHasANavigationTitle() {
        let model = model()
        XCTAssertEqual(
            model.panes(language: CopyLocale.language).count,
            model.config.visiblePanes.count
        )
        for pane in model.panes(language: CopyLocale.language) {
            XCTAssertFalse(pane.title.isEmpty, "\(pane.id) 的页签名称为空")
        }
    }

    // MARK: - 编辑首页

    /// 拖动把卡片放到指定空格，并留下原来的空格。
    func testMovingAWidgetStoresItsExplicitPosition() {
        let model = model()
        model.moveWidget(id: "w-clock", toColumn: 2, toRow: 2)

        let moved = spot("w-clock", in: model)
        XCTAssertEqual(moved?.column, 2)
        XCTAssertEqual(moved?.row, 2)
        XCTAssertEqual(spot("w-battery", in: model)?.column, 2)
        XCTAssertEqual(spot("w-battery", in: model)?.row, 0)
    }

    /// 占用区与越界位置都不改布局。
    func testInvalidWidgetMovesKeepTheLayout() {
        let model = model()
        model.moveWidget(id: "w-battery", toColumn: 0, toRow: 0)
        XCTAssertEqual(spot("w-battery", in: model)?.column, 2)
        XCTAssertEqual(spot("w-battery", in: model)?.row, 0)

        model.moveWidget(id: "w-battery", toColumn: 4, toRow: 0)
        XCTAssertEqual(spot("w-battery", in: model)?.column, 2)
        XCTAssertEqual(spot("w-battery", in: model)?.row, 0)
    }

    /// 缩放保留左上角；空间不足时保持原尺寸。
    func testResizingAWidgetKeepsItsPositionOrRevertsOnConflict() {
        let model = model()
        model.resizeWidget(id: "w-devices", to: .tall)
        XCTAssertEqual(spot("w-devices", in: model)?.size.key, "tall")
        XCTAssertEqual(spot("w-devices", in: model)?.column, 2)
        XCTAssertEqual(spot("w-devices", in: model)?.row, 1)

        model.resizeWidget(id: "w-clock", to: .large)
        XCTAssertEqual(spot("w-clock", in: model)?.size.key, "wide")
        XCTAssertEqual(spot("w-clock", in: model)?.column, 0)
        XCTAssertEqual(spot("w-clock", in: model)?.row, 0)
    }

    /// 删除只删那一块，其余卡片保持坐标。
    func testRemovingAWidgetDropsOnlyThatOne() {
        let model = model()
        model.moveWidget(id: "w-clock", toColumn: 2, toRow: 2)
        let target = model.homeWidgets[1]
        model.removeWidget(id: target.id)
        XCTAssertEqual(model.homeWidgets.count, 5)
        XCTAssertFalse(model.homeWidgets.contains { $0.id == target.id })
        XCTAssertEqual(spot("w-clock", in: model)?.column, 2)
        XCTAssertEqual(spot("w-clock", in: model)?.row, 2)
    }

    /// 删空之后首页是空态，行数为零。
    func testRemovingEveryWidgetLeavesAnEmptyHome() {
        let model = model()
        for widget in model.homeWidgets {
            model.removeWidget(id: widget.id)
        }
        XCTAssertTrue(model.homeWidgets.isEmpty)
        XCTAssertEqual(model.homeRows, 0)
    }

    // MARK: - 页签排序

    /// 页签换位按可见列表的下标走，隐藏的工作区不参与。
    func testMovingAPaneReordersTheVisibleTabs() {
        let model = model()
        let before = model.panes(language: CopyLocale.language).map(\.id)
        model.movePane(from: 0, to: 1)
        var expected = before
        let moved = expected.remove(at: 0)
        expected.insert(moved, at: 1)
        XCTAssertEqual(model.panes(language: CopyLocale.language).map(\.id), expected)
    }

    /// 越界的页签换位被忽略。
    func testMovingAPaneOutOfRangeIsIgnored() {
        let model = model()
        let before = model.panes(language: CopyLocale.language).map(\.id)
        model.movePane(from: 0, to: 99)
        model.movePane(from: 99, to: 0)
        XCTAssertEqual(model.panes(language: CopyLocale.language).map(\.id), before)
    }

    // MARK: - 指针切换页签

    /// 刚展开时的 hover 保护不切页，也不把这次 hover 排到保护结束。
    func testInitialHoverProtectionIgnoresHoverWithoutQueueing() {
        let model = model()
        let target = HubDestination.pane(id: PaneKind.clipboard.defaultId)

        model.beginInitialHoverProtection()
        model.pointerEntered(target)

        XCTAssertTrue(model.isInitialHoverProtected)
        XCTAssertEqual(model.destination, .home)
        XCTAssertNil(model.pendingDestination)

        model.endInitialHoverProtection()
        model.pointerEntered(target)
        XCTAssertEqual(model.destination, target, "保护结束后重新进入应正常切页")
    }

    /// hover 保护只拦截指针，不拦截点选。
    func testClickingStillWorksDuringInitialHoverProtection() {
        let model = model()
        let target = PaneKind.clipboard.defaultId

        model.beginInitialHoverProtection()
        model.select(paneID: target)

        XCTAssertEqual(model.destination, .pane(id: target))
    }

    /// 展开动画结束后，保护在指定时长后自动解除。
    func testInitialHoverProtectionEndsAfterTheDelay() async {
        let model = model()
        model.beginInitialHoverProtection()
        model.scheduleInitialHoverProtectionEnd(after: 0.02)

        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertFalse(model.isInitialHoverProtected)
    }

    /// 冷却早就走完了，进入就换，没有等待。
    func testHoveringAnotherPaneSwitchesImmediately() {
        let model = model()
        let target = HubDestination.pane(id: PaneKind.clipboard.defaultId)

        model.pointerEntered(target)

        XCTAssertEqual(model.destination, target)
        XCTAssertNil(model.pendingDestination, "立刻换掉了，不该留下待切换")
    }

    /// 停在已经选中的页签上什么都不做。否则滑块会白闪一次。
    func testHoveringTheCurrentPaneDoesNothing() {
        let model = model()
        model.select(paneID: PaneKind.clipboard.defaultId)

        model.pointerEntered(.pane(id: PaneKind.clipboard.defaultId))

        XCTAssertNil(model.pendingDestination, "停在已选中的页签上不该等")
    }

    /// 冷却没走完，第二次切换先等着。
    func testTheCooldownBlocksASecondSwitch() {
        let model = model()
        let first = HubDestination.pane(id: PaneKind.clipboard.defaultId)
        let second = HubDestination.pane(id: PaneKind.files.defaultId)

        model.pointerEntered(first)
        model.pointerEntered(second)

        XCTAssertEqual(model.destination, first, "冷却里不该换第二次")
        XCTAssertEqual(model.pendingDestination, second, "第二次应该排着")
        XCTAssertNotNil(model.lastSwitchAt)
    }

    /// 冷却走完，排着的那一次自己换过去。
    func testTheDeferredSwitchFiresWhenTheCooldownEnds() async {
        let model = model()
        let second = HubDestination.pane(id: PaneKind.files.defaultId)

        model.pointerEntered(.pane(id: PaneKind.clipboard.defaultId))
        model.pointerEntered(second)
        await waitForSwitch(model, to: second)

        XCTAssertEqual(model.destination, second)
        XCTAssertNil(model.pendingDestination, "换完不该还留着")
    }

    /// 没等到冷却走完就离开，排着的那一次取消。
    func testLeavingTheTabCancelsTheDeferredSwitch() async {
        let model = model()
        let first = HubDestination.pane(id: PaneKind.clipboard.defaultId)
        let second = HubDestination.pane(id: PaneKind.files.defaultId)

        model.pointerEntered(first)
        model.pointerEntered(second)
        model.pointerExited(second)

        XCTAssertNil(model.pendingDestination, "离开该页签应该立刻取消")

        await waitOutTheCooldownWindow()
        XCTAssertEqual(model.destination, first, "离开后不该再换页")
    }

    /// 指针从 A 移到 B 时，事件顺序是 `enter(B)` 再到 `exit(A)`。
    /// 那时排着的是 B，`exit(A)` 不该把它清掉。
    func testLeavingAnotherTabKeepsThePendingSwitch() {
        let model = model()
        let first = HubDestination.pane(id: PaneKind.clipboard.defaultId)
        let second = HubDestination.pane(id: PaneKind.files.defaultId)

        model.pointerEntered(first)
        model.pointerEntered(second)
        model.pointerExited(first)

        XCTAssertEqual(model.pendingDestination, second, "exit(旧页签) 不该动新页签的等待")
    }

    /// 冷却里连着进入两个页签，只换到最后停住的那一个。
    func testHoveringASecondTabRearmsTheSwitch() async {
        let model = model()
        let third = HubDestination.pane(id: PaneKind.devices.defaultId)

        model.pointerEntered(.pane(id: PaneKind.clipboard.defaultId))
        model.pointerEntered(.pane(id: PaneKind.files.defaultId))
        model.pointerEntered(third)
        await waitForSwitch(model, to: third)

        XCTAssertEqual(model.destination, third, "应该换到最后停住的那一个")
    }

    /// 冷却里点选别的页签，排着的那一次作废。用户已经用点选改过主意。
    func testClickingCancelsTheDeferredSwitch() async {
        let model = model()
        let deferred = HubDestination.pane(id: PaneKind.files.defaultId)
        let clicked = HubDestination.pane(id: PaneKind.devices.defaultId)

        model.pointerEntered(.pane(id: PaneKind.clipboard.defaultId))
        model.pointerEntered(deferred)
        model.select(paneID: PaneKind.devices.defaultId)

        XCTAssertEqual(model.destination, clicked)
        XCTAssertNil(model.pendingDestination, "点选应该把排着的那一次清掉")

        await waitOutTheCooldownWindow()
        XCTAssertEqual(model.destination, clicked, "点选之后不该被指针抢回去")
    }

    /// 面板收起时取消待切换。收起后 AppKit 不发 `mouseExited`，不取消还会换一次。
    func testCancelHoverSwitchStopsTheDeferredSwitch() async {
        let model = model()
        let first = HubDestination.pane(id: PaneKind.clipboard.defaultId)

        model.pointerEntered(first)
        model.pointerEntered(.pane(id: PaneKind.files.defaultId))
        model.cancelHoverSwitch()

        XCTAssertNil(model.pendingDestination)

        await waitOutTheCooldownWindow()
        XCTAssertEqual(model.destination, first, "取消后不该再换页")
    }

    /// 编辑模式里不换。那时点选也不换页，指针不该是一条后门。
    func testHoveringIsIgnoredWhileEditing() async {
        let model = model()
        model.performPageAction()
        XCTAssertTrue(model.isEditing, "首页上的动作按钮应该进编辑模式")

        model.pointerEntered(.pane(id: PaneKind.clipboard.defaultId))

        XCTAssertNil(model.pendingDestination, "编辑模式里不该换页")

        await waitOutTheCooldownWindow()
        XCTAssertEqual(model.destination, .home, "编辑模式里不该换页")
    }

    /// 首页入口也是一个目的地，指针一样换过去。
    func testHoveringTheHomeEntryGoesBackHome() async {
        let model = model()
        model.select(paneID: PaneKind.clipboard.defaultId)

        model.pointerEntered(.home)
        await waitForSwitch(model, to: .home)

        XCTAssertEqual(model.destination, .home)
    }

    /// 等到换页发生。查状态，不查时长（实测 39）。
    ///
    /// 超时给 4 秒，远大于冷却时长，机器再慢也不至于误报。
    private func waitForSwitch(_ model: WorkbenchModel, to destination: HubDestination) async {
        let deadline = Date().addingTimeInterval(4)
        while model.destination != destination, Date() < deadline {
            // 让出主 actor，计时任务才跑得动。
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// 等一个「不该发生」的有界窗口。冷却时长再加一点余量。
    private func waitOutTheCooldownWindow() async {
        try? await Task.sleep(for: .seconds(HubMotion.hoverCooldown + 0.3))
    }

    // MARK: - 落盘

    /// 接了落盘之后，改动写进文件，重建模型还能读回来。
    func testChangesSurviveAReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-workbench-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let path = directory.appendingPathComponent("workbench.json").path
        let model = model()
        model.attach(store: WorkbenchStore.companion.create(path: path))
        let removed = "w-battery"
        model.removeWidget(id: removed)
        model.moveWidget(id: "w-clock", toColumn: 2, toRow: 2)
        model.movePane(from: 0, to: 1)
        let expectedOrder = model.panes(language: CopyLocale.language).map(\.id)

        let reloaded = WorkbenchModel()
        reloaded.attach(store: WorkbenchStore.companion.create(path: path))
        XCTAssertFalse(reloaded.homeWidgets.contains { $0.id == removed }, "删除没有落盘")
        XCTAssertEqual(
            reloaded.panes(language: CopyLocale.language).map(\.id),
            expectedOrder,
            "页签顺序没有落盘"
        )
        XCTAssertEqual(spot("w-clock", in: reloaded)?.column, 2, "卡片列没有落盘")
        XCTAssertEqual(spot("w-clock", in: reloaded)?.row, 2, "卡片行没有落盘")
    }
}

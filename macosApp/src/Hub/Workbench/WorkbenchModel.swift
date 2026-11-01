import Foundation
import kmpDomain

/// 挂帘的工作台状态。
///
/// 持有工作台配置、当前目的地和编辑模式开关。视图只读它，改动都走这里的方法，
/// 方法改完配置就落盘。
///
/// 指针切换页签的判定也住在这里：它是改 `destination` 的一条路径，
/// 与点选共用同一道门，编辑模式那一类规则不必写两遍。
///
/// **编辑模式不进 `HubStateMachine`。** 状态机的六个态由合同与
/// `DesignContractTests` 逐字钉死。扩态是 `docs/design/workbench-architecture.md`
/// 交给 ADR 的事，不该夹在界面对齐里做。
@MainActor
@Observable
final class WorkbenchModel {
    /// 工作台配置。改动一律走下面的方法，直接写会绕过落盘。
    private(set) var config: WorkbenchConfig
    /// 当前显示的位置。默认首页。
    var destination: HubDestination = .home {
        didSet {
            guard destination != oldValue else { return }
            // 换页就退出编辑模式。页签与卡片是两个页面的东西，一起编辑会串。
            isEditing = false
            // 换页签就重新起算冷却。指针还停在别的项上时，那一次待切换作废：
            // 用户已经用点选改过主意。
            lastSwitchAt = Date()
            cancelHoverSwitch()
        }
    }
    /// 编辑模式。顶栏右端那个按钮切换它。
    var isEditing = false

    /// 一次性的文件筛选请求。旧「截图」目的地经这里进入文件区，消费后清空。
    private(set) var pendingFileFilter: FileAreaFilterChoice?

    /// 落盘。为 nil 时不存（预览与测试）。
    private var store: WorkbenchStore?

    init(store: WorkbenchStore? = nil) {
        self.store = store
        self.config = store?.load() ?? WorkbenchConfig.companion.defaults()
    }

    /// 接上落盘，并立刻读一次盘。
    ///
    /// `AppDelegate` 在 `start()` 之前调。不在 `init` 里读盘，是因为控制器与
    /// 运行时都要先装配好；测试与预览则根本不接。
    func attach(store: WorkbenchStore) {
        self.store = store
        config = store.load()
    }

    // MARK: - 读

    /// 顶栏要画的页签。隐藏的工作区不出现。
    ///
    /// 语言由视图传入，避免模型保存一份可能过期或与运行时不同的语言。
    func panes(language: AppLanguage) -> [PaneItem] {
        config.visiblePanes.compactMap { pane in
            guard let tab = HubTab(rawValue: pane.kind.key) else { return nil }
            let title = pane.title.isEmpty ? tab.title.text(for: language) : pane.title
            return PaneItem(id: pane.id, tab: tab, title: title)
        }
    }

    /// 界面上可见的工作区数量。编辑提示条用它。
    var visiblePaneCount: Int { config.visiblePanes.count }

    /// 首页的组件。
    var homeWidgets: [WidgetInstance] { config.homeWidgets }

    /// 首页网格几行。面板高度按它算。
    var homeRows: Int {
        BentoPacker.rows(BentoPacker.pack(config.homeWidgets, columns: HubMetrics.bentoColumns))
    }

    /// 某个目的地的种类。找不到时回落到占位页。
    func tab(for destination: HubDestination) -> HubTab {
        guard let id = destination.paneID, let pane = config.pane(id: id) else { return .now }
        return HubTab(rawValue: pane.kind.key) ?? .board
    }

    /// 顶栏右端的动作。首页提供编辑动作，其余工作区不重复提供设置入口。
    var pageAction: LocalizedCopy? {
        if isEditing { return ContractCopy.copyHubActionDone }
        switch destination {
        case .home: return ContractCopy.copyHubActionEdit
        case .pane: return nil
        }
    }

    // MARK: - 写

    /// 顶栏右端按钮的动作。
    func performPageAction() {
        if isEditing {
            isEditing = false
            return
        }
        guard destination == .home else { return }
        isEditing = true
    }

    /// 打开文件区，并可附带一次筛选请求。截图入口使用截图筛选。
    func showFileArea(filter: FileAreaFilterChoice? = nil) {
        pendingFileFilter = filter
        destination = .pane(id: PaneKind.files.defaultId)
    }

    /// 文件页读到请求后清空，避免下次进入时重复套用旧筛选。
    func consumeFileFilterRequest() {
        pendingFileFilter = nil
    }

    /// 换一个工作区。编辑模式里不换，与打样一致。
    ///
    /// 配置里没有这个 id 时停在原地：换过去会显示一页没有标题行的占位内容。
    func select(paneID: String) {
        guard !isEditing, config.pane(id: paneID) != nil else { return }
        destination = .pane(id: paneID)
    }

    /// Opens one built-in page from a fixed Agent enum.
    ///
    /// Returns false when the page is hidden or the enum maps to a custom board.
    @discardableResult
    func open(_ tab: HubTab) -> Bool {
        guard tab != .board,
              let pane = config.visiblePanes.first(where: { $0.kind.key == tab.rawValue })
        else { return false }
        isEditing = false
        destination = .pane(id: pane.id)
        return true
    }

    /// 换工作区的顺序。参数是可见工作区里的下标。
    func movePane(from: Int, to: Int) {
        let visible = config.visiblePanes
        guard visible.indices.contains(from), visible.indices.contains(to), from != to else { return }
        // `movePane` 要的是全量列表里的下标，隐藏的工作区也算数。
        guard let index = config.panes.firstIndex(where: { $0.id == visible[to].id }) else { return }
        update(config.movePane(id: visible[from].id, toIndex: Int32(index)))
    }

    /// 把一块组件放到指定网格位置。位置冲突时保持原样。
    func moveWidget(id: String, toColumn column: Int, toRow row: Int) {
        let spots = BentoPacker.pack(config.homeWidgets, columns: HubMetrics.bentoColumns)
        guard let spot = spots.first(where: { $0.id == id }) else { return }
        guard BentoPacker.canPlace(
            id: id,
            size: spot.size,
            column: column,
            row: row,
            among: spots,
            columns: HubMetrics.bentoColumns,
            maximumRows: BentoPacker.rows(spots)
        ) else { return }

        let widgets = BentoPacker.materialized(
            config.homeWidgets,
            columns: HubMetrics.bentoColumns
        ).map { widget in
            guard widget.id == id else { return widget }
            return widget.withGridFrame(
                size: widget.size,
                column: Int32(column),
                row: Int32(row)
            )
        }
        update(replacingWidgets(widgets))
    }

    /// 改一块组件的档位。尺寸会碰到别的卡片时保持原样。
    func resizeWidget(id: String, to size: WidgetSize) {
        let spots = BentoPacker.pack(config.homeWidgets, columns: HubMetrics.bentoColumns)
        guard let spot = spots.first(where: { $0.id == id }), spot.size.key != size.key else { return }
        guard BentoPacker.canPlace(
            id: id,
            size: size,
            column: spot.column,
            row: spot.row,
            among: spots,
            columns: HubMetrics.bentoColumns,
            maximumRows: BentoPacker.rows(spots)
        ) else { return }

        let widgets = BentoPacker.materialized(
            config.homeWidgets,
            columns: HubMetrics.bentoColumns
        ).map { widget in
            guard widget.id == id else { return widget }
            return widget.withGridFrame(
                size: size,
                column: widget.column,
                row: widget.row
            )
        }
        update(replacingWidgets(widgets))
    }

    /// 删一块组件。其余组件保持当前坐标，不自动回流。
    func removeWidget(id: String) {
        let widgets = BentoPacker.materialized(
            config.homeWidgets,
            columns: HubMetrics.bentoColumns
        ).filter { $0.id != id }
        update(replacingWidgets(widgets))
    }

    // MARK: - 指针切换页签

    /// 指针正停着、冷却还没走完的那个目的地。nil 表示没有待切换。
    private(set) var pendingDestination: HubDestination?

    /// 上一次换页签的时刻。指针切换按冷却窗口放行。
    private(set) var lastSwitchAt: Date?

    private var cooldownTask: Task<Void, Never>?
    private var initialHoverProtectionTask: Task<Void, Never>?

    /// 工作台刚展开时暂时忽略导航 hover。
    ///
    /// 保护从面板开始出现时生效，展开动画结束后再保留 0.5 秒。这样面板一上屏
    /// 就不会被指针当前位置误切页，也不会在保护结束时补触发。
    private(set) var isInitialHoverProtected = false

    /// 指针进入一个页签。冷却已经走完就立刻切，没走完就等它走完再切。
    ///
    /// 编辑模式里不切：那时点选也不换页，指针不该是一条后门。
    /// 停在已经选中的页签上也不切，否则滑块会白闪一次。
    func pointerEntered(_ destination: HubDestination) {
        cancelHoverSwitch()
        guard !isInitialHoverProtected, !isEditing, destination != self.destination else { return }
        let remaining = cooldownRemaining()
        guard remaining > 0 else {
            select(destination)
            return
        }
        pendingDestination = destination
        cooldownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.fireSwitch(destination)
        }
    }

    /// 指针离开一个页签。只有离开正在等的那一个才取消。
    ///
    /// 指针从 A 移到 B 时事件顺序是 `enter(B)` 再到 `exit(A)`。
    /// 那时正在等的是 B，`exit(A)` 不该动它。
    func pointerExited(_ destination: HubDestination) {
        guard pendingDestination == destination else { return }
        cancelHoverSwitch()
    }

    /// 取消待切换。面板收起时调用。
    ///
    /// 面板被 `orderOut` 时 AppKit 不发 `mouseExited`，指针停在某个页签上的
    /// 等待会继续跑。不取消的话，收起后还会切一次。
    func cancelHoverSwitch() {
        cooldownTask?.cancel()
        cooldownTask = nil
        pendingDestination = nil
    }

    /// 面板开始出现时进入 hover 保护。每次展开都重新开始。
    func beginInitialHoverProtection() {
        initialHoverProtectionTask?.cancel()
        initialHoverProtectionTask = nil
        isInitialHoverProtected = true
        cancelHoverSwitch()
    }

    /// 展开动画结束后，再保留指定的 hover 保护时间。
    func scheduleInitialHoverProtectionEnd(after delay: TimeInterval) {
        guard isInitialHoverProtected else { return }
        initialHoverProtectionTask?.cancel()
        initialHoverProtectionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.isInitialHoverProtected = false
            self?.initialHoverProtectionTask = nil
        }
    }

    /// 立即结束 hover 保护。测试和面板提前收起时使用。
    func endInitialHoverProtection() {
        initialHoverProtectionTask?.cancel()
        initialHoverProtectionTask = nil
        isInitialHoverProtected = false
    }

    /// 冷却走完，换到那一页。
    ///
    /// 这里再查一次编辑模式：等的那段时间里，用户可能已经按了编辑按钮。
    private func fireSwitch(_ destination: HubDestination) {
        guard pendingDestination == destination else { return }
        cancelHoverSwitch()
        select(destination)
    }

    /// 冷却还剩多久。没换过页签、或者冷却已经走完，返回 0。
    private func cooldownRemaining() -> TimeInterval {
        guard let lastSwitchAt else { return 0 }
        return max(0, HubMotion.hoverCooldown - Date().timeIntervalSince(lastSwitchAt))
    }

    /// 换一个目的地。指针切换走这里，与点选同一条路。
    ///
    /// 首页不是工作区，`select(paneID:)` 管不到它，所以在这一层分开。
    private func select(_ destination: HubDestination) {
        guard !isEditing else { return }
        switch destination {
        case .home: self.destination = .home
        case .pane(let id): select(paneID: id)
        }
    }

    // MARK: - 落盘

    /// 换掉组件列表，其余字段照抄。
    private func replacingWidgets(_ widgets: [WidgetInstance]) -> WorkbenchConfig {
        config.doCopy(
            schemaVersion: config.schemaVersion,
            panes: config.panes,
            homeWidgets: widgets
        )
    }

    /// 改配置并落盘。
    ///
    /// `WorkbenchStore.save` 自己咽掉写盘失败，不抛异常，所以这里不需要接错误。
    /// 内存里的配置先改，界面立刻跟上；落不落得下是下一步的事。
    private func update(_ next: WorkbenchConfig) {
        config = next
        guard let store else { return }
        _ = store.save(config: next)
    }
}

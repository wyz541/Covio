import AppKit
import Observation
import SwiftUI

/// Notch Shell 的控制器。
///
/// 职责：
/// - 为每块屏幕维护一个热区面板。
/// - 维护唯一的 Hub 面板，显示时移动到指针所在屏幕。
/// - 驱动 `HubStateMachine`，执行计时与面板显示。
///
/// 状态词汇全部来自设计合同，不造新词。
@MainActor
@Observable
final class NotchShellController {
    /// 面板生命周期状态。来源是合同 `states.menuBarAndNotchHub.hubStates`。
    private(set) var state: HubState = .hidden
    /// 内容区状态。来源是合同 `states.notchOutputHub.states`。M1 固定为 collapsed。
    private(set) var outputState: HubOutputState = .collapsed
    /// 工作台状态。当前页、页签列表、首页组件和编辑模式都住在这里。
    /// 这些状态不改变外壳尺寸。
    let workbench = WorkbenchModel()

    /// Hub 外壳的共享状态。搜索文字与设置分节住在这里。
    ///
    /// 由控制器持有，所以面板收起再展开时搜索文字与分节不丢。
    let chrome = HubChromeModel()

    /// 页内 Popover 的生命周期。Popover 打开时暂停自动收起。
    let popoverCoordinator = HubPopoverCoordinator()

    /// 当前面板所在的屏幕几何。
    private(set) var geometry: ScreenGeometry?
    /// 系统是否要求减弱动态效果。
    private(set) var reduceMotion = false

    private var machine = HubStateMachine()
    private var hotZonePanels: [HotZonePanel] = []
    private var hubPanel: HubPanel?
    private var expandTimer: Timer?
    private var collapseTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let pointerLocation: @MainActor () -> CGPoint
    private var collapseAfterPopoversDismiss = false
    private var keepOpenAfterGesturePresentation = false

    /// 运行时。Hub 的设置页读它。测试与预览里可以是 nil，那时设置页显示占位。
    var runtime: AppRuntime?
    /// 打开独立设置窗口。生产环境由 `AppDelegate` 接线；预览与测试没有接线时
    /// 搜索仍回落到工作台内旧路径。
    var onOpenSettings: ((SettingsSearchHit?) -> Void)?
    /// `pointerLocation` 是唯一为了测试留的接缝。默认读真实指针位置。
    /// 测试注入固定坐标，就不必真的移动用户的鼠标。
    init(pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }) {
        self.pointerLocation = pointerLocation
    }

    /// 面板是否处于展开态。视图用它驱动窗帘动画。
    var isExpanded: Bool { state != .hidden && state != .exit }

    // MARK: - 只读状态。供测试与手工验证使用。

    /// 每块屏幕一个热区面板的矩形。
    var hotZoneRects: [CGRect] { hotZonePanels.map(\.frame) }

    /// Hub 面板当前是否在屏幕上。
    var isHubPanelOnScreen: Bool { hubPanel?.isVisible ?? false }

    /// Hub 面板当前的矩形。
    var hubPanelFrame: CGRect? { hubPanel?.frame }

    /// 菜单栏当前是否可见。全屏 Space 里为 false，此时热区隐藏。
    var isHotZoneEnabled: Bool { geometry?.isMenuBarVisible ?? true }

    // MARK: - 生命周期

    func start() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popoverCoordinator.onActivityChanged = { [weak self] active in
            self?.popoverActivityChanged(active)
        }
        rebuildHotZones()
        observeSystemChanges()
        applyVisibility()
    }

    func stop() {
        cancelTimers()
        popoverCoordinator.onActivityChanged = nil
        popoverCoordinator.reset()
        workbench.endInitialHoverProtection()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
        hotZonePanels.forEach { $0.orderOut(nil) }
        hotZonePanels.removeAll()
        hubPanel?.orderOut(nil)
        hubPanel = nil
    }

    // MARK: - 外部入口

    /// `Control+Option+T` 与菜单栏菜单都走这里。Hub 打开时收起，否则打开。
    func toggle() {
        if state == .hidden || state == .exit {
            show()
        } else {
            requestCollapse()
        }
    }

    func show() {
        guard state == .hidden || state == .exit else {
            // 已经打开。刷新几何，指针可能换了屏幕。
            if state != .exit { relocateIfNeeded() }
            return
        }
        collapseAfterPopoversDismiss = false
        keepOpenAfterGesturePresentation = false
        send(.pointerEnteredHotZone)
    }

    /// 手势入口打开工作台。
    ///
    /// 双指手势不移动指针。面板出现时指针通常不在工作台内，
    /// 所以手势打开要等指针进入后再恢复普通的移出收起规则。
    func showFromGesture() {
        guard state == .hidden || state == .exit else {
            if state != .exit { relocateIfNeeded() }
            return
        }
        collapseAfterPopoversDismiss = false
        keepOpenAfterGesturePresentation = true
        send(.pointerEnteredHotZone)
    }

    /// 请求收起。
    ///
    /// 编辑模式里第一次请求先退出编辑，不收起面板。拖动卡片时指针常会划出面板，
    /// 直接收起会把编辑到一半的布局丢掉。
    func requestCollapse() {
        if workbench.isEditing {
            workbench.isEditing = false
            return
        }
        if popoverCoordinator.hasActivePopover {
            collapseAfterPopoversDismiss = true
            popoverCoordinator.requestDismissal()
            return
        }
        send(.collapseRequested)
    }

    /// 指针进入面板。抽成方法是为了让测试能直接驱动这条路径。
    func pointerEnteredHub() {
        send(.pointerEnteredHub)
    }

    /// 指针离开面板。抽成方法是为了让测试能直接驱动这条路径。
    func pointerExitedHub() {
        send(.pointerExitedHub)
    }

    // MARK: - 状态机

    private func send(_ event: HubEvent) {
        guard machine.canHandle(event) else { return }
        let previous = machine.state
        machine.handle(event)
        state = machine.state
        react(to: event, from: previous)
        applyVisibility()
    }

    private func react(to event: HubEvent, from previous: HubState) {
        // 目标状态自身的副作用。收起动画从进入 .exit 开始计时。
        if state == .exit, previous != .exit {
            // 面板被 orderOut 时 AppKit 不发 mouseExited，指针停在某个页签上的
            // 等待会继续跑。不取消的话，收起后还会切一次。
            workbench.cancelHoverSwitch()
            workbench.endInitialHoverProtection()
            collapseAfterPopoversDismiss = false
            beginCollapse()
        }

        switch event {
        case .pointerEnteredHotZone:
            // 必须先取消旧的计时，再展开。展开过程中可能因为指针不在面板里
            // 立刻又启动收起计时，那个计时不能被这里清掉。
            cancelCollapseTimer()
            if state == .hover { presentHub() }

        case .pointerEnteredHub:
            // 指针进入面板。取消待收起计时，内容区进入就绪。
            cancelCollapseTimer()
            keepOpenAfterGesturePresentation = false
            if state == .active, outputState == .collapsed {
                outputState = .ready
            }

        case .pointerExitedHub:
            guard state != .exit else { break }
            if !popoverCoordinator.hasActivePopover {
                outputState = .collapsed
            }
            // 编辑模式里不排收起计时。拖一块卡时指针会短暂划出面板，
            // 那不算「用户想走」。收起的入口只剩 Escape 与点胶囊。
            // Popover 打开时也保留面板，否则 Popover 会失去可操作的父视图。
            if !workbench.isEditing, !popoverCoordinator.hasActivePopover {
                startCollapseTimer()
            }

        case .expandFinished:
            workbench.scheduleInitialHoverProtectionEnd(after: HubMotion.initialHoverProtection)
            // 展开结束时指针可能已经在面板里。
            if state == .open, pointerIsInsideHubPanel {
                send(.pointerEnteredHub)
            }

        case .collapseRequested:
            // 只取消展开计时。收起计时是上面 beginCollapse() 刚启动的，不能动。
            cancelExpandTimer()
            keepOpenAfterGesturePresentation = false
            outputState = .collapsed

        case .collapseFinished:
            outputState = .collapsed

        case .failureRaised:
            cancelCollapseTimer()
            outputState = .error

        case .failureCleared:
            outputState = .ready

        case .pointerExitedHotZone:
            break
        }
    }

    // MARK: - 面板动作

    private func presentHub() {
        makeHubPanel()
        guard let hubPanel else { return }
        guard let geometry = ScreenGeometry.current(location: pointerLocation()) else { return }
        self.geometry = geometry

        hubPanel.setFrame(geometry.expandedRect, display: true)
        // 先进入保护，再显示视图。视图出现时触发的 hover 也会被拦住。
        workbench.beginInitialHoverProtection()
        hubPanel.orderFrontRegardless()
        hubPanel.makeKey()
        if let host = hubPanel.contentView {
            hubPanel.makeFirstResponder(host)
        }

        cancelExpandTimer()
        let duration = HubMotion.expandDuration(reduceMotion: reduceMotion)
        expandTimer = schedule(after: duration) { [weak self] in
            self?.send(.expandFinished)
        }

        // 面板出现时指针可能已经在外面。tracking area 的 mouseEntered 要等下一次鼠标移动，
        // 所以在建立面板后主动查一次真实指针位置，避免 Hub 卡在展开态。
        // 手势打开是例外：双指手势不移动指针，必须等工作台收到指针交互后再恢复自动收起。
        if !pointerIsInsideHubPanel && !keepOpenAfterGesturePresentation {
            send(.pointerExitedHub)
        }
    }

    /// Popover 活动状态变化。
    ///
    /// 首个 Popover 打开时取消待收起计时。最后一个关闭后，等显式收起，或按
    /// 指针当前位置重新走普通自动收起规则。
    private func popoverActivityChanged(_ active: Bool) {
        if active {
            cancelCollapseTimer()
            return
        }
        if collapseAfterPopoversDismiss {
            collapseAfterPopoversDismiss = false
            send(.collapseRequested)
            return
        }
        guard state == .open || state == .active else { return }
        if !workbench.isEditing, !pointerIsInsideHubPanel {
            startCollapseTimer()
        }
    }

    private func beginCollapse() {
        cancelExpandTimer()
        let duration = HubMotion.collapseDuration(reduceMotion: reduceMotion)
        collapseTimer = schedule(after: duration) { [weak self] in
            self?.send(.collapseFinished)
        }
    }

    /// 状态变化后同步窗口的可见性。
    ///
    /// 热区面板可见当且仅当 Hub 收起。这样两个面板不会互相遮挡，
    /// 也不会出现热区的 `mouseExited` 把刚展开的 Hub 关掉。
    private func applyVisibility() {
        let hubVisible = state.isPanelVisible
        for panel in hotZonePanels {
            let shouldShow = !hubVisible && (geometryFor(panel)?.isMenuBarVisible ?? false)
            if shouldShow {
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }
        if !hubVisible {
            hubPanel?.orderOut(nil)
        }
    }

    private func relocateIfNeeded() {
        guard let hubPanel, let geometry = ScreenGeometry.current(location: pointerLocation()) else { return }
        guard geometry != self.geometry else { return }
        self.geometry = geometry
        hubPanel.setFrame(geometry.expandedRect, display: true)
    }

    private var pointerIsInsideHubPanel: Bool {
        guard let hubPanel else { return false }
        return hubPanel.frame.contains(pointerLocation())
    }

    /// 热区报的「离开」要不要转给状态机。
    ///
    /// 挂帘面板一露出来就盖住热区：面板是 960 × 547，热区只是刘海那一条
    /// 186 × 32，横向纵向都被包住。热区随后收到的「离开」是面板挡出来的，
    /// 不是用户走开。照发的话状态机按 `.hover + .pointerExitedHotZone → .hidden`
    /// 把刚展开的面板收回去，热区重新露出来又收到「进入」，两边来回弹。
    ///
    /// 实测：指针停在热区不动，3 秒采样 24 次，开 11 次关 13 次。
    ///
    /// 面板可见时，进出由面板自己的跟踪区报，热区不再插话。
    static func shouldReportHotZoneExit(hubVisible: Bool, pointerInsideHub: Bool) -> Bool {
        !(hubVisible && pointerInsideHub)
    }

    // MARK: - 计时

    private func schedule(after delay: TimeInterval, _ body: @escaping @MainActor () -> Void) -> Timer {
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { body() }
        }
    }

    private func startCollapseTimer() {
        cancelCollapseTimer()
        collapseTimer = schedule(after: HubMotion.pointerExitCollapseDelay) { [weak self] in
            self?.send(.collapseRequested)
        }
    }

    private func cancelExpandTimer() {
        expandTimer?.invalidate()
        expandTimer = nil
    }

    private func cancelCollapseTimer() {
        collapseTimer?.invalidate()
        collapseTimer = nil
    }

    private func cancelTimers() {
        cancelExpandTimer()
        cancelCollapseTimer()
    }

    // MARK: - 面板与屏幕

    private func makeHubPanel() {
        guard hubPanel == nil else { return }
        let initial = ScreenGeometry.current(location: pointerLocation())?.expandedRect
            ?? CGRect(
                x: 0,
                y: 0,
                width: HubMetrics.panelWidth,
                height: HubMetrics.preferredShellContentHeight
            )
        let panel = HubPanel(rect: initial)

        let host = PointerTrackingHost(rootView: hubContentView())
        host.onPointerEnter = { [weak self] in self?.pointerEnteredHub() }
        host.onPointerExit = { [weak self] in self?.pointerExitedHub() }
        panel.contentView = host
        // Escape 先清搜索：用户在搜索时按 Escape 想关掉结果，不是收起整个面板。
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if !self.chrome.handleEscape() {
                self.requestCollapse()
            }
        }


        hubPanel = panel
    }

    /// 在菜单栏入口出现后预先创建隐藏的 Hub 面板。
    ///
    /// 面板保持 `orderOut`，不会进入屏幕、接收鼠标或改变可见状态。
    /// 如果用户已经打开 Hub，这里不会再次创建。
    func prepareHubPanel() {
        makeHubPanel()
        guard let hubPanel else { return }
        if let geometry = ScreenGeometry.current(location: pointerLocation()) {
            hubPanel.setFrame(geometry.expandedRect, display: false)
        }
        hubPanel.contentView?.layoutSubtreeIfNeeded()
        hubPanel.contentView?.displayIfNeeded()
    }

    private func hubContentView() -> some View {
        // 外壳尺寸由屏幕决定。这里用一个稳定的几何快照，
        // 屏幕变化时由 rebuild 重建面板。
        let snapshot = geometry ?? ScreenGeometry.current(location: pointerLocation())
        return HubContentRoot(controller: self, initialGeometry: snapshot, runtime: runtime)
    }

    /// 重建热区面板。显示器变化与全屏 Space 切换时调用。
    private func rebuildHotZones() {
        hotZonePanels.forEach { $0.orderOut(nil) }
        hotZonePanels.removeAll()

        for screen in NSScreen.screens {
            let geometry = ScreenGeometry(screen: screen)
            let panel = HotZonePanel(rect: geometry.hotZoneRect)
            let host = PointerTrackingView(frame: .zero)
            host.onPointerEnter = { [weak self] in self?.send(.pointerEnteredHotZone) }
            host.onPointerExit = { [weak self] in
                guard let self else { return }
                // 面板盖住热区时那次「离开」是假的，别让它把面板收回去。
                let report = Self.shouldReportHotZoneExit(
                    hubVisible: self.hubPanel?.isVisible ?? false,
                    pointerInsideHub: self.pointerIsInsideHubPanel
                )
                guard report else { return }
                self.send(.pointerExitedHotZone)
            }
            panel.contentView = host
            panel.orderFrontRegardless()
            hotZonePanels.append(panel)
        }
    }

    /// 找回某个热区面板对应的屏幕几何。面板顺序与 `NSScreen.screens` 一致。
    private func geometryFor(_ panel: HotZonePanel) -> ScreenGeometry? {
        guard let index = hotZonePanels.firstIndex(where: { $0 === panel }) else { return nil }
        let screens = NSScreen.screens
        guard index < screens.count else { return nil }
        return ScreenGeometry(screen: screens[index])
    }

    /// 刷新全部几何。显示器配置或菜单栏可见性变化后调用。
    func refreshLayout() {
        geometry = ScreenGeometry.current(location: pointerLocation())
        if state == .hidden {
            rebuildHotZones()
        } else {
            // 展开中换屏：把面板移到新屏幕，热区跟着重建。
            rebuildHotZones()
            if let hubPanel, let geometry {
                hubPanel.setFrame(geometry.expandedRect, display: true)
            }
        }
        applyVisibility()
    }

    private func observeSystemChanges() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLayout() }
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLayout() }
        })
    }
}

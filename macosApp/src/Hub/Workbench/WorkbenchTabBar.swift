import SwiftUI

/// 顶栏上的一个工作区。
///
/// 视图不直接拿 `PaneInstance`：那是 Kotlin 的类，名字随时可能被配置改掉。
/// 这里只留画一条页签要用的三样。
struct PaneItem: Identifiable, Equatable, Sendable {
    let id: String
    let tab: HubTab
    /// 已经解析好的显示名。用户改过名就是用户的名字。
    let title: String
}

/// 页签拖动排序的换算。
///
/// 一次拖动里 `onChanged` 连着来，`translation` 是从起点累计的。
/// 所以每次都只补上「这一次新跨过的条数」，不把累计值重算一遍：
/// 重算会把已经挪过的位置再挪一次，页签冲过头。
struct TabReorderState {
    /// 已经补过的条数。
    private(set) var applied = 0
    /// 跨过一条页签要拖多少点。
    private let step: CGFloat

    init(step: CGFloat) {
        self.step = step
    }

    /// 这一次该往哪边挪几条。零表示还没跨过一条。
    mutating func delta(forTranslation width: CGFloat) -> Int {
        guard step > 0 else { return 0 }
        let steps = Int(width / step)
        defer { applied = steps }
        return steps - applied
    }

    /// 松手，下一次拖动从头计。
    mutating func reset() {
        applied = 0
    }
}

/// 挂帘顶部的横向页签栏。合同 `component/tab-bar`，`nativeSize` 是 960 × 46。
///
/// 左端固定是首页入口，紧挨着搜索框，中间是工作区页签，右端是当前页的动作。
/// 导航按钮默认透明。选中态使用淡强调色 regular 玻璃。
/// 指针悬停与键盘焦点使用 regular 玻璃，并叠加高对比焦点环。
/// 编辑模式里页签前面加拖动把手，横向拖过 84 点换一次位置。
struct WorkbenchTabBar: View {
    let panes: [PaneItem]
    let destination: HubDestination
    let isEditing: Bool
    let searchPlaceholder: LocalizedCopy
    @Binding var searchText: String
    let language: AppLanguage
    let pageAction: LocalizedCopy?
    let reduceMotion: Bool
    let onHome: () -> Void
    let onSelect: (String) -> Void
    let onReorder: (Int, Int) -> Void
    let onPageAction: () -> Void
    /// 指针进出某个目的地。切换判定住在 `WorkbenchModel` 里，这里只转达。
    ///
    /// 顶栏上表示「去哪里」的两处 —— 首页入口与工作区页签 —— 都报。
    /// 搜索框与右端的动作按钮不报：它们表示「做什么」，滑过不该换页。
    let onHover: (HubDestination, Bool) -> Void

    /// 正在拖的页签 id，与这一次拖动已经挪过的条数。
    @State private var reorderID: String?
    @State private var reorder = TabReorderState(step: HubMetrics.tabReorderStep)
    /// 指针当前所在的导航按钮。未选中按钮只在指针进入时显示玻璃。
    @State private var hoveredTarget: NavigationGlassTarget?
    /// 键盘焦点所在的导航按钮。焦点态同样显示玻璃。
    @FocusState private var focusedTarget: NavigationGlassTarget?
    /// 搜索框的键盘焦点。搜索框不是目的地，所以单独保存焦点状态。
    @FocusState private var searchFocused: Bool
    var body: some View {
        HStack(spacing: HubMetrics.tabBarItemGap) {
            homeEntry
            searchField
            tabStrip
            // 页签不够宽时，空位留在页签与动作位之间。左侧元素的位置因此不随页面变。
            Spacer(minLength: 0)
            pageActionSlot
        }
        .padding(.horizontal, HubMetrics.tabBarHPadding)
        .frame(width: HubMetrics.tabBarWidth, height: HubMetrics.tabBarHeight)
        .controlSize(.small)
        .animation(selectionAnimation, value: destination)
        .animation(interactionAnimation, value: hoveredTarget)
        .animation(interactionAnimation, value: focusedTarget)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ContractCopy.copyNavRailLabel.text(for: language))
    }

    // MARK: - 首页入口

    /// 固定在左端，不参与排序，也不随页签滚动。
    private var homeEntry: some View {
        let isSelected = destination == .home
        return Button(action: onHome) {
            homeLabel
                .contentShape(Rectangle())
                .background { navigationBackground(for: .home, isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .focused($focusedTarget, equals: .home)
        .overlay { navigationFocusRing(for: .home) }
        .accessibilityLabel(ContractCopy.copyHubActionHome.text(for: language))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .onHover { inside in
            hoveredTarget = inside ? .home : nil
            onHover(.home, inside)
        }
    }

    // MARK: - 搜索

    private var searchField: some View {
        HStack(spacing: MacTheme.space2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
                .disabled(isEditing)

            if !searchText.isEmpty, !isEditing {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.textSecondary)
                        .frame(width: 16, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ContractCopy.copyHubSearchClear.text(for: language))
            }
        }
        .padding(.leading, MacTheme.space3)
        .padding(.trailing, MacTheme.space2)
        .frame(width: HubMetrics.searchFieldWidth, height: HubMetrics.searchFieldHeight)
        .glassEffect(.regular.interactive(), in: .capsule)
        .overlay { searchFocusRing }
        .opacity(isEditing ? 0.6 : 1)
        .accessibilityLabel(placeholder)
        .background {
            Button("") {
                searchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .disabled(isEditing)
        }
    }

    @ViewBuilder
    private var searchFocusRing: some View {
        if searchFocused {
            Capsule(style: .continuous)
                .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                .allowsHitTesting(false)
        }
    }

    private var placeholder: String {
        searchPlaceholder.text(for: language)
    }

    // MARK: - 页签

    @ViewBuilder
    private var tabStrip: some View {
        if HubMetrics.tabsWidth(count: panes.count) <= HubMetrics.tabStripWidth {
            tabRow
        } else {
            ScrollView(.horizontal) {
                tabRow
            }
            .scrollIndicators(.never)
        }
    }

    private var tabRow: some View {
        HStack(spacing: HubMetrics.tabGap) {
            ForEach(Array(panes.enumerated()), id: \.element.id) { _, pane in
                tab(pane)
            }
        }
        .padding(.vertical, 1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func tab(_ pane: PaneItem) -> some View {
        let isSelected = destination == .pane(id: pane.id)
        return Button {
            guard !isEditing else { return }
            onSelect(pane.id)
        } label: {
            tabLabel(pane, isSelected: isSelected)
                .contentShape(Rectangle())
                .background {
                    navigationBackground(for: .pane(pane.id), isSelected: isSelected)
                }
        }
        .buttonStyle(.plain)
        .focused($focusedTarget, equals: .pane(pane.id))
        .overlay { navigationFocusRing(for: .pane(pane.id)) }
        .accessibilityLabel(pane.title)
        .accessibilityHint(pane.tab.summary.text(for: language))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .onHover { inside in
            hoveredTarget = inside ? .pane(pane.id) : nil
            onHover(.pane(id: pane.id), inside)
        }
        .gesture(isEditing ? reorderGesture(pane: pane) : nil)
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: HubMotion.tabSwitch)
    }

    private var interactionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: HubMotion.tabSwitch)
    }

    private var homeLabel: some View {
        Text(ContractCopy.copyHubActionHome.text(for: language))
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .padding(.horizontal, HubMetrics.tabHPadding)
            .frame(minWidth: HubMetrics.homeEntryWidth, minHeight: HubMetrics.homeEntryHeight)
    }

    private func tabLabel(_ pane: PaneItem, isSelected: Bool) -> some View {
        HStack(spacing: MacTheme.space1) {
            if isEditing {
                Text("⣿")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(pane.title)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, HubMetrics.tabHPadding)
        .frame(width: HubMetrics.tabWidth, height: HubMetrics.tabHeight)
    }

    /// 导航高亮使用固定尺寸的颜色胶囊，不参与外层 Liquid Glass 合并。
    @ViewBuilder
    private func navigationBackground(
        for target: NavigationGlassTarget,
        isSelected: Bool
    ) -> some View {
        if isSelected {
            Capsule(style: .continuous).fill(MacTheme.accent.opacity(0.24))
        } else if hoveredTarget == target || focusedTarget == target {
            Capsule(style: .continuous).fill(MacTheme.accent.opacity(0.12))
        } else {
            Color.clear
        }
    }

    private func actionGlass(for target: NavigationGlassTarget) -> Glass {
        hoveredTarget == target || focusedTarget == target
            ? .regular.tint(MacTheme.accent.opacity(0.12)).interactive()
            : .identity
    }

    @ViewBuilder
    private func navigationFocusRing(for target: NavigationGlassTarget) -> some View {
        if focusedTarget == target {
            Capsule(style: .continuous)
                .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                .allowsHitTesting(false)
        }
    }

    /// 编辑模式里的拖动排序。跨过一条页签的宽度就换一次位置。
    ///
    /// 每次都按 id 重新找当前下标：上一次换位之后页签已经挪了，
    /// 用闭包里那个旧下标会越挪越偏。
    private func reorderGesture(pane: PaneItem) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if reorderID != pane.id {
                    reorderID = pane.id
                    reorder.reset()
                }
                let delta = reorder.delta(forTranslation: value.translation.width)
                guard delta != 0,
                      !panes.isEmpty,
                      let current = panes.firstIndex(where: { $0.id == pane.id })
                else { return }
                let target = (current + delta).clamped(to: 0...(panes.count - 1))
                guard target != current else { return }
                onReorder(current, target)
            }
            .onEnded { _ in
                reorderID = nil
                reorder.reset()
            }
    }

    // MARK: - 当前页的动作

    /// 动作位至少占按钮的最小宽度，并贴住右端。
    ///
    /// 空位用定宽的 `Color.clear`。`Color.clear` 本身会吃满剩余宽度：
    /// 首页有按钮时整行居中，工作区没有按钮时整行贴左，切换页签时顶栏就整体横移。
    @ViewBuilder
    private var pageActionSlot: some View {
        if let pageAction {
            pageActionButton(pageAction)
        } else {
            Color.clear
                .frame(width: HubMetrics.actionButtonMinWidth, height: HubMetrics.tabHeight)
        }
    }

    private func pageActionButton(_ action: LocalizedCopy) -> some View {
        Button(action: onPageAction) {
            pageActionLabel(action)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedTarget, equals: .pageAction)
        .glassEffect(actionGlass(for: .pageAction), in: .capsule)
        .overlay { navigationFocusRing(for: .pageAction) }
        .accessibilityLabel(action.text(for: language))
        .onHover { hoveredTarget = $0 ? .pageAction : nil }
    }

    private func pageActionLabel(_ action: LocalizedCopy) -> some View {
        Text(action.text(for: language))
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, HubMetrics.actionHPadding)
            .frame(minWidth: HubMetrics.actionButtonMinWidth, minHeight: HubMetrics.tabHeight)
    }

}

private enum NavigationGlassTarget: Hashable {
    case home
    case pane(String)
    case pageAction
}

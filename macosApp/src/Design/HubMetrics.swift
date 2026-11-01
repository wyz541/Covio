import CoreGraphics

/// 挂帘面板的几何参数。
///
/// 来源有两处：
/// - `docs/covio-design-contract.json` 给组件的 `nativeSize`。
/// - `MacTheme` 的间距令牌，用来把高度按各段相加。
///
/// 冲突时以合同为准。`DesignContractTests` 会逐值比对。
///
/// 面板的组成是「悬浮顶栏 46 + 内容顶部留白 11 + 内容列」。内容列自带
/// 24 点内边距，里面是「页标题行 + 主体」。高度按各段相加，不写死一个数：
/// 少算一段会把底部裁掉。
enum HubMetrics {
    /// Hub 最小宽度 720 点。
    static let minWidth: CGFloat = 720

    /// Hub 最大宽度是屏幕宽度减 80 点。
    static let horizontalScreenMargin: CGFloat = 80

    /// Hub 最大高度是屏幕高度减 120 点。
    static let verticalScreenMargin: CGFloat = 120

    // MARK: - 面板

    /// 面板宽度 960 点。合同 `component/tab-bar` 的 `nativeSize.width`。
    static let panelWidth: CGFloat = 960

    /// 面板内边距 24 点。合同 `token/space/6`。
    static let panelPadding: CGFloat = MacTheme.space6

    /// 内容列宽度。等于面板宽度减去两边内边距。
    ///
    /// 960 − 24 × 2 = 912。合同 `component/page-title` 的 `nativeSize.width`。
    static var contentColumnWidth: CGFloat { panelWidth - panelPadding * 2 }

    // MARK: - 功能层

    /// 导航层底部到初始内容顶部的留白 11 点。
    ///
    /// 内容本身延伸到导航层背后。这条留白只防止首屏内容被导航层压住，
    /// 不是可见的板间距。
    static let navigationContentGap: CGFloat = 11

    /// 顶栏与菜单栏之间的缝 11 点。
    ///
    /// 控制中心最上面那个模块离菜单栏也有一段。取与内容顶部留白同值，
    /// 整个组合的节奏才一致。
    ///
    /// 它算进面板窗口的高度，但不进卡片的 frame：进了的话挂帘收起时会先露出
    /// 一条空缝，再露出顶栏。
    static let plateTopInset: CGFloat = 11

    /// 内容区底板的圆角 23 点。
    ///
    /// 控制中心的面板是一块圆角矩形，实测圆角约 22 点，面板高约 558 点。
    /// 取 23 与顶栏同值：导航层与内容层属于同一族。
    ///
    /// 卡片在底板上面，圆角 16 点，比底板小 —— 内层的圆角要小于外层。
    static let contentPlateRadius: CGFloat = 23

    // MARK: - 顶栏

    /// 顶栏高度 46 点。合同 `component/tab-bar` 的 `nativeSize.height`。
    static let tabBarHeight: CGFloat = 46

    /// 顶栏宽度。与面板同宽，内边距由顶栏自己留。
    static var tabBarWidth: CGFloat { panelWidth }

    /// 内容列的顶部内边距。首屏内容从导航层下方开始。
    ///
    /// 导航层叠在内容上。滚动后，内容可以从导航层背后经过。
    static var contentTopPadding: CGFloat {
        tabBarHeight + navigationContentGap + panelPadding
    }

    /// 顶栏横向内边距。
    static let tabBarHPadding: CGFloat = MacTheme.space6

    /// 顶栏里各件之间的间距。
    static let tabBarItemGap: CGFloat = MacTheme.space2

    /// 首页入口按钮。合同 `component/button` 的命中区下限是 24 点。
    static let homeEntryWidth: CGFloat = 52
    static let homeEntryHeight: CGFloat = 30

    /// 搜索框。
    static let searchFieldWidth: CGFloat = 190
    static let searchFieldHeight: CGFloat = 30

    /// 一条页签的高度。选中滑块也用它。
    static let tabHeight: CGFloat = 30

    /// 一条页签的固定宽度。文字超长时截断，不能把选中背景撑开。
    static let tabWidth: CGFloat = 72

    /// 页签之间的间距。
    static let tabGap: CGFloat = 4

    /// 页签的横向内边距。
    static let tabHPadding: CGFloat = MacTheme.space3

    /// 拖动换位时，跨过多少点算换一条页签。
    ///
    /// 页签宽度固定，换位步长还要算上页签间距。
    static let tabReorderStep: CGFloat = tabWidth + tabGap

    /// 右端动作按钮的横向内边距。
    static let actionHPadding: CGFloat = MacTheme.space3

    /// 顶栏里除页签区之外各件的宽度之和。
    ///
    /// 页签区占剩下的宽度，所以这个和必须小于内容列宽度。
    static var tabBarFixedWidth: CGFloat {
        homeEntryWidth + searchFieldWidth + actionButtonMinWidth
            + tabBarItemGap * 3
    }

    /// 顶栏留给工作区页签的宽度。
    static var tabStripWidth: CGFloat {
        tabBarWidth - tabBarHPadding * 2 - tabBarFixedWidth
    }

    /// 一排固定宽度页签的总宽度。
    static func tabsWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * tabWidth + CGFloat(count - 1) * tabGap
    }

    /// 动作按钮的最小宽度。四段文案最长是「设置」，两个字。
    static let actionButtonMinWidth: CGFloat = 52

    // MARK: - 内容列

    /// 内容列里各段之间的间距。
    static let pageGap: CGFloat = MacTheme.space3

    /// 页标题行的行高。合同 `component/page-title` 的 `nativeSize.height`。
    static let pageHeadingHeight: CGFloat = 24

    /// 页标题与主体之间的间距。
    static let pageHeadingGap: CGFloat = 10

    /// 工作区页操作行的行高。与页标题行使用同一尺寸。
    static let pageActionHeight: CGFloat = 24

    /// 工作区页操作行与主体之间的间距。
    static let pageActionGap: CGFloat = 10

    /// 搜索结果一条的高度。
    ///
    /// 结果列表现在排在内容列里，内边距由内容列给，所以直接用设置行的行高，
    /// 不再像左栏时代那样减掉一层。
    static let searchRowHeight: CGFloat = MacControlSize.settingRowHeight

    // MARK: - bento 网格

    /// 网格列数。
    static let bentoColumns = 4

    /// 一块卡片最多跨几行。档位只有 1×1、2×1、1×2、2×2 四种，所以上限是 2。
    static let bentoMaxRows = 2

    /// 网格行高 96 点。
    static let bentoRowHeight: CGFloat = 96

    /// 卡片之间的间距 12 点。合同 `token/space/3`。
    static let bentoGap: CGFloat = MacTheme.space3

    /// 卡片圆角 16 点。合同 `token/radius/large`。
    static let bentoCardRadius: CGFloat = 16

    /// 卡片内边距 14 点。
    static let bentoCardPadding: CGFloat = 14

    /// 卡片右上角删除钮的直径。
    static let bentoDeleteSize: CGFloat = 20

    /// 卡片右下角缩放手柄的边长。合同要求命中区不小于 24 点。
    static let bentoResizeSize: CGFloat = 26

    /// 列宽。(912 − 12 × 3) / 4 = 219 点。合同 `component/widget-card` 的 `nativeSize.width`。
    static var bentoColumnWidth: CGFloat {
        (contentColumnWidth - bentoGap * CGFloat(bentoColumns - 1)) / CGFloat(bentoColumns)
    }

    /// 一列跨到下一列的步长。
    static var bentoColumnStep: CGFloat { bentoColumnWidth + bentoGap }

    /// 一行跨到下一行的步长。
    static var bentoRowStep: CGFloat { bentoRowHeight + bentoGap }

    /// 一块跨 `columns` 列的卡片宽度。中间那几条间距也算进来。
    static func bentoCardWidth(columns: Int) -> CGFloat {
        guard columns > 1 else { return bentoColumnWidth }
        return bentoColumnWidth * CGFloat(columns) + bentoGap * CGFloat(columns - 1)
    }

    /// 一块跨 `rows` 行的卡片高度。
    static func bentoCardHeight(rows: Int) -> CGFloat {
        guard rows > 1 else { return bentoRowHeight }
        return bentoRowHeight * CGFloat(rows) + bentoGap * CGFloat(rows - 1)
    }

    /// 网格高度。零行时是零。
    static func bentoGridHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * bentoRowHeight + CGFloat(rows - 1) * bentoGap
    }

    /// 首页没有组件时那块提示的高度。
    static let emptyHomeHeight: CGFloat = 160

    /// 默认的首页行数。六块默认组件装箱后是四行。
    ///
    /// 只用于预览与测试的默认参数。真机上由 `BentoPacker` 按实际组件算。
    static let defaultHomeRows = 4

    // MARK: - 编辑模式

    /// 编辑提示条的高度。按钮 28 点加上下内边距 8 点。
    static let editBannerHeight: CGFloat = 44

    // MARK: - 页内容

    /// 占位页的主体高度。占位页只有一张说明卡。
    static let placeholderBodyHeight: CGFloat = 180

    /// 监控页的卡片高度。两行卡片加间距和工具栏正好填满主体。
    static let monitorCardHeight: CGFloat = 236

    /// 监控页工具栏的高度。左侧是实时状态，右侧是概览与电源切换。
    static let monitorToolbarHeight: CGFloat = 24

    /// 监控页的主体高度：工具栏、三行卡片与三处间距。
    static let monitorBodyHeight: CGFloat = monitorToolbarHeight + MacTheme.space2 + monitorCardHeight * 3 + MacTheme.space3 * 2

    /// 设置页的主体高度。五个分节共用，内容超出时页内滚动。
    static let settingsBodyHeight: CGFloat = 500

    /// 剪切板页的主体高度：列表区、提示条与它们之间的间距。
    ///
    /// 提示条可能出现也可能不出现，所以按它出现算，宁可多留一点也不裁掉。
    static var clipboardBodyHeight: CGFloat {
        ClipboardTabView.listHeight + ClipboardTabView.noticeGap + ClipboardTabView.noticeHeight
    }

    /// 文件区主体高度。`component/file-area` 的合同尺寸是 912 × 538。
    static let filesBodyHeight: CGFloat = FileAreaMetrics.areaHeight

    /// Agent 页的主体高度：对话区、确认卡和输入框。
    static let agentBodyHeight: CGFloat = 580
    static let agentTranscriptHeight: CGFloat = 430
    static let agentComposerHeight: CGFloat = 34

    /// 某个页面的主体高度，不含页标题行。
    static func bodyHeight(for page: HubPage) -> CGFloat {
        switch page {
        case .home(let rows):
            rows > 0 ? bentoGridHeight(rows: rows) : emptyHomeHeight
        case .pane(let tab):
            switch tab {
            case .devices: monitorBodyHeight
            case .now, .board: placeholderBodyHeight
            case .settings: settingsBodyHeight
            case .clipboard: clipboardBodyHeight
            case .files: filesBodyHeight
            case .agent: agentBodyHeight
            }
        }
    }

    /// 内容列里页操作行加主体的高度。
    ///
    /// 页签已经显示页面身份。只有带页面动作的工作区保留操作行。
    static func pageContentHeight(for page: HubPage) -> CGFloat {
        switch page {
        case .home:
            return bodyHeight(for: page)
        case .pane(let tab):
            let actionRow = tab.hasInlineActions ? pageActionHeight + pageActionGap : 0
            return actionRow + bodyHeight(for: page)
        }
    }

    /// 导航层与内容层共用的高度：顶栏、内容顶部留白与内容列。
    ///
    /// 内容板里面是内容列的内边距与页内容。编辑模式在内容列顶部多一条提示条，
    /// 提示条下面留一段间距。
    ///
    /// 与菜单栏之间那条缝不在这里，见 [plateTopInset]。卡片按这个高度排，
    /// 面板窗口按 [contentHeight] 排。
    static func plateStackHeight(for page: HubPage, editing: Bool = false) -> CGFloat {
        let chrome = tabBarHeight + navigationContentGap + panelPadding * 2
        let banner = editing ? editBannerHeight + pageGap : 0
        return chrome + banner + pageContentHeight(for: page)
    }

    /// 某个页面的面板高度。面板窗口的高度由它决定。
    ///
    /// 等于内容层的高度加上与菜单栏之间的缝。内边距已经算在 `plateStackHeight`
    /// 里，所以这里不再加一次。
    ///
    /// `HubView` 的卡片 frame 用 `plateStackHeight`，窗口 frame 用这个值。
    /// 两边不一致会把内容裁掉。
    static func contentHeight(for page: HubPage, editing: Bool = false) -> CGFloat {
        plateTopInset + plateStackHeight(for: page, editing: editing)
    }

    // MARK: - 菜单栏

    /// 菜单栏项的命中区。来源是合同 `component/tray-icon` 的 `nativeSize`。
    static let trayIconHitTarget: CGFloat = 44

    /// 合同 `accessibilityRules`：交互目标不小于 24 点，主控件尽量 44 点。
    static let minHitTarget: CGFloat = 24
    static let preferredHitTarget: CGFloat = 44

    /// 非刘海屏的热区尺寸。热区在菜单栏下方，所以做得又窄又薄。
    static let notchlessHotZoneWidth: CGFloat = 200
    static let notchlessHotZoneHeight: CGFloat = 6

    // MARK: - 屏幕

    /// Hub 宽度。以面板宽度为基准，限制在最小宽度与屏幕宽度减 80 之间。
    static func hubWidth(screenWidth: CGFloat) -> CGFloat {
        let maximum = max(minWidth, screenWidth - horizontalScreenMargin)
        return min(max(panelWidth, minWidth), maximum)
    }

    /// Hub 的最大高度。
    static func hubMaxHeight(screenHeight: CGFloat) -> CGFloat {
        max(0, screenHeight - verticalScreenMargin)
    }

    /// 展开态的面板高度。
    ///
    /// 不给 `contentHeight` 时用首页的高度。
    static func expandedHeight(
        safeAreaTop: CGFloat,
        screenHeight: CGFloat,
        contentHeight: CGFloat = HubMetrics.contentHeight(for: .home(rows: defaultHomeRows))
    ) -> CGFloat {
        let chrome = safeAreaTop + contentHeight
        return min(chrome, hubMaxHeight(screenHeight: screenHeight))
    }
}

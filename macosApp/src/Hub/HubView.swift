import AppKit
import SwiftUI

/// Hub 面板的根视图。
///
/// 面板窗口的尺寸在屏幕变化时固定下来。展开与收起只改内容的高度，
/// 所以视觉上是一条从顶部垂下来的窗帘。
///
/// 顶栏是悬浮在内容上的功能层。内容延伸到顶栏背后，并从顶栏下方开始首屏排版。
/// 顶栏不绘制独立底材，导航控件直接叠在内容层的同一 surface 上。
/// 视觉关系参考 macOS 26 Tahoe 的 Apple Maps。
/// 顶栏与菜单栏之间留一条 11 点的缝，收起时不会先露出空板。
///
/// 内容板自带 24 点内边距。页签栏提供页面标识，内容区直接从页面主体开始。
/// 需要页面动作的工作区保留一条操作行。
///
/// 这个视图不持有控制器，只接收值。这样它可以被预览与测试。
struct HubView: View {
    let geometry: ScreenGeometry
    let isExpanded: Bool
    let reduceMotion: Bool
    let hubState: HubState
    let outputState: HubOutputState
    @Bindable var workbench: WorkbenchModel
    /// 外壳的共享状态。搜索文字与设置分节住在这里。
    @Bindable var chrome: HubChromeModel
    let runtime: AppRuntime?
    /// Popover 打开时用它通知控制器暂停自动收起。
    var popoverCoordinator: HubPopoverCoordinator? = nil
    /// 预览与测试没有运行时，用这个语言取文案。
    var previewLanguage: AppLanguage = CopyLocale.language

    var body: some View {
        VStack(spacing: 0) {
            // 刘海屏要让开刘海那一条。非刘海屏这里是 0。
            Color.clear
                .frame(height: geometry.panelTopInset)

            // 顶栏与菜单栏之间的缝。排在内容层外面：进了内容层的话，挂帘收起时
            // 会先露出一条空缝，再露出顶栏。
            Color.clear
                .frame(height: HubMetrics.plateTopInset)

            navigationLayers
                .frame(height: isExpanded ? plateStackHeight : 0)
                .opacity(cardOpacity)
                .clipped()

            Spacer(minLength: 0)
        }
        .frame(
            width: geometry.expandedRect.width,
            height: geometry.expandedRect.height,
            alignment: .top
        )
        // 宿主给固定外壳更大或更小的尺寸时，内容始终贴着顶部。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(curtainAnimation, value: isExpanded)
        .onChange(of: workbench.destination) { _, _ in
            chrome.clearSearch()
            if !isClipboardDestination {
                chrome.clearClipboardSelection()
            }
        }
    }

    /// 导航层与内容层共用的固定高度。
    private var plateStackHeight: CGFloat {
        geometry.shellPlateStackHeight
    }

    /// 减弱动态效果时只改透明度，不做位移。
    private var cardOpacity: Double {
        guard reduceMotion else { return 1 }
        return isExpanded ? 1 : 0
    }

    private var curtainAnimation: Animation {
        if reduceMotion {
            return .linear(duration: HubMotion.reducedMotion)
        }
        return isExpanded
            ? .spring(response: HubMotion.expand, dampingFraction: 0.82)
            : .easeOut(duration: HubMotion.collapse)
    }

    /// 当前界面语言。运行时缺失时（预览、测试）跟随系统。
    private var language: AppLanguage { runtime?.language ?? previewLanguage }

    // MARK: - 功能层

    /// 内容层与悬浮的导航控件。
    ///
    /// 内容区先铺满整个面板。顶栏控件最后叠在内容之上，所以内容在视觉与布局上
    /// 都延伸到导航层背后。顶栏控件不创建第二层面板底材。
    private var navigationLayers: some View {
        ZStack(alignment: .top) {
            // 底板独立成背景层。它不能进入下面的 GlassEffectContainer，
            // 否则大底板会与导航控件的局部玻璃合并，干扰控件文字。
            plateLayer
            GlassEffectContainer(spacing: 0) {
                ZStack(alignment: .top) {
                    contentArea
                    topBarLayer
                }
            }
        }
        .frame(width: HubMetrics.panelWidth, height: plateStackHeight, alignment: .top)
        .overlay(alignment: .bottomTrailing) {
            if let runtime, let update = runtime.availableUpdate {
                WorkbenchUpdateBadge(
                    version: update.version,
                    language: language,
                    isChecking: runtime.isCheckingForUpdates
                ) {
                    runtime.checkForUpdates(manual: true)
                }
                .padding(.trailing, HubMetrics.panelPadding)
                .padding(.bottom, HubMetrics.panelPadding)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: HubMotion.tabSwitch),
            value: runtime?.availableUpdate?.version
        )
        // 高亮行从环境里取，六个设置页不必各自拿一遍模型。
        .environment(\.highlightedSettingsRow, chrome.highlightedRowID)
    }

    /// 内容底板。默认是 Liquid Glass；`.system` 可供调试对照。
    private var plateLayer: some View {
        Color.clear
            .frame(width: HubMetrics.panelWidth, height: plateStackHeight)
            .glassSurface(
                cornerRadius: HubMetrics.contentPlateRadius,
                tint: GlassSurfaceMode.plateTint,
                mode: GlassSurfaceMode.plateMode
            )
            .allowsHitTesting(false)
    }

    private var topBarLayer: some View {
        WorkbenchTabBar(
            panes: workbench.panes(language: language),
            destination: workbench.destination,
            isEditing: workbench.isEditing,
            searchPlaceholder: isClipboardDestination
                ? ContractCopy.copyClipboardSearchPlaceholder
                : ContractCopy.copyNavSearchPlaceholder,
            searchText: $chrome.searchText,
            language: language,
            pageAction: workbench.pageAction,
            reduceMotion: reduceMotion,
            onHome: { workbench.destination = .home },
            onSelect: { workbench.select(paneID: $0) },
            onReorder: { workbench.movePane(from: $0, to: $1) },
            onPageAction: { workbench.performPageAction() },
            onHover: reportHover
        )
    }

    /// 指针进出的上报。切换判定住在 `WorkbenchModel` 里，这里只转达。
    private func reportHover(_ destination: HubDestination, inside: Bool) {
        if inside { workbench.pointerEntered(destination) }
        else { workbench.pointerExited(destination) }
    }

    /// 内容层铺满整个面板，顶栏叠在它上方。
    ///
    /// 内容底材默认走 Liquid Glass。卡片叠在内容层里，不带着色。
    private var contentArea: some View {
        contentColumn
            .frame(width: HubMetrics.panelWidth, height: plateStackHeight, alignment: .top)
    }

    // MARK: - 内容列

    private var contentColumn: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: HubMetrics.pageGap) {
                if workbench.isEditing {
                    EditBanner(
                        paneCount: workbench.visiblePaneCount,
                        widgetCount: workbench.homeWidgets.count,
                        language: language
                    ) { workbench.isEditing = false }
                }

                if isSettingsSearch {
                    SettingsSearchResults(chrome: chrome, language: language) { hit in
                        _ = workbench.openSettings()
                        chrome.reveal(hit)
                    }
                } else {
                    pageContent
                }
            }
            .padding(.horizontal, HubMetrics.panelPadding)
            .padding(.top, HubMetrics.contentTopPadding)
            .padding(.bottom, HubMetrics.panelPadding)
            .frame(width: HubMetrics.panelWidth, alignment: .topLeading)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// 顶部搜索框在非剪切板页签里显示工作区与设置结果。
    /// 剪切板页签直接过滤当前列表，所以不切换到设置搜索结果。
    private var isSettingsSearch: Bool {
        !isClipboardDestination &&
            !chrome.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isClipboardDestination: Bool {
        guard case .pane(let id) = workbench.destination else { return false }
        return workbench.config.pane(id: id)?.kind == PaneKind.clipboard
    }

    // MARK: - 页内容

    @ViewBuilder
    private var pageContent: some View {
        switch workbench.destination {
        case .home:
            homeContent
        case .pane:
            HubTabContent(
                tab: workbench.tab(for: workbench.destination),
                workbench: workbench,
                chrome: chrome,
                hubState: hubState,
                outputState: outputState,
                language: language,
                runtime: runtime,
                popoverCoordinator: popoverCoordinator,
                searchText: chrome.searchText
            )
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        if workbench.homeWidgets.isEmpty {
            EmptyHomeView(isEditing: workbench.isEditing, language: language)
        } else {
            BentoGrid(
                widgets: workbench.homeWidgets,
                isEditing: workbench.isEditing,
                language: language,
                runtime: runtime,
                onMove: { id, column, row in
                    workbench.moveWidget(id: id, toColumn: column, toRow: row)
                },
                onResize: { id, size in workbench.resizeWidget(id: id, to: size) },
                onDelete: { workbench.removeWidget(id: $0) }
            )
        }
    }
}

/// 首页为空时的提示。
struct EmptyHomeView: View {
    let isEditing: Bool
    let language: AppLanguage

    var body: some View {
        VStack(spacing: MacTheme.space2) {
            Text(ContractCopy.copyHubHomeEmptyTitle.text(for: language))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textSecondary)
        }
        .frame(width: HubMetrics.contentColumnWidth, height: HubMetrics.emptyHomeHeight)
        .background(
            MacTheme.material,
            in: RoundedRectangle(cornerRadius: HubMetrics.bentoCardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: HubMetrics.bentoCardRadius, style: .continuous)
                .strokeBorder(MacTheme.divider, lineWidth: 1)
        )
        .glassSurface(cornerRadius: HubMetrics.bentoCardRadius)
    }

    private var hint: String {
        let copy = isEditing
            ? ContractCopy.copyHubHomeEmptyHintEditing
            : ContractCopy.copyHubHomeEmptyHint
        return copy.text(for: language)
    }
}

/// 页签内容的分发。
///
/// 设置页、截图页、剪切板页与文件页已经有真实内容。其余页签还是占位。
/// 运行时缺失时（预览、测试）一律显示占位。
struct HubTabContent: View {
    let tab: HubTab
    let workbench: WorkbenchModel
    @Bindable var chrome: HubChromeModel
    let hubState: HubState
    let outputState: HubOutputState
    let language: AppLanguage
    let runtime: AppRuntime?
    let popoverCoordinator: HubPopoverCoordinator?
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: HubMetrics.pageActionGap) {
            if tab.hasInlineActions {
                PaneActionRow {
                    pageActions
                }
            }

            body(width: HubMetrics.contentColumnWidth)
                .frame(
                    width: HubMetrics.contentColumnWidth,
                    height: HubMetrics.bodyHeight(for: .pane(tab)),
                    alignment: .topLeading
                )
        }
    }

    /// 工作区页操作行里的动作。
    @ViewBuilder
    private var pageActions: some View {
        if let runtime {
            switch tab {
            case .agent:
                AgentHeadingActions(agent: runtime.agent, language: language)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func body(width: CGFloat) -> some View {
        if tab == .devices {
            MonitorTabView(
                language: language,
                runtime: runtime,
                popoverCoordinator: popoverCoordinator
            )
        } else if let runtime, tab == .settings {
            SettingsTabView(runtime: runtime, section: chrome.settingsSection, chrome: chrome)
        } else if let runtime, tab == .clipboard {
            ClipboardTabView(
                clipboard: runtime.clipboard,
                runtime: runtime,
                searchText: searchText,
                selection: $chrome.clipboardSelectionID,
                onClearSearch: { chrome.clearSearch() }
            )
        } else if let runtime, tab == .files {
            FilesTabView(
                shelf: runtime.shelf,
                workspace: runtime.workspace,
                transfer: runtime.transfer,
                autoNaming: runtime.autoNaming,
                modelSetup: runtime.modelSetup,
                policy: runtime.config.fileNaming,
                language: language,
                searchText: chrome.searchText,
                requestedFilter: workbench.pendingFileFilter,
                onConsumeRequestedFilter: workbench.consumeFileFilterRequest
            )
        } else if let runtime, tab == .agent {
            AgentTabView(
                agent: runtime.agent,
                language: language,
                modelSetup: runtime.modelSetup
            )
        } else {
            HubPlaceholderView(
                tab: tab,
                hubState: hubState,
                outputState: outputState,
                language: language
            )
        }
    }
}

/// 页签内容的占位。
///
/// 还没落地的页签显示模块说明，证明页签切换生效。
/// `#if DEBUG` 的那段是插桩 HUD，对应风险清单 R2：
/// 手工验证面板行为时常显 `hubState`、内容态与前台应用。
struct HubPlaceholderView: View {
    let tab: HubTab
    let hubState: HubState
    let outputState: HubOutputState
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space3) {
            MacCard {
                Text(ContractCopy.copyHubPlaceholderNotice.text(for: language))
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.textSecondary)
            }

            Spacer(minLength: 0)

            #if DEBUG
            Divider()
            Text(hud)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            #endif
        }
        .padding(.horizontal, MacTheme.space4)
        .padding(.vertical, MacTheme.space3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    #if DEBUG
    private var hud: String {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
        return """
        tab=\(tab.rawValue) hub=\(hubState.rawValue) output=\(outputState.rawValue)
        frontmost=\(frontmost)
        """
    }
    #endif
}

import AppKit
import Observation
import SwiftUI

/// SwiftUI Settings 场景可能在运行时创建前就实例化，所以单独发布运行时。
@MainActor
@Observable
final class SettingsRuntimeProvider {
    var runtime: AppRuntime?
}

struct SettingsSceneRoot: View {
    @Bindable var runtimeProvider: SettingsRuntimeProvider
    let chrome: HubChromeModel
    let onSettingsAppear: () -> Void

    var body: some View {
        if let runtime = runtimeProvider.runtime {
            CovioSettingsView(
                runtime: runtime,
                chrome: chrome,
                onSettingsAppear: onSettingsAppear
            )
        } else {
            ProgressView()
                .frame(
                    width: SettingsWindowMetrics.contentSize.width,
                    height: SettingsWindowMetrics.contentSize.height
                )
        }
    }
}

/// 原生 Settings 场景的内容。
///
/// `TabView` 在 macOS Settings 场景里生成系统工具栏分页。Liquid Glass 由系统
/// 工具栏、搜索框和标准控件提供；内容层使用 grouped `Form`，不重复绘制玻璃。
struct CovioSettingsView: View {
    let runtime: AppRuntime
    @Bindable var chrome: HubChromeModel
    var onSettingsAppear: () -> Void = {}

    var body: some View {
        TabView(selection: $chrome.settingsSection) {
            tab(.overview) {
                CovioSettingsPane(runtime: runtime, section: .overview, chrome: chrome) {
                    OverviewPage(runtime: runtime)
                }
            }
            tab(.battery) {
                CovioSettingsPane(runtime: runtime, section: .battery, chrome: chrome) {
                    BatteryPage(runtime: runtime)
                }
            }
            tab(.idle) {
                CovioSettingsPane(runtime: runtime, section: .idle, chrome: chrome) {
                    IdlePage(runtime: runtime)
                }
            }
            tab(.clipboard) {
                CovioSettingsPane(runtime: runtime, section: .clipboard, chrome: chrome) {
                    ClipboardPage(runtime: runtime)
                }
            }
            tab(.assistant) {
                CovioSettingsPane(runtime: runtime, section: .assistant, chrome: chrome) {
                    AssistantPage(runtime: runtime)
                }
            }
            tab(.general) {
                CovioSettingsPane(runtime: runtime, section: .general, chrome: chrome) {
                    GeneralPage(runtime: runtime)
                }
            }
        }
        .scenePadding()
        .frame(
            width: SettingsWindowMetrics.contentSize.width,
            height: SettingsWindowMetrics.contentSize.height
        )
        .searchable(
            text: $chrome.searchText,
            placement: .toolbar,
            prompt: Text(ContractCopy.copySettingsSearchPlaceholder.text(for: runtime.language))
        )
        .onExitCommand { chrome.clearSearch() }
        .environment(\.settingsContentSurface, true)
        .onAppear(perform: onSettingsAppear)
        .background(
            SettingsWindowConfigurator(title: windowTitle)
                .frame(width: 0, height: 0)
        )
    }

    private var windowTitle: String {
        chrome.settingsSection.pageTitle.text(for: runtime.language)
    }

    private func tab<Content: View>(
        _ section: SettingsSection,
        @ViewBuilder content: () -> Content
    ) -> some TabContent<SettingsSection> {
        Tab(
            section.navTitle.text(for: runtime.language),
            systemImage: section.symbolName,
            value: section,
            content: content
        )
    }
}

/// 单个设置分页。搜索结果显示在当前分页上方。
private struct CovioSettingsPane<Content: View>: View {
    let runtime: AppRuntime
    let section: SettingsSection
    let chrome: HubChromeModel
    @ViewBuilder var content: Content

    private var isSearching: Bool {
        !chrome.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .topLeading) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isSearching {
                    SettingsSearchResults(chrome: chrome, language: runtime.language) { hit in
                        chrome.reveal(hit)
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(SettingsWindowMetrics.overlayPadding)
                    .zIndex(1)
                }
            }
            .environment(\.highlightedSettingsRow, chrome.highlightedRowID)
            .onChange(of: chrome.revealCount) { _, _ in
                guard let target = chrome.scrollTarget else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
            .onAppear {
                guard chrome.highlightedRowID != nil, let target = chrome.scrollTarget else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
    }
}

enum SettingsWindowMetrics {
    static let contentSize = NSSize(width: 900, height: 640)
    static let overlayPadding: CGFloat = MacTheme.space6
    static let identifier = NSUserInterfaceItemIdentifier("CovioSettingsWindow")
}

private struct SettingsContentSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 设置窗口把内容层切换成系统表单材质，避免在内容层叠加 Liquid Glass。
    var settingsContentSurface: Bool {
        get { self[SettingsContentSurfaceKey.self] }
        set { self[SettingsContentSurfaceKey.self] = newValue }
    }
}

/// 把 SwiftUI Settings 场景的窗口配置成固定设置窗口。
private struct SettingsWindowConfigurator: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> SettingsWindowProbeView {
        let view = SettingsWindowProbeView()
        view.title = title
        return view
    }

    func updateNSView(_ nsView: SettingsWindowProbeView, context: Context) {
        nsView.title = title
        nsView.configureWindow()
    }
}

@MainActor
private final class SettingsWindowProbeView: NSView {
    var title = "" {
        didSet { configureWindow() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        window.identifier = SettingsWindowMetrics.identifier
        window.title = title
        window.tabbingMode = .disallowed
        window.contentMinSize = SettingsWindowMetrics.contentSize
        window.contentMaxSize = SettingsWindowMetrics.contentSize
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.toolbar?.allowsUserCustomization = false
        window.toolbar?.isVisible = true
    }
}

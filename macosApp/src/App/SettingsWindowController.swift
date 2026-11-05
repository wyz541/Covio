import AppKit
import SwiftUI

/// 独立的设置窗口。
///
/// 设置不再嵌入工作台面板。窗口由应用代理持有，关闭后进程继续留在菜单栏。
@MainActor
final class SettingsWindowController: NSWindowController {
    static let contentSize = NSSize(width: 960, height: 640)
    static let minimumContentSize = NSSize(width: 760, height: 520)
    static let windowIdentifier = NSUserInterfaceItemIdentifier("CovioSettingsWindow")

    let chrome: HubChromeModel
    private let runtime: AppRuntime

    init(runtime: AppRuntime, chrome: HubChromeModel = HubChromeModel()) {
        self.runtime = runtime
        self.chrome = chrome

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = Self.windowIdentifier
        window.title = ContractCopy.copyHubTabSettings.text(for: runtime.language)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentMinSize = Self.minimumContentSize
        window.setFrameAutosaveName("CovioSettingsWindow")
        window.center()
        window.contentView = NSHostingView(
            rootView: SettingsWindowView(runtime: runtime, chrome: chrome)
                .onChange(of: runtime.language) { _, language in
                    window.title = ContractCopy.copyHubTabSettings.text(for: language)
                }
        )

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController 只支持代码创建")
    }

    /// 设置窗口是否仍在屏幕上或已最小化。
    var isOpen: Bool {
        guard let window else { return false }
        return window.isVisible || window.isMiniaturized
    }

    var selectedSection: SettingsSection { chrome.settingsSection }
    var scrollTarget: String? { chrome.scrollTarget }

    /// 打开设置窗口。窗口已经存在时只把它带到前台。
    func show(section: SettingsSection? = nil, reveal hit: SettingsSearchHit? = nil) {
        chrome.clearSearch()
        chrome.clearHighlight()
        if let section {
            chrome.select(section)
        }
        if let hit {
            chrome.select(hit.section)
        }

        bringForward()
        guard let hit else { return }
        // 新窗口要在第一帧排版之后才能滚到目标行。
        DispatchQueue.main.async { [weak self] in
            self?.chrome.reveal(hit)
        }
    }

    /// 把已有窗口带到前台。最小化时先恢复。
    func bringForward() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// 独立设置窗口的内容。搜索框在窗口标题栏下方，结果覆盖在设置内容上。
struct SettingsWindowView: View {
    let runtime: AppRuntime
    @Bindable var chrome: HubChromeModel

    private var language: AppLanguage { runtime.language }
    private var isSearching: Bool {
        !chrome.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()

            ZStack(alignment: .topLeading) {
                SettingsTabView(runtime: runtime, section: chrome.settingsSection, chrome: chrome)

                if isSearching {
                    SettingsSearchResults(chrome: chrome, language: language) { hit in
                        chrome.reveal(hit)
                    }
                    .padding(.horizontal, MacTheme.space4)
                    .padding(.top, MacTheme.space2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacTheme.canvas)
        .environment(\.highlightedSettingsRow, chrome.highlightedRowID)
        .onExitCommand { chrome.clearSearch() }
    }

    private var searchField: some View {
        HStack(spacing: MacTheme.space2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.textSecondary)
                .accessibilityHidden(true)

            TextField(
                ContractCopy.copySettingsSearchPlaceholder.text(for: language),
                text: $chrome.searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))

            if !chrome.searchText.isEmpty {
                Button {
                    chrome.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ContractCopy.copyStateCancel.text(for: language))
            }
        }
        .padding(.horizontal, MacTheme.space3)
        .frame(height: 34)
        .background(
            MacTheme.surface,
            in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
                .strokeBorder(MacTheme.divider, lineWidth: 1)
        )
        .accessibilityLabel(ContractCopy.copySettingsSearchPlaceholder.text(for: language))
        .padding(.horizontal, MacTheme.space4)
        .padding(.vertical, MacTheme.space3)
    }
}

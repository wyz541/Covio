import SwiftUI

/// 设置页签的根视图。
///
/// 分节切换在顶部胶囊里，页内不再自带分节导航：
/// 左边一列分节导航与左边的悬浮导航栏叠在一起会显得挤。
/// 这个视图只按传进来的分节显示内容，并让内容滚动。
///
/// 每一节的内容按固定信息顺序排列：
/// 最常用的开关在前，状态与危险动作在后。
struct SettingsTabView: View {
    let runtime: AppRuntime
    /// 当前分节。切换由 `HubChromeModel.settingsSection` 驱动。
    let section: SettingsSection
    /// 外壳的共享状态。搜索跳转时要滚到某一行。
    let chrome: HubChromeModel

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker

            ScrollViewReader { proxy in
                Group {
                    if section == .general {
                        GeneralPage(runtime: runtime)
                    } else {
                        ScrollView {
                            content
                                .padding(.horizontal, MacTheme.space4)
                                .padding(.vertical, MacTheme.space3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                // 跳转序号变了才滚，否则同一行连点两次不会重新滚。
                .onChange(of: chrome.revealCount) {
                    guard let target = chrome.scrollTarget else { return }
                    // 分节刚换过，内容要下一帧才排好，所以这一帧之后才滚。
                    DispatchQueue.main.async {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 设置分节导航。工作台页签不再承载子分节，所以导航固定在设置内容顶部。
    private var sectionPicker: some View {
        let sections = SettingsSection.allCases
        let selectedIndex = sections.firstIndex(of: section) ?? 0
        return HStack(spacing: MacTheme.space3) {
            Text(ContractCopy.copyHubTabSettings.text(for: runtime.language))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            MacSegmented(
                options: sections.map { $0.navTitle.text(for: runtime.language) },
                selectedIndex: selectedIndex,
                onSelect: { index in chrome.select(sections[index]) },
                accessibilityLabel: ContractCopy.copyHubTabSettings.text(for: runtime.language)
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, MacTheme.space4)
        .padding(.top, MacTheme.space3)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview: OverviewPage(runtime: runtime)
        case .battery: BatteryPage(runtime: runtime)
        case .idle: IdlePage(runtime: runtime)
        case .clipboard: ClipboardPage(runtime: runtime)
        case .assistant: AssistantPage(runtime: runtime)
        case .general: EmptyView()
        }
    }
}

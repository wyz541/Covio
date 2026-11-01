import SwiftUI

/// 页标题行。合同 `component/page-title`，`nativeSize` 是 912 × 24。
///
/// 标题 18 点半粗加一句说明 11 点次要色，底部对齐排一行，间距 10 点。
/// 右端挂当前页的动作。打样没画动作，动作原本在顶部胶囊里，胶囊没了要有地方去。
///
/// 首页没有标题行：打样的首页直接从网格开始。
struct PaneHeading<Action: View>: View {
    let title: String
    let summary: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .bottom, spacing: HubMetrics.pageHeadingGap) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)

            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(MacTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: MacTheme.space3)

            action
        }
        .frame(width: HubMetrics.contentColumnWidth, height: HubMetrics.pageHeadingHeight, alignment: .bottomLeading)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

extension PaneHeading where Action == EmptyView {
    init(title: String, summary: String) {
        self.init(title: title, summary: summary) { EmptyView() }
    }
}

/// 工作区页操作行。页签栏已经显示当前页面的名称与说明，内容区不重复标题。
/// 只有 Agent 这类需要页面动作的工作区使用这一行。
struct PaneActionRow<Action: View>: View {
    @ViewBuilder var action: Action

    var body: some View {
        HStack(alignment: .center, spacing: MacTheme.space3) {
            Spacer(minLength: 0)
            action
        }
        .frame(width: HubMetrics.contentColumnWidth, height: HubMetrics.pageActionHeight, alignment: .trailing)
        .accessibilityElement(children: .contain)
    }
}

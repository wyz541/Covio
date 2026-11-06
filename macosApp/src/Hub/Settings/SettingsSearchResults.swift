import SwiftUI

/// 搜索结果列表。浮在页内容上方。
///
/// 只在搜索框有字的时候出现。没有命中时显示一条「没有匹配的设置」。
/// 点一条就跳到那一项。
struct SettingsSearchResults: View {
    let chrome: HubChromeModel
    let language: AppLanguage
    let onSelect: (SettingsSearchHit) -> Void

    private var hits: [SettingsSearchHit] { chrome.results(language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space1) {
            header
            if hits.isEmpty {
                Text(ContractCopy.copyNavSearchEmpty.text(for: language))
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
                    .padding(.horizontal, MacTheme.space3)
                    .frame(height: HubMetrics.searchRowHeight)
            } else {
                ForEach(hits) { hit in
                    row(hit)
                }
            }
        }
        .padding(MacTheme.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                .strokeBorder(MacTheme.divider, lineWidth: 1)
        )
        .shadow(color: MacTheme.shadow.opacity(0.35), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        Text(ContractCopy.copyNavSearchResults.text(for: language))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MacTheme.textSecondary)
            .padding(.horizontal, MacTheme.space3)
    }

    private func row(_ hit: SettingsSearchHit) -> some View {
        Button {
            onSelect(hit)
        } label: {
            HStack(spacing: MacTheme.space2) {
                Text(hit.entry.title.text(for: language))
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: MacTheme.space2)
                // 分节名放右边，用户能看出这一项在哪一节。
                Text(hit.section.navTitle.text(for: language))
                    .font(.system(size: 10))
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, MacTheme.space3)
            .frame(height: HubMetrics.searchRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hit.entry.title.text(for: language))
        .accessibilityHint(hit.section.navTitle.text(for: language))
    }
}

import SwiftUI

/// 工作台右下角的更新入口。
///
/// 更新入口不放进顶栏，避免占用导航宽度或遮挡页签。
struct WorkbenchUpdateBadge: View {
    let version: String
    let language: AppLanguage
    let isChecking: Bool
    let onCheck: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onCheck) {
            HStack(spacing: MacTheme.space2) {
                if isChecking {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(MacTheme.textPrimary)
            .padding(.horizontal, HubMetrics.actionHPadding)
            .frame(minHeight: HubMetrics.tabHeight)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isChecking)
        .focused($isFocused)
        .glassEffect(updateGlass, in: .capsule)
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    isFocused ? Color(nsColor: .keyboardFocusIndicatorColor) : .clear,
                    lineWidth: 2
                )
                .allowsHitTesting(false)
        }
        .shadow(color: MacTheme.shadow.opacity(0.28), radius: 8, y: 4)
        .accessibilityLabel(title)
        .accessibilityHint(ContractCopy.copyGeneralCheckUpdates.text(for: language))
        .onHover { isHovering = $0 }
    }

    static func title(version: String, language: AppLanguage) -> String {
        "\(ContractCopy.copyDialogUpdateTitle.text(for: language)) · \(version)"
    }

    private var title: String {
        Self.title(version: version, language: language)
    }

    private var updateGlass: Glass {
        let opacity = isHovering || isFocused ? 0.5 : 0.32
        return .regular.tint(MacTheme.accent.opacity(opacity)).interactive()
    }
}

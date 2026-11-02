import SwiftUI

/// 设置界面的基础控件。
///
/// 每个控件对应设计合同里的一个组件。尺寸注释里的键就是合同的键路径，
/// `DesignContractTests` 会逐值比对 `HubMetrics`，改这里要同步改合同。
///
/// 全部用系统控件搭。SwiftUI 在 macOS 上已经把开关、分段控件、
/// 输入框画成原生外观，自己画会与系统不一致。
enum MacControlSize {
    /// 合同 `component/switch` 的 `nativeSize`。
    static let switchWidth: CGFloat = 38
    /// 合同 `component/setting-row` 的 `nativeSize`。
    static let settingRowHeight: CGFloat = 52
    /// 合同 `component/number-field` 的 `nativeSize`。
    static let numberFieldWidth: CGFloat = 120
    /// 合同 `component/segmented` 的 `nativeSize`。
    static let segmentedWidth: CGFloat = 260
}

/// 分组的设置表面。合同 `component/card`。
///
/// 合同要求不要嵌套卡片。这里不做检查，靠使用方遵守。
struct MacCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space3) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MacTheme.space4)
        // 填充写在前、玻璃加在后：玻璃模糊压在卡片底下，桌面透过来。
        // 用不透明的 `surface` 会把模糊整个盖住。
        .background(MacTheme.material, in: shape)
        .overlay(shape.strokeBorder(MacTheme.divider, lineWidth: 1))
        .glassSurface(cornerRadius: MacTheme.cardRadius)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
    }
}

/// 标签、说明与控件的一行。合同 `component/setting-row`。
///
/// 整行可点，命中区不小于合同要求的 44 点。
struct MacSettingRow<Control: View>: View {
    let title: String
    var description: String?
    @ViewBuilder var control: Control

    init(title: String, description: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MacTheme.space3) {
            VStack(alignment: .leading, spacing: MacTheme.space1) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(MacTheme.textPrimary)
                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(MacTheme.textSecondary)
                }
            }
            Spacer(minLength: MacTheme.space2)
            control
        }
        .frame(minHeight: MacControlSize.settingRowHeight - MacTheme.space2, alignment: .center)
    }
}

/// 二元开关。合同 `component/switch`。
///
/// 无障碍名称由 `label` 提供，VoiceOver 会读当前值。
struct MacSwitch: View {
    let label: String
    @Binding var isOn: Bool
    var isEnabled = true
    var size: ControlSize = .small

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(size)
            .disabled(!isEnabled)
            .accessibilityLabel(label)
    }
}

/// 数值输入。合同 `component/number-field`。
///
/// 输入不是数字时把边框染成错误色，并且不回调。
/// 调用方据此决定要不要写配置。
struct MacNumberField: View {
    let label: String
    @Binding var text: String
    var isEnabled = true

    private var isError: Bool { Int(text) == nil }

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: MacControlSize.numberFieldWidth)
            .disabled(!isEnabled)
            .overlay(
                RoundedRectangle(cornerRadius: MacTheme.smallRadius, style: .continuous)
                    .strokeBorder(isError ? MacTheme.errorText : .clear, lineWidth: 1)
            )
            .accessibilityLabel(label)
            .accessibilityValue(text)
    }
}

/// 单选分段控件。合同 `component/segmented`。
struct MacSegmented: View {
    let options: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    var accessibilityLabel: String? = nil

    var body: some View {
        Picker("", selection: Binding(get: { selectedIndex }, set: { onSelect($0) })) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Text(option).tag(index)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(minWidth: MacControlSize.segmentedWidth)
        .accessibilityLabel(Text(accessibilityLabel ?? options.joined(separator: ", ")))
    }
}

/// 按钮的视觉层级。合同 `component/button` 的变体。
enum MacButtonKind {
    /// 主操作。品牌填充。
    case primary
    /// 次操作。默认描边。
    case secondary
    /// 破坏性或低频操作。无边框。
    case plain
}

/// 按钮。合同 `component/button`。
///
/// 用 `.plain` 样式自己画外观：系统样式在这个尺寸下留白太多。
/// 按下时降透明度，键盘焦点环交给系统。
struct MacButton: View {
    /// 按钮的最小高度。文字一行时按钮就是这个高度。
    ///
    /// 标 `nonisolated` 是因为 `HubMetrics`（非隔离）要用它算按钮行的高度。
    nonisolated static let minHeight: CGFloat = 22

    let title: String
    var kind: MacButtonKind = .secondary
    var isEnabled = true
    var minimumHitHeight: CGFloat = MacButton.minHeight
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            buttonSurface
                .padding(.vertical, hitPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(MacButtonInteractionStyle(reduceMotion: reduceMotion))
        .focused($isFocused)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { isHovering = $0 }
    }

    private var buttonSurface: some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(foreground)
            .padding(.horizontal, MacTheme.space3)
            .frame(minHeight: MacButton.minHeight)
            .background(background, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .overlay(shape.strokeBorder(isFocused ? MacTheme.focusRing : .clear, lineWidth: 2))
            .brightness(kind == .primary && isHovering ? 0.06 : 0)
            .contentShape(Rectangle())
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MacTheme.mediumRadius, style: .continuous)
    }

    private var hitPadding: CGFloat {
        max(0, (minimumHitHeight - MacButton.minHeight) / 2)
    }

    private var foreground: Color {
        kind == .primary ? MacTheme.color(ContractColors.tokenColorTextOnAccent) : MacTheme.textPrimary
    }

    private var background: Color {
        switch kind {
        case .primary: MacTheme.brand
        case .secondary: isHovering ? MacTheme.controlFillHover : MacTheme.controlFill
        case .plain: isHovering ? MacTheme.controlFillHover : .clear
        }
    }

    private var border: Color {
        switch kind {
        case .primary: .clear
        case .secondary: MacTheme.divider
        case .plain: .clear
        }
    }
}

private struct MacButtonInteractionStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 行内提示。合同 `component/alert`。
enum MacAlertKind {
    case info
    case warning
    case error
    case success

    var text: Color {
        switch self {
        case .info: MacTheme.textPrimary
        case .warning: MacTheme.warningText
        case .error: MacTheme.errorText
        case .success: MacTheme.successText
        }
    }

    var background: Color {
        switch self {
        case .info: MacTheme.infoBackground
        case .warning: MacTheme.warningBackground
        case .error: MacTheme.errorBackground
        case .success: MacTheme.successBackground
        }
    }

    /// 无障碍名称。合同要求颜色不能是唯一的线索，所以每种提示都带一个词。
    func label(for language: AppLanguage) -> String {
        switch self {
        case .info: ContractCopy.copyStateLabelInfo.text(for: language)
        case .warning: ContractCopy.copyStateLabelWarning.text(for: language)
        case .error: ContractCopy.copyStateLabelError.text(for: language)
        case .success: ContractCopy.copyStateLabelSuccess.text(for: language)
        }
    }
}

struct MacAlert: View {
    let message: String
    var kind: MacAlertKind = .info
    var language: AppLanguage = CopyLocale.language

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MacTheme.space2) {
            Text(kind.label(for: language))
                .font(.system(size: 11, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
        }
        .foregroundStyle(kind.text)
        .padding(MacTheme.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.background, in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 卡片内的小标题。
struct MacSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MacTheme.textPrimary)
    }
}

/// 一行状态文字。用于「版本: 0.5.0」这类只读信息。
struct MacStatusLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(MacTheme.textSecondary)
            .padding(.vertical, 1)
    }
}

import SwiftUI

/// 更新区使用原生 Form 行和标准动作按钮。
///
/// 组件只负责信息与动作。分组、材质和行距由 Settings 的 `.grouped` Form 提供，
/// 不在内容层重复绘制卡片。所有控件保持系统原生外观。
struct UpdaterSettingsFormContent: View {
    let presentation: UpdaterSettingsPresentation
    let language: AppLanguage
    let onAutomaticUpdates: (Bool) -> Void
    let onCheck: () -> Void
    let onInstall: () -> Void
    let onRestart: () -> Void

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { presentation.automaticUpdatesEnabled },
                set: onAutomaticUpdates
            )
        ) {
            Text(ContractCopy.copyGeneralUpdateAutomatic.text(for: language))
        }
        .toggleStyle(.switch)
        .disabled(!presentation.canChangeAutomaticUpdates)

        LabeledContent(ContractCopy.copyGeneralUpdateStatus.text(for: language)) {
            HStack(spacing: 6) {
                if presentation.busy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    UpdaterStatusIndicator(state: presentation.status?.state)
                }
                Text(presentation.stateText)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }

        if let progress = presentation.downloadProgress {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .accessibilityLabel(ContractCopy.copyGeneralUpdateDownloading.text(for: language))
                .accessibilityValue(presentation.downloadPercentText ?? "")
        }

        LabeledContent(ContractCopy.copyGeneralUpdateLastCheck.text(for: language)) {
            Text(presentation.lastCheckText)
                .foregroundStyle(.secondary)
        }

        if let version = presentation.availableVersionText {
            LabeledContent(
                ContractCopy.copyGeneralUpdateAvailableVersion.text(for: language)
            ) {
                Text(version)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }

        HStack(spacing: MacTheme.space2) {
            Spacer(minLength: 0)
            Button {
                onCheck()
            } label: {
                Label(
                    ContractCopy.copyGeneralCheckUpdates.text(for: language),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .buttonStyle(.bordered)
            .disabled(!presentation.canCheck)

            if presentation.canInstall {
                Button {
                    onInstall()
                } label: {
                    Label(
                        ContractCopy.copyGeneralUpdateInstall.text(for: language),
                        systemImage: "arrow.down.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
            }

            if presentation.canRestart {
                Button {
                    onRestart()
                } label: {
                    Label(
                        ContractCopy.copyGeneralUpdateRestart.text(for: language),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }

        if let alert = presentation.alertText {
            Label(
                alert,
                systemImage: presentation.unavailable
                    ? "xmark.octagon.fill"
                    : "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(presentation.unavailable ? .red : .orange)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct UpdaterStatusIndicator: View {
    let state: UpdaterEngineState?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch state {
        case .available, .restartRequired:
            .accentColor
        case .failed, .repairRequired, .notConfigured:
            .red
        case .checking, .downloading, .installing:
            .orange
        case .idle, .none:
            MacTheme.textSecondary
        }
    }
}

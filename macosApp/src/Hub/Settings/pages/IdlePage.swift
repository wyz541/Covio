import SwiftUI

/// 闲置页。
///
/// 顺序：阻止闲置睡眠、充电时也阻止、到点自动取消。
struct IdlePage: View {
    let runtime: AppRuntime

    var body: some View {
        Form {
            Section {
                Toggle(
                    ContractCopy.copyIdlePreventIdle.text(for: runtime.language),
                    isOn: Binding(
                        get: { !runtime.appState.idleSleepAvailable },
                        set: { _ in runtime.toggleIdleSleep() }
                    )
                )
                .toggleStyle(.switch)
                .settingsRowAnchor(SettingsRowID.idlePrevent)

                Toggle(
                    ContractCopy.copyIdleWhileCharging.text(for: runtime.language),
                    isOn: Binding(
                        get: { runtime.config.disableIdleSleepInCharging },
                        set: { runtime.setDisableIdleWhileCharging($0) }
                    )
                )
                .toggleStyle(.switch)
                .settingsRowAnchor(SettingsRowID.idleCharging)
            } footer: {
                if let error = runtime.appState.lastError {
                    Label(
                        "\(ContractCopy.copyToastError.text(for: runtime.language)) \(error)",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section {
                Text(ContractCopy.copyIdleCancelAfter.text(for: runtime.language))
                    .font(.headline)
                    .settingsRowAnchor(SettingsRowID.idleCancel)
                CancellationOptions(language: runtime.language) {
                    runtime.scheduleCancelIdle(seconds: $0)
                }
                if let remaining = runtime.appState.idleCancelRemainingSeconds {
                    LabeledContent(ContractCopy.copyIdleRemaining.text(for: runtime.language)) {
                        Text(
                            SettingsFormat.duration(
                                seconds: remaining.int64Value,
                                language: runtime.language
                            )
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI

/// 概览页。
///
/// 顺序：主控卡（总开关与两个立即动作）、状态行。
/// Helper 属于 Covio 全局运行能力，不在设置页单独显示。
struct OverviewPage: View {
    let runtime: AppRuntime

    var body: some View {
        Form {
            Section {
                Toggle(
                    ContractCopy.copyOverviewRulesMaster.text(for: runtime.language),
                    isOn: Binding(
                        get: { runtime.config.enabled },
                        set: { runtime.setEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .settingsRowAnchor(SettingsRowID.overviewMaster)
            }

            Section {
                Text(runtime.batteryText())
                    .foregroundStyle(.secondary)

                HStack(spacing: MacTheme.space2) {
                    Button(ContractCopy.copyOverviewActionSleepNow.text(for: runtime.language)) {
                        runtime.sleepNow()
                    }
                    .buttonStyle(.borderedProminent)

                    Button(ContractCopy.copyOverviewActionDisplayOff.text(for: runtime.language)) {
                        runtime.displaySleepNow()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI

/// 电池页。
///
/// 顺序：低电量睡眠开关、容量阈值、剩余时间阈值。
struct BatteryPage: View {
    let runtime: AppRuntime

    var body: some View {
        Form {
            Section {
                Toggle(
                    ContractCopy.copyBatteryEnabled.text(for: runtime.language),
                    isOn: Binding(
                        get: { runtime.config.lowBatteryCapacitySleep },
                        set: { runtime.setLowBatterySleep($0) }
                    )
                )
                .toggleStyle(.switch)
                .settingsRowAnchor(SettingsRowID.batteryEnabled)

                NumberRow(
                    label: ContractCopy.copyBatteryCapacityThreshold.text(for: runtime.language),
                    value: runtime.config.lowBatteryCapacity,
                    unit: "%"
                ) { runtime.setLowBatteryCapacity($0, valid: $1) }
                .settingsRowAnchor(SettingsRowID.batteryCapacity)

                NumberRow(
                    label: ContractCopy.copyBatteryTimeThreshold.text(for: runtime.language),
                    value: runtime.config.lowTimeRemainingMinutes,
                    unit: ContractCopy.copyBatteryUnitMinutes.text(for: runtime.language)
                ) { runtime.setLowTimeRemaining($0, valid: $1) }
                .settingsRowAnchor(SettingsRowID.batteryTime)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

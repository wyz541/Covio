import AppKit
import SwiftUI

/// 通用页。
///
/// 顺序：深色唤醒、休眠模式、语言、登录项与通知、检查更新、日志与重置。
/// 危险动作排在最后，且用 `.plain` 按钮，与常规开关拉开距离。
struct GeneralPage: View {
    let runtime: AppRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space6) {
            MacCard {
                MacSettingRow(title: ContractCopy.copyGeneralDarkwake.text(for: runtime.language)) {
                    MacSwitch(
                        label: ContractCopy.copyGeneralDarkwake.text(for: runtime.language),
                        isOn: Binding(
                            get: { runtime.config.darkWakeAwarenessEnabled },
                            set: { runtime.setDarkWakeAwareness($0) }
                        )
                    )
                }
                DarkWakeStatusView(runtime: runtime)
            }
            .settingsRowAnchor(SettingsRowID.generalDarkWake)

            MacCard {
                MacSectionTitle(text: ContractCopy.copyGeneralSleepMode.text(for: runtime.language))
                SleepModeOptions(runtime: runtime)
            }
            .settingsRowAnchor(SettingsRowID.generalSleepMode)

            MacCard {
                MacSectionTitle(text: ContractCopy.copyGeneralLanguage.text(for: runtime.language))
                LanguageOptions(runtime: runtime)
            }
            .settingsRowAnchor(SettingsRowID.generalLanguage)

            LocalModelPackagesCard(runtime: runtime)
                .settingsRowAnchor(SettingsRowID.generalLocalModel)

            AgentExternalServiceCard(runtime: runtime)
                .settingsRowAnchor(SettingsRowID.generalExternalAgent)

            MacCard {
                MacSettingRow(title: ContractCopy.copyGeneralLaunchAtLogin.text(for: runtime.language)) {
                    MacSwitch(
                        label: ContractCopy.copyGeneralLaunchAtLogin.text(for: runtime.language),
                        isOn: Binding(
                            get: { runtime.config.launchAtLogin },
                            set: { runtime.setLaunchAtLogin($0) }
                        )
                    )
                }
                MacSettingRow(title: ContractCopy.copyGeneralNotifications.text(for: runtime.language)) {
                    MacSwitch(
                        label: ContractCopy.copyGeneralNotifications.text(for: runtime.language),
                        isOn: Binding(
                            get: { runtime.config.notificationsEnabled },
                            set: { runtime.setNotifications($0) }
                        )
                    )
                }
                .settingsRowAnchor(SettingsRowID.generalNotifications)
            }
            .settingsRowAnchor(SettingsRowID.generalLogin)

            MacCard {
                MacSettingRow(title: ContractCopy.copyGeneralCheckUpdates.text(for: runtime.language)) {
                    HStack(spacing: MacTheme.space2) {
                        MacSwitch(
                            label: ContractCopy.copyGeneralCheckUpdates.text(for: runtime.language),
                            isOn: Binding(
                                get: { runtime.config.updateCheckEnabled },
                                set: { runtime.setUpdateChecks($0) }
                            )
                        )
                        MacButton(
                            title: ContractCopy.copyGeneralCheckUpdates.text(for: runtime.language),
                            isEnabled: !runtime.busy
                        ) { runtime.checkForUpdates(manual: true) }
                    }
                }
            }
            .settingsRowAnchor(SettingsRowID.generalUpdates)

            ReleaseIdentityCard(runtime: runtime)
                .settingsRowAnchor(SettingsRowID.generalVersion)

            MacCard {
                HStack(spacing: MacTheme.space2) {
                    MacButton(title: ContractCopy.copyHubLogView.text(for: runtime.language)) { runtime.viewLog() }
                    MacButton(title: ContractCopy.copyHubLogExport.text(for: runtime.language)) { runtime.exportLog() }
                    MacButton(
                        title: ContractCopy.copyGeneralClearConfig.text(for: runtime.language),
                        kind: .plain,
                        isEnabled: !runtime.busy
                    ) { confirmClearConfig() }
                    .settingsRowAnchor(SettingsRowID.generalReset)
                }
                .settingsRowAnchor(SettingsRowID.generalLogs)
            }
        }
    }

    /// 清除配置不可撤销，所以先弹确认。
    private func confirmClearConfig() {
        let alert = NSAlert()
        alert.messageText = ContractCopy.copyDialogResetTitle.text(for: runtime.language)
        alert.informativeText = ContractCopy.copyDialogResetBody.text(for: runtime.language)
        alert.addButton(withTitle: ContractCopy.copyDialogResetTitle.text(for: runtime.language))
        alert.addButton(withTitle: ContractCopy.copyStateCancel.text(for: runtime.language))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runtime.clearConfig()
    }
}

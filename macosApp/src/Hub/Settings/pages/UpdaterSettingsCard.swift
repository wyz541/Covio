import SwiftUI

struct UpdaterSettingsCard: View {
    let runtime: AppRuntime

    var body: some View {
        let presentation = UpdaterSettingsPresentation(
            status: runtime.updaterStatus,
            busy: runtime.updaterBusy,
            unavailable: runtime.updaterUnavailable,
            language: runtime.language
        )
        UpdaterSettingsCardContent(
            presentation: presentation,
            language: runtime.language,
            onAutomaticUpdates: runtime.setUpdaterAutomatic,
            onCheck: runtime.checkUpdaterNow,
            onInstall: runtime.installAvailableUpdate,
            onRestart: runtime.restartAppForUpdate
        )
        .onAppear { runtime.refreshUpdaterStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            runtime.refreshUpdaterStatus()
        }
    }
}

struct UpdaterSettingsCardContent: View {
    let presentation: UpdaterSettingsPresentation
    let language: AppLanguage
    let onAutomaticUpdates: (Bool) -> Void
    let onCheck: () -> Void
    let onInstall: () -> Void
    let onRestart: () -> Void

    private var value: UpdaterSettingsPresentation { presentation }

    var body: some View {
        MacCard {
            MacSettingRow(title: ContractCopy.copyGeneralUpdateAutomatic.text(for: language)) {
                MacSwitch(
                    label: ContractCopy.copyGeneralUpdateAutomatic.text(for: language),
                    isOn: Binding(
                        get: { value.automaticUpdatesEnabled },
                        set: onAutomaticUpdates
                    ),
                    isEnabled: value.canChangeAutomaticUpdates
                )
            }

            MacSettingRow(title: ContractCopy.copyGeneralUpdateStatus.text(for: language)) {
                Text(value.stateText)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
                    .accessibilityLabel(
                        ContractCopy.copyGeneralUpdateStatus.text(for: language)
                    )
                    .accessibilityValue(value.stateText)
            }

            MacSettingRow(title: ContractCopy.copyGeneralUpdateLastCheck.text(for: language)) {
                Text(value.lastCheckText)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.textSecondary)
            }

            if let version = value.availableVersionText {
                MacSettingRow(
                    title: ContractCopy.copyGeneralUpdateAvailableVersion.text(for: language)
                ) {
                    Text(version)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                }
            }

            HStack(spacing: MacTheme.space2) {
                MacButton(
                    title: ContractCopy.copyGeneralCheckUpdates.text(for: language),
                    isEnabled: value.canCheck
                ) { onCheck() }

                if value.canInstall {
                    MacButton(
                        title: ContractCopy.copyGeneralUpdateInstall.text(for: language),
                        kind: .primary
                    ) { onInstall() }
                }

                if value.canRestart {
                    MacButton(
                        title: ContractCopy.copyGeneralUpdateRestart.text(for: language),
                        kind: .primary
                    ) { onRestart() }
                }
            }

            if let alert = value.alertText {
                MacAlert(
                    message: alert,
                    kind: value.unavailable ? .error : .warning
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

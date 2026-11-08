import AppKit
import SwiftUI

/// 通用页使用 macOS Settings 的分组表单结构。
///
/// 页面按系统设置的习惯组织：
/// - 行为设置使用原生 Toggle 和 Picker。
/// - 更新状态使用 LabeledContent，控件在行尾对齐。
/// - 安装和重启只在对应状态出现。
/// - 动作按钮使用 Liquid Glass，并放在独立分组。
struct GeneralPage: View {
    let runtime: AppRuntime

    var body: some View {
        Form {
            behaviorSection
            startupSection
            triggerSection
            updateSection
            versionSection
            diagnosticsSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var behaviorSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { runtime.config.darkWakeAwarenessEnabled },
                    set: { runtime.setDarkWakeAwareness($0) }
                )
            ) {
                Text(ContractCopy.copyGeneralDarkwake.text(for: runtime.language))
            }
            .toggleStyle(.switch)
            .settingsRowAnchor(SettingsRowID.generalDarkWake)

            darkWakeStatusRows

            Picker(
                ContractCopy.copyGeneralSleepMode.text(for: runtime.language),
                selection: Binding(
                    get: { runtime.config.hibernateMode?.int32Value ?? SleepModeOptions.modes[0] },
                    set: { runtime.setSleepMode($0) }
                )
            ) {
                ForEach(SleepModeOptions.modes, id: \.self) { mode in
                    Text(SettingsFormat.sleepModeLabel(mode, language: runtime.language))
                        .tag(mode)
                }
            }
            .pickerStyle(.menu)
            .settingsRowAnchor(SettingsRowID.generalSleepMode)

            Picker(
                ContractCopy.copyGeneralLanguage.text(for: runtime.language),
                selection: Binding(
                    get: { runtime.languagePreference },
                    set: { runtime.setLanguagePreference($0) }
                )
            ) {
                ForEach(LanguageOptions.preferences, id: \.self) { preference in
                    Text(LanguageOptions.title(preference, language: runtime.language))
                        .tag(preference)
                }
            }
            .pickerStyle(.menu)
            .settingsRowAnchor(SettingsRowID.generalLanguage)
        }
    }

    private var startupSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { runtime.config.launchAtLogin },
                    set: { runtime.setLaunchAtLogin($0) }
                )
            ) {
                Text(ContractCopy.copyGeneralLaunchAtLogin.text(for: runtime.language))
            }
            .toggleStyle(.switch)
            .settingsRowAnchor(SettingsRowID.generalLogin)

            Toggle(
                isOn: Binding(
                    get: { runtime.config.notificationsEnabled },
                    set: { runtime.setNotifications($0) }
                )
            ) {
                Text(ContractCopy.copyGeneralNotifications.text(for: runtime.language))
            }
            .toggleStyle(.switch)
            .settingsRowAnchor(SettingsRowID.generalNotifications)
        }
    }

    private var triggerSection: some View {
        Section {
            LabeledContent(ContractCopy.copyGeneralTriggerShortcut.text(for: runtime.language)) {
                HStack(spacing: MacTheme.space2) {
                    Text(GlobalHotKey.hubToggle.displayName)
                        .font(.system(.body, design: .monospaced))
                    TriggerAvailabilityLabel(
                        available: runtime.globalTriggerStatus.hotKeyRegistered,
                        language: runtime.language
                    )
                }
            }
            .settingsRowAnchor(SettingsRowID.generalTriggerShortcut)

            Toggle(
                isOn: Binding(
                    get: { runtime.config.trackpadGestureEnabled },
                    set: { runtime.setTrackpadGestureEnabled($0) }
                )
            ) {
                Text(ContractCopy.copyGeneralTriggerGesture.text(for: runtime.language))
            }
            .toggleStyle(.switch)
            .settingsRowAnchor(SettingsRowID.generalTriggerGesture)

            LabeledContent(ContractCopy.copyGeneralTriggerSwipeDown.text(for: runtime.language)) {
                if runtime.config.trackpadGestureEnabled {
                    TriggerAvailabilityLabel(
                        available: runtime.globalTriggerStatus.swipeAvailable,
                        language: runtime.language
                    )
                } else {
                    Label(
                        ContractCopy.copyGeneralTriggerOff.text(for: runtime.language),
                        systemImage: "minus.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            LabeledContent(ContractCopy.copyGeneralTriggerTopEdge.text(for: runtime.language)) {
                TriggerAvailabilityLabel(available: true, language: runtime.language)
            }
            .settingsRowAnchor(SettingsRowID.generalTriggerTopEdge)
        } header: {
            Text(ContractCopy.copyGeneralSectionTriggers.text(for: runtime.language))
        } footer: {
            Text(ContractCopy.copyGeneralTriggerFooter.text(for: runtime.language))
        }
    }

    private var updateSection: some View {
        Section {
            UpdaterSettingsFormContent(
                presentation: UpdaterSettingsPresentation(
                    status: runtime.updaterStatus,
                    busy: runtime.updaterBusy,
                    unavailable: runtime.updaterUnavailable,
                    language: runtime.language
                ),
                language: runtime.language,
                onAutomaticUpdates: runtime.setUpdaterAutomatic,
                onCheck: runtime.checkUpdaterNow,
                onInstall: runtime.installAvailableUpdate,
                onRestart: runtime.restartAppForUpdate
            )
            .settingsRowAnchor(SettingsRowID.generalUpdates)
        } header: {
            Text(ContractCopy.copyGeneralSectionUpdates.text(for: runtime.language))
        }
        .onAppear {
            runtime.refreshUpdaterStatus()
            runtime.startUpdaterStatusMonitoring()
        }
        .onDisappear {
            runtime.stopUpdaterStatusMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            runtime.refreshUpdaterStatus()
        }
    }

    private var versionSection: some View {
        Section {
            ReleaseIdentityRows(runtime: runtime)
                .settingsRowAnchor(SettingsRowID.generalVersion)
        } header: {
            Text(ContractCopy.copyGeneralVersionTitle.text(for: runtime.language))
        }
    }

    private var diagnosticsSection: some View {
        Section {
            HStack(spacing: MacTheme.space3) {
                Button(ContractCopy.copyHubLogView.text(for: runtime.language)) {
                    runtime.viewLog()
                }
                .buttonStyle(.bordered)

                Button(ContractCopy.copyHubLogExport.text(for: runtime.language)) {
                    runtime.exportLog()
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
            .settingsRowAnchor(SettingsRowID.generalLogs)

            Button(
                ContractCopy.copyGeneralClearConfig.text(for: runtime.language),
                role: .destructive
            ) {
                confirmClearConfig()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(runtime.busy)
            .settingsRowAnchor(SettingsRowID.generalReset)
        } header: {
            Text(ContractCopy.copyGeneralSectionDiagnostics.text(for: runtime.language))
        }
    }

    private var darkWakeStatusRows: some View {
        let status = runtime.appState.darkWake
        return LabeledContent(ContractCopy.copyGeneralDarkwakeLast.text(for: runtime.language)) {
            HStack(spacing: 6) {
                if status.scanning {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(darkWakeActivityText(status))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func darkWakeActivityText(_ status: DarkWakeStatus) -> String {
        if status.scanning {
            return ContractCopy.copyStateLoading.text(for: runtime.language)
        }
        guard status.available else {
            return ContractCopy.copyStateEmpty.text(for: runtime.language)
        }
        let last = status.lastAtEpochSeconds.map {
            SettingsFormat.wakeTime(epochSeconds: $0.int64Value)
        } ?? ContractCopy.copyStateEmpty.text(for: runtime.language)
        guard let reason = status.lastReason, !reason.isEmpty else {
            return last
        }
        return "\(last) · \(reason)"
    }

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

private struct TriggerAvailabilityLabel: View {
    let available: Bool?
    let language: AppLanguage

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(color)
            .accessibilityElement(children: .combine)
    }

    private var text: String {
        switch available {
        case true:
            ContractCopy.copyGeneralTriggerAvailable.text(for: language)
        case false:
            ContractCopy.copyGeneralTriggerUnavailable.text(for: language)
        case nil:
            ContractCopy.copyStateLoading.text(for: language)
        }
    }

    private var symbol: String {
        switch available {
        case true: "checkmark.circle.fill"
        case false: "xmark.circle.fill"
        case nil: "clock"
        }
    }

    private var color: Color {
        switch available {
        case true: .green
        case false: .red
        case nil: .secondary
        }
    }
}

struct GeneralSettingsHeader: View {
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MacTheme.space3) {
            Text(ContractCopy.copyPageGeneralTitle.text(for: language))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            Text(ContractCopy.copyPageGeneralSummary.text(for: language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.top, MacTheme.space4)
        .padding(.bottom, MacTheme.space2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ReleaseIdentityRows: View {
    let runtime: AppRuntime

    private var display: ReleaseIdentityDisplay {
        ReleaseIdentityDisplay.live()
    }

    var body: some View {
        LabeledContent(ContractCopy.copyGeneralVersionClient.text(for: runtime.language)) {
            Text(display.clientVersion)
                .fontWeight(.medium)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        LabeledContent(ContractCopy.copyGeneralVersionBuild.text(for: runtime.language)) {
            Text(display.buildNumber)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        LabeledContent(ContractCopy.copyGeneralVersionChannel.text(for: runtime.language)) {
            Text(display.channel)
                .textSelection(.enabled)
        }
        LabeledContent(ContractCopy.copyGeneralVersionGit.text(for: runtime.language)) {
            Text(display.gitShortSHA)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        LabeledContent(ContractCopy.copyGeneralVersionHelper.text(for: runtime.language)) {
            Text(display.helperProtocolVersion)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }
}

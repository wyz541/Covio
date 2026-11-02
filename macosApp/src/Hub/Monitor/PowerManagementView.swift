import SwiftUI
import kmpDomain

enum PowerSessionPresentation {
    static let availableModes: [PowerRuntime.SessionMode] = [.system, .display]
}

/// `Monitor` 页签 Power card 第三段浮层中的电源管理面。
///
/// 所有值都来自 `AppRuntime.powerRuntime`。布局按 macOS 设置页的阅读顺序组织：
/// 当前状态、当前会话、规则、历史。状态块不参与设置动作，规则只在自己的分组内解释。
struct PowerManagementView: View {
    let model: any PowerManagementModel

    @State private var sessionMode: PowerRuntime.SessionMode = .system
    @State private var sessionDuration: PowerRuntime.SessionDuration = .oneHour
    @State private var outcome: PowerOutcome?
    @State private var advancedRulesExpanded = false
    @State private var historyExpanded = false

    private var language: AppLanguage { model.language }

    init(model: any PowerManagementModel) {
        self.model = model
        _sessionMode = State(initialValue: model.sessionMode == .lid ? .system : model.sessionMode ?? .system)
        #if DEBUG
        let previewExpanded = ProcessInfo.processInfo.environment["COVIO_POWER_PREVIEW_ADVANCED"] == "1"
        #else
        let previewExpanded = false
        #endif
        _advancedRulesExpanded = State(initialValue: previewExpanded)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MacTheme.space4) {
                statusCard
                sessionCard
                rulesCard
                historyCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, MacTheme.space5)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    // MARK: - 当前供电

    private var statusCard: some View {
        PowerSettingsCard {
            HStack(alignment: .center, spacing: MacTheme.space3) {
                sectionHeader(
                    title: ContractCopy.copyPowerSectionStatus.text(for: language),
                    symbol: "bolt.batteryblock.fill"
                )
                Spacer(minLength: MacTheme.space3)
                Text(ContractCopy.copyOverviewRulesMaster.text(for: language))
                    .font(.callout)
                    .foregroundStyle(MacTheme.textSecondary)
                MacSwitch(
                    label: ContractCopy.copyOverviewRulesMaster.text(for: language),
                    isOn: Binding(
                        get: { model.powerConfig.enabled },
                        set: { model.setPowerEnabled($0) }
                    ),
                    size: .regular
                )
            }

            Text(ContractCopy.copyPowerDescriptionMaster.text(for: language))
                .font(.caption)
                .foregroundStyle(MacTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            powerSummary
                .padding(.top, MacTheme.space1)

            if !model.powerConfig.enabled {
                MacAlert(
                    message: ContractCopy.copyPowerErrorMasterOff.text(for: language),
                    kind: .warning,
                    language: language
                )
            }
            if hasExternalSleepConflict {
                MacAlert(
                    message: ContractCopy.copyPowerAlertExternalConflict.text(for: language),
                    kind: .error,
                    language: language
                )
            }
            if thermalNeedsAttention {
                MacAlert(
                    message: ContractCopy.copyPowerAlertThermal.text(for: language),
                    kind: .warning,
                    language: language
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var powerSummary: some View {
        VStack(alignment: .leading, spacing: MacTheme.space3) {
            HStack(alignment: .center, spacing: MacTheme.space3) {
                ZStack {
                    Circle()
                        .fill(batteryTint.opacity(0.12))
                    Image(systemName: batterySymbol)
                        .font(.system(size: 22, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(batteryTint)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: MacTheme.space1) {
                    Text(powerHeadline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text(powerSubtitle)
                        .font(.callout)
                        .foregroundStyle(MacTheme.textSecondary)
                }

                Spacer(minLength: MacTheme.space3)

                PowerStatusPill(
                    label: powerStatusPillLabel,
                    symbol: powerStatusPillSymbol,
                    tint: powerStatusPillTint
                )
            }
            .accessibilityElement(children: .combine)

            rowDivider()

            HStack(alignment: .top, spacing: MacTheme.space5) {
                PowerStatusMetric(
                    title: ContractCopy.copyMonitorThermal.text(for: language),
                    value: thermalValue
                )
                PowerStatusMetric(
                    title: ContractCopy.copyPowerStatusLowPowerMode.text(for: language),
                    value: boolValue(model.observation.lowPowerModeEnabled?.boolValue)
                )
            }
        }
    }

    // MARK: - 保持唤醒

    private var sessionCard: some View {
        PowerSettingsCard {
            HStack(alignment: .center, spacing: MacTheme.space3) {
                sectionHeader(
                    title: ContractCopy.copyPowerSectionSession.text(for: language),
                    symbol: "cup.and.saucer.fill"
                )
                Spacer(minLength: MacTheme.space3)
                PowerStatusPill(
                    label: sessionPillLabel,
                    symbol: sessionPillSymbol,
                    tint: sessionPillTint
                )
            }

            if model.hasManualSession {
                activeSessionSummary
            } else {
                sessionSetup
            }

            if !supportingReasons.isEmpty {
                VStack(alignment: .leading, spacing: MacTheme.space1) {
                    ForEach(supportingReasons) { reason in
                        sessionReasonRow(reason)
                    }
                }
                .padding(.top, MacTheme.space1)
            }

            if let message = safetyVetoMessage {
                MacAlert(message: message, kind: .warning, language: language)
            }
            if let error = powerExecutionError {
                MacAlert(message: executionErrorText(error), kind: .error, language: language)
            } else if let outcome {
                MacAlert(message: outcome.message, kind: outcome.kind, language: language)
            } else if let message = model.statusMessage, !message.isEmpty {
                MacAlert(message: message, kind: .info, language: language)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var activeSessionSummary: some View {
        HStack(alignment: .center, spacing: MacTheme.space3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(MacTheme.successText)

            VStack(alignment: .leading, spacing: MacTheme.space1) {
                Text(model.sessionMode.map(sessionModeTitle) ?? ContractCopy.copyPowerSessionActive.text(for: language))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(sessionRemainingText)
                    .font(.callout)
                    .foregroundStyle(MacTheme.textSecondary)
            }

            Spacer(minLength: MacTheme.space3)

            MonitorGlassActionButton(
                title: ContractCopy.copyPowerSessionEnd.text(for: language),
                symbol: "stop.fill"
            ) {
                model.endSession()
                outcome = PowerOutcome(
                    message: ContractCopy.copyStateSuccess.text(for: language),
                    kind: .success
                )
            }
        }
        .padding(MacTheme.space3)
        .background(
            MacTheme.successBackground,
            in: RoundedRectangle(cornerRadius: MacTheme.compactRadius, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    private var sessionSetup: some View {
        VStack(alignment: .leading, spacing: MacTheme.space2) {
            MacSettingRow(title: ContractCopy.copyPowerSessionMode.text(for: language)) {
                Picker(
                    ContractCopy.copyPowerSessionMode.text(for: language),
                    selection: $sessionMode
                ) {
                    ForEach(PowerSessionPresentation.availableModes) { mode in
                        Text(sessionModeTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 230, alignment: .trailing)
            }

            rowDivider()

            MacSettingRow(title: ContractCopy.copyPowerSessionDuration.text(for: language)) {
                Picker(
                    ContractCopy.copyPowerSessionDuration.text(for: language),
                    selection: $sessionDuration
                ) {
                    ForEach(PowerRuntime.SessionDuration.allCases) { duration in
                        Text(durationTitle(duration)).tag(duration)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 160, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: MacTheme.space3) {
                VStack(alignment: .leading, spacing: MacTheme.space1) {
                    Text(sessionSetupStatusText)
                        .font(.callout)
                        .foregroundStyle(MacTheme.textSecondary)
                    Text(ContractCopy.copyPowerSessionStartHint.text(for: language))
                        .font(.caption)
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Spacer(minLength: MacTheme.space3)
                MonitorGlassActionButton(
                    title: ContractCopy.copyPowerSessionStart.text(for: language),
                    symbol: "play.fill",
                    isEnabled: canStartSession
                ) {
                    let started = model.startSession(mode: sessionMode, duration: sessionDuration)
                    outcome = PowerOutcome(
                        message: (started ? ContractCopy.copyStateSuccess : ContractCopy.copyStateError)
                            .text(for: language),
                        kind: started ? .success : .error
                    )
                }
            }
            .padding(.top, MacTheme.space1)
        }
    }

    private func sessionReasonRow(_ reason: PowerReason) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacTheme.space2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(MacTheme.successText)
            Text(reason.title)
                .font(.callout)
                .foregroundStyle(MacTheme.textPrimary)
            Spacer(minLength: MacTheme.space2)
            if let detail = reason.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(MacTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 安全与自动规则

    private var rulesCard: some View {
        PowerSettingsCard {
            sectionHeader(
                title: ContractCopy.copyPowerSectionRules.text(for: language),
                symbol: "shield.lefthalf.filled"
            )

            ruleGroupTitle(ContractCopy.copyPowerSectionAutomatic.text(for: language))
            settingToggleRow(
                title: ContractCopy.copyPowerRulesAdapter.text(for: language),
                isOn: Binding(
                    get: { model.powerConfig.keepAwakeOnAdapter },
                    set: { model.setPowerKeepAwakeOnAdapter($0) }
                )
            )
            rowDivider()
            settingToggleRow(
                title: ContractCopy.copyPowerRulesBattery.text(for: language),
                description: ContractCopy.copyPowerRulesBatteryHint.text(for: language),
                isOn: Binding(
                    get: { model.powerConfig.keepAwakeOnBattery },
                    set: { model.setPowerKeepAwakeOnBattery($0) }
                )
            )

            Text(ContractCopy.copyPowerClosedLidPointer.text(for: language))
                .font(.caption)
                .foregroundStyle(MacTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, MacTheme.space1)

            rowDivider()
            DisclosureGroup(isExpanded: $advancedRulesExpanded) {
                advancedRulesContent
                    .padding(.top, MacTheme.space1)
            } label: {
                HStack(alignment: .center, spacing: MacTheme.space3) {
                    Text(ContractCopy.copyPowerSectionAdvanced.text(for: language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer(minLength: MacTheme.space3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }


    private var advancedRulesContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ruleGroupTitle(ContractCopy.copyPowerSectionSafety.text(for: language))
            MacSettingRow(
                title: ContractCopy.copyPowerRulesBatteryFloor.text(for: language),
                description: ContractCopy.copyPowerRulesBatteryFloorHint.text(for: language)
            ) {
                Stepper(
                    value: Binding(
                        get: { Int(model.powerConfig.batteryFloorPercent) },
                        set: { model.setPowerBatteryFloor($0) }
                    ),
                    in: 5...50,
                    step: 5
                ) {
                    Text("\(model.powerConfig.batteryFloorPercent)%")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .frame(minWidth: 42, alignment: .trailing)
                }
                .accessibilityLabel(ContractCopy.copyPowerRulesBatteryFloor.text(for: language))
            }
            rowDivider()
            settingToggleRow(
                title: ContractCopy.copyPowerStatusLowPowerMode.text(for: language),
                description: ContractCopy.copyPowerRulesLowPowerHint.text(for: language),
                isOn: Binding(
                    get: { model.powerConfig.yieldOnLowPowerMode },
                    set: { model.setPowerYieldOnLowPowerMode($0) }
                )
            )
            rowDivider()
            settingToggleRow(
                title: ContractCopy.copyPowerRulesHeatGuard.text(for: language),
                description: ContractCopy.copyPowerRulesHeatGuardHint.text(for: language),
                isOn: Binding(
                    get: { model.powerConfig.heatGuardEnabled },
                    set: { model.setPowerHeatGuard($0) }
                )
            )
        }
    }

    private func settingToggleRow(
        title: String,
        description: String? = nil,
        isOn: Binding<Bool>,
        isEnabled: Bool = true
    ) -> some View {
        MacSettingRow(title: title, description: description) {
            MacSwitch(label: title, isOn: isOn, isEnabled: isEnabled)
        }
    }

    private func ruleGroupTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MacTheme.textSecondary)
            .padding(.top, MacTheme.space2)
            .padding(.bottom, MacTheme.space1)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 最近活动

    private var historyCard: some View {
        PowerSettingsCard {
            DisclosureGroup(isExpanded: $historyExpanded) {
                VStack(alignment: .leading, spacing: MacTheme.space2) {
                    Text(ContractCopy.copyPowerHistoryHint.text(for: language))
                        .font(.caption)
                        .foregroundStyle(MacTheme.textSecondary)

                    if model.recentHistory.isEmpty {
                        HStack(spacing: MacTheme.space2) {
                            Image(systemName: "tray")
                                .font(.callout)
                                .foregroundStyle(MacTheme.disabledText)
                            Text(ContractCopy.copyPowerHistoryNoEvents.text(for: language))
                                .font(.callout)
                                .foregroundStyle(MacTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(model.recentHistory.enumerated()), id: \.element.id) { index, event in
                                historyRow(event)
                                if index < model.recentHistory.count - 1 {
                                    rowDivider()
                                }
                            }
                        }
                    }
                }
                .padding(.top, MacTheme.space2)
            } label: {
                HStack(alignment: .center, spacing: MacTheme.space3) {
                    sectionHeader(
                        title: ContractCopy.copyPowerSectionHistory.text(for: language),
                        symbol: "clock.arrow.circlepath"
                    )
                    Spacer(minLength: MacTheme.space3)
                    Text(ContractCopy.copyPowerHistoryWindow.text(for: language))
                        .font(.caption)
                        .foregroundStyle(MacTheme.textSecondary)
                }
            }
            .accessibilityHint(ContractCopy.copyPowerHistoryHint.text(for: language))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func historyRow(_ event: PowerHistoryEvent) -> some View {
        HStack(alignment: .center, spacing: MacTheme.space2) {
            Text(Self.historyTime.string(
                from: Date(timeIntervalSince1970: TimeInterval(event.atEpochSeconds))
            ))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(MacTheme.textSecondary)
            .frame(width: 42, alignment: .leading)
            Image(systemName: historySymbol(event.kind))
                .font(.caption)
                .foregroundStyle(historyColor(event.kind))
                .frame(width: 16)
            Text(historyTitle(event.kind))
                .font(.callout.weight(.medium))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer(minLength: MacTheme.space2)
            if let detail = historyDetail(event) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(MacTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 状态与动作

    private var canStartSession: Bool {
        model.sleepProtectionEnabled &&
            model.powerConfig.enabled &&
            (!model.hasManualSession || model.sessionMode != sessionMode)
    }

    private var supportingReasons: [PowerReason] {
        let reasons = reasons
        guard model.hasManualSession else { return reasons }
        return reasons.filter { $0.id != "session" }
    }

    private var reasons: [PowerReason] {
        var result: [PowerReason] = []
        if model.decision.automaticRuleApplied {
            result.append(
                PowerReason(
                    id: "automatic",
                    title: ContractCopy.copyPowerSessionReasonAdapter.text(for: language),
                    detail: ContractCopy.copyPowerSessionActive.text(for: language)
                )
            )
        }
        if model.hasManualSession, let mode = model.sessionMode {
            result.append(
                PowerReason(
                    id: "session",
                    title: sessionModeTitle(mode),
                    detail: model.remainingSeconds.map {
                        "\(ContractCopy.copyPowerSessionExpires.text(for: language)) \(SettingsFormat.duration(seconds: $0, language: language))"
                    } ?? ContractCopy.copyPowerSessionDurationOpen.text(for: language)
                )
            )
        }
        if let remaining = model.appState.idleCancelRemainingSeconds?.int64Value {
            result.append(
                PowerReason(
                    id: "legacy-idle-timer",
                    title: ContractCopy.copyPowerSessionSystem.text(for: language),
                    detail: SettingsFormat.duration(seconds: remaining, language: language)
                )
            )
        }
        if !model.appState.idleSleepAvailable,
           !model.decision.preventUserIdleSystemSleep,
           model.appState.idleCancelRemainingSeconds == nil {
            result.append(
                PowerReason(
                    id: "engine-idle",
                    title: ContractCopy.copyPowerSessionSystem.text(for: language),
                    detail: ContractCopy.copyPowerSessionActive.text(for: language)
                )
            )
        }
        return result
    }

    private var sessionIsActive: Bool {
        model.hasManualSession ||
            model.decision.preventUserIdleSystemSleep ||
            model.decision.preventUserIdleDisplaySleep
    }

    private var sessionPillLabel: String {
        (sessionIsActive ? ContractCopy.copyPowerSessionActive : ContractCopy.copyPowerSessionInactive)
            .text(for: language)
    }

    private var sessionPillSymbol: String {
        sessionIsActive ? "checkmark.circle.fill" : "pause.circle"
    }

    private var sessionPillTint: Color {
        sessionIsActive ? MacTheme.successText : MacTheme.textSecondary
    }

    private var sessionRemainingText: String {
        guard let remaining = model.remainingSeconds else {
            return ContractCopy.copyPowerSessionDurationOpen.text(for: language)
        }
        return "\(ContractCopy.copyPowerSessionExpires.text(for: language)) \(SettingsFormat.duration(seconds: remaining, language: language))"
    }

    private var safetyVetoMessage: String? {
        var seen = Set<String>()
        let messages = powerSafetyVetoes.compactMap { veto -> String? in
            let text = vetoText(veto)
            guard seen.insert(text).inserted else { return nil }
            return text
        }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private var powerSafetyVetoes: [SafetyVeto] {
        model.decision.safetyVetoes.filter { veto in
            switch veto {
            case .closedLidDisabled,
                 .helperUnavailable,
                 .externalDisplayConnected,
                 .externalDisplayUnknown:
                false
            default:
                true
            }
        }
    }

    private var powerHeadline: String {
        switch model.observation.powerState {
        case .charging, .charged, .acPower:
            return ContractCopy.copyPowerStatusAdapter.text(for: language)
        case .discharging:
            return ContractCopy.copyMonitorPowerStateBattery.text(for: language)
        case .unknown:
            return ContractCopy.copyPowerSectionStatus.text(for: language)
        default:
            return ContractCopy.copyPowerSectionStatus.text(for: language)
        }
    }

    private var powerSubtitle: String {
        guard model.observation.hasBattery?.boolValue != false else {
            return adapterValue
        }
        return "\(batteryValue) · \(adapterValue)"
    }

    private var batteryPercent: Int? {
        model.observation.batteryPercent?.intValue
    }

    private var batterySymbol: String {
        guard let percent = batteryPercent else { return "battery.0percent" }
        return switch percent {
        case 88...: "battery.100percent"
        case 63...: "battery.75percent"
        case 38...: "battery.50percent"
        case 13...: "battery.25percent"
        default: "battery.0percent"
        }
    }

    private var batteryTint: Color {
        if let percent = batteryPercent, percent <= 20 {
            return MacTheme.warningText
        }
        switch model.observation.powerState {
        case .charging, .charged:
            return MacTheme.successText
        default:
            return MacTheme.accent
        }
    }

    private var powerStatusPillLabel: String {
        if !model.powerConfig.enabled {
            return ContractCopy.copyPowerRulesOff.text(for: language)
        }
        return ContractCopy.copyPowerRulesOn.text(for: language)
    }

    private var powerStatusPillSymbol: String {
        model.powerConfig.enabled ? "checkmark.shield.fill" : "power"
    }

    private var powerStatusPillTint: Color {
        model.powerConfig.enabled ? MacTheme.successText : MacTheme.textSecondary
    }

    private var powerExecutionError: String? {
        guard let error = model.executionError else { return nil }
        if error == "helper-unavailable" || error == "lid-hold-not-applied" {
            return nil
        }
        return error
    }

    private var sessionSetupStatusText: String {
        sessionIsActive
            ? ContractCopy.copyPowerSessionActive.text(for: language)
            : ContractCopy.copyPowerSessionNone.text(for: language)
    }

    private func executionErrorText(_ error: String) -> String {
        switch error {
        case "sleep-protection-disabled":
            ContractCopy.copyPowerErrorMasterOff.text(for: language)
        case "lid-hold-not-applied":
            ContractCopy.copyPowerErrorLidNotApplied.text(for: language)
        case "helper-unavailable":
            ContractCopy.copyPowerAlertHelperMissing.text(for: language)
        default:
            error
        }
    }

    private var batteryValue: String {
        guard model.observation.hasBattery?.boolValue != false else {
            return ContractCopy.copyStateEmpty.text(for: language)
        }
        guard let percent = model.observation.batteryPercent?.intValue else {
            return ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
        return "\(percent)%"
    }

    private var adapterValue: String {
        switch model.observation.powerState {
        case .charging, .charged, .acPower:
            return ContractCopy.copyPowerStatusConnected.text(for: language)
        case .discharging:
            return ContractCopy.copyPowerStatusNotConnected.text(for: language)
        case .unknown:
            return ContractCopy.copyMonitorStateUnknown.text(for: language)
        default:
            return ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
    }

    private var thermalValue: String {
        switch model.observation.thermalState {
        case .nominal: ContractCopy.copyMonitorThermalNominal.text(for: language)
        case .fair: ContractCopy.copyMonitorThermalFair.text(for: language)
        case .serious: ContractCopy.copyMonitorThermalSerious.text(for: language)
        case .critical: ContractCopy.copyMonitorThermalCritical.text(for: language)
        case .unknown: ContractCopy.copyMonitorStateUnknown.text(for: language)
        default: ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
    }

    private var thermalNeedsAttention: Bool {
        model.observation.thermalState == .serious || model.observation.thermalState == .critical
    }

    private var hasExternalSleepConflict: Bool {
        model.snapshot.sleepDisabled?.boolValue == true &&
            model.snapshot.covioOwnsSleepDisabled?.boolValue != true
    }

    private func boolValue(_ value: Bool?) -> String {
        guard let value else {
            return ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
        return (value ? ContractCopy.copyPowerRulesOn : ContractCopy.copyPowerRulesOff).text(for: language)
    }

    private func sessionModeTitle(_ mode: PowerRuntime.SessionMode) -> String {
        switch mode {
        case .system: ContractCopy.copyPowerSessionSystem.text(for: language)
        case .display: ContractCopy.copyPowerSessionDisplay.text(for: language)
        case .lid:
            model.powerConfig.closedLidZeroBrightness &&
                model.closedLidZeroBrightnessAvailability.isAvailable
                ? ContractCopy.copyPowerSessionLidZeroBrightness.text(for: language)
                : ContractCopy.copyPowerSessionLidDisplayOff.text(for: language)
        }
    }

    private func durationTitle(_ duration: PowerRuntime.SessionDuration) -> String {
        switch duration {
        case .fifteenMinutes: ContractCopy.copyPowerSessionDuration15m.text(for: language)
        case .oneHour: ContractCopy.copyPowerSessionDuration1h.text(for: language)
        case .twoHours: ContractCopy.copyPowerSessionDuration2h.text(for: language)
        case .fourHours: ContractCopy.copyPowerSessionDuration4h.text(for: language)
        case .untilOff: ContractCopy.copyPowerSessionDurationOpen.text(for: language)
        }
    }

    private func vetoText(_ veto: SafetyVeto) -> String {
        switch veto {
        case .powerDisabled:
            ContractCopy.copyPowerRulesOff.text(for: language)
        case .batteryFloor:
            ContractCopy.copyPowerRulesBatteryFloor.text(for: language)
        case .thermalSerious, .thermalCritical:
            ContractCopy.copyPowerAlertThermal.text(for: language)
        case .lowPowerMode:
            ContractCopy.copyPowerStatusLowPowerMode.text(for: language)
        case .closedLidTimeCap:
            ContractCopy.copyMonitorDisplayTimeCap.text(for: language)
        case .closedLidDisabled:
            ContractCopy.copyPowerRulesLid.text(for: language)
        case .helperUnavailable:
            ContractCopy.copyPowerStatusGuardMissing.text(for: language)
        case .batteryStateUnknown:
            ContractCopy.copyMonitorStateUnknown.text(for: language)
        case .externalDisplayConnected, .externalDisplayUnknown:
            ContractCopy.copyPowerStatusExternalDisplay.text(for: language)
        case .sleepDisabledStateUnknown, .externalSleepDisabledConflict:
            ContractCopy.copyPowerAlertExternalConflict.text(for: language)
        case .explicitlyPaused:
            ContractCopy.copyPowerSessionInactive.text(for: language)
        default:
            ContractCopy.copyStateWarning.text(for: language)
        }
    }

    private func historyTitle(_ kind: PowerHistoryKind) -> String {
        switch kind {
        case .adapterConnected:
            ContractCopy.copyPowerHistoryAdapterConnected.text(for: language)
        case .adapterDisconnected:
            ContractCopy.copyPowerHistoryAdapterDisconnected.text(for: language)
        case .slept:
            ContractCopy.copyPowerHistorySlept.text(for: language)
        case .darkWake, .fullWake:
            ContractCopy.copyPowerHistoryWoke.text(for: language)
        case .holdStarted:
            ContractCopy.copyPowerHistoryHoldStarted.text(for: language)
        case .guardReleased:
            ContractCopy.copyPowerHistoryGuardReleased.text(for: language)
        case .externalConflict:
            ContractCopy.copyPowerAlertExternalConflict.text(for: language)
        case .externalConflictCleared:
            ContractCopy.copyPowerHistoryExternalConflictCleared.text(for: language)
        default:
            ContractCopy.copyStateWarning.text(for: language)
        }
    }

    private func historyDetail(_ event: PowerHistoryEvent) -> String? {
        let type: String? = switch event.kind {
        case .darkWake: "DarkWake"
        case .fullWake: "Full wake"
        default: nil
        }
        let detail = event.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return switch (type, detail.isEmpty) {
        case let (type?, false): "\(type) · \(detail)"
        case let (type?, true): type
        case (nil, false): detail
        case (nil, true): nil
        }
    }

    private func historySymbol(_ kind: PowerHistoryKind) -> String {
        switch kind {
        case .adapterConnected, .adapterDisconnected: "powerplug.fill"
        case .slept: "moon.fill"
        case .darkWake: "moon.haze.fill"
        case .fullWake: "sun.max.fill"
        case .holdStarted: "cup.and.saucer.fill"
        case .guardReleased: "shield.slash.fill"
        case .externalConflict: "exclamationmark.triangle.fill"
        case .externalConflictCleared: "checkmark.shield.fill"
        default: "circle.fill"
        }
    }

    private func historyColor(_ kind: PowerHistoryKind) -> Color {
        switch kind {
        case .guardReleased, .externalConflict: MacTheme.warningText
        case .fullWake, .externalConflictCleared: MacTheme.successText
        default: MacTheme.textSecondary
        }
    }

    private func sectionHeader(title: String, symbol: String) -> some View {
        Label {
            Text(title)
                .font(.headline)
                .foregroundStyle(MacTheme.textPrimary)
        } icon: {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(MacTheme.accent)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func rowDivider() -> some View {
        Divider()
            .overlay(MacTheme.divider)
            .padding(.vertical, MacTheme.space1)
    }

    private static let historyTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct PowerSettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space3) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MacTheme.space4)
        .popoverContentSurface()
        .accessibilityElement(children: .contain)
    }
}

struct MonitorGlassActionButton: View {
    let title: String
    let symbol: String
    var isEnabled = true
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, MacTheme.space2)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .overlay(
            Capsule()
                .strokeBorder(isFocused ? MacTheme.focusRing : .clear, lineWidth: 2)
        )
        .focused($isFocused)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(title)
    }
}

private struct PowerStatusMetric: View {
    let title: String
    let value: String
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(colorSchemeContrast == .increased ? MacTheme.textPrimary : MacTheme.textSecondary)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PowerStatusPill: View {
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, MacTheme.space2)
            .padding(.vertical, MacTheme.space1)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

private struct PowerReason: Identifiable {
    let id: String
    let title: String
    let detail: String?
}

private struct PowerOutcome {
    let message: String
    let kind: MacAlertKind
}


/// 电源管理面需要的最小运行时合同。
///
/// `AppRuntime` 提供真实系统状态与持久化动作。
/// 调试预览提供稳定的样本状态，便于检查布局与状态文案。
@MainActor
protocol PowerManagementModel: AnyObject {
    var language: AppLanguage { get }
    var sleepProtectionEnabled: Bool { get }
    var displayConfig: DisplayConfig { get }
    var closedLidPowerPolicy: ClosedLidPowerPolicy { get }
    var powerConfig: PowerConfig { get }
    var observation: PowerObservation { get }
    var snapshot: PowerSnapshot { get }
    var decision: PowerDecision { get }
    var helperStatus: HelperStatus { get }
    var helperServiceState: HelperServiceState { get }
    var executionError: String? { get }
    var hasManualSession: Bool { get }
    var sessionMode: PowerRuntime.SessionMode? { get }
    var remainingSeconds: Int64? { get }
    var recentHistory: [PowerHistoryEvent] { get }
    var closedLidZeroBrightnessPhase: ClosedLidZeroBrightnessPhase { get }
    var closedLidZeroBrightnessAvailability: ClosedLidBrightnessAvailability { get }
    var closedLidZeroBrightnessError: String? { get }
    var appState: AppState { get }
    var statusMessage: String? { get }
    var busy: Bool { get }

    func setPowerEnabled(_ enabled: Bool)
    func setPowerKeepAwakeOnAdapter(_ enabled: Bool)
    func setPowerKeepAwakeOnBattery(_ enabled: Bool)
    func setPowerYieldOnLowPowerMode(_ enabled: Bool)
    func setPowerHeatGuard(_ enabled: Bool)
    func setPowerBatteryFloor(_ percent: Int)
    func setPowerClosedLidTimeCapMinutes(_ minutes: Int)
    func setClosedLidPowerPolicy(_ policy: ClosedLidPowerPolicy)
    func setDisplayClosedLidMode(_ mode: ClosedLidDisplayMode)
    func setDisplayPauseWithExternalDisplay(_ enabled: Bool)
    func startSession(mode: PowerRuntime.SessionMode, duration: PowerRuntime.SessionDuration) -> Bool
    func endSession()
    func displaySleepNow()
    func openDisplaySettings()
}

extension AppRuntime: PowerManagementModel {
    var sleepProtectionEnabled: Bool { config.enabled }
    var powerConfig: PowerConfig { config.power }
    var observation: PowerObservation { powerRuntime.observation }
    var snapshot: PowerSnapshot { powerRuntime.snapshot }
    var decision: PowerDecision { powerRuntime.decision }
    var executionError: String? { powerRuntime.executionError }
    var hasManualSession: Bool { powerRuntime.hasManualSession }
    var sessionMode: PowerRuntime.SessionMode? { powerRuntime.sessionMode }
    var remainingSeconds: Int64? { powerRuntime.remainingSeconds }
    var recentHistory: [PowerHistoryEvent] { powerRuntime.recentHistory }
    var closedLidZeroBrightnessPhase: ClosedLidZeroBrightnessPhase {
        powerRuntime.closedLidZeroBrightnessPhase
    }
    var closedLidZeroBrightnessAvailability: ClosedLidBrightnessAvailability {
        powerRuntime.closedLidZeroBrightnessAvailability
    }
    var closedLidZeroBrightnessError: String? { powerRuntime.closedLidZeroBrightnessError }

    func startSession(mode: PowerRuntime.SessionMode, duration: PowerRuntime.SessionDuration) -> Bool {
        powerRuntime.startSession(mode: mode, duration: duration)
    }

    func endSession() {
        powerRuntime.endSession()
    }
}

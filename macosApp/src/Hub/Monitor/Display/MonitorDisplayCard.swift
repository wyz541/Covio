import AppKit
import SwiftUI
import kmpDomain

enum ClosedLidSettingsPresentation {
    static let timeCapOptions = [30, 60, 120, 240, 480, 1_440]

    static func showsTimeCap(for policy: ClosedLidPowerPolicy) -> Bool {
        policy.keepsAwake
    }

    static func guardMessage(
        for vetoes: [SafetyVeto],
        policy: ClosedLidPowerPolicy,
        language: AppLanguage
    ) -> String? {
        guard policy.keepsAwake else { return nil }
        var seen = Set<String>()
        let reasons = vetoes.compactMap { veto -> String? in
            guard let text = guardReason(veto, language: language) else { return nil }
            guard seen.insert(text).inserted else { return nil }
            return text
        }
        guard !reasons.isEmpty else { return nil }
        return String(
            format: ContractCopy.copyMonitorDisplayGuardPaused.text(for: language),
            reasons.joined(separator: " · ")
        )
    }

    static func guardReason(_ veto: SafetyVeto, language: AppLanguage) -> String? {
        switch veto {
        case .batteryFloor:
            ContractCopy.copyMonitorDisplayGuardBatteryFloor.text(for: language)
        case .thermalSerious, .thermalCritical:
            ContractCopy.copyMonitorDisplayGuardThermal.text(for: language)
        case .lowPowerMode:
            ContractCopy.copyMonitorDisplayGuardLowPowerMode.text(for: language)
        case .closedLidTimeCap:
            ContractCopy.copyMonitorDisplayGuardTimeCap.text(for: language)
        case .externalDisplayConnected:
            ContractCopy.copyMonitorDisplayGuardExternalDisplay.text(for: language)
        case .externalDisplayUnknown:
            ContractCopy.copyMonitorDisplayGuardExternalDisplayUnknown.text(for: language)
        case .batteryStateUnknown:
            ContractCopy.copyMonitorDisplayGuardBatteryStateUnknown.text(for: language)
        case .sleepDisabledStateUnknown:
            ContractCopy.copyMonitorDisplayGuardSleepStateUnknown.text(for: language)
        case .externalSleepDisabledConflict:
            ContractCopy.copyMonitorDisplayGuardSleepSettingConflict.text(for: language)
        case .closedLidDisabled:
            ContractCopy.copyMonitorDisplayGuardClosedLidDisabled.text(for: language)
        case .powerDisabled, .explicitlyPaused, .helperUnavailable:
            nil
        default:
            nil
        }
    }
}

/// `Monitor` 网格中的屏幕卡片。
///
/// 卡片显示状态、亮度和显示功耗。
/// 第三段打开详情与持久化设置。
struct MonitorDisplayCard: View {
    let display: MonitorSnapshot.Display
    let language: AppLanguage
    let powerModel: (any PowerManagementModel)?
    let popoverCoordinator: HubPopoverCoordinator?
    var popoverInitiallyPresented = false

    @AppStorage("monitor.display.detailsExpanded") private var detailsExpanded = false
    @State private var detailsPresented = false
    @State private var popoverID = UUID().uuidString
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: toggleDetails) {
            MonitorCardShell(
                kind: .display,
                accent: accent,
                language: language,
                combinesAccessibility: false
            ) {
                VStack(alignment: .leading, spacing: MacTheme.space2) {
                    HStack(spacing: MacTheme.space3) {
                        MonitorRing(
                            fraction: brightnessFraction,
                            accent: accent,
                            value: brightnessText
                        )
                        VStack(alignment: .leading, spacing: MacTheme.space1) {
                            Text(ContractCopy.copyMonitorDisplayBrightness.text(for: language))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(MacTheme.textSecondary)
                            Text(stateText)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(MacTheme.textPrimary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(ContractCopy.copyMonitorDisplayPower.text(for: language))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(MacTheme.textSecondary)
                                Text(powerText)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(MacTheme.textPrimary)
                                    .monospacedDigit()
                            }
                            if let powerUnavailableText {
                                Text(powerUnavailableText)
                                    .font(.system(size: 9))
                                    .foregroundStyle(MacTheme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    Spacer(minLength: 0)
                    MonitorDetailRows(details: detailRows)
                    actionRow
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onKeyPress(.return) {
            toggleDetails()
            return .handled
        }
        .onKeyPress(.space) {
            toggleDetails()
            return .handled
        }
        .onAppear {
            setDetailsPresented(popoverInitiallyPresented || shouldRestoreStoredPresentation)
        }
        .onChange(of: detailsPresented) { _, presented in
            detailsExpanded = presented
            if !presented {
                popoverCoordinator?.setPresented(false, id: popoverID)
            }
        }
        .onChange(of: popoverCoordinator?.dismissalRequest) { _, _ in
            setDetailsPresented(false)
        }
        .popover(isPresented: $detailsPresented, arrowEdge: .trailing) {
            MonitorDisplayDetailPanel(
                display: display,
                language: language,
                powerModel: powerModel,
                onClose: { setDetailsPresented(false) }
            )
            .onAppear {
                popoverCoordinator?.setPresented(true, id: popoverID)
            }
            .onDisappear {
                popoverCoordinator?.setPresented(false, id: popoverID)
            }
        }
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
                    .stroke(MacTheme.focusRing, lineWidth: 2)
                    .padding(1)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(actionText)
        .onDisappear {
            popoverCoordinator?.setPresented(false, id: popoverID)
        }
    }

    private var accent: Color {
        MacTheme.color(ContractColors.tokenColorBrand)
    }

    private var detailRows: [MonitorDetail] {
        [
            MonitorDetail(
                ContractCopy.copyPowerStatusExternalDisplay.text(for: language),
                externalDisplayText
            ),
            MonitorDetail(
                ContractCopy.copyMonitorDisplayResolution.text(for: language),
                resolutionText
            ),
            MonitorDetail(
                ContractCopy.copyMonitorDisplayRefreshRate.text(for: language),
                refreshRateText
            ),
        ]
    }

    private var actionRow: some View {
        HStack(spacing: 4) {
            Text(actionText)
                .foregroundStyle(MacTheme.textSecondary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(accent)
                .rotationEffect(detailsPresented ? .degrees(90) : .zero)
                .animation(.easeInOut(duration: 0.22), value: detailsPresented)
        }
        .font(.system(size: 9, weight: .medium))
        .frame(height: 12)
    }

    private var stateText: String {
        switch display.state {
        case .active: ContractCopy.copyMonitorDisplayStatusActive.text(for: language)
        case .asleep: ContractCopy.copyMonitorDisplayStatusAsleep.text(for: language)
        case .offline: ContractCopy.copyMonitorDisplayStatusOffline.text(for: language)
        case .unknown: ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
    }

    private var brightnessText: String {
        display.brightnessPercent.map { "\(Int(min(100, max(0, $0)).rounded()))%" }
            ?? ContractCopy.copyMonitorUnavailable.text(for: language)
    }

    private var brightnessFraction: Double? {
        guard let brightness = display.brightnessPercent, brightness.isFinite else {
            return nil
        }
        return min(1, max(0, brightness / 100))
    }

    private var powerText: String {
        MonitorPowerFormat.watts(display.powerWatts)
    }

    private var powerUnavailableText: String? {
        display.powerWatts == nil
            ? ContractCopy.copyMonitorDisplayPowerUnavailable.text(for: language)
            : nil
    }

    private var externalDisplayText: String {
        guard let count = display.externalDisplayCount else {
            return ContractCopy.copyMonitorUnavailable.text(for: language)
        }
        return count == 0
            ? ContractCopy.copyPowerStatusNoExternalDisplay.text(for: language)
            : String(count)
    }

    private var resolutionText: String {
        guard let width = display.pixelWidth, let height = display.pixelHeight else {
            return ContractCopy.copyMonitorUnavailable.text(for: language)
        }
        return "\(width) × \(height)"
    }

    private var refreshRateText: String {
        guard let refreshRate = display.refreshRate, refreshRate.isFinite else {
            return ContractCopy.copyMonitorUnavailable.text(for: language)
        }
        return String(format: "%.0f Hz", refreshRate)
    }

    private var actionText: String {
        (detailsPresented
            ? ContractCopy.copyMonitorDisplayDetailsCollapse
            : ContractCopy.copyMonitorDisplayDetailsExpand)
            .text(for: language)
    }

    private var accessibilityLabel: String {
        [
            ContractCopy.copyMonitorTitleDisplay.text(for: language),
            stateText,
            "\(ContractCopy.copyMonitorDisplayBrightness.text(for: language)) \(brightnessText)",
            "\(ContractCopy.copyMonitorDisplayPower.text(for: language)) \(powerText)",
        ].joined(separator: ", ")
    }

    private func toggleDetails() {
        setDetailsPresented(!detailsPresented)
    }

    private var shouldRestoreStoredPresentation: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["COVIO_MONITOR_PREVIEW"] != "1" && detailsExpanded
        #else
        detailsExpanded
        #endif
    }

    private func setDetailsPresented(_ presented: Bool) {
        detailsPresented = presented
        popoverCoordinator?.setPresented(presented, id: popoverID)
    }
}

/// 第三段 popover 只显示卡片摘要之外的动作和设置。
private struct MonitorDisplayDetailPanel: View {
    let display: MonitorSnapshot.Display
    let language: AppLanguage
    let powerModel: (any PowerManagementModel)?
    let onClose: () -> Void

    private var panelHeight: CGFloat {
        let available = NSScreen.main?.visibleFrame.height ?? 800
        return min(548, max(420, available - 140))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space3) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: MacTheme.space3) {
                    if let powerModel {
                        quickActions(model: powerModel)
                        closedLidCard(model: powerModel)
                        Text(ContractCopy.copyMonitorDisplaySafetyNote.text(for: language))
                            .font(.caption)
                            .foregroundStyle(MacTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, MacTheme.space4)
            }
            .scrollIndicators(.automatic)
        }
        .padding(MacTheme.space4)
        .frame(width: 520, height: panelHeight)
    }

    private var header: some View {
        HStack(spacing: MacTheme.space2) {
            Image(systemName: displaySymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(display.state == .asleep ? MacTheme.textSecondary : MacTheme.brand)
            Text(ContractCopy.copyMonitorDisplayDetailsTitle.text(for: language))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(MacTheme.textSecondary)
            .accessibilityLabel(ContractCopy.copyMonitorPowerDetailsClose.text(for: language))
        }
        .frame(height: 26)
    }

    private func quickActions(model: any PowerManagementModel) -> some View {
        GlassEffectContainer(spacing: MacTheme.space2) {
            HStack(spacing: MacTheme.space2) {
                MonitorGlassActionButton(
                    title: ContractCopy.copyMonitorDisplayActionSleep.text(for: language),
                    symbol: "display"
                ) {
                    model.displaySleepNow()
                }
                MonitorGlassActionButton(
                    title: ContractCopy.copyMonitorDisplayActionSettings.text(for: language),
                    symbol: "gearshape"
                ) {
                    model.openDisplaySettings()
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ContractCopy.copyMonitorDisplayActionsTitle.text(for: language))
    }

    private func closedLidCard(model: any PowerManagementModel) -> some View {
        DisplaySettingsCard {
            DisplaySectionHeader(
                title: ContractCopy.copyMonitorDisplayClosedLidTitle.text(for: language),
                symbol: "laptopcomputer"
            )

            if model.helperStatus != .match || model.helperServiceState != .enabled {
                MacAlert(
                    message: ContractCopy.copyPowerAlertHelperMissing.text(for: language),
                    kind: .warning,
                    language: language
                )
            }
            if !model.sleepProtectionEnabled || !model.powerConfig.enabled {
                MacAlert(
                    message: ContractCopy.copyPowerErrorMasterOff.text(for: language),
                    kind: .warning,
                    language: language
                )
            }
            if let error = closedLidRuntimeError(model) {
                MacAlert(message: error, kind: .error, language: language)
            }
            if let message = ClosedLidSettingsPresentation.guardMessage(
                for: model.decision.safetyVetoes,
                policy: model.closedLidPowerPolicy,
                language: language
            ) {
                MacAlert(message: message, kind: .warning, language: language)
            }

            MacSettingRow(
                title: ContractCopy.copyLidHoldPolicy.text(for: language),
                description: ContractCopy.copyLidHoldPolicyHint.text(for: language)
            ) {
                Picker(
                    ContractCopy.copyLidHoldPolicy.text(for: language),
                    selection: Binding(
                        get: { model.closedLidPowerPolicy },
                        set: { model.setClosedLidPowerPolicy($0) }
                    )
                ) {
                    ForEach(
                        [ClosedLidPowerPolicy.sleep, .adapter, .battery, .any],
                        id: \.stableID
                    ) { policy in
                        Text(policy.title.text(for: language))
                            .tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 250, alignment: .trailing)
            }

            if model.closedLidPowerPolicy == .battery || model.closedLidPowerPolicy == .any {
                MacAlert(
                    message: ContractCopy.copyLidWarning.text(for: language),
                    kind: .warning,
                    language: language
                )
            }

            if ClosedLidSettingsPresentation.showsTimeCap(for: model.closedLidPowerPolicy) {
                Divider().overlay(MacTheme.divider)

                MacSettingRow(
                    title: ContractCopy.copyMonitorDisplayTimeCap.text(for: language),
                    description: ContractCopy.copyMonitorDisplayTimeCapHint.text(for: language)
                ) {
                    Picker(
                        ContractCopy.copyMonitorDisplayTimeCap.text(for: language),
                        selection: Binding(
                            get: { Int(model.powerConfig.closedLidTimeCapMinutes) },
                            set: { model.setPowerClosedLidTimeCapMinutes($0) }
                        )
                    ) {
                        ForEach(ClosedLidSettingsPresentation.timeCapOptions, id: \.self) { minutes in
                            Text(SettingsFormat.duration(seconds: Int64(minutes) * 60, language: language))
                                .tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(minWidth: 140, alignment: .trailing)
                }

                Divider().overlay(MacTheme.divider)

                MacSettingRow(title: ContractCopy.copyMonitorDisplayMode.text(for: language)) {
                    Picker(
                        ContractCopy.copyMonitorDisplayMode.text(for: language),
                        selection: Binding(
                            get: { effectiveMode(for: model) },
                            set: { model.setDisplayClosedLidMode($0) }
                        )
                    ) {
                        Text(ContractCopy.copyMonitorDisplayModeOff.text(for: language))
                            .tag(ClosedLidDisplayMode.displayOff)
                        Text(ContractCopy.copyMonitorDisplayModeBlack.text(for: language))
                            .tag(ClosedLidDisplayMode.blackScreenPipeline)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(minWidth: 210, alignment: .trailing)
                    .disabled(model.helperStatus != .match)
                }

                if !model.closedLidZeroBrightnessAvailability.isAvailable {
                    Text(ContractCopy.copyPowerRulesClosedLidZeroBrightnessUnavailable.text(for: language))
                        .font(.caption)
                        .foregroundStyle(MacTheme.warningText)
                }

                Divider().overlay(MacTheme.divider)

                MacSettingRow(
                    title: ContractCopy.copyPowerRulesExternalDisplay.text(for: language),
                    description: ContractCopy.copyPowerRulesExternalDisplayHint.text(for: language)
                ) {
                    MacSwitch(
                        label: ContractCopy.copyPowerRulesExternalDisplay.text(for: language),
                        isOn: Binding(
                            get: { model.displayConfig.pauseWhenExternalDisplayConnected },
                            set: { model.setDisplayPauseWithExternalDisplay($0) }
                        ),
                        isEnabled: model.helperStatus == .match
                    )
                }
            }

            Divider().overlay(MacTheme.divider)

            if let error = model.closedLidZeroBrightnessError, !error.isEmpty,
               model.displayConfig.closedLidDisplayMode == .blackScreenPipeline {
                MacAlert(
                    message: "\(ContractCopy.copyPowerRulesClosedLidZeroBrightnessFailed.text(for: language)) \(error)",
                    kind: .warning,
                    language: language
                )
            }
        }
    }

    private var displaySymbol: String {
        switch display.state {
        case .active: "display"
        case .asleep: "display"
        case .offline: "display.trianglebadge.exclamationmark"
        case .unknown: "display"
        }
    }

    private func effectiveMode(for model: any PowerManagementModel) -> ClosedLidDisplayMode {
        guard model.displayConfig.keepAwakeWhenLidClosed else { return .system }
        return model.displayConfig.closedLidDisplayMode == .system
            ? .blackScreenPipeline
            : model.displayConfig.closedLidDisplayMode
    }

    private func closedLidRuntimeError(_ model: any PowerManagementModel) -> String? {
        guard let error = model.executionError,
              error != model.closedLidZeroBrightnessError
        else { return nil }
        return switch error {
        case "helper-unavailable":
            ContractCopy.copyPowerAlertHelperMissing.text(for: language)
        case "lid-hold-not-applied":
            ContractCopy.copyPowerErrorLidNotApplied.text(for: language)
        default:
            error
        }
    }

}

private struct DisplaySectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title)
                .font(.headline)
                .foregroundStyle(MacTheme.textPrimary)
        } icon: {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(MacTheme.brand)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct DisplaySettingsCard<Content: View>: View {
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

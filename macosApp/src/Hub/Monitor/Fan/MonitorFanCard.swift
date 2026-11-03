import SwiftUI

struct MonitorFanCard: View {
    let reading: MonitorFanReading
    let temperatureHistory: [Double]
    let language: AppLanguage
    @ObservedObject var model: MonitorFanControlModel
    var popoverCoordinator: HubPopoverCoordinator? = nil

    @State private var popoverPresented = false
    @State private var popoverID = UUID().uuidString
    @Environment(\.monitorFanForceOpaqueSurface) private var forceOpaqueSurface

    private var controlTemperature: Double? {
        model.configuration.controlTemperature(in: reading)
    }

    private var usageFraction: Double? {
        reading.maximumUsageFraction
    }

    private var usageText: String {
        usageFraction.map(MonitorFormat.percent) ?? "—"
    }

    private var controlStatus: FanCardControlStatus {
        if model.busy || model.availability == .checking {
            return .applying
        }
        if model.helperStatus?.active == true || model.configuration.enabled {
            return .owned
        }
        return .systemControl
    }

    private var statusIndicator: MonitorCardStatusIndicator {
        MonitorCardStatusIndicator(
            accessibilityLabel: ContractCopy.copyMonitorFanA11yStatus.text(for: language),
            accessibilityValue: controlStatus.copy.text(for: language),
            color: controlStatus.color,
            symbolName: controlStatus.symbolName
        )
    }

    private var controlSummaryText: String {
        MonitorFanControlCopy.summary(
            configuration: model.configuration,
            reading: reading,
            language: language
        )
    }

    private var fanDetails: [MonitorDetail] {
        reading.units.prefix(3).map { fan in
            let percent = fan.usageFraction.map(MonitorFormat.percent) ?? "—"
            let value = "\(percent) · \(MonitorFanFormat.rpm(fan.rpm)) / "
                + MonitorFanFormat.targetRPM(fan.targetRPM)
            return MonitorDetail(
                String(
                    format: ContractCopy.copyMonitorFanUnit.text(for: language),
                    fan.index + 1
                ),
                value
            )
        }
    }

    var body: some View {
        MonitorCardShell(
            kind: .fan,
            accent: MonitorCardKind.fan.accent,
            language: language,
            combinesAccessibility: false,
            statusIndicator: statusIndicator,
            glassInteractive: true
        ) {
            VStack(alignment: .leading, spacing: MacTheme.space2) {
                HStack(spacing: MacTheme.space3) {
                    VStack(spacing: MacTheme.space1) {
                        MonitorRing(
                            fraction: usageFraction,
                            accent: MonitorCardKind.fan.accent,
                            value: usageText
                        )
                        Text(ContractCopy.copyMonitorUsage.text(for: language))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    temperatureTrend
                }
                Spacer(minLength: 0)
                MonitorDetailRows(details: fanDetails)
                actionRow
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .popover(isPresented: $popoverPresented, arrowEdge: .bottom) {
            MonitorFanPopover(
                reading: reading,
                language: language,
                model: model
            )
            .frame(width: 420, alignment: .topLeading)
            .onAppear {
                popoverCoordinator?.setPresented(true, id: popoverID)
            }
            .onDisappear {
                popoverCoordinator?.setPresented(false, id: popoverID)
            }
        }
        .onChange(of: popoverPresented) { _, presented in
            if !presented {
                popoverCoordinator?.setPresented(false, id: popoverID)
            }
        }
        .onChange(of: popoverCoordinator?.dismissalRequest) { _, _ in
            setPopoverPresented(false)
        }
        .onAppear {
            model.adoptDefaultSensors(from: reading)
            model.refreshFanControlStatus()
        }
        .onChange(of: reading) { _, value in
            model.adoptDefaultSensors(from: value)
        }
        .onDisappear {
            popoverCoordinator?.setPresented(false, id: popoverID)
        }
    }

    /// 同时更新 Popover 与协调器。先登记再等窗口出现，避免指针事件抢先启动收起。
    private func setPopoverPresented(_ presented: Bool) {
        popoverPresented = presented
        popoverCoordinator?.setPresented(presented, id: popoverID)
    }

    private var temperatureTrend: some View {
        VStack(alignment: .leading, spacing: MacTheme.space1) {
            HStack(alignment: .firstTextBaseline, spacing: MacTheme.space1) {
                Text(ContractCopy.copyMonitorFanControlTemperature.text(for: language))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                Spacer(minLength: 0)
                Text(MonitorFanFormat.temperature(controlTemperature))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.textPrimary)
                    .monospacedDigit()
            }
            Text(controlSummaryText)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            ZStack {
                if temperatureHistory.filter(\.isFinite).count >= 2 {
                    MonitorSparkline(
                        values: temperatureHistory,
                        accent: MacTheme.errorText,
                        normalizesToRange: true
                    )
                } else {
                    Text(ContractCopy.copyMonitorPowerHistoryAccumulating.text(for: language))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                }
            }
            .frame(height: 38)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var actionRow: some View {
        Button {
            setPopoverPresented(!popoverPresented)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(MonitorCardKind.fan.accent)
                Text(ContractCopy.copyMonitorFanDetails.text(for: language))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MonitorCardKind.fan.accent)
                    .rotationEffect(popoverPresented ? .degrees(90) : .zero)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
        }
        .modifier(MonitorFanGlassButtonStyleModifier(forceOpaque: forceOpaqueSurface))
        .accessibilityLabel(ContractCopy.copyMonitorFanA11yOpen.text(for: language))
    }

}

private enum FanCardControlStatus {
    case applying
    case owned
    case systemControl

    var copy: LocalizedCopy {
        switch self {
        case .applying: ContractCopy.copyMonitorFanApplying
        case .owned: ContractCopy.copyMonitorFanOwned
        case .systemControl: ContractCopy.copyMonitorFanSystemControl
        }
    }

    var color: Color {
        switch self {
        case .applying: MacTheme.warningText
        case .owned: MacTheme.successText
        case .systemControl: MacTheme.textSecondary
        }
    }

    var symbolName: String {
        switch self {
        case .applying: "circle.dashed"
        case .owned: "circle.fill"
        case .systemControl: "circle"
        }
    }
}

private enum MonitorFanControlCopy {
    static func summary(
        configuration: MonitorFanConfiguration,
        reading: MonitorFanReading,
        language: AppLanguage
    ) -> String {
        let sources = configuration.selectedPreset.isCurvePreset
            ? []
            : configuration.enabledTemperatureSources
        if sources.count == 1, let source = sources.first {
            return String(
                format: ContractCopy.copyMonitorFanControlSource.text(for: language),
                sourceTitle(source, language: language)
            )
        }
        if sources.count > 1 {
            return String(
                format: ContractCopy.copyMonitorFanSourceSummary.text(for: language),
                sources.count
            )
        }
        let knownKeys = Set(reading.temperatures.map(\.key))
        let selected = configuration.selectedSensorKeys.filter(knownKeys.contains)
        let count = selected.isEmpty ? reading.temperatures.count : selected.count
        return String(
            format: ContractCopy.copyMonitorFanControlSummary.text(for: language),
            count
        )
    }

    private static func sourceTitle(
        _ source: MonitorFanTemperatureSource,
        language: AppLanguage
    ) -> String {
        switch source {
        case .cpu:
            ContractCopy.copyMonitorFanSourceCpu.text(for: language)
        case .gpu:
            ContractCopy.copyMonitorFanSourceGpu.text(for: language)
        case .battery:
            ContractCopy.copyMonitorFanSourceBattery.text(for: language)
        }
    }
}

struct MonitorFanPopover: View {
    let reading: MonitorFanReading
    let language: AppLanguage
    @ObservedObject var model: MonitorFanControlModel
    var scrollsContent = true
    var rendersForSnapshot = false
    var sensorsInitiallyExpanded = false
    var advancedInitiallyExpanded = false

    @State private var sensorsExpanded = false
    @State private var sensorQuery = ""
    @State private var advancedExpanded = false
    @State private var hoveredPreset: MonitorFanPreset?
    @Namespace private var strategyGlassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.monitorFanForceOpaqueSurface) private var forceOpaqueSurface

    private var sourceTemperatures: [MonitorFanTemperatureSource: Double] {
        var values = model.configuration.temperatureSourceReadings(in: reading)
        for source in MonitorFanTemperatureSource.allCases where values[source] == nil {
            values[source] = model.helperStatus?.sourceTemperatures[source.rawValue]
        }
        return values
    }

    private var controlTemperature: Double? {
        return model.configuration.controlTemperature(in: reading)
    }

    private var helperReady: Bool {
        model.availability == .ready
    }

    private var isControllingFans: Bool {
        model.helperStatus?.active == true || model.configuration.enabled
    }

    private var preferredHeight: CGFloat {
        if model.configuration.mode == .automatic {
            return 300
        }
        if advancedExpanded {
            return 760
        }
        if model.configuration.mode == .manual {
            return 560
        }
        return 600
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 12)
            if scrollsContent {
                ScrollView(.vertical, showsIndicators: false) {
                    detailContent
                }
                .defaultScrollAnchor(sensorsInitiallyExpanded ? .bottom : .top)
            } else {
                detailContent
            }
        }
        .padding(16)
        .frame(width: 420, height: preferredHeight, alignment: .topLeading)
        .tint(MonitorFanPresetStyle.accent)
        .animation(reduceMotion ? nil : .easeOut(duration: HubMotion.tabSwitch), value: hoveredPreset)
        .onAppear {
            if sensorsInitiallyExpanded {
                sensorsExpanded = true
            }
            if advancedInitiallyExpanded {
                advancedExpanded = true
            }
            model.migrateLegacyPresetIfNeeded(reading: reading)
            model.refreshFanControlStatus()
        }
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(MonitorFanPolicy.heartbeatSeconds))
                } catch {
                    break
                }
                model.refreshFanControlStatus()
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !helperReady {
                helperCallout
            }
            if model.configuration.selectedPreset == .system {
                systemControlCallout
            }
            controls
        }
        .padding(.bottom, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(reading.units) { fan in
                fanHeaderRow(fan)
            }
        }
    }

    private func fanHeaderRow(_ fan: MonitorFanReading.Unit) -> some View {
        let fraction = fan.usageFraction
        let percent = fraction.map { MonitorFormat.percent($0) } ?? "—"
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fanDisplayName(fan))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer(minLength: 0)
                Text("\(percent) · \(MonitorFanFormat.rpm(fan.rpm))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(MacTheme.textSecondary)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MacTheme.textSecondary.opacity(0.16))
                        .glassEffect(forceOpaqueSurface ? .identity : .clear, in: .capsule)
                    Capsule()
                        .fill(MonitorFanPresetStyle.accent.opacity(0.92))
                        .frame(width: geometry.size.width * min(1, max(0, fraction ?? 0)))
                        .glassEffect(
                            forceOpaqueSurface
                                ? .identity
                                : .regular.tint(MonitorFanPresetStyle.accent.opacity(0.72)),
                            in: .capsule
                        )
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fanDisplayName(fan))
        .accessibilityValue(
            "\(percent), \(MonitorFanFormat.rpm(fan.rpm)), "
            + "\(ContractCopy.copyMonitorFanTarget.text(for: language)) "
            + MonitorFanFormat.targetRPM(displayedTargetRPM(for: fan))
        )
    }

    private func fanDisplayName(_ fan: MonitorFanReading.Unit) -> String {
        if reading.units.count == 2 {
            return fan.index == 0
                ? ContractCopy.copyMonitorFanLeft.text(for: language)
                : ContractCopy.copyMonitorFanRight.text(for: language)
        }
        return String(
            format: ContractCopy.copyMonitorFanUnit.text(for: language),
            fan.index + 1
        )
    }

    private func displayedTargetRPM(for fan: MonitorFanReading.Unit) -> Double {
        switch model.configuration.mode {
        case .automatic:
            return fan.targetRPM
        case .manual:
            guard model.manualMode(for: fan.index) == .manual else {
                return fan.targetRPM
            }
            return model.configuration.manualRPM[String(fan.index)] ?? fan.targetRPM
        case .curve:
            if let temperature = controlTemperature,
               let percent = model.configuration.presetTargetPercent(at: temperature) {
                return MonitorFanPercent.rpm(
                    percent: percent,
                    minimumRPM: fan.minimumRPM,
                    maximumRPM: fan.maximumRPM
                )
            }
            if !model.configuration.enabledTemperatureSources.isEmpty,
               let percent = model.configuration.mergedTargetPercent(
                   sourceTemperatures: sourceTemperatures
               ) {
                return MonitorFanPercent.rpm(
                    percent: percent,
                    minimumRPM: fan.minimumRPM,
                    maximumRPM: fan.maximumRPM
                )
            }
            guard let temperature = controlTemperature else { return fan.targetRPM }
            return model.configuration.target(
                fanIndex: fan.index,
                temperature: temperature,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM
            )
        }
    }

    private var takeoverBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.warningText)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ContractCopy.copyMonitorFanTakeoverTitle.text(for: language))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Text(ContractCopy.copyMonitorFanTakeoverBody.text(for: language))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = model.visibleErrorMessage {
                        Text(message)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MacTheme.errorText)
                            .textSelection(.enabled)
                    }
                }
            }

            Button {
                model.restore()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                    Text(ContractCopy.copyMonitorFanRestoreSystem.text(for: language))
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MonitorCardKind.fan.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    MonitorCardKind.fan.accent.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(MonitorCardKind.fan.accent.opacity(0.55), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .disabled(model.busy)
            .accessibilityHint(ContractCopy.copyMonitorFanTakeoverBody.text(for: language))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popoverContentSurface(
            cornerRadius: 9,
            tint: MacTheme.warningText.opacity(0.10)
        )
    }

    private var helperCallout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(
                    model.availability == .missing || model.availability == .outdated
                        ? ContractCopy.copyMonitorFanHelperRequired.text(for: language)
                        : ContractCopy.copyMonitorFanHelperUnavailable.text(for: language)
                )
            } icon: {
                Image(systemName: "shield.lefthalf.filled")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MacTheme.textSecondary)

        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monitorFanGlassPanel(
            cornerRadius: 14,
            tint: MacTheme.warningText.opacity(0.12)
        )
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            strategyHeader
            strategyControl

            if model.configuration.selectedPreset.isCurvePreset {
                Text(ContractCopy.copyMonitorFanCurveSummary.text(for: language))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                curveEditor

                if let message = model.visibleErrorMessage {
                    Text(message)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTheme.errorText)
                        .textSelection(.enabled)
                }

                DisclosureGroup(isExpanded: $advancedExpanded) {
                    sensorSection
                        .padding(.top, 8)
                } label: {
                    HStack(spacing: 6) {
                        Text(ContractCopy.copyMonitorFanAdvanced.text(for: language))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MacTheme.textPrimary)
                        Spacer(minLength: 0)
                        Text(presetTitle(model.configuration.selectedPreset))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    .frame(minHeight: 24)
                }
                .tint(MonitorFanPresetStyle.accent)
            } else if model.configuration.selectedPreset == .manual {
                manualControls
            }
        }
        .padding(12)
        .monitorFanGlassPanel(cornerRadius: 18)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(MacTheme.divider.opacity(0.36), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    private var strategyHeader: some View {
        HStack(spacing: 8) {
            Text(ContractCopy.copyMonitorFanStrategy.text(for: language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
            Spacer(minLength: 0)
            if isControllingFans {
                Button {
                    model.restore()
                } label: {
                    Label(
                        ContractCopy.copyMonitorFanReturnToMacos.text(for: language),
                        systemImage: "arrow.uturn.backward"
                    )
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 26)
                }
                .modifier(MonitorFanGlassButtonStyleModifier(forceOpaque: forceOpaqueSurface))
                .tint(MonitorFanPresetStyle.accent)
                .disabled(model.busy)
            } else {
                Text(ContractCopy.copyMonitorFanSystemControl.text(for: language))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }
        }
    }

    private var strategyControl: some View {
        GlassEffectContainer(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(visiblePresets, id: \.rawValue) { preset in
                    let selected = visibleSelection == preset
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: HubMotion.tabSwitch)) {
                            model.selectPreset(preset, reading: reading)
                        }
                    } label: {
                        Text(presetTitle(preset))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                selected && forceOpaqueSurface ? Color.white : MacTheme.textPrimary
                            )
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(
                                forceOpaqueSurface && selected
                                    ? MonitorFanPresetStyle.accent
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        forceOpaqueSurface ? .identity : strategyGlass(for: preset),
                        in: .rect(cornerRadius: 9)
                    )
                    .glassEffectID(
                        selected && !forceOpaqueSurface ? "fan-strategy-selection" : nil,
                        in: strategyGlassNamespace
                    )
                    .glassEffectTransition(.matchedGeometry)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .disabled(model.busy)
                    .onHover { inside in
                        hoveredPreset = inside ? preset : nil
                    }
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(MacTheme.textSecondary.opacity(0.075))
            )
        }
        .animation(reduceMotion ? nil : .easeOut(duration: HubMotion.tabSwitch), value: visibleSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ContractCopy.copyMonitorFanStrategy.text(for: language))
    }

    private func strategyGlass(for preset: MonitorFanPreset) -> Glass {
        if preset == visibleSelection {
            return .regular.tint(MonitorFanPresetStyle.accent).interactive()
        }
        if hoveredPreset == preset {
            return .clear.interactive()
        }
        return .identity
    }

    private var visibleSelection: MonitorFanPreset {
        model.configuration.selectedPreset == .legacy
            ? .custom
            : model.configuration.selectedPreset
    }

    private var visiblePresets: [MonitorFanPreset] {
        if model.configuration.selectedPreset == .manual {
            return MonitorFanPreset.selectable + [.manual]
        }
        return MonitorFanPreset.selectable
    }

    private func presetTitle(_ preset: MonitorFanPreset) -> String {
        switch preset {
        case .system:
            ContractCopy.copyMonitorFanPresetSystem.text(for: language)
        case .quiet:
            ContractCopy.copyMonitorFanPresetQuiet.text(for: language)
        case .compile:
            ContractCopy.copyMonitorFanPresetCompile.text(for: language)
        case .sustained:
            ContractCopy.copyMonitorFanPresetSustained.text(for: language)
        case .custom, .legacy:
            ContractCopy.copyMonitorFanPresetCustom.text(for: language)
        case .manual:
            ContractCopy.copyMonitorFanManualRpm.text(for: language)
        }
    }

    private var curveEditor: some View {
        MonitorFanCurveEditor(
            reading: reading,
            preset: model.configuration.selectedPreset,
            points: model.configuration.activePresetPoints,
            controlTemperature: controlTemperature,
            language: language,
            interactive: !rendersForSnapshot,
            busy: model.busy,
            isCustomized: model.configuration.isPresetCustomized(),
            onCommit: { points in
                model.setPresetPoints(
                    points,
                    reading: reading,
                    applyImmediately: true
                )
            },
            onReset: {
                model.resetPreset(reading: reading)
            }
        )
    }

    private var controlSummaryText: String {
        MonitorFanControlCopy.summary(
            configuration: model.configuration,
            reading: reading,
            language: language
        )
    }

    private var manualControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(ContractCopy.copyMonitorFanManualRpm.text(for: language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer(minLength: 0)
                compactActionButton(
                    ContractCopy.copyMonitorFanFullSpeedAll,
                    systemImage: "forward.fill"
                ) {
                    model.boostAllFans(reading: reading)
                }
                compactActionButton(
                    ContractCopy.copyMonitorFanRestoreAutoCurve,
                    systemImage: "arrow.uturn.backward"
                ) {
                    model.restoreAutoCurve(reading: reading)
                }
            }
            if reading.units.count > 1 {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ContractCopy.copyMonitorFanSyncFans.text(for: language))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MacTheme.textPrimary)
                        Text(ContractCopy.copyMonitorFanSyncHint.text(for: language))
                            .font(.system(size: 8))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if rendersForSnapshot {
                        MonitorFanSnapshotSwitch(
                            isOn: model.configuration.syncFans,
                            label: ContractCopy.copyMonitorFanSyncFans.text(for: language)
                        )
                    } else {
                        Toggle("", isOn: Binding(
                            get: { model.configuration.syncFans },
                            set: { model.setSyncFans($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(model.busy)
                    }
                }
            }
            ForEach(reading.units) { fan in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(String(
                            format: ContractCopy.copyMonitorFanUnit.text(for: language),
                            fan.index + 1
                        ))
                        .font(.system(size: 10, weight: .medium))
                        Spacer(minLength: 0)
                        Text(MonitorFanFormat.rpm(
                            model.manualMode(for: fan.index) == .manual
                                ? model.configuration.manualRPM[String(fan.index)]
                                : fan.rpm
                        ))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        compactActionButton(
                            ContractCopy.copyMonitorFanFullSpeed,
                            systemImage: "forward.fill"
                        ) {
                            model.boostFan(fan.index, reading: reading)
                        }
                        .accessibilityLabel(String(
                            format: ContractCopy.copyMonitorFanFullSpeedUnit.text(for: language),
                            fan.index + 1
                        ))
                    }
                    Picker("", selection: Binding(
                        get: { model.manualMode(for: fan.index) },
                        set: { model.setManualMode($0, fanIndex: fan.index, reading: reading) }
                    )) {
                        Text(ContractCopy.copyMonitorFanAutomatic.text(for: language))
                            .tag(MonitorFanMode.automatic)
                        Text(ContractCopy.copyMonitorFanManual.text(for: language))
                            .tag(MonitorFanMode.manual)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 150)
                    .disabled(model.busy)

                    if model.manualMode(for: fan.index) == .manual {
                        if rendersForSnapshot {
                            MonitorFanSnapshotSlider(
                                value: model.configuration.manualRPM[String(fan.index)] ?? fan.minimumRPM,
                                range: fan.minimumRPM...max(fan.minimumRPM + 1, fan.maximumRPM)
                            )
                        } else {
                            Slider(
                                value: Binding(
                                    get: {
                                        model.configuration.manualRPM[String(fan.index)] ?? fan.minimumRPM
                                    },
                                    set: {
                                        model.setManualRPM(
                                            $0,
                                            fanIndex: fan.index,
                                            reading: reading
                                        )
                                    }
                                ),
                                in: fan.minimumRPM...max(fan.minimumRPM + 1, fan.maximumRPM),
                                step: 50
                            )
                            .disabled(model.busy)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func compactActionButton(
        _ title: LocalizedCopy,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if rendersForSnapshot {
                Button(action: action) {
                    Label(title.text(for: language), systemImage: systemImage)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(MacTheme.textSecondary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button(title.text(for: language), systemImage: systemImage, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .disabled(model.busy)
    }

    private var sensorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            DisclosureGroup(isExpanded: $sensorsExpanded) {
                VStack(alignment: .leading, spacing: 5) {
                    TextField(
                        ContractCopy.copyMonitorFanSensorFilter.text(for: language),
                        text: $sensorQuery
                    )
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .accessibilityLabel(ContractCopy.copyMonitorFanSensorFilter.text(for: language))

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredTemperatures) { sensor in
                                Toggle(isOn: Binding(
                                    get: { model.configuration.selectedSensorKeys.contains(sensor.key) },
                                    set: { model.setSensor(sensor.key, enabled: $0, reading: reading) }
                                )) {
                                    HStack(spacing: 6) {
                                        Text(SMCTemperatureName.displayName(
                                            for: sensor.key,
                                            language: language
                                        ))
                                        Text(sensor.key)
                                            .foregroundStyle(MacTheme.textSecondary)
                                        Spacer(minLength: 0)
                                        Text(MonitorFanFormat.temperature(sensor.celsius))
                                            .monospacedDigit()
                                    }
                                    .font(.system(size: 9, weight: .medium))
                                }
                                .toggleStyle(.checkbox)
                                .frame(minHeight: 22)
                            }
                            if filteredTemperatures.isEmpty {
                                Text(ContractCopy.copyMonitorFanSensorFilterEmpty.text(for: language))
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(MacTheme.textSecondary)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxHeight: 150)

                    Text(ContractCopy.copyMonitorFanSensorLibraryHint.text(for: language))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                }
            } label: {
                Text(ContractCopy.copyMonitorFanControlSensors.text(for: language))
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(10)
        .popoverContentSurface()
    }

    private var filteredTemperatures: [MonitorFanReading.Temperature] {
        reading.temperatures.filter { sensor in
            SMCTemperatureName.matches(sensor.key, query: sensorQuery)
        }
    }

    private var systemControlCallout: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "fanblades.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MonitorFanPresetStyle.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(ContractCopy.copyMonitorFanSystemControlTitle.text(for: language))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Text(ContractCopy.copyMonitorFanSystemControlBody.text(for: language))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = model.visibleErrorMessage {
                    Text(message)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTheme.errorText)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monitorFanGlassPanel(cornerRadius: 14)
    }
}

private struct MonitorFanSnapshotSlider: View {
    let value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(
                1,
                max(0, (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound))
            )
            let knobX = max(0, min(proxy.size.width - 16, proxy.size.width * fraction - 8))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MacTheme.textSecondary.opacity(0.18))
                    .frame(height: 5)
                Capsule()
                    .fill(MacTheme.accent)
                    .frame(width: max(5, proxy.size.width * fraction), height: 5)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .offset(x: knobX)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 22)
        .accessibilityHidden(true)
    }
}

private struct MonitorFanSnapshotSwitch: View {
    let isOn: Bool
    let label: String

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? MacTheme.accent : MacTheme.textSecondary.opacity(0.18))
                .frame(width: 42, height: 24)
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                .padding(2)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

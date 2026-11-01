import SwiftUI
import kmpDomain

/// Stats 风格的实时监控页。
///
/// 页面只在自己出现时运行采样任务。`HubView` 切到别的页后，SwiftUI 会取消
/// `.task`，采样器随之停止。
struct MonitorTabView: View {
    let language: AppLanguage
    let powerModel: (any PowerManagementModel)?
    let runtime: AppRuntime?
    let popoverCoordinator: HubPopoverCoordinator?
    private let runsSampling: Bool
    private let powerPopoverInitiallyPresented: Bool
    private let powerPopoverInitialTab: MonitorPowerDetailTab
    private let displayPopoverInitiallyPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: MonitorSnapshot
    @State private var history: MonitorHistory
    @State private var powerHistory = MonitorPowerHistory()
    @State private var sampler = MonitorSampler()
    @State private var reportPresented = false
    @StateObject private var fanControlModel = MonitorFanControlModel()

    init(
        language: AppLanguage,
        powerModel: (any PowerManagementModel)? = nil,
        runtime: AppRuntime? = nil,
        popoverCoordinator: HubPopoverCoordinator? = nil,
        initialSnapshot: MonitorSnapshot = .empty,
        initialHistory: MonitorHistory = MonitorHistory(),
        initialPowerHistory: MonitorPowerHistory = MonitorPowerHistory(),
        runsSampling: Bool = true,
        powerPopoverInitiallyPresented: Bool = false,
        powerPopoverInitialTab: MonitorPowerDetailTab = .details,
        displayPopoverInitiallyPresented: Bool = false
    ) {
        self.language = language
        self.powerModel = powerModel ?? runtime
        self.runtime = runtime
        self.popoverCoordinator = popoverCoordinator
        self.runsSampling = runsSampling
        self.powerPopoverInitiallyPresented = powerPopoverInitiallyPresented
        self.powerPopoverInitialTab = powerPopoverInitialTab
        self.displayPopoverInitiallyPresented = displayPopoverInitiallyPresented
        _snapshot = State(initialValue: initialSnapshot)
        _history = State(initialValue: initialHistory)
        _powerHistory = State(initialValue: initialPowerHistory)
    }

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 170), spacing: MacTheme.space3),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space2) {
            toolbarRow
            overview
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            fanControlModel.updateGlobalHelperStatus(runtime?.helperStatus ?? powerModel?.helperStatus)
            guard runsSampling else { return }
            await runSamples()
        }
        .task {
            guard runsSampling else { return }
            await runPowerSamples()
        }
        .sheet(isPresented: $reportPresented) {
            if let reportModel = runtime?.monitorHistoryReport {
                MonitorReportView(model: reportModel, language: language)
            }
        }
        .onChange(of: runtime?.helperStatus) { _, _ in
            fanControlModel.updateGlobalHelperStatus(runtime?.helperStatus ?? powerModel?.helperStatus)
        }
    }

    @ViewBuilder
    private var toolbarRow: some View {
        HStack(spacing: MacTheme.space2) {
            statusRow
                .frame(maxWidth: .infinity, alignment: .leading)
            if runtime?.monitorHistoryReport != nil {
                Button(ContractCopy.copyMonitorReportOpen.text(for: language)) {
                    reportPresented = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint(ContractCopy.copyMonitorReportSummary.text(for: language))
            }
        }
        .frame(height: HubMetrics.monitorToolbarHeight)
    }

    private var overview: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: MacTheme.space3) {
                cpuCard
                gpuCard
                memoryCard
                diskCard
                networkCard
                powerCard
                displayCard
                fanCard
            }
        }
    }

    // MARK: - 采样

    private func runSamples() async {
        while !Task.isCancelled {
            let next = await sampler.sample()
            guard !Task.isCancelled else { break }
            await MainActor.run {
                snapshot = next
                if let fan = next.fan {
                    fanControlModel.updatePowerSource(next.fanPowerSource, reading: fan)
                }
                history.append(
                    next,
                    fanControlTemperature: next.fan.flatMap {
                        fanControlModel.configuration.controlTemperature(in: $0)
                    }
                )
            }
            do {
                try await Task.sleep(for: .seconds(MonitorCadence.interval(for: next)))
            } catch {
                break
            }
        }
    }

    /// 电源数据独立刷新。耗电窗口内部每 10 秒扫描一次进程。
    private func runPowerSamples() async {
        while !Task.isCancelled {
            let power = await sampler.samplePowerOnly()
            guard !Task.isCancelled else { break }
            await MainActor.run {
                snapshot = snapshot.replacingPower(power)
                if let fan = snapshot.fan {
                    fanControlModel.updatePowerSource(snapshot.fanPowerSource, reading: fan)
                }
                powerHistory.append(power)
            }
            do {
                try await Task.sleep(for: .seconds(MonitorPowerFormat.powerRefreshSeconds))
            } catch {
                break
            }
        }
    }

    // MARK: - 状态行

    private var statusRow: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .accessibilityHidden(true)
    }

    // MARK: - 卡片

    @ViewBuilder
    private var cpuCard: some View {
        if let cpu = snapshot.cpu {
            MonitorGaugeCard(
                kind: .cpu,
                fraction: cpu.usage,
                value: MonitorFormat.percent(cpu.usage),
                history: history.cpu,
                accent: MonitorCardKind.cpu.accent,
                language: language,
                perCore: cpu.perCore,
                details: [
                    .init(ContractCopy.copyMonitorPerCore.text(for: language), MonitorFormat.percent(cpu.perCore.reduce(0, +) / Double(max(1, cpu.perCore.count)))),
                    .init(ContractCopy.copyMonitorLoad1.text(for: language), MonitorFormat.load(cpu.loadAverage)),
                    .init(ContractCopy.copyMonitorCores.text(for: language), "\(cpu.coreCount)"),
                ]
            )
        } else {
            MonitorUnavailableCard(kind: .cpu, language: language)
        }
    }

    @ViewBuilder
    private var gpuCard: some View {
        if let gpu = snapshot.gpu {
            MonitorGaugeCard(
                kind: .gpu,
                fraction: gpu.usage,
                value: MonitorFormat.percent(gpu.usage),
                history: history.gpu,
                accent: MonitorCardKind.gpu.accent,
                language: language,
                perCore: nil,
                details: [
                    .init(ContractCopy.copyMonitorGpuMemory.text(for: language), MonitorFormat.bytes(gpu.memoryUsed)),
                    .init(ContractCopy.copyMonitorGpuDevice.text(for: language), gpu.model),
                ]
            )
        } else {
            MonitorUnavailableCard(kind: .gpu, language: language)
        }
    }

    @ViewBuilder
    private var memoryCard: some View {
        if let memory = snapshot.memory, memory.total > 0 {
            let fraction = memory.used / memory.total
            MonitorGaugeCard(
                kind: .memory,
                fraction: fraction,
                value: MonitorFormat.percent(fraction),
                history: history.memory,
                accent: MonitorCardKind.memory.accent,
                language: language,
                perCore: nil,
                details: [
                    .init(ContractCopy.copyMonitorMemoryUsed.text(for: language), MonitorFormat.bytes(memory.used)),
                    .init(ContractCopy.copyMonitorMemoryTotal.text(for: language), MonitorFormat.bytes(memory.total)),
                    .init(ContractCopy.copyMonitorMemorySwap.text(for: language), MonitorFormat.bytes(memory.swapUsed)),
                    .init(ContractCopy.copyMonitorMemoryPressure.text(for: language), pressureText(memory.pressure)),
                ]
            )
        } else {
            MonitorUnavailableCard(kind: .memory, language: language)
        }
    }

    @ViewBuilder
    private var diskCard: some View {
        if let disk = snapshot.disk, disk.total > 0 {
            let fraction = disk.used / disk.total
            MonitorGaugeCard(
                kind: .disk,
                fraction: fraction,
                value: MonitorFormat.percent(fraction),
                history: history.disk,
                accent: MonitorCardKind.disk.accent,
                language: language,
                perCore: nil,
                details: [
                    .init(ContractCopy.copyMonitorDiskRead.text(for: language), MonitorFormat.rate(disk.readRate)),
                    .init(ContractCopy.copyMonitorDiskWrite.text(for: language), MonitorFormat.rate(disk.writeRate)),
                    .init(ContractCopy.copyMonitorDiskFree.text(for: language), MonitorFormat.bytes(disk.free)),
                ]
            )
        } else {
            MonitorUnavailableCard(kind: .disk, language: language)
        }
    }

    @ViewBuilder
    private var powerCard: some View {
        if let power = snapshot.power {
            MonitorPowerCard(
                power: power,
                history: powerHistory,
                language: language,
                reduceMotion: reduceMotion,
                runtime: runtime,
                powerModel: powerModel,
                popoverCoordinator: popoverCoordinator,
                popoverInitiallyPresented: powerPopoverInitiallyPresented,
                popoverInitialTab: powerPopoverInitialTab,
                onOpenApp: openApplication
            )
        } else {
            MonitorPowerCard(
                power: MonitorSnapshot.Power.empty,
                history: powerHistory,
                language: language,
                reduceMotion: reduceMotion,
                runtime: runtime,
                powerModel: powerModel,
                popoverCoordinator: popoverCoordinator,
                popoverInitiallyPresented: powerPopoverInitiallyPresented,
                popoverInitialTab: powerPopoverInitialTab,
                onOpenApp: openApplication
            )
        }
    }

    @ViewBuilder
    private var fanCard: some View {
        if let fan = snapshot.fan, !fan.units.isEmpty {
            MonitorFanCard(
                reading: fan,
                cpuHistory: history.cpu,
                temperatureHistory: history.fanTemperature,
                rpmHistory: history.fanRPM,
                language: language,
                model: fanControlModel,
                popoverCoordinator: popoverCoordinator
            )
        }
    }

    private var displayCard: some View {
        MonitorDisplayCard(
            display: snapshot.display ?? .empty,
            language: language,
            powerModel: powerModel,
            popoverCoordinator: popoverCoordinator,
            popoverInitiallyPresented: displayPopoverInitiallyPresented
        )
    }

    @ViewBuilder
    private var networkCard: some View {
        if let network = snapshot.network {
            MonitorNetworkCard(
                network: network,
                downloadHistory: history.download,
                uploadHistory: history.upload,
                language: language
            )
        } else {
            MonitorUnavailableCard(kind: .network, language: language)
        }
    }

    private func pressureText(_ pressure: MonitorSnapshot.MemoryPressure) -> String {
        switch pressure {
        case .normal: ContractCopy.copyMonitorMemoryPressureNormal.text(for: language)
        case .warning: ContractCopy.copyMonitorMemoryPressureWarning.text(for: language)
        case .critical: ContractCopy.copyMonitorMemoryPressureCritical.text(for: language)
        }
    }

    private func openApplication(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in }
    }
}

// MARK: - 卡片种类

enum MonitorCardKind {
    case cpu
    case gpu
    case memory
    case disk
    case network
    case power
    case display
    case fan

    var title: LocalizedCopy {
        switch self {
        case .cpu: ContractCopy.copyMonitorTitleCpu
        case .gpu: ContractCopy.copyMonitorTitleGpu
        case .memory: ContractCopy.copyMonitorTitleMemory
        case .disk: ContractCopy.copyMonitorTitleDisk
        case .network: ContractCopy.copyMonitorTitleNetwork
        case .power: ContractCopy.copyMonitorTitleBattery
        case .display: ContractCopy.copyMonitorTitleDisplay
        case .fan: ContractCopy.copyMonitorFanTitle
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.stack.3d.up.fill"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .power: "powerplug.fill"
        case .display: "display"
        case .fan: "fanblades.fill"
        }
    }

    var accent: Color {
        switch self {
        case .cpu: MacTheme.color(ContractColors.tokenColorBrand)
        case .gpu: MacTheme.accent
        case .memory: MacTheme.color(ContractColors.tokenColorSuccessFill)
        case .disk: MacTheme.color(ContractColors.tokenColorWarningFill)
        case .network: MacTheme.color(ContractColors.tokenColorErrorText)
        case .power: MacTheme.color(ContractColors.tokenColorSuccessFill)
        case .display: MacTheme.color(ContractColors.tokenColorBrand)
        case .fan: MacTheme.color(ContractColors.tokenColorBrand)
        }
    }
}

// MARK: - 电源卡片

private struct MonitorPowerCard: View {
    let power: MonitorSnapshot.Power
    let history: MonitorPowerHistory
    let language: AppLanguage
    let reduceMotion: Bool
    let runtime: AppRuntime?
    let powerModel: (any PowerManagementModel)?
    let popoverCoordinator: HubPopoverCoordinator?
    let popoverInitiallyPresented: Bool
    let popoverInitialTab: MonitorPowerDetailTab
    let onOpenApp: (String) -> Void

    @AppStorage("monitor.power.detailsExpanded") private var detailsExpanded = false
    @State private var detailsPresented = false
    @State private var popoverID = UUID().uuidString
    @State private var chargingPulse = false
    @FocusState private var isFocused: Bool

    private var lowBattery: Bool {
        guard let percent = power.batteryPercent else { return false }
        return percent < MonitorPowerFormat.lowBatteryPercent
    }

    private var criticalBattery: Bool {
        guard let percent = power.batteryPercent else { return false }
        return percent < MonitorPowerFormat.criticalBatteryPercent
    }

    private var highTemperature: Bool {
        guard let value = power.temperatureCelsius else { return false }
        return value >= MonitorPowerFormat.highTemperatureCelsius
    }

    private var accent: Color {
        switch power.supply {
        case .charging, .adapter:
            MacTheme.successText
        case .battery:
            lowBattery ? MacTheme.errorText : MacTheme.brand
        case .unknown:
            MacTheme.textSecondary
        }
    }

    private var temperatureAccent: Color {
        highTemperature ? MacTheme.errorText : MacTheme.warningText
    }

    private var statusText: String {
        switch power.supply {
        case .battery: ContractCopy.copyMonitorPowerStateBattery.text(for: language)
        case .charging: ContractCopy.copyMonitorStateCharging.text(for: language)
        case .adapter: ContractCopy.copyMonitorPowerStateConnected.text(for: language)
        case .unknown: ContractCopy.copyMonitorStateUnknown.text(for: language)
        }
    }

    private var detailActionText: String {
        if detailsPresented {
            return powerModel == nil
                ? ContractCopy.copyMonitorPowerDetailsCollapse.text(for: language)
                : ContractCopy.copyMonitorPowerDetailsCollapseSettings.text(for: language)
        }
        return powerModel == nil
            ? ContractCopy.copyMonitorPowerDetailsExpand.text(for: language)
            : ContractCopy.copyMonitorPowerDetailsExpandSettings.text(for: language)
    }

    var body: some View {
        Button {
            toggleDetails()
        } label: {
            MonitorCardShell(
                kind: .power,
                accent: accent,
                language: language,
                combinesAccessibility: false
            ) {
                VStack(alignment: .leading, spacing: MacTheme.space2) {
                    HStack(spacing: MacTheme.space3) {
                        MonitorPowerRing(
                            fraction: batteryFraction,
                            accent: accent,
                            value: batteryValue,
                            isCharging: power.supply == .charging,
                            chargingPulse: chargingPulse,
                            reduceMotion: reduceMotion
                        )
                        MonitorPowerTrendSection(
                            power: power,
                            history: history,
                            language: language,
                            powerAccent: accent,
                            temperatureAccent: temperatureAccent,
                            warning: warningHint
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                    MonitorDetailRows(details: cardDetails)
                    detailActionRow
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
            MonitorPowerDetailPanel(
                power: power,
                history: history,
                language: language,
                reduceMotion: reduceMotion,
                runtime: runtime,
                powerModel: powerModel,
                initialTab: popoverInitialTab,
                onOpenApp: onOpenApp,
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
        .accessibilityHint(detailActionText)
        .onDisappear {
            popoverCoordinator?.setPresented(false, id: popoverID)
        }
        .task(id: power.supply) {
            chargingPulse = false
            guard power.supply == .charging, !reduceMotion else { return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.7)) {
                    chargingPulse.toggle()
                }
                do {
                    try await Task.sleep(for: .milliseconds(700))
                } catch {
                    break
                }
            }
        }
    }

    private var accessibilityLabel: String {
        let percent = MonitorPowerFormat.percent(power.batteryPercent)
        let temperature = MonitorPowerFormat.temperature(power.temperatureCelsius)
        return "\(ContractCopy.copyMonitorTitleBattery.text(for: language)), \(statusText), \(percent), \(temperature)"
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

    /// 同时更新 Popover 与协调器。先登记再等窗口出现，避免指针事件抢先启动收起。
    private func setDetailsPresented(_ presented: Bool) {
        detailsPresented = presented
        popoverCoordinator?.setPresented(presented, id: popoverID)
    }

    private var batteryFraction: Double {
        min(1, max(0, (power.batteryPercent ?? 0) / 100))
    }

    private var batteryValue: String {
        power.hasBattery ? MonitorPowerFormat.percent(power.batteryPercent) : "—"
    }

    private var cardDetails: [MonitorDetail] {
        var details = [
            MonitorDetail(ContractCopy.copyMonitorBatteryState.text(for: language), statusText),
            MonitorDetail(
                ContractCopy.copyMonitorPowerDraw.text(for: language),
                MonitorPowerFormat.watts(power.watts)
            ),
        ]
        if power.hasBattery {
            details.append(
                MonitorDetail(
                    ContractCopy.copyMonitorPowerTemperature.text(for: language),
                    MonitorPowerFormat.temperature(power.temperatureCelsius)
                )
            )
        }
        return details
    }

    private var detailActionRow: some View {
        HStack(spacing: 4) {
            Text(detailActionText)
                .foregroundStyle(MacTheme.textSecondary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(accent)
                .rotationEffect(detailsPresented ? .degrees(90) : .zero)
                .animation(
                    .easeInOut(duration: MonitorPowerFormat.detailAnimationSeconds),
                    value: detailsPresented
                )
        }
        .font(.system(size: 9, weight: .medium))
        .frame(height: 12)
    }

    private var warningHint: MonitorPowerWarning? {
        if criticalBattery {
            return MonitorPowerWarning(
                text: ContractCopy.copyMonitorPowerCriticalBattery.text(for: language),
                symbol: "exclamationmark.octagon.fill",
                color: MacTheme.errorText
            )
        }
        if lowBattery {
            return MonitorPowerWarning(
                text: ContractCopy.copyMonitorPowerLowBattery.text(for: language),
                symbol: "exclamationmark.triangle.fill",
                color: MacTheme.errorText
            )
        }
        if highTemperature {
            return MonitorPowerWarning(
                text: ContractCopy.copyMonitorPowerHighTemperature.text(for: language),
                symbol: "thermometer.high",
                color: MacTheme.errorText
            )
        }
        if power.hasReadFailure {
            return MonitorPowerWarning(
                text: ContractCopy.copyMonitorPowerReadFailed.text(for: language),
                symbol: "exclamationmark.triangle.fill",
                color: MacTheme.warningText
            )
        }
        return nil
    }
}

private struct MonitorPowerWarning {
    let text: String
    let symbol: String
    let color: Color
}

private struct MonitorPowerRing: View {
    let fraction: Double
    let accent: Color
    let value: String
    let isCharging: Bool
    let chargingPulse: Bool
    let reduceMotion: Bool

    var body: some View {
        MonitorRing(fraction: fraction, accent: accent, value: value)
            .overlay(alignment: .bottomTrailing) {
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(MacTheme.successText)
                        .padding(3)
                        .background(MacTheme.successBackground, in: Circle())
                        .opacity(reduceMotion || chargingPulse ? 1 : 0.38)
                        .scaleEffect(reduceMotion || chargingPulse ? 1 : 0.86)
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: 72, height: 72)
            .accessibilityHidden(true)
    }
}

private struct MonitorPowerTrendSection: View {
    let power: MonitorSnapshot.Power
    let history: MonitorPowerHistory
    let language: AppLanguage
    let powerAccent: Color
    let temperatureAccent: Color
    let warning: MonitorPowerWarning?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let warning {
                    Label(warning.text, systemImage: warning.symbol)
                        .foregroundStyle(warning.color)
                } else {
                    Text(ContractCopy.copyMonitorPowerTrendTitle.text(for: language))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Text(ContractCopy.copyMonitorPowerTrendWindow.text(for: language))
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            HStack(spacing: 7) {
                trendLegend(
                    symbol: "bolt.fill",
                    value: MonitorPowerFormat.watts(power.watts),
                    color: powerAccent
                )
                trendLegend(
                    symbol: "thermometer.medium",
                    value: MonitorPowerFormat.temperature(power.temperatureCelsius),
                    color: temperatureAccent
                )
                Spacer(minLength: 0)
            }

            MonitorPowerDualLineChart(
                powerValues: history.recentPower.map(Optional.some),
                temperatureValues: power.hasBattery
                    ? history.recentTemperature.map(Optional.some)
                    : [],
                powerAccent: powerAccent,
                temperatureAccent: temperatureAccent,
                emptyText: ContractCopy.copyMonitorPowerHistoryAccumulating.text(for: language)
            )
            .frame(height: 42)
        }
    }

    private func trendLegend(symbol: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
                .monospacedDigit()
        }
    }
}

private struct MonitorPowerDualLineChart: View {
    let powerValues: [Double?]
    let temperatureValues: [Double?]
    let powerAccent: Color
    let temperatureAccent: Color
    let emptyText: String

    var body: some View {
        GeometryReader { proxy in
            let powerCount = validCount(powerValues)
            let temperatureCount = validCount(temperatureValues)
            let hasAnyData = powerCount + temperatureCount > 0
            let hasEnoughData = max(powerCount, temperatureCount) >= 2
            ZStack {
                linePath(values: powerValues, in: proxy.size, zeroBaseline: true)
                    .stroke(
                        powerAccent,
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )
                linePath(values: temperatureValues, in: proxy.size, zeroBaseline: false)
                    .stroke(
                        temperatureAccent.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    )
                markerPath(values: powerValues, in: proxy.size, zeroBaseline: true)
                    .fill(powerAccent)
                markerPath(values: temperatureValues, in: proxy.size, zeroBaseline: false)
                    .fill(temperatureAccent)

                if !hasAnyData {
                    Text(emptyText)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !hasEnoughData {
                    Text(emptyText)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MacTheme.surface.opacity(0.72), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func validCount(_ values: [Double?]) -> Int {
        values.filter { $0?.isFinite == true }.count
    }

    private func markerPath(
        values: [Double?],
        in size: CGSize,
        zeroBaseline: Bool
    ) -> Path {
        let finiteValues = values.compactMap { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return value
        }
        guard let lastIndex = values.lastIndex(where: { $0?.isFinite == true }),
              let lastValue = values[lastIndex],
              !finiteValues.isEmpty
        else { return Path() }

        let minimum = zeroBaseline ? 0 : (finiteValues.min() ?? 0) - 1
        let maximum = zeroBaseline
            ? max(finiteValues.max() ?? 1, 0.1)
            : max((finiteValues.max() ?? 1) + 1, minimum + 1)
        let span = max(0.001, maximum - minimum)
        let denominator = max(1, values.count - 1)
        let x = values.count == 1
            ? size.width
            : size.width * CGFloat(lastIndex) / CGFloat(denominator)
        let normalized = min(1, max(0, (lastValue - minimum) / span))
        let y = size.height - CGFloat(normalized) * max(0, size.height - 2) - 1
        var path = Path()
        path.addEllipse(in: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 3.6))
        return path
    }

    private func linePath(
        values: [Double?],
        in size: CGSize,
        zeroBaseline: Bool
    ) -> Path {
        let finiteValues = values.compactMap { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return value
        }
        guard !finiteValues.isEmpty else { return Path() }

        let minimum = zeroBaseline ? 0 : (finiteValues.min() ?? 0) - 1
        let maximum = zeroBaseline
            ? max(finiteValues.max() ?? 1, 0.1)
            : max((finiteValues.max() ?? 1) + 1, minimum + 1)
        let span = max(0.001, maximum - minimum)
        let denominator = max(1, values.count - 1)
        var path = Path()
        var hasCurrentPoint = false

        for (index, raw) in values.enumerated() {
            guard let value = raw, value.isFinite else {
                hasCurrentPoint = false
                continue
            }
            let x = values.count == 1
                ? size.width
                : size.width * CGFloat(index) / CGFloat(denominator)
            let normalized = min(1, max(0, (value - minimum) / span))
            let y = size.height - CGFloat(normalized) * max(0, size.height - 2) - 1
            let point = CGPoint(x: x, y: y)
            if hasCurrentPoint {
                path.addLine(to: point)
            } else {
                path.move(to: point)
            }
            hasCurrentPoint = true
        }
        return path
    }
}

// MARK: - 可展开详情

enum MonitorPowerDetailTab: Hashable {
    case details
    case power
}

struct MonitorPowerDetailPanel: View {
    let power: MonitorSnapshot.Power
    let history: MonitorPowerHistory
    let language: AppLanguage
    let reduceMotion: Bool
    let runtime: AppRuntime?
    let powerModel: (any PowerManagementModel)?
    let onOpenApp: (String) -> Void
    let onClose: () -> Void

    @State private var selectedTab: MonitorPowerDetailTab

    init(
        power: MonitorSnapshot.Power,
        history: MonitorPowerHistory,
        language: AppLanguage,
        reduceMotion: Bool,
        runtime: AppRuntime?,
        powerModel: (any PowerManagementModel)? = nil,
        initialTab: MonitorPowerDetailTab = .details,
        onOpenApp: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.power = power
        self.history = history
        self.language = language
        self.reduceMotion = reduceMotion
        self.runtime = runtime
        self.powerModel = powerModel
        self.onOpenApp = onOpenApp
        self.onClose = onClose
        _selectedTab = State(initialValue: powerModel == nil ? .details : initialTab)
    }

    private var detailHeight: CGFloat {
        let available = NSScreen.main?.visibleFrame.height ?? 800
        return min(MonitorPowerDetailLayoutPolicy.fullHeight, max(300, available - 140))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if powerModel != nil {
                Picker(ContractCopy.copyPowerPopoverTitle.text(for: language), selection: $selectedTab) {
                    Text(ContractCopy.copyPowerPopoverDetails.text(for: language))
                        .tag(MonitorPowerDetailTab.details)
                    Text(ContractCopy.copyPowerPopoverPower.text(for: language))
                        .tag(MonitorPowerDetailTab.power)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel(ContractCopy.copyPowerPopoverTitle.text(for: language))
            }

            if selectedTab == .power, let powerModel {
                PowerManagementView(model: powerModel)
            } else {
                GeometryReader { proxy in
                    detailsContent(height: proxy.size.height)
                }
            }
        }
        .padding(MacTheme.space4)
        .frame(width: 560, height: detailHeight)
    }

    @ViewBuilder
    private func detailsContent(height: CGFloat) -> some View {
        let visibility = MonitorPowerDetailLayoutPolicy.resolve(height: height)
        VStack(alignment: .leading, spacing: 8) {
            if power.hasBattery {
                MonitorPowerChargeLimitControls(
                    runtime: runtime,
                    power: power,
                    language: language
                )
            }
            if visibility.showsTopApps {
                topAppsSection
            }
            if visibility.showsHistory {
                historySection
            }
            if visibility.showsEstimate, power.hasBattery {
                estimateSection
            }
            if visibility.showsCharging,
               power.hasBattery,
               power.supply == .charging || power.supply == .adapter {
                chargingSection
            }
            if visibility.showsEvents {
                eventsSection
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: MacTheme.space2) {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
            Text(
                selectedTab == .power
                    ? ContractCopy.copyPowerPopoverTitle.text(for: language)
                    : ContractCopy.copyMonitorPowerDetailsTitle.text(for: language)
            )
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

    private var accent: Color {
        switch power.supply {
        case .charging, .adapter: MacTheme.successText
        case .battery: MacTheme.brand
        case .unknown: MacTheme.textSecondary
        }
    }

    private var topAppsSection: some View {
        MonitorPowerDetailSection(
            title: ContractCopy.copyMonitorPowerTopApps.text(for: language)
        ) {
            if power.energyDataAvailable, !power.topApps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(power.topApps.prefix(3))) { app in
                        if let bundlePath = app.bundlePath {
                            Button {
                                onOpenApp(bundlePath)
                            } label: {
                                topAppRow(app)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .frame(height: 28)
                            .accessibilityLabel(
                                "\(app.name), \(MonitorPowerFormat.energy(app.energyMilliwattHours)), \(MonitorPowerFormat.share(app.share))"
                            )
                        } else {
                            topAppRow(app)
                                .frame(height: 28)
                        }
                    }
                }
            } else {
                emptyRow(ContractCopy.copyMonitorPowerNoData.text(for: language))
            }
        }
    }

    private func topAppRow(_ app: MonitorSnapshot.Power.TopApp) -> some View {
        HStack(spacing: MacTheme.space2) {
            Text(app.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(MonitorPowerFormat.energy(app.energyMilliwattHours))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(MacTheme.textSecondary)
                .monospacedDigit()
            Text(MonitorPowerFormat.share(app.share))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var historySection: some View {
        let points = history.minutePoints
        return MonitorPowerDetailSection(
            title: ContractCopy.copyMonitorPowerHistoryTitle.text(for: language)
        ) {
            HStack(spacing: 10) {
                detailLegend(
                    symbol: "bolt.fill",
                    value: MonitorPowerFormat.watts(points.last?.watts),
                    color: MacTheme.successText
                )
                if power.hasBattery {
                    detailLegend(
                        symbol: "thermometer.medium",
                        value: MonitorPowerFormat.temperature(points.last?.temperatureCelsius),
                        color: MacTheme.warningText
                    )
                }
                Spacer(minLength: 0)
            }
            MonitorPowerDualLineChart(
                powerValues: points.map(\.watts),
                temperatureValues: power.hasBattery ? points.map(\.temperatureCelsius) : [],
                powerAccent: MacTheme.successText,
                temperatureAccent: MacTheme.warningText,
                emptyText: ContractCopy.copyMonitorPowerHistoryAccumulating.text(for: language)
            )
            .frame(height: 104)
        }
    }

    private var estimateSection: some View {
        MonitorPowerDetailSection(
            title: ContractCopy.copyMonitorPowerRemaining.text(for: language)
        ) {
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerRemaining.text(for: language),
                value: MonitorPowerFormat.remaining(power.remainingSeconds, language: language),
                symbol: "hourglass"
            )
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerAverageDraw.text(for: language),
                value: MonitorPowerFormat.watts(power.averageWatts),
                symbol: "chart.line.uptrend.xyaxis"
            )
            Text(ContractCopy.copyMonitorPowerEstimateBasis.text(for: language))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
        }
    }

    private var chargingSection: some View {
        MonitorPowerDetailSection(
            title: ContractCopy.copyMonitorPowerChargeTitle.text(for: language)
        ) {
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerChargePower.text(for: language),
                value: MonitorPowerFormat.watts(power.chargePowerWatts),
                symbol: "bolt.fill",
                color: MacTheme.successText
            )
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerChargeTimeToFull.text(for: language),
                value: MonitorPowerFormat.remaining(power.timeToFullSeconds, language: language),
                symbol: "timer"
            )
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerChargeHealth.text(for: language),
                value: MonitorPowerFormat.percent(power.batteryHealthPercent),
                symbol: "heart.text.square"
            )
        }
    }

    private var eventsSection: some View {
        MonitorPowerDetailSection(
            title: ContractCopy.copyMonitorPowerEventsTitle.text(for: language)
        ) {
            if power.events.isEmpty {
                emptyRow(ContractCopy.copyMonitorPowerNoData.text(for: language))
            } else {
                ForEach(Array(power.events.suffix(3).reversed())) { event in
                    HStack(spacing: MacTheme.space2) {
                        Image(systemName: eventSymbol(event.kind))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(eventColor(event.kind))
                            .frame(width: 12)
                        Text(eventText(event.kind))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MacTheme.textPrimary)
                        Spacer(minLength: 4)
                        Text(MonitorPowerFormat.eventTime(event.at, language: language))
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                    .frame(height: 22)
                }
            }
        }
    }

    private func detailLegend(symbol: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
                .monospacedDigit()
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(MacTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
    }

    private func eventText(_ kind: MonitorPowerEvent.Kind) -> String {
        switch kind {
        case .connected: ContractCopy.copyMonitorPowerEventsConnected.text(for: language)
        case .disconnected: ContractCopy.copyMonitorPowerEventsDisconnected.text(for: language)
        case .fullyCharged: ContractCopy.copyMonitorPowerEventsFullyCharged.text(for: language)
        }
    }

    private func eventSymbol(_ kind: MonitorPowerEvent.Kind) -> String {
        switch kind {
        case .connected: "powerplug.fill"
        case .disconnected: "powerplug"
        case .fullyCharged: "battery.100percent.bolt"
        }
    }

    private func eventColor(_ kind: MonitorPowerEvent.Kind) -> Color {
        switch kind {
        case .connected, .fullyCharged: MacTheme.successText
        case .disconnected: MacTheme.textSecondary
        }
    }
}

private struct MonitorPowerChargeLimitControls: View {
    let runtime: AppRuntime?
    let power: MonitorSnapshot.Power
    let language: AppLanguage

    @State private var pendingLimit: Double
    @State private var pendingActiveDischarge: Bool
    @State private var busy = false
    @State private var localError: String?

    init(runtime: AppRuntime?, power: MonitorSnapshot.Power, language: AppLanguage) {
        self.runtime = runtime
        self.power = power
        self.language = language
        _pendingLimit = State(
            initialValue: Double(
                runtime?.config.chargeLimitPercent
                    ?? ChargeLimitPolicyKt.DEFAULT_CHARGE_LIMIT_PERCENT
            )
        )
        _pendingActiveDischarge = State(
            initialValue: runtime?.config.chargeLimitActiveDischarge ?? false
        )
    }

    private var isEnabled: Bool { runtime?.config.chargeLimitEnabled == true }

    private var status: ChargeLimitHelperStatus? { runtime?.chargeLimitStatus }

    private var controlsDisabled: Bool {
        busy || runtime?.helperStatus != .match || status?.phase == "unsupported"
    }

    private var statusSymbol: String {
        guard runtime != nil, runtime?.helperStatus == .match else {
            return "exclamationmark.triangle.fill"
        }
        if localError != nil { return "exclamationmark.triangle.fill" }
        guard runtime?.config.chargeLimitEnabled == true else { return "gearshape.fill" }
        guard let status else { return "exclamationmark.triangle.fill" }
        if status.bypassEngaged { return "powerplug.fill" }
        return switch status.phase {
        case "charging", "full": "bolt.fill"
        case "discharging": "arrow.down.circle.fill"
        case "stoppingDischarge": "arrow.down.circle"
        case "holding", "sailing", "aboveLimit": "pause.circle.fill"
        case "applying", "calibration", "systemProtection": "arrow.triangle.2.circlepath"
        case "unplugged": "powerplug"
        case "unsupported", "conflict", "error": "exclamationmark.triangle.fill"
        default: "gearshape.fill"
        }
    }

    private var statusColor: Color {
        guard runtime?.helperStatus == .match else { return MacTheme.warningText }
        if localError != nil { return MacTheme.errorText }
        guard runtime?.config.chargeLimitEnabled == true else { return MacTheme.textSecondary }
        guard let status else { return MacTheme.warningText }
        if status.bypassEngaged { return MacTheme.successText }
        return switch status.phase {
        case "charging", "full", "holding", "sailing", "aboveLimit":
            MacTheme.successText
        case "discharging", "stoppingDischarge":
            MacTheme.warningText
        case "applying", "calibration", "systemProtection", "unplugged":
            MacTheme.warningText
        case "unsupported", "conflict", "error": MacTheme.errorText
        default: MacTheme.textSecondary
        }
    }

    private var statusText: String {
        guard let runtime else {
            return ContractCopy.copyMonitorPowerChargeLimitHelperRequired.text(for: language)
        }
        guard runtime.helperStatus == .match else {
            return ContractCopy.copyMonitorPowerChargeLimitHelperRequired.text(for: language)
        }
        if let localError { return localError }
        guard runtime.config.chargeLimitEnabled else {
            return ContractCopy.copyMonitorPowerChargeLimitStateSystem.text(for: language)
        }
        guard let status, status.enabled else {
            return ContractCopy.copyMonitorPowerChargeLimitFailed.text(for: language)
        }
        if status.bypassEngaged {
            return ContractCopy.copyMonitorPowerChargeLimitStateBypass.text(for: language)
        }
        return switch status.phase {
        case "applying":
            ContractCopy.copyMonitorPowerChargeLimitApplying.text(for: language)
        case "discharging":
            ContractCopy.copyMonitorPowerChargeLimitStateDischarging.text(for: language)
        case "stoppingDischarge":
            ContractCopy.copyMonitorPowerChargeLimitStateStoppingDischarge.text(for: language)
        case "charging":
            ContractCopy.copyMonitorStateCharging.text(for: language)
        case "holding":
            ContractCopy.copyMonitorPowerChargeLimitStateHolding.text(for: language)
        case "sailing":
            ContractCopy.copyMonitorPowerChargeLimitStateSailing.text(for: language)
        case "aboveLimit":
            ContractCopy.copyMonitorPowerChargeLimitStateAboveLimit.text(for: language)
        case "full":
            ContractCopy.copyMonitorStateCharged.text(for: language)
        case "calibration":
            ContractCopy.copyMonitorPowerChargeLimitStateCalibration.text(for: language)
        case "systemProtection":
            ContractCopy.copyMonitorPowerChargeLimitStateProtection.text(for: language)
        case "conflict":
            ContractCopy.copyMonitorPowerChargeLimitStateConflict.text(for: language)
        case "unplugged":
            ContractCopy.copyMonitorPowerChargeLimitStateUnplugged.text(for: language)
        case "unsupported":
            ContractCopy.copyMonitorPowerChargeLimitUnsupported.text(for: language)
        case "helperMissing":
            ContractCopy.copyMonitorPowerChargeLimitHelperRequired.text(for: language)
        case "error":
            ContractCopy.copyMonitorPowerChargeLimitStateError.text(for: language)
        default:
            ContractCopy.copyMonitorPowerChargeLimitStateSystem.text(for: language)
        }
    }

    var body: some View {
        MonitorPowerDetailSection(
            title: ContractCopy.copyMonitorPowerChargeLimitTitle.text(for: language)
        ) {
            HStack(spacing: MacTheme.space2) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: MacTheme.space2) {
                Text("\(Int(pendingLimit))%")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.textPrimary)
                    .monospacedDigit()
                    .frame(width: 46, alignment: .leading)
                Slider(value: $pendingLimit, in: 40...100, step: 5)
                    .disabled(controlsDisabled)
                    .accessibilityLabel(ContractCopy.copyMonitorPowerChargeLimitTitle.text(for: language))
            }
            .frame(height: 24)

            HStack(spacing: 5) {
                ForEach([50, 60, 70, 80, 90, 100], id: \.self) { value in
                    Button("\(value)%") {
                        pendingLimit = Double(value)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .frame(minWidth: 48, minHeight: 24)
                    .contentShape(Rectangle())
                    .disabled(controlsDisabled)
                    .accessibilityLabel("\(value)%")
                }
                Spacer(minLength: 0)
            }

            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerChargeLimitCurrentCharge.text(for: language),
                value: MonitorPowerFormat.percent(power.batteryPercent),
                symbol: "battery.75percent"
            )
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerChargeLimitCurrentTarget.text(for: language),
                value: MonitorPowerFormat.percent(status?.targetPercent.map(Double.init)),
                symbol: "scope"
            )
            MonitorPowerDetailRow(
                label: ContractCopy.copyMonitorPowerChargeLimitResumeAt.text(for: language),
                value: resumeText,
                symbol: "arrow.clockwise"
            )

            Toggle(isOn: $pendingActiveDischarge) {
                Text(ContractCopy.copyMonitorPowerChargeLimitActiveDischarge.text(for: language))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(
                controlsDisabled ||
                    pendingLimit >= 100 ||
                    status?.activeDischargeSupported == false
            )

            if pendingActiveDischarge {
                Text(ContractCopy.copyMonitorPowerChargeLimitActiveDischargeWarning.text(for: language))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: MacTheme.space2) {
                Button(isEnabled
                    ? ContractCopy.copyMonitorPowerChargeLimitApply.text(for: language)
                    : ContractCopy.copyMonitorPowerChargeLimitEnable.text(for: language)
                ) {
                    apply()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(controlsDisabled)

                if isEnabled || status?.enabled == true {
                    Button(ContractCopy.copyMonitorPowerChargeLimitRestore.text(for: language)) {
                        restore()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(busy || runtime?.helperStatus != .match)
                }
                Spacer(minLength: 0)
            }
        }
        .task {
            guard let runtime else { return }
            while !Task.isCancelled {
                runtime.refreshChargeLimitStatusInBackground()
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }
            }
        }
        .onChange(of: runtime?.config.chargeLimitPercent) { _, value in
            if let value { pendingLimit = Double(value) }
        }
        .onChange(of: runtime?.config.chargeLimitActiveDischarge) { _, value in
            if let value { pendingActiveDischarge = value }
        }
        .onChange(of: runtime?.helperStatus) { _, _ in
            runtime?.refreshChargeLimitStatus()
        }
    }

    private var resumeText: String {
        guard let limit = status?.userLimitPercent ?? runtime.map({ Int($0.config.chargeLimitPercent) })
        else { return "—" }
        let resume = ChargeLimitPolicy.shared.resumeThreshold(upperLimitPercent: Int32(limit))
        return "\(resume)%"
    }

    private func apply() {
        guard let runtime else { return }
        busy = true
        let success = runtime.applyChargeLimit(
            Int(pendingLimit),
            activeDischarge: pendingActiveDischarge
        )
        busy = false
        localError = success ? nil : ContractCopy.copyMonitorPowerChargeLimitFailed.text(for: language)
    }

    private func restore() {
        guard let runtime else { return }
        busy = true
        let success = runtime.restoreChargeLimit()
        busy = false
        localError = success ? nil : ContractCopy.copyMonitorPowerChargeLimitFailed.text(for: language)
    }
}

private struct MonitorPowerDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MacTheme.textSecondary)
                .lineLimit(1)
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popoverContentSurface(cornerRadius: 9)
    }
}

private struct MonitorPowerDetailRow: View {
    let label: String
    let value: String
    let symbol: String
    var color: Color = MacTheme.textPrimary

    var body: some View {
        HStack(spacing: MacTheme.space2) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(height: 18)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 仪表卡片

struct MonitorDetail: Identifiable {
    let label: String
    let value: String
    var id: String { "\(label):\(value)" }

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

struct MonitorDetailRows: View {
    let details: [MonitorDetail]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(details.prefix(3)) { detail in
                HStack(spacing: MacTheme.space2) {
                    Text(detail.label)
                        .foregroundStyle(MacTheme.textSecondary)
                    Spacer(minLength: MacTheme.space1)
                    Text(detail.value)
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)
                }
            }
        }
        .font(.system(size: 9, weight: .medium))
    }
}

private struct MonitorGaugeCard: View {
    let kind: MonitorCardKind
    let fraction: Double
    let value: String
    let history: [Double]
    let accent: Color
    let language: AppLanguage
    let perCore: [Double]?
    let details: [MonitorDetail]

    var body: some View {
        MonitorCardShell(kind: kind, accent: accent, language: language) {
            VStack(alignment: .leading, spacing: MacTheme.space2) {
                HStack(spacing: MacTheme.space3) {
                    MonitorRing(fraction: fraction, accent: accent, value: value)
                    VStack(alignment: .leading, spacing: MacTheme.space1) {
                        Text(ContractCopy.copyMonitorUsage.text(for: language))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MacTheme.textSecondary)
                        MonitorSparkline(values: history, accent: accent)
                            .frame(height: 58)
                    }
                }

                if let perCore {
                    MonitorCoreBars(values: perCore, accent: accent)
                }

                Spacer(minLength: 0)
                MonitorDetailRows(details: details)
            }
        }
    }
}

private struct MonitorNetworkCard: View {
    let network: MonitorSnapshot.Network
    let downloadHistory: [Double]
    let uploadHistory: [Double]
    let language: AppLanguage

    var body: some View {
        MonitorCardShell(kind: .network, accent: MonitorCardKind.network.accent, language: language) {
            VStack(alignment: .leading, spacing: MacTheme.space2) {
                HStack(spacing: MacTheme.space3) {
                    rateBlock(
                        title: ContractCopy.copyMonitorNetworkDownload.text(for: language),
                        value: MonitorFormat.rate(network.downloadRate),
                        symbol: "arrow.down",
                        color: MacTheme.accent
                    )
                    Divider().frame(height: 34)
                    rateBlock(
                        title: ContractCopy.copyMonitorNetworkUpload.text(for: language),
                        value: MonitorFormat.rate(network.uploadRate),
                        symbol: "arrow.up",
                        color: MacTheme.errorText
                    )
                }

                ZStack(alignment: .bottom) {
                    MonitorSparkline(values: uploadHistory, accent: MacTheme.errorText.opacity(0.65))
                    MonitorSparkline(values: downloadHistory, accent: MacTheme.accent)
                }
                .frame(height: 54)
                .padding(.top, MacTheme.space1)

                Spacer(minLength: 0)
                HStack(spacing: MacTheme.space2) {
                    Text(ContractCopy.copyMonitorNetworkInterface.text(for: language))
                        .foregroundStyle(MacTheme.textSecondary)
                    Spacer(minLength: MacTheme.space1)
                    Text(network.interfaceName)
                        .foregroundStyle(MacTheme.textPrimary)
                        .lineLimit(1)
                }
                .font(.system(size: 9, weight: .medium))
            }
        }
    }

    private func rateBlock(title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MonitorUnavailableCard: View {
    let kind: MonitorCardKind
    let language: AppLanguage

    var body: some View {
        MonitorCardShell(kind: kind, accent: kind.accent, language: language) {
            VStack(alignment: .leading, spacing: MacTheme.space2) {
                Spacer(minLength: 0)
                Image(systemName: "waveform.slash")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(kind.accent.opacity(0.85))
                Text(ContractCopy.copyMonitorUnavailable.text(for: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }
}

struct MonitorCardShell<Content: View>: View {
    let kind: MonitorCardKind
    let accent: Color
    let language: AppLanguage
    var combinesAccessibility = true
    var statusText: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: MacTheme.space2) {
            HStack(spacing: MacTheme.space2) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 16, height: 16)
                Text(kind.title.text(for: language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer(minLength: MacTheme.space1)
                if let statusText {
                    Text(statusText.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(accent.opacity(0.12), in: Capsule())
                }
            }

            content
        }
        .padding(MacTheme.space3)
        .frame(maxWidth: .infinity).frame(height: HubMetrics.monitorCardHeight, alignment: .topLeading)
        .background(cardBackground, in: shape)
        .glassSurface(cornerRadius: MacTheme.cardRadius)
        .overlay(shape.strokeBorder(accent.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: combinesAccessibility ? .combine : .contain)
        .accessibilityLabel(kind.title.text(for: language))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MacTheme.cardRadius, style: .continuous)
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(0.22),
                accent.opacity(0.08),
                MacTheme.surface.opacity(0.62),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - 图形件

struct MonitorRing: View {
    let fraction: Double?
    let accent: Color
    let value: String

    private var clampedFraction: Double? {
        guard let fraction, fraction.isFinite else { return nil }
        return min(1, max(0, fraction))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(MacTheme.divider.opacity(0.8), lineWidth: 7)
            if let clampedFraction {
                Circle()
                    .trim(from: 0, to: max(0.002, clampedFraction))
                    .stroke(
                        AngularGradient(
                            colors: [accent.opacity(0.45), accent, accent.opacity(0.72)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.28), value: clampedFraction)
            }
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textPrimary)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }
}

private struct MonitorSparkline: View {
    let values: [Double]
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let line = linePath(in: proxy.size)
            ZStack {
                areaPath(in: proxy.size)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.28), accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                line
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.7), accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let capacity = max(2, values.count)
        let maximum = max(values.max() ?? 0, 0.000_001)
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(max(1, capacity - 1))
            let y = size.height - (size.height - 3) * CGFloat(min(1, max(0, value / maximum)))
            return CGPoint(x: x, y: max(1.5, y))
        }
    }

    private func linePath(in size: CGSize) -> Path {
        let points = normalizedPoints(in: size)
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func areaPath(in size: CGSize) -> Path {
        let points = normalizedPoints(in: size)
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: size.height))
        path.addLine(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

private struct MonitorCoreBars: View {
    let values: [Double]
    let accent: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.prefix(16).enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(accent.opacity(0.35 + min(0.65, max(0, value) * 0.65)))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, 18 * min(1, max(0, value))))
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

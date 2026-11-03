import Charts
import SwiftUI

enum MonitorFanPresetStyle {
    static var accent: Color {
        MacTheme.color(ContractColors.tokenColorSuccessText)
    }
}

private struct MonitorFanForceOpaqueSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var monitorFanForceOpaqueSurface: Bool {
        get { self[MonitorFanForceOpaqueSurfaceKey.self] }
        set { self[MonitorFanForceOpaqueSurfaceKey.self] = newValue }
    }
}

enum MonitorFanGlassButtonShape {
    case capsule
    case circle

    var borderShape: ButtonBorderShape {
        switch self {
        case .circle: .circle
        case .capsule: .capsule
        }
    }
}

struct MonitorFanGlassButtonStyleModifier: ViewModifier {
    var shape: MonitorFanGlassButtonShape = .capsule
    let forceOpaque: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if forceOpaque {
            content
                .buttonStyle(.plain)
                .background(MacTheme.elevated.opacity(0.82), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(MacTheme.divider.opacity(0.55), lineWidth: 0.75)
                }
        } else {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(shape.borderShape)
                .controlSize(.small)
        }
    }
}

/// 风扇控制的内容面板。默认使用清透玻璃；辅助功能需要更高对比时退回不透明表面。
private struct MonitorFanGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.monitorFanForceOpaqueSurface) private var forceOpaqueSurface

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var usesOpaqueSurface: Bool {
        forceOpaqueSurface || reduceTransparency || colorSchemeContrast == .increased
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesOpaqueSurface {
            content
                .background(shape.fill(tint ?? MacTheme.surface))
                .overlay(shape.strokeBorder(MacTheme.divider, lineWidth: 1))
        } else {
            content.glassSurface(cornerRadius: cornerRadius, tint: tint, mode: .clear)
        }
    }
}

extension View {
    @MainActor
    func monitorFanGlassPanel(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        modifier(MonitorFanGlassPanelModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

/// 所有风扇共享的温度到风量曲线编辑器。
///
/// 拖动只更新本地草稿。松手时一次提交，避免连续写配置打断手势。
/// 图上的实线是预设请求，圆点是当前实际风量。
struct MonitorFanCurveEditor: View {
    let reading: MonitorFanReading
    let preset: MonitorFanPreset
    let points: [MonitorFanPresetPoint]
    let controlTemperature: Double?
    let language: AppLanguage
    let interactive: Bool
    let busy: Bool
    let isCustomized: Bool
    let onCommit: ([MonitorFanPresetPoint]) -> Void
    let onReset: () -> Void

    @State private var draftPoints: [MonitorFanPresetPoint] = []
    @State private var selectedPointIndex = 0
    @State private var draggingPointIndex: Int?
    @State private var preciseExpanded = false
    @State private var hoveredPointIndex: Int?
    @Namespace private var pointGlassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.monitorFanForceOpaqueSurface) private var forceOpaqueSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(ContractCopy.copyMonitorFanPresetCurve.text(for: language))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer(minLength: 0)
                if isCustomized {
                    Button {
                        onReset()
                        syncDraft()
                    } label: {
                        Label(
                            ContractCopy.copyMonitorFanResetPreset.text(for: language),
                            systemImage: "arrow.counterclockwise"
                        )
                        .font(.system(size: 8, weight: .semibold))
                    }
                    .modifier(MonitorFanGlassButtonStyleModifier(forceOpaque: forceOpaqueSurface))
                    .disabled(busy)
                }
            }

            chartWithInteraction

            nodeToolbar
            legend

            DisclosureGroup(isExpanded: $preciseExpanded) {
                preciseControls
                    .padding(10)
                    .monitorFanGlassPanel(cornerRadius: 12)
                    .padding(.top, 6)
            } label: {
                Text(ContractCopy.copyMonitorFanPreciseAdjust.text(for: language))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            .tint(MonitorFanPresetStyle.accent)
        }
        .onAppear(perform: syncDraft)
        .onChange(of: preset) { _, _ in
            selectedPointIndex = 0
            syncDraft()
        }
        .onChange(of: points) { _, _ in
            guard draggingPointIndex == nil else { return }
            syncDraft()
        }
    }

    private var chart: some View {
        Chart {
            ForEach(draftPoints) { point in
                AreaMark(
                    x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), point.temperature),
                    yStart: .value(ContractCopy.copyMonitorFanAirflow.text(for: language), 0),
                    yEnd: .value(ContractCopy.copyMonitorFanAirflow.text(for: language), point.percent)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            MonitorFanPresetStyle.accent.opacity(0.22),
                            MonitorFanPresetStyle.accent.opacity(0.025),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            ForEach(draftPoints) { point in
                LineMark(
                    x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), point.temperature),
                    y: .value(ContractCopy.copyMonitorFanAirflow.text(for: language), point.percent)
                )
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .foregroundStyle(MonitorFanPresetStyle.accent)
            }

            ForEach(Array(draftPoints.enumerated()), id: \.element.id) { index, point in
                PointMark(
                    x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), point.temperature),
                    y: .value(ContractCopy.copyMonitorFanAirflow.text(for: language), point.percent)
                )
                .symbolSize(index == selectedPointIndex ? 118 : 82)
                .foregroundStyle(MonitorFanPresetStyle.accent)

                PointMark(
                    x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), point.temperature),
                    y: .value(ContractCopy.copyMonitorFanAirflow.text(for: language), point.percent)
                )
                .symbolSize(index == selectedPointIndex ? 74 : 48)
                .foregroundStyle(MacTheme.surface)
            }

            if let controlTemperature {
                RuleMark(
                    x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), controlTemperature)
                )
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(MacTheme.textSecondary.opacity(0.50))
            }

            if let controlTemperature,
               let targetPercent = MonitorFanPresetCurve.targetPercent(
                   points: draftPoints,
                   temperature: controlTemperature
               ) {
                PointMark(
                    x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), controlTemperature),
                    y: .value(ContractCopy.copyMonitorFanAirflow.text(for: language), targetPercent)
                )
                .symbolSize(46)
                .foregroundStyle(MonitorFanPresetStyle.accent)

                PointMark(
                    x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), controlTemperature),
                    y: .value(ContractCopy.copyMonitorFanAirflow.text(for: language), targetPercent)
                )
                .symbolSize(22)
                .foregroundStyle(MacTheme.surface)
            }

            if let controlTemperature,
               let currentPercent = MonitorFanPresetCurve.currentPercent(in: reading) {
                PointMark(
                    x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), controlTemperature),
                    y: .value(ContractCopy.copyMonitorFanAirflow.text(for: language), currentPercent)
                )
                .symbolSize(92)
                .foregroundStyle(MonitorFanPresetStyle.accent)

                PointMark(
                    x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), controlTemperature),
                    y: .value(ContractCopy.copyMonitorFanAirflow.text(for: language), currentPercent)
                )
                .symbolSize(58)
                .foregroundStyle(MacTheme.surface)

                PointMark(
                    x: .value(ContractCopy.copyMonitorFanTemperature.text(for: language), controlTemperature),
                    y: .value(ContractCopy.copyMonitorFanAirflow.text(for: language), currentPercent)
                )
                .symbolSize(20)
                .foregroundStyle(MonitorFanPresetStyle.accent)
            }
        }
        .chartXScale(domain: 38...MonitorFanPolicy.maximumFullCelsius)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: [40, 60, 80, 100]) {
                AxisGridLine()
                    .foregroundStyle(MacTheme.textSecondary.opacity(0.18))
                AxisValueLabel()
                    .foregroundStyle(MacTheme.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine()
                    .foregroundStyle(MacTheme.textSecondary.opacity(0.18))
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text("\(Int(percent))%")
                    }
                }
                .foregroundStyle(MacTheme.textSecondary)
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .frame(height: 214)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(MacTheme.divider.opacity(0.34), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .animation(nil, value: draftPoints)
    }

    @ViewBuilder
    private var chartWithInteraction: some View {
        if interactive {
            chart
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(dragGesture(proxy: proxy, geometry: geometry))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ContractCopy.copyMonitorFanPresetA11y.text(for: language))
                .accessibilityValue(accessibilityValue)
        } else {
            chart
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ContractCopy.copyMonitorFanPresetA11y.text(for: language))
                .accessibilityValue(accessibilityValue)
        }
    }

    private var nodeToolbar: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(draftPoints.indices, id: \.self) { index in
                    let selected = index == selectedPointIndex
                    Button("\(index + 1)") {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: HubMotion.tabSwitch)) {
                            selectedPointIndex = index
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(
                        selected && forceOpaqueSurface ? Color.white : MacTheme.textPrimary
                    )
                    .frame(width: 26, height: 24)
                    .background(
                        forceOpaqueSurface && selected
                            ? MonitorFanPresetStyle.accent
                            : Color.clear,
                        in: Capsule()
                    )
                    .contentShape(Capsule())
                    .glassEffect(
                        forceOpaqueSurface
                            ? .identity
                            : selected
                                ? .regular.tint(MonitorFanPresetStyle.accent).interactive()
                                : (hoveredPointIndex == index ? .clear.interactive() : .identity),
                        in: .capsule
                    )
                    .glassEffectID(
                        selected && !forceOpaqueSurface ? "fan-point-selection" : nil,
                        in: pointGlassNamespace
                    )
                    .glassEffectTransition(.matchedGeometry)
                    .accessibilityLabel(
                        String(
                            format: ContractCopy.copyMonitorFanControlPoint.text(for: language),
                            index + 1
                        )
                    )
                    .disabled(busy)
                    .onHover { inside in
                        hoveredPointIndex = inside ? index : nil
                    }
                }

                Spacer(minLength: 0)

                Button {
                    addPoint()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .modifier(MonitorFanGlassButtonStyleModifier(
                    shape: .circle,
                    forceOpaque: forceOpaqueSurface
                ))
                .help(ContractCopy.copyMonitorFanAddPoint.text(for: language))
                .accessibilityLabel(ContractCopy.copyMonitorFanAddPoint.text(for: language))
                .disabled(busy || draftPoints.count >= MonitorFanPolicy.maximumCurvePointCount)

                Button {
                    deletePoint()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 24)
                }
                .modifier(MonitorFanGlassButtonStyleModifier(
                    shape: .circle,
                    forceOpaque: forceOpaqueSurface
                ))
                .help(ContractCopy.copyMonitorFanDeletePoint.text(for: language))
                .accessibilityLabel(ContractCopy.copyMonitorFanDeletePoint.text(for: language))
                .disabled(busy || draftPoints.count <= 2)
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: HubMotion.tabSwitch),
            value: selectedPointIndex
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: HubMotion.tabSwitch),
            value: hoveredPointIndex
        )
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(MonitorFanPresetStyle.accent)
                .frame(width: 20, height: 2)
            Text(ContractCopy.copyMonitorFanPresetLegend.text(for: language))
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)

            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .stroke(MonitorFanPresetStyle.accent, lineWidth: 1.4)
                    .frame(width: 9, height: 9)
                Circle()
                    .fill(MonitorFanPresetStyle.accent)
                    .frame(width: 3, height: 3)
            }
            Text(currentFlowText)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
                .monospacedDigit()
        }
    }

    private var preciseControls: some View {
        Group {
            if draftPoints.indices.contains(selectedPointIndex) {
                let point = draftPoints[selectedPointIndex]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(
                            format: ContractCopy.copyMonitorFanControlPoint.text(for: language),
                            selectedPointIndex + 1
                        ))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        Spacer(minLength: 0)
                        Text("\(Int(point.temperature.rounded())) °C · \(Int(point.percent.rounded()))%")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(MacTheme.textSecondary)
                            .monospacedDigit()
                    }

                    HStack(spacing: 8) {
                        Text(ContractCopy.copyMonitorFanTemperature.text(for: language))
                            .font(.system(size: 8))
                            .foregroundStyle(MacTheme.textSecondary)
                            .frame(width: 42, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { draftPoints[selectedPointIndex].temperature },
                                set: { temperature in
                                    updatePoint(
                                        selectedPointIndex,
                                        temperature: temperature,
                                        percent: draftPoints[selectedPointIndex].percent
                                    )
                                }
                            ),
                            in: MonitorFanPresetCurve.editableTemperatureRange(
                                index: selectedPointIndex,
                                points: draftPoints
                            )
                        ) { editing in
                            if !editing { commitDraft() }
                        }
                        .disabled(busy)
                    }

                    HStack(spacing: 8) {
                        Text(ContractCopy.copyMonitorFanAirflow.text(for: language))
                            .font(.system(size: 8))
                            .foregroundStyle(MacTheme.textSecondary)
                            .frame(width: 42, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { draftPoints[selectedPointIndex].percent },
                                set: { percent in
                                    updatePoint(
                                        selectedPointIndex,
                                        temperature: draftPoints[selectedPointIndex].temperature,
                                        percent: percent
                                    )
                                }
                            ),
                            in: 0...100
                        ) { editing in
                            if !editing { commitDraft() }
                        }
                        .disabled(busy)
                    }
                }
            }
        }
    }

    private var currentFlowText: String {
        let current = MonitorFanPresetCurve.currentPercent(in: reading)
            .map { "\(Int($0.rounded()))%" }
            ?? "—"
        return String(
            format: ContractCopy.copyMonitorFanPresetCurrent.text(for: language),
            current
        )
    }

    private var accessibilityValue: String {
        let pointText = draftPoints.map {
            "\(Int($0.temperature.rounded())) °C \(Int($0.percent.rounded()))%"
        }.joined(separator: "，")
        let current = MonitorFanPresetCurve.currentPercent(in: reading)
            .map { "\(Int($0.rounded()))%" }
            ?? "—"
        return "\(pointText)。\(ContractCopy.copyMonitorFanActual.text(for: language)) \(current)"
    }

    private func syncDraft() {
        draftPoints = MonitorFanPresetCurve.normalized(points)
        selectedPointIndex = min(selectedPointIndex, max(0, draftPoints.count - 1))
    }

    private func addPoint() {
        guard draftPoints.count < MonitorFanPolicy.maximumCurvePointCount else { return }
        var sorted = draftPoints.sorted { $0.temperature < $1.temperature }
        guard sorted.count >= 2 else { return }
        var insertAt = 1
        var largestGap = -Double.infinity
        for index in 1..<sorted.count {
            let gap = sorted[index].temperature - sorted[index - 1].temperature
            if gap > largestGap {
                largestGap = gap
                insertAt = index
            }
        }
        let before = sorted[insertAt - 1]
        let after = sorted[insertAt]
        sorted.insert(
            MonitorFanPresetPoint(
                temperature: ((before.temperature + after.temperature) / 2).rounded(),
                percent: ((before.percent + after.percent) / 2).rounded()
            ),
            at: insertAt
        )
        draftPoints = sorted
        selectedPointIndex = insertAt
        commitDraft()
    }

    private func deletePoint() {
        guard draftPoints.count > 2, draftPoints.indices.contains(selectedPointIndex) else {
            return
        }
        draftPoints.remove(at: selectedPointIndex)
        selectedPointIndex = min(selectedPointIndex, draftPoints.count - 1)
        commitDraft()
    }

    private func updatePoint(_ index: Int, temperature: Double, percent: Double) {
        guard draftPoints.indices.contains(index) else { return }
        let range = MonitorFanPresetCurve.editableTemperatureRange(
            index: index,
            points: draftPoints
        )
        draftPoints[index] = MonitorFanPresetPoint(
            temperature: min(range.upperBound, max(range.lowerBound, temperature.rounded())),
            percent: min(100, max(0, percent.rounded()))
        )
    }

    private func commitDraft() {
        let movedTemperature = draftPoints.indices.contains(selectedPointIndex)
            ? draftPoints[selectedPointIndex].temperature
            : nil
        let sorted = draftPoints.sorted { $0.temperature < $1.temperature }
        draftPoints = sorted
        if let movedTemperature,
           let index = sorted.firstIndex(where: { $0.temperature == movedTemperature }) {
            selectedPointIndex = index
        }
        onCommit(sorted)
    }

    private func dragGesture(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard interactive, let plotFrame = proxy.plotFrame else { return }
                let frame = geometry[plotFrame]
                if draggingPointIndex == nil {
                    draggingPointIndex = nearestPointIndex(
                        location: value.location,
                        frame: frame,
                        proxy: proxy
                    )
                    if let draggingPointIndex {
                        selectedPointIndex = draggingPointIndex
                    }
                }
                guard let index = draggingPointIndex, draftPoints.indices.contains(index) else {
                    return
                }
                let x = value.location.x - frame.origin.x
                let y = value.location.y - frame.origin.y
                guard let temperature = proxy.value(atX: x, as: Double.self),
                      let percent = proxy.value(atY: y, as: Double.self)
                else { return }
                updatePoint(index, temperature: temperature, percent: percent)
            }
            .onEnded { _ in
                guard draggingPointIndex != nil else { return }
                draggingPointIndex = nil
                commitDraft()
            }
    }

    private func nearestPointIndex(
        location: CGPoint,
        frame: CGRect,
        proxy: ChartProxy
    ) -> Int? {
        let candidates = draftPoints.indices.compactMap { index -> (Int, CGPoint)? in
            guard let x = proxy.position(forX: draftPoints[index].temperature),
                  let y = proxy.position(forY: draftPoints[index].percent)
            else { return nil }
            return (index, CGPoint(x: frame.origin.x + x, y: frame.origin.y + y))
        }
        guard let nearest = candidates.min(by: {
            hypot($0.1.x - location.x, $0.1.y - location.y)
                < hypot($1.1.x - location.x, $1.1.y - location.y)
        }), hypot(nearest.1.x - location.x, nearest.1.y - location.y) <= 28 else {
            return nil
        }
        return nearest.0
    }
}

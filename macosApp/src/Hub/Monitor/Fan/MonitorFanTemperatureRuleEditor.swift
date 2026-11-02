import SwiftUI

/// CPU、GPU 和电池来源的温度控制点编辑器。
///
/// 每个来源保存独立的温度到百分比曲线。底部摘要调用与 helper 相同的
/// `mergedTargetPercent`，只显示来源合并后的每台风扇请求。
struct MonitorFanTemperatureRuleEditor: View {
    let reading: MonitorFanReading
    let configuration: MonitorFanConfiguration
    let helperSourceTemperatures: [String: Double]
    let language: AppLanguage
    let busy: Bool
    let onToggleSource: (MonitorFanTemperatureSource, Bool) -> Void
    let onChangePoints: (
        MonitorFanTemperatureSource,
        [MonitorFanTemperatureRulePoint],
        Bool
    ) -> Void

    @State private var draftRules: MonitorFanTemperatureRuleDraft
    @State private var editingSource: MonitorFanTemperatureSource?

    init(
        reading: MonitorFanReading,
        configuration: MonitorFanConfiguration,
        helperSourceTemperatures: [String: Double],
        language: AppLanguage,
        busy: Bool,
        onToggleSource: @escaping (MonitorFanTemperatureSource, Bool) -> Void,
        onChangePoints: @escaping (
            MonitorFanTemperatureSource,
            [MonitorFanTemperatureRulePoint],
            Bool
        ) -> Void
    ) {
        self.reading = reading
        self.configuration = configuration
        self.helperSourceTemperatures = helperSourceTemperatures
        self.language = language
        self.busy = busy
        self.onToggleSource = onToggleSource
        self.onChangePoints = onChangePoints
        _draftRules = State(initialValue: MonitorFanTemperatureRuleDraft(configuration: configuration))
    }

    private var sourceTemperatures: [MonitorFanTemperatureSource: Double] {
        var values = configuration.temperatureSourceReadings(in: reading)
        for source in MonitorFanTemperatureSource.allCases where values[source] == nil {
            values[source] = helperSourceTemperatures[source.rawValue]
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ContractCopy.copyMonitorFanTemperatureSources.text(for: language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                Spacer(minLength: 0)
                Text(ContractCopy.copyMonitorFanSourceHint.text(for: language))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
            }

            ForEach(MonitorFanTemperatureSource.allCases, id: \.self) { source in
                sourceEditor(source)
            }

            if !configuration.enabledTemperatureSources.isEmpty {
                mergedTargetSummary
            }
        }
        .onChange(of: configuration) { _, configuration in
            draftRules.sync(from: configuration, preserving: editingSource)
        }
    }

    private func sourceEditor(_ source: MonitorFanTemperatureSource) -> some View {
        let enabled = configuration.hasTemperatureRules(for: source)
        return VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: Binding(
                get: { enabled },
                set: { onToggleSource(source, $0) }
            )) {
                HStack(spacing: 6) {
                    Text(sourceTitle(source))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MacTheme.textPrimary)
                    Spacer(minLength: 0)
                    Text(sourceTemperatureText(source))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(
                            sourceTemperatures[source] == nil
                                ? MacTheme.textSecondary
                                : MacTheme.accent
                        )
                        .monospacedDigit()
                    if !sourceRequestText(source).isEmpty {
                        Text(sourceRequestText(source))
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(MacTheme.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(busy)
            .accessibilityLabel(sourceTitle(source))
            .accessibilityValue(sourceAccessibilityValue(source))

            if enabled {
                let points = configuredPoints(for: source)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(points.indices, id: \.self) { index in
                        pointEditor(source: source, index: index, points: points)
                    }
                }

                HStack(spacing: 6) {
                    Button {
                        addPoint(source: source, points: points)
                    } label: {
                        Label(
                            ContractCopy.copyMonitorFanAddTemperaturePoint.text(for: language),
                            systemImage: "plus"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(
                        busy
                            || points.count >= MonitorFanPolicy.maximumRulePointCount
                            || !canAddPoint(to: points)
                    )

                    Spacer(minLength: 0)
                    Text(String(format: "%d / %d", points.count, MonitorFanPolicy.maximumRulePointCount))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(8)
        .background(
            MacTheme.material.opacity(0.62),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(MacTheme.divider.opacity(0.45), lineWidth: 0.75)
        )
    }

    private func pointEditor(
        source: MonitorFanTemperatureSource,
        index: Int,
        points: [MonitorFanTemperatureRulePoint]
    ) -> some View {
        let point = points[index]
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text("#\(index + 1)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(MacTheme.textSecondary)
                    .frame(width: 20, alignment: .leading)

                TextField(
                    "",
                    value: temperatureBinding(source: source, index: index),
                    format: .number.precision(.fractionLength(0))
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .accessibilityLabel(ContractCopy.copyMonitorFanTemperature.text(for: language))
                .accessibilityValue("\(Int(point.celsius.rounded())) °C")

                Text("°C")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)

                Text("→")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)

                TextField(
                    "",
                    value: percentTextBinding(source: source, index: index),
                    format: .number.precision(.fractionLength(0))
                )
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .accessibilityLabel(ContractCopy.copyMonitorFanSourceFanPercentLabel.text(for: language))
                .accessibilityValue("\(Int(point.fanPercent.rounded()))%")

                Text("%")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)

                Spacer(minLength: 0)

                Button {
                    deletePoint(source: source, index: index, points: points)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    points.count > 2 && !busy ? MacTheme.errorText : MacTheme.disabledText
                )
                .frame(width: 24, height: 24)
                .disabled(busy || points.count <= 2)
                .accessibilityLabel(ContractCopy.copyMonitorFanDeletePoint.text(for: language))
            }

            percentSliderRow(
                value: percentBinding(source: source, index: index),
                fans: reading.units,
                accessibilityLabel: "\(sourceTitle(source)) \(controlPointTitle(index)) \(ContractCopy.copyMonitorFanSourceFanPercentLabel.text(for: language))",
                accessibilityValue: pointAccessibilityValue(point),
                onEditingChanged: { editing in
                    editingSource = editing ? source : nil
                    if !editing { commit(source) }
                }
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            MacTheme.surface.opacity(0.36),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private func percentSliderRow(
        value: Binding<Double>,
        fans: [MonitorFanReading.Unit],
        accessibilityLabel: String,
        accessibilityValue: String,
        onEditingChanged: @escaping (Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Slider(
                value: value,
                in: 0...100,
                step: MonitorFanPolicy.rulePercentStep,
                onEditingChanged: onEditingChanged
            )
            .disabled(busy)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)

            VStack(spacing: 2) {
                ForEach(fans) { fan in
                    fanRpmRow(fan: fan, percent: value.wrappedValue)
                }
            }
        }
    }

    private func fanRpmRow(fan: MonitorFanReading.Unit, percent: Double) -> some View {
        let summary = MonitorFanRpmScale.summary(for: fan, percent: percent)
        return HStack(spacing: 6) {
            Text("F\(fan.index + 1)")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.textSecondary)
                .frame(width: 16, alignment: .leading)

            rpmEndpointChip(summary.minimumRPM)

            Spacer(minLength: 4)

            Text(MonitorFanFormat.rpm(summary.targetRPM))
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(MacTheme.accent)
                .monospacedDigit()

            Spacer(minLength: 4)

            rpmEndpointChip(summary.maximumRPM)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ContractCopy.copyMonitorFanUnit.text(for: language)) \(fan.index + 1)")
        .accessibilityValue(
            "\(Int(summary.minimumRPM.rounded())) RPM，目标 \(Int(summary.targetRPM.rounded())) RPM，最高 \(Int(summary.maximumRPM.rounded())) RPM"
        )
    }

    private func rpmEndpointChip(_ rpm: Double) -> some View {
        Text("\(Int(rpm.rounded()))")
            .font(.system(size: 7, weight: .medium, design: .rounded))
            .foregroundStyle(MacTheme.textSecondary)
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(MacTheme.surface.opacity(0.34))
            )
            .overlay(
                Capsule().strokeBorder(MacTheme.divider.opacity(0.55), lineWidth: 0.5)
            )
    }

    private func fixedValueRow(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(MacTheme.textSecondary)
                .frame(width: 58, alignment: .leading)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(MacTheme.textSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private var mergedTargetSummary: some View {
        let temperatures = sourceTemperatures
        let percent = mergedTargetPercent(sourceTemperatures: temperatures)
        return VStack(alignment: .leading, spacing: 5) {
            Divider()
            Text(ContractCopy.copyMonitorFanTarget.text(for: language))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MacTheme.textSecondary)
            ForEach(reading.units) { fan in
                HStack(spacing: 6) {
                    Image(systemName: "fanblades.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(MonitorCardKind.fan.accent)
                    Text(String(
                        format: ContractCopy.copyMonitorFanUnit.text(for: language),
                        fan.index + 1
                    ))
                    .font(.system(size: 9, weight: .medium))
                    Spacer(minLength: 0)
                    if let percent {
                        Text(String(
                            format: ContractCopy.copyMonitorFanSourceFanPercent.text(for: language),
                            Int(percent.rounded())
                        ))
                        .foregroundStyle(MacTheme.textPrimary)
                        Text(MonitorFanFormat.rpm(MonitorFanPercent.rpm(
                            percent: percent,
                            minimumRPM: fan.minimumRPM,
                            maximumRPM: fan.maximumRPM
                        )))
                        .foregroundStyle(MacTheme.textSecondary)
                    } else {
                        Text(ContractCopy.copyMonitorFanSourceUnavailable.text(for: language))
                            .foregroundStyle(MacTheme.textSecondary)
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
            }
        }
    }

    private func sourceTitle(_ source: MonitorFanTemperatureSource) -> String {
        switch source {
        case .cpu:
            ContractCopy.copyMonitorFanSourceCpu.text(for: language)
        case .gpu:
            ContractCopy.copyMonitorFanSourceGpu.text(for: language)
        case .battery:
            ContractCopy.copyMonitorFanSourceBattery.text(for: language)
        }
    }

    private func sourceTemperatureText(_ source: MonitorFanTemperatureSource) -> String {
        guard let temperature = sourceTemperatures[source] else {
            return ContractCopy.copyMonitorFanSourceUnavailable.text(for: language)
        }
        return MonitorFanFormat.temperature(temperature)
    }

    private func pointAccessibilityValue(_ point: MonitorFanTemperatureRulePoint) -> String {
        let percent = "\(Int(point.fanPercent.rounded()))%"
        let targets = reading.units.map { fan in
            let rpm = MonitorFanPercent.rpm(
                percent: point.fanPercent,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM
            )
            return "\(ContractCopy.copyMonitorFanUnit.text(for: language)) \(Int(rpm.rounded())) RPM"
        }
        return ([percent] + targets).joined(separator: "，")
    }

    private func sourceRequestText(_ source: MonitorFanTemperatureSource) -> String {
        guard configuration.hasTemperatureRules(for: source) else { return "" }
        guard let temperature = sourceTemperatures[source],
              let percent = targetPercent(for: source, temperature: temperature)
        else { return "" }
        return String(
            format: ContractCopy.copyMonitorFanSourceRequest.text(for: language),
            Int(percent.rounded())
        )
    }

    private func sourceAccessibilityValue(_ source: MonitorFanTemperatureSource) -> String {
        let temperature = sourceTemperatureText(source)
        let request = sourceRequestText(source)
        return request.isEmpty ? temperature : "\(temperature)，\(request)"
    }

    private func controlPointTitle(_ index: Int) -> String {
        String(
            format: ContractCopy.copyMonitorFanControlPoint.text(for: language),
            index + 1
        )
    }

    private func configuredPoints(
        for source: MonitorFanTemperatureSource
    ) -> [MonitorFanTemperatureRulePoint] {
        draftRules.points(for: source)
    }

    private func temperatureBinding(
        source: MonitorFanTemperatureSource,
        index: Int
    ) -> Binding<Double> {
        Binding(
            get: {
                let points = draftRules.points(for: source)
                guard points.indices.contains(index) else { return MonitorFanPolicy.minimumRuleCelsius }
                return points[index].celsius
            },
            set: { value in
                draftRules.updatePoint(
                    source: source,
                    index: index,
                    celsius: value,
                    percent: nil
                )
                commit(source)
            }
        )
    }

    private func percentBinding(
        source: MonitorFanTemperatureSource,
        index: Int
    ) -> Binding<Double> {
        Binding(
            get: {
                let points = draftRules.points(for: source)
                guard points.indices.contains(index) else { return 0 }
                return points[index].fanPercent
            },
            set: { value in
                editingSource = source
                draftRules.updatePoint(
                    source: source,
                    index: index,
                    celsius: nil,
                    percent: value
                )
            }
        )
    }

    private func percentTextBinding(
        source: MonitorFanTemperatureSource,
        index: Int
    ) -> Binding<Double> {
        Binding(
            get: {
                let points = draftRules.points(for: source)
                guard points.indices.contains(index) else { return 0 }
                return points[index].fanPercent
            },
            set: { value in
                draftRules.updatePoint(
                    source: source,
                    index: index,
                    celsius: nil,
                    percent: value
                )
                commit(source)
            }
        )
    }

    private func targetPercent(
        for source: MonitorFanTemperatureSource,
        temperature: Double
    ) -> Double? {
        let points = draftRules.points(for: source)
        guard points.count >= 2 else { return nil }
        return MonitorFanTemperatureRule.targetPercent(points: points, temperature: temperature)
    }

    private func mergedTargetPercent(
        sourceTemperatures: [MonitorFanTemperatureSource: Double]
    ) -> Double? {
        let requests: [Double] = configuration.enabledTemperatureSources.compactMap { source in
            guard let temperature = sourceTemperatures[source] else { return nil }
            return targetPercent(for: source, temperature: temperature)
        }
        return requests.max()
    }

    private func commit(_ source: MonitorFanTemperatureSource) {
        editingSource = nil
        onChangePoints(source, draftRules.points(for: source), true)
    }

    private func addPoint(
        source: MonitorFanTemperatureSource,
        points: [MonitorFanTemperatureRulePoint]
    ) {
        guard points.count < MonitorFanPolicy.maximumRulePointCount else { return }
        var sorted = points.sorted { $0.celsius < $1.celsius }
        guard sorted.count >= 2 else { return }
        if let last = sorted.last,
           last.celsius + MonitorFanPolicy.minimumRuleTemperatureSpan
            <= MonitorFanPolicy.maximumRuleCelsius {
            sorted.append(MonitorFanTemperatureRulePoint(
                celsius: last.celsius + MonitorFanPolicy.minimumRuleTemperatureSpan,
                fanPercent: last.fanPercent
            ))
            draftRules.setPoints(sorted, for: source)
            commit(source)
            return
        }
        if let first = sorted.first,
           first.celsius - MonitorFanPolicy.minimumRuleTemperatureSpan
            >= MonitorFanPolicy.minimumRuleCelsius {
            sorted.insert(MonitorFanTemperatureRulePoint(
                celsius: first.celsius - MonitorFanPolicy.minimumRuleTemperatureSpan,
                fanPercent: first.fanPercent
            ), at: 0)
            draftRules.setPoints(sorted, for: source)
            commit(source)
            return
        }
        var insertAt = 1
        var gap = -Double.infinity
        for index in 1..<sorted.count {
            let candidate = sorted[index].celsius - sorted[index - 1].celsius
            if candidate > gap {
                gap = candidate
                insertAt = index
            }
        }
        guard gap >= MonitorFanPolicy.minimumRuleTemperatureSpan * 2 else { return }
        let before = sorted[insertAt - 1]
        let after = sorted[insertAt]
        sorted.insert(
            MonitorFanTemperatureRulePoint(
                celsius: ((before.celsius + after.celsius) / 2).rounded(),
                fanPercent: MonitorFanTemperatureRule.snappedPercent(
                    (before.fanPercent + after.fanPercent) / 2
                )
            ),
            at: insertAt
        )
        draftRules.setPoints(sorted, for: source)
        commit(source)
    }

    private func deletePoint(
        source: MonitorFanTemperatureSource,
        index: Int,
        points: [MonitorFanTemperatureRulePoint]
    ) {
        guard points.count > 2, points.indices.contains(index) else { return }
        var updated = points
        updated.remove(at: index)
        draftRules.setPoints(updated, for: source)
        commit(source)
    }

    private func largestGap(in points: [MonitorFanTemperatureRulePoint]) -> Double {
        let sorted = points.sorted { $0.celsius < $1.celsius }
        guard sorted.count >= 2 else { return 0 }
        return zip(sorted, sorted.dropFirst()).map { right, next in
            next.celsius - right.celsius
        }.max() ?? 0
    }

    private func canAddPoint(to points: [MonitorFanTemperatureRulePoint]) -> Bool {
        guard points.count < MonitorFanPolicy.maximumRulePointCount,
              let first = points.min(by: { $0.celsius < $1.celsius }),
              let last = points.max(by: { $0.celsius < $1.celsius })
        else { return false }
        return last.celsius + MonitorFanPolicy.minimumRuleTemperatureSpan
                <= MonitorFanPolicy.maximumRuleCelsius
            || first.celsius - MonitorFanPolicy.minimumRuleTemperatureSpan
                >= MonitorFanPolicy.minimumRuleCelsius
            || largestGap(in: points) >= MonitorFanPolicy.minimumRuleTemperatureSpan * 2
    }
}

import Foundation

protocol FanControlTemperatureReading {
    func read(sensorKeys: Set<String>?) -> SMCFanReadingSnapshot
}

protocol FanControlFanWriting: AnyObject {
    var holdingCount: Int { get }

    func isHolding(_ index: Int) -> Bool
    func hold(_ index: Int) throws
    func ensureHeld(_ index: Int) throws
    func writeTarget(_ index: Int, rpm: Double) throws
    func release(_ index: Int) throws
    func releaseAll() throws
}

extension SMCFanReader: FanControlTemperatureReading {}
extension StatsFanControl: FanControlFanWriting {}

struct FanControlHardware {
    let reader: any FanControlTemperatureReading
    let writer: any FanControlFanWriting
}

/// The root helper owns the curve timer. The app only renews a short lease.
/// If Covio exits or crashes, the helper restores system control automatically.
final class FanControlRuntime: @unchecked Sendable {
    private enum State: String {
        case system
        case applying
        case controlled
        case error
    }

    private let queue = DispatchQueue(label: "com.wyz.covio.fan-control")
    private let log: HelperLog?
    private let now: () -> Date
    private let schedulesTimer: Bool
    private let hardwareFactory: () throws -> FanControlHardware
    private var reader: (any FanControlTemperatureReading)?
    private var writer: (any FanControlFanWriting)?
    private var configuration: MonitorFanConfiguration?
    private var timer: DispatchSourceTimer?
    private var state: State = .system
    private var leaseDeadline = Date.distantPast
    private var heldTemperature: Double?
    private var heldSourceTemperatures: [MonitorFanTemperatureSource: Double] = [:]
    private var lastTargets: [Int: Double] = [:]
    private var consecutiveFailures = 0
    private var lastError: String?
    private var controlTemperature: Double?
    private var sourceTemperatures: [MonitorFanTemperatureSource: Double] = [:]

    init(
        log: HelperLog? = nil,
        now: @escaping () -> Date = Date.init,
        schedulesTimer: Bool = true,
        hardwareFactory: (() throws -> FanControlHardware)? = nil
    ) {
        self.log = log
        self.now = now
        self.schedulesTimer = schedulesTimer
        self.hardwareFactory = hardwareFactory ?? Self.defaultHardware
    }

    func handle(_ request: HelperRequest) -> HelperReply? {
        guard HelperWire.shared.isFanControlCommand(command: request.command) else {
            return nil
        }
        return queue.sync {
            switch request.command {
            case HelperWire.shared.COMMAND_FAN_CONTROL_STATUS:
                return statusReply(requestId: request.requestId)
            case HelperWire.shared.COMMAND_FAN_CONTROL_KEEP_ALIVE:
                return keepAlive(requestId: request.requestId)
            case HelperWire.shared.COMMAND_FAN_CONTROL_CONFIGURE:
                return configure(request)
            case HelperWire.shared.COMMAND_FAN_CONTROL_RESTORE:
                return restore(requestId: request.requestId, error: nil)
            default:
                return HelperWire.shared.failure(
                    requestId: request.requestId,
                    message: "Command is not allowed"
                )
            }
        }
    }

    func shutdown() {
        queue.sync {
            _ = restore(requestId: "shutdown", error: nil)
        }
    }

    func prepareForInstallTransaction(requestId: String) -> HelperReply {
        queue.sync {
            restore(requestId: requestId, error: nil)
        }
    }

    /// Drives one control cycle. The timer uses the same path; tests disable the timer and call it directly.
    func driveControlCycle() {
        queue.sync {
            applyControl()
        }
    }

    private func configure(_ request: HelperRequest) -> HelperReply {
        guard let parsed = parseConfiguration(request.payload) else {
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: "Invalid fan configuration"
            )
        }
        if parsed.mode.isAutomatic {
            return restore(requestId: request.requestId, error: nil)
        }

        let hardware: FanControlHardware
        do {
            hardware = try hardwareOrThrow()
        } catch {
            lastError = String(describing: error)
            state = .error
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: lastError ?? "Fan control is unavailable"
            )
        }

        let fanSnapshot = hardware.reader.read(sensorKeys: nil)
        guard !fanSnapshot.fans.isEmpty else {
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: "This Mac has no controllable fans"
            )
        }

        let minimums = Dictionary(uniqueKeysWithValues: fanSnapshot.fans.map {
            ($0.index, $0.minimumRPM)
        })
        let maximums = Dictionary(uniqueKeysWithValues: fanSnapshot.fans.map {
            ($0.index, $0.maximumRPM)
        })
        var normalized = parsed.normalized(fanMinimums: minimums, fanMaximums: maximums)
        if normalized.selectedSensorKeys.isEmpty {
            normalized.selectedSensorKeys = SMCFanReader.controlSensorKeys(
                for: fanSnapshot.temperatures,
                allKeys: fanSnapshot.temperatures.map(\.key)
            )
        }
        let controlledFans = fanSnapshot.fans.filter {
            normalized.controlMode(for: $0.index) != .automatic
        }

        if writer?.holdingCount ?? 0 > 0 {
            do {
                try writer?.releaseAll()
            } catch {
                state = .error
                lastError = String(describing: error)
                return HelperWire.shared.failure(
                    requestId: request.requestId,
                    message: lastError ?? "Fan control could not be released"
                )
            }
        }
        stopTimer()
        configuration = normalized
        state = .applying
        leaseDeadline = now().addingTimeInterval(MonitorFanPolicy.leaseSeconds)
        heldTemperature = nil
        heldSourceTemperatures.removeAll(keepingCapacity: true)
        controlTemperature = nil
        sourceTemperatures.removeAll(keepingCapacity: true)
        lastTargets.removeAll(keepingCapacity: true)
        consecutiveFailures = 0
        lastError = nil

        do {
            for fan in controlledFans {
                try hardware.writer.hold(fan.index)
            }
        } catch {
            try? hardware.writer.releaseAll()
            configuration = nil
            state = .error
            lastError = String(describing: error)
            log?.error("Fan control could not take ownership", error)
            return HelperWire.shared.failure(
                requestId: request.requestId,
                message: lastError ?? "Fan control could not take ownership"
            )
        }

        writer = hardware.writer
        guard !controlledFans.isEmpty else {
            state = .system
            leaseDeadline = .distantPast
            return statusReply(requestId: request.requestId)
        }
        state = .controlled
        startTimer()
        applyControl()
        return statusReply(requestId: request.requestId)
    }

    private func keepAlive(requestId: String) -> HelperReply {
        guard state == .controlled || state == .applying else {
            return statusReply(requestId: requestId)
        }
        leaseDeadline = now().addingTimeInterval(MonitorFanPolicy.leaseSeconds)
        return statusReply(requestId: requestId)
    }

    private func restore(requestId: String, error: String?) -> HelperReply {
        stopTimer()
        var restoreError = error
        do {
            try writer?.releaseAll()
        } catch {
            restoreError = String(describing: error)
            log?.error("Fan control could not be restored", error)
        }
        configuration = nil
        state = restoreError == nil ? .system : .error
        leaseDeadline = .distantPast
        heldTemperature = nil
        heldSourceTemperatures.removeAll(keepingCapacity: true)
        controlTemperature = nil
        sourceTemperatures.removeAll(keepingCapacity: true)
        lastTargets.removeAll(keepingCapacity: true)
        consecutiveFailures = 0
        lastError = restoreError
        return statusReply(requestId: requestId)
    }

    private func startTimer() {
        guard schedulesTimer else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + .milliseconds(100),
            repeating: .milliseconds(Int(MonitorFanPolicy.controlIntervalSeconds * 1_000))
        )
        source.setEventHandler { [weak self] in
            self?.applyControl()
        }
        source.resume()
        timer = source
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func applyControl() {
        guard state == .controlled, let configuration else { return }
        if now() >= leaseDeadline {
            _ = restore(requestId: "lease-expired", error: nil)
            log?.info("Fan control lease expired; restored system control")
            return
        }
        guard let reader, let writer else { return }

        let usesTemperatureRules = configuration.mode == .curve
            && !configuration.temperatureRules.isEmpty
        let selected = Set(configuration.selectedSensorKeys)
        let sensorKeys = usesTemperatureRules ? nil : (selected.isEmpty ? nil : selected)
        let snapshot = reader.read(sensorKeys: sensorKeys)
        guard !snapshot.fans.isEmpty else {
            registerFailure("Fan readings are unavailable")
            return
        }

        var stableTemperature: Double?
        var fanRequests: [Int: [Double]] = [:]
        if configuration.mode == .curve {
            if usesTemperatureRules {
                let readings = SMCFanReader.temperatureSourceReadings(
                    for: snapshot.temperatures
                )
                var stableBySource: [MonitorFanTemperatureSource: Double] = [:]
                for source in MonitorFanTemperatureSource.allCases
                    where configuration.hasTemperatureRules(for: source) {
                    guard let current = readings[source] else { continue }
                    let stable = MonitorFanCurve.heldTemperature(
                        current: current,
                        previous: heldSourceTemperatures[source]
                    )
                    heldSourceTemperatures[source] = stable
                    stableBySource[source] = stable
                    guard let percent = configuration.targetPercent(
                        for: source,
                        temperature: stable
                    ) else { continue }
                    for fan in snapshot.fans {
                        let rpm = MonitorFanPercent.rpm(
                            percent: percent,
                            minimumRPM: fan.minimumRPM,
                            maximumRPM: fan.maximumRPM
                        )
                        fanRequests[fan.index, default: []].append(rpm)
                    }
                }
                guard !fanRequests.isEmpty else {
                    registerFailure("Control temperature is unavailable")
                    return
                }
                sourceTemperatures = stableBySource
                controlTemperature = stableBySource.values.max()
            } else {
                guard let currentTemperature = snapshot.temperatures.map(\.celsius).max() else {
                    registerFailure("Control temperature is unavailable")
                    return
                }
                stableTemperature = MonitorFanCurve.heldTemperature(
                    current: currentTemperature,
                    previous: heldTemperature
                )
                heldTemperature = stableTemperature
                controlTemperature = stableTemperature
                sourceTemperatures.removeAll(keepingCapacity: true)
            }
        }

        do {
            for fan in snapshot.fans {
                if configuration.controlMode(for: fan.index) == .automatic {
                    if writer.isHolding(fan.index) {
                        try writer.release(fan.index)
                    }
                    lastTargets.removeValue(forKey: fan.index)
                    continue
                }
                try writer.ensureHeld(fan.index)
                let target: Double
                if configuration.mode == .manual {
                    target = configuration.manualRPM[String(fan.index)] ?? fan.minimumRPM
                } else if !fanRequests.isEmpty {
                    target = fanRequests[fan.index]?.max() ?? fan.minimumRPM
                } else {
                    target = configuration.target(
                        fanIndex: fan.index,
                        temperature: stableTemperature ?? 0,
                        minimumRPM: fan.minimumRPM,
                        maximumRPM: fan.maximumRPM
                    )
                }
                let safeTarget = min(fan.maximumRPM, max(fan.minimumRPM, target))
                let requestedTarget = lastTargets[fan.index]
                let targetDrift = abs(fan.targetRPM - safeTarget) > 25
                if requestedTarget == nil ||
                    abs((requestedTarget ?? 0) - safeTarget) >= 1 ||
                    targetDrift {
                    try writer.writeTarget(fan.index, rpm: safeTarget)
                    lastTargets[fan.index] = safeTarget
                }
            }
            if writer.holdingCount == 0 {
                stopTimer()
                state = .system
                leaseDeadline = .distantPast
                heldTemperature = nil
                heldSourceTemperatures.removeAll(keepingCapacity: true)
                controlTemperature = nil
                sourceTemperatures.removeAll(keepingCapacity: true)
            }
            consecutiveFailures = 0
            lastError = nil
        } catch {
            registerFailure(String(describing: error))
        }
    }

    private func registerFailure(_ message: String) {
        consecutiveFailures += 1
        lastError = message
        log?.error("Fan control write failed: \(message)")
        if consecutiveFailures >= MonitorFanPolicy.maximumConsecutiveWriteFailures {
            _ = restore(requestId: "write-failed", error: message)
        }
    }

    private func hardwareOrThrow() throws -> FanControlHardware {
        if let reader, let writer {
            return FanControlHardware(reader: reader, writer: writer)
        }
        let hardware = try hardwareFactory()
        reader = hardware.reader
        writer = hardware.writer
        return hardware
    }

    private static func defaultHardware() throws -> FanControlHardware {
        let access = try SMCAccess()
        let keys = access.allKeys()
        let newReader = SMCFanReader(access: access, allKeys: keys)
        let newWriter = StatsFanControl(access: access, allKeys: keys)
        return FanControlHardware(reader: newReader, writer: newWriter)
    }

    private func parseConfiguration(_ payload: [String: String]) -> MonitorFanConfiguration? {
        guard payload["enabled"] == "true",
              let modeText = payload["mode"],
              let mode = switch modeText {
              case "auto": MonitorFanMode.automatic
              case "curve": MonitorFanMode.curve
              case "manual": MonitorFanMode.manual
              default: nil
              },
              let start = Double(payload["start"] ?? ""),
              let full = Double(payload["full"] ?? ""),
              start.isFinite,
              full.isFinite
        else { return nil }

        let sensors = (payload["sensors"] ?? "")
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
        var manualRPM: [String: Double] = [:]
        for pair in (payload["manualRPM"] ?? "").split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let fanIndex = Int(parts[0]),
                  let rpm = Double(parts[1]),
                  rpm.isFinite
            else { continue }
            manualRPM[String(fanIndex)] = rpm
        }

        var curves: [String: [MonitorFanCurvePoint]] = [:]
        if let curveText = payload["curves"], !curveText.isEmpty {
            guard let data = curveText.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(
                      [String: [MonitorFanCurvePoint]].self,
                      from: data
                  )
            else {
                return nil
            }
            curves = decoded
        }

        var manualModes: [String: MonitorFanMode] = [:]
        if let modeText = payload["manualModes"], !modeText.isEmpty {
            guard let data = modeText.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(
                      [String: MonitorFanMode].self,
                      from: data
                  )
            else {
                return nil
            }
            manualModes = decoded
        }

        var temperatureRules: [String: [MonitorFanTemperatureRulePoint]] = [:]
        if let rulesText = payload["temperatureRules"], !rulesText.isEmpty {
            guard let data = rulesText.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(
                      [String: [MonitorFanTemperatureRulePoint]].self,
                      from: data
                  )
            else {
                return nil
            }
            temperatureRules = decoded
        }

        return MonitorFanConfiguration(
            enabled: true,
            mode: mode,
            startCelsius: start,
            fullCelsius: full,
            selectedSensorKeys: sensors,
            manualRPM: manualRPM,
            manualModes: manualModes,
            curves: curves,
            temperatureRules: temperatureRules
        )
    }

    private func statusReply(requestId: String) -> HelperReply {
        var result = [
            "state": state.rawValue,
            "active": state == .controlled ? "true" : "false",
            "mode": configuration?.mode.rawValue ?? "system",
            "leaseRemainingSeconds": String(
                max(0, Int(leaseDeadline.timeIntervalSince(now()).rounded(.up)))
            ),
        ]
        if let controlTemperature {
            result["controlTemperature"] = String(format: "%.2f", controlTemperature)
        }
        if !sourceTemperatures.isEmpty {
            let values = Dictionary(uniqueKeysWithValues: sourceTemperatures.map {
                ($0.key.rawValue, $0.value)
            })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(values),
               let text = String(data: data, encoding: .utf8) {
                result["sourceTemperatures"] = text
            }
        }
        if let lastError {
            result["error"] = lastError
        }
        return HelperWire.shared.success(requestId: requestId, result: result)
    }
}

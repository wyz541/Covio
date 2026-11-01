#if DEBUG
import AppKit
import CoreGraphics
import ScreenCaptureKit
import SwiftUI
import kmpDomain

/// 调试构建的独立监控窗口。
///
/// 全量运行时会在系统唤醒回调里执行已有逻辑。这个入口绕过运行时，
/// 只用来检查 `MonitorTabView` 的真实布局和读数。
struct MonitorPreviewRoot: View {
    private let language: AppLanguage
    let snapshot: MonitorSnapshot
    let history: MonitorHistory
    let powerHistory: MonitorPowerHistory
    let runsSampling: Bool
    let powerModel: (any PowerManagementModel)?
    let powerPopoverInitiallyPresented: Bool
    let powerPopoverInitialTab: MonitorPowerDetailTab
    let displayPopoverInitiallyPresented: Bool
    let width: CGFloat?
    let height: CGFloat?

    init(
        snapshot: MonitorSnapshot = .empty,
        history: MonitorHistory = MonitorHistory(),
        powerHistory: MonitorPowerHistory = MonitorPowerHistory(),
        runsSampling: Bool = true,
        powerModel: (any PowerManagementModel)? = nil,
        powerPopoverInitiallyPresented: Bool = false,
        powerPopoverInitialTab: MonitorPowerDetailTab = .details,
        displayPopoverInitiallyPresented: Bool = false,
        language: AppLanguage = .simplifiedChinese,
        width: CGFloat? = nil,
        height: CGFloat? = nil
    ) {
        self.language = language
        self.snapshot = snapshot
        self.history = history
        self.powerHistory = powerHistory
        self.runsSampling = runsSampling
        self.powerModel = powerModel
        self.powerPopoverInitiallyPresented = powerPopoverInitiallyPresented
        self.powerPopoverInitialTab = powerPopoverInitialTab
        self.displayPopoverInitiallyPresented = displayPopoverInitiallyPresented
        self.width = width
        self.height = height
    }

    var body: some View {
        let totalWidth = width ?? HubMetrics.panelWidth
        let totalHeight = height ?? HubMetrics.monitorBodyHeight + HubMetrics.panelPadding * 2
        let bodyHeight = max(HubMetrics.monitorBodyHeight, totalHeight - HubMetrics.panelPadding * 2)
        MonitorTabView(
            language: language,
            powerModel: powerModel,
            initialSnapshot: snapshot,
            initialHistory: history,
            initialPowerHistory: powerHistory,
            runsSampling: runsSampling,
            powerPopoverInitiallyPresented: powerPopoverInitiallyPresented,
            powerPopoverInitialTab: powerPopoverInitialTab,
            displayPopoverInitiallyPresented: displayPopoverInitiallyPresented
        )
        .frame(height: bodyHeight)
        .padding(HubMetrics.panelPadding)
        .frame(width: totalWidth, height: totalHeight, alignment: .topLeading)
        .background(MacTheme.canvas)
    }
}

/// 电源管理面的固定样本。只用于调试预览，不执行系统动作。
@MainActor
@Observable
final class PowerPreviewModel: PowerManagementModel {
    let language: AppLanguage
    var sleepProtectionEnabled = true
    var powerConfig: PowerConfig
    var displayConfig: DisplayConfig
    var closedLidPowerPolicy: ClosedLidPowerPolicy
    var observation: PowerObservation
    var snapshot: PowerSnapshot
    var decision: PowerDecision
    var helperStatus: HelperStatus = .match
    var helperServiceState: HelperServiceState = .enabled
    var executionError: String?
    var closedLidZeroBrightnessPhase: ClosedLidZeroBrightnessPhase = .ready
    var closedLidZeroBrightnessAvailability: ClosedLidBrightnessAvailability = .available
    var closedLidZeroBrightnessError: String?
    var hasManualSession = false
    var sessionMode: PowerRuntime.SessionMode?
    var remainingSeconds: Int64?
    var recentHistory: [PowerHistoryEvent] = []
    var appState: AppState = AppRuntime.initialState(enabled: true)
    var statusMessage: String?
    var busy = false

    init() {
        language = AppLanguage(
            rawValue: ProcessInfo.processInfo.environment["COVIO_POWER_PREVIEW_LANGUAGE"] ?? ""
        ) ?? .simplifiedChinese
        let previewPower = PowerConfig(
            enabled: true,
            keepAwakeOnAdapter: true,
            keepAwakeOnBattery: false,
            allowClosedLid: true,
            pauseClosedLidWithExternalDisplay: true,
            batteryFloorPercent: 15,
            batteryFloorRecoveryPercent: 20,
            yieldOnLowPowerMode: true,
            heatGuardEnabled: true,
            closedLidTimeCapMinutes: 240,
            closedLidZeroBrightness: true
        )
        powerConfig = previewPower
        let previewDisplay = DisplayConfig.companion.fromLegacy(
            power: previewPower,
            keepsAwakeOnAdapter: false,
            keepsAwakeOnBattery: false
        )
        displayConfig = previewDisplay
        closedLidPowerPolicy = previewDisplay.closedLidPowerPolicy
        let sampleObservation = PowerObservation(
            batteryPercent: KotlinInt(int: 84),
            hasBattery: KotlinBoolean(bool: true),
            powerState: .acPower,
            externalDisplayCount: KotlinInt(int: 0),
            lidState: .open,
            thermalState: .nominal,
            lowPowerModeEnabled: KotlinBoolean(bool: false)
        )
        observation = sampleObservation
        snapshot = PowerSnapshot(
            observation: sampleObservation,
            helperStatus: .match,
            sleepDisabled: KotlinBoolean(bool: false),
            covioOwnsSleepDisabled: KotlinBoolean(bool: false)
        )
        decision = PowerDecision(
            preventUserIdleSystemSleep: false,
            preventUserIdleDisplaySleep: false,
            preventLidSleep: false,
            appliedLeaseLevel: nil,
            activeLeaseIds: [],
            automaticRuleApplied: false,
            safetyVetoes: [],
            batteryGuardLatched: false
        )
        let now = Int64(Date().timeIntervalSince1970)
        recentHistory = [
            PowerHistoryEvent(
                id: "preview-adapter",
                kind: .adapterConnected,
                atEpochSeconds: now - 60,
                detail: ""
            ),
            PowerHistoryEvent(
                id: "preview-hold",
                kind: .holdStarted,
                atEpochSeconds: now - 180,
                detail: "lid"
            ),
            PowerHistoryEvent(
                id: "preview-wake",
                kind: .fullWake,
                atEpochSeconds: now - 600,
                detail: "UserActivity"
            ),
        ]
        if ProcessInfo.processInfo.environment["COVIO_POWER_PREVIEW_SESSION"] == "active" {
            _ = startSession(mode: .lid, duration: .oneHour)
            remainingSeconds = 2_700
        }
    }

    func setPowerEnabled(_ enabled: Bool) {
        sleepProtectionEnabled = enabled
        powerConfig = copyPower(enabled: enabled)
    }
    func setPowerKeepAwakeOnAdapter(_ enabled: Bool) { powerConfig = copyPower(adapter: enabled) }
    func setPowerKeepAwakeOnBattery(_ enabled: Bool) { powerConfig = copyPower(battery: enabled) }
    func setPowerYieldOnLowPowerMode(_ enabled: Bool) { powerConfig = copyPower(lowPower: enabled) }
    func setPowerHeatGuard(_ enabled: Bool) { powerConfig = copyPower(heat: enabled) }
    func setPowerBatteryFloor(_ percent: Int) { powerConfig = copyPower(floor: Int32(percent)) }
    func setPowerClosedLidTimeCapMinutes(_ minutes: Int) { powerConfig = copyPower(cap: Int32(minutes)) }
    func setClosedLidPowerPolicy(_ policy: ClosedLidPowerPolicy) {
        closedLidPowerPolicy = policy
        let mode: ClosedLidDisplayMode
        if !policy.keepsAwake {
            mode = displayConfig.closedLidDisplayMode
        } else if displayConfig.closedLidDisplayMode == .system {
            mode = .blackScreenPipeline
        } else {
            mode = displayConfig.closedLidDisplayMode
        }
        displayConfig = copyDisplay(policy: policy, mode: mode)
        powerConfig = copyPower(lid: policy.keepsAwake, zeroBrightness: mode == .blackScreenPipeline)
        closedLidZeroBrightnessPhase = mode == .blackScreenPipeline ? .ready : .disabled
        decision = PowerDecision(
            preventUserIdleSystemSleep: policy.keepsAwake,
            preventUserIdleDisplaySleep: false,
            preventLidSleep: policy.keepsAwake,
            appliedLeaseLevel: policy.keepsAwake ? .closedLid : nil,
            activeLeaseIds: policy.keepsAwake ? ["power/closed-lid/policy"] : [],
            automaticRuleApplied: false,
            safetyVetoes: [],
            batteryGuardLatched: false
        )
    }
    func setDisplayClosedLidMode(_ mode: ClosedLidDisplayMode) {
        if mode == .system {
            setClosedLidPowerPolicy(.sleep)
        } else {
            let policy = closedLidPowerPolicy == .sleep ? .adapter : closedLidPowerPolicy
            setClosedLidPowerPolicy(policy)
            displayConfig = copyDisplay(mode: mode)
            powerConfig = copyPower(zeroBrightness: mode == .blackScreenPipeline)
        }
    }
    func setDisplayPauseWithExternalDisplay(_ enabled: Bool) {
        displayConfig = copyDisplay(pauseWithExternal: enabled)
        powerConfig = copyPower(external: enabled)
    }

    func startSession(mode: PowerRuntime.SessionMode, duration: PowerRuntime.SessionDuration) -> Bool {
        hasManualSession = true
        sessionMode = mode
        remainingSeconds = duration.seconds
        let level: HoldLeaseLevel = switch mode {
        case .system: .system
        case .display: .systemAndDisplay
        case .lid: .closedLid
        }
        decision = PowerDecision(
            preventUserIdleSystemSleep: true,
            preventUserIdleDisplaySleep: level == .systemAndDisplay,
            preventLidSleep: level == .closedLid,
            appliedLeaseLevel: level,
            activeLeaseIds: ["power/session/preview"],
            automaticRuleApplied: false,
            safetyVetoes: [],
            batteryGuardLatched: false
        )
        return true
    }

    func endSession() {
        hasManualSession = false
        sessionMode = nil
        remainingSeconds = nil
        decision = PowerDecision(
            preventUserIdleSystemSleep: true,
            preventUserIdleDisplaySleep: false,
            preventLidSleep: false,
            appliedLeaseLevel: nil,
            activeLeaseIds: [],
            automaticRuleApplied: true,
            safetyVetoes: [],
            batteryGuardLatched: false
        )
    }

    func displaySleepNow() {}

    func openDisplaySettings() {}

    private func copyPower(
        enabled: Bool? = nil,
        adapter: Bool? = nil,
        battery: Bool? = nil,
        lid: Bool? = nil,
        external: Bool? = nil,
        lowPower: Bool? = nil,
        heat: Bool? = nil,
        floor: Int32? = nil,
        cap: Int32? = nil,
        zeroBrightness: Bool? = nil
    ) -> PowerConfig {
        PowerConfig(
            enabled: enabled ?? powerConfig.enabled,
            keepAwakeOnAdapter: adapter ?? powerConfig.keepAwakeOnAdapter,
            keepAwakeOnBattery: battery ?? powerConfig.keepAwakeOnBattery,
            allowClosedLid: lid ?? powerConfig.allowClosedLid,
            pauseClosedLidWithExternalDisplay: external ?? powerConfig.pauseClosedLidWithExternalDisplay,
            batteryFloorPercent: floor ?? powerConfig.batteryFloorPercent,
            batteryFloorRecoveryPercent: min((floor ?? powerConfig.batteryFloorPercent) + 5, 100),
            yieldOnLowPowerMode: lowPower ?? powerConfig.yieldOnLowPowerMode,
            heatGuardEnabled: heat ?? powerConfig.heatGuardEnabled,
            closedLidTimeCapMinutes: cap ?? powerConfig.closedLidTimeCapMinutes,
            closedLidZeroBrightness: zeroBrightness ?? powerConfig.closedLidZeroBrightness
        )
    }

    private func copyDisplay(
        policy: ClosedLidPowerPolicy? = nil,
        mode: ClosedLidDisplayMode? = nil,
        pauseWithExternal: Bool? = nil
    ) -> DisplayConfig {
        let nextPolicy = policy ?? displayConfig.closedLidPowerPolicy
        return DisplayConfig(
            schemaVersion: displayConfig.schemaVersion,
            keepAwakeWhenLidClosed: nextPolicy.keepsAwake,
            closedLidPowerPolicy: nextPolicy,
            closedLidDisplayMode: mode ?? displayConfig.closedLidDisplayMode,
            pauseWhenExternalDisplayConnected: pauseWithExternal
                ?? displayConfig.pauseWhenExternalDisplayConnected
        )
    }
}

@MainActor
enum MonitorSnapshotRenderer {
    static func render(to path: String) async -> Bool {
        let sampler = MonitorSampler()
        var history = MonitorHistory()
        var powerHistory = MonitorPowerHistory()
        var snapshot = MonitorSnapshot.empty
        // 能耗窗口要跨过第一次 10 秒基线，截图才会显示真实的 Top3。
        for index in 0..<26 {
            snapshot = await sampler.sample()
            history.append(snapshot)
            if let power = snapshot.power {
                powerHistory.append(power)
            }
            guard index < 25 else { continue }
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return false
            }
        }

        // ImageRenderer 不能合成 `.glassEffect`。截图时临时换成常规材质，
        // 布局与内容不变，只替代无法离屏渲染的玻璃层。
        let previousMode = GlassSurfaceMode.current
        GlassSurfaceMode.current = .material
        defer { GlassSurfaceMode.current = previousMode }

        let colorScheme: ColorScheme = ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
            .lowercased() == "dark" ? .dark : .light
        let renderer = ImageRenderer(
            content: MonitorPreviewRoot(
                snapshot: snapshot,
                history: history,
                powerHistory: powerHistory,
                runsSampling: false
            )
            .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

@MainActor
enum MonitorPowerDetailRenderer {
    static func render(to path: String) async -> Bool {
        let sampler = MonitorSampler()
        var powerHistory = MonitorPowerHistory()
        var power = MonitorSnapshot.Power.empty
        for index in 0..<26 {
            power = await sampler.samplePowerOnly()
            powerHistory.append(power)
            guard index < 25 else { continue }
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return false
            }
        }

        let colorScheme: ColorScheme = ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
            .lowercased() == "dark" ? .dark : .light
        let content = MonitorPowerDetailPanel(
            power: power,
            history: powerHistory,
            language: .simplifiedChinese,
            reduceMotion: false,
            runtime: nil,
            powerModel: nil,
            onOpenApp: { _ in },
            onClose: {}
        )
        .environment(\.colorScheme, colorScheme)
        .padding(24)
        .background(MacTheme.canvas)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

@MainActor
struct PowerPopoverPreviewRoot: View {
    let powerModel: any PowerManagementModel
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            MacTheme.canvas
                .ignoresSafeArea()
            MonitorPowerDetailPanel(
                power: MonitorPowerPreviewFixtures.power,
                history: MonitorPowerHistory(),
                language: powerModel.language,
                reduceMotion: false,
                runtime: nil,
                powerModel: powerModel,
                initialTab: .power,
                onOpenApp: { _ in },
                onClose: {}
            )
            .padding(24)
        }
        .frame(width: width, height: height)
    }
}

@MainActor
enum PowerPreviewRenderer {
    static func render(to path: String) async -> Bool {
        let appearance = ProcessInfo.processInfo.environment["COVIO_FORCE_APPEARANCE"]?
            .lowercased()
        let dark = appearance == "dark" ||
            ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?.lowercased() == "dark"
        let colorScheme: ColorScheme = dark ? .dark : .light
        let preserveGlass = ProcessInfo.processInfo.environment["COVIO_POWER_RENDER_GLASS"] == "1"
        let dynamicType: DynamicTypeSize = ProcessInfo.processInfo.environment["COVIO_POWER_RENDER_DYNAMIC_TYPE"] == "accessibility3"
            ? .accessibility3
            : .large
        let width = Double(
            ProcessInfo.processInfo.environment["COVIO_POWER_RENDER_WIDTH"] ?? ""
        ) ?? 620
        let height = Double(
            ProcessInfo.processInfo.environment["COVIO_POWER_RENDER_HEIGHT"] ?? ""
        ) ?? 848
        let model = PowerPreviewModel()
        return await MonitorFanPreviewSnapshot.write(
            PowerPopoverPreviewRoot(
                powerModel: model,
                width: width,
                height: height
            )
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicType),
            size: CGSize(width: width, height: height),
            path: path,
            dark: dark,
            glassMode: preserveGlass ? nil : .material
        )
    }
}

enum MonitorPowerPreviewFixtures {
    static let power = MonitorSnapshot.Power(
        supply: .adapter,
        hasBattery: true,
        batteryPercent: 84,
        temperatureCelsius: 33,
        watts: 18.1,
        averageWatts: 18.1,
        remainingSeconds: nil,
        chargePowerWatts: 9.8,
        timeToFullSeconds: 18_660,
        batteryHealthPercent: 97,
        topApps: [],
        events: [],
        batteryDataAvailable: true,
        powerDataAvailable: true,
        energyDataAvailable: true
    )
}

enum MonitorDisplayPreviewFixtures {
    static let display = MonitorSnapshot.Display(
        state: .active,
        brightnessPercent: 58,
        powerWatts: nil,
        externalDisplayCount: 0,
        pixelWidth: 3_456,
        pixelHeight: 2_234,
        refreshRate: 120
    )
}

enum MonitorFanPreviewFixtures {
    static var reading: MonitorFanReading {
        MonitorFanReading(
            temperatures: [
                .init(key: "TCMz", celsius: 65.9),
                .init(key: "TC0P", celsius: 61.2),
                .init(key: "TG0D", celsius: 55.4),
                .init(key: "TB0T", celsius: 35.1),
                .init(key: "TD3P", celsius: 48.6),
            ],
            units: [
                .init(index: 0, rpm: 2_789, minimumRPM: 1_499, maximumRPM: 5_348, targetRPM: 2_588, mode: 1),
                .init(index: 1, rpm: 2_954, minimumRPM: 1_499, maximumRPM: 5_776, targetRPM: 2_709, mode: 1),
            ]
        )
    }
}

@MainActor
struct MonitorFanPreviewRoot: View {
    private static var scenario: String {
        ProcessInfo.processInfo.environment["COVIO_MONITOR_FAN_RENDER_SCENARIO"] ?? "curve"
    }

    private static var previewError: String? {
        scenario == "error" ? "Fan control write failed" : nil
    }

    static var renderHeight: CGFloat {
        if scenario == "system-control" {
            return 280
        }
        if scenario == "temperature-rules-advanced" {
            return 1050
        }
        return 360
    }

    private static var usesTemperatureRules: Bool {
        scenario == "temperature-rules" || scenario == "temperature-rules-advanced"
    }

    private static var controlsFans: Bool {
        scenario != "error" && scenario != "system-control"
    }

    @StateObject private var model = MonitorFanControlModel(
        previewConfiguration: MonitorFanConfiguration(
            enabled: Self.controlsFans,
            mode: Self.scenario == "manual-sync"
                ? .manual
                : Self.scenario == "system-control" ? .automatic : .curve,
            startCelsius: 58,
            fullCelsius: 86,
            selectedSensorKeys: ["TCMz", "TC0P"],
            manualRPM: ["0": 2_588, "1": 2_709],
            manualModes: ["0": .manual, "1": .manual],
            syncFans: Self.scenario == "manual-sync",
            powerSource: Self.scenario.hasPrefix("power-curves") ? .battery : .adapter,
            curves: [
                "0": [
                    .init(temperature: 45, rpm: 1_200),
                    .init(temperature: 62, rpm: 2_200),
                    .init(temperature: 78, rpm: 3_900),
                    .init(temperature: 92, rpm: 5_348),
                ],
                "1": [
                    .init(temperature: 45, rpm: 1_300),
                    .init(temperature: 62, rpm: 2_400),
                    .init(temperature: 78, rpm: 4_300),
                    .init(temperature: 92, rpm: 5_776),
                ],
            ],
            batteryCurves: Self.scenario == "power-curves"
                ? [
                    "0": [
                        .init(temperature: 50, rpm: 1_200),
                        .init(temperature: 70, rpm: 2_200),
                        .init(temperature: 86, rpm: 3_900),
                        .init(temperature: 100, rpm: 5_348),
                    ],
                    "1": [
                        .init(temperature: 50, rpm: 1_300),
                        .init(temperature: 70, rpm: 2_600),
                        .init(temperature: 86, rpm: 4_400),
                        .init(temperature: 100, rpm: 5_776),
                    ],
                ]
                : [:],
            temperatureRules: Self.usesTemperatureRules
                ? ["battery": MonitorFanTemperatureRule.defaultPoints(for: .battery)]
                : [:]
        ),
        availability: .ready,
        helperStatus: FanControlHelperStatus(
            active: Self.controlsFans,
            mode: Self.scenario == "manual-sync"
                ? "manual"
                : Self.scenario == "system-control" ? "system" : "curve",
            controlTemperature: 65.9,
            leaseRemainingSeconds: 20,
            error: Self.previewError,
            sourceTemperatures: Self.usesTemperatureRules
                ? ["battery": 35.1]
                : [:]
        )
    )

    var body: some View {
        MonitorFanPopover(
            reading: MonitorFanPreviewFixtures.reading,
            language: .simplifiedChinese,
            model: model,
            scrollsContent: Self.scenario == "sensors",
            rendersForSnapshot: true,
            sensorsInitiallyExpanded: Self.scenario == "sensors",
            advancedInitiallyExpanded: Self.scenario == "temperature-rules-advanced"
        )
        .frame(width: 420, alignment: .topLeading)
        .background(MacTheme.surface)
    }
}

@MainActor
struct MonitorFanCardPreviewRoot: View {
    @StateObject private var model = MonitorFanControlModel(
        previewConfiguration: MonitorFanConfiguration(
            enabled: true,
            mode: .curve,
            startCelsius: 58,
            fullCelsius: 86,
            selectedSensorKeys: ["TCMz", "TC0P"],
            manualRPM: ["0": 2_588, "1": 2_709]
        ),
        availability: .ready,
        helperStatus: FanControlHelperStatus(
            active: true,
            mode: "automatic",
            controlTemperature: 65.9,
            leaseRemainingSeconds: 20,
            error: nil
        )
    )

    var body: some View {
        MonitorFanCard(
            reading: MonitorFanPreviewFixtures.reading,
            cpuHistory: [0.12, 0.18, 0.34, 0.42, 0.26, 0.31, 0.39, 0.44],
            temperatureHistory: [61.2, 62.8, 64.1, 63.6, 64.8, 65.9],
            rpmHistory: [1_920, 2_040, 2_260, 2_380, 2_560, 2_789],
            language: .simplifiedChinese,
            model: model
        )
        .frame(width: 296, height: HubMetrics.monitorCardHeight)
        .padding(24)
        .background(MacTheme.canvas)
    }
}

@MainActor
enum MonitorFanPreviewSnapshot {
    static func write<Content: View>(
        _ content: Content,
        size: CGSize,
        path: String,
        dark: Bool,
        glassMode: GlassSurfaceMode? = .material
    ) async -> Bool {
        let previousMode = GlassSurfaceMode.current
        if let glassMode { GlassSurfaceMode.current = glassMode }
        defer { GlassSurfaceMode.current = previousMode }

        let host = NSHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: size)
        host.wantsLayer = true
        host.layer?.contentsScale = 2

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(200))
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let bitmap: NSBitmapImageRep
        if let image = await screenCapture(window: window, size: size) {
            bitmap = NSBitmapImageRep(cgImage: image)
        } else if let cached = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: cached)
            bitmap = cached
        } else {
            window.orderOut(nil)
            return false
        }
        window.orderOut(nil)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func screenCapture(window: NSWindow, size: CGSize) async -> CGImage? {
        for _ in 0..<4 {
            if let content = try? await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            ), let capturedWindow = content.windows.first(where: {
                $0.windowID == CGWindowID(window.windowNumber)
            }) {
                let configuration = SCStreamConfiguration()
                configuration.width = Int(size.width * 2)
                configuration.height = Int(size.height * 2)
                configuration.showsCursor = false
                let filter = SCContentFilter(desktopIndependentWindow: capturedWindow)
                return try? await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}

@MainActor
enum MonitorFanDetailRenderer {
    static func render(to path: String) async -> Bool {
        let dark = Self.dark
        return await MonitorFanPreviewSnapshot.write(
            MonitorFanPreviewRoot()
                .environment(\.colorScheme, dark ? .dark : .light),
            size: CGSize(width: 420, height: MonitorFanPreviewRoot.renderHeight),
            path: path,
            dark: dark
        )
    }

    private static var dark: Bool {
        ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
            .lowercased() == "dark"
    }
}

@MainActor
enum MonitorFanCardRenderer {
    static func render(to path: String) async -> Bool {
        let dark = Self.dark
        return await MonitorFanPreviewSnapshot.write(
            MonitorFanCardPreviewRoot()
                .environment(\.colorScheme, dark ? .dark : .light),
            size: CGSize(width: 344, height: 284),
            path: path,
            dark: dark
        )
    }

    private static var dark: Bool {
        ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
            .lowercased() == "dark"
    }
}

@MainActor
final class MonitorPreviewWindowController: NSWindowController {
    init() {
        let showsPowerPopover = ProcessInfo.processInfo.environment[
            "COVIO_POWER_POPOVER_PREVIEW"
        ] == "1"
        let showsDisplayPopover = ProcessInfo.processInfo.environment[
            "COVIO_DISPLAY_POPOVER_PREVIEW"
        ] == "1"
        let previewHeight = showsDisplayPopover
            ? 1_040
            : showsPowerPopover
                ? MonitorPowerDetailLayoutPolicy.fullHeight + 100
                : HubMetrics.monitorBodyHeight + HubMetrics.panelPadding * 2
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: HubMetrics.panelWidth,
                height: previewHeight
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Covio Monitor Preview"
        window.appearance = HubAppearance.panel
        let powerModel = PowerPreviewModel()
        let snapshot = showsPowerPopover
            ? MonitorSnapshot.empty
                .replacingPower(MonitorPowerPreviewFixtures.power)
                .replacingDisplay(MonitorDisplayPreviewFixtures.display)
            : showsDisplayPopover
                ? MonitorSnapshot.empty
                    .replacingPower(MonitorPowerPreviewFixtures.power)
                    .replacingDisplay(MonitorDisplayPreviewFixtures.display)
                : .empty
        window.contentView = NSHostingView(
            rootView: MonitorPreviewRoot(
                snapshot: snapshot,
                runsSampling: !(showsPowerPopover || showsDisplayPopover),
                powerModel: powerModel,
                powerPopoverInitiallyPresented: showsPowerPopover,
                powerPopoverInitialTab: .power,
                displayPopoverInitiallyPresented: showsDisplayPopover,
                language: powerModel.language,
                height: previewHeight
            )
        )
        window.center()
        super.init(window: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class PowerPopoverPreviewWindowController: NSWindowController {
    init(powerModel: any PowerManagementModel) {
        let size = CGSize(width: 620, height: 848)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Covio Power Popover Preview"
        window.appearance = HubAppearance.panel
        window.contentView = NSHostingView(
            rootView: PowerPopoverPreviewRoot(
                powerModel: powerModel,
                width: size.width,
                height: size.height
            )
        )
        window.center()
        super.init(window: window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
#endif

import AppKit
import SwiftUI
import kmpDomain

/// 应用代理。装配 Notch Shell、菜单栏图标与全局快捷键。
///
/// `Info.plist` 的 `LSUIElement` 是 true，所以这是一个没有 Dock 图标与主菜单的代理应用。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 当前应用代理。宿主测试用它检查启动后的菜单栏入口装配。
    static private(set) weak var current: AppDelegate?

    /// 运行时。引擎与端口都由它持有。
    ///
    /// 单实例检查通过之后才创建，避免第二个进程去动 shared 的配置文件。
    private var runtime: AppRuntime?
    private let shell = NotchShellController()
    private(set) var statusItemController: StatusItemController?
    private var hotKey: GlobalHotKey?
    private var twoFingerSwipeMonitor: TwoFingerSwipeMonitor?
    private var instanceLock: SingleInstanceLock?
    #if DEBUG
    private var monitorPreview: NSWindowController?
    private var glassPlatePreviewWindow: NSWindow?
    private var fanPreviewWindow: NSWindow?
    private var fanCapabilityPreviewWindow: NSWindow?
    private var reportPreview: MonitorReportPreviewWindowController?
    private var fileAreaPreview: NSWindow?
    private var fileAreaLivePreview: FileAreaLivePreviewController?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        // LSUIElement 已经让进程成为代理应用。这里显式再设一次，防止从 Xcode 直接运行时不一致。
        NSApp.setActivationPolicy(.accessory)

        #if DEBUG
        switch ProcessInfo.processInfo.environment["COVIO_FORCE_APPEARANCE"]?.lowercased() {
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            break
        }
        #endif

        if let path = ProcessInfo.processInfo.environment["COVIO_FILE_NAMING_ACCEPTANCE_PATH"],
           !path.isEmpty
        {
            Task { @MainActor in
                exit(
                    await FileNamingAcceptanceVerifier.run(
                        outputURL: URL(fileURLWithPath: path)
                    )
                )
            }
            return
        }

        if let path = ProcessInfo.processInfo.environment["COVIO_FILE_NAMING_SMOKE_PATH"],
           !path.isEmpty
        {
            Task { @MainActor in
                exit(
                    await FileNamingSmokeVerifier.run(
                        outputURL: URL(fileURLWithPath: path)
                    )
                )
            }
            return
        }

        if let path = ProcessInfo.processInfo.environment["COVIO_AGENT_ACCEPTANCE_PATH"],
           !path.isEmpty
        {
            Task { @MainActor in
                exit(
                    await AgentAcceptanceVerifier.run(
                        outputURL: URL(fileURLWithPath: path)
                    )
                )
            }
            return
        }

        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["COVIO_MODEL_SETUP_RENDER"],
           !path.isEmpty
        {
            Task { @MainActor in
                exit(await ModelSetupPreviewRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        #endif

        // 调试构建可以用环境变量换玻璃底材，便于同一次构建对照截图。
        GlassSurfaceMode.applyEnvironmentOverride()
        MacTheme.applyEnvironmentOverride()

        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["COVIO_MONITOR_HISTORY_SOAK_PATH"],
           !path.isEmpty {
            let seconds = Double(
                ProcessInfo.processInfo.environment["COVIO_MONITOR_HISTORY_SOAK_SECONDS"] ?? ""
            ) ?? 3_600
            let language = ProcessInfo.processInfo.environment["COVIO_MONITOR_HISTORY_LANGUAGE"]
                .flatMap(AppLanguage.init(rawValue:)) ?? CopyLocale.language
            Task { @MainActor in
                exit(
                    await MonitorHistorySoakVerifier.run(
                        outputDirectory: URL(fileURLWithPath: path),
                        duration: seconds,
                        language: language
                    ) ? 0 : 1
                )
            }
            return
        }
        if ProcessInfo.processInfo.environment["COVIO_MONITOR_REPORT_PREVIEW"] == "1" {
            NSApp.setActivationPolicy(.regular)
            Task { @MainActor [weak self] in
                guard let self,
                      let preview = await MonitorReportPreviewWindowController.make()
                else { return }
                self.reportPreview = preview
            }
            return
        }
        if let path = ProcessInfo.processInfo.environment["COVIO_MONITOR_REPORT_RENDER"],
           !path.isEmpty {
            Task { @MainActor in
                exit(await MonitorReportPreviewRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        if let path = ProcessInfo.processInfo.environment["COVIO_MONITOR_RENDER"], !path.isEmpty {
            Task { @MainActor in
                exit(await MonitorSnapshotRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        if let path = ProcessInfo.processInfo.environment["COVIO_MONITOR_DETAIL_RENDER"], !path.isEmpty {
            Task { @MainActor in
                exit(await MonitorPowerDetailRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        if let path = ProcessInfo.processInfo.environment["COVIO_POWER_RENDER"], !path.isEmpty {
            Task { @MainActor in
                exit(await PowerPreviewRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        if let path = ProcessInfo.processInfo.environment["COVIO_MONITOR_FAN_DETAIL_RENDER"], !path.isEmpty {
            Task { @MainActor in
                exit(await MonitorFanDetailRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        if let path = ProcessInfo.processInfo.environment["COVIO_MONITOR_FAN_CARD_RENDER"], !path.isEmpty {
            Task { @MainActor in
                exit(await MonitorFanCardRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        if let path = ProcessInfo.processInfo.environment["COVIO_FAN_CAPABILITY_RENDER"], !path.isEmpty {
            Task { @MainActor in
                exit(await FanCapabilityPreviewRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        if ProcessInfo.processInfo.environment["COVIO_FAN_CAPABILITY_PREVIEW"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let scenario = FanCapabilityPreviewRenderer.scenarioFromEnvironment
            let isDark = scenario == .dark ||
                ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?.lowercased() == "dark"
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 960),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Covio Fan Capability Preview"
            window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            window.contentView = NSHostingView(
                rootView: FanCapabilityPreviewRoot(scenario: scenario, dark: isDark)
                    .environment(\.colorScheme, isDark ? .dark : .light)
            )
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            fanCapabilityPreviewWindow = window
            return
        }
        if ProcessInfo.processInfo.environment["COVIO_MONITOR_PREVIEW"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let preview = MonitorPreviewWindowController()
            monitorPreview = preview
            preview.showWindow(nil)
            return
        }
        if ProcessInfo.processInfo.environment["COVIO_GLASS_PLATE_PREVIEW"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let isDark = ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
                .lowercased() == "dark"
            let colorScheme: ColorScheme = isDark ? .dark : .light
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_120, height: 760),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.title = "Covio Glass Plate Preview"
            window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = NSHostingView(
                rootView: HubGlassPlatePreviewRoot(colorScheme: colorScheme)
            )
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            glassPlatePreviewWindow = window
            return
        }
        if ProcessInfo.processInfo.environment["COVIO_MONITOR_FAN_PREVIEW"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 468, height: 668),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Covio Fan Control Preview"
            window.isOpaque = false
            window.backgroundColor = .clear
            let isDark = ProcessInfo.processInfo.environment["AppleInterfaceStyle"]?
                .lowercased() == "dark"
            let colorScheme: ColorScheme = isDark ? .dark : .light
            window.contentView = NSHostingView(
                rootView: MonitorFanPreviewRoot()
                    .padding(24)
                    .environment(\.colorScheme, colorScheme)
            )
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            fanPreviewWindow = window
            return
        }
        if ProcessInfo.processInfo.environment["COVIO_POWER_PREVIEW"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let preview = PowerPopoverPreviewWindowController(powerModel: PowerPreviewModel())
            monitorPreview = preview
            preview.showWindow(nil)
            return
        }
        if ProcessInfo.processInfo.environment["COVIO_POWER_LIVE_PREVIEW"] == "1" {
            // Hardware-only Power checks need the real runtime and a visible
            // window. The normal app path remains the menu-bar shell.
            NSApp.setActivationPolicy(.regular)
            AppPaths.ensureSupportDirectory()
            let runtime = AppRuntime()
            self.runtime = runtime
            runtime.start()
            if ProcessInfo.processInfo.environment["COVIO_POWER_LIVE_AUTOSTART_LID"] == "1" {
                Task { @MainActor in
                    for _ in 0 ..< 25 {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard runtime.powerRuntime.helperStatus == .match else { continue }
                        _ = runtime.startSession(mode: .lid, duration: .oneHour)
                        return
                    }
                }
            }
            let preview = PowerPopoverPreviewWindowController(powerModel: runtime)
            monitorPreview = preview
            preview.showWindow(nil)
            return
        }
        if let path = ProcessInfo.processInfo.environment["COVIO_AGENT_RENDER"], !path.isEmpty {
            Task { @MainActor in
                exit(await AgentPreviewRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        if let path = ProcessInfo.processInfo.environment["COVIO_SETTINGS_UPDATE_RENDER"],
           !path.isEmpty
        {
            Task { @MainActor in
                exit(await SettingsUpdatePreviewRenderer.render(to: path) ? 0 : 1)
            }
            return
        }
        if let path = ProcessInfo.processInfo.environment["COVIO_FILE_AREA_RENDER"], !path.isEmpty {
            let width = Double(ProcessInfo.processInfo.environment["COVIO_FILE_AREA_WIDTH"] ?? "960") ?? 960
            Task { @MainActor in
                exit(FileAreaPreviewRenderer.render(panelWidth: width, to: path) ? 0 : 1)
            }
            return
        }
        if ProcessInfo.processInfo.environment["COVIO_FILE_AREA_LIVE_PREVIEW"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let width = Double(ProcessInfo.processInfo.environment["COVIO_FILE_AREA_WIDTH"] ?? "960") ?? 960
            let state = FileAreaLivePreviewState(
                rawValue: ProcessInfo.processInfo.environment["COVIO_FILE_AREA_PREVIEW_STATE"] ?? "normal"
            ) ?? .normal
            let reduceMotion = ProcessInfo.processInfo.environment["COVIO_FILE_AREA_REDUCE_MOTION"] == "1"
            let preview = FileAreaLivePreviewController(
                panelWidth: width,
                state: state,
                reduceMotion: reduceMotion
            )
            fileAreaLivePreview = preview
            preview.present()
            return
        }
        if ProcessInfo.processInfo.environment["COVIO_FILE_AREA_PREVIEW"] == "1" {
            NSApp.setActivationPolicy(.regular)
            let width = Double(ProcessInfo.processInfo.environment["COVIO_FILE_AREA_WIDTH"] ?? "960") ?? 960
            let contentWidth = width - HubMetrics.panelPadding * 2
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: FileAreaMetrics.areaHeight),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Covio File Area"
            window.contentView = NSHostingView(
                rootView: FileAreaShowcaseView(
                    contentWidth: contentWidth,
                    language: .simplifiedChinese
                )
            )
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            fileAreaPreview = window
            return
        }
        #endif

        // 测试进程不是真实实例，不参与单实例仲裁。
        // 真实应用在跑时仲裁会失败，那会把整个测试套件终止掉。
        if !LaunchEnvironment.isRunningTests() {
            // 单实例。Compose 版用 app.lock，本版用 app.swiftui.lock，两版可以同时运行。
            let lock = SingleInstanceLock()
            guard lock.acquire() else {
                NSLog("Covio 已经在运行。本进程退出。")
                NSApp.terminate(nil)
                return
            }
            instanceLock = lock
        }

        AppPaths.ensureSupportDirectory()

        #if DEBUG
        let liveClipboardPreview =
            ProcessInfo.processInfo.environment["COVIO_CLIPBOARD_LIVE_PREVIEW"] == "1"
        if liveClipboardPreview, !ClipboardWorkspaceLivePreview.prepare() {
            NSLog("剪切板原生预览数据未准备成功。")
            return
        }
        #endif

        let runtime = AppRuntime()
        self.runtime = runtime
        shell.runtime = runtime
        runtime.agentUIActions.setOpenPaneAction { [weak self] pane in
            guard let self else { return false }
            let opened: Bool
            switch pane {
            case .agent:
                self.shell.chrome.select(.assistant)
                opened = self.shell.workbench.openSettings()
            case .settings:
                self.shell.chrome.select(.overview)
                opened = self.shell.workbench.openSettings()
            case .now, .clipboard, .files, .devices:
                opened = self.shell.workbench.open(pane.hubTab)
            }
            guard opened else { return false }
            self.shell.show()
            return true
        }
        // 工作台配置落盘。文件不存在时 `load()` 给默认值，所以首次启动就有六块组件。
        shell.workbench.attach(
            store: WorkbenchStore.companion.create(path: AppPaths.workbenchFile.path)
        )
        // 测试进程里不启动运行时。`start()` 会连真实的存储与系统设置：
        // 它监视真实截图目录，还会写真实 `shelf.json`。
        // 界面装配照旧，所以 `testHostApplicationRunsTheShell` 仍然有效。
        // 测试要的运行时由测试自己用假实现构造。
        if !LaunchEnvironment.isRunningTests() {
            runtime.start()
        }

        shell.start()

        #if DEBUG
        if liveClipboardPreview {
            Task { @MainActor in
                shell.workbench.select(paneID: PaneKind.clipboard.defaultId)
                try? await Task.sleep(for: .milliseconds(120))
                shell.showFromGesture()
            }
        }
        #endif

        if !LaunchEnvironment.isRunningTests() {
            let shell = self.shell
            let monitor = TwoFingerSwipeMonitor { [weak shell] in
                shell?.showFromGesture()
            }
            let result = monitor.start()
            if case let .started(deviceCount) = result {
                NSLog("双指下滑入口已启动，设备数：%d", deviceCount)
            } else if let errorCode = result.errorCode {
                NSLog("双指下滑入口不可用：%@", errorCode)
            }
            twoFingerSwipeMonitor = monitor
        }

        let statusItemController = StatusItemController(shell: shell, runtime: runtime)
        self.statusItemController = statusItemController

        if LaunchEnvironment.isSlimInstallProfile() {
            Task { @MainActor in
                self.shell.show()
            }
        }

        #if DEBUG
        // Visual QA uses an isolated support directory and skips the global hotkey.
        if ProcessInfo.processInfo.environment["COVIO_HUB_PREVIEW"] == "1" {
            NSApp.setActivationPolicy(.regular)
            Task { @MainActor in
                if let rawSection = ProcessInfo.processInfo.environment["COVIO_SETTINGS_PREVIEW_SECTION"],
                   let section = SettingsSection(rawValue: rawSection)
                {
                    self.shell.chrome.select(section)
                    _ = self.shell.workbench.openSettings()
                }
                // 固定打开，避免指针不在面板内时自动收起，截图才可复现。
                self.shell.showFromGesture()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        #endif

        // Control+Option+T 打开或收起 Hub。
        let hotKey = GlobalHotKey { [weak self] in
            self?.shell.toggle()
        }
        if !hotKey.register() {
            // Carbon 在快捷键冲突时静默失败。计划的 M4 要求设置页暴露这个状态。
            NSLog("Control+Option+T 注册失败。快捷键可能已被其它应用占用。")
        }
        self.hotKey = hotKey
    }

    /// 应用菜单和 ⌘, 打开真实的工作台设置页。
    @discardableResult
    func openSettingsFromApplicationMenu() -> Bool {
        guard shell.workbench.openSettings() else { return false }
        shell.showFromGesture()
        return true
    }

    #if DEBUG
    var debugWorkbenchDestination: HubDestination {
        shell.workbench.destination
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        Self.current = nil
        hotKey?.unregister()
        statusItemController?.tearDown()
        // Stop the lease before the helper expires it. The helper also restores
        // after a crash, but normal quit should not leave fan control running.
        FanControlLeaseKeeper.shared.stopAndRestore()
        // 先停引擎。它会撤销 `pmset` 的改动，必须在进程退出前跑完。
        runtime?.stop()
        twoFingerSwipeMonitor?.stop()
        twoFingerSwipeMonitor = nil
        shell.stop()
        instanceLock?.release()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

import AppKit
import Foundation

/// SwiftUI 宿主运行时。
///
/// 职责：
/// - 持有全部 Ports 与 `Engine`。
/// - 把引擎状态与配置暴露成可观察属性，界面直接读。
/// - 提供设置页要调用的动作。
///
/// 只跑在主线程。`Engine` 自己加锁，所以后台的端口回调进来也安全。
///
/// 截图目录监听在 `ShelfRuntime` 里，剪贴板属于 M4。
@MainActor
@Observable
final class AppRuntime {
    /// 引擎状态。
    private(set) var appState: AppState
    /// 当前配置。写它一律走 `updateConfig`。
    private(set) var config: AppConfig
    /// 特权 helper 的状态。
    private(set) var helperStatus: HelperStatus = .missing
    /// Helper 服务生命周期状态。
    private(set) var helperServiceState: HelperServiceState = .notRegistered
    /// helper 当前执行的充电上限状态。
    private(set) var chargeLimitStatus: ChargeLimitHelperStatus?
    /// 一次性提示。界面读完应调用 `clearStatus`。
    private(set) var statusMessage: String?
    /// 有耗时操作在跑。界面据此禁用按钮。
    private(set) var busy = false
    /// 更新检查正在执行。工作台更新入口据此避免重复触发。
    private(set) var isCheckingForUpdates = false
    /// 最近一次成功检查发现的新版本。无更新或尚未检查时为 nil。
    private(set) var availableUpdate: UpdateInfo?
    /// Root updater 的最近一次状态。
    private(set) var updaterStatus: UpdaterStatus?
    /// Root updater 正在执行状态或操作请求。
    private(set) var updaterBusy = false
    /// Root updater 不可用。Migration PKG 或 repair PKG 缺失时保持 true。
    private(set) var updaterUnavailable = false
    /// 首次启动的引导是否可见。
    private(set) var welcomeVisible: Bool

    /// 界面语言。跟随配置，配置为空时跟随系统。
    var language: AppLanguage { AppLanguage.fromCode(config.language) }
    /// 语言设置。空字符串表示跟随系统。
    var languagePreference: AppLanguagePreference { AppLanguagePreference.fromCode(config.language) }
    /// 屏幕 card 的持久化设置。
    var displayConfig: DisplayConfig {
        config.display ?? DisplayConfig.companion.fromLegacy(
            power: config.power,
            keepsAwakeOnAdapter: config.disableLidSleepInCharging,
            keepsAwakeOnBattery: config.disableLidSleepOnBattery
        )
    }
    /// Screen card 的单一合盖保持策略。
    var closedLidPowerPolicy: ClosedLidPowerPolicy {
        displayConfig.closedLidPowerPolicy
    }

    let logger: AppLogger

    /// 截图库。文件区读它。
    let shelf: ShelfRuntime

    /// 剪切板。Hub 的剪切板页签读它。
    let clipboard: ClipboardRuntime

    /// 共享文件工作区。Hub 的文件页签读它。
    let workspace: WorkspaceRuntime

    /// 文件区的短期传输任务。任务不持久化。
    let transfer: WorkspaceTransferRuntime

    /// 电源管理面的真实运行时。
    let powerRuntime: PowerRuntime
    /// 文件自动命名。Hub 的文件页签读它。
    let autoNaming: AutoNamingRuntime

    /// 离线本地服务 Agent。Hub 的 Agent 页签读它。
    let agent: AgentChatRuntime

    /// 用户明确授权给 Agent 读取的文件。
    let agentAttachments: AgentAttachmentStore

    /// Agent 导航与设置工具的唯一入口。
    let agentUIActions = AgentUIActionRouter()

    /// 外部本地 Agent 的 loopback MCP 服务。
    private(set) var agentExternalService: AgentExternalMCPService?
    private(set) var agentExternalError: String?

    /// 文件自动命名和 Agent 共用同一个本地模型容器。
    let modelSetup: ModelSetupRuntime
    private let localModelRuntime: LocalModelRuntime
    private var activeModelConfiguration: NamingModelConfiguration?
    private let agentGateway: AgentServiceGateway
    private let modelSelectionState: LocalModelSelectionState
    /// 当前激活的模型档位。没有模型时是 nil。
    var activeModelTier: LocalModelTier? { modelSetup.activeTier }
    private let agentHistoryStore: any AgentHistoryStoring
    private let agentExternalAuditStore: (any AgentExternalAuditStoring)?
    private let monitorHistorySampler: any MonitorHistorySampling
    let monitorHistoryReport: MonitorReportModel
    private let agentExternalTokenStore = AgentExternalTokenStore()
    private let agentExternalPreferences: AgentExternalServicePreferences

    private let configStore: ConfigStore
    /// 剪切板回报错误的中间人。理由见 `ClipboardBridge`。
    private let clipboardBridge: ClipboardBridge
    private let engine: Engine
    private let powerSource: PowerSource
    private let powerObservationSource: PowerObservationSource
    private let lid: LidSensor
    private let idle: IdleSensor
    private let sleepController: SleepController
    private let sleepWatcher: SleepWatcher
    private let wakeLogReader: WakeLogReader
    private let privileged: PrivilegedOps
    private let helperMonitor: HelperStatusMonitor?
    private let helperServiceManager: any HelperServiceManaging
    private let chargeLimitClient: any ChargeLimitClientProtocol
    private let loginItem: LoginItem
    private let notifier: Notifier
    private let updateChecker: UpdateChecker
    private let updaterClient: any CovioUpdaterClientProtocol
    private let updaterRequestTimeout: TimeInterval
    private let updaterOperationTimeout: TimeInterval
    /// 通知开关的持有者。`MacNotifier` 要一个读开关的闭包，
    /// 那个闭包必须在 `self` 建好之前交出去，所以开关放在这个独立对象里。
    private let notificationGate: NotificationGate

    private let stateForwarder: StateForwarder
    private var tickTimer: Timer?
    private var updateTimer: Timer?
    private var updaterTimeoutTask: Task<Void, Never>?
    private var updaterRequestGeneration = 0
    private var ticks = 0

    /// 每秒一次的心跳间隔。
    static let tickInterval: TimeInterval = 1
    /// 每五次心跳刷新一次 helper 状态。
    static let helperRefreshTicks = 5
    /// 启动后 30 秒做第一次自动更新检查。
    static let firstUpdateCheckDelay: TimeInterval = 30

    /// 端口都按协议收。默认值是 macOS 的真实实现，测试传假的。
    init(
        logger: AppLogger? = nil,
        configStore: ConfigStore? = nil,
        power: PowerSource = MacPowerSource(),
        lid: LidSensor = MacLidSensor(),
        idle: IdleSensor = MacIdleSensor(),
        sleepController: SleepController = MacSleepController(),
        sleepWatcher: SleepWatcher = MacSleepWatcher(),
        wakeLogReader: WakeLogReader = PmsetWakeLogReader(),
        privileged: PrivilegedOps? = nil,
        helperServiceManager: (any HelperServiceManaging)? = nil,
        chargeLimitClient: any ChargeLimitClientProtocol = HelperClient(),
        loginItem: LoginItem = MacLoginItem(),
        notifier: Notifier? = nil,
        updateChecker: UpdateChecker = GithubUpdateChecker(),
        updaterClient: any CovioUpdaterClientProtocol = CovioUpdaterClient(),
        updaterRequestTimeout: TimeInterval = 8,
        updaterOperationTimeout: TimeInterval = 45,
        powerObservation: PowerObservationSource? = nil,
        powerHistoryStore: PowerHistoryStore? = nil,
        closedLidBrightnessBackend: ClosedLidBrightnessBackend? = nil,
        closedLidBrightnessStore: ClosedLidBrightnessRecoveryStoring? = nil,
        shelf: ShelfRuntime? = nil,
        clipboard: ClipboardRuntime? = nil,
        workspace: WorkspaceRuntime? = nil,
        transfer: WorkspaceTransferRuntime? = nil,
        autoNaming: AutoNamingRuntime? = nil,
        modelSetup: ModelSetupRuntime? = nil,
        agentHistoryStore: (any AgentHistoryStoring)? = nil,
        monitorHistoryStore: (any MonitorHistoryStoring)? = nil,
        monitorHistorySampler: (any MonitorHistorySampling)? = nil,
        agentExternalPreferences: AgentExternalServicePreferences = .standard
    ) {
        let resolvedLogger = logger ?? FileAppLogger()
        self.agentExternalPreferences = agentExternalPreferences
        let resolvedStore = configStore ?? ConfigStore.companion.create(path: AppPaths.configFile.path)

        let resolvedPrivileged: PrivilegedOps
        let resolvedHelperMonitor: HelperStatusMonitor?
        if let privileged {
            resolvedPrivileged = privileged
            resolvedHelperMonitor = privileged as? HelperStatusMonitor
        } else {
            let monitor = HelperStatusMonitor(
                upstream: MacPrivilegedOps(logger: resolvedLogger)
            )
            resolvedPrivileged = monitor
            resolvedHelperMonitor = monitor
        }
        let resolvedPowerObservation = powerObservation ?? MacPowerObservationSource()
        let resolvedPowerHistory = powerHistoryStore ?? PowerHistoryStore.companion.create(
            path: AppPaths.powerHistoryFile.path
        )

        self.logger = resolvedLogger
        self.configStore = resolvedStore
        self.powerSource = power
        self.powerObservationSource = resolvedPowerObservation
        self.lid = lid
        self.idle = idle
        self.sleepController = sleepController
        self.sleepWatcher = sleepWatcher
        self.wakeLogReader = wakeLogReader
        self.privileged = resolvedPrivileged
        self.helperMonitor = resolvedHelperMonitor
        self.helperServiceManager = helperServiceManager ?? SMAppHelperServiceManager.shared
        self.chargeLimitClient = chargeLimitClient
        self.loginItem = loginItem
        self.notificationGate = NotificationGate()
        self.notifier = notifier ?? MacNotifier(logger: resolvedLogger) { [gate = notificationGate] in
            gate.isEnabled
        }
        self.updateChecker = updateChecker
        self.updaterClient = updaterClient
        self.updaterRequestTimeout = updaterRequestTimeout
        self.updaterOperationTimeout = updaterOperationTimeout

        // 空语言表示跟随系统。不要把解析出的语言写回配置，否则系统语言以后变化时不再生效。
        var loaded = resolvedStore.load()
        if loaded.power.enabled != loaded.enabled {
            let draft = ConfigDraft(loaded)
            draft.power = Self.powerWithEnabled(loaded.power, enabled: loaded.enabled)
            loaded = draft.build()
            resolvedStore.save(config: loaded)
        }
        self.config = loaded
        self.appState = AppRuntime.initialState(enabled: loaded.enabled)
        self.welcomeVisible = loaded.firstRun
        self.notificationGate.isEnabled = loaded.notificationsEnabled

        // 转发器先建好再交给引擎。闭包捕获 `self` 要等全部存储属性赋值完，
        // 所以挂闭包的动作放在引擎之后。
        let forwarder = StateForwarder()
        self.stateForwarder = forwarder

        let shelfStore = ShelfStoreClient()
        let screenshotPreferences = MacScreenshotPreferenceStore()
        let resolvedShelf = shelf ?? ShelfRuntime(
            store: shelfStore,
            preferences: screenshotPreferences,
            environment: ScreenshotLibraryEnvironment(
                screenshotDirectory: { screenshotPreferences.screenshotDirectory() }
            )
        )
        self.shelf = resolvedShelf

        // 剪切板同样要先建好中间人。开关与快捷键都读配置。
        let clipboardBridge = ClipboardBridge(config: loaded)
        self.clipboardBridge = clipboardBridge
        let resolvedClipboard = clipboard ?? ClipboardRuntime(
            store: ClipboardStore.companion.create(path: AppPaths.clipboardFile.path),
            imageDirectory: AppPaths.clipboardDirectory,
            environment: ClipboardEnvironment(
                isEnabled: { clipboardBridge.config.clipboardEnabled },
                hotKeyBinding: { action in
                    switch action {
                    case .pasteStack: clipboardBridge.config.clipboardPasteStackHotKey
                    case .captureSelection: clipboardBridge.config.clipboardCaptureHotKey
                    }
                },
                language: { AppLanguage.fromCode(clipboardBridge.config.language) }
            ),
            bridge: clipboardBridge
        )
        self.clipboard = resolvedClipboard

        // 工作区没有配置依赖，也没有要交出去的闭包。直接建。
        let resolvedWorkspace = workspace ?? WorkspaceRuntime()
        self.workspace = resolvedWorkspace
        self.transfer = transfer ?? WorkspaceTransferRuntime(workspace: resolvedWorkspace)

        let resourceRoot = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        let resolvedModelSetup = modelSetup ?? ModelSetupRuntime()
        self.modelSetup = resolvedModelSetup
        let memory = LocalModelMemoryProbe.current()
        let registeredConfiguration: NamingModelConfiguration? = {
            guard let registeredTier = resolvedModelSetup.selectedRegisteredTier,
                  resolvedModelSetup.state(for: registeredTier).isReady,
                  let registration = resolvedModelSetup.registration(for: registeredTier),
                  memory.availableBytes >= registeredTier.estimatedWorkingSetBytes
            else { return nil }
            return NamingModelConfiguration(
                modelDirectory: URL(fileURLWithPath: registration.directoryPath, isDirectory: true),
                tier: registeredTier
            )
        }()
        let bundledConfiguration = NamingModelConfiguration.bundled(
            resourceDirectory: resourceRoot,
            environment: ProcessInfo.processInfo.environment
        )
        let modelConfiguration = registeredConfiguration ?? bundledConfiguration
        if let modelConfiguration {
            resolvedModelSetup.setActiveTier(modelConfiguration.tier)
            if registeredConfiguration == nil {
                resolvedModelSetup.markBundledModel(tier: modelConfiguration.tier)
            }
        }
        let modelSelectionState = LocalModelSelectionState(initialTier: modelConfiguration?.tier)
        self.modelSelectionState = modelSelectionState
        let localModelRuntime = LocalModelRuntime(
            modelDirectory: modelConfiguration?.modelDirectory
        )
        self.localModelRuntime = localModelRuntime
        self.activeModelConfiguration = modelConfiguration
        let initialNamingModel = modelConfiguration.map {
            Self.makeNamingModel(configuration: $0, containerRuntime: localModelRuntime)
        } ?? UnavailableNamingModel()
        let resolvedAutoNaming = autoNaming ?? AutoNamingRuntime(model: initialNamingModel)
        self.autoNaming = resolvedAutoNaming
        let agentAttachments = AgentAttachmentStore()
        self.agentAttachments = agentAttachments
        let resolvedAgentHistory = agentHistoryStore
            ?? AgentHistoryStore(path: AppPaths.agentHistoryFile)
        self.agentHistoryStore = resolvedAgentHistory
        self.agentExternalAuditStore = resolvedAgentHistory as? any AgentExternalAuditStoring
        let resolvedMonitorHistoryStore = monitorHistoryStore
            ?? MonitorHistoryStore(path: AppPaths.monitorHistoryFile)
        self.monitorHistorySampler = monitorHistorySampler
            ?? MonitorHistorySampler(store: resolvedMonitorHistoryStore)
        self.monitorHistoryReport = MonitorReportModel(store: resolvedMonitorHistoryStore)
        let agentGateway = AgentServiceGateway(
            handlers: AgentAppServices.handlers(
                shelf: resolvedShelf,
                clipboard: resolvedClipboard,
                workspace: resolvedWorkspace,
                attachments: agentAttachments,
                autoNaming: resolvedAutoNaming,
                fileNamingPolicy: loaded.fileNaming,
                uiActions: agentUIActions,
                modelRuntime: localModelRuntime
            )
        )
        self.agentGateway = agentGateway
        self.agent = AgentChatRuntime(
            model: LocalAgentModel(
                modelDirectory: modelConfiguration?.modelDirectory,
                gateway: agentGateway,
                containerRuntime: localModelRuntime,
                agentToolCallingAvailable: {
                    await modelSelectionState.supportsAgentToolCalling()
                }
            ),
            gateway: agentGateway,
            historyStore: resolvedAgentHistory,
            attachmentStore: agentAttachments
        )

        let resolvedDisplayConfig = loaded.display ?? DisplayConfig.companion.fromLegacy(
            power: loaded.power,
            keepsAwakeOnAdapter: loaded.disableLidSleepInCharging,
            keepsAwakeOnBattery: loaded.disableLidSleepOnBattery
        )
        let engine = Engine(
            initialConfig: loaded,
            power: power,
            lid: lid,
            idle: idle,
            sleepController: sleepController,
            sleepWatcher: sleepWatcher,
            privileged: resolvedPrivileged,
            logger: resolvedLogger,
            wakeLogReader: wakeLogReader,
            // 下面这三个闭包由引擎在后台唤醒扫描线程上调用。
            // 标 `@Sendable` 让它们脱离主 actor；不标的话闭包继承 `init` 的隔离，
            // 后台线程一调就撞 `dispatch_assert_queue` 断言。
            clock: { @Sendable in AppRuntime.nowMillis() },
            stateListener: forwarder,
            // 引擎要求这个块跑在别的线程上。桥接闭包不能自动证明 Sendable，
            // 用 `SendableBox` 把「按约定跨线程」这件事写在一处。
            wakeScanExecutor: { @Sendable block in
                let box = SendableBox(block)
                // 等 applicationDidFinishLaunching 返回并显示 UI。
                // 然后把扫描送到 utility 队列，启动路径不等待。
                DispatchQueue.main.async {
                    DispatchQueue.global(qos: .utility).async { _ = box.value() }
                }
            },
            wakeDelay: { @Sendable millis in
                let seconds = Double(millis.int64Value) / 1_000
                if seconds > 0 { Thread.sleep(forTimeInterval: seconds) }
            },
            wakeRetryDelayMillis: 1_000,
            wakeRetryCount: 3,
            wakeCacheNowMillis: { @Sendable in AppRuntime.nowMillis() }
        )
        self.engine = engine
        self.powerRuntime = PowerRuntime(
            engine: engine,
            privileged: resolvedPrivileged,
            observationSource: resolvedPowerObservation,
            historyStore: resolvedPowerHistory,
            config: loaded.power,
            displayConfig: resolvedDisplayConfig,
            sleepProtectionEnabled: loaded.enabled,
            closedLidBrightnessBackend: closedLidBrightnessBackend,
            closedLidBrightnessStore: closedLidBrightnessStore
        )

        forwarder.handler = { @Sendable [weak self] state in
            MainActor.assumeIsolated { self?.appState = state }
        }
        resolvedModelSetup.activatePackage = { [weak self] verified in
            guard let self else {
                throw LocalModelPackageFailure(
                    code: .modelBusy,
                    detail: "The app runtime is unavailable."
                )
            }
            try await self.activateVerifiedModelPackage(verified)
        }
        resolvedModelSetup.deactivatePackage = { [weak self] tier in
            guard let self else { return }
            try await self.deactivateModelPackage(tier: tier)
        }
        agentUIActions.install(
            openPane: nil,
            readSetting: { [weak self] key in
                self?.agentSettingValue(for: key)
            },
            changeSetting: { [weak self] key, value in
                self?.applyAgentSettingChange(key: key, value: value) ?? false
            }
        )
#if DEBUG
        if let version = ProcessInfo.processInfo.environment["COVIO_UPDATE_PREVIEW_VERSION"],
           !version.isEmpty
        {
            availableUpdate = UpdateInfo(
                version: version,
                title: "Covio \(version)",
                releaseUrl: "https://github.com/wyz541/kmp-Covio/releases",
                publishedAt: ""
            )
        }
#endif
        if agentExternalServiceEnabled {
            configureAgentExternalService()
        }
        resolvedHelperMonitor?.setUpdateHandler { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.applyHelperSnapshot(snapshot)
            }
        }
    }

    var agentExternalServiceEnabled: Bool {
        agentExternalPreferences.isEnabled()
    }

    func setAgentExternalServiceEnabled(_ enabled: Bool) {
        agentExternalPreferences.setEnabled(enabled)
        agentExternalError = nil
        if enabled {
            if agentExternalService == nil {
                configureAgentExternalService()
            } else {
                agentExternalService?.start()
            }
        } else {
            agentExternalService?.stop()
        }
    }

    func rotateAgentExternalToken() {
        let wasEnabled = agentExternalServiceEnabled
        agentExternalService?.stop()
        agentExternalService = nil
        agentExternalError = nil
        do {
            _ = try agentExternalTokenStore.rotate()
            configureAgentExternalService()
            if wasEnabled {
                agentExternalService?.start()
            }
        } catch {
            agentExternalError = error.localizedDescription
        }
    }

    private func configureAgentExternalService() {
        guard let agentExternalAuditStore else {
            agentExternalError = "External Agent audit storage is unavailable."
            return
        }
        agentExternalError = nil
        do {
            let token = try agentExternalTokenStore.loadOrCreate()
            let service = AgentExternalMCPService(
                gateway: agentGateway,
                auditStore: agentExternalAuditStore,
                token: token
            )
            agentExternalService = service
            service.setOnPendingActionChanged { [weak self] in
                await self?.agent.refreshExternalToolState()
            }
            Task {
                await agentGateway.setAuditObserver { [weak service] audit in
                    await service?.recordExternalAudit(audit)
                }
            }
            if agentExternalServiceEnabled {
                service.start()
            }
        } catch {
            agentExternalError = error.localizedDescription
        }
    }

    /// Unloads the old model before the shared runtime receives the next loader.
    private func activateVerifiedModelPackage(
        _ verified: VerifiedLocalModelPackage
    ) async throws {
        guard !agent.isBusy,
              agent.pendingAction == nil,
              await autoNaming.prepareForModelSwitch(),
              await agent.prepareForModelSwitch()
        else {
            throw LocalModelPackageFailure(
                code: .modelBusy,
                detail: "Finish the current local model task before switching."
            )
        }
        let previousConfiguration = activeModelConfiguration
        let previousTier = await modelSelectionState.currentTier()
        await localModelRuntime.unloadModelContainer()
        do {
            await localModelRuntime.replaceModelDirectory(verified.directory)
            let configuration = NamingModelConfiguration(
                modelDirectory: verified.directory,
                tier: verified.tier
            )
            let replaced = await autoNaming.replaceModel(
                Self.makeNamingModel(
                    configuration: configuration,
                    containerRuntime: localModelRuntime
                )
            )
            guard replaced else {
                throw LocalModelPackageFailure(
                    code: .modelBusy,
                    detail: "Finish the current file naming task before switching."
                )
            }
            await modelSelectionState.set(verified.tier)
            activeModelConfiguration = configuration
        } catch {
            await localModelRuntime.replaceModelDirectory(previousConfiguration?.modelDirectory)
            _ = await autoNaming.replaceModel(
                previousConfiguration.map {
                    Self.makeNamingModel(
                        configuration: $0,
                        containerRuntime: localModelRuntime
                    )
                } ?? UnavailableNamingModel()
            )
            await modelSelectionState.set(previousTier)
            activeModelConfiguration = previousConfiguration
            throw error
        }
    }

    private func deactivateModelPackage(tier: LocalModelTier) async throws {
        guard modelSetup.activeTier == tier else { return }
        guard !agent.isBusy,
              agent.pendingAction == nil,
              await autoNaming.prepareForModelSwitch(),
              await agent.prepareForModelSwitch()
        else {
            throw LocalModelPackageFailure(
                code: .modelBusy,
                detail: "Finish the current local model task before removing it."
            )
        }
        await localModelRuntime.unloadModelContainer()
        await localModelRuntime.replaceModelDirectory(nil)
        _ = await autoNaming.replaceModel(UnavailableNamingModel())
        await modelSelectionState.set(nil)
        activeModelConfiguration = nil
    }

    private static func makeNamingModel(
        configuration: NamingModelConfiguration,
        containerRuntime: LocalModelRuntime
    ) -> any NamingModelServing {
        NamingModelCoordinator(
            primary: MLXNamingModel(
                configuration: configuration,
                containerRuntime: containerRuntime
            )
        )
    }

    // MARK: - 生命周期

    /// 启动引擎与两条后台节奏。可以重复调用，第二次没有副作用。
    func start() {
        guard tickTimer == nil else { return }
        logger.info(message: "Covio \(CovioReleaseIdentity.APP_VERSION) starting")

        helperServiceState = helperServiceManager.state
        helperMonitor?.requestProbe(force: true)
        helperStatus = privileged.status()
        reconcileChargeLimit()
        syncHibernateMode()
        syncLoginItem()
        engine.start()
        powerRuntime.start()
        monitorHistorySampler.start()
        syncState()
        Task {
            await modelSetup.refresh()
            await agent.restoreHistory()
        }
        if agentExternalServiceEnabled {
            agentExternalService?.start()
        }

        // 截图库的错误要显示在 Hub 上，出口在这里接。
        shelf.onError = { [weak self] entry in
            guard let self else { return }
            self.statusMessage = entry.text(for: self.language)
        }
        shelf.start()

        clipboardBridge.report = { [weak self] entry in
            guard let self else { return }
            self.statusMessage = entry.text(for: self.language)
        }
        clipboard.applyConfiguration()

        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        updateTimer = Timer.scheduledTimer(withTimeInterval: Self.firstUpdateCheckDelay, repeats: false) { _ in
            MainActor.assumeIsolated {
                self.checkForUpdates(manual: false)
                self.updateTimer = Timer.scheduledTimer(
                    withTimeInterval: Double(max(1, self.config.updateCheckIntervalHours)) * 3_600,
                    repeats: true
                ) { _ in
                    MainActor.assumeIsolated { self.checkForUpdates(manual: false) }
                }
            }
        }
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        updateTimer?.invalidate()
        updateTimer = nil
        shelf.stop()
        clipboard.stop()
        powerRuntime.stop()
        monitorHistorySampler.stop()
        agentExternalService?.stop()
        engine.stop()
    }

    private func tick() {
        guard engine.tick(nowMillis: AppRuntime.nowMillis()) else { return }
        powerRuntime.refresh()
        ticks += 1
        syncState()
        if ticks % Self.helperRefreshTicks == 0 {
            // 心跳里不等待：缓存立即返回，真实探测在后台执行。
            if let helperMonitor {
                helperMonitor.requestProbe()
            } else {
                Task { @MainActor in await refreshHelperStatus() }
            }
        }
    }

    // MARK: - 设置动作。

    func setEnabled(_ enabled: Bool) {
        if !updateConfigDraft({
            $0.enabled = enabled
            $0.power = Self.powerWithEnabled($0.power, enabled: enabled)
        }) {
            statusMessage = ContractCopy.copyToastError.text(for: language)
        }
    }

    private func agentSettingValue(for key: AgentSettingKey) -> AgentSettingValue? {
        switch key {
        case .appEnabled: .boolean(config.enabled)
        case .notificationsEnabled: .boolean(config.notificationsEnabled)
        case .updateChecksEnabled: .boolean(config.updateCheckEnabled)
        case .clipboardEnabled: .boolean(config.clipboardEnabled)
        case .powerEnabled: .boolean(config.power.enabled)
        case .batteryFloorPercent: .integer(Int(config.power.batteryFloorPercent))
        case .language: .string(languagePreference.agentValue)
        }
    }

    private func applyAgentSettingChange(
        key: AgentSettingKey,
        value: AgentSettingValue
    ) -> Bool {
        guard key.accepts(value) else { return false }
        switch (key, value) {
        case (.appEnabled, .boolean(let enabled)):
            setEnabled(enabled)
            return config.enabled == enabled
        case (.notificationsEnabled, .boolean(let enabled)):
            setNotifications(enabled)
            return config.notificationsEnabled == enabled
        case (.updateChecksEnabled, .boolean(let enabled)):
            setUpdateChecks(enabled)
            return config.updateCheckEnabled == enabled
        case (.clipboardEnabled, .boolean(let enabled)):
            setClipboardEnabled(enabled)
            return config.clipboardEnabled == enabled
        case (.powerEnabled, .boolean(let enabled)):
            setPowerEnabled(enabled)
            return config.power.enabled == enabled
        case (.batteryFloorPercent, .integer(let percent)):
            setPowerBatteryFloor(percent)
            return Int(config.power.batteryFloorPercent) == min(max(percent, 0), 95)
        case (.language, .string(let code)):
            guard let preference = AppLanguagePreference.parse(code) else { return false }
            setLanguagePreference(preference)
            return config.language == preference.rawValue
        default:
            return false
        }
    }

    func setLowBatterySleep(_ enabled: Bool) { write { $0.lowBatteryCapacitySleep = enabled } }

    /// `valid` 为假时不写配置。界面在输入不是数字时传假。
    func setLowBatteryCapacity(_ value: Int, valid: Bool) {
        guard valid else { return }
        write { $0.lowBatteryCapacity = Int32(min(max(value, 0), 100)) }
    }

    func setLowTimeRemaining(_ value: Int, valid: Bool) {
        guard valid else { return }
        write { $0.lowTimeRemainingMinutes = Int32(max(value, 0)) }
    }

    func setDisableIdleWhileCharging(_ enabled: Bool) {
        write { $0.disableIdleSleepInCharging = enabled }
    }

    func setPowerEnabled(_ enabled: Bool) {
        setEnabled(enabled)
    }

    func setPowerKeepAwakeOnAdapter(_ enabled: Bool) {
        updatePower { copyPower($0, keepAwakeOnAdapter: enabled) }
    }

    func setPowerKeepAwakeOnBattery(_ enabled: Bool) {
        updatePower { copyPower($0, keepAwakeOnBattery: enabled) }
    }

    func setPowerBatteryFloor(_ percent: Int) {
        let floor = min(max(percent, 0), 95)
        updatePower {
            copyPower(
                $0,
                batteryFloorPercent: Int32(floor),
                batteryFloorRecoveryPercent: Int32(min(floor + 5, 100))
            )
        }
    }

    func setPowerYieldOnLowPowerMode(_ enabled: Bool) {
        updatePower { copyPower($0, yieldOnLowPowerMode: enabled) }
    }

    func setPowerHeatGuard(_ enabled: Bool) {
        updatePower { copyPower($0, heatGuardEnabled: enabled) }
    }

    func setPowerClosedLidTimeCapMinutes(_ minutes: Int) {
        updatePower { copyPower($0, closedLidTimeCapMinutes: Int32(min(max(minutes, 30), 1_440))) }
    }

    func setClosedLidPowerPolicy(_ policy: ClosedLidPowerPolicy) {
        _ = applyClosedLidPolicy(policy)
    }

    func setDisplayClosedLidMode(_ mode: ClosedLidDisplayMode) {
        let policy = mode == .system
            ? .sleep
            : (closedLidPowerPolicy == .sleep ? .adapter : closedLidPowerPolicy)
        _ = applyClosedLidPolicy(policy, mode: mode)
    }

    func setDisplayPauseWithExternalDisplay(_ enabled: Bool) {
        _ = applyClosedLidPolicy(closedLidPowerPolicy, pauseWithExternalDisplay: enabled)
    }

    @discardableResult
    private func applyClosedLidPolicy(
        _ policy: ClosedLidPowerPolicy,
        mode requestedMode: ClosedLidDisplayMode? = nil,
        pauseWithExternalDisplay: Bool? = nil
    ) -> Bool {
        if policy != .sleep, powerRuntime.helperStatus != .match {
            statusMessage = ContractCopy.copyToastError.text(for: language)
            return false
        }
        if requestedMode == .blackScreenPipeline,
           (!powerRuntime.closedLidZeroBrightnessAvailability.isAvailable) {
            statusMessage = ContractCopy.copyToastError.text(for: language)
            return false
        }
        return updateConfigDraft { draft in
            let display = draft.display
                ?? DisplayConfig.companion.fromLegacy(
                    power: draft.power,
                    keepsAwakeOnAdapter: draft.disableLidSleepInCharging,
                    keepsAwakeOnBattery: draft.disableLidSleepOnBattery
                )
            let mode: ClosedLidDisplayMode
            if let requestedMode, requestedMode != .system {
                mode = requestedMode
            } else if policy == .sleep, requestedMode == nil {
                mode = display.closedLidDisplayMode
            } else if policy == .sleep {
                mode = .system
            } else if display.closedLidDisplayMode == .system {
                mode = powerRuntime.closedLidZeroBrightnessAvailability.isAvailable
                    ? .blackScreenPipeline
                    : .displayOff
            } else {
                mode = display.closedLidDisplayMode
            }
            draft.display = DisplayConfig(
                schemaVersion: display.schemaVersion,
                keepAwakeWhenLidClosed: policy.keepsAwake,
                closedLidPowerPolicy: policy,
                closedLidDisplayMode: mode,
                pauseWhenExternalDisplayConnected: pauseWithExternalDisplay
                    ?? display.pauseWhenExternalDisplayConnected
            )
            draft.disableLidSleepInCharging = policy.keepsAwakeOnAdapter
            draft.disableLidSleepOnBattery = policy.keepsAwakeOnBattery
            draft.lidSleepImmediateOnClose = true
            draft.power = copyPower(
                draft.power,
                allowClosedLid: policy.keepsAwake,
                pauseClosedLidWithExternalDisplay: pauseWithExternalDisplay
                    ?? display.pauseWhenExternalDisplayConnected,
                closedLidZeroBrightness: mode == .blackScreenPipeline
            )
        }
    }

    func openDisplaySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Displays-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func setDarkWakeAwareness(_ enabled: Bool) { write { $0.darkWakeAwarenessEnabled = enabled } }
    func setNotifications(_ enabled: Bool) { write { $0.notificationsEnabled = enabled } }
    func setUpdateChecks(_ enabled: Bool) {
        if !enabled { availableUpdate = nil }
        write { $0.updateCheckEnabled = enabled }
    }
    func setSleepMode(_ mode: Int32) { write { $0.hibernateMode = mode } }

    /// 设置语言偏好。跟随系统时写入空字符串，保持与旧版配置兼容。
    func setLanguagePreference(_ preference: AppLanguagePreference) {
        write { $0.language = preference.rawValue }
    }

    /// 直接选择受支持的界面语言。
    func changeLanguage(_ language: AppLanguage) {
        setLanguagePreference(AppLanguagePreference(language: language))
    }

    /// 剪切板记录的总开关。关掉时停止监听，并注销两个快捷键。
    func setClipboardEnabled(_ enabled: Bool) {
        write { $0.clipboardEnabled = enabled }
        clipboard.applyConfiguration()
    }

    /// 给一个动作换快捷键。写回配置之后立刻重新注册。
    func setClipboardHotKey(_ action: ClipboardHotKeyAction, to binding: String) {
        switch action {
        case .pasteStack: write { $0.clipboardPasteStackHotKey = binding }
        case .captureSelection: write { $0.clipboardCaptureHotKey = binding }
        }
        clipboard.reloadHotKeys()
    }

    /// 合盖后是否阻止睡眠。开关状态来自引擎，不是配置。
    func toggleLidSleep() {
        engine.setLidSleepAvailable(available: !appState.lidSleepAvailable)
        syncState()
    }

    /// 闲置时是否阻止睡眠。开关状态来自引擎的实际断言。
    func toggleIdleSleep() {
        engine.setIdleSleepAvailable(available: !appState.idleSleepAvailable)
        syncState()
    }

    func scheduleCancelIdle(seconds: Int64) { engine.scheduleCancelIdle(afterSeconds: seconds) }
    func scheduleCancelLid(seconds: Int64) { engine.scheduleCancelLid(afterSeconds: seconds) }
    func sleepNow() { engine.sleepNow() }
    func displaySleepNow() { engine.displaySleepNow() }

    func dismissWelcome() {
        welcomeVisible = false
        write { $0.firstRun = false }
    }

    func clearStatus() { statusMessage = nil }

    /// 退出应用。导航栏底部的退出按钮走这里。
    ///
    /// **警告：** 退出会停止全部规则，机器不再按配置自动睡眠。
    /// 按钮排在导航栏底部组最后一项，避免与设置按钮误点。
    ///
    /// 默认实现真的退出。测试注入假闭包，断言被调用即可，
    /// 不必真的结束测试宿主。
    var quitHandler: @MainActor () -> Void = { NSApp.terminate(nil) }

    func requestQuit() { quitHandler() }

    /// 清除配置。下次启动回到默认值。
    ///
    /// **警告：** 会删掉用户全部设置。界面必须先确认。
    func clearConfig() {
        if config.chargeLimitEnabled, helperStatus == .match, !restoreChargeLimit() {
            return
        }
        let defaults = ConfigStore.companion.defaults()
        configStore.save(config: defaults)
        config = defaults
        clipboardBridge.config = defaults
        _ = engine.updateConfig(newConfig: defaults)
        powerRuntime.updateConfig(
            defaults.power,
            displayConfig: defaults.display
                ?? DisplayConfig.companion.fromLegacy(
                    power: defaults.power,
                    keepsAwakeOnAdapter: defaults.disableLidSleepInCharging,
                    keepsAwakeOnBattery: defaults.disableLidSleepOnBattery
                ),
            sleepProtectionEnabled: defaults.enabled
        )
        reconcileChargeLimit()
        syncState()
        statusMessage = ContractCopy.copyDialogResetTitle.text(for: language)
    }

    // MARK: - helper

    func installHelper() {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            let installed = privileged.install()
            helperServiceState = helperServiceManager.state
            if helperServiceState == .requiresApproval {
                helperServiceManager.openSystemSettings()
            }
            await refreshHelperStatus(waitForMatch: installed)
            busy = false
            let success = helperStatus == .match
            if success {
                statusMessage = ContractCopy.copyOverviewHelperInstalled.text(for: language)
            } else if helperServiceState == .requiresApproval {
                statusMessage = ContractCopy.copyHelperServiceRequiresApproval.text(for: language)
            } else if case .error = helperServiceState {
                statusMessage = HelperServicePresentation.value(
                    helperServiceState,
                    language: language
                )
            } else {
                statusMessage = ContractCopy.copyDialogHelperUnavailableBody.text(for: language)
            }
            if success { dismissWelcome() }
        }
    }

    func uninstallHelper() {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            let removed = privileged.uninstall()
            helperServiceState = helperServiceManager.state
            helperStatus = .missing
            chargeLimitStatus = nil
            _ = engine.setLidSleepAvailable(available: true)
            powerRuntime.refreshHelperStatusNow()
            syncState()
            busy = false
            let entry = removed ? ContractCopy.copyOverviewHelperMissing : ContractCopy.copyToastError
            statusMessage = entry.text(for: language)
        }
    }

    /// 等 helper 起来。刚装完 launchd 还没把 socket 建好，立刻查会读到未安装。
    ///
    /// 最多等 5 秒，每 200 毫秒查询一次。
    private func refreshHelperStatus(waitForMatch: Bool = false) async {
        helperServiceState = helperServiceManager.state
        if let helperMonitor {
            var snapshot = await helperMonitor.probe(force: true)
            if waitForMatch && snapshot?.status != .match {
                let deadline = Date().addingTimeInterval(5)
                while Date() < deadline {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    snapshot = await helperMonitor.probe(force: true)
                    if snapshot?.status == .match { break }
                }
            }
            if let snapshot {
                applyHelperSnapshot(snapshot)
            }
            return
        }

        applyHelperStatus(privileged.status())
    }

    private func applyHelperSnapshot(_ snapshot: HelperStatusSnapshot) {
        applyHelperStatus(snapshot.status)
    }

    private func applyHelperStatus(_ status: HelperStatus) {
        let changed = helperStatus != status
        helperStatus = status
        if status != .match {
            chargeLimitStatus = nil
        }
        powerRuntime.refreshHelperStatusNow()
        guard changed else { return }
        syncState()
        if status == .match {
            _ = engine.updateConfig(newConfig: config)
            reconcileChargeLimit()
        }
    }

    func openHelperApproval() {
        helperServiceManager.openSystemSettings()
    }

    // MARK: - 充电上限

    func refreshChargeLimitStatus() {
        guard helperStatus == .match else {
            chargeLimitStatus = nil
            return
        }
        chargeLimitStatus = chargeLimitClient.chargeLimitStatus()
    }

    /// 详情浮层使用。把同步 socket 请求移出主线程。
    func refreshChargeLimitStatusInBackground() {
        guard helperStatus == .match else {
            chargeLimitStatus = nil
            return
        }
        let client = chargeLimitClient
        Task { @MainActor [weak self] in
            let status = await Task.detached { client.chargeLimitStatus() }.value
            guard !Task.isCancelled else { return }
            self?.chargeLimitStatus = status
        }
    }

    /// 设置上限并保存本机配置。helper 失败时不写配置。
    @discardableResult
    func applyChargeLimit(_ percent: Int, activeDischarge: Bool) -> Bool {
        guard helperStatus == .match else {
            statusMessage = ContractCopy.copyStatusItemHelperError.text(for: language)
            return false
        }
        guard chargeLimitClient.setChargeLimit(
            percent: percent,
            activeDischarge: activeDischarge
        ) else {
            _ = updateConfigDraft {
                $0.chargeLimitEnabled = false
                $0.chargeLimitActiveDischarge = false
            }
            statusMessage = ContractCopy.copyToastError.text(for: language)
            refreshChargeLimitStatus()
            return false
        }
        let saved = updateConfigDraft {
            $0.chargeLimitEnabled = true
            $0.chargeLimitPercent = Int32(percent)
            $0.chargeLimitActiveDischarge = activeDischarge
        }
        guard saved else {
            _ = chargeLimitClient.restoreChargeLimit()
            refreshChargeLimitStatus()
            return false
        }
        refreshChargeLimitStatus()
        return true
    }

    @discardableResult
    func applyChargeLimit(_ percent: Int) -> Bool {
        applyChargeLimit(percent, activeDischarge: false)
    }

    /// 恢复 macOS 系统策略。helper 恢复失败时保留配置。
    @discardableResult
    func restoreChargeLimit() -> Bool {
        guard helperStatus == .match else {
            statusMessage = ContractCopy.copyStatusItemHelperError.text(for: language)
            return false
        }
        guard chargeLimitClient.restoreChargeLimit() else {
            statusMessage = ContractCopy.copyToastError.text(for: language)
            refreshChargeLimitStatus()
            return false
        }
        _ = updateConfigDraft {
            $0.chargeLimitEnabled = false
            $0.chargeLimitActiveDischarge = false
        }
        refreshChargeLimitStatus()
        return true
    }

    /// 启动后让配置与 helper 状态对齐。
    private func reconcileChargeLimit() {
        guard helperStatus == .match else {
            chargeLimitStatus = nil
            return
        }
        let status = chargeLimitClient.chargeLimitStatus()
        chargeLimitStatus = status
        if config.chargeLimitEnabled {
            let desired = Int(config.chargeLimitPercent)
            let desiredActiveDischarge = config.chargeLimitActiveDischarge
            if status?.enabled != true ||
                status?.userLimitPercent != desired ||
                status?.activeDischargeEnabled != desiredActiveDischarge {
                if !chargeLimitClient.setChargeLimit(
                    percent: desired,
                    activeDischarge: desiredActiveDischarge
                ) {
                    _ = updateConfigDraft {
                        $0.chargeLimitEnabled = false
                        $0.chargeLimitActiveDischarge = false
                    }
                    statusMessage = ContractCopy.copyToastError.text(for: language)
                }
                chargeLimitStatus = chargeLimitClient.chargeLimitStatus()
            }
        } else if status?.enabled == true {
            _ = chargeLimitClient.restoreChargeLimit()
            chargeLimitStatus = chargeLimitClient.chargeLimitStatus()
        }
        powerRuntime.refreshHelperStatusNow()
    }

    private func lidPolicyAvailable() -> Bool {
        guard helperStatus == .match else {
            statusMessage = ContractCopy.copyStatusItemHelperError.text(for: language)
            return false
        }
        return true
    }

    // MARK: - 更新


    func refreshUpdaterStatus() {
        guard let generation = beginUpdaterRequest() else { return }
        updaterClient.getStatus { [weak self] result in
            Task { @MainActor in
                guard let self, self.updaterRequestGeneration == generation else { return }
                self.finishUpdaterRequest(generation: generation)
                switch result {
                case .success(let status):
                    self.updaterStatus = status
                    self.updaterUnavailable = false
                case .failure:
                    self.updaterStatus = nil
                    self.updaterUnavailable = true
                }
            }
        }
    }

    func setUpdaterAutomatic(_ enabled: Bool) {
        guard let generation = beginUpdaterRequest(timeout: updaterOperationTimeout) else { return }
        updaterClient.setAutomaticUpdates(enabled) { [weak self] result in
            Task { @MainActor in
                guard let self, self.updaterRequestGeneration == generation else { return }
                self.finishUpdaterRequest(generation: generation)
                switch result {
                case .success:
                    self.setUpdateChecks(enabled)
                    self.updaterUnavailable = false
                    self.refreshUpdaterStatus()
                case .failure:
                    self.updaterUnavailable = self.updaterStatus == nil
                    self.statusMessage = ContractCopy.copyToastError.text(for: self.language)
                }
            }
        }
    }

    func checkUpdaterNow() {
        guard let generation = beginUpdaterRequest(timeout: updaterOperationTimeout) else { return }
        updaterClient.checkNow { [weak self] result in
            Task { @MainActor in
                guard let self, self.updaterRequestGeneration == generation else { return }
                self.finishUpdaterRequest(generation: generation)
                switch result {
                case .success(let value):
                    self.updaterUnavailable = false
                    self.statusMessage = UpdaterSettingsPresentation.stateText(
                        value.state,
                        language: self.language
                    )
                    self.refreshUpdaterStatus()
                case .failure:
                    self.updaterStatus = nil
                    self.updaterUnavailable = true
                    self.statusMessage = ContractCopy.copyToastError.text(for: self.language)
                }
            }
        }
    }

    func installAvailableUpdate() {
        guard let generation = beginUpdaterRequest(timeout: updaterOperationTimeout) else { return }
        updaterClient.installAvailable { [weak self] result in
            Task { @MainActor in
                guard let self, self.updaterRequestGeneration == generation else { return }
                self.finishUpdaterRequest(generation: generation)
                switch result {
                case .success(let value):
                    self.updaterUnavailable = false
                    self.statusMessage = UpdaterSettingsPresentation.stateText(
                        value.state,
                        language: self.language
                    )
                    self.refreshUpdaterStatus()
                case .failure:
                    self.updaterUnavailable = true
                    self.statusMessage = ContractCopy.copyToastError.text(for: self.language)
                }
            }
        }
    }

    func restartAppForUpdate() {
        guard let generation = beginUpdaterRequest(timeout: updaterOperationTimeout) else { return }
        updaterClient.restartApp { [weak self] result in
            Task { @MainActor in
                guard let self, self.updaterRequestGeneration == generation else { return }
                self.finishUpdaterRequest(generation: generation)
                switch result {
                case .success(let value):
                    self.updaterUnavailable = false
                    self.statusMessage = UpdaterSettingsPresentation.stateText(
                        value.state,
                        language: self.language
                    )
                    self.refreshUpdaterStatus()
                case .failure:
                    self.updaterUnavailable = true
                    self.statusMessage = ContractCopy.copyToastError.text(for: self.language)
                }
            }
        }
    }

    private func beginUpdaterRequest(timeout requestedTimeout: TimeInterval? = nil) -> Int? {
        guard !updaterBusy else { return nil }
        updaterBusy = true
        updaterRequestGeneration += 1
        let generation = updaterRequestGeneration
        updaterTimeoutTask?.cancel()
        let timeout = max(requestedTimeout ?? updaterRequestTimeout, 0.1)
        updaterTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled,
                  let self,
                  self.updaterRequestGeneration == generation
            else { return }
            self.updaterClient.invalidate()
            self.finishUpdaterRequest(generation: generation)
            self.updaterStatus = nil
            self.updaterUnavailable = true
            self.statusMessage = ContractCopy.copyToastError.text(for: self.language)
        }
        return generation
    }

    private func finishUpdaterRequest(generation: Int) {
        guard updaterRequestGeneration == generation else { return }
        updaterTimeoutTask?.cancel()
        updaterTimeoutTask = nil
        updaterBusy = false
        updaterRequestGeneration += 1
    }

    func checkForUpdates(manual: Bool) {
#if DEBUG
        if !manual,
           ProcessInfo.processInfo.environment["COVIO_UPDATE_PREVIEW_VERSION"] != nil
        {
            return
        }
#endif
        let now = AppRuntime.nowEpochSeconds()
        if !manual && !UpdatePolicy.shouldCheck(config: config, nowEpochSeconds: now) { return }
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        Task { @MainActor in
            defer { isCheckingForUpdates = false }
            let release = await Self.fetchRelease(updateChecker).value
            write { $0.lastUpdateCheckEpochSeconds = now }
            guard let release else {
                if manual {
                    statusMessage = ContractCopy.copyToastError.text(for: language)
                }
                return
            }
            let update = UpdatePolicy.selectUpdate(
                candidate: release,
                currentVersion: CovioReleaseIdentity.APP_VERSION
            )
            availableUpdate = update
            if let update {
                notifier.notify(
                    title: ContractCopy.copyDialogUpdateTitle.text(for: language),
                    subtitle: "",
                    message: "\(update.version) · \(update.title)",
                    releaseUrl: update.releaseUrl
                )
                if manual, let url = URL(string: update.releaseUrl) {
                    NSWorkspace.shared.open(url)
                }
                statusMessage = "\(ContractCopy.copyDialogUpdateTitle.text(for: language)): \(update.version)"
            } else if manual {
                statusMessage = ContractCopy.copyHubUpdateUpToDate.text(for: language)
            }
        }
    }

    /// `UpdateChecker` 是同步的，放到后台线程跑，避免卡住主线程十秒。
    ///
    /// `UpdateChecker` 是 ObjC 协议，Swift 看不出实现能不能跨线程。
    /// 唯一的实现 `GithubUpdateChecker` 只持有不可变的 URL 与 URLSession，
    /// 两者都线程安全，所以用 `SendableBox` 显式声明。
    private static func fetchRelease(_ checker: UpdateChecker) async -> SendableBox<UpdateInfo?> {
        let boxedChecker = SendableBox(checker)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: SendableBox(boxedChecker.value.latestRelease()))
            }
        }
    }

    // MARK: - 日志

    func viewLog() {
        let path = logger.logFile()
        guard !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// 导出日志。把用户主目录替换成 `~`，导出的文件不泄露用户名。
    func exportLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Covio.log"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            let source = URL(fileURLWithPath: logger.logFile())
            let text = (try? String(contentsOf: source, encoding: .utf8)) ?? ""
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            try text.replacingOccurrences(of: home, with: "~")
                .write(to: target, atomically: true, encoding: .utf8)
            statusMessage = ContractCopy.copyToastSuccess.text(for: language)
        } catch {
            logger.warn(message: "Cannot export log", error: nil)
            statusMessage = ContractCopy.copyToastError.text(for: language)
        }
    }

    // MARK: - 内部

    /// 改一个配置字段并落盘。
    ///
    /// 引擎拒绝时回滚。拒绝的原因是当前状态下这条规则不成立，
    /// 例如 helper 不在却要接管合盖。
    private func write(_ change: (ConfigDraft) -> Void) {
        updateConfigDraft(change)
    }

    /// 改若干字段并落盘。返回引擎是否接受。
    @discardableResult
    private func updateConfigDraft(_ change: (ConfigDraft) -> Void) -> Bool {
        let draft = ConfigDraft(config)
        change(draft)
        return updateConfig(draft.build())
    }

    @discardableResult
    private func updateConfig(_ newConfig: AppConfig) -> Bool {
        let previous = config
        let candidate = newConfig.normalized()
        let draft = ConfigDraft(candidate)
        draft.power = Self.powerWithEnabled(candidate.power, enabled: candidate.enabled)
        let normalized = draft.build().normalized()
        config = normalized
        clipboardBridge.config = normalized
        configStore.save(config: normalized)
        let success = engine.updateConfig(newConfig: normalized)
        if !success {
            config = previous
            clipboardBridge.config = previous
            configStore.save(config: previous)
            _ = engine.updateConfig(newConfig: previous)
        }
        powerRuntime.updateConfig(
            config.power,
            displayConfig: displayConfig,
            sleepProtectionEnabled: config.enabled
        )
        syncState()
        return success
    }

    private func updatePower(_ change: (PowerConfig) -> PowerConfig) {
        write {
            $0.power = Self.powerWithEnabled(change($0.power).normalized(), enabled: $0.enabled)
        }
    }

    private static func powerWithEnabled(_ value: PowerConfig, enabled: Bool) -> PowerConfig {
        PowerConfig(
            enabled: enabled,
            keepAwakeOnAdapter: value.keepAwakeOnAdapter,
            keepAwakeOnBattery: value.keepAwakeOnBattery,
            allowClosedLid: value.allowClosedLid,
            pauseClosedLidWithExternalDisplay: value.pauseClosedLidWithExternalDisplay,
            batteryFloorPercent: value.batteryFloorPercent,
            batteryFloorRecoveryPercent: value.batteryFloorRecoveryPercent,
            yieldOnLowPowerMode: value.yieldOnLowPowerMode,
            heatGuardEnabled: value.heatGuardEnabled,
            closedLidTimeCapMinutes: value.closedLidTimeCapMinutes,
            closedLidZeroBrightness: value.closedLidZeroBrightness
        )
    }

    private func copyPower(
        _ value: PowerConfig,
        enabled: Bool? = nil,
        keepAwakeOnAdapter: Bool? = nil,
        keepAwakeOnBattery: Bool? = nil,
        allowClosedLid: Bool? = nil,
        pauseClosedLidWithExternalDisplay: Bool? = nil,
        batteryFloorPercent: Int32? = nil,
        batteryFloorRecoveryPercent: Int32? = nil,
        yieldOnLowPowerMode: Bool? = nil,
        heatGuardEnabled: Bool? = nil,
        closedLidTimeCapMinutes: Int32? = nil,
        closedLidZeroBrightness: Bool? = nil
    ) -> PowerConfig {
        PowerConfig(
            enabled: enabled ?? value.enabled,
            keepAwakeOnAdapter: keepAwakeOnAdapter ?? value.keepAwakeOnAdapter,
            keepAwakeOnBattery: keepAwakeOnBattery ?? value.keepAwakeOnBattery,
            allowClosedLid: allowClosedLid ?? value.allowClosedLid,
            pauseClosedLidWithExternalDisplay: pauseClosedLidWithExternalDisplay
                ?? value.pauseClosedLidWithExternalDisplay,
            batteryFloorPercent: batteryFloorPercent ?? value.batteryFloorPercent,
            batteryFloorRecoveryPercent: batteryFloorRecoveryPercent
                ?? value.batteryFloorRecoveryPercent,
            yieldOnLowPowerMode: yieldOnLowPowerMode ?? value.yieldOnLowPowerMode,
            heatGuardEnabled: heatGuardEnabled ?? value.heatGuardEnabled,
            closedLidTimeCapMinutes: closedLidTimeCapMinutes ?? value.closedLidTimeCapMinutes,
            closedLidZeroBrightness: closedLidZeroBrightness ?? value.closedLidZeroBrightness
        )
    }

    /// 把引擎状态读回来，并补上 helper 状态。
    private func syncState() {
        appState = engine.currentState.doCopy(
            battery: engine.currentState.battery,
            lid: engine.currentState.lid,
            enabled: engine.currentState.enabled,
            idleSleepAvailable: engine.currentState.idleSleepAvailable,
            idleSleepPrevention: engine.currentState.idleSleepPrevention,
            lidSleepAvailable: engine.currentState.lidSleepAvailable,
            idleCancelRemainingSeconds: engine.currentState.idleCancelRemainingSeconds,
            lidCancelRemainingSeconds: engine.currentState.lidCancelRemainingSeconds,
            darkWake: engine.currentState.darkWake,
            helperStatus: helperStatus,
            lidLeaseStatus: engine.currentState.lidLeaseStatus,
            lastError: engine.currentState.lastError
        )
    }

    /// 开机自启的真实状态以系统为准，不是配置。
    /// 用户在「系统设置」里改过之后，配置里的值就过时了。
    private func syncLoginItem() {
        let actual = loginItem.isEnabled()
        guard actual != config.launchAtLogin else { return }
        updateConfigDraft { $0.launchAtLogin = actual }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let applied = enabled ? loginItem.enable() : loginItem.disable()
        guard applied else {
            statusMessage = ContractCopy.copyToastError.text(for: language)
            return
        }
        write { $0.launchAtLogin = enabled }
    }

    /// 休眠模式的真实值以 `pmset` 为准。
    private func syncHibernateMode() {
        guard let actual = privileged.hibernateMode() else { return }
        guard actual.int32Value != config.hibernateMode?.int32Value else { return }
        write { $0.hibernateMode = actual }
    }

    /// 引擎启动前的状态。全默认，只有 `enabled` 来自配置。
    ///
    /// 桥接层不向 Swift 导出默认参数，所以这里要写全所有字段。
    static func initialState(enabled: Bool) -> AppState {
        AppState(
            battery: nil,
            lid: .unknown,
            enabled: enabled,
            idleSleepAvailable: true,
            idleSleepPrevention: .none,
            lidSleepAvailable: true,
            idleCancelRemainingSeconds: nil,
            lidCancelRemainingSeconds: nil,
            darkWake: DarkWakeStatus(
                available: false,
                scanning: false,
                lastAtEpochSeconds: nil,
                lastKind: nil,
                lastReason: nil,
                count24h: 0
            ),
            helperStatus: .missing,
            lidLeaseStatus: LidLeaseStatus(
                available: false,
                protocolVersion: nil,
                sleepDisabled: nil,
                covioOwned: nil,
                activeLeaseCount: 0,
                expiresAtEpochSeconds: nil,
                error: nil
            ),
            lastError: nil
        )
    }

    /// 当前毫秒时间戳。
    ///
    /// **必须是非隔离的。** 引擎的后台唤醒扫描线程会通过 `clock` 与
    /// `wakeCacheNowMillis` 调它。留在主 actor 上会在那边触发
    /// `dispatch_assert_queue` 断言，进程直接崩。
    nonisolated static func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
    nonisolated static func nowEpochSeconds() -> Int64 { Int64(Date().timeIntervalSince1970) }

    /// 实时电池文字。
    func batteryText() -> String {
        guard let battery = appState.battery else { return ContractCopy.copyStateEmpty.text(for: language) }
        let stateText: String
        switch battery.state {
        case .discharging: stateText = ContractCopy.copyTrayTooltipBattery.text(for: language)
        case .charging: stateText = ContractCopy.copyTrayTooltipCharging.text(for: language)
        // `AC` 是单位记号，不是文案，不进合同。
        case .charged, .acPower: stateText = "AC"
        default: stateText = ContractCopy.copyStateEmpty.text(for: language)
        }
        return "\(battery.percent)% · \(stateText)"
    }
}

/// `AppConfig` 的可变草稿。
///
/// 桥接模型在 Swift 里字段全只读，没有 `copy` 之外的改法。
/// 全部字段的 `doCopy` 写十遍会出错，所以集中到这里。
/// 加字段时只改这一处。
final class ConfigDraft {
    var schemaVersion: Int32
    var language: String
    var enabled: Bool
    var launchAtLogin: Bool
    var lowBatteryCapacitySleep: Bool
    var lowBatteryCapacity: Int32
    var lowTimeRemainingMinutes: Int32
    var disableIdleSleepInCharging: Bool
    var disableLidSleepInCharging: Bool
    var disableLidSleepOnBattery: Bool
    var darkWakeAwarenessEnabled: Bool
    var lidSleepImmediateOnClose: Bool
    var notificationsEnabled: Bool
    var updateCheckEnabled: Bool
    var updateCheckIntervalHours: Int32
    var lastUpdateCheckEpochSeconds: Int64
    var hibernateMode: Int32?
    var firstRun: Bool
    var clipboardEnabled: Bool
    var clipboardPasteStackHotKey: String
    var clipboardCaptureHotKey: String
    var power: PowerConfig
    var display: DisplayConfig?
    var chargeLimitEnabled: Bool
    var chargeLimitPercent: Int32
    var chargeLimitActiveDischarge: Bool
    var fileNaming: FileNamingPolicy

    init(_ config: AppConfig) {
        schemaVersion = config.schemaVersion
        language = config.language
        enabled = config.enabled
        launchAtLogin = config.launchAtLogin
        lowBatteryCapacitySleep = config.lowBatteryCapacitySleep
        lowBatteryCapacity = config.lowBatteryCapacity
        lowTimeRemainingMinutes = config.lowTimeRemainingMinutes
        disableIdleSleepInCharging = config.disableIdleSleepInCharging
        disableLidSleepInCharging = config.disableLidSleepInCharging
        disableLidSleepOnBattery = config.disableLidSleepOnBattery
        darkWakeAwarenessEnabled = config.darkWakeAwarenessEnabled
        lidSleepImmediateOnClose = config.lidSleepImmediateOnClose
        notificationsEnabled = config.notificationsEnabled
        updateCheckEnabled = config.updateCheckEnabled
        updateCheckIntervalHours = config.updateCheckIntervalHours
        lastUpdateCheckEpochSeconds = config.lastUpdateCheckEpochSeconds
        hibernateMode = config.hibernateMode
        firstRun = config.firstRun
        clipboardEnabled = config.clipboardEnabled
        clipboardPasteStackHotKey = config.clipboardPasteStackHotKey
        clipboardCaptureHotKey = config.clipboardCaptureHotKey
        power = config.power
        display = config.display
        chargeLimitEnabled = config.chargeLimitEnabled
        chargeLimitPercent = config.chargeLimitPercent
        chargeLimitActiveDischarge = config.chargeLimitActiveDischarge
        fileNaming = config.fileNaming
    }

    func build() -> AppConfig {
        AppConfig(
            schemaVersion: schemaVersion,
            language: language,
            enabled: enabled,
            launchAtLogin: launchAtLogin,
            lowBatteryCapacitySleep: lowBatteryCapacitySleep,
            lowBatteryCapacity: lowBatteryCapacity,
            lowTimeRemainingMinutes: lowTimeRemainingMinutes,
            disableIdleSleepInCharging: disableIdleSleepInCharging,
            disableLidSleepInCharging: disableLidSleepInCharging,
            disableLidSleepOnBattery: disableLidSleepOnBattery,
            darkWakeAwarenessEnabled: darkWakeAwarenessEnabled,
            lidSleepImmediateOnClose: lidSleepImmediateOnClose,
            notificationsEnabled: notificationsEnabled,
            updateCheckEnabled: updateCheckEnabled,
            updateCheckIntervalHours: updateCheckIntervalHours,
            lastUpdateCheckEpochSeconds: lastUpdateCheckEpochSeconds,
            hibernateMode: hibernateMode,
            firstRun: firstRun,
            shelfEnabled: false,
            screenshotInboxEnabled: false,
            shelfSoundsEnabled: false,
            clipboardEnabled: clipboardEnabled,
            clipboardPasteStackHotKey: clipboardPasteStackHotKey,
            clipboardCaptureHotKey: clipboardCaptureHotKey,
            power: power,
            display: display,
            chargeLimitEnabled: chargeLimitEnabled,
            chargeLimitPercent: chargeLimitPercent,
            chargeLimitActiveDischarge: chargeLimitActiveDischarge,
            fileNaming: fileNaming
        )
    }
}

/// 引擎状态的转发。
///
/// `StateListener` 在引擎线程上被调用，所以这里立刻跳回主线程。
/// 不跳的话 SwiftUI 会在后台线程改可观察属性。
private final class StateForwarder: NSObject, StateListener {
    /// 引擎启动前是 nil。运行时在 `init` 末尾挂上。
    ///
    /// 标 `@Sendable` 是为了能在 `onState` 里把它带进主线程队列。
    /// 闭包体只改主线程上的可观察属性，所以是安全的。
    var handler: (@MainActor @Sendable (AppState) -> Void)?

    func onState(state: AppState) {
        // 先取出闭包再跨线程。直接捕获 `self` 会让 Swift 认为整个转发器
        // 都跨了线程，而它只该带走这一个闭包。
        // 闭包自身标了 `@Sendable`，所以这是允许的。
        guard let handler else { return }
        let box = SendableBox(state)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { handler(box.value) }
        }
    }
}

/// 跨线程传一个桥接层的不可变对象。
///
/// 桥接模型在 Swift 中字段全只读，按约定跨线程传递是安全的。
/// Swift 看不到这一点。用它把这件事写在一处，
/// 而不是在每个调用点撒 `@unchecked Sendable`。
final class SendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) { self.value = value }
}

/// 通知开关的持有者。
///
/// `MacNotifier` 在构造时要一个读开关的闭包，而那个闭包必须先于 `self` 存在。
/// 所以开关放在这个独立对象里，运行时每次写配置时同步它。
final class NotificationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false

    var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue } }
    }
}

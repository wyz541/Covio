import XCTest
@testable import Covio

/// `AppRuntime` 的设置动作。
///
/// 每个动作都要落盘，所以每条用例都指向一个临时目录，
/// 断言既看内存里的 `config`，也看文件里的内容。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/ui/AppRuntime.kt`。
@MainActor
final class AppRuntimeTests: XCTestCase {
    private var directory: URL!
    private var runtime: AppRuntime!
    private var privileged: FakePrivilegedOps!
    private var powerObservation: FakePowerObservationSource!
    private var chargeLimitClient: FakeChargeLimitClient!
    private var loginItem: FakeLoginItem!
    private var notifier: FakeNotifier!
    private var updateChecker: FakeUpdateChecker!
    private var helperServiceManager: FakeHelperServiceManager!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // 停掉心跳。忘了停会让计时器在下一个用例里继续跑。
        runtime?.stop()
        runtime = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private var configFile: URL { directory.appendingPathComponent("config.json") }

    /// 建一个运行时。端口全用假的，不碰真实系统。
    ///
    /// `engineStarted` 为假时心跳不启动。只有需要 helper 状态的用例才启动它。
    ///
    /// helper 装没装要在构造前定好：`start()` 只在第一次调用时读状态，
    /// 之后再改假端口就晚了。
    @discardableResult
    private func makeRuntime(
        engineStarted: Bool = false,
        helperInstalled: Bool = false,
        helperStatus: HelperStatus? = nil,
        helperServiceState: HelperServiceState? = nil,
        updateRelease: UpdateInfo? = nil,
        brightnessBackend: FakeClosedLidBrightnessBackend = FakeClosedLidBrightnessBackend(brightness: 0.6)
    ) -> AppRuntime {
        privileged = FakePrivilegedOps()
        privileged.statusValue = helperStatus ?? (helperInstalled ? .match : .missing)
        powerObservation = FakePowerObservationSource()
        powerObservation = FakePowerObservationSource()
        chargeLimitClient = FakeChargeLimitClient()
        loginItem = FakeLoginItem()
        notifier = FakeNotifier()
        updateChecker = FakeUpdateChecker()
        updateChecker.release = updateRelease
        helperServiceManager = FakeHelperServiceManager(
            state: helperServiceState ?? (helperInstalled ? .enabled : .legacy)
        )
        let modelRoot = directory.appendingPathComponent("Models", isDirectory: true)
        let downloadsDirectory = modelRoot.appendingPathComponent("Downloads", isDirectory: true)
        let packagesDirectory = modelRoot.appendingPathComponent("Packages", isDirectory: true)
        let modelRegistry = LocalModelPackageRegistryStore(
            path: modelRoot.appendingPathComponent("registry.json")
        )
        let modelInstaller = LocalModelDownloader(
            downloadsDirectory: downloadsDirectory,
            packagesDirectory: packagesDirectory,
            registry: modelRegistry
        )
        let modelSetup = ModelSetupRuntime(
            installer: modelInstaller,
            registry: modelRegistry,
            statusStore: LocalModelDownloadStatusStore(
                roots: LocalModelDownloadRoots(
                    downloadsDirectory: downloadsDirectory,
                    packagesDirectory: packagesDirectory
                )
            ),
            packagesDirectory: packagesDirectory
        )
        let created = AppRuntime(
            logger: MemoryLogger(),
            configStore: ConfigStore.companion.create(path: configFile.path),
            power: FakePower(),
            lid: FakeLid(),
            idle: FakeIdle(),
            sleepController: FakeSleepController(),
            sleepWatcher: FakeSleepWatcher(),
            wakeLogReader: WakeLogStore(nil),
            privileged: privileged,
            helperServiceManager: helperServiceManager,
            chargeLimitClient: chargeLimitClient,
            loginItem: loginItem,
            notifier: notifier,
            updateChecker: updateChecker,
            powerObservation: powerObservation,
            powerHistoryStore: PowerHistoryStore.companion.create(
                path: directory.appendingPathComponent("power-history.json").path
            ),
            closedLidBrightnessBackend: brightnessBackend,
            closedLidBrightnessStore: FakeClosedLidBrightnessRecoveryStore(),
            shelf: makeShelf(),
            workspace: makeWorkspace(),
            modelSetup: modelSetup,
            agentHistoryStore: AgentHistoryStore(
                path: directory.appendingPathComponent("agent-history.sqlite3")
            ),
            monitorHistoryStore: MonitorHistoryStore(
                path: directory.appendingPathComponent("monitor-history.sqlite")
            ),
            monitorHistorySampler: NoopMonitorHistorySampler(),
            agentExternalPreferences: .disabled
        )
        runtime = created
        if engineStarted { created.start() }
        return created
    }

    func testStartupWithoutModelKeepsNonAIFeaturesAvailable() {
        let created = makeRuntime()

        XCTAssertNil(created.activeModelTier)
        XCTAssertEqual(created.modelSetup.preferredState.phase, .notInstalled)

        created.setLowBatteryCapacity(42, valid: true)

        XCTAssertEqual(created.config.lowBatteryCapacity, 42)
    }

    func testAgentUIActionsUseOnlyAllowlistedSettings() {
        let created = makeRuntime()

        let read = created.agentUIActions.readSetting("notifications.enabled")
        let unknown = created.agentUIActions.readSetting("system.anything")
        let changed = created.agentUIActions.requestSettingChange(
            "notifications.enabled",
            valueText: "false"
        )

        XCTAssertTrue(read.ok)
        XCTAssertTrue(changed.ok)
        XCTAssertFalse(created.config.notificationsEnabled)
        XCTAssertFalse(unknown.ok)
        XCTAssertEqual(unknown.errorCode, .invalidArguments)
    }

    /// 自动检查发现新版本后，工作台可读取版本号并显示更新入口。
    func testUpdateCheckPublishesTheAvailableVersion() async throws {
        let created = makeRuntime(
            updateRelease: UpdateInfo(
                version: "9.9.9",
                title: "Covio 9.9.9",
                releaseUrl: "https://example.com/covio",
                publishedAt: ""
            )
        )

        created.checkForUpdates(manual: false)

        for _ in 0..<100 where created.availableUpdate == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(created.availableUpdate?.version, "9.9.9")
        XCTAssertFalse(created.isCheckingForUpdates)

        created.setUpdateChecks(false)
        XCTAssertNil(created.availableUpdate, "关闭更新检查后，工作台不再显示旧入口")
    }

    /// 挂帘运行时。存储、系统偏好、监视器全指向临时目录或假实现。
    ///
    /// 不接替身的话，`start()` 会去动真实的 `~/Library/Application Support/Covio`，
    /// 还会监视用户的桌面。
    private func makeShelf() -> ShelfRuntime {
        let store = ShelfStoreClient(
            path: directory.appendingPathComponent("shelf.json").path
        )
        return ShelfRuntime(
            store: store,
            preferences: FakeLegacyScreenshotPreferences(),
            environment: ScreenshotLibraryEnvironment(
                screenshotDirectory: {
                    self.directory.appendingPathComponent("Screenshots", isDirectory: true)
                },
                now: { 0 }
            ),
            watcherFactory: FakeScreenshotWatcherFactory().factory
        )
    }

    /// 工作区运行时。索引指向临时目录，打开与显示都不动真实系统。
    ///
    /// 不接替身的话，构造时的一次清理会去动真实的 `~/Library/Application Support/Covio/Workspace`，
    /// 并删掉用户过期的内容。理由同 [makeShelf]。
    private func makeWorkspace() -> WorkspaceRuntime {
        var environment = WorkspaceEnvironment()
        environment.open = { _ in }
        environment.reveal = { _ in }
        return WorkspaceRuntime(
            client: WorkspaceStoreClient(directory: directory.path),
            environment: environment
        )
    }

    /// 读出落盘的 JSON。断言用。
    private func savedJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: configFile)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// 等一个异步动作收尾。`installHelper` 与 `uninstallHelper` 都开任务。
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - 首次启动

    /// 首次启动保留空语言码，空语言码表示跟随系统。
    func testFirstLaunchKeepsFollowingTheSystemLanguage() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: configFile.path))
        let created = makeRuntime()

        XCTAssertEqual(created.languagePreference, .system)
        XCTAssertEqual(created.language, CopyLocale.language)
        XCTAssertEqual(created.config.language, "")
        XCTAssertEqual(try savedJSON()["language"] as? String, "")
    }

    /// 首次启动显示欢迎页。用户关掉之后写回 `firstRun`。
    func testWelcomeIsDismissedOnlyOnce() throws {
        let created = makeRuntime()
        XCTAssertTrue(created.welcomeVisible)

        created.dismissWelcome()

        XCTAssertFalse(created.welcomeVisible)
        XCTAssertEqual(try savedJSON()["firstRun"] as? Bool, false)
    }

    func testExperimentalZeroBrightnessIsOnAndCanBeDisabled() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)

        XCTAssertTrue(created.config.power.closedLidZeroBrightness)

        created.setDisplayClosedLidMode(.displayOff)

        XCTAssertFalse(created.config.power.closedLidZeroBrightness)
        let power = try XCTUnwrap(savedJSON()["power"] as? [String: Any])
        XCTAssertEqual(power["closedLidZeroBrightness"] as? Bool, false)
        let display = try XCTUnwrap(savedJSON()["display"] as? [String: Any])
        XCTAssertEqual(display["closedLidDisplayMode"] as? String, "displayOff")
    }

    func testUnavailableExperimentalBrightnessCannotBeEnabled() {
        let unavailable = FakeClosedLidBrightnessBackend(brightness: 0.6)
        unavailable.availability = .unavailable("unmeasured macOS")
        let created = makeRuntime(
            engineStarted: true,
            helperInstalled: true,
            brightnessBackend: unavailable
        )
        created.setDisplayClosedLidMode(.displayOff)

        created.setDisplayClosedLidMode(.blackScreenPipeline)

        XCTAssertFalse(created.config.power.closedLidZeroBrightness)
    }

    // MARK: - 数值字段的边界

    /// 电池百分比夹在 0 到 100。
    func testLowBatteryCapacityIsClamped() throws {
        let created = makeRuntime()

        created.setLowBatteryCapacity(150, valid: true)
        XCTAssertEqual(created.config.lowBatteryCapacity, 100)
        XCTAssertEqual(try savedJSON()["lowBatteryCapacity"] as? Int, 100)

        created.setLowBatteryCapacity(-5, valid: true)
        XCTAssertEqual(created.config.lowBatteryCapacity, 0)

        created.setLowBatteryCapacity(20, valid: true)
        XCTAssertEqual(created.config.lowBatteryCapacity, 20)
    }

    /// 输入框内容不是数字时界面传 `valid: false`，此时配置不动。
    func testInvalidNumberIsIgnored() throws {
        let created = makeRuntime()
        created.setLowBatteryCapacity(30, valid: true)

        created.setLowBatteryCapacity(0, valid: false)
        created.setLowTimeRemaining(0, valid: false)

        XCTAssertEqual(created.config.lowBatteryCapacity, 30)
        XCTAssertEqual(created.config.lowTimeRemainingMinutes, 10)
    }

    /// 剩余分钟数只夹下界。
    func testLowTimeRemainingIsClampedAtZero() throws {
        let created = makeRuntime()

        created.setLowTimeRemaining(-30, valid: true)
        XCTAssertEqual(created.config.lowTimeRemainingMinutes, 0)

        created.setLowTimeRemaining(45, valid: true)
        XCTAssertEqual(created.config.lowTimeRemainingMinutes, 45)
        // 落盘的键名是 0.4.2 用的那个。
        XCTAssertEqual(try savedJSON()["lowTimeRemaining"] as? Int, 45)
    }

    // MARK: - 语言

    /// 换语言立刻落盘，界面文案跟着换。跟随系统写回空字符串。
    func testLanguageChangeIsPersisted() throws {
        let created = makeRuntime()

        created.setLanguagePreference(.simplifiedChinese)

        XCTAssertEqual(created.language, .simplifiedChinese)
        XCTAssertEqual(created.languagePreference, .simplifiedChinese)
        XCTAssertEqual(created.config.language, "zh-CN")
        XCTAssertEqual(try savedJSON()["language"] as? String, "zh-CN")

        created.setLanguagePreference(.english)
        XCTAssertEqual(created.language, .english)
        XCTAssertEqual(created.languagePreference, .english)
        XCTAssertEqual(try savedJSON()["language"] as? String, "en")

        created.setLanguagePreference(.system)
        XCTAssertEqual(created.language, CopyLocale.language)
        XCTAssertEqual(created.languagePreference, .system)
        XCTAssertEqual(created.config.language, "")
        XCTAssertEqual(try savedJSON()["language"] as? String, "")
    }

    // MARK: - 休眠模式

    /// 三种受支持的模式都写得进去。
    func testSupportedSleepModesAreAccepted() throws {
        let created = makeRuntime()

        for mode in [Int32(0), 3, 25] {
            created.setSleepMode(mode)
            XCTAssertEqual(created.config.hibernateMode?.int32Value, mode)
            XCTAssertEqual(try savedJSON()["hibernateMode"] as? Int, Int(mode))
        }
    }

    /// 不受支持的模式被 `normalized()` 丢掉，落盘的是空值。
    func testUnsupportedSleepModeIsDropped() throws {
        let created = makeRuntime()
        created.setSleepMode(3)

        created.setSleepMode(7)

        XCTAssertNil(created.config.hibernateMode)
        XCTAssertTrue(try savedJSON()["hibernateMode"] is NSNull)
    }

    // MARK: - 合盖策略与 helper

    /// helper 没装时不许启用自动合盖租约。
    func testClosedLidPolicyIsRefusedWithoutTheHelper() throws {
        let created = makeRuntime(engineStarted: true)
        XCTAssertEqual(created.helperStatus, .missing)

        created.setClosedLidPowerPolicy(.battery)

        XCTAssertEqual(created.closedLidPowerPolicy, .adapter)
        XCTAssertFalse(created.config.disableLidSleepOnBattery)
        XCTAssertNotNil(created.statusMessage, "拒绝时必须给用户一句话")
    }

    /// helper 在时策略可以写入，并同步旧字段供降级版本读取。
    func testClosedLidPolicyIsAcceptedWithTheHelper() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        XCTAssertEqual(created.helperStatus, .match)

        created.setClosedLidPowerPolicy(.battery)

        XCTAssertEqual(created.closedLidPowerPolicy, .battery)
        XCTAssertFalse(created.config.disableLidSleepInCharging)
        XCTAssertTrue(created.config.disableLidSleepOnBattery)
        let display = try XCTUnwrap(savedJSON()["display"] as? [String: Any])
        XCTAssertEqual(display["closedLidPowerPolicy"] as? String, "battery")
    }

    /// 关闭自动保持不需要 helper。用户总是能撤销一个已经生效的限制。
    func testClosedLidPolicyCanAlwaysReturnToSleep() throws {
        ConfigStore.companion.create(path: configFile.path).save(
            config: AppConfigs.make(
                display: DisplayConfig(
                    schemaVersion: 2,
                    keepAwakeWhenLidClosed: true,
                    closedLidPowerPolicy: .battery,
                    closedLidDisplayMode: .blackScreenPipeline,
                    pauseWhenExternalDisplayConnected: true
                )
            )
        )
        let created = makeRuntime(engineStarted: true)
        XCTAssertEqual(created.helperStatus, .missing)
        XCTAssertEqual(created.closedLidPowerPolicy, .battery)

        created.setClosedLidPowerPolicy(.sleep)

        XCTAssertEqual(created.closedLidPowerPolicy, .sleep)
        XCTAssertFalse(created.config.disableLidSleepInCharging)
        XCTAssertFalse(created.config.disableLidSleepOnBattery)
        XCTAssertTrue(created.config.lidSleepImmediateOnClose)
    }

    /// 闲置开关不经过 helper，直接写。
    func testIdleSwitchDoesNotNeedTheHelper() throws {
        let created = makeRuntime(engineStarted: true)

        created.setDisableIdleWhileCharging(true)

        XCTAssertTrue(created.config.disableIdleSleepInCharging)
        XCTAssertNil(created.statusMessage)
    }

    /// 闲置开关按真实断言状态切换，连续两次回到原状态。
    func testIdleToggleUsesTheActualAssertionState() {
        let created = makeRuntime(engineStarted: true)

        created.toggleIdleSleep()
        XCTAssertFalse(created.appState.idleSleepAvailable)
        XCTAssertEqual(created.appState.idleSleepPrevention, .system)

        created.toggleIdleSleep()
        XCTAssertTrue(created.appState.idleSleepAvailable)
        XCTAssertEqual(created.appState.idleSleepPrevention, .none)
    }

    /// 装 helper 成功后收起欢迎页，并给出成功提示。
    func testInstallHelperSucceeds() async throws {
        let created = makeRuntime(helperInstalled: true)

        created.installHelper()
        await waitUntil { !created.busy }

        XCTAssertEqual(created.helperStatus, .match)
        XCTAssertEqual(created.statusMessage, ContractCopy.copyOverviewHelperInstalled.text(for: created.language))
        XCTAssertFalse(created.welcomeVisible, "装好之后欢迎页要让位")
    }

    func testInstallHelperOpensApprovalAndKeepsSafeModeVisible() async throws {
        let created = makeRuntime(
            helperServiceState: .requiresApproval
        )
        privileged.installResult = false

        created.installHelper()
        await waitUntil { !created.busy }

        XCTAssertEqual(created.helperServiceState, .requiresApproval)
        XCTAssertEqual(
            created.statusMessage,
            ContractCopy.copyHelperServiceRequiresApproval.text(for: created.language)
        )
        XCTAssertTrue(helperServiceManager.didOpenSettings)
    }

    /// 卸载 helper 之后释放租约，但保留用户选择的策略。
    func testUninstallHelperClearsTheLidPolicy() async throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        created.setClosedLidPowerPolicy(.battery)
        XCTAssertEqual(created.closedLidPowerPolicy, .battery)

        created.uninstallHelper()
        await waitUntil { !created.busy }

        XCTAssertEqual(created.helperStatus, .missing)
        XCTAssertTrue(created.appState.lidSleepAvailable, "helper 走了就限制不住了，状态要如实反映")
        XCTAssertEqual(created.closedLidPowerPolicy, .battery)
    }

    /// Power 管理面的意图要同时更新内存、运行时和配置文件。
    func testPowerRulesArePersistedAndForwardedToTheRuntime() throws {
        let created = makeRuntime()

        created.setPowerKeepAwakeOnAdapter(false)
        created.setPowerBatteryFloor(30)
        created.setPowerClosedLidTimeCapMinutes(90)

        let saved = try XCTUnwrap(savedJSON()["power"] as? [String: Any])
        XCTAssertEqual(saved["keepAwakeOnAdapter"] as? Bool, false)
        XCTAssertEqual(saved["batteryFloorPercent"] as? Int, 30)
        XCTAssertEqual(saved["batteryFloorRecoveryPercent"] as? Int, 35)
        XCTAssertEqual(saved["closedLidTimeCapMinutes"] as? Int, 90)
        XCTAssertFalse(created.powerRuntime.config.keepAwakeOnAdapter)
        XCTAssertEqual(created.powerRuntime.config.batteryFloorPercent, 30)
        XCTAssertEqual(created.powerRuntime.config.closedLidTimeCapMinutes, 90)
    }

    func testDisplaySettingsArePersistedAndMirroredIntoPowerConfig() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)

        created.setDisplayClosedLidMode(.displayOff)
        created.setDisplayPauseWithExternalDisplay(false)
        created.setClosedLidPowerPolicy(.battery)

        XCTAssertTrue(created.displayConfig.keepAwakeWhenLidClosed)
        XCTAssertEqual(created.displayConfig.closedLidPowerPolicy, .battery)
        XCTAssertEqual(created.displayConfig.closedLidDisplayMode, .displayOff)
        XCTAssertFalse(created.displayConfig.pauseWhenExternalDisplayConnected)
        XCTAssertTrue(created.powerRuntime.config.allowClosedLid)
        XCTAssertFalse(created.powerRuntime.config.closedLidZeroBrightness)
        XCTAssertFalse(created.powerRuntime.config.pauseClosedLidWithExternalDisplay)

        var saved = try XCTUnwrap(savedJSON()["display"] as? [String: Any])
        XCTAssertEqual(saved["keepAwakeWhenLidClosed"] as? Bool, true)
        XCTAssertEqual(saved["closedLidPowerPolicy"] as? String, "battery")
        XCTAssertEqual(saved["closedLidDisplayMode"] as? String, "displayOff")
        XCTAssertEqual(saved["pauseWhenExternalDisplayConnected"] as? Bool, false)

        created.setClosedLidPowerPolicy(.sleep)
        XCTAssertFalse(created.displayConfig.keepAwakeWhenLidClosed)
        XCTAssertEqual(created.displayConfig.closedLidPowerPolicy, .sleep)
        XCTAssertEqual(created.displayConfig.closedLidDisplayMode, .displayOff)
        saved = try XCTUnwrap(savedJSON()["display"] as? [String: Any])
        XCTAssertEqual(saved["closedLidPowerPolicy"] as? String, "sleep")
        XCTAssertEqual(saved["closedLidDisplayMode"] as? String, "displayOff")
    }

    func testPowerEnableStateStaysAlignedWithSleepProtection() throws {
        let created = makeRuntime()

        created.setPowerEnabled(false)

        XCTAssertFalse(created.config.enabled)
        XCTAssertFalse(created.config.power.enabled)
        XCTAssertFalse(created.powerRuntime.sleepProtectionEnabled)
        var saved = try XCTUnwrap(savedJSON()["power"] as? [String: Any])
        XCTAssertEqual(try savedJSON()["enabled"] as? Bool, false)
        XCTAssertEqual(saved["enabled"] as? Bool, false)

        created.setEnabled(true)

        XCTAssertTrue(created.config.enabled)
        XCTAssertTrue(created.config.power.enabled)
        XCTAssertTrue(created.powerRuntime.sleepProtectionEnabled)
        saved = try XCTUnwrap(savedJSON()["power"] as? [String: Any])
        XCTAssertEqual(try savedJSON()["enabled"] as? Bool, true)
        XCTAssertEqual(saved["enabled"] as? Bool, true)
    }

    func testStartupAlignsLegacyPowerEnablementWithSleepProtection() throws {
        let draft = ConfigDraft(AppConfigs.defaults)
        draft.enabled = false
        ConfigStore.companion.create(path: configFile.path).save(config: draft.build())

        let created = makeRuntime()

        XCTAssertFalse(created.config.enabled)
        XCTAssertFalse(created.config.power.enabled)
        XCTAssertFalse(created.powerRuntime.sleepProtectionEnabled)
        let saved = try XCTUnwrap(savedJSON()["power"] as? [String: Any])
        XCTAssertEqual(saved["enabled"] as? Bool, false)
    }

    func testLidToggleUsesActualAvailability() {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        XCTAssertTrue(created.appState.lidSleepAvailable)

        created.toggleLidSleep()
        XCTAssertFalse(created.appState.lidSleepAvailable)

        created.toggleLidSleep()
        XCTAssertTrue(created.appState.lidSleepAvailable)
    }

    // MARK: - 充电上限

    func testDefaultConfigAppliesSeventyAtStartup() {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)

        XCTAssertTrue(created.config.chargeLimitEnabled)
        XCTAssertEqual(created.config.chargeLimitPercent, 70)
        XCTAssertEqual(chargeLimitClient.setValues, [70])
        XCTAssertEqual(chargeLimitClient.setActiveValues, [false])
    }

    func testApplyChargeLimitPersistsOnlyAfterHelperAccepts() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        chargeLimitClient.resetCalls()

        XCTAssertTrue(created.applyChargeLimit(85))

        XCTAssertEqual(chargeLimitClient.setValues, [85])
        XCTAssertTrue(created.config.chargeLimitEnabled)
        XCTAssertEqual(created.config.chargeLimitPercent, 85)
        XCTAssertEqual(try savedJSON()["chargeLimitEnabled"] as? Bool, true)
        XCTAssertEqual(try savedJSON()["chargeLimitPercent"] as? Int, 85)
    }

    func testChargeLimitWriteIsBlockedInHelperSafeMode() throws {
        let created = makeRuntime(engineStarted: true, helperStatus: .identityMismatch)

        XCTAssertEqual(created.helperStatus, .identityMismatch)
        XCTAssertFalse(created.applyChargeLimit(85))
        XCTAssertTrue(chargeLimitClient.setValues.isEmpty)
        XCTAssertTrue(created.config.chargeLimitEnabled)
        XCTAssertEqual(created.config.chargeLimitPercent, 70)
    }

    func testApplyChargeLimitPersistsActiveDischarge() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        chargeLimitClient.resetCalls()

        XCTAssertTrue(created.applyChargeLimit(70, activeDischarge: true))

        XCTAssertEqual(chargeLimitClient.setValues, [70])
        XCTAssertEqual(chargeLimitClient.setActiveValues, [true])
        XCTAssertTrue(created.config.chargeLimitActiveDischarge)
        XCTAssertEqual(try savedJSON()["chargeLimitActiveDischarge"] as? Bool, true)
    }

    func testRestoreChargeLimitClearsTheSavedIntent() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        chargeLimitClient.resetCalls()
        XCTAssertTrue(created.applyChargeLimit(70, activeDischarge: true))

        XCTAssertTrue(created.restoreChargeLimit())

        XCTAssertEqual(chargeLimitClient.restoreCalls, 1)
        XCTAssertFalse(created.config.chargeLimitEnabled)
        XCTAssertFalse(created.config.chargeLimitActiveDischarge)
    }

    func testFailedChargeLimitApplyDoesNotPersistTheIntent() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        chargeLimitClient.resetCalls()
        chargeLimitClient.setResult = false

        XCTAssertFalse(created.applyChargeLimit(85))

        XCTAssertFalse(created.config.chargeLimitEnabled)
        XCTAssertNotNil(created.statusMessage)
    }

    func testFailedChargeLimitChangeDisablesThePreviousIntent() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        chargeLimitClient.resetCalls()
        XCTAssertTrue(created.applyChargeLimit(70, activeDischarge: true))
        chargeLimitClient.setResult = false

        XCTAssertFalse(created.applyChargeLimit(90))

        XCTAssertFalse(created.config.chargeLimitEnabled)
        XCTAssertFalse(created.config.chargeLimitActiveDischarge)
        XCTAssertNotNil(created.statusMessage)
    }

    func testStartupDisablesAnIntentThatTheHelperRejects() throws {
        let store = ConfigStore.companion.create(path: configFile.path)
        let draft = ConfigDraft(store.load())
        draft.chargeLimitEnabled = true
        draft.chargeLimitPercent = 70
        store.save(config: draft.build())

        let created = makeRuntime(helperInstalled: true)
        chargeLimitClient.setResult = false
        created.start()

        XCTAssertFalse(created.config.chargeLimitEnabled)
        XCTAssertNotNil(created.statusMessage)
    }

    func testStartupReconcilesActiveDischargeWithTheHelper() throws {
        let store = ConfigStore.companion.create(path: configFile.path)
        let draft = ConfigDraft(store.load())
        draft.chargeLimitEnabled = true
        draft.chargeLimitPercent = 70
        draft.chargeLimitActiveDischarge = true
        store.save(config: draft.build())

        let created = makeRuntime(helperInstalled: true)
        chargeLimitClient.status = ChargeLimitHelperStatus(
            enabled: true,
            userLimitPercent: 70,
            targetPercent: 80,
            chargingLatch: false,
            phase: "aboveLimit",
            bypassEngaged: false,
            originalFeatureState: 1,
            originalLimitPercent: 80,
            originalOptimizedChargingEnabled: true,
            activeDischargeEnabled: false
        )
        created.start()

        XCTAssertEqual(chargeLimitClient.setActiveValues, [true])
        XCTAssertTrue(created.config.chargeLimitActiveDischarge)
    }

    // MARK: - 清除配置

    /// 清除配置会删掉用户全部设置，回到默认值。
    ///
    /// **警告：** 界面必须先确认。这里只测数据，测不了确认框。
    func testClearConfigRestoresDefaults() throws {
        let created = makeRuntime()
        created.setLowBatteryCapacity(42, valid: true)
        created.changeLanguage(.english)
        created.setSleepMode(25)

        created.clearConfig()

        let defaults = ConfigStore.companion.defaults()
        XCTAssertEqual(created.config.lowBatteryCapacity, defaults.lowBatteryCapacity)
        XCTAssertEqual(created.config.hibernateMode?.int32Value, defaults.hibernateMode?.int32Value)
        XCTAssertEqual(created.config.firstRun, defaults.firstRun)
        XCTAssertTrue(created.config.chargeLimitEnabled)
        XCTAssertEqual(created.config.chargeLimitPercent, 70)
        XCTAssertTrue(created.config.power.closedLidZeroBrightness)
        XCTAssertNotNil(created.statusMessage)
    }

    func testClearConfigRestoresAnActiveChargeLimitFirst() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        chargeLimitClient.resetCalls()
        XCTAssertTrue(created.applyChargeLimit(85))

        created.clearConfig()

        XCTAssertEqual(chargeLimitClient.restoreCalls, 1)
        XCTAssertEqual(chargeLimitClient.setValues, [85, 70])
        XCTAssertTrue(created.config.chargeLimitEnabled)
        XCTAssertEqual(created.config.chargeLimitPercent, 70)
    }

    func testFailedChargeLimitRestorePreventsClearingConfig() throws {
        let created = makeRuntime(engineStarted: true, helperInstalled: true)
        chargeLimitClient.resetCalls()
        XCTAssertTrue(created.applyChargeLimit(85))
        chargeLimitClient.restoreResult = false

        created.clearConfig()

        XCTAssertTrue(created.config.chargeLimitEnabled)
        XCTAssertEqual(created.config.chargeLimitPercent, 85)
        XCTAssertEqual(chargeLimitClient.restoreCalls, 1)
        XCTAssertNotNil(created.statusMessage)
    }

    // MARK: - 开关分组

    /// 剩下的开关逐条写进对应的键。
    func testRemainingSwitchesWriteTheirOwnKeys() throws {
        let created = makeRuntime()

        created.setEnabled(false)
        created.setLowBatterySleep(false)
        created.setDarkWakeAwareness(false)
        created.setNotifications(false)
        created.setUpdateChecks(false)

        let json = try savedJSON()
        XCTAssertEqual(json["enabled"] as? Bool, false)
        XCTAssertEqual(json["lowBatteryCapacitySleep"] as? Bool, false)
        XCTAssertEqual(json["darkWakeAwarenessEnabled"] as? Bool, false)
        XCTAssertEqual(json["lidSleepImmediateOnClose"] as? Bool, true)
        XCTAssertEqual(json["notificationsEnabled"] as? Bool, false)
        XCTAssertEqual(json["updateCheckEnabled"] as? Bool, false)
    }

    /// 提示语可以清掉。
    func testStatusMessageCanBeCleared() throws {
        let created = makeRuntime(engineStarted: true)
        created.setClosedLidPowerPolicy(.battery)
        XCTAssertNotNil(created.statusMessage)

        created.clearStatus()

        XCTAssertNil(created.statusMessage)
    }

    /// 退出走注入的闭包。
    ///
    /// 默认实现真的调 `NSApp.terminate`，测试里换成假闭包，
    /// 否则宿主应用会被结束，剩下的用例都跑不到。
    func testRequestQuitCallsTheInjectedHandler() throws {
        let created = makeRuntime()
        var quits = 0
        created.quitHandler = { quits += 1 }

        created.requestQuit()
        created.requestQuit()

        XCTAssertEqual(quits, 2)
    }
}

private final class FakeHelperServiceManager: HelperServiceManaging {
    var state: HelperServiceState
    var lastError: String?
    var hasRegisteredService: Bool { state == .enabled || state == .requiresApproval }
    var didOpenSettings = false

    init(state: HelperServiceState) {
        self.state = state
    }

    func register() throws {}

    func unregister() throws {
        state = .notRegistered
    }

    func openSystemSettings() {
        didOpenSettings = true
    }
}

private final class FakeChargeLimitClient: ChargeLimitClientProtocol, @unchecked Sendable {
    var status: ChargeLimitHelperStatus?
    var setResult = true
    var restoreResult = true
    var setValues: [Int] = []
    var setActiveValues: [Bool] = []
    var restoreCalls = 0

    func chargeLimitStatus() -> ChargeLimitHelperStatus? { status }

    func setChargeLimit(percent: Int, activeDischarge: Bool) -> Bool {
        setValues.append(percent)
        setActiveValues.append(activeDischarge)
        return setResult
    }

    func restoreChargeLimit() -> Bool {
        restoreCalls += 1
        return restoreResult
    }

    func resetCalls() {
        setValues.removeAll()
        setActiveValues.removeAll()
        restoreCalls = 0
    }
}

/// 假的登录项。开机自启要写 `~/Library/LaunchAgents`，测试不能碰。
final class FakeLoginItem: NSObject, LoginItem {
    var enabled = false

    func isEnabled() -> Bool { enabled }

    func enable() -> Bool {
        enabled = true
        return true
    }

    func disable() -> Bool {
        enabled = false
        return true
    }
}

/// 假的通知器。测试不能真的弹通知。
final class FakeNotifier: NSObject, Notifier {
    private(set) var notifications: [(title: String, message: String)] = []

    func notify(title: String, subtitle: String, message: String, releaseUrl: String?) {
        notifications.append((title: title, message: message))
    }
}

/// 假的更新检查器。不发网络请求。
final class FakeUpdateChecker: NSObject, UpdateChecker {
    var release: UpdateInfo?

    func latestRelease() -> UpdateInfo? { release }
}

@MainActor
private final class NoopMonitorHistorySampler: MonitorHistorySampling {
    func start() {}
    func stop() {}
}

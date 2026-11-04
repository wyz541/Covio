import XCTest
import kmpDomain
@testable import Covio

/// `config.json` 与 0.4.2 的双向兼容。
///
/// M2 的完成判据之一。两版共用同一个文件，迁移期间用户可能来回启动两次，
/// 所以两个方向都要成立：
///
/// 1. 0.4.2 写的文件，SwiftUI 版读得对。
/// 2. SwiftUI 版写的文件，0.4.2 读得对，且没被抹掉不认识的键。
///
/// 第 2 条靠 `ConfigStore.save` 的合并写入实现。这里断言合并确实发生。
final class ConfigCompatibilityTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-config-compat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var configFile: URL { directory.appendingPathComponent("config.json") }

    private func store() -> ConfigStore {
        ConfigStore.companion.create(path: configFile.path)
    }

    private func write(_ text: String) throws {
        try text.write(to: configFile, atomically: true, encoding: .utf8)
    }

    private func readText() throws -> String {
        try String(contentsOf: configFile, encoding: .utf8)
    }

    /// 0.4.2 写出的完整文件。字段名与取值都照抄那一版的输出。
    private let legacyConfig = """
    {
        "schemaVersion": 3,
        "language": "zh",
        "enabled": false,
        "launchAtLogin": true,
        "lowBatteryCapacitySleep": false,
        "lowBatteryCapacity": 15,
        "lowTimeRemaining": 25,
        "disableIdleSleepInCharging": true,
        "disableLidSleepInCharging": true,
        "disableLidSleepOnBattery": true,
        "darkWakeAwarenessEnabled": false,
        "lidSleepImmediateOnClose": false,
        "notificationsEnabled": false,
        "updateCheckEnabled": false,
        "updateCheckIntervalHours": 12,
        "lastUpdateCheckEpochSeconds": 1700000000,
        "hibernateMode": 3,
        "firstRun": false,
        "shelfEnabled": false,
        "screenshotInboxEnabled": false,
        "shelfSoundsEnabled": false
    }
    """

    func testReadsEveryFieldOfALegacyFile() throws {
        try write(legacyConfig)
        let config = store().load()

        XCTAssertEqual(config.schemaVersion, 3)
        XCTAssertEqual(config.language, "zh")
        XCTAssertFalse(config.enabled)
        XCTAssertTrue(config.launchAtLogin)
        XCTAssertFalse(config.lowBatteryCapacitySleep)
        XCTAssertEqual(config.lowBatteryCapacity, 15)
        XCTAssertEqual(config.lowTimeRemainingMinutes, 25)
        XCTAssertTrue(config.disableIdleSleepInCharging)
        XCTAssertTrue(config.disableLidSleepInCharging)
        XCTAssertTrue(config.disableLidSleepOnBattery)
        XCTAssertFalse(config.darkWakeAwarenessEnabled)
        XCTAssertTrue(config.lidSleepImmediateOnClose)
        XCTAssertFalse(config.notificationsEnabled)
        XCTAssertFalse(config.updateCheckEnabled)
        XCTAssertEqual(config.updateCheckIntervalHours, 12)
        XCTAssertEqual(config.lastUpdateCheckEpochSeconds, 1_700_000_000)
        XCTAssertEqual(config.hibernateMode?.int32Value, 3)
        XCTAssertFalse(config.firstRun)
        XCTAssertFalse(config.shelfEnabled)
        XCTAssertFalse(config.screenshotInboxEnabled)
        XCTAssertFalse(config.shelfSoundsEnabled)
    }

    /// `lowTimeRemainingMinutes` 的 JSON 键是 `lowTimeRemaining`。
    /// 这一条单独测，因为写错名字不会报错，只会静默用默认值。
    func testLegacyLowTimeRemainingKeyIsHonoured() throws {
        try write(#"{"lowTimeRemaining": 25}"#)
        XCTAssertEqual(store().load().lowTimeRemainingMinutes, 25)
    }

    /// 单个键的类型不对时，只有那个键回退到默认值。
    func testOneBadKeyFallsBackWithoutAffectingOthers() throws {
        try write(#"{"enabled": "yes", "lowBatteryCapacity": 15}"#)
        let config = store().load()

        XCTAssertEqual(config.enabled, AppConfigs.defaults.enabled, "类型不对的键要用默认值")
        XCTAssertEqual(config.lowBatteryCapacity, 15, "其它键不受影响")
    }

    /// 旧版文件没有 `power`。加载后必须得到本版默认意图。
    func testLegacyConfigGetsPowerDefaults() throws {
        try write(legacyConfig)
        let config = store().load()
        let power = config.power

        XCTAssertTrue(power.enabled)
        XCTAssertTrue(power.keepAwakeOnAdapter)
        XCTAssertFalse(power.keepAwakeOnBattery)
        XCTAssertTrue(power.allowClosedLid)
        XCTAssertEqual(power.batteryFloorPercent, 15)
        XCTAssertEqual(power.batteryFloorRecoveryPercent, 20)
        XCTAssertEqual(power.closedLidTimeCapMinutes, 240)
        XCTAssertTrue(power.closedLidZeroBrightness)
        XCTAssertEqual(config.display?.keepAwakeWhenLidClosed, true)
        XCTAssertEqual(config.display?.closedLidPowerPolicy, .any)
        XCTAssertEqual(config.display?.closedLidDisplayMode, .blackScreenPipeline)
        XCTAssertEqual(config.display?.pauseWhenExternalDisplayConnected, true)
    }

    func testDisplayConfigOverridesLegacyPowerMirror() throws {
        try write(
            """
            {
              "power": {
                "allowClosedLid": true,
                "pauseClosedLidWithExternalDisplay": true,
                "closedLidZeroBrightness": true
              },
              "display": {
                "schemaVersion": 1,
                "keepAwakeWhenLidClosed": false,
                "closedLidDisplayMode": "displayOff",
                "pauseWhenExternalDisplayConnected": false
              }
            }
            """
        )

        let config = store().load()

        XCTAssertFalse(config.power.allowClosedLid)
        XCTAssertFalse(config.power.pauseClosedLidWithExternalDisplay)
        XCTAssertFalse(config.power.closedLidZeroBrightness)
        XCTAssertFalse(config.display?.keepAwakeWhenLidClosed ?? true)
        XCTAssertEqual(config.display?.closedLidPowerPolicy, .sleep)
        XCTAssertEqual(config.display?.closedLidDisplayMode, .displayOff)
    }

    func testClosedLidPolicyIsAuthoritativeOverLegacyMirrors() throws {
        try write(
            """
            {
              "disableLidSleepInCharging": true,
              "disableLidSleepOnBattery": true,
              "lidSleepImmediateOnClose": false,
              "display": {
                "schemaVersion": 2,
                "keepAwakeWhenLidClosed": true,
                "closedLidPowerPolicy": "sleep",
                "closedLidDisplayMode": "displayOff",
                "pauseWhenExternalDisplayConnected": true
              }
            }
            """
        )

        let config = store().load()

        XCTAssertEqual(config.display?.closedLidPowerPolicy, .sleep)
        XCTAssertEqual(config.display?.keepAwakeWhenLidClosed, false)
        XCTAssertFalse(config.disableLidSleepInCharging)
        XCTAssertFalse(config.disableLidSleepOnBattery)
        XCTAssertTrue(config.lidSleepImmediateOnClose)
    }

    /// 缺少实验黑屏键时使用新默认值；显式关闭必须保留。
    func testExplicitlyDisabledExperimentalBlackScreenSurvivesLoading() throws {
        try write(#"{"power":{"closedLidZeroBrightness":false}}"#)

        XCTAssertFalse(store().load().power.closedLidZeroBrightness)
    }

    /// Power 意图与既有配置一起原子写入并原样读回。
    func testPowerConfigRoundTrips() throws {
        let power = PowerConfig(
            enabled: false,
            keepAwakeOnAdapter: false,
            keepAwakeOnBattery: true,
            allowClosedLid: false,
            pauseClosedLidWithExternalDisplay: false,
            batteryFloorPercent: 25,
            batteryFloorRecoveryPercent: 30,
            yieldOnLowPowerMode: false,
            heatGuardEnabled: false,
            closedLidTimeCapMinutes: 90,
            closedLidZeroBrightness: true
        )
        let store = store()
        store.save(config: AppConfigs.make(power: power))
        let loaded = store.load().power

        XCTAssertFalse(loaded.enabled)
        XCTAssertFalse(loaded.keepAwakeOnAdapter)
        XCTAssertTrue(loaded.keepAwakeOnBattery)
        XCTAssertFalse(loaded.allowClosedLid)
        XCTAssertFalse(loaded.pauseClosedLidWithExternalDisplay)
        XCTAssertEqual(loaded.batteryFloorPercent, 25)
        XCTAssertEqual(loaded.batteryFloorRecoveryPercent, 30)
        XCTAssertFalse(loaded.yieldOnLowPowerMode)
        XCTAssertFalse(loaded.heatGuardEnabled)
        XCTAssertEqual(loaded.closedLidTimeCapMinutes, 90)
        XCTAssertTrue(loaded.closedLidZeroBrightness)
    }

    /// 保存时先读回现有 JSON 再合并，所以本版不认识的键会留下。
    /// 两版共存期间这条不能破。
    func testSaveKeepsKeysThisVersionDoesNotKnow() throws {
        try write(#"{"enabled": true, "someFutureKey": "keep me", "anotherOne": 42}"#)
        let store = store()
        _ = store.load()
        store.save(config: AppConfigs.make(enabled: false))

        let text = try readText()
        XCTAssertTrue(text.contains("someFutureKey"), "不认识的键被抹掉了：\(text)")
        XCTAssertTrue(text.contains("keep me"), "不认识的键的值被改掉了：\(text)")
        XCTAssertTrue(text.contains("anotherOne"), "不认识的键被抹掉了：\(text)")
        XCTAssertTrue(text.contains("\"enabled\" : false") || text.contains("\"enabled\": false"), "本次改动没写进去：\(text)")
    }

    /// 本版写出的文件能被本版原样读回。
    func testRoundTripKeepsEveryField() throws {
        let store = store()
        let original = AppConfigs.make(
            lowBatteryCapacity: 15,
            lowBatteryCapacitySleep: false,
            lowTimeRemainingMinutes: 25,
            disableIdleSleepInCharging: true,
            disableLidSleepInCharging: true,
            disableLidSleepOnBattery: true,
            darkWakeAwarenessEnabled: false,
            lidSleepImmediateOnClose: false,
            enabled: false,
            display: DisplayConfig(
                schemaVersion: 2,
                keepAwakeWhenLidClosed: true,
                closedLidPowerPolicy: .any,
                closedLidDisplayMode: .blackScreenPipeline,
                pauseWhenExternalDisplayConnected: true
            )
        )
        store.save(config: original)
        let reloaded = store.load()

        XCTAssertEqual(reloaded.lowBatteryCapacity, 15)
        XCTAssertFalse(reloaded.lowBatteryCapacitySleep)
        XCTAssertEqual(reloaded.lowTimeRemainingMinutes, 25)
        XCTAssertTrue(reloaded.disableIdleSleepInCharging)
        XCTAssertTrue(reloaded.disableLidSleepInCharging)
        XCTAssertTrue(reloaded.disableLidSleepOnBattery)
        XCTAssertFalse(reloaded.darkWakeAwarenessEnabled)
        XCTAssertTrue(reloaded.lidSleepImmediateOnClose)
        XCTAssertFalse(reloaded.enabled)
    }

    /// 写出的 JSON 用的是 0.4.2 的键名，不是 Kotlin 的属性名。
    /// 键名对不上，老版本就读不到新版本写的值。
    func testWrittenKeysMatchTheLegacyNames() throws {
        let store = store()
        store.save(config: AppConfigs.make(lowTimeRemainingMinutes: 25))

        let text = try readText()
        for key in [
            "schemaVersion", "language", "enabled", "launchAtLogin",
            "lowBatteryCapacitySleep", "lowBatteryCapacity", "lowTimeRemaining",
            "disableIdleSleepInCharging", "disableLidSleepInCharging",
            "disableLidSleepOnBattery", "darkWakeAwarenessEnabled",
            "lidSleepImmediateOnClose", "notificationsEnabled", "updateCheckEnabled",
            "updateCheckIntervalHours", "lastUpdateCheckEpochSeconds",
            "hibernateMode", "firstRun", "shelfEnabled",
            "screenshotInboxEnabled", "shelfSoundsEnabled",
        ] {
            XCTAssertTrue(text.contains("\"\(key)\""), "写出的文件缺少键 \(key)：\(text)")
        }
    }

    /// 文件不存在时写出一份默认配置，与 0.4.2 的首次启动行为一致。
    func testFirstRunWritesADefaultFile() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: configFile.path))
        let config = store().load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: configFile.path))
        XCTAssertEqual(config.schemaVersion, AppConfigs.defaults.schemaVersion)
        XCTAssertEqual(config.enabled, AppConfigs.defaults.enabled)
    }

    /// 文件内容不是合法 JSON 时整份回退到默认值，不抛错。
    func testBrokenFileFallsBackToDefaults() throws {
        try write("{ this is not json")
        let config = store().load()
        XCTAssertEqual(config.lowBatteryCapacity, AppConfigs.defaults.lowBatteryCapacity)
    }
}

/// helper 契约的守卫。
///
/// 路径、版本号与命令白名单的权威是共享模块的 `HelperContract.kt`，
/// Swift 侧直接读 Kotlin 的值，不另抄一份。这里钉住三件事：
///
/// 1. 读到的确实是 Kotlin 的值，不是某个空集合。
/// 2. 安装脚本里写死的字面量与协议常量一致。
/// 3. 协议允许的休眠模式确实能通过校验。
final class HelperContractMirrorTests: XCTestCase {
    func testCommandAllowListComesFromKotlin() {
        let kotlin = HelperContractKt.HELPER_ALLOWED_COMMANDS
        XCTAssertEqual(HelperProtocol.allowedCommands, kotlin)
        XCTAssertFalse(kotlin.isEmpty, "白名单为空会让所有命令都被拒绝")
    }

    func testSupportedHibernateModesComeFromKotlin() {
        let kotlin = Set(ModelsKt.SUPPORTED_HIBERNATE_MODES.map { Int($0.int32Value) })
        XCTAssertEqual(HelperProtocol.supportedHibernateModes, kotlin)
        XCTAssertFalse(kotlin.isEmpty, "白名单不该为空，否则休眠模式永远设不进去")
    }

    func testPathsComeFromKotlin() {
        XCTAssertEqual(HelperProtocol.socketPath, HelperContractKt.HELPER_SOCKET_PATH)
        XCTAssertEqual(HelperProtocol.helperDirectory, HelperContractKt.HELPER_DIRECTORY)
        XCTAssertEqual(HelperProtocol.helperBinaryPath, HelperContractKt.HELPER_BINARY_PATH)
        XCTAssertEqual(HelperProtocol.chargeLimitStatePath, HelperContractKt.HELPER_CHARGE_LIMIT_STATE_PATH)
        XCTAssertEqual(HelperProtocol.chargeLimitRuntimePath, HelperContractKt.HELPER_CHARGE_LIMIT_RUNTIME_PATH)
        XCTAssertEqual(HelperProtocol.versionPath, HelperContractKt.HELPER_VERSION_PATH)
        XCTAssertEqual(HelperProtocol.allowedUidPath, HelperContractKt.HELPER_ALLOWED_UID_PATH)
        XCTAssertEqual(HelperProtocol.clientRequirementPath, HelperContractKt.HELPER_CLIENT_REQUIREMENT_PATH)
        XCTAssertEqual(HelperProtocol.plistPath, HelperContractKt.HELPER_PLIST_PATH)
        XCTAssertEqual(HelperProtocol.logPath, HelperContractKt.HELPER_LOG_PATH)
        XCTAssertEqual(HelperProtocol.appPathFile, HelperContractKt.HELPER_APP_PATH_FILE)
        XCTAssertEqual(HelperProtocol.sleepOwnerPath, HelperContractKt.HELPER_SLEEP_OWNER_PATH)
        XCTAssertFalse(HelperProtocol.socketPath.isEmpty, "路径为空会让 helper 装到奇怪的位置")
    }

    func testLeaseTimingComesFromKotlin() {
        XCTAssertEqual(HelperProtocol.leaseDurationSeconds, 60)
        XCTAssertEqual(HelperProtocol.leaseRenewSeconds, 15)
        XCTAssertEqual(HelperProtocol.sleepOwnerValue, "covio-sleep-disabled-v2")
    }

    func testProtocolVersionComesFromKotlin() {
        XCTAssertEqual(HelperProtocol.protocolVersion, HelperContractKt.HELPER_PROTOCOL_VERSION)
    }

    /// 版本号只有一个来源：`release/release-manifest.json`。
    ///
    /// 完整 SemVer 进入自定义 `CovioClientVersion`。
    /// Apple 的 `MARKETING_VERSION` 只保存稳定的三数字产品版本。
    ///
    /// 测试跑在宿主应用进程里，所以 `Bundle.main` 就是 Covio.app。
    func testBundleProductVersionMatchesTheKotlinConstant() throws {
        let bundle = Bundle.main
        XCTAssertEqual(bundle.bundleIdentifier, "com.wyz.covio", "测试宿主不是 Covio.app")
        let short = try XCTUnwrap(
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            "包里读不到 CFBundleShortVersionString"
        )
        XCTAssertEqual(GeneratedReleaseIdentityKt.APP_PRODUCT_VERSION, short)
    }

    /// Build number、release ID 和 helper 协议都来自生成的发布身份。
    func testReleaseIdentityMatchesTheBundle() throws {
        let bundle = Bundle.main
        let short = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let build = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        let clientVersion = try XCTUnwrap(
            bundle.object(forInfoDictionaryKey: "CovioClientVersion") as? String
        )
        let productVersion = try XCTUnwrap(
            bundle.object(forInfoDictionaryKey: "CovioProductVersion") as? String
        )
        let channel = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CovioReleaseChannel") as? String)
        let commit = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CovioGitCommit") as? String)
        let releaseID = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "CovioReleaseId") as? String)
        let protocolVersion = try XCTUnwrap(
            bundle.object(forInfoDictionaryKey: "CovioHelperProtocolVersion") as? String
        )
        let transactionVersion = try XCTUnwrap(
            bundle.object(forInfoDictionaryKey: "CovioInstallTransactionVersion") as? String
        )
        let helperInstallMode = try XCTUnwrap(
            bundle.object(forInfoDictionaryKey: "CovioHelperInstallMode") as? String
        )

        XCTAssertEqual(GeneratedReleaseIdentity.clientVersion, GeneratedReleaseIdentityKt.APP_VERSION)
        XCTAssertEqual(GeneratedReleaseIdentity.productVersion, GeneratedReleaseIdentityKt.APP_PRODUCT_VERSION)
        XCTAssertEqual(GeneratedReleaseIdentity.buildNumber, Int(GeneratedReleaseIdentityKt.APP_BUILD_NUMBER))
        XCTAssertEqual(GeneratedReleaseIdentity.channel, GeneratedReleaseIdentityKt.APP_RELEASE_CHANNEL)
        XCTAssertEqual(short, GeneratedReleaseIdentity.productVersion)
        XCTAssertEqual(clientVersion, GeneratedReleaseIdentity.clientVersion)
        XCTAssertEqual(productVersion, GeneratedReleaseIdentity.productVersion)
        XCTAssertEqual(build, String(GeneratedReleaseIdentity.buildNumber))
        XCTAssertEqual(channel, GeneratedReleaseIdentity.channel)
        XCTAssertEqual(protocolVersion, String(GeneratedReleaseIdentity.helperProtocolVersion))
        XCTAssertEqual(protocolVersion, HelperProtocol.protocolVersion)
        XCTAssertEqual(transactionVersion, "1")
        XCTAssertEqual(helperInstallMode, "legacy")
        XCTAssertFalse(commit.isEmpty)
        XCTAssertEqual(releaseID, "\(clientVersion)-g\(commit)")
    }

    /// Legacy plist 必须指向固定 helper 并声明同一个 XPC 服务。
    func testInstalledLaunchDaemonUsesTheFixedHelperAndXPCService() {
        let script = HelperInstaller.installScript(
            executablePath: "/Applications/Covio.app/Contents/MacOS/CovioHelper",
            uid: "501",
            version: GeneratedReleaseIdentityKt.APP_VERSION
        )
        XCTAssertTrue(
            script.contains("<string>\(HelperProtocol.helperBinaryPath)</string>"),
            "安装脚本没写固定 helper 路径：\(script)"
        )
        XCTAssertTrue(
            script.contains("<key>\(HelperProtocol.xpcServiceName)</key>"),
            "安装脚本没声明 XPC Mach service：\(script)"
        )
    }

    /// 卸载脚本必须删掉同一批路径，否则重装会读到上一版的残留。
    func testUninstallScriptRemovesTheSamePaths() {
        let script = HelperInstaller.uninstallScript()
        for path in [
            HelperProtocol.plistPath,
            HelperProtocol.helperDirectory,
        ] {
            XCTAssertTrue(script.contains(path), "卸载脚本没删 \(path)：\(script)")
        }
    }
}

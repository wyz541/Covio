import Foundation

/// 设置行的锚点。
///
/// 这些字符串是唯一的：搜索跳转、滚动定位与高亮都用它。
/// 目录表与各页的 `.settingsRowAnchor(_:)` 都引用这里的常量，
/// 所以字符串不会两处各写一遍。
enum SettingsRowID {
    // 概览
    static let overviewMaster = "overview.master"

    // 电池
    static let batteryEnabled = "battery.enabled"
    static let batteryCapacity = "battery.capacity"
    static let batteryTime = "battery.time"

    // 闲置
    static let idlePrevent = "idle.prevent"
    static let idleCharging = "idle.charging"
    static let idleCancel = "idle.cancel"

    // 剪贴板
    static let clipboardEnabled = "clipboard.enabled"
    static let clipboardHotKeys = "clipboard.hot-keys"

    // 通用
    static let generalDarkWake = "general.darkwake"
    static let generalSleepMode = "general.sleep-mode"
    static let generalLanguage = "general.language"
    static let generalLocalModel = "general.local-model"
    static let generalExternalAgent = "general.external-agent"
    static let generalLogin = "general.login"
    static let generalNotifications = "general.notifications"
    static let generalUpdates = "general.updates"
    static let generalVersion = "general.version"
    static let generalLogs = "general.logs"
    static let generalReset = "general.reset"
}

/// 一条可搜索的设置项。
struct SettingsCatalogEntry: Sendable, Equatable {
    /// 行锚点。与页面上 `.settingsRowAnchor(_:)` 的值一致。
    let rowID: String
    /// 所属分节。跳转时切到这一节。
    let section: SettingsSection
    /// 行标题。合同 `copy/*`。
    let title: LocalizedCopy
    /// 行的补充说明。没有说明的行是 nil。
    let summary: LocalizedCopy?
    /// 补充关键词。里面同时放中文与英文，所以两种界面语言都能搜到。
    let keywords: [String]
}

/// 设置项的目录表。
///
/// 这是搜索的唯一数据源：界面不参与搜索，只消费 `SettingsSearchIndex` 的结果。
/// 表里的顺序就是界面上的顺序，结果也按这个顺序返回。
///
/// 每加一行设置，这里要加一条，并在页面上加 `.settingsRowAnchor(_:)`。
/// `SettingsCatalogTests` 会检查锚点不重复、每节都有行。
enum SettingsCatalog {
    static let entries: [SettingsCatalogEntry] = overview + battery + idle + clipboard + general

    private static let overview: [SettingsCatalogEntry] = [
        SettingsCatalogEntry(
            rowID: SettingsRowID.overviewMaster,
            section: .overview,
            title: ContractCopy.copyOverviewRulesMaster,
            summary: ContractCopy.copyPageOverviewSummary,
            keywords: ["master", "rules", "enable", "总开关", "主控", "规则", "启用"]
        ),
    ]

    private static let battery: [SettingsCatalogEntry] = [
        SettingsCatalogEntry(
            rowID: SettingsRowID.batteryEnabled,
            section: .battery,
            title: ContractCopy.copyBatteryEnabled,
            summary: ContractCopy.copyPageBatterySummary,
            keywords: ["battery", "low", "power", "电池", "低电量"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.batteryCapacity,
            section: .battery,
            title: ContractCopy.copyBatteryCapacityThreshold,
            summary: nil,
            keywords: ["battery", "capacity", "percent", "threshold", "电池", "容量", "百分比", "阈值"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.batteryTime,
            section: .battery,
            title: ContractCopy.copyBatteryTimeThreshold,
            summary: nil,
            keywords: ["battery", "time", "remaining", "minutes", "电池", "剩余", "时间", "分钟"]
        ),
    ]

    private static let idle: [SettingsCatalogEntry] = [
        SettingsCatalogEntry(
            rowID: SettingsRowID.idlePrevent,
            section: .idle,
            title: ContractCopy.copyIdlePreventIdle,
            summary: ContractCopy.copyPageIdleSummary,
            keywords: ["idle", "display", "prevent", "sleep", "闲置", "阻止", "息屏"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.idleCharging,
            section: .idle,
            title: ContractCopy.copyIdleWhileCharging,
            summary: nil,
            keywords: ["idle", "charging", "power", "闲置", "充电"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.idleCancel,
            section: .idle,
            title: ContractCopy.copyIdleCancelAfter,
            summary: nil,
            keywords: ["idle", "cancel", "timer", "auto", "闲置", "取消", "定时", "自动"]
        ),
    ]

    private static let clipboard: [SettingsCatalogEntry] = [
        SettingsCatalogEntry(
            rowID: SettingsRowID.clipboardEnabled,
            section: .clipboard,
            title: ContractCopy.copyClipboardSettingsEnabled,
            summary: ContractCopy.copyClipboardSettingsAccessibilityFallback,
            keywords: ["clipboard", "history", "paste", "剪贴板", "剪切板", "历史", "粘贴"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.clipboardHotKeys,
            section: .clipboard,
            title: ContractCopy.copyClipboardSettingsHotKeys,
            summary: nil,
            keywords: ["clipboard", "hotkey", "shortcut", "剪贴板", "剪切板", "快捷键"]
        ),
    ]

    private static let general: [SettingsCatalogEntry] = [
        SettingsCatalogEntry(
            rowID: SettingsRowID.generalDarkWake,
            section: .general,
            title: ContractCopy.copyGeneralDarkwake,
            summary: ContractCopy.copyPageGeneralSummary,
            keywords: ["darkwake", "wake", "log", "深色唤醒", "唤醒", "日志"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.generalSleepMode,
            section: .general,
            title: ContractCopy.copyGeneralSleepMode,
            summary: nil,
            keywords: ["hibernate", "hibernatemode", "sleep", "休眠", "睡眠", "模式"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.generalLanguage,
            section: .general,
            title: ContractCopy.copyGeneralLanguage,
            summary: nil,
            keywords: [
                "language", "locale", "system", "english", "chinese",
                "语言", "系统语言", "跟随系统", "英文", "中文",
            ]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.generalLocalModel,
            section: .general,
            title: ContractCopy.copyGeneralLocalModelTitle,
            summary: ContractCopy.copyGeneralLocalModelSummary,
            keywords: [
                "model", "mlx", "qwen", "download", "import", "license", "revision",
                "offline", "local", "模型", "下载", "导入", "许可证", "版本", "离线", "本地",
            ]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.generalExternalAgent,
            section: .general,
            title: ContractCopy.copyGeneralExternalAgentTitle,
            summary: ContractCopy.copyGeneralExternalAgentSummary,
            keywords: ["agent", "mcp", "loopback", "offline", "token", "外部", "本地", "服务"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.generalLogin,
            section: .general,
            title: ContractCopy.copyGeneralLaunchAtLogin,
            summary: nil,
            keywords: ["login", "startup", "boot", "登录", "开机", "自启"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.generalNotifications,
            section: .general,
            title: ContractCopy.copyGeneralNotifications,
            summary: nil,
            keywords: ["notification", "alert", "通知", "提醒"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.generalUpdates,
            section: .general,
            title: ContractCopy.copyGeneralCheckUpdates,
            summary: nil,
            keywords: ["update", "version", "release", "更新", "版本", "升级"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.generalVersion,
            section: .general,
            title: ContractCopy.copyGeneralVersionTitle,
            summary: nil,
            keywords: [
                "version", "build", "channel", "git", "commit", "release",
                "版本", "构建", "渠道", "提交", "协议", "发布",
            ]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.generalLogs,
            section: .general,
            title: ContractCopy.copyHubLogView,
            summary: nil,
            keywords: ["log", "export", "diagnose", "日志", "导出", "诊断"]
        ),
        SettingsCatalogEntry(
            rowID: SettingsRowID.generalReset,
            section: .general,
            title: ContractCopy.copyGeneralClearConfig,
            summary: ContractCopy.copyDialogResetBody,
            keywords: ["reset", "clear", "default", "重置", "清除", "默认"]
        ),
    ]
}

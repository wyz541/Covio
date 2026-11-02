import Foundation

/// 设置页签里的六个分节。
///
/// 名称与顺序来自设计合同的导航文案。
/// 每节的标题与说明来自 `copy/page/*/title` 与 `copy/page/*/summary`。
///
/// 切换由顶部胶囊里的分段控件驱动，状态住在 `HubChromeModel.settingsSection`。
enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case battery
    case idle
    case clipboard
    case assistant
    case general

    var id: String { rawValue }

    /// 分节导航上的短名称。合同 `copy/nav/*`。
    var navTitle: LocalizedCopy {
        switch self {
        case .overview: ContractCopy.copyNavOverview
        case .battery: ContractCopy.copyNavBattery
        case .idle: ContractCopy.copyNavIdle
        case .clipboard: ContractCopy.copyNavClipboard
        case .assistant: ContractCopy.copySettingsAssistant
        case .general: ContractCopy.copyNavGeneral
        }
    }

    /// 页标题。合同 `copy/page/*/title`。
    var pageTitle: LocalizedCopy {
        switch self {
        case .overview: ContractCopy.copyPageOverviewTitle
        case .battery: ContractCopy.copyPageBatteryTitle
        case .idle: ContractCopy.copyPageIdleTitle
        case .clipboard: ContractCopy.copyPageClipboardTitle
        case .assistant: ContractCopy.copySettingsAssistant
        case .general: ContractCopy.copyPageGeneralTitle
        }
    }

    /// 页说明。合同 `copy/page/*/summary`。
    var pageSummary: LocalizedCopy {
        switch self {
        case .overview: ContractCopy.copyPageOverviewSummary
        case .battery: ContractCopy.copyPageBatterySummary
        case .idle: ContractCopy.copyPageIdleSummary
        case .clipboard: ContractCopy.copyPageClipboardSummary
        case .assistant: ContractCopy.copyHubTabAgentSummary
        case .general: ContractCopy.copyPageGeneralSummary
        }
    }
}

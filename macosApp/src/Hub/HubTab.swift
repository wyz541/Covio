import Foundation

/// 工作区页面的种类。
///
/// 模型那一侧的种类是 Kotlin 的 `PaneKind`。它在 Swift 里是一个类，不能穷举 switch，
/// 所以宿主镜像一个同形的枚举，两边靠 `rawValue`（等于 `PaneKind.key`）互转。
///
/// 文案键与顺序由 `DesignContractTests` 守住。
enum HubTab: String, CaseIterable, Sendable {
    case now
    case agent
    case clipboard
    case files
    case devices
    case settings
    /// 用户自建的工作区。没有模块页面，只显示组件网格。
    case board

    init(kind: PaneKind) {
        self = HubTab(rawValue: kind.key) ?? .board
    }

    var paneKind: PaneKind {
        switch self {
        case .now: PaneKind.now
        case .agent: PaneKind.agent
        case .clipboard: PaneKind.clipboard
        case .files: PaneKind.files
        case .devices: PaneKind.devices
        case .settings: PaneKind.settings
        case .board: PaneKind.board
        }
    }

    /// 页签标题。用户改过名的工作区用配置里的名字，不用这一条。
    var title: LocalizedCopy {
        switch self {
        case .now: ContractCopy.copyHubTabNow
        case .agent: ContractCopy.copyHubTabAgent
        case .clipboard: ContractCopy.copyHubTabClipboard
        case .files: ContractCopy.copyHubTabFiles
        case .devices: ContractCopy.copyHubTabDevices
        case .settings: ContractCopy.copyHubTabSettings
        case .board: ContractCopy.copyHubTabBoard
        }
    }

    /// 页签的无障碍提示。标题提供页面名称，提示补充页面内容。
    var summary: LocalizedCopy {
        switch self {
        case .now: ContractCopy.copyHubTabNowSummary
        case .agent: ContractCopy.copyHubTabAgentSummary
        case .clipboard: ContractCopy.copyHubTabClipboardSummary
        case .files: ContractCopy.copyHubTabFilesSummary
        case .devices: ContractCopy.copyHubTabDevicesSummary
        case .settings: ContractCopy.copyHubTabSettingsSummary
        case .board: ContractCopy.copyHubTabBoardSummary
        }
    }

    /// 工作区是否需要内容区顶部的操作行。
    var hasInlineActions: Bool {
        switch self {
        case .agent: true
        case .now, .clipboard, .files, .devices, .settings, .board: false
        }
    }

    /// 页签上的图标。
    ///
    /// 用字符而不是 SF Symbol。模型里 `PaneInstance.icon` 存的就是一个字符，
    /// 打样的图标选择器给的也是字符，两边的取值必须一致。
    var glyph: String {
        switch self {
        case .now: "◉"
        case .agent: "✦"
        case .clipboard: "▤"
        case .files: "▢"
        case .devices: "▭"
        case .settings: "⚙"
        case .board: "◇"
        }
    }
}

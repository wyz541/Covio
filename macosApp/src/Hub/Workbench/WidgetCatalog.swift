import Foundation

/// 内置组件的种类。
///
/// 模型里的 `WidgetInstance.kind` 是字符串：组件目录还没定，枚举会逼着模型
/// 提前认识每一种组件。宿主这一侧给内置的六种一个枚举，目录表才能穷举。
/// 认不出的种类走 `WidgetCatalog.descriptor(for:)` 的兜底分支，卡片不丢。
enum WidgetKind: String, CaseIterable, Sendable {
    case clock = "w-clock"
    case battery = "w-battery"
    case transfer = "w-transfer"
    case actions = "w-actions"
    case shots = "w-shots"
    case devices = "w-devices"
}

/// 目录里的一条。
struct WidgetDescriptor: Equatable {
    /// 卡片第一行。认不出的种类直接用种类名。
    let title: String
    /// 卡片底色。取自合同 `token/color/widget-tint-*`。
    let tint: ContractColor
}

/// 组件目录。
///
/// 照 `SettingsCatalog` 的写法：一张声明式的表，取值全部来自合同。
enum WidgetCatalog {
    /// 一块组件在界面上要显示的东西。
    static func descriptor(for kind: String, language: AppLanguage) -> WidgetDescriptor {
        guard let known = WidgetKind(rawValue: kind) else {
            // 认不出的种类也要显示。丢掉就丢了用户排好的位置。
            return WidgetDescriptor(title: kind, tint: ContractColors.tokenColorSurface)
        }
        return WidgetDescriptor(
            title: title(for: known).text(for: language),
            tint: tint(for: known)
        )
    }

    static func title(for kind: WidgetKind) -> LocalizedCopy {
        switch kind {
        case .clock: ContractCopy.copyHubWidgetClockTitle
        case .battery: ContractCopy.copyHubWidgetBatteryTitle
        case .transfer: ContractCopy.copyHubWidgetTransferTitle
        case .actions: ContractCopy.copyHubWidgetActionsTitle
        case .shots: ContractCopy.copyHubWidgetShotsTitle
        case .devices: ContractCopy.copyHubWidgetDevicesTitle
        }
    }

    static func tint(for kind: WidgetKind) -> ContractColor {
        switch kind {
        case .clock: ContractColors.tokenColorWidgetTintAmber
        case .battery: ContractColors.tokenColorWidgetTintMint
        case .transfer: ContractColors.tokenColorWidgetTintSky
        case .actions: ContractColors.tokenColorWidgetTintApricot
        case .shots: ContractColors.tokenColorWidgetTintRose
        case .devices: ContractColors.tokenColorWidgetTintSlate
        }
    }

    /// 尺寸档位标签。合同 `copy/hub/widget/size/<键>`。
    static func sizeLabel(_ size: WidgetSize) -> LocalizedCopy {
        switch size.key {
        case "wide": ContractCopy.copyHubWidgetSizeWide
        case "tall": ContractCopy.copyHubWidgetSizeTall
        case "large": ContractCopy.copyHubWidgetSizeLarge
        default: ContractCopy.copyHubWidgetSizeSmall
        }
    }
}

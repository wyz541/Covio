// 本文件由 scripts/generate-contract-constants.py 生成。不要手改。
// 权威是 docs/covio-design-contract.json。
// 改合同后重跑脚本：python3 scripts/generate-contract-constants.py

import CoreGraphics
import Foundation

/// 设计合同里的一枚颜色令牌。
///
/// 值是合同里的十六进制字符串，浅色与深色各一份。
/// `MacTheme` 负责把它转成随外观变化的颜色。
struct ContractColor: Sendable, Equatable {
    let key: String
    let lightHex: String
    let darkHex: String
}

/// 设计合同 `tokens` 段里的颜色。`token/art/*` 是插图用的装饰色，不在这里。
enum ContractColors {
    /// `token/color/accent-system` — System emphasis color for controls, selection, and focus rings.
    static let tokenColorAccentSystem = ContractColor(key: "token/color/accent-system", lightHex: "#007AFF", darkHex: "#0A84FF")
    /// `token/color/action-fill` — System action fill, focus ring, and active icon fill.
    static let tokenColorActionFill = ContractColor(key: "token/color/action-fill", lightHex: "#0A84FF", darkHex: "#0A84FF")
    /// `token/color/action-text` — Action text, links, and small action labels.
    static let tokenColorActionText = ContractColor(key: "token/color/action-text", lightHex: "#0066CC", darkHex: "#4DA3FF")
    /// `token/color/brand` — Covio brand fill and selected emphasis.
    static let tokenColorBrand = ContractColor(key: "token/color/brand", lightHex: "#4656A4", darkHex: "#4656A4")
    /// `token/color/brand-hover` — Brand hover feedback.
    static let tokenColorBrandHover = ContractColor(key: "token/color/brand-hover", lightHex: "#3B4A93", darkHex: "#5966A8")
    /// `token/color/brand-pressed` — Brand pressed feedback.
    static let tokenColorBrandPressed = ContractColor(key: "token/color/brand-pressed", lightHex: "#2E3A75", darkHex: "#23304D")
    /// `token/color/canvas` — Default page canvas.
    static let tokenColorCanvas = ContractColor(key: "token/color/canvas", lightHex: "#F2F2F7", darkHex: "#1C1C1E")
    /// `token/color/control-fill` — Default native control fill.
    static let tokenColorControlFill = ContractColor(key: "token/color/control-fill", lightHex: "#FFFFFF", darkHex: "#3A3A3C")
    /// `token/color/control-fill-hover` — Hovered native control fill.
    static let tokenColorControlFillHover = ContractColor(key: "token/color/control-fill-hover", lightHex: "#F0F0F2", darkHex: "#48484A")
    /// `token/color/control-fill-pressed` — Pressed native control fill.
    static let tokenColorControlFillPressed = ContractColor(key: "token/color/control-fill-pressed", lightHex: "#E5E5EA", darkHex: "#545456")
    /// `token/color/disabled-text` — Inactive control text and nonessential disabled labels.
    static let tokenColorDisabledText = ContractColor(key: "token/color/disabled-text", lightHex: "#98989D", darkHex: "#98989D")
    /// `token/color/divider` — Separators, control borders, and subtle outlines.
    static let tokenColorDivider = ContractColor(key: "token/color/divider", lightHex: "#D1D1D6", darkHex: "#3A3A3C")
    /// `token/color/elevated` — Elevated neutral surfaces and grouped controls.
    static let tokenColorElevated = ContractColor(key: "token/color/elevated", lightHex: "#F7F7F9", darkHex: "#3A3A3C")
    /// `token/color/error-bg` — Subtle error background.
    static let tokenColorErrorBg = ContractColor(key: "token/color/error-bg", lightHex: "#FFF0F1", darkHex: "#3E151A")
    /// `token/color/error-fill` — Error fill and error icon foreground.
    static let tokenColorErrorFill = ContractColor(key: "token/color/error-fill", lightHex: "#D70015", darkHex: "#D70015")
    /// `token/color/error-text` — Error text.
    static let tokenColorErrorText = ContractColor(key: "token/color/error-text", lightHex: "#D70015", darkHex: "#FF6961")
    /// `token/color/focus-ring` — Keyboard focus ring color.
    static let tokenColorFocusRing = ContractColor(key: "token/color/focus-ring", lightHex: "#007AFF", darkHex: "#0A84FF")
    /// `token/color/info-bg` — Informational background.
    static let tokenColorInfoBg = ContractColor(key: "token/color/info-bg", lightHex: "#EEF5FF", darkHex: "#102743")
    /// `token/color/material-medium` — Medium light and dark material fill.
    static let tokenColorMaterialMedium = ContractColor(key: "token/color/material-medium", lightHex: "#FFFFFFC7", darkHex: "#1C1C1E94")
    /// `token/color/material-thick` — Thick light and dark material fill.
    static let tokenColorMaterialThick = ContractColor(key: "token/color/material-thick", lightHex: "#FFFFFFDB", darkHex: "#1C1C1EAD")
    /// `token/color/material-thin` — Thin light and dark material fill.
    static let tokenColorMaterialThin = ContractColor(key: "token/color/material-thin", lightHex: "#FFFFFFB2", darkHex: "#1C1C1E7A")
    /// `token/color/material-ultra-thick` — Ultra-thick light and dark material fill.
    static let tokenColorMaterialUltraThick = ContractColor(key: "token/color/material-ultra-thick", lightHex: "#FFFFFFEF", darkHex: "#1C1C1EC7")
    /// `token/color/material-ultra-thin` — Ultra-thin light and dark material fill.
    static let tokenColorMaterialUltraThin = ContractColor(key: "token/color/material-ultra-thin", lightHex: "#FFFFFF9E", darkHex: "#1C1C1E61")
    /// `token/color/menu-selection` — Selected menu-item fill.
    static let tokenColorMenuSelection = ContractColor(key: "token/color/menu-selection", lightHex: "#007AFF", darkHex: "#0A84FF")
    /// `token/color/muted` — Muted fills and tertiary visual elements.
    static let tokenColorMuted = ContractColor(key: "token/color/muted", lightHex: "#B6B6BC", darkHex: "#636366")
    /// `token/color/overlay` — Modal and popover overlay color.
    static let tokenColorOverlay = ContractColor(key: "token/color/overlay", lightHex: "#00000033", darkHex: "#00000080")
    /// `token/color/scrim` — Modal scrim.
    static let tokenColorScrim = ContractColor(key: "token/color/scrim", lightHex: "#00000033", darkHex: "#00000073")
    /// `token/color/separator` — Divider and separator color.
    static let tokenColorSeparator = ContractColor(key: "token/color/separator", lightHex: "#D1D1D6", darkHex: "#3A3A3C")
    /// `token/color/shadow` — Window, menu, and card shadow.
    static let tokenColorShadow = ContractColor(key: "token/color/shadow", lightHex: "#0000002E", darkHex: "#00000059")
    /// `token/color/sidebar-fill` — Sidebar material fill.
    static let tokenColorSidebarFill = ContractColor(key: "token/color/sidebar-fill", lightHex: "#F2F2F7E6", darkHex: "#1C1C1ED9")
    /// `token/color/slider-track` — Slider and range-control track fill.
    static let tokenColorSliderTrack = ContractColor(key: "token/color/slider-track", lightHex: "#D1D1D6", darkHex: "#48484A")
    /// `token/color/success-bg` — Subtle success background.
    static let tokenColorSuccessBg = ContractColor(key: "token/color/success-bg", lightHex: "#E5F8EA", darkHex: "#14351D")
    /// `token/color/success-fill` — Success fill and success icon foreground.
    static let tokenColorSuccessFill = ContractColor(key: "token/color/success-fill", lightHex: "#34C759", darkHex: "#34C759")
    /// `token/color/success-text` — Success text.
    static let tokenColorSuccessText = ContractColor(key: "token/color/success-text", lightHex: "#1E7A34", darkHex: "#6EDB84")
    /// `token/color/surface` — Cards, windows, and primary surfaces.
    static let tokenColorSurface = ContractColor(key: "token/color/surface", lightHex: "#FFFFFF", darkHex: "#2C2C2E")
    /// `token/color/text-on-accent` — Text and icon color on blue accent fills.
    static let tokenColorTextOnAccent = ContractColor(key: "token/color/text-on-accent", lightHex: "#FFFFFF", darkHex: "#FFFFFF")
    /// `token/color/text-primary` — Primary text and monochrome icon foreground.
    static let tokenColorTextPrimary = ContractColor(key: "token/color/text-primary", lightHex: "#1D1D1F", darkHex: "#F5F5F7")
    /// `token/color/text-secondary` — Secondary supporting text.
    static let tokenColorTextSecondary = ContractColor(key: "token/color/text-secondary", lightHex: "#6E6E73", darkHex: "#AEAEB2")
    /// `token/color/toolbar-fill` — Toolbar material fill.
    static let tokenColorToolbarFill = ContractColor(key: "token/color/toolbar-fill", lightHex: "#F7F7F9E6", darkHex: "#2C2C2ED9")
    /// `token/color/warning-bg` — Subtle warning background.
    static let tokenColorWarningBg = ContractColor(key: "token/color/warning-bg", lightHex: "#FFF2DC", darkHex: "#3A2A08")
    /// `token/color/warning-fill` — Warning fill and warning icon foreground.
    static let tokenColorWarningFill = ContractColor(key: "token/color/warning-fill", lightHex: "#FF9F0A", darkHex: "#FF9F0A")
    /// `token/color/warning-text` — Warning text.
    static let tokenColorWarningText = ContractColor(key: "token/color/warning-text", lightHex: "#8A4B00", darkHex: "#FFB340")
    /// `token/color/widget-tint-amber` — 组件卡片底色 1。现在。
    static let tokenColorWidgetTintAmber = ContractColor(key: "token/color/widget-tint-amber", lightHex: "#FFF2BD", darkHex: "#FFF2BD")
    /// `token/color/widget-tint-apricot` — 组件卡片底色 5。快捷操作。
    static let tokenColorWidgetTintApricot = ContractColor(key: "token/color/widget-tint-apricot", lightHex: "#FFF1DD", darkHex: "#FFF1DD")
    /// `token/color/widget-tint-mint` — 组件卡片底色 2。电量。
    static let tokenColorWidgetTintMint = ContractColor(key: "token/color/widget-tint-mint", lightHex: "#E5F8EA", darkHex: "#E5F8EA")
    /// `token/color/widget-tint-rose` — 组件卡片底色 4。最近截图。
    static let tokenColorWidgetTintRose = ContractColor(key: "token/color/widget-tint-rose", lightHex: "#FFE8EA", darkHex: "#FFE8EA")
    /// `token/color/widget-tint-sky` — 组件卡片底色 3。传输。
    static let tokenColorWidgetTintSky = ContractColor(key: "token/color/widget-tint-sky", lightHex: "#DDE7F8", darkHex: "#DDE7F8")
    /// `token/color/widget-tint-slate` — 组件卡片底色 6。设备。
    static let tokenColorWidgetTintSlate = ContractColor(key: "token/color/widget-tint-slate", lightHex: "#E9EDF5", darkHex: "#E9EDF5")
    /// `token/color/window-chrome` — Window title-bar and chrome fill.
    static let tokenColorWindowChrome = ContractColor(key: "token/color/window-chrome", lightHex: "#F5F5F7", darkHex: "#2C2C2E")
    /// `token/color/window-close` — macOS close window button.
    static let tokenColorWindowClose = ContractColor(key: "token/color/window-close", lightHex: "#FF5F57", darkHex: "#FF5F57")
    /// `token/color/window-minimize` — macOS minimize window button.
    static let tokenColorWindowMinimize = ContractColor(key: "token/color/window-minimize", lightHex: "#FEBC2E", darkHex: "#FEBC2E")
    /// `token/color/window-zoom` — macOS zoom window button.
    static let tokenColorWindowZoom = ContractColor(key: "token/color/window-zoom", lightHex: "#28C840", darkHex: "#28C840")

    static let all: [ContractColor] = [
        tokenColorAccentSystem,
        tokenColorActionFill,
        tokenColorActionText,
        tokenColorBrand,
        tokenColorBrandHover,
        tokenColorBrandPressed,
        tokenColorCanvas,
        tokenColorControlFill,
        tokenColorControlFillHover,
        tokenColorControlFillPressed,
        tokenColorDisabledText,
        tokenColorDivider,
        tokenColorElevated,
        tokenColorErrorBg,
        tokenColorErrorFill,
        tokenColorErrorText,
        tokenColorFocusRing,
        tokenColorInfoBg,
        tokenColorMaterialMedium,
        tokenColorMaterialThick,
        tokenColorMaterialThin,
        tokenColorMaterialUltraThick,
        tokenColorMaterialUltraThin,
        tokenColorMenuSelection,
        tokenColorMuted,
        tokenColorOverlay,
        tokenColorScrim,
        tokenColorSeparator,
        tokenColorShadow,
        tokenColorSidebarFill,
        tokenColorSliderTrack,
        tokenColorSuccessBg,
        tokenColorSuccessFill,
        tokenColorSuccessText,
        tokenColorSurface,
        tokenColorTextOnAccent,
        tokenColorTextPrimary,
        tokenColorTextSecondary,
        tokenColorToolbarFill,
        tokenColorWarningBg,
        tokenColorWarningFill,
        tokenColorWarningText,
        tokenColorWidgetTintAmber,
        tokenColorWidgetTintApricot,
        tokenColorWidgetTintMint,
        tokenColorWidgetTintRose,
        tokenColorWidgetTintSky,
        tokenColorWidgetTintSlate,
        tokenColorWindowChrome,
        tokenColorWindowClose,
        tokenColorWindowMinimize,
        tokenColorWindowZoom,
    ]
}

/// 设计合同 `tokens` 段里的尺寸。半径、间距、材质不透明度。
enum ContractDimensions {
    /// `token/material/blur` — Figma material blur radius.
    static let tokenMaterialBlur: CGFloat = 60
    /// `token/material/opacity/medium` — Medium material opacity.
    static let tokenMaterialOpacityMedium: CGFloat = 0.78
    /// `token/material/opacity/thick` — Thick material opacity.
    static let tokenMaterialOpacityThick: CGFloat = 0.86
    /// `token/material/opacity/thin` — Thin material opacity.
    static let tokenMaterialOpacityThin: CGFloat = 0.7
    /// `token/material/opacity/ultra-thick` — Ultra-thick material opacity.
    static let tokenMaterialOpacityUltraThick: CGFloat = 0.94
    /// `token/material/opacity/ultra-thin` — Ultra-thin material opacity.
    static let tokenMaterialOpacityUltraThin: CGFloat = 0.62
    /// `token/radius/card` — Card corner radius.
    static let tokenRadiusCard: CGFloat = 12
    /// `token/radius/compact` — Compact surface corner radius.
    static let tokenRadiusCompact: CGFloat = 8
    /// `token/radius/control` — Native control corner radius.
    static let tokenRadiusControl: CGFloat = 6
    /// `token/radius/large` — Cards and screenshot cards.
    static let tokenRadiusLarge: CGFloat = 16
    /// `token/radius/material` — Sequoia material and surface corner radius.
    static let tokenRadiusMaterial: CGFloat = 12
    /// `token/radius/medium` — Buttons and status labels.
    static let tokenRadiusMedium: CGFloat = 12
    /// `token/radius/panel` — 挂帘面板的圆角。
    static let tokenRadiusPanel: CGFloat = 23
    /// `token/radius/pill` — Pill buttons and status labels.
    static let tokenRadiusPill: CGFloat = 999
    /// `token/radius/popover` — Popover, alert, and dialog corner radius.
    static let tokenRadiusPopover: CGFloat = 10
    /// `token/radius/small` — Inputs and small controls.
    static let tokenRadiusSmall: CGFloat = 8
    /// `token/size/workbench-shell-height` — 固定工作台外壳的首选内容高度。屏幕高度不足时按可用高度收缩；页签和编辑模式切换不改变外壳高度。
    static let tokenSizeWorkbenchShellHeight: CGFloat = 880
    /// `token/space/1` — Tight icon and label spacing.
    static let tokenSpace1: CGFloat = 4
    /// `token/space/10` — Page top and bottom padding.
    static let tokenSpace10: CGFloat = 40
    /// `token/space/2` — Compact control spacing.
    static let tokenSpace2: CGFloat = 8
    /// `token/space/3` — Setting row spacing.
    static let tokenSpace3: CGFloat = 12
    /// `token/space/4` — Card inner padding.
    static let tokenSpace4: CGFloat = 16
    /// `token/space/5` — Primary card group spacing.
    static let tokenSpace5: CGFloat = 20
    /// `token/space/6` — Card-to-card spacing.
    static let tokenSpace6: CGFloat = 24
    /// `token/space/8` — Page section spacing.
    static let tokenSpace8: CGFloat = 32

    /// 键名与取值的对照。供测试遍历。
    static let all: [String: CGFloat] = [
        "token/material/blur": tokenMaterialBlur,
        "token/material/opacity/medium": tokenMaterialOpacityMedium,
        "token/material/opacity/thick": tokenMaterialOpacityThick,
        "token/material/opacity/thin": tokenMaterialOpacityThin,
        "token/material/opacity/ultra-thick": tokenMaterialOpacityUltraThick,
        "token/material/opacity/ultra-thin": tokenMaterialOpacityUltraThin,
        "token/radius/card": tokenRadiusCard,
        "token/radius/compact": tokenRadiusCompact,
        "token/radius/control": tokenRadiusControl,
        "token/radius/large": tokenRadiusLarge,
        "token/radius/material": tokenRadiusMaterial,
        "token/radius/medium": tokenRadiusMedium,
        "token/radius/panel": tokenRadiusPanel,
        "token/radius/pill": tokenRadiusPill,
        "token/radius/popover": tokenRadiusPopover,
        "token/radius/small": tokenRadiusSmall,
        "token/size/workbench-shell-height": tokenSizeWorkbenchShellHeight,
        "token/space/1": tokenSpace1,
        "token/space/10": tokenSpace10,
        "token/space/2": tokenSpace2,
        "token/space/3": tokenSpace3,
        "token/space/4": tokenSpace4,
        "token/space/5": tokenSpace5,
        "token/space/6": tokenSpace6,
        "token/space/8": tokenSpace8,
    ]
}

/// 设计合同 `tokens` 段里的一枚动效令牌。
///
/// 时长单位是秒，与 `TimeInterval` 一致。合同里写的是毫秒。
/// `curve` 是曲线的中文描述。
/// `reducedSeconds` 只在合同写了 `reducedMotionMs` 时有值。
struct ContractMotionToken: Sendable, Equatable {
    let key: String
    let seconds: TimeInterval
    let minSeconds: TimeInterval
    let maxSeconds: TimeInterval
    let reducedSeconds: TimeInterval?
    let curve: String
}

/// 设计合同 `tokens` 段里的动效时长。
enum ContractMotion {
    /// `token/motion/error-appear` — 错误出现。160 毫秒，淡入和轻微位移。
    static let tokenMotionErrorAppear = ContractMotionToken(key: "token/motion/error-appear", seconds: 0.16, minSeconds: 0.16, maxSeconds: 0.16, reducedSeconds: nil, curve: "淡入和轻微位移")
    /// `token/motion/file-focus-switch` — Switch the detailed file focus with a short fade.
    static let tokenMotionFileFocusSwitch = ContractMotionToken(key: "token/motion/file-focus-switch", seconds: 0.12, minSeconds: 0.1, maxSeconds: 0.16, reducedSeconds: 0.08, curve: "缓出")
    /// `token/motion/hub-collapse` — Hub 收起。160 至 220 毫秒，缓出曲线。
    static let tokenMotionHubCollapse = ContractMotionToken(key: "token/motion/hub-collapse", seconds: 0.19, minSeconds: 0.16, maxSeconds: 0.22, reducedSeconds: 0.12, curve: "缓出曲线")
    /// `token/motion/hub-expand` — Hub 展开。220 至 280 毫秒，弹性曲线。
    static let tokenMotionHubExpand = ContractMotionToken(key: "token/motion/hub-expand", seconds: 0.25, minSeconds: 0.22, maxSeconds: 0.28, reducedSeconds: 0.12, curve: "弹性曲线")
    /// `token/motion/pointer-exit-collapse` — 指针移出 Hub 后收起的等待时间。
    static let tokenMotionPointerExitCollapse = ContractMotionToken(key: "token/motion/pointer-exit-collapse", seconds: 0.5, minSeconds: 0.5, maxSeconds: 0.5, reducedSeconds: nil, curve: "指针移出后等待，然后收起")
    /// `token/motion/reduced-motion` — 减弱动态效果。120 毫秒，只改变透明度。
    static let tokenMotionReducedMotion = ContractMotionToken(key: "token/motion/reduced-motion", seconds: 0.12, minSeconds: 0.12, maxSeconds: 0.12, reducedSeconds: nil, curve: "只改变透明度")
    /// `token/motion/screenshot-capture` — 截图捕获。650 毫秒，保留现有捕获动画。
    static let tokenMotionScreenshotCapture = ContractMotionToken(key: "token/motion/screenshot-capture", seconds: 0.65, minSeconds: 0.65, maxSeconds: 0.65, reducedSeconds: nil, curve: "保留现有捕获动画")
    /// `token/motion/screenshot-copy` — 截图复制。1200 毫秒提示，保留现有摆动反馈。
    static let tokenMotionScreenshotCopy = ContractMotionToken(key: "token/motion/screenshot-copy", seconds: 1.2, minSeconds: 1.2, maxSeconds: 1.2, reducedSeconds: nil, curve: "保留现有摆动反馈")
    /// `token/motion/tab-switch` — 页签切换。160 毫秒，选中玻璃在按钮间形变，导航栏不位移。
    static let tokenMotionTabSwitch = ContractMotionToken(key: "token/motion/tab-switch", seconds: 0.16, minSeconds: 0.16, maxSeconds: 0.16, reducedSeconds: nil, curve: "按钮间形变")
    /// `token/motion/transfer-complete` — 传输完成。240 毫秒，进度变为完成状态。
    static let tokenMotionTransferComplete = ContractMotionToken(key: "token/motion/transfer-complete", seconds: 0.24, minSeconds: 0.24, maxSeconds: 0.24, reducedSeconds: nil, curve: "进度变为完成状态")
    /// `token/motion/transfer-start` — 传输开始。180 毫秒，卡片抬起并显示进度。
    static let tokenMotionTransferStart = ContractMotionToken(key: "token/motion/transfer-start", seconds: 0.18, minSeconds: 0.18, maxSeconds: 0.18, reducedSeconds: nil, curve: "卡片抬起并显示进度")

    /// 全部条目。供测试遍历。
    static let all: [ContractMotionToken] = [
        tokenMotionErrorAppear,
        tokenMotionFileFocusSwitch,
        tokenMotionHubCollapse,
        tokenMotionHubExpand,
        tokenMotionPointerExitCollapse,
        tokenMotionReducedMotion,
        tokenMotionScreenshotCapture,
        tokenMotionScreenshotCopy,
        tokenMotionTabSwitch,
        tokenMotionTransferComplete,
        tokenMotionTransferStart,
    ]
}

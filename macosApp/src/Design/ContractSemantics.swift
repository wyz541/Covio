// 本文件由 scripts/generate-contract-constants.py 生成。不要手改。
// 权威是 macOS/iOS Apple design。
// docs/covio-design-contract.json 是机器可读投影。
// 改合同后重跑脚本：python3 scripts/generate-contract-constants.py

import Foundation

/// 设计合同里的一个语义角色。
struct ContractSemanticRole: Sendable, Equatable {
    let key: String
    let name: String
    let category: String
    let tokenKeys: [String]
    let typographyKey: String?
    let accessibilityRole: String
    let behavior: String
    let acceptanceIds: [String]
}

/// 设计合同 `semanticRoles` 段。
enum ContractSemanticRoles {
    /// `role/action/primary` — Use for the main action in one local decision area.
    static let roleActionPrimary = ContractSemanticRole(key: "role/action/primary", name: "Primary action", category: "action", tokenKeys: ["token/color/action-fill", "token/color/text-on-accent", "token/radius/small"], typographyKey: "typography/action", accessibilityRole: "button", behavior: "Use for the main action in one local decision area.", acceptanceIds: ["acceptance/visual/semantic-color-roles", "acceptance/visual/semantic-surface-hierarchy"])
    /// `role/focus/ring` — Show the ring on every keyboard-focusable control and keep it visible in both themes.
    static let roleFocusRing = ContractSemanticRole(key: "role/focus/ring", name: "Focus ring", category: "focus", tokenKeys: ["token/color/focus-ring"], typographyKey: nil, accessibilityRole: "focusIndicator", behavior: "Show the ring on every keyboard-focusable control and keep it visible in both themes.", acceptanceIds: ["acceptance/visual/semantic-surface-hierarchy", "acceptance/behavior/focus-order"])
    /// `role/navigation/selected` — Mark exactly one selected destination in a navigation group.
    static let roleNavigationSelected = ContractSemanticRole(key: "role/navigation/selected", name: "Selected navigation", category: "navigation", tokenKeys: ["token/color/menu-selection", "token/color/text-on-accent"], typographyKey: "typography/action", accessibilityRole: "tab", behavior: "Mark exactly one selected destination in a navigation group.", acceptanceIds: ["acceptance/visual/semantic-color-roles", "acceptance/behavior/focus-order"])
    /// `role/status/error` — Pair the color with text or an icon and announce the status to assistive technology.
    static let roleStatusError = ContractSemanticRole(key: "role/status/error", name: "Error status", category: "status", tokenKeys: ["token/color/error-text", "token/color/error-bg"], typographyKey: "typography/caption", accessibilityRole: "alert", behavior: "Pair the color with text or an icon and announce the status to assistive technology.", acceptanceIds: ["acceptance/visual/semantic-color-roles"])
    /// `role/surface/canvas` — Use as the page background below cards and grouped controls.
    static let roleSurfaceCanvas = ContractSemanticRole(key: "role/surface/canvas", name: "Canvas surface", category: "surface", tokenKeys: ["token/color/canvas"], typographyKey: nil, accessibilityRole: "group", behavior: "Use as the page background below cards and grouped controls.", acceptanceIds: ["acceptance/visual/semantic-color-roles", "acceptance/visual/semantic-surface-hierarchy"])
    /// `role/surface/card` — Use for cards and grouped surfaces that sit above the canvas.
    static let roleSurfaceCard = ContractSemanticRole(key: "role/surface/card", name: "Card surface", category: "surface", tokenKeys: ["token/color/surface", "token/radius/large"], typographyKey: nil, accessibilityRole: "group", behavior: "Use for cards and grouped surfaces that sit above the canvas.", acceptanceIds: ["acceptance/visual/semantic-color-roles", "acceptance/visual/semantic-surface-hierarchy"])
    /// `role/text/primary` — Use for primary reading content and monochrome icon foregrounds.
    static let roleTextPrimary = ContractSemanticRole(key: "role/text/primary", name: "Primary text", category: "text", tokenKeys: ["token/color/text-primary"], typographyKey: "typography/body", accessibilityRole: "staticText", behavior: "Use for primary reading content and monochrome icon foregrounds.", acceptanceIds: ["acceptance/visual/semantic-color-roles", "acceptance/visual/typography-hierarchy"])
    /// `role/text/secondary` — Use only when text supports a stronger primary label or value.
    static let roleTextSecondary = ContractSemanticRole(key: "role/text/secondary", name: "Secondary text", category: "text", tokenKeys: ["token/color/text-secondary"], typographyKey: "typography/caption", accessibilityRole: "staticText", behavior: "Use only when text supports a stronger primary label or value.", acceptanceIds: ["acceptance/visual/semantic-color-roles", "acceptance/visual/typography-hierarchy"])

    static let all: [ContractSemanticRole] = [
        roleActionPrimary,
        roleFocusRing,
        roleNavigationSelected,
        roleStatusError,
        roleSurfaceCanvas,
        roleSurfaceCard,
        roleTextPrimary,
        roleTextSecondary,
    ]
}

/// 焦点顺序中的一步。
struct ContractFocusStep: Sendable, Equatable {
    let id: String
    let order: Int
    let componentKey: String
    let elementKey: String
    let behavior: String
}

/// 一个焦点作用域的完整顺序。
struct ContractFocusOrder: Sendable, Equatable {
    let key: String
    let name: String
    let scope: String
    let wrapFocus: Bool
    let trapFocus: Bool
    let restoreFocus: Bool
    let steps: [ContractFocusStep]
    let acceptanceIds: [String]
}

/// 设计合同 `focusOrder` 段。
enum ContractFocusOrders {
    static let focusDialog = ContractFocusOrder(
        key: "focus/dialog",
        name: "Modal dialog traversal",
        scope: "modal",
        wrapFocus: true,
        trapFocus: true,
        restoreFocus: true,
        steps: [
            ContractFocusStep(id: "focus/dialog/message", order: 1, componentKey: "component/alert", elementKey: "message", behavior: "Expose the message before its actions in reading order."),
            ContractFocusStep(id: "focus/dialog/primary", order: 2, componentKey: "component/button", elementKey: "primary", behavior: "Focus the primary action before secondary actions."),
            ContractFocusStep(id: "focus/dialog/secondary", order: 3, componentKey: "component/button", elementKey: "secondary", behavior: "Keep secondary actions after the primary action unless a destructive action needs separation."),
        ],
        acceptanceIds: ["acceptance/behavior/focus-order"]
    )
    static let focusFileArea = ContractFocusOrder(
        key: "focus/file-area",
        name: "File area traversal",
        scope: "file-area",
        wrapFocus: false,
        trapFocus: false,
        restoreFocus: true,
        steps: [
            ContractFocusStep(id: "focus/file-area/filter", order: 1, componentKey: "component/file-filter-menu", elementKey: "filter", behavior: "Focus the filter menu before item actions."),
            ContractFocusStep(id: "focus/file-area/add", order: 2, componentKey: "component/button", elementKey: "add", behavior: "Focus the Add action after the filter menu."),
            ContractFocusStep(id: "focus/file-area/focus-card", order: 3, componentKey: "component/file-focus-card", elementKey: "focus-card", behavior: "Focus the detailed item first."),
            ContractFocusStep(id: "focus/file-area/quiet-tiles", order: 4, componentKey: "component/file-quiet-tile", elementKey: "quiet-tiles", behavior: "Move through quiet tiles row-first with four columns."),
            ContractFocusStep(id: "focus/file-area/item-actions", order: 5, componentKey: "component/file-context-menu", elementKey: "item-actions", behavior: "Open item actions from the focused item and restore focus to that item on close."),
        ],
        acceptanceIds: ["acceptance/behavior/focus-order"]
    )
    static let focusSettings = ContractFocusOrder(
        key: "focus/settings",
        name: "Settings traversal",
        scope: "settings",
        wrapFocus: false,
        trapFocus: false,
        restoreFocus: true,
        steps: [
            ContractFocusStep(id: "focus/settings/back", order: 1, componentKey: "component/button", elementKey: "back", behavior: "Focus the back action before the settings content."),
            ContractFocusStep(id: "focus/settings/search", order: 2, componentKey: "component/toolbar", elementKey: "search", behavior: "Focus settings search before the navigation list."),
            ContractFocusStep(id: "focus/settings/navigation", order: 3, componentKey: "component/tab-bar", elementKey: "section-list", behavior: "Move through settings sections in displayed order."),
            ContractFocusStep(id: "focus/settings/controls", order: 4, componentKey: "component/setting-row", elementKey: "active-section-controls", behavior: "Move through controls in the active section from top to bottom."),
        ],
        acceptanceIds: ["acceptance/behavior/focus-order"]
    )
    static let focusWorkbench = ContractFocusOrder(
        key: "focus/workbench",
        name: "Workbench traversal",
        scope: "workbench",
        wrapFocus: false,
        trapFocus: false,
        restoreFocus: false,
        steps: [
            ContractFocusStep(id: "focus/workbench/search", order: 1, componentKey: "component/toolbar", elementKey: "search", behavior: "Focus the search field first."),
            ContractFocusStep(id: "focus/workbench/navigation", order: 2, componentKey: "component/tab-bar", elementKey: "selected-tab", behavior: "Move through workbench destinations in displayed order."),
            ContractFocusStep(id: "focus/workbench/actions", order: 3, componentKey: "component/button", elementKey: "page-actions", behavior: "Visit page actions before page content."),
            ContractFocusStep(id: "focus/workbench/content", order: 4, componentKey: "component/file-area", elementKey: "content", behavior: "Enter the active page content after its toolbar and actions."),
        ],
        acceptanceIds: ["acceptance/behavior/focus-order"]
    )

    static let all: [ContractFocusOrder] = [
        focusDialog,
        focusFileArea,
        focusSettings,
        focusWorkbench,
    ]
}

/// 平台差异覆盖记录。
struct ContractPlatformOverride: Sendable, Equatable {
    let key: String
    let name: String
    let platform: String
    let contractKey: String
    let status: String
    let behavior: String
    let reason: String
    let evidence: [String]
    let issue: Int
    let acceptanceIds: [String]
}

/// 设计合同 `platformOverrides` 段。
enum ContractPlatformOverrides {
    /// `override/android/interface-font` — Use Roboto with the platform sans-serif fallback when Android delivery starts.
    static let overrideAndroidInterfaceFont = ContractPlatformOverride(key: "override/android/interface-font", name: "Android interface font", platform: "android", contractKey: "font/interface/android", status: "deferred", behavior: "Use Roboto with the platform sans-serif fallback when Android delivery starts.", reason: "Android is outside the first-version product scope.", evidence: ["docs/design/shared-design-contract.md"], issue: 740, acceptanceIds: ["acceptance/visual/platform-font-mapping"])
    /// `override/android/material` — Use platform surfaces that preserve the same semantic hierarchy when Android delivery starts.
    static let overrideAndroidMaterial = ContractPlatformOverride(key: "override/android/material", name: "Android material surrogate", platform: "android", contractKey: "component/material", status: "deferred", behavior: "Use platform surfaces that preserve the same semantic hierarchy when Android delivery starts.", reason: "Android is outside the first-version product scope.", evidence: ["docs/design/shared-design-contract.md"], issue: 740, acceptanceIds: ["acceptance/visual/semantic-surface-hierarchy"])
    /// `override/windows/focus-ring` — Use the shared focus-ring color and keep the indicator visible against every contract surface.
    static let overrideWindowsFocusRing = ContractPlatformOverride(key: "override/windows/focus-ring", name: "Windows focus treatment", platform: "windows", contractKey: "token/color/focus-ring", status: "required", behavior: "Use the shared focus-ring color and keep the indicator visible against every contract surface.", reason: "Windows keyboard focus needs a visible indicator that Compose can draw consistently.", evidence: ["docs/process/interaction-contract.md", "docs/design/shared-design-contract.md"], issue: 740, acceptanceIds: ["acceptance/behavior/focus-order"])
    /// `override/windows/interface-font` — Resolve interface text with Segoe UI Variable. Fall back to Segoe UI only when the variable font is unavailable.
    static let overrideWindowsInterfaceFont = ContractPlatformOverride(key: "override/windows/interface-font", name: "Windows interface font", platform: "windows", contractKey: "font/interface/windows", status: "required", behavior: "Resolve interface text with Segoe UI Variable. Fall back to Segoe UI only when the variable font is unavailable.", reason: "SF Pro is not licensed for Windows and its glyph metrics differ from Segoe UI Variable.", evidence: ["docs/research/compose-rust-bridge/evidence.md", "docs/design/shared-design-contract.md"], issue: 740, acceptanceIds: ["acceptance/visual/platform-font-mapping"])
    /// `override/windows/material` — Use tonal fills, borders, radius, and shadows to preserve surface hierarchy without copying Liquid Glass blur.
    static let overrideWindowsMaterial = ContractPlatformOverride(key: "override/windows/material", name: "Windows material surrogate", platform: "windows", contractKey: "component/material", status: "required", behavior: "Use tonal fills, borders, radius, and shadows to preserve surface hierarchy without copying Liquid Glass blur.", reason: "Compose and egui do not provide a cross-platform equivalent of Apple Liquid Glass.", evidence: ["docs/design/windows-visual-language.md", "docs/design/shared-design-contract.md"], issue: 740, acceptanceIds: ["acceptance/visual/semantic-surface-hierarchy"])
    /// `override/windows/reduced-motion` — Use reduced durations and remove nonessential position changes when the operating system requests reduced motion.
    static let overrideWindowsReducedMotion = ContractPlatformOverride(key: "override/windows/reduced-motion", name: "Windows reduced motion", platform: "windows", contractKey: "token/motion/reduced-motion", status: "required", behavior: "Use reduced durations and remove nonessential position changes when the operating system requests reduced motion.", reason: "The visual result must remain usable without the full expand and collapse sequence.", evidence: ["docs/process/interaction-contract.md", "docs/design/shared-design-contract.md"], issue: 740, acceptanceIds: ["acceptance/behavior/reduced-motion"])

    static let all: [ContractPlatformOverride] = [
        overrideAndroidInterfaceFont,
        overrideAndroidMaterial,
        overrideWindowsFocusRing,
        overrideWindowsInterfaceFont,
        overrideWindowsMaterial,
        overrideWindowsReducedMotion,
    ]
}

/// 可复核的视觉或行为验收条目。
struct ContractAcceptanceCriterion: Sendable, Equatable {
    let key: String
    let name: String
    let kind: String
    let platforms: [String]
    let criteria: String
    let contractKeys: [String]
    let evidence: String
}

/// 设计合同 `acceptanceCriteria` 段。
enum ContractAcceptanceCriteria {
    /// `acceptance/behavior/focus-order` — Keyboard traversal follows the documented scope order and restores focus after modal dismissal.
    static let acceptanceBehaviorFocusOrder = ContractAcceptanceCriterion(key: "acceptance/behavior/focus-order", name: "Keyboard focus order", kind: "behavior", platforms: ["macos", "windows"], criteria: "Keyboard traversal follows the documented scope order and restores focus after modal dismissal.", contractKeys: ["focus/workbench", "focus/file-area", "focus/settings", "focus/dialog"], evidence: "Automated focus-order tests and a manual keyboard traversal record.")
    /// `acceptance/behavior/reduced-motion` — Reduced motion uses the reduced duration and removes nonessential position changes.
    static let acceptanceBehaviorReducedMotion = ContractAcceptanceCriterion(key: "acceptance/behavior/reduced-motion", name: "Reduced motion", kind: "behavior", platforms: ["macos", "windows"], criteria: "Reduced motion uses the reduced duration and removes nonessential position changes.", contractKeys: ["token/motion/reduced-motion", "token/motion/file-focus-switch", "token/motion/hub-expand", "override/windows/reduced-motion"], evidence: "Automated timing tests and a short reduced-motion capture.")
    /// `acceptance/visual/platform-font-mapping` — Apple hosts use SF Pro. Windows uses Segoe UI Variable and never loads SF Pro.
    static let acceptanceVisualPlatformFontMapping = ContractAcceptanceCriterion(key: "acceptance/visual/platform-font-mapping", name: "Platform font mapping", kind: "visual", platforms: ["macos", "ios", "windows"], criteria: "Apple hosts use SF Pro. Windows uses Segoe UI Variable and never loads SF Pro.", contractKeys: ["font/interface/apple", "font/interface/windows", "override/windows/interface-font"], evidence: "Host font diagnostics and Before and After screenshots from each target platform.")
    /// `acceptance/visual/semantic-color-roles` — Each semantic role uses its contract token in light and dark modes.
    static let acceptanceVisualSemanticColorRoles = ContractAcceptanceCriterion(key: "acceptance/visual/semantic-color-roles", name: "Semantic color roles", kind: "visual", platforms: ["macos", "ios", "windows"], criteria: "Each semantic role uses its contract token in light and dark modes.", contractKeys: ["role/text/primary", "role/text/secondary", "role/surface/canvas", "role/surface/card", "role/action/primary", "role/status/error", "role/focus/ring", "role/navigation/selected"], evidence: "Before and After screenshots for each changed surface in light and dark modes.")
    /// `acceptance/visual/semantic-surface-hierarchy` — Platform material differences preserve the canvas, card, action, and focus hierarchy.
    static let acceptanceVisualSemanticSurfaceHierarchy = ContractAcceptanceCriterion(key: "acceptance/visual/semantic-surface-hierarchy", name: "Semantic surface hierarchy", kind: "visual", platforms: ["macos", "ios", "windows"], criteria: "Platform material differences preserve the canvas, card, action, and focus hierarchy.", contractKeys: ["role/surface/canvas", "role/surface/card", "role/action/primary", "role/focus/ring", "override/windows/material"], evidence: "Light and dark screenshots plus the recorded platform override.")
    /// `acceptance/visual/typography-hierarchy` — Titles, body text, actions, and captions keep the documented size and line-height hierarchy.
    static let acceptanceVisualTypographyHierarchy = ContractAcceptanceCriterion(key: "acceptance/visual/typography-hierarchy", name: "Typography hierarchy", kind: "visual", platforms: ["macos", "ios", "windows"], criteria: "Titles, body text, actions, and captions keep the documented size and line-height hierarchy.", contractKeys: ["typography/page-title", "typography/section-title", "typography/card-title", "typography/body", "typography/action", "typography/caption", "typography/empty-state"], evidence: "Before and After screenshots with representative titles, body text, actions, and captions.")

    static let all: [ContractAcceptanceCriterion] = [
        acceptanceBehaviorFocusOrder,
        acceptanceBehaviorReducedMotion,
        acceptanceVisualPlatformFontMapping,
        acceptanceVisualSemanticColorRoles,
        acceptanceVisualSemanticSurfaceHierarchy,
        acceptanceVisualTypographyHierarchy,
    ]
}

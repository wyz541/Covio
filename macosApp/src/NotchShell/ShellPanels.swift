import AppKit

/// 面板的外观。默认跟随系统。
///
/// 面板原先固定深色，理由是「控制中心在浅色与深色系统外观下都是深色的」。
/// 真机复核（2026-10-17）推翻了这条：系统在浅色外观时，控制中心是浅底板加深色文字，
/// 与控制中心同时截的图里，`Wi-Fi`、`蓝牙`、`显示器` 都是深色字。
/// 固定深色会让工作台在浅色系统下变成深底板加白字，与控制中心正好相反。
///
/// 所以现在返回 `nil`，面板跟随系统外观。合同的浅色与深色两套取值都生效：
/// 浅色下 `text-primary` 是 `#1D1D1F`、`text-secondary` 是 `#6E6E73`，
/// 深色下是 `#F5F5F7` 与 `#AEAEB2`。
///
/// 注意 `Color(nsColor:)` 的解析时机：面板在**第一次渲染之前**就设好外观时，
/// 动态颜色按那套取值解析，实测有效。运行中途改 `appearance` 不会重解析。
///
/// `token/color/widget-tint-*` 的深色取值与浅色完全相同，都是浅底。
/// 组件卡片靠 `MacTheme.tintedCardOpacity` 把这个值压淡，见那里的说明。
///
/// 调试构建可以用 `COVIO_APPEARANCE=light` 或 `=dark` 覆盖，用来复核两套取值下的表现。
enum HubAppearance {
    @MainActor static var panel: NSAppearance? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["COVIO_APPEARANCE"] {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default: break
        }
        #endif
        return nil
    }
}

/// 无边框浮层面板的共同配置。
///
/// 设置顺序有硬性要求。`isFloatingPanel = true` 会把 `level` 重置为 `.floating`（3）。
/// M0 实测：
///
/// | 顺序 | 读回的 `level.rawValue` |
/// | --- | --- |
/// | 先 `isFloatingPanel`，再 `level` | 25 |
/// | 先 `level`，再 `isFloatingPanel` | 3 |
///
/// 见 `docs/adr/adr-0001-macos-ui-swiftui.md` 实测 9。
/// 旧版宿主的 `FLOATING_WINDOW_LEVEL = 3` 就是踩了这个坑。
@MainActor
class ShellPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 外观跟随系统。理由见 [HubAppearance]。
        appearance = HubAppearance.panel

        // 顺序不能换。先 isFloatingPanel，再 level。
        isFloatingPanel = true
        level = .statusBar

        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // 编辑输入或拖动文件时 Hub 不自动收起。
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        // 阴影要轻量。窗口阴影关掉，改由 SwiftUI 侧画，控制更直接。
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        animationBehavior = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ShellPanel 只支持代码创建")
    }

    override var canBecomeMain: Bool { false }
}

/// 顶部热区面板。每块屏幕一个，常驻。
///
/// 它自己不激活应用、不接受键盘。作用只有一个：报告指针何时进入热区。
@MainActor
final class HotZonePanel: ShellPanel {
    init(rect: CGRect) {
        super.init(contentRect: rect)
        // 热区必须能收到鼠标事件，否则 tracking area 不会触发。
        ignoresMouseEvents = false
    }

    /// 热区面板永远不能成为 key window。它只是触发器。
    override var canBecomeKey: Bool { false }
}

/// Hub 面板。整个进程只有一个。
///
/// `.nonactivatingPanel` 让点击不激活 Covio，`canBecomeKey = true` 让面板能收到键盘。
/// 两者合起来是 M4 粘贴回填需要的行为：Hub 显示后前台应用不改变，但 Escape 仍然可用。
@MainActor
final class HubPanel: ShellPanel {
    /// Escape 的处理。`cancelOperation` 与 `keyDown` 都会走到这里。
    var onCancel: (() -> Void)?

    private static let escapeKeyCode: UInt16 = 53

    init(rect: CGRect) {
        super.init(contentRect: rect)
        ignoresMouseEvents = false
        // 默认值为 true，面板只在有视图需要键盘时才成为 key window。
        // Escape 要立即收起，所以这里关掉这个优化。
        becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == Self.escapeKeyCode {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

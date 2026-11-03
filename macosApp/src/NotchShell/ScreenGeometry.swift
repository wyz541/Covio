import AppKit

/// 一块屏幕的触发几何。
///
/// 全部从 `NSScreen` 读出，不写死数值。M0 实测本机内建视网膜屏是 1728 × 1117，
/// 顶部安全区 32 点，刘海占 x 从 771.5 到 956.5。见 `docs/adr/adr-0001-macos-ui-swiftui.md` 实测 8。
struct ScreenGeometry: Equatable, Sendable {
    /// 屏幕的完整坐标系。
    let frame: CGRect
    /// 去掉菜单栏与 Dock 之后的坐标系。
    let visibleFrame: CGRect
    /// 顶部安全区高度。刘海屏是 32 点，非刘海屏是 0。
    let safeAreaTop: CGFloat
    /// 刘海在屏幕坐标里的矩形。非刘海屏是 nil。
    let notch: CGRect?

    var hasNotch: Bool { notch != nil }

    /// 菜单栏当前是否可见。
    ///
    /// 全屏 Space 里菜单栏自动隐藏，`visibleFrame` 就与 `frame` 一样高。
    /// 全屏 Space 要隐藏顶部热区，所以这个判断是热区开关的依据。
    var isMenuBarVisible: Bool { visibleFrame.maxY < frame.maxY }

    /// 面板的顶边。刘海屏贴屏幕顶边，非刘海屏贴菜单栏下沿。
    var panelTop: CGFloat {
        hasNotch ? frame.maxY : visibleFrame.maxY
    }

    /// 面板内容相对面板顶边的内缩。刘海屏要让开刘海那一条。
    var panelTopInset: CGFloat {
        hasNotch ? safeAreaTop : 0
    }

    /// 顶部热区在屏幕坐标里的矩形。
    ///
    /// 刘海屏用刘海本身。刘海那一块没有菜单栏项目，所以挡住点击没有代价。
    /// 非刘海屏用菜单栏下方的一条窄带。
    var hotZoneRect: CGRect {
        if let notch {
            return notch
        }
        let width = min(HubMetrics.notchlessHotZoneWidth, frame.width)
        return CGRect(
            x: frame.midX - width / 2,
            y: visibleFrame.maxY - HubMetrics.notchlessHotZoneHeight,
            width: width,
            height: HubMetrics.notchlessHotZoneHeight
        )
    }

    /// 折叠态的面板尺寸。等于热区尺寸。
    var collapsedSize: CGSize {
        hotZoneRect.size
    }

    /// 固定外壳的内容高度。只由屏幕高度与顶部安全区决定。
    var shellContentHeight: CGFloat {
        HubMetrics.shellContentHeight(screenHeight: frame.height, safeAreaTop: panelTopInset)
    }

    /// 固定外壳里导航层与内容层共用的高度。
    var shellPlateStackHeight: CGFloat {
        HubMetrics.shellPlateStackHeight(screenHeight: frame.height, safeAreaTop: panelTopInset)
    }

    /// 展开态的面板矩形。页签与编辑模式不参与计算。
    var expandedRect: CGRect {
        expandedRect(contentHeight: shellContentHeight)
    }

    /// 按给定内容高度计算展开态面板矩形。面板锚定在顶部中央。
    func expandedRect(contentHeight: CGFloat) -> CGRect {
        let width = HubMetrics.hubWidth(screenWidth: frame.width)
        let height = HubMetrics.expandedHeight(
            safeAreaTop: panelTopInset,
            screenHeight: frame.height,
            contentHeight: contentHeight
        )
        return CGRect(
            x: frame.midX - width / 2,
            y: panelTop - height,
            width: width,
            height: height
        )
    }

    /// 面板在给定状态下应该占用的矩形。
    func panelRect(visible: Bool) -> CGRect {
        visible ? expandedRect : collapsedRect
    }

    /// 折叠态的面板矩形。
    var collapsedRect: CGRect {
        let size = collapsedSize
        return CGRect(
            x: frame.midX - size.width / 2,
            y: panelTop - size.height,
            width: size.width,
            height: size.height
        )
    }
}

extension ScreenGeometry {
    init(screen: NSScreen) {
        self.frame = screen.frame
        self.visibleFrame = screen.visibleFrame
        self.safeAreaTop = screen.safeAreaInsets.top
        self.notch = Self.notchRect(screen: screen)
    }

    /// 从两个辅助区的空隙算刘海。
    ///
    /// macOS 用 `auxiliaryTopLeftArea` 与 `auxiliaryTopRightArea` 描述刘海两侧的可用区域。
    /// 本机实测：左区 `(0, 1085, 771.5, 32)`，右区 `(956.5, 1085, 771.5, 32)`。
    /// 两区之间的空隙就是刘海。
    static func notchRect(screen: NSScreen) -> CGRect? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }
        let minX = left.maxX
        let maxX = right.minX
        guard maxX > minX else { return nil }
        let height = max(left.height, right.height)
        guard height > 0 else { return nil }
        return CGRect(
            x: minX,
            y: screen.frame.maxY - height,
            width: maxX - minX,
            height: height
        )
    }

    /// 指针所在屏幕的几何。找不到时回落到主屏。
    ///
    /// `location` 用屏幕坐标。默认读真实指针位置，测试可以传入固定值。
    static func current(
        location: CGPoint = NSEvent.mouseLocation,
        screens: [NSScreen] = NSScreen.screens
    ) -> ScreenGeometry? {
        if let screen = screens.first(where: { $0.frame.contains(location) }) {
            return ScreenGeometry(screen: screen)
        }
        guard let main = NSScreen.main ?? screens.first else { return nil }
        return ScreenGeometry(screen: main)
    }
}

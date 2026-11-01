import AppKit
import SwiftUI

/// 玻璃底材的模式。
///
/// 底板默认使用 Liquid Glass 的 `.regular` 变体。
/// Liquid Glass 负责面板级模糊与自带的镜面亮边。
/// 卡片继续使用 `.clear`，只加薄高光，不重复底板模糊。
///
/// 面板有两层：
///
/// 1. 一块铺满面板的**内容层**，使用 Liquid Glass。
/// 2. 卡片与导航控件叠在内容层上。卡片使用 `.clear`；
///    导航控件只在需要时显示局部玻璃或填充。
///
/// `.system` 保留为调试对照。它使用 `NSVisualEffectView` 的语义材质，
/// 不再作为默认底板。
///
/// 真机对照时，把一个带文字的窗口摆在面板下面。正常模式下，面板区域的文字
/// 会被底板模糊。卡片自身不再重复模糊。
enum GlassSurfaceMode: String, CaseIterable, Sendable {
    /// Liquid Glass 的标准材质。模糊到位，自带一圈镜面亮边。卡片用它。
    ///
    /// 真机实测（2026-10-17，满量程渐变垫在背后，浅色外观，着色 0）：
    /// 桌面亮度从 24 级变到 207 级，面板从 152 级走到 243 级，斜率 0.50。
    /// 加一层黑 0.4 着色以后曲线被压到 62 到 118 级，斜率掉到 0.28 —— 那才是死灰板。
    case glass
    /// Liquid Glass 的清透材质。几乎不模糊，只加薄高光。叠在模糊上面的模块用它。
    case clear
    /// 常规毛玻璃。对照用。斜率 0.34。
    case material
    /// 超薄毛玻璃。对照用。斜率 0.53。不带边框。
    case ultraThin
    /// 系统材质（`NSVisualEffectView`）。保留为调试对照。
    ///
    /// 材质种类由 [plateMaterial] 定。该模式不带 Liquid Glass 的亮边。
    case system

    /// 当前生效的模式。
    ///
    /// 只在主线程改：界面全部在主线程构建。
    /// 调试构建可以用环境变量 `COVIO_GLASS_SURFACE` 覆盖，便于同一次构建换材质截图。
    ///
    /// 这里只影响没显式传 `mode` 的调用点，也就是叠在底板上的那些卡片。
    @MainActor static var current: GlassSurfaceMode = .clear

    /// `.system` 对照模式用的材质。
    ///
    /// 取 `.hudWindow`：AppKit 头文件的说明是
    /// 「The material used as the background of heads-up display (HUD) windows.」
    /// 面板正是浮在桌面上的 HUD 窗口。
    ///
    /// 它是语义材质里最透的一档，真机实测（2026-10-17，浅色外观，满量程渐变垫在背后）
    /// 传递曲线是 `0.25·桌面 + 149`。会模糊的材质里没有比它更透的。
    ///
    /// 默认底板不再使用这个材质。
    /// 调试构建可以用 `COVIO_PLATE_MATERIAL` 换成别的语义材质对照，
    /// 认得出的名字见 [material(named:)]。
    @MainActor static var plateMaterial: NSVisualEffectView.Material = .hudWindow

    /// 材质名字到系统材质的对照。认不出的名字返回 nil。
    static func material(named name: String) -> NSVisualEffectView.Material? {
        switch name {
        case "hudWindow": return .hudWindow
        case "popover": return .popover
        case "menu": return .menu
        case "sidebar": return .sidebar
        case "fullScreenUI": return .fullScreenUI
        case "contentBackground": return .contentBackground
        case "windowBackground": return .windowBackground
        case "underWindowBackground": return .underWindowBackground
        case "underPageBackground": return .underPageBackground
        case "titlebar": return .titlebar
        case "headerView": return .headerView
        case "sheet": return .sheet
        case "toolTip": return .toolTip
        default: return nil
        }
    }

    /// 底板的着色不透明度。取 0 到 1 的黑色。默认 0，不加着色。
    ///
    /// 为什么取 0：真机实测（2026-10-17，满量程黑白渐变垫在面板背后，浅色外观）。
    /// 同一种 Liquid Glass，加一层黑 0.4 着色以后曲线被压到 62 到 118 级，
    /// 斜率从 0.50 掉到 0.28。工作台此前看起来像一块死灰板，压平曲线的是这层着色。
    ///
    /// 取值由**传递曲线**定，不由单点差定。桌面亮度分箱，取每箱里面板的平均亮度，
    /// 得到一条线。线的斜率就是底材的有效透明度，与桌面内容无关。
    ///
    /// | 底材 | 斜率 | 面板亮度范围 |
    /// | --- | --- | --- |
    /// | 控制中心 | 0.71 | 66 → 196 |
    /// | `.glass`，不着色 | 0.50 | 152 → 243 |
    /// | `.ultraThin` | 0.49 | 132 → 221 |
    /// | `.glass`，黑 0.4 着色 | 0.28 | 62 → 118 |
    ///
    /// 调试构建可以用 `COVIO_PLATE_TINT` 覆盖。真机对照用它扫值。
    @MainActor static var plateTintOpacity: Double = 0

    /// 底板默认使用的 Liquid Glass 材质。
    static let plateDefaultMode: GlassSurfaceMode = .glass

    /// 底板当前使用的底材。默认走 Liquid Glass。
    ///
    /// 卡片仍走 `.clear`。卡片不重复底板模糊。
    ///
    /// 调试构建可以用 `COVIO_PLATE_MODE` 覆盖，用来复核别的底材。
    @MainActor static var plateMode: GlassSurfaceMode = plateDefaultMode

    /// 底板用的着色。不透明度是 0 时返回 nil，玻璃走原样。
    @MainActor static var plateTint: Color? {
        plateTintOpacity > 0 ? .black.opacity(plateTintOpacity) : nil
    }

    /// 从环境变量取覆盖值。取值不认识时保持原样。
    @MainActor static func applyEnvironmentOverride() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let raw = env["COVIO_GLASS_SURFACE"], let mode = GlassSurfaceMode(rawValue: raw) {
            current = mode
            NSLog("Covio 玻璃底材被环境变量改成 \(mode.rawValue)。")
        }
        if let raw = env["COVIO_PLATE_TINT"], let value = Double(raw) {
            plateTintOpacity = min(max(value, 0), 1)
            NSLog("Covio 底板着色被环境变量改成 \(plateTintOpacity)。")
        }
        if let raw = env["COVIO_PLATE_MODE"], let mode = GlassSurfaceMode(rawValue: raw) {
            plateMode = mode
            NSLog("Covio 底板底材被环境变量改成 \(mode.rawValue)。")
        }
        if let raw = env["COVIO_PLATE_MATERIAL"], let material = GlassSurfaceMode.material(named: raw) {
            plateMaterial = material
            NSLog("Covio 底板材质被环境变量改成 \(raw)。")
        }
        #endif
    }
}

extension View {
    /// 给视图加一层玻璃底材与圆角。
    ///
    /// 圆角由调用方从 `MacTheme` 取，不在这里写数值。
    /// `tint` 给玻璃上色，用于首页的彩色卡片。
    @MainActor
    func glassSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        interactive: Bool = false,
        mode: GlassSurfaceMode? = nil
    ) -> some View {
        // 默认值在主线程取：`current` 是主线程隔离的，不能写在默认参数里。
        modifier(
            GlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                interactive: interactive,
                mode: mode ?? GlassSurfaceMode.current
            )
        )
    }

    /// Popover 内容层使用的标准材质。
    ///
    /// popover 外壳由系统提供 Liquid Glass。
    /// 内容层按 Apple HIG 使用标准材质，避免重复模糊和混淆层级。
    /// 减少透明度或增强对比时改用不透明 surface。
    @MainActor
    func popoverContentSurface(
        cornerRadius: CGFloat = MacTheme.cardRadius,
        tint: Color? = nil
    ) -> some View {
        modifier(
            PopoverContentSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint
            )
        )
    }
}

private struct PopoverContentSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var usesOpaqueSurface: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesOpaqueSurface {
            content
                .background(shape.fill(tint ?? MacTheme.surface))
                .overlay(shape.strokeBorder(MacTheme.divider, lineWidth: 1))
        } else {
            content
                .background(
                    shape.fill(
                        tint ?? MacTheme.surface.opacity(colorScheme == .dark ? 0.16 : 0.26)
                    )
                )
                .overlay(shape.strokeBorder(MacTheme.divider.opacity(0.48), lineWidth: 0.75))
        }
    }
}

/// 玻璃底材。所有模式共用圆角。
private struct GlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    let mode: GlassSurfaceMode

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// 把着色与交互开关套到玻璃变体上。
    private func variant(_ base: Glass) -> Glass {
        let tinted = tint.map { base.tint($0) } ?? base
        return interactive ? tinted.interactive() : tinted
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch mode {
        case .glass:
            content.glassEffect(variant(.regular), in: .rect(cornerRadius: cornerRadius))
        case .clear:
            content.glassEffect(variant(.clear), in: .rect(cornerRadius: cornerRadius))
        case .material:
            // 毛玻璃模式没有原生着色，用一层半透明填充代替。
            // 材质原样使用，不乘不透明度倍率。
            content
                .background(shape.fill(tint ?? .clear))
                .background(shape.fill(.regularMaterial))
        case .ultraThin:
            content
                .background(shape.fill(tint ?? .clear))
                .background(shape.fill(.ultraThinMaterial))
        case .system:
            content
                .background(shape.fill(tint ?? .clear))
                .background(SystemBackdrop(material: GlassSurfaceMode.plateMaterial, cornerRadius: cornerRadius))
        }
    }
}

/// 系统材质做的半透明模糊底。
///
/// `blendingMode` 取 `.behindWindow`：模糊的是窗口背后的桌面。
/// 面板是无边框透明窗口，所以这一层看到的就是桌面。
///
/// `state` 取 `.active`。默认的 `.followsWindowActiveState` 会在应用不是前台时
/// 把材质调淡，面板是 `.nonactivatingPanel`，点它不激活应用，会被误判成非前台。
private struct SystemBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.layer?.cornerRadius = cornerRadius
    }
}

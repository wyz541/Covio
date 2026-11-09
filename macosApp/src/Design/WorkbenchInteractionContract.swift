import Foundation

/// macOS Workbench 的共享交互合同。
///
/// 这个类型是 Workbench 触发、几何和动效的权威来源。
/// `docs/macos-interaction-contract.json` 由这个类型确定性导出。
/// Windows 只能消费导出物，不能维护第二份共享值。
struct WorkbenchInteractionContract: Codable, Equatable, Sendable {
    static let current = WorkbenchInteractionContract(
        contractId: "covio.workbench.interaction",
        schemaVersion: "1.0.0",
        trigger: Trigger(
            dwellMs: 0,
            cooldownMs: 0,
            pointerExitCollapseMs: 500,
            geometry: TriggerGeometry(
                alignment: .topCenter,
                displaySelection: .pointerDisplayThenMainFallback,
                notchedDisplay: .notch,
                notchlessDisplay: .centeredBand,
                notchlessWidthPoints: 200,
                notchlessHeightPoints: 6
            )
        ),
        reveal: Transition(
            direction: .topToBottom,
            durationMs: 250,
            easing: Easing(
                type: .spring,
                responseSeconds: 0.25,
                dampingFraction: 0.82
            )
        ),
        conceal: Transition(
            direction: .bottomToTop,
            durationMs: 190,
            easing: Easing(type: .easeOut)
        ),
        reducedMotion: ReducedMotion(
            durationMs: 120,
            effect: .opacity
        ),
        geometry: Geometry(
            panelWidthPoints: 960,
            panelCornerRadiusPoints: 23
        ),
        platformOverrides: [
            PlatformOverride(
                id: "windows-top-edge-dwell",
                platform: .windows,
                field: "trigger.dwellMs",
                value: 180,
                reason: "Windows polls global pointer position. A dwell window blocks short edge passes.",
                evidence: ["docs/design/windows-triggers.md"]
            ),
            PlatformOverride(
                id: "windows-top-edge-cooldown",
                platform: .windows,
                field: "trigger.cooldownMs",
                value: 700,
                reason: "Windows global pointer polling needs a cooldown after one Workbench trigger.",
                evidence: ["rust/apps/covio-windows/src/top_edge.rs"]
            ),
            PlatformOverride(
                id: "windows-top-edge-half-width",
                platform: .windows,
                field: "trigger.geometry.centeredHalfWidthPercent",
                value: 5,
                reason: "Windows has no physical notch. The trigger uses the top center five-percent band.",
                evidence: [
                    "docs/design/windows-triggers.md",
                    "rust/apps/covio-windows/src/top_edge.rs",
                ]
            ),
            PlatformOverride(
                id: "windows-top-edge-thickness",
                platform: .windows,
                field: "trigger.geometry.topEdgeThicknessPixels",
                value: 2,
                reason: "Windows pointer coordinates need a two-pixel top edge tolerance.",
                evidence: ["rust/apps/covio-windows/src/top_edge.rs"]
            ),
        ]
    )

    let contractId: String
    let schemaVersion: String
    let trigger: Trigger
    let reveal: Transition
    let conceal: Transition
    let reducedMotion: ReducedMotion
    let geometry: Geometry
    let platformOverrides: [PlatformOverride]

    /// 生成稳定、排序、带末尾换行的 JSON。
    func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(contentsOf: [0x0A])
        return data
    }
}

extension WorkbenchInteractionContract {
    /// 顶部触发区域的对齐方式。
    enum TriggerAlignment: String, Codable, Equatable, Sendable {
        case topCenter
    }

    /// 有多个显示器时，选择触发屏幕的规则。
    enum DisplaySelection: String, Codable, Equatable, Sendable {
        case pointerDisplayThenMainFallback
    }

    /// 顶部触发区域的形状。
    enum TriggerShape: String, Codable, Equatable, Sendable {
        case notch
        case centeredBand
    }

    /// Workbench 的显示或隐藏方向。
    enum TransitionDirection: String, Codable, Equatable, Sendable {
        case topToBottom
        case bottomToTop
    }

    /// SwiftUI 动画类型。
    enum EasingType: String, Codable, Equatable, Sendable {
        case spring
        case easeOut
    }

    /// 减弱动态效果时使用的变化。
    enum ReducedMotionEffect: String, Codable, Equatable, Sendable {
        case opacity
    }

    /// 允许声明实现覆盖的平台。
    enum Platform: String, Codable, Equatable, Sendable {
        case windows
    }

    /// 触发时序和触发几何。
    struct Trigger: Codable, Equatable, Sendable {
        let dwellMs: Double
        let cooldownMs: Double
        let pointerExitCollapseMs: Double
        let geometry: TriggerGeometry

        var dwellSeconds: TimeInterval { dwellMs / 1000 }
        var cooldownSeconds: TimeInterval { cooldownMs / 1000 }
        var pointerExitCollapseSeconds: TimeInterval { pointerExitCollapseMs / 1000 }
    }

    /// 顶部触发区域的几何。
    struct TriggerGeometry: Codable, Equatable, Sendable {
        let alignment: TriggerAlignment
        let displaySelection: DisplaySelection
        let notchedDisplay: TriggerShape
        let notchlessDisplay: TriggerShape
        let notchlessWidthPoints: Double
        let notchlessHeightPoints: Double
    }

    /// 一次显示或隐藏转换。
    struct Transition: Codable, Equatable, Sendable {
        let direction: TransitionDirection
        let durationMs: Double
        let easing: Easing

        var durationSeconds: TimeInterval { durationMs / 1000 }
    }

    /// 动画曲线参数。
    struct Easing: Codable, Equatable, Sendable {
        let type: EasingType
        let responseSeconds: Double?
        let dampingFraction: Double?

        init(
            type: EasingType,
            responseSeconds: Double? = nil,
            dampingFraction: Double? = nil
        ) {
            self.type = type
            self.responseSeconds = responseSeconds
            self.dampingFraction = dampingFraction
        }

        /// Evaluates the shared conformance vector model.
        func progress(at normalizedTime: Double, durationSeconds: Double) -> Double {
            let time = min(max(normalizedTime, 0), 1)
            if time <= 0 { return 0 }
            if time >= 1 { return 1 }
            switch type {
            case .easeOut:
                return 1 - pow(1 - time, 3)
            case .spring:
                return springProgress(
                    responseSeconds: responseSeconds ?? durationSeconds,
                    dampingFraction: dampingFraction ?? 1,
                    time: time * durationSeconds
                )
            }
        }

        private func springProgress(
            responseSeconds: Double,
            dampingFraction: Double,
            time: Double
        ) -> Double {
            let angularFrequency = 2 * Double.pi / responseSeconds
            let decay = exp(-dampingFraction * angularFrequency * time)
            if dampingFraction < 1 {
                let dampedFrequency =
                    angularFrequency * sqrt(1 - pow(dampingFraction, 2))
                let cosine = cos(dampedFrequency * time)
                let sine = sin(dampedFrequency * time)
                return 1 - decay * (
                    cosine
                        + dampingFraction * angularFrequency / dampedFrequency * sine
                )
            }
            return 1 - decay * (1 + angularFrequency * time)
        }
    }

    /// 减弱动态效果参数。
    struct ReducedMotion: Codable, Equatable, Sendable {
        let durationMs: Double
        let effect: ReducedMotionEffect

        var durationSeconds: TimeInterval { durationMs / 1000 }
    }

    /// Workbench 面板几何。
    struct Geometry: Codable, Equatable, Sendable {
        let panelWidthPoints: Double
        let panelCornerRadiusPoints: Double
    }

    /// 一个显式、可追溯的平台覆盖。
    struct PlatformOverride: Codable, Equatable, Sendable {
        let id: String
        let platform: Platform
        let field: String
        let value: Double
        let reason: String
        let evidence: [String]
    }
}

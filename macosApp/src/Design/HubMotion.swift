import Foundation
import SwiftUI

/// Hub 的动效参数。
///
/// Workbench 的显示、隐藏、触发和指针移出参数来自
/// WorkbenchInteractionContract。其他共享动效仍来自设计合同生成的常量。
enum HubMotion {
    private static let contract = WorkbenchInteractionContract.current

    /// Hub 展开时长。
    static let expand: TimeInterval = contract.reveal.durationSeconds

    /// Hub 收起时长。
    static let collapse: TimeInterval = contract.conceal.durationSeconds

    /// 指针进入热区后等待多久再触发。
    static let triggerDwell: TimeInterval = contract.trigger.dwellSeconds

    /// 一次触发后的冷却时间。
    static let triggerCooldown: TimeInterval = contract.trigger.cooldownSeconds

    /// 页签切换：160 毫秒，横向滑动加淡入。
    static let tabSwitch: TimeInterval = ContractMotion.tokenMotionTabSwitch.seconds

    /// 截图捕获：650 毫秒。
    static let screenshotCapture: TimeInterval = ContractMotion.tokenMotionScreenshotCapture.seconds

    /// 截图复制：1200 毫秒提示。
    static let screenshotCopy: TimeInterval = ContractMotion.tokenMotionScreenshotCopy.seconds

    /// 文件焦点切换：120 毫秒；减弱动态效果时 80 毫秒。
    static let fileFocusSwitch: TimeInterval = ContractMotion.tokenMotionFileFocusSwitch.seconds
    static let fileFocusSwitchReduced: TimeInterval =
        ContractMotion.tokenMotionFileFocusSwitch.reducedSeconds ?? 0.08

    /// 传输开始：180 毫秒。
    static let transferStart: TimeInterval = ContractMotion.tokenMotionTransferStart.seconds

    /// 传输完成：240 毫秒。
    static let transferComplete: TimeInterval = ContractMotion.tokenMotionTransferComplete.seconds

    /// 错误出现：160 毫秒。
    static let errorAppear: TimeInterval = ContractMotion.tokenMotionErrorAppear.seconds

    /// 减弱动态效果：只改透明度。
    static let reducedMotion: TimeInterval = contract.reducedMotion.durationSeconds

    /// 指针移出 Hub 后收起的等待时间。
    static let pointerExitCollapseDelay: TimeInterval =
        contract.trigger.pointerExitCollapseSeconds

    /// 换页签后多久内，指针不再触发切换。
    /// 合同没有这枚令牌，取值按「指针扫过顶栏只切一次」的手感定。
    static let hoverCooldown: TimeInterval = 0.25

    /// 工作台展开完成后，导航 hover 继续停用的时间。
    /// 用于拦住从顶部热区进入页签的误触。
    static let initialHoverProtection: TimeInterval = 0.5

    /// 呼吸灯一次亮灭的时长。合同没有这枚令牌，取值按肉眼可见的缓慢呼吸定。
    static let pulse: TimeInterval = 1.2

    /// 生效的展开时长。
    static func expandDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedMotion : expand
    }

    /// 生效的收起时长。
    static func collapseDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedMotion : collapse
    }

    /// 返回挂帘当前状态使用的动画。
    static func curtainAnimation(isExpanded: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .linear(duration: reducedMotion)
        }
        return animation(for: isExpanded ? contract.reveal : contract.conceal)
    }

    private static func animation(
        for transition: WorkbenchInteractionContract.Transition
    ) -> Animation {
        switch transition.easing.type {
        case .spring:
            return .spring(
                response: transition.durationSeconds,
                dampingFraction: transition.easing.dampingFraction ?? 1
            )
        case .easeOut:
            return .easeOut(duration: transition.durationSeconds)
        }
    }
}

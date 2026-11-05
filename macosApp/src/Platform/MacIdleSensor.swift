import CoreGraphics
import Foundation

/// `IdleSensor` 端口的 macOS 实现。
///
/// 读「距离上一次任意输入事件过了多少秒」。
///
/// 这个值不受本应用自己阻止空闲睡眠的影响，所以引擎可以拿它和系统
/// 空闲超时比较，判断是否需要手动休眠。
final class MacIdleSensor: NSObject, IdleSensor {
    /// `kCGAnyInputEventType` 在 Swift 里没有对应的枚举成员，只能自己造。
    /// 它的值是 `~0`，与 Rust core 的任意输入事件常量相等。
    private static let anyInputEvent = CGEventType(rawValue: ~0)!

    func idleSeconds() -> Int64 {
        Int64(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInputEvent))
    }
}

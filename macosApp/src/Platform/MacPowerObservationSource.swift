import AppKit
import CoreGraphics
import Foundation
@preconcurrency import IOKit.ps

/// `PowerObservationSource` 的 macOS 实现。
///
/// 电池与合盖事件复用现有端口。
/// 热状态、低电量模式和显示器变化使用公开通知补齐。
final class MacPowerObservationSource: NSObject, PowerObservationSource, @unchecked Sendable {
    private let lock = NSLock()
    private let power = MacPowerSource()
    private let lid = MacLidSensor()
    private var listener: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var stopped = true

    func read() -> PowerObservation {
        let battery = MacPowerSource.readBatteryReading()
        let provider = Self.readProviderPowerState()
        return PowerObservation(
            batteryPercent: battery.percent.map { Int32($0) },
            hasBattery: battery.hasInternalBattery,
            powerState: Self.resolvePowerState(provider: provider, battery: battery.state),
            externalDisplayCount: ExternalDisplayReader.count().map { Int32($0) },
            lidState: MacLidSensor.readClamshellState(),
            thermalState: Self.mapThermalState(ProcessInfo.processInfo.thermalState),
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    func subscribe(listener_: @escaping () -> Void) {
        lock.lock()
        if !stopped {
            lock.unlock()
            return
        }
        listener = listener_
        stopped = false
        lock.unlock()

        power.subscribe { [weak self] in self?.publish() }
        lid.subscribe { [weak self] _ in self?.publish() }

        let center = NotificationCenter.default
        let tokens = [
            center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in self?.publish() },
            center.addObserver(
                forName: Notification.Name("NSProcessInfoPowerStateDidChangeNotification"),
                object: ProcessInfo.processInfo,
                queue: nil
            ) { [weak self] _ in self?.publish() },
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in self?.publish() },
        ]

        lock.lock()
        let shouldStopImmediately = stopped
        if !shouldStopImmediately {
            observers = tokens
        }
        lock.unlock()

        if shouldStopImmediately {
            Self.removeObservers(tokens)
            power.stop()
            lid.stop()
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        listener = nil
        let observers = self.observers
        self.observers = []
        lock.unlock()

        Self.removeObservers(observers)
        power.stop()
        lid.stop()
    }

    private func publish() {
        lock.lock()
        let callback = stopped ? nil : listener
        lock.unlock()
        guard let callback else { return }
        let box = KotlinBox(callback)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { box.value() }
        }
    }

    private static func removeObservers(_ observers: [NSObjectProtocol]) {
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    /// 读 IOPS 当前供电来源。无可靠值时返回 `UNKNOWN`。
    static func readProviderPowerState() -> PowerState {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return .unknown }
        guard let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String? else {
            return .unknown
        }
        return mapProviderType(type)
    }

    /// 把 IOPS 的供电来源字符串映射为共享枚举。
    static func mapProviderType(_ value: String) -> PowerState {
        switch value {
        case "AC Power":
            return .acPower
        case "Battery Power":
            return .discharging
        default:
            return .unknown
        }
    }

    /// 电池状态比供电来源更具体，保留充电和充满状态。
    static func resolvePowerState(provider: PowerState, battery: PowerState) -> PowerState {
        if provider == .acPower, battery == .charging || battery == .charged {
            return battery
        }
        return provider == .unknown ? battery : provider
    }

    static func mapThermalState(_ value: ProcessInfo.ThermalState) -> ThermalState {
        switch value {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .unknown
        }
    }

    /// 统计在线且非内建的显示器。读取失败时返回 nil。
    static func readExternalDisplayCount() -> Int? {
        ExternalDisplayReader.count()
    }
}

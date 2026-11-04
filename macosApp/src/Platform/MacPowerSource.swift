import Foundation
// IOKit 与 CoreFoundation 的类型没有标注 Sendable。加 @preconcurrency
// 让这些告警降级，不然每个持有 CFRunLoopSource 的闭包都报错。
@preconcurrency import CoreFoundation
@preconcurrency import IOKit
@preconcurrency import IOKit.ps

/// `PowerSource` 端口的 macOS 实现。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/platform/MacPowerSource.kt`。
/// Kotlin 版通过 JNA 调 IOKit，这里直接用 IOKit 的 Swift 接口。
///
/// 两路通知都在：IOPS 推送变化，5 秒轮询兜底。
/// 只用推送会在某些机型上漏掉充电状态变化，只用轮询会让电量显示延迟。
// 所有可变状态都由 `lock` 保护，所以可以跨线程传。
final class MacPowerSource: NSObject, PowerSource, @unchecked Sendable {
    private let lock = NSLock()
    private var listener: (() -> Void)?
    private var runLoopSource: CFRunLoopSource?
    private var eventThread: Thread?
    private var pollTimer: DispatchSourceTimer?
    private var stopped = false

    func read() -> BatteryStatus? {
        Self.readBattery()
    }

    func subscribe(listener_: @escaping () -> Void) {
        lock.lock()
        listener = listener_
        stopped = false
        lock.unlock()

        registerPowerNotifications()
        startPolling()
    }

    func stop() {
        lock.lock()
        stopped = true
        listener = nil
        let source = runLoopSource
        runLoopSource = nil
        lock.unlock()

        pollTimer?.cancel()
        pollTimer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode) }
        eventThread = nil
    }

    // MARK: - 私有

    private func notify() {
        lock.lock()
        let listener = self.listener
        lock.unlock()
        listener?()
    }

    private func registerPowerNotifications() {
        // 回调不能捕获上下文，所以用 refCon 传回自身。
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<MacPowerSource>.fromOpaque(context).takeUnretainedValue().notify()
        }, context)?.takeRetainedValue() else { return }

        lock.lock()
        runLoopSource = source
        lock.unlock()

        let thread = Thread { [weak self] in
            // 不在这里捕获 `source`：CFRunLoopSource 不是 Sendable，
            // 捕获会让这个 @Sendable 闭包报警告。改成回读一次。
            guard let self, let source = self.runLoopSourceIfRunning else { return }
            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .defaultMode)
            CFRunLoopRun()
        }
        thread.name = "Covio-power-events"
        thread.qualityOfService = .utility
        eventThread = thread
        thread.start()
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    /// 一次拿到 source 与停止标志，避开「线程启动」与「stop()」的竞争。
    private var runLoopSourceIfRunning: CFRunLoopSource? {
        lock.lock()
        defer { lock.unlock() }
        return stopped ? nil : runLoopSource
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self, !self.isStopped else { return }
            self.notify()
        }
        pollTimer = timer
        timer.resume()
    }

    internal struct BatteryReading {
        let status: BatteryStatus?
        let percent: Int?
        let hasInternalBattery: Bool?
        let state: PowerState
    }

    /// 读内置电池。没有内置电池（台式机）时返回 nil。
    static func readBattery() -> BatteryStatus? {
        readBatteryReading().status
    }

    /// 保留“是否存在电池”和“百分比是否可读”的区别。
    ///
    /// 百分比缺失时不填 0。0 是有效读数，不能代替未知值。
    static func readBatteryReading() -> BatteryReading {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return BatteryReading(status: nil, percent: nil, hasInternalBattery: nil, state: .unknown)
        }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryReading(status: nil, percent: nil, hasInternalBattery: nil, state: .unknown)
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            let type = description["Type"] as? String ?? ""
            guard type.caseInsensitiveCompare("InternalBattery") == .orderedSame else { continue }

            let current = description["Current Capacity"] as? Int
            let maximum = description["Max Capacity"] as? Int
            let percent = batteryPercent(current: current, maximum: maximum)

            let isCharging = description["Is Charging"] as? Bool ?? false
            let isCharged = description["Is Charged"] as? Bool ?? false
            let powerState = description["Power Source State"] as? String ?? ""
            let state: PowerState
            if isCharged {
                state = .charged
            } else if isCharging {
                state = .charging
            } else if powerState.caseInsensitiveCompare("Battery Power") == .orderedSame {
                state = .discharging
            } else if powerState.caseInsensitiveCompare("AC Power") == .orderedSame {
                state = .acPower
            } else {
                state = .unknown
            }

            let minutesKey = state == .discharging ? "Time to Empty" : "Time to Full Charge"
            let minutes = description[minutesKey] as? Int
            let remaining = (minutes ?? 0) > 0 ? Int64(minutes!) * 60 : nil
            let status = percent.map {
                BatteryStatus(
                    percent: Int32(min(max($0, 0), 100)),
                    state: state,
                    remainingSeconds: remaining
                )
            }
            return BatteryReading(
                status: status,
                percent: percent,
                hasInternalBattery: true,
                state: state
            )
        }
        return BatteryReading(status: nil, percent: nil, hasInternalBattery: false, state: .unknown)
    }

    /// 容量值只按 current / maximum 计算。任一值缺失时返回 nil。
    static func batteryPercent(current: Int?, maximum: Int?) -> Int? {
        guard let current, let maximum, maximum > 0 else { return nil }
        return min(max((current * 100) / maximum, 0), 100)
    }
}

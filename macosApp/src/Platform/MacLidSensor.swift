import Foundation
@preconcurrency import IOKit

/// `LidSensor` 端口的 macOS 实现。
///
/// 读 `IOPMrootDomain` 的 `AppleClamshellState` 属性，并订阅该服务的状态变化。
///
/// 台式机没有这个属性，此时返回 `UNKNOWN`。调用方必须把 `UNKNOWN` 当作
/// 「不知道」，不能当作「打开」。
// 所有可变状态都由 `lock` 保护，所以可以跨线程传。
final class MacLidSensor: NSObject, LidSensor, @unchecked Sendable {
    private let lock = NSLock()
    private var listener: ((LidState) -> Void)?
    private var stopped = false
    private var notificationPort: IONotificationPortRef?
    private var runLoopSource: CFRunLoopSource?
    private var service: io_object_t = 0
    private var notification: io_object_t = 0
    private var eventThread: Thread?
    private var runLoop: CFRunLoop?

    func read() -> LidState {
        Self.readClamshellState()
    }

    func subscribe(listener: @escaping (LidState) -> Void) {
        lock.lock()
        self.listener = listener
        stopped = false
        lock.unlock()

        let thread = Thread { [weak self] in
            guard let self else { return }
            self.runEventLoop()
        }
        thread.name = "Covio-lid-events"
        thread.qualityOfService = .utility
        eventThread = thread
        thread.start()
    }

    func stop() {
        lock.lock()
        stopped = true
        listener = nil
        let runLoop = self.runLoop
        lock.unlock()

        if let runLoop { CFRunLoopStop(runLoop) }
        releaseNativeObjects()
    }

    // MARK: - 私有

    /// 读合盖状态。属性不存在时返回 `UNKNOWN`。
    static func readClamshellState() -> LidState {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return .unknown }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(
            service,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(0)
        )?.takeRetainedValue() else { return .unknown }

        guard let value = property as? Bool else { return .unknown }
        return value ? .closed : .open
    }

    private func runEventLoop() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        guard let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else { return }
        runLoopSource = source

        let matched = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard matched != 0 else { return }
        service = matched

        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(
            port,
            matched,
            // 第三个参数是 `io_name_t`，即 C 字符串，不是 CFString。
            "IOGeneralInterest",
            { context, _, _, _ in
                guard let context else { return }
                let sensor = Unmanaged<MacLidSensor>.fromOpaque(context).takeUnretainedValue()
                sensor.publish(sensor.read())
            },
            context,
            &notification
        )
        guard result == KERN_SUCCESS else { return }

        let loop = CFRunLoopGetCurrent()
        runLoop = loop
        CFRunLoopAddSource(loop, source, .defaultMode)
        publish(read())

        lock.lock()
        let alreadyStopped = stopped
        lock.unlock()
        guard !alreadyStopped else { return }
        CFRunLoopRun()
    }

    private func publish(_ state: LidState) {
        lock.lock()
        let listener = self.listener
        lock.unlock()
        listener?(state)
    }

    private func releaseNativeObjects() {
        lock.lock()
        defer { lock.unlock() }
        if let runLoop, let runLoopSource {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .defaultMode)
        }
        if notification != 0 {
            IOObjectRelease(notification)
            notification = 0
        }
        if service != 0 {
            IOObjectRelease(service)
            service = 0
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        runLoopSource = nil
        runLoop = nil
    }
}

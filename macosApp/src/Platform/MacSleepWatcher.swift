import Foundation
import IOKit
import IOKit.pwr_mgt

/// `SleepWatcher` 端口的 macOS 实现。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/platform/MacSleepWatcher.kt`。
/// 用 `IORegisterForSystemPower` 订阅系统电源消息。
///
/// 系统要睡眠时会阻塞等待 `IOAllowPowerChange`。这里收到
/// `kIOMessageSystemWillSleep` 后立刻放行，所以不会拖慢睡眠。
// 所有可变状态都由 `lock` 保护，所以可以跨线程传。
final class MacSleepWatcher: NSObject, SleepWatcher, @unchecked Sendable {
    /// 与 `IOKit.pwr_mgt` 的消息常量对应。0xe0000280 等值来自 IOMessage.h。
    private static let systemWillSleep = 0xe000_0280
    private static let systemWillPowerOn = 0xe000_0320
    private static let systemHasPoweredOn = 0xe000_0300

    private let lock = NSLock()
    private var listener: ((SleepEvent) -> Void)?
    private var stopped = false
    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var notificationPort: IONotificationPortRef?
    private var runLoop: CFRunLoop?
    private var eventThread: Thread?

    // 参数名必须写成 `listener__`：Kotlin 的 `subscribe(listener:)` 导出到
    // Objective-C 后选择子是 `subscribeListener__:`，多出的下划线是 konanc
    // 为带参数的闭包加的。写成 `listener` 编译不过。
    func subscribe(listener__: @escaping (SleepEvent) -> Void) {
        lock.lock()
        self.listener = listener__
        stopped = false
        lock.unlock()

        let thread = Thread { [weak self] in
            self?.runEventLoop()
        }
        thread.name = "Covio-sleep-watcher"
        thread.qualityOfService = .utility
        eventThread = thread
        thread.start()
    }

    func stop() {
        lock.lock()
        stopped = true
        listener = nil
        let runLoop = self.runLoop
        let port = rootPort
        let notifier = self.notifier
        let notificationPort = self.notificationPort
        rootPort = 0
        self.notifier = 0
        self.notificationPort = nil
        self.runLoop = nil
        lock.unlock()

        if let runLoop { CFRunLoopStop(runLoop) }
        if port != 0 {
            var handle = notifier
            IODeregisterForSystemPower(&handle)
            if let notificationPort { IONotificationPortDestroy(notificationPort) }
            IOServiceClose(port)
        }
    }

    // MARK: - 私有

    private func runEventLoop() {
        var port: IONotificationPortRef?
        var notifier: io_object_t = 0
        let context = Unmanaged.passUnretained(self).toOpaque()
        let connection = IORegisterForSystemPower(
            context,
            &port,
            { context, _, messageType, argument in
                guard let context else { return }
                let watcher = Unmanaged<MacSleepWatcher>.fromOpaque(context).takeUnretainedValue()
                watcher.handle(messageType: messageType, argument: argument)
            },
            &notifier
        )
        guard connection != 0, let port,
              let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue()
        else { return }

        lock.lock()
        rootPort = connection
        self.notifier = notifier
        notificationPort = port
        let alreadyStopped = stopped
        lock.unlock()
        guard !alreadyStopped else {
            var handle = notifier
            IODeregisterForSystemPower(&handle)
            IONotificationPortDestroy(port)
            IOServiceClose(connection)
            return
        }

        let loop = CFRunLoopGetCurrent()
        runLoop = loop
        CFRunLoopAddSource(loop, source, .defaultMode)
        CFRunLoopRun()
    }

    private func handle(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        switch Int(messageType) {
        case Self.systemWillSleep:
            publish(.willsleep)
            // 必须放行，否则系统会等到超时才睡。
            let port = rootPort
            if port != 0, let argument {
                IOAllowPowerChange(port, Int(bitPattern: argument))
            }
        case Self.systemWillPowerOn, Self.systemHasPoweredOn:
            publish(.wakesignal)
        default:
            break
        }
    }

    private func publish(_ event: SleepEvent) {
        lock.lock()
        let listener = self.listener
        lock.unlock()
        listener?(event)
    }
}

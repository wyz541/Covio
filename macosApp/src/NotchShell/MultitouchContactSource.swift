import CoreFoundation
import CoreGraphics
import Darwin
import Foundation

/// 私有触控板入口的启动结果。
enum MultitouchStartResult: Equatable, Sendable {
    case started(deviceCount: Int)
    case frameworkMissing
    case symbolMissing
    case noDevice

    /// 日志里的稳定错误码。没有错误时为空。
    var errorCode: String? {
        switch self {
        case .started:
            nil
        case .frameworkMissing:
            "multitouch_framework_missing"
        case .symbolMissing:
            "multitouch_symbol_missing"
        case .noDevice:
            "multitouch_no_device"
        }
    }
}

/// 接触帧来源。测试可以替换真实私有框架。
protocol MultitouchContactSourceProtocol: AnyObject, Sendable {
    @discardableResult
    func start(onFrame: @escaping @Sendable (TouchFrame) -> Void) -> MultitouchStartResult
    func stop()
}

/// 私有 `MultitouchSupport.framework` 的适配器。
///
/// 只调用四个核心函数：
/// `MTDeviceCreateList`、`MTRegisterContactFrameCallback`、`MTDeviceStart`、`MTDeviceStop`。
/// 不调用会崩溃的 `MTDeviceGet*` 访问器。
final class MultitouchContactSource: MultitouchContactSourceProtocol, @unchecked Sendable {
    private typealias Device = UnsafeMutableRawPointer
    private typealias CreateList = @convention(c) () -> CFArray?
    private typealias RegisterCallback = @convention(c) (Device, MTContactCallback) -> Void
    private typealias StartDevice = @convention(c) (Device, Int32) -> Void
    private typealias StopDevice = @convention(c) (Device, Int32) -> Void

    private struct Library {
        let handle: UnsafeMutableRawPointer
        let deviceList: CFArray
        let devices: [Device]
        let registerCallback: RegisterCallback
        let startDevice: StartDevice
        let stopDevice: StopDevice
    }

    private static let defaultFrameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    private let frameworkPath: String
    private let lock = NSLock()
    private var library: Library?

    init(frameworkPath: String = MultitouchContactSource.defaultFrameworkPath) {
        self.frameworkPath = frameworkPath
    }

    @discardableResult
    func start(onFrame: @escaping @Sendable (TouchFrame) -> Void) -> MultitouchStartResult {
        if let count = lock.withLock({ library?.devices.count }) {
            return .started(deviceCount: count)
        }

        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            return .frameworkMissing
        }

        guard let createListSymbol = dlsym(handle, "MTDeviceCreateList"),
              let registerSymbol = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startSymbol = dlsym(handle, "MTDeviceStart"),
              let stopSymbol = dlsym(handle, "MTDeviceStop")
        else {
            dlclose(handle)
            return .symbolMissing
        }

        let createList = unsafeBitCast(createListSymbol, to: CreateList.self)
        let registerCallback = unsafeBitCast(registerSymbol, to: RegisterCallback.self)
        let startDevice = unsafeBitCast(startSymbol, to: StartDevice.self)
        let stopDevice = unsafeBitCast(stopSymbol, to: StopDevice.self)

        guard let list = createList() else {
            dlclose(handle)
            return .noDevice
        }
        let count = CFArrayGetCount(list)
        guard count > 0 else {
            dlclose(handle)
            return .noDevice
        }

        // 让 CFArray 在设备运行期间保持存活。
        let devices = (0..<count).map { index in
            unsafeBitCast(CFArrayGetValueAtIndex(list, index), to: Device.self)
        }
        let installed = Library(
            handle: handle,
            deviceList: list,
            devices: devices,
            registerCallback: registerCallback,
            startDevice: startDevice,
            stopDevice: stopDevice
        )

        lock.withLock {
            library = installed
        }
        MultitouchCallbackRouter.shared.install(onFrame)
        for device in devices {
            registerCallback(device, multitouchContactCallback)
            startDevice(device, 0)
        }
        return .started(deviceCount: devices.count)
    }

    func stop() {
        let installed = lock.withLock { () -> Library? in
            defer { library = nil }
            return library
        }
        guard let installed else { return }

        MultitouchCallbackRouter.shared.remove()
        for device in installed.devices {
            installed.stopDevice(device, 0)
        }
        dlclose(installed.handle)
    }

    deinit {
        stop()
    }
}

/// 私有框架回调。必须是没有捕获的 C 函数。
private typealias MTContactCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeRawPointer?,
    Int32,
    Double,
    Int32
) -> Int32

private func multitouchContactCallback(
    _ device: UnsafeMutableRawPointer?,
    _ touches: UnsafeRawPointer?,
    _ count: Int32,
    _ timestamp: Double,
    _ frameNumber: Int32
) -> Int32 {
    _ = device
    _ = frameNumber
    let optionKeyDown = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    let frame = TouchFrame.parse(
        touches: touches,
        count: count,
        timestamp: timestamp,
        optionKeyDown: optionKeyDown
    )
    MultitouchCallbackRouter.shared.deliver(frame)
    return 0
}

/// 让无 refcon 的私有回调找到当前监听者。
private final class MultitouchCallbackRouter: @unchecked Sendable {
    static let shared = MultitouchCallbackRouter()

    private let lock = NSLock()
    private var handler: (@Sendable (TouchFrame) -> Void)?

    private init() {}

    func install(_ handler: @escaping @Sendable (TouchFrame) -> Void) {
        lock.withLock {
            self.handler = handler
        }
    }

    func remove() {
        lock.withLock {
            handler = nil
        }
    }

    func deliver(_ frame: TouchFrame) {
        let currentHandler: (@Sendable (TouchFrame) -> Void)? = lock.withLock {
            self.handler
        }
        currentHandler?(frame)
    }
}

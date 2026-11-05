import Foundation
import IOKit.pwr_mgt

/// `SleepController` 端口的 macOS 实现。
///
/// 系统保持唤醒使用 `PreventUserIdleSystemSleep`。
/// 屏幕保持唤醒使用 `PreventUserIdleDisplaySleep`。
/// 屏幕断言已经阻止系统空闲睡眠，所以两种断言不叠加。
///
/// **警告：** 断言没释放会让 Mac 无法空闲睡眠。停止与错误路径都会尝试释放。
final class MacSleepController: NSObject, SleepController {
    private let lock = NSLock()
    private var assertion: IOPMAssertionID = 0
    private var assertionPrevention: IdleSleepPrevention = .none

    /// 缓存规则的权威实现已迁入 Rust core，Swift 适配器只缓存 OS 读取结果。
    ///
    /// 桥接层不向 Swift 导出默认参数，所以 `ttlMillis` 要显式传。
    private let timeoutCache: IdleSleepTimeoutCache

    init(
        clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
        timeoutReader: @escaping () -> Int64? = { PmsetReader.systemIdleSleepTimeoutSeconds() }
    ) {
        timeoutCache = IdleSleepTimeoutCache(
            clock: clock,
            timeoutReader: timeoutReader,
            ttlMillis: IdleSleepTimeoutCache.companion.DEFAULT_TTL_MILLIS
        )
        super.init()
    }

    func sleep() {
        PmsetCommand.run("sleepnow")
    }

    func displaySleep() {
        PmsetCommand.run("displaysleepnow")
    }

    func applyIdleSleepPrevention(prevention requested: IdleSleepPrevention) -> IdleSleepAssertionResult {
        lock.lock()
        defer { lock.unlock() }
        timeoutCache.invalidate()

        if requested == .unknown {
            return IdleSleepAssertionResult(
                requested: requested,
                actual: readAssertionLocked(),
                success: false,
                error: "Unknown idle sleep prevention request"
            )
        }
        if requested == .none {
            return releaseAssertionLocked()
        }

        let currentActual = readAssertionLocked()
        if assertion != 0, assertionPrevention == requested, currentActual == requested {
            return IdleSleepAssertionResult(
                requested: requested,
                actual: currentActual,
                success: true,
                error: nil
            )
        }

        let previousID = assertion
        let previousPrevention = assertionPrevention
        var created: IOPMAssertionID = 0
        let createResult = IOPMAssertionCreateWithName(
            assertionType(for: requested),
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionReason(for: requested),
            &created
        )
        guard createResult == kIOReturnSuccess, created != 0 else {
            return IdleSleepAssertionResult(
                requested: requested,
                actual: readAssertionLocked(),
                success: false,
                error: ioError("IOPMAssertionCreateWithName", createResult)
            )
        }

        if previousID != 0 {
            let releaseResult = IOPMAssertionRelease(previousID)
            guard releaseSucceeded(releaseResult) else {
                IOPMAssertionRelease(created)
                assertion = previousID
                assertionPrevention = previousPrevention
                return IdleSleepAssertionResult(
                    requested: requested,
                    actual: readAssertionLocked(),
                    success: false,
                    error: ioError("IOPMAssertionRelease", releaseResult)
                )
            }
        }

        assertion = created
        assertionPrevention = requested
        let actual = readAssertionLocked()
        if actual == requested {
            return IdleSleepAssertionResult(
                requested: requested,
                actual: actual,
                success: true,
                error: nil
            )
        }

        // 无法验证新断言时释放它。未知状态必须允许系统睡眠。
        let cleanup = IOPMAssertionRelease(created)
        if releaseSucceeded(cleanup) {
            assertion = 0
            assertionPrevention = .none
        }
        let finalActual = readAssertionLocked()
        return IdleSleepAssertionResult(
            requested: requested,
            actual: finalActual,
            success: false,
            error: "Assertion readback mismatch: requested \(requested), actual \(actual)"
        )
    }

    func readIdleSleepPrevention() -> IdleSleepPrevention {
        lock.lock()
        defer { lock.unlock() }
        return readAssertionLocked()
    }

    func systemIdleSleepTimeoutSeconds() -> Int64? {
        lock.lock()
        let prevention = readAssertionLocked()
        lock.unlock()
        let held = prevention == .system || prevention == .systemAndDisplay
        // 已经阻止空闲睡眠时，系统设置无关紧要。
        if held { return nil }
        return timeoutCache.get()
    }

    private func releaseAssertionLocked() -> IdleSleepAssertionResult {
        guard assertion != 0 else {
            return IdleSleepAssertionResult(
                requested: .none,
                actual: .none,
                success: true,
                error: nil
            )
        }
        let releasedID = assertion
        let released = IOPMAssertionRelease(releasedID)
        let didRelease = releaseSucceeded(released)
        if didRelease {
            assertion = 0
            assertionPrevention = .none
        }
        let actual = readAssertionLocked()
        return IdleSleepAssertionResult(
            requested: .none,
            actual: actual,
            success: didRelease && actual == .none,
            error: didRelease
                ? (actual == .none ? nil : "Assertion readback mismatch after release")
                : ioError("IOPMAssertionRelease", released)
        )
    }

    private func readAssertionLocked() -> IdleSleepPrevention {
        guard assertion != 0 else { return .none }
        guard let properties = IOPMAssertionCopyProperties(assertion)?
            .takeRetainedValue() as? [String: Any] else {
            return .unknown
        }
        let level = (properties["AssertLevel"] as? NSNumber)?.int32Value ?? 0
        guard level == Int32(kIOPMAssertionLevelOn) else { return .none }
        let type = properties["AssertType"] as? String ?? ""
        switch type {
        case "PreventUserIdleSystemSleep":
            return .system
        case "PreventUserIdleDisplaySleep":
            return .systemAndDisplay
        default:
            return .unknown
        }
    }

    private func assertionType(for prevention: IdleSleepPrevention) -> CFString {
        if prevention == .systemAndDisplay {
            return "PreventUserIdleDisplaySleep" as CFString
        }
        return "PreventUserIdleSystemSleep" as CFString
    }

    private func assertionReason(for prevention: IdleSleepPrevention) -> CFString {
        if prevention == .systemAndDisplay {
            return "Covio keeps the display and system awake" as CFString
        }
        return "Covio keeps the system awake" as CFString
    }

    private func releaseSucceeded(_ result: IOReturn) -> Bool {
        result == kIOReturnSuccess || result == kIOReturnNotFound
    }

    private func ioError(_ operation: String, _ result: IOReturn) -> String {
        "\(operation) failed with IOReturn 0x\(String(result, radix: 16))"
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }
        if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }
}

/// 子进程调用的统一入口。用于不需要 root 的 `pmset` 与 `osascript`。
///
/// 只关心「跑完」还是「超时」，不收集输出。需要输出的用 `PmsetReader`。
enum PmsetCommand {
    static func run(
        _ arguments: String...,
        executable: String = "/usr/bin/pmset",
        timeout: TimeInterval = 10
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        wait(for: process, timeout: timeout)
    }

    /// 等到进程结束或超时。超时就发 SIGTERM，不无限等。
    static func wait(for process: Process, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning { process.terminate() }
    }
}

extension PmsetReader {
    /// 读 `pmset -g` 里的 `sleep` 值，单位秒。取最小值，因为输出可能有多段。
    ///
    /// 解析规则住在 Rust core，Swift 适配器只负责执行 `pmset`。
    static func systemIdleSleepTimeoutSeconds() -> Int64? {
        guard let text = readConfiguration() else { return nil }
        guard let seconds = PmsetConfigParser.sleepTimeoutSeconds(text: text) else {
            return nil
        }
        return seconds
    }
}

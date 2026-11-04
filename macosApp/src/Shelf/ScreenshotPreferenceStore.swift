import Foundation

/// 一条 `defaults` 命令的结果。
struct PreferenceCommandResult: Equatable, Sendable {
    let exitCode: Int32
    let output: String
}

/// 读取系统截图偏好，并清理旧版接管留下的快照。
///
/// 对应 Compose 版的
/// `app/src/com/wyz/covio/app/platform/ScreenshotPreferenceStore.kt`。
///
/// 系统截图偏好存在 `com.apple.screencapture` 这个 defaults 域里。
/// 新版只读取截图目录。快照只在升级时用于恢复旧版改动。
protocol ScreenshotPreferenceStore: LegacyScreenshotPreferenceRestoring, Sendable {
    func read() -> ScreenshotInboxSnapshot
    func restore(snapshot: ScreenshotInboxSnapshot) -> Bool
    /// macOS 当前保存截图的目录。
    func screenshotDirectory() -> URL
}

/// 走 `/usr/bin/defaults` 的实现。
///
/// 用命令行而不是 `UserDefaults(suiteName:)`，因为命令行写的是系统域，
/// 与 `screencapture` 自己读的是同一份。`UserDefaults` 写应用沙盒里的域，
/// 系统截图不会读到。
final class MacScreenshotPreferenceStore: ScreenshotPreferenceStore, @unchecked Sendable {
    typealias Runner = @Sendable ([String]) -> PreferenceCommandResult

    private let runner: Runner
    private let domain: String
    private let captureDirectoryOverride: URL?

    init(
        domain: String = ScreenshotPreferencePolicy.shared.DOMAIN,
        runner: @escaping Runner = MacScreenshotPreferenceStore.runDefaults,
        captureDirectoryOverride: URL? = MacScreenshotPreferenceStore.environmentCaptureDirectory
    ) {
        self.domain = domain
        self.runner = runner
        self.captureDirectoryOverride = captureDirectoryOverride
    }

    func read() -> ScreenshotInboxSnapshot {
        // 三个键都要保留「不存在」与「值是多少」的区别。
        // `show-thumbnail` 不存在时要记成空，还原时才懂得去删键，而不是写回一个 false。
        ScreenshotInboxSnapshot(
            location: readString(ScreenshotPreferencePolicy.shared.KEY_LOCATION),
            locationScreenshot: readString(ScreenshotPreferencePolicy.shared.KEY_LOCATION_SCREENSHOT),
            showThumbnail: readBoolean(ScreenshotPreferencePolicy.shared.KEY_SHOW_THUMBNAIL)
        )
    }

    func restore(snapshot: ScreenshotInboxSnapshot) -> Bool {
        // 三个都要还原。有一个失败也算失败，但剩下的仍然要试，不能中途退出。
        var ok = true
        ok = restoreValue(
            ScreenshotPreferencePolicy.shared.KEY_LOCATION, value: snapshot.location, isString: true
        ) && ok
        ok = restoreValue(
            ScreenshotPreferencePolicy.shared.KEY_LOCATION_SCREENSHOT,
            value: snapshot.locationScreenshot,
            isString: true
        ) && ok
        let thumbnail = snapshot.showThumbnail.map { $0.boolValue ? "1" : "0" }
        ok = restoreValue(
            ScreenshotPreferencePolicy.shared.KEY_SHOW_THUMBNAIL, value: thumbnail, isString: false
        ) && ok
        return ok
    }

    /// 调试构建可用 `COVIO_SCREENSHOT_CAPTURE_DIR` 指向隔离目录。
    static var environmentCaptureDirectory: URL? {
        guard let value = ProcessInfo.processInfo.environment["COVIO_SCREENSHOT_CAPTURE_DIR"],
              !value.isEmpty
        else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    /// 读取 macOS 27 的截图专用目录。没有设置时回落到桌面。
    func screenshotDirectory() -> URL {
        if let captureDirectoryOverride {
            return captureDirectoryOverride.standardizedFileURL
        }
        let snapshot = read()
        let value = snapshot.locationScreenshot ?? snapshot.location
        guard let value, !value.isEmpty else { return ShelfPaths.desktopDirectory }
        let expanded = (value as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, isDirectory: true)
        return url.standardizedFileURL
    }

    /// 读取一个字符串键。键不存在或输出为空时返回空。
    ///
    /// 引号、空串和退出码的判定规则住在 Rust core 的 screenshot preference policy 里。
    func readString(_ key: String) -> String? {
        let result = runner(["/usr/bin/defaults", "read", domain, key])
        return ScreenshotPreferencePolicy.shared.parseString(
            exitCode: result.exitCode, output: result.output
        )
    }

    /// 读取一个布尔键。取值不认识时返回空，不猜。
    func readBoolean(_ key: String) -> Bool? {
        let result = runner(["/usr/bin/defaults", "read", domain, key])
        return ScreenshotPreferencePolicy.shared.parseBoolean(
            exitCode: result.exitCode, output: result.output
        )?.boolValue
    }

    private func writeString(_ key: String, value: String) -> Bool {
        runner(["/usr/bin/defaults", "write", domain, key, "-string", value]).exitCode == 0
    }

    private func writeBoolean(_ key: String, value: Bool) -> Bool {
        runner([
            "/usr/bin/defaults", "write", domain, key, "-bool", value ? "true" : "false",
        ]).exitCode == 0
    }

    /// 把键还原成快照里的值。快照里没有这个键就删掉它。
    ///
    /// 「值换成哪个字面量」和「删键算不算成功」两条规则住在
    /// Rust core 的 screenshot preference policy 里。
    private func restoreValue(_ key: String, value: String?, isString: Bool) -> Bool {
        if let value {
            let argument = ScreenshotPreferencePolicy.shared.writeArgument(
                value: value, isString: isString
            )
            return runner([
                "/usr/bin/defaults", "write", domain, key, isString ? "-string" : "-bool", argument,
            ]).exitCode == 0
        }
        let result = runner(["/usr/bin/defaults", "delete", domain, key])
        // 键本来就没有时 delete 会报错，这算还原成功。
        return ScreenshotPreferencePolicy.shared.deleteIsSuccess(
            exitCode: result.exitCode, output: result.output
        )
    }

    /// 跑一条 `defaults` 命令。标准错误合并进标准输出，与 Kotlin 版一致。
    ///
    /// 超过五秒就当失败并杀掉进程。超时时长由
    /// `ScreenshotPreferencePolicy.COMMAND_TIMEOUT_MILLIS` 给出。`defaults` 正常在毫秒级返回，
    /// 卡住通常是被系统对话框挡住，继续等没有意义。
    ///
    /// **不要用 `waitUntilExit()`。** 它在等待期间会转运行循环，
    /// 于是主线程上等子进程的时候会插进来别的任务（启动流程里就是这么被插断的），
    /// 而且子进程真的卡住时它永远不返回。这里改用轮询，两件事都没有。
    static let runDefaults: Runner = { command in
        guard let executable = command.first else {
            return PreferenceCommandResult(exitCode: -1, output: "")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return PreferenceCommandResult(exitCode: -1, output: "")
        }

        // 必须先读干净再等进程退出。管道缓冲区满了的话进程会卡在写上，
        // 那时等退出的循环永远不返回。
        let box = OutputBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.store(pipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        let deadline = DispatchTime.now() + .milliseconds(
            Int(ScreenshotPreferencePolicy.shared.COMMAND_TIMEOUT_MILLIS)
        )
        var timedOut = group.wait(timeout: deadline) == .timedOut
        if !timedOut {
            // 管道关了不等于进程走了。退出也要有上限。
            timedOut = !waitForExit(process, until: deadline)
        }
        guard !timedOut else {
            terminate(process)
            return PreferenceCommandResult(exitCode: -1, output: "")
        }

        let text = String(data: box.value, encoding: .utf8) ?? ""
        return PreferenceCommandResult(exitCode: process.terminationStatus, output: text)
    }

    /// 轮询等进程退出。到点还没走就返回假。
    ///
    /// 每个 `defaults` 都在毫秒级返回，所以正常情况第一轮就退出循环。
    private static func waitForExit(_ process: Process, until deadline: DispatchTime) -> Bool {
        while process.isRunning, DispatchTime.now() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        return !process.isRunning
    }

    /// 杀掉超时的子进程并收尸，免得留下僵尸进程。
    ///
    /// **警告：** `kill(0, ...)` 会杀掉整个进程组，包含自己。
    /// 所以进程号无效时直接跳过。
    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        if pid > 0 { kill(pid, SIGKILL) }
        _ = waitForExit(process, until: DispatchTime.now() + .seconds(2))
    }
}

/// 跨线程搬运管道输出。
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

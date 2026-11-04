import Foundation

/// `AppLogger` 端口的 macOS 实现。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/platform/FileAppLogger.kt`。
/// 写到 `~/Library/Application Support/com.wyz.covio/logs/Covio.log`，
/// 超过 5 MB 就轮转，保留 `.1` 到 `.3`。
final class FileAppLogger: NSObject, AppLogger {
    private let lock = NSLock()
    private let directory: URL
    private let file: URL

    static let maxBytes = 5 * 1024 * 1024

    init(directory: URL = AppPaths.supportDirectory.appendingPathComponent("logs", isDirectory: true)) {
        self.directory = directory
        file = directory.appendingPathComponent("Covio.log")
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func info(message: String) {
        write(level: "INFO", message: message, error: nil)
    }

    func warn(message: String, error: KotlinThrowable?) {
        write(level: "WARN", message: message, error: error)
    }

    func error(message: String, error: KotlinThrowable?) {
        write(level: "ERROR", message: message, error: error)
    }

    func logFile() -> String {
        file.path
    }

    // MARK: - 私有

    private func write(level: String, message: String, error: KotlinThrowable?) {
        lock.lock()
        defer { lock.unlock() }
        rotateIfNeeded()
        var line = "\(ISO8601DateFormatter().string(from: Date())) \(level) \(message)"
        if let error { line += ": \(FileAppLogger.describe(error))" }
        line += "\n"
        guard let data = line.data(using: .utf8) else { return }
        append(data)
    }

    /// 与 Kotlin 的 `Throwable.stackTraceToString()` 对齐：
    /// 先写消息，再逐行写栈帧，每行前面加一个制表符。
    ///
    /// `KotlinThrowable` 导出到 Swift 后没有 `stackTraceToString()`，
    /// 只有 `getStackTrace()`。所以这里自己拼。
    static func describe(_ error: KotlinThrowable) -> String {
        error.stackTraceToString()
    }

    private func append(_ data: Data) {
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }

    private func rotateIfNeeded() {
        let manager = FileManager.default
        guard let size = try? manager.attributesOfItem(atPath: file.path)[.size] as? Int,
              size >= Self.maxBytes
        else { return }

        try? manager.removeItem(at: rotated(3))
        for index in stride(from: 2, through: 1, by: -1) {
            let source = rotated(index)
            guard manager.fileExists(atPath: source.path) else { continue }
            try? manager.removeItem(at: rotated(index + 1))
            try? manager.moveItem(at: source, to: rotated(index + 1))
        }
        try? manager.removeItem(at: rotated(1))
        try? manager.moveItem(at: file, to: rotated(1))
    }

    private func rotated(_ index: Int) -> URL {
        directory.appendingPathComponent("Covio.log.\(index)")
    }
}

/// `WakeLogReader` 端口的 macOS 实现。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/platform/PmsetWakeLogReader.kt`。
/// 跑 `pmset -g log` 并把输出交给 Kotlin 的 `PmsetWakeLogParser`。
/// 解析留在共享层，两个平台的结果必然一致。
///
/// 输出可能有几 MB，所以先落到临时文件再读，不占内存管道。
final class PmsetWakeLogReader: NSObject, WakeLogReader {
    private let timeout: TimeInterval
    private let nowEpochSeconds: () -> Int64

    init(
        timeoutMillis: Int64 = 20_000,
        nowEpochSeconds: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }
    ) {
        timeout = TimeInterval(timeoutMillis) / 1_000
        self.nowEpochSeconds = nowEpochSeconds
        super.init()
    }

    func read() -> WakeLogSnapshot? {
        guard timeout > 0 else { return nil }
        guard let text = PmsetWakeLogReader.runPmsetLog(timeout: timeout) else { return nil }
        return PmsetWakeLogParser.parse(text: text, nowEpochSeconds: nowEpochSeconds())
    }

    /// 跑 `pmset -g log`。超时或非零退出返回 nil。
    static func runPmsetLog(timeout: TimeInterval) -> String? {
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("covio-pmset-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else { return nil }
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "log"]
        process.standardInput = FileHandle.nullDevice
        guard let handle = try? FileHandle(forWritingTo: output) else { return nil }
        process.standardOutput = handle
        process.standardError = handle

        guard (try? process.run()) != nil else { return nil }
        PmsetCommand.wait(for: process, timeout: timeout)
        guard !process.isRunning, process.terminationStatus == 0 else { return nil }
        try? handle.close()
        return try? String(contentsOf: output, encoding: .utf8)
    }
}

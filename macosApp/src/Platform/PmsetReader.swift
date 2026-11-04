import Foundation

/// `pmset -g` 的读取。写操作只由 helper 执行。
enum PmsetReader {
    /// 读取当前休眠模式。命令失败、超时或输出不含该键时返回 nil。
    static func hibernateMode(timeout: TimeInterval = 5) -> Int? {
        guard let text = readConfiguration(timeout: timeout) else { return nil }
        guard let mode = PmsetConfigParser.hibernateMode(text: text) else { return nil }
        return Int(mode)
    }

    /// 读当前 `disablesleep`。helper 协议不兼容时由客户端做只读兜底。
    static func sleepDisabled(timeout: TimeInterval = 5) -> Bool? {
        guard let text = readConfiguration(timeout: timeout) else { return nil }
        return PmsetConfigParser.sleepDisabled(text: text)
    }

    /// 跑 `pmset -g` 并返回全部输出。命令失败或超时返回 nil。
    static func readConfiguration(timeout: TimeInterval = 5) -> String? {
        run(["-g"], timeout: timeout)
    }

    private static func run(_ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // 先把输出读完再 waitUntilExit，否则管道写满会互相卡死。
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: output, encoding: .utf8)
    }
}

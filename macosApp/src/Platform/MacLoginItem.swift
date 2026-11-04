import Foundation

/// `LoginItem` 端口的 macOS 实现。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/platform/MacLoginItem.kt`。
/// 写 `~/Library/LaunchAgents/<APP_ID>.plist`，然后用 `launchctl` 注册。
///
/// plist 的内容与 Kotlin 版逐字节相同，所以两版可以互相卸载对方的登录项。
final class MacLoginItem: NSObject, LoginItem {
    private let plistURL: URL
    private let launchctl: ([String]) -> Bool

    init(
        plistURL: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(ModelsKt.APP_ID).plist"),
        launchctl: @escaping ([String]) -> Bool = MacLoginItem.runLaunchctl
    ) {
        self.plistURL = plistURL
        self.launchctl = launchctl
        super.init()
    }

    func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func enable() -> Bool {
        let manager = FileManager.default
        do {
            try manager.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try MacLoginItem.plistText(command: command, arguments: arguments)
                .write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        let domain = "gui/\(MacLoginItem.currentUid())"
        let target = "\(domain)/\(ModelsKt.APP_ID)"
        guard launchctl(["enable", target]) else { return false }
        if launchctl(["print", target]) { return true }
        return launchctl(["bootstrap", domain, plistURL.path])
    }

    func disable() -> Bool {
        try? FileManager.default.removeItem(at: plistURL)
        return launchctl(["disable", "gui/\(MacLoginItem.currentUid())/\(ModelsKt.APP_ID)"])
    }

    /// 命令行形式的启动命令。用于文档与排查，不参与启动。
    func developmentCommand() -> String {
        MacLoginItem.commandLine(command: command, arguments: arguments)
    }

    // MARK: - 私有

    /// 当前进程的启动命令。
    ///
    /// 打包后 `Bundle.main.executableURL` 指向 `.app` 内的可执行文件。
    /// 从命令行直接跑时它指向那个可执行文件本身。
    private var command: String {
        Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? "Covio"
    }

    /// 不用 `ProcessInfo.arguments`：那里面第一个元素是可执行文件路径，会重复。
    private var arguments: [String] { [] }

    // MARK: - 纯函数，可单独测试

    static func plistText(command: String, arguments: [String]) -> String {
        let values = ([command] + arguments)
            .map { "        <string>\(xmlEscape($0))</string>" }
            .joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(ModelsKt.APP_ID)</string>
            <key>ProgramArguments</key>
            <array>
        \(values)
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """
    }

    static func commandLine(command: String, arguments: [String]) -> String {
        ([command] + arguments).map(shellQuote).joined(separator: " ")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func currentUid() -> String {
        String(getuid())
    }

    /// 跑 `launchctl`。超时 5 秒，超时就杀进程并返回 false。
    static func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        // 读完输出再等，否则管道写满会互相卡死。
        _ = pipe.fileHandleForReading.readDataToEndOfFile()
        PmsetCommand.wait(for: process, timeout: 5)
        guard !process.isRunning else { return false }
        return process.terminationStatus == 0
    }
}

/// `UpdateChecker` 端口的 macOS 实现。
///
/// 对应 Compose 版的 `app/src/com/wyz/covio/app/platform/GithubUpdateChecker.kt`。
/// 读 GitHub releases 页面的 HTML，取客户端版本最大的发布。
/// internal build 同时识别 SemVer prerelease 和 stable tag。
/// public build 只识别 stable tag。旧语义版本 tag 继续忽略。
///
/// 解析器是纯函数，测试直接喂 HTML 字符串。
final class GithubUpdateChecker: NSObject, UpdateChecker {
    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(string: "https://github.com/wises231/kmp-Covio/releases")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
        super.init()
    }

    func latestRelease() -> UpdateInfo? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Covio/\(GeneratedReleaseIdentityKt.APP_VERSION)", forHTTPHeaderField: "User-Agent")

        // 端口方法不是 async，所以用信号量把异步请求变同步。
        // 请求有 10 秒超时，信号量再兜 15 秒，不会永久阻塞。
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data,
                  let body = String(data: data, encoding: .utf8)
            else { return }
            box.value = Self.parseRelease(body)
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 15)
        task.cancel()
        return box.value
    }

    /// 跨线程传一次结果。`URLSession` 的回调在别的队列上跑，所以需要加锁。
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: UpdateInfo?

        var value: UpdateInfo? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return stored
            }
            set {
                lock.lock()
                stored = newValue
                lock.unlock()
            }
        }
    }

    /// 从 HTML 里挑出最新的可接受发布。没有匹配时返回 nil。
    static func parseRelease(
        _ body: String,
        includeInternal: Bool = GeneratedReleaseIdentity.channel == "internal"
    ) -> UpdateInfo? {
        let pattern = try? NSRegularExpression(
            pattern: #"href\s*=\s*["']([^"']*?/releases/tag/([^"'/?#]+))["']"#,
            options: [.caseInsensitive]
        )
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        var best: (version: ReleaseVersion, url: String)?
        for match in pattern?.matches(in: body, options: [], range: range) ?? [] {
            guard let pathRange = Range(match.range(at: 1), in: body),
                  let tagRange = Range(match.range(at: 2), in: body),
                  let version = clientVersion(
                      forTag: String(body[tagRange]),
                      includeInternal: includeInternal
                  )
            else { continue }
            let path = String(body[pathRange])
            let url = path.hasPrefix("http") ? path : "https://github.com\(path)"
            if let current = best, current.version >= version { continue }
            best = (version, url)
        }
        guard let best else { return nil }
        return UpdateInfo(
            version: best.version.description,
            title: "Covio \(best.version.description)",
            releaseUrl: best.url,
            publishedAt: ""
        )
    }

    private static func clientVersion(forTag tag: String, includeInternal: Bool) -> ReleaseVersion? {
        guard tag.hasPrefix("v"), let version = ReleaseVersion(String(tag.dropFirst())) else {
            return nil
        }
        if version.isStable {
            return version
        }
        guard includeInternal,
              version.prerelease.count == 2,
              version.prerelease[0] == "internal",
              let build = Int(version.prerelease[1]),
              version.isInternalBuild(build)
        else {
            return nil
        }
        return version
    }
}

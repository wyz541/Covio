import XCTest
@testable import Covio

/// `MacLoginItem` 的断言。
///
/// 登录项写 `~/Library/LaunchAgents/<APP_ID>.plist`，再用 `launchctl` 注册。
/// 测试不碰真的 LaunchAgents 目录，也不跑真的 `launchctl`：
/// plist 路径与命令执行器都是注入的，断言只看写出的 plist 文本与命令序列。
///
/// plist 的内容与旧版逐字节相同，新旧版本可以互相卸载对方的登录项。
/// 所以这里的断言也是兼容性的守卫。
final class LoginItemTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-login-item-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var plistURL: URL {
        directory.appendingPathComponent("\(CovioRuntimeConstants.APP_ID).plist")
    }

    private var target: String {
        "gui/\(MacLoginItem.currentUid())/\(CovioRuntimeConstants.APP_ID)"
    }

    // MARK: - plist 文本

    func testPlistDeclaresTheAppLabelAndProgram() {
        let text = MacLoginItem.plistText(command: "/Applications/Covio.app", arguments: [])
        XCTAssertTrue(text.contains("<string>\(CovioRuntimeConstants.APP_ID)</string>"))
        XCTAssertTrue(text.contains("<string>/Applications/Covio.app</string>"))
        XCTAssertTrue(text.contains("<key>RunAtLoad</key>"))
        XCTAssertTrue(text.contains("<key>KeepAlive</key>"))
        XCTAssertTrue(text.contains("<key>SuccessfulExit</key>"))
        XCTAssertTrue(text.contains("<key>ProcessType</key>"))
    }

    func testPlistKeepsArgumentsInOrder() {
        let text = MacLoginItem.plistText(command: "/usr/bin/java", arguments: ["-jar", "/tmp/app.jar"])
        XCTAssertTrue(text.contains("<string>/usr/bin/java</string>"))
        XCTAssertTrue(text.contains("<string>-jar</string>"))
        XCTAssertTrue(text.contains("<string>/tmp/app.jar</string>"))
    }

    func testPlistIsAValidPropertyList() throws {
        let text = MacLoginItem.plistText(command: "/Applications/Covio.app", arguments: [])
        let parsed = try PropertyListSerialization.propertyList(
            from: Data(text.utf8),
            options: [],
            format: nil
        ) as? [String: Any]
        XCTAssertEqual(parsed?["Label"] as? String, CovioRuntimeConstants.APP_ID)
        XCTAssertEqual(parsed?["ProcessType"] as? String, "Interactive")
    }

    // MARK: - 注册与注销

    /// 先删 plist 再 disable。反过来的话 `launchctl` 会重新写一个出来。
    func testDisableDeletesThePlistBeforeLaunchctlDisable() throws {
        try Data("test".utf8).write(to: plistURL)
        var calls: [[String]] = []
        var plistExistedDuringCall: [Bool] = []
        let item = MacLoginItem(plistURL: plistURL) { arguments in
            calls.append(arguments)
            plistExistedDuringCall.append(FileManager.default.fileExists(atPath: self.plistURL.path))
            return true
        }

        XCTAssertTrue(item.disable())
        XCTAssertEqual(calls, [["disable", target]])
        XCTAssertEqual(plistExistedDuringCall, [false])
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
    }

    func testEnableSkipsBootstrapWhenTheServiceIsLoaded() throws {
        var calls: [[String]] = []
        let item = MacLoginItem(plistURL: plistURL) { arguments in
            calls.append(arguments)
            return true
        }

        XCTAssertTrue(item.enable())
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0], ["enable", target])
        XCTAssertEqual(calls[1], ["print", target])
    }

    func testEnableBootstrapsWhenTheServiceIsNotLoaded() throws {
        var calls: [[String]] = []
        let item = MacLoginItem(plistURL: plistURL) { arguments in
            calls.append(arguments)
            return arguments.first != "print"
        }

        XCTAssertTrue(item.enable())
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(calls[0], ["enable", target])
        XCTAssertEqual(calls[1], ["print", target])
        XCTAssertEqual(calls[2], ["bootstrap", "gui/\(MacLoginItem.currentUid())", plistURL.path])
    }

    // MARK: - 纯函数

    func testXmlEscapingNeutralizesMarkupCharacters() {
        XCTAssertEqual(
            MacLoginItem.xmlEscape("a&b<c>d\"e'f"),
            "a&amp;b&lt;c&gt;d&quot;e&apos;f"
        )
    }

    func testShellQuotingWrapsValuesWithSpaces() {
        XCTAssertEqual(
            MacLoginItem.commandLine(command: "/Applications/Lid SleepX.app", arguments: []),
            "'/Applications/Lid SleepX.app'"
        )
    }

    func testDevelopmentCommandIsNotEmpty() {
        let item = MacLoginItem(plistURL: plistURL) { _ in true }
        XCTAssertFalse(item.developmentCommand().isEmpty)
    }
}

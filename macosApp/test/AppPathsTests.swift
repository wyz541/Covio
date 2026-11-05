import XCTest
@testable import Covio

/// 新旧版本共存的路径测试。
///
/// 当前宿主与旧版宿主共用数据目录与 `config.json`，只有锁文件名不同。
final class AppPathsTests: XCTestCase {
    func testSupportDirectoryMatchesTheLegacyLocation() {
        XCTAssertEqual(AppPaths.appID, "com.wyz.covio")
        XCTAssertTrue(AppPaths.supportDirectory.path.hasSuffix("Application Support/com.wyz.covio"))
    }

    func testSupportDirectoryCanBeIsolatedForBundleVerification() {
        let expected = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-support-\(UUID().uuidString)", isDirectory: true)
        let actual = AppPaths.supportDirectory(
            environment: ["COVIO_SUPPORT_DIR": expected.path]
        )
        XCTAssertEqual(actual.path, expected.path)
    }

    func testBothVersionsUseDifferentLockFiles() {
        XCTAssertNotEqual(AppPaths.lockFile, AppPaths.legacyLockFile)
        XCTAssertEqual(AppPaths.lockFile.lastPathComponent, "app.swiftui.lock")
        XCTAssertEqual(AppPaths.legacyLockFile.lastPathComponent, "app.lock")
    }

    func testPowerHistorySitsInTheSupportDirectory() {
        XCTAssertEqual(
            AppPaths.powerHistoryFile.deletingLastPathComponent().lastPathComponent,
            "Power"
        )
        XCTAssertEqual(AppPaths.powerHistoryFile.lastPathComponent, "history.json")
        XCTAssertEqual(
            AppPaths.powerHistoryFile.deletingLastPathComponent().deletingLastPathComponent(),
            AppPaths.supportDirectory
        )
    }

    func testLocalModelRegistrySitsInTheSupportDirectory() {
        XCTAssertEqual(AppPaths.localModelPackagesFile.deletingLastPathComponent().lastPathComponent, "Models")
        XCTAssertEqual(AppPaths.localModelPackagesFile.lastPathComponent, "imported-packages.json")
        XCTAssertEqual(
            AppPaths.localModelPackagesFile.deletingLastPathComponent().deletingLastPathComponent(),
            AppPaths.supportDirectory
        )
    }

    func testAgentHistorySitsInTheSupportDirectory() {
        XCTAssertEqual(
            AppPaths.agentHistoryFile.deletingLastPathComponent().lastPathComponent,
            "Agent"
        )
        XCTAssertEqual(AppPaths.agentHistoryFile.lastPathComponent, "history.sqlite3")
        XCTAssertEqual(
            AppPaths.agentHistoryFile.deletingLastPathComponent().deletingLastPathComponent(),
            AppPaths.supportDirectory
        )
    }

    func testMonitorHistorySitsInTheSupportDirectory() {
        XCTAssertEqual(
            AppPaths.monitorHistoryFile.deletingLastPathComponent().lastPathComponent,
            "Monitor"
        )
        XCTAssertEqual(AppPaths.monitorHistoryFile.lastPathComponent, "history.sqlite")
        XCTAssertEqual(
            AppPaths.monitorHistoryFile.deletingLastPathComponent().deletingLastPathComponent(),
            AppPaths.supportDirectory
        )
    }

    func testBothVersionsShareTheSameConfigFile() {
        // M2 要求 config.json 与 0.4.2 双向兼容，所以必须指向同一个文件。
        XCTAssertEqual(AppPaths.configFile.lastPathComponent, "config.json")
        XCTAssertEqual(AppPaths.configFile.deletingLastPathComponent(), AppPaths.supportDirectory)
    }

    func testEnsureSupportDirectoryCreatesTheFolder() throws {
        XCTAssertTrue(AppPaths.ensureSupportDirectory())
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: AppPaths.supportDirectory.path,
            isDirectory: &isDirectory
        )
        XCTAssertTrue(exists)
        XCTAssertTrue(isDirectory.boolValue)
    }

    /// 同一进程重复取锁是幂等的。
    func testLockIsReentrantWithinOneProcess() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-test-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: url) }

        let lock = SingleInstanceLock(url: url)
        XCTAssertTrue(lock.acquire())
        XCTAssertTrue(lock.isAcquired)
        XCTAssertTrue(lock.acquire(), "同一实例重复取锁应该直接成功")

        lock.release()
        XCTAssertFalse(lock.isAcquired)
    }

    /// 锁被另一个实例持有时取锁失败。`flock` 按打开的文件描述算，所以同一进程的
    /// 两次 `open()` 也会互斥。
    func testLockIsExclusiveAcrossDescriptors() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-test-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = SingleInstanceLock(url: url)
        XCTAssertTrue(first.acquire())

        let second = SingleInstanceLock(url: url)
        XCTAssertFalse(second.acquire(), "第二个实例不应该拿到锁")

        first.release()
        XCTAssertTrue(second.acquire(), "锁释放后第二个实例应该能拿到")
        second.release()
    }

    /// 两版共存的直接证明：同时持有两个 lock 文件。
    func testBothVersionsCanHoldTheirLocksAtTheSameTime() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-coexist-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let current = SingleInstanceLock(url: directory.appendingPathComponent(AppPaths.swiftUILockFileName))
        let legacy = SingleInstanceLock(url: directory.appendingPathComponent(AppPaths.legacyLockFileName))

        XCTAssertTrue(current.acquire(), "当前版本应该拿到自己的锁")
        XCTAssertTrue(legacy.acquire(), "旧版应该能同时拿到自己的锁")
        XCTAssertTrue(current.isAcquired)
        XCTAssertTrue(legacy.isAcquired)

        // 但同一版仍然只有一个实例。
        let secondCurrent = SingleInstanceLock(
            url: directory.appendingPathComponent(AppPaths.swiftUILockFileName)
        )
        XCTAssertFalse(secondCurrent.acquire(), "当前版本的第二个实例不应该拿到锁")

        current.release()
        legacy.release()
    }
}

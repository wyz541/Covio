import Foundation

/// 应用用到的文件路径。
///
/// 数据目录是 `~/Library/Application Support/com.wyz.covio/`。
/// 当前宿主与旧版宿主使用不同的锁文件名，所以两个版本可以同时运行。
enum AppPaths {
    /// 固定的应用标识。
    static let appID = "com.wyz.covio"

    /// 旧版宿主使用的锁文件名。
    static let legacyLockFileName = "app.lock"
    /// SwiftUI 版用的 lock 文件名。两版不同，所以可以同时运行。
    static let swiftUILockFileName = "app.swiftui.lock"

    /// `~/Library/Application Support/com.wyz.covio`。
    ///
    /// 调试构建可用 `COVIO_SUPPORT_DIR` 指向隔离目录。
    /// 真机验收因此能同时运行第二个实例，不碰正在使用的配置与锁。
    static var supportDirectory: URL {
        supportDirectory(environment: ProcessInfo.processInfo.environment)
    }

    static func supportDirectory(environment: [String: String]) -> URL {
        if let override = environment["COVIO_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let root = base.first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return root.appendingPathComponent(appID, isDirectory: true)
    }

    /// 两版共用的配置文件。M2 要求它与 0.4.2 双向兼容。
    static var configFile: URL {
        supportDirectory.appendingPathComponent("config.json")
    }

    /// 电源事件历史。固定上限，原子写入。
    static var powerHistoryFile: URL {
        supportDirectory
            .appendingPathComponent("Power", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    /// Experimental private-brightness recovery record.
    static var closedLidBrightnessRecoveryFile: URL {
        supportDirectory
            .appendingPathComponent("Power", isDirectory: true)
            .appendingPathComponent("zero-brightness-recovery.json")
    }

    /// 工作台配置。工作区顺序与首页组件都在这里。
    ///
    /// 权威路径由 Rust core 的 data layout 定义，这里跟着它走。
    /// 与 `config.json` 分两个文件：工作台配置损坏时只回退布局，不动用户设置。
    static var workbenchFile: URL {
        supportDirectory.appendingPathComponent("workbench.json")
    }

    /// 用户导入的本地模型包注册表。
    static var localModelPackagesFile: URL {
        localModelsDirectory
            .appendingPathComponent("imported-packages.json")
    }

    /// 下载中和已安装模型共用的 Application Support 根目录。
    static var localModelsDirectory: URL {
        supportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    /// 模型下载状态和 Hub 暂存目录。
    static var localModelDownloadsDirectory: URL {
        localModelsDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// 通过 app 内下载器安装的模型包目录。
    static var localModelPackagesDirectory: URL {
        localModelsDirectory.appendingPathComponent("Packages", isDirectory: true)
    }

    /// Agent 会话与工具审计的本地 SQLite 数据库。
    static var agentHistoryFile: URL {
        supportDirectory
            .appendingPathComponent("Agent", isDirectory: true)
            .appendingPathComponent("history.sqlite3")
    }

    /// Monitor 历史性能样本的本地 SQLite 数据库。
    static var monitorHistoryFile: URL {
        supportDirectory
            .appendingPathComponent("Monitor", isDirectory: true)
            .appendingPathComponent("history.sqlite")
    }

    /// 文件重命名的撤销计划。每条计划在改名之前写入。
    static var renameUndoDirectory: URL {
        supportDirectory.appendingPathComponent("rename-undo", isDirectory: true)
    }

    /// SwiftUI 版的单实例锁文件。
    static var lockFile: URL {
        supportDirectory.appendingPathComponent(swiftUILockFileName)
    }

    /// 旧版宿主的单实例锁文件。只用于兼容测试与迁移脚本。
    static var legacyLockFile: URL {
        supportDirectory.appendingPathComponent(legacyLockFileName)
    }

    /// 剪切板条目的落盘目录。
    ///
    /// 与截图索引同一个写法：用 `Covio` 而不是 `com.wyz.covio`，
    /// 二进制文件都放在 `~/Library/Application Support/Covio/` 下。
    /// 权威路径由 Rust core 的 data layout 定义，这里跟着它走。
    static var clipboardDirectory: URL {
        let root = supportDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Covio", isDirectory: true)
        return root.appendingPathComponent("Clipboard", isDirectory: true)
    }

    /// 剪切板状态文件。
    static var clipboardFile: URL {
        clipboardDirectory.appendingPathComponent("clipboard.json")
    }

    /// 确保数据目录存在。
    @discardableResult
    static func ensureSupportDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            return false
        }
    }
}

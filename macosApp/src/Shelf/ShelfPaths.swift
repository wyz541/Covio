import Foundation

/// 截图库用到的路径。
///
/// 与 Rust core 的 Apple data layout 一致。
///
/// 注意应用数据目录用的是应用名 `Covio`，配置目录用的是 bundle id `com.wyz.covio`。
/// 两者不同，这是 0.4.2 的既有布局，不能改，否则老用户的截图索引会找不到。
enum ShelfPaths {
    /// 应用数据目录名。用应用名，不用 bundle id。
    static let directoryName = "Covio"
    static let screenshotsDirectoryName = "Screenshots"
    /// 截图索引文件名。
    static let storeFileName = "shelf.json"

    static var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// `~/Library/Application Support/Covio/Screenshots`。
    ///
    /// 旧版截图接管曾把截图存到这里。现在只保存截图索引。
    /// 调试构建可用 `COVIO_SCREENSHOT_INDEX_DIR` 指向隔离目录。
    static var screenshotsDirectory: URL {
        screenshotsDirectory(environment: ProcessInfo.processInfo.environment)
    }

    static func screenshotsDirectory(environment: [String: String]) -> URL {
        if let override = environment["COVIO_SCREENSHOT_INDEX_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(screenshotsDirectoryName, isDirectory: true)
    }

    /// `~/Library/Application Support/Covio/Screenshots/shelf.json`。
    static var storeFile: URL {
        screenshotsDirectory.appendingPathComponent(storeFileName)
    }

    /// `~/Desktop`。系统截图默认存这里。
    static var desktopDirectory: URL {
        home.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// `~/.Trash`。系统回收站不可用时的退路。
    static var trashDirectory: URL {
        home.appendingPathComponent(".Trash", isDirectory: true)
    }
}

import Foundation

/// 工作区用到的路径。
///
/// 权威是 Rust core 的 `WorkspaceStore.defaultDirectory()`。
/// 这里不自行拼接 `Library/Application Support`，而是读取共享层提供的路径。
/// 与 `ShelfPaths` 的差别就在这里：应用数据目录是 0.4.2 的既有布局，只能在 Swift 里写死。
enum WorkspacePaths {
    /// `<应用数据根>/Covio/Workspace`。
    static var workspaceDirectory: URL {
        URL(fileURLWithPath: WorkspaceStore.companion.defaultDirectory(), isDirectory: true)
    }

    /// 索引文件。
    static var indexFile: URL {
        workspaceDirectory.appendingPathComponent("index.json")
    }
}

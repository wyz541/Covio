import AppKit
import Foundation

/// 截图库读取外部世界的入口。
@MainActor
struct ScreenshotLibraryEnvironment {
    /// macOS 当前保存截图的目录。
    var screenshotDirectory: @MainActor @Sendable () -> URL = { ShelfPaths.desktopDirectory }
    /// 当前时间，秒。用单调时钟，不受用户修改系统时间影响。
    var now: @MainActor @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
}

/// 旧截图接管留下的偏好快照。
protocol LegacyScreenshotPreferenceRestoring {
    func restore(snapshot: ScreenshotInboxSnapshot) -> Bool
}

/// 截图库。
///
/// 职责只有三项：
/// - 监视 macOS 的截图目录。
/// - 把截图路径保存在 `shelf.json`。
/// - 给文件区提供复制、打开、标记和移除动作。
///
/// Covio 不修改 `com.apple.screencapture`，不显示顶部挂帘，也不播放截图音效。
@MainActor
@Observable
final class ShelfRuntime {
    /// 截图列表，最旧的在前。
    private(set) var items: [ShelfItem] = []

    private let store: ShelfStoreClient
    private let preferences: LegacyScreenshotPreferenceRestoring
    private let environment: ScreenshotLibraryEnvironment
    private let watcherFactory: ScreenshotWatcherFactory

    /// 出错时给用户看的一句话。`AppRuntime` 启动后接到自己的状态栏提示上。
    var onError: (@MainActor (LocalizedCopy) -> Void)?

    private var watchers: [ScreenshotWatching] = []
    private var started = false

    init(
        store: ShelfStoreClient,
        preferences: LegacyScreenshotPreferenceRestoring,
        environment: ScreenshotLibraryEnvironment = ScreenshotLibraryEnvironment(),
        watcherFactory: @escaping ScreenshotWatcherFactory = ScreenshotWatcher.make
    ) {
        self.store = store
        self.preferences = preferences
        self.environment = environment
        self.watcherFactory = watcherFactory
        items = store.load().items
    }

    /// 启动截图目录监听。可以重复调用，第二次没有副作用。
    func start() {
        guard !started else { return }
        started = true
        restoreLegacyTakeover()
        items = store.load().items
        startWatcher()
        refreshExistingFiles()
    }

    /// 停止截图目录监听。
    func stop() {
        started = false
        stopWatchers()
    }

    // MARK: - 文件动作

    func copyItem(_ item: ShelfItem) {
        guard ShelfClipboard.copy(URL(fileURLWithPath: item.path)) else {
            onError?(ContractCopy.copyTopShelfErrorCopy)
            return
        }
    }

    func openItem(_ item: ShelfItem) {
        let url = URL(fileURLWithPath: item.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            onError?(ContractCopy.copyTopShelfErrorOpen)
            return
        }
        guard NSWorkspace.shared.open(url) else {
            onError?(ContractCopy.copyTopShelfErrorOpen)
            return
        }
    }

    /// 用系统标记工具打开。工具不可用时退回预览。
    func markupItem(_ item: ShelfItem) {
        let url = URL(fileURLWithPath: item.path)
        let name = NSSharingService.Name("com.apple.MarkupUI.Markup")
        if let service = NSSharingService(named: name), service.canPerform(withItems: [url]) {
            service.perform(withItems: [url])
            return
        }
        guard NSWorkspace.shared.open(url) else {
            onError?(ContractCopy.copyTopShelfErrorMarkup)
            return
        }
    }

    /// 从截图列表移除。只改索引，不删除磁盘文件。
    func removeItem(_ item: ShelfItem) {
        let normalized = ShelfStore.companion.canonicalPath(value: item.path)
        items = items.filter {
            ShelfStore.companion.canonicalPath(value: $0.path) != normalized
        }
        persist()
    }

    /// 清空截图索引。预览与测试使用。
    func clearItems() {
        items = []
        persist()
    }

    // MARK: - 自动发现

    /// 新截图落盘。只更新列表和索引。
    func addItem(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let normalized = ShelfStore.companion.canonicalPath(value: url.path)
        let item = ShelfItem(path: normalized, addedAtEpochSeconds: Int64(environment.now()))
        let kept = items.filter {
            ShelfStore.companion.canonicalPath(value: $0.path) != normalized
        }
        let updated = ShelfStore.companion.normalizeItems(
            items: kept + [item],
            limit: Int32(ShelfStoreClient.maxItems),
            exists: { _ in true }
        )
        guard updated.map(\.path) != items.map(\.path) else { return }
        items = updated
        persist()
    }

    /// 文件被外部删掉后，从列表中移除。
    func refreshExistingFiles() {
        let snapshot = items
        guard !snapshot.isEmpty else { return }
        let paths = snapshot.map(\.path)
        Task { @MainActor in
            let surviving = await Task.detached(priority: .utility) {
                Set(paths.filter { FileManager.default.fileExists(atPath: $0) })
            }.value
            let trimmed = ShelfStore.companion.normalizeItems(
                items: items,
                limit: Int32(ShelfStoreClient.maxItems),
                exists: { surviving.contains($0) }
            )
            guard trimmed.map(\.path) != items.map(\.path) else { return }
            items = trimmed
            persist()
        }
    }

    // MARK: - 私有

    /// 恢复旧版本接管改写的系统截图设置。快照成功后立即清空。
    private func restoreLegacyTakeover() {
        let state = store.load()
        guard let snapshot = state.preferenceSnapshot else { return }
        guard preferences.restore(snapshot: snapshot) else {
            onError?(ContractCopy.copyTopShelfErrorRestore)
            return
        }
        store.save(
            state.doCopy(
                items: state.items,
                revealed: true,
                preferenceSnapshot: nil
            )
        )
    }

    private func startWatcher() {
        stopWatchers()
        guard started else { return }
        let directory = environment.screenshotDirectory()
        let watcher = watcherFactory(
            directory,
            ShelfPaths.screenshotsDirectory,
            true,
            { [weak self] url in self?.addItem(at: url) },
            { [weak self] in self?.refreshExistingFiles() }
        )
        watcher.start()
        watchers = [watcher]
    }

    private func stopWatchers() {
        watchers.forEach { $0.close() }
        watchers = []
    }

    /// 落盘。旧状态中的其它字段原样保留。
    private func persist() {
        let state = store.load()
        store.save(
            state.doCopy(
                items: items,
                revealed: state.revealed,
                preferenceSnapshot: state.preferenceSnapshot
            )
        )
    }
}

/// 监视器的接口。测试传假的，不必真的动文件系统。
@MainActor
protocol ScreenshotWatching: AnyObject {
    func start()
    func close()
}

extension ScreenshotWatcher: ScreenshotWatching {}

/// 造监视器。参数依次是监视目录、专属目录、是否要求截图属性、两个回调。
typealias ScreenshotWatcherFactory = @MainActor (
    URL,
    URL,
    Bool,
    @escaping (URL) -> Void,
    @escaping () -> Void
) -> ScreenshotWatching

extension ScreenshotWatcher {
    /// 默认的监视器工厂。
    static let make: ScreenshotWatcherFactory = { directory, dedicated, requireAttribute, onNew, onChange in
        ScreenshotWatcher(
            directory: directory,
            dedicatedDirectory: dedicated,
            requireScreenCaptureAttribute: requireAttribute,
            onNew: onNew,
            onChange: onChange
        )
    }
}

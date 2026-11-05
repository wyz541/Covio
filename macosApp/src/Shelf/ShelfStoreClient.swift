import Foundation

/// 截图索引状态的持久化。
///
/// 对应 Rust core 的 shelf store。
/// 实现只有一份，在 Rust core 里，这里只是把它包成 Swift 用起来顺手的样子。
///
/// 存储位置是 `~/Library/Application Support/Covio/Screenshots/shelf.json`。
/// 新旧版本共用这一个文件，所以读写都经过 Rust core，不能在 Swift 里另写一套序列化。
final class ShelfStoreClient: @unchecked Sendable {
    private let store: ShelfStore
    private let lock = NSLock()

    /// 按路径构造。测试用临时目录。
    init(path: String) {
        store = ShelfStore.companion.create(path: path)
    }

    /// 按默认位置构造。
    convenience init() {
        self.init(path: ShelfPaths.storeFile.path)
    }

    /// 读取状态。文件不存在或者内容坏了都返回空状态，不抛错。
    func load() -> ShelfStoreState {
        lock.lock()
        defer { lock.unlock() }
        return store.load()
    }

    /// 写入状态，返回规范化之后的状态。
    @discardableResult
    func save(_ state: ShelfStoreState) -> ShelfStoreState {
        lock.lock()
        defer { lock.unlock() }
        return store.save(state: state)
    }

    /// 删除状态文件。清除配置时用。
    @discardableResult
    func clear() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return store.clear()
    }

    /// 截图索引条目上限。
    static var maxItems: Int {
        Int(ShelfStore.companion.MAX_ITEMS)
    }

    /// 底下那份共享层实现。
    ///
    /// 给需要直接拿 `ShelfStore` 的调用方用。
    /// **不要另建实例**：两个实例写同一个 `shelf.json` 会互相覆盖。
    var sharedStore: ShelfStore { store }

    /// 空状态。
    static var emptyState: ShelfStoreState {
        ShelfStoreState.companion.defaults()
    }
}

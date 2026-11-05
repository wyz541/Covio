import Foundation

/// 工作区状态的持久化。
///
/// 对应 Rust core 的 workspace store。
/// 实现只有一份，在 Rust core 里，这里只是把它包成 Swift 用起来顺手的样子。
///
/// 存储位置是 `<应用数据根>/Covio/Workspace/`。索引与内容都由 Rust core 读写，
/// 不能在 Swift 里另写一套。
///
/// 每一项都拿同一把锁：`WorkspaceRuntime` 在主线程上跑，但内容落盘与淘汰可能在别处触发。
final class WorkspaceStoreClient: @unchecked Sendable {
    let store: WorkspaceStore
    private let lock = NSLock()

    /// 按目录构造。测试用临时目录。
    init(directory: String) {
        store = WorkspaceStore.companion.create(directory: directory)
    }

    /// 按默认位置构造。
    convenience init() {
        self.init(directory: WorkspacePaths.workspaceDirectory.path)
    }

    /// 保存索引。索引里的策略就是后续判断的依据，所以换策略也走这里。
    @discardableResult
    func save(_ state: WorkspaceState) -> WorkspaceState {
        lock.lock()
        defer { lock.unlock() }
        return store.save(state: state)
    }

    /// 读取索引。文件不存在或者内容坏了都返回空状态，不抛错。
    func load() -> WorkspaceState {
        lock.lock()
        defer { lock.unlock() }
        return store.load()
    }

    /// 放入一个文件。返回新的索引状态与这一次的判断结果。
    func putFile(
        state: WorkspaceState,
        sourcePath: String,
        displayName: String,
        contentType: String,
        originDeviceId: String,
        nowEpochSeconds: Int64
    ) -> WorkspacePutResult {
        lock.lock()
        defer { lock.unlock() }
        return store.putFile(
            state: state,
            sourcePath: sourcePath,
            displayName: displayName,
            contentType: contentType,
            originDeviceId: originDeviceId,
            nowEpochSeconds: nowEpochSeconds
        )
    }

    /// 放入一段文字。没有落盘文件的条目走这里。
    func putText(
        state: WorkspaceState,
        text: String,
        displayName: String,
        contentType: String,
        originDeviceId: String,
        nowEpochSeconds: Int64
    ) -> WorkspacePutResult {
        lock.lock()
        defer { lock.unlock() }
        return store.putText(
            state: state,
            text: text,
            displayName: displayName,
            contentType: contentType,
            originDeviceId: originDeviceId,
            nowEpochSeconds: nowEpochSeconds
        )
    }

    /// 改一条条目的置顶标记。
    func setPinned(state: WorkspaceState, entryId: String, pinned: Bool) -> WorkspaceState {
        lock.lock()
        defer { lock.unlock() }
        return store.setPinned(state: state, entryId: entryId, pinned: pinned)
    }

    /// 只改条目可用性，不改内容与排序字段。
    func setAvailability(
        state: WorkspaceState,
        entryId: String,
        availability: WorkspaceAvailability
    ) -> WorkspaceState {
        let entries = state.entries.map { entry in
            entry.entryId == entryId ? entry.withAvailability(availability) : entry
        }
        return save(state.doCopy(schemaVersion: state.schemaVersion, entries: entries, policy: state.policy))
    }

    /// 启动时把没有内存任务接管的 FETCHING 状态恢复为 REMOTE。
    func clearOrphanedFetching(
        state: WorkspaceState,
        activeEntryIds: Set<String>
    ) -> WorkspaceState {
        var changed = false
        let entries = state.entries.map { entry in
            guard entry.availability == WorkspaceAvailability.fetching,
                  !activeEntryIds.contains(entry.entryId)
            else { return entry }
            changed = true
            return entry.withAvailability(WorkspaceAvailability.remote)
        }
        guard changed else { return state }
        return save(state.doCopy(schemaVersion: state.schemaVersion, entries: entries, policy: state.policy))
    }

    /// 删掉一条条目及其内容，并留下删除标记。
    func remove(state: WorkspaceState, entryId: String, nowEpochSeconds: Int64) -> WorkspaceState {
        lock.lock()
        defer { lock.unlock() }
        return store.remove(state: state, entryId: entryId, nowEpochSeconds: nowEpochSeconds)
    }

    /// 执行一次过期与淘汰。
    func sweep(policy: WorkspacePolicy, nowEpochSeconds: Int64) -> WorkspacePlan {
        lock.lock()
        defer { lock.unlock() }
        return store.sweep(policy: policy, nowEpochSeconds: nowEpochSeconds)
    }

    /// 清空工作区。清除配置时用。
    @discardableResult
    func clear() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return store.clear()
    }

    /// 一条条目内容的落盘位置。摘要不合法、或者本机没有内容时返回 nil。
    func contentPath(entryId: String) -> String? {
        guard let path = store.contentPath(entryId: entryId), store.hasContent(entryId: entryId) else {
            return nil
        }
        return path
    }

    /// 界面上的排列顺序。顺序规则在 Rust core 里，由各平台共用。
    static func displayOrder(_ state: WorkspaceState) -> [WorkspaceEntry] {
        WorkspaceLogic.shared.displayOrder(entries: state.entries)
    }

    /// 本机内容占用的字节数。
    static func localBytes(_ state: WorkspaceState) -> Int64 {
        state.entries.reduce(0) { total, entry in total + entry.localBytes }
    }

    /// 空状态。
    static var emptyState: WorkspaceState {
        WorkspaceState.companion.defaults()
    }
}

private extension WorkspaceEntry {
    func withAvailability(_ availability: WorkspaceAvailability) -> WorkspaceEntry {
        doCopy(
            entryId: entryId,
            kind: kind,
            displayName: displayName,
            byteSize: byteSize,
            contentType: contentType,
            createdAtEpochSeconds: createdAtEpochSeconds,
            originDeviceId: originDeviceId,
            expiresAtEpochSeconds: expiresAtEpochSeconds,
            availability: availability,
            pinned: pinned
        )
    }
}

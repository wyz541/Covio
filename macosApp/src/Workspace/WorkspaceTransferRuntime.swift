import Foundation
import Observation

/// 传输方向。首版界面只启动下载，上传也保留在模型里供复制引擎接入。
enum WorkspaceTransferDirection: String, Sendable {
    case upload
    case download
}

/// 短期传输状态。任务只活在本次启动内。
enum WorkspaceTransferPhase: String, Sendable {
    case waiting
    case transferring
    case failed
    case cancelled
}

/// 线格式错误码的 Swift 镜像。
enum WorkspaceTransferFailure: String, Sendable {
    case quotaExceeded = "quota_exceeded"
    case storageFull = "storage_full"
    case connectionFailed = "connection_failed"
    case entryMissing = "entry_not_found"
}

/// 一条内容对应的唯一传输任务。
struct WorkspaceTransferTask: Identifiable, Equatable, Sendable {
    let entryId: String
    let direction: WorkspaceTransferDirection
    let peerDeviceId: String
    let totalBytes: Int64
    var phase: WorkspaceTransferPhase
    var transferredBytes: Int64
    var failure: WorkspaceTransferFailure?

    var id: String { entryId }
    var errorCode: String? { failure?.rawValue }
    var progress: Double {
        guard totalBytes > 0 else { return phase == .transferring ? 1 : 0 }
        return min(1, max(0, Double(transferredBytes) / Double(totalBytes)))
    }
}

/// 文件区传输运行时要用的外部能力。测试传假的可用空间。
@MainActor
struct WorkspaceTransferEnvironment {
    var availableBytes: () -> Int64 = {
        let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: WorkspacePaths.workspaceDirectory.path
        )
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }
}

/// 临时传输任务表。
///
/// 任务以内容摘要为键，不复制 `FileAreaItem`。界面只把任务叠加在原条目上。
@MainActor
@Observable
final class WorkspaceTransferRuntime {
    private(set) var tasks: [String: WorkspaceTransferTask] = [:]

    private let workspace: WorkspaceRuntime
    private let environment: WorkspaceTransferEnvironment

    init(
        workspace: WorkspaceRuntime,
        environment: WorkspaceTransferEnvironment = WorkspaceTransferEnvironment()
    ) {
        self.workspace = workspace
        self.environment = environment
        // 传输任务只在内存里。启动时不存在能接管旧 FETCHING 状态的任务。
        workspace.reconcileOrphanedTransfers(activeEntryIds: [])
    }

    /// 正在等待或传输中的内容摘要。
    var activeEntryIDs: Set<String> {
        Set(tasks.values.compactMap { task in
            switch task.phase {
            case .waiting, .transferring: task.entryId
            case .failed, .cancelled: nil
            }
        })
    }

    var activeCount: Int { activeEntryIDs.count }

    func task(for entryId: String) -> WorkspaceTransferTask? {
        tasks[entryId]
    }

    /// 开始下载。同一内容重复开始只更新同一条任务。
    @discardableResult
    func beginDownload(_ entryId: String) -> Bool {
        guard let entry = workspace.entries.first(where: { $0.entryId == entryId }) else {
            return false
        }
        guard entry.availability != WorkspaceAvailability.local else { return false }
        return start(entry: entry, direction: .download)
    }

    /// 标记传输层已经连上，开始移动字节。
    func markTransferring(_ entryId: String) {
        guard var task = tasks[entryId],
              task.phase == .waiting || task.phase == .transferring
        else { return }
        task.phase = .transferring
        task.failure = nil
        tasks[entryId] = task
    }

    /// 更新已收到或已发送的字节数。
    func updateProgress(_ entryId: String, transferredBytes: Int64) {
        guard var task = tasks[entryId],
              task.phase == .waiting || task.phase == .transferring
        else { return }
        task.transferredBytes = max(0, min(transferredBytes, task.totalBytes))
        task.phase = task.transferredBytes > 0 ? .transferring : .waiting
        task.failure = nil
        tasks[entryId] = task
    }

    /// 记录失败。条目回到 REMOTE，用户可以从同一卡片重试。
    func fail(_ entryId: String, error: WorkspaceTransferFailure) {
        guard var task = tasks[entryId] else { return }
        task.phase = .failed
        task.failure = error
        tasks[entryId] = task
        workspace.setAvailability(.remote, for: entryId)
    }

    /// 取消后保留任务，显示取消状态并让用户重试。
    func cancel(_ entryId: String) {
        guard var task = tasks[entryId] else { return }
        task.phase = .cancelled
        task.transferredBytes = 0
        task.failure = nil
        tasks[entryId] = task
        workspace.setAvailability(.remote, for: entryId)
    }

    /// 重试沿用同一任务与同一对端。空间不足时直接进入失败状态。
    @discardableResult
    func retry(_ entryId: String) -> Bool {
        guard let existing = tasks[entryId],
              let entry = workspace.entries.first(where: { $0.entryId == entryId })
        else { return false }
        return start(entry: entry, direction: existing.direction, peerDeviceId: existing.peerDeviceId)
    }

    /// 成功提交后移除临时任务，并把条目改为本机可用。
    func complete(_ entryId: String) {
        tasks.removeValue(forKey: entryId)
        workspace.setAvailability(.local, for: entryId)
    }

    /// 删除条目时同步丢弃临时任务。删除本身由工作区执行。
    func discard(_ entryId: String) {
        tasks.removeValue(forKey: entryId)
    }

    private func start(
        entry: WorkspaceEntry,
        direction: WorkspaceTransferDirection,
        peerDeviceId: String? = nil
    ) -> Bool {
        let required = max(0, entry.byteSize)
        let available = environment.availableBytes()
        var task = WorkspaceTransferTask(
            entryId: entry.entryId,
            direction: direction,
            peerDeviceId: peerDeviceId ?? entry.originDeviceId,
            totalBytes: entry.byteSize,
            phase: .waiting,
            transferredBytes: 0,
            failure: nil
        )

        guard available >= required else {
            task.phase = .failed
            task.failure = .quotaExceeded
            tasks[entry.entryId] = task
            workspace.setAvailability(.remote, for: entry.entryId)
            return false
        }

        tasks[entry.entryId] = task
        workspace.setAvailability(.fetching, for: entry.entryId)
        return true
    }
}

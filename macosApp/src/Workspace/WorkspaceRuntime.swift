import AppKit
import Foundation
import UniformTypeIdentifiers

/// 工作区运行时要用的外部能力。测试传假的。
@MainActor
struct WorkspaceEnvironment {
    /// 当前时间，秒。
    var now: () -> Int64 = { Int64(Date().timeIntervalSince1970) }
    /// 放入方设备标识。配对落地之前一直是空串。
    var originDeviceId: () -> String = { "" }
    /// 文件的内容类型。认不出来给空串，分类再看扩展名。
    var contentType: (URL) -> String = { WorkspaceRuntime.contentType(of: $0) }
    /// 是不是普通文件。目录不能直接放入。
    var isRegularFile: (URL) -> Bool = { url in
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
    }
    /// 用默认应用打开内容。
    var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// 在访达里选中内容。
    var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
}

/// 工作区的运行时。
///
/// 职责：
/// - 读工作区索引，按 Rust core 的顺序规则排出界面顺序。
/// - 放入文件、置顶、删除、清理过期。
/// - 取出内容给默认应用打开，或在访达里显示。
///
/// 索引与内容的读写全在 Rust core 的 `WorkspaceStore` 里，这里只管状态与提示。
/// 只跑在主线程。
@MainActor
@Observable
final class WorkspaceRuntime {
    /// 条目列表。置顶的在前，其余从新到旧。
    private(set) var entries: [WorkspaceEntry] = []
    /// 保留策略。
    private(set) var policy: WorkspacePolicy = WorkspacePolicy.companion.defaults()
    /// 本机内容占用的字节数。
    private(set) var totalBytes: Int64 = 0
    /// 最近一次失败。界面读完应调用 [clearMessages]。
    private(set) var errorMessage: LocalizedCopy?
    /// 最近一条说明，例如「工作区里已经有这份内容」。
    private(set) var infoMessage: LocalizedCopy?

    private let client: WorkspaceStoreClient
    private let environment: WorkspaceEnvironment
    private var state: WorkspaceState

    init(
        client: WorkspaceStoreClient = WorkspaceStoreClient(),
        environment: WorkspaceEnvironment = WorkspaceEnvironment(),
        policy: WorkspacePolicy? = nil
    ) {
        self.client = client
        self.environment = environment

        var loaded = client.load()
        // 传入的策略覆盖索引里的那一份。淘汰与放入都以索引里的策略为准。
        if let policy {
            loaded = client.save(loaded.doCopy(schemaVersion: loaded.schemaVersion, entries: loaded.entries, policy: policy))
        }

        // 启动时清一次过期内容。过期是隐私控制，不只是清理。
        let plan = client.sweep(policy: loaded.policy, nowEpochSeconds: environment.now())
        if plan.changed {
            loaded = client.load()
        }
        self.state = loaded
        self.entries = WorkspaceStoreClient.displayOrder(loaded)
        self.policy = loaded.policy
        self.totalBytes = WorkspaceStoreClient.localBytes(loaded)
    }

    /// 放入若干文件。返回被接受的条数。
    ///
    /// 同一份内容再放一次算成功，但只留一条，并给出说明。
    @discardableResult
    func intake(urls: [URL]) -> Int {
        guard !urls.isEmpty else { return 0 }
        var accepted = 0
        var failure: LocalizedCopy?
        var info: LocalizedCopy?
        var working = state

        for url in urls {
            guard environment.isRegularFile(url) else {
                failure = ContractCopy.copyHubFilesErrorImport
                continue
            }
            let result = client.putFile(
                state: working,
                sourcePath: url.path,
                displayName: url.lastPathComponent,
                contentType: environment.contentType(url),
                originDeviceId: environment.originDeviceId(),
                nowEpochSeconds: environment.now()
            )
            working = result.state

            if result.admission == WorkspaceAdmission.accepted {
                // 索引没写进磁盘时不算放进去：重启之后这一条就没了。
                if result.persisted {
                    accepted += 1
                } else {
                    failure = ContractCopy.copyHubFilesErrorSave
                }
            } else if result.admission == WorkspaceAdmission.duplicate {
                info = ContractCopy.copyHubFilesNoticeDuplicate
            } else if result.admission == WorkspaceAdmission.quotaExceeded {
                failure = ContractCopy.copyHubFilesErrorQuota
            } else if result.admission == WorkspaceAdmission.tooLarge {
                failure = ContractCopy.copyHubFilesErrorTooLarge
            } else {
                failure = ContractCopy.copyHubFilesErrorImport
            }
        }

        adopt(working)
        errorMessage = failure
        infoMessage = failure == nil
            ? (info ?? (accepted > 0 ? ContractCopy.copyHubFilesNoticeSaved : nil))
            : nil
        return accepted
    }

    /// 存入若干已经落盘的文件。返回被接受的条数。
    @discardableResult
    func save(filesAt paths: [String]) -> Int {
        intake(urls: paths.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) })
    }

    /// 存入一段文字。剪切板里的文字、链接与颜色走这里。
    ///
    /// 空白文字不存，返回假。文件名由共享层按正文取，四个平台一致。
    /// 索引没写进磁盘时也返回假：重启之后这一条就没了。
    @discardableResult
    func save(text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let result = client.putText(
            state: state,
            text: text,
            displayName: WorkspaceLogic.shared.suggestedTextName(text: text),
            contentType: "text/plain",
            originDeviceId: environment.originDeviceId(),
            nowEpochSeconds: environment.now()
        )
        adopt(result.state)
        apply(result)
        return result.accepted && result.persisted
    }

    /// 存入一条剪切板条目。返回被接受的条数。
    ///
    /// 图片与文件条目存它们已经落盘的文件，文字、链接与颜色存正文。
    /// 哪种条目有文件由共享层判断，见 `ClipboardLogic.importPaths`。
    @discardableResult
    func save(clipItem: ClipItem) -> Int {
        let paths = ClipboardLogic.shared.importPaths(item: clipItem)
        if paths.isEmpty {
            return save(text: clipItem.text) ? 1 : 0
        }
        return save(filesAt: paths)
    }

    /// 记下一条放入的结果。说明与失败互斥。
    private func apply(_ result: WorkspacePutResult) {
        switch result.admission {
        case WorkspaceAdmission.accepted:
            // 内容收下了但索引没落盘：报错，不报成功。
            errorMessage = result.persisted ? nil : ContractCopy.copyHubFilesErrorSave
            infoMessage = result.persisted ? ContractCopy.copyHubFilesNoticeSaved : nil
        case WorkspaceAdmission.duplicate:
            errorMessage = nil
            infoMessage = ContractCopy.copyHubFilesNoticeDuplicate
        case WorkspaceAdmission.tooLarge:
            errorMessage = ContractCopy.copyHubFilesErrorTooLarge
            infoMessage = nil
        case WorkspaceAdmission.quotaExceeded:
            errorMessage = ContractCopy.copyHubFilesErrorQuota
            infoMessage = nil
        default:
            errorMessage = ContractCopy.copyHubFilesErrorImport
            infoMessage = nil
        }
    }

    func togglePin(_ entryId: String) {
        guard let entry = entries.first(where: { $0.entryId == entryId }) else { return }
        adopt(client.setPinned(state: state, entryId: entryId, pinned: !entry.pinned))
    }

    func remove(_ entryId: String) {
        adopt(client.remove(state: state, entryId: entryId, nowEpochSeconds: environment.now()))
    }

    /// 清理过期与超出上限的条目。返回清掉的条数。
    @discardableResult
    func sweep() -> Int {
        let plan = client.sweep(policy: policy, nowEpochSeconds: environment.now())
        let reloaded = client.load()
        adopt(reloaded)
        if plan.changed {
            infoMessage = ContractCopy.copyHubFilesNoticeSwept
        }
        return plan.removed.count
    }

    /// 清空工作区。置顶的条目也删。
    func clearAll() {
        client.clear()
        adopt(WorkspaceStoreClient.emptyState)
    }

    func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    /// 一条条目内容的落盘位置。本机没有内容时返回 nil。
    func contentURL(_ entryId: String) -> URL? {
        guard let path = client.contentPath(entryId: entryId) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func open(_ entryId: String) {
        guard let url = contentURL(entryId) else {
            errorMessage = ContractCopy.copyHubFilesErrorMissing
            return
        }
        environment.open(url)
    }

    /// 复制本机内容。与截图卡片共用同一种文件剪贴板写法。
    func copy(_ entryId: String) {
        guard let url = contentURL(entryId) else {
            errorMessage = ContractCopy.copyHubFilesErrorMissing
            infoMessage = nil
            return
        }
        guard ShelfClipboard.copy(url) else {
            errorMessage = ContractCopy.copyHubFilesErrorCopy
            infoMessage = nil
            return
        }
        errorMessage = nil
    }

    /// 复制文本正文。只有文本条目使用这一条。
    func copyText(_ entryId: String) {
        guard let url = contentURL(entryId),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            errorMessage = ContractCopy.copyHubFilesErrorMissing
            infoMessage = nil
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            errorMessage = ContractCopy.copyHubFilesErrorCopy
            infoMessage = nil
            return
        }
        errorMessage = nil
    }

    /// 把条目的本机可用状态同步给界面。
    func setAvailability(_ availability: WorkspaceAvailability, for entryId: String) {
        adopt(client.setAvailability(state: state, entryId: entryId, availability: availability))
    }

    /// 启动时清掉上次进程留下的 FETCHING 状态。
    func reconcileOrphanedTransfers(activeEntryIds: Set<String>) {
        adopt(client.clearOrphanedFetching(state: state, activeEntryIds: activeEntryIds))
    }

    func reveal(_ entryId: String) {
        guard let url = contentURL(entryId) else {
            errorMessage = ContractCopy.copyHubFilesErrorMissing
            return
        }
        environment.reveal(url)
    }

    private func adopt(_ next: WorkspaceState) {
        state = next
        entries = WorkspaceStoreClient.displayOrder(next)
        policy = next.policy
        totalBytes = WorkspaceStoreClient.localBytes(next)
    }

    /// 文件的内容类型。认出扩展名时给 MIME，认不出给空串。
    nonisolated static func contentType(of url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return "" }
        return type.preferredMIMEType ?? ""
    }
}

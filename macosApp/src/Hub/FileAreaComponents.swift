import AppKit
import SwiftUI

private struct FileAreaReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// 调试预览可固定减弱动态效果；正常运行时使用系统设置。
    var fileAreaReduceMotionOverride: Bool? {
        get { self[FileAreaReduceMotionOverrideKey.self] }
        set { self[FileAreaReduceMotionOverrideKey.self] = newValue }
    }
}

/// 文件区筛选。桥接层的 `FileAreaFilter` 负责数据筛选，这个 Swift 枚举只负责菜单状态。
enum FileAreaFilterChoice: String, CaseIterable, Identifiable {
    case all
    case screenshots
    case files
    case text
    case transfers

    var id: String { rawValue }

    var filter: FileAreaFilter {
        switch self {
        case .all: FileAreaFilter.all
        case .screenshots: FileAreaFilter.screenshots
        case .files: FileAreaFilter.files
        case .text: FileAreaFilter.text
        case .transfers: FileAreaFilter.transfers
        }
    }

    var title: LocalizedCopy {
        switch self {
        case .all: ContractCopy.copyHubFilesFilterAll
        case .screenshots: ContractCopy.copyHubFilesFilterScreenshots
        case .files: ContractCopy.copyHubFilesFilterFiles
        case .text: ContractCopy.copyHubFilesFilterText
        case .transfers: ContractCopy.copyHubFilesFilterTransfers
        }
    }
}

/// 文件区能执行的动作。动作由截图运行时或工作区运行时执行，视图只描述菜单项。
enum FileAreaAction: Hashable {
    case open
    case copy
    case copyText
    case markup
    case saveToWorkspace
    case reveal
    case pin(Bool)
    case download
    case cancelTransfer
    case retry
    case remove

    var title: LocalizedCopy {
        switch self {
        case .open: ContractCopy.copyHubFilesActionOpen
        case .copy: ContractCopy.copyHubFilesActionCopy
        case .copyText: ContractCopy.copyHubFilesActionCopyText
        case .markup: ContractCopy.copyHubFilesActionMarkup
        case .saveToWorkspace: ContractCopy.copyHubFilesActionSaveToWorkspace
        case .reveal: ContractCopy.copyHubFilesActionReveal
        case .pin(let pinned):
            pinned ? ContractCopy.copyHubFilesActionUnpin : ContractCopy.copyHubFilesActionPin
        case .download: ContractCopy.copyHubFilesActionDownload
        case .cancelTransfer: ContractCopy.copyHubFilesActionCancelTransfer
        case .retry: ContractCopy.copyHubFilesActionRetry
        case .remove: ContractCopy.copyHubFilesActionRemove
        }
    }

    var symbol: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .copy: "doc.on.doc"
        case .copyText: "text.alignleft"
        case .markup: "pencil.tip.crop.circle"
        case .saveToWorkspace: "tray.and.arrow.down"
        case .reveal: "folder"
        case .pin: "pin"
        case .download: "arrow.down.circle"
        case .cancelTransfer: "xmark.circle"
        case .retry: "arrow.clockwise"
        case .remove: "trash"
        }
    }

    var isDestructive: Bool { self == .remove }
    var separatorBefore: Bool { isDestructive }
}

/// 文件区的固定几何。来源是 `component/file-area` 与各子组件合同尺寸。
enum FileAreaMetrics {
    static let areaHeight: CGFloat = 538
    static let toolbarHeight: CGFloat = 28
    static let toolbarGap: CGFloat = 12
    static let focusHeight: CGFloat = 176
    static let quietTileHeight: CGFloat = 146
    static let quietPreviewHeight: CGFloat = 104
    static let quietColumns = 4
    static let quietGap: CGFloat = 14
    static let stageGap: CGFloat = 16
    static let contentCornerRadius: CGFloat = 12
    static let tileCornerRadius: CGFloat = 9

    /// 四列网格的单格宽度。960 点面板对应合同里的 217.5 点。
    static func quietTileWidth(containerWidth: CGFloat) -> CGFloat {
        max(0, (containerWidth - quietGap * CGFloat(quietColumns - 1)) / CGFloat(quietColumns))
    }
}

/// 文件条目的展示文案和动作顺序。这里是纯规则，便于单测。
enum FileAreaPresentation {
    static func typeTitle(for item: FileAreaItem, language: AppLanguage) -> String {
        switch item.kind {
        case FileAreaKind.screenshot: ContractCopy.copyHubFilesFilterScreenshots.text(for: language)
        case FileAreaKind.image: ContractCopy.copyHubFilesKindImage.text(for: language)
        case FileAreaKind.text: ContractCopy.copyHubFilesFilterText.text(for: language)
        case FileAreaKind.pdf: ContractCopy.copyHubFilesKindPdf.text(for: language)
        case FileAreaKind.audio: ContractCopy.copyHubFilesKindAudio.text(for: language)
        default: ContractCopy.copyHubFilesFilterFiles.text(for: language)
        }
    }

    /// 排序后的完整右键菜单。传输动作排第一，删除永远在最后。
    static func contextActions(
        for item: FileAreaItem,
        task: WorkspaceTransferTask? = nil
    ) -> [FileAreaAction] {
        var actions: [FileAreaAction] = []
        let capabilities = item.capabilities

        if let transferAction = transferAction(for: item, task: task) {
            actions.append(transferAction)
        } else {
            if capabilities.canCopy {
                actions.append(.copy)
            } else if capabilities.canCopyText {
                actions.append(.copyText)
            }
            if capabilities.canOpen { actions.append(.open) }
            if capabilities.canMarkup { actions.append(.markup) }
            if capabilities.canSaveToWorkspace { actions.append(.saveToWorkspace) }
            if capabilities.canReveal { actions.append(.reveal) }
            if capabilities.canPin { actions.append(.pin(item.pinned)) }
        }
        if capabilities.canRemove { actions.append(.remove) }
        return actions
    }

    /// 焦点卡最多显示三个主动作。传输动作拥有最高优先级。
    static func focusActions(
        for item: FileAreaItem,
        task: WorkspaceTransferTask? = nil
    ) -> [FileAreaAction] {
        var actions: [FileAreaAction] = []
        if let transferAction = transferAction(for: item, task: task) {
            actions.append(transferAction)
        }
        if item.capabilities.canOpen { actions.append(.open) }
        if item.capabilities.canCopy {
            actions.append(.copy)
        } else if item.capabilities.canCopyText {
            actions.append(.copyText)
        }
        if item.capabilities.canMarkup { actions.append(.markup) }
        if item.capabilities.canReveal { actions.append(.reveal) }
        if item.capabilities.canPin && actions.count < 3 { actions.append(.pin(item.pinned)) }
        return Array(actions.prefix(3))
    }

    /// 安静格子只显示一个快捷动作。传输状态总是先给出取消或重试。
    static func quickAction(
        for item: FileAreaItem,
        task: WorkspaceTransferTask? = nil
    ) -> FileAreaAction? {
        if let transferAction = transferAction(for: item, task: task) {
            return transferAction
        }
        if item.capabilities.canOpen { return .open }
        if item.capabilities.canCopyText { return .copyText }
        if item.capabilities.canCopy { return .copy }
        if item.capabilities.canMarkup { return .markup }
        return nil
    }

    /// 元数据：大小与加入时间。大小优先用投影值，截图由文件属性补齐。
    static func metadata(for item: FileAreaItem, url: URL?, language: AppLanguage) -> String {
        var parts: [String] = []
        let bytes = item.byteSize > 0 ? item.byteSize : fileSize(url)
        if bytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        if item.createdAtEpochSeconds > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(item.createdAtEpochSeconds))
            parts.append(
                date.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened)
                        .locale(language.locale)
                )
            )
        }
        return parts.joined(separator: " · ")
    }

    /// 状态文字。颜色不是唯一线索，所以每个状态都有文字。
    static func statusTitle(
        for item: FileAreaItem,
        language: AppLanguage,
        task: WorkspaceTransferTask? = nil
    ) -> String? {
        if let task {
            switch task.phase {
            case .waiting:
                return ContractCopy.copyHubFilesStateWaiting.text(for: language)
            case .transferring:
                let percent = Int((task.progress * 100).rounded())
                return "\(ContractCopy.copyHubFilesStateTransferring.text(for: language)) \(percent)%"
            case .failed:
                return ContractCopy.copyHubFilesStateTransferFailed.text(for: language)
            case .cancelled:
                return ContractCopy.copyHubFilesStateTransferCancelled.text(for: language)
            }
        }
        switch item.availability {
        case FileAreaAvailability.remote:
            return ContractCopy.copyHubFilesStateOnOtherDevice.text(for: language)
        case FileAreaAvailability.fetching:
            return ContractCopy.copyHubFilesStateFetching.text(for: language)
        case FileAreaAvailability.unavailable:
            return ContractCopy.copyHubFilesStateUnavailable.text(for: language)
        default:
            return nil
        }
    }

    /// 失败任务的恢复说明。错误码保持可追踪，界面文案按用户能处理的动作分类。
    static func transferFailureDetail(
        for task: WorkspaceTransferTask,
        language: AppLanguage
    ) -> String? {
        guard task.phase == .failed, let failure = task.failure else { return nil }
        switch failure {
        case .quotaExceeded:
            return ContractCopy.copyHubFilesErrorQuota.text(for: language)
        case .storageFull:
            return ContractCopy.copyHubFilesErrorSave.text(for: language)
        case .connectionFailed:
            return ContractCopy.copyHubFilesErrorConnection.text(for: language)
        case .entryMissing:
            return ContractCopy.copyHubFilesErrorMissing.text(for: language)
        }
    }

    /// 焦点卡第二行。远端条目省略本机文件大小，避免让索引看起来像已下载。
    static func subtitle(
        for item: FileAreaItem,
        url: URL?,
        language: AppLanguage,
        task: WorkspaceTransferTask? = nil
    ) -> String {
        let origin = item.originDeviceId.isEmpty
            ? ContractCopy.copyHubFilesStateLocal.text(for: language)
            : item.originDeviceId
        var detail = statusTitle(for: item, language: language, task: task)
            ?? metadata(for: item, url: url, language: language)
        if let task,
           let failure = transferFailureDetail(for: task, language: language),
           !failure.isEmpty {
            detail = "\(detail) · \(failure)"
        }
        return detail.isEmpty ? origin : "\(origin) · \(detail)"
    }

    static func accessibilityValue(
        for item: FileAreaItem,
        url: URL?,
        language: AppLanguage,
        task: WorkspaceTransferTask? = nil
    ) -> String {
        let type = typeTitle(for: item, language: language)
        let subtitle = subtitle(for: item, url: url, language: language, task: task)
        let actions = contextActions(for: item, task: task)
            .map { $0.title.text(for: language) }
            .joined(separator: ", ")
        return actions.isEmpty ? "\(type), \(subtitle)" : "\(type), \(subtitle), \(actions)"
    }

    /// 搜索同时覆盖名称、来源和类别。筛选仍由 Rust core 投影执行。
    static func matches(item: FileAreaItem, query: String, language: AppLanguage) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let fields = [
            item.displayName,
            item.originDeviceId,
            typeTitle(for: item, language: language),
            statusTitle(for: item, language: language) ?? "",
        ]
        return fields.contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private static func transferAction(
        for item: FileAreaItem,
        task: WorkspaceTransferTask?
    ) -> FileAreaAction? {
        if let task {
            switch task.phase {
            case .waiting, .transferring: return .cancelTransfer
            case .failed, .cancelled: return .retry
            }
        }
        if item.capabilities.canDownload { return .download }
        return nil
    }

    private static func fileSize(_ url: URL?) -> Int64 {
        guard let url,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize
        else { return 0 }
        return Int64(size)
    }
}

/// 文件区上方的唯一工具行：筛选、数量、实时状态和加入。
struct FileFilterMenuView: View {
    let selection: FileAreaFilterChoice
    let counts: [FileAreaFilterChoice: Int]
    let language: AppLanguage
    let onSelect: (FileAreaFilterChoice) -> Void

    var body: some View {
        Menu {
            ForEach(FileAreaFilterChoice.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    Label {
                        Text("\(option.title.text(for: language))   \(counts[option, default: 0])")
                    } icon: {
                        if option == selection {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection.title.text(for: language))
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(MacTheme.textSecondary)
            }
            .foregroundStyle(MacTheme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: FileAreaMetrics.toolbarHeight)
            .background(
                MacTheme.elevated.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(selection.title.text(for: language))
        .accessibilityValue("\(counts[selection, default: 0])")
    }
}

/// 空状态与无匹配状态。没有结果时不显示常驻工具行。
struct FileEmptyStateView: View {
    enum State {
        case empty
        case noMatch
    }

    let state: State
    let language: AppLanguage
    let onImport: () -> Void
    let onNewText: () -> Void
    let onClearFilter: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: state == .empty ? "plus" : "magnifyingglass")
                .font(.system(size: state == .empty ? 22 : 21, weight: .light))
                .foregroundStyle(state == .empty ? MacTheme.textPrimary : MacTheme.textSecondary)
                .frame(width: 46, height: 46)
                .background(
                    MacTheme.elevated.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.textPrimary)
                .padding(.top, 11)

            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.textSecondary)
                .padding(.top, 4)

            HStack(spacing: 7) {
                if state == .empty {
                    FileMiniButton(
                        title: ContractCopy.copyHubFilesActionImport.text(for: language),
                        primary: true,
                        action: onImport
                    )
                    FileMiniButton(
                        title: ContractCopy.copyHubFilesActionNewText.text(for: language),
                        primary: false,
                        action: onNewText
                    )
                } else {
                    FileMiniButton(
                        title: ContractCopy.copyHubFilesActionClearFilter.text(for: language),
                        primary: false,
                        action: onClearFilter
                    )
                }
            }
            .padding(.top, 13)

            if state == .empty {
                Text("⌘O  \(ContractCopy.copyHubFilesActionImport.text(for: language))     ⌘N  \(ContractCopy.copyHubFilesActionNewText.text(for: language))")
                    .font(.system(size: 8))
                    .foregroundStyle(MacTheme.disabledText)
                    .padding(.top, 11)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private var title: String {
        state == .empty
            ? ContractCopy.copyHubFilesEmptyTitle.text(for: language)
            : ContractCopy.copyHubFilesNoMatchTitle.text(for: language)
    }

    private var hint: String {
        state == .empty
            ? ContractCopy.copyHubFilesEmptyHint.text(for: language)
            : ContractCopy.copyHubFilesNoMatchHint.text(for: language)
    }
}

/// 键盘打开的完整动作菜单。视觉与右键菜单同序，焦点由上下键和 Tab 管理。
struct FileKeyboardActionMenuView: View {
    let item: FileAreaItem
    let language: AppLanguage
    var transferTask: WorkspaceTransferTask? = nil
    let onDismiss: () -> Void
    let onAction: (FileAreaAction) -> Void

    @FocusState private var focusedAction: Int?

    private var actions: [FileAreaAction] {
        FileAreaPresentation.contextActions(for: item, task: transferTask)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                if action.separatorBefore {
                    Divider().padding(.vertical, 4)
                }
                Button {
                    onDismiss()
                    onAction(action)
                } label: {
                    Label(action.title.text(for: language), systemImage: action.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(action.isDestructive ? MacTheme.errorText : MacTheme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .padding(.horizontal, 8)
                        .background(
                            focusedAction == index ? MacTheme.brand.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable()
                .focused($focusedAction, equals: index)
            }
        }
        .padding(6)
        .frame(width: 160)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                focusedAction = 0
            }
        }
        .onKeyPress(.downArrow) {
            moveFocus(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveFocus(by: -1)
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .accessibilityElement(children: .contain)
    }

    private func moveFocus(by delta: Int) {
        guard !actions.isEmpty else { return }
        let current = focusedAction ?? 0
        focusedAction = min(max(0, current + delta), actions.count - 1)
    }
}

/// 原生右键菜单的内容。删除动作在最后，并使用独立的破坏性样式与分隔线。
struct FileContextMenuView: View {
    let item: FileAreaItem
    let language: AppLanguage
    var transferTask: WorkspaceTransferTask? = nil
    let onAction: (FileAreaAction) -> Void

    var body: some View {
        ForEach(Array(FileAreaPresentation.contextActions(for: item, task: transferTask).enumerated()), id: \.offset) { _, action in
            if action.separatorBefore {
                Divider()
            }
            if action.isDestructive {
                Button(role: .destructive) {
                    onAction(action)
                } label: {
                    Label(action.title.text(for: language), systemImage: action.symbol)
                }
            } else {
                Button {
                    onAction(action)
                } label: {
                    Label(action.title.text(for: language), systemImage: action.symbol)
                }
            }
        }
    }
}

/// 唯一的详细焦点卡。左侧是内容预览，右侧只保留一个标题、一行元数据和最多三个动作。
struct FileFocusCardView: View {
    let item: FileAreaItem
    let url: URL?
    let language: AppLanguage
    var transferTask: WorkspaceTransferTask? = nil
    var keyboardFocused = false
    var keyboardMenuRequested = false
    var keyboardMenuRequestNonce = 0
    var onKeyboardMenuDismissed: () -> Void = {}
    let onAction: (FileAreaAction) -> Void

    @State private var hovered = false
    @State private var keyboardMenuPresented = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                FilePreviewView(item: item, url: url)
                    .frame(width: geometry.size.width * 0.43)
                    .overlay(alignment: .topLeading) {
                        if item.pinned {
                            FilePinnedBadge(language: language)
                        }
                    }
                    .overlay {
                        FileStatusOverlay(item: item, language: language, transferTask: transferTask)
                    }

                details
                    .frame(width: geometry.size.width * 0.57)
            }
            .clipShape(RoundedRectangle(cornerRadius: FileAreaMetrics.contentCornerRadius, style: .continuous))
            .background(
                (hovered ? MacTheme.elevated.opacity(0.94) : MacTheme.material.opacity(0.86)),
                in: RoundedRectangle(cornerRadius: FileAreaMetrics.contentCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FileAreaMetrics.contentCornerRadius, style: .continuous)
                    .strokeBorder(
                        keyboardFocused ? MacTheme.focusRing : MacTheme.divider.opacity(0.68),
                        lineWidth: keyboardFocused ? 2 : 0.7
                    )
            )
        }
        .frame(height: FileAreaMetrics.focusHeight)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) {
            if item.capabilities.canOpen { onAction(.open) }
        }
        .contextMenu {
            FileContextMenuView(item: item, language: language, transferTask: transferTask, onAction: onAction)
        }
        .fileDragSource(url: url, enabled: item.capabilities.canDragOut)
        .onChange(of: keyboardMenuRequestNonce) { _, _ in
            if keyboardMenuRequested { keyboardMenuPresented = true }
        }
        .onChange(of: keyboardMenuPresented) { _, presented in
            if !presented { onKeyboardMenuDismissed() }
        }
        .popover(isPresented: $keyboardMenuPresented, arrowEdge: .bottom) {
            keyboardMenu
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(FileAreaPresentation.accessibilityValue(for: item, url: url, language: language, task: transferTask))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(FileAreaPresentation.typeTitle(for: item, language: language))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MacTheme.textSecondary)
                Spacer(minLength: 0)
                Menu {
                    FileContextMenuView(item: item, language: language, transferTask: transferTask, onAction: onAction)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(ContractCopy.copyHubFilesActionMore.text(for: language))
            }

            Text(item.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MacTheme.textPrimary)
                .lineLimit(2)
                .padding(.top, 5)

            Text(FileAreaPresentation.subtitle(for: item, url: url, language: language, task: transferTask))
                .font(.system(size: 9.5))
                .foregroundStyle(MacTheme.textSecondary)
                .lineLimit(1)
                .padding(.top, 4)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                    FileMiniButton(
                        title: action.title.text(for: language),
                        primary: index == 0
                    ) {
                        onAction(action)
                    }
                }
            }

            Text(keyboardHint)
                .font(.system(size: 8))
                .foregroundStyle(MacTheme.disabledText)
                .padding(.top, 7)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
    }

    private var keyboardMenu: some View {
        FileKeyboardActionMenuView(
            item: item,
            language: language,
            transferTask: transferTask,
            onDismiss: { keyboardMenuPresented = false },
            onAction: onAction
        )
    }

    private var actions: [FileAreaAction] {
        FileAreaPresentation.focusActions(for: item, task: transferTask)
    }

    private var keyboardHint: String {
        if let transferTask {
            let transferHint: String
            switch transferTask.phase {
            case .waiting, .transferring:
                transferHint = ContractCopy.copyHubFilesActionCancelTransfer.text(for: language)
            case .failed, .cancelled:
                transferHint = ContractCopy.copyHubFilesActionRetry.text(for: language)
            }
            return "\(transferHint)   M  \(ContractCopy.copyHubFilesActionMore.text(for: language))   ⌘⌫  \(ContractCopy.copyHubFilesActionRemove.text(for: language))"
        }
        if item.availability == FileAreaAvailability.remote {
            return "\(ContractCopy.copyHubFilesActionDownload.text(for: language))   M  \(ContractCopy.copyHubFilesActionMore.text(for: language))   ⌘⌫  \(ContractCopy.copyHubFilesActionRemove.text(for: language))"
        }
        return "↵  \(ContractCopy.copyHubFilesActionOpen.text(for: language))   ⌘C  \(copyShortcut)   M  \(ContractCopy.copyHubFilesActionMore.text(for: language))   ⌘⌫  \(ContractCopy.copyHubFilesActionRemove.text(for: language))"
    }

    private var copyShortcut: String {
        item.capabilities.canCopyText
            ? ContractCopy.copyHubFilesActionCopyText.text(for: language)
            : ContractCopy.copyHubFilesActionCopy.text(for: language)
    }
}

/// 安静网格里的一件内容。默认不显示动作，悬停时只出现一个快捷动作和菜单按钮。
struct FileQuietTileView: View {
    let item: FileAreaItem
    let url: URL?
    let language: AppLanguage
    var transferTask: WorkspaceTransferTask? = nil
    var keyboardFocused = false
    var keyboardMenuRequested = false
    var keyboardMenuRequestNonce = 0
    var onKeyboardMenuDismissed: () -> Void = {}
    let onSelect: () -> Void
    let onAction: (FileAreaAction) -> Void

    @State private var hovered = false
    @State private var keyboardMenuPresented = false

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 3) {
                preview
                Text(item.displayName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(MacTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .frame(width: geometry.size.width, alignment: .topLeading)
                    .frame(height: 24, alignment: .topLeading)
                Text(statusText)
                    .font(.system(size: 8.3))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .frame(width: geometry.size.width, alignment: .topLeading)
                    .frame(height: 10, alignment: .topLeading)
            }
            .frame(width: geometry.size.width, height: FileAreaMetrics.quietTileHeight, alignment: .topLeading)
        }
        .frame(height: FileAreaMetrics.quietTileHeight)
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2) {
            if item.capabilities.canOpen { onAction(.open) }
        }
        .contextMenu {
            FileContextMenuView(item: item, language: language, transferTask: transferTask, onAction: onAction)
        }
        .fileDragSource(url: url, enabled: item.capabilities.canDragOut)
        .onChange(of: keyboardMenuRequestNonce) { _, _ in
            if keyboardMenuRequested { keyboardMenuPresented = true }
        }
        .onChange(of: keyboardMenuPresented) { _, presented in
            if !presented { onKeyboardMenuDismissed() }
        }
        .popover(isPresented: $keyboardMenuPresented, arrowEdge: .bottom) {
            keyboardMenu
        }
        .overlay(
            RoundedRectangle(cornerRadius: FileAreaMetrics.tileCornerRadius, style: .continuous)
                .strokeBorder(keyboardFocused ? MacTheme.focusRing : .clear, lineWidth: 2)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(FileAreaPresentation.accessibilityValue(for: item, url: url, language: language, task: transferTask))
        .accessibilityAddTraits(.isButton)
    }

    private var preview: some View {
        FilePreviewView(item: item, url: url)
            .frame(maxWidth: .infinity)
            .frame(height: FileAreaMetrics.quietPreviewHeight)
            .clipShape(RoundedRectangle(cornerRadius: FileAreaMetrics.tileCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FileAreaMetrics.tileCornerRadius, style: .continuous)
                    .strokeBorder(
                        hovered ? MacTheme.divider.opacity(0.72) : MacTheme.divider.opacity(0.5),
                        lineWidth: hovered ? 1 : 0.5
                    )
            )
            .overlay(alignment: .topLeading) {
                if item.pinned {
                    FilePinnedBadge(language: language)
                }
            }
            .overlay {
                FileStatusOverlay(item: item, language: language, transferTask: transferTask, compact: true)
            }
            .overlay(alignment: .bottom) {
                if hovered || keyboardFocused || keyboardMenuPresented {
                    hoverActions
                        .padding(.horizontal, 4)
                        .padding(.bottom, 3)
                }
            }
    }

    private var hoverActions: some View {
        HStack(spacing: 4) {
            if let action = quickAction {
                Button {
                    onAction(action)
                } label: {
                    Text(action.title.text(for: language))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(MacTheme.textPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            MacTheme.elevated.opacity(0.92),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }

            Menu {
                FileContextMenuView(item: item, language: language, transferTask: transferTask, onAction: onAction)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MacTheme.textPrimary)
                    .frame(width: 21, height: 19)
                    .background(
                        MacTheme.elevated.opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(ContractCopy.copyHubFilesActionMore.text(for: language))
        }
        .frame(height: 25)
        .padding(.vertical, 3)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.52)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var keyboardMenu: some View {
        FileKeyboardActionMenuView(
            item: item,
            language: language,
            transferTask: transferTask,
            onDismiss: { keyboardMenuPresented = false },
            onAction: onAction
        )
    }

    private var quickAction: FileAreaAction? {
        FileAreaPresentation.quickAction(for: item, task: transferTask)
    }

    private var statusText: String {
        if let status = FileAreaPresentation.statusTitle(for: item, language: language, task: transferTask) {
            return status
        }
        return FileAreaPresentation.metadata(for: item, url: url, language: language)
    }

    private var statusColor: Color {
        if transferTask?.phase == .failed {
            return MacTheme.errorText
        }
        if transferTask?.phase == .waiting || transferTask?.phase == .transferring {
            return MacTheme.brand
        }
        switch item.availability {
        case FileAreaAvailability.remote, FileAreaAvailability.fetching:
            return MacTheme.brand
        default:
            return MacTheme.textSecondary
        }
    }
}

/// 内容预览。截图与图片使用真实缩略图，其它类型使用轻量图形，不读取无关正文。
struct FilePreviewView: View {
    let item: FileAreaItem
    let url: URL?

    var body: some View {
        switch item.kind {
        case FileAreaKind.screenshot, FileAreaKind.image:
            imagePreview
        case FileAreaKind.text:
            textPreview
        case FileAreaKind.pdf:
            documentPreview(label: "PDF", color: Color(red: 0.84, green: 0, blue: 0.08))
        case FileAreaKind.audio:
            audioPreview
        default:
            documentPreview(label: url?.pathExtension.uppercased() ?? "FILE", color: MacTheme.brand)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let url, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            documentPreview(label: "IMG", color: MacTheme.brand)
        }
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("TEXT")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(red: 0.6, green: 0.47, blue: 0.16))
            Text(Self.textPreview(url: url))
                .font(.system(size: 9.5))
                .foregroundStyle(Color(red: 0.19, green: 0.18, blue: 0.15))
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .background(Color(red: 1, green: 0.98, blue: 0.91))
    }

    private func documentPreview(label: String, color: Color) -> some View {
        ZStack {
            Color(red: 0.95, green: 0.95, blue: 0.97)
            VStack(spacing: 5) {
                Image(systemName: item.kind == FileAreaKind.pdf ? "doc.richtext" : "doc")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
    }

    private var audioPreview: some View {
        ZStack {
            Color(red: 0.95, green: 0.94, blue: 0.98)
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array([12, 24, 38, 56, 31, 46, 22, 14].enumerated()), id: \.offset) { _, height in
                    Capsule()
                        .fill(Color(red: 0.46, green: 0.33, blue: 0.72))
                        .frame(width: 4, height: height)
                }
            }
        }
    }

    /// 只读前 2 KB。预览不为了几行字扫描大文件。
    private static func textPreview(url: URL?) -> String {
        guard let url,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 2_048)) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// 传输状态只叠加在原条目上，不复制卡片。
private struct FileStatusOverlay: View {
    let item: FileAreaItem
    let language: AppLanguage
    var transferTask: WorkspaceTransferTask? = nil
    var compact = false

    var body: some View {
        if let transferTask {
            transferStatus(transferTask)
        } else {
            itemStatus
        }
    }

    @ViewBuilder
    private func transferStatus(_ task: WorkspaceTransferTask) -> some View {
        switch task.phase {
        case .waiting:
            bottomStatus(
                ContractCopy.copyHubFilesStateWaiting.text(for: language),
                progress: nil,
                background: .black.opacity(compact ? 0.42 : 0.72)
            )
        case .transferring:
            bottomStatus(
                FileAreaPresentation.statusTitle(for: item, language: language, task: task)
                    ?? ContractCopy.copyHubFilesStateTransferring.text(for: language),
                progress: task.progress,
                background: .black.opacity(compact ? 0.42 : 0.72)
            )
        case .failed:
            bottomStatus(
                "\(ContractCopy.copyHubFilesStateTransferFailed.text(for: language)) · \(ContractCopy.copyHubFilesActionRetry.text(for: language))",
                progress: nil,
                background: MacTheme.errorText.opacity(0.9),
                showsSpinner: false
            )
        case .cancelled:
            bottomStatus(
                "\(ContractCopy.copyHubFilesStateTransferCancelled.text(for: language)) · \(ContractCopy.copyHubFilesActionRetry.text(for: language))",
                progress: nil,
                background: .black.opacity(0.66),
                showsSpinner: false
            )
        }
    }

    @ViewBuilder
    private var itemStatus: some View {
        switch item.availability {
        case FileAreaAvailability.remote:
            fullStatus(
                title: ContractCopy.copyHubFilesStateOnOtherDevice.text(for: language),
                detail: compact ? "" : ContractCopy.copyHubFilesActionDownload.text(for: language),
                background: .black.opacity(0.58)
            )
        case FileAreaAvailability.fetching:
            bottomStatus(
                ContractCopy.copyHubFilesStateFetching.text(for: language),
                progress: nil,
                background: .black.opacity(compact ? 0.42 : 0.72)
            )
        case FileAreaAvailability.unavailable:
            fullStatus(
                title: ContractCopy.copyHubFilesStateUnavailable.text(for: language),
                detail: compact ? "" : ContractCopy.copyHubFilesErrorMissing.text(for: language),
                background: .black.opacity(0.7)
            )
        default:
            EmptyView()
        }
    }

    private func bottomStatus(
        _ title: String,
        progress: Double?,
        background: Color,
        showsSpinner: Bool = true
    ) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if showsSpinner {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(title)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(MacTheme.brand)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(background)
        }
    }

    private func fullStatus(title: String, detail: String, background: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold))
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 7.5))
                    .opacity(0.78)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
    }
}

private struct FilePinnedBadge: View {
    let language: AppLanguage

    var body: some View {
        Text(ContractCopy.copyHubFilesActionPin.text(for: language))
            .font(.system(size: 7.5, weight: .medium))
            .foregroundStyle(MacTheme.textPrimary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                MacTheme.elevated.opacity(0.86),
                in: Capsule()
            )
            .padding(6)
    }
}

/// 文件区的小动作按钮。高度 24 点，视觉上低于页标题行的常规按钮。
struct FileMiniButton: View {
    let title: String
    var primary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: primary ? .medium : .regular))
                .foregroundStyle(
                    primary
                        ? MacTheme.color(ContractColors.tokenColorTextOnAccent)
                        : MacTheme.textPrimary
                )
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    primary ? MacTheme.brand : MacTheme.elevated.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 只为真实文件挂拖出。远端或不可用条目不会启动空拖拽。
private struct FileDragSourceModifier: ViewModifier {
    let url: URL?
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled, let url {
            content.onDrag {
                NSItemProvider(contentsOf: url) ?? NSItemProvider()
            }
        } else {
            content
        }
    }
}

private extension View {
    func fileDragSource(url: URL?, enabled: Bool) -> some View {
        modifier(FileDragSourceModifier(url: url, enabled: enabled))
    }
}

/// 在 ScrollView 内，SwiftUI 的方向键事件可能先被滚动容器吃掉。
/// 这个零尺寸 AppKit 监视器只处理文件区已聚焦时的四个方向键，不改其它键盘事件。
struct FileAreaArrowKeyMonitor: NSViewRepresentable {
    let isActive: Bool
    let onMove: (MoveCommandDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isActive: isActive, onMove: onMove)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.onMove = onMove
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    @MainActor
    final class Coordinator {
        var isActive: Bool
        var onMove: (MoveCommandDirection) -> Void
        private var monitor: Any?

        init(isActive: Bool, onMove: @escaping (MoveCommandDirection) -> Void) {
            self.isActive = isActive
            self.onMove = onMove
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isActive else { return event }
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return event }
                let direction: MoveCommandDirection?
                switch event.keyCode {
                case 123: direction = .left
                case 124: direction = .right
                case 126: direction = .up
                case 125: direction = .down
                default: direction = nil
                }
                guard let direction else { return event }
                self.onMove(direction)
                return nil
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

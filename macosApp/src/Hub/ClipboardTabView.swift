import Foundation
import SwiftUI

/// 剪切板页签。
///
/// 内容按时间合并为列表，详情区固定显示选中条目。
/// 截图的复制、预览与标记复用截图库行为。
struct ClipboardTabView: View {
    let clipboard: ClipboardRuntime
    let runtime: AppRuntime
    let searchText: String
    @Binding var selection: String?
    let onClearSearch: () -> Void

    private var language: AppLanguage { runtime.language }

    private var data: ClipboardWorkspaceData {
        ClipboardWorkspaceData(
            clips: clipboard.items,
            screenshots: runtime.shelf.items
        )
    }

    /// 真实窗口验收时预先选中第一条文本，截图能同时显示选中行与主操作。
    private var previewSelectionID: String? {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["COVIO_CLIPBOARD_LIVE_PREVIEW"] == "1" else {
            return nil
        }
        if let selectedID = ProcessInfo.processInfo.environment["COVIO_CLIPBOARD_LIVE_PREVIEW_SELECTION"],
           !selectedID.isEmpty {
            return "clip:\(selectedID)"
        }
        return clipboard.items
            .first { $0.kind == .text }
            .map { "clip:\($0.id)" }
        #else
        return nil
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.noticeGap) {
            ClipboardWorkspaceBoard(
                data: data,
                language: language,
                searchText: searchText,
                initiallySelectedID: previewSelectionID,
                selectedID: $selection,
                onClearSearch: onClearSearch,
                onPrimary: primary,
                onAction: perform
            ) {
                ClipboardHeadingActions(clipboard: clipboard, language: language)
            }

            if let notice {
                MacAlert(message: notice, kind: .warning)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func primary(_ item: ClipboardWorkspaceItem) {
        switch item {
        case .clip(let clip):
            clipboard.paste(clip.id)
        case .screenshot(let screenshot):
            runtime.shelf.copyItem(screenshot)
        }
    }

    private func perform(_ item: ClipboardWorkspaceItem, _ action: ClipboardWorkspaceAction) {
        switch (item, action) {
        case (.clip(let clip), .copy):
            clipboard.copyToPasteboard(clip.id)
        case (.clip(let clip), .togglePin):
            clipboard.togglePin(clip.id)
        case (.clip(let clip), .saveToWorkspace):
            _ = runtime.workspace.save(clipItem: clip)
        case (.clip(let clip), .remove):
            clipboard.remove(clip.id)
        case (.screenshot(let screenshot), .copy):
            runtime.shelf.copyItem(screenshot)
        case (.screenshot(let screenshot), .saveToWorkspace):
            _ = runtime.workspace.intake(urls: [URL(fileURLWithPath: screenshot.path)])
        case (.screenshot(let screenshot), .remove):
            runtime.shelf.removeItem(screenshot)
        case (.screenshot(let screenshot), .preview):
            runtime.shelf.openItem(screenshot)
        case (.screenshot(let screenshot), .markup):
            runtime.shelf.markupItem(screenshot)
        case (.clip, .preview), (.clip, .markup), (.screenshot, .togglePin):
            break
        }
    }

    /// 当前要提示的那一条。错误优先于权限提示。
    private var notice: String? {
        if let error = clipboard.errorMessage {
            return error.text(for: language)
        }
        if !clipboard.failedHotKeys.isEmpty {
            return ContractCopy.copyClipboardErrorHotKey.text(for: language)
        }
        return nil
    }

    /// 工作区主体的高度。筛选栏、列表与详情区都算在里面。
    nonisolated static let listHeight: CGFloat = ClipboardWorkspaceMetrics.boardHeight

    /// 提示条的高度：`MacAlert` 的上下内边距加一行 11 点文字。
    nonisolated static let noticeHeight: CGFloat = 40

    /// 主体与提示条之间的间距。`HubMetrics` 按它相加。
    nonisolated static let noticeGap: CGFloat = MacTheme.space3
}

/// 剪切板页的胶囊动作：暂停记录、全部清除、条数。
///
/// 这三个动作放在筛选栏右端，列表区只承载内容。
struct ClipboardHeadingActions: View {
    let clipboard: ClipboardRuntime
    let language: AppLanguage

    var body: some View {
        HStack(spacing: MacTheme.space2) {
            MacButton(
                title: clipboard.isPaused
                    ? ContractCopy.copyClipboardStateResume.text(for: language)
                    : ContractCopy.copyClipboardStatePause.text(for: language)
            ) {
                clipboard.setPaused(!clipboard.isPaused)
            }
            MacButton(
                title: ContractCopy.copyClipboardActionClear.text(for: language),
                isEnabled: clipboard.items.contains { !$0.pinned }
            ) {
                clipboard.clearAll()
            }
            MacStatusLine(text: statusText)
        }
    }

    private var statusText: String {
        let unpinned = clipboard.items.filter { !$0.pinned }.count
        return "\(unpinned) / \(Int(clipboard.policy.maxItems))"
    }
}

// 本文件由 scripts/generate-contract-constants.py 生成。不要手改。
// 权威是 docs/covio-design-contract.json。
// 改合同后重跑脚本：python3 scripts/generate-contract-constants.py

import Foundation

/// 设计合同 `copy` 段的全部文案。
///
/// 键名就是合同里的键路径。`DesignContractTests` 逐条比对，
/// 所以这里的值不能手改。
enum ContractCopy {
    /// `copy/agent/action-cancelled`
    static let copyAgentActionCancelled = LocalizedCopy(key: "copy/agent/action-cancelled", en: "Local action cancelled.", zhHans: "本地操作已取消。")
    /// `copy/agent/action-completed`
    static let copyAgentActionCompleted = LocalizedCopy(key: "copy/agent/action-completed", en: "Local action completed.", zhHans: "本地操作已完成。")
    /// `copy/agent/action-failed`
    static let copyAgentActionFailed = LocalizedCopy(key: "copy/agent/action-failed", en: "Local action failed.", zhHans: "本地操作失败。")
    /// `copy/agent/attach-files`
    static let copyAgentAttachFiles = LocalizedCopy(key: "copy/agent/attach-files", en: "Attach files", zhHans: "添加附件")
    /// `copy/agent/cancel`
    static let copyAgentCancel = LocalizedCopy(key: "copy/agent/cancel", en: "Cancel", zhHans: "取消")
    /// `copy/agent/clear`
    static let copyAgentClear = LocalizedCopy(key: "copy/agent/clear", en: "New chat", zhHans: "新对话")
    /// `copy/agent/confirm`
    static let copyAgentConfirm = LocalizedCopy(key: "copy/agent/confirm", en: "Allow", zhHans: "允许")
    /// `copy/agent/confirm-body`
    static let copyAgentConfirmBody = LocalizedCopy(key: "copy/agent/confirm-body", en: "The agent will run this local service after your confirmation.", zhHans: "确认后 Agent 将执行此本地服务。")
    /// `copy/agent/confirm-title`
    static let copyAgentConfirmTitle = LocalizedCopy(key: "copy/agent/confirm-title", en: "Allow local action?", zhHans: "允许本地操作？")
    /// `copy/agent/copy-characters`
    static let copyAgentCopyCharacters = LocalizedCopy(key: "copy/agent/copy-characters", en: "Copy %d characters to the clipboard.", zhHans: "复制 %d 个字符到剪贴板。")
    /// `copy/agent/empty-body`
    static let copyAgentEmptyBody = LocalizedCopy(key: "copy/agent/empty-body", en: "It can inspect attached files, answer with citations, and use local system services. Side effects need confirmation.", zhHans: "可检查附件、带来源回答问题，并使用本地系统服务。有副作用的操作需要确认。")
    /// `copy/agent/empty-response`
    static let copyAgentEmptyResponse = LocalizedCopy(key: "copy/agent/empty-response", en: "No response.", zhHans: "没有返回内容。")
    /// `copy/agent/empty-title`
    static let copyAgentEmptyTitle = LocalizedCopy(key: "copy/agent/empty-title", en: "Ask the local agent", zhHans: "询问本地 Agent")
    /// `copy/agent/error`
    static let copyAgentError = LocalizedCopy(key: "copy/agent/error", en: "The local agent could not complete this request.", zhHans: "本地 Agent 无法完成此请求。")
    /// `copy/agent/history/clear-all`
    static let copyAgentHistoryClearAll = LocalizedCopy(key: "copy/agent/history/clear-all", en: "Clear All History", zhHans: "清除全部历史")
    /// `copy/agent/history/clear-body`
    static let copyAgentHistoryClearBody = LocalizedCopy(key: "copy/agent/history/clear-body", en: "This removes saved conversations and tool audit records from this Mac. It cannot be undone.", zhHans: "此操作会删除这台 Mac 上保存的会话和工具审计记录。此操作无法撤销。")
    /// `copy/agent/history/clear-title`
    static let copyAgentHistoryClearTitle = LocalizedCopy(key: "copy/agent/history/clear-title", en: "Clear all local Agent history?", zhHans: "清除全部本地 Agent 历史？")
    /// `copy/agent/name`
    static let copyAgentName = LocalizedCopy(key: "copy/agent/name", en: "Covio Agent", zhHans: "Covio Agent")
    /// `copy/agent/offline`
    static let copyAgentOffline = LocalizedCopy(key: "copy/agent/offline", en: "Local only", zhHans: "仅本地")
    /// `copy/agent/placeholder`
    static let copyAgentPlaceholder = LocalizedCopy(key: "copy/agent/placeholder", en: "Ask about this Mac or your workspace", zhHans: "询问这台 Mac 或工作区")
    /// `copy/agent/remove-attachment`
    static let copyAgentRemoveAttachment = LocalizedCopy(key: "copy/agent/remove-attachment", en: "Remove attachment", zhHans: "移除附件")
    /// `copy/agent/send`
    static let copyAgentSend = LocalizedCopy(key: "copy/agent/send", en: "Send", zhHans: "发送")
    /// `copy/agent/stop`
    static let copyAgentStop = LocalizedCopy(key: "copy/agent/stop", en: "Stop", zhHans: "停止")
    /// `copy/agent/stopped`
    static let copyAgentStopped = LocalizedCopy(key: "copy/agent/stopped", en: "Stopped.", zhHans: "已停止。")
    /// `copy/agent/thinking`
    static let copyAgentThinking = LocalizedCopy(key: "copy/agent/thinking", en: "Using local services…", zhHans: "正在使用本地服务…")
    /// `copy/agent/you`
    static let copyAgentYou = LocalizedCopy(key: "copy/agent/you", en: "You", zhHans: "你")
    /// `copy/app/name`
    static let copyAppName = LocalizedCopy(key: "copy/app/name", en: "Covio", zhHans: "Covio")
    /// `copy/app/tagline`
    static let copyAppTagline = LocalizedCopy(key: "copy/app/tagline", en: "Keep your Mac awake when it matters.", zhHans: "在需要时保持 Mac 唤醒。")
    /// `copy/auto-naming/action/apply`
    static let copyAutoNamingActionApply = LocalizedCopy(key: "copy/auto-naming/action/apply", en: "Rename Selected", zhHans: "重命名所选")
    /// `copy/auto-naming/action/auto-name`
    static let copyAutoNamingActionAutoName = LocalizedCopy(key: "copy/auto-naming/action/auto-name", en: "Auto Name…", zhHans: "自动命名…")
    /// `copy/auto-naming/action/cancel`
    static let copyAutoNamingActionCancel = LocalizedCopy(key: "copy/auto-naming/action/cancel", en: "Cancel", zhHans: "取消")
    /// `copy/auto-naming/action/close`
    static let copyAutoNamingActionClose = LocalizedCopy(key: "copy/auto-naming/action/close", en: "Close", zhHans: "关闭")
    /// `copy/auto-naming/action/select`
    static let copyAutoNamingActionSelect = LocalizedCopy(key: "copy/auto-naming/action/select", en: "Include this file", zhHans: "选择这个文件")
    /// `copy/auto-naming/action/undo`
    static let copyAutoNamingActionUndo = LocalizedCopy(key: "copy/auto-naming/action/undo", en: "Undo Renames", zhHans: "撤销重命名")
    /// `copy/auto-naming/error/analysis`
    static let copyAutoNamingErrorAnalysis = LocalizedCopy(key: "copy/auto-naming/error/analysis", en: "Auto naming could not finish. No files were changed.", zhHans: "自动命名未完成。文件没有改动。")
    /// `copy/auto-naming/error/rename`
    static let copyAutoNamingErrorRename = LocalizedCopy(key: "copy/auto-naming/error/rename", en: "The rename run failed. No file was overwritten.", zhHans: "重命名失败。没有文件被覆盖。")
    /// `copy/auto-naming/error/undo`
    static let copyAutoNamingErrorUndo = LocalizedCopy(key: "copy/auto-naming/error/undo", en: "Undo could not finish. No file was overwritten.", zhHans: "撤销未完成。没有文件被覆盖。")
    /// `copy/auto-naming/label/evidence`
    static let copyAutoNamingLabelEvidence = LocalizedCopy(key: "copy/auto-naming/label/evidence", en: "Evidence", zhHans: "依据")
    /// `copy/auto-naming/label/original`
    static let copyAutoNamingLabelOriginal = LocalizedCopy(key: "copy/auto-naming/label/original", en: "Current name", zhHans: "当前名称")
    /// `copy/auto-naming/label/target`
    static let copyAutoNamingLabelTarget = LocalizedCopy(key: "copy/auto-naming/label/target", en: "Proposed name", zhHans: "建议名称")
    /// `copy/auto-naming/label/warnings`
    static let copyAutoNamingLabelWarnings = LocalizedCopy(key: "copy/auto-naming/label/warnings", en: "Warnings", zhHans: "警告")
    /// `copy/auto-naming/notice/applied`
    static let copyAutoNamingNoticeApplied = LocalizedCopy(key: "copy/auto-naming/notice/applied", en: "Selected files were renamed.", zhHans: "所选文件已重命名。")
    /// `copy/auto-naming/notice/cancelled`
    static let copyAutoNamingNoticeCancelled = LocalizedCopy(key: "copy/auto-naming/notice/cancelled", en: "Auto naming canceled.", zhHans: "已取消自动命名。")
    /// `copy/auto-naming/notice/no-files`
    static let copyAutoNamingNoticeNoFiles = LocalizedCopy(key: "copy/auto-naming/notice/no-files", en: "Choose at least one file.", zhHans: "请选择至少一个文件。")
    /// `copy/auto-naming/notice/no-results`
    static let copyAutoNamingNoticeNoResults = LocalizedCopy(key: "copy/auto-naming/notice/no-results", en: "No file could be analyzed.", zhHans: "没有可分析的文件。")
    /// `copy/auto-naming/notice/no-selection`
    static let copyAutoNamingNoticeNoSelection = LocalizedCopy(key: "copy/auto-naming/notice/no-selection", en: "Select at least one ready file.", zhHans: "请选择至少一个可重命名文件。")
    /// `copy/auto-naming/notice/partial-failure`
    static let copyAutoNamingNoticePartialFailure = LocalizedCopy(key: "copy/auto-naming/notice/partial-failure", en: "Some files were renamed. Review the failed items.", zhHans: "部分文件已重命名。请检查失败条目。")
    /// `copy/auto-naming/notice/partial-undo`
    static let copyAutoNamingNoticePartialUndo = LocalizedCopy(key: "copy/auto-naming/notice/partial-undo", en: "Some files were restored. Review the failed items.", zhHans: "部分文件已恢复。请检查失败条目。")
    /// `copy/auto-naming/notice/undone`
    static let copyAutoNamingNoticeUndone = LocalizedCopy(key: "copy/auto-naming/notice/undone", en: "The last rename run was undone.", zhHans: "已撤销上次重命名。")
    /// `copy/auto-naming/risk/conflict`
    static let copyAutoNamingRiskConflict = LocalizedCopy(key: "copy/auto-naming/risk/conflict", en: "Name conflict", zhHans: "名称冲突")
    /// `copy/auto-naming/risk/fallback`
    static let copyAutoNamingRiskFallback = LocalizedCopy(key: "copy/auto-naming/risk/fallback", en: "Fallback title", zhHans: "回退标题")
    /// `copy/auto-naming/risk/low-confidence`
    static let copyAutoNamingRiskLowConfidence = LocalizedCopy(key: "copy/auto-naming/risk/low-confidence", en: "Low confidence", zhHans: "低可信")
    /// `copy/auto-naming/risk/mixed`
    static let copyAutoNamingRiskMixed = LocalizedCopy(key: "copy/auto-naming/risk/mixed", en: "Mixed content", zhHans: "混合内容")
    /// `copy/auto-naming/risk/prompt-injection`
    static let copyAutoNamingRiskPromptInjection = LocalizedCopy(key: "copy/auto-naming/risk/prompt-injection", en: "Possible prompt injection", zhHans: "可能存在提示注入")
    /// `copy/auto-naming/risk/scanned`
    static let copyAutoNamingRiskScanned = LocalizedCopy(key: "copy/auto-naming/risk/scanned", en: "Scanned document", zhHans: "扫描件")
    /// `copy/auto-naming/risk/truncated`
    static let copyAutoNamingRiskTruncated = LocalizedCopy(key: "copy/auto-naming/risk/truncated", en: "Input truncated", zhHans: "输入已截断")
    /// `copy/auto-naming/status/blocked`
    static let copyAutoNamingStatusBlocked = LocalizedCopy(key: "copy/auto-naming/status/blocked", en: "Blocked", zhHans: "已阻止")
    /// `copy/auto-naming/status/failed`
    static let copyAutoNamingStatusFailed = LocalizedCopy(key: "copy/auto-naming/status/failed", en: "Failed", zhHans: "失败")
    /// `copy/auto-naming/status/ready`
    static let copyAutoNamingStatusReady = LocalizedCopy(key: "copy/auto-naming/status/ready", en: "Ready", zhHans: "可重命名")
    /// `copy/auto-naming/status/renamed`
    static let copyAutoNamingStatusRenamed = LocalizedCopy(key: "copy/auto-naming/status/renamed", en: "Renamed", zhHans: "已重命名")
    /// `copy/auto-naming/status/undone`
    static let copyAutoNamingStatusUndone = LocalizedCopy(key: "copy/auto-naming/status/undone", en: "Undone", zhHans: "已撤销")
    /// `copy/auto-naming/subtitle`
    static let copyAutoNamingSubtitle = LocalizedCopy(key: "copy/auto-naming/subtitle", en: "Files stay in their original folders. Review every proposed name before applying.", zhHans: "文件留在原目录。应用前请检查每个建议名称。")
    /// `copy/auto-naming/title`
    static let copyAutoNamingTitle = LocalizedCopy(key: "copy/auto-naming/title", en: "Review Auto Names", zhHans: "检查自动命名")
    /// `copy/battery/capacity-threshold`
    static let copyBatteryCapacityThreshold = LocalizedCopy(key: "copy/battery/capacity-threshold", en: "Capacity threshold", zhHans: "容量阈值")
    /// `copy/battery/enabled`
    static let copyBatteryEnabled = LocalizedCopy(key: "copy/battery/enabled", en: "Sleep at low battery", zhHans: "低电量时睡眠")
    /// `copy/battery/time-threshold`
    static let copyBatteryTimeThreshold = LocalizedCopy(key: "copy/battery/time-threshold", en: "Remaining time threshold", zhHans: "剩余时间阈值")
    /// `copy/battery/unit/minutes`
    static let copyBatteryUnitMinutes = LocalizedCopy(key: "copy/battery/unit/minutes", en: "minutes", zhHans: "分钟")
    /// `copy/battery/unit/percent`
    static let copyBatteryUnitPercent = LocalizedCopy(key: "copy/battery/unit/percent", en: "percent", zhHans: "百分比")
    /// `copy/clipboard/action/clear`
    static let copyClipboardActionClear = LocalizedCopy(key: "copy/clipboard/action/clear", en: "Clear All", zhHans: "全部清除")
    /// `copy/clipboard/action/clear-search`
    static let copyClipboardActionClearSearch = LocalizedCopy(key: "copy/clipboard/action/clear-search", en: "Clear Search", zhHans: "清除搜索")
    /// `copy/clipboard/action/open-settings`
    static let copyClipboardActionOpenSettings = LocalizedCopy(key: "copy/clipboard/action/open-settings", en: "Open System Settings", zhHans: "打开系统设置")
    /// `copy/clipboard/action/paste`
    static let copyClipboardActionPaste = LocalizedCopy(key: "copy/clipboard/action/paste", en: "Paste", zhHans: "粘贴")
    /// `copy/clipboard/action/pin`
    static let copyClipboardActionPin = LocalizedCopy(key: "copy/clipboard/action/pin", en: "Pin", zhHans: "置顶")
    /// `copy/clipboard/action/remove`
    static let copyClipboardActionRemove = LocalizedCopy(key: "copy/clipboard/action/remove", en: "Remove", zhHans: "删除")
    /// `copy/clipboard/action/unpin`
    static let copyClipboardActionUnpin = LocalizedCopy(key: "copy/clipboard/action/unpin", en: "Unpin", zhHans: "取消置顶")
    /// `copy/clipboard/action/workspace`
    static let copyClipboardActionWorkspace = LocalizedCopy(key: "copy/clipboard/action/workspace", en: "Save to Workspace", zhHans: "存入工作区")
    /// `copy/clipboard/empty`
    static let copyClipboardEmpty = LocalizedCopy(key: "copy/clipboard/empty", en: "Nothing copied yet", zhHans: "还没有复制内容")
    /// `copy/clipboard/error/accessibility`
    static let copyClipboardErrorAccessibility = LocalizedCopy(key: "copy/clipboard/error/accessibility", en: "Paste needs Accessibility permission.", zhHans: "粘贴回填需要辅助功能权限。")
    /// `copy/clipboard/error/hot-key`
    static let copyClipboardErrorHotKey = LocalizedCopy(key: "copy/clipboard/error/hot-key", en: "This shortcut is already taken.", zhHans: "这个快捷键已被占用。")
    /// `copy/clipboard/error/image`
    static let copyClipboardErrorImage = LocalizedCopy(key: "copy/clipboard/error/image", en: "Cannot save the image.", zhHans: "无法保存图片。")
    /// `copy/clipboard/error/paste`
    static let copyClipboardErrorPaste = LocalizedCopy(key: "copy/clipboard/error/paste", en: "Cannot paste into the front app.", zhHans: "无法粘贴到前台应用。")
    /// `copy/clipboard/filter/all`
    static let copyClipboardFilterAll = LocalizedCopy(key: "copy/clipboard/filter/all", en: "All Types", zhHans: "全部类型")
    /// `copy/clipboard/group/earlier`
    static let copyClipboardGroupEarlier = LocalizedCopy(key: "copy/clipboard/group/earlier", en: "Earlier", zhHans: "更早")
    /// `copy/clipboard/group/pinned`
    static let copyClipboardGroupPinned = LocalizedCopy(key: "copy/clipboard/group/pinned", en: "Pinned", zhHans: "置顶")
    /// `copy/clipboard/group/today`
    static let copyClipboardGroupToday = LocalizedCopy(key: "copy/clipboard/group/today", en: "Today", zhHans: "今天")
    /// `copy/clipboard/group/yesterday`
    static let copyClipboardGroupYesterday = LocalizedCopy(key: "copy/clipboard/group/yesterday", en: "Yesterday", zhHans: "昨天")
    /// `copy/clipboard/kind/dedicated`
    static let copyClipboardKindDedicated = LocalizedCopy(key: "copy/clipboard/kind/dedicated", en: "Dedicated", zhHans: "专有")
    /// `copy/clipboard/no-match/hint`
    static let copyClipboardNoMatchHint = LocalizedCopy(key: "copy/clipboard/no-match/hint", en: "Try another word or clear the search.", zhHans: "换一个词，或清除搜索。")
    /// `copy/clipboard/no-match/title`
    static let copyClipboardNoMatchTitle = LocalizedCopy(key: "copy/clipboard/no-match/title", en: "No matching items", zhHans: "没有匹配内容")
    /// `copy/clipboard/preview/empty`
    static let copyClipboardPreviewEmpty = LocalizedCopy(key: "copy/clipboard/preview/empty", en: "Select an item to preview.", zhHans: "选择一条内容查看详情。")
    /// `copy/clipboard/search-placeholder`
    static let copyClipboardSearchPlaceholder = LocalizedCopy(key: "copy/clipboard/search-placeholder", en: "Search clipboard", zhHans: "搜索剪切板")
    /// `copy/clipboard/settings/accessibility`
    static let copyClipboardSettingsAccessibility = LocalizedCopy(key: "copy/clipboard/settings/accessibility", en: "Accessibility permission", zhHans: "辅助功能权限")
    /// `copy/clipboard/settings/accessibility-fallback`
    static let copyClipboardSettingsAccessibilityFallback = LocalizedCopy(key: "copy/clipboard/settings/accessibility-fallback", en: "Copying still works. Without this permission Covio cannot press ⌘V for you.", zhHans: "复制仍然可用。没有这个权限时 Covio 不能替你按 ⌘V。")
    /// `copy/clipboard/settings/capture-hot-key`
    static let copyClipboardSettingsCaptureHotKey = LocalizedCopy(key: "copy/clipboard/settings/capture-hot-key", en: "Capture selection", zhHans: "抓取选中内容")
    /// `copy/clipboard/settings/enabled`
    static let copyClipboardSettingsEnabled = LocalizedCopy(key: "copy/clipboard/settings/enabled", en: "Record clipboard history", zhHans: "记录剪切板历史")
    /// `copy/clipboard/settings/granted`
    static let copyClipboardSettingsGranted = LocalizedCopy(key: "copy/clipboard/settings/granted", en: "Granted", zhHans: "已授权")
    /// `copy/clipboard/settings/hot-key-conflict`
    static let copyClipboardSettingsHotKeyConflict = LocalizedCopy(key: "copy/clipboard/settings/hot-key-conflict", en: "Registration failed. Another app owns this shortcut. Pick another one.", zhHans: "注册失败。这个快捷键被别的应用占用了，换一个。")
    /// `copy/clipboard/settings/hot-keys`
    static let copyClipboardSettingsHotKeys = LocalizedCopy(key: "copy/clipboard/settings/hot-keys", en: "Shortcuts", zhHans: "快捷键")
    /// `copy/clipboard/settings/not-granted`
    static let copyClipboardSettingsNotGranted = LocalizedCopy(key: "copy/clipboard/settings/not-granted", en: "Not granted", zhHans: "未授权")
    /// `copy/clipboard/settings/paste-stack-hot-key`
    static let copyClipboardSettingsPasteStackHotKey = LocalizedCopy(key: "copy/clipboard/settings/paste-stack-hot-key", en: "Paste next from stack", zhHans: "粘贴栈的下一条")
    /// `copy/clipboard/settings/request-permission`
    static let copyClipboardSettingsRequestPermission = LocalizedCopy(key: "copy/clipboard/settings/request-permission", en: "Request Permission", zhHans: "申请权限")
    /// `copy/clipboard/state/pause`
    static let copyClipboardStatePause = LocalizedCopy(key: "copy/clipboard/state/pause", en: "Pause", zhHans: "暂停记录")
    /// `copy/clipboard/state/paused`
    static let copyClipboardStatePaused = LocalizedCopy(key: "copy/clipboard/state/paused", en: "Recording paused", zhHans: "已暂停记录")
    /// `copy/clipboard/state/resume`
    static let copyClipboardStateResume = LocalizedCopy(key: "copy/clipboard/state/resume", en: "Resume", zhHans: "继续记录")
    /// `copy/clipboard/title`
    static let copyClipboardTitle = LocalizedCopy(key: "copy/clipboard/title", en: "Clipboard", zhHans: "剪切板")
    /// `copy/component/material/blur`
    static let copyComponentMaterialBlur = LocalizedCopy(key: "copy/component/material/blur", en: "Blur", zhHans: "模糊")
    /// `copy/component/material/medium`
    static let copyComponentMaterialMedium = LocalizedCopy(key: "copy/component/material/medium", en: "Medium", zhHans: "中")
    /// `copy/component/material/thick`
    static let copyComponentMaterialThick = LocalizedCopy(key: "copy/component/material/thick", en: "Thick", zhHans: "厚")
    /// `copy/component/material/thin`
    static let copyComponentMaterialThin = LocalizedCopy(key: "copy/component/material/thin", en: "Thin", zhHans: "薄")
    /// `copy/component/material/ultra-thick`
    static let copyComponentMaterialUltraThick = LocalizedCopy(key: "copy/component/material/ultra-thick", en: "Ultra Thick", zhHans: "超厚")
    /// `copy/component/material/ultra-thin`
    static let copyComponentMaterialUltraThin = LocalizedCopy(key: "copy/component/material/ultra-thin", en: "Ultra Thin", zhHans: "超薄")
    /// `copy/component/popover/bottom`
    static let copyComponentPopoverBottom = LocalizedCopy(key: "copy/component/popover/bottom", en: "Bottom", zhHans: "底部")
    /// `copy/component/popover/custom`
    static let copyComponentPopoverCustom = LocalizedCopy(key: "copy/component/popover/custom", en: "Custom", zhHans: "自定义")
    /// `copy/component/popover/form`
    static let copyComponentPopoverForm = LocalizedCopy(key: "copy/component/popover/form", en: "Form", zhHans: "表单")
    /// `copy/component/popover/menu`
    static let copyComponentPopoverMenu = LocalizedCopy(key: "copy/component/popover/menu", en: "Menu", zhHans: "菜单")
    /// `copy/component/popover/top`
    static let copyComponentPopoverTop = LocalizedCopy(key: "copy/component/popover/top", en: "Top", zhHans: "顶部")
    /// `copy/component/toolbar/compact`
    static let copyComponentToolbarCompact = LocalizedCopy(key: "copy/component/toolbar/compact", en: "Compact", zhHans: "紧凑")
    /// `copy/component/toolbar/default`
    static let copyComponentToolbarDefault = LocalizedCopy(key: "copy/component/toolbar/default", en: "Default", zhHans: "默认")
    /// `copy/component/window-shell/compact`
    static let copyComponentWindowShellCompact = LocalizedCopy(key: "copy/component/window-shell/compact", en: "Compact", zhHans: "紧凑")
    /// `copy/component/window-shell/sidebar`
    static let copyComponentWindowShellSidebar = LocalizedCopy(key: "copy/component/window-shell/sidebar", en: "Sidebar", zhHans: "侧边栏")
    /// `copy/component/window-shell/standard`
    static let copyComponentWindowShellStandard = LocalizedCopy(key: "copy/component/window-shell/standard", en: "Standard", zhHans: "标准")
    /// `copy/component/window-shell/toolbar`
    static let copyComponentWindowShellToolbar = LocalizedCopy(key: "copy/component/window-shell/toolbar", en: "Toolbar", zhHans: "工具栏")
    /// `copy/dialog/helper-install/body`
    static let copyDialogHelperInstallBody = LocalizedCopy(key: "copy/dialog/helper-install/body", en: "Covio needs system support for privileged controls.", zhHans: "Covio 需要系统支持来完成特权控制。")
    /// `copy/dialog/helper-install/title`
    static let copyDialogHelperInstallTitle = LocalizedCopy(key: "copy/dialog/helper-install/title", en: "Repair Covio support", zhHans: "修复 Covio 支持")
    /// `copy/dialog/helper-unavailable/body`
    static let copyDialogHelperUnavailableBody = LocalizedCopy(key: "copy/dialog/helper-unavailable/body", en: "Covio system support is unavailable. Reinstall Covio and try again.", zhHans: "Covio 系统支持暂不可用。请重新安装 Covio 后重试。")
    /// `copy/dialog/helper-unavailable/title`
    static let copyDialogHelperUnavailableTitle = LocalizedCopy(key: "copy/dialog/helper-unavailable/title", en: "Covio support unavailable", zhHans: "Covio 支持不可用")
    /// `copy/dialog/reset/body`
    static let copyDialogResetBody = LocalizedCopy(key: "copy/dialog/reset/body", en: "This action removes all local Covio settings.", zhHans: "此操作会删除全部本地 Covio 设置。")
    /// `copy/dialog/reset/title`
    static let copyDialogResetTitle = LocalizedCopy(key: "copy/dialog/reset/title", en: "Clear configuration?", zhHans: "清除配置？")
    /// `copy/dialog/update/body`
    static let copyDialogUpdateBody = LocalizedCopy(key: "copy/dialog/update/body", en: "A new Covio version is ready.", zhHans: "新的 Covio 版本已就绪。")
    /// `copy/dialog/update/title`
    static let copyDialogUpdateTitle = LocalizedCopy(key: "copy/dialog/update/title", en: "Update available", zhHans: "有可用更新")
    /// `copy/general/check-updates`
    static let copyGeneralCheckUpdates = LocalizedCopy(key: "copy/general/check-updates", en: "Check for updates", zhHans: "检查更新")
    /// `copy/general/clear-config`
    static let copyGeneralClearConfig = LocalizedCopy(key: "copy/general/clear-config", en: "Clear Configuration…", zhHans: "清除配置…")
    /// `copy/general/darkwake`
    static let copyGeneralDarkwake = LocalizedCopy(key: "copy/general/darkwake", en: "DarkWake awareness", zhHans: "DarkWake 感知")
    /// `copy/general/external-agent/copied`
    static let copyGeneralExternalAgentCopied = LocalizedCopy(key: "copy/general/external-agent/copied", en: "Pairing copied.", zhHans: "配对信息已复制。")
    /// `copy/general/external-agent/copy-pairing`
    static let copyGeneralExternalAgentCopyPairing = LocalizedCopy(key: "copy/general/external-agent/copy-pairing", en: "Copy Pairing", zhHans: "复制配对信息")
    /// `copy/general/external-agent/enabled`
    static let copyGeneralExternalAgentEnabled = LocalizedCopy(key: "copy/general/external-agent/enabled", en: "Enable local MCP service", zhHans: "启用本地 MCP 服务")
    /// `copy/general/external-agent/endpoint`
    static let copyGeneralExternalAgentEndpoint = LocalizedCopy(key: "copy/general/external-agent/endpoint", en: "Endpoint", zhHans: "Endpoint")
    /// `copy/general/external-agent/rotate-token`
    static let copyGeneralExternalAgentRotateToken = LocalizedCopy(key: "copy/general/external-agent/rotate-token", en: "Rotate Token", zhHans: "轮换 Token")
    /// `copy/general/external-agent/starting`
    static let copyGeneralExternalAgentStarting = LocalizedCopy(key: "copy/general/external-agent/starting", en: "Starting…", zhHans: "正在启动…")
    /// `copy/general/external-agent/summary`
    static let copyGeneralExternalAgentSummary = LocalizedCopy(key: "copy/general/external-agent/summary", en: "Allow local agents to use Covio services through an authenticated MCP endpoint.", zhHans: "允许本地 Agent 通过带认证的 MCP endpoint 使用 Covio 服务。")
    /// `copy/general/external-agent/title`
    static let copyGeneralExternalAgentTitle = LocalizedCopy(key: "copy/general/external-agent/title", en: "External Agent", zhHans: "外部 Agent")
    /// `copy/general/external-agent/unavailable`
    static let copyGeneralExternalAgentUnavailable = LocalizedCopy(key: "copy/general/external-agent/unavailable", en: "Local MCP service is unavailable.", zhHans: "本地 MCP 服务不可用。")
    /// `copy/general/external-agent/warning`
    static let copyGeneralExternalAgentWarning = LocalizedCopy(key: "copy/general/external-agent/warning", en: "Only loopback clients with the token can connect. Side effects still require confirmation.", zhHans: "只有持有 token 的 loopback 客户端可以连接。副作用仍需要确认。")
    /// `copy/general/language`
    static let copyGeneralLanguage = LocalizedCopy(key: "copy/general/language", en: "Language", zhHans: "语言")
    /// `copy/general/language/chinese`
    static let copyGeneralLanguageChinese = LocalizedCopy(key: "copy/general/language/chinese", en: "Simplified Chinese", zhHans: "简体中文")
    /// `copy/general/language/english`
    static let copyGeneralLanguageEnglish = LocalizedCopy(key: "copy/general/language/english", en: "English", zhHans: "English")
    /// `copy/general/language/system`
    static let copyGeneralLanguageSystem = LocalizedCopy(key: "copy/general/language/system", en: "Follow System", zhHans: "跟随系统")
    /// `copy/general/launch-at-login`
    static let copyGeneralLaunchAtLogin = LocalizedCopy(key: "copy/general/launch-at-login", en: "Launch at login", zhHans: "登录时启动")
    /// `copy/general/local-model/active`
    static let copyGeneralLocalModelActive = LocalizedCopy(key: "copy/general/local-model/active", en: "Active", zhHans: "已启用")
    /// `copy/general/local-model/agent-disabled`
    static let copyGeneralLocalModelAgentDisabled = LocalizedCopy(key: "copy/general/local-model/agent-disabled", en: "Agent tool calling is unavailable while the 30B-A3B model is active.", zhHans: "30B-A3B 模型启用时不能使用 Agent 工具调用。")
    /// `copy/general/local-model/failed`
    static let copyGeneralLocalModelFailed = LocalizedCopy(key: "copy/general/local-model/failed", en: "The model package could not be loaded.", zhHans: "无法加载模型包。")
    /// `copy/general/local-model/import`
    static let copyGeneralLocalModelImport = LocalizedCopy(key: "copy/general/local-model/import", en: "Import…", zhHans: "导入…")
    /// `copy/general/local-model/minimum`
    static let copyGeneralLocalModelMinimum = LocalizedCopy(key: "copy/general/local-model/minimum", en: "Requires %d GB RAM", zhHans: "需要 %d GB 内存")
    /// `copy/general/local-model/summary`
    static let copyGeneralLocalModelSummary = LocalizedCopy(key: "copy/general/local-model/summary", en: "Download or import a model. AI features run locally after setup.", zhHans: "下载或导入模型。安装完成后，AI 功能在本机运行。")
    /// `copy/general/local-model/title`
    static let copyGeneralLocalModelTitle = LocalizedCopy(key: "copy/general/local-model/title", en: "Local model", zhHans: "本地模型")
    /// `copy/general/local-model/unsupported`
    static let copyGeneralLocalModelUnsupported = LocalizedCopy(key: "copy/general/local-model/unsupported", en: "Not supported on this Mac", zhHans: "这台 Mac 不支持")
    /// `copy/general/local-model/use`
    static let copyGeneralLocalModelUse = LocalizedCopy(key: "copy/general/local-model/use", en: "Use", zhHans: "使用")
    /// `copy/general/local-model/verifying`
    static let copyGeneralLocalModelVerifying = LocalizedCopy(key: "copy/general/local-model/verifying", en: "Verifying…", zhHans: "正在验证…")
    /// `copy/general/notifications`
    static let copyGeneralNotifications = LocalizedCopy(key: "copy/general/notifications", en: "Notifications", zhHans: "通知")
    /// `copy/general/sleep-mode`
    static let copyGeneralSleepMode = LocalizedCopy(key: "copy/general/sleep-mode", en: "Sleep mode", zhHans: "睡眠模式")
    /// `copy/general/sleep-mode/default`
    static let copyGeneralSleepModeDefault = LocalizedCopy(key: "copy/general/sleep-mode/default", en: "3 · Default", zhHans: "3 · 默认")
    /// `copy/general/sleep-mode/fastest`
    static let copyGeneralSleepModeFastest = LocalizedCopy(key: "copy/general/sleep-mode/fastest", en: "0 · Fastest", zhHans: "0 · 最快")
    /// `copy/general/sleep-mode/lowest-power`
    static let copyGeneralSleepModeLowestPower = LocalizedCopy(key: "copy/general/sleep-mode/lowest-power", en: "25 · Lowest power", zhHans: "25 · 最省电")
    /// `copy/helper/service/enabled`
    static let copyHelperServiceEnabled = LocalizedCopy(key: "copy/helper/service/enabled", en: "Managed by macOS", zhHans: "由 macOS 管理")
    /// `copy/helper/service/error`
    static let copyHelperServiceError = LocalizedCopy(key: "copy/helper/service/error", en: "Covio system support needs attention", zhHans: "Covio 系统支持需要处理")
    /// `copy/helper/service/legacy`
    static let copyHelperServiceLegacy = LocalizedCopy(key: "copy/helper/service/legacy", en: "Covio support needs migration", zhHans: "Covio 支持需要迁移")
    /// `copy/helper/service/not-found`
    static let copyHelperServiceNotFound = LocalizedCopy(key: "copy/helper/service/not-found", en: "Bundled Covio support is missing", zhHans: "应用内的 Covio 支持缺失")
    /// `copy/helper/service/not-registered`
    static let copyHelperServiceNotRegistered = LocalizedCopy(key: "copy/helper/service/not-registered", en: "Covio support is not registered", zhHans: "Covio 支持未注册")
    /// `copy/helper/service/requires-approval`
    static let copyHelperServiceRequiresApproval = LocalizedCopy(key: "copy/helper/service/requires-approval", en: "Approve Covio support in System Settings", zhHans: "请在系统设置中批准 Covio 支持")
    /// `copy/helper/service/unsupported`
    static let copyHelperServiceUnsupported = LocalizedCopy(key: "copy/helper/service/unsupported", en: "Covio support is unavailable on this macOS", zhHans: "当前 macOS 不支持所需系统能力")
    /// `copy/hub/action/back`
    static let copyHubActionBack = LocalizedCopy(key: "copy/hub/action/back", en: "Back", zhHans: "返回")
    /// `copy/hub/action/done`
    static let copyHubActionDone = LocalizedCopy(key: "copy/hub/action/done", en: "Done", zhHans: "完成")
    /// `copy/hub/action/edit`
    static let copyHubActionEdit = LocalizedCopy(key: "copy/hub/action/edit", en: "Edit", zhHans: "编辑")
    /// `copy/hub/action/home`
    static let copyHubActionHome = LocalizedCopy(key: "copy/hub/action/home", en: "Home", zhHans: "首页")
    /// `copy/hub/action/settings`
    static let copyHubActionSettings = LocalizedCopy(key: "copy/hub/action/settings", en: "Settings", zhHans: "设置")
    /// `copy/hub/edit/banner`
    static let copyHubEditBanner = LocalizedCopy(key: "copy/hub/edit/banner", en: "Edit mode: drag tabs or cards to move them, use arrow keys to nudge, drag the corner to resize, click the cross to remove.", zhHans: "编辑模式：拖动页签或卡片移动，方向键微调，拖右下角缩放，点叉删除。")
    /// `copy/hub/edit/reorder`
    static let copyHubEditReorder = LocalizedCopy(key: "copy/hub/edit/reorder", en: "Reorder", zhHans: "排序")
    /// `copy/hub/edit/widget-count`
    static let copyHubEditWidgetCount = LocalizedCopy(key: "copy/hub/edit/widget-count", en: "widgets", zhHans: "块组件")
    /// `copy/hub/edit/workspace-count`
    static let copyHubEditWorkspaceCount = LocalizedCopy(key: "copy/hub/edit/workspace-count", en: "workspaces", zhHans: "个工作区")
    /// `copy/hub/files/action/add`
    static let copyHubFilesActionAdd = LocalizedCopy(key: "copy/hub/files/action/add", en: "Add…", zhHans: "加入…")
    /// `copy/hub/files/action/cancel-transfer`
    static let copyHubFilesActionCancelTransfer = LocalizedCopy(key: "copy/hub/files/action/cancel-transfer", en: "Cancel Transfer", zhHans: "取消传输")
    /// `copy/hub/files/action/clear-filter`
    static let copyHubFilesActionClearFilter = LocalizedCopy(key: "copy/hub/files/action/clear-filter", en: "Clear Filter", zhHans: "清除筛选")
    /// `copy/hub/files/action/copy`
    static let copyHubFilesActionCopy = LocalizedCopy(key: "copy/hub/files/action/copy", en: "Copy", zhHans: "复制")
    /// `copy/hub/files/action/copy-text`
    static let copyHubFilesActionCopyText = LocalizedCopy(key: "copy/hub/files/action/copy-text", en: "Copy Text", zhHans: "复制正文")
    /// `copy/hub/files/action/dismiss`
    static let copyHubFilesActionDismiss = LocalizedCopy(key: "copy/hub/files/action/dismiss", en: "Dismiss", zhHans: "关闭")
    /// `copy/hub/files/action/download`
    static let copyHubFilesActionDownload = LocalizedCopy(key: "copy/hub/files/action/download", en: "Download", zhHans: "下载")
    /// `copy/hub/files/action/import`
    static let copyHubFilesActionImport = LocalizedCopy(key: "copy/hub/files/action/import", en: "Import Files…", zhHans: "放入文件…")
    /// `copy/hub/files/action/markup`
    static let copyHubFilesActionMarkup = LocalizedCopy(key: "copy/hub/files/action/markup", en: "Mark Up", zhHans: "标注")
    /// `copy/hub/files/action/more`
    static let copyHubFilesActionMore = LocalizedCopy(key: "copy/hub/files/action/more", en: "More", zhHans: "更多")
    /// `copy/hub/files/action/new-text`
    static let copyHubFilesActionNewText = LocalizedCopy(key: "copy/hub/files/action/new-text", en: "New Text…", zhHans: "新建文本…")
    /// `copy/hub/files/action/open`
    static let copyHubFilesActionOpen = LocalizedCopy(key: "copy/hub/files/action/open", en: "Open", zhHans: "打开")
    /// `copy/hub/files/action/pin`
    static let copyHubFilesActionPin = LocalizedCopy(key: "copy/hub/files/action/pin", en: "Pin", zhHans: "置顶")
    /// `copy/hub/files/action/remove`
    static let copyHubFilesActionRemove = LocalizedCopy(key: "copy/hub/files/action/remove", en: "Remove", zhHans: "删除")
    /// `copy/hub/files/action/retry`
    static let copyHubFilesActionRetry = LocalizedCopy(key: "copy/hub/files/action/retry", en: "Retry", zhHans: "重试")
    /// `copy/hub/files/action/reveal`
    static let copyHubFilesActionReveal = LocalizedCopy(key: "copy/hub/files/action/reveal", en: "Show in Finder", zhHans: "在访达中显示")
    /// `copy/hub/files/action/save-to-workspace`
    static let copyHubFilesActionSaveToWorkspace = LocalizedCopy(key: "copy/hub/files/action/save-to-workspace", en: "Save to Workspace", zhHans: "存入工作区")
    /// `copy/hub/files/action/sweep`
    static let copyHubFilesActionSweep = LocalizedCopy(key: "copy/hub/files/action/sweep", en: "Clean Up", zhHans: "清理过期")
    /// `copy/hub/files/action/unpin`
    static let copyHubFilesActionUnpin = LocalizedCopy(key: "copy/hub/files/action/unpin", en: "Unpin", zhHans: "取消置顶")
    /// `copy/hub/files/count/items`
    static let copyHubFilesCountItems = LocalizedCopy(key: "copy/hub/files/count/items", en: "items", zhHans: "项")
    /// `copy/hub/files/empty`
    static let copyHubFilesEmpty = LocalizedCopy(key: "copy/hub/files/empty", en: "The workspace is empty", zhHans: "工作区还是空的")
    /// `copy/hub/files/empty/hint`
    static let copyHubFilesEmptyHint = LocalizedCopy(key: "copy/hub/files/empty/hint", en: "Screenshots, files, and text stay in recent use.", zhHans: "截图、文件或文本会停在最近使用的位置。")
    /// `copy/hub/files/empty/title`
    static let copyHubFilesEmptyTitle = LocalizedCopy(key: "copy/hub/files/empty/title", en: "Drop the next item here", zhHans: "把下一件内容放进来")
    /// `copy/hub/files/error/connection`
    static let copyHubFilesErrorConnection = LocalizedCopy(key: "copy/hub/files/error/connection", en: "Cannot reach the other device.", zhHans: "无法连接另一台设备。")
    /// `copy/hub/files/error/copy`
    static let copyHubFilesErrorCopy = LocalizedCopy(key: "copy/hub/files/error/copy", en: "Cannot copy this item.", zhHans: "无法复制这件内容。")
    /// `copy/hub/files/error/import`
    static let copyHubFilesErrorImport = LocalizedCopy(key: "copy/hub/files/error/import", en: "Cannot read this file.", zhHans: "读不到这个文件。")
    /// `copy/hub/files/error/missing`
    static let copyHubFilesErrorMissing = LocalizedCopy(key: "copy/hub/files/error/missing", en: "This device no longer has the content.", zhHans: "本机已经没有这份内容。")
    /// `copy/hub/files/error/quota`
    static let copyHubFilesErrorQuota = LocalizedCopy(key: "copy/hub/files/error/quota", en: "The workspace is full. Remove an entry or raise the limit.", zhHans: "工作区已满。删除一些条目，或调高上限。")
    /// `copy/hub/files/error/save`
    static let copyHubFilesErrorSave = LocalizedCopy(key: "copy/hub/files/error/save", en: "Cannot write to the workspace.", zhHans: "写不进工作区。")
    /// `copy/hub/files/error/too-large`
    static let copyHubFilesErrorTooLarge = LocalizedCopy(key: "copy/hub/files/error/too-large", en: "This file is over the single entry limit.", zhHans: "这个文件超过单条目上限。")
    /// `copy/hub/files/filter/all`
    static let copyHubFilesFilterAll = LocalizedCopy(key: "copy/hub/files/filter/all", en: "All", zhHans: "全部")
    /// `copy/hub/files/filter/files`
    static let copyHubFilesFilterFiles = LocalizedCopy(key: "copy/hub/files/filter/files", en: "Files", zhHans: "文件")
    /// `copy/hub/files/filter/screenshots`
    static let copyHubFilesFilterScreenshots = LocalizedCopy(key: "copy/hub/files/filter/screenshots", en: "Screenshots", zhHans: "截图")
    /// `copy/hub/files/filter/text`
    static let copyHubFilesFilterText = LocalizedCopy(key: "copy/hub/files/filter/text", en: "Text", zhHans: "文本")
    /// `copy/hub/files/filter/transfers`
    static let copyHubFilesFilterTransfers = LocalizedCopy(key: "copy/hub/files/filter/transfers", en: "Transfers", zhHans: "传输")
    /// `copy/hub/files/hint`
    static let copyHubFilesHint = LocalizedCopy(key: "copy/hub/files/hint", en: "Drop files here, or use Import Files.", zhHans: "把文件拖到这里，或点「放入文件」。")
    /// `copy/hub/files/kind/audio`
    static let copyHubFilesKindAudio = LocalizedCopy(key: "copy/hub/files/kind/audio", en: "Audio", zhHans: "音频")
    /// `copy/hub/files/kind/image`
    static let copyHubFilesKindImage = LocalizedCopy(key: "copy/hub/files/kind/image", en: "Image", zhHans: "图片")
    /// `copy/hub/files/kind/pdf`
    static let copyHubFilesKindPdf = LocalizedCopy(key: "copy/hub/files/kind/pdf", en: "PDF", zhHans: "PDF")
    /// `copy/hub/files/no-match/hint`
    static let copyHubFilesNoMatchHint = LocalizedCopy(key: "copy/hub/files/no-match/hint", en: "Try another keyword or clear the current filter.", zhHans: "换一个关键词，或清除当前筛选。")
    /// `copy/hub/files/no-match/title`
    static let copyHubFilesNoMatchTitle = LocalizedCopy(key: "copy/hub/files/no-match/title", en: "No matching files", zhHans: "没有匹配的文件")
    /// `copy/hub/files/notice/duplicate`
    static let copyHubFilesNoticeDuplicate = LocalizedCopy(key: "copy/hub/files/notice/duplicate", en: "The workspace already has this content.", zhHans: "工作区里已经有这份内容。")
    /// `copy/hub/files/notice/saved`
    static let copyHubFilesNoticeSaved = LocalizedCopy(key: "copy/hub/files/notice/saved", en: "Saved to the workspace.", zhHans: "已存入工作区。")
    /// `copy/hub/files/notice/swept`
    static let copyHubFilesNoticeSwept = LocalizedCopy(key: "copy/hub/files/notice/swept", en: "Removed expired entries.", zhHans: "已清理过期条目。")
    /// `copy/hub/files/state/fetching`
    static let copyHubFilesStateFetching = LocalizedCopy(key: "copy/hub/files/state/fetching", en: "Retrieving", zhHans: "正在取回")
    /// `copy/hub/files/state/local`
    static let copyHubFilesStateLocal = LocalizedCopy(key: "copy/hub/files/state/local", en: "Available on this Mac", zhHans: "本机可用")
    /// `copy/hub/files/state/on-other-device`
    static let copyHubFilesStateOnOtherDevice = LocalizedCopy(key: "copy/hub/files/state/on-other-device", en: "On another device", zhHans: "在另一台设备")
    /// `copy/hub/files/state/transfer-cancelled`
    static let copyHubFilesStateTransferCancelled = LocalizedCopy(key: "copy/hub/files/state/transfer-cancelled", en: "Transfer cancelled", zhHans: "已取消传输")
    /// `copy/hub/files/state/transfer-failed`
    static let copyHubFilesStateTransferFailed = LocalizedCopy(key: "copy/hub/files/state/transfer-failed", en: "Transfer failed", zhHans: "传输失败")
    /// `copy/hub/files/state/transferring`
    static let copyHubFilesStateTransferring = LocalizedCopy(key: "copy/hub/files/state/transferring", en: "Transferring", zhHans: "正在传输")
    /// `copy/hub/files/state/unavailable`
    static let copyHubFilesStateUnavailable = LocalizedCopy(key: "copy/hub/files/state/unavailable", en: "Content unavailable", zhHans: "内容不可用")
    /// `copy/hub/files/state/waiting`
    static let copyHubFilesStateWaiting = LocalizedCopy(key: "copy/hub/files/state/waiting", en: "Waiting to transfer", zhHans: "等待传输")
    /// `copy/hub/files/status/active`
    static let copyHubFilesStatusActive = LocalizedCopy(key: "copy/hub/files/status/active", en: "active", zhHans: "进行中")
    /// `copy/hub/files/usage`
    static let copyHubFilesUsage = LocalizedCopy(key: "copy/hub/files/usage", en: "In use", zhHans: "已占用")
    /// `copy/hub/home/empty-hint`
    static let copyHubHomeEmptyHint = LocalizedCopy(key: "copy/hub/home/empty-hint", en: "Turn on edit mode to add widgets.", zhHans: "进入编辑模式可以添加组件。")
    /// `copy/hub/home/empty-hint-editing`
    static let copyHubHomeEmptyHintEditing = LocalizedCopy(key: "copy/hub/home/empty-hint-editing", en: "Drag one in from the widget library.", zhHans: "从组件库里拖一块进来。")
    /// `copy/hub/home/empty-title`
    static let copyHubHomeEmptyTitle = LocalizedCopy(key: "copy/hub/home/empty-title", en: "No widgets yet", zhHans: "首页还没有组件")
    /// `copy/hub/log/export`
    static let copyHubLogExport = LocalizedCopy(key: "copy/hub/log/export", en: "Export Log…", zhHans: "导出日志…")
    /// `copy/hub/log/view`
    static let copyHubLogView = LocalizedCopy(key: "copy/hub/log/view", en: "View Log", zhHans: "查看日志")
    /// `copy/hub/placeholder-notice`
    static let copyHubPlaceholderNotice = LocalizedCopy(key: "copy/hub/placeholder-notice", en: "This tab is a placeholder. Content lands in a later phase.", zhHans: "本页签是占位。内容在后续阶段落地。")
    /// `copy/hub/power/segment/overview`
    static let copyHubPowerSegmentOverview = LocalizedCopy(key: "copy/hub/power/segment/overview", en: "Overview", zhHans: "概览")
    /// `copy/hub/power/segment/power`
    static let copyHubPowerSegmentPower = LocalizedCopy(key: "copy/hub/power/segment/power", en: "Power", zhHans: "电源")
    /// `copy/hub/power/summary`
    static let copyHubPowerSummary = LocalizedCopy(key: "copy/hub/power/summary", en: "Manage sleep, display, lid, battery, and adapter behavior.", zhHans: "管理睡眠、屏幕、合盖、电池和适配器行为。")
    /// `copy/hub/power/title`
    static let copyHubPowerTitle = LocalizedCopy(key: "copy/hub/power/title", en: "Power management", zhHans: "电源管理")
    /// `copy/hub/search/clear`
    static let copyHubSearchClear = LocalizedCopy(key: "copy/hub/search/clear", en: "Clear search", zhHans: "清除搜索")
    /// `copy/hub/tab/agent`
    static let copyHubTabAgent = LocalizedCopy(key: "copy/hub/tab/agent", en: "Agent", zhHans: "助手")
    /// `copy/hub/tab/agent/summary`
    static let copyHubTabAgentSummary = LocalizedCopy(key: "copy/hub/tab/agent/summary", en: "Chat with the offline local agent and its local services.", zhHans: "与离线本地 Agent 对话并使用本地服务。")
    /// `copy/hub/tab/board`
    static let copyHubTabBoard = LocalizedCopy(key: "copy/hub/tab/board", en: "Custom", zhHans: "自建")
    /// `copy/hub/tab/board/summary`
    static let copyHubTabBoardSummary = LocalizedCopy(key: "copy/hub/tab/board/summary", en: "A custom workspace with just the widget grid.", zhHans: "自建工作区，只有组件网格。")
    /// `copy/hub/tab/clipboard`
    static let copyHubTabClipboard = LocalizedCopy(key: "copy/hub/tab/clipboard", en: "Clipboard", zhHans: "剪贴板")
    /// `copy/hub/tab/clipboard/summary`
    static let copyHubTabClipboardSummary = LocalizedCopy(key: "copy/hub/tab/clipboard/summary", en: "Find recent files, text, images, and screenshots.", zhHans: "按时间查找文件、文本、图片和截图。")
    /// `copy/hub/tab/devices`
    static let copyHubTabDevices = LocalizedCopy(key: "copy/hub/tab/devices", en: "Monitor", zhHans: "监控")
    /// `copy/hub/tab/devices/summary`
    static let copyHubTabDevicesSummary = LocalizedCopy(key: "copy/hub/tab/devices/summary", en: "Live CPU, GPU, memory, disk, network, and power metrics.", zhHans: "CPU、GPU、内存、磁盘、网络和电源的实时指标。")
    /// `copy/hub/tab/files`
    static let copyHubTabFiles = LocalizedCopy(key: "copy/hub/tab/files", en: "Files", zhHans: "文件")
    /// `copy/hub/tab/files/summary`
    static let copyHubTabFilesSummary = LocalizedCopy(key: "copy/hub/tab/files/summary", en: "Temporary files, free space, and expiry.", zhHans: "临时文件、剩余空间和过期时间。")
    /// `copy/hub/tab/now`
    static let copyHubTabNow = LocalizedCopy(key: "copy/hub/tab/now", en: "Now", zhHans: "现在")
    /// `copy/hub/tab/now/summary`
    static let copyHubTabNowSummary = LocalizedCopy(key: "copy/hub/tab/now/summary", en: "Power, battery, lid, device links, and pending items.", zhHans: "电源、电池、合盖、设备连接和待处理项。")
    /// `copy/hub/tab/screenshots`
    static let copyHubTabScreenshots = LocalizedCopy(key: "copy/hub/tab/screenshots", en: "Screenshots", zhHans: "截图")
    /// `copy/hub/tab/screenshots/summary`
    static let copyHubTabScreenshotsSummary = LocalizedCopy(key: "copy/hub/tab/screenshots/summary", en: "Recent screenshots and the capture toolbar.", zhHans: "最近截图和截图工具栏。")
    /// `copy/hub/tab/settings`
    static let copyHubTabSettings = LocalizedCopy(key: "copy/hub/tab/settings", en: "Settings", zhHans: "设置")
    /// `copy/hub/tab/settings/summary`
    static let copyHubTabSettingsSummary = LocalizedCopy(key: "copy/hub/tab/settings/summary", en: "Permissions, language, notifications, privacy, and retention.", zhHans: "权限、语言、通知、隐私和保留策略。")
    /// `copy/hub/update/up-to-date`
    static let copyHubUpdateUpToDate = LocalizedCopy(key: "copy/hub/update/up-to-date", en: "Covio is up to date.", zhHans: "Covio 已是最新版本。")
    /// `copy/hub/widget/actions/title`
    static let copyHubWidgetActionsTitle = LocalizedCopy(key: "copy/hub/widget/actions/title", en: "Shortcuts", zhHans: "快捷操作")
    /// `copy/hub/widget/battery/title`
    static let copyHubWidgetBatteryTitle = LocalizedCopy(key: "copy/hub/widget/battery/title", en: "Battery", zhHans: "电量")
    /// `copy/hub/widget/clock/title`
    static let copyHubWidgetClockTitle = LocalizedCopy(key: "copy/hub/widget/clock/title", en: "Now", zhHans: "现在")
    /// `copy/hub/widget/devices/title`
    static let copyHubWidgetDevicesTitle = LocalizedCopy(key: "copy/hub/widget/devices/title", en: "Monitor", zhHans: "监控")
    /// `copy/hub/widget/move-down`
    static let copyHubWidgetMoveDown = LocalizedCopy(key: "copy/hub/widget/move-down", en: "Move down", zhHans: "向下移动")
    /// `copy/hub/widget/move-left`
    static let copyHubWidgetMoveLeft = LocalizedCopy(key: "copy/hub/widget/move-left", en: "Move left", zhHans: "向左移动")
    /// `copy/hub/widget/move-right`
    static let copyHubWidgetMoveRight = LocalizedCopy(key: "copy/hub/widget/move-right", en: "Move right", zhHans: "向右移动")
    /// `copy/hub/widget/move-up`
    static let copyHubWidgetMoveUp = LocalizedCopy(key: "copy/hub/widget/move-up", en: "Move up", zhHans: "向上移动")
    /// `copy/hub/widget/remove`
    static let copyHubWidgetRemove = LocalizedCopy(key: "copy/hub/widget/remove", en: "Remove", zhHans: "删除")
    /// `copy/hub/widget/resize`
    static let copyHubWidgetResize = LocalizedCopy(key: "copy/hub/widget/resize", en: "Resize", zhHans: "缩放")
    /// `copy/hub/widget/shots/title`
    static let copyHubWidgetShotsTitle = LocalizedCopy(key: "copy/hub/widget/shots/title", en: "Recent Shots", zhHans: "最近截图")
    /// `copy/hub/widget/size/large`
    static let copyHubWidgetSizeLarge = LocalizedCopy(key: "copy/hub/widget/size/large", en: "Large", zhHans: "大")
    /// `copy/hub/widget/size/small`
    static let copyHubWidgetSizeSmall = LocalizedCopy(key: "copy/hub/widget/size/small", en: "Small", zhHans: "小")
    /// `copy/hub/widget/size/tall`
    static let copyHubWidgetSizeTall = LocalizedCopy(key: "copy/hub/widget/size/tall", en: "Tall", zhHans: "高")
    /// `copy/hub/widget/size/wide`
    static let copyHubWidgetSizeWide = LocalizedCopy(key: "copy/hub/widget/size/wide", en: "Wide", zhHans: "宽")
    /// `copy/hub/widget/transfer/title`
    static let copyHubWidgetTransferTitle = LocalizedCopy(key: "copy/hub/widget/transfer/title", en: "Transfers", zhHans: "传输")
    /// `copy/icon/concept/blue-grid`
    static let copyIconConceptBlueGrid = LocalizedCopy(key: "copy/icon/concept/blue-grid", en: "05 · BLUE GRID", zhHans: "05 · 蓝色网格")
    /// `copy/icon/concept/blue-koala`
    static let copyIconConceptBlueKoala = LocalizedCopy(key: "copy/icon/concept/blue-koala", en: "00 · BLUE KOALA", zhHans: "00 · 蓝色考拉")
    /// `copy/icon/concept/blue-orbit`
    static let copyIconConceptBlueOrbit = LocalizedCopy(key: "copy/icon/concept/blue-orbit", en: "01 · BLUE ORBIT", zhHans: "01 · 蓝色轨道")
    /// `copy/icon/concept/notch-core`
    static let copyIconConceptNotchCore = LocalizedCopy(key: "copy/icon/concept/notch-core", en: "02 · NOTCH CORE", zhHans: "02 · 刘海核心")
    /// `copy/icon/concept/status-pulse`
    static let copyIconConceptStatusPulse = LocalizedCopy(key: "copy/icon/concept/status-pulse", en: "04 · STATUS PULSE", zhHans: "04 · 状态脉冲")
    /// `copy/icon/concept/top-shelf`
    static let copyIconConceptTopShelf = LocalizedCopy(key: "copy/icon/concept/top-shelf", en: "03 · TOP SHELF", zhHans: "03 · 顶部挂架")
    /// `copy/idle/cancel-after`
    static let copyIdleCancelAfter = LocalizedCopy(key: "copy/idle/cancel-after", en: "Cancel after", zhHans: "在此时间后取消")
    /// `copy/idle/prevent-idle`
    static let copyIdlePreventIdle = LocalizedCopy(key: "copy/idle/prevent-idle", en: "Prevent idle sleep", zhHans: "阻止闲置睡眠")
    /// `copy/idle/remaining`
    static let copyIdleRemaining = LocalizedCopy(key: "copy/idle/remaining", en: "Remaining time", zhHans: "剩余时间")
    /// `copy/idle/while-charging`
    static let copyIdleWhileCharging = LocalizedCopy(key: "copy/idle/while-charging", en: "Prevent sleep while charging", zhHans: "充电时阻止睡眠")
    /// `copy/lid/hold-policy`
    static let copyLidHoldPolicy = LocalizedCopy(key: "copy/lid/hold-policy", en: "Closed-lid behavior", zhHans: "合盖行为")
    /// `copy/lid/hold-policy/adapter`
    static let copyLidHoldPolicyAdapter = LocalizedCopy(key: "copy/lid/hold-policy/adapter", en: "Keep awake on power adapter", zhHans: "接通电源时保持运行")
    /// `copy/lid/hold-policy/any`
    static let copyLidHoldPolicyAny = LocalizedCopy(key: "copy/lid/hold-policy/any", en: "Always keep awake", zhHans: "始终保持运行")
    /// `copy/lid/hold-policy/battery`
    static let copyLidHoldPolicyBattery = LocalizedCopy(key: "copy/lid/hold-policy/battery", en: "Keep awake on battery", zhHans: "使用电池时保持运行")
    /// `copy/lid/hold-policy/hint`
    static let copyLidHoldPolicyHint = LocalizedCopy(key: "copy/lid/hold-policy/hint", en: "macOS still controls screen locking and authentication.", zhHans: "macOS 仍会独立执行锁屏和身份验证。")
    /// `copy/lid/hold-policy/sleep`
    static let copyLidHoldPolicySleep = LocalizedCopy(key: "copy/lid/hold-policy/sleep", en: "Sleep when the lid closes", zhHans: "合盖时睡眠")
    /// `copy/lid/warning`
    static let copyLidWarning = LocalizedCopy(key: "copy/lid/warning", en: "This option increases battery drain.", zhHans: "此选项会增加电池耗电。")
    /// `copy/macos27-alignment/measurement`
    static let copyMacos27AlignmentMeasurement = LocalizedCopy(key: "copy/macos27-alignment/measurement", en: "Measurement Comparison", zhHans: "测量值对照")
    /// `copy/macos27-alignment/static-verified`
    static let copyMacos27AlignmentStaticVerified = LocalizedCopy(key: "copy/macos27-alignment/static-verified", en: "Static verified", zhHans: "静态已验证")
    /// `copy/mode/dark`
    static let copyModeDark = LocalizedCopy(key: "copy/mode/dark", en: "Dark", zhHans: "深色")
    /// `copy/mode/light`
    static let copyModeLight = LocalizedCopy(key: "copy/mode/light", en: "Light", zhHans: "浅色")
    /// `copy/model-setup/action-download`
    static let copyModelSetupActionDownload = LocalizedCopy(key: "copy/model-setup/action-download", en: "Download model", zhHans: "下载模型")
    /// `copy/model-setup/action-pause`
    static let copyModelSetupActionPause = LocalizedCopy(key: "copy/model-setup/action-pause", en: "Pause", zhHans: "暂停")
    /// `copy/model-setup/action-remove`
    static let copyModelSetupActionRemove = LocalizedCopy(key: "copy/model-setup/action-remove", en: "Remove model", zhHans: "移除模型")
    /// `copy/model-setup/action-resume`
    static let copyModelSetupActionResume = LocalizedCopy(key: "copy/model-setup/action-resume", en: "Resume", zhHans: "继续")
    /// `copy/model-setup/action-retry`
    static let copyModelSetupActionRetry = LocalizedCopy(key: "copy/model-setup/action-retry", en: "Retry", zhHans: "重试")
    /// `copy/model-setup/error-activation`
    static let copyModelSetupErrorActivation = LocalizedCopy(key: "copy/model-setup/error-activation", en: "The model was downloaded but could not be activated. Retry.", zhHans: "模型已下载，但无法启用。请重试。")
    /// `copy/model-setup/error-disk`
    static let copyModelSetupErrorDisk = LocalizedCopy(key: "copy/model-setup/error-disk", en: "Not enough disk space. Free space and retry.", zhHans: "磁盘空间不足。释放空间后重试。")
    /// `copy/model-setup/error-generic`
    static let copyModelSetupErrorGeneric = LocalizedCopy(key: "copy/model-setup/error-generic", en: "The model could not be installed. Retry or import a local package.", zhHans: "无法安装模型。请重试或导入本地模型包。")
    /// `copy/model-setup/error-memory`
    static let copyModelSetupErrorMemory = LocalizedCopy(key: "copy/model-setup/error-memory", en: "This Mac does not have enough available memory.", zhHans: "这台 Mac 的可用内存不足。")
    /// `copy/model-setup/error-network`
    static let copyModelSetupErrorNetwork = LocalizedCopy(key: "copy/model-setup/error-network", en: "The model could not be downloaded. Check the network and retry.", zhHans: "无法下载模型。检查网络后重试。")
    /// `copy/model-setup/error-revision`
    static let copyModelSetupErrorRevision = LocalizedCopy(key: "copy/model-setup/error-revision", en: "The model revision does not match this app. Import a compatible package or update the app.", zhHans: "模型 revision 与此 App 不匹配。请导入兼容模型包或更新 App。")
    /// `copy/model-setup/error-verification`
    static let copyModelSetupErrorVerification = LocalizedCopy(key: "copy/model-setup/error-verification", en: "The model failed verification. Retry or import a valid package.", zhHans: "模型未通过校验。请重试或导入有效模型包。")
    /// `copy/model-setup/license`
    static let copyModelSetupLicense = LocalizedCopy(key: "copy/model-setup/license", en: "License: %@", zhHans: "许可证：%@")
    /// `copy/model-setup/network`
    static let copyModelSetupNetwork = LocalizedCopy(key: "copy/model-setup/network", en: "First download requires an internet connection. After setup, AI works offline.", zhHans: "首次下载需要网络连接。安装完成后，AI 功能可离线使用。")
    /// `copy/model-setup/recommended`
    static let copyModelSetupRecommended = LocalizedCopy(key: "copy/model-setup/recommended", en: "Recommended", zhHans: "推荐")
    /// `copy/model-setup/remove-body`
    static let copyModelSetupRemoveBody = LocalizedCopy(key: "copy/model-setup/remove-body", en: "AI features will stop until a model is installed again. Imported model files remain on this Mac.", zhHans: "AI 功能会停止，直到重新安装模型。导入的模型文件仍保留在这台 Mac。")
    /// `copy/model-setup/remove-title`
    static let copyModelSetupRemoveTitle = LocalizedCopy(key: "copy/model-setup/remove-title", en: "Remove this model?", zhHans: "移除此模型？")
    /// `copy/model-setup/select-model`
    static let copyModelSetupSelectModel = LocalizedCopy(key: "copy/model-setup/select-model", en: "Choose another model in Settings.", zhHans: "请在设置中选择其他模型。")
    /// `copy/model-setup/size`
    static let copyModelSetupSize = LocalizedCopy(key: "copy/model-setup/size", en: "Download size: %@", zhHans: "下载大小：%@")
    /// `copy/model-setup/state-downloading`
    static let copyModelSetupStateDownloading = LocalizedCopy(key: "copy/model-setup/state-downloading", en: "Downloading %d%%", zhHans: "正在下载 %d%%")
    /// `copy/model-setup/state-failed`
    static let copyModelSetupStateFailed = LocalizedCopy(key: "copy/model-setup/state-failed", en: "Model setup failed", zhHans: "模型安装失败")
    /// `copy/model-setup/state-not-installed`
    static let copyModelSetupStateNotInstalled = LocalizedCopy(key: "copy/model-setup/state-not-installed", en: "Not installed", zhHans: "未安装")
    /// `copy/model-setup/state-paused`
    static let copyModelSetupStatePaused = LocalizedCopy(key: "copy/model-setup/state-paused", en: "Download paused", zhHans: "下载已暂停")
    /// `copy/model-setup/state-ready`
    static let copyModelSetupStateReady = LocalizedCopy(key: "copy/model-setup/state-ready", en: "Ready for offline use", zhHans: "已可离线使用")
    /// `copy/model-setup/state-verifying`
    static let copyModelSetupStateVerifying = LocalizedCopy(key: "copy/model-setup/state-verifying", en: "Verifying downloaded files", zhHans: "正在校验下载文件")
    /// `copy/model-setup/summary`
    static let copyModelSetupSummary = LocalizedCopy(key: "copy/model-setup/summary", en: "Covio downloads the model after your confirmation. The model runs only on this Mac.", zhHans: "确认后 Covio 下载模型。模型只在这台 Mac 上运行。")
    /// `copy/model-setup/title`
    static let copyModelSetupTitle = LocalizedCopy(key: "copy/model-setup/title", en: "AI model required", zhHans: "需要 AI 模型")
    /// `copy/monitor/battery/remaining`
    static let copyMonitorBatteryRemaining = LocalizedCopy(key: "copy/monitor/battery/remaining", en: "Remaining", zhHans: "剩余")
    /// `copy/monitor/battery/source`
    static let copyMonitorBatterySource = LocalizedCopy(key: "copy/monitor/battery/source", en: "Source", zhHans: "电源")
    /// `copy/monitor/battery/state`
    static let copyMonitorBatteryState = LocalizedCopy(key: "copy/monitor/battery/state", en: "State", zhHans: "状态")
    /// `copy/monitor/cores`
    static let copyMonitorCores = LocalizedCopy(key: "copy/monitor/cores", en: "Cores", zhHans: "核心")
    /// `copy/monitor/disk/free`
    static let copyMonitorDiskFree = LocalizedCopy(key: "copy/monitor/disk/free", en: "Free", zhHans: "可用")
    /// `copy/monitor/disk/read`
    static let copyMonitorDiskRead = LocalizedCopy(key: "copy/monitor/disk/read", en: "Read", zhHans: "读取")
    /// `copy/monitor/disk/used`
    static let copyMonitorDiskUsed = LocalizedCopy(key: "copy/monitor/disk/used", en: "Used", zhHans: "已用")
    /// `copy/monitor/disk/write`
    static let copyMonitorDiskWrite = LocalizedCopy(key: "copy/monitor/disk/write", en: "Write", zhHans: "写入")
    /// `copy/monitor/display/action-settings`
    static let copyMonitorDisplayActionSettings = LocalizedCopy(key: "copy/monitor/display/action-settings", en: "Open Display Settings", zhHans: "打开显示器设置")
    /// `copy/monitor/display/action-sleep`
    static let copyMonitorDisplayActionSleep = LocalizedCopy(key: "copy/monitor/display/action-sleep", en: "Turn display off now", zhHans: "立即关闭显示器")
    /// `copy/monitor/display/actions-title`
    static let copyMonitorDisplayActionsTitle = LocalizedCopy(key: "copy/monitor/display/actions-title", en: "Display actions", zhHans: "屏幕操作")
    /// `copy/monitor/display/brightness`
    static let copyMonitorDisplayBrightness = LocalizedCopy(key: "copy/monitor/display/brightness", en: "Brightness", zhHans: "亮度")
    /// `copy/monitor/display/closed-lid-title`
    static let copyMonitorDisplayClosedLidTitle = LocalizedCopy(key: "copy/monitor/display/closed-lid-title", en: "Closed-lid policy", zhHans: "合盖策略")
    /// `copy/monitor/display/details-collapse`
    static let copyMonitorDisplayDetailsCollapse = LocalizedCopy(key: "copy/monitor/display/details-collapse", en: "Hide details and settings", zhHans: "收起详情与设置")
    /// `copy/monitor/display/details-expand`
    static let copyMonitorDisplayDetailsExpand = LocalizedCopy(key: "copy/monitor/display/details-expand", en: "Show details and settings", zhHans: "展开详情与设置")
    /// `copy/monitor/display/details-title`
    static let copyMonitorDisplayDetailsTitle = LocalizedCopy(key: "copy/monitor/display/details-title", en: "Display details", zhHans: "屏幕详情")
    /// `copy/monitor/display/guard-battery-floor`
    static let copyMonitorDisplayGuardBatteryFloor = LocalizedCopy(key: "copy/monitor/display/guard-battery-floor", en: "battery floor reached", zhHans: "电量已到下限")
    /// `copy/monitor/display/guard-battery-state-unknown`
    static let copyMonitorDisplayGuardBatteryStateUnknown = LocalizedCopy(key: "copy/monitor/display/guard-battery-state-unknown", en: "the battery state is unknown", zhHans: "电池状态未知")
    /// `copy/monitor/display/guard-closed-lid-disabled`
    static let copyMonitorDisplayGuardClosedLidDisabled = LocalizedCopy(key: "copy/monitor/display/guard-closed-lid-disabled", en: "closed-lid hold is off", zhHans: "合盖保持唤醒已关闭")
    /// `copy/monitor/display/guard-external-display`
    static let copyMonitorDisplayGuardExternalDisplay = LocalizedCopy(key: "copy/monitor/display/guard-external-display", en: "an external display is connected", zhHans: "已连接外接屏")
    /// `copy/monitor/display/guard-external-display-unknown`
    static let copyMonitorDisplayGuardExternalDisplayUnknown = LocalizedCopy(key: "copy/monitor/display/guard-external-display-unknown", en: "the external display state is unknown", zhHans: "外接屏状态未知")
    /// `copy/monitor/display/guard-low-power-mode`
    static let copyMonitorDisplayGuardLowPowerMode = LocalizedCopy(key: "copy/monitor/display/guard-low-power-mode", en: "Low Power Mode is on", zhHans: "低电量模式已开启")
    /// `copy/monitor/display/guard-paused`
    static let copyMonitorDisplayGuardPaused = LocalizedCopy(key: "copy/monitor/display/guard-paused", en: "Closed-lid hold is paused: %@", zhHans: "合盖保持唤醒已暂停：%@。")
    /// `copy/monitor/display/guard-sleep-setting-conflict`
    static let copyMonitorDisplayGuardSleepSettingConflict = LocalizedCopy(key: "copy/monitor/display/guard-sleep-setting-conflict", en: "another app controls system sleep", zhHans: "其他应用控制了系统睡眠")
    /// `copy/monitor/display/guard-sleep-state-unknown`
    static let copyMonitorDisplayGuardSleepStateUnknown = LocalizedCopy(key: "copy/monitor/display/guard-sleep-state-unknown", en: "the system sleep state is unknown", zhHans: "系统睡眠状态未知")
    /// `copy/monitor/display/guard-thermal`
    static let copyMonitorDisplayGuardThermal = LocalizedCopy(key: "copy/monitor/display/guard-thermal", en: "heat protection is active", zhHans: "温度保护已生效")
    /// `copy/monitor/display/guard-time-cap`
    static let copyMonitorDisplayGuardTimeCap = LocalizedCopy(key: "copy/monitor/display/guard-time-cap", en: "time limit reached", zhHans: "已达到时限")
    /// `copy/monitor/display/keep-awake`
    static let copyMonitorDisplayKeepAwake = LocalizedCopy(key: "copy/monitor/display/keep-awake", en: "Keep system running with lid closed", zhHans: "合盖时保持系统运行")
    /// `copy/monitor/display/keep-awake-hint`
    static let copyMonitorDisplayKeepAwakeHint = LocalizedCopy(key: "copy/monitor/display/keep-awake-hint", en: "Uses Covio system support and the Power safety guards.", zhHans: "使用 Covio 系统支持和 Power 安全护栏。")
    /// `copy/monitor/display/mode`
    static let copyMonitorDisplayMode = LocalizedCopy(key: "copy/monitor/display/mode", en: "Screen when lid closes", zhHans: "合盖时的屏幕")
    /// `copy/monitor/display/mode-black`
    static let copyMonitorDisplayModeBlack = LocalizedCopy(key: "copy/monitor/display/mode-black", en: "Black screen, display active", zhHans: "黑屏并保持显示链路")
    /// `copy/monitor/display/mode-off`
    static let copyMonitorDisplayModeOff = LocalizedCopy(key: "copy/monitor/display/mode-off", en: "Turn display off", zhHans: "关闭显示器")
    /// `copy/monitor/display/mode-system`
    static let copyMonitorDisplayModeSystem = LocalizedCopy(key: "copy/monitor/display/mode-system", en: "Follow system", zhHans: "跟随系统")
    /// `copy/monitor/display/power`
    static let copyMonitorDisplayPower = LocalizedCopy(key: "copy/monitor/display/power", en: "Display power", zhHans: "显示功耗")
    /// `copy/monitor/display/power-unavailable`
    static let copyMonitorDisplayPowerUnavailable = LocalizedCopy(key: "copy/monitor/display/power-unavailable", en: "No reliable display power reading.", zhHans: "没有可靠的显示功耗读数。")
    /// `copy/monitor/display/refresh-rate`
    static let copyMonitorDisplayRefreshRate = LocalizedCopy(key: "copy/monitor/display/refresh-rate", en: "Refresh rate", zhHans: "刷新率")
    /// `copy/monitor/display/resolution`
    static let copyMonitorDisplayResolution = LocalizedCopy(key: "copy/monitor/display/resolution", en: "Resolution", zhHans: "分辨率")
    /// `copy/monitor/display/safety-note`
    static let copyMonitorDisplaySafetyNote = LocalizedCopy(key: "copy/monitor/display/safety-note", en: "Battery and thermal safety settings stay in the Power card. This card shows when a guard pauses closed-lid hold.", zhHans: "电池与温度安全设置仍在电源卡片。护栏暂停合盖保持唤醒时，此处会显示原因。")
    /// `copy/monitor/display/session-start`
    static let copyMonitorDisplaySessionStart = LocalizedCopy(key: "copy/monitor/display/session-start", en: "Start closed-lid session", zhHans: "开始合盖会话")
    /// `copy/monitor/display/status-title`
    static let copyMonitorDisplayStatusTitle = LocalizedCopy(key: "copy/monitor/display/status-title", en: "Screen status", zhHans: "屏幕状态")
    /// `copy/monitor/display/status/active`
    static let copyMonitorDisplayStatusActive = LocalizedCopy(key: "copy/monitor/display/status/active", en: "Active", zhHans: "活跃")
    /// `copy/monitor/display/status/asleep`
    static let copyMonitorDisplayStatusAsleep = LocalizedCopy(key: "copy/monitor/display/status/asleep", en: "Asleep", zhHans: "已休眠")
    /// `copy/monitor/display/status/offline`
    static let copyMonitorDisplayStatusOffline = LocalizedCopy(key: "copy/monitor/display/status/offline", en: "Offline", zhHans: "离线")
    /// `copy/monitor/display/time-cap`
    static let copyMonitorDisplayTimeCap = LocalizedCopy(key: "copy/monitor/display/time-cap", en: "Closed-lid time cap", zhHans: "合盖时长上限")
    /// `copy/monitor/display/time-cap-hint`
    static let copyMonitorDisplayTimeCapHint = LocalizedCopy(key: "copy/monitor/display/time-cap-hint", en: "End closed-lid hold after this limit.", zhHans: "达到此时限后结束合盖保持唤醒。")
    /// `copy/monitor/fan/a11y-curve`
    static let copyMonitorFanA11yCurve = LocalizedCopy(key: "copy/monitor/fan/a11y-curve", en: "Fan temperature curve", zhHans: "风扇温控曲线")
    /// `copy/monitor/fan/a11y-open`
    static let copyMonitorFanA11yOpen = LocalizedCopy(key: "copy/monitor/fan/a11y-open", en: "Open fan controls", zhHans: "打开风扇控制")
    /// `copy/monitor/fan/a11y-status`
    static let copyMonitorFanA11yStatus = LocalizedCopy(key: "copy/monitor/fan/a11y-status", en: "Fan control status", zhHans: "风扇控制状态")
    /// `copy/monitor/fan/active-curve-adapter`
    static let copyMonitorFanActiveCurveAdapter = LocalizedCopy(key: "copy/monitor/fan/active-curve-adapter", en: "Active curve: plugged-in", zhHans: "生效曲线：插电")
    /// `copy/monitor/fan/active-curve-battery`
    static let copyMonitorFanActiveCurveBattery = LocalizedCopy(key: "copy/monitor/fan/active-curve-battery", en: "Active curve: battery", zhHans: "生效曲线：电池")
    /// `copy/monitor/fan/active-curve-mixed`
    static let copyMonitorFanActiveCurveMixed = LocalizedCopy(key: "copy/monitor/fan/active-curve-mixed", en: "Active curve: battery with plugged-in fallback", zhHans: "生效曲线：电池，部分风扇回退插电")
    /// `copy/monitor/fan/actual`
    static let copyMonitorFanActual = LocalizedCopy(key: "copy/monitor/fan/actual", en: "Actual", zhHans: "当前")
    /// `copy/monitor/fan/add-point`
    static let copyMonitorFanAddPoint = LocalizedCopy(key: "copy/monitor/fan/add-point", en: "Add point", zhHans: "添加控制点")
    /// `copy/monitor/fan/add-temperature-point`
    static let copyMonitorFanAddTemperaturePoint = LocalizedCopy(key: "copy/monitor/fan/add-temperature-point", en: "Add temperature point", zhHans: "添加温度点")
    /// `copy/monitor/fan/advanced`
    static let copyMonitorFanAdvanced = LocalizedCopy(key: "copy/monitor/fan/advanced", en: "Advanced settings", zhHans: "高级设置")
    /// `copy/monitor/fan/all-fans`
    static let copyMonitorFanAllFans = LocalizedCopy(key: "copy/monitor/fan/all-fans", en: "All fans", zhHans: "全部风扇")
    /// `copy/monitor/fan/applying`
    static let copyMonitorFanApplying = LocalizedCopy(key: "copy/monitor/fan/applying", en: "Applying", zhHans: "正在接管")
    /// `copy/monitor/fan/auto-curve`
    static let copyMonitorFanAutoCurve = LocalizedCopy(key: "copy/monitor/fan/auto-curve", en: "Covio curve", zhHans: "Covio 曲线")
    /// `copy/monitor/fan/automatic`
    static let copyMonitorFanAutomatic = LocalizedCopy(key: "copy/monitor/fan/automatic", en: "Automatic", zhHans: "自动")
    /// `copy/monitor/fan/balanced`
    static let copyMonitorFanBalanced = LocalizedCopy(key: "copy/monitor/fan/balanced", en: "Balanced", zhHans: "均衡")
    /// `copy/monitor/fan/battery-curve-fallback`
    static let copyMonitorFanBatteryCurveFallback = LocalizedCopy(key: "copy/monitor/fan/battery-curve-fallback", en: "Battery curve is empty. Covio uses the plugged-in curve.", zhHans: "电池曲线为空。Covio 使用插电曲线。")
    /// `copy/monitor/fan/clear-battery-curve`
    static let copyMonitorFanClearBatteryCurve = LocalizedCopy(key: "copy/monitor/fan/clear-battery-curve", en: "Clear battery curve", zhHans: "清空电池曲线")
    /// `copy/monitor/fan/control-point`
    static let copyMonitorFanControlPoint = LocalizedCopy(key: "copy/monitor/fan/control-point", en: "Control point %d", zhHans: "控制点 %d")
    /// `copy/monitor/fan/control-sensors`
    static let copyMonitorFanControlSensors = LocalizedCopy(key: "copy/monitor/fan/control-sensors", en: "Control sensors", zhHans: "控制传感器")
    /// `copy/monitor/fan/control-source`
    static let copyMonitorFanControlSource = LocalizedCopy(key: "copy/monitor/fan/control-source", en: "Control source: %@", zhHans: "控温来源：%@")
    /// `copy/monitor/fan/control-summary`
    static let copyMonitorFanControlSummary = LocalizedCopy(key: "copy/monitor/fan/control-summary", en: "Control sensors: %d · highest wins", zhHans: "控制传感器：%d 个取最高")
    /// `copy/monitor/fan/control-temperature`
    static let copyMonitorFanControlTemperature = LocalizedCopy(key: "copy/monitor/fan/control-temperature", en: "Control temperature", zhHans: "控制温度")
    /// `copy/monitor/fan/copy-adapter-curve`
    static let copyMonitorFanCopyAdapterCurve = LocalizedCopy(key: "copy/monitor/fan/copy-adapter-curve", en: "Copy plugged-in curve to battery", zhHans: "复制插电曲线到电池")
    /// `copy/monitor/fan/curve`
    static let copyMonitorFanCurve = LocalizedCopy(key: "copy/monitor/fan/curve", en: "Temperature curve", zhHans: "温控曲线")
    /// `copy/monitor/fan/curve-hint`
    static let copyMonitorFanCurveHint = LocalizedCopy(key: "copy/monitor/fan/curve-hint", en: "Drag points or use the sliders.", zhHans: "拖动控制点，或使用滑杆编辑。")
    /// `copy/monitor/fan/curve-source`
    static let copyMonitorFanCurveSource = LocalizedCopy(key: "copy/monitor/fan/curve-source", en: "Curve source", zhHans: "曲线电源")
    /// `copy/monitor/fan/curve-source-adapter`
    static let copyMonitorFanCurveSourceAdapter = LocalizedCopy(key: "copy/monitor/fan/curve-source-adapter", en: "Plugged-in curve", zhHans: "插电曲线")
    /// `copy/monitor/fan/curve-source-battery`
    static let copyMonitorFanCurveSourceBattery = LocalizedCopy(key: "copy/monitor/fan/curve-source-battery", en: "Battery curve", zhHans: "电池曲线")
    /// `copy/monitor/fan/delete-point`
    static let copyMonitorFanDeletePoint = LocalizedCopy(key: "copy/monitor/fan/delete-point", en: "Delete point", zhHans: "删除控制点")
    /// `copy/monitor/fan/details`
    static let copyMonitorFanDetails = LocalizedCopy(key: "copy/monitor/fan/details", en: "Fan control", zhHans: "风扇控制")
    /// `copy/monitor/fan/enable`
    static let copyMonitorFanEnable = LocalizedCopy(key: "copy/monitor/fan/enable", en: "Enable fan control", zhHans: "启用风扇控制")
    /// `copy/monitor/fan/full-caption`
    static let copyMonitorFanFullCaption = LocalizedCopy(key: "copy/monitor/fan/full-caption", en: "%d °C reaches full speed", zhHans: "%d °C 达到全速")
    /// `copy/monitor/fan/full-speed`
    static let copyMonitorFanFullSpeed = LocalizedCopy(key: "copy/monitor/fan/full-speed", en: "Full speed", zhHans: "全速")
    /// `copy/monitor/fan/full-speed-all`
    static let copyMonitorFanFullSpeedAll = LocalizedCopy(key: "copy/monitor/fan/full-speed-all", en: "All fans full speed", zhHans: "全部风扇全速")
    /// `copy/monitor/fan/full-speed-unit`
    static let copyMonitorFanFullSpeedUnit = LocalizedCopy(key: "copy/monitor/fan/full-speed-unit", en: "Set fan %d to full speed", zhHans: "风扇 %d 设为全速")
    /// `copy/monitor/fan/full-temperature`
    static let copyMonitorFanFullTemperature = LocalizedCopy(key: "copy/monitor/fan/full-temperature", en: "Full-speed temperature", zhHans: "全速温度")
    /// `copy/monitor/fan/helper-required`
    static let copyMonitorFanHelperRequired = LocalizedCopy(key: "copy/monitor/fan/helper-required", en: "Fan control requires Covio system support.", zhHans: "风扇控制需要 Covio 系统支持。")
    /// `copy/monitor/fan/helper-unavailable`
    static let copyMonitorFanHelperUnavailable = LocalizedCopy(key: "copy/monitor/fan/helper-unavailable", en: "Covio system support is unavailable. Fan readings remain available.", zhHans: "Covio 系统支持暂不可用。风扇读数仍可使用。")
    /// `copy/monitor/fan/install-helper`
    static let copyMonitorFanInstallHelper = LocalizedCopy(key: "copy/monitor/fan/install-helper", en: "Restore Covio support", zhHans: "恢复 Covio 支持")
    /// `copy/monitor/fan/legend-window`
    static let copyMonitorFanLegendWindow = LocalizedCopy(key: "copy/monitor/fan/legend-window", en: "Recent samples", zhHans: "近期采样")
    /// `copy/monitor/fan/manual`
    static let copyMonitorFanManual = LocalizedCopy(key: "copy/monitor/fan/manual", en: "Manual", zhHans: "手动")
    /// `copy/monitor/fan/manual-rpm`
    static let copyMonitorFanManualRpm = LocalizedCopy(key: "copy/monitor/fan/manual-rpm", en: "Manual RPM", zhHans: "手动转速")
    /// `copy/monitor/fan/owned`
    static let copyMonitorFanOwned = LocalizedCopy(key: "copy/monitor/fan/owned", en: "Covio control", zhHans: "Covio 已接管")
    /// `copy/monitor/fan/power-source-adapter`
    static let copyMonitorFanPowerSourceAdapter = LocalizedCopy(key: "copy/monitor/fan/power-source-adapter", en: "Current: power adapter", zhHans: "当前：插电")
    /// `copy/monitor/fan/power-source-battery`
    static let copyMonitorFanPowerSourceBattery = LocalizedCopy(key: "copy/monitor/fan/power-source-battery", en: "Current: battery", zhHans: "当前：电池")
    /// `copy/monitor/fan/power-source-unknown`
    static let copyMonitorFanPowerSourceUnknown = LocalizedCopy(key: "copy/monitor/fan/power-source-unknown", en: "Current: power source unknown", zhHans: "当前：电源未知")
    /// `copy/monitor/fan/quiet`
    static let copyMonitorFanQuiet = LocalizedCopy(key: "copy/monitor/fan/quiet", en: "Quiet", zhHans: "安静")
    /// `copy/monitor/fan/read-failed`
    static let copyMonitorFanReadFailed = LocalizedCopy(key: "copy/monitor/fan/read-failed", en: "Fan readings are unavailable.", zhHans: "风扇读数不可用。")
    /// `copy/monitor/fan/reset-curve`
    static let copyMonitorFanResetCurve = LocalizedCopy(key: "copy/monitor/fan/reset-curve", en: "Reset to line", zhHans: "恢复直线")
    /// `copy/monitor/fan/restore-auto-curve`
    static let copyMonitorFanRestoreAutoCurve = LocalizedCopy(key: "copy/monitor/fan/restore-auto-curve", en: "Restore auto curve", zhHans: "恢复自动曲线")
    /// `copy/monitor/fan/restore-system`
    static let copyMonitorFanRestoreSystem = LocalizedCopy(key: "copy/monitor/fan/restore-system", en: "Restore system control", zhHans: "恢复系统控制")
    /// `copy/monitor/fan/rpm`
    static let copyMonitorFanRpm = LocalizedCopy(key: "copy/monitor/fan/rpm", en: "RPM", zhHans: "转速")
    /// `copy/monitor/fan/sensor-filter`
    static let copyMonitorFanSensorFilter = LocalizedCopy(key: "copy/monitor/fan/sensor-filter", en: "Filter sensors", zhHans: "筛选传感器")
    /// `copy/monitor/fan/sensor-filter-empty`
    static let copyMonitorFanSensorFilterEmpty = LocalizedCopy(key: "copy/monitor/fan/sensor-filter-empty", en: "No matching sensors", zhHans: "没有匹配的传感器")
    /// `copy/monitor/fan/sensor-library-hint`
    static let copyMonitorFanSensorLibraryHint = LocalizedCopy(key: "copy/monitor/fan/sensor-library-hint", en: "64 sensors have names. Unknown keys show the raw key.", zhHans: "64 个传感器有名称。未知键显示原始键。")
    /// `copy/monitor/fan/source-battery`
    static let copyMonitorFanSourceBattery = LocalizedCopy(key: "copy/monitor/fan/source-battery", en: "Battery temperature", zhHans: "电池温度")
    /// `copy/monitor/fan/source-cpu`
    static let copyMonitorFanSourceCpu = LocalizedCopy(key: "copy/monitor/fan/source-cpu", en: "CPU temperature", zhHans: "CPU 温度")
    /// `copy/monitor/fan/source-fan-percent`
    static let copyMonitorFanSourceFanPercent = LocalizedCopy(key: "copy/monitor/fan/source-fan-percent", en: "Fan %d%%", zhHans: "风扇 %d%%")
    /// `copy/monitor/fan/source-fan-percent-label`
    static let copyMonitorFanSourceFanPercentLabel = LocalizedCopy(key: "copy/monitor/fan/source-fan-percent-label", en: "Fan percentage", zhHans: "风扇百分比")
    /// `copy/monitor/fan/source-gpu`
    static let copyMonitorFanSourceGpu = LocalizedCopy(key: "copy/monitor/fan/source-gpu", en: "GPU temperature", zhHans: "GPU 温度")
    /// `copy/monitor/fan/source-hint`
    static let copyMonitorFanSourceHint = LocalizedCopy(key: "copy/monitor/fan/source-hint", en: "Each source uses its hottest sensor. The highest fan request wins.", zhHans: "每个来源取最热传感器。风扇采用最高请求。")
    /// `copy/monitor/fan/source-request`
    static let copyMonitorFanSourceRequest = LocalizedCopy(key: "copy/monitor/fan/source-request", en: "%d%% request", zhHans: "%d%% 请求")
    /// `copy/monitor/fan/source-summary`
    static let copyMonitorFanSourceSummary = LocalizedCopy(key: "copy/monitor/fan/source-summary", en: "%d control sources · highest wins", zhHans: "%d 个控温来源取最高")
    /// `copy/monitor/fan/source-unavailable`
    static let copyMonitorFanSourceUnavailable = LocalizedCopy(key: "copy/monitor/fan/source-unavailable", en: "No sensor found", zhHans: "未检测到传感器")
    /// `copy/monitor/fan/start-caption`
    static let copyMonitorFanStartCaption = LocalizedCopy(key: "copy/monitor/fan/start-caption", en: "%d °C starts ramping", zhHans: "%d °C 开始升温")
    /// `copy/monitor/fan/start-temperature`
    static let copyMonitorFanStartTemperature = LocalizedCopy(key: "copy/monitor/fan/start-temperature", en: "Start temperature", zhHans: "起转温度")
    /// `copy/monitor/fan/sync-fans`
    static let copyMonitorFanSyncFans = LocalizedCopy(key: "copy/monitor/fan/sync-fans", en: "Synchronize fans", zhHans: "同步风扇控制")
    /// `copy/monitor/fan/sync-hint`
    static let copyMonitorFanSyncHint = LocalizedCopy(key: "copy/monitor/fan/sync-hint", en: "Apply changes by RPM percentage.", zhHans: "按转速百分比同步到全部风扇。")
    /// `copy/monitor/fan/system-auto`
    static let copyMonitorFanSystemAuto = LocalizedCopy(key: "copy/monitor/fan/system-auto", en: "System automatic", zhHans: "系统自动")
    /// `copy/monitor/fan/system-control`
    static let copyMonitorFanSystemControl = LocalizedCopy(key: "copy/monitor/fan/system-control", en: "System control", zhHans: "系统控制")
    /// `copy/monitor/fan/system-control-body`
    static let copyMonitorFanSystemControlBody = LocalizedCopy(key: "copy/monitor/fan/system-control-body", en: "Switching to Covio curve or manual speed lets Covio take control.", zhHans: "切换到 Covio 曲线或手动转速后，Covio 会接管。")
    /// `copy/monitor/fan/system-control-title`
    static let copyMonitorFanSystemControlTitle = LocalizedCopy(key: "copy/monitor/fan/system-control-title", en: "macOS is controlling the fans", zhHans: "macOS 正在控制风扇")
    /// `copy/monitor/fan/takeover-body`
    static let copyMonitorFanTakeoverBody = LocalizedCopy(key: "copy/monitor/fan/takeover-body", en: "Covio is controlling the fans. Writing fan speed changes hardware behavior. System control resumes after Covio quits, crashes, or the lease expires.", zhHans: "Covio 正在控制风扇。写入转速会改变硬件行为。退出、崩溃或租约过期后，系统会恢复控制。")
    /// `copy/monitor/fan/takeover-title`
    static let copyMonitorFanTakeoverTitle = LocalizedCopy(key: "copy/monitor/fan/takeover-title", en: "System fan control is paused", zhHans: "系统风扇控制已暂停")
    /// `copy/monitor/fan/target`
    static let copyMonitorFanTarget = LocalizedCopy(key: "copy/monitor/fan/target", en: "Target", zhHans: "目标")
    /// `copy/monitor/fan/temperature`
    static let copyMonitorFanTemperature = LocalizedCopy(key: "copy/monitor/fan/temperature", en: "Temperature", zhHans: "温度")
    /// `copy/monitor/fan/temperature-sources`
    static let copyMonitorFanTemperatureSources = LocalizedCopy(key: "copy/monitor/fan/temperature-sources", en: "Temperature sources", zhHans: "温度来源")
    /// `copy/monitor/fan/temperature-tick`
    static let copyMonitorFanTemperatureTick = LocalizedCopy(key: "copy/monitor/fan/temperature-tick", en: "1 °C per step", zhHans: "每格 1 °C")
    /// `copy/monitor/fan/title`
    static let copyMonitorFanTitle = LocalizedCopy(key: "copy/monitor/fan/title", en: "Fan", zhHans: "风扇")
    /// `copy/monitor/fan/turbo`
    static let copyMonitorFanTurbo = LocalizedCopy(key: "copy/monitor/fan/turbo", en: "Turbo", zhHans: "强力")
    /// `copy/monitor/fan/unavailable`
    static let copyMonitorFanUnavailable = LocalizedCopy(key: "copy/monitor/fan/unavailable", en: "Fan data unavailable", zhHans: "风扇数据不可用")
    /// `copy/monitor/fan/unit`
    static let copyMonitorFanUnit = LocalizedCopy(key: "copy/monitor/fan/unit", en: "Fan %d", zhHans: "风扇 %d")
    /// `copy/monitor/fan/warning`
    static let copyMonitorFanWarning = LocalizedCopy(key: "copy/monitor/fan/warning", en: "Writing fan speed changes hardware behavior.", zhHans: "写入风扇转速会改变硬件行为。")
    /// `copy/monitor/gpu/device`
    static let copyMonitorGpuDevice = LocalizedCopy(key: "copy/monitor/gpu/device", en: "Device", zhHans: "设备")
    /// `copy/monitor/gpu/memory`
    static let copyMonitorGpuMemory = LocalizedCopy(key: "copy/monitor/gpu/memory", en: "Memory in use", zhHans: "已用显存")
    /// `copy/monitor/history`
    static let copyMonitorHistory = LocalizedCopy(key: "copy/monitor/history", en: "60 samples", zhHans: "60 个采样")
    /// `copy/monitor/live`
    static let copyMonitorLive = LocalizedCopy(key: "copy/monitor/live", en: "Live", zhHans: "实时")
    /// `copy/monitor/load1`
    static let copyMonitorLoad1 = LocalizedCopy(key: "copy/monitor/load1", en: "Load 1m", zhHans: "1 分钟负载")
    /// `copy/monitor/memory-pressure/critical`
    static let copyMonitorMemoryPressureCritical = LocalizedCopy(key: "copy/monitor/memory-pressure/critical", en: "Critical", zhHans: "紧急")
    /// `copy/monitor/memory-pressure/normal`
    static let copyMonitorMemoryPressureNormal = LocalizedCopy(key: "copy/monitor/memory-pressure/normal", en: "Normal", zhHans: "正常")
    /// `copy/monitor/memory-pressure/warning`
    static let copyMonitorMemoryPressureWarning = LocalizedCopy(key: "copy/monitor/memory-pressure/warning", en: "Warning", zhHans: "警告")
    /// `copy/monitor/memory/pressure`
    static let copyMonitorMemoryPressure = LocalizedCopy(key: "copy/monitor/memory/pressure", en: "Pressure", zhHans: "压力")
    /// `copy/monitor/memory/swap`
    static let copyMonitorMemorySwap = LocalizedCopy(key: "copy/monitor/memory/swap", en: "Swap", zhHans: "交换")
    /// `copy/monitor/memory/total`
    static let copyMonitorMemoryTotal = LocalizedCopy(key: "copy/monitor/memory/total", en: "Total", zhHans: "总量")
    /// `copy/monitor/memory/used`
    static let copyMonitorMemoryUsed = LocalizedCopy(key: "copy/monitor/memory/used", en: "Used", zhHans: "已用")
    /// `copy/monitor/network/download`
    static let copyMonitorNetworkDownload = LocalizedCopy(key: "copy/monitor/network/download", en: "Download", zhHans: "下行")
    /// `copy/monitor/network/interface`
    static let copyMonitorNetworkInterface = LocalizedCopy(key: "copy/monitor/network/interface", en: "Interface", zhHans: "接口")
    /// `copy/monitor/network/upload`
    static let copyMonitorNetworkUpload = LocalizedCopy(key: "copy/monitor/network/upload", en: "Upload", zhHans: "上行")
    /// `copy/monitor/per-core`
    static let copyMonitorPerCore = LocalizedCopy(key: "copy/monitor/per-core", en: "Per core", zhHans: "每核")
    /// `copy/monitor/power/average/draw`
    static let copyMonitorPowerAverageDraw = LocalizedCopy(key: "copy/monitor/power/average/draw", en: "Average power", zhHans: "平均功耗")
    /// `copy/monitor/power/charge-limit/active-discharge`
    static let copyMonitorPowerChargeLimitActiveDischarge = LocalizedCopy(key: "copy/monitor/power/charge-limit/active-discharge", en: "Discharge above limit", zhHans: "高于上限时主动放电")
    /// `copy/monitor/power/charge-limit/active-discharge-warning`
    static let copyMonitorPowerChargeLimitActiveDischargeWarning = LocalizedCopy(key: "copy/monitor/power/charge-limit/active-discharge-warning", en: "Warning: this option increases battery cycles.", zhHans: "警告：此选项会增加电池循环。")
    /// `copy/monitor/power/charge-limit/apply`
    static let copyMonitorPowerChargeLimitApply = LocalizedCopy(key: "copy/monitor/power/charge-limit/apply", en: "Apply limit", zhHans: "应用上限")
    /// `copy/monitor/power/charge-limit/applying`
    static let copyMonitorPowerChargeLimitApplying = LocalizedCopy(key: "copy/monitor/power/charge-limit/applying", en: "Applying charge limit", zhHans: "正在应用充电上限")
    /// `copy/monitor/power/charge-limit/current-charge`
    static let copyMonitorPowerChargeLimitCurrentCharge = LocalizedCopy(key: "copy/monitor/power/charge-limit/current-charge", en: "Current charge", zhHans: "当前电量")
    /// `copy/monitor/power/charge-limit/current-target`
    static let copyMonitorPowerChargeLimitCurrentTarget = LocalizedCopy(key: "copy/monitor/power/charge-limit/current-target", en: "Current target", zhHans: "当前目标")
    /// `copy/monitor/power/charge-limit/enable`
    static let copyMonitorPowerChargeLimitEnable = LocalizedCopy(key: "copy/monitor/power/charge-limit/enable", en: "Enable limit", zhHans: "启用上限")
    /// `copy/monitor/power/charge-limit/failed`
    static let copyMonitorPowerChargeLimitFailed = LocalizedCopy(key: "copy/monitor/power/charge-limit/failed", en: "Charge limit did not apply", zhHans: "充电上限未生效")
    /// `copy/monitor/power/charge-limit/helper-required`
    static let copyMonitorPowerChargeLimitHelperRequired = LocalizedCopy(key: "copy/monitor/power/charge-limit/helper-required", en: "Charge limit requires Covio system support.", zhHans: "充电上限需要 Covio 系统支持。")
    /// `copy/monitor/power/charge-limit/restore`
    static let copyMonitorPowerChargeLimitRestore = LocalizedCopy(key: "copy/monitor/power/charge-limit/restore", en: "Restore system default", zhHans: "恢复系统默认")
    /// `copy/monitor/power/charge-limit/resume-at`
    static let copyMonitorPowerChargeLimitResumeAt = LocalizedCopy(key: "copy/monitor/power/charge-limit/resume-at", en: "Resume charging at", zhHans: "恢复充电阈值")
    /// `copy/monitor/power/charge-limit/state/above-limit`
    static let copyMonitorPowerChargeLimitStateAboveLimit = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/above-limit", en: "Above limit", zhHans: "高于上限")
    /// `copy/monitor/power/charge-limit/state/bypass`
    static let copyMonitorPowerChargeLimitStateBypass = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/bypass", en: "Bypass power", zhHans: "旁路供电")
    /// `copy/monitor/power/charge-limit/state/calibration`
    static let copyMonitorPowerChargeLimitStateCalibration = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/calibration", en: "Calibration in progress", zhHans: "校准中")
    /// `copy/monitor/power/charge-limit/state/conflict`
    static let copyMonitorPowerChargeLimitStateConflict = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/conflict", en: "System policy conflict", zhHans: "系统策略冲突")
    /// `copy/monitor/power/charge-limit/state/discharging`
    static let copyMonitorPowerChargeLimitStateDischarging = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/discharging", en: "Discharging to limit", zhHans: "正在放电至上限")
    /// `copy/monitor/power/charge-limit/state/error`
    static let copyMonitorPowerChargeLimitStateError = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/error", en: "Charge limit error", zhHans: "充电上限错误")
    /// `copy/monitor/power/charge-limit/state/holding`
    static let copyMonitorPowerChargeLimitStateHolding = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/holding", en: "Charging paused", zhHans: "已暂停充电")
    /// `copy/monitor/power/charge-limit/state/protection`
    static let copyMonitorPowerChargeLimitStateProtection = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/protection", en: "System protection", zhHans: "系统保护中")
    /// `copy/monitor/power/charge-limit/state/sailing`
    static let copyMonitorPowerChargeLimitStateSailing = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/sailing", en: "Holding current level", zhHans: "保持当前电量")
    /// `copy/monitor/power/charge-limit/state/stopping-discharge`
    static let copyMonitorPowerChargeLimitStateStoppingDischarge = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/stopping-discharge", en: "Stopping discharge", zhHans: "正在停止放电")
    /// `copy/monitor/power/charge-limit/state/system`
    static let copyMonitorPowerChargeLimitStateSystem = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/system", en: "macOS controls the charge limit", zhHans: "macOS 控制充电上限")
    /// `copy/monitor/power/charge-limit/state/unplugged`
    static let copyMonitorPowerChargeLimitStateUnplugged = LocalizedCopy(key: "copy/monitor/power/charge-limit/state/unplugged", en: "Connect the power adapter", zhHans: "请接通电源适配器")
    /// `copy/monitor/power/charge-limit/title`
    static let copyMonitorPowerChargeLimitTitle = LocalizedCopy(key: "copy/monitor/power/charge-limit/title", en: "Charge limit", zhHans: "充电上限")
    /// `copy/monitor/power/charge-limit/unsupported`
    static let copyMonitorPowerChargeLimitUnsupported = LocalizedCopy(key: "copy/monitor/power/charge-limit/unsupported", en: "Charge limit is unavailable", zhHans: "当前设备不支持充电上限")
    /// `copy/monitor/power/charge/health`
    static let copyMonitorPowerChargeHealth = LocalizedCopy(key: "copy/monitor/power/charge/health", en: "Battery health", zhHans: "电池健康度")
    /// `copy/monitor/power/charge/power`
    static let copyMonitorPowerChargePower = LocalizedCopy(key: "copy/monitor/power/charge/power", en: "Charging power", zhHans: "充电功率")
    /// `copy/monitor/power/charge/time-to-full`
    static let copyMonitorPowerChargeTimeToFull = LocalizedCopy(key: "copy/monitor/power/charge/time-to-full", en: "Time to full", zhHans: "预计充满")
    /// `copy/monitor/power/charge/title`
    static let copyMonitorPowerChargeTitle = LocalizedCopy(key: "copy/monitor/power/charge/title", en: "Charging information", zhHans: "充电信息")
    /// `copy/monitor/power/critical-battery`
    static let copyMonitorPowerCriticalBattery = LocalizedCopy(key: "copy/monitor/power/critical-battery", en: "Battery critical", zhHans: "电量极低")
    /// `copy/monitor/power/details/close`
    static let copyMonitorPowerDetailsClose = LocalizedCopy(key: "copy/monitor/power/details/close", en: "Close power details", zhHans: "关闭电源详情")
    /// `copy/monitor/power/details/collapse`
    static let copyMonitorPowerDetailsCollapse = LocalizedCopy(key: "copy/monitor/power/details/collapse", en: "Hide details", zhHans: "收起详情")
    /// `copy/monitor/power/details/collapse-settings`
    static let copyMonitorPowerDetailsCollapseSettings = LocalizedCopy(key: "copy/monitor/power/details/collapse-settings", en: "Hide details and settings", zhHans: "收起详情与设置")
    /// `copy/monitor/power/details/expand`
    static let copyMonitorPowerDetailsExpand = LocalizedCopy(key: "copy/monitor/power/details/expand", en: "Show details", zhHans: "展开详情")
    /// `copy/monitor/power/details/expand-settings`
    static let copyMonitorPowerDetailsExpandSettings = LocalizedCopy(key: "copy/monitor/power/details/expand-settings", en: "Show details and settings", zhHans: "展开详情与设置")
    /// `copy/monitor/power/details/title`
    static let copyMonitorPowerDetailsTitle = LocalizedCopy(key: "copy/monitor/power/details/title", en: "Power details", zhHans: "电源详情")
    /// `copy/monitor/power/draw`
    static let copyMonitorPowerDraw = LocalizedCopy(key: "copy/monitor/power/draw", en: "Power draw", zhHans: "功耗")
    /// `copy/monitor/power/estimate/basis`
    static let copyMonitorPowerEstimateBasis = LocalizedCopy(key: "copy/monitor/power/estimate/basis", en: "Based on recent average power", zhHans: "按近期平均功耗估算")
    /// `copy/monitor/power/events/connected`
    static let copyMonitorPowerEventsConnected = LocalizedCopy(key: "copy/monitor/power/events/connected", en: "Adapter connected", zhHans: "已接通电源")
    /// `copy/monitor/power/events/disconnected`
    static let copyMonitorPowerEventsDisconnected = LocalizedCopy(key: "copy/monitor/power/events/disconnected", en: "Adapter disconnected", zhHans: "已断开电源")
    /// `copy/monitor/power/events/fully-charged`
    static let copyMonitorPowerEventsFullyCharged = LocalizedCopy(key: "copy/monitor/power/events/fully-charged", en: "Fully charged", zhHans: "已充满")
    /// `copy/monitor/power/events/title`
    static let copyMonitorPowerEventsTitle = LocalizedCopy(key: "copy/monitor/power/events/title", en: "Power events · 24 h", zhHans: "供电事件 · 近 24 小时")
    /// `copy/monitor/power/high-temperature`
    static let copyMonitorPowerHighTemperature = LocalizedCopy(key: "copy/monitor/power/high-temperature", en: "Battery hot", zhHans: "电池温度高")
    /// `copy/monitor/power/history/accumulating`
    static let copyMonitorPowerHistoryAccumulating = LocalizedCopy(key: "copy/monitor/power/history/accumulating", en: "Collecting data", zhHans: "数据积累中")
    /// `copy/monitor/power/history/title`
    static let copyMonitorPowerHistoryTitle = LocalizedCopy(key: "copy/monitor/power/history/title", en: "Power and temperature · 30 min", zhHans: "功耗与温度 · 近 30 分钟")
    /// `copy/monitor/power/low-battery`
    static let copyMonitorPowerLowBattery = LocalizedCopy(key: "copy/monitor/power/low-battery", en: "Low battery", zhHans: "电量低")
    /// `copy/monitor/power/no-battery`
    static let copyMonitorPowerNoBattery = LocalizedCopy(key: "copy/monitor/power/no-battery", en: "No battery", zhHans: "无电池设备")
    /// `copy/monitor/power/no-data`
    static let copyMonitorPowerNoData = LocalizedCopy(key: "copy/monitor/power/no-data", en: "No data", zhHans: "暂无数据")
    /// `copy/monitor/power/read-failed`
    static let copyMonitorPowerReadFailed = LocalizedCopy(key: "copy/monitor/power/read-failed", en: "Some readings unavailable", zhHans: "部分读数不可用")
    /// `copy/monitor/power/remaining`
    static let copyMonitorPowerRemaining = LocalizedCopy(key: "copy/monitor/power/remaining", en: "Estimated time", zhHans: "预计可使用")
    /// `copy/monitor/power/state/battery`
    static let copyMonitorPowerStateBattery = LocalizedCopy(key: "copy/monitor/power/state/battery", en: "On battery", zhHans: "电池供电")
    /// `copy/monitor/power/state/connected`
    static let copyMonitorPowerStateConnected = LocalizedCopy(key: "copy/monitor/power/state/connected", en: "Power connected", zhHans: "已接通电源")
    /// `copy/monitor/power/temperature`
    static let copyMonitorPowerTemperature = LocalizedCopy(key: "copy/monitor/power/temperature", en: "Temperature", zhHans: "温度")
    /// `copy/monitor/power/top-apps`
    static let copyMonitorPowerTopApps = LocalizedCopy(key: "copy/monitor/power/top-apps", en: "Top energy · 1 hour", zhHans: "耗电 Top3 · 近 1 小时")
    /// `copy/monitor/power/trend/title`
    static let copyMonitorPowerTrendTitle = LocalizedCopy(key: "copy/monitor/power/trend/title", en: "Recent trend", zhHans: "近期趋势")
    /// `copy/monitor/power/trend/window`
    static let copyMonitorPowerTrendWindow = LocalizedCopy(key: "copy/monitor/power/trend/window", en: "Last 1 min", zhHans: "近 1 分钟")
    /// `copy/monitor/report/cancel`
    static let copyMonitorReportCancel = LocalizedCopy(key: "copy/monitor/report/cancel", en: "Cancel", zhHans: "取消")
    /// `copy/monitor/report/chart/cpu-gpu`
    static let copyMonitorReportChartCpuGpu = LocalizedCopy(key: "copy/monitor/report/chart/cpu-gpu", en: "CPU and GPU", zhHans: "CPU 与 GPU")
    /// `copy/monitor/report/chart/memory`
    static let copyMonitorReportChartMemory = LocalizedCopy(key: "copy/monitor/report/chart/memory", en: "Memory pressure by usage", zhHans: "内存使用率")
    /// `copy/monitor/report/chart/network`
    static let copyMonitorReportChartNetwork = LocalizedCopy(key: "copy/monitor/report/chart/network", en: "Network throughput", zhHans: "网络吞吐")
    /// `copy/monitor/report/clear`
    static let copyMonitorReportClear = LocalizedCopy(key: "copy/monitor/report/clear", en: "Clear history", zhHans: "清除历史")
    /// `copy/monitor/report/close`
    static let copyMonitorReportClose = LocalizedCopy(key: "copy/monitor/report/close", en: "Close", zhHans: "关闭")
    /// `copy/monitor/report/coverage/observed`
    static let copyMonitorReportCoverageObserved = LocalizedCopy(key: "copy/monitor/report/coverage/observed", en: "Observed", zhHans: "已记录")
    /// `copy/monitor/report/coverage/samples`
    static let copyMonitorReportCoverageSamples = LocalizedCopy(key: "copy/monitor/report/coverage/samples", en: "Samples", zhHans: "样本")
    /// `copy/monitor/report/coverage/sleep`
    static let copyMonitorReportCoverageSleep = LocalizedCopy(key: "copy/monitor/report/coverage/sleep", en: "Sleep", zhHans: "睡眠")
    /// `copy/monitor/report/coverage/title`
    static let copyMonitorReportCoverageTitle = LocalizedCopy(key: "copy/monitor/report/coverage/title", en: "Data coverage", zhHans: "数据覆盖")
    /// `copy/monitor/report/coverage/unknown`
    static let copyMonitorReportCoverageUnknown = LocalizedCopy(key: "copy/monitor/report/coverage/unknown", en: "Unknown gaps", zhHans: "未知缺口")
    /// `copy/monitor/report/delete-confirm`
    static let copyMonitorReportDeleteConfirm = LocalizedCopy(key: "copy/monitor/report/delete-confirm", en: "Clear history", zhHans: "清除历史")
    /// `copy/monitor/report/delete-message`
    static let copyMonitorReportDeleteMessage = LocalizedCopy(key: "copy/monitor/report/delete-message", en: "This removes all locally stored samples and cannot be undone.", zhHans: "这会删除全部本机样本，且不能撤销。")
    /// `copy/monitor/report/delete-title`
    static let copyMonitorReportDeleteTitle = LocalizedCopy(key: "copy/monitor/report/delete-title", en: "Clear performance history?", zhHans: "清除性能历史？")
    /// `copy/monitor/report/empty`
    static let copyMonitorReportEmpty = LocalizedCopy(key: "copy/monitor/report/empty", en: "No samples in this range.", zhHans: "这个范围内没有样本。")
    /// `copy/monitor/report/error`
    static let copyMonitorReportError = LocalizedCopy(key: "copy/monitor/report/error", en: "The report could not be built.", zhHans: "无法生成报告。")
    /// `copy/monitor/report/events/title`
    static let copyMonitorReportEventsTitle = LocalizedCopy(key: "copy/monitor/report/events/title", en: "Events", zhHans: "事件")
    /// `copy/monitor/report/export`
    static let copyMonitorReportExport = LocalizedCopy(key: "copy/monitor/report/export", en: "Export HTML", zhHans: "导出 HTML")
    /// `copy/monitor/report/export-error`
    static let copyMonitorReportExportError = LocalizedCopy(key: "copy/monitor/report/export-error", en: "The report could not be exported.", zhHans: "无法导出报告。")
    /// `copy/monitor/report/export-success`
    static let copyMonitorReportExportSuccess = LocalizedCopy(key: "copy/monitor/report/export-success", en: "Report exported.", zhHans: "报告已导出。")
    /// `copy/monitor/report/gaps/title`
    static let copyMonitorReportGapsTitle = LocalizedCopy(key: "copy/monitor/report/gaps/title", en: "Collection gaps", zhHans: "采集缺口")
    /// `copy/monitor/report/generated`
    static let copyMonitorReportGenerated = LocalizedCopy(key: "copy/monitor/report/generated", en: "Generated", zhHans: "生成时间")
    /// `copy/monitor/report/loading`
    static let copyMonitorReportLoading = LocalizedCopy(key: "copy/monitor/report/loading", en: "Building report…", zhHans: "正在生成报告…")
    /// `copy/monitor/report/method`
    static let copyMonitorReportMethod = LocalizedCopy(key: "copy/monitor/report/method", en: "Collected locally. No data was uploaded.", zhHans: "本机采集。没有上传数据。")
    /// `copy/monitor/report/no-data-hint`
    static let copyMonitorReportNoDataHint = LocalizedCopy(key: "copy/monitor/report/no-data-hint", en: "Keep Covio running to collect history.", zhHans: "保持 Covio 运行，才能积累历史。")
    /// `copy/monitor/report/open`
    static let copyMonitorReportOpen = LocalizedCopy(key: "copy/monitor/report/open", en: "Report", zhHans: "历史报告")
    /// `copy/monitor/report/partial`
    static let copyMonitorReportPartial = LocalizedCopy(key: "copy/monitor/report/partial", en: "Coverage is incomplete. The report marks missing time.", zhHans: "覆盖不完整。报告会标出缺失时间。")
    /// `copy/monitor/report/peaks/metric`
    static let copyMonitorReportPeaksMetric = LocalizedCopy(key: "copy/monitor/report/peaks/metric", en: "Metric", zhHans: "指标")
    /// `copy/monitor/report/peaks/title`
    static let copyMonitorReportPeaksTitle = LocalizedCopy(key: "copy/monitor/report/peaks/title", en: "Peaks", zhHans: "峰值")
    /// `copy/monitor/report/peaks/value`
    static let copyMonitorReportPeaksValue = LocalizedCopy(key: "copy/monitor/report/peaks/value", en: "Peak", zhHans: "峰值")
    /// `copy/monitor/report/range/end`
    static let copyMonitorReportRangeEnd = LocalizedCopy(key: "copy/monitor/report/range/end", en: "End", zhHans: "结束")
    /// `copy/monitor/report/range/last-10-days`
    static let copyMonitorReportRangeLast10Days = LocalizedCopy(key: "copy/monitor/report/range/last-10-days", en: "Last 10 days", zhHans: "最近 10 天")
    /// `copy/monitor/report/range/limit`
    static let copyMonitorReportRangeLimit = LocalizedCopy(key: "copy/monitor/report/range/limit", en: "Ranges are limited to 14 days.", zhHans: "时间范围最多 14 天。")
    /// `copy/monitor/report/range/start`
    static let copyMonitorReportRangeStart = LocalizedCopy(key: "copy/monitor/report/range/start", en: "Start", zhHans: "开始")
    /// `copy/monitor/report/summary`
    static let copyMonitorReportSummary = LocalizedCopy(key: "copy/monitor/report/summary", en: "Export a local report for the selected time range.", zhHans: "导出所选时间段的本机报告。")
    /// `copy/monitor/report/system/chip`
    static let copyMonitorReportSystemChip = LocalizedCopy(key: "copy/monitor/report/system/chip", en: "Chip", zhHans: "芯片")
    /// `copy/monitor/report/system/disk`
    static let copyMonitorReportSystemDisk = LocalizedCopy(key: "copy/monitor/report/system/disk", en: "Disk", zhHans: "磁盘")
    /// `copy/monitor/report/system/memory`
    static let copyMonitorReportSystemMemory = LocalizedCopy(key: "copy/monitor/report/system/memory", en: "Memory", zhHans: "内存")
    /// `copy/monitor/report/system/model`
    static let copyMonitorReportSystemModel = LocalizedCopy(key: "copy/monitor/report/system/model", en: "Model", zhHans: "机型")
    /// `copy/monitor/report/system/os`
    static let copyMonitorReportSystemOs = LocalizedCopy(key: "copy/monitor/report/system/os", en: "macOS", zhHans: "macOS")
    /// `copy/monitor/report/system/start`
    static let copyMonitorReportSystemStart = LocalizedCopy(key: "copy/monitor/report/system/start", en: "Start", zhHans: "开始")
    /// `copy/monitor/report/system/title`
    static let copyMonitorReportSystemTitle = LocalizedCopy(key: "copy/monitor/report/system/title", en: "System", zhHans: "系统")
    /// `copy/monitor/report/table/confidence`
    static let copyMonitorReportTableConfidence = LocalizedCopy(key: "copy/monitor/report/table/confidence", en: "Confidence", zhHans: "置信度")
    /// `copy/monitor/report/table/count`
    static let copyMonitorReportTableCount = LocalizedCopy(key: "copy/monitor/report/table/count", en: "Count", zhHans: "次数")
    /// `copy/monitor/report/table/cpu`
    static let copyMonitorReportTableCpu = LocalizedCopy(key: "copy/monitor/report/table/cpu", en: "CPU", zhHans: "CPU")
    /// `copy/monitor/report/table/data`
    static let copyMonitorReportTableData = LocalizedCopy(key: "copy/monitor/report/table/data", en: "Data table", zhHans: "数据表")
    /// `copy/monitor/report/table/duration`
    static let copyMonitorReportTableDuration = LocalizedCopy(key: "copy/monitor/report/table/duration", en: "Duration", zhHans: "持续")
    /// `copy/monitor/report/table/event`
    static let copyMonitorReportTableEvent = LocalizedCopy(key: "copy/monitor/report/table/event", en: "Event", zhHans: "事件")
    /// `copy/monitor/report/table/gpu`
    static let copyMonitorReportTableGpu = LocalizedCopy(key: "copy/monitor/report/table/gpu", en: "GPU", zhHans: "GPU")
    /// `copy/monitor/report/table/kind`
    static let copyMonitorReportTableKind = LocalizedCopy(key: "copy/monitor/report/table/kind", en: "Kind", zhHans: "类型")
    /// `copy/monitor/report/table/memory`
    static let copyMonitorReportTableMemory = LocalizedCopy(key: "copy/monitor/report/table/memory", en: "Memory", zhHans: "内存")
    /// `copy/monitor/report/table/network-down`
    static let copyMonitorReportTableNetworkDown = LocalizedCopy(key: "copy/monitor/report/table/network-down", en: "Download", zhHans: "下行")
    /// `copy/monitor/report/table/network-up`
    static let copyMonitorReportTableNetworkUp = LocalizedCopy(key: "copy/monitor/report/table/network-up", en: "Upload", zhHans: "上行")
    /// `copy/monitor/report/table/reason`
    static let copyMonitorReportTableReason = LocalizedCopy(key: "copy/monitor/report/table/reason", en: "Reason", zhHans: "原因")
    /// `copy/monitor/report/table/source`
    static let copyMonitorReportTableSource = LocalizedCopy(key: "copy/monitor/report/table/source", en: "Source", zhHans: "来源")
    /// `copy/monitor/report/table/time`
    static let copyMonitorReportTableTime = LocalizedCopy(key: "copy/monitor/report/table/time", en: "Time", zhHans: "时间")
    /// `copy/monitor/report/thresholds/title`
    static let copyMonitorReportThresholdsTitle = LocalizedCopy(key: "copy/monitor/report/thresholds/title", en: "Notable periods", zhHans: "异常时段")
    /// `copy/monitor/report/title`
    static let copyMonitorReportTitle = LocalizedCopy(key: "copy/monitor/report/title", en: "Performance history", zhHans: "性能历史报告")
    /// `copy/monitor/report/unavailable/title`
    static let copyMonitorReportUnavailableTitle = LocalizedCopy(key: "copy/monitor/report/unavailable/title", en: "Unavailable metrics", zhHans: "不可得指标")
    /// `copy/monitor/sampling/fast`
    static let copyMonitorSamplingFast = LocalizedCopy(key: "copy/monitor/sampling/fast", en: "1s", zhHans: "1 秒")
    /// `copy/monitor/sampling/slow`
    static let copyMonitorSamplingSlow = LocalizedCopy(key: "copy/monitor/sampling/slow", en: "5s", zhHans: "5 秒")
    /// `copy/monitor/state/ac-power`
    static let copyMonitorStateAcPower = LocalizedCopy(key: "copy/monitor/state/ac-power", en: "Power adapter", zhHans: "电源适配器")
    /// `copy/monitor/state/charged`
    static let copyMonitorStateCharged = LocalizedCopy(key: "copy/monitor/state/charged", en: "Charged", zhHans: "已充满")
    /// `copy/monitor/state/charging`
    static let copyMonitorStateCharging = LocalizedCopy(key: "copy/monitor/state/charging", en: "Charging", zhHans: "充电中")
    /// `copy/monitor/state/on-battery`
    static let copyMonitorStateOnBattery = LocalizedCopy(key: "copy/monitor/state/on-battery", en: "On battery", zhHans: "使用电池")
    /// `copy/monitor/state/unknown`
    static let copyMonitorStateUnknown = LocalizedCopy(key: "copy/monitor/state/unknown", en: "Unknown", zhHans: "未知")
    /// `copy/monitor/thermal`
    static let copyMonitorThermal = LocalizedCopy(key: "copy/monitor/thermal", en: "Thermal", zhHans: "热状态")
    /// `copy/monitor/thermal/critical`
    static let copyMonitorThermalCritical = LocalizedCopy(key: "copy/monitor/thermal/critical", en: "Critical", zhHans: "过热")
    /// `copy/monitor/thermal/fair`
    static let copyMonitorThermalFair = LocalizedCopy(key: "copy/monitor/thermal/fair", en: "Fair", zhHans: "较热")
    /// `copy/monitor/thermal/nominal`
    static let copyMonitorThermalNominal = LocalizedCopy(key: "copy/monitor/thermal/nominal", en: "Normal", zhHans: "正常")
    /// `copy/monitor/thermal/serious`
    static let copyMonitorThermalSerious = LocalizedCopy(key: "copy/monitor/thermal/serious", en: "Serious", zhHans: "过热")
    /// `copy/monitor/title/battery`
    static let copyMonitorTitleBattery = LocalizedCopy(key: "copy/monitor/title/battery", en: "Power", zhHans: "电源")
    /// `copy/monitor/title/cpu`
    static let copyMonitorTitleCpu = LocalizedCopy(key: "copy/monitor/title/cpu", en: "CPU", zhHans: "CPU")
    /// `copy/monitor/title/disk`
    static let copyMonitorTitleDisk = LocalizedCopy(key: "copy/monitor/title/disk", en: "Disk", zhHans: "磁盘")
    /// `copy/monitor/title/display`
    static let copyMonitorTitleDisplay = LocalizedCopy(key: "copy/monitor/title/display", en: "Screen", zhHans: "屏幕")
    /// `copy/monitor/title/gpu`
    static let copyMonitorTitleGpu = LocalizedCopy(key: "copy/monitor/title/gpu", en: "GPU", zhHans: "GPU")
    /// `copy/monitor/title/memory`
    static let copyMonitorTitleMemory = LocalizedCopy(key: "copy/monitor/title/memory", en: "Memory", zhHans: "内存")
    /// `copy/monitor/title/network`
    static let copyMonitorTitleNetwork = LocalizedCopy(key: "copy/monitor/title/network", en: "Network", zhHans: "网络")
    /// `copy/monitor/unavailable`
    static let copyMonitorUnavailable = LocalizedCopy(key: "copy/monitor/unavailable", en: "Unavailable", zhHans: "不可用")
    /// `copy/monitor/uptime`
    static let copyMonitorUptime = LocalizedCopy(key: "copy/monitor/uptime", en: "Uptime", zhHans: "运行时间")
    /// `copy/monitor/usage`
    static let copyMonitorUsage = LocalizedCopy(key: "copy/monitor/usage", en: "Usage", zhHans: "使用率")
    /// `copy/nav/battery`
    static let copyNavBattery = LocalizedCopy(key: "copy/nav/battery", en: "Battery", zhHans: "电池")
    /// `copy/nav/clipboard`
    static let copyNavClipboard = LocalizedCopy(key: "copy/nav/clipboard", en: "Clipboard", zhHans: "剪贴板")
    /// `copy/nav/general`
    static let copyNavGeneral = LocalizedCopy(key: "copy/nav/general", en: "General", zhHans: "通用")
    /// `copy/nav/idle`
    static let copyNavIdle = LocalizedCopy(key: "copy/nav/idle", en: "Idle", zhHans: "闲置")
    /// `copy/nav/overview`
    static let copyNavOverview = LocalizedCopy(key: "copy/nav/overview", en: "Overview", zhHans: "概览")
    /// `copy/nav/quit`
    static let copyNavQuit = LocalizedCopy(key: "copy/nav/quit", en: "Quit Covio", zhHans: "退出 Covio")
    /// `copy/nav/rail-label`
    static let copyNavRailLabel = LocalizedCopy(key: "copy/nav/rail-label", en: "Hub tab bar", zhHans: "Hub 页签栏")
    /// `copy/nav/search-empty`
    static let copyNavSearchEmpty = LocalizedCopy(key: "copy/nav/search-empty", en: "No matching settings", zhHans: "没有匹配的设置")
    /// `copy/nav/search-placeholder`
    static let copyNavSearchPlaceholder = LocalizedCopy(key: "copy/nav/search-placeholder", en: "Search workspaces and settings", zhHans: "搜索工作区与设置")
    /// `copy/nav/search-results`
    static let copyNavSearchResults = LocalizedCopy(key: "copy/nav/search-results", en: "Search results", zhHans: "搜索结果")
    /// `copy/nav/status-paused`
    static let copyNavStatusPaused = LocalizedCopy(key: "copy/nav/status-paused", en: "Paused", zhHans: "已暂停")
    /// `copy/nav/status-running`
    static let copyNavStatusRunning = LocalizedCopy(key: "copy/nav/status-running", en: "Running", zhHans: "运行中")
    /// `copy/nav/top-shelf`
    static let copyNavTopShelf = LocalizedCopy(key: "copy/nav/top-shelf", en: "Top Shelf", zhHans: "顶部挂帘")
    /// `copy/notch-hub/layout/collapsed-presence`
    static let copyNotchHubLayoutCollapsedPresence = LocalizedCopy(key: "copy/notch-hub/layout/collapsed-presence", en: "A · Collapsed Presence", zhHans: "A · 收起存在感")
    /// `copy/notch-hub/layout/drag-target`
    static let copyNotchHubLayoutDragTarget = LocalizedCopy(key: "copy/notch-hub/layout/drag-target", en: "C · Drag Target", zhHans: "C · 拖放目标")
    /// `copy/notch-hub/layout/expanded-output`
    static let copyNotchHubLayoutExpandedOutput = LocalizedCopy(key: "copy/notch-hub/layout/expanded-output", en: "B · Expanded Output", zhHans: "B · 展开输出")
    /// `copy/notch-hub/state/active`
    static let copyNotchHubStateActive = LocalizedCopy(key: "copy/notch-hub/state/active", en: "Active", zhHans: "活动")
    /// `copy/notch-hub/state/collapsed`
    static let copyNotchHubStateCollapsed = LocalizedCopy(key: "copy/notch-hub/state/collapsed", en: "Collapsed", zhHans: "收起")
    /// `copy/notch-hub/state/drag-target`
    static let copyNotchHubStateDragTarget = LocalizedCopy(key: "copy/notch-hub/state/drag-target", en: "Drag Target", zhHans: "拖放目标")
    /// `copy/notch-hub/state/error`
    static let copyNotchHubStateError = LocalizedCopy(key: "copy/notch-hub/state/error", en: "Error", zhHans: "错误")
    /// `copy/notch-hub/state/exit`
    static let copyNotchHubStateExit = LocalizedCopy(key: "copy/notch-hub/state/exit", en: "Exit", zhHans: "退出")
    /// `copy/notch-hub/state/expanded`
    static let copyNotchHubStateExpanded = LocalizedCopy(key: "copy/notch-hub/state/expanded", en: "Expanded Output", zhHans: "展开输出")
    /// `copy/notch-hub/state/hidden`
    static let copyNotchHubStateHidden = LocalizedCopy(key: "copy/notch-hub/state/hidden", en: "Hidden", zhHans: "隐藏")
    /// `copy/notch-hub/state/hover`
    static let copyNotchHubStateHover = LocalizedCopy(key: "copy/notch-hub/state/hover", en: "Hover", zhHans: "悬停")
    /// `copy/notch-hub/state/open`
    static let copyNotchHubStateOpen = LocalizedCopy(key: "copy/notch-hub/state/open", en: "Open", zhHans: "打开")
    /// `copy/notch-hub/state/processing`
    static let copyNotchHubStateProcessing = LocalizedCopy(key: "copy/notch-hub/state/processing", en: "Processing", zhHans: "处理中")
    /// `copy/notch-hub/state/ready`
    static let copyNotchHubStateReady = LocalizedCopy(key: "copy/notch-hub/state/ready", en: "Ready", zhHans: "就绪")
    /// `copy/overview/action/display-off`
    static let copyOverviewActionDisplayOff = LocalizedCopy(key: "copy/overview/action/display-off", en: "Turn Display Off", zhHans: "关闭显示器")
    /// `copy/overview/action/sleep-now`
    static let copyOverviewActionSleepNow = LocalizedCopy(key: "copy/overview/action/sleep-now", en: "Sleep Now", zhHans: "立即睡眠")
    /// `copy/overview/helper/install`
    static let copyOverviewHelperInstall = LocalizedCopy(key: "copy/overview/helper/install", en: "Restore Covio support", zhHans: "恢复 Covio 支持")
    /// `copy/overview/helper/installed`
    static let copyOverviewHelperInstalled = LocalizedCopy(key: "copy/overview/helper/installed", en: "Covio support is ready", zhHans: "Covio 支持已就绪")
    /// `copy/overview/helper/missing`
    static let copyOverviewHelperMissing = LocalizedCopy(key: "copy/overview/helper/missing", en: "Covio support is unavailable", zhHans: "Covio 支持不可用")
    /// `copy/overview/helper/version`
    static let copyOverviewHelperVersion = LocalizedCopy(key: "copy/overview/helper/version", en: "Version", zhHans: "版本")
    /// `copy/overview/rules/master`
    static let copyOverviewRulesMaster = LocalizedCopy(key: "copy/overview/rules/master", en: "Sleep protection", zhHans: "睡眠保护")
    /// `copy/page/battery/state/disabled`
    static let copyPageBatteryStateDisabled = LocalizedCopy(key: "copy/page/battery/state/disabled", en: "04 · Battery - Disabled", zhHans: "04 · Battery - 不可用")
    /// `copy/page/battery/state/empty`
    static let copyPageBatteryStateEmpty = LocalizedCopy(key: "copy/page/battery/state/empty", en: "04 · Battery - Empty", zhHans: "04 · Battery - 无项目")
    /// `copy/page/battery/state/error`
    static let copyPageBatteryStateError = LocalizedCopy(key: "copy/page/battery/state/error", en: "04 · Battery - Error", zhHans: "04 · Battery - 操作失败")
    /// `copy/page/battery/state/loading`
    static let copyPageBatteryStateLoading = LocalizedCopy(key: "copy/page/battery/state/loading", en: "04 · Battery - Loading", zhHans: "04 · Battery - 正在加载")
    /// `copy/page/battery/state/normal`
    static let copyPageBatteryStateNormal = LocalizedCopy(key: "copy/page/battery/state/normal", en: "04 · Battery - Normal", zhHans: "04 · Battery - 就绪")
    /// `copy/page/battery/state/success`
    static let copyPageBatteryStateSuccess = LocalizedCopy(key: "copy/page/battery/state/success", en: "04 · Battery - Success", zhHans: "04 · Battery - 已完成")
    /// `copy/page/battery/state/warning`
    static let copyPageBatteryStateWarning = LocalizedCopy(key: "copy/page/battery/state/warning", en: "04 · Battery - Warning", zhHans: "04 · Battery - 需要检查")
    /// `copy/page/battery/summary`
    static let copyPageBatterySummary = LocalizedCopy(key: "copy/page/battery/summary", en: "Sleep when battery power reaches a threshold.", zhHans: "电池电量达到阈值时睡眠。")
    /// `copy/page/battery/title`
    static let copyPageBatteryTitle = LocalizedCopy(key: "copy/page/battery/title", en: "Battery", zhHans: "电池")
    /// `copy/page/clipboard/summary`
    static let copyPageClipboardSummary = LocalizedCopy(key: "copy/page/clipboard/summary", en: "Manage clipboard history, the paste stack, and shortcuts.", zhHans: "管理剪贴板历史、粘贴栈和快捷键。")
    /// `copy/page/clipboard/title`
    static let copyPageClipboardTitle = LocalizedCopy(key: "copy/page/clipboard/title", en: "Clipboard", zhHans: "剪贴板")
    /// `copy/page/general/state/disabled`
    static let copyPageGeneralStateDisabled = LocalizedCopy(key: "copy/page/general/state/disabled", en: "08 · General - Disabled", zhHans: "08 · General - 不可用")
    /// `copy/page/general/state/empty`
    static let copyPageGeneralStateEmpty = LocalizedCopy(key: "copy/page/general/state/empty", en: "08 · General - Empty", zhHans: "08 · General - 无项目")
    /// `copy/page/general/state/error`
    static let copyPageGeneralStateError = LocalizedCopy(key: "copy/page/general/state/error", en: "08 · General - Error", zhHans: "08 · General - 操作失败")
    /// `copy/page/general/state/loading`
    static let copyPageGeneralStateLoading = LocalizedCopy(key: "copy/page/general/state/loading", en: "08 · General - Loading", zhHans: "08 · General - 正在加载")
    /// `copy/page/general/state/normal`
    static let copyPageGeneralStateNormal = LocalizedCopy(key: "copy/page/general/state/normal", en: "08 · General - Normal", zhHans: "08 · General - 就绪")
    /// `copy/page/general/state/success`
    static let copyPageGeneralStateSuccess = LocalizedCopy(key: "copy/page/general/state/success", en: "08 · General - Success", zhHans: "08 · General - 已完成")
    /// `copy/page/general/state/warning`
    static let copyPageGeneralStateWarning = LocalizedCopy(key: "copy/page/general/state/warning", en: "08 · General - Warning", zhHans: "08 · General - 需要检查")
    /// `copy/page/general/summary`
    static let copyPageGeneralSummary = LocalizedCopy(key: "copy/page/general/summary", en: "Control startup, updates, language, and power mode.", zhHans: "控制启动、更新、语言和电源模式。")
    /// `copy/page/general/title`
    static let copyPageGeneralTitle = LocalizedCopy(key: "copy/page/general/title", en: "General", zhHans: "通用")
    /// `copy/page/idle/state/disabled`
    static let copyPageIdleStateDisabled = LocalizedCopy(key: "copy/page/idle/state/disabled", en: "06 · Idle - Disabled", zhHans: "06 · Idle - 不可用")
    /// `copy/page/idle/state/empty`
    static let copyPageIdleStateEmpty = LocalizedCopy(key: "copy/page/idle/state/empty", en: "06 · Idle - Empty", zhHans: "06 · Idle - 无项目")
    /// `copy/page/idle/state/error`
    static let copyPageIdleStateError = LocalizedCopy(key: "copy/page/idle/state/error", en: "06 · Idle - Error", zhHans: "06 · Idle - 操作失败")
    /// `copy/page/idle/state/loading`
    static let copyPageIdleStateLoading = LocalizedCopy(key: "copy/page/idle/state/loading", en: "06 · Idle - Loading", zhHans: "06 · Idle - 正在加载")
    /// `copy/page/idle/state/normal`
    static let copyPageIdleStateNormal = LocalizedCopy(key: "copy/page/idle/state/normal", en: "06 · Idle - Normal", zhHans: "06 · Idle - 就绪")
    /// `copy/page/idle/state/success`
    static let copyPageIdleStateSuccess = LocalizedCopy(key: "copy/page/idle/state/success", en: "06 · Idle - Success", zhHans: "06 · Idle - 已完成")
    /// `copy/page/idle/state/warning`
    static let copyPageIdleStateWarning = LocalizedCopy(key: "copy/page/idle/state/warning", en: "06 · Idle - Warning", zhHans: "06 · Idle - 需要检查")
    /// `copy/page/idle/summary`
    static let copyPageIdleSummary = LocalizedCopy(key: "copy/page/idle/summary", en: "Control sleep behavior while the Mac is idle.", zhHans: "控制 Mac 闲置时的睡眠行为。")
    /// `copy/page/idle/title`
    static let copyPageIdleTitle = LocalizedCopy(key: "copy/page/idle/title", en: "Idle", zhHans: "闲置")
    /// `copy/page/overview/state/disabled`
    static let copyPageOverviewStateDisabled = LocalizedCopy(key: "copy/page/overview/state/disabled", en: "03 · Overview - Disabled", zhHans: "03 · Overview - 不可用")
    /// `copy/page/overview/state/empty`
    static let copyPageOverviewStateEmpty = LocalizedCopy(key: "copy/page/overview/state/empty", en: "03 · Overview - Empty", zhHans: "03 · Overview - 无项目")
    /// `copy/page/overview/state/error`
    static let copyPageOverviewStateError = LocalizedCopy(key: "copy/page/overview/state/error", en: "03 · Overview - Error", zhHans: "03 · Overview - 操作失败")
    /// `copy/page/overview/state/loading`
    static let copyPageOverviewStateLoading = LocalizedCopy(key: "copy/page/overview/state/loading", en: "03 · Overview - Loading", zhHans: "03 · Overview - 正在加载")
    /// `copy/page/overview/state/normal`
    static let copyPageOverviewStateNormal = LocalizedCopy(key: "copy/page/overview/state/normal", en: "03 · Overview - Normal", zhHans: "03 · Overview - 就绪")
    /// `copy/page/overview/state/success`
    static let copyPageOverviewStateSuccess = LocalizedCopy(key: "copy/page/overview/state/success", en: "03 · Overview - Success", zhHans: "03 · Overview - 已完成")
    /// `copy/page/overview/state/warning`
    static let copyPageOverviewStateWarning = LocalizedCopy(key: "copy/page/overview/state/warning", en: "03 · Overview - Warning", zhHans: "03 · Overview - 需要检查")
    /// `copy/page/overview/summary`
    static let copyPageOverviewSummary = LocalizedCopy(key: "copy/page/overview/summary", en: "Manage sleep rules and Covio status.", zhHans: "管理睡眠规则和 Covio 状态。")
    /// `copy/page/overview/title`
    static let copyPageOverviewTitle = LocalizedCopy(key: "copy/page/overview/title", en: "Overview", zhHans: "概览")
    /// `copy/page/top-shelf-settings/state/disabled`
    static let copyPageTopShelfSettingsStateDisabled = LocalizedCopy(key: "copy/page/top-shelf-settings/state/disabled", en: "07 · Top Shelf Settings - Disabled", zhHans: "07 · Top Shelf Settings - 不可用")
    /// `copy/page/top-shelf-settings/state/empty`
    static let copyPageTopShelfSettingsStateEmpty = LocalizedCopy(key: "copy/page/top-shelf-settings/state/empty", en: "07 · Top Shelf Settings - Empty", zhHans: "07 · Top Shelf Settings - 无项目")
    /// `copy/page/top-shelf-settings/state/error`
    static let copyPageTopShelfSettingsStateError = LocalizedCopy(key: "copy/page/top-shelf-settings/state/error", en: "07 · Top Shelf Settings - Error", zhHans: "07 · Top Shelf Settings - 操作失败")
    /// `copy/page/top-shelf-settings/state/loading`
    static let copyPageTopShelfSettingsStateLoading = LocalizedCopy(key: "copy/page/top-shelf-settings/state/loading", en: "07 · Top Shelf Settings - Loading", zhHans: "07 · Top Shelf Settings - 正在加载")
    /// `copy/page/top-shelf-settings/state/normal`
    static let copyPageTopShelfSettingsStateNormal = LocalizedCopy(key: "copy/page/top-shelf-settings/state/normal", en: "07 · Top Shelf Settings - Normal", zhHans: "07 · Top Shelf Settings - 就绪")
    /// `copy/page/top-shelf-settings/state/success`
    static let copyPageTopShelfSettingsStateSuccess = LocalizedCopy(key: "copy/page/top-shelf-settings/state/success", en: "07 · Top Shelf Settings - Success", zhHans: "07 · Top Shelf Settings - 已完成")
    /// `copy/page/top-shelf-settings/state/warning`
    static let copyPageTopShelfSettingsStateWarning = LocalizedCopy(key: "copy/page/top-shelf-settings/state/warning", en: "07 · Top Shelf Settings - Warning", zhHans: "07 · Top Shelf Settings - 需要检查")
    /// `copy/page/top-shelf-settings/summary`
    static let copyPageTopShelfSettingsSummary = LocalizedCopy(key: "copy/page/top-shelf-settings/summary", en: "Control screenshot takeover and the top shelf.", zhHans: "控制截图接管和顶部挂帘。")
    /// `copy/page/top-shelf-settings/title`
    static let copyPageTopShelfSettingsTitle = LocalizedCopy(key: "copy/page/top-shelf-settings/title", en: "Top Shelf", zhHans: "顶部挂帘")
    /// `copy/power/alert/external-conflict`
    static let copyPowerAlertExternalConflict = LocalizedCopy(key: "copy/power/alert/external-conflict", en: "Another app changed the sleep setting. Covio will not clear it.", zhHans: "其他应用修改了睡眠设置。Covio 不会清除该设置。")
    /// `copy/power/alert/helper-missing`
    static let copyPowerAlertHelperMissing = LocalizedCopy(key: "copy/power/alert/helper-missing", en: "Covio system support is unavailable. Reinstall Covio before using closed-lid hold.", zhHans: "Covio 系统支持暂不可用。重新安装 Covio 后可使用合盖保持唤醒。")
    /// `copy/power/alert/thermal`
    static let copyPowerAlertThermal = LocalizedCopy(key: "copy/power/alert/thermal", en: "The heat guard will release every hold.", zhHans: "温度保护会释放全部保持唤醒。")
    /// `copy/power/closed-lid-pointer`
    static let copyPowerClosedLidPointer = LocalizedCopy(key: "copy/power/closed-lid-pointer", en: "Closed-lid sleep and display behavior are managed in the Screen card.", zhHans: "合盖睡眠与显示行为由屏幕卡片管理。")
    /// `copy/power/description/master`
    static let copyPowerDescriptionMaster = LocalizedCopy(key: "copy/power/description/master", en: "Manage open-lid sleep and safety guards. Turning this off releases every rule and session.", zhHans: "管理开盖睡眠和安全护栏。关闭后会释放全部规则和会话。")
    /// `copy/power/error/lid-not-applied`
    static let copyPowerErrorLidNotApplied = LocalizedCopy(key: "copy/power/error/lid-not-applied", en: "Covio did not apply closed-lid protection. Check system support and try again.", zhHans: "Covio 没有应用合盖保护。检查系统支持后重试。")
    /// `copy/power/error/master-off`
    static let copyPowerErrorMasterOff = LocalizedCopy(key: "copy/power/error/master-off", en: "Turn on Sleep Protection before starting a session.", zhHans: "启动会话前，请先打开“睡眠保护”。")
    /// `copy/power/history/adapter-connected`
    static let copyPowerHistoryAdapterConnected = LocalizedCopy(key: "copy/power/history/adapter-connected", en: "Power adapter connected", zhHans: "已接通电源")
    /// `copy/power/history/adapter-disconnected`
    static let copyPowerHistoryAdapterDisconnected = LocalizedCopy(key: "copy/power/history/adapter-disconnected", en: "Power adapter disconnected", zhHans: "已断开电源")
    /// `copy/power/history/external-conflict-cleared`
    static let copyPowerHistoryExternalConflictCleared = LocalizedCopy(key: "copy/power/history/external-conflict-cleared", en: "External sleep setting recovered", zhHans: "外部睡眠设置已恢复")
    /// `copy/power/history/guard-released`
    static let copyPowerHistoryGuardReleased = LocalizedCopy(key: "copy/power/history/guard-released", en: "Heat guard released the hold", zhHans: "温度保护已释放保持唤醒")
    /// `copy/power/history/hint`
    static let copyPowerHistoryHint = LocalizedCopy(key: "copy/power/history/hint", en: "Shows power and sleep events from the last 24 hours.", zhHans: "显示最近 24 小时的电源和睡眠事件。")
    /// `copy/power/history/hold-started`
    static let copyPowerHistoryHoldStarted = LocalizedCopy(key: "copy/power/history/hold-started", en: "Closed-lid hold started", zhHans: "合盖保持唤醒已开始")
    /// `copy/power/history/no-events`
    static let copyPowerHistoryNoEvents = LocalizedCopy(key: "copy/power/history/no-events", en: "No recent events", zhHans: "最近没有事件")
    /// `copy/power/history/slept`
    static let copyPowerHistorySlept = LocalizedCopy(key: "copy/power/history/slept", en: "Mac slept", zhHans: "Mac 已睡眠")
    /// `copy/power/history/window`
    static let copyPowerHistoryWindow = LocalizedCopy(key: "copy/power/history/window", en: "Last 24 hours", zhHans: "最近 24 小时")
    /// `copy/power/history/woke`
    static let copyPowerHistoryWoke = LocalizedCopy(key: "copy/power/history/woke", en: "Mac woke", zhHans: "Mac 已唤醒")
    /// `copy/power/overview/note`
    static let copyPowerOverviewNote = LocalizedCopy(key: "copy/power/overview/note", en: "The existing live metrics stay in Overview.", zhHans: "现有实时指标保留在概览中。")
    /// `copy/power/popover/details`
    static let copyPowerPopoverDetails = LocalizedCopy(key: "copy/power/popover/details", en: "Details", zhHans: "详情")
    /// `copy/power/popover/power`
    static let copyPowerPopoverPower = LocalizedCopy(key: "copy/power/popover/power", en: "Power", zhHans: "电源")
    /// `copy/power/popover/title`
    static let copyPowerPopoverTitle = LocalizedCopy(key: "copy/power/popover/title", en: "Power settings", zhHans: "电源设置")
    /// `copy/power/rules/adapter`
    static let copyPowerRulesAdapter = LocalizedCopy(key: "copy/power/rules/adapter", en: "Keep awake on adapter while open", zhHans: "开盖且接通电源时保持唤醒")
    /// `copy/power/rules/battery`
    static let copyPowerRulesBattery = LocalizedCopy(key: "copy/power/rules/battery", en: "Keep awake on battery while open", zhHans: "开盖且使用电池时保持唤醒")
    /// `copy/power/rules/battery-floor`
    static let copyPowerRulesBatteryFloor = LocalizedCopy(key: "copy/power/rules/battery-floor", en: "Battery floor", zhHans: "电池下限")
    /// `copy/power/rules/battery-floor-hint`
    static let copyPowerRulesBatteryFloorHint = LocalizedCopy(key: "copy/power/rules/battery-floor-hint", en: "Release protection when the battery reaches this level.", zhHans: "电量降到该值时释放保护。")
    /// `copy/power/rules/battery-hint`
    static let copyPowerRulesBatteryHint = LocalizedCopy(key: "copy/power/rules/battery-hint", en: "This can drain the battery faster while the lid is open.", zhHans: "开盖时会加快电池耗电。")
    /// `copy/power/rules/closed-lid-zero-brightness`
    static let copyPowerRulesClosedLidZeroBrightness = LocalizedCopy(key: "copy/power/rules/closed-lid-zero-brightness", en: "Experimental closed-lid black screen", zhHans: "实验性合盖黑屏")
    /// `copy/power/rules/closed-lid-zero-brightness-failed`
    static let copyPowerRulesClosedLidZeroBrightnessFailed = LocalizedCopy(key: "copy/power/rules/closed-lid-zero-brightness-failed", en: "Zero brightness failed. Covio restored the original brightness when possible and fell back to the public screen-off path.", zhHans: "零亮度设置失败。Covio 已尽力恢复原亮度，并回退到公开关屏路径。")
    /// `copy/power/rules/closed-lid-zero-brightness-hint`
    static let copyPowerRulesClosedLidZeroBrightnessHint = LocalizedCopy(key: "copy/power/rules/closed-lid-zero-brightness-hint", en: "On by default. While closed-lid hold is active, the panel is set to 0.0. The framebuffer and display pipeline stay active and may support Computer Use or remote capture, but this is not guaranteed. The private API can break after a macOS update.", zhHans: "默认开启。合盖保持唤醒时，面板亮度设为 0.0；framebuffer 和显示链路保持在线，可能支持 Computer Use 或远程截图，但不保证可用。私有接口可能随 macOS 更新失效。")
    /// `copy/power/rules/closed-lid-zero-brightness-unavailable`
    static let copyPowerRulesClosedLidZeroBrightnessUnavailable = LocalizedCopy(key: "copy/power/rules/closed-lid-zero-brightness-unavailable", en: "Unavailable on this macOS version or hardware.", zhHans: "当前 macOS 版本或硬件不支持。")
    /// `copy/power/rules/external-display`
    static let copyPowerRulesExternalDisplay = LocalizedCopy(key: "copy/power/rules/external-display", en: "Pause lid hold with external display", zhHans: "有外接屏时暂停合盖保持唤醒")
    /// `copy/power/rules/external-display-hint`
    static let copyPowerRulesExternalDisplayHint = LocalizedCopy(key: "copy/power/rules/external-display-hint", en: "Pause a closed-lid session when an external display is connected.", zhHans: "连接外接屏时暂停合盖会话。")
    /// `copy/power/rules/heat-guard`
    static let copyPowerRulesHeatGuard = LocalizedCopy(key: "copy/power/rules/heat-guard", en: "Heat guard", zhHans: "温度保护")
    /// `copy/power/rules/heat-guard-hint`
    static let copyPowerRulesHeatGuardHint = LocalizedCopy(key: "copy/power/rules/heat-guard-hint", en: "Release protection when macOS reports serious heat.", zhHans: "macOS 报告高温时释放保护。")
    /// `copy/power/rules/lid`
    static let copyPowerRulesLid = LocalizedCopy(key: "copy/power/rules/lid", en: "Allow closed-lid hold", zhHans: "允许合盖保持唤醒")
    /// `copy/power/rules/lid-hint`
    static let copyPowerRulesLidHint = LocalizedCopy(key: "copy/power/rules/lid-hint", en: "Requires Covio system support and a successful safety check.", zhHans: "需要 Covio 系统支持和安全检查通过。")
    /// `copy/power/rules/low-power-hint`
    static let copyPowerRulesLowPowerHint = LocalizedCopy(key: "copy/power/rules/low-power-hint", en: "Release protection when Low Power Mode is on.", zhHans: "启用低电量模式时释放保护。")
    /// `copy/power/rules/off`
    static let copyPowerRulesOff = LocalizedCopy(key: "copy/power/rules/off", en: "Off", zhHans: "关闭")
    /// `copy/power/rules/on`
    static let copyPowerRulesOn = LocalizedCopy(key: "copy/power/rules/on", en: "On", zhHans: "开启")
    /// `copy/power/section/advanced`
    static let copyPowerSectionAdvanced = LocalizedCopy(key: "copy/power/section/advanced", en: "Advanced safety", zhHans: "高级安全")
    /// `copy/power/section/automatic`
    static let copyPowerSectionAutomatic = LocalizedCopy(key: "copy/power/section/automatic", en: "Automatically keep awake", zhHans: "自动保持唤醒")
    /// `copy/power/section/history`
    static let copyPowerSectionHistory = LocalizedCopy(key: "copy/power/section/history", en: "Recent activity", zhHans: "最近活动")
    /// `copy/power/section/rules`
    static let copyPowerSectionRules = LocalizedCopy(key: "copy/power/section/rules", en: "Safety and automation", zhHans: "安全与自动规则")
    /// `copy/power/section/safety`
    static let copyPowerSectionSafety = LocalizedCopy(key: "copy/power/section/safety", en: "Safety guards", zhHans: "安全护栏")
    /// `copy/power/section/session`
    static let copyPowerSectionSession = LocalizedCopy(key: "copy/power/section/session", en: "Open-lid keep awake", zhHans: "开盖时保持唤醒")
    /// `copy/power/section/status`
    static let copyPowerSectionStatus = LocalizedCopy(key: "copy/power/section/status", en: "Current power", zhHans: "当前供电")
    /// `copy/power/session/active`
    static let copyPowerSessionActive = LocalizedCopy(key: "copy/power/session/active", en: "Active", zhHans: "运行中")
    /// `copy/power/session/display`
    static let copyPowerSessionDisplay = LocalizedCopy(key: "copy/power/session/display", en: "System + display", zhHans: "系统与屏幕")
    /// `copy/power/session/duration`
    static let copyPowerSessionDuration = LocalizedCopy(key: "copy/power/session/duration", en: "Duration", zhHans: "时长")
    /// `copy/power/session/duration-15m`
    static let copyPowerSessionDuration15m = LocalizedCopy(key: "copy/power/session/duration-15m", en: "15 min", zhHans: "15 分钟")
    /// `copy/power/session/duration-1h`
    static let copyPowerSessionDuration1h = LocalizedCopy(key: "copy/power/session/duration-1h", en: "1 hour", zhHans: "1 小时")
    /// `copy/power/session/duration-2h`
    static let copyPowerSessionDuration2h = LocalizedCopy(key: "copy/power/session/duration-2h", en: "2 hours", zhHans: "2 小时")
    /// `copy/power/session/duration-4h`
    static let copyPowerSessionDuration4h = LocalizedCopy(key: "copy/power/session/duration-4h", en: "4 hours", zhHans: "4 小时")
    /// `copy/power/session/duration-open`
    static let copyPowerSessionDurationOpen = LocalizedCopy(key: "copy/power/session/duration-open", en: "Until off", zhHans: "直到关闭")
    /// `copy/power/session/end`
    static let copyPowerSessionEnd = LocalizedCopy(key: "copy/power/session/end", en: "End", zhHans: "结束")
    /// `copy/power/session/expires`
    static let copyPowerSessionExpires = LocalizedCopy(key: "copy/power/session/expires", en: "Ends in", zhHans: "剩余")
    /// `copy/power/session/inactive`
    static let copyPowerSessionInactive = LocalizedCopy(key: "copy/power/session/inactive", en: "Off", zhHans: "关闭")
    /// `copy/power/session/lid`
    static let copyPowerSessionLid = LocalizedCopy(key: "copy/power/session/lid", en: "Closed lid", zhHans: "合盖运行")
    /// `copy/power/session/lid-display-off`
    static let copyPowerSessionLidDisplayOff = LocalizedCopy(key: "copy/power/session/lid-display-off", en: "Closed lid, screen off", zhHans: "合盖关屏")
    /// `copy/power/session/lid-display-off-hint`
    static let copyPowerSessionLidDisplayOffHint = LocalizedCopy(key: "copy/power/session/lid-display-off-hint", en: "The Mac stays awake. Covio turns the display off after the lid closes.", zhHans: "Mac 保持运行，Covio 在合盖后关闭屏幕。")
    /// `copy/power/session/lid-zero-brightness`
    static let copyPowerSessionLidZeroBrightness = LocalizedCopy(key: "copy/power/session/lid-zero-brightness", en: "Closed lid, black screen (display active)", zhHans: "合盖黑屏（显示链路保持）")
    /// `copy/power/session/mode`
    static let copyPowerSessionMode = LocalizedCopy(key: "copy/power/session/mode", en: "Session type", zhHans: "会话类型")
    /// `copy/power/session/none`
    static let copyPowerSessionNone = LocalizedCopy(key: "copy/power/session/none", en: "No open-lid keep-awake session is active.", zhHans: "当前没有开盖保持唤醒会话。")
    /// `copy/power/session/reason-adapter`
    static let copyPowerSessionReasonAdapter = LocalizedCopy(key: "copy/power/session/reason-adapter", en: "Power adapter connected", zhHans: "已接通电源")
    /// `copy/power/session/reason-lid`
    static let copyPowerSessionReasonLid = LocalizedCopy(key: "copy/power/session/reason-lid", en: "Lid held only while safety checks pass", zhHans: "安全条件通过时才保持合盖运行")
    /// `copy/power/session/start`
    static let copyPowerSessionStart = LocalizedCopy(key: "copy/power/session/start", en: "Start", zhHans: "开始")
    /// `copy/power/session/start-hint`
    static let copyPowerSessionStartHint = LocalizedCopy(key: "copy/power/session/start-hint", en: "Keep the system or display awake while the lid is open.", zhHans: "开盖时按需保持系统或屏幕唤醒。")
    /// `copy/power/session/system`
    static let copyPowerSessionSystem = LocalizedCopy(key: "copy/power/session/system", en: "System", zhHans: "仅系统")
    /// `copy/power/status/adapter`
    static let copyPowerStatusAdapter = LocalizedCopy(key: "copy/power/status/adapter", en: "Adapter", zhHans: "适配器")
    /// `copy/power/status/connected`
    static let copyPowerStatusConnected = LocalizedCopy(key: "copy/power/status/connected", en: "Connected", zhHans: "已连接")
    /// `copy/power/status/external-display`
    static let copyPowerStatusExternalDisplay = LocalizedCopy(key: "copy/power/status/external-display", en: "External display", zhHans: "外接屏")
    /// `copy/power/status/guard-missing`
    static let copyPowerStatusGuardMissing = LocalizedCopy(key: "copy/power/status/guard-missing", en: "Safety guard unavailable", zhHans: "安全护栏不可用")
    /// `copy/power/status/guard-ready`
    static let copyPowerStatusGuardReady = LocalizedCopy(key: "copy/power/status/guard-ready", en: "Safety guard ready", zhHans: "安全护栏就绪")
    /// `copy/power/status/helper`
    static let copyPowerStatusHelper = LocalizedCopy(key: "copy/power/status/helper", en: "Covio support", zhHans: "Covio 支持")
    /// `copy/power/status/helper-hint`
    static let copyPowerStatusHelperHint = LocalizedCopy(key: "copy/power/status/helper-hint", en: "Covio applies privileged system changes.", zhHans: "Covio 负责应用特权系统更改。")
    /// `copy/power/status/low-power-mode`
    static let copyPowerStatusLowPowerMode = LocalizedCopy(key: "copy/power/status/low-power-mode", en: "Low Power Mode", zhHans: "低电量模式")
    /// `copy/power/status/no-external-display`
    static let copyPowerStatusNoExternalDisplay = LocalizedCopy(key: "copy/power/status/no-external-display", en: "None", zhHans: "无")
    /// `copy/power/status/not-connected`
    static let copyPowerStatusNotConnected = LocalizedCopy(key: "copy/power/status/not-connected", en: "Not connected", zhHans: "未连接")
    /// `copy/state/cancel`
    static let copyStateCancel = LocalizedCopy(key: "copy/state/cancel", en: "Cancel", zhHans: "取消")
    /// `copy/state/component/toolbar/default/disabled`
    static let copyStateComponentToolbarDefaultDisabled = LocalizedCopy(key: "copy/state/component/toolbar/default/disabled", en: "Disabled", zhHans: "禁用")
    /// `copy/state/component/toolbar/default/focused`
    static let copyStateComponentToolbarDefaultFocused = LocalizedCopy(key: "copy/state/component/toolbar/default/focused", en: "Focused", zhHans: "聚焦")
    /// `copy/state/component/toolbar/default/hover`
    static let copyStateComponentToolbarDefaultHover = LocalizedCopy(key: "copy/state/component/toolbar/default/hover", en: "Hover", zhHans: "悬停")
    /// `copy/state/component/toolbar/default/pressed`
    static let copyStateComponentToolbarDefaultPressed = LocalizedCopy(key: "copy/state/component/toolbar/default/pressed", en: "Pressed", zhHans: "按下")
    /// `copy/state/disabled`
    static let copyStateDisabled = LocalizedCopy(key: "copy/state/disabled", en: "Unavailable", zhHans: "不可用")
    /// `copy/state/empty`
    static let copyStateEmpty = LocalizedCopy(key: "copy/state/empty", en: "No items", zhHans: "无项目")
    /// `copy/state/error`
    static let copyStateError = LocalizedCopy(key: "copy/state/error", en: "Action failed", zhHans: "操作失败")
    /// `copy/state/label/error`
    static let copyStateLabelError = LocalizedCopy(key: "copy/state/label/error", en: "Error", zhHans: "错误")
    /// `copy/state/label/info`
    static let copyStateLabelInfo = LocalizedCopy(key: "copy/state/label/info", en: "Info", zhHans: "信息")
    /// `copy/state/label/success`
    static let copyStateLabelSuccess = LocalizedCopy(key: "copy/state/label/success", en: "Done", zhHans: "完成")
    /// `copy/state/label/warning`
    static let copyStateLabelWarning = LocalizedCopy(key: "copy/state/label/warning", en: "Warning", zhHans: "警告")
    /// `copy/state/loading`
    static let copyStateLoading = LocalizedCopy(key: "copy/state/loading", en: "Loading", zhHans: "正在加载")
    /// `copy/state/normal`
    static let copyStateNormal = LocalizedCopy(key: "copy/state/normal", en: "Ready", zhHans: "就绪")
    /// `copy/state/retry`
    static let copyStateRetry = LocalizedCopy(key: "copy/state/retry", en: "Retry", zhHans: "重试")
    /// `copy/state/success`
    static let copyStateSuccess = LocalizedCopy(key: "copy/state/success", en: "Completed", zhHans: "已完成")
    /// `copy/state/warning`
    static let copyStateWarning = LocalizedCopy(key: "copy/state/warning", en: "Review required", zhHans: "需要检查")
    /// `copy/status-item/charging`
    static let copyStatusItemCharging = LocalizedCopy(key: "copy/status-item/charging", en: "Battery is charging.", zhHans: "电池正在充电。")
    /// `copy/status-item/default`
    static let copyStatusItemDefault = LocalizedCopy(key: "copy/status-item/default", en: "Covio is available.", zhHans: "Covio 可用。")
    /// `copy/status-item/disabled`
    static let copyStatusItemDisabled = LocalizedCopy(key: "copy/status-item/disabled", en: "Covio is paused.", zhHans: "Covio 已暂停。")
    /// `copy/status-item/helper-error`
    static let copyStatusItemHelperError = LocalizedCopy(key: "copy/status-item/helper-error", en: "Covio system support needs attention.", zhHans: "Covio 系统支持需要处理。")
    /// `copy/status-item/helper-identity-mismatch`
    static let copyStatusItemHelperIdentityMismatch = LocalizedCopy(key: "copy/status-item/helper-identity-mismatch", en: "Covio components are out of sync.", zhHans: "Covio 组件版本不一致。")
    /// `copy/status-item/helper-outdated`
    static let copyStatusItemHelperOutdated = LocalizedCopy(key: "copy/status-item/helper-outdated", en: "Covio needs an update.", zhHans: "Covio 需要更新。")
    /// `copy/status-item/helper-safe-mode`
    static let copyStatusItemHelperSafeMode = LocalizedCopy(key: "copy/status-item/helper-safe-mode", en: "Privileged controls are disabled until Covio support is restored.", zhHans: "恢复 Covio 支持前，特权控制保持禁用。")
    /// `copy/status-item/helper-untrusted`
    static let copyStatusItemHelperUntrusted = LocalizedCopy(key: "copy/status-item/helper-untrusted", en: "Covio cannot verify its system support.", zhHans: "Covio 无法验证系统支持。")
    /// `copy/status-item/idle-prevented`
    static let copyStatusItemIdlePrevented = LocalizedCopy(key: "copy/status-item/idle-prevented", en: "Idle sleep is prevented.", zhHans: "已阻止空闲休眠。")
    /// `copy/status-item/lid-prevented`
    static let copyStatusItemLidPrevented = LocalizedCopy(key: "copy/status-item/lid-prevented", en: "Lid sleep is prevented.", zhHans: "已阻止合盖休眠。")
    /// `copy/status-item/low-battery`
    static let copyStatusItemLowBattery = LocalizedCopy(key: "copy/status-item/low-battery", en: "Battery is low.", zhHans: "电池电量低。")
    /// `copy/toast/error`
    static let copyToastError = LocalizedCopy(key: "copy/toast/error", en: "The operation failed. Try again.", zhHans: "操作失败。请重试。")
    /// `copy/toast/success`
    static let copyToastSuccess = LocalizedCopy(key: "copy/toast/success", en: "Operation completed.", zhHans: "操作已完成。")
    /// `copy/toast/warning`
    static let copyToastWarning = LocalizedCopy(key: "copy/toast/warning", en: "Review the result before you continue.", zhHans: "继续前检查结果。")
    /// `copy/top-shelf/action/clear-all`
    static let copyTopShelfActionClearAll = LocalizedCopy(key: "copy/top-shelf/action/clear-all", en: "Clear", zhHans: "清空")
    /// `copy/top-shelf/action/copy`
    static let copyTopShelfActionCopy = LocalizedCopy(key: "copy/top-shelf/action/copy", en: "Copy", zhHans: "复制")
    /// `copy/top-shelf/action/hide-toolbar`
    static let copyTopShelfActionHideToolbar = LocalizedCopy(key: "copy/top-shelf/action/hide-toolbar", en: "Hide Toolbar", zhHans: "隐藏工具栏")
    /// `copy/top-shelf/action/markup`
    static let copyTopShelfActionMarkup = LocalizedCopy(key: "copy/top-shelf/action/markup", en: "Markup", zhHans: "标记")
    /// `copy/top-shelf/action/open-folder`
    static let copyTopShelfActionOpenFolder = LocalizedCopy(key: "copy/top-shelf/action/open-folder", en: "Open Folder", zhHans: "打开目录")
    /// `copy/top-shelf/action/preview`
    static let copyTopShelfActionPreview = LocalizedCopy(key: "copy/top-shelf/action/preview", en: "Preview", zhHans: "预览")
    /// `copy/top-shelf/action/remove`
    static let copyTopShelfActionRemove = LocalizedCopy(key: "copy/top-shelf/action/remove", en: "Remove", zhHans: "移除")
    /// `copy/top-shelf/action/remove-from-shelf`
    static let copyTopShelfActionRemoveFromShelf = LocalizedCopy(key: "copy/top-shelf/action/remove-from-shelf", en: "Remove from Shelf", zhHans: "从工具栏移除")
    /// `copy/top-shelf/action/show-toolbar`
    static let copyTopShelfActionShowToolbar = LocalizedCopy(key: "copy/top-shelf/action/show-toolbar", en: "Show Toolbar", zhHans: "显示工具栏")
    /// `copy/top-shelf/action/workspace`
    static let copyTopShelfActionWorkspace = LocalizedCopy(key: "copy/top-shelf/action/workspace", en: "Save to Workspace", zhHans: "存入工作区")
    /// `copy/top-shelf/clear`
    static let copyTopShelfClear = LocalizedCopy(key: "copy/top-shelf/clear", en: "Clear Shelf", zhHans: "清空挂帘")
    /// `copy/top-shelf/empty`
    static let copyTopShelfEmpty = LocalizedCopy(key: "copy/top-shelf/empty", en: "No screenshots match your filters.", zhHans: "没有截图符合筛选条件。")
    /// `copy/top-shelf/enabled`
    static let copyTopShelfEnabled = LocalizedCopy(key: "copy/top-shelf/enabled", en: "Top Shelf", zhHans: "顶部挂帘")
    /// `copy/top-shelf/error/copy`
    static let copyTopShelfErrorCopy = LocalizedCopy(key: "copy/top-shelf/error/copy", en: "Cannot copy the screenshot.", zhHans: "无法复制截图。")
    /// `copy/top-shelf/error/directory`
    static let copyTopShelfErrorDirectory = LocalizedCopy(key: "copy/top-shelf/error/directory", en: "Cannot open the screenshot folder.", zhHans: "无法打开截图目录。")
    /// `copy/top-shelf/error/markup`
    static let copyTopShelfErrorMarkup = LocalizedCopy(key: "copy/top-shelf/error/markup", en: "Cannot open Markup.", zhHans: "无法打开标记工具。")
    /// `copy/top-shelf/error/move`
    static let copyTopShelfErrorMove = LocalizedCopy(key: "copy/top-shelf/error/move", en: "The file operation failed.", zhHans: "文件操作失败。")
    /// `copy/top-shelf/error/open`
    static let copyTopShelfErrorOpen = LocalizedCopy(key: "copy/top-shelf/error/open", en: "Cannot open the screenshot.", zhHans: "无法打开截图。")
    /// `copy/top-shelf/error/restore`
    static let copyTopShelfErrorRestore = LocalizedCopy(key: "copy/top-shelf/error/restore", en: "System screenshot settings were not restored.", zhHans: "系统截图设置未能恢复。")
    /// `copy/top-shelf/error/takeover`
    static let copyTopShelfErrorTakeover = LocalizedCopy(key: "copy/top-shelf/error/takeover", en: "Screenshot takeover failed.", zhHans: "截图接管失败。")
    /// `copy/top-shelf/none`
    static let copyTopShelfNone = LocalizedCopy(key: "copy/top-shelf/none", en: "No screenshots", zhHans: "没有截图")
    /// `copy/top-shelf/open-folder`
    static let copyTopShelfOpenFolder = LocalizedCopy(key: "copy/top-shelf/open-folder", en: "Open Screenshot Folder", zhHans: "打开截图文件夹")
    /// `copy/top-shelf/pending-notice`
    static let copyTopShelfPendingNotice = LocalizedCopy(key: "copy/top-shelf/pending-notice", en: "These switches save the setting now. The shelf itself arrives in a later phase.", zhHans: "这些开关现在只保存设置。挂帘本体在后续阶段接上。")
    /// `copy/top-shelf/show`
    static let copyTopShelfShow = LocalizedCopy(key: "copy/top-shelf/show", en: "Show Shelf", zhHans: "显示挂帘")
    /// `copy/top-shelf/sounds`
    static let copyTopShelfSounds = LocalizedCopy(key: "copy/top-shelf/sounds", en: "Screenshot sounds", zhHans: "截图声音")
    /// `copy/top-shelf/state/cancel`
    static let copyTopShelfStateCancel = LocalizedCopy(key: "copy/top-shelf/state/cancel", en: "CANCEL", zhHans: "取消拖拽")
    /// `copy/top-shelf/state/drag-to-app`
    static let copyTopShelfStateDragToApp = LocalizedCopy(key: "copy/top-shelf/state/drag-to-app", en: "DRAG TO APP", zhHans: "拖到应用")
    /// `copy/top-shelf/state/drag-to-folder`
    static let copyTopShelfStateDragToFolder = LocalizedCopy(key: "copy/top-shelf/state/drag-to-folder", en: "DRAG TO FOLDER", zhHans: "拖到文件夹")
    /// `copy/top-shelf/state/drag-to-trash`
    static let copyTopShelfStateDragToTrash = LocalizedCopy(key: "copy/top-shelf/state/drag-to-trash", en: "DRAG TO TRASH", zhHans: "拖到废纸篓")
    /// `copy/top-shelf/state/hover`
    static let copyTopShelfStateHover = LocalizedCopy(key: "copy/top-shelf/state/hover", en: "HOVER", zhHans: "悬停")
    /// `copy/top-shelf/state/right-click-menu`
    static let copyTopShelfStateRightClickMenu = LocalizedCopy(key: "copy/top-shelf/state/right-click-menu", en: "RIGHT-CLICK MENU", zhHans: "右键菜单")
    /// `copy/top-shelf/status`
    static let copyTopShelfStatus = LocalizedCopy(key: "copy/top-shelf/status", en: "Shelf status", zhHans: "挂帘状态")
    /// `copy/top-shelf/take-over`
    static let copyTopShelfTakeOver = LocalizedCopy(key: "copy/top-shelf/take-over", en: "Take over screenshots", zhHans: "接管截图")
    /// `copy/top-shelf/title`
    static let copyTopShelfTitle = LocalizedCopy(key: "copy/top-shelf/title", en: "Top Shelf", zhHans: "顶部工具栏")
    /// `copy/tray/action/display-off`
    static let copyTrayActionDisplayOff = LocalizedCopy(key: "copy/tray/action/display-off", en: "Turn Display Off", zhHans: "关闭显示器")
    /// `copy/tray/action/quit`
    static let copyTrayActionQuit = LocalizedCopy(key: "copy/tray/action/quit", en: "Quit Covio", zhHans: "退出 Covio")
    /// `copy/tray/action/settings`
    static let copyTrayActionSettings = LocalizedCopy(key: "copy/tray/action/settings", en: "Settings…", zhHans: "设置…")
    /// `copy/tray/action/show-shelf`
    static let copyTrayActionShowShelf = LocalizedCopy(key: "copy/tray/action/show-shelf", en: "Show Shelf", zhHans: "显示挂帘")
    /// `copy/tray/action/sleep-now`
    static let copyTrayActionSleepNow = LocalizedCopy(key: "copy/tray/action/sleep-now", en: "Sleep Now", zhHans: "立即睡眠")
    /// `copy/tray/tooltip/battery`
    static let copyTrayTooltipBattery = LocalizedCopy(key: "copy/tray/tooltip/battery", en: "On battery", zhHans: "使用电池")
    /// `copy/tray/tooltip/charging`
    static let copyTrayTooltipCharging = LocalizedCopy(key: "copy/tray/tooltip/charging", en: "Charging", zhHans: "正在充电")
    /// `copy/tray/tooltip/helper-error`
    static let copyTrayTooltipHelperError = LocalizedCopy(key: "copy/tray/tooltip/helper-error", en: "System support error", zhHans: "系统支持错误")
    /// `copy/tray/tooltip/idle-prevented`
    static let copyTrayTooltipIdlePrevented = LocalizedCopy(key: "copy/tray/tooltip/idle-prevented", en: "Idle sleep prevented", zhHans: "已阻止闲置睡眠")
    /// `copy/tray/tooltip/lid-prevented`
    static let copyTrayTooltipLidPrevented = LocalizedCopy(key: "copy/tray/tooltip/lid-prevented", en: "Lid sleep prevented", zhHans: "已阻止合盖睡眠")
    /// `copy/tray/tooltip/low-battery`
    static let copyTrayTooltipLowBattery = LocalizedCopy(key: "copy/tray/tooltip/low-battery", en: "Low battery", zhHans: "电量低")
    /// `copy/tray/tooltip/normal`
    static let copyTrayTooltipNormal = LocalizedCopy(key: "copy/tray/tooltip/normal", en: "Covio status", zhHans: "Covio 状态")

    /// 全部条目。供测试遍历。
    static let all: [LocalizedCopy] = [
        copyAgentActionCancelled,
        copyAgentActionCompleted,
        copyAgentActionFailed,
        copyAgentAttachFiles,
        copyAgentCancel,
        copyAgentClear,
        copyAgentConfirm,
        copyAgentConfirmBody,
        copyAgentConfirmTitle,
        copyAgentCopyCharacters,
        copyAgentEmptyBody,
        copyAgentEmptyResponse,
        copyAgentEmptyTitle,
        copyAgentError,
        copyAgentHistoryClearAll,
        copyAgentHistoryClearBody,
        copyAgentHistoryClearTitle,
        copyAgentName,
        copyAgentOffline,
        copyAgentPlaceholder,
        copyAgentRemoveAttachment,
        copyAgentSend,
        copyAgentStop,
        copyAgentStopped,
        copyAgentThinking,
        copyAgentYou,
        copyAppName,
        copyAppTagline,
        copyAutoNamingActionApply,
        copyAutoNamingActionAutoName,
        copyAutoNamingActionCancel,
        copyAutoNamingActionClose,
        copyAutoNamingActionSelect,
        copyAutoNamingActionUndo,
        copyAutoNamingErrorAnalysis,
        copyAutoNamingErrorRename,
        copyAutoNamingErrorUndo,
        copyAutoNamingLabelEvidence,
        copyAutoNamingLabelOriginal,
        copyAutoNamingLabelTarget,
        copyAutoNamingLabelWarnings,
        copyAutoNamingNoticeApplied,
        copyAutoNamingNoticeCancelled,
        copyAutoNamingNoticeNoFiles,
        copyAutoNamingNoticeNoResults,
        copyAutoNamingNoticeNoSelection,
        copyAutoNamingNoticePartialFailure,
        copyAutoNamingNoticePartialUndo,
        copyAutoNamingNoticeUndone,
        copyAutoNamingRiskConflict,
        copyAutoNamingRiskFallback,
        copyAutoNamingRiskLowConfidence,
        copyAutoNamingRiskMixed,
        copyAutoNamingRiskPromptInjection,
        copyAutoNamingRiskScanned,
        copyAutoNamingRiskTruncated,
        copyAutoNamingStatusBlocked,
        copyAutoNamingStatusFailed,
        copyAutoNamingStatusReady,
        copyAutoNamingStatusRenamed,
        copyAutoNamingStatusUndone,
        copyAutoNamingSubtitle,
        copyAutoNamingTitle,
        copyBatteryCapacityThreshold,
        copyBatteryEnabled,
        copyBatteryTimeThreshold,
        copyBatteryUnitMinutes,
        copyBatteryUnitPercent,
        copyClipboardActionClear,
        copyClipboardActionClearSearch,
        copyClipboardActionOpenSettings,
        copyClipboardActionPaste,
        copyClipboardActionPin,
        copyClipboardActionRemove,
        copyClipboardActionUnpin,
        copyClipboardActionWorkspace,
        copyClipboardEmpty,
        copyClipboardErrorAccessibility,
        copyClipboardErrorHotKey,
        copyClipboardErrorImage,
        copyClipboardErrorPaste,
        copyClipboardFilterAll,
        copyClipboardGroupEarlier,
        copyClipboardGroupPinned,
        copyClipboardGroupToday,
        copyClipboardGroupYesterday,
        copyClipboardKindDedicated,
        copyClipboardNoMatchHint,
        copyClipboardNoMatchTitle,
        copyClipboardPreviewEmpty,
        copyClipboardSearchPlaceholder,
        copyClipboardSettingsAccessibility,
        copyClipboardSettingsAccessibilityFallback,
        copyClipboardSettingsCaptureHotKey,
        copyClipboardSettingsEnabled,
        copyClipboardSettingsGranted,
        copyClipboardSettingsHotKeyConflict,
        copyClipboardSettingsHotKeys,
        copyClipboardSettingsNotGranted,
        copyClipboardSettingsPasteStackHotKey,
        copyClipboardSettingsRequestPermission,
        copyClipboardStatePause,
        copyClipboardStatePaused,
        copyClipboardStateResume,
        copyClipboardTitle,
        copyComponentMaterialBlur,
        copyComponentMaterialMedium,
        copyComponentMaterialThick,
        copyComponentMaterialThin,
        copyComponentMaterialUltraThick,
        copyComponentMaterialUltraThin,
        copyComponentPopoverBottom,
        copyComponentPopoverCustom,
        copyComponentPopoverForm,
        copyComponentPopoverMenu,
        copyComponentPopoverTop,
        copyComponentToolbarCompact,
        copyComponentToolbarDefault,
        copyComponentWindowShellCompact,
        copyComponentWindowShellSidebar,
        copyComponentWindowShellStandard,
        copyComponentWindowShellToolbar,
        copyDialogHelperInstallBody,
        copyDialogHelperInstallTitle,
        copyDialogHelperUnavailableBody,
        copyDialogHelperUnavailableTitle,
        copyDialogResetBody,
        copyDialogResetTitle,
        copyDialogUpdateBody,
        copyDialogUpdateTitle,
        copyGeneralCheckUpdates,
        copyGeneralClearConfig,
        copyGeneralDarkwake,
        copyGeneralExternalAgentCopied,
        copyGeneralExternalAgentCopyPairing,
        copyGeneralExternalAgentEnabled,
        copyGeneralExternalAgentEndpoint,
        copyGeneralExternalAgentRotateToken,
        copyGeneralExternalAgentStarting,
        copyGeneralExternalAgentSummary,
        copyGeneralExternalAgentTitle,
        copyGeneralExternalAgentUnavailable,
        copyGeneralExternalAgentWarning,
        copyGeneralLanguage,
        copyGeneralLanguageChinese,
        copyGeneralLanguageEnglish,
        copyGeneralLanguageSystem,
        copyGeneralLaunchAtLogin,
        copyGeneralLocalModelActive,
        copyGeneralLocalModelAgentDisabled,
        copyGeneralLocalModelFailed,
        copyGeneralLocalModelImport,
        copyGeneralLocalModelMinimum,
        copyGeneralLocalModelSummary,
        copyGeneralLocalModelTitle,
        copyGeneralLocalModelUnsupported,
        copyGeneralLocalModelUse,
        copyGeneralLocalModelVerifying,
        copyGeneralNotifications,
        copyGeneralSleepMode,
        copyGeneralSleepModeDefault,
        copyGeneralSleepModeFastest,
        copyGeneralSleepModeLowestPower,
        copyHelperServiceEnabled,
        copyHelperServiceError,
        copyHelperServiceLegacy,
        copyHelperServiceNotFound,
        copyHelperServiceNotRegistered,
        copyHelperServiceRequiresApproval,
        copyHelperServiceUnsupported,
        copyHubActionBack,
        copyHubActionDone,
        copyHubActionEdit,
        copyHubActionHome,
        copyHubActionSettings,
        copyHubEditBanner,
        copyHubEditReorder,
        copyHubEditWidgetCount,
        copyHubEditWorkspaceCount,
        copyHubFilesActionAdd,
        copyHubFilesActionCancelTransfer,
        copyHubFilesActionClearFilter,
        copyHubFilesActionCopy,
        copyHubFilesActionCopyText,
        copyHubFilesActionDismiss,
        copyHubFilesActionDownload,
        copyHubFilesActionImport,
        copyHubFilesActionMarkup,
        copyHubFilesActionMore,
        copyHubFilesActionNewText,
        copyHubFilesActionOpen,
        copyHubFilesActionPin,
        copyHubFilesActionRemove,
        copyHubFilesActionRetry,
        copyHubFilesActionReveal,
        copyHubFilesActionSaveToWorkspace,
        copyHubFilesActionSweep,
        copyHubFilesActionUnpin,
        copyHubFilesCountItems,
        copyHubFilesEmpty,
        copyHubFilesEmptyHint,
        copyHubFilesEmptyTitle,
        copyHubFilesErrorConnection,
        copyHubFilesErrorCopy,
        copyHubFilesErrorImport,
        copyHubFilesErrorMissing,
        copyHubFilesErrorQuota,
        copyHubFilesErrorSave,
        copyHubFilesErrorTooLarge,
        copyHubFilesFilterAll,
        copyHubFilesFilterFiles,
        copyHubFilesFilterScreenshots,
        copyHubFilesFilterText,
        copyHubFilesFilterTransfers,
        copyHubFilesHint,
        copyHubFilesKindAudio,
        copyHubFilesKindImage,
        copyHubFilesKindPdf,
        copyHubFilesNoMatchHint,
        copyHubFilesNoMatchTitle,
        copyHubFilesNoticeDuplicate,
        copyHubFilesNoticeSaved,
        copyHubFilesNoticeSwept,
        copyHubFilesStateFetching,
        copyHubFilesStateLocal,
        copyHubFilesStateOnOtherDevice,
        copyHubFilesStateTransferCancelled,
        copyHubFilesStateTransferFailed,
        copyHubFilesStateTransferring,
        copyHubFilesStateUnavailable,
        copyHubFilesStateWaiting,
        copyHubFilesStatusActive,
        copyHubFilesUsage,
        copyHubHomeEmptyHint,
        copyHubHomeEmptyHintEditing,
        copyHubHomeEmptyTitle,
        copyHubLogExport,
        copyHubLogView,
        copyHubPlaceholderNotice,
        copyHubPowerSegmentOverview,
        copyHubPowerSegmentPower,
        copyHubPowerSummary,
        copyHubPowerTitle,
        copyHubSearchClear,
        copyHubTabAgent,
        copyHubTabAgentSummary,
        copyHubTabBoard,
        copyHubTabBoardSummary,
        copyHubTabClipboard,
        copyHubTabClipboardSummary,
        copyHubTabDevices,
        copyHubTabDevicesSummary,
        copyHubTabFiles,
        copyHubTabFilesSummary,
        copyHubTabNow,
        copyHubTabNowSummary,
        copyHubTabScreenshots,
        copyHubTabScreenshotsSummary,
        copyHubTabSettings,
        copyHubTabSettingsSummary,
        copyHubUpdateUpToDate,
        copyHubWidgetActionsTitle,
        copyHubWidgetBatteryTitle,
        copyHubWidgetClockTitle,
        copyHubWidgetDevicesTitle,
        copyHubWidgetMoveDown,
        copyHubWidgetMoveLeft,
        copyHubWidgetMoveRight,
        copyHubWidgetMoveUp,
        copyHubWidgetRemove,
        copyHubWidgetResize,
        copyHubWidgetShotsTitle,
        copyHubWidgetSizeLarge,
        copyHubWidgetSizeSmall,
        copyHubWidgetSizeTall,
        copyHubWidgetSizeWide,
        copyHubWidgetTransferTitle,
        copyIconConceptBlueGrid,
        copyIconConceptBlueKoala,
        copyIconConceptBlueOrbit,
        copyIconConceptNotchCore,
        copyIconConceptStatusPulse,
        copyIconConceptTopShelf,
        copyIdleCancelAfter,
        copyIdlePreventIdle,
        copyIdleRemaining,
        copyIdleWhileCharging,
        copyLidHoldPolicy,
        copyLidHoldPolicyAdapter,
        copyLidHoldPolicyAny,
        copyLidHoldPolicyBattery,
        copyLidHoldPolicyHint,
        copyLidHoldPolicySleep,
        copyLidWarning,
        copyMacos27AlignmentMeasurement,
        copyMacos27AlignmentStaticVerified,
        copyModeDark,
        copyModeLight,
        copyModelSetupActionDownload,
        copyModelSetupActionPause,
        copyModelSetupActionRemove,
        copyModelSetupActionResume,
        copyModelSetupActionRetry,
        copyModelSetupErrorActivation,
        copyModelSetupErrorDisk,
        copyModelSetupErrorGeneric,
        copyModelSetupErrorMemory,
        copyModelSetupErrorNetwork,
        copyModelSetupErrorRevision,
        copyModelSetupErrorVerification,
        copyModelSetupLicense,
        copyModelSetupNetwork,
        copyModelSetupRecommended,
        copyModelSetupRemoveBody,
        copyModelSetupRemoveTitle,
        copyModelSetupSelectModel,
        copyModelSetupSize,
        copyModelSetupStateDownloading,
        copyModelSetupStateFailed,
        copyModelSetupStateNotInstalled,
        copyModelSetupStatePaused,
        copyModelSetupStateReady,
        copyModelSetupStateVerifying,
        copyModelSetupSummary,
        copyModelSetupTitle,
        copyMonitorBatteryRemaining,
        copyMonitorBatterySource,
        copyMonitorBatteryState,
        copyMonitorCores,
        copyMonitorDiskFree,
        copyMonitorDiskRead,
        copyMonitorDiskUsed,
        copyMonitorDiskWrite,
        copyMonitorDisplayActionSettings,
        copyMonitorDisplayActionSleep,
        copyMonitorDisplayActionsTitle,
        copyMonitorDisplayBrightness,
        copyMonitorDisplayClosedLidTitle,
        copyMonitorDisplayDetailsCollapse,
        copyMonitorDisplayDetailsExpand,
        copyMonitorDisplayDetailsTitle,
        copyMonitorDisplayGuardBatteryFloor,
        copyMonitorDisplayGuardBatteryStateUnknown,
        copyMonitorDisplayGuardClosedLidDisabled,
        copyMonitorDisplayGuardExternalDisplay,
        copyMonitorDisplayGuardExternalDisplayUnknown,
        copyMonitorDisplayGuardLowPowerMode,
        copyMonitorDisplayGuardPaused,
        copyMonitorDisplayGuardSleepSettingConflict,
        copyMonitorDisplayGuardSleepStateUnknown,
        copyMonitorDisplayGuardThermal,
        copyMonitorDisplayGuardTimeCap,
        copyMonitorDisplayKeepAwake,
        copyMonitorDisplayKeepAwakeHint,
        copyMonitorDisplayMode,
        copyMonitorDisplayModeBlack,
        copyMonitorDisplayModeOff,
        copyMonitorDisplayModeSystem,
        copyMonitorDisplayPower,
        copyMonitorDisplayPowerUnavailable,
        copyMonitorDisplayRefreshRate,
        copyMonitorDisplayResolution,
        copyMonitorDisplaySafetyNote,
        copyMonitorDisplaySessionStart,
        copyMonitorDisplayStatusTitle,
        copyMonitorDisplayStatusActive,
        copyMonitorDisplayStatusAsleep,
        copyMonitorDisplayStatusOffline,
        copyMonitorDisplayTimeCap,
        copyMonitorDisplayTimeCapHint,
        copyMonitorFanA11yCurve,
        copyMonitorFanA11yOpen,
        copyMonitorFanA11yStatus,
        copyMonitorFanActiveCurveAdapter,
        copyMonitorFanActiveCurveBattery,
        copyMonitorFanActiveCurveMixed,
        copyMonitorFanActual,
        copyMonitorFanAddPoint,
        copyMonitorFanAddTemperaturePoint,
        copyMonitorFanAdvanced,
        copyMonitorFanAllFans,
        copyMonitorFanApplying,
        copyMonitorFanAutoCurve,
        copyMonitorFanAutomatic,
        copyMonitorFanBalanced,
        copyMonitorFanBatteryCurveFallback,
        copyMonitorFanClearBatteryCurve,
        copyMonitorFanControlPoint,
        copyMonitorFanControlSensors,
        copyMonitorFanControlSource,
        copyMonitorFanControlSummary,
        copyMonitorFanControlTemperature,
        copyMonitorFanCopyAdapterCurve,
        copyMonitorFanCurve,
        copyMonitorFanCurveHint,
        copyMonitorFanCurveSource,
        copyMonitorFanCurveSourceAdapter,
        copyMonitorFanCurveSourceBattery,
        copyMonitorFanDeletePoint,
        copyMonitorFanDetails,
        copyMonitorFanEnable,
        copyMonitorFanFullCaption,
        copyMonitorFanFullSpeed,
        copyMonitorFanFullSpeedAll,
        copyMonitorFanFullSpeedUnit,
        copyMonitorFanFullTemperature,
        copyMonitorFanHelperRequired,
        copyMonitorFanHelperUnavailable,
        copyMonitorFanInstallHelper,
        copyMonitorFanLegendWindow,
        copyMonitorFanManual,
        copyMonitorFanManualRpm,
        copyMonitorFanOwned,
        copyMonitorFanPowerSourceAdapter,
        copyMonitorFanPowerSourceBattery,
        copyMonitorFanPowerSourceUnknown,
        copyMonitorFanQuiet,
        copyMonitorFanReadFailed,
        copyMonitorFanResetCurve,
        copyMonitorFanRestoreAutoCurve,
        copyMonitorFanRestoreSystem,
        copyMonitorFanRpm,
        copyMonitorFanSensorFilter,
        copyMonitorFanSensorFilterEmpty,
        copyMonitorFanSensorLibraryHint,
        copyMonitorFanSourceBattery,
        copyMonitorFanSourceCpu,
        copyMonitorFanSourceFanPercent,
        copyMonitorFanSourceFanPercentLabel,
        copyMonitorFanSourceGpu,
        copyMonitorFanSourceHint,
        copyMonitorFanSourceRequest,
        copyMonitorFanSourceSummary,
        copyMonitorFanSourceUnavailable,
        copyMonitorFanStartCaption,
        copyMonitorFanStartTemperature,
        copyMonitorFanSyncFans,
        copyMonitorFanSyncHint,
        copyMonitorFanSystemAuto,
        copyMonitorFanSystemControl,
        copyMonitorFanSystemControlBody,
        copyMonitorFanSystemControlTitle,
        copyMonitorFanTakeoverBody,
        copyMonitorFanTakeoverTitle,
        copyMonitorFanTarget,
        copyMonitorFanTemperature,
        copyMonitorFanTemperatureSources,
        copyMonitorFanTemperatureTick,
        copyMonitorFanTitle,
        copyMonitorFanTurbo,
        copyMonitorFanUnavailable,
        copyMonitorFanUnit,
        copyMonitorFanWarning,
        copyMonitorGpuDevice,
        copyMonitorGpuMemory,
        copyMonitorHistory,
        copyMonitorLive,
        copyMonitorLoad1,
        copyMonitorMemoryPressureCritical,
        copyMonitorMemoryPressureNormal,
        copyMonitorMemoryPressureWarning,
        copyMonitorMemoryPressure,
        copyMonitorMemorySwap,
        copyMonitorMemoryTotal,
        copyMonitorMemoryUsed,
        copyMonitorNetworkDownload,
        copyMonitorNetworkInterface,
        copyMonitorNetworkUpload,
        copyMonitorPerCore,
        copyMonitorPowerAverageDraw,
        copyMonitorPowerChargeLimitActiveDischarge,
        copyMonitorPowerChargeLimitActiveDischargeWarning,
        copyMonitorPowerChargeLimitApply,
        copyMonitorPowerChargeLimitApplying,
        copyMonitorPowerChargeLimitCurrentCharge,
        copyMonitorPowerChargeLimitCurrentTarget,
        copyMonitorPowerChargeLimitEnable,
        copyMonitorPowerChargeLimitFailed,
        copyMonitorPowerChargeLimitHelperRequired,
        copyMonitorPowerChargeLimitRestore,
        copyMonitorPowerChargeLimitResumeAt,
        copyMonitorPowerChargeLimitStateAboveLimit,
        copyMonitorPowerChargeLimitStateBypass,
        copyMonitorPowerChargeLimitStateCalibration,
        copyMonitorPowerChargeLimitStateConflict,
        copyMonitorPowerChargeLimitStateDischarging,
        copyMonitorPowerChargeLimitStateError,
        copyMonitorPowerChargeLimitStateHolding,
        copyMonitorPowerChargeLimitStateProtection,
        copyMonitorPowerChargeLimitStateSailing,
        copyMonitorPowerChargeLimitStateStoppingDischarge,
        copyMonitorPowerChargeLimitStateSystem,
        copyMonitorPowerChargeLimitStateUnplugged,
        copyMonitorPowerChargeLimitTitle,
        copyMonitorPowerChargeLimitUnsupported,
        copyMonitorPowerChargeHealth,
        copyMonitorPowerChargePower,
        copyMonitorPowerChargeTimeToFull,
        copyMonitorPowerChargeTitle,
        copyMonitorPowerCriticalBattery,
        copyMonitorPowerDetailsClose,
        copyMonitorPowerDetailsCollapse,
        copyMonitorPowerDetailsCollapseSettings,
        copyMonitorPowerDetailsExpand,
        copyMonitorPowerDetailsExpandSettings,
        copyMonitorPowerDetailsTitle,
        copyMonitorPowerDraw,
        copyMonitorPowerEstimateBasis,
        copyMonitorPowerEventsConnected,
        copyMonitorPowerEventsDisconnected,
        copyMonitorPowerEventsFullyCharged,
        copyMonitorPowerEventsTitle,
        copyMonitorPowerHighTemperature,
        copyMonitorPowerHistoryAccumulating,
        copyMonitorPowerHistoryTitle,
        copyMonitorPowerLowBattery,
        copyMonitorPowerNoBattery,
        copyMonitorPowerNoData,
        copyMonitorPowerReadFailed,
        copyMonitorPowerRemaining,
        copyMonitorPowerStateBattery,
        copyMonitorPowerStateConnected,
        copyMonitorPowerTemperature,
        copyMonitorPowerTopApps,
        copyMonitorPowerTrendTitle,
        copyMonitorPowerTrendWindow,
        copyMonitorReportCancel,
        copyMonitorReportChartCpuGpu,
        copyMonitorReportChartMemory,
        copyMonitorReportChartNetwork,
        copyMonitorReportClear,
        copyMonitorReportClose,
        copyMonitorReportCoverageObserved,
        copyMonitorReportCoverageSamples,
        copyMonitorReportCoverageSleep,
        copyMonitorReportCoverageTitle,
        copyMonitorReportCoverageUnknown,
        copyMonitorReportDeleteConfirm,
        copyMonitorReportDeleteMessage,
        copyMonitorReportDeleteTitle,
        copyMonitorReportEmpty,
        copyMonitorReportError,
        copyMonitorReportEventsTitle,
        copyMonitorReportExport,
        copyMonitorReportExportError,
        copyMonitorReportExportSuccess,
        copyMonitorReportGapsTitle,
        copyMonitorReportGenerated,
        copyMonitorReportLoading,
        copyMonitorReportMethod,
        copyMonitorReportNoDataHint,
        copyMonitorReportOpen,
        copyMonitorReportPartial,
        copyMonitorReportPeaksMetric,
        copyMonitorReportPeaksTitle,
        copyMonitorReportPeaksValue,
        copyMonitorReportRangeEnd,
        copyMonitorReportRangeLast10Days,
        copyMonitorReportRangeLimit,
        copyMonitorReportRangeStart,
        copyMonitorReportSummary,
        copyMonitorReportSystemChip,
        copyMonitorReportSystemDisk,
        copyMonitorReportSystemMemory,
        copyMonitorReportSystemModel,
        copyMonitorReportSystemOs,
        copyMonitorReportSystemStart,
        copyMonitorReportSystemTitle,
        copyMonitorReportTableConfidence,
        copyMonitorReportTableCount,
        copyMonitorReportTableCpu,
        copyMonitorReportTableData,
        copyMonitorReportTableDuration,
        copyMonitorReportTableEvent,
        copyMonitorReportTableGpu,
        copyMonitorReportTableKind,
        copyMonitorReportTableMemory,
        copyMonitorReportTableNetworkDown,
        copyMonitorReportTableNetworkUp,
        copyMonitorReportTableReason,
        copyMonitorReportTableSource,
        copyMonitorReportTableTime,
        copyMonitorReportThresholdsTitle,
        copyMonitorReportTitle,
        copyMonitorReportUnavailableTitle,
        copyMonitorSamplingFast,
        copyMonitorSamplingSlow,
        copyMonitorStateAcPower,
        copyMonitorStateCharged,
        copyMonitorStateCharging,
        copyMonitorStateOnBattery,
        copyMonitorStateUnknown,
        copyMonitorThermal,
        copyMonitorThermalCritical,
        copyMonitorThermalFair,
        copyMonitorThermalNominal,
        copyMonitorThermalSerious,
        copyMonitorTitleBattery,
        copyMonitorTitleCpu,
        copyMonitorTitleDisk,
        copyMonitorTitleDisplay,
        copyMonitorTitleGpu,
        copyMonitorTitleMemory,
        copyMonitorTitleNetwork,
        copyMonitorUnavailable,
        copyMonitorUptime,
        copyMonitorUsage,
        copyNavBattery,
        copyNavClipboard,
        copyNavGeneral,
        copyNavIdle,
        copyNavOverview,
        copyNavQuit,
        copyNavRailLabel,
        copyNavSearchEmpty,
        copyNavSearchPlaceholder,
        copyNavSearchResults,
        copyNavStatusPaused,
        copyNavStatusRunning,
        copyNavTopShelf,
        copyNotchHubLayoutCollapsedPresence,
        copyNotchHubLayoutDragTarget,
        copyNotchHubLayoutExpandedOutput,
        copyNotchHubStateActive,
        copyNotchHubStateCollapsed,
        copyNotchHubStateDragTarget,
        copyNotchHubStateError,
        copyNotchHubStateExit,
        copyNotchHubStateExpanded,
        copyNotchHubStateHidden,
        copyNotchHubStateHover,
        copyNotchHubStateOpen,
        copyNotchHubStateProcessing,
        copyNotchHubStateReady,
        copyOverviewActionDisplayOff,
        copyOverviewActionSleepNow,
        copyOverviewHelperInstall,
        copyOverviewHelperInstalled,
        copyOverviewHelperMissing,
        copyOverviewHelperVersion,
        copyOverviewRulesMaster,
        copyPageBatteryStateDisabled,
        copyPageBatteryStateEmpty,
        copyPageBatteryStateError,
        copyPageBatteryStateLoading,
        copyPageBatteryStateNormal,
        copyPageBatteryStateSuccess,
        copyPageBatteryStateWarning,
        copyPageBatterySummary,
        copyPageBatteryTitle,
        copyPageClipboardSummary,
        copyPageClipboardTitle,
        copyPageGeneralStateDisabled,
        copyPageGeneralStateEmpty,
        copyPageGeneralStateError,
        copyPageGeneralStateLoading,
        copyPageGeneralStateNormal,
        copyPageGeneralStateSuccess,
        copyPageGeneralStateWarning,
        copyPageGeneralSummary,
        copyPageGeneralTitle,
        copyPageIdleStateDisabled,
        copyPageIdleStateEmpty,
        copyPageIdleStateError,
        copyPageIdleStateLoading,
        copyPageIdleStateNormal,
        copyPageIdleStateSuccess,
        copyPageIdleStateWarning,
        copyPageIdleSummary,
        copyPageIdleTitle,
        copyPageOverviewStateDisabled,
        copyPageOverviewStateEmpty,
        copyPageOverviewStateError,
        copyPageOverviewStateLoading,
        copyPageOverviewStateNormal,
        copyPageOverviewStateSuccess,
        copyPageOverviewStateWarning,
        copyPageOverviewSummary,
        copyPageOverviewTitle,
        copyPageTopShelfSettingsStateDisabled,
        copyPageTopShelfSettingsStateEmpty,
        copyPageTopShelfSettingsStateError,
        copyPageTopShelfSettingsStateLoading,
        copyPageTopShelfSettingsStateNormal,
        copyPageTopShelfSettingsStateSuccess,
        copyPageTopShelfSettingsStateWarning,
        copyPageTopShelfSettingsSummary,
        copyPageTopShelfSettingsTitle,
        copyPowerAlertExternalConflict,
        copyPowerAlertHelperMissing,
        copyPowerAlertThermal,
        copyPowerClosedLidPointer,
        copyPowerDescriptionMaster,
        copyPowerErrorLidNotApplied,
        copyPowerErrorMasterOff,
        copyPowerHistoryAdapterConnected,
        copyPowerHistoryAdapterDisconnected,
        copyPowerHistoryExternalConflictCleared,
        copyPowerHistoryGuardReleased,
        copyPowerHistoryHint,
        copyPowerHistoryHoldStarted,
        copyPowerHistoryNoEvents,
        copyPowerHistorySlept,
        copyPowerHistoryWindow,
        copyPowerHistoryWoke,
        copyPowerOverviewNote,
        copyPowerPopoverDetails,
        copyPowerPopoverPower,
        copyPowerPopoverTitle,
        copyPowerRulesAdapter,
        copyPowerRulesBattery,
        copyPowerRulesBatteryFloor,
        copyPowerRulesBatteryFloorHint,
        copyPowerRulesBatteryHint,
        copyPowerRulesClosedLidZeroBrightness,
        copyPowerRulesClosedLidZeroBrightnessFailed,
        copyPowerRulesClosedLidZeroBrightnessHint,
        copyPowerRulesClosedLidZeroBrightnessUnavailable,
        copyPowerRulesExternalDisplay,
        copyPowerRulesExternalDisplayHint,
        copyPowerRulesHeatGuard,
        copyPowerRulesHeatGuardHint,
        copyPowerRulesLid,
        copyPowerRulesLidHint,
        copyPowerRulesLowPowerHint,
        copyPowerRulesOff,
        copyPowerRulesOn,
        copyPowerSectionAdvanced,
        copyPowerSectionAutomatic,
        copyPowerSectionHistory,
        copyPowerSectionRules,
        copyPowerSectionSafety,
        copyPowerSectionSession,
        copyPowerSectionStatus,
        copyPowerSessionActive,
        copyPowerSessionDisplay,
        copyPowerSessionDuration,
        copyPowerSessionDuration15m,
        copyPowerSessionDuration1h,
        copyPowerSessionDuration2h,
        copyPowerSessionDuration4h,
        copyPowerSessionDurationOpen,
        copyPowerSessionEnd,
        copyPowerSessionExpires,
        copyPowerSessionInactive,
        copyPowerSessionLid,
        copyPowerSessionLidDisplayOff,
        copyPowerSessionLidDisplayOffHint,
        copyPowerSessionLidZeroBrightness,
        copyPowerSessionMode,
        copyPowerSessionNone,
        copyPowerSessionReasonAdapter,
        copyPowerSessionReasonLid,
        copyPowerSessionStart,
        copyPowerSessionStartHint,
        copyPowerSessionSystem,
        copyPowerStatusAdapter,
        copyPowerStatusConnected,
        copyPowerStatusExternalDisplay,
        copyPowerStatusGuardMissing,
        copyPowerStatusGuardReady,
        copyPowerStatusHelper,
        copyPowerStatusHelperHint,
        copyPowerStatusLowPowerMode,
        copyPowerStatusNoExternalDisplay,
        copyPowerStatusNotConnected,
        copyStateCancel,
        copyStateComponentToolbarDefaultDisabled,
        copyStateComponentToolbarDefaultFocused,
        copyStateComponentToolbarDefaultHover,
        copyStateComponentToolbarDefaultPressed,
        copyStateDisabled,
        copyStateEmpty,
        copyStateError,
        copyStateLabelError,
        copyStateLabelInfo,
        copyStateLabelSuccess,
        copyStateLabelWarning,
        copyStateLoading,
        copyStateNormal,
        copyStateRetry,
        copyStateSuccess,
        copyStateWarning,
        copyStatusItemCharging,
        copyStatusItemDefault,
        copyStatusItemDisabled,
        copyStatusItemHelperError,
        copyStatusItemHelperIdentityMismatch,
        copyStatusItemHelperOutdated,
        copyStatusItemHelperSafeMode,
        copyStatusItemHelperUntrusted,
        copyStatusItemIdlePrevented,
        copyStatusItemLidPrevented,
        copyStatusItemLowBattery,
        copyToastError,
        copyToastSuccess,
        copyToastWarning,
        copyTopShelfActionClearAll,
        copyTopShelfActionCopy,
        copyTopShelfActionHideToolbar,
        copyTopShelfActionMarkup,
        copyTopShelfActionOpenFolder,
        copyTopShelfActionPreview,
        copyTopShelfActionRemove,
        copyTopShelfActionRemoveFromShelf,
        copyTopShelfActionShowToolbar,
        copyTopShelfActionWorkspace,
        copyTopShelfClear,
        copyTopShelfEmpty,
        copyTopShelfEnabled,
        copyTopShelfErrorCopy,
        copyTopShelfErrorDirectory,
        copyTopShelfErrorMarkup,
        copyTopShelfErrorMove,
        copyTopShelfErrorOpen,
        copyTopShelfErrorRestore,
        copyTopShelfErrorTakeover,
        copyTopShelfNone,
        copyTopShelfOpenFolder,
        copyTopShelfPendingNotice,
        copyTopShelfShow,
        copyTopShelfSounds,
        copyTopShelfStateCancel,
        copyTopShelfStateDragToApp,
        copyTopShelfStateDragToFolder,
        copyTopShelfStateDragToTrash,
        copyTopShelfStateHover,
        copyTopShelfStateRightClickMenu,
        copyTopShelfStatus,
        copyTopShelfTakeOver,
        copyTopShelfTitle,
        copyTrayActionDisplayOff,
        copyTrayActionQuit,
        copyTrayActionSettings,
        copyTrayActionShowShelf,
        copyTrayActionSleepNow,
        copyTrayTooltipBattery,
        copyTrayTooltipCharging,
        copyTrayTooltipHelperError,
        copyTrayTooltipIdlePrevented,
        copyTrayTooltipLidPrevented,
        copyTrayTooltipLowBattery,
        copyTrayTooltipNormal,
    ]
}

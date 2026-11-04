import Foundation

/// 剪切板内容的显示类型。类型不再决定主列表结构，只用于筛选。
enum ClipboardWorkspaceKind: String, CaseIterable, Identifiable {
    case files
    case text
    case images
    case screenshots

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .files:
            ContractCopy.copyHubFilesFilterFiles.text(for: language)
        case .text:
            ContractCopy.copyHubFilesFilterText.text(for: language)
        case .images:
            ContractCopy.copyHubFilesKindImage.text(for: language)
        case .screenshots:
            ContractCopy.copyHubFilesFilterScreenshots.text(for: language)
        }
    }

    var symbol: String {
        switch self {
        case .files: "folder"
        case .text: "text.alignleft"
        case .images: "photo"
        case .screenshots: "camera.viewfinder"
        }
    }
}

/// 类型筛选器。默认显示全部类型。
enum ClipboardWorkspaceFilter: String, CaseIterable, Identifiable {
    case all
    case files
    case text
    case images
    case screenshots

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .all:
            ContractCopy.copyClipboardFilterAll.text(for: language)
        case .files:
            ClipboardWorkspaceKind.files.title(for: language)
        case .text:
            ClipboardWorkspaceKind.text.title(for: language)
        case .images:
            ClipboardWorkspaceKind.images.title(for: language)
        case .screenshots:
            ClipboardWorkspaceKind.screenshots.title(for: language)
        }
    }

    func includes(_ kind: ClipboardWorkspaceKind) -> Bool {
        switch self {
        case .all:
            true
        case .files:
            kind == .files
        case .text:
            kind == .text
        case .images:
            kind == .images
        case .screenshots:
            kind == .screenshots
        }
    }
}

/// 一条可以显示在列表和详情区的剪切板内容。
enum ClipboardWorkspaceItem: Identifiable {
    case clip(ClipItem)
    case screenshot(ShelfItem)

    var id: String {
        switch self {
        case .clip(let item):
            "clip:\(item.id)"
        case .screenshot(let item):
            "screenshot:\(item.path)"
        }
    }

    var kind: ClipboardWorkspaceKind {
        switch self {
        case .clip(let item):
            switch item.kind {
            case .files:
                .files
            case .image:
                .images
            case .text, .link, .color:
                .text
            default:
                .text
            }
        case .screenshot:
            .screenshots
        }
    }

    var pinned: Bool {
        switch self {
        case .clip(let item): item.pinned
        case .screenshot: false
        }
    }

    var filePath: String {
        switch self {
        case .clip(let item): item.filePath
        case .screenshot(let item): item.path
        }
    }

    var createdAtEpochSeconds: Int64 {
        switch self {
        case .clip(let item): item.createdAtEpochSeconds
        case .screenshot(let item): item.addedAtEpochSeconds
        }
    }

    var byteSize: Int64 {
        switch self {
        case .clip(let item): item.byteSize
        case .screenshot(let item):
            (try? URL(fileURLWithPath: item.path)
                .resourceValues(forKeys: [.fileSizeKey])
                .fileSize)
                .map(Int64.init) ?? 0
        }
    }

    var clipItem: ClipItem? {
        guard case .clip(let item) = self else { return nil }
        return item
    }

    var screenshotItem: ShelfItem? {
        guard case .screenshot(let item) = self else { return nil }
        return item
    }

    /// 详情区的主操作名称。剪切板内容粘贴，截图复制。
    func primaryTitle(for language: AppLanguage) -> String {
        switch self {
        case .clip:
            ContractCopy.copyClipboardActionPaste.text(for: language)
        case .screenshot:
            ContractCopy.copyTopShelfActionCopy.text(for: language)
        }
    }

    /// 更多菜单和右键菜单共用的次要动作顺序。
    var secondaryActions: [ClipboardWorkspaceAction] {
        switch self {
        case .clip:
            [.copy, .togglePin, .saveToWorkspace, .remove]
        case .screenshot:
            [.copy, .saveToWorkspace, .preview, .markup, .remove]
        }
    }

    func actionTitle(_ action: ClipboardWorkspaceAction, language: AppLanguage) -> String {
        switch action {
        case .copy:
            ContractCopy.copyTopShelfActionCopy.text(for: language)
        case .togglePin:
            pinned
                ? ContractCopy.copyClipboardActionUnpin.text(for: language)
                : ContractCopy.copyClipboardActionPin.text(for: language)
        case .saveToWorkspace:
            ContractCopy.copyClipboardActionWorkspace.text(for: language)
        case .remove:
            ContractCopy.copyClipboardActionRemove.text(for: language)
        case .preview:
            ContractCopy.copyTopShelfActionPreview.text(for: language)
        case .markup:
            ContractCopy.copyTopShelfActionMarkup.text(for: language)
        }
    }

    /// VoiceOver 读出的补充信息。标题单独作为标签，这里只放属性和状态。
    func accessibilityValue(for language: AppLanguage) -> String {
        var values = [
            kind.title(for: language),
            metadata(for: language),
            ClipboardWorkspaceTime.text(createdAtEpochSeconds, language: language),
        ]
        if pinned {
            values.append(ContractCopy.copyClipboardActionPin.text(for: language))
        }
        return values.joined(separator: "，")
    }

    /// VoiceOver 读出主操作和全部次要动作。
    func accessibilityHint(for language: AppLanguage) -> String {
        let primary = primaryTitle(for: language)
        let more = ContractCopy.copyHubFilesActionMore.text(for: language)
        let secondary = secondaryActions
            .map { actionTitle($0, language: language) }
            .joined(separator: "、")
        return "\(primary)；\(more)：\(secondary)"
    }

    /// 详情正文。文件使用完整路径列表，图片使用 OCR 文本，其余使用原正文。
    var detailText: String {
        guard let clipItem else { return "" }
        return clipItem.text
    }

    var filePaths: [String] {
        guard let clipItem, clipItem.kind == .files else { return [] }
        let lines = clipItem.text
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        return lines.isEmpty && !clipItem.filePath.isEmpty ? [clipItem.filePath] : lines
    }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .clip(let item):
            switch item.kind {
            case .files:
                let paths = filePaths
                let first = paths.first.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? URL(fileURLWithPath: item.filePath).lastPathComponent
                guard paths.count > 1 else { return first }
                return "\(first) +\(paths.count - 1)"
            case .image:
                let ocr = Self.firstLine(item.text)
                return ocr.isEmpty ? URL(fileURLWithPath: item.filePath).lastPathComponent : ocr
            case .text, .link, .color:
                let value = Self.firstLine(item.text)
                return value.isEmpty ? ContractCopy.copyClipboardEmpty.text(for: language) : value
            default:
                let value = Self.firstLine(item.text)
                return value.isEmpty ? ContractCopy.copyClipboardEmpty.text(for: language) : value
            }
        case .screenshot(let item):
            return URL(fileURLWithPath: item.path).lastPathComponent
        }
    }

    /// 列表行里的一行次要信息。
    func metadata(for language: AppLanguage) -> String {
        let source: String
        switch self {
        case .clip(let item):
            source = Self.sourceName(item.sourceBundleId, language: language)
        case .screenshot:
            source = ClipboardWorkspaceKind.screenshots.title(for: language)
        }
        return [source, sizeText].compactMap { $0 }.joined(separator: " · ")
    }

    var sizeText: String? {
        guard byteSize > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    func matches(_ query: String, language: AppLanguage) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let haystack = [
            kind.title(for: language),
            title(for: language),
            metadata(for: language),
            detailText,
            filePath,
        ].joined(separator: "\n")
        return haystack.localizedCaseInsensitiveContains(needle)
    }

    /// bundle id 的最后一段作为来源短名。
    static func sourceName(_ bundleID: String, language: AppLanguage) -> String {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ContractCopy.copyHubFilesStateLocal.text(for: language)
        }
        guard let last = trimmed.split(separator: ".").last else { return trimmed }
        return String(last).prefix(1).uppercased() + String(String(last).dropFirst())
    }

    private static func firstLine(_ text: String) -> String {
        text
            .split(separator: "\n", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// 时间列表里的一个分组。
enum ClipboardWorkspaceSectionKind: String, Identifiable {
    case pinned
    case today
    case yesterday
    case earlier

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .pinned:
            ContractCopy.copyClipboardGroupPinned.text(for: language)
        case .today:
            ContractCopy.copyClipboardGroupToday.text(for: language)
        case .yesterday:
            ContractCopy.copyClipboardGroupYesterday.text(for: language)
        case .earlier:
            ContractCopy.copyClipboardGroupEarlier.text(for: language)
        }
    }
}

struct ClipboardWorkspaceSection: Identifiable {
    let kind: ClipboardWorkspaceSectionKind
    let items: [ClipboardWorkspaceItem]

    var id: ClipboardWorkspaceSectionKind { kind }
}

/// 把剪切板历史与截图库合并成按时间排序的统一列表。
struct ClipboardWorkspaceData {
    let clips: [ClipItem]
    let screenshots: [ShelfItem]

    func allItems(language: AppLanguage) -> [ClipboardWorkspaceItem] {
        let clips = clips
            .map(ClipboardWorkspaceItem.clip)
            .filter { $0.title(for: language) != "" }
        let screenshots = screenshots.map(ClipboardWorkspaceItem.screenshot)
        return (clips + screenshots).sorted {
            if $0.createdAtEpochSeconds == $1.createdAtEpochSeconds {
                return $0.id < $1.id
            }
            return $0.createdAtEpochSeconds > $1.createdAtEpochSeconds
        }
    }

    func items(
        query: String,
        filter: ClipboardWorkspaceFilter,
        language: AppLanguage
    ) -> [ClipboardWorkspaceItem] {
        allItems(language: language).filter {
            filter.includes($0.kind) && $0.matches(query, language: language)
        }
    }

    func sections(
        query: String,
        filter: ClipboardWorkspaceFilter,
        language: AppLanguage,
        now: Date = .now
    ) -> [ClipboardWorkspaceSection] {
        let visible = items(query: query, filter: filter, language: language)
        let pinned = visible.filter(\.pinned)
        let unpinned = visible.filter { !$0.pinned }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        func sectionKind(for item: ClipboardWorkspaceItem) -> ClipboardWorkspaceSectionKind {
            let date = Date(timeIntervalSince1970: TimeInterval(item.createdAtEpochSeconds))
            let itemStart = calendar.startOfDay(for: date)
            let dayOffset = calendar.dateComponents([.day], from: itemStart, to: todayStart).day ?? 0
            switch dayOffset {
            case 0: return .today
            case 1: return .yesterday
            default: return .earlier
            }
        }

        let today = unpinned.filter { sectionKind(for: $0) == .today }
        let yesterday = unpinned.filter { sectionKind(for: $0) == .yesterday }
        let earlier = unpinned.filter { sectionKind(for: $0) == .earlier }

        var sections: [ClipboardWorkspaceSection] = []
        if !pinned.isEmpty {
            sections.append(ClipboardWorkspaceSection(kind: .pinned, items: pinned))
        }
        if !today.isEmpty {
            sections.append(ClipboardWorkspaceSection(kind: .today, items: today))
        }
        if !yesterday.isEmpty {
            sections.append(ClipboardWorkspaceSection(kind: .yesterday, items: yesterday))
        }
        if !earlier.isEmpty {
            sections.append(ClipboardWorkspaceSection(kind: .earlier, items: earlier))
        }
        return sections
    }
}

/// 条目的次要动作。
enum ClipboardWorkspaceAction: Equatable {
    case copy
    case togglePin
    case saveToWorkspace
    case remove
    case preview
    case markup

    var symbol: String {
        switch self {
        case .copy: "doc.on.doc"
        case .togglePin: "pin"
        case .saveToWorkspace: "tray.and.arrow.down"
        case .remove: "trash"
        case .preview: "eye"
        case .markup: "pencil.tip.crop.circle"
        }
    }
}

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 一次渲染要用的只读文件区快照。
private struct FileAreaSnapshot {
    let items: [FileAreaItem]
    let filteredItems: [FileAreaItem]
    let selectedItem: FileAreaItem?
    let quietItems: [FileAreaItem]
    let filterCounts: [FileAreaFilterChoice: Int]
    let activeTransferCount: Int
}

/// 文件区的键盘顺序。焦点卡排在网格之前，网格严格按行优先。
enum FileAreaKeyboardNavigation {
    static func order(selectedID: String?, quietIDs: [String]) -> [String] {
        guard let selectedID else { return quietIDs }
        return [selectedID] + quietIDs
    }

    static func destination(
        _ direction: MoveCommandDirection,
        from currentID: String,
        order: [String],
        columns: Int = FileAreaMetrics.quietColumns
    ) -> String? {
        guard let index = order.firstIndex(of: currentID) else { return nil }
        let nextIndex: Int?
        switch direction {
        case .left:
            nextIndex = index > 0 ? index - 1 : nil
        case .right:
            nextIndex = index + 1 < order.count ? index + 1 : nil
        case .up:
            if index == 0 {
                nextIndex = nil
            } else if index <= columns {
                nextIndex = 0
            } else {
                nextIndex = index - columns
            }
        case .down:
            if index == 0 {
                nextIndex = order.count > 1 ? 1 : nil
            } else {
                let candidate = index + columns
                nextIndex = candidate < order.count ? candidate : nil
            }
        @unknown default:
            nextIndex = nil
        }
        guard let nextIndex else { return nil }
        return order[nextIndex]
    }

    static func itemAfterRemoval(_ itemID: String, order: [String]) -> String? {
        guard let index = order.firstIndex(of: itemID) else { return nil }
        if index + 1 < order.count { return order[index + 1] }
        if index > 0 { return order[index - 1] }
        return nil
    }
}

/// 统一文件区。
///
/// 一级导航里只有一个文件工作区。截图、工作区文件和传输状态都从同一份
/// `FileAreaItem` 投影读取。详细操作只占用一个焦点位，其余内容退到四列安静网格。
struct FilesTabView: View {
    let shelf: ShelfRuntime
    let workspace: WorkspaceRuntime
    let transfer: WorkspaceTransferRuntime
    let autoNaming: AutoNamingRuntime
    var modelSetup: ModelSetupRuntime? = nil
    let policy: FileNamingPolicy
    let language: AppLanguage
    let searchText: String
    var requestedFilter: FileAreaFilterChoice?
    var onConsumeRequestedFilter: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.fileAreaReduceMotionOverride) private var reduceMotionOverride
    @State private var selection: FileAreaFilterChoice = .all
    @State private var selectedItemID: String?
    @State private var dropTargeted = false
    @State private var keyboardMenuRequestID: String?
    @State private var keyboardMenuRequestNonce = 0
    @State private var showModelSetup = false
    @FocusState private var keyboardFocusedItemID: String?

    var body: some View {
        let snapshot = makeSnapshot()
        return Group {
            if autoNaming.stage == .idle {
                fileArea(snapshot)
            } else {
                AutoNamingPreviewView(
                    runtime: autoNaming,
                    language: language,
                    modelSetup: modelSetup
                )
            }
        }
        // 内边距由内容列给，这里不再加一层。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            intake(providers)
        }
        .onAppear(perform: consumeRequestedFilter)
        .task { await modelSetup?.refresh() }
        .onChange(of: requestedFilter) { _, _ in consumeRequestedFilter() }
        .onChange(of: snapshot.filteredItems.map(\.id)) { _, ids in
            guard let firstID = ids.first else {
                selectedItemID = nil
                keyboardFocusedItemID = nil
                return
            }
            if selectedItemID.map({ ids.contains($0) }) != true {
                selectedItemID = firstID
            }
            if let focused = keyboardFocusedItemID, !ids.contains(focused) {
                keyboardFocusedItemID = firstID
            }
        }
        .sheet(isPresented: $showModelSetup) {
            if let modelSetup {
                VStack(alignment: .trailing, spacing: MacTheme.space3) {
                    ModelSetupInlineCard(
                        model: modelSetup,
                        language: language,
                        purpose: .naming
                    )
                    MacButton(title: ContractCopy.copyHubActionDone.text(for: language)) {
                        showModelSetup = false
                    }
                }
                .padding(MacTheme.space4)
                .frame(width: 620)
                .background(MacTheme.canvas)
            }
        }
        .background {
            // 空状态和无匹配也遵守同一组快捷键。
            HStack {
                Button("") { chooseFiles() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("") { showNewTextDialog() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func fileArea(_ snapshot: FileAreaSnapshot) -> some View {
        if snapshot.items.isEmpty {
            FileEmptyStateView(
                state: .empty,
                language: language,
                onImport: chooseFiles,
                onNewText: showNewTextDialog,
                onClearFilter: clearFilters
            )
            .frame(maxHeight: .infinity)
        } else if snapshot.filteredItems.isEmpty {
            FileEmptyStateView(
                state: .noMatch,
                language: language,
                onImport: chooseFiles,
                onNewText: showNewTextDialog,
                onClearFilter: clearFilters
            )
            .frame(maxHeight: .infinity)
        } else {
            populatedArea(snapshot)
        }
    }

    private func populatedArea(_ snapshot: FileAreaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: FileAreaMetrics.toolbarGap) {
            utilityBar(snapshot)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let selectedItem = snapshot.selectedItem {
                        FileFocusCardView(
                            item: selectedItem,
                            url: url(for: selectedItem),
                            language: language,
                            transferTask: transfer.task(for: selectedItem.itemId),
                            keyboardFocused: keyboardFocusedItemID == selectedItem.id,
                            keyboardMenuRequested: keyboardMenuRequestID == selectedItem.id,
                            keyboardMenuRequestNonce: keyboardMenuRequestNonce,
                            onKeyboardMenuDismissed: {
                                restoreKeyboardFocus(to: selectedItem.id)
                            }
                        ) { action in
                            perform(action, on: selectedItem)
                        }
                        .id(selectedItem.id)
                        .transition(.opacity)
                        .contentTransition(.opacity)
                        .animation(focusAnimation, value: selectedItem.id)
                        .focusable { isFocused in
                            updateKeyboardFocus(isFocused, id: selectedItem.id)
                        }
                        .focused($keyboardFocusedItemID, equals: selectedItem.id)
                        .onMoveCommand { direction in
                            moveKeyboardFocus(
                                direction,
                                from: selectedItem.id,
                                snapshot: snapshot
                            )
                        }
                        .onKeyPress(.leftArrow) {
                            moveKeyboardFocus(.left, from: selectedItem.id, snapshot: snapshot)
                            return .handled
                        }
                        .onKeyPress(.rightArrow) {
                            moveKeyboardFocus(.right, from: selectedItem.id, snapshot: snapshot)
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            moveKeyboardFocus(.up, from: selectedItem.id, snapshot: snapshot)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            moveKeyboardFocus(.down, from: selectedItem.id, snapshot: snapshot)
                            return .handled
                        }
                        .onKeyPress { press in
                            handleKeyPress(press, item: selectedItem, snapshot: snapshot)
                        }

                        if !snapshot.quietItems.isEmpty {
                            LazyVGrid(columns: quietColumns, alignment: .leading, spacing: FileAreaMetrics.quietGap) {
                                ForEach(snapshot.quietItems, id: \.id) { item in
                                    FileQuietTileView(
                                        item: item,
                                        url: url(for: item),
                                        language: language,
                                        transferTask: transfer.task(for: item.itemId),
                                        keyboardFocused: keyboardFocusedItemID == item.id,
                                        keyboardMenuRequested: keyboardMenuRequestID == item.id,
                                        keyboardMenuRequestNonce: keyboardMenuRequestNonce,
                                        onKeyboardMenuDismissed: {
                                            restoreKeyboardFocus(to: item.id)
                                        },
                                        onSelect: { select(item.id) }
                                    ) { action in
                                        perform(action, on: item)
                                    }
                                    .focusable { isFocused in
                                        updateKeyboardFocus(isFocused, id: item.id)
                                    }
                                    .focused($keyboardFocusedItemID, equals: item.id)
                                    .onMoveCommand { direction in
                                        moveKeyboardFocus(direction, from: item.id, snapshot: snapshot)
                                    }
                                    .onKeyPress(.leftArrow) {
                                        moveKeyboardFocus(.left, from: item.id, snapshot: snapshot)
                                        return .handled
                                    }
                                    .onKeyPress(.rightArrow) {
                                        moveKeyboardFocus(.right, from: item.id, snapshot: snapshot)
                                        return .handled
                                    }
                                    .onKeyPress(.upArrow) {
                                        moveKeyboardFocus(.up, from: item.id, snapshot: snapshot)
                                        return .handled
                                    }
                                    .onKeyPress(.downArrow) {
                                        moveKeyboardFocus(.down, from: item.id, snapshot: snapshot)
                                        return .handled
                                    }
                                    .onKeyPress { press in
                                        handleKeyPress(press, item: item, snapshot: snapshot)
                                    }
                                }
                            }
                            .padding(.top, FileAreaMetrics.stageGap)
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: FileAreaMetrics.areaHeight, alignment: .top)
        .background {
            FileAreaArrowKeyMonitor(
                isActive: keyboardFocusedItemID != nil && keyboardMenuRequestID == nil
            ) { direction in
                guard let focused = keyboardFocusedItemID else { return }
                moveKeyboardFocus(direction, from: focused, snapshot: snapshot)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice {
                HStack(spacing: MacTheme.space2) {
                    MacAlert(message: notice, kind: noticeKind)
                    Button {
                        workspace.clearMessages()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(
                                MacTheme.elevated.opacity(0.9),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ContractCopy.copyHubFilesActionDismiss.text(for: language))
                }
                .padding(.top, MacTheme.space2)
                .transition(.opacity)
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: FileAreaMetrics.contentCornerRadius, style: .continuous)
                    .strokeBorder(MacTheme.brand, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(
                        MacTheme.brand.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: FileAreaMetrics.contentCornerRadius, style: .continuous)
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private func utilityBar(_ snapshot: FileAreaSnapshot) -> some View {
        HStack(spacing: 10) {
            FileFilterMenuView(
                selection: selection,
                counts: snapshot.filterCounts,
                language: language
            ) { option in
                selection = option
            }

            Text("\(snapshot.filteredItems.count) \(ContractCopy.copyHubFilesCountItems.text(for: language))")
                .font(.system(size: 9))
                .foregroundStyle(MacTheme.textSecondary)

            if snapshot.activeTransferCount > 0 {
                HStack(spacing: 5) {
                    Circle()
                        .fill(MacTheme.brand)
                        .frame(width: 5, height: 5)
                    Text("\(snapshot.activeTransferCount) \(ContractCopy.copyHubFilesStatusActive.text(for: language))")
                        .font(.system(size: 9))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 0)
            addMenu
        }
        .frame(height: FileAreaMetrics.toolbarHeight)
    }

    private var addMenu: some View {
        Menu {
            Button {
                chooseFiles()
            } label: {
                Label(ContractCopy.copyHubFilesActionImport.text(for: language), systemImage: "folder.badge.plus")
            }
            Button {
                showNewTextDialog()
            } label: {
                Label(ContractCopy.copyHubFilesActionNewText.text(for: language), systemImage: "text.badge.plus")
            }
            Divider()
            Button {
                chooseAutoNameFiles()
            } label: {
                Label(ContractCopy.copyAutoNamingActionAutoName.text(for: language), systemImage: "wand.and.stars")
            }
            .disabled(autoNaming.stage != .idle || autoNaming.busy)
            Button {
                workspace.sweep()
            } label: {
                Label(ContractCopy.copyHubFilesActionSweep.text(for: language), systemImage: "clock.arrow.circlepath")
            }
            .disabled(workspace.entries.isEmpty)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(MacTheme.textPrimary)
                .frame(width: FileAreaMetrics.toolbarHeight, height: FileAreaMetrics.toolbarHeight)
                .background(
                    MacTheme.elevated.opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(ContractCopy.copyHubFilesActionAdd.text(for: language))
    }

    /// 一次渲染只做一次投影、筛选和计数。文件区最多几十条，但不应在每次子视图取值时重算。
    private func makeSnapshot() -> FileAreaSnapshot {
        let items = projectionItems()
        let filtered = FileAreaProjection.shared
            .filter(items: items, filter: selection.filter)
            .filter {
                FileAreaPresentation.matches(item: $0, query: searchText, language: language)
            }
        let selected = selectedItemID.flatMap { id in
            filtered.first(where: { $0.id == id })
        } ?? filtered.first
        let quiet = selected.map { selected in
            filtered.filter { $0.id != selected.id }
        } ?? filtered
        let counts = Dictionary(uniqueKeysWithValues: FileAreaFilterChoice.allCases.map { option in
            (option, FileAreaProjection.shared.filter(items: items, filter: option.filter).count)
        })
        let activeTaskIDs = transfer.activeEntryIDs
        let itemFallbackCount = items.count { item in
            guard item.availability == FileAreaAvailability.remote ||
                    item.availability == FileAreaAvailability.fetching
            else { return false }
            return transfer.task(for: item.itemId) == nil
        }
        let activeTransfers = activeTaskIDs.count + itemFallbackCount
        return FileAreaSnapshot(
            items: items,
            filteredItems: filtered,
            selectedItem: selected,
            quietItems: quiet,
            filterCounts: counts,
            activeTransferCount: activeTransfers
        )
    }

    /// 投影保留两个底层来源。页面只在渲染时拼接，不复制持久化模型。
    private func projectionItems() -> [FileAreaItem] {
        let existingScreenshots = shelf.items.compactMap { item -> String? in
            FileManager.default.fileExists(atPath: item.path) ? item.path : nil
        }
        return FileAreaProjection.shared.build(
            shelfItems: shelf.items,
            workspaceEntries: workspace.entries,
            existingScreenshotPaths: existingScreenshots
        )
    }

    private var quietColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 72), spacing: FileAreaMetrics.quietGap, alignment: .top),
            count: FileAreaMetrics.quietColumns
        )
    }

    private var reduceMotion: Bool {
        reduceMotionOverride ?? systemReduceMotion
    }

    private var focusAnimation: Animation {
        let duration = reduceMotion
            ? HubMotion.fileFocusSwitchReduced
            : HubMotion.fileFocusSwitch
        return .easeOut(duration: duration)
    }

    private var notice: String? {
        if let error = workspace.errorMessage {
            return error.text(for: language)
        }
        if let info = workspace.infoMessage {
            return info.text(for: language)
        }
        return nil
    }

    private var noticeKind: MacAlertKind {
        workspace.errorMessage == nil ? .info : .error
    }

    private func select(_ id: String) {
        selectedItemID = id
        keyboardMenuRequestID = nil
    }

    private func updateKeyboardFocus(_ isFocused: Bool, id: String) {
        if isFocused {
            keyboardFocusedItemID = id
            return
        }
        Task { @MainActor in
            await Task.yield()
            if keyboardFocusedItemID == id { keyboardFocusedItemID = nil }
        }
    }

    private func restoreKeyboardFocus(to id: String) {
        keyboardMenuRequestID = nil
        keyboardFocusedItemID = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            keyboardFocusedItemID = id
        }
    }

    /// 空格把键盘焦点对应的安静格子提升为焦点卡；同一个 id 让焦点不丢失。
    private func promoteToFocus(_ item: FileAreaItem, snapshot: FileAreaSnapshot) {
        guard snapshot.quietItems.contains(where: { $0.id == item.id }) else { return }
        selectedItemID = item.id
        keyboardMenuRequestID = nil
        // 等焦点卡换进同一 id，再把键盘焦点接过去。
        Task { @MainActor in
            await Task.yield()
            keyboardFocusedItemID = item.id
        }
    }

    private func moveKeyboardFocus(
        _ direction: MoveCommandDirection,
        from currentID: String,
        snapshot: FileAreaSnapshot
    ) {
        let order = focusOrder(snapshot)
        keyboardFocusedItemID = FileAreaKeyboardNavigation.destination(
            direction,
            from: currentID,
            order: order
        )
    }

    /// 焦点位永远排在网格之前，网格按行优先顺序排列。
    private func focusOrder(_ snapshot: FileAreaSnapshot) -> [String] {
        FileAreaKeyboardNavigation.order(
            selectedID: snapshot.selectedItem?.id,
            quietIDs: snapshot.quietItems.map(\.id)
        )
    }

    private func handleKeyPress(
        _ press: KeyPress,
        item: FileAreaItem,
        snapshot: FileAreaSnapshot
    ) -> KeyPress.Result {
        let command = press.modifiers.contains(.command)
        if press.key == .leftArrow {
            moveKeyboardFocus(.left, from: item.id, snapshot: snapshot)
            return .handled
        }
        if press.key == .rightArrow {
            moveKeyboardFocus(.right, from: item.id, snapshot: snapshot)
            return .handled
        }
        if press.key == .upArrow {
            moveKeyboardFocus(.up, from: item.id, snapshot: snapshot)
            return .handled
        }
        if press.key == .downArrow {
            moveKeyboardFocus(.down, from: item.id, snapshot: snapshot)
            return .handled
        }
        if command && press.characters.lowercased() == "c" {
            if item.capabilities.canCopy {
                perform(.copy, on: item)
                return .handled
            }
            if item.capabilities.canCopyText {
                perform(.copyText, on: item)
                return .handled
            }
            return .ignored
        }
        if command && (press.key == .delete || press.key == .deleteForward) {
            guard item.capabilities.canRemove else { return .ignored }
            let nextID = FileAreaKeyboardNavigation.itemAfterRemoval(
                item.id,
                order: focusOrder(snapshot)
            )
            perform(.remove, on: item)
            keyboardFocusedItemID = nextID
            return .handled
        }
        if press.key == .return {
            if item.capabilities.canOpen {
                perform(.open, on: item)
                return .handled
            }
            if let action = FileAreaPresentation.quickAction(
                for: item,
                task: transfer.task(for: item.itemId)
            ) {
                perform(action, on: item)
                return .handled
            }
            return .ignored
        }
        if press.key == .space {
            guard snapshot.quietItems.contains(where: { $0.id == item.id }) else {
                return .ignored
            }
            promoteToFocus(item, snapshot: snapshot)
            return .handled
        }
        if press.characters.lowercased() == "m",
           !press.modifiers.contains(.command),
           !press.modifiers.contains(.control),
           !press.modifiers.contains(.option) {
            keyboardMenuRequestID = item.id
            keyboardMenuRequestNonce += 1
            return .handled
        }
        return .ignored
    }

    private func clearFilters() {
        selection = .all
        selectedItemID = nil
        keyboardFocusedItemID = nil
        keyboardMenuRequestID = nil
    }

    private func consumeRequestedFilter() {
        guard let requestedFilter else { return }
        selection = requestedFilter
        selectedItemID = nil
        keyboardFocusedItemID = nil
        keyboardMenuRequestID = nil
        onConsumeRequestedFilter()
    }

    private func url(for item: FileAreaItem) -> URL? {
        if item.origin == FileAreaOrigin.screenshot {
            let url = URL(fileURLWithPath: item.itemId)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return workspace.contentURL(item.itemId)
    }

    private func perform(_ action: FileAreaAction, on item: FileAreaItem) {
        switch action {
        case .open:
            if item.origin == FileAreaOrigin.screenshot {
                shelf.openItem(shelfItem(item))
            } else {
                workspace.open(item.itemId)
            }
        case .copy:
            if item.origin == FileAreaOrigin.screenshot {
                shelf.copyItem(shelfItem(item))
            } else {
                workspace.copy(item.itemId)
            }
        case .copyText:
            workspace.copyText(item.itemId)
        case .markup:
            shelf.markupItem(shelfItem(item))
        case .saveToWorkspace:
            _ = workspace.save(filesAt: [item.itemId])
        case .reveal:
            workspace.reveal(item.itemId)
        case .pin:
            workspace.togglePin(item.itemId)
        case .download:
            transfer.beginDownload(item.itemId)
        case .cancelTransfer:
            transfer.cancel(item.itemId)
        case .retry:
            transfer.retry(item.itemId)
        case .remove:
            transfer.discard(item.itemId)
            if item.origin == FileAreaOrigin.screenshot {
                shelf.removeItem(shelfItem(item))
            } else {
                workspace.remove(item.itemId)
            }
        }
    }

    private func shelfItem(_ item: FileAreaItem) -> ShelfItem {
        ShelfItem(path: item.itemId, addedAtEpochSeconds: item.createdAtEpochSeconds)
    }

    /// 接收拖进来的文件。
    ///
    /// 只取 `fileURL`。读取在后台，读完回主线程放入。
    /// 不等读取结果：等待会卡住主线程的绘图。
    private func intake(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        var accepted = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                guard let url = FilesTabView.fileURL(from: item) else { return }
                Task { @MainActor in
                    workspace.intake(urls: [url])
                }
            }
        }
        return accepted
    }

    /// 从拖放项里取出文件地址。系统两种都给过：URL 与 data。
    private nonisolated static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        return nil
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        workspace.intake(urls: panel.urls)
    }

    private func chooseAutoNameFiles() {
        if let modelSetup, !modelSetup.isAIReady {
            showModelSetup = true
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        Task {
            await autoNaming.analyze(urls: panel.urls, policy: policy)
        }
    }

    /// 使用原生编辑器输入临时文本。保存后进入工作区，正文不再复制到其它位置。
    private func showNewTextDialog() {
        let alert = NSAlert()
        alert.messageText = ContractCopy.copyHubFilesActionNewText.text(for: language)
        alert.informativeText = ContractCopy.copyHubFilesEmptyHint.text(for: language)
        alert.addButton(withTitle: ContractCopy.copyHubFilesActionNewText.text(for: language))
        alert.addButton(withTitle: ContractCopy.copyStateCancel.text(for: language))

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = workspace.save(text: textView.string)
    }
}

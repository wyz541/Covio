#if DEBUG
import AppKit
import SwiftUI

/// 文件区的确定性调试画面。只用于本地视觉验收，不参与发布构建。
struct FileAreaShowcaseView: View {
    let contentWidth: CGFloat
    let language: AppLanguage

    @State private var selection: FileAreaFilterChoice = .all
    @State private var selectedID = "text"

    var body: some View {
        VStack(alignment: .leading, spacing: FileAreaMetrics.toolbarGap) {
            HStack(spacing: 10) {
                FileFilterMenuView(
                    selection: selection,
                    counts: Dictionary(uniqueKeysWithValues: FileAreaFilterChoice.allCases.map { ($0, count(for: $0)) }),
                    language: language
                ) { choice in
                    selection = choice
                    selectedID = filteredItems.first?.id ?? ""
                }
                Text("\(filteredItems.count) \(ContractCopy.copyHubFilesCountItems.text(for: language))")
                    .font(.system(size: 9))
                    .foregroundStyle(MacTheme.textSecondary)
                HStack(spacing: 5) {
                    Circle().fill(MacTheme.brand).frame(width: 5, height: 5)
                    Text("\(activeTransferCount) \(ContractCopy.copyHubFilesStatusActive.text(for: language))")
                        .font(.system(size: 9))
                        .foregroundStyle(MacTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background(
                        MacTheme.elevated.opacity(0.72),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
            .frame(height: FileAreaMetrics.toolbarHeight)

            if let selectedItem {
                FileFocusCardView(
                    item: selectedItem,
                    url: nil,
                    language: language,
                    transferTask: transferTask(for: selectedItem),
                    keyboardFocused: true,
                    onAction: { _ in }
                )
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 72), spacing: FileAreaMetrics.quietGap, alignment: .top),
                    count: FileAreaMetrics.quietColumns
                ),
                alignment: .leading,
                spacing: FileAreaMetrics.quietGap
            ) {
                ForEach(quietItems, id: \.id) { item in
                    FileQuietTileView(
                        item: item,
                        url: nil,
                        language: language,
                        transferTask: transferTask(for: item),
                        onSelect: { selectedID = item.id },
                        onAction: { _ in }
                    )
                }
            }
            .padding(.top, FileAreaMetrics.stageGap)
        }
        .padding(.horizontal, 24)
        .frame(width: contentWidth + 48, height: FileAreaMetrics.areaHeight, alignment: .topLeading)
        .background(Color(red: 0.68, green: 0.64, blue: 0.71))
    }

    private func transferTask(for item: FileAreaItem) -> WorkspaceTransferTask? {
        switch item.id {
        case "remote":
            WorkspaceTransferTask(
                entryId: item.itemId,
                direction: .download,
                peerDeviceId: "iPhone",
                totalBytes: item.byteSize,
                phase: .waiting,
                transferredBytes: 0,
                failure: nil
            )
        case "fetching":
            WorkspaceTransferTask(
                entryId: item.itemId,
                direction: .download,
                peerDeviceId: "iPad",
                totalBytes: item.byteSize,
                phase: .transferring,
                transferredBytes: item.byteSize * 62 / 100,
                failure: nil
            )
        case "failed":
            WorkspaceTransferTask(
                entryId: item.itemId,
                direction: .download,
                peerDeviceId: "MacBook Air",
                totalBytes: item.byteSize,
                phase: .failed,
                transferredBytes: 0,
                failure: .connectionFailed
            )
        case "cancelled":
            WorkspaceTransferTask(
                entryId: item.itemId,
                direction: .download,
                peerDeviceId: "iPhone",
                totalBytes: item.byteSize,
                phase: .cancelled,
                transferredBytes: 0,
                failure: nil
            )
        default:
            nil
        }
    }

    private func count(for filter: FileAreaFilterChoice) -> Int {
        FileAreaProjection.shared.filter(items: items, filter: filter.filter).count
    }

    private var filteredItems: [FileAreaItem] {
        FileAreaProjection.shared.filter(items: items, filter: selection.filter)
    }

    private var selectedItem: FileAreaItem? {
        filteredItems.first(where: { $0.id == selectedID }) ?? filteredItems.first
    }

    private var quietItems: [FileAreaItem] {
        guard let selectedItem else { return filteredItems }
        return filteredItems.filter { $0.id != selectedItem.id }
    }

    private var activeTransferCount: Int {
        items.compactMap { transferTask(for: $0) }.count { task in
            task.phase == .waiting || task.phase == .transferring
        }
    }

    private var items: [FileAreaItem] {
        [
            item("text", .text, "发布说明草稿.txt", pinned: true),
            item("shot-1", .screenshot, "截屏 2026-10-21 14.32.png"),
            item("shot-2", .screenshot, "截屏 2026-10-21 14.28.png"),
            item("pdf", .pdf, "Covio Design Contract v1.3.pdf"),
            item("remote", .image, "iPhone 参考.heic", availability: .remote),
            item("fetching", .file, "交互录屏 03.mov", availability: .fetching),
            item("audio", .audio, "旧录音.m4a", availability: .unavailable),
            item("failed", .pdf, "客户反馈.pdf", availability: .remote),
            item("cancelled", .file, "客户反馈.zip", availability: .remote),
        ]
    }

    private func item(
        _ id: String,
        _ kind: FileAreaKind,
        _ name: String,
        pinned: Bool = false,
        availability: FileAreaAvailability = FileAreaAvailability.local
    ) -> FileAreaItem {
        let local = availability == FileAreaAvailability.local
        let screenshot = kind == FileAreaKind.screenshot
        let text = kind == FileAreaKind.text
        return FileAreaItem(
            id: id,
            origin: screenshot ? FileAreaOrigin.screenshot : FileAreaOrigin.workspace,
            itemId: id,
            displayName: name,
            kind: kind,
            createdAtEpochSeconds: 1_792_560_000,
            byteSize: screenshot ? 1_887_437 : 1_024,
            originDeviceId: availability == FileAreaAvailability.local ? "" : "iPhone",
            expiresAtEpochSeconds: 0,
            availability: availability,
            pinned: pinned,
            capabilities: FileAreaCapabilities(
                canOpen: local,
                canCopy: local && !text,
                canCopyText: local && text,
                canMarkup: screenshot,
                canDragOut: local,
                canSaveToWorkspace: screenshot,
                canReveal: local && !screenshot,
                canPin: local && !screenshot,
                canRemove: true,
                canDownload: availability == FileAreaAvailability.remote,
                canCancel: availability == FileAreaAvailability.fetching
            )
        )
    }
}

@MainActor
enum FileAreaPreviewRenderer {
    static func render(panelWidth: CGFloat, to path: String) -> Bool {
        let language = AppLanguage.simplifiedChinese
        let contentWidth = panelWidth - HubMetrics.panelPadding * 2
        let view = FileAreaShowcaseView(contentWidth: contentWidth, language: language)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
#endif

#if DEBUG
enum FileAreaLivePreviewState: String {
    case normal
    case empty
    case noMatch
    case error
}

/// 用真实的 `FilesTabView`、真实的焦点修饰器和隔离数据做无障碍验收。
@MainActor
final class FileAreaLivePreviewController: NSWindowController {
    private let workspace: WorkspaceRuntime
    private let transfer: WorkspaceTransferRuntime
    private let shelf: ShelfRuntime
    private let autoNaming: AutoNamingRuntime
    private let policy: FileNamingPolicy
    private let rootDirectory: URL

    init(
        panelWidth: CGFloat,
        state: FileAreaLivePreviewState = .normal,
        reduceMotion: Bool = false
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-file-area-live-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        rootDirectory = root

        let workspaceDirectory = root.appendingPathComponent("Workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        let policy = FileNamingPolicy.companion.defaults()
        let workspacePolicy = WorkspacePolicy.companion.defaults().doCopy(
            maxTotalBytes: 64 * 1_024 * 1_024,
            maxEntryBytes: 16 * 1_024 * 1_024,
            retentionDays: 30,
            lazyFetchThresholdBytes: 8 * 1_024 * 1_024
        )
        var environment = WorkspaceEnvironment()
        environment.now = { 1_792_560_000 }
        let client = WorkspaceStoreClient(directory: workspaceDirectory.path)

        let image = root.appendingPathComponent("product-board.png")
        let text = root.appendingPathComponent("发布说明草稿.txt")
        Self.writePreviewImage(to: image)
        try? "文件区不再分截图页。截图只是文件区的一种筛选。".write(
            to: text,
            atomically: true,
            encoding: .utf8
        )
        let seed = WorkspaceRuntime(client: client, environment: environment, policy: workspacePolicy)
        seed.intake(urls: [image, text])

        let current = client.load()
        let remote = [
            Self.remoteEntry(1, kind: .image, name: "等待取回.heic", bytes: 3_200_000),
            Self.remoteEntry(2, kind: .file, name: "交互录屏 03.mov", bytes: 128_000_000),
            Self.remoteEntry(3, kind: .pdf, name: "客户反馈.pdf", bytes: 2_100_000),
            Self.remoteEntry(4, kind: .file, name: "客户反馈.zip", bytes: 18_500_000),
        ]
        client.save(current.doCopy(
            schemaVersion: current.schemaVersion,
            entries: current.entries + remote,
            policy: current.policy
        ))

        let workspace = WorkspaceRuntime(
            client: WorkspaceStoreClient(directory: workspaceDirectory.path),
            environment: environment,
            policy: workspacePolicy
        )
        let transfer = WorkspaceTransferRuntime(
            workspace: workspace,
            environment: WorkspaceTransferEnvironment(availableBytes: { 10_000_000_000 })
        )
        transfer.beginDownload(remote[0].entryId)
        transfer.beginDownload(remote[1].entryId)
        transfer.markTransferring(remote[1].entryId)
        transfer.updateProgress(remote[1].entryId, transferredBytes: remote[1].byteSize * 62 / 100)
        transfer.beginDownload(remote[2].entryId)
        transfer.fail(remote[2].entryId, error: .connectionFailed)
        transfer.beginDownload(remote[3].entryId)
        transfer.cancel(remote[3].entryId)

        let screenshotDirectory = root.appendingPathComponent("Screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
        let shot1 = screenshotDirectory.appendingPathComponent("截屏 2026-10-21 14.32.png")
        let shot2 = screenshotDirectory.appendingPathComponent("截屏 2026-10-21 14.28.png")
        Self.writePreviewImage(to: shot1)
        Self.writePreviewImage(to: shot2)
        let shelfStore = ShelfStoreClient(path: screenshotDirectory.appendingPathComponent("shelf.json").path)
        let shelfDefaults = ShelfStoreState.companion.defaults()
        shelfStore.save(shelfDefaults.doCopy(
            items: [
                ShelfItem(path: shot1.path, addedAtEpochSeconds: 1_792_559_900),
                ShelfItem(path: shot2.path, addedAtEpochSeconds: 1_792_559_800),
            ],
            revealed: true,
            preferenceSnapshot: nil
        ))
        let shelf = ShelfRuntime(
            store: shelfStore,
            preferences: FileAreaPreviewPreferenceStore(),
            environment: ScreenshotLibraryEnvironment(
                screenshotDirectory: { screenshotDirectory }
            )
        )

        if state == .empty {
            shelf.clearItems()
            workspace.clearAll()
        } else if state == .noMatch {
            shelf.clearItems()
        } else if state == .error {
            workspace.intake(urls: [root.appendingPathComponent("missing-file")])
        }

        self.workspace = workspace
        self.transfer = transfer
        self.shelf = shelf
        self.autoNaming = AutoNamingRuntime()
        self.policy = policy

        let contentWidth = panelWidth - HubMetrics.panelPadding * 2
        let rootView = FilesTabView(
            shelf: shelf,
            workspace: workspace,
            transfer: transfer,
            autoNaming: autoNaming,
            policy: policy,
            language: .simplifiedChinese,
            searchText: "",
            requestedFilter: state == .noMatch ? .screenshots : nil
        )
        .frame(width: contentWidth, height: FileAreaMetrics.areaHeight)
        .padding(.horizontal, HubMetrics.panelPadding)
        .environment(\.fileAreaReduceMotionOverride, reduceMotion)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: FileAreaMetrics.areaHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Covio File Area"
        window.contentView = NSHostingView(rootView: rootView)
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        super.close()
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    private static func remoteEntry(
        _ index: Int,
        kind: WorkspaceKind,
        name: String,
        bytes: Int64
    ) -> WorkspaceEntry {
        WorkspaceEntry(
            entryId: String(repeating: String(index), count: 64),
            kind: kind,
            displayName: name,
            byteSize: bytes,
            contentType: "",
            createdAtEpochSeconds: Int64(index),
            originDeviceId: index == 2 ? "iPad" : "iPhone",
            expiresAtEpochSeconds: 0,
            availability: WorkspaceAvailability.remote,
            pinned: false
        )
    }

    private static func writePreviewImage(to url: URL) {
        let size = NSSize(width: 640, height: 360)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.40, green: 0.49, blue: 0.75, alpha: 1),
            NSColor(calibratedRed: 0.84, green: 0.63, blue: 0.50, alpha: 1),
            NSColor(calibratedRed: 0.95, green: 0.84, blue: 0.71, alpha: 1),
        ])?.draw(in: NSRect(origin: .zero, size: size), angle: -35)
        NSColor(calibratedWhite: 1, alpha: 0.72).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 70, y: 84, width: 430, height: 170),
            xRadius: 18,
            yRadius: 18
        ).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url, options: .atomic)
    }
}

private final class FileAreaPreviewPreferenceStore: LegacyScreenshotPreferenceRestoring {
    func restore(snapshot: ScreenshotInboxSnapshot) -> Bool { true }
}
#endif

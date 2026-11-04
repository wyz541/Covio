#if DEBUG
import AppKit
import Foundation

/// 为真实应用窗口准备隔离的剪切板与截图数据。
///
/// 只在 DEBUG 构建中由 `COVIO_CLIPBOARD_LIVE_PREVIEW=1` 调用。调用方必须同时设置
/// `COVIO_SUPPORT_DIR` 与 `COVIO_SCREENSHOT_INDEX_DIR`，否则会写入真实应用数据。
@MainActor
enum ClipboardWorkspaceLivePreview {
    static func prepare() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["COVIO_SUPPORT_DIR"]?.isEmpty == false,
              environment["COVIO_SCREENSHOT_INDEX_DIR"]?.isEmpty == false
        else { return false }

        let root = AppPaths.supportDirectory.appendingPathComponent("ClipboardLivePreview", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            return false
        }

        let data = ClipboardWorkspacePreviewFixtures.make(in: root)

        let configStore = ConfigStore.companion.create(path: AppPaths.configFile.path)
        let draft = ConfigDraft(configStore.load())
        draft.language = AppLanguage.simplifiedChinese.rawValue
        draft.clipboardEnabled = true
        configStore.save(config: draft.build())

        let defaults = ClipboardState.companion.defaults()
        let clipboardState = defaults.doCopy(
            items: data.clips,
            pasteStack: [],
            paused: false,
            policy: ClipPolicy.companion.defaults()
        )
        _ = ClipboardStore.companion.create(path: AppPaths.clipboardFile.path).save(state: clipboardState)

        let shelfDefaults = ShelfStoreState.companion.defaults()
        let shelfState = shelfDefaults.doCopy(
            items: data.screenshots,
            revealed: true,
            preferenceSnapshot: nil
        )
        let shelfStore = ShelfStoreClient(path: ShelfPaths.storeFile.path)
        shelfStore.save(shelfState)
        return true
    }
}

@MainActor
private enum ClipboardWorkspacePreviewFixtures {
    static func make(in root: URL) -> ClipboardWorkspaceData {
        let now = Int64(Date().timeIntervalSince1970)
        let fileDirectory = root.appendingPathComponent("Files", isDirectory: true)
        let imageDirectory = root.appendingPathComponent("Images", isDirectory: true)
        let screenshotDirectory = root.appendingPathComponent("Screenshots", isDirectory: true)
        for directory in [fileDirectory, imageDirectory, screenshotDirectory] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let pdf = fileDirectory.appendingPathComponent("产品评审.pdf")
        let zip = fileDirectory.appendingPathComponent("品牌素材.zip")
        let markdown = fileDirectory.appendingPathComponent("验收记录.md")
        let notes = fileDirectory.appendingPathComponent("口令草稿.txt")
        try? Data().write(to: pdf)
        try? Data().write(to: zip)
        try? "## 验收记录\n\n检查四类内容。".write(to: markdown, atomically: true, encoding: .utf8)
        try? "临时文字".write(to: notes, atomically: true, encoding: .utf8)

        let image1 = imageDirectory.appendingPathComponent("cover-light.png")
        let image2 = imageDirectory.appendingPathComponent("cover-dark.png")
        let image3 = imageDirectory.appendingPathComponent("材质参考.png")
        let image4 = imageDirectory.appendingPathComponent("Covio 图标.png")
        writeImage(to: image1, colors: [NSColor(calibratedRed: 0.40, green: 0.68, blue: 0.86, alpha: 1), NSColor(calibratedRed: 0.29, green: 0.61, blue: 0.49, alpha: 1)])
        writeImage(to: image2, colors: [NSColor(calibratedRed: 0.27, green: 0.36, blue: 0.67, alpha: 1), NSColor(calibratedRed: 0.76, green: 0.43, blue: 0.55, alpha: 1)])
        writeImage(to: image3, colors: [NSColor(calibratedRed: 0.84, green: 0.58, blue: 0.38, alpha: 1), NSColor(calibratedRed: 0.95, green: 0.83, blue: 0.67, alpha: 1)])
        writeImage(to: image4, colors: [NSColor(calibratedRed: 0.38, green: 0.46, blue: 0.75, alpha: 1), NSColor(calibratedRed: 0.57, green: 0.66, blue: 0.94, alpha: 1)])

        let shot1 = screenshotDirectory.appendingPathComponent("Safari 窗口.png")
        let shot2 = screenshotDirectory.appendingPathComponent("文件面板.png")
        let shot3 = screenshotDirectory.appendingPathComponent("完整桌面.png")
        let shot4 = screenshotDirectory.appendingPathComponent("菜单栏细节.png")
        for (index, url) in [shot1, shot2, shot3, shot4].enumerated() {
            writeScreenshot(
                to: url,
                colors: index.isMultiple(of: 2)
                    ? [NSColor(calibratedRed: 0.52, green: 0.45, blue: 0.86, alpha: 1), NSColor(calibratedRed: 0.77, green: 0.49, blue: 0.73, alpha: 1)]
                    : [NSColor(calibratedRed: 0.35, green: 0.52, blue: 0.84, alpha: 1), NSColor(calibratedRed: 0.78, green: 0.58, blue: 0.83, alpha: 1)]
            )
        }

        let clips = [
            ClipItem(
                id: "file-pdf",
                kind: .files,
                text: pdf.path,
                filePath: pdf.path,
                byteSize: 2_100_000,
                createdAtEpochSeconds: now - 30,
                pinned: true,
                sourceBundleId: "com.apple.finder"
            ),
            ClipItem(
                id: "file-zip",
                kind: .files,
                text: zip.path,
                filePath: zip.path,
                byteSize: 18_600_000,
                createdAtEpochSeconds: now - 120,
                pinned: false,
                sourceBundleId: "com.apple.Safari"
            ),
            ClipItem(
                id: "file-md",
                kind: .files,
                text: markdown.path,
                filePath: markdown.path,
                byteSize: 24_000,
                createdAtEpochSeconds: now - 240,
                pinned: false,
                sourceBundleId: "com.apple.dt.Xcode"
            ),
            ClipItem(
                id: "file-notes",
                kind: .files,
                text: notes.path,
                filePath: notes.path,
                byteSize: 1_000,
                createdAtEpochSeconds: now - 360,
                pinned: false,
                sourceBundleId: "com.apple.TextEdit"
            ),
            ClipItem(
                id: "text-figma",
                kind: .text,
                text: """
                剪切板 Markdown 预览

                ## 详情样例

                把 **重点内容** 和 *补充说明* 发给设计组。

                - 支持 `行内代码`
                - 支持 [设计链接](https://example.com)

                > 原始文本保持不变。

                ```swift
                let ready = true
                ```
                """,
                filePath: "",
                byteSize: 0,
                createdAtEpochSeconds: now - 60,
                pinned: false,
                sourceBundleId: "com.apple.Safari"
            ),
            ClipItem(
                id: "text-link",
                kind: .link,
                text: "https://figma.com/file/covio",
                filePath: "",
                byteSize: 0,
                createdAtEpochSeconds: now - 180,
                pinned: true,
                sourceBundleId: "com.apple.Safari"
            ),
            ClipItem(
                id: "text-color",
                kind: .color,
                text: "#4656A4",
                filePath: "",
                byteSize: 0,
                createdAtEpochSeconds: now - 300,
                pinned: false,
                sourceBundleId: "com.apple.Preview"
            ),
            ClipItem(
                id: "text-note",
                kind: .text,
                text: "明天检查深色模式与键盘操作。",
                filePath: "",
                byteSize: 0,
                createdAtEpochSeconds: now - 55,
                pinned: false,
                sourceBundleId: "com.apple.TextEdit"
            ),
            ClipItem(
                id: "image-light",
                kind: .image,
                text: "浅色封面",
                filePath: image1.path,
                byteSize: 1_800_000,
                createdAtEpochSeconds: now - 90,
                pinned: false,
                sourceBundleId: "com.apple.Preview"
            ),
            ClipItem(
                id: "image-dark",
                kind: .image,
                text: "深色封面",
                filePath: image2.path,
                byteSize: 1_700_000,
                createdAtEpochSeconds: now - 210,
                pinned: false,
                sourceBundleId: "com.apple.Preview"
            ),
            ClipItem(
                id: "image-material",
                kind: .image,
                text: "材质参考",
                filePath: image3.path,
                byteSize: 6_200_000,
                createdAtEpochSeconds: now - 330,
                pinned: false,
                sourceBundleId: "com.apple.finder"
            ),
            ClipItem(
                id: "image-icon",
                kind: .image,
                text: "Covio 图标",
                filePath: image4.path,
                byteSize: 512_000,
                createdAtEpochSeconds: now - 450,
                pinned: false,
                sourceBundleId: "com.apple.Preview"
            ),
        ]

        let screenshots = [
            ShelfItem(path: shot1.path, addedAtEpochSeconds: now - 15),
            ShelfItem(path: shot2.path, addedAtEpochSeconds: now - 150),
            ShelfItem(path: shot3.path, addedAtEpochSeconds: now - 270),
            ShelfItem(path: shot4.path, addedAtEpochSeconds: now - 390),
        ]

        return ClipboardWorkspaceData(clips: clips, screenshots: screenshots)
    }

    private static func writeImage(to url: URL, colors: [NSColor]) {
        let size = NSSize(width: 640, height: 360)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: colors)?.draw(in: NSRect(origin: .zero, size: size), angle: -35)
        NSColor.white.withAlphaComponent(0.72).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 70, y: 84, width: 430, height: 170),
            xRadius: 18,
            yRadius: 18
        ).fill()
        image.unlockFocus()
        writePNG(image, to: url)
    }

    private static func writeScreenshot(to url: URL, colors: [NSColor]) {
        let size = NSSize(width: 640, height: 400)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: colors)?.draw(in: NSRect(origin: .zero, size: size), angle: -35)
        NSColor.white.withAlphaComponent(0.86).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 54, y: 54, width: 532, height: 292),
            xRadius: 18,
            yRadius: 18
        ).fill()
        NSColor(calibratedWhite: 0.28, alpha: 0.74).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 54, y: 306, width: 532, height: 40),
            xRadius: 18,
            yRadius: 18
        ).fill()
        image.unlockFocus()
        writePNG(image, to: url)
    }

    private static func writePNG(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: url, options: .atomic)
    }
}
#endif

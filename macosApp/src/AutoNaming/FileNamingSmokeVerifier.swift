import AppKit
import Foundation

/// 发布包内的自动命名烟雾测试。只在设置了验证环境变量时运行。
enum FileNamingSmokeVerifier {
    @MainActor
    static func run(outputURL: URL) async -> Int32 {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("covio-file-naming-smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        do {
            try FileManager.default.createDirectory(
                at: workingDirectory,
                withIntermediateDirectories: true
            )
            let textURL = workingDirectory.appendingPathComponent("input.txt")
            try "2026 年第四季度产品预算评审。项目：离线文件自动命名。".write(
                to: textURL,
                atomically: true,
                encoding: .utf8
            )
            let imageURL = workingDirectory.appendingPathComponent("receipt.png")
            try makeReceiptImage().write(to: imageURL, options: .atomic)

            guard let configuration = NamingModelConfiguration.bundled(
                resourceDirectory: Bundle.main.resourceURL,
                environment: [:]
            ) else {
                throw NamingModelError(.modelDirectoryMissing)
            }
            var configurationValue = configuration
            configurationValue.requestTimeout = .seconds(120)
            let model = NamingModelCoordinator(
                primary: MLXNamingModel(configuration: configurationValue),
                timeout: .seconds(120)
            )
            let runtime = AutoNamingRuntime(
                extractor: FileNamingContentExtractor(),
                model: model,
                renameService: FileRenameService(
                    journal: FileRenameJournalStore(
                        directory: workingDirectory.appendingPathComponent("undo", isDirectory: true)
                    )
                ),
                nowEpochSeconds: { 1_000 },
                makeRunID: { "bundle-smoke" }
            )

            await runtime.analyze(
                urls: [textURL, imageURL],
                policy: FileNamingPolicy.companion.defaults()
            )
            guard runtime.stage == .preview, runtime.selectedIDs.count == 2 else {
                throw SmokeError("text and image did not both reach preview")
            }
            let preview = runtime.items.map(\.dictionary)
            await runtime.applySelected()
            guard let applied = runtime.lastRunResult, applied.failureCount == 0 else {
                throw SmokeError("rename run failed")
            }
            await runtime.undoLastRun()
            guard let undone = runtime.lastUndoResult, undone.failureCount == 0 else {
                throw SmokeError("undo run failed")
            }
            guard FileManager.default.fileExists(atPath: textURL.path),
                  FileManager.default.fileExists(atPath: imageURL.path)
            else {
                throw SmokeError("undo did not restore both files")
            }

            try write(
                [
                    "ok": true,
                    "stage": runtime.stage.rawValue,
                    "selected": 2,
                    "renamed": applied.successCount,
                    "undoSucceeded": undone.successCount,
                    "items": preview,
                ],
                to: outputURL
            )
            return 0
        } catch {
            try? write(
                ["ok": false, "error": error.localizedDescription],
                to: outputURL
            )
            return 1
        }
    }

    @MainActor
    private static func makeReceiptImage() throws -> Data {
        let size = NSSize(width: 900, height: 600)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor.black.setStroke()
        NSBezierPath(rect: NSRect(x: 24, y: 24, width: 852, height: 552)).stroke()

        let title: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30),
            .foregroundColor: NSColor.darkGray,
        ]
        ("差旅报销单" as NSString).draw(at: NSPoint(x: 70, y: 500), withAttributes: title)
        ("金额：128.00 元" as NSString).draw(at: NSPoint(x: 70, y: 390), withAttributes: body)
        ("日期：2026-10-18" as NSString).draw(at: NSPoint(x: 70, y: 320), withAttributes: body)
        ("用途：离线文件命名调研" as NSString).draw(at: NSPoint(x: 70, y: 250), withAttributes: body)
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let data = representation.representation(using: .png, properties: [:])
        else {
            throw SmokeError("cannot create receipt image")
        }
        return data
    }

    private static func write(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }
}

private struct SmokeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private extension AutoNamingPreviewItem {
    var dictionary: [String: Any] {
        [
            "originalName": originalName,
            "targetName": targetName ?? "",
            "status": status.rawValue,
            "errorCode": errorCode ?? "",
        ]
    }
}

private extension AutoNamingStage {
    var rawValue: String {
        switch self {
        case .idle: "idle"
        case .analyzing: "analyzing"
        case .preview: "preview"
        case .applying: "applying"
        case .results: "results"
        case .undoing: "undoing"
        }
    }
}

import AppKit

/// 从系统剪贴板读出来的一条内容。
///
/// 是 [ClipItem] 的「还没分配 id 与时间」版本。分类由 Rust core 的
/// `ClipboardLogic.classify` 判定，判定结果放在 [kind]。
struct ClipboardPayload: Equatable {
    var kind: ClipKind
    var text: String = ""
    var filePath: String = ""
    var byteSize: Int64 = 0
}

/// 系统剪贴板的读写。
///
/// 旧版 0.4.2 只有截图专用的 `ShelfClipboard`，没有通用剪贴板载荷模型。
///
/// **读的顺序是文件、图片、文本。** 从访达复制图片时剪贴板上同时有
/// `fileURL`、TIFF 和字符串三种表示，从浏览器复制图片时同时有 TIFF 与字符串。
/// 先读文件才能保住原文件；先读字符串的话，复制一张图会变成一段 HTML。
enum ClipboardPayloadReader {
    /// 读出剪贴板当前内容。读不出认得的类型时返回 nil。
    ///
    /// 图片会落盘，所以调用方要传一个可写的目录。落盘失败时降级成文本条目。
    static func read(
        _ pasteboard: NSPasteboard = .general,
        imageDirectory: URL,
        writer: ClipboardImageWriter = ClipboardImageWriter()
    ) -> ClipboardPayload? {
        if let files = fileList(pasteboard) {
            return files
        }
        if let image = imagePayload(pasteboard, imageDirectory: imageDirectory, writer: writer) {
            return image
        }
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return ClipboardPayload(kind: ClipboardLogic.shared.classify(text: string), text: string)
        }
        return nil
    }

    /// 剪贴板上的文件地址。
    ///
    /// 多个文件时只把第一个放进 `filePath`（用于判重与预览），
    /// 完整列表按行放在 `text` 里。
    private static func fileList(_ pasteboard: NSPasteboard) -> ClipboardPayload? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty
        else { return nil }

        let paths = urls.map { $0.path(percentEncoded: false) }
        var size: Int64 = 0
        for path in paths {
            size += byteSize(of: URL(fileURLWithPath: path))
        }
        return ClipboardPayload(
            kind: ClipKind.files,
            text: paths.joined(separator: "\n"),
            filePath: paths[0],
            byteSize: size
        )
    }

    private static func imagePayload(
        _ pasteboard: NSPasteboard,
        imageDirectory: URL,
        writer: ClipboardImageWriter
    ) -> ClipboardPayload? {
        guard let data = pngData(pasteboard) else { return nil }
        guard let path = writer.write(data, into: imageDirectory) else {
            // 存不下图片时至少保住一段说明，不然用户按了复制却什么都没有。
            return ClipboardPayload(kind: ClipKind.text, text: ContractCopy.copyClipboardErrorImage.text)
        }
        return ClipboardPayload(
            kind: ClipKind.image,
            filePath: path,
            byteSize: Int64(data.count)
        )
    }

    /// 剪贴板上的图片转成 PNG。
    ///
    /// 优先用现成的 PNG 表示，没有再从 TIFF 转。
    private static func pngData(_ pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: .png) { return data }
        guard let tiff = pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func byteSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}

/// 把剪贴板上的图片写到磁盘。
///
/// 文件名按内容取哈希，所以同一张图复制两次只占一份空间。
/// 这与 `Screenshots/` 目录的惯例一致：二进制在文件系统里，元数据在状态文件里。
struct ClipboardImageWriter {
    /// 写入并返回路径。写不进去时返回 nil。
    func write(_ data: Data, into directory: URL) -> String? {
        let name = "\(Self.fingerprint(data)).png"
        let target = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) { return target.path }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // 先写临时文件再改名，避免掉电留下半个图片。
            let temporary = target.appendingPathExtension("tmp")
            try data.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
            return target.path
        } catch {
            return nil
        }
    }

    /// 内容指纹。用 FNV-1a，够短而且两平台一致，不依赖 CryptoKit。
    static func fingerprint(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

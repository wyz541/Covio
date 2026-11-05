import AppKit
import Foundation

/// 把截图放进系统剪贴板。
///
///
/// README 第 74 行：单击卡片同时复制图片和文件地址。
/// 所以一次要写两种类型：`fileURL` 让访达和聊天软件能收到文件，
/// 图片类型让图片编辑器和文档能直接粘贴。
///
/// 旧版走 AWT 的 `javaFileListFlavor` 与 `imageFlavor`。
/// 这里用 `NSPasteboard.writeObjects`，一次写入两种类型。
/// 分两次 `declareTypes` 会互相清空，只能一次写完。
enum ShelfClipboard {
    /// 复制一个文件。文件不存在或者不是图片时只写文件地址。
    @discardableResult
    static func copy(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        var objects: [NSPasteboardWriting] = [url as NSURL]
        // 读不出图片时仍然写文件地址，与旧版行为一致。
        if let image = NSImage(contentsOf: url) {
            objects.append(image)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects(objects)
    }
}

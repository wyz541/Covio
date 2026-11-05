import AppKit

/// 把一条剪切板记录写回系统剪贴板。
///
/// 与 [ClipboardPayloadReader] 互为反向。落在磁盘上的图片读回来写成图片与文件地址，
/// 文件列表写成文件地址，其余按纯文本写。
enum ClipboardWriter {
    /// 写入并返回是否成功。
    @discardableResult
    static func write(_ item: ClipItem, to pasteboard: NSPasteboard = .general) -> Bool {
        // 桥接层的种类值不是 Swift enum，所以这里用比较而不是 switch。
        if item.kind == ClipKind.image {
            guard let image = NSImage(contentsOfFile: item.filePath) else { return false }
            // 访达的 ⌘V 只接受文件地址。只写图片时，粘贴到访达没有反应。
            // 与 [ShelfClipboard] 一致，一次写文件地址与图片两种类型。
            // 分两次写会互相清空，只能一次写完。
            let url = URL(fileURLWithPath: item.filePath) as NSURL
            pasteboard.clearContents()
            return pasteboard.writeObjects([url, image])
        }
        if item.kind == ClipKind.files {
            let urls = item.text
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) as NSURL }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects(urls)
        }
        guard !item.text.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(item.text, forType: .string)
    }
}

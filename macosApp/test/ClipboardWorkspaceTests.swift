import XCTest
@testable import Covio

final class ClipboardWorkspaceTests: XCTestCase {
    func testAllItemsAreSortedNewestFirst() {
        let items = makeData().items(query: "", filter: .all, language: .simplifiedChinese)

        XCTAssertEqual(items.map(\.id).first, "screenshot:/tmp/newest.png")
        XCTAssertEqual(items.filter { $0.kind == .files }.count, 4)
        XCTAssertEqual(items.filter { $0.kind == .text }.count, 4)
        XCTAssertEqual(items.filter { $0.kind == .images }.count, 4)
        XCTAssertEqual(items.filter { $0.kind == .screenshots }.count, 3)
    }

    func testFiltersShowOnlyTheRequestedType() {
        let data = makeData()

        XCTAssertTrue(data.items(query: "", filter: .files, language: .simplifiedChinese).allSatisfy {
            $0.kind == .files
        })
        XCTAssertTrue(data.items(query: "", filter: .text, language: .simplifiedChinese).allSatisfy {
            $0.kind == .text
        })
        XCTAssertTrue(data.items(query: "", filter: .images, language: .simplifiedChinese).allSatisfy {
            $0.kind == .images
        })
        XCTAssertTrue(data.items(query: "", filter: .screenshots, language: .simplifiedChinese).allSatisfy {
            $0.kind == .screenshots
        })
    }

    func testSearchMatchesSourceAndKeepsTypeFiltering() {
        let data = makeData()

        let allMatches = data.items(query: "Safari", filter: .all, language: .simplifiedChinese)
        let textMatches = data.items(query: "Safari", filter: .text, language: .simplifiedChinese)

        XCTAssertEqual(allMatches.count, 3)
        XCTAssertEqual(textMatches.count, 2)
        XCTAssertTrue(textMatches.allSatisfy { $0.kind == .text })
    }

    func testSearchMatchesScreenshotType() {
        let items = makeData().items(query: "截图", filter: .all, language: .simplifiedChinese)

        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { $0.kind == .screenshots })
    }

    func testEmptySearchReturnsNoItemsOrSections() {
        let data = makeData()
        let query = "没有这一条"

        XCTAssertTrue(data.items(query: query, filter: .all, language: .simplifiedChinese).isEmpty)
        XCTAssertTrue(
            data.sections(query: query, filter: .all, language: .simplifiedChinese).isEmpty
        )
    }

    func testMarkdownParsesSupportedBlocks() throws {
        let source = """
        # 标题

        段落包含 **粗体**、*斜体* 和 `代码`。

        - 第一项
        - 第二项

        > 引用

        ```swift
        let value = 1
        ```

        ---
        """

        let document = ClipboardMarkdownDocument(source: source)

        XCTAssertTrue(document.usesMarkdown)
        XCTAssertEqual(
            blockKinds(document.blocks),
            ["heading1", "paragraph", "list.unordered", "blockQuote", "codeBlock", "thematicBreak"]
        )

        let code = try XCTUnwrap(document.blocks.first { block in
            if case .codeBlock = block { return true }
            return false
        })
        guard case .codeBlock(let language, let content) = code else {
            return XCTFail("缺少代码块")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(content, "let value = 1")
    }

    func testMarkdownKeepsOnlyHTTPAndHTTPSLinks() throws {
        let source = """
        [HTTP](http://example.com) [HTTPS](https://example.com) [Mail](mailto:test@example.com)
        [File](file:///tmp/covio) [Relative](/local) [Script](javascript:alert(1))
        """
        let document = ClipboardMarkdownDocument(source: source)
        let content = try XCTUnwrap(attributedContent(of: document.blocks.first))
        let links = content.runs.compactMap { $0.link?.absoluteString }

        XCTAssertTrue(document.usesMarkdown)
        XCTAssertEqual(links, ["http://example.com", "https://example.com"])
        XCTAssertEqual(
            String(content.characters).split(whereSeparator: \.isWhitespace),
            ["HTTP", "HTTPS", "Mail", "File", "Relative", "Script"]
        )
    }

    func testPlainAndIncompleteMarkdownKeepTheRawSource() {
        let plain = "第一行\n第二行"
        let incomplete = "**未闭合"
        let html = "<script>alert(1)</script>"

        XCTAssertFalse(ClipboardMarkdownDocument(source: plain).usesMarkdown)
        XCTAssertFalse(ClipboardMarkdownDocument(source: incomplete).usesMarkdown)
        XCTAssertFalse(ClipboardMarkdownDocument(source: html).usesMarkdown)
        XCTAssertEqual(ClipboardMarkdownDocument(source: plain).source, plain)
        XCTAssertEqual(ClipboardMarkdownDocument(source: incomplete).source, incomplete)
        XCTAssertEqual(ClipboardMarkdownDocument(source: html).source, html)
    }

    func testMarkdownImageKeepsAltTextWithoutKeepingTheRemoteURL() throws {
        let document = ClipboardMarkdownDocument(source: "![Covio](https://example.com/a.png)")
        let content = try XCTUnwrap(attributedContent(of: document.blocks.first))

        XCTAssertTrue(document.usesMarkdown)
        XCTAssertEqual(String(content.characters), "Covio")
        XCTAssertTrue(content.runs.allSatisfy { $0.imageURL == nil })
    }

    func testNestedListsKeepTheirOrdinals() throws {
        let source = """
        1. 第一层
           1. 第二层
        2. 下一项
        """
        let document = ClipboardMarkdownDocument(source: source)
        let list = try XCTUnwrap(document.blocks.first)
        guard case .list(.ordered, let items) = list else {
            return XCTFail("缺少有序列表")
        }

        XCTAssertEqual(items.map(\.ordinal), [1, 2])
        let nested = try XCTUnwrap(items.first?.blocks.first { block in
            if case .list = block { return true }
            return false
        })
        guard case .list(.ordered, let nestedItems) = nested else {
            return XCTFail("缺少嵌套列表")
        }
        XCTAssertEqual(nestedItems.map(\.ordinal), [1])
    }

    func testPinnedItemsComeBeforeTodayAndOlderSections() {
        let now = Int64(Date().timeIntervalSince1970)
        let data = ClipboardWorkspaceData(
            clips: [
                clip(id: "today", kind: .text, title: "Today", epoch: now - 60),
                clip(id: "pinned", kind: .text, title: "Pinned", epoch: now - 3_600, pinned: true),
                clip(id: "yesterday", kind: .text, title: "Yesterday", epoch: now - 86_400),
                clip(id: "earlier", kind: .text, title: "Earlier", epoch: now - 3 * 86_400),
            ],
            screenshots: []
        )

        let sections = data.sections(
            query: "",
            filter: .all,
            language: .simplifiedChinese,
            now: Date(timeIntervalSince1970: TimeInterval(now))
        )

        XCTAssertEqual(sections.map(\.kind), [.pinned, .today, .yesterday, .earlier])
        XCTAssertEqual(sections.first?.items.map(\.id), ["clip:pinned"])
    }

    func testFileItemsExposeEveryPathForDetailView() {
        let first = "/tmp/one.pdf"
        let second = "/tmp/two.pdf"
        let item = ClipboardWorkspaceItem.clip(
            ClipItem(
                id: "files",
                kind: .files,
                text: "\(first)\n\(second)",
                filePath: first,
                byteSize: 42,
                createdAtEpochSeconds: 1,
                pinned: false,
                sourceBundleId: "com.apple.finder"
            )
        )

        XCTAssertEqual(item.filePaths, [first, second])
        XCTAssertEqual(item.title(for: .simplifiedChinese), "one.pdf +1")
    }

    func testActionMenusMatchClipAndScreenshotCapabilities() throws {
        let items = makeData().allItems(language: .simplifiedChinese)
        let clip = try XCTUnwrap(items.first { $0.kind == .text })
        let screenshot = try XCTUnwrap(items.first { $0.kind == .screenshots })

        XCTAssertEqual(
            clip.secondaryActions,
            [.copy, .togglePin, .saveToWorkspace, .remove]
        )
        XCTAssertEqual(
            screenshot.secondaryActions,
            [.copy, .saveToWorkspace, .preview, .markup, .remove]
        )
        XCTAssertEqual(clip.primaryTitle(for: .simplifiedChinese), "粘贴")
        XCTAssertEqual(screenshot.primaryTitle(for: .simplifiedChinese), "复制")
    }

    func testPinnedClipUsesTheUnpinActionTitle() throws {
        let pinned = ClipItem(
            id: "pinned",
            kind: .text,
            text: "Pinned",
            filePath: "",
            byteSize: 0,
            createdAtEpochSeconds: 1,
            pinned: true,
            sourceBundleId: "com.apple.Safari"
        )
        let item = ClipboardWorkspaceItem.clip(pinned)

        XCTAssertEqual(
            item.actionTitle(.togglePin, language: .simplifiedChinese),
            "取消置顶"
        )
    }

    private func makeData() -> ClipboardWorkspaceData {
        let now = Int64(Date().timeIntervalSince1970)
        return ClipboardWorkspaceData(
            clips: [
                clip(id: "file-1", kind: .files, title: "One.pdf", source: "com.apple.finder", epoch: now - 40),
                clip(id: "file-2", kind: .files, title: "Two.zip", source: "com.apple.Safari", epoch: now - 39),
                clip(id: "file-3", kind: .files, title: "Three.md", source: "com.apple.dt.Xcode", epoch: now - 38),
                clip(id: "file-4", kind: .files, title: "Four.txt", source: "com.apple.TextEdit", epoch: now - 37),
                clip(id: "text-1", kind: .text, title: "产品预览", source: "com.apple.Safari", epoch: now - 36),
                clip(id: "link-1", kind: .link, title: "https://example.com", source: "com.apple.Safari", epoch: now - 35),
                clip(id: "color-1", kind: .color, title: "#4656A4", source: "com.apple.Preview", epoch: now - 34),
                clip(id: "text-2", kind: .text, title: "说明文字", source: "com.apple.TextEdit", epoch: now - 33),
                clip(id: "image-1", kind: .image, title: "one.png", source: "com.apple.Preview", epoch: now - 32),
                clip(id: "image-2", kind: .image, title: "two.png", source: "com.apple.Preview", epoch: now - 31),
                clip(id: "image-3", kind: .image, title: "three.png", source: "com.apple.Preview", epoch: now - 30),
                clip(id: "image-4", kind: .image, title: "four.png", source: "com.apple.Preview", epoch: now - 29),
            ],
            screenshots: [
                ShelfItem(path: "/tmp/newest.png", addedAtEpochSeconds: now - 1),
                ShelfItem(path: "/tmp/截图 1.png", addedAtEpochSeconds: now - 28),
                ShelfItem(path: "/tmp/截图 2.png", addedAtEpochSeconds: now - 27),
            ]
        )
    }

    private func clip(
        id: String,
        kind: ClipKind,
        title: String = "",
        source: String = "com.apple.finder",
        epoch: Int64,
        pinned: Bool = false
    ) -> ClipItem {
        ClipItem(
            id: id,
            kind: kind,
            text: title,
            filePath: kind == .files || kind == .image ? "/tmp/\(title)" : "",
            byteSize: 0,
            createdAtEpochSeconds: epoch,
            pinned: pinned,
            sourceBundleId: source
        )
    }

    private func blockKinds(_ blocks: [ClipboardMarkdownBlock]) -> [String] {
        blocks.map { block in
            switch block {
            case .paragraph:
                "paragraph"
            case .heading(let level, _):
                "heading\(level)"
            case .codeBlock:
                "codeBlock"
            case .list(.ordered, _):
                "list.ordered"
            case .list(.unordered, _):
                "list.unordered"
            case .blockQuote:
                "blockQuote"
            case .thematicBreak:
                "thematicBreak"
            case .unsupported:
                "unsupported"
            }
        }
    }

    private func attributedContent(of block: ClipboardMarkdownBlock?) -> AttributedString? {
        guard let block else { return nil }
        switch block {
        case .paragraph(let content), .heading(_, let content), .unsupported(let content):
            return content
        case .codeBlock:
            return nil
        case .list(_, let items):
            return attributedContent(of: items.first?.blocks.first)
        case .blockQuote(let blocks):
            return attributedContent(of: blocks.first)
        case .thematicBreak:
            return nil
        }
    }
}

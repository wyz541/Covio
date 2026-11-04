package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ClipboardStoreTest {
    /// 整段文本就是一个链接才算链接。夹在句子里不算。
    @Test
    fun `classification separates links colours and plain text`() {
        assertEquals(ClipKind.LINK, ClipboardLogic.classify("https://example.com/a?b=1"))
        assertEquals(ClipKind.LINK, ClipboardLogic.classify("  HTTP://example.com  "))
        assertEquals(ClipKind.COLOR, ClipboardLogic.classify("#ff8800"))
        assertEquals(ClipKind.COLOR, ClipboardLogic.classify("#abc"))
        assertEquals(ClipKind.COLOR, ClipboardLogic.classify("rgba(1, 2, 3, 0.5)"))
        assertEquals(ClipKind.TEXT, ClipboardLogic.classify("看这个 https://example.com"))
        assertEquals(ClipKind.TEXT, ClipboardLogic.classify("#不 是颜色"))
        assertEquals(ClipKind.TEXT, ClipboardLogic.classify("   "))
    }

    @Test
    fun `store round trips items stack and policy`() =
        withTemporaryDirectory("clipboard") { directory ->
            val path = directory.resolve("clipboard.json")
            val store = ClipboardStore(path.toString())
            val expected = ClipboardState(
                items = listOf(ClipItem("a", ClipKind.TEXT, text = "hello", createdAtEpochSeconds = 5L)),
                pasteStack = listOf("a"),
                paused = true,
                policy = ClipPolicy(maxItems = 3),
            )

            store.save(expected)

            assertEquals(expected, store.load())
        }

    /// 同一个标识只留最新的一条。
    @Test
    fun `prune keeps only the newest copy of the same content`() {
        val items = listOf(
            ClipItem("old", ClipKind.TEXT, text = "same", createdAtEpochSeconds = 10L),
            ClipItem("new", ClipKind.TEXT, text = "same", createdAtEpochSeconds = 20L),
            ClipItem("other", ClipKind.TEXT, text = "different", createdAtEpochSeconds = 5L),
        )

        val kept = ClipboardLogic.prune(items, ClipPolicy(), nowEpochSeconds = 20L)

        assertEquals(listOf("new", "other"), kept.map(ClipItem::id))
    }

    /// 过期的丢掉。置顶的不过期。
    @Test
    fun `prune drops expired items but keeps pinned ones`() {
        val now = 10L * 24 * 60 * 60
        val stale = now - 8L * 24 * 60 * 60
        val items = listOf(
            ClipItem("stale", ClipKind.TEXT, text = "old", createdAtEpochSeconds = stale),
            ClipItem("pinned", ClipKind.TEXT, text = "keep", createdAtEpochSeconds = stale, pinned = true),
        )

        val kept = ClipboardLogic.prune(items, ClipPolicy(maxAgeDays = 7), nowEpochSeconds = now)

        assertEquals(listOf("pinned"), kept.map(ClipItem::id))
    }

    /// 条数上限只数没置顶的。
    @Test
    fun `prune counts only unpinned items against the limit`() {
        val items = (0 until 5).map { index ->
            ClipItem("i$index", ClipKind.TEXT, text = "t$index", createdAtEpochSeconds = index.toLong())
        } + ClipItem("pin", ClipKind.TEXT, text = "p", createdAtEpochSeconds = 0L, pinned = true)

        val kept = ClipboardLogic.prune(items, ClipPolicy(maxItems = 2), nowEpochSeconds = 100L)

        assertEquals(setOf("pin", "i4", "i3"), kept.map(ClipItem::id).toSet())
    }

    /// 总字节上限只算没置顶的。
    @Test
    fun `prune respects the total byte budget`() {
        val items = listOf(
            ClipItem("big", ClipKind.IMAGE, filePath = "/tmp/big.png", byteSize = 900, createdAtEpochSeconds = 9L),
            ClipItem("small", ClipKind.IMAGE, filePath = "/tmp/small.png", byteSize = 50, createdAtEpochSeconds = 8L),
        )

        val kept = ClipboardLogic.prune(
            items,
            ClipPolicy(maxTotalBytes = 100),
            nowEpochSeconds = 10L,
            exists = { true },
        )

        assertEquals(listOf("small"), kept.map(ClipItem::id))
    }

    /// 落盘文件被删掉的图片条目要摘掉。文本条目不看文件。
    @Test
    fun `prune drops image items whose file is gone`() {
        val items = listOf(
            ClipItem("gone", ClipKind.IMAGE, filePath = "/tmp/gone.png", createdAtEpochSeconds = 2L),
            ClipItem("here", ClipKind.IMAGE, filePath = "/tmp/here.png", createdAtEpochSeconds = 1L),
            ClipItem("text", ClipKind.TEXT, text = "kept", createdAtEpochSeconds = 0L),
        )

        val kept = ClipboardLogic.prune(
            items,
            ClipPolicy(),
            nowEpochSeconds = 10L,
            exists = { it.endsWith("here.png") },
        )

        assertEquals(setOf("here", "text"), kept.map(ClipItem::id).toSet())
    }

    /// 正文与路径都为空的条目是坏数据。
    @Test
    fun `prune drops empty items`() {
        val items = listOf(ClipItem("empty", ClipKind.TEXT), ClipItem("ok", ClipKind.TEXT, text = "x"))

        val kept = ClipboardLogic.prune(items, ClipPolicy(), nowEpochSeconds = 0L)

        assertEquals(listOf("ok"), kept.map(ClipItem::id))
    }

    /// 粘贴栈里的条目可能已经被删掉了，取队首时顺带清掉失效的。
    @Test
    fun `next paste skips ids that are no longer present`() {
        val state = ClipboardState(
            items = listOf(ClipItem("live", ClipKind.TEXT, text = "x")),
            pasteStack = listOf("gone", "live"),
        )

        val (remaining, item) = ClipboardLogic.nextPaste(state)

        assertEquals("live", item?.id)
        assertEquals(emptyList(), remaining.pasteStack)
    }

    @Test
    fun `next paste returns nothing for an empty stack`() {
        val (remaining, item) = ClipboardLogic.nextPaste(ClipboardState())

        assertNull(item)
        assertEquals(emptyList(), remaining.pasteStack)
    }

    /// 同一个条目只排一次，重排时挪到队尾。
    @Test
    fun `pushing onto the paste stack moves an existing entry to the back`() {
        assertEquals(listOf("b", "a"), ClipboardLogic.pushPasteStack(listOf("a", "b"), "a"))
        assertEquals(listOf("a", "b"), ClipboardLogic.pushPasteStack(listOf("a"), "b"))
    }

    @Test
    fun `clear removes the clipboard file and load returns defaults`() =
        withTemporaryDirectory("clipboard") { directory ->
            val path = directory.resolve("clipboard.json")
            val store = ClipboardStore(path.toString())
            store.save(ClipboardState(items = listOf(ClipItem("a", ClipKind.TEXT, text = "x"))))

            assertTrue(path.exists)
            assertTrue(store.clear())
            assertEquals(ClipboardState(), store.load())
        }

    /// 保存时先写 `.tmp` 再原子改名，所以目录里不留临时文件。
    @Test
    fun `save leaves no temporary file behind`() =
        withTemporaryDirectory("clipboard") { directory ->
            val store = ClipboardStore(directory.resolve("clipboard.json").toString())
            store.save(ClipboardState(items = listOf(ClipItem("a", ClipKind.TEXT, text = "x"))))

            val leftovers = okio.FileSystem.SYSTEM.list(directory).map { it.name }.filter { it.endsWith(".tmp") }
            assertEquals(emptyList(), leftovers)
        }

    /**
     * 写不进去时不抛异常。
     *
     * Kotlin 的异常跨到 Swift 没有接收方，会直接终止进程。
     */
    @Test
    fun `save swallows write failures`() =
        withTemporaryDirectory("clipboard") { directory ->
            // 拿一个普通文件当目录用，写它下面的路径一定失败。
            val blocker = directory.resolve("blocker")
            blocker.writeText("not a directory")
            val store = ClipboardStore(blocker.resolve("clipboard.json").toString())

            store.save(ClipboardState(items = listOf(ClipItem("a", ClipKind.TEXT, text = "x"))))

            assertEquals("not a directory", blocker.readText(), "失败时不该动到那个文件")
        }

    /// 条目的落盘目录沿用 `APP_NAME`，与晾衣线目录同一套写法。
    @Test
    fun `default paths use the app name directory`() {
        val path = defaultClipboardPath()
        assertTrue(
            path.endsWith("${AppDirectories.userApplicationSupport}/$APP_NAME/Clipboard/clipboard.json"),
            "剪切板路径不对：$path",
        )
        assertEquals(ClipboardStore.defaultDirectory(), path.removeSuffix("/clipboard.json"))
    }

    /// 图片与文件条目有落盘文件，可以导入工作区。
    @Test
    fun `import paths lists the files behind an item`() {
        val image = ClipItem("a", ClipKind.IMAGE, filePath = "/tmp/a.png")
        assertEquals(listOf("/tmp/a.png"), ClipboardLogic.importPaths(image))

        // 文件条目可能复制了多个文件：第一个在 filePath，完整列表在 text。
        val files = ClipItem(
            "b",
            ClipKind.FILES,
            text = "/tmp/a.png\n/tmp/b.png",
            filePath = "/tmp/a.png",
        )
        assertEquals(listOf("/tmp/a.png", "/tmp/b.png"), ClipboardLogic.importPaths(files))
    }

    /// 文字、链接与颜色条目没有落盘文件，导入时走另一条路。
    @Test
    fun `import paths is empty for text items`() {
        assertEquals(emptyList(), ClipboardLogic.importPaths(ClipItem("a", ClipKind.TEXT, text = "hello")))
        assertEquals(emptyList(), ClipboardLogic.importPaths(ClipItem("b", ClipKind.LINK, text = "https://a.example")))
        assertEquals(emptyList(), ClipboardLogic.importPaths(ClipItem("c", ClipKind.COLOR, text = "#ff0000")))
        // 路径为空的坏数据也不该给出空串。
        assertEquals(emptyList(), ClipboardLogic.importPaths(ClipItem("d", ClipKind.IMAGE, filePath = "  ")))
    }
}

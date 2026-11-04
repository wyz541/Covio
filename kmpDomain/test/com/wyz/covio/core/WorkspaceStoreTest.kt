package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import okio.FileSystem

/**
 * `WorkspaceStore` 的持久化测试。
 *
 * 内容按摘要落盘，索引原子写入，淘汰时连内容一起删。
 * 与 [ClipboardStoreTest] 同一套写法：临时目录里跑，跑完删掉。
 */
class WorkspaceStoreTest {
    private fun storeIn(directory: okio.Path): WorkspaceStore =
        WorkspaceStore.create(directory.resolve("Workspace").toString())

    private fun entry(
        entryId: String,
        bytes: Long = 0L,
        createdAt: Long = 0L,
        expiresAt: Long = 0L,
    ): WorkspaceEntry = WorkspaceEntry(
        entryId = entryId,
        byteSize = bytes,
        createdAtEpochSeconds = createdAt,
        expiresAtEpochSeconds = expiresAt,
    )

    private fun digestOf(text: String): String = WorkspaceStore.digestOf(text.encodeToByteArray())

    /** 测试里的「现在」。删除标记按天保留，固定一个值就够了。 */
    private companion object {
        const val NOW_EPOCH_SECONDS = 1_700_000_000L
        const val SECONDS_PER_DAY = 24L * 60 * 60
    }

    @Test
    fun `index round trips entries and policy`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val expected = WorkspaceState(
                entries = listOf(entry(digestOf("hello"), bytes = 5L, createdAt = 10L, expiresAt = 20L)),
                policy = WorkspacePolicy(maxTotalBytes = 1024L, maxEntryBytes = 512L, retentionDays = 3),
            )

            store.save(expected)

            assertEquals(expected, store.load())
        }

    @Test
    fun `load returns defaults when the index is missing`() =
        withTemporaryDirectory("workspace") { directory ->
            assertEquals(WorkspaceState(), storeIn(directory).load())
        }

    /// 坏掉的 JSON 当作空索引，不抛异常。
    @Test
    fun `load returns defaults when the index is corrupt`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val index = directory.resolve("Workspace/index.json")
            FileSystem.SYSTEM.createDirectories(index.parent!!)
            index.writeText("{ not json")

            assertEquals(WorkspaceState(), store.load())
        }

    /// 保存时先写 `.tmp` 再原子改名，所以目录里不留临时文件。
    @Test
    fun `save leaves no temporary file behind`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            store.save(WorkspaceState(entries = listOf(entry(digestOf("x")))))

            val leftovers = FileSystem.SYSTEM.list(directory.resolve("Workspace"))
                .map { it.name }
                .filter { it.endsWith(".tmp") }
            assertEquals(emptyList(), leftovers)
        }

    @Test
    fun `content is stored under its digest and read back`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val bytes = "一段内容".encodeToByteArray()

            val entryId = store.importContent(bytes)
            assertNotNull(entryId)
            assertEquals(digestOf("一段内容"), entryId)
            assertTrue(store.hasContent(entryId))
            assertContentEquals(bytes, store.readContent(entryId))
            assertTrue(store.verifyContent(entryId))
            assertTrue(store.contentPath(entryId)!!.endsWith("/objects/$entryId"))
        }

    /// 相同内容只存一份：摘要就是文件名。
    @Test
    fun `the same content is stored once`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val bytes = "same".encodeToByteArray()

            val first = store.importContent(bytes)
            val second = store.importContent(bytes)

            assertEquals(first, second)
            assertEquals(1, FileSystem.SYSTEM.list(directory.resolve("Workspace/objects")).size)
            assertEquals(emptyList(), FileSystem.SYSTEM.list(directory.resolve("Workspace/incoming")))
        }

    /// 摘要对不上时什么都不写。
    @Test
    fun `put content refuses a digest that does not match`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val wrongId = digestOf("other")

            assertFalse(store.putContent(wrongId, "payload".encodeToByteArray()))
            assertFalse(store.hasContent(wrongId))
            assertFalse(FileSystem.SYSTEM.exists(directory.resolve("Workspace/objects")))
        }

    /// 摘要以外的字符不该拼进路径。
    @Test
    fun `content paths refuse anything that is not a digest`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)

            assertNull(store.contentPath("../../etc/passwd"))
            assertNull(store.contentPath(""))
            assertNull(store.readContent("../escape"))
            assertFalse(store.hasContent("../escape"))
            assertFalse(store.deleteContent("../escape"))
            assertFalse(store.verifyContent("../escape"))
            assertFalse(FileSystem.SYSTEM.exists(directory.resolve("etc")))
        }

    @Test
    fun `deleting content makes verification fail`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val entryId = store.importContent("gone".encodeToByteArray())!!

            assertTrue(store.deleteContent(entryId))
            assertFalse(store.hasContent(entryId))
            assertFalse(store.verifyContent(entryId))
            assertNull(store.readContent(entryId))
        }

    /// 淘汰与过期都连内容一起删，剩下的索引落盘。
    @Test
    fun `sweep deletes the content of expired and evicted entries`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val keptId = store.importContent("kept".encodeToByteArray())!!
            val expiredId = store.importContent("expired".encodeToByteArray())!!
            val evictedId = store.importContent("evicted".encodeToByteArray())!!
            val policy = WorkspacePolicy(maxTotalBytes = 300L, maxEntryBytes = 300L, retentionDays = 7)
            store.save(
                WorkspaceState(
                    entries = listOf(
                        entry(keptId, bytes = 100L, createdAt = 100L),
                        entry(evictedId, bytes = 300L, createdAt = 10L),
                        entry(expiredId, bytes = 100L, createdAt = 100L, expiresAt = 999L),
                    ),
                    policy = policy,
                ),
            )

            val plan = store.sweep(policy, nowEpochSeconds = 1000L)

            assertEquals(listOf(keptId), plan.kept.map(WorkspaceEntry::entryId))
            assertEquals(listOf(expiredId), plan.expired.map(WorkspaceEntry::entryId))
            assertEquals(listOf(evictedId), plan.evicted.map(WorkspaceEntry::entryId))
            assertTrue(store.hasContent(keptId))
            assertFalse(store.hasContent(expiredId))
            assertFalse(store.hasContent(evictedId))
            assertEquals(listOf(keptId), store.load().entries.map(WorkspaceEntry::entryId))
            assertEquals(policy, store.load().policy)
        }

    /**
     * 没有变化就不落盘。
     *
     * 应用每次启动都清一次。空工作区空转时不该建出索引文件，
     * 否则用户只是打开应用就会多一个目录。
     */
    @Test
    fun `sweep writes nothing when there is nothing to remove`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val indexPath = directory.resolve("Workspace/index.json")

            val plan = store.sweep(WorkspacePolicy(), nowEpochSeconds = 1000L)

            assertFalse(plan.changed)
            assertFalse(FileSystem.SYSTEM.exists(indexPath), "空转不该建索引文件")
        }

    /** 策略变了要落盘，否则下次启动读到的是旧策略。 */
    @Test
    fun `sweep persists a changed policy`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val policy = WorkspacePolicy(maxTotalBytes = 1024L, maxEntryBytes = 512L, retentionDays = 3)

            store.sweep(policy, nowEpochSeconds = 1000L)

            assertEquals(policy.normalized(), store.load().policy)
        }

    @Test
    fun `clear removes the index and both content directories`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val entryId = store.importContent("x".encodeToByteArray())!!
            store.save(WorkspaceState(entries = listOf(entry(entryId, bytes = 1L))))

            assertTrue(store.clear())

            assertEquals(WorkspaceState(), store.load())
            assertFalse(FileSystem.SYSTEM.exists(directory.resolve("Workspace/objects")))
            assertFalse(FileSystem.SYSTEM.exists(directory.resolve("Workspace/incoming")))
        }

    /**
     * 写不进去时不抛异常。
     *
     * Kotlin 的异常跨到 Swift 没有接收方，会直接终止进程。
     */
    @Test
    fun `save swallows write failures`() =
        withTemporaryDirectory("workspace") { directory ->
            // 拿一个普通文件当目录用，写它下面的路径一定失败。
            val blocker = directory.resolve("blocker")
            blocker.writeText("not a directory")
            val store = WorkspaceStore.create(blocker.resolve("Workspace").toString())

            val saved = store.save(WorkspaceState(entries = listOf(entry(digestOf("x")))))

            assertEquals(1, saved.entries.size)
            assertEquals("not a directory", blocker.readText(), "失败时不该动到那个文件")
            assertEquals(WorkspaceState(), store.load())
        }

    /**
     * 写失败时 [WorkspaceStore.saveReporting] 回 null，调用方据此报错。
     *
     * [WorkspaceStore.save] 只看状态，分不出写没写进去。
     */
    @Test
    fun `save reporting tells whether the index reached the disk`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val state = WorkspaceState(entries = listOf(entry(digestOf("x"))))

            assertEquals(state, store.saveReporting(state))

            // 把临时文件占成一个目录，写索引必然失败。
            FileSystem.SYSTEM.createDirectories(directory.resolve("Workspace/index.json.tmp"))

            assertNull(store.saveReporting(state.copy(entries = state.entries + entry(digestOf("y")))))
            assertEquals(state, store.load(), "失败时磁盘上还是上一份索引")
        }

    /**
     * 索引没写进磁盘时放入不算成功。
     *
     * 内容已经在 `objects` 里了，但重启之后没有索引就找不回来，所以内存里也不留这一条。
     */
    @Test
    fun `put file reports a failed index write`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val source = directory.resolve("note.txt")
            source.writeText("hello")
            FileSystem.SYSTEM.createDirectories(directory.resolve("Workspace/index.json.tmp"))

            val result = store.putFile(
                state = WorkspaceState(),
                sourcePath = source.toString(),
                displayName = "note.txt",
                contentType = "text/plain",
                originDeviceId = "mac-1",
                nowEpochSeconds = 100L,
            )

            assertEquals(WorkspaceAdmission.ACCEPTED, result.admission)
            assertFalse(result.persisted)
            assertNull(result.entry, "没落盘的条目不报给界面")
            assertEquals(emptyList(), result.state.entries)
            assertEquals(WorkspaceState(), store.load())
        }

    /// 放进去的那一条落盘了，`persisted` 才是真。
    @Test
    fun `put file reports a persisted entry`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val source = directory.resolve("note.txt")
            source.writeText("hello")

            val result = store.putFile(
                state = WorkspaceState(),
                sourcePath = source.toString(),
                displayName = "note.txt",
                contentType = "text/plain",
                originDeviceId = "mac-1",
                nowEpochSeconds = 100L,
            )

            assertTrue(result.persisted)
            assertNotNull(result.entry)
            assertEquals(1, store.load().entries.size)
        }

    /// 工作区目录沿用 `APP_NAME`，与晾衣线和剪切板同一套写法。
    @Test
    fun `default paths use the app name directory`() {
        val directory = WorkspaceStore.defaultDirectory()
        assertTrue(
            directory.endsWith("${AppDirectories.userApplicationSupport}/$APP_NAME/Workspace"),
            "工作区目录不对：$directory",
        )
        assertEquals(directory, defaultWorkspaceDirectory())
    }

    /// 放入一个真实文件：内容按摘要落盘，条目进索引。
    @Test
    fun `put file copies the content and records the entry`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val source = directory.resolve("合同.pdf")
            source.writeText("pdf bytes")

            val result = store.putFile(
                state = WorkspaceState(),
                sourcePath = source.toString(),
                displayName = "合同.pdf",
                contentType = "application/pdf",
                originDeviceId = "mac-1",
                nowEpochSeconds = 100L,
            )

            assertEquals(WorkspaceAdmission.ACCEPTED, result.admission)
            assertTrue(result.accepted)
            val entry = result.entry!!
            assertEquals(digestOf("pdf bytes"), entry.entryId)
            assertEquals(WorkspaceKind.PDF, entry.kind)
            assertEquals(9L, entry.byteSize)
            assertEquals(100L, entry.createdAtEpochSeconds)
            assertEquals("mac-1", entry.originDeviceId)
            assertEquals(100L + 30L * 24 * 60 * 60, entry.expiresAtEpochSeconds)
            assertTrue(store.hasContent(entry.entryId))
            assertEquals(listOf(entry.entryId), result.state.entries.map(WorkspaceEntry::entryId))
            assertEquals(listOf(entry.entryId), store.load().entries.map(WorkspaceEntry::entryId))
            assertEquals("pdf bytes", source.readText(), "源文件不该被动过")
        }

    /// 同一个文件放两次只留一条，也不留半份文件。
    @Test
    fun `put file merges the same content into one entry`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val source = directory.resolve("note.txt")
            source.writeText("hello")
            val first = store.putFile(WorkspaceState(), source.toString(), "note.txt", "text/plain", "", 100L)

            val second = store.putFile(first.state, source.toString(), "note.txt", "text/plain", "", 200L)

            assertEquals(WorkspaceAdmission.DUPLICATE, second.admission)
            assertEquals(first.entry?.entryId, second.entry?.entryId)
            assertEquals(first.entry?.createdAtEpochSeconds, second.entry?.createdAtEpochSeconds)
            assertEquals(1, second.state.entries.size)
            assertEquals(1, FileSystem.SYSTEM.list(directory.resolve("Workspace/objects")).size)
            assertEquals(emptyList(), FileSystem.SYSTEM.list(directory.resolve("Workspace/incoming")))
        }

    /// 超过单条目上限时不落盘，也不留半份文件。
    @Test
    fun `put file refuses content over the entry limit`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val source = directory.resolve("big.bin")
            source.writeText("0123456789")
            val state = WorkspaceState(policy = WorkspacePolicy(maxTotalBytes = 5L, maxEntryBytes = 5L))

            val result = store.putFile(state, source.toString(), "big.bin", "", "", 100L)

            assertEquals(WorkspaceAdmission.TOO_LARGE, result.admission)
            assertNull(result.entry)
            assertEquals(emptyList(), result.state.entries)
            assertEquals(emptyList(), store.load().entries)
            assertFalse(FileSystem.SYSTEM.exists(directory.resolve("Workspace/objects")))
            assertFalse(FileSystem.SYSTEM.exists(directory.resolve("Workspace/incoming")), "没有半份文件")
        }

    /// 空间不足时拒绝新条目，已有条目不动。
    @Test
    fun `put file refuses when the workspace is full`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val first = directory.resolve("a.txt")
            first.writeText("aaaa")
            val second = directory.resolve("b.txt")
            second.writeText("bbbb")
            val state = WorkspaceState(policy = WorkspacePolicy(maxTotalBytes = 6L, maxEntryBytes = 6L))
            val stored = store.putFile(state, first.toString(), "a.txt", "", "", 100L)

            val result = store.putFile(stored.state, second.toString(), "b.txt", "", "", 200L)

            assertEquals(WorkspaceAdmission.QUOTA_EXCEEDED, result.admission)
            assertNull(result.entry)
            assertEquals(1, store.load().entries.size)
            assertFalse(store.hasContent(digestOf("bbbb")))
        }

    /// 源文件读不动时返回 `FAILED`，不写坏索引。
    @Test
    fun `put file reports a missing source as failed`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)

            val result = store.putFile(
                state = WorkspaceState(),
                sourcePath = directory.resolve("没有这个文件").toString(),
                displayName = "没有这个文件",
                contentType = "",
                originDeviceId = "",
                nowEpochSeconds = 100L,
            )

            assertEquals(WorkspaceAdmission.FAILED, result.admission)
            assertNull(result.entry)
            assertEquals(WorkspaceState(), store.load())
        }

    /// 放入一段文字：内容按摘要落盘，条目进索引。
    @Test
    fun `put text writes the content and records the entry`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)

            val result = store.putText(
                state = WorkspaceState(),
                text = "剪贴板里的一段字",
                displayName = "剪贴板里的一段字.txt",
                contentType = "text/plain",
                originDeviceId = "",
                nowEpochSeconds = 100L,
            )

            assertEquals(WorkspaceAdmission.ACCEPTED, result.admission)
            val entry = result.entry!!
            assertEquals(WorkspaceKind.TEXT, entry.kind)
            assertEquals("剪贴板里的一段字.txt", entry.displayName)
            assertEquals(entry.byteSize, "剪贴板里的一段字".encodeToByteArray().size.toLong())
            assertEquals("剪贴板里的一段字", store.readContent(entry.entryId)?.decodeToString())
        }

    /// 同一段文字放两次只留一条，不留第二份文件。
    @Test
    fun `put text merges the same content into one entry`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val first = store.putText(WorkspaceState(), "same", "a.txt", "text/plain", "", 100L)

            val second = store.putText(first.state, "same", "b.txt", "text/plain", "", 200L)

            assertEquals(WorkspaceAdmission.DUPLICATE, second.admission)
            assertEquals(first.entry?.entryId, second.entry?.entryId)
            assertEquals(1, FileSystem.SYSTEM.list(directory.resolve("Workspace/objects")).size)
        }

    /// 内容超过单条目上限时不落盘。
    @Test
    fun `put text refuses content over the entry limit`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val state = WorkspaceState(policy = WorkspacePolicy(maxTotalBytes = 5L, maxEntryBytes = 5L))

            val result = store.putText(state, "0123456789", "big.txt", "text/plain", "", 100L)

            assertEquals(WorkspaceAdmission.TOO_LARGE, result.admission)
            assertNull(result.entry)
            assertFalse(FileSystem.SYSTEM.exists(directory.resolve("Workspace/incoming")), "没有半份文件")
        }

    @Test
    fun `pinning and removing rewrite the index`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val entryId = store.importContent("x".encodeToByteArray())!!
            val state = store.save(WorkspaceState(entries = listOf(entry(entryId, bytes = 1L))))

            val pinned = store.setPinned(state, entryId, pinned = true)
            assertTrue(pinned.entries.single().pinned)
            assertTrue(store.load().entries.single().pinned)

            val removed = store.remove(pinned, entryId, NOW_EPOCH_SECONDS)
            assertEquals(emptyList(), removed.entries)
            assertEquals(emptyList(), store.load().entries)
            assertFalse(store.hasContent(entryId), "删除条目要连内容一起删")
        }

    /// 摘要不合法的条目改不动，也不会被写成空索引。
    @Test
    fun `pinning and removing ignore malformed digests`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val entryId = store.importContent("x".encodeToByteArray())!!
            val state = store.save(WorkspaceState(entries = listOf(entry(entryId, bytes = 1L))))

            assertEquals(state, store.setPinned(state, "../escape", pinned = true))
            assertEquals(state, store.remove(state, "../escape", NOW_EPOCH_SECONDS))
            assertEquals(1, store.load().entries.size)
        }

    // MARK: - 删除标记

    /// 删条目时留下标记。标记挡住的是对端晚一步的复制。
    @Test
    fun `removing an entry leaves a tombstone`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val entryId = store.importContent("x".encodeToByteArray())!!
            val state = store.save(WorkspaceState(entries = listOf(entry(entryId, bytes = 1L))))

            store.remove(state, entryId, NOW_EPOCH_SECONDS)

            val marks = store.loadTombstones()
            assertEquals(listOf(entryId), marks.map { it.entryId })
            assertEquals(NOW_EPOCH_SECONDS, marks.single().deletedAtEpochSeconds)
        }

    /// 标记写不进去时什么都不删。删了内容又没有标记，对端会把它复制回来。
    @Test
    fun `removing an entry keeps it when the tombstone cannot be written`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val entryId = store.importContent("x".encodeToByteArray())!!
            val state = store.save(WorkspaceState(entries = listOf(entry(entryId, bytes = 1L))))
            // 把 `.tmp` 占成目录，原子改名就写不进去。
            FileSystem.SYSTEM.createDirectories(directory.resolve("Workspace/tombstones.json.tmp"))

            assertEquals(state, store.remove(state, entryId, NOW_EPOCH_SECONDS))
            assertEquals(1, store.load().entries.size)
            assertTrue(store.hasContent(entryId), "标记没写成，内容也要留着")
        }

    /// 标记单独存一个文件，跨重启读得回来。
    @Test
    fun `tombstones round trip through a reload`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val entryId = digestOf("gone")
            assertTrue(store.markDeleted(entryId, NOW_EPOCH_SECONDS))

            assertEquals(entryId, storeIn(directory).loadTombstones().single().entryId)
        }

    /// 摘要不合法的标记丢掉：它挡不住任何东西，还会把文件撑大。
    @Test
    fun `load tombstones drops the malformed marks`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val good = digestOf("good")
            FileSystem.SYSTEM.createDirectories(directory.resolve("Workspace"))
            FileSystem.SYSTEM.write(directory.resolve("Workspace/tombstones.json")) {
                writeUtf8(
                    """[{"entryId":"nope","deletedAtEpochSeconds":1},""" +
                        """{"entryId":"$good","deletedAtEpochSeconds":2}]""",
                )
            }

            assertEquals(listOf(good), store.loadTombstones().map { it.entryId })
        }

    /// 坏掉的标记文件当作没有标记，不抛异常。
    @Test
    fun `load tombstones ignores a corrupt file`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            FileSystem.SYSTEM.createDirectories(directory.resolve("Workspace"))
            FileSystem.SYSTEM.write(directory.resolve("Workspace/tombstones.json")) { writeUtf8("{") }

            assertEquals(emptyList(), store.loadTombstones())
        }

    /// 保留期过了的标记在清理时丢掉。
    @Test
    fun `sweep prunes tombstones past the retention window`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val old = digestOf("old")
            val fresh = digestOf("fresh")
            store.saveTombstonesReporting(
                listOf(
                    WorkspaceTombstone(old, NOW_EPOCH_SECONDS - (WorkspaceLogic.TOMBSTONE_RETENTION_DAYS + 1) * SECONDS_PER_DAY),
                    WorkspaceTombstone(fresh, NOW_EPOCH_SECONDS),
                ),
            )

            store.sweep(WorkspacePolicy(), NOW_EPOCH_SECONDS)

            assertEquals(listOf(fresh), store.loadTombstones().map { it.entryId })
        }

    /// 保留期内的标记清理不动：它还要继续拦人。
    @Test
    fun `sweep keeps the tombstones inside the retention window`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val kept = digestOf("kept")
            store.saveTombstonesReporting(listOf(WorkspaceTombstone(kept, NOW_EPOCH_SECONDS)))

            store.sweep(WorkspacePolicy(), NOW_EPOCH_SECONDS)

            assertEquals(listOf(kept), store.loadTombstones().map { it.entryId })
        }

    /// 清空工作区时标记一起删。留着会拦住用户重新放入同样的内容。
    @Test
    fun `clear drops the tombstones`() =
        withTemporaryDirectory("workspace") { directory ->
            val store = storeIn(directory)
            val entryId = digestOf("gone")
            store.markDeleted(entryId, NOW_EPOCH_SECONDS)
            assertTrue(FileSystem.SYSTEM.exists(directory.resolve("Workspace/tombstones.json")))

            store.clear()

            assertEquals(emptyList(), store.loadTombstones())
            assertFalse(FileSystem.SYSTEM.exists(directory.resolve("Workspace/tombstones.json")))
        }
}

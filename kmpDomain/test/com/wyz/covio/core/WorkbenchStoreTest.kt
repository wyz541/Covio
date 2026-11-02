package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import okio.FileSystem
import okio.Path
import okio.Path.Companion.toPath

/**
 * 工作台配置的模型与持久化。
 *
 * 验收标准来自 issue #78：重启应用后布局不变；配置损坏时回退默认布局，工作台仍可用。
 * 所以这里除了往返，还盯着三种坏文件：整份坏掉、一条工作区坏掉、一条组件坏掉。
 */
class WorkbenchStoreTest {
    private fun storeAt(directory: Path): WorkbenchStore =
        WorkbenchStore(directory.resolve("workbench.json").toString())

    @Test
    fun `store round trips panes order and home widgets`() =
        withTemporaryDirectory("workbench") { directory ->
            val store = storeAt(directory)
            val config = WorkbenchConfig.defaults()
                .renamePane("now", "此刻")
                .movePane("settings", 0)
                .setPaneHidden("devices", true)
                .copy(
                    homeWidgets = listOf(
                        WidgetInstance(
                            id = "w1",
                            kind = "clock",
                            size = WidgetSize.WIDE,
                            column = 2,
                            row = 3,
                        ),
                    ),
                )

            store.save(config)

            assertEquals(config.normalized(), store.load())
        }

    @Test
    fun `a missing file loads the documented builtin panes and hides fixed-entry panes`() =
        withTemporaryDirectory("workbench") { directory ->
            val path = directory.resolve("workbench.json")

            val config = WorkbenchStore(path.toString()).load()

            assertEquals(
                listOf("now", "agent", "clipboard", "files", "devices", "settings"),
                config.panes.map { it.id },
            )
            assertEquals(
                listOf("now", "clipboard", "files", "devices"),
                config.visiblePanes.map { it.id },
            )
            // 首页默认放六块组件，与打样的 `defaultWidgets()` 一致。
            // 空列表会让真机首次启动的首页是空的，与打样对不上。
            assertEquals(
                listOf("w-clock", "w-battery", "w-transfer", "w-actions", "w-shots", "w-devices"),
                config.homeWidgets.map { it.id },
            )
            assertFalse(path.exists, "读的时候不该建文件")
        }

    @Test
    fun `schema one screenshot pane migrates into the files area`() =
        withTemporaryDirectory("workbench") { directory ->
            val path = directory.resolve("workbench.json")
            path.writeText(
                """
                {
                  "schemaVersion": 1,
                  "panes": [
                    {"id": "now", "kind": "now"},
                    {"id": "screenshots", "kind": "screenshots", "title": "旧截图", "isHidden": true},
                    {"id": "files", "kind": "files", "title": "资料"},
                    {"id": "mine", "kind": "board", "title": "我的"},
                    {"id": "settings", "kind": "settings"}
                  ],
                  "homeWidgets": []
                }
                """.trimIndent(),
            )

            val config = WorkbenchStore(path.toString()).load()

            assertEquals(WORKBENCH_SCHEMA_VERSION, config.schemaVersion)
            assertEquals(
                listOf("now", "files", "mine", "settings", "agent", "clipboard", "devices"),
                config.panes.map { it.id },
            )
            assertEquals("资料", config.pane("files")?.title, "文件工作区的自定义名称要保留")
            assertNull(config.pane("screenshots"), "当前 schema 不再保留截图工作区")
        }

    @Test
    fun `a corrupt file falls back to the default layout`() =
        withTemporaryDirectory("workbench") { directory ->
            val path = directory.resolve("workbench.json")
            path.writeText("{ 这不是 JSON")

            assertEquals(WorkbenchConfig.defaults(), WorkbenchStore(path.toString()).load())
        }

    /**
     * 一条工作区坏掉时只丢那一条。
     *
     * 补回来的内置工作区排在末尾：原位置已经丢了，插在中间会打乱用户排好的顺序。
     */
    @Test
    fun `one unreadable pane does not take the others down`() =
        withTemporaryDirectory("workbench") { directory ->
            val path = directory.resolve("workbench.json")
            path.writeText(
                """
                {
                  "schemaVersion": 1,
                  "panes": [
                    {"id": "now", "kind": "now"},
                    {"id": "broken", "kind": "没有这个模块"},
                    {"id": "mine", "kind": "board", "title": "我的"}
                  ],
                  "homeWidgets": []
                }
                """.trimIndent(),
            )

            val config = WorkbenchStore(path.toString()).load()

            assertEquals(
                listOf("now", "mine", "agent", "clipboard", "files", "devices", "settings"),
                config.panes.map { it.id },
            )
        }

    @Test
    fun `a builtin pane cannot be removed but can be hidden`() {
        val config = WorkbenchConfig.defaults()

        assertEquals(config, config.removePane("now"), "内置工作区不该被删掉")

        val hidden = config.setPaneHidden("now", true)

        assertNotNull(hidden.pane("now"), "隐藏之后条目还在文件里，只是 tab bar 不画")
        assertTrue(hidden.pane("now")!!.isHidden)
        assertEquals(
            listOf("clipboard", "files", "devices"),
            hidden.visiblePanes.map { it.id },
        )
    }

    @Test
    fun `assistant and settings never appear in workbench navigation`() {
        val visible = WorkbenchConfig.defaults().visiblePanes.map { it.kind }

        assertFalse(PaneKind.AGENT in visible)
        assertFalse(PaneKind.SETTINGS in visible)
    }

    @Test
    fun `a custom pane can be added and removed`() {
        val board = PaneInstance(id = "mine", kind = PaneKind.BOARD, title = "我的")

        val added = WorkbenchConfig.defaults().addPane(board)
        assertEquals("mine", added.panes.last().id)

        val removed = added.removePane("mine")
        assertNull(removed.pane("mine"))
        assertEquals(WorkbenchConfig.defaults(), removed)
    }

    @Test
    fun `addPane refuses a builtin kind a taken id and a full list`() {
        val fresh = WorkbenchConfig.defaults()
        assertEquals(fresh, fresh.addPane(PaneInstance.builtin(PaneKind.NOW)), "内置工作区不该由用户加出来")
        assertEquals(fresh, fresh.addPane(PaneInstance.builtin(PaneKind.SCREENSHOTS)), "历史截图工作区也不该由用户加出来")
        assertEquals(fresh, fresh.addPane(PaneInstance(id = "now", kind = PaneKind.BOARD)), "id 撞车了")

        val full = WorkbenchConfig(panes = (0 until 20).map { PaneInstance(id = "c$it", kind = PaneKind.BOARD) }).normalized()
        assertEquals(WorkbenchConfig.MAX_PANES, full.panes.size)
        assertEquals(full, full.addPane(PaneInstance(id = "extra", kind = PaneKind.BOARD)), "到上限了")
    }

    /** 超过上限时先丢自建工作区。内置的一个都不丢，否则「设置」会消失。 */
    @Test
    fun `the pane cap drops custom panes and never a builtin`() {
        val customs = (0 until 20).map { PaneInstance(id = "c$it", kind = PaneKind.BOARD) }

        val config = WorkbenchConfig(panes = customs).normalized()

        assertEquals(WorkbenchConfig.MAX_PANES, config.panes.size)
        assertEquals(6, config.panes.count { it.isBuiltin })
        assertEquals((0 until 6).map { "c$it" }, config.panes.filterNot { it.isBuiltin }.map { it.id })
    }

    @Test
    fun `a duplicate pane id keeps the first entry`() {
        val config = WorkbenchConfig(
            panes = listOf(
                PaneInstance(id = "mine", kind = PaneKind.BOARD, title = "第一个"),
                PaneInstance(id = "mine", kind = PaneKind.BOARD, title = "第二个"),
            ),
        ).normalized()

        assertEquals("第一个", config.pane("mine")?.title)
    }

    /**
     * 内置工作区的 id 由种类定。
     *
     * 手改过的文件里 id 与种类可能对不上。照抄那个 id，补回来的内置工作区就会撞车，
     * 于是出现两个 id 相同的页签。
     */
    @Test
    fun `a builtin pane takes its id from its kind`() {
        val config = WorkbenchConfig(
            panes = listOf(
                PaneInstance(id = "now", kind = PaneKind.CLIPBOARD, title = "错位的"),
                PaneInstance(id = "clipboard", kind = PaneKind.BOARD, title = "偷了保留 id 的"),
            ),
        ).normalized()

        assertEquals(config.panes.size, config.panes.map { it.id }.distinct().size, "id 撞车了")
        assertEquals("错位的", config.pane("clipboard")?.title)
        assertEquals(PaneKind.NOW, config.pane("now")?.kind)
        assertNull(config.panes.firstOrNull { it.title == "偷了保留 id 的" })
    }

    @Test
    fun `a key this version does not know survives a save`() =
        withTemporaryDirectory("workbench") { directory ->
            val path = directory.resolve("workbench.json")
            path.writeText("""{"schemaVersion":1,"panes":[],"homeWidgets":[],"futureThing":{"a":1}}""")
            val store = WorkbenchStore(path.toString())

            store.save(store.load())

            assertTrue(path.readText().contains("futureThing"), "本版不认识的顶层键被抹掉了")
        }

    @Test
    fun `widgets keep an unknown kind but lose a blank id`() {
        val widgets = listOf(
            WidgetInstance(id = "w1", kind = "clock", size = WidgetSize.WIDE),
            WidgetInstance(id = "", kind = "clock"),
            WidgetInstance(id = "w3", kind = ""),
            WidgetInstance(id = "w1", kind = "battery"),
            WidgetInstance(id = "w5", kind = "brand-new-widget"),
        )

        val config = WorkbenchConfig(homeWidgets = widgets).normalized()

        assertEquals(listOf("w1", "w5"), config.homeWidgets.map { it.id })
        assertEquals(WidgetSize.WIDE, config.homeWidgets.first().size, "id 重复时留第一个")
    }

    /** 尺寸认不出时缩小一档显示就好，没有理由丢掉用户排好的卡片。 */
    @Test
    fun `an unknown widget size falls back instead of dropping the widget`() =
        withTemporaryDirectory("workbench") { directory ->
            val path = directory.resolve("workbench.json")
            path.writeText(
                """{"schemaVersion":1,"panes":[],"homeWidgets":[{"id":"w1","kind":"clock","size":"巨大"}]}""",
            )

            val config = WorkbenchStore(path.toString()).load()

            assertEquals(WidgetSize.FALLBACK, config.homeWidgets.single().size)
            assertEquals(-1, config.homeWidgets.single().column)
            assertEquals(-1, config.homeWidgets.single().row)
            assertEquals(WORKBENCH_SCHEMA_VERSION, config.schemaVersion)
        }

    @Test
    fun `a partial widget position becomes automatic`() =
        withTemporaryDirectory("workbench") { directory ->
            val path = directory.resolve("workbench.json")
            path.writeText(
                """{"schemaVersion":2,"panes":[],"homeWidgets":[{"id":"w1","kind":"clock","column":2}]}""",
            )

            val widget = WorkbenchStore(path.toString()).load().homeWidgets.single()

            assertEquals(WIDGET_AUTOMATIC_POSITION, widget.column)
            assertEquals(WIDGET_AUTOMATIC_POSITION, widget.row)
        }

    @Test
    fun `widget positions use stable json field names`() =
        withTemporaryDirectory("workbench") { directory ->
            val path = directory.resolve("workbench.json")
            val store = WorkbenchStore(path.toString())
            store.save(
                WorkbenchConfig.defaults().copy(
                    homeWidgets = listOf(
                        WidgetInstance(
                            id = "w1",
                            kind = "clock",
                            column = 2,
                            row = 3,
                        ),
                    ),
                ),
            )

            val json = path.readText()
            assertTrue(json.contains("\"column\": 2"), json)
            assertTrue(json.contains("\"row\": 3"), json)
        }

    @Test
    fun `clear removes the file and load returns defaults`() =
        withTemporaryDirectory("workbench") { directory ->
            val path = directory.resolve("workbench.json")
            val store = WorkbenchStore(path.toString())
            store.save(WorkbenchConfig.defaults().addPane(PaneInstance(id = "mine", kind = PaneKind.BOARD)))

            assertTrue(path.exists)
            assertTrue(store.clear())
            assertFalse(path.exists)
            assertEquals(WorkbenchConfig.defaults(), store.load())
        }

    /// 保存时先写 `.tmp` 再原子改名，所以目录里不留临时文件。
    @Test
    fun `save leaves no temporary file behind`() =
        withTemporaryDirectory("workbench") { directory ->
            storeAt(directory).save(WorkbenchConfig.defaults())

            val leftovers = FileSystem.SYSTEM.list(directory).map { it.name }.filter { it.endsWith(".tmp") }
            assertEquals(emptyList(), leftovers)
        }

    /**
     * 写不进去时不抛异常。
     *
     * Kotlin 的异常跨到 Swift 没有接收方，会直接终止进程。
     * 落盘是每次改布局都会跑的一步，磁盘满或者目录被删就会走到这里。
     */
    @Test
    fun `save swallows write failures`() =
        withTemporaryDirectory("workbench") { directory ->
            // 拿一个普通文件当目录用，写它下面的路径一定失败。
            val blocker = directory.resolve("blocker")
            blocker.writeText("not a directory")

            val store = WorkbenchStore(blocker.resolve("workbench.json").toString())

            // 不抛异常，而且照常返回规范化之后的结果。
            assertEquals(WorkbenchConfig.defaults(), store.save(WorkbenchConfig.defaults()))
        }

    /** 种类的键既是序列化用的名字，也是内置工作区的固定 id。两者必须一致。 */
    @Test
    fun `the pane kind keys match what goes into the file`() {
        val json = WorkbenchStore.defaultJson()

        for (kind in PaneKind.entries) {
            assertEquals("\"${kind.key}\"", json.encodeToString(PaneKind.serializer(), kind), "${kind.name} 的键与 @SerialName 不一致")
        }
    }

    /** 固定 id 让宿主随时找得到「设置」这个工作区，用户改名也不影响。 */
    @Test
    fun `a builtin pane keeps its id after a rename`() {
        val renamed = WorkbenchConfig.defaults().renamePane("settings", "偏好")

        assertEquals("偏好", renamed.pane("settings")?.title)
        assertEquals("settings", renamed.pane("settings")?.id)
    }

    /**
     * 内置工作区的显示名来自设计合同，不在模型里写死。
     *
     * 名字写死在模型里，换语言时不会跟着变。所以模型只给文案键，
     * 宿主用这个键读生成的 `ContractCopy`。
     */
    @Test
    fun `every builtin pane reads its name from the design contract`() {
        val contractPath = sequenceOf(
            "docs/covio-design-contract.json",
            "../docs/covio-design-contract.json",
            "../../docs/covio-design-contract.json",
        ).firstOrNull { FileSystem.SYSTEM.exists(it.toPath()) }
        assertNotNull(contractPath, "找不到设计合同。工作目录是 ${FileSystem.SYSTEM.canonicalize(".".toPath())}")

        val result = DesignContractReader.read(contractPath)
        val contract = assertNotNull(result.contract, "设计合同读不出来：${result.errors.map { it.describe() }}")

        for (kind in PaneKind.entries.filter { it.isBuiltin }) {
            val key = assertNotNull(kind.titleCopyKey, "${kind.name} 是内置工作区，应当有文案键")
            assertNotNull(contract.entry(key), "$key 不在设计合同的 copy 段里")
        }
        assertNull(PaneKind.BOARD.titleCopyKey, "自建工作区没有内置名字")
    }
}

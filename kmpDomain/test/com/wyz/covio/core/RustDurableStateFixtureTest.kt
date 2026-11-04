package com.wyz.covio.core

import kotlinx.serialization.json.JsonElement
import okio.FileSystem
import okio.Path.Companion.toPath
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/**
 * Rust 与 Kotlin 共用的 durable-state 语料。
 *
 * Rust 侧 `durable_state_compatibility.rs` 读取同一对 fixture。
 */
class RustDurableStateFixtureTest {
    private val fixtureDirectory: String? = sequenceOf(
        "rust/crates/covio-core/tests/fixtures",
        "../rust/crates/covio-core/tests/fixtures",
        "../../rust/crates/covio-core/tests/fixtures",
    ).firstOrNull { FileSystem.SYSTEM.exists(it.toPath()) }

    private fun fixture(name: String): String {
        val directory = assertNotNull(fixtureDirectory, "找不到 Rust durable-state fixture")
        return FileSystem.SYSTEM.read("$directory/$name".toPath()) { readUtf8() }
    }

    private fun json(text: String): JsonElement =
        ConfigStore.defaultJson().parseToJsonElement(text)

    @Test
    fun `shelf fixture round trips through Kotlin`() =
        withTemporaryDirectory("rust-shelf-fixture") { directory ->
            val screenshot = directory.resolve("screenshot.png")
            screenshot.writeText("image")
            val fixtureText = fixture("shelf-state.json")
                .replace("__SCREENSHOT_PATH__", screenshot.toString())
            val path = directory.resolve("shelf.json")
            path.writeText(fixtureText)

            val store = ShelfStore(path.toString())
            store.save(store.load())

            assertEquals(json(fixtureText), json(path.readText()))
        }

    @Test
    fun `clipboard fixture round trips through Kotlin`() =
        withTemporaryDirectory("rust-clipboard-fixture") { directory ->
            val fixtureText = fixture("clipboard-state.json")
            val path = directory.resolve("clipboard.json")
            path.writeText(fixtureText)

            val store = ClipboardStore(path.toString())
            store.save(store.load())

            assertEquals(json(fixtureText), json(path.readText()))
        }
}

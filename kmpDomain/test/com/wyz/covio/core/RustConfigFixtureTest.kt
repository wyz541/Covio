package com.wyz.covio.core

import kotlinx.serialization.json.JsonElement
import okio.FileSystem
import okio.Path.Companion.toPath
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/**
 * Rust 与 Kotlin 共用的配置语料。
 *
 * Rust 侧的 `config_compatibility.rs` 读取同一对 fixture。
 * 这组测试保证 Kotlin 写出的字段、默认值和迁移结果仍与 Rust 对照一致。
 */
class RustConfigFixtureTest {
    private val fixtureDirectory: String? = sequenceOf(
        "rust/crates/covio-core/tests/fixtures",
        "../rust/crates/covio-core/tests/fixtures",
        "../../rust/crates/covio-core/tests/fixtures",
    ).firstOrNull { FileSystem.SYSTEM.exists(it.toPath()) }

    private fun fixture(name: String): JsonElement {
        val directory = assertNotNull(fixtureDirectory, "找不到 Rust 配置 fixture")
        val text = FileSystem.SYSTEM.read("$directory/$name".toPath()) { readUtf8() }
        return ConfigStore.defaultJson().parseToJsonElement(text)
    }

    @Test
    fun `the current Kotlin config round trips the shared fixture`() =
        withTemporaryDirectory("rust-config-current") { directory ->
            val current = fixture("config-v3-current.json")
            val path = directory.resolve("config.json")
            path.writeText(ConfigStore.defaultJson().encodeToString(JsonElement.serializer(), current))

            val store = ConfigStore(path.toString())
            store.save(store.load())

            val saved = ConfigStore.defaultJson().parseToJsonElement(path.readText())
            assertEquals(current, saved)
        }

    @Test
    fun `the legacy Kotlin fixture upgrades to the current shared fixture`() =
        withTemporaryDirectory("rust-config-legacy") { directory ->
            val legacy = fixture("config-v3-legacy-21.json")
            val current = fixture("config-v3-current.json")
            val path = directory.resolve("config.json")
            path.writeText(ConfigStore.defaultJson().encodeToString(JsonElement.serializer(), legacy))

            val store = ConfigStore(path.toString())
            store.save(store.load())

            val saved = ConfigStore.defaultJson().parseToJsonElement(path.readText())
            assertEquals(current, saved)
        }
}

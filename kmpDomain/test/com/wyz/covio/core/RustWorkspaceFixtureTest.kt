package com.wyz.covio.core

import kotlinx.serialization.json.JsonElement
import okio.FileSystem
import okio.Path.Companion.toPath
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull

/** Rust 与 Kotlin 共用的 workspace fixture。 */
class RustWorkspaceFixtureTest {
    private val fixtureDirectory: String? = sequenceOf(
        "rust/crates/covio-core/tests/fixtures",
        "../rust/crates/covio-core/tests/fixtures",
        "../../rust/crates/covio-core/tests/fixtures",
    ).firstOrNull { FileSystem.SYSTEM.exists(it.toPath()) }

    private fun fixture(name: String): String {
        val directory = assertNotNull(fixtureDirectory, "找不到 Rust workspace fixture")
        return FileSystem.SYSTEM.read("$directory/$name".toPath()) { readUtf8() }
    }

    private fun json(text: String): JsonElement =
        ConfigStore.defaultJson().parseToJsonElement(text)

    @Test
    fun `workspace index fixture round trips through Kotlin`() =
        withTemporaryDirectory("rust-workspace-index") { directory ->
            val text = fixture("workspace-index.json")
            val path = directory.resolve("index.json")
            path.writeText(text)
            val store = WorkspaceStore(directory.toString())

            store.save(store.load())

            assertEquals(json(text), json(path.readText()))
        }

    @Test
    fun `workspace tombstones round trip through Kotlin`() =
        withTemporaryDirectory("rust-workspace-tombstones") { directory ->
            val text = fixture("workspace-tombstones.json")
            val path = directory.resolve("tombstones.json")
            path.writeText(text)
            val store = WorkspaceStore(directory.toString())

            store.saveTombstonesReporting(store.loadTombstones())

            assertEquals(json(text), json(path.readText()))
        }

    @Test
    fun `workspace request and response fixtures keep the wire shape`() {
        val requestText = fixture("workspace-request.json")
        val request = assertNotNull(WorkspaceWire.decodeRequest(requestText))
        assertEquals(json(requestText), json(WorkspaceWire.encode(request)))
        assertIs<WorkspaceEntryParse.Ok>(WorkspaceWire.entry(request.args))

        val responseText = fixture("workspace-response.json")
        val response = assertNotNull(WorkspaceWire.decodeResponse(responseText))
        assertEquals(json(responseText), json(WorkspaceWire.encode(response)))
    }
}

package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PowerHistoryTest {
    @Test
    fun `store round trips bounded events`() = withTemporaryDirectory("power-history") { directory ->
        val store = PowerHistoryStore(directory.resolve("history.json").toString())
        val event = event("a", PowerHistoryKind.ADAPTER_CONNECTED, 10, "84%")

        val state = assertNotNull(store.append(event, nowEpochSeconds = 10))

        assertEquals(listOf(event), state.events)
        assertEquals(state, store.load(nowEpochSeconds = 10))
    }

    @Test
    fun `prune keeps the newest events up to the hard limit`() {
        val events = (0..5).map { event("e$it", PowerHistoryKind.SLEPT, it.toLong()) }

        val kept = PowerHistoryLogic.prune(
            events = events,
            policy = PowerHistoryPolicy(maxEvents = 3, maxAgeDays = 7),
            nowEpochSeconds = 5,
        )

        assertEquals(listOf("e5", "e4", "e3"), kept.map(PowerHistoryEvent::id))
    }

    @Test
    fun `prune drops events older than the retention window`() {
        val now = 10L * 24 * 60 * 60
        val stale = now - 8L * 24 * 60 * 60

        val kept = PowerHistoryLogic.prune(
            events = listOf(
                event("stale", PowerHistoryKind.FULL_WAKE, stale),
                event("fresh", PowerHistoryKind.DARK_WAKE, now),
            ),
            policy = PowerHistoryPolicy(maxAgeDays = 7),
            nowEpochSeconds = now,
        )

        assertEquals(listOf("fresh"), kept.map(PowerHistoryEvent::id))
    }

    @Test
    fun `recent returns only the requested window`() {
        val now = 1_000L
        val kept = PowerHistoryLogic.recent(
            events = listOf(
                event("old", PowerHistoryKind.SLEPT, 100),
                event("new", PowerHistoryKind.FULL_WAKE, 950),
            ),
            nowEpochSeconds = now,
            windowSeconds = 100,
        )

        assertEquals(listOf("new"), kept.map(PowerHistoryEvent::id))
    }

    @Test
    fun `append leaves no temporary file behind`() = withTemporaryDirectory("power-history") { directory ->
        val store = PowerHistoryStore(directory.resolve("history.json").toString())
        store.append(event("a", PowerHistoryKind.HOLD_STARTED, 1), nowEpochSeconds = 1)

        val leftovers = okio.FileSystem.SYSTEM.list(directory)
            .map { it.name }
            .filter { it.endsWith(".tmp") }
        assertEquals(emptyList(), leftovers)
    }

    @Test
    fun `append returns null when the file cannot be written`() =
        withTemporaryDirectory("power-history") { directory ->
            val blocker = directory.resolve("blocker")
            blocker.writeText("not a directory")
            val store = PowerHistoryStore(blocker.resolve("history.json").toString())

            assertNull(store.append(event("a", PowerHistoryKind.SLEPT, 1), nowEpochSeconds = 1))
            assertEquals("not a directory", blocker.readText())
        }

    @Test
    fun `corrupt history loads as an empty state`() =
        withTemporaryDirectory("power-history") { directory ->
            val path = directory.resolve("history.json")
            path.writeText("{")
            val store = PowerHistoryStore(path.toString())

            assertEquals(PowerHistoryState(), store.load(nowEpochSeconds = 1))
        }

    @Test
    fun `clear removes history and a temporary file`() =
        withTemporaryDirectory("power-history") { directory ->
            val path = directory.resolve("history.json")
            val temporary = directory.resolve("history.json.tmp")
            temporary.writeText("partial")
            val store = PowerHistoryStore(path.toString())
            store.append(event("a", PowerHistoryKind.SLEPT, 1), nowEpochSeconds = 1)

            assertTrue(store.clear())
            assertFalse(path.exists)
            assertFalse(temporary.exists)
        }

    @Test
    fun `default path sits next to the shared config`() {
        assertTrue(
            defaultPowerHistoryPath().endsWith("${AppDirectories.userApplicationSupport}/$APP_ID/Power/history.json"),
            "实际值：${defaultPowerHistoryPath()}",
        )
    }

    private fun event(
        id: String,
        kind: PowerHistoryKind,
        atEpochSeconds: Long,
        detail: String = "",
    ): PowerHistoryEvent = PowerHistoryEvent(
        id = id,
        kind = kind,
        atEpochSeconds = atEpochSeconds,
        detail = detail,
    )
}

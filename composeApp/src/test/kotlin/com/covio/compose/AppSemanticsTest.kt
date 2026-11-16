package com.covio.compose

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import com.wyz.covio.bridge.CovioClient
import com.wyz.covio.bridge.CovioSessionConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import java.awt.Canvas
import java.awt.event.KeyEvent
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class AppSemanticsTest {
    @OptIn(ExperimentalComposeUiApi::class)
    @Test
    fun screensExposeLabelsTargetsAndKeyboardFocus() {
        val root = Files.createTempDirectory("covio-compose-semantics").toFile()
        val client = CovioClient(config(root.absolutePath))
        val adapters = PlatformAdapters(client)
        val controller = AppController(client, adapters)
        val scene = ImageComposeScene(
            width = 1180,
            height = 820,
            density = Density(1f),
            layoutDirection = LayoutDirection.Ltr,
            coroutineContext = Dispatchers.Unconfined,
        ) {
            CovioApp(
                controller = controller,
                darkTheme = false,
                initializeOnLaunch = false,
                pollEvents = false,
            )
        }
        try {
            runBlocking { controller.initialize() }
            Screen.entries.forEach { screen ->
                controller.selectScreen(screen)
                if (screen == Screen.Pair) {
                    runBlocking { controller.startPairing() }
                }
                settle(scene)
                val nodes = scene.semanticsOwners.flatMap { it.rootSemanticsNode.flatten() }
                val clickable = nodes.filter { it.config.contains(SemanticsActions.OnClick) }
                assertTrue(clickable.isNotEmpty(), "$screen has no clickable semantics")
                clickable.forEach { node ->
                    assertTrue(node.label().isNotBlank(), "$screen has an unlabeled control ${node.id}")
                    assertTrue(
                        node.boundsInRoot.height >= 44f,
                        "$screen control ${node.label()} is shorter than 44dp at ${node.boundsInRoot}",
                    )
                }
            }

            controller.selectScreen(Screen.Devices)
            settle(scene)
            val initialNodes = scene.semanticsOwners.flatMap { it.rootSemanticsNode.flatten() }
            val tabs = initialNodes.filter { node ->
                node.config.contains(SemanticsProperties.ContentDescription) &&
                    node.config[SemanticsProperties.ContentDescription].any { it.endsWith(" tab") }
            }
            assertEquals(Screen.entries.size, tabs.size)
            tabs.forEach { assertEquals(Role.Tab, it.config[SemanticsProperties.Role]) }
            assertEquals(1, tabs.count { it.config[SemanticsProperties.Selected] })

            val focusTargets = mutableSetOf<String>()
            repeat(12) {
                sendTab(scene)
                settle(scene)
                scene.semanticsOwners
                    .flatMap { it.rootSemanticsNode.flatten() }
                    .firstOrNull {
                        it.config.contains(SemanticsProperties.Focused) &&
                            it.config[SemanticsProperties.Focused]
                    }
                    ?.let { focusTargets += it.label().ifBlank { it.id.toString() } }
            }
            assertTrue(focusTargets.size >= 4, "Tab reached only $focusTargets")
        } finally {
            scene.close()
            adapters.close()
            client.close()
            root.deleteRecursively()
        }
    }

    private fun settle(scene: ImageComposeScene) {
        repeat(2) { scene.render().close() }
    }

    private fun SemanticsNode.label(): String = buildList {
        if (config.contains(SemanticsProperties.ContentDescription)) {
            addAll(config[SemanticsProperties.ContentDescription])
        }
        if (config.contains(SemanticsProperties.Text)) {
            addAll(config[SemanticsProperties.Text].map { it.text })
        }
    }.filter { it.isNotBlank() }.joinToString(" ")

    private fun SemanticsNode.flatten(): List<SemanticsNode> =
        listOf(this) + children.flatMap { it.flatten() }

    private fun sendTab(scene: ImageComposeScene) {
        val awtEvent = KeyEvent(
            Canvas(),
            KeyEvent.KEY_PRESSED,
            System.currentTimeMillis(),
            0,
            KeyEvent.VK_TAB,
            '\t',
            KeyEvent.KEY_LOCATION_STANDARD,
        )
        val composeEvent = Class.forName("androidx.compose.ui.input.key.KeyEvent_desktopKt")
            .getMethod("toComposeEvent", KeyEvent::class.java)
            .invoke(null, awtEvent)
        val sendKeyEvent = ImageComposeScene::class.java.methods
            .firstOrNull { it.name.startsWith("sendKeyEvent") }
            ?: error("ImageComposeScene.sendKeyEvent is unavailable")
        sendKeyEvent.invoke(scene, composeEvent)
    }

    private fun config(root: String): CovioSessionConfig = CovioSessionConfig(
        dataRoot = root,
        displayName = "Compose semantics test",
        systemName = System.getProperty("os.name"),
        systemVersion = System.getProperty("os.version"),
        appVersion = "test",
        hostAdapters = listOf("file_picker", "notification", "background_task", "app_lifecycle"),
    )
}

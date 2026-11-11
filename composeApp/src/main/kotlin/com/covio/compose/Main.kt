package com.covio.compose

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import com.wyz.covio.bridge.CovioClient
import com.wyz.covio.bridge.CovioSessionConfig
import java.io.File
import java.awt.Dimension

fun main(args: Array<String>) {
    if (args.contains("--headless-smoke")) {
        runHeadlessSmoke(args)
        return
    }
    application {
    val options = LaunchOptions.parse(args)
    val config = CovioSessionConfig(
        dataRoot = options.dataRoot.absolutePath,
        displayName = System.getenv("COMPUTERNAME") ?: "Windows device",
        systemName = System.getProperty("os.name") ?: "Windows",
        systemVersion = System.getProperty("os.version") ?: "unknown",
        appVersion = GeneratedReleaseIdentity.clientVersion,
        hostAdapters = listOf("file_picker", "notification", "background_task", "app_lifecycle"),
    )
    val client = remember { CovioClient(config) }
    val adapters = remember { PlatformAdapters(client) }
    val controller = remember { AppController(client, adapters) }
    val darkTheme = when (options.theme) {
        "dark" -> true
        "light" -> false
        else -> isSystemInDarkTheme()
    }
    val windowState = rememberWindowState(
        width = 1180.dp,
        height = 820.dp,
        position = WindowPosition(Alignment.Center),
    )
    DisposableEffect(Unit) {
        adapters.setForeground()
        onDispose {
            runCatching { adapters.setBackground() }
            adapters.close()
            client.close()
        }
    }
    Window(
        onCloseRequest = ::exitApplication,
        title = "Covio",
        state = windowState,
    ) {
        LaunchedEffect(Unit) {
            window.minimumSize = Dimension(980, 700)
        }
        CovioApp(
            controller = controller,
            darkTheme = darkTheme,
            screenshot = options.screenshot,
            baselineResult = options.baselineResult,
            onScreenshotCaptured = ::exitApplication,
            onBaselineFinished = ::exitApplication,
        )
    }
    }
}

private data class LaunchOptions(
    val theme: String?,
    val screen: Screen,
    val screenshot: ScreenshotSpec?,
    val dataRoot: File,
    val baselineResult: File?,
) {
    companion object {
        fun parse(args: Array<String>): LaunchOptions {
            var theme: String? = null
            var screen = Screen.Devices
            var screenshotPath: File? = null
            var dataRoot = defaultDataRoot()
            var baselineResult: File? = null
            var index = 0
            while (index < args.size) {
                when (val argument = args[index]) {
                    "--theme" -> {
                        theme = args.getOrNull(++index) ?: error("--theme requires light or dark")
                    }
                    "--screen" -> {
                        val value = args.getOrNull(++index) ?: error("--screen requires a value")
                        screen = Screen.entries.firstOrNull { it.name.equals(value, ignoreCase = true) }
                            ?: error("unknown screen: $value")
                    }
                    "--screenshot" -> {
                        val value = args.getOrNull(++index) ?: error("--screenshot requires a path")
                        screenshotPath = File(value).absoluteFile
                    }
                    "--data-dir" -> {
                        val value = args.getOrNull(++index) ?: error("--data-dir requires a path")
                        dataRoot = File(value).absoluteFile
                    }
                    "--baseline-result" -> {
                        val value = args.getOrNull(++index) ?: error("--baseline-result requires a path")
                        baselineResult = File(value).absoluteFile
                    }
                    else -> error("unknown argument: $argument")
                }
                index++
            }
            require(theme == null || theme == "light" || theme == "dark") {
                "--theme must be light or dark"
            }
            return LaunchOptions(
                theme = theme,
                screen = screen,
                screenshot = screenshotPath?.let {
                    ScreenshotSpec(it, theme ?: "light", screen)
                },
                dataRoot = dataRoot,
                baselineResult = baselineResult,
            )
        }

        private fun defaultDataRoot(): File {
            val localAppData = System.getenv("LOCALAPPDATA")
            val root = if (localAppData.isNullOrBlank()) {
                File(System.getProperty("user.home"), ".covio")
            } else {
                File(localAppData, "Covio")
            }
            return root.absoluteFile
        }
    }
}

private fun runHeadlessSmoke(args: Array<String>) {
    val options = LaunchOptions.parse(args.filterNot { it == "--headless-smoke" }.toTypedArray())
    val config = CovioSessionConfig(
        dataRoot = options.dataRoot.absolutePath,
        displayName = System.getenv("COMPUTERNAME") ?: "Windows device",
        systemName = System.getProperty("os.name") ?: "Windows",
        systemVersion = System.getProperty("os.version") ?: "unknown",
        appVersion = GeneratedReleaseIdentity.clientVersion,
        hostAdapters = listOf("file_picker", "notification", "background_task", "app_lifecycle"),
    )
    CovioClient(config).use { client ->
        val snapshot = client.request("app.snapshot")
        check(snapshot["device"] != null)
        println("Compose headless smoke passed")
    }
}

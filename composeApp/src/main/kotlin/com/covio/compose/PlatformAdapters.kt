package com.covio.compose

import com.wyz.covio.bridge.CovioClient
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.JsonPrimitive
import java.awt.Color
import java.awt.Image
import java.awt.SystemTray
import java.awt.TrayIcon
import java.io.File
import java.net.NetworkInterface
import java.util.Collections
import javax.swing.JFileChooser

data class CapabilityLease(
    val leaseId: String,
    val displayName: String,
)

class PlatformAdapters(
    private val client: CovioClient,
) {
    private val trayIcon: TrayIcon? by lazy {
        if (!SystemTray.isSupported()) return@lazy null
        TrayIcon(Color(0x46, 0x56, 0xA4).toImage(), "Covio").also {
            SystemTray.getSystemTray().add(it)
        }
    }

    fun reportCapabilities() {
        client.request(
            "capabilities.report",
            buildJsonObject {
                put(
                    "adapters",
                    kotlinx.serialization.json.buildJsonArray {
                        add(JsonPrimitive("file_picker"))
                        add(JsonPrimitive("notification"))
                        add(JsonPrimitive("background_task"))
                        add(JsonPrimitive("app_lifecycle"))
                    },
                )
            },
        )
    }

    fun updateNetworkStatus() {
        val online = runCatching {
            Collections.list(NetworkInterface.getNetworkInterfaces()).any {
                it.isUp && !it.isLoopback
            }
        }.getOrDefault(false)
        client.request("network.status", buildJsonObject { put("online", online) })
    }

    fun pickFile(): CapabilityLease? {
        val request = client.request(
            "capability.request",
            buildJsonObject {
                put("kind", "file_picker")
                put("purpose", "send_file")
            },
        )
        val requestId = request.string("request_id")
        val chooser = JFileChooser().apply {
            dialogTitle = "Choose a file to send"
            fileSelectionMode = JFileChooser.FILES_ONLY
            isMultiSelectionEnabled = false
        }
        if (chooser.showOpenDialog(null) != JFileChooser.APPROVE_OPTION) {
            runCatching { complete(requestId, "cancelled") }
            return null
        }
        val path = chooser.selectedFile.absolutePath
        val completed = complete(requestId, "selected", path)
        return CapabilityLease(
            completed.string("lease_id"),
            chooser.selectedFile.name,
        )
    }

    fun pickDestination(): CapabilityLease? {
        val request = client.request(
            "capability.request",
            buildJsonObject {
                put("kind", "file_picker")
                put("purpose", "destination_directory")
            },
        )
        val requestId = request.string("request_id")
        val chooser = JFileChooser().apply {
            dialogTitle = "Choose a destination folder"
            fileSelectionMode = JFileChooser.DIRECTORIES_ONLY
            isMultiSelectionEnabled = false
        }
        if (chooser.showOpenDialog(null) != JFileChooser.APPROVE_OPTION) {
            runCatching { complete(requestId, "cancelled") }
            return null
        }
        val selected = chooser.selectedFile
        val completed = complete(requestId, "selected", selected.absolutePath)
        return CapabilityLease(
            completed.string("lease_id"),
            selected.name,
        )
    }

    fun acquireBackground() {
        val request = client.request(
            "capability.request",
            buildJsonObject {
                put("kind", "background_task")
                put("purpose", "transfer")
            },
        )
        complete(request.string("request_id"), "completed")
    }

    fun notify(title: String, body: String) {
        val requestId = runCatching {
            client.request(
                "capability.request",
                buildJsonObject {
                    put("kind", "notification")
                    put("purpose", "transfer")
                    put(
                        "parameters",
                        buildJsonObject {
                            put("title", title)
                            put("body", body)
                        },
                    )
                },
            ).string("request_id")
        }.getOrNull() ?: return
        trayIcon?.displayMessage(title, body, TrayIcon.MessageType.INFO)
        complete(requestId, "completed")
    }

    fun setForeground() {
        client.request("lifecycle.foreground")
    }

    fun setBackground() {
        client.request("lifecycle.background")
    }

    fun close() {
        trayIcon?.let { icon ->
            runCatching { SystemTray.getSystemTray().remove(icon) }
        }
    }

    private fun complete(
        requestId: String,
        outcome: String,
        path: String? = null,
    ): JsonObject = client.request(
        "capability.complete",
        buildJsonObject {
            put("requestId", requestId)
            put("outcome", outcome)
            path?.let { put("path", it) }
        },
    )

    private fun JsonObject.string(key: String): String =
        this[key]?.jsonPrimitive?.contentOrNull ?: error("missing $key")
}

private fun Color.toImage(): Image = java.awt.image.BufferedImage(16, 16, java.awt.image.BufferedImage.TYPE_INT_ARGB).also { image ->
    val graphics = image.createGraphics()
    graphics.color = this
    graphics.fillOval(1, 1, 14, 14)
    graphics.dispose()
}

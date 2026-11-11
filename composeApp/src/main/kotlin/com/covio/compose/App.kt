package com.covio.compose

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.common.BitMatrix
import com.google.zxing.qrcode.QRCodeWriter
import com.wyz.covio.bridge.CovioClient
import com.wyz.covio.bridge.CovioCommandException
import com.wyz.covio.bridge.CovioEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.awt.Robot
import java.awt.Window
import java.io.File
import java.lang.management.ManagementFactory
import javax.imageio.ImageIO

enum class Screen(val label: String, val subtitle: String) {
    Devices("Devices", "This device and trusted peers"),
    Pair("Pair", "Scan a QR code to trust a device"),
    Send("Send", "Choose a trusted device and a file"),
    Receive("Receive", "Wait for the next file"),
}

data class ScreenshotSpec(val path: File, val theme: String, val screen: Screen)

class AppController(
    private val client: CovioClient,
    private val adapters: PlatformAdapters,
) {
    var snapshot by mutableStateOf<JsonObject?>(null)
        private set
    var screen by mutableStateOf(Screen.Devices)
    var busy by mutableStateOf(false)
        private set
    var status by mutableStateOf("Ready")
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var pairingMode by mutableStateOf(PairingMode.Create)
    var pairingQr by mutableStateOf<String?>(null)
        private set
    var pairingResponse by mutableStateOf<String?>(null)
        private set
    var pairingCode by mutableStateOf<String?>(null)
        private set
    var responseInput by mutableStateOf("")
    var confirmationInput by mutableStateOf("")
    var offerInput by mutableStateOf("")
    var selectedPeer by mutableStateOf<String?>(null)
    var selectedFile by mutableStateOf<CapabilityLease?>(null)
        private set
    var destination by mutableStateOf<CapabilityLease?>(null)
        private set
    var progressPercent by mutableStateOf<Int?>(null)
        private set

    suspend fun initialize() = action("Loading device") {
        adapters.reportCapabilities()
        adapters.updateNetworkStatus()
        refreshSnapshot()
        status = "Ready"
    }

    suspend fun refresh() = action("Refreshing") {
        adapters.updateNetworkStatus()
        refreshSnapshot()
        status = "Ready"
    }

    suspend fun startPairing() = action("Creating pairing offer") {
        val value = client.request("pairing.start", timeoutMs = 300_000)
        pairingQr = value.stringOrNull("qr_payload")
        pairingResponse = null
        pairingCode = null
        pairingMode = PairingMode.Create
        status = "Show this QR code to the other device"
    }

    suspend fun acceptOffer() = action("Reading pairing offer") {
        val value = client.request(
            "pairing.accept_offer",
            buildJsonObject { put("qrPayload", offerInput.trim()) },
            timeoutMs = 300_000,
        )
        pairingResponse = value.stringOrNull("response_payload")
        pairingCode = value.stringOrNull("code")
        pairingMode = PairingMode.Join
        status = "Compare the six-digit code on both devices"
    }

    suspend fun acceptResponse() = action("Checking pairing response") {
        val value = client.request(
            "pairing.accept_response",
            buildJsonObject { put("responsePayload", responseInput.trim()) },
            timeoutMs = 300_000,
        )
        pairingQr = null
        pairingCode = value.stringOrNull("code")
        status = "Compare the six-digit code on both devices"
    }

    suspend fun confirmPairing() = action("Confirming pairing") {
        client.request(
            "pairing.confirm",
            buildJsonObject { put("code", confirmationInput.trim()) },
            timeoutMs = 300_000,
        )
        pairingCode = null
        pairingResponse = null
        pairingQr = null
        confirmationInput = ""
        refreshSnapshot()
        screen = Screen.Devices
        status = "Device trusted"
    }

    suspend fun cancelPairing() = action("Cancelling pairing") {
        client.request("pairing.cancel")
        pairingQr = null
        pairingResponse = null
        pairingCode = null
        responseInput = ""
        offerInput = ""
        confirmationInput = ""
        status = "Pairing cancelled"
    }

    suspend fun chooseFile() = action("Choosing a file") {
        selectedFile = withContext(Dispatchers.IO) { adapters.pickFile() }
        if (selectedFile != null) status = "File ready to send"
    }

    suspend fun chooseDestination() = action("Choosing a destination") {
        destination = withContext(Dispatchers.IO) { adapters.pickDestination() }
        if (destination != null) status = "Destination ready"
    }

    suspend fun sendFile() = action("Sending file") {
        val peer = selectedPeer ?: error("Select a trusted device first")
        val file = selectedFile ?: error("Choose a file first")
        adapters.acquireBackground()
        progressPercent = 0
        client.request(
            "transfer.send",
            buildJsonObject {
                put("peerDeviceId", peer)
                put("fileLease", file.leaseId)
            },
            timeoutMs = 15 * 60 * 1000,
        )
        progressPercent = 100
        adapters.notify("Covio", "File sent to ${peerName(peer)}")
        status = "File sent"
        refreshSnapshot()
    }

    suspend fun receiveFile() = action("Waiting for a file") {
        val target = destination ?: error("Choose a destination folder first")
        adapters.acquireBackground()
        progressPercent = 0
        client.request(
            "transfer.receive",
            buildJsonObject { put("destinationLease", target.leaseId) },
            timeoutMs = 15 * 60 * 1000,
        )
        progressPercent = 100
        adapters.notify("Covio", "File received")
        status = "File received"
        refreshSnapshot()
    }

    suspend fun pollEvent(): CovioEvent? = withContext(Dispatchers.IO) {
        client.nextEvent(250)
    }

    fun handleEvent(event: CovioEvent) {
        if (event.name != "transfer.progress") return
        val percent = event.payload["progress_percent"]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
        if (percent != null) {
            progressPercent = percent
            status = "Transfer $percent%"
        }
    }

    fun clearError() {
        error = null
    }

    fun selectScreen(next: Screen) {
        screen = next
        error = null
    }

    fun peerName(deviceId: String): String {
        val devices = snapshot?.get("trusted_devices")?.jsonArray ?: return deviceId.take(12)
        return devices.firstOrNull {
            it.jsonObject["device_id"]?.jsonPrimitive?.contentOrNull == deviceId
        }?.jsonObject?.get("display_name")?.jsonPrimitive?.contentOrNull ?: deviceId.take(12)
    }

    private suspend fun refreshSnapshot() {
        snapshot = client.request("app.snapshot").also { value ->
            val devices = value["trusted_devices"]?.jsonArray
            if (selectedPeer == null && devices?.isNotEmpty() == true) {
                selectedPeer = devices.first().jsonObject["device_id"]?.jsonPrimitive?.contentOrNull
            }
        }
    }

    private suspend fun action(label: String, block: suspend () -> Unit) {
        if (busy) return
        busy = true
        error = null
        status = label
        try {
            block()
        } catch (failure: CovioCommandException) {
            error = "${failure.message} (${failure.code})"
            status = "Needs attention"
        } catch (failure: Throwable) {
            error = failure.message ?: "Operation failed"
            status = "Needs attention"
        } finally {
            busy = false
        }
    }
}

enum class PairingMode {
    Create,
    Join,
}

@Composable
fun CovioApp(
    controller: AppController,
    darkTheme: Boolean,
    screenshot: ScreenshotSpec? = null,
    baselineResult: File? = null,
    onScreenshotCaptured: (() -> Unit)? = null,
    onBaselineFinished: (() -> Unit)? = null,
) {
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        withContext(Dispatchers.IO) { controller.initialize() }
        if (screenshot != null) {
            controller.selectScreen(screenshot.screen)
            if (screenshot.screen == Screen.Pair) {
                withContext(Dispatchers.IO) { controller.startPairing() }
            }
            delay(3_000)
            captureWindow(screenshot.path)
            onScreenshotCaptured?.invoke()
        }
        if (baselineResult != null) {
            val frameTimesMs = mutableListOf<Double>()
            var observedFrames = 0
            repeat(120) {
                val started = System.nanoTime()
                val observed = withTimeoutOrNull(50L) {
                    withFrameNanos { }
                    true
                } ?: false
                if (observed) {
                    observedFrames++
                    frameTimesMs += (System.nanoTime() - started) / 1_000_000.0
                } else {
                    frameTimesMs += 16.67
                }
            }
            writePerformanceBaseline(baselineResult, frameTimesMs, observedFrames)
            onBaselineFinished?.invoke()
        }
    }
    LaunchedEffect(controller) {
        while (true) {
            val event = controller.pollEvent()
            if (event != null) controller.handleEvent(event)
        }
    }
    CovioTheme(dark = darkTheme) {
        Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Row(Modifier.fillMaxSize()) {
                Sidebar(selected = controller.screen, onSelect = controller::selectScreen)
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.background)
                        .padding(horizontal = 36.dp, vertical = 30.dp),
                ) {
                    Header(controller)
                    Spacer(Modifier.height(24.dp))
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .verticalScroll(rememberScrollState()),
                    ) {
                        when (controller.screen) {
                            Screen.Devices -> DevicesScreen(controller, scope)
                            Screen.Pair -> PairScreen(controller, scope)
                            Screen.Send -> SendScreen(controller, scope)
                            Screen.Receive -> ReceiveScreen(controller, scope)
                        }
                    }
                    StatusBar(controller)
                }
            }
        }
    }
}

@Composable
private fun Sidebar(selected: Screen, onSelect: (Screen) -> Unit) {
    val colors = MaterialTheme.colorScheme
    Column(
        modifier = Modifier
            .width(224.dp)
            .fillMaxHeight()
            .background(colors.surfaceVariant.copy(alpha = 0.72f))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text("Covio", style = MaterialTheme.typography.headlineSmall)
        Text(
            "Private, direct file sharing",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(bottom = 20.dp),
        )
        Screen.entries.forEach { item ->
            val active = item == selected
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (active) colors.primary.copy(alpha = 0.14f) else Color.Transparent)
                    .clickable { onSelect(item) }
                    .padding(horizontal = 12.dp)
                    .semantics { contentDescription = "${item.label} tab" },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    item.label,
                    color = if (active) colors.primary else colors.onSurface,
                    fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
        Spacer(Modifier.weight(1f))
        Text("Internal preview", fontSize = 11.sp, color = colors.onSurfaceVariant)
        Text("JNI + Rust core", fontSize = 11.sp, color = colors.onSurfaceVariant)
    }
}

@Composable
private fun Header(controller: AppController) {
    val colors = MaterialTheme.colorScheme
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column {
            Text(controller.screen.label, style = MaterialTheme.typography.headlineSmall)
            Text(
                controller.screen.subtitle,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(top = 5.dp),
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (controller.busy) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
            }
            Text(controller.status, style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
        }
    }
}

@Composable
private fun DevicesScreen(controller: AppController, scope: kotlinx.coroutines.CoroutineScope) {
    val snapshot = controller.snapshot
    val device = snapshot?.get("device")?.jsonObject
    val identity = device?.get("identity")?.jsonObject
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        InfoCard(
            title = "This device",
            badge = if (device?.get("online")?.jsonPrimitive?.contentOrNull == "true") "ONLINE" else "OFFLINE",
        ) {
            KeyValue("Name", identity?.string("display_name") ?: "Preparing device")
            KeyValue("Device ID", identity?.string("device_id")?.let(::shortId) ?: "Pending")
            KeyValue(
                "System",
                "${device?.string("system_name") ?: "Windows"} ${device?.string("system_version") ?: ""}".trim(),
            )
            KeyValue("Version", device?.string("app_version") ?: "Internal")
        }
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            color = MaterialTheme.colorScheme.surface,
        ) {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Trusted devices", style = MaterialTheme.typography.titleMedium)
                    ActionButton("Refresh", "Refresh device and capability state") {
                        scope.launch(Dispatchers.IO) { controller.refresh() }
                    }
                }
                HorizontalDivider()
                val devices = snapshot?.get("trusted_devices")?.jsonArray ?: JsonArray(emptyList())
                if (devices.isEmpty()) {
                    Text("No trusted devices yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    devices.forEach { item ->
                        val value = item.jsonObject
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            Column {
                                Text(value.string("display_name"), fontWeight = FontWeight.Medium)
                                Text(shortId(value.string("device_id")), fontSize = 11.sp)
                            }
                            Text("Trusted", color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
        }
        CapabilityCard(snapshot?.get("capabilities")?.jsonArray ?: JsonArray(emptyList()))
    }
}

@Composable
private fun CapabilityCard(capabilities: JsonArray) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Platform capabilities", style = MaterialTheme.typography.titleMedium)
            Text(
                "Rust validates every host adapter before a platform request is allowed.",
                style = MaterialTheme.typography.bodyMedium,
            )
            capabilities.chunked(3).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { item ->
                        val value = item.jsonObject
                        CapabilityPill(
                            name = value.string("kind"),
                            available = value["available"]?.jsonPrimitive?.contentOrNull == "true",
                            modifier = Modifier.weight(1f),
                        )
                    }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun CapabilityPill(
    name: String,
    available: Boolean,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.colorScheme
    Row(
        modifier = modifier
            .height(34.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (available) colors.primary.copy(alpha = 0.10f) else colors.surfaceVariant)
            .padding(horizontal = 8.dp)
            .semantics { contentDescription = "$name capability ${if (available) "available" else "unavailable"}" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(8.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(if (available) colors.primary else colors.outline),
        )
        Spacer(Modifier.width(7.dp))
        Text(name.replace('_', ' '), fontSize = 11.sp)
    }
}

@Composable
private fun PairScreen(controller: AppController, scope: kotlinx.coroutines.CoroutineScope) {
    Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
        Surface(
            modifier = Modifier.weight(1f),
            shape = RoundedCornerShape(12.dp),
            color = MaterialTheme.colorScheme.surface,
        ) {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ModeButton("Create QR", controller.pairingMode == PairingMode.Create) {
                        controller.pairingMode = PairingMode.Create
                    }
                    ModeButton("Join with QR", controller.pairingMode == PairingMode.Join) {
                        controller.pairingMode = PairingMode.Join
                    }
                }
                if (controller.pairingMode == PairingMode.Create) {
                    Text("Create a short-lived QR offer.", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "The other device reads the offer, returns a response, and both users compare a six-digit code.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    ActionButton("Create pairing QR", "Create a pairing QR offer") {
                        scope.launch(Dispatchers.IO) { controller.startPairing() }
                    }
                    controller.pairingQr?.let { payload ->
                        QrCode(payload)
                        OutlinedTextField(
                            value = payload,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("QR payload") },
                            modifier = Modifier.fillMaxWidth(),
                            minLines = 2,
                        )
                    }
                    OutlinedTextField(
                        value = controller.responseInput,
                        onValueChange = { controller.responseInput = it },
                        label = { Text("Pairing response") },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 2,
                    )
                    ActionButton(
                        "Accept response",
                        "Accept the pairing response",
                        enabled = controller.responseInput.isNotBlank(),
                    ) { scope.launch(Dispatchers.IO) { controller.acceptResponse() } }
                } else {
                    Text("Read the invite QR.", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Paste the QR payload shown by the other device. The response and confirmation code stay on this device.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    OutlinedTextField(
                        value = controller.offerInput,
                        onValueChange = { controller.offerInput = it },
                        label = { Text("QR payload from other device") },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 3,
                    )
                    ActionButton(
                        "Read QR offer",
                        "Read the pairing QR offer",
                        enabled = controller.offerInput.isNotBlank(),
                    ) { scope.launch(Dispatchers.IO) { controller.acceptOffer() } }
                }
            }
        }
        Surface(
            modifier = Modifier.width(360.dp),
            shape = RoundedCornerShape(12.dp),
            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.65f),
        ) {
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Confirmation", style = MaterialTheme.typography.titleMedium)
                controller.pairingCode?.let { code ->
                    Text(code, fontSize = 34.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                    Text(
                        "Both users must see the same code. The code alone cannot complete pairing.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    OutlinedTextField(
                        value = controller.confirmationInput,
                        onValueChange = { controller.confirmationInput = it },
                        label = { Text("Enter six-digit code") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    ActionButton(
                        "Confirm and trust",
                        "Confirm the pairing code and trust the device",
                        enabled = controller.confirmationInput.length == 6,
                    ) { scope.launch(Dispatchers.IO) { controller.confirmPairing() } }
                } ?: Text(
                    "The confirmation code appears after a signed response is accepted.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                controller.pairingResponse?.let { response ->
                    OutlinedTextField(
                        value = response,
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Response to return to the other device") },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 3,
                    )
                }
                ActionButton("Cancel pairing", "Cancel the current pairing session") {
                    scope.launch(Dispatchers.IO) { controller.cancelPairing() }
                }
            }
        }
    }
}

@Composable
private fun SendScreen(controller: AppController, scope: kotlinx.coroutines.CoroutineScope) {
    val devices = controller.snapshot?.get("trusted_devices")?.jsonArray ?: JsonArray(emptyList())
    Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Send to", style = MaterialTheme.typography.titleMedium)
            if (devices.isEmpty()) {
                Text("Pair a device before sending.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                devices.forEach { item ->
                    val value = item.jsonObject
                    val id = value.string("device_id")
                    DeviceChoice(
                        name = value.string("display_name"),
                        detail = shortId(id),
                        selected = controller.selectedPeer == id,
                        onClick = { controller.selectedPeer = id },
                    )
                }
            }
            HorizontalDivider()
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text("File", style = MaterialTheme.typography.titleMedium)
                    Text(controller.selectedFile?.displayName ?: "No file selected")
                }
                ActionButton("Choose file", "Choose a file to send") {
                    scope.launch(Dispatchers.IO) { controller.chooseFile() }
                }
            }
            ActionButton(
                "Send file",
                "Send the selected file to the trusted device",
                enabled = controller.selectedPeer != null && controller.selectedFile != null,
            ) { scope.launch(Dispatchers.IO) { controller.sendFile() } }
            Text(
                "The receiving device must be waiting on its Receive screen. Files use the Rust iroh transport and do not enter the control channel.",
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun ReceiveScreen(controller: AppController, scope: kotlinx.coroutines.CoroutineScope) {
    Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Receive the next file", style = MaterialTheme.typography.titleMedium)
            Text(
                "Choose a destination folder. The receiver accepts the next offer from a trusted device and shows the checkpoint as it runs.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text("Destination", fontWeight = FontWeight.Medium)
                    Text(controller.destination?.displayName ?: "No destination selected")
                }
                ActionButton("Choose folder", "Choose a destination folder") {
                    scope.launch(Dispatchers.IO) { controller.chooseDestination() }
                }
            }
            ActionButton(
                "Wait for file",
                "Wait for a file from a trusted device",
                enabled = controller.destination != null,
            ) { scope.launch(Dispatchers.IO) { controller.receiveFile() } }
            Text(
                "Receiving is bounded by the Rust transfer window and checkpoint store. The final file uses a same-volume staging path.",
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun DeviceChoice(
    name: String,
    detail: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 44.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (selected) colors.primary.copy(alpha = 0.12f) else colors.surfaceVariant)
            .clickable(onClick = onClick)
            .padding(12.dp)
            .semantics { contentDescription = "Select device $name" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(10.dp)
                .clip(RoundedCornerShape(5.dp))
                .background(if (selected) colors.primary else colors.outline),
        )
        Spacer(Modifier.width(10.dp))
        Column {
            Text(name, fontWeight = FontWeight.Medium)
            Text(detail, fontSize = 11.sp, color = colors.onSurfaceVariant)
        }
    }
}

@Composable
private fun InfoCard(title: String, badge: String, content: @Composable () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Surface(shape = RoundedCornerShape(12.dp), color = colors.surface, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(title, style = MaterialTheme.typography.titleMedium)
                Text(
                    badge,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (badge == "ONLINE") colors.primary else colors.onSurfaceVariant,
                )
            }
            HorizontalDivider()
            content()
        }
    }
}

@Composable
private fun KeyValue(key: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(key, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            value,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.width(440.dp),
        )
    }
}

@Composable
private fun QrCode(payload: String) {
    val matrix = remember(payload) { createQr(payload) }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(250.dp)
            .padding(8.dp)
            .semantics { contentDescription = "Pairing QR code" },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(230.dp)) {
            val cell = size.minDimension / matrix.width
            for (x in 0 until matrix.width) {
                for (y in 0 until matrix.height) {
                    if (matrix[x, y]) {
                        drawRect(
                            color = Color.Black,
                            topLeft = androidx.compose.ui.geometry.Offset(x * cell, y * cell),
                            size = androidx.compose.ui.geometry.Size(cell, cell),
                        )
                    }
                }
            }
        }
    }
}

private fun createQr(payload: String): BitMatrix = QRCodeWriter().encode(
    payload,
    BarcodeFormat.QR_CODE,
    256,
    256,
    mapOf(EncodeHintType.MARGIN to 1),
)

@Composable
private fun ModeButton(label: String, selected: Boolean, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Surface(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .clickable(onClick = onClick)
            .semantics { contentDescription = "$label mode" },
        color = if (selected) colors.primary.copy(alpha = 0.16f) else colors.surfaceVariant,
        shape = RoundedCornerShape(8.dp),
    ) {
        Text(
            label,
            modifier = Modifier
                .height(44.dp)
                .padding(horizontal = 12.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            color = if (selected) colors.primary else colors.onSurface,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun ActionButton(
    label: String,
    description: String,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.colorScheme
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .height(44.dp)
            .semantics { contentDescription = description },
        shape = RoundedCornerShape(8.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = colors.primary,
            contentColor = colors.onPrimary,
            disabledContainerColor = colors.surfaceVariant,
            disabledContentColor = colors.onSurfaceVariant,
        ),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 14.dp),
    ) {
        Text(label, fontSize = 12.sp)
    }
}

@Composable
private fun StatusBar(controller: AppController) {
    val colors = MaterialTheme.colorScheme
    if (controller.error == null && controller.progressPercent == null) {
        Text(
            "Rust core owns pairing, transfer, capability, and error state.",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(top = 18.dp),
        )
        return
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(colors.errorContainer.copy(alpha = if (controller.error == null) 0.35f else 0.75f))
            .padding(12.dp)
            .semantics { contentDescription = "Status message" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            controller.error ?: "Transfer ${controller.progressPercent}%",
            color = if (controller.error == null) colors.onSurface else colors.error,
            modifier = Modifier.weight(1f),
        )
        if (controller.error != null) {
            Box(
                modifier = Modifier
                    .heightIn(min = 44.dp)
                    .widthIn(min = 64.dp)
                    .clickable { controller.clearError() }
                    .padding(8.dp)
                    .semantics { contentDescription = "Dismiss status message" },
                contentAlignment = Alignment.Center,
            ) {
                Text("Dismiss", color = colors.error)
            }
        }
    }
}

private fun JsonObject.string(key: String): String =
    this[key]?.jsonPrimitive?.contentOrNull ?: ""

private fun JsonObject.stringOrNull(key: String): String? =
    this[key]?.jsonPrimitive?.contentOrNull

private fun shortId(value: String): String =
    if (value.length <= 18) value else "${value.take(8)}…${value.takeLast(8)}"

private fun writePerformanceBaseline(path: File, frameTimesMs: List<Double>, observedFrames: Int) {
    val processStartMs = java.lang.ProcessHandle.current().info().startInstant().orElse(null)
        ?.toEpochMilli()
    val coldStartMs = processStartMs?.let { (System.currentTimeMillis() - it).coerceAtLeast(0) } ?: 0
    val runtime = ManagementFactory.getRuntimeMXBean()
    val memory = ManagementFactory.getMemoryMXBean()
    val os = ManagementFactory.getOperatingSystemMXBean()
    val payload = kotlinx.serialization.json.buildJsonObject {
        put("schema_version", 1)
        put("cold_start_ms", coldStartMs)
        put("jvm_uptime_ms", runtime.uptime)
        put("heap_used_bytes", memory.heapMemoryUsage.used)
        put("heap_committed_bytes", memory.heapMemoryUsage.committed)
        put("non_heap_used_bytes", memory.nonHeapMemoryUsage.used)
        put("committed_virtual_bytes", if (os is com.sun.management.OperatingSystemMXBean) os.committedVirtualMemorySize else 0L)
        put("available_processors", Runtime.getRuntime().availableProcessors())
        put("os_name", System.getProperty("os.name"))
        put("os_version", System.getProperty("os.version"))
        put("frame_sample_count", frameTimesMs.size)
        put("frame_samples_observed", observedFrames)
        put("frame_average_ms", frameTimesMs.average().takeIf { !it.isNaN() } ?: 0.0)
        val sorted = frameTimesMs.sorted()
        put("frame_p95_ms", sorted.getOrNull(((sorted.size - 1) * 0.95).toInt()) ?: 0.0)
        put("frame_max_ms", sorted.lastOrNull() ?: 0.0)
    }
    path.parentFile?.mkdirs()
    path.writeText(payload.toString(), Charsets.UTF_8)
}

private fun captureWindow(path: File) {
    runCatching {
        val window = Window.getWindows().firstOrNull { it.isShowing } ?: return
        window.isAlwaysOnTop = true
        window.toFront()
        window.requestFocus()
        Thread.sleep(750)
        path.parentFile?.mkdirs()
        ImageIO.write(Robot().createScreenCapture(window.bounds), "png", path)
    }
}

package com.wyz.covio.bridge

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.nio.file.Files
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class CovioNativeBridgeTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun requestEventErrorCancelAndShutdownRoundTrip() {
        val root = Files.createTempDirectory("covio-jni-test").toFile()
        try {
            val client = CovioClient(config(root.absolutePath))
            val echo = client.request(
                "diagnostics.echo",
                buildJsonObject { put("value", 741) },
            )
            assertEquals(741, echo["payload"]?.jsonObject?.get("value")?.toString()?.toInt())
            var sawCompleted = false
            repeat(8) {
                val event = client.nextEvent(2_000) ?: return@repeat
                if (event.name == "request.completed") sawCompleted = true
            }
            assertTrue(sawCompleted)

            val errorBox = NativeErrorBox()
            val errorStatus = CovioNative.nativeDispatch(
                handle = client.nativeHandle,
                message = "not-json".encodeToByteArray(),
                nowUnixMillis = System.currentTimeMillis(),
                outMessage = ByteArrayBox(),
                errorOut = errorBox,
            )
            assertEquals(4, errorStatus)
            assertEquals(4, errorBox.code)

            val requestId = UUID.randomUUID().toString()
            val request = json.parseToJsonElement(
                """
                {"kind":"request","body":{"protocol_version":1,"request_id":"$requestId","generation":1,"command":"diagnostics.wait","deadline":null,"payload":{"milliseconds":2000}}}
                """.trimIndent(),
            ).jsonObject
            var response: kotlinx.serialization.json.JsonObject? = null
            val worker = Thread {
                response = client.dispatch(request)
            }
            worker.start()
            Thread.sleep(80)
            client.cancel(requestId)
            worker.join(2_000)
            val result = response?.get("body")?.jsonObject?.get("result")?.jsonObject
            assertEquals("error", result?.get("status")?.toString()?.trim('"'))

            client.shutdown(true)
            assertFailsWith<CovioNativeException> {
                client.request("diagnostics.echo")
            }
            client.close()
        } finally {
            root.deleteRecursively()
        }
    }

    private fun config(root: String): CovioSessionConfig = CovioSessionConfig(
        dataRoot = root,
        displayName = "JNI test device",
        systemName = System.getProperty("os.name"),
        systemVersion = System.getProperty("os.version"),
        appVersion = "test",
        hostAdapters = listOf("file_picker", "notification", "background_task", "app_lifecycle"),
    )
}

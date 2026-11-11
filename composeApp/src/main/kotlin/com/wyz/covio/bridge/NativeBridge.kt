package com.wyz.covio.bridge

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID

internal class NativeErrorBox {
    @JvmField
    var code: Int = 0

    @JvmField
    var message: String = ""
}

internal class ByteArrayBox {
    @JvmField
    var bytes: ByteArray? = null
}

internal object CovioNative {
    init {
        CovioNativeLibrary.load()
    }

    external fun nativeAbiVersion(): Int
    external fun nativeProtocolVersion(): Int
    external fun nativeOpenSession(
        generation: Long,
        revision: Long,
        maxControlBytes: Int,
        errorOut: NativeErrorBox,
    ): Long
    external fun nativeConfigure(handle: Long, configJson: ByteArray, errorOut: NativeErrorBox): Int
    external fun nativeRelease(handle: Long)
    external fun nativeDispatch(
        handle: Long,
        message: ByteArray,
        nowUnixMillis: Long,
        outMessage: ByteArrayBox,
        errorOut: NativeErrorBox,
    ): Int
    external fun nativeCancel(
        handle: Long,
        requestId: ByteArray,
        reason: Int,
        nowUnixMillis: Long,
        errorOut: NativeErrorBox,
    ): Int
    external fun nativeShutdown(
        handle: Long,
        immediate: Boolean,
        hasDeadline: Boolean,
        deadlineUnixMillis: Long,
        nowUnixMillis: Long,
        errorOut: NativeErrorBox,
    ): Int
    external fun nativeNextEvent(
        handle: Long,
        timeoutMs: Int,
        outMessage: ByteArrayBox,
        errorOut: NativeErrorBox,
    ): Int
    external fun nativeLifecycle(handle: Long): Int
    external fun nativeActiveRequestCount(handle: Long): Long
}

internal object CovioNativeLibrary {
    private const val WINDOWS_LIBRARY = "/native/windows-x64/covio_jni.dll"
    private var loaded = false

    @Synchronized
    fun load() {
        if (loaded) return
        val explicit = System.getenv("COVIO_JNI_LIBRARY")
        if (!explicit.isNullOrBlank()) {
            System.load(File(explicit).absolutePath)
            loaded = true
            return
        }
        val resource = CovioNativeLibrary::class.java.getResource(WINDOWS_LIBRARY)
            ?: error("Covio JNI library resource is missing")
        val temporary = Files.createTempFile("covio-jni-", ".dll").toFile()
        resource.openStream().use { input ->
            temporary.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        temporary.deleteOnExit()
        System.load(temporary.absolutePath)
        loaded = true
    }
}

class CovioNativeException(
    val code: Int,
    message: String,
) : RuntimeException(message)

class CovioCommandException(
    val code: String,
    message: String,
    val retryable: Boolean,
) : RuntimeException(message)

@Serializable
data class CovioSessionConfig(
    val dataRoot: String,
    val displayName: String,
    val systemName: String,
    val systemVersion: String,
    val appVersion: String,
    val hostAdapters: List<String>,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("dataRoot", dataRoot)
        put("displayName", displayName)
        put("systemName", systemName)
        put("systemVersion", systemVersion)
        put("appVersion", appVersion)
        put(
            "hostAdapters",
            kotlinx.serialization.json.buildJsonArray {
                hostAdapters.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) }
            },
        )
    }
}

class CovioEvent(
    val name: String,
    val payload: JsonObject,
)

class CovioClient(
    config: CovioSessionConfig,
) : AutoCloseable {
    private val json = Json {
        ignoreUnknownKeys = true
    }
    internal val nativeHandle: Long
    private var closed = false

    init {
        val error = NativeErrorBox()
        nativeHandle = CovioNative.nativeOpenSession(1, 0, 1 shl 20, error)
        checkNative(error)
        if (nativeHandle == 0L) {
            throw CovioNativeException(0, "native session handle is invalid")
        }
        val configure = CovioNative.nativeConfigure(
            nativeHandle,
            json.encodeToString(CovioSessionConfig.serializer(), config).encodeToByteArray(),
            error,
        )
        checkNative(error, configure)
    }

    fun request(
        command: String,
        payload: JsonElement = buildJsonObject {},
        timeoutMs: Long = 120_000,
    ): JsonObject {
        val requestId = UUID.randomUUID().toString()
        val message = buildJsonObject {
            put("kind", "request")
            put(
                "body",
                buildJsonObject {
                    put("protocol_version", 1)
                    put("request_id", requestId)
                    put("generation", 1)
                    put("command", command)
                    put("deadline", nowUnixMillis() + timeoutMs)
                    put("payload", payload)
                },
            )
        }
        val response = dispatch(message)
        val result = response["body"]?.jsonObject?.get("result")?.jsonObject
            ?: error("native response is missing a result")
        return when (result["status"]?.jsonPrimitive?.content) {
            "ok" -> result["data"]?.jsonObject ?: buildJsonObject {}
            "error" -> {
                val error = result["error"]?.jsonObject
                throw CovioCommandException(
                    error?.get("code")?.jsonPrimitive?.contentOrNull ?: "internal",
                    error?.get("message")?.jsonPrimitive?.contentOrNull ?: "command failed",
                    error?.get("retryable")?.jsonPrimitive?.contentOrNull?.toBoolean() ?: false,
                )
            }
            else -> error("native response status is unknown")
        }
    }

    fun dispatch(message: JsonObject): JsonObject {
        val error = NativeErrorBox()
        val output = ByteArrayBox()
        val status = CovioNative.nativeDispatch(
            nativeHandle,
            json.encodeToString(JsonObject.serializer(), message).encodeToByteArray(),
            nowUnixMillis(),
            output,
            error,
        )
        checkNative(error, status)
        return json.parseToJsonElement(
            output.bytes?.toString(Charsets.UTF_8) ?: error("native dispatch returned no bytes"),
        ).jsonObject
    }

    fun cancel(requestId: String) {
        val error = NativeErrorBox()
        val status = CovioNative.nativeCancel(
            nativeHandle,
            requestId.encodeToByteArray(),
            0,
            nowUnixMillis(),
            error,
        )
        checkNative(error, status)
    }

    fun nextEvent(timeoutMs: Int = 250): CovioEvent? {
        val error = NativeErrorBox()
        val output = ByteArrayBox()
        val status = CovioNative.nativeNextEvent(nativeHandle, timeoutMs, output, error)
        checkNative(error, status)
        val bytes = output.bytes ?: return null
        val body = json.parseToJsonElement(bytes.toString(Charsets.UTF_8))
            .jsonObject["body"]?.jsonObject
            ?: return null
        return CovioEvent(
            body["event"]?.jsonPrimitive?.content ?: return null,
            body["payload"]?.jsonObject ?: buildJsonObject {},
        )
    }

    fun lifecycle(): Int = CovioNative.nativeLifecycle(nativeHandle)

    fun activeRequestCount(): Long = CovioNative.nativeActiveRequestCount(nativeHandle)

    fun shutdown(immediate: Boolean = true) {
        if (closed) return
        val error = NativeErrorBox()
        val status = CovioNative.nativeShutdown(
            nativeHandle,
            immediate,
            false,
            0,
            nowUnixMillis(),
            error,
        )
        checkNative(error, status)
    }

    override fun close() {
        if (closed) return
        runCatching {
            val error = NativeErrorBox()
            val status = CovioNative.nativeShutdown(
                nativeHandle,
                true,
                false,
                0,
                nowUnixMillis(),
                error,
            )
            checkNative(error, status)
        }
        closed = true
        CovioNative.nativeRelease(nativeHandle)
    }

    private fun checkNative(error: NativeErrorBox, status: Int = error.code) {
        if (status != 0 || error.code != 0) {
            throw CovioNativeException(
                if (error.code != 0) error.code else status,
                error.message.ifBlank { "native bridge failed with status $status" },
            )
        }
    }
}

private fun nowUnixMillis(): Long = System.currentTimeMillis()

package com.wyz.covio.core

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * 特权 helper 的线上协议：编解码、校验与回复构造。
 *
 * 两端的 helper 都调用这里：macOS 宿主的 Swift 版与 Compose 版的 Kotlin 版。
 * 协议只有一份实现，两侧不可能漂移。
 *
 * 分成三类：
 * - 协议值（socket 上限、权限位、命令名）在这里定义。
 * - 套接字读写与进程启动是 OS 调用，留在各宿主。
 * - 路径、版本号与命令白名单在 `HelperContract.kt`。
 *
 * 错误文案是线上契约。客户端按文案判断失败原因，
 * 所以下面这些字符串要逐字保留，改字等于改协议。
 */
object HelperWire {
    /** 单条请求的字节上限。超过就断开，防止内存被撑爆。 */
    const val MAX_REQUEST_BYTES = 64 * 1024

    /** 单条回复的字节上限。客户端按它读回包。 */
    const val MAX_REPLY_BYTES = 64 * 1024

    /** socket 文件的权限位 `0666`。任意用户可连，uid 校验在连接后做。 */
    const val SOCKET_PERMISSIONS = 0x1B6

    const val COMMAND_VERSION = "version"
    const val COMMAND_SET_DISABLE_SLEEP = "setDisableSleep"
    const val COMMAND_SET_HIBERNATE_MODE = "setHibernateMode"
    const val COMMAND_LID_LEASE_ACQUIRE = "lidLeaseAcquire"
    const val COMMAND_LID_LEASE_RENEW = "lidLeaseRenew"
    const val COMMAND_LID_LEASE_RELEASE = "lidLeaseRelease"
    const val COMMAND_LID_LEASE_STATUS = "lidLeaseStatus"
    const val COMMAND_CHARGE_LIMIT_STATUS = "chargeLimitStatus"
    const val COMMAND_CHARGE_LIMIT_CONFIGURE = "chargeLimitConfigure"
    const val COMMAND_CHARGE_LIMIT_RESTORE = "chargeLimitRestore"
    const val COMMAND_FAN_CONTROL_STATUS = "fanControlStatus"
    const val COMMAND_FAN_CONTROL_CONFIGURE = "fanControlConfigure"
    const val COMMAND_FAN_CONTROL_KEEP_ALIVE = "fanControlKeepAlive"
    const val COMMAND_FAN_CONTROL_RESTORE = "fanControlRestore"

    /** 升级前恢复 helper 持有的全部特权状态。 */
    const val COMMAND_PREPARE_INSTALL_TRANSACTION = "prepareInstallTransaction"

    const val ERROR_UNSUPPORTED_PROTOCOL = "Unsupported protocol version"
    const val ERROR_EXTERNAL_DISPLAY = "Closed lid lease is blocked while an external display is connected"
    const val ERROR_CANNOT_READ_EXTERNAL_DISPLAY = "Cannot read external display count"
    const val ERROR_EXTERNAL_SLEEP_CONFLICT = "SleepDisabled is owned by an external tool"
    const val ERROR_CANNOT_READ_SLEEP_DISABLED = "Cannot read SleepDisabled"
    const val ERROR_CANNOT_WRITE_SLEEP_DISABLED = "Cannot write SleepDisabled"
    const val ERROR_CANNOT_READ_OWNERSHIP = "Cannot read SleepDisabled ownership"
    const val ERROR_TOO_MANY_LEASES = "Too many active lid leases"

    /**
     * 线上 JSON 的形状。
     *
     * 三个开关都是为了对齐 0.4.2 已经发出的字节：
     * - `ignoreUnknownKeys`：新版客户端加字段后，旧版 helper 还要能读。
     * - `encodeDefaults = false`：空 `payload` 不写出来。
     * - `explicitNulls = false`：`result` 与 `error` 为 null 时整个键不写。
     */
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = false
        explicitNulls = false
    }

    // MARK: 编解码

    /**
     * 编码一条请求。
     *
     * 不会失败：`HelperRequest` 是固定形状的可序列化类型，没有自定义序列化器。
     */
    fun encodeRequest(request: HelperRequest): String = json.encodeToString(request)

    fun decodeRequest(line: String): HelperRequest? =
        runCatching { json.decodeFromString<HelperRequest>(line) }.getOrNull()

    /** 编码一条回复。同 [encodeRequest]，不会失败。 */
    fun encodeReply(reply: HelperReply): String = json.encodeToString(reply)

    fun decodeReply(line: String): HelperReply? =
        runCatching { json.decodeFromString<HelperReply>(line) }.getOrNull()

    // MARK: 回复构造

    /**
     * 成功回复。
     *
     * `result` 为空时不写出这个键。空对象不携带信息，
     * 省略它与写出 `{}` 对客户端等价。
     */
    fun success(requestId: String, result: Map<String, String> = emptyMap()): HelperReply =
        HelperReply(HELPER_PROTOCOL_VERSION, requestId, true, result.ifEmpty { null }, null)

    fun failure(requestId: String, message: String): HelperReply =
        HelperReply(HELPER_PROTOCOL_VERSION, requestId, false, null, message)

    fun versionReply(requestId: String): HelperReply = success(
        requestId,
        mapOf(
            "version" to APP_VERSION,
            "protocolVersion" to HELPER_PROTOCOL_VERSION,
        ),
    )

    /**
     * 新 helper 的完整发布身份应答。
     *
     * `version` 和 `protocolVersion` 保留给旧客户端。新 app 再读取其余字段做精确比较。
     */
    fun versionReply(requestId: String, identity: HelperReleaseIdentity): HelperReply = success(
        requestId,
        mapOf(
            "version" to identity.clientVersion,
            "clientVersion" to identity.clientVersion,
            "productVersion" to identity.productVersion,
            "buildNumber" to identity.buildNumber,
            "gitCommit" to identity.gitCommit,
            "releaseId" to identity.releaseId,
            "protocolVersion" to identity.protocolVersion,
            "helperSHA256" to identity.helperSHA256,
            "channel" to identity.channel,
        ),
    )

    fun leaseStatusReply(
        requestId: String,
        sleepDisabled: Boolean?,
        covioOwned: Boolean?,
        activeLeaseCount: Int,
        expiresAtEpochSeconds: Long?,
    ): HelperReply {
        val result = buildMap {
            put("activeLeaseCount", activeLeaseCount.coerceAtLeast(0).toString())
            put("sleepDisabled", sleepDisabled?.toString() ?: "unknown")
            put("covioOwned", covioOwned?.toString() ?: "unknown")
            expiresAtEpochSeconds?.let { put("expiresAtEpochSeconds", it.toString()) }
        }
        return success(requestId, result)
    }

    // MARK: 校验

    /**
     * 校验一条请求。返回 null 表示通过，否则返回拒绝原因。
     *
     * 只检查协议层：版本、请求号、命令白名单与命令自己的取值。
     * uid 校验不在这里，它属于宿主。
     */
    fun validate(request: HelperRequest): String? {
        // 旧版只能探测版本。它不能再获得任何写权限。
        val legacyVersionProbe = request.version == "1" && request.command == COMMAND_VERSION
        if (request.version != HELPER_PROTOCOL_VERSION && !legacyVersionProbe) {
            return ERROR_UNSUPPORTED_PROTOCOL
        }
        if (request.requestId.isBlank()) return "Missing requestId"
        if (request.command !in HELPER_ALLOWED_COMMANDS) return "Command is not allowed"

        when (request.command) {
            COMMAND_SET_DISABLE_SLEEP -> {
                val value = request.payload["disabled"] ?: return "Missing disabled value"
                if (value != "true" && value != "false") return "Invalid disabled value"
            }

            COMMAND_SET_HIBERNATE_MODE -> {
                val mode = request.payload["mode"]?.toIntOrNull() ?: return "Missing hibernate mode"
                if (mode !in SUPPORTED_HIBERNATE_MODES) return "Invalid hibernate mode"
            }

            COMMAND_LID_LEASE_ACQUIRE, COMMAND_LID_LEASE_RENEW -> {
                val leaseId = request.payload["leaseId"] ?: return "Missing leaseId"
                if (leaseId.isBlank() || leaseId.length > HELPER_LEASE_ID_MAX_LENGTH) {
                    return "Invalid leaseId"
                }
                val externalDisplays = request.payload["externalDisplayCount"]?.toIntOrNull()
                    ?: return "Missing external display count"
                if (externalDisplays < 0) return "Invalid external display count"
            }

            COMMAND_LID_LEASE_RELEASE -> {
                val leaseId = request.payload["leaseId"] ?: return "Missing leaseId"
                if (leaseId.isBlank() || leaseId.length > HELPER_LEASE_ID_MAX_LENGTH) {
                    return "Invalid leaseId"
                }
            }
        }
        if (request.command == COMMAND_CHARGE_LIMIT_CONFIGURE) {
            val percent = request.payload["percent"]?.toIntOrNull() ?: return "Missing charge limit"
            if (!ChargeLimitPolicy.isValidUpperLimit(percent)) return "Invalid charge limit"
            val activeDischarge = request.payload["activeDischarge"]
            if (activeDischarge != null && activeDischarge != "true" && activeDischarge != "false") {
                return "Invalid active discharge value"
            }
        }
        if (request.command == COMMAND_FAN_CONTROL_CONFIGURE) {
            if (request.payload["enabled"] != "true") return "Fan control must be enabled"
            val mode = request.payload["mode"]
            if (mode != "auto" && mode != "curve" && mode != "manual") return "Invalid fan control mode"
            val start = request.payload["start"]?.toDoubleOrNull()
                ?: return "Missing fan start temperature"
            val full = request.payload["full"]?.toDoubleOrNull()
                ?: return "Missing fan full temperature"
            if (!start.isFinite() || !full.isFinite() || start !in 35.0..80.0 ||
                full !in (start + 5.0)..105.0
            ) {
                return "Invalid fan curve"
            }
            val sensors = request.payload["sensors"].orEmpty()
            if (sensors.length > 512) return "Fan sensor list is too long"
            val sensorKeys = sensors.split(',').filter { it.isNotBlank() }
            if (sensorKeys.size > 32) return "Too many fan sensors"
            if (sensorKeys.any { it.length != 4 }) return "Invalid fan sensor key"
            val manual = request.payload["manualRPM"].orEmpty()
            if (manual.length > 1024) return "Fan RPM list is too long"
            val manualModes = request.payload["manualModes"].orEmpty()
            if (manualModes.length > 1_024) return "Fan mode list is too long"
            if (manualModes.any { it == '\u0000' || it == '\n' || it == '\r' }) {
                return "Invalid fan mode list"
            }
            val curves = request.payload["curves"].orEmpty()
            if (curves.length > 8_192) return "Fan curve list is too long"
            if (curves.any { it == '\u0000' || it == '\n' || it == '\r' }) {
                return "Invalid fan curve list"
            }
            val temperatureRules = request.payload["temperatureRules"].orEmpty()
            if (temperatureRules.length > 4_096) return "Fan temperature rules are too long"
            if (temperatureRules.any { it == '\u0000' || it == '\n' || it == '\r' }) {
                return "Invalid fan temperature rules"
            }
            for (pair in manual.split(',').filter { it.isNotBlank() }) {
                val parts = pair.split(':', limit = 2)
                if (parts.size != 2) return "Invalid fan RPM"
                val fan = parts[0].toIntOrNull() ?: return "Invalid fan index"
                val rpm = parts[1].toDoubleOrNull() ?: return "Invalid fan RPM"
                if (fan !in 0..15 || !rpm.isFinite() || rpm !in 0.0..15000.0) {
                    return "Invalid fan RPM"
                }
            }
        }
        return null
    }

    /** 充电控制命令需要调用方代码签名，不能只靠已安装用户的 uid。 */
    fun isChargeLimitCommand(command: String): Boolean = command == COMMAND_CHARGE_LIMIT_STATUS ||
        command == COMMAND_CHARGE_LIMIT_CONFIGURE ||
        command == COMMAND_CHARGE_LIMIT_RESTORE

    /** 风扇命令会写 SMC，必须和充电命令一样校验调用方签名。 */
    fun isFanControlCommand(command: String): Boolean = command == COMMAND_FAN_CONTROL_STATUS ||
        command == COMMAND_FAN_CONTROL_CONFIGURE ||
        command == COMMAND_FAN_CONTROL_KEEP_ALIVE ||
        command == COMMAND_FAN_CONTROL_RESTORE

    fun requiresClientSignature(command: String): Boolean =
        isChargeLimitCommand(command) || isFanControlCommand(command) ||
            command == COMMAND_PREPARE_INSTALL_TRANSACTION

    // MARK: pmset 调用

    /**
     * 这条请求要跑的命令行。
     *
     * 返回 null 表示这条命令不跑 `pmset`。`version` 不跑，
     * 白名单外的命令在 [validate] 就已被拒绝。
     */
    fun pmsetArguments(request: HelperRequest): List<String>? = when (request.command) {
        COMMAND_SET_DISABLE_SLEEP -> listOf(
            "-a",
            "disablesleep",
            if (request.payload["disabled"] == "true") "1" else "0",
        )

        COMMAND_SET_HIBERNATE_MODE -> request.payload["mode"]
            ?.toIntOrNull()
            ?.let { listOf("-a", "hibernatemode", it.toString()) }

        else -> null
    }

    /** 直接写 `disablesleep` 的参数。只能由 helper 的租约协调器调用。 */
    fun disableSleepArguments(disabled: Boolean): List<String> =
        listOf("-a", "disablesleep", if (disabled) "1" else "0")

    /**
     * `pmset` 跑完之后的回复。
     *
     * `pmset` 失败时把它的输出当错误文案。没有输出时用退出码拼一句，
     * 好让日志里看得出是哪一步失败。
     */
    fun pmsetReply(requestId: String, exitCode: Int, output: String): HelperReply {
        if (exitCode == 0) return success(requestId)
        val text = output.trim()
        return failure(requestId, text.ifEmpty { "pmset exited with $exitCode" })
    }
}

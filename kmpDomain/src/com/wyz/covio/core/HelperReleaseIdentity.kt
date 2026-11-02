package com.wyz.covio.core

/**
 * app 与 helper 共同携带的完整发布身份。
 *
 * 字段都保留为字符串，因为同一组值会穿过 Kotlin、Swift 和 Unix socket JSON 边界。
 * 比较前通过 [HelperReleaseHandshake.parse] 做格式校验。
 */
data class HelperReleaseIdentity(
    val releaseId: String,
    val clientVersion: String,
    val productVersion: String,
    val buildNumber: String,
    val gitCommit: String,
    val protocolVersion: String,
    val helperSHA256: String,
    val channel: String,
)

/** 发布身份解析与比较。只有实现放在共享层，两个宿主不会各写一套规则。 */
object HelperReleaseHandshake {
    private val SEMVER = Regex("^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)$")
    private val CLIENT_VERSION = Regex("^\\d\\.\\d\\.\\d\\.\\d$")
    private val COMMIT = Regex("^[0-9a-f]{40}$")
    private val SHA256 = Regex("^[0-9a-f]{64}$")
    private val CHANNELS = setOf("internal", "public")

    private val IDENTITY_FIELDS = setOf(
        "releaseId",
        "clientVersion",
        "productVersion",
        "buildNumber",
        "gitCommit",
        "helperSHA256",
        "channel",
    )

    /** 解析 `version` 应答中的完整身份。缺字段或格式错误时返回 null。 */
    fun parse(result: Map<String, String>): HelperReleaseIdentity? {
        val releaseId = result["releaseId"]?.trim().orEmpty()
        val compatibilityVersion = result["version"]?.trim()
        val clientVersion = result["clientVersion"]?.trim().orEmpty()
        val productVersion = result["productVersion"]?.trim().orEmpty()
        val buildNumber = result["buildNumber"]?.trim().orEmpty()
        val gitCommit = result["gitCommit"]?.trim().orEmpty()
        val protocolVersion = result["protocolVersion"]?.trim().orEmpty()
        val helperSHA256 = result["helperSHA256"]?.trim().orEmpty()
        val channel = result["channel"]?.trim().orEmpty()
        val build = buildNumber.toLongOrNull()
        val protocol = protocolVersion.toIntOrNull()

        if (!CLIENT_VERSION.matches(clientVersion)) return null
        if (!compatibilityVersion.isNullOrEmpty() && compatibilityVersion != clientVersion) return null
        if (!SEMVER.matches(productVersion)) return null
        if (build == null || build.toString() != buildNumber) return null
        if (ClientVersion.fromBuild(build)?.toString() != clientVersion) return null
        if (!COMMIT.matches(gitCommit)) return null
        if (protocol == null || protocol < 1 || protocol.toString() != protocolVersion) return null
        if (!SHA256.matches(helperSHA256)) return null
        if (channel !in CHANNELS) return null
        if (releaseId != "$clientVersion-g$gitCommit") return null

        return HelperReleaseIdentity(
            releaseId = releaseId,
            clientVersion = clientVersion,
            productVersion = productVersion,
            buildNumber = buildNumber,
            gitCommit = gitCommit,
            protocolVersion = protocolVersion,
            helperSHA256 = helperSHA256,
            channel = channel,
        )
    }

    /** 旧 helper 的 `version` 应答没有任何发布身份字段。 */
    fun hasIdentityFields(result: Map<String, String>): Boolean =
        IDENTITY_FIELDS.any(result::containsKey)

    /**
     * 比较完整发布身份。
     *
     * 旧协议、旧版本和旧 build 返回 [HelperStatus.OUTDATED]。
     * 同版本但 commit、摘要、releaseId 或 channel 不同返回 [HelperStatus.IDENTITY_MISMATCH]。
     */
    fun classify(
        expected: HelperReleaseIdentity,
        observed: HelperReleaseIdentity,
        signatureTrusted: Boolean,
    ): HelperStatus {
        if (!signatureTrusted) return HelperStatus.UNTRUSTED
        if (observed.protocolVersion != expected.protocolVersion) return HelperStatus.OUTDATED
        if (isOlder(observed, expected)) return HelperStatus.OUTDATED
        return if (observed == expected) HelperStatus.MATCH else HelperStatus.IDENTITY_MISMATCH
    }

    private fun isOlder(observed: HelperReleaseIdentity, expected: HelperReleaseIdentity): Boolean {
        val observedVersion = clientVersionParts(observed.clientVersion) ?: return false
        val expectedVersion = clientVersionParts(expected.clientVersion) ?: return false
        for (index in 0..3) {
            if (observedVersion[index] != expectedVersion[index]) {
                return observedVersion[index] < expectedVersion[index]
            }
        }
        val observedBuild = observed.buildNumber.toLongOrNull() ?: return false
        val expectedBuild = expected.buildNumber.toLongOrNull() ?: return false
        return observedBuild < expectedBuild
    }

    private fun clientVersionParts(version: String): List<Long>? =
        CLIENT_VERSION.matchEntire(version)?.value?.split('.')?.mapNotNull(String::toLongOrNull)
            ?.takeIf { it.size == 4 }
}

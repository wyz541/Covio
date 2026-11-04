package com.wyz.covio.core

/** 历史四位客户端版本。只用于读取旧安装记录和旧 helper 身份。 */
data class ClientVersion(
    val thousands: Int,
    val hundreds: Int,
    val tens: Int,
    val ones: Int,
) : Comparable<ClientVersion> {
    override fun compareTo(other: ClientVersion): Int {
        compareValues(thousands, other.thousands).takeIf { it != 0 }?.let { return it }
        compareValues(hundreds, other.hundreds).takeIf { it != 0 }?.let { return it }
        compareValues(tens, other.tens).takeIf { it != 0 }?.let { return it }
        return compareValues(ones, other.ones)
    }

    override fun toString(): String = "$thousands.$hundreds.$tens.$ones"

    companion object {
        private val pattern = Regex("^[vV]?(\\d)\\.(\\d)\\.(\\d)\\.(\\d)$")

        fun parse(value: String): ClientVersion? {
            val match = pattern.matchEntire(value.trim()) ?: return null
            return ClientVersion(
                thousands = match.groupValues[1].toIntOrNull() ?: return null,
                hundreds = match.groupValues[2].toIntOrNull() ?: return null,
                tens = match.groupValues[3].toIntOrNull() ?: return null,
                ones = match.groupValues[4].toIntOrNull() ?: return null,
            )
        }

        fun fromBuild(buildNumber: Long): ClientVersion? {
            if (buildNumber !in 1L..9999L) return null
            val digits = buildNumber.toString().padStart(4, '0')
            return ClientVersion(
                thousands = digits[0].digitToInt(),
                hundreds = digits[1].digitToInt(),
                tens = digits[2].digitToInt(),
                ones = digits[3].digitToInt(),
            )
        }
    }
}

/** Semantic Versioning 2.0.0。Build metadata 不参与优先级比较。 */
data class SemanticVersion(
    val major: Int,
    val minor: Int,
    val patch: Int,
    val prerelease: List<String> = emptyList(),
    val buildMetadata: List<String> = emptyList(),
) : Comparable<SemanticVersion> {
    val baseVersion: String
        get() = "$major.$minor.$patch"

    override fun compareTo(other: SemanticVersion): Int {
        compareValues(major, other.major).takeIf { it != 0 }?.let { return it }
        compareValues(minor, other.minor).takeIf { it != 0 }?.let { return it }
        compareValues(patch, other.patch).takeIf { it != 0 }?.let { return it }
        if (prerelease.isEmpty() && other.prerelease.isEmpty()) return 0
        if (prerelease.isEmpty()) return 1
        if (other.prerelease.isEmpty()) return -1
        for (index in 0 until maxOf(prerelease.size, other.prerelease.size)) {
            val left = prerelease.getOrNull(index)
            val right = other.prerelease.getOrNull(index)
            if (left == null) return -1
            if (right == null) return 1
            val result = comparePrereleaseIdentifier(left, right)
            if (result != 0) return result
        }
        return 0
    }

    override fun toString(): String = buildString {
        append(baseVersion)
        if (prerelease.isNotEmpty()) append("-").append(prerelease.joinToString("."))
        if (buildMetadata.isNotEmpty()) append("+").append(buildMetadata.joinToString("."))
    }

    fun isInternalBuild(buildNumber: Long): Boolean =
        buildMetadata.isEmpty() && prerelease == listOf("internal", buildNumber.toString())

    companion object {
        private val pattern = Regex(
            "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)" +
                "(?:-([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?" +
                "(?:\\+([0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*))?$",
        )

        fun parse(value: String): SemanticVersion? {
            val match = pattern.matchEntire(value.trim()) ?: return null
            val prerelease = match.groupValues[4].takeIf(String::isNotEmpty)?.split('.').orEmpty()
            if (prerelease.any { it.isNumericIdentifier() && it.length > 1 && it.startsWith('0') }) {
                return null
            }
            return SemanticVersion(
                major = match.groupValues[1].toIntOrNull() ?: return null,
                minor = match.groupValues[2].toIntOrNull() ?: return null,
                patch = match.groupValues[3].toIntOrNull() ?: return null,
                prerelease = prerelease,
                buildMetadata = match.groupValues[5].takeIf(String::isNotEmpty)?.split('.').orEmpty(),
            )
        }

        /** 解析 GitHub tag。`v` 是 tag 约定，不属于 SemVer 版本本体。 */
        fun parseTag(value: String): SemanticVersion? {
            val tag = value.trim()
            if (!tag.startsWith('v')) return null
            return parse(tag.drop(1))
        }

        private fun comparePrereleaseIdentifier(left: String, right: String): Int {
            val leftNumeric = left.isNumericIdentifier()
            val rightNumeric = right.isNumericIdentifier()
            return when {
                leftNumeric && rightNumeric -> {
                    val length = left.length.compareTo(right.length)
                    if (length != 0) length else left.compareTo(right)
                }
                leftNumeric -> -1
                rightNumeric -> 1
                else -> left.compareTo(right)
            }
        }

        private fun String.isNumericIdentifier(): Boolean = isNotEmpty() && all { it in '0'..'9' }
    }
}

fun isStableVersion(value: String): Boolean = SemanticVersion.parse(value)?.prerelease?.isEmpty() == true

fun isNewerVersion(candidate: String, current: String): Boolean {
    val left = SemanticVersion.parse(candidate) ?: return false
    val right = SemanticVersion.parse(current) ?: return false
    return left > right
}

@Suppress("unused")
fun isStableClientVersion(value: String): Boolean = ClientVersion.parse(value) != null

@Suppress("unused")
fun isNewerClientVersion(candidate: String, current: String): Boolean {
    val left = ClientVersion.parse(candidate) ?: return false
    val right = ClientVersion.parse(current) ?: return false
    return left > right
}

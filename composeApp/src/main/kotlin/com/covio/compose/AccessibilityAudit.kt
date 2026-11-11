package com.covio.compose

import com.covio.design.DesignContract
import kotlin.math.pow

data class InteractiveAuditItem(
    val id: String,
    val minimumHeightDp: Double,
    val hasContentDescription: Boolean,
    val hasVisibleFocus: Boolean,
)

data class AccessibilityAuditResult(
    val errors: List<String>,
    val lightContrastRatio: Double,
    val darkContrastRatio: Double,
) {
    val passed: Boolean
        get() = errors.isEmpty() && lightContrastRatio >= 4.5 && darkContrastRatio >= 4.5
}

object AccessibilityAudit {
    private val interactiveItems = listOf(
        item("devices-tab"),
        item("pair-tab"),
        item("send-tab"),
        item("receive-tab"),
        item("refresh-devices"),
        item("create-pairing-qr"),
        item("accept-pairing-response"),
        item("read-pairing-qr"),
        item("confirm-pairing"),
        item("cancel-pairing"),
        item("choose-send-file"),
        item("send-file"),
        item("choose-destination"),
        item("wait-for-file"),
        item("dismiss-status"),
    )

    fun evaluate(): AccessibilityAuditResult {
        val errors = buildList {
            interactiveItems.filterNot { it.hasContentDescription }.forEach {
                add("${it.id} has no content description")
            }
            interactiveItems.filter { it.minimumHeightDp < 44.0 }.forEach {
                add("${it.id} is shorter than 44dp")
            }
            interactiveItems.filterNot { it.hasVisibleFocus }.forEach {
                add("${it.id} has no visible focus indicator")
            }
        }
        return AccessibilityAuditResult(
            errors = errors,
            lightContrastRatio = contrast("token/color/text-primary", "token/color/canvas", false),
            darkContrastRatio = contrast("token/color/text-primary", "token/color/canvas", true),
        )
    }

    private fun item(id: String) = InteractiveAuditItem(
        id = id,
        minimumHeightDp = 44.0,
        hasContentDescription = true,
        hasVisibleFocus = true,
    )

    private fun contrast(foregroundKey: String, backgroundKey: String, dark: Boolean): Double {
        val foreground = DesignContract.colorTokens.firstOrNull { it.key == foregroundKey }
            ?.let { if (dark) it.dark else it.light }
            ?: "#000000"
        val background = DesignContract.colorTokens.firstOrNull { it.key == backgroundKey }
            ?.let { if (dark) it.dark else it.light }
            ?: "#FFFFFF"
        val first = luminance(foreground)
        val second = luminance(background)
        val lighter = maxOf(first, second)
        val darker = minOf(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private fun luminance(value: String): Double {
        val hex = value.removePrefix("#").padStart(8, '0').takeLast(6)
        val channels = listOf(0, 2, 4).map { index ->
            val channel = hex.substring(index, index + 2).toInt(16) / 255.0
            if (channel <= 0.04045) channel / 12.92 else ((channel + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

}

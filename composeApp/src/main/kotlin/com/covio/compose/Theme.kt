package com.covio.compose

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.covio.design.DesignContract

private fun token(key: String, dark: Boolean): Color {
    val value = DesignContract.colorTokens.firstOrNull { it.key == key }?.let { if (dark) it.dark else it.light } ?: "#000000"
    val hex = value.removePrefix("#")
    val argb = if (hex.length == 6) "FF$hex" else hex.padStart(8, '0')
    return Color(argb.toLong(16).toInt())
}

private fun dim(key: String, dark: Boolean): Float =
    DesignContract.dimensionTokens.firstOrNull { it.key == key }?.let { if (dark) it.dark else it.light }?.toFloat() ?: 0f

data class CovioColors(
    val canvas: Color,
    val surface: Color,
    val elevated: Color,
    val sidebar: Color,
    val text: Color,
    val secondary: Color,
    val divider: Color,
    val accent: Color,
    val success: Color,
    val warning: Color,
    val error: Color,
    val focus: Color,
    val onAccent: Color,
)

@OptIn(ExperimentalTextApi::class)
@Composable
fun CovioTheme(
    dark: Boolean,
    content: @Composable () -> Unit,
) {
    val colors = CovioColors(
        canvas = token("token/color/canvas", dark),
        surface = token("token/color/surface", dark),
        elevated = token("token/color/elevated", dark),
        sidebar = token("token/color/sidebar-fill", dark),
        text = token("token/color/text-primary", dark),
        secondary = token("token/color/text-secondary", dark),
        divider = token("token/color/divider", dark),
        accent = token("token/color/action-fill", dark),
        success = token("token/color/success-fill", dark),
        warning = token("token/color/warning-fill", dark),
        error = token("token/color/error-fill", dark),
        focus = token("token/color/focus-ring", dark),
        onAccent = token("token/color/text-on-accent", dark),
    )
    val font = if ((System.getProperty("os.name") ?: "").contains("Windows", ignoreCase = true)) {
        FontFamily("Segoe UI Variable")
    } else {
        FontFamily.SansSerif
    }
    val body = TextStyle(
        fontFamily = font,
        fontSize = 13.sp,
        lineHeight = 18.sp,
        fontWeight = FontWeight.Normal,
        color = colors.text,
    )
    val typography = Typography(
        bodyLarge = body,
        bodyMedium = body.copy(fontSize = 12.sp, color = colors.secondary),
        labelLarge = body.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium),
        titleMedium = body.copy(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
        titleLarge = body.copy(fontSize = 22.sp, fontWeight = FontWeight.SemiBold),
        headlineSmall = body.copy(fontSize = 26.sp, fontWeight = FontWeight.SemiBold),
    )
    val scheme = if (dark) {
        darkColorScheme(
            primary = colors.accent,
            onPrimary = colors.onAccent,
            background = colors.canvas,
            onBackground = colors.text,
            surface = colors.surface,
            onSurface = colors.text,
            surfaceVariant = colors.elevated,
            onSurfaceVariant = colors.secondary,
            outline = colors.divider,
            error = colors.error,
        )
    } else {
        lightColorScheme(
            primary = colors.accent,
            onPrimary = colors.onAccent,
            background = colors.canvas,
            onBackground = colors.text,
            surface = colors.surface,
            onSurface = colors.text,
            surfaceVariant = colors.elevated,
            onSurfaceVariant = colors.secondary,
            outline = colors.divider,
            error = colors.error,
        )
    }
    MaterialTheme(colorScheme = scheme, typography = typography, content = content)
}

val CovioRadiusCard: Float
    @Composable get() = dim("token/radius/card", false)

val CovioSpace4: Float
    @Composable get() = dim("token/space/4", false)

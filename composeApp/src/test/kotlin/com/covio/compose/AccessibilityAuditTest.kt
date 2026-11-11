package com.covio.compose

import kotlin.test.Test
import kotlin.test.assertTrue

class AccessibilityAuditTest {
    @Test
    fun interactiveBaselineMeetsTargetSizeLabelAndContrast() {
        val result = AccessibilityAudit.evaluate()
        assertTrue(result.passed, result.errors.joinToString("; "))
    }
}

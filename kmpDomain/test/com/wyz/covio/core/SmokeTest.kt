package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SmokeTest {
    /**
     * 版本号要能解析，并与构建号和产品版本一致。
     *
     * 这里不写死具体数字：数字每次发版都变，写死了就得跟着改两处。
     * 真正要守住的是「它是唯一的版本来源，而且格式合法」，
     * Xcode 的版本与它一致由 `ConfigCompatibilityTests` 守。
     */
    @Test
    fun versionIsPresentAndParsable() {
        assertTrue(APP_VERSION.isNotBlank())
        val parsed = requireNotNull(SemanticVersion.parse(APP_VERSION))
        assertEquals(APP_VERSION, parsed.toString())
        assertTrue(parsed.isInternalBuild(APP_BUILD_NUMBER))
        assertEquals(APP_PRODUCT_VERSION, parsed.baseVersion)
    }
}

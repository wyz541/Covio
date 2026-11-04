package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * 目录布局的钉子。
 *
 * 平台数据根由 `PlatformDataRootTest` 覆盖。
 * 这里验证应用名和子目录在真实目标上的拼接。
 */
class PathLayoutTest {
    @Test
    fun `the config directory uses the application id`() {
        assertTrue(
            defaultConfigPath().endsWith("${AppDirectories.userApplicationSupport}/$APP_ID/config.json"),
            "实际值：${defaultConfigPath()}",
        )
    }

    /// 工作台配置与 `config.json` 并列。两者分开，坏掉一个不影响另一个。
    @Test
    fun `the workbench config sits next to the app config`() {
        assertTrue(
            defaultWorkbenchPath().endsWith("${AppDirectories.userApplicationSupport}/$APP_ID/workbench.json"),
            "实际值：${defaultWorkbenchPath()}",
        )
        assertNotEquals(
            defaultConfigPath().substringAfterLast("/"),
            defaultWorkbenchPath().substringAfterLast("/"),
            "工作台配置不该与 config.json 合并成一个文件",
        )
    }

    @Test
    fun `the shelf directory uses the application name`() {
        assertTrue(
            defaultShelfPath().endsWith("${AppDirectories.userApplicationSupport}/$APP_NAME/Screenshots/shelf.json"),
            "实际值：${defaultShelfPath()}",
        )
    }

    @Test
    fun `the clipboard directory uses the application name`() {
        assertTrue(
            ClipboardStore.defaultDirectory().endsWith("${AppDirectories.userApplicationSupport}/$APP_NAME/Clipboard"),
            "实际值：${ClipboardStore.defaultDirectory()}",
        )
    }

    @Test
    fun `the workspace directory uses the application name`() {
        assertTrue(
            WorkspaceStore.defaultDirectory().endsWith("${AppDirectories.userApplicationSupport}/$APP_NAME/Workspace"),
            "实际值：${WorkspaceStore.defaultDirectory()}",
        )
    }

    @Test
    fun `the shelf and the config do not share a directory`() {
        // 晾衣线用 APP_NAME，配置用 APP_ID。混用会让老用户的设置或截图丢失。
        assertNotEquals(
            defaultShelfPath().substringBeforeLast("/Screenshots/"),
            defaultConfigPath().substringBeforeLast("/config.json"),
        )
    }
}

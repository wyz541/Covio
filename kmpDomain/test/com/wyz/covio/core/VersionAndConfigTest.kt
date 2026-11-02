package com.wyz.covio.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import okio.Path.Companion.toPath

class VersionAndConfigTest {
    @Test
    fun `semantic version comparison handles releases and prereleases`() {
        assertTrue(isNewerVersion("1.2.0", "1.1.9"))
        assertTrue(isNewerVersion("1.0.1", "1.0.0"))
        assertFalse(isNewerVersion("1.0.0-beta.1", "1.0.0"))
        assertFalse(isStableVersion("1.0.0-beta.1"))
        assertTrue(isStableVersion("v1.0.0"))
    }

    @Test
    fun `config defaults are written and loaded`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            val store = ConfigStore(path.toString())
            val defaults = store.load()
            assertTrue(defaults.enabled)
            assertEquals(6, defaults.lowBatteryCapacity)
            assertEquals(10, defaults.lowTimeRemainingMinutes)
            assertEquals(null, defaults.hibernateMode)
            assertTrue(defaults.chargeLimitEnabled)
            assertEquals(70, defaults.chargeLimitPercent)
            assertTrue(defaults.power.closedLidZeroBrightness)
            assertEquals(ClosedLidPowerPolicy.ADAPTER, defaults.display?.closedLidPowerPolicy)
            assertTrue(defaults.lidSleepImmediateOnClose)
            assertTrue(path.exists)
        }

    @Test
    fun `version one config migrates new fields to version three defaults`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText("""{"schemaVersion":1,"enabled":false,"disableLidSleepInCharging":true}""")
            val store = ConfigStore(path.toString())
            val loaded = store.load()

            assertEquals(3, loaded.schemaVersion)
            assertFalse(loaded.enabled)
            assertTrue(loaded.disableLidSleepInCharging)
            assertFalse(loaded.disableLidSleepOnBattery)
            assertEquals(ClosedLidPowerPolicy.ADAPTER, loaded.display?.closedLidPowerPolicy)
            assertTrue(loaded.lidSleepImmediateOnClose)
            assertTrue(loaded.darkWakeAwarenessEnabled)

            store.save(loaded)
            val saved = store.load()
            assertEquals(3, saved.schemaVersion)
            assertFalse(saved.disableLidSleepOnBattery)
            assertTrue(saved.darkWakeAwarenessEnabled)
        }

    @Test
    fun `version two config gains disabled screenshot compatibility keys`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            val store = ConfigStore(path.toString())
            path.writeText("""{"schemaVersion":2,"disableLidSleepOnBattery":true,"darkWakeAwarenessEnabled":false}""")
            val loaded = store.load()
            assertEquals(3, loaded.schemaVersion)
            assertTrue(loaded.disableLidSleepOnBattery)
            assertEquals(ClosedLidPowerPolicy.BATTERY, loaded.display?.closedLidPowerPolicy)
            assertTrue(loaded.lidSleepImmediateOnClose)
            assertFalse(loaded.darkWakeAwarenessEnabled)
            assertFalse(loaded.shelfEnabled)
            assertFalse(loaded.screenshotInboxEnabled)
            assertFalse(loaded.shelfSoundsEnabled)
        }

    @Test
    fun `closed lid policy owns legacy lid mirrors`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText(
                """
                {
                    "disableLidSleepInCharging": true,
                    "disableLidSleepOnBattery": true,
                    "lidSleepImmediateOnClose": false,
                    "display": {
                        "schemaVersion": 2,
                        "keepAwakeWhenLidClosed": true,
                        "closedLidPowerPolicy": "sleep",
                        "closedLidDisplayMode": "displayOff",
                        "pauseWhenExternalDisplayConnected": true
                    }
                }
                """.trimIndent(),
            )

            val loaded = ConfigStore(path.toString()).load()

            assertEquals(ClosedLidPowerPolicy.SLEEP, loaded.display?.closedLidPowerPolicy)
            assertFalse(loaded.disableLidSleepInCharging)
            assertFalse(loaded.disableLidSleepOnBattery)
            assertTrue(loaded.lidSleepImmediateOnClose)
        }

    @Test
    fun `invalid config values fall back and unknown fields survive save`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText(
                """{"lowBatteryCapacity":999,"lowTimeRemaining":"bad","updateCheckIntervalHours":0,"unknown":{"keep":true}}""",
            )
            val store = ConfigStore(path.toString())
            val loaded = store.load().copy(enabled = false)
            assertEquals(100, loaded.lowBatteryCapacity)
            assertEquals(10, loaded.lowTimeRemainingMinutes)
            assertEquals(1, loaded.updateCheckIntervalHours)
            store.save(loaded)
            val text = path.readText()
            assertTrue(text.contains("\"unknown\""))
            assertTrue(text.contains("\"keep\""))
        }

    @Test
    fun `config keeps supported hibernate modes and rejects other values`() {
        assertEquals(25, AppConfig(hibernateMode = 25).normalized().hibernateMode)
        assertEquals(null, AppConfig(hibernateMode = 7).normalized().hibernateMode)
    }

    @Test
    fun `charge limit settings survive a save and load`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            val store = ConfigStore(path.toString())
            store.save(
                AppConfig(
                    chargeLimitEnabled = true,
                    chargeLimitPercent = 85,
                    chargeLimitActiveDischarge = true,
                ),
            )

            val loaded = store.load()

            assertTrue(loaded.chargeLimitEnabled)
            assertEquals(85, loaded.chargeLimitPercent)
            assertTrue(loaded.chargeLimitActiveDischarge)
        }

    @Test
    fun `an invalid charge limit falls back to seventy`() {
        assertEquals(70, AppConfig(chargeLimitPercent = 79).normalized().chargeLimitPercent)
        assertEquals(70, AppConfig(chargeLimitPercent = 15).normalized().chargeLimitPercent)
        assertEquals(100, AppConfig(chargeLimitPercent = 100).normalized().chargeLimitPercent)
    }

    @Test
    fun `explicit disabled charge limit survives loading`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText(
                """{"chargeLimitEnabled":false,"chargeLimitPercent":75,"chargeLimitActiveDischarge":false}""",
            )

            val loaded = ConfigStore(path.toString()).load()

            assertFalse(loaded.chargeLimitEnabled)
            assertEquals(75, loaded.chargeLimitPercent)
            assertFalse(loaded.chargeLimitActiveDischarge)
        }

    @Test
    fun `an older config gains the charge limit defaults`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText("""{"schemaVersion":3,"enabled":true}""")

            val loaded = ConfigStore(path.toString()).load()

            assertTrue(loaded.chargeLimitEnabled)
            assertEquals(70, loaded.chargeLimitPercent)
            assertFalse(loaded.chargeLimitActiveDischarge)
        }

    /// M4：剪切板默认开启，两个快捷键是出厂组合。
    @Test
    fun `clipboard defaults record history with the shipped shortcuts`() {
        val config = AppConfig()
        assertTrue(config.clipboardEnabled)
        assertEquals("shift+cmd+V", config.clipboardPasteStackHotKey)
        assertEquals("shift+cmd+C", config.clipboardCaptureHotKey)
    }

    /// 快捷键写法写坏了要退回出厂组合。键名合法性由 Swift 侧判断，
    /// 这里只管空白与长度。
    @Test
    fun `clipboard shortcuts fall back when the value is unusable`() {
        assertEquals(
            DEFAULT_PASTE_STACK_HOT_KEY,
            AppConfig(clipboardPasteStackHotKey = "   ").normalized().clipboardPasteStackHotKey,
        )
        assertEquals(
            DEFAULT_CAPTURE_HOT_KEY,
            AppConfig(clipboardCaptureHotKey = "x".repeat(64)).normalized().clipboardCaptureHotKey,
        )
        assertEquals(
            "control+shift+B",
            AppConfig(clipboardPasteStackHotKey = " control+shift+B ").normalized().clipboardPasteStackHotKey,
        )
    }

    @Test
    fun `clipboard settings survive a save and load`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            val store = ConfigStore(path.toString())
            store.save(
                AppConfig(clipboardEnabled = false, clipboardPasteStackHotKey = "control+shift+B"),
            )

            val loaded = store.load()

            assertFalse(loaded.clipboardEnabled)
            assertEquals("control+shift+B", loaded.clipboardPasteStackHotKey)
            // 没写过的那个用出厂组合。
            assertEquals(DEFAULT_CAPTURE_HOT_KEY, loaded.clipboardCaptureHotKey)
        }

    /// 0.4.2 的 `config.json` 里没有剪切板的键，读回来要是出厂值。
    @Test
    fun `a config without clipboard keys gains the defaults`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText("""{"schemaVersion":3,"enabled":true,"shelfEnabled":false}""")

            val loaded = ConfigStore(path.toString()).load()

            assertTrue(loaded.clipboardEnabled)
            assertEquals(DEFAULT_PASTE_STACK_HOT_KEY, loaded.clipboardPasteStackHotKey)
            assertEquals(DEFAULT_CAPTURE_HOT_KEY, loaded.clipboardCaptureHotKey)
        }

    @Test
    fun `clear removes the configuration file`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            val store = ConfigStore(path.toString())
            store.save(AppConfig())
            assertTrue(path.exists)
            assertTrue(store.clear())
            assertFalse(path.exists)
            assertTrue(store.load().enabled)
        }

    @Test
    fun `update policy ignores prereleases and respects interval`() {
        val config = AppConfig(lastUpdateCheckEpochSeconds = 1_000, updateCheckIntervalHours = 24)
        assertFalse(UpdatePolicy.shouldCheck(config, 1_000 + 23 * 3_600))
        assertTrue(UpdatePolicy.shouldCheck(config, 1_000 + 24 * 3_600))
        val prerelease = UpdateInfo("0.0.2.0-internal", "beta", "https://example.com")
        val stable = UpdateInfo("0.0.2.0", "stable", "https://example.com")
        assertEquals(null, UpdatePolicy.selectUpdate(prerelease, "0.0.1.5"))
        assertEquals(stable, UpdatePolicy.selectUpdate(stable, "0.0.1.5"))
    }

    @Test
    fun `client versions use four decimal place digits`() {
        assertEquals(ClientVersion(0, 0, 1, 5), ClientVersion.parse("v0.0.1.5"))
        assertEquals(ClientVersion(0, 1, 0, 0), ClientVersion.parse("0.1.0.0"))
        assertTrue(isNewerClientVersion("0.1.0.0", "0.0.9.9"))
        assertFalse(isNewerClientVersion("0.0.1.5", "0.0.1.5"))
        assertNull(ClientVersion.parse("0.0.1.6-internal"))
        assertNull(ClientVersion.parse("0.0.1.6-g0123456789abcdef"))
        assertNull(ClientVersion.parse("0.0.1.6+15"))
        assertEquals("0.0.0.1", ClientVersion.fromBuild(1)?.toString())
        assertEquals("0.0.1.6", ClientVersion.fromBuild(16)?.toString())
        assertEquals("0.1.0.0", ClientVersion.fromBuild(100)?.toString())
        assertEquals("9.9.9.9", ClientVersion.fromBuild(9999)?.toString())
        assertNull(ClientVersion.fromBuild(0))
        assertNull(ClientVersion.fromBuild(10000))
    }

    /// M2 的完成判据之一：`config.json` 与 0.4.2 双向兼容。
    /// 这条用 0.4.2 会写出的完整字段集验证读回后逐字段相等。
    @Test
    fun `a config written by an older release loads without loss`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            // 0.4.2 的 ConfigStore.save 会写出全部字段，且 encodeDefaults = true。
            path.writeText(
                """
                {
                    "schemaVersion": 3,
                    "language": "zh-Hans",
                    "enabled": false,
                    "launchAtLogin": true,
                    "lowBatteryCapacitySleep": false,
                    "lowBatteryCapacity": 15,
                    "lowTimeRemaining": 25,
                    "disableIdleSleepInCharging": true,
                    "disableLidSleepInCharging": false,
                    "disableLidSleepOnBattery": true,
                    "darkWakeAwarenessEnabled": false,
                    "lidSleepImmediateOnClose": false,
                    "notificationsEnabled": false,
                    "updateCheckEnabled": false,
                    "updateCheckIntervalHours": 48,
                    "lastUpdateCheckEpochSeconds": 1700000000,
                    "hibernateMode": 25,
                    "firstRun": false,
                    "shelfEnabled": false,
                    "screenshotInboxEnabled": false,
                    "shelfSoundsEnabled": false
                }
            """.trimIndent(),
            )

            val loaded = ConfigStore(path.toString()).load()

            assertEquals(3, loaded.schemaVersion)
            assertEquals("zh-Hans", loaded.language)
            assertFalse(loaded.enabled)
            assertTrue(loaded.launchAtLogin)
            assertFalse(loaded.lowBatteryCapacitySleep)
            assertEquals(15, loaded.lowBatteryCapacity)
            assertEquals(25, loaded.lowTimeRemainingMinutes)
            assertTrue(loaded.disableIdleSleepInCharging)
            assertFalse(loaded.disableLidSleepInCharging)
            assertTrue(loaded.disableLidSleepOnBattery)
            assertFalse(loaded.darkWakeAwarenessEnabled)
            assertTrue(loaded.lidSleepImmediateOnClose)
            assertEquals(ClosedLidPowerPolicy.BATTERY, loaded.display?.closedLidPowerPolicy)
            assertFalse(loaded.notificationsEnabled)
            assertFalse(loaded.updateCheckEnabled)
            assertEquals(48, loaded.updateCheckIntervalHours)
            assertEquals(1_700_000_000L, loaded.lastUpdateCheckEpochSeconds)
            assertEquals(25, loaded.hibernateMode)
            assertFalse(loaded.firstRun)
            assertFalse(loaded.shelfEnabled)
            assertFalse(loaded.screenshotInboxEnabled)
            assertFalse(loaded.shelfSoundsEnabled)
        }

    /// 反向：本版写出的文件，0.4.2 必须能原样读回。所以每个键名都要在。
    @Test
    fun `saved config contains every key the older release expects`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            ConfigStore(path.toString()).save(AppConfig())
            val text = path.readText()

            val expectedKeys = listOf(
                "schemaVersion", "language", "enabled", "launchAtLogin",
                "lowBatteryCapacitySleep", "lowBatteryCapacity", "lowTimeRemaining",
                "disableIdleSleepInCharging", "disableLidSleepInCharging", "disableLidSleepOnBattery",
                "darkWakeAwarenessEnabled", "lidSleepImmediateOnClose", "notificationsEnabled",
                "updateCheckEnabled", "updateCheckIntervalHours", "lastUpdateCheckEpochSeconds",
                "hibernateMode", "firstRun", "shelfEnabled", "screenshotInboxEnabled",
                "shelfSoundsEnabled",
            )
            for (key in expectedKeys) {
                assertTrue(text.contains("\"$key\""), "config.json 缺少键 $key")
            }
        }

    @Test
    fun `old version three config loads default power settings`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText("""{"schemaVersion":3,"enabled":false}""")
            val loaded = ConfigStore(path.toString()).load()

            assertEquals(3, loaded.schemaVersion)
            assertFalse(loaded.enabled)
            assertTrue(loaded.power.closedLidZeroBrightness)
            assertEquals(PowerConfig.defaults(), loaded.power)
        }

    @Test
    fun `power config round trips and keeps unknown nested keys`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText(
                """
                {
                  "power": {
                    "enabled": false,
                    "keepAwakeOnAdapter": false,
                    "keepAwakeOnBattery": true,
                    "allowClosedLid": false,
                    "pauseClosedLidWithExternalDisplay": false,
                    "batteryFloorPercent": 25,
                    "batteryFloorRecoveryPercent": 30,
                    "yieldOnLowPowerMode": false,
                    "heatGuardEnabled": false,
                    "closedLidTimeCapMinutes": 90,
                    "closedLidZeroBrightness": true,
                    "futureNestedKey": {"keep": true}
                  }
                }
                """.trimIndent(),
            )
            val store = ConfigStore(path.toString())
            val loaded = store.load()

            assertFalse(loaded.power.enabled)
            assertFalse(loaded.power.keepAwakeOnAdapter)
            assertTrue(loaded.power.keepAwakeOnBattery)
            assertFalse(loaded.power.allowClosedLid)
            assertFalse(loaded.power.pauseClosedLidWithExternalDisplay)
            assertEquals(25, loaded.power.batteryFloorPercent)
            assertEquals(30, loaded.power.batteryFloorRecoveryPercent)
            assertFalse(loaded.power.yieldOnLowPowerMode)
            assertFalse(loaded.power.heatGuardEnabled)
            assertEquals(90, loaded.power.closedLidTimeCapMinutes)
            assertTrue(loaded.power.closedLidZeroBrightness)

            store.save(loaded)
            val text = path.readText()
            assertTrue(text.contains("futureNestedKey"))
            assertTrue(text.contains("\"keep\""))
        }

    @Test
    fun `explicitly disabled experimental black screen survives loading`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText("""{"power":{"closedLidZeroBrightness":false}}""")

            val loaded = ConfigStore(path.toString()).load()

            assertFalse(loaded.power.closedLidZeroBrightness)
        }

    @Test
    fun `bad power key falls back without affecting sibling keys`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText("""{"power":{"enabled":"yes","batteryFloorPercent":25}}""")
            val loaded = ConfigStore(path.toString()).load()

            assertEquals(PowerConfig.defaults().enabled, loaded.power.enabled)
            assertEquals(25, loaded.power.batteryFloorPercent)
            assertTrue(loaded.power.closedLidZeroBrightness)
        }

    @Test
    fun `display config migrates from legacy power fields`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText(
                """
                {
                  "power": {
                    "allowClosedLid": false,
                    "pauseClosedLidWithExternalDisplay": false,
                    "closedLidZeroBrightness": true
                  }
                }
                """.trimIndent(),
            )

            val loaded = ConfigStore(path.toString()).load()

            assertFalse(loaded.display!!.keepAwakeWhenLidClosed)
            assertEquals(ClosedLidDisplayMode.BLACK_SCREEN_PIPELINE, loaded.display!!.closedLidDisplayMode)
            assertFalse(loaded.display!!.pauseWhenExternalDisplayConnected)
            assertFalse(loaded.power.allowClosedLid)
            assertTrue(loaded.power.closedLidZeroBrightness)
        }

    @Test
    fun `display config overrides the legacy power mirror`() =
        withTemporaryDirectory("config") { directory ->
            val path = directory.resolve("config.json")
            path.writeText(
                """
                {
                  "power": {
                    "allowClosedLid": true,
                    "pauseClosedLidWithExternalDisplay": true,
                    "closedLidZeroBrightness": true
                  },
                  "display": {
                    "schemaVersion": 1,
                    "keepAwakeWhenLidClosed": false,
                    "closedLidDisplayMode": "displayOff",
                    "pauseWhenExternalDisplayConnected": false,
                    "futureNestedKey": {"keep": true}
                  }
                }
                """.trimIndent(),
            )
            val store = ConfigStore(path.toString())
            val loaded = store.load()

            assertFalse(loaded.display!!.keepAwakeWhenLidClosed)
            assertEquals(ClosedLidDisplayMode.DISPLAY_OFF, loaded.display!!.closedLidDisplayMode)
            assertFalse(loaded.power.allowClosedLid)
            assertFalse(loaded.power.pauseClosedLidWithExternalDisplay)
            assertFalse(loaded.power.closedLidZeroBrightness)

            store.save(loaded)
            val text = path.readText()
            assertTrue(text.contains("futureNestedKey"))
            assertTrue(text.contains("\"keep\""))
        }

    /// 默认路径必须与 0.4.2 完全一致，否则老用户的设置会丢。
    @Test
    fun `default paths match the older release layout`() {
        val config = defaultConfigPath()
        assertTrue(
            config.endsWith("/Library/Application Support/$APP_ID/config.json"),
            "配置路径不对：$config",
        )
        val shelf = defaultShelfPath()
        assertTrue(
            shelf.endsWith("/Library/Application Support/$APP_NAME/Screenshots/shelf.json"),
            "晾衣线路径不对：$shelf",
        )
        assertTrue(config.toPath().isAbsolute)
        assertTrue(shelf.toPath().isAbsolute)
    }

    /**
     * 配置文件写不进去时不抛异常。
     *
     * Kotlin 的异常跨到 Swift 没有接收方，会直接终止进程。
     * 设置页每改一项都会落盘，磁盘满或者目录被删就会走到这里。
     */
    @Test
    fun `config save swallows write failures`() =
        withTemporaryDirectory("config") { directory ->
            // 拿一个普通文件当目录用，写它下面的路径一定失败。
            val blocker = directory.resolve("blocker")
            blocker.writeText("not a directory")
            val store = ConfigStore(blocker.resolve("config.json").toString())

            // 要的就是不抛异常。抛出去的话 Swift 那边会直接终止进程。
            store.save(AppConfig(lowBatteryCapacity = 42))

            assertEquals("not a directory", blocker.readText(), "失败时不该动到那个文件")
        }
}

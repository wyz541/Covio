package com.wyz.covio.core

object UpdatePolicy {
    fun shouldCheck(config: AppConfig, nowEpochSeconds: Long): Boolean {
        if (!config.updateCheckEnabled) return false
        val interval = config.updateCheckIntervalHours.coerceAtLeast(1) * 3_600L
        return nowEpochSeconds - config.lastUpdateCheckEpochSeconds >= interval
    }

    fun selectUpdate(candidate: UpdateInfo?, currentVersion: String): UpdateInfo? {
        if (candidate == null || !isStableVersion(candidate.version)) return null
        return candidate.takeIf { isNewerVersion(it.version, currentVersion) }
    }
}

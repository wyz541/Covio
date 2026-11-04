//! Update selection and update-check timing.

use crate::{AppConfig, version::is_newer_version, version::is_stable_version};
use serde::{Deserialize, Serialize};

/// One release candidate returned by an update source.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateInfo {
    /// Release version.
    pub version: String,
    /// Release title.
    pub title: String,
    /// Release URL.
    pub release_url: String,
    /// Publication time.
    pub published_at: String,
}

impl UpdateInfo {
    /// Creates an update candidate without a publication time.
    #[must_use]
    pub fn new(
        version: impl Into<String>,
        title: impl Into<String>,
        release_url: impl Into<String>,
    ) -> Self {
        Self {
            version: version.into(),
            title: title.into(),
            release_url: release_url.into(),
            published_at: String::new(),
        }
    }
}

/// Returns whether the update check interval has elapsed.
#[must_use]
pub fn should_check(config: &AppConfig, now_epoch_seconds: i64) -> bool {
    if !config.update_check_enabled {
        return false;
    }
    let interval = i64::from(config.update_check_interval_hours.max(1)) * 3_600;
    now_epoch_seconds.saturating_sub(config.last_update_check_epoch_seconds) >= interval
}

/// Selects a stable candidate newer than the current version.
#[must_use]
pub fn select_update(candidate: Option<&UpdateInfo>, current_version: &str) -> Option<UpdateInfo> {
    let candidate = candidate?;
    if !is_stable_version(&candidate.version)
        || !is_newer_version(&candidate.version, current_version)
    {
        return None;
    }
    Some(candidate.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> AppConfig {
        AppConfig {
            last_update_check_epoch_seconds: 1_000,
            update_check_interval_hours: 24,
            ..AppConfig::default()
        }
    }

    #[test]
    fn update_policy_ignores_prereleases_and_respects_interval() {
        let value = config();
        assert!(!should_check(&value, 1_000 + 23 * 3_600));
        assert!(should_check(&value, 1_000 + 24 * 3_600));

        let prerelease = UpdateInfo::new("0.6.0-internal.24", "beta", "https://example.com");
        let stable = UpdateInfo::new("0.6.0", "stable", "https://example.com");
        assert_eq!(select_update(Some(&prerelease), "0.6.0-internal.23"), None);
        assert_eq!(
            select_update(Some(&stable), "0.6.0-internal.23"),
            Some(stable)
        );
    }

    #[test]
    fn disabled_or_too_frequent_checks_are_skipped() {
        let mut value = config();
        value.update_check_enabled = false;
        assert!(!should_check(&value, i64::MAX));
        value.update_check_enabled = true;
        value.update_check_interval_hours = 0;
        assert!(should_check(&value, 1_000 + 3_600));
        assert!(!should_check(&value, 1_000 + 3_599));
    }

    #[test]
    fn invalid_and_older_candidates_are_ignored() {
        assert_eq!(select_update(None, "1.0.0"), None);
        for version in ["not-semver", "1.0.0", "0.9.9", "1.0.0-beta.1"] {
            let candidate = UpdateInfo::new(version, "candidate", "https://example.com");
            assert_eq!(select_update(Some(&candidate), "1.0.0"), None);
        }
        let candidate = UpdateInfo::new("1.0.1+ci.1", "candidate", "https://example.com");
        assert_eq!(select_update(Some(&candidate), "1.0.0"), Some(candidate));
    }
}

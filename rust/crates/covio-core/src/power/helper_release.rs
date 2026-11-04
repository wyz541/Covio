//! Full app/helper release identity parsing and comparison.

use super::models::HelperStatus;
use crate::version::{ClientVersion, SemanticVersion};
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::sync::OnceLock;

/// Full identity shared by the app and privileged helper.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HelperReleaseIdentity {
    /// Release id.
    pub release_id: String,
    /// Client version.
    pub client_version: String,
    /// Product version.
    pub product_version: String,
    /// Build number as text.
    pub build_number: String,
    /// Git commit.
    pub git_commit: String,
    /// Helper protocol version.
    pub protocol_version: String,
    /// Helper SHA-256.
    pub helper_sha256: String,
    /// Release channel.
    pub channel: String,
}

impl HelperReleaseIdentity {
    /// Returns identity fields as a string map.
    #[must_use]
    pub fn to_result_map(&self) -> std::collections::BTreeMap<String, String> {
        [
            ("releaseId", self.release_id.as_str()),
            ("clientVersion", self.client_version.as_str()),
            ("productVersion", self.product_version.as_str()),
            ("buildNumber", self.build_number.as_str()),
            ("gitCommit", self.git_commit.as_str()),
            ("protocolVersion", self.protocol_version.as_str()),
            ("helperSHA256", self.helper_sha256.as_str()),
            ("channel", self.channel.as_str()),
        ]
        .into_iter()
        .map(|(key, value)| (key.to_owned(), value.to_owned()))
        .collect()
    }
}

/// Release identity rules.
pub struct HelperReleaseHandshake;

impl HelperReleaseHandshake {
    /// Parses a helper version result.
    #[must_use]
    pub fn parse(
        result: &std::collections::BTreeMap<String, String>,
    ) -> Option<HelperReleaseIdentity> {
        let value = |key: &str| result.get(key).map_or("", |value| value.trim());
        let release_id = value("releaseId");
        let compatibility_version = result.get("version").map(|value| value.trim());
        let client_version = value("clientVersion");
        let product_version = value("productVersion");
        let build_number = value("buildNumber");
        let git_commit = value("gitCommit");
        let protocol_version = value("protocolVersion");
        let helper_sha256 = value("helperSHA256");
        let channel = value("channel");
        let build = build_number.parse::<i64>().ok()?;
        let protocol = protocol_version.parse::<i32>().ok()?;
        let semantic_version = SemanticVersion::parse(client_version);
        let legacy_version = ClientVersion::parse(client_version);
        let product = SemanticVersion::parse(product_version)?;

        if semantic_version.is_none() && legacy_version.is_none() {
            return None;
        }
        if compatibility_version.is_some_and(|value| !value.is_empty() && value != client_version) {
            return None;
        }
        if !product.prerelease.is_empty() || !product.build_metadata.is_empty() {
            return None;
        }
        if !(1..=9_999).contains(&build) || build.to_string() != build_number {
            return None;
        }
        if !matches!(channel, "internal" | "public") {
            return None;
        }
        if let Some(version) = &semantic_version {
            if !version.build_metadata.is_empty() {
                return None;
            }
            if product_version != version.base_version() {
                return None;
            }
            let valid_channel = match channel {
                "internal" => version.is_internal_build(build),
                "public" => version.prerelease.is_empty(),
                _ => false,
            };
            if !valid_channel {
                return None;
            }
        } else if ClientVersion::from_build(build)
            .map(|value| value.to_string())
            .as_deref()
            != Some(client_version)
        {
            return None;
        }
        if !commit_pattern().is_match(git_commit) {
            return None;
        }
        if protocol < 1 || protocol.to_string() != protocol_version {
            return None;
        }
        if !sha_pattern().is_match(helper_sha256) {
            return None;
        }
        if release_id != format!("{client_version}-g{git_commit}") {
            return None;
        }
        Some(HelperReleaseIdentity {
            release_id: release_id.to_owned(),
            client_version: client_version.to_owned(),
            product_version: product_version.to_owned(),
            build_number: build_number.to_owned(),
            git_commit: git_commit.to_owned(),
            protocol_version: protocol_version.to_owned(),
            helper_sha256: helper_sha256.to_owned(),
            channel: channel.to_owned(),
        })
    }

    /// Returns whether a result contains any new identity field.
    #[must_use]
    pub fn has_identity_fields(result: &std::collections::BTreeMap<String, String>) -> bool {
        [
            "releaseId",
            "clientVersion",
            "productVersion",
            "buildNumber",
            "gitCommit",
            "helperSHA256",
            "channel",
        ]
        .iter()
        .any(|key| result.contains_key(*key))
    }

    /// Compares expected and observed identities.
    #[must_use]
    pub fn classify(
        expected: &HelperReleaseIdentity,
        observed: &HelperReleaseIdentity,
        signature_trusted: bool,
    ) -> HelperStatus {
        if !signature_trusted {
            return HelperStatus::Untrusted;
        }
        if observed.protocol_version != expected.protocol_version || is_older(observed, expected) {
            return HelperStatus::Outdated;
        }
        if observed == expected {
            HelperStatus::Match
        } else {
            HelperStatus::IdentityMismatch
        }
    }
}

fn is_older(observed: &HelperReleaseIdentity, expected: &HelperReleaseIdentity) -> bool {
    let observed_semantic = SemanticVersion::parse(&observed.client_version);
    let expected_semantic = SemanticVersion::parse(&expected.client_version);
    if let Some(expected_version) = expected_semantic {
        let Some(observed_version) = observed_semantic else {
            return true;
        };
        if observed_version != expected_version {
            return observed_version < expected_version;
        }
    } else {
        let Some(observed_version) = ClientVersion::parse(&observed.client_version) else {
            return false;
        };
        let Some(expected_version) = ClientVersion::parse(&expected.client_version) else {
            return false;
        };
        if observed_version != expected_version {
            return observed_version < expected_version;
        }
    }
    let Some(observed_build) = observed.build_number.parse::<i64>().ok() else {
        return false;
    };
    let Some(expected_build) = expected.build_number.parse::<i64>().ok() else {
        return false;
    };
    observed_build < expected_build
}

fn commit_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| Regex::new(r"^[0-9a-f]{40}$").expect("commit regex"))
}

fn sha_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| Regex::new(r"^[0-9a-f]{64}$").expect("sha regex"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn identity() -> HelperReleaseIdentity {
        HelperReleaseIdentity {
            release_id: format!("0.6.0-internal.24-g{}", "a".repeat(40)),
            client_version: "0.6.0-internal.24".to_owned(),
            product_version: "0.6.0".to_owned(),
            build_number: "24".to_owned(),
            git_commit: "a".repeat(40),
            protocol_version: "10".to_owned(),
            helper_sha256: "b".repeat(64),
            channel: "internal".to_owned(),
        }
    }

    #[test]
    fn parses_and_classifies_identity() {
        let expected = identity();
        let parsed = HelperReleaseHandshake::parse(&expected.to_result_map()).expect("identity");
        assert_eq!(parsed, expected);
        assert_eq!(
            HelperReleaseHandshake::classify(&expected, &parsed, true),
            HelperStatus::Match
        );
        assert_eq!(
            HelperReleaseHandshake::classify(&expected, &parsed, false),
            HelperStatus::Untrusted
        );
    }

    #[test]
    fn rejects_old_identity_and_bad_fields() {
        let expected = identity();
        let mut observed = expected.clone();
        observed.client_version = "0.6.0-internal.23".to_owned();
        observed.release_id = format!("{}-g{}", observed.client_version, observed.git_commit);
        assert_eq!(
            HelperReleaseHandshake::classify(&expected, &observed, true),
            HelperStatus::Outdated
        );
        let mut result = expected.to_result_map();
        result.insert("helperSHA256".to_owned(), "short".to_owned());
        assert_eq!(HelperReleaseHandshake::parse(&result), None);
        assert!(HelperReleaseHandshake::has_identity_fields(&result));
    }

    #[test]
    fn legacy_release_is_outdated_or_mismatched_by_rules() {
        let expected = HelperReleaseIdentity {
            release_id: "0.0.1.6-g0".to_owned(),
            client_version: "0.0.1.6".to_owned(),
            product_version: "0.0.0".to_owned(),
            build_number: "16".to_owned(),
            git_commit: "0".repeat(40),
            protocol_version: "10".to_owned(),
            helper_sha256: "0".repeat(64),
            channel: "internal".to_owned(),
        };
        let parsed = HelperReleaseHandshake::parse(&expected.to_result_map());
        // Legacy client versions do not require a semantic product relationship.
        assert!(parsed.is_none());
    }
}

//! Covio client and semantic version rules.

use regex::Regex;
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::fmt;
use std::sync::OnceLock;

/// Historical four-digit client version.
///
/// This type reads old install records and helper identities. New product
/// versions use [`SemanticVersion`].
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClientVersion {
    /// First digit.
    pub thousands: u8,
    /// Second digit.
    pub hundreds: u8,
    /// Third digit.
    pub tens: u8,
    /// Fourth digit.
    pub ones: u8,
}

impl ClientVersion {
    /// Parses `v0.0.1.5` or `0.0.1.5`.
    #[must_use]
    pub fn parse(value: &str) -> Option<Self> {
        let captures = client_version_pattern().captures(value.trim())?;
        Some(Self {
            thousands: captures.get(1)?.as_str().parse().ok()?,
            hundreds: captures.get(2)?.as_str().parse().ok()?,
            tens: captures.get(3)?.as_str().parse().ok()?,
            ones: captures.get(4)?.as_str().parse().ok()?,
        })
    }

    /// Converts a build number in `1..=9999` to four digits.
    #[must_use]
    pub fn from_build(build_number: i64) -> Option<Self> {
        if !(1..=9_999).contains(&build_number) {
            return None;
        }
        let digits = format!("{build_number:04}");
        let mut values = digits.bytes().map(|byte| byte - b'0');
        Some(Self {
            thousands: values.next()?,
            hundreds: values.next()?,
            tens: values.next()?,
            ones: values.next()?,
        })
    }
}

impl fmt::Display for ClientVersion {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "{}.{}.{}.{}",
            self.thousands, self.hundreds, self.tens, self.ones
        )
    }
}

/// Semantic Versioning 2.0.0 version.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SemanticVersion {
    /// Major number.
    pub major: u32,
    /// Minor number.
    pub minor: u32,
    /// Patch number.
    pub patch: u32,
    /// Prerelease identifiers.
    pub prerelease: Vec<String>,
    /// Build metadata identifiers.
    pub build_metadata: Vec<String>,
}

impl SemanticVersion {
    /// Returns `major.minor.patch`.
    #[must_use]
    pub fn base_version(&self) -> String {
        format!("{}.{}.{}", self.major, self.minor, self.patch)
    }

    /// Returns true for `-internal.<buildNumber>` without build metadata.
    #[must_use]
    pub fn is_internal_build(&self, build_number: i64) -> bool {
        self.build_metadata.is_empty()
            && self.prerelease == ["internal".to_owned(), build_number.to_string()]
    }

    /// Parses canonical SemVer 2.0.0 text.
    #[must_use]
    pub fn parse(value: &str) -> Option<Self> {
        let captures = semantic_version_pattern().captures(value.trim())?;
        let parse_number = |index: usize| -> Option<u32> {
            i32::try_from(captures.get(index)?.as_str().parse::<i64>().ok()?)
                .ok()
                .and_then(|value| u32::try_from(value).ok())
        };
        let prerelease = captures
            .get(4)
            .map(|capture| capture.as_str())
            .filter(|value| !value.is_empty())
            .map(|value| value.split('.').map(str::to_owned).collect::<Vec<_>>())
            .unwrap_or_default();
        if prerelease
            .iter()
            .any(|identifier| is_numeric_identifier(identifier) && has_leading_zero(identifier))
        {
            return None;
        }
        Some(Self {
            major: parse_number(1)?,
            minor: parse_number(2)?,
            patch: parse_number(3)?,
            prerelease,
            build_metadata: captures
                .get(5)
                .map(|capture| capture.as_str())
                .filter(|value| !value.is_empty())
                .map(|value| value.split('.').map(str::to_owned).collect())
                .unwrap_or_default(),
        })
    }

    /// Parses a GitHub `v` tag.
    #[must_use]
    pub fn parse_tag(value: &str) -> Option<Self> {
        value.trim().strip_prefix('v').and_then(Self::parse)
    }
}

impl Ord for SemanticVersion {
    fn cmp(&self, other: &Self) -> Ordering {
        self.major
            .cmp(&other.major)
            .then_with(|| self.minor.cmp(&other.minor))
            .then_with(|| self.patch.cmp(&other.patch))
            .then_with(
                || match (self.prerelease.is_empty(), other.prerelease.is_empty()) {
                    (true, true) => Ordering::Equal,
                    (true, false) => Ordering::Greater,
                    (false, true) => Ordering::Less,
                    (false, false) => compare_prerelease(&self.prerelease, &other.prerelease),
                },
            )
    }
}

impl PartialOrd for SemanticVersion {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl fmt::Display for SemanticVersion {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.base_version())?;
        if !self.prerelease.is_empty() {
            write!(formatter, "-{}", self.prerelease.join("."))?;
        }
        if !self.build_metadata.is_empty() {
            write!(formatter, "+{}", self.build_metadata.join("."))?;
        }
        Ok(())
    }
}

fn compare_prerelease(left: &[String], right: &[String]) -> Ordering {
    for (left, right) in left.iter().zip(right) {
        let ordering = compare_prerelease_identifier(left, right);
        if ordering != Ordering::Equal {
            return ordering;
        }
    }
    left.len().cmp(&right.len())
}

fn compare_prerelease_identifier(left: &str, right: &str) -> Ordering {
    match (is_numeric_identifier(left), is_numeric_identifier(right)) {
        (true, true) => left.len().cmp(&right.len()).then_with(|| left.cmp(right)),
        (true, false) => Ordering::Less,
        (false, true) => Ordering::Greater,
        (false, false) => left.cmp(right),
    }
}

fn is_numeric_identifier(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit())
}

fn has_leading_zero(value: &str) -> bool {
    value.len() > 1 && value.starts_with('0')
}

/// Returns true when `value` is a stable semantic version.
#[must_use]
pub fn is_stable_version(value: &str) -> bool {
    SemanticVersion::parse(value).is_some_and(|version| version.prerelease.is_empty())
}

/// Returns true when both versions parse and `candidate` is newer.
#[must_use]
pub fn is_newer_version(candidate: &str, current: &str) -> bool {
    let Some(candidate) = SemanticVersion::parse(candidate) else {
        return false;
    };
    let Some(current) = SemanticVersion::parse(current) else {
        return false;
    };
    candidate > current
}

/// Returns true when `value` is a valid four-digit client version.
#[must_use]
pub fn is_stable_client_version(value: &str) -> bool {
    ClientVersion::parse(value).is_some()
}

/// Returns true when both client versions parse and `candidate` is newer.
#[must_use]
pub fn is_newer_client_version(candidate: &str, current: &str) -> bool {
    let Some(candidate) = ClientVersion::parse(candidate) else {
        return false;
    };
    let Some(current) = ClientVersion::parse(current) else {
        return false;
    };
    candidate > current
}

fn client_version_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN
        .get_or_init(|| Regex::new(r"^[vV]?(\d)\.(\d)\.(\d)\.(\d)$").expect("client version regex"))
}

fn semantic_version_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        Regex::new(
            r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$",
        )
        .expect("semantic version regex")
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn semantic_versions_compare_releases_and_prereleases() {
        assert!(is_newer_version("0.6.1", "0.6.0"));
        assert!(is_newer_version("0.6.0", "0.6.0-internal.23"));
        assert!(is_newer_version("0.6.0-internal.10", "0.6.0-internal.9"));
        assert!(!is_newer_version("0.6.0-internal.9", "0.6.0-internal.10"));
        assert!(!is_stable_version("0.6.0-internal.23"));
        assert!(is_stable_version("0.6.0"));
    }

    #[test]
    fn semantic_parser_enforces_canonical_syntax() {
        assert_eq!(
            SemanticVersion::parse("0.6.0-internal.23").map(|value| value.to_string()),
            Some("0.6.0-internal.23".to_owned())
        );
        assert_eq!(
            SemanticVersion::parse("0.6.0+ci.7").map(|value| value.to_string()),
            Some("0.6.0+ci.7".to_owned())
        );
        for value in [
            "v0.6.0",
            "0.06.0",
            "0.6.0-internal.023",
            "0.6.0-internal..23",
            "0.6.0-",
            "0.6.0+",
            "0.6",
            "0.6.0.1",
        ] {
            assert_eq!(SemanticVersion::parse(value), None, "{value}");
        }
        assert_eq!(
            SemanticVersion::parse_tag("v0.6.0-internal.23").map(|value| value.to_string()),
            Some("0.6.0-internal.23".to_owned())
        );
        assert_eq!(SemanticVersion::parse_tag("0.6.0"), None);
    }

    #[test]
    fn build_metadata_does_not_change_priority() {
        let left = SemanticVersion::parse("1.2.3+build.1").unwrap();
        let right = SemanticVersion::parse("1.2.3+build.2").unwrap();
        assert_eq!(left.cmp(&right), Ordering::Equal);
        assert_eq!(left.to_string(), "1.2.3+build.1");
    }

    #[test]
    fn numeric_prerelease_identifiers_sort_before_text() {
        assert!(is_newer_version("1.0.0-alpha", "1.0.0-1"));
        assert!(is_newer_version("1.0.0-alpha.1", "1.0.0-alpha"));
        assert!(is_newer_version("1.0.0-beta", "1.0.0-alpha"));
    }

    #[test]
    fn internal_build_detection_is_exact() {
        assert!(
            SemanticVersion::parse("0.6.0-internal.16")
                .unwrap()
                .is_internal_build(16)
        );
        assert!(
            !SemanticVersion::parse("0.6.0-internal.16+ci")
                .unwrap()
                .is_internal_build(16)
        );
        assert!(
            !SemanticVersion::parse("0.6.0-internal.17")
                .unwrap()
                .is_internal_build(16)
        );
    }

    #[test]
    fn client_versions_use_four_decimal_digits() {
        assert_eq!(
            ClientVersion::parse("v0.0.1.5").map(|value| value.to_string()),
            Some("0.0.1.5".to_owned())
        );
        assert_eq!(
            ClientVersion::parse("0.1.0.0").map(|value| value.to_string()),
            Some("0.1.0.0".to_owned())
        );
        assert!(is_newer_client_version("0.1.0.0", "0.0.9.9"));
        assert!(!is_newer_client_version("0.0.1.5", "0.0.1.5"));
        for value in [
            "0.0.1.6-internal",
            "0.0.1.6-g0123456789abcdef",
            "0.0.1.6+15",
        ] {
            assert_eq!(ClientVersion::parse(value), None, "{value}");
        }
        assert_eq!(
            ClientVersion::from_build(1).map(|value| value.to_string()),
            Some("0.0.0.1".to_owned())
        );
        assert_eq!(
            ClientVersion::from_build(16).map(|value| value.to_string()),
            Some("0.0.1.6".to_owned())
        );
        assert_eq!(
            ClientVersion::from_build(100).map(|value| value.to_string()),
            Some("0.1.0.0".to_owned())
        );
        assert_eq!(
            ClientVersion::from_build(9_999).map(|value| value.to_string()),
            Some("9.9.9.9".to_owned())
        );
        assert_eq!(ClientVersion::from_build(0), None);
        assert_eq!(ClientVersion::from_build(10_000), None);
    }
}

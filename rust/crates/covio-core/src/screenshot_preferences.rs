//! macOS screenshot preference text rules.
//!
//! Running `defaults` is a platform capability. This module only parses its
//! output and formats values for a write-back.

/// Removes paired quotes from a successful string read.
#[must_use]
pub fn parse_string(exit_code: i32, output: &str) -> Option<String> {
    if exit_code != 0 {
        return None;
    }
    let trimmed = output.trim();
    let unquoted = trimmed
        .strip_prefix('"')
        .and_then(|value| value.strip_suffix('"'))
        .filter(|_| trimmed.len() >= 2)
        .unwrap_or(trimmed);
    (!unquoted.is_empty()).then(|| unquoted.to_owned())
}

/// Parses a recognized boolean spelling. Unknown values stay unknown.
#[must_use]
pub fn parse_boolean(exit_code: i32, output: &str) -> Option<bool> {
    if exit_code != 0 {
        return None;
    }
    match output.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" => Some(true),
        "0" | "false" | "no" => Some(false),
        _ => None,
    }
}

/// Formats a stored snapshot value for `defaults write`.
#[must_use]
pub fn write_argument(value: &str, is_string: bool) -> String {
    if is_string {
        value.to_owned()
    } else if value == "1" {
        "true".to_owned()
    } else {
        "false".to_owned()
    }
}

/// Treats an already-absent key as a successful deletion.
#[must_use]
pub fn delete_is_success(exit_code: i32, output: &str) -> bool {
    exit_code == 0 || output.to_ascii_lowercase().contains("does not exist")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trims_plain_strings_and_removes_paired_quotes() {
        assert_eq!(
            parse_string(0, " /tmp/shots\n ").as_deref(),
            Some("/tmp/shots")
        );
        assert_eq!(
            parse_string(0, "\"/tmp/My Shots\"\n").as_deref(),
            Some("/tmp/My Shots")
        );
        assert_eq!(parse_string(0, "\"").as_deref(), Some("\""));
    }

    #[test]
    fn failed_or_empty_string_reads_are_unknown() {
        assert_eq!(parse_string(1, "/tmp/shots"), None);
        assert_eq!(parse_string(0, "\n"), None);
        assert_eq!(parse_string(0, "\"\""), None);
    }

    #[test]
    fn parses_known_boolean_spellings() {
        for value in ["1", "true", "YES", " yes\n"] {
            assert_eq!(parse_boolean(0, value), Some(true));
        }
        for value in ["0", "false", "No", " no\n"] {
            assert_eq!(parse_boolean(0, value), Some(false));
        }
        assert_eq!(parse_boolean(0, "maybe"), None);
        assert_eq!(parse_boolean(1, "1"), None);
    }

    #[test]
    fn formats_write_arguments() {
        assert_eq!(write_argument("1", false), "true");
        assert_eq!(write_argument("0", false), "false");
        assert_eq!(write_argument("1", true), "1");
        assert_eq!(write_argument("/tmp/shots", true), "/tmp/shots");
    }

    #[test]
    fn missing_keys_count_as_successful_deletes() {
        assert!(delete_is_success(0, ""));
        assert!(delete_is_success(
            1,
            "The domain/default pair does not exist"
        ));
        assert!(delete_is_success(1, "Domain DOES NOT EXIST"));
        assert!(!delete_is_success(1, "Operation not permitted"));
    }
}

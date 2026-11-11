//! Directory protocol path validation.

use super::super::{TransferError, TransferErrorCode};
use unicode_normalization::UnicodeNormalization;

/// Maximum UTF-8 length of one relative protocol path.
pub const MAX_DIRECTORY_PATH_BYTES: usize = 4_096;
/// Maximum UTF-8 length of one path component.
pub const MAX_DIRECTORY_COMPONENT_BYTES: usize = 255;
/// Maximum nesting depth accepted in one directory manifest.
pub const MAX_DIRECTORY_DEPTH: usize = 64;

/// Validates one normalized relative directory path.
pub fn validate_directory_path(path: &str) -> Result<(), TransferError> {
    let normalized = path.nfc().collect::<String>();
    if normalized != path {
        return Err(invalid_path());
    }
    if path.is_empty()
        || path.len() > MAX_DIRECTORY_PATH_BYTES
        || path.starts_with('/')
        || path.contains('\\')
    {
        return Err(invalid_path());
    }
    let components = path.split('/').collect::<Vec<_>>();
    if components.len() > MAX_DIRECTORY_DEPTH {
        return Err(invalid_path());
    }
    for component in components {
        validate_component(component)?;
    }
    Ok(())
}

/// Validates one path component such as a root folder name.
pub fn validate_component(component: &str) -> Result<(), TransferError> {
    let normalized = component.nfc().collect::<String>();
    if normalized != component
        || component.is_empty()
        || component.len() > MAX_DIRECTORY_COMPONENT_BYTES
        || component == "."
        || component == ".."
        || component.contains(['/', '\\'])
        || component.ends_with('.')
        || component.ends_with(' ')
        || component.chars().any(|character| {
            character.is_control() || matches!(character, '<' | '>' | ':' | '"' | '|' | '?' | '*')
        })
        || is_windows_reserved_name(component)
    {
        return Err(invalid_path());
    }
    Ok(())
}

/// Returns the case-folded key used for collision detection.
#[must_use]
pub fn path_collision_key(path: &str) -> String {
    path.to_lowercase()
}

fn is_windows_reserved_name(component: &str) -> bool {
    let stem = component
        .split('.')
        .next()
        .unwrap_or(component)
        .trim_end_matches([' ', '.'])
        .to_ascii_uppercase();
    matches!(
        stem.as_str(),
        "CON" | "PRN" | "AUX" | "NUL" | "CLOCK$" | "CONIN$" | "CONOUT$"
    ) || matches!(
        stem.as_str(),
        "COM1"
            | "COM2"
            | "COM3"
            | "COM4"
            | "COM5"
            | "COM6"
            | "COM7"
            | "COM8"
            | "COM9"
            | "LPT1"
            | "LPT2"
            | "LPT3"
            | "LPT4"
            | "LPT5"
            | "LPT6"
            | "LPT7"
            | "LPT8"
            | "LPT9"
            | "COM¹"
            | "COM²"
            | "COM³"
            | "LPT¹"
            | "LPT²"
            | "LPT³"
    )
}

fn invalid_path() -> TransferError {
    TransferError::new(
        TransferErrorCode::PathInvalid,
        "directory path is invalid",
        false,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_nested_nfc_paths() {
        validate_directory_path("photos/2026/holiday.jpg").expect("valid path");
    }

    #[test]
    fn rejects_traversal_absolute_and_mixed_separators() {
        for path in ["../escape", "/root/file", "C:/file", "a//b", "a\\b"] {
            assert_eq!(
                validate_directory_path(path)
                    .expect_err("invalid path")
                    .code(),
                TransferErrorCode::PathInvalid
            );
        }
    }

    #[test]
    fn rejects_windows_reserved_names_and_trailing_characters() {
        for path in [
            "CON",
            "con.txt",
            "folder/PRN.log",
            "COM1 .txt",
            "file.",
            "file ",
            "a/b/c.",
        ] {
            assert_eq!(
                validate_directory_path(path)
                    .expect_err("invalid path")
                    .code(),
                TransferErrorCode::PathInvalid
            );
        }
    }

    #[test]
    fn rejects_control_characters_and_non_nfc_text() {
        assert!(validate_directory_path("folder/file\u{0000}.txt").is_err());
        assert!(validate_directory_path("cafe\u{0301}/menu.txt").is_err());
    }

    #[test]
    fn collision_key_is_unicode_case_folded() {
        assert_eq!(path_collision_key("Folder/README.md"), "folder/readme.md");
    }
}

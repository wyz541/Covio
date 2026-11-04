//! Lexical path rules shared by shelf and clipboard logic.

use std::path::{Component, Path, PathBuf};
use std::sync::OnceLock;

/// Image extensions accepted by the screenshot shelf.
const SHELF_IMAGE_EXTENSIONS: [&str; 8] =
    ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp"];

/// Returns whether the final path segment has an accepted image extension.
#[must_use]
pub fn is_shelf_image_file_name(file_name: &str) -> bool {
    file_name.rsplit_once('.').is_some_and(|(_, extension)| {
        SHELF_IMAGE_EXTENSIONS
            .iter()
            .any(|accepted| extension.eq_ignore_ascii_case(accepted))
    })
}

/// Returns whether the final path segment has an accepted image extension.
#[must_use]
pub fn is_shelf_image_file(path: &str) -> bool {
    Path::new(path)
        .file_name()
        .and_then(|name| name.to_str())
        .map_or_else(
            || {
                path.rsplit(['/', '\\'])
                    .next()
                    .is_some_and(is_shelf_image_file_name)
            },
            is_shelf_image_file_name,
        )
}

/// Returns whether a file is inside a dedicated directory or has the screenshot attribute.
#[must_use]
pub fn accepts_shelf_file(
    path: &str,
    dedicated_directory: &str,
    has_screen_capture_attribute: impl Fn(&str) -> bool,
) -> bool {
    if !is_shelf_image_file(path) {
        return false;
    }
    if is_path_inside(path, dedicated_directory) {
        return true;
    }
    has_screen_capture_attribute(path)
}

/// Compares paths by normalized path segments.
#[must_use]
pub fn is_path_inside(path: &str, directory: &str) -> bool {
    if path.trim().is_empty() || directory.trim().is_empty() {
        return false;
    }
    let child = PathBuf::from(canonical_path(path));
    let parent = PathBuf::from(canonical_path(directory));
    child.starts_with(parent)
}

/// Makes a path absolute and removes `.` and `..` segments without resolving links.
#[must_use]
pub fn canonical_path(value: &str) -> String {
    let path = Path::new(value);
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        working_directory().join(path)
    };
    lexical_normalize(&absolute).to_string_lossy().into_owned()
}

fn working_directory() -> &'static Path {
    static WORKING_DIRECTORY: OnceLock<PathBuf> = OnceLock::new();
    WORKING_DIRECTORY.get_or_init(|| {
        std::env::current_dir().unwrap_or_else(|_| PathBuf::from(std::path::MAIN_SEPARATOR_STR))
    })
}

fn lexical_normalize(path: &Path) -> PathBuf {
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Prefix(prefix) => normalized.push(prefix.as_os_str()),
            Component::RootDir => normalized.push(Component::RootDir.as_os_str()),
            Component::CurDir => {}
            Component::ParentDir => {
                if !normalized.pop() && !path.is_absolute() {
                    normalized.push("..");
                }
            }
            Component::Normal(segment) => normalized.push(segment),
        }
    }
    normalized
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn image_extension_uses_only_the_final_segment() {
        assert!(is_shelf_image_file_name("photo.HEIC"));
        assert!(is_shelf_image_file_name("photo.webp"));
        assert!(!is_shelf_image_file_name("notes.txt"));
        assert!(!is_shelf_image_file_name("noextension"));
        assert!(!is_shelf_image_file("/tmp/album.png/notes"));
    }

    #[test]
    fn path_containment_uses_segments() {
        assert!(is_path_inside("/tmp/screenshots/a.png", "/tmp/screenshots"));
        assert!(!is_path_inside(
            "/tmp/screenshots-backup/a.png",
            "/tmp/screenshots"
        ));
    }

    #[test]
    fn acceptance_checks_extension_before_attribute() {
        assert!(accepts_shelf_file(
            "/tmp/screenshots/capture.PNG",
            "/tmp/screenshots",
            |_| false
        ));
        assert!(!accepts_shelf_file(
            "/tmp/other.png",
            "/tmp/screenshots",
            |_| false
        ));
        assert!(accepts_shelf_file(
            "/tmp/other.png",
            "/tmp/screenshots",
            |_| true
        ));
        assert!(!accepts_shelf_file(
            "/tmp/notes.txt",
            "/tmp/screenshots",
            |_| true
        ));
    }
}

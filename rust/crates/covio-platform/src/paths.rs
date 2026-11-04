//! User-data path policies shared by platform adapters.

use std::path::{Path, PathBuf};

/// Stable application identifier.
pub const APP_ID: &str = "com.wyz.covio";

/// Stable application display name used by the existing data layout.
pub const APP_NAME: &str = "Covio";

/// Paths for durable application data.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DataPaths {
    /// The platform user application-support root.
    pub user_application_support: PathBuf,
    /// Configuration directory keyed by [`APP_ID`].
    pub config_directory: PathBuf,
    /// Existing configuration file.
    pub config_file: PathBuf,
    /// Existing screenshot shelf file keyed by [`APP_NAME`].
    pub shelf_file: PathBuf,
    /// Existing clipboard directory.
    pub clipboard_directory: PathBuf,
    /// Existing workspace directory.
    pub workspace_directory: PathBuf,
}

impl DataPaths {
    /// Builds the existing Covio data layout under a user application-support root.
    ///
    /// The configuration directory uses `APP_ID`.
    /// Screenshot, clipboard, and workspace data use `APP_NAME`.
    /// These names must not be unified without a data migration.
    #[must_use]
    pub fn apple(user_application_support: impl Into<PathBuf>) -> Self {
        let user_application_support = user_application_support.into();
        let config_directory = user_application_support.join(APP_ID);
        let app_directory = user_application_support.join(APP_NAME);
        let screenshot_directory = app_directory.join("Screenshots");
        Self {
            user_application_support,
            config_file: config_directory.join("config.json"),
            config_directory,
            shelf_file: screenshot_directory.join("shelf.json"),
            clipboard_directory: app_directory.join("Clipboard"),
            workspace_directory: app_directory.join("Workspace"),
        }
    }

    /// Returns the existing clipboard state file.
    #[must_use]
    pub fn clipboard_file(&self) -> PathBuf {
        self.clipboard_directory.join("clipboard.json")
    }
}

/// Appends the legacy `.tmp` suffix without replacing the original extension.
#[must_use]
pub fn temporary_path(path: &Path) -> PathBuf {
    let mut value = path.as_os_str().to_os_string();
    value.push(".tmp");
    PathBuf::from(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apple_layout_uses_the_id_and_name_separately() {
        let root = Path::new("/tmp/Library/Application Support");
        let paths = DataPaths::apple(root);
        assert_eq!(paths.config_file, root.join("com.wyz.covio/config.json"));
        assert_eq!(paths.shelf_file, root.join("Covio/Screenshots/shelf.json"));
        assert_eq!(paths.clipboard_directory, root.join("Covio/Clipboard"));
        assert_eq!(paths.workspace_directory, root.join("Covio/Workspace"));
        assert_ne!(paths.config_directory, root.join("Covio"));
    }
}

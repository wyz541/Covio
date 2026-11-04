//! User-data path policies shared by platform adapters.

use crate::PlatformError;
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

    /// Builds the Windows data layout under one application directory.
    ///
    /// The caller supplies the complete `%LOCALAPPDATA%\\Covio` directory.
    /// Configuration remains at the root. Screenshot, clipboard, and
    /// workspace data remain in their existing child directories.
    #[must_use]
    pub fn windows(app_directory: impl Into<PathBuf>) -> Self {
        let app_directory = app_directory.into();
        let screenshot_directory = app_directory.join("Screenshots");
        Self {
            user_application_support: app_directory.clone(),
            config_directory: app_directory.clone(),
            config_file: app_directory.join("config.json"),
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

/// Resolves the stable Windows current-user application directory.
#[derive(Debug, Clone, Copy, Default)]
pub struct WindowsAppDataDirectory;

impl WindowsAppDataDirectory {
    /// Returns `%LOCALAPPDATA%\\Covio` without reading the environment.
    #[must_use]
    pub fn app_directory(local_app_data: impl AsRef<Path>) -> PathBuf {
        local_app_data.as_ref().join(APP_NAME)
    }

    /// Reads `%LOCALAPPDATA%` and returns its Covio application directory.
    ///
    /// A missing or empty variable returns a typed unavailable error. The
    /// adapter does not fall back to the current directory or a temp directory.
    pub fn from_environment() -> Result<PathBuf, PlatformError> {
        let root = std::env::var_os("LOCALAPPDATA")
            .filter(|value| !value.is_empty())
            .ok_or_else(|| PlatformError::unavailable("Windows app data is unavailable"))?;
        Ok(Self::app_directory(root))
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

    #[test]
    fn windows_layout_keeps_the_existing_app_directory() {
        let root = Path::new("/tmp/LocalAppData/Covio");
        let paths = DataPaths::windows(root);
        assert_eq!(paths.config_file, root.join("config.json"));
        assert_eq!(paths.shelf_file, root.join("Screenshots/shelf.json"));
        assert_eq!(
            paths.clipboard_file(),
            root.join("Clipboard/clipboard.json")
        );
        assert_eq!(paths.workspace_directory, root.join("Workspace"));
        assert_eq!(
            WindowsAppDataDirectory::app_directory("/tmp/LocalAppData"),
            root
        );
    }
}

//! Platform capability contracts for the Covio Rust core.
//!
//! This crate defines bounded ports. It does not provide a plaintext fallback
//! for secure storage and it does not perform OS-specific work in core code.

#![deny(unsafe_code)]

mod capabilities;
mod filesystem;
#[cfg(any(target_os = "macos", target_os = "ios"))]
mod macos_secret;
mod paths;
mod secret;
mod windows_adapters;
mod windows_credentials;

pub use capabilities::{
    CAPABILITY_KIND_COUNT, CapabilityKind, CapabilityStatus, MacCapabilitySet, WindowsCapabilitySet,
};
pub use filesystem::StdFileStore;
#[cfg(any(target_os = "macos", target_os = "ios"))]
pub use macos_secret::KeychainSecretStore;
pub use paths::{APP_ID, APP_NAME, DataPaths, WindowsAppDataDirectory, temporary_path};
pub use secret::{SecretKey, SecretStore, SecretValue, UnavailableSecretStore};
pub use windows_adapters::{
    Clipboard, FilePicker, FilePickerRequest, MAX_CLIPBOARD_TEXT_BYTES,
    MAX_NOTIFICATION_BODY_BYTES, MAX_NOTIFICATION_TITLE_BYTES, MAX_PICKED_FILES,
    MAX_STARTUP_NAME_BYTES, NotificationRequest, Notifier, ScreenshotDirectory,
    StartupRegistration, StartupSpec, UnavailablePlatformAdapter, UpdateHandoff,
    UpdateHandoffRequest, WindowsScreenshotDirectory,
};
#[cfg(target_os = "windows")]
pub use windows_adapters::{
    WindowsClipboard, WindowsFilePicker, WindowsPlatformAdapters, WindowsStartupRegistration,
    WindowsToastNotifier, WindowsUpdateHandoff,
};
pub use windows_credentials::{
    CredentialBackend, CredentialStore, WINDOWS_SECRET_BLOB_LIMIT, WINDOWS_SECRET_SERVICE,
};
#[cfg(target_os = "windows")]
pub use windows_credentials::{WindowsCredentialBackend, WindowsCredentialStore};

use std::error::Error;
use std::fmt;
use std::path::Path;

/// Stable platform capability error categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlatformErrorCode {
    /// The capability is not available.
    Unavailable,
    /// The caller supplied invalid input.
    InvalidArgument,
    /// The operating system denied access.
    PermissionDenied,
    /// The user must authenticate before the operation can continue.
    AuthenticationRequired,
    /// The device is locked.
    Locked,
    /// The user or caller cancelled the operation.
    Cancelled,
    /// The platform invalidated a protected key.
    KeyInvalidated,
    /// The operating system reported an I/O failure.
    Io,
}

/// A typed platform capability error.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlatformError {
    code: PlatformErrorCode,
    message: String,
    retryable: bool,
}

impl PlatformError {
    /// Creates a platform capability error.
    #[must_use]
    pub fn new(code: PlatformErrorCode, message: impl Into<String>, retryable: bool) -> Self {
        Self {
            code,
            message: message.into(),
            retryable,
        }
    }

    /// Creates an unavailable capability error.
    #[must_use]
    pub fn unavailable(message: impl Into<String>) -> Self {
        Self::new(PlatformErrorCode::Unavailable, message, false)
    }

    /// Creates an invalid-input error.
    #[must_use]
    pub fn invalid_argument(message: impl Into<String>) -> Self {
        Self::new(PlatformErrorCode::InvalidArgument, message, false)
    }

    /// Creates a permission-denied error.
    #[must_use]
    pub fn permission_denied(message: impl Into<String>) -> Self {
        Self::new(PlatformErrorCode::PermissionDenied, message, false)
    }

    /// Creates an authentication-required error.
    #[must_use]
    pub fn authentication_required(message: impl Into<String>) -> Self {
        Self::new(PlatformErrorCode::AuthenticationRequired, message, true)
    }

    /// Creates a locked-device error.
    #[must_use]
    pub fn locked(message: impl Into<String>) -> Self {
        Self::new(PlatformErrorCode::Locked, message, true)
    }

    /// Creates a cancelled-operation error.
    #[must_use]
    pub fn cancelled(message: impl Into<String>) -> Self {
        Self::new(PlatformErrorCode::Cancelled, message, false)
    }

    /// Creates a key-invalidated error.
    #[must_use]
    pub fn key_invalidated(message: impl Into<String>) -> Self {
        Self::new(PlatformErrorCode::KeyInvalidated, message, false)
    }

    /// Creates an I/O error.
    #[must_use]
    pub fn io(message: impl Into<String>, retryable: bool) -> Self {
        Self::new(PlatformErrorCode::Io, message, retryable)
    }

    /// Returns the stable error category.
    #[must_use]
    pub const fn code(&self) -> PlatformErrorCode {
        self.code
    }

    /// Returns the internal error message.
    #[must_use]
    pub fn message(&self) -> &str {
        &self.message
    }

    /// Returns whether the caller may retry.
    #[must_use]
    pub const fn retryable(&self) -> bool {
        self.retryable
    }
}

impl fmt::Display for PlatformError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for PlatformError {}

/// Filesystem entry kind reported by a platform adapter.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileEntryKind {
    /// A regular file.
    File,
    /// A directory.
    Directory,
    /// A symbolic link. Directory scanning must not follow this link.
    Symlink,
    /// A device, pipe, socket, or another unsupported entry.
    Other,
}

/// Portable file metadata exposed by a filesystem adapter.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileEntryMetadata {
    /// Entry kind.
    pub kind: FileEntryKind,
    /// File size in bytes. Directories use zero.
    pub size: u64,
    /// Modification time in Unix milliseconds.
    pub modified_at_ms: Option<i64>,
    /// Whether the current user cannot write the entry.
    pub readonly: bool,
    /// Whether the owner executable bit is set.
    pub executable: bool,
}

impl FileEntryMetadata {
    /// Creates metadata for a regular file fallback.
    #[must_use]
    pub const fn file(size: u64) -> Self {
        Self {
            kind: FileEntryKind::File,
            size,
            modified_at_ms: None,
            readonly: false,
            executable: false,
        }
    }
}

/// Filesystem capability used by durable-state stores.
pub trait FileStore {
    /// Reads a file. A missing file returns `Ok(None)`.
    fn read(&self, path: &Path) -> Result<Option<Vec<u8>>, PlatformError>;

    /// Returns whether a file exists.
    ///
    /// Implementations should override this when they can check existence
    /// without reading the whole file.
    fn exists(&self, path: &Path) -> Result<bool, PlatformError> {
        self.read(path).map(|contents| contents.is_some())
    }

    /// Returns the file size. A missing file returns `Ok(None)`.
    ///
    /// Native adapters should override this with an OS metadata call.
    fn metadata_size(&self, path: &Path) -> Result<Option<u64>, PlatformError> {
        Ok(self.read(path)?.map(|contents| contents.len() as u64))
    }

    /// Returns portable metadata without following a final symbolic link.
    fn metadata(&self, path: &Path) -> Result<Option<FileEntryMetadata>, PlatformError> {
        Ok(self.metadata_size(path)?.map(FileEntryMetadata::file))
    }

    /// Lists direct child names without following symbolic links.
    fn directory_entries(&self, _path: &Path) -> Result<Vec<String>, PlatformError> {
        Err(PlatformError::unavailable(
            "directory enumeration is unavailable",
        ))
    }

    /// Reads a bounded byte range. A missing file returns `Ok(None)`.
    ///
    /// Native adapters should override this to avoid reading the full file.
    fn read_range(
        &self,
        path: &Path,
        offset: u64,
        length: usize,
    ) -> Result<Option<Vec<u8>>, PlatformError> {
        Ok(self.read(path)?.map(|contents| {
            let start = usize::try_from(offset)
                .unwrap_or(usize::MAX)
                .min(contents.len());
            let end = start.saturating_add(length).min(contents.len());
            contents[start..end].to_vec()
        }))
    }

    /// Creates a directory and its parents.
    fn create_dir_all(&self, path: &Path) -> Result<(), PlatformError>;

    /// Writes through a same-directory temporary file and atomic rename.
    fn write_atomic(&self, path: &Path, contents: &[u8]) -> Result<(), PlatformError>;

    /// Appends bytes and returns the resulting file size.
    ///
    /// Native adapters should override this with an append-only file handle.
    fn append(&self, path: &Path, contents: &[u8]) -> Result<u64, PlatformError> {
        let mut existing = self.read(path)?.unwrap_or_default();
        existing.extend_from_slice(contents);
        self.write_atomic(path, &existing)?;
        Ok(existing.len() as u64)
    }

    /// Atomically moves one file over another path.
    ///
    /// Native adapters should override this with an OS atomic rename.
    fn atomic_move(&self, source: &Path, target: &Path) -> Result<(), PlatformError> {
        let contents = self
            .read(source)?
            .ok_or_else(|| PlatformError::io("source file is missing", false))?;
        self.write_atomic(target, &contents)?;
        self.remove_file(source)?;
        Ok(())
    }

    /// Replaces a target with a source file while preserving the old target on failure.
    ///
    /// Native adapters should override this with an OS atomic replacement.
    fn atomic_replace(&self, source: &Path, target: &Path) -> Result<(), PlatformError> {
        self.remove_file(target)?;
        self.atomic_move(source, target)
    }

    /// Truncates a file to an exact length.
    fn truncate(&self, path: &Path, length: u64) -> Result<(), PlatformError> {
        let mut contents = self
            .read(path)?
            .ok_or_else(|| PlatformError::io("file is missing", false))?;
        let length = usize::try_from(length).unwrap_or(usize::MAX);
        let target = length.min(contents.len());
        contents.truncate(target);
        self.write_atomic(path, &contents)
    }

    /// Applies portable read-only and owner-executable metadata.
    fn set_permissions(
        &self,
        _path: &Path,
        _readonly: bool,
        _executable: bool,
    ) -> Result<(), PlatformError> {
        Err(PlatformError::unavailable(
            "filesystem metadata updates are unavailable",
        ))
    }

    /// Removes a file. A missing file returns `Ok(false)`.
    fn remove_file(&self, path: &Path) -> Result<bool, PlatformError>;

    /// Removes a directory tree. A missing directory is a successful no-op.
    fn remove_tree(&self, path: &Path) -> Result<(), PlatformError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn temporary_path_appends_the_compatibility_suffix() {
        let path = Path::new("/tmp/config.json");
        assert_eq!(temporary_path(path), Path::new("/tmp/config.json.tmp"));
    }
}

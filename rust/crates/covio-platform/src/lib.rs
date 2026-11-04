//! Platform capability contracts for the Covio Rust core.
//!
//! This crate defines bounded ports. It does not provide a plaintext fallback
//! for secure storage and it does not perform OS-specific work in core code.

#![forbid(unsafe_code)]

mod paths;
mod secret;

pub use paths::{APP_ID, APP_NAME, DataPaths, temporary_path};
pub use secret::{SecretKey, SecretStore, SecretValue, UnavailableSecretStore};

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

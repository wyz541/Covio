//! Shared, UI-independent types for the Covio Rust application core.
//!
//! This crate owns identifiers and state revisions that cross platform
//! boundaries. It does not own platform windows, rendering, or OS services.

#![forbid(unsafe_code)]

pub mod clipboard;
mod config;
pub mod design_contract;
pub mod path_policy;
pub mod power;
pub mod shelf;
pub mod update;
pub mod version;
pub mod workspace;

pub use config::{
    AppConfig, CONFIG_SCHEMA_VERSION, ClosedLidDisplayMode, ClosedLidPowerPolicy, ConfigLoadResult,
    ConfigLoadSource, ConfigLoadWarning, ConfigStore, DEFAULT_CAPTURE_HOT_KEY,
    DEFAULT_CHARGE_LIMIT_PERCENT, DEFAULT_FILE_NAMING_MAX_UTF8_BYTES,
    DEFAULT_FILE_NAMING_MIN_CONFIDENCE, DEFAULT_FILE_NAMING_TEMPLATE, DEFAULT_PASTE_STACK_HOT_KEY,
    DisplayConfig, FILE_NAMING_SCHEMA_VERSION, FileNamingConflictPolicy, FileNamingDateSource,
    FileNamingPolicy, PowerConfig, SUPPORTED_HIBERNATE_MODES,
};

pub use design_contract::{
    DesignContract, DesignContractDiagnostic, DesignContractReader, DesignContractSeverity,
    DesignContractValidationResult, DesignCopyEntry, DesignToken,
};
pub use update::{UpdateInfo, select_update, should_check};
pub use version::{
    ClientVersion, SemanticVersion, is_newer_client_version, is_newer_version,
    is_stable_client_version, is_stable_version,
};

use covio_platform::{PlatformError, PlatformErrorCode};
use serde::{Deserialize, Serialize};
use std::error::Error;
use std::fmt;

/// A bounded request identifier supplied by a platform host.
pub const MAX_REQUEST_ID_BYTES: usize = 128;

/// A monotonic session generation.
#[derive(
    Debug, Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize,
)]
#[serde(transparent)]
pub struct Generation(u64);

impl Generation {
    /// The initial generation.
    pub const INITIAL: Self = Self(0);

    /// Creates a generation from a raw value.
    #[must_use]
    pub const fn new(value: u64) -> Self {
        Self(value)
    }

    /// Returns the raw generation value.
    #[must_use]
    pub const fn get(self) -> u64 {
        self.0
    }

    /// Returns the next generation when the counter has not overflowed.
    #[must_use]
    pub const fn checked_next(self) -> Option<Self> {
        match self.0.checked_add(1) {
            Some(value) => Some(Self(value)),
            None => None,
        }
    }
}

/// A monotonic revision within one generation.
#[derive(
    Debug, Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize,
)]
#[serde(transparent)]
pub struct Revision(u64);

impl Revision {
    /// The initial revision.
    pub const INITIAL: Self = Self(0);

    /// Creates a revision from a raw value.
    #[must_use]
    pub const fn new(value: u64) -> Self {
        Self(value)
    }

    /// Returns the raw revision value.
    #[must_use]
    pub const fn get(self) -> u64 {
        self.0
    }

    /// Returns the next revision when the counter has not overflowed.
    #[must_use]
    pub const fn checked_next(self) -> Option<Self> {
        match self.0.checked_add(1) {
            Some(value) => Some(Self(value)),
            None => None,
        }
    }
}

/// A validated request identifier.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct RequestId(String);

impl RequestId {
    /// Creates a request identifier after checking length and characters.
    ///
    /// Valid characters are ASCII letters, digits, `-`, `_`, `.`, `:`, and `/`.
    pub fn try_new(value: impl Into<String>) -> Result<Self, CoreError> {
        let value = value.into();
        if value.is_empty()
            || value.len() > MAX_REQUEST_ID_BYTES
            || !value.bytes().all(is_request_id_byte)
        {
            return Err(CoreError::new(
                CoreErrorCode::InvalidArgument,
                "request id is empty, too long, or contains unsupported characters",
            ));
        }
        Ok(Self(value))
    }

    /// Returns the identifier as a string slice.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl fmt::Display for RequestId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

const fn is_request_id_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b':' | b'/')
}

/// An absolute deadline in Unix milliseconds.
#[derive(
    Debug, Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize,
)]
#[serde(transparent)]
pub struct Deadline(u64);

impl Deadline {
    /// Creates a deadline from Unix milliseconds.
    #[must_use]
    pub const fn from_unix_millis(value: u64) -> Self {
        Self(value)
    }

    /// Returns the deadline in Unix milliseconds.
    #[must_use]
    pub const fn as_unix_millis(self) -> u64 {
        self.0
    }

    /// Returns true when the deadline has been reached.
    #[must_use]
    pub const fn is_reached(self, now_unix_millis: u64) -> bool {
        now_unix_millis >= self.0
    }
}

/// A stable error category returned by core operations.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CoreErrorCode {
    /// The caller supplied invalid input.
    InvalidArgument,
    /// A requested object does not exist.
    NotFound,
    /// The operation conflicts with current durable state.
    Conflict,
    /// The operation is not available on this platform or release.
    Unsupported,
    /// The caller used an outdated generation.
    StaleGeneration,
    /// The caller used an outdated revision.
    StaleRevision,
    /// The operation was cancelled.
    Cancelled,
    /// The operation exceeded its deadline.
    DeadlineExceeded,
    /// The core is draining or stopped.
    ShuttingDown,
    /// A platform capability failed.
    Io,
    /// An unexpected internal failure occurred.
    Internal,
}

/// A typed core error.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoreError {
    code: CoreErrorCode,
    message: String,
    retryable: bool,
}

impl CoreError {
    /// Creates a core error.
    #[must_use]
    pub fn new(code: CoreErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            retryable: matches!(
                code,
                CoreErrorCode::DeadlineExceeded
                    | CoreErrorCode::ShuttingDown
                    | CoreErrorCode::Io
                    | CoreErrorCode::Internal
            ),
        }
    }

    /// Returns the stable error category.
    #[must_use]
    pub const fn code(&self) -> CoreErrorCode {
        self.code
    }

    /// Returns the internal error message.
    ///
    /// The bridge must not serialize this text directly.
    #[must_use]
    pub fn message(&self) -> &str {
        &self.message
    }

    /// Returns whether the caller may retry the operation.
    #[must_use]
    pub const fn retryable(&self) -> bool {
        self.retryable
    }
}

impl fmt::Display for CoreError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for CoreError {}

impl From<PlatformError> for CoreError {
    fn from(error: PlatformError) -> Self {
        let code = match error.code() {
            PlatformErrorCode::Unavailable => CoreErrorCode::Unsupported,
            PlatformErrorCode::InvalidArgument => CoreErrorCode::InvalidArgument,
            PlatformErrorCode::PermissionDenied | PlatformErrorCode::Io => CoreErrorCode::Io,
        };
        let message = match code {
            CoreErrorCode::Unsupported => "platform capability is unavailable",
            CoreErrorCode::InvalidArgument => "platform input is invalid",
            CoreErrorCode::Io => "platform capability failed",
            _ => "platform capability failed",
        };
        Self::new(code, message)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generations_and_revisions_do_not_wrap() {
        assert_eq!(Generation::new(1).checked_next(), Some(Generation::new(2)));
        assert_eq!(Generation::new(u64::MAX).checked_next(), None);
        assert_eq!(Revision::new(u64::MAX).checked_next(), None);
    }

    #[test]
    fn request_ids_accept_uuid_and_trace_shapes() {
        let id = RequestId::try_new("3c1f9e0a:42/session-1").expect("valid id");
        assert_eq!(id.as_str(), "3c1f9e0a:42/session-1");
    }

    #[test]
    fn request_ids_reject_empty_control_and_long_values() {
        assert!(RequestId::try_new("").is_err());
        assert!(RequestId::try_new("has space").is_err());
        assert!(RequestId::try_new("line\nbreak").is_err());
        assert!(RequestId::try_new("a".repeat(MAX_REQUEST_ID_BYTES + 1)).is_err());
    }

    #[test]
    fn deadlines_are_inclusive() {
        let deadline = Deadline::from_unix_millis(100);
        assert!(!deadline.is_reached(99));
        assert!(deadline.is_reached(100));
    }

    #[test]
    fn core_errors_keep_retry_policy() {
        let error = CoreError::new(CoreErrorCode::Unsupported, "unsupported");
        assert!(!error.retryable());
        let error = CoreError::new(CoreErrorCode::Io, "io failed");
        assert!(error.retryable());
    }
}

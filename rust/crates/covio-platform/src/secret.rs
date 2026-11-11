//! Secure-storage capability contracts.

use crate::{PlatformError, PlatformErrorCode};
use std::fmt;
use zeroize::Zeroize;

/// A stable secret identifier.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct SecretKey(String);

impl SecretKey {
    /// Creates a secret key after checking length and characters.
    pub fn try_new(value: impl Into<String>) -> Result<Self, PlatformError> {
        let value = value.into();
        if value.is_empty() || value.len() > 128 || !value.bytes().all(is_secret_key_byte) {
            return Err(PlatformError::invalid_argument("secret key is invalid"));
        }
        Ok(Self(value))
    }

    /// Returns the key as a string slice.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

const fn is_secret_key_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b':' | b'/')
}

/// Secret bytes with redacted debug output and zeroization on drop.
pub struct SecretValue(Vec<u8>);

impl SecretValue {
    /// Creates a secret value from raw bytes.
    #[must_use]
    pub fn new(value: impl Into<Vec<u8>>) -> Self {
        Self(value.into())
    }

    /// Returns the secret bytes to a caller that needs the backend value.
    #[must_use]
    pub fn expose(&self) -> &[u8] {
        &self.0
    }

    /// Returns the secret length.
    #[must_use]
    pub fn len(&self) -> usize {
        self.0.len()
    }

    /// Returns whether the secret is empty.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

impl fmt::Debug for SecretValue {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("SecretValue(<redacted>)")
    }
}

impl Drop for SecretValue {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

/// Secure-storage capability.
///
/// Implementations must not fall back to plaintext files or configuration JSON.
pub trait SecretStore {
    /// Reads a secret. A missing key returns `Ok(None)`.
    fn read(&self, key: &SecretKey) -> Result<Option<SecretValue>, PlatformError>;

    /// Writes or replaces a secret.
    fn write(&self, key: &SecretKey, value: &SecretValue) -> Result<(), PlatformError>;

    /// Deletes a secret. A missing key is a successful no-op.
    fn delete(&self, key: &SecretKey) -> Result<(), PlatformError>;
}

impl<T: SecretStore + ?Sized> SecretStore for Box<T> {
    fn read(&self, key: &SecretKey) -> Result<Option<SecretValue>, PlatformError> {
        (**self).read(key)
    }

    fn write(&self, key: &SecretKey, value: &SecretValue) -> Result<(), PlatformError> {
        (**self).write(key, value)
    }

    fn delete(&self, key: &SecretKey) -> Result<(), PlatformError> {
        (**self).delete(key)
    }
}

/// A secret store used until a native platform adapter is installed.
#[derive(Debug, Clone, Copy, Default)]
pub struct UnavailableSecretStore;

impl SecretStore for UnavailableSecretStore {
    fn read(&self, _key: &SecretKey) -> Result<Option<SecretValue>, PlatformError> {
        Err(unavailable())
    }

    fn write(&self, _key: &SecretKey, _value: &SecretValue) -> Result<(), PlatformError> {
        Err(unavailable())
    }

    fn delete(&self, _key: &SecretKey) -> Result<(), PlatformError> {
        Err(unavailable())
    }
}

fn unavailable() -> PlatformError {
    PlatformError::new(
        PlatformErrorCode::Unavailable,
        "secure storage is unavailable",
        false,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secret_debug_output_is_redacted() {
        let secret = SecretValue::new(b"top-secret".to_vec());
        let debug = format!("{secret:?}");
        assert_eq!(debug, "SecretValue(<redacted>)");
        assert!(!debug.contains("top-secret"));
    }

    #[test]
    fn secret_value_is_accessible_only_through_expose() {
        let secret = SecretValue::new(b"token".to_vec());
        assert_eq!(secret.expose(), b"token");
        assert_eq!(secret.len(), 5);
        assert!(!secret.is_empty());
    }

    #[test]
    fn secret_keys_are_bounded() {
        assert!(SecretKey::try_new("provider/api-key").is_ok());
        assert!(SecretKey::try_new("").is_err());
        assert!(SecretKey::try_new("has space").is_err());
        assert!(SecretKey::try_new("a".repeat(129)).is_err());
    }

    #[test]
    fn unavailable_store_has_no_plaintext_fallback() {
        let store = UnavailableSecretStore;
        let key = SecretKey::try_new("provider/api-key").expect("valid key");
        let error = store.read(&key).expect_err("unavailable");
        assert_eq!(error.code(), PlatformErrorCode::Unavailable);
    }
}

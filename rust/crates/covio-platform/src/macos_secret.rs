//! macOS Keychain `SecretStore` adapter.

use crate::{PlatformError, SecretKey, SecretStore, SecretValue};
use security_framework::passwords::{
    PasswordOptions, delete_generic_password_options, generic_password,
    set_generic_password_options,
};

const DEFAULT_SERVICE: &str = "com.wyz.covio.credentials";
const ERR_SEC_ITEM_NOT_FOUND: i32 = -25300;
const ERR_SEC_AUTH_FAILED: i32 = -25293;
const ERR_SEC_INTERACTION_NOT_ALLOWED: i32 = -25308;
const ERR_SEC_USER_CANCELED: i32 = -128;
const ERR_SEC_MISSING_ENTITLEMENT: i32 = -34018;

/// Backend operations used by [`KeychainSecretStore`].
pub trait KeychainBackend {
    /// Reads one backend value.
    fn read(&self, service: &str, account: &str) -> Result<Option<Vec<u8>>, PlatformError>;
    /// Writes or replaces one backend value.
    fn write(&self, service: &str, account: &str, value: &[u8]) -> Result<(), PlatformError>;
    /// Deletes one backend value.
    fn delete(&self, service: &str, account: &str) -> Result<(), PlatformError>;
}

/// Security.framework Keychain backend.
#[derive(Debug, Clone, Copy, Default)]
pub struct SecurityKeychainBackend;

impl KeychainBackend for SecurityKeychainBackend {
    fn read(&self, service: &str, account: &str) -> Result<Option<Vec<u8>>, PlatformError> {
        match generic_password(password_options(service, account, true)) {
            Ok(value) => Ok(Some(value)),
            Err(error)
                if matches!(
                    error.code(),
                    ERR_SEC_ITEM_NOT_FOUND | ERR_SEC_MISSING_ENTITLEMENT
                ) =>
            {
                match generic_password(password_options(service, account, false)) {
                    Ok(value) => Ok(Some(value)),
                    Err(error) if error.code() == ERR_SEC_ITEM_NOT_FOUND => Ok(None),
                    Err(error) => Err(keychain_error(error.code())),
                }
            }
            Err(error) => Err(keychain_error(error.code())),
        }
    }

    fn write(&self, service: &str, account: &str, value: &[u8]) -> Result<(), PlatformError> {
        match set_generic_password_options(value, password_options(service, account, true)) {
            Ok(()) => Ok(()),
            Err(error) if error.code() == ERR_SEC_MISSING_ENTITLEMENT => {
                set_generic_password_options(value, password_options(service, account, false))
                    .map_err(|error| keychain_error(error.code()))
            }
            Err(error) => Err(keychain_error(error.code())),
        }
    }

    fn delete(&self, service: &str, account: &str) -> Result<(), PlatformError> {
        match delete_generic_password_options(password_options(service, account, true)) {
            Ok(()) => Ok(()),
            Err(error)
                if matches!(
                    error.code(),
                    ERR_SEC_ITEM_NOT_FOUND | ERR_SEC_MISSING_ENTITLEMENT
                ) =>
            {
                match delete_generic_password_options(password_options(service, account, false)) {
                    Ok(()) => Ok(()),
                    Err(error) if error.code() == ERR_SEC_ITEM_NOT_FOUND => Ok(()),
                    Err(error) => Err(keychain_error(error.code())),
                }
            }
            Err(error) => Err(keychain_error(error.code())),
        }
    }
}

/// macOS Keychain secret store.
#[derive(Debug, Clone)]
pub struct KeychainSecretStore<B = SecurityKeychainBackend> {
    service: String,
    backend: B,
}

impl Default for KeychainSecretStore<SecurityKeychainBackend> {
    fn default() -> Self {
        Self::new(DEFAULT_SERVICE)
    }
}

impl KeychainSecretStore<SecurityKeychainBackend> {
    /// Creates a Keychain store for one service name.
    #[must_use]
    pub fn new(service: impl Into<String>) -> Self {
        Self {
            service: service.into(),
            backend: SecurityKeychainBackend,
        }
    }
}

impl<B: KeychainBackend> KeychainSecretStore<B> {
    /// Creates a store with an injected backend for tests or future adapters.
    #[must_use]
    pub fn with_backend(service: impl Into<String>, backend: B) -> Self {
        Self {
            service: service.into(),
            backend,
        }
    }
}

impl<B: KeychainBackend> SecretStore for KeychainSecretStore<B> {
    fn read(&self, key: &SecretKey) -> Result<Option<SecretValue>, PlatformError> {
        self.backend
            .read(&self.service, key.as_str())
            .map(|value| value.map(SecretValue::new))
    }

    fn write(&self, key: &SecretKey, value: &SecretValue) -> Result<(), PlatformError> {
        self.backend
            .write(&self.service, key.as_str(), value.expose())
    }

    fn delete(&self, key: &SecretKey) -> Result<(), PlatformError> {
        self.backend.delete(&self.service, key.as_str())
    }
}

fn password_options(service: &str, account: &str, data_protection: bool) -> PasswordOptions {
    let mut options = PasswordOptions::new_generic_password(service, account);
    if data_protection {
        options.use_protected_keychain();
        options.set_access_synchronized(Some(false));
    }
    options
}

fn keychain_error(status: i32) -> PlatformError {
    match status {
        ERR_SEC_AUTH_FAILED => {
            PlatformError::authentication_required("keychain authentication is required")
        }
        ERR_SEC_INTERACTION_NOT_ALLOWED => {
            PlatformError::locked("keychain is unavailable while the device is locked")
        }
        ERR_SEC_USER_CANCELED => PlatformError::cancelled("keychain access was cancelled"),
        ERR_SEC_MISSING_ENTITLEMENT => {
            PlatformError::unavailable("keychain entitlement is unavailable")
        }
        _ => PlatformError::io(
            format!("keychain operation failed with status {status}"),
            false,
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use std::sync::Mutex;

    #[derive(Default)]
    struct MemoryBackend {
        values: Mutex<BTreeMap<(String, String), Vec<u8>>>,
    }

    impl KeychainBackend for MemoryBackend {
        fn read(&self, service: &str, account: &str) -> Result<Option<Vec<u8>>, PlatformError> {
            Ok(self
                .values
                .lock()
                .unwrap()
                .get(&(service.to_owned(), account.to_owned()))
                .cloned())
        }

        fn write(&self, service: &str, account: &str, value: &[u8]) -> Result<(), PlatformError> {
            self.values
                .lock()
                .unwrap()
                .insert((service.to_owned(), account.to_owned()), value.to_vec());
            Ok(())
        }

        fn delete(&self, service: &str, account: &str) -> Result<(), PlatformError> {
            self.values
                .lock()
                .unwrap()
                .remove(&(service.to_owned(), account.to_owned()));
            Ok(())
        }
    }

    #[test]
    fn store_reads_replaces_and_deletes_values() {
        let store = KeychainSecretStore::with_backend("test", MemoryBackend::default());
        let key = SecretKey::try_new("provider/api-key").expect("key");
        assert!(store.read(&key).expect("read missing").is_none());
        store
            .write(&key, &SecretValue::new(b"first".to_vec()))
            .expect("write");
        assert_eq!(
            store.read(&key).expect("read").expect("value").expose(),
            b"first"
        );
        store
            .write(&key, &SecretValue::new(b"second".to_vec()))
            .expect("replace");
        assert_eq!(
            store.read(&key).expect("read").expect("value").expose(),
            b"second"
        );
        store.delete(&key).expect("delete");
        assert!(store.read(&key).expect("read missing").is_none());
        store.delete(&key).expect("delete missing");
    }

    #[test]
    fn errors_do_not_expose_secret_values() {
        let error = keychain_error(ERR_SEC_AUTH_FAILED);
        assert_eq!(
            error.code(),
            crate::PlatformErrorCode::AuthenticationRequired
        );
        assert!(!error.message().contains("top-secret"));
        let debug = format!("{:?}", SecretValue::new(b"top-secret".to_vec()));
        assert!(!debug.contains("top-secret"));
    }

    #[test]
    #[ignore = "requires a signed macOS host with keychain entitlement"]
    fn real_keychain_round_trip_and_replacement() {
        use std::time::{SystemTime, UNIX_EPOCH};

        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let service = format!("com.wyz.covio.rust.test.{}.{nonce}", std::process::id());
        let store = KeychainSecretStore::new(service);
        let key = SecretKey::try_new("round-trip").expect("key");
        store.delete(&key).expect("delete stale");
        store
            .write(&key, &SecretValue::new(b"first-secret".to_vec()))
            .expect("write");
        assert_eq!(
            store.read(&key).expect("read").expect("value").expose(),
            b"first-secret"
        );
        store
            .write(&key, &SecretValue::new(b"second-secret".to_vec()))
            .expect("replace");
        assert_eq!(
            store.read(&key).expect("read").expect("value").expose(),
            b"second-secret"
        );
        store.delete(&key).expect("delete");
        assert!(store.read(&key).expect("read missing").is_none());
    }
}

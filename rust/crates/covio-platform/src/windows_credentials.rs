//! Windows Credential Manager `SecretStore` adapter.

use crate::{PlatformError, SecretKey, SecretStore, SecretValue};
use std::sync::Mutex;

/// Default service name used by the Covio Windows product.
pub const WINDOWS_SECRET_SERVICE: &str = "Covio.CredentialVault.v1";

/// Maximum generic credential blob accepted by Windows Credential Manager.
pub const WINDOWS_SECRET_BLOB_LIMIT: usize = 5 * 512;

/// Backend operations used by [`CredentialStore`].
pub trait CredentialBackend: Send + Sync {
    /// Reads one backend value.
    fn read(&self, service: &str, account: &str) -> Result<Option<Vec<u8>>, PlatformError>;
    /// Writes or replaces one backend value.
    fn write(&self, service: &str, account: &str, value: &[u8]) -> Result<(), PlatformError>;
    /// Deletes one backend value.
    fn delete(&self, service: &str, account: &str) -> Result<(), PlatformError>;
}

/// Secret store backed by a native credential backend.
///
/// The store never writes secrets to application data or configuration files.
/// Operations are serialized because the Windows Credential Manager does not
/// guarantee correct ordering for concurrent access to one credential.
pub struct CredentialStore<B> {
    service: String,
    backend: B,
    operation_lock: Mutex<()>,
}

impl<B: CredentialBackend> CredentialStore<B> {
    /// Creates a store with an injected backend.
    #[must_use]
    pub fn with_backend(service: impl Into<String>, backend: B) -> Self {
        Self {
            service: service.into(),
            backend,
            operation_lock: Mutex::new(()),
        }
    }

    fn lock(&self) -> Result<std::sync::MutexGuard<'_, ()>, PlatformError> {
        self.operation_lock
            .lock()
            .map_err(|_| PlatformError::io("Windows credential storage lock was poisoned", false))
    }
}

impl<B: CredentialBackend> SecretStore for CredentialStore<B> {
    fn read(&self, key: &SecretKey) -> Result<Option<SecretValue>, PlatformError> {
        let _guard = self.lock()?;
        self.backend
            .read(&self.service, key.as_str())
            .map(|value| value.map(SecretValue::new))
    }

    fn write(&self, key: &SecretKey, value: &SecretValue) -> Result<(), PlatformError> {
        if value.len() > WINDOWS_SECRET_BLOB_LIMIT {
            return Err(PlatformError::invalid_argument(
                "secret exceeds the Windows Credential Manager limit",
            ));
        }
        let _guard = self.lock()?;
        self.backend
            .write(&self.service, key.as_str(), value.expose())
    }

    fn delete(&self, key: &SecretKey) -> Result<(), PlatformError> {
        let _guard = self.lock()?;
        self.backend.delete(&self.service, key.as_str())
    }
}

#[cfg(target_os = "windows")]
#[allow(unsafe_code)]
mod system {
    use super::{
        CredentialBackend, CredentialStore, WINDOWS_SECRET_BLOB_LIMIT, WINDOWS_SECRET_SERVICE,
    };
    use crate::PlatformError;
    use std::ffi::{OsStr, c_void};
    use std::os::windows::ffi::OsStrExt;
    use std::ptr;
    use std::slice;
    use windows_sys::Win32::Foundation::{
        ERROR_INVALID_PARAMETER, ERROR_NO_SUCH_LOGON_SESSION, ERROR_NOT_FOUND, GetLastError,
    };
    use windows_sys::Win32::Security::Credentials::{
        CRED_MAX_GENERIC_TARGET_NAME_LENGTH, CRED_PERSIST_LOCAL_MACHINE, CRED_TYPE_GENERIC,
        CREDENTIALW, CredDeleteW, CredFree, CredReadW, CredWriteW,
    };

    /// Safe wrapper around the Windows Credential Manager backend.
    #[derive(Debug, Clone, Copy, Default)]
    pub struct WindowsCredentialBackend;

    /// Native Windows Credential Manager store.
    pub type WindowsCredentialStore = CredentialStore<WindowsCredentialBackend>;

    impl WindowsCredentialStore {
        /// Creates the product store with the stable Covio service name.
        #[must_use]
        pub fn native() -> Self {
            Self::with_backend(WINDOWS_SECRET_SERVICE, WindowsCredentialBackend)
        }
    }

    impl Default for WindowsCredentialStore {
        fn default() -> Self {
            Self::native()
        }
    }

    impl CredentialBackend for WindowsCredentialBackend {
        fn read(&self, service: &str, account: &str) -> Result<Option<Vec<u8>>, PlatformError> {
            let target = target_name(service, account)?;
            let mut credential = ptr::null_mut();
            let ok = unsafe { CredReadW(target.as_ptr(), CRED_TYPE_GENERIC, 0, &mut credential) };
            if ok == 0 {
                return match windows_error() {
                    ERROR_NOT_FOUND => Ok(None),
                    code => Err(windows_error_to_platform(code)),
                };
            }
            if credential.is_null() {
                return Err(PlatformError::io(
                    "Windows Credential Manager returned an empty result",
                    false,
                ));
            }
            let credential_ref = unsafe { &*credential };
            let result = if credential_ref.Persist != CRED_PERSIST_LOCAL_MACHINE {
                Err(PlatformError::unavailable(
                    "Windows Credential Manager returned a non-local credential",
                ))
            } else {
                let length = usize::try_from(credential_ref.CredentialBlobSize)
                    .map_err(|_| PlatformError::invalid_argument("credential blob is too large"))?;
                if length > WINDOWS_SECRET_BLOB_LIMIT {
                    Err(PlatformError::invalid_argument(
                        "credential blob is too large",
                    ))
                } else if length == 0 {
                    Ok(Some(Vec::new()))
                } else if credential_ref.CredentialBlob.is_null() {
                    Err(PlatformError::io(
                        "Windows Credential Manager returned a null blob",
                        false,
                    ))
                } else {
                    Ok(Some(
                        unsafe { slice::from_raw_parts(credential_ref.CredentialBlob, length) }
                            .to_vec(),
                    ))
                }
            };
            unsafe { CredFree(credential.cast::<c_void>()) };
            result
        }

        fn write(&self, service: &str, account: &str, value: &[u8]) -> Result<(), PlatformError> {
            if value.len() > WINDOWS_SECRET_BLOB_LIMIT {
                return Err(PlatformError::invalid_argument(
                    "secret exceeds the Windows Credential Manager limit",
                ));
            }
            let target = target_name(service, account)?;
            let credential = CREDENTIALW {
                Type: CRED_TYPE_GENERIC,
                TargetName: target.as_ptr().cast_mut(),
                CredentialBlobSize: u32::try_from(value.len())
                    .map_err(|_| PlatformError::invalid_argument("credential blob is too large"))?,
                CredentialBlob: value.as_ptr().cast_mut(),
                Persist: CRED_PERSIST_LOCAL_MACHINE,
                ..CREDENTIALW::default()
            };
            let ok = unsafe { CredWriteW(&credential, 0) };
            if ok == 0 {
                return Err(windows_error_to_platform(windows_error()));
            }
            Ok(())
        }

        fn delete(&self, service: &str, account: &str) -> Result<(), PlatformError> {
            let target = target_name(service, account)?;
            let ok = unsafe { CredDeleteW(target.as_ptr(), CRED_TYPE_GENERIC, 0) };
            if ok == 0 {
                return match windows_error() {
                    ERROR_NOT_FOUND => Ok(()),
                    code => Err(windows_error_to_platform(code)),
                };
            }
            Ok(())
        }
    }

    fn target_name(service: &str, account: &str) -> Result<Vec<u16>, PlatformError> {
        if !service.starts_with(WINDOWS_SECRET_SERVICE) || account.is_empty() {
            return Err(PlatformError::invalid_argument(
                "credential target is outside the Covio namespace",
            ));
        }
        let target = format!("{service}.{account}");
        let wide: Vec<u16> = OsStr::new(&target)
            .encode_wide()
            .chain(std::iter::once(0))
            .collect();
        if wide.len() > usize::try_from(CRED_MAX_GENERIC_TARGET_NAME_LENGTH).unwrap_or(usize::MAX) {
            return Err(PlatformError::invalid_argument(
                "credential target is too long",
            ));
        }
        Ok(wide)
    }

    fn windows_error() -> u32 {
        unsafe { GetLastError() }
    }

    fn windows_error_to_platform(code: u32) -> PlatformError {
        match code {
            ERROR_INVALID_PARAMETER => {
                PlatformError::invalid_argument("Windows Credential Manager rejected the entry")
            }
            ERROR_NO_SUCH_LOGON_SESSION => PlatformError::authentication_required(
                "Windows Credential Manager has no active user session",
            ),
            _ => PlatformError::io(
                format!("Windows Credential Manager operation failed with status {code}"),
                false,
            ),
        }
    }
}

#[cfg(target_os = "windows")]
pub use system::{WindowsCredentialBackend, WindowsCredentialStore};

#[cfg(test)]
mod tests {
    use super::*;
    use crate::PlatformErrorCode;
    use std::collections::BTreeMap;
    use std::sync::Mutex;

    #[derive(Default)]
    struct MemoryBackend {
        values: Mutex<BTreeMap<(String, String), Vec<u8>>>,
    }

    impl CredentialBackend for MemoryBackend {
        fn read(&self, service: &str, account: &str) -> Result<Option<Vec<u8>>, PlatformError> {
            Ok(self
                .values
                .lock()
                .expect("values")
                .get(&(service.to_owned(), account.to_owned()))
                .cloned())
        }

        fn write(&self, service: &str, account: &str, value: &[u8]) -> Result<(), PlatformError> {
            self.values
                .lock()
                .expect("values")
                .insert((service.to_owned(), account.to_owned()), value.to_vec());
            Ok(())
        }

        fn delete(&self, service: &str, account: &str) -> Result<(), PlatformError> {
            self.values
                .lock()
                .expect("values")
                .remove(&(service.to_owned(), account.to_owned()));
            Ok(())
        }
    }

    struct DeniedBackend;

    impl CredentialBackend for DeniedBackend {
        fn read(&self, _service: &str, _account: &str) -> Result<Option<Vec<u8>>, PlatformError> {
            Err(PlatformError::permission_denied(
                "Windows Credential Manager access was denied",
            ))
        }

        fn write(
            &self,
            _service: &str,
            _account: &str,
            _value: &[u8],
        ) -> Result<(), PlatformError> {
            Err(PlatformError::permission_denied(
                "Windows Credential Manager access was denied",
            ))
        }

        fn delete(&self, _service: &str, _account: &str) -> Result<(), PlatformError> {
            Err(PlatformError::permission_denied(
                "Windows Credential Manager access was denied",
            ))
        }
    }

    #[test]
    fn store_reads_replaces_and_deletes_values() {
        let store = CredentialStore::with_backend("test", MemoryBackend::default());
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
    fn credential_errors_use_typed_categories_and_redact_values() {
        let store = CredentialStore::with_backend("test", DeniedBackend);
        let key = SecretKey::try_new("provider/api-key").expect("key");
        let value = SecretValue::new(b"top-secret".to_vec());
        let error = store.write(&key, &value).expect_err("denied");
        assert_eq!(error.code(), PlatformErrorCode::PermissionDenied);
        assert!(!error.message().contains("top-secret"));
        assert!(!format!("{value:?}").contains("top-secret"));
    }

    #[test]
    fn oversized_values_fail_before_the_backend() {
        let store = CredentialStore::with_backend("test", MemoryBackend::default());
        let key = SecretKey::try_new("provider/api-key").expect("key");
        let value = SecretValue::new(vec![7; WINDOWS_SECRET_BLOB_LIMIT + 1]);
        let error = store.write(&key, &value).expect_err("oversized");
        assert_eq!(error.code(), PlatformErrorCode::InvalidArgument);
    }

    #[cfg(target_os = "windows")]
    #[test]
    fn real_credential_manager_round_trip_and_delete() {
        use std::time::{SystemTime, UNIX_EPOCH};

        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let store = WindowsCredentialStore::default();
        let key = SecretKey::try_new(format!("windows-round-trip-{nonce}")).expect("key");
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

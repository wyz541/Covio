//! Encrypted, device-bound credential records.
//!
//! Native secure storage owns only the 32-byte root key. This module owns the
//! encrypted record file, AAD binding, revision checks, rotation, and zeroizing
//! secret access. Product bridges must expose purpose-specific operations, not
//! a generic secret read.

use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use covio_platform::{
    FileStore, PlatformError, PlatformErrorCode, SecretKey, SecretStore, SecretValue,
};
use hkdf::Hkdf;
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use std::collections::BTreeMap;
use std::error::Error;
use std::fmt;
use std::path::{Path, PathBuf};
use zeroize::{Zeroize, ZeroizeOnDrop};

const VAULT_FORMAT_VERSION: u16 = 1;
const VAULT_ALGORITHM: u16 = 1;
const VAULT_FILE: &str = "credential-vault.json";
const APP_ID: &str = "com.wyz.covio";
const ROOT_KEY_PREFIX: &str = "credential/root";
const MAX_CREDENTIAL_ID_BYTES: usize = 160;
const MAX_SECRET_BYTES: usize = 16 * 1024;
const NONCE_BYTES: usize = 24;
const ROOT_KEY_BYTES: usize = 32;

/// Stable credential failure categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum CredentialErrorCode {
    NotFound = 1001,
    AlreadyExists = 1002,
    InvalidArgument = 1003,
    BackendUnavailable = 1004,
    AuthenticationRequired = 1005,
    DeviceLocked = 1006,
    UserCancelled = 1007,
    KeyInvalidated = 1008,
    IntegrityFailed = 1009,
    RecordCorrupt = 1010,
    VersionUnsupported = 1011,
    RecoveryRequired = 1012,
    Internal = 1013,
}

/// A credential failure without secret material.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CredentialError {
    code: CredentialErrorCode,
    message: String,
    retryable: bool,
}

impl CredentialError {
    #[must_use]
    pub fn new(code: CredentialErrorCode, message: impl Into<String>, retryable: bool) -> Self {
        Self {
            code,
            message: message.into(),
            retryable,
        }
    }

    #[must_use]
    pub const fn code(&self) -> CredentialErrorCode {
        self.code
    }

    #[must_use]
    pub fn message(&self) -> &str {
        &self.message
    }

    #[must_use]
    pub const fn retryable(&self) -> bool {
        self.retryable
    }

    pub(crate) fn from_platform(error: PlatformError) -> Self {
        let code = match error.code() {
            PlatformErrorCode::Unavailable => CredentialErrorCode::BackendUnavailable,
            PlatformErrorCode::InvalidArgument => CredentialErrorCode::InvalidArgument,
            PlatformErrorCode::PermissionDenied => CredentialErrorCode::BackendUnavailable,
            PlatformErrorCode::AuthenticationRequired => {
                CredentialErrorCode::AuthenticationRequired
            }
            PlatformErrorCode::Locked => CredentialErrorCode::DeviceLocked,
            PlatformErrorCode::Cancelled => CredentialErrorCode::UserCancelled,
            PlatformErrorCode::KeyInvalidated => CredentialErrorCode::KeyInvalidated,
            PlatformErrorCode::Io => CredentialErrorCode::BackendUnavailable,
        };
        Self::new(code, error.message(), error.retryable())
    }
}

impl fmt::Display for CredentialError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for CredentialError {}

/// A bounded credential record identifier.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct CredentialId(String);

impl CredentialId {
    pub fn try_new(value: impl Into<String>) -> Result<Self, CredentialError> {
        let value = value.into();
        if value.is_empty()
            || value.len() > MAX_CREDENTIAL_ID_BYTES
            || !value.bytes().all(is_credential_id_byte)
        {
            return Err(CredentialError::new(
                CredentialErrorCode::InvalidArgument,
                "credential id is invalid",
                false,
            ));
        }
        Ok(Self(value))
    }

    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

const fn is_credential_id_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b':' | b'/')
}

/// The purpose of one credential record.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecordKind {
    Pairing,
    DeviceIdentity,
    TransportGroupKey,
    ProviderApiKey,
    UpdateSecret,
    AgentToken,
}

impl RecordKind {
    const fn as_str(self) -> &'static str {
        match self {
            Self::Pairing => "pairing",
            Self::DeviceIdentity => "device_identity",
            Self::TransportGroupKey => "transport_group_key",
            Self::ProviderApiKey => "provider_api_key",
            Self::UpdateSecret => "update_secret",
            Self::AgentToken => "agent_token",
        }
    }
}

/// Metadata returned after a record write.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecordMetadata {
    pub record_id: CredentialId,
    pub record_kind: RecordKind,
    pub revision: u64,
    pub key_generation: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct VaultMetadata {
    format_version: u16,
    alg_id: u16,
    vault_id: String,
    device_id: String,
    key_generation: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct EncryptedRecord {
    record_id: String,
    record_kind: RecordKind,
    revision: u64,
    nonce: Vec<u8>,
    ciphertext: Vec<u8>,
    created_at: i64,
    updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct VaultFile {
    metadata: VaultMetadata,
    records: BTreeMap<String, EncryptedRecord>,
}

#[derive(Serialize)]
struct AadV1<'a> {
    app_id: &'a str,
    device_id: &'a str,
    vault_id: &'a str,
    key_generation: u32,
    record_id: &'a str,
    record_kind: &'a str,
    format_version: u16,
    revision: u64,
}

#[derive(Zeroize, ZeroizeOnDrop)]
struct RootKey([u8; ROOT_KEY_BYTES]);

impl RootKey {
    fn generate() -> Result<Self, CredentialError> {
        let mut bytes = [0_u8; ROOT_KEY_BYTES];
        getrandom::getrandom(&mut bytes).map_err(internal_random_error)?;
        Ok(Self(bytes))
    }

    fn from_secret(value: SecretValue) -> Result<Self, CredentialError> {
        if value.expose().len() != ROOT_KEY_BYTES {
            return Err(CredentialError::new(
                CredentialErrorCode::RecoveryRequired,
                "credential root key has an invalid length",
                false,
            ));
        }
        let mut bytes = [0_u8; ROOT_KEY_BYTES];
        bytes.copy_from_slice(value.expose());
        Ok(Self(bytes))
    }

    fn as_bytes(&self) -> &[u8; ROOT_KEY_BYTES] {
        &self.0
    }
}
/// An encrypted credential vault backed by a platform secret store.
pub struct CredentialVault<S, F> {
    root: PathBuf,
    path: PathBuf,
    secrets: S,
    files: F,
    state: VaultFile,
}

impl<S: SecretStore, F: FileStore> CredentialVault<S, F> {
    /// Creates a new vault and stores a fresh root key in native secure storage.
    pub fn create(root: impl Into<PathBuf>, secrets: S, files: F) -> Result<Self, CredentialError> {
        let root = root.into();
        let path = root.join(VAULT_FILE);
        files
            .create_dir_all(&root)
            .map_err(CredentialError::from_platform)?;
        if files
            .read(&path)
            .map_err(CredentialError::from_platform)?
            .is_some()
        {
            return Err(CredentialError::new(
                CredentialErrorCode::AlreadyExists,
                "credential vault already exists",
                false,
            ));
        }
        let metadata = VaultMetadata {
            format_version: VAULT_FORMAT_VERSION,
            alg_id: VAULT_ALGORITHM,
            vault_id: random_hex(16)?,
            device_id: random_hex(16)?,
            key_generation: 1,
        };
        let root_key = RootKey::generate()?;
        let secret_key = root_key_secret_key(&metadata)?;
        let root_value = SecretValue::new(root_key.as_bytes().to_vec());
        if let Err(error) = secrets.write(&secret_key, &root_value) {
            return Err(CredentialError::from_platform(error));
        }
        if let Err(error) = load_root_key(&metadata, &secrets) {
            let _ = secrets.delete(&secret_key);
            return Err(error);
        }
        let state = VaultFile {
            metadata,
            records: BTreeMap::new(),
        };
        if let Err(error) = write_state(&path, &files, &state) {
            let _ = files.remove_file(&path);
            let _ = secrets.delete(&secret_key);
            return Err(error);
        }
        Ok(Self {
            root,
            path,
            secrets,
            files,
            state,
        })
    }

    /// Opens an existing vault or creates it when the vault file is absent.
    ///
    /// This operation does not require `SecretStore: Clone`; platform stores
    /// such as Windows Credential Manager can stay single-owner.
    pub fn open_or_create(
        root: impl Into<PathBuf>,
        secrets: S,
        files: F,
    ) -> Result<Self, CredentialError> {
        let root = root.into();
        let path = root.join(VAULT_FILE);
        files
            .create_dir_all(&root)
            .map_err(CredentialError::from_platform)?;
        if files
            .read(&path)
            .map_err(CredentialError::from_platform)?
            .is_some()
        {
            Self::open(root, secrets, files)
        } else {
            Self::create(root, secrets, files)
        }
    }

    /// Opens an existing vault and verifies its root key is present.
    pub fn open(root: impl Into<PathBuf>, secrets: S, files: F) -> Result<Self, CredentialError> {
        let root = root.into();
        let path = root.join(VAULT_FILE);
        let state = read_state(&path, &files)?;
        let root_key = load_root_key(&state.metadata, &secrets)?;
        drop(root_key);
        Ok(Self {
            root,
            path,
            secrets,
            files,
            state,
        })
    }

    #[must_use]
    pub fn root(&self) -> &Path {
        &self.root
    }

    #[must_use]
    pub const fn key_generation(&self) -> u32 {
        self.state.metadata.key_generation
    }

    /// Stores or replaces one credential record.
    pub fn put(
        &mut self,
        record_id: &CredentialId,
        record_kind: RecordKind,
        value: &SecretValue,
        now_ms: i64,
    ) -> Result<RecordMetadata, CredentialError> {
        if value.len() > MAX_SECRET_BYTES {
            return Err(CredentialError::new(
                CredentialErrorCode::InvalidArgument,
                "credential value exceeds the vault limit",
                false,
            ));
        }
        let previous = self.state.records.get(record_id.as_str()).cloned();
        let revision = previous
            .as_ref()
            .map_or(1, |record| record.revision.saturating_add(1));
        let created_at = previous.as_ref().map_or(now_ms, |record| record.created_at);
        let root_key = load_root_key(&self.state.metadata, &self.secrets)?;
        let nonce = random_bytes(NONCE_BYTES)?;
        let aad = aad_bytes(&self.state.metadata, record_id, record_kind, revision)?;
        let key = derive_record_key(&root_key, &self.state.metadata, record_kind)?;
        let cipher =
            XChaCha20Poly1305::new_from_slice(key.as_ref()).map_err(|_| cipher_init_error())?;
        let ciphertext = cipher
            .encrypt(
                XNonce::from_slice(&nonce),
                Payload {
                    msg: value.expose(),
                    aad: &aad,
                },
            )
            .map_err(|_| {
                CredentialError::new(
                    CredentialErrorCode::Internal,
                    "credential encryption failed",
                    false,
                )
            })?;
        let record = EncryptedRecord {
            record_id: record_id.as_str().to_owned(),
            record_kind,
            revision,
            nonce,
            ciphertext,
            created_at,
            updated_at: now_ms,
        };
        self.state
            .records
            .insert(record_id.as_str().to_owned(), record);
        if let Err(error) = write_state(&self.path, &self.files, &self.state) {
            restore_record(&mut self.state, record_id, previous);
            return Err(error);
        }
        Ok(RecordMetadata {
            record_id: record_id.clone(),
            record_kind,
            revision,
            key_generation: self.state.metadata.key_generation,
        })
    }

    /// Accesses one decrypted credential through a short-lived closure.
    pub fn with_secret<T>(
        &self,
        record_id: &CredentialId,
        operation: impl FnOnce(&SecretValue) -> Result<T, CredentialError>,
    ) -> Result<T, CredentialError> {
        let record = self.state.records.get(record_id.as_str()).ok_or_else(|| {
            CredentialError::new(
                CredentialErrorCode::NotFound,
                "credential record was not found",
                false,
            )
        })?;
        if record.record_id != record_id.as_str() {
            return Err(CredentialError::new(
                CredentialErrorCode::RecordCorrupt,
                "credential record metadata is inconsistent",
                false,
            ));
        }
        validate_nonce(&record.nonce)?;
        let root_key = load_root_key(&self.state.metadata, &self.secrets)?;
        let aad = aad_bytes(
            &self.state.metadata,
            record_id,
            record.record_kind,
            record.revision,
        )?;
        let key = derive_record_key(&root_key, &self.state.metadata, record.record_kind)?;
        let cipher =
            XChaCha20Poly1305::new_from_slice(key.as_ref()).map_err(|_| cipher_init_error())?;
        let plaintext = cipher
            .decrypt(
                XNonce::from_slice(&record.nonce),
                Payload {
                    msg: &record.ciphertext,
                    aad: &aad,
                },
            )
            .map_err(|_| {
                CredentialError::new(
                    CredentialErrorCode::IntegrityFailed,
                    "credential integrity check failed",
                    false,
                )
            })?;
        operation(&SecretValue::new(plaintext))
    }

    #[must_use]
    pub fn exists(&self, record_id: &CredentialId) -> bool {
        self.state.records.contains_key(record_id.as_str())
    }

    /// Deletes one record. A missing record is a successful no-op.
    pub fn delete(&mut self, record_id: &CredentialId) -> Result<(), CredentialError> {
        let previous = self.state.records.remove(record_id.as_str());
        if previous.is_none() {
            return Ok(());
        }
        if let Err(error) = write_state(&self.path, &self.files, &self.state) {
            if let Some(record) = previous {
                self.state
                    .records
                    .insert(record_id.as_str().to_owned(), record);
            }
            return Err(error);
        }
        Ok(())
    }

    /// Rotates the root key and re-encrypts every record.
    pub fn rotate(&mut self, now_ms: i64) -> Result<u32, CredentialError> {
        let old_metadata = self.state.metadata.clone();
        let old_key = load_root_key(&old_metadata, &self.secrets)?;
        let new_generation = old_metadata.key_generation.checked_add(1).ok_or_else(|| {
            CredentialError::new(
                CredentialErrorCode::Internal,
                "credential key generation overflow",
                false,
            )
        })?;
        let new_metadata = VaultMetadata {
            key_generation: new_generation,
            ..old_metadata.clone()
        };
        let new_key = RootKey::generate()?;
        let mut new_state = VaultFile {
            metadata: new_metadata,
            records: BTreeMap::new(),
        };
        for (id, record) in &self.state.records {
            validate_nonce(&record.nonce)?;
            let record_id = CredentialId::try_new(id.clone())?;
            let aad = aad_bytes(
                &old_metadata,
                &record_id,
                record.record_kind,
                record.revision,
            )?;
            let old_record_key = derive_record_key(&old_key, &old_metadata, record.record_kind)?;
            let old_cipher = XChaCha20Poly1305::new_from_slice(old_record_key.as_ref())
                .map_err(|_| cipher_init_error())?;
            let plaintext = old_cipher
                .decrypt(
                    XNonce::from_slice(&record.nonce),
                    Payload {
                        msg: &record.ciphertext,
                        aad: &aad,
                    },
                )
                .map_err(|_| {
                    CredentialError::new(
                        CredentialErrorCode::IntegrityFailed,
                        "credential integrity check failed during rotation",
                        false,
                    )
                })?;
            let revision = record.revision.saturating_add(1);
            let nonce = random_bytes(NONCE_BYTES)?;
            let new_aad = aad_bytes(
                &new_state.metadata,
                &record_id,
                record.record_kind,
                revision,
            )?;
            let new_key_for_record =
                derive_record_key(&new_key, &new_state.metadata, record.record_kind)?;
            let new_cipher = XChaCha20Poly1305::new_from_slice(new_key_for_record.as_ref())
                .map_err(|_| cipher_init_error())?;
            let ciphertext = new_cipher
                .encrypt(
                    XNonce::from_slice(&nonce),
                    Payload {
                        msg: &plaintext,
                        aad: &new_aad,
                    },
                )
                .map_err(|_| {
                    CredentialError::new(
                        CredentialErrorCode::Internal,
                        "credential encryption failed during rotation",
                        false,
                    )
                })?;
            new_state.records.insert(
                id.clone(),
                EncryptedRecord {
                    record_id: id.clone(),
                    record_kind: record.record_kind,
                    revision,
                    nonce,
                    ciphertext,
                    created_at: record.created_at,
                    updated_at: now_ms,
                },
            );
        }
        let new_secret_key = root_key_secret_key(&new_state.metadata)?;
        let new_value = SecretValue::new(new_key.as_bytes().to_vec());
        if let Err(error) = self.secrets.write(&new_secret_key, &new_value) {
            return Err(CredentialError::from_platform(error));
        }
        if let Err(error) = load_root_key(&new_state.metadata, &self.secrets) {
            let _ = self.secrets.delete(&new_secret_key);
            return Err(error);
        }
        if let Err(error) = write_state(&self.path, &self.files, &new_state) {
            let _ = self.secrets.delete(&new_secret_key);
            return Err(error);
        }
        let old_secret_key = root_key_secret_key(&old_metadata)?;
        let _ = self.secrets.delete(&old_secret_key);
        self.state = new_state;
        Ok(new_generation)
    }

    /// Removes the vault and its root key.
    pub fn destroy(self) -> Result<(), CredentialError> {
        let secret_key = root_key_secret_key(&self.state.metadata)?;
        self.files
            .remove_file(&self.path)
            .map_err(CredentialError::from_platform)?;
        self.secrets
            .delete(&secret_key)
            .map_err(CredentialError::from_platform)
    }
}

fn root_key_secret_key(metadata: &VaultMetadata) -> Result<SecretKey, CredentialError> {
    SecretKey::try_new(format!(
        "{ROOT_KEY_PREFIX}/{}/{}/{}",
        metadata.vault_id, metadata.key_generation, metadata.device_id
    ))
    .map_err(CredentialError::from_platform)
}

fn load_root_key<S: SecretStore>(
    metadata: &VaultMetadata,
    secrets: &S,
) -> Result<RootKey, CredentialError> {
    let key = root_key_secret_key(metadata)?;
    let value = secrets
        .read(&key)
        .map_err(CredentialError::from_platform)?
        .ok_or_else(|| {
            CredentialError::new(
                CredentialErrorCode::RecoveryRequired,
                "credential root key is missing",
                false,
            )
        })?;
    RootKey::from_secret(value)
}

fn validate_metadata(metadata: &VaultMetadata) -> Result<(), CredentialError> {
    if metadata.format_version != VAULT_FORMAT_VERSION {
        return Err(CredentialError::new(
            CredentialErrorCode::VersionUnsupported,
            "credential vault format is unsupported",
            false,
        ));
    }
    if metadata.alg_id != VAULT_ALGORITHM
        || metadata.vault_id.is_empty()
        || metadata.device_id.is_empty()
    {
        return Err(CredentialError::new(
            CredentialErrorCode::RecordCorrupt,
            "credential vault metadata is invalid",
            false,
        ));
    }
    Ok(())
}

fn read_state<F: FileStore>(path: &Path, files: &F) -> Result<VaultFile, CredentialError> {
    let bytes = files
        .read(path)
        .map_err(CredentialError::from_platform)?
        .ok_or_else(|| {
            CredentialError::new(
                CredentialErrorCode::NotFound,
                "credential vault file is missing",
                false,
            )
        })?;
    let state: VaultFile = serde_json::from_slice(&bytes).map_err(|_| {
        CredentialError::new(
            CredentialErrorCode::RecordCorrupt,
            "credential vault file is malformed",
            false,
        )
    })?;
    validate_state(&state)?;
    Ok(state)
}

fn validate_state(state: &VaultFile) -> Result<(), CredentialError> {
    validate_metadata(&state.metadata)?;
    for (id, record) in &state.records {
        CredentialId::try_new(id.clone())?;
        if record.record_id != *id || record.nonce.len() != NONCE_BYTES {
            return Err(CredentialError::new(
                CredentialErrorCode::RecordCorrupt,
                "credential record metadata is invalid",
                false,
            ));
        }
    }
    Ok(())
}

fn write_state<F: FileStore>(
    path: &Path,
    files: &F,
    state: &VaultFile,
) -> Result<(), CredentialError> {
    let bytes = serde_json::to_vec(state).map_err(|_| {
        CredentialError::new(
            CredentialErrorCode::Internal,
            "credential vault serialization failed",
            false,
        )
    })?;
    files
        .write_atomic(path, &bytes)
        .map_err(CredentialError::from_platform)
}

fn aad_bytes(
    metadata: &VaultMetadata,
    record_id: &CredentialId,
    record_kind: RecordKind,
    revision: u64,
) -> Result<Vec<u8>, CredentialError> {
    serde_json::to_vec(&AadV1 {
        app_id: APP_ID,
        device_id: &metadata.device_id,
        vault_id: &metadata.vault_id,
        key_generation: metadata.key_generation,
        record_id: record_id.as_str(),
        record_kind: record_kind.as_str(),
        format_version: metadata.format_version,
        revision,
    })
    .map_err(|_| {
        CredentialError::new(
            CredentialErrorCode::Internal,
            "credential AAD serialization failed",
            false,
        )
    })
}

fn derive_record_key(
    root_key: &RootKey,
    metadata: &VaultMetadata,
    record_kind: RecordKind,
) -> Result<zeroize::Zeroizing<[u8; 32]>, CredentialError> {
    let hkdf = Hkdf::<Sha256>::new(Some(metadata.vault_id.as_bytes()), root_key.as_bytes());
    let mut output = zeroize::Zeroizing::new([0_u8; 32]);
    hkdf.expand(record_kind.as_str().as_bytes(), output.as_mut())
        .map_err(|_| {
            CredentialError::new(
                CredentialErrorCode::Internal,
                "credential key derivation failed",
                false,
            )
        })?;
    Ok(output)
}

fn validate_nonce(nonce: &[u8]) -> Result<(), CredentialError> {
    if nonce.len() == NONCE_BYTES {
        Ok(())
    } else {
        Err(CredentialError::new(
            CredentialErrorCode::RecordCorrupt,
            "credential nonce is malformed",
            false,
        ))
    }
}

fn cipher_init_error() -> CredentialError {
    CredentialError::new(
        CredentialErrorCode::Internal,
        "credential cipher initialization failed",
        false,
    )
}

fn restore_record(
    state: &mut VaultFile,
    record_id: &CredentialId,
    previous: Option<EncryptedRecord>,
) {
    match previous {
        Some(record) => {
            state.records.insert(record_id.as_str().to_owned(), record);
        }
        None => {
            state.records.remove(record_id.as_str());
        }
    }
}

fn random_hex(bytes: usize) -> Result<String, CredentialError> {
    let mut value = vec![0_u8; bytes];
    getrandom::getrandom(&mut value).map_err(internal_random_error)?;
    let mut text = String::with_capacity(bytes * 2);
    for byte in &value {
        use std::fmt::Write;
        let _ = write!(text, "{byte:02x}");
    }
    value.zeroize();
    Ok(text)
}

fn random_bytes(bytes: usize) -> Result<Vec<u8>, CredentialError> {
    let mut value = vec![0_u8; bytes];
    getrandom::getrandom(&mut value).map_err(internal_random_error)?;
    Ok(value)
}

fn internal_random_error(_error: getrandom::Error) -> CredentialError {
    CredentialError::new(
        CredentialErrorCode::Internal,
        "credential random generation failed",
        false,
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use std::sync::{Arc, Mutex};

    #[derive(Clone, Default)]
    struct MemorySecrets {
        values: Arc<Mutex<BTreeMap<String, Vec<u8>>>>,
        failure: Arc<Mutex<Option<PlatformErrorCode>>>,
    }

    impl MemorySecrets {
        fn fail(&self, code: PlatformErrorCode) {
            *self.failure.lock().unwrap() = Some(code);
        }

        fn clear_failure(&self) {
            *self.failure.lock().unwrap() = None;
        }

        fn clear_values(&self) {
            self.values.lock().unwrap().clear();
        }
    }

    impl SecretStore for MemorySecrets {
        fn read(&self, key: &SecretKey) -> Result<Option<SecretValue>, PlatformError> {
            if let Some(code) = *self.failure.lock().unwrap() {
                return Err(PlatformError::new(code, "test secret failure", false));
            }
            Ok(self
                .values
                .lock()
                .unwrap()
                .get(key.as_str())
                .cloned()
                .map(SecretValue::new))
        }

        fn write(&self, key: &SecretKey, value: &SecretValue) -> Result<(), PlatformError> {
            if let Some(code) = *self.failure.lock().unwrap() {
                return Err(PlatformError::new(code, "test secret failure", false));
            }
            self.values
                .lock()
                .unwrap()
                .insert(key.as_str().to_owned(), value.expose().to_vec());
            Ok(())
        }

        fn delete(&self, key: &SecretKey) -> Result<(), PlatformError> {
            if let Some(code) = *self.failure.lock().unwrap() {
                return Err(PlatformError::new(code, "test secret failure", false));
            }
            self.values.lock().unwrap().remove(key.as_str());
            Ok(())
        }
    }

    #[derive(Clone, Default)]
    struct MemoryFiles {
        values: Arc<Mutex<BTreeMap<PathBuf, Vec<u8>>>>,
        write_failure: Arc<Mutex<Option<PlatformErrorCode>>>,
    }

    impl MemoryFiles {
        fn replace(&self, path: &Path, value: Vec<u8>) {
            self.values.lock().unwrap().insert(path.to_owned(), value);
        }

        fn fail_write(&self, code: PlatformErrorCode) {
            *self.write_failure.lock().unwrap() = Some(code);
        }
    }

    impl FileStore for MemoryFiles {
        fn read(&self, path: &Path) -> Result<Option<Vec<u8>>, PlatformError> {
            Ok(self.values.lock().unwrap().get(path).cloned())
        }

        fn create_dir_all(&self, _path: &Path) -> Result<(), PlatformError> {
            Ok(())
        }

        fn write_atomic(&self, path: &Path, contents: &[u8]) -> Result<(), PlatformError> {
            if let Some(code) = *self.write_failure.lock().unwrap() {
                return Err(PlatformError::new(code, "test file failure", false));
            }
            self.replace(path, contents.to_vec());
            Ok(())
        }

        fn remove_file(&self, path: &Path) -> Result<bool, PlatformError> {
            Ok(self.values.lock().unwrap().remove(path).is_some())
        }

        fn remove_tree(&self, _path: &Path) -> Result<(), PlatformError> {
            Ok(())
        }
    }

    fn record() -> CredentialId {
        CredentialId::try_new("pairing/peer-1/psk").expect("record id")
    }

    #[test]
    fn stores_reopens_and_deletes_a_record() {
        let secrets = MemorySecrets::default();
        let files = MemoryFiles::default();
        let mut vault = CredentialVault::create("/tmp/covio-test", secrets.clone(), files.clone())
            .expect("create");
        let id = record();
        vault
            .put(
                &id,
                RecordKind::Pairing,
                &SecretValue::new(b"shared-secret".to_vec()),
                100,
            )
            .expect("put");
        drop(vault);

        let reopened = CredentialVault::open("/tmp/covio-test", secrets, files).expect("reopen");
        reopened
            .with_secret(&id, |secret| {
                assert_eq!(secret.expose(), b"shared-secret");
                Ok(())
            })
            .expect("read");
        let mut reopened = reopened;
        reopened.delete(&id).expect("delete");
        assert!(!reopened.exists(&id));
    }

    #[test]
    fn create_failure_removes_the_root_key_and_vault_file() {
        let secrets = MemorySecrets::default();
        let files = MemoryFiles::default();
        files.fail_write(PlatformErrorCode::Io);

        let error = CredentialVault::create("/tmp/covio-test", secrets.clone(), files.clone())
            .map(|_| ())
            .expect_err("create must fail");
        assert_eq!(error.code(), CredentialErrorCode::BackendUnavailable);
        assert!(secrets.values.lock().unwrap().is_empty());
        assert!(
            files
                .read(&Path::new("/tmp/covio-test").join(VAULT_FILE))
                .expect("read vault file")
                .is_none()
        );
    }

    #[test]
    fn missing_root_key_requires_recovery() {
        let secrets = MemorySecrets::default();
        let files = MemoryFiles::default();
        let mut vault =
            CredentialVault::create("/tmp/covio-test", secrets.clone(), files).expect("create");
        let id = record();
        vault
            .put(
                &id,
                RecordKind::Pairing,
                &SecretValue::new(b"secret".to_vec()),
                1,
            )
            .expect("put");
        secrets.clear_values();
        let error = vault
            .with_secret(&id, |_| Ok(()))
            .expect_err("missing root");
        assert_eq!(error.code(), CredentialErrorCode::RecoveryRequired);
    }

    #[test]
    fn locked_and_cancelled_errors_are_typed() {
        let secrets = MemorySecrets::default();
        let files = MemoryFiles::default();
        let mut vault =
            CredentialVault::create("/tmp/covio-test", secrets.clone(), files).expect("create");
        let id = record();
        vault
            .put(
                &id,
                RecordKind::Pairing,
                &SecretValue::new(b"secret".to_vec()),
                1,
            )
            .expect("put");

        secrets.fail(PlatformErrorCode::Locked);
        let error = vault.with_secret(&id, |_| Ok(())).expect_err("locked");
        assert_eq!(error.code(), CredentialErrorCode::DeviceLocked);

        secrets.fail(PlatformErrorCode::Cancelled);
        let error = vault.with_secret(&id, |_| Ok(())).expect_err("cancelled");
        assert_eq!(error.code(), CredentialErrorCode::UserCancelled);
        secrets.clear_failure();
    }

    #[test]
    fn corrupted_ciphertext_is_integrity_failure() {
        let secrets = MemorySecrets::default();
        let files = MemoryFiles::default();
        let mut vault = CredentialVault::create("/tmp/covio-test", secrets.clone(), files.clone())
            .expect("create");
        let id = record();
        vault
            .put(
                &id,
                RecordKind::Pairing,
                &SecretValue::new(b"secret".to_vec()),
                1,
            )
            .expect("put");
        let path = vault.root().join(VAULT_FILE);
        let mut state: serde_json::Value =
            serde_json::from_slice(&files.read(&path).unwrap().expect("vault file")).expect("json");
        state["records"][id.as_str()]["ciphertext"] = serde_json::json!([0]);
        files.replace(&path, serde_json::to_vec(&state).expect("json"));
        let reopened = CredentialVault::open("/tmp/covio-test", secrets, files)
            .expect("reopen corrupted vault");
        let error = reopened
            .with_secret(&id, |_| Ok(()))
            .expect_err("integrity");
        assert_eq!(error.code(), CredentialErrorCode::IntegrityFailed);
    }

    #[test]
    fn rotation_failure_does_not_write_a_new_root_key() {
        let secrets = MemorySecrets::default();
        let files = MemoryFiles::default();
        let mut vault =
            CredentialVault::create("/tmp/covio-test", secrets.clone(), files).expect("create");
        let id = record();
        vault
            .put(
                &id,
                RecordKind::Pairing,
                &SecretValue::new(b"secret".to_vec()),
                1,
            )
            .expect("put");
        vault
            .state
            .records
            .get_mut(id.as_str())
            .expect("record")
            .ciphertext = vec![0];

        let error = vault.rotate(2).expect_err("rotation must fail");
        assert_eq!(error.code(), CredentialErrorCode::IntegrityFailed);
        assert_eq!(vault.key_generation(), 1);
        assert_eq!(secrets.values.lock().unwrap().len(), 1);
    }

    #[test]
    fn rotation_rewrites_records_and_generation() {
        let secrets = MemorySecrets::default();
        let files = MemoryFiles::default();
        let mut vault = CredentialVault::create("/tmp/covio-test", secrets.clone(), files.clone())
            .expect("create");
        let id = record();
        vault
            .put(
                &id,
                RecordKind::TransportGroupKey,
                &SecretValue::new(b"secret".to_vec()),
                1,
            )
            .expect("put");
        let generation = vault.rotate(2).expect("rotate");
        assert_eq!(generation, 2);
        drop(vault);

        let reopened = CredentialVault::open("/tmp/covio-test", secrets, files).expect("reopen");
        assert_eq!(reopened.key_generation(), 2);
        reopened
            .with_secret(&id, |secret| {
                assert_eq!(secret.expose(), b"secret");
                Ok(())
            })
            .expect("read after rotate");
    }
}

//! Device identity, QR pairing, and durable trusted-device records.
//!
//! The private Ed25519 seed stays in the encrypted credential vault. QR
//! offers contain public identity data and an X25519 ephemeral public key.
//! Both users compare a six-digit code derived from the authenticated
//! transcript. The code alone never completes pairing.

use crate::credential::{
    CredentialError, CredentialErrorCode, CredentialId, CredentialVault, RecordKind,
};
use covio_platform::{FileStore, PlatformError, SecretStore, SecretValue};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use hkdf::Hkdf;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::error::Error;
use std::fmt;
use std::path::{Path, PathBuf};
use subtle::ConstantTimeEq;
use x25519_dalek::{PublicKey as X25519PublicKey, StaticSecret};
use zeroize::{Zeroize, Zeroizing};

/// Version of the pairing wire format.
pub const PAIRING_PROTOCOL_VERSION: u16 = 1;
/// Default lifetime of one pairing offer.
pub const PAIRING_OFFER_TTL_MS: i64 = 120_000;
/// Maximum number of trusted devices in one registry.
pub const MAX_PAIRED_DEVICES: usize = 256;
/// Maximum number of retained consumed offer IDs.
pub const MAX_CONSUMED_OFFERS: usize = 4096;
/// Maximum number of retained revoked-device tombstones.
pub const MAX_REVOKED_DEVICES: usize = 4096;

const DEVICE_IDENTITY_RECORD_ID: &str = "device/identity/signing-key";
const DEVICE_IDENTITY_RECORD_VERSION: u16 = 1;
const PAIRING_REGISTRY_VERSION: u16 = 1;
const PAIRING_QR_PREFIX: &str = "covio-pair/1/";
const PAIRING_RESPONSE_PREFIX: &str = "covio-pair-response/1/";
const PAIRING_OFFER_DOMAIN: &[u8] = b"covio-pairing-offer-v1";
const PAIRING_RESPONSE_DOMAIN: &[u8] = b"covio-pairing-response-v1";
const PAIRING_TRANSCRIPT_DOMAIN: &[u8] = b"covio-pairing-transcript-v1";
const PAIRING_CODE_INFO: &[u8] = b"covio pairing confirmation code v1";
const PAIRING_CODE_MODULUS: u64 = 1_000_000;
const CONSUMED_OFFER_RETENTION_MS: i64 = 86_400_000;
const REVOKED_DEVICE_RETENTION_MS: i64 = 2_592_000_000;
const MAX_DISPLAY_NAME_BYTES: usize = 128;
const MAX_CAPABILITIES: usize = 32;
const MAX_CAPABILITY_BYTES: usize = 64;
const MAX_WIRE_PAYLOAD_BYTES: usize = 8192;
const MAX_REGISTRY_BYTES: usize = 2 * 1024 * 1024;

/// Stable pairing failure categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum PairingErrorCode {
    InvalidArgument = 2001,
    IdentityNotFound = 2002,
    ProtocolUnsupported = 2003,
    OfferExpired = 2004,
    OfferInvalidSignature = 2005,
    ResponseInvalidSignature = 2006,
    ResponseMismatch = 2007,
    SelfPairing = 2008,
    ConfirmationMismatch = 2009,
    ReplayDetected = 2010,
    RegistryFull = 2011,
    StorageFailure = 2012,
    RecordCorrupt = 2013,
    CredentialUnavailable = 2014,
    Internal = 2015,
}

/// A pairing failure without the private key or confirmation code.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairingError {
    code: PairingErrorCode,
    message: String,
    retryable: bool,
}

impl PairingError {
    fn new(code: PairingErrorCode, message: impl Into<String>, retryable: bool) -> Self {
        Self {
            code,
            message: message.into(),
            retryable,
        }
    }

    fn invalid(message: impl Into<String>) -> Self {
        Self::new(PairingErrorCode::InvalidArgument, message, false)
    }

    /// Returns the stable error code.
    #[must_use]
    pub const fn code(&self) -> PairingErrorCode {
        self.code
    }

    /// Returns a safe diagnostic message.
    #[must_use]
    pub fn message(&self) -> &str {
        &self.message
    }

    /// Returns whether the caller can retry the operation.
    #[must_use]
    pub const fn retryable(&self) -> bool {
        self.retryable
    }

    fn from_credential(error: CredentialError) -> Self {
        let code = match error.code() {
            CredentialErrorCode::NotFound => PairingErrorCode::IdentityNotFound,
            CredentialErrorCode::InvalidArgument => PairingErrorCode::InvalidArgument,
            CredentialErrorCode::AlreadyExists => PairingErrorCode::Internal,
            CredentialErrorCode::IntegrityFailed | CredentialErrorCode::RecordCorrupt => {
                PairingErrorCode::RecordCorrupt
            }
            CredentialErrorCode::VersionUnsupported => PairingErrorCode::ProtocolUnsupported,
            CredentialErrorCode::BackendUnavailable
            | CredentialErrorCode::AuthenticationRequired
            | CredentialErrorCode::DeviceLocked
            | CredentialErrorCode::UserCancelled
            | CredentialErrorCode::KeyInvalidated
            | CredentialErrorCode::RecoveryRequired => PairingErrorCode::CredentialUnavailable,
            CredentialErrorCode::Internal => PairingErrorCode::Internal,
        };
        Self::new(code, error.message(), error.retryable())
    }

    fn from_platform(error: PlatformError) -> Self {
        Self::new(
            PairingErrorCode::StorageFailure,
            error.message(),
            error.retryable(),
        )
    }
}

impl fmt::Display for PairingError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for PairingError {}

/// Public device identity.
///
/// `device_id` is the full fingerprint of the Ed25519 public key.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DevicePublicIdentity {
    pub device_id: String,
    pub display_name: String,
    pub public_key: String,
}

/// One trusted device record.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairedDevice {
    pub device_id: String,
    pub display_name: String,
    pub public_key: String,
    pub paired_at_ms: i64,
    pub last_seen_ms: i64,
}

/// A short-lived QR pairing offer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairingOffer {
    pub protocol_version: u16,
    pub offer_id: String,
    pub sender_device_id: String,
    pub sender_display_name: String,
    pub sender_public_key: String,
    pub sender_ephemeral_public_key: String,
    pub expires_at_ms: i64,
    pub capabilities: Vec<String>,
    pub signature: String,
}

impl PairingOffer {
    /// Serializes this offer into the QR payload string.
    pub fn to_qr_payload(&self) -> Result<String, PairingError> {
        let json = serde_json::to_string(self).map_err(|_| {
            PairingError::new(
                PairingErrorCode::Internal,
                "pairing offer serialization failed",
                false,
            )
        })?;
        build_payload(PAIRING_QR_PREFIX, &json)
    }

    /// Parses and verifies one QR payload.
    pub fn from_qr_payload(payload: &str) -> Result<Self, PairingError> {
        let offer: Self = parse_payload(PAIRING_QR_PREFIX, payload)?;
        verify_offer(&offer)?;
        Ok(offer)
    }
}

/// A response created by the device that scanned the QR offer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PairingResponse {
    pub protocol_version: u16,
    pub offer_id: String,
    pub responder_device_id: String,
    pub responder_display_name: String,
    pub responder_public_key: String,
    pub responder_ephemeral_public_key: String,
    pub signature: String,
}

impl PairingResponse {
    /// Serializes this response for the transport layer.
    pub fn to_wire_payload(&self) -> Result<String, PairingError> {
        let json = serde_json::to_string(self).map_err(|_| {
            PairingError::new(
                PairingErrorCode::Internal,
                "pairing response serialization failed",
                false,
            )
        })?;
        build_payload(PAIRING_RESPONSE_PREFIX, &json)
    }

    /// Parses one response payload without trusting it.
    pub fn from_wire_payload(payload: &str) -> Result<Self, PairingError> {
        parse_payload(PAIRING_RESPONSE_PREFIX, payload)
    }
}

/// A six-digit confirmation code shown on both devices.
pub struct PairingCode(String);

impl PairingCode {
    fn new(value: u64) -> Self {
        Self(format!("{:06}", value % PAIRING_CODE_MODULUS))
    }

    /// Returns the display value.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }

    fn matches(&self, input: &str) -> bool {
        if input.len() != 6 || !input.bytes().all(|byte| byte.is_ascii_digit()) {
            return false;
        }
        self.0.as_bytes().ct_eq(input.as_bytes()).into()
    }
}

impl fmt::Debug for PairingCode {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("PairingCode(<redacted>)")
    }
}

impl Drop for PairingCode {
    fn drop(&mut self) {
        self.0.zeroize();
    }
}

/// The first side of a pairing session, before a response arrives.
pub struct PairingInitiator<F: FileStore + Clone> {
    offer: PairingOffer,
    local_identity: DevicePublicIdentity,
    local_ephemeral_secret: StaticSecret,
    registry: PairingRegistry<F>,
}

impl<F: FileStore + Clone> PairingInitiator<F> {
    /// Returns the offer encoded in the displayed QR code.
    #[must_use]
    pub fn offer(&self) -> &PairingOffer {
        &self.offer
    }

    /// Verifies a response and derives the confirmation code.
    pub fn complete(
        self,
        response: &PairingResponse,
        now_ms: i64,
    ) -> Result<PairingInitiatorAwaitingConfirmation<F>, PairingError> {
        ensure_not_expired(self.offer.expires_at_ms, now_ms)?;
        if response.offer_id != self.offer.offer_id {
            return Err(PairingError::new(
                PairingErrorCode::ResponseMismatch,
                "pairing response belongs to another offer",
                false,
            ));
        }
        let responder = identity_from_fields(
            &response.responder_device_id,
            &response.responder_display_name,
            &response.responder_public_key,
        )?;
        if responder.device_id == self.local_identity.device_id {
            return Err(PairingError::new(
                PairingErrorCode::SelfPairing,
                "a device cannot pair with itself",
                false,
            ));
        }
        verify_response(&self.offer, response)?;
        let remote_ephemeral = decode_x25519_public_key(&response.responder_ephemeral_public_key)?;
        let shared = self
            .local_ephemeral_secret
            .diffie_hellman(&remote_ephemeral);
        if !shared.was_contributory() {
            return Err(PairingError::new(
                PairingErrorCode::InvalidArgument,
                "pairing produced a non-contributory shared secret",
                false,
            ));
        }
        let code = derive_confirmation_code(&self.offer, response, &shared.to_bytes())?;
        Ok(PairingInitiatorAwaitingConfirmation {
            offer_id: self.offer.offer_id.clone(),
            expires_at_ms: self.offer.expires_at_ms,
            remote_device: paired_device_from_identity(responder, now_ms),
            code,
            registry: self.registry,
        })
    }
}

/// A pairing initiator that is waiting for the user to verify the code.
pub struct PairingInitiatorAwaitingConfirmation<F: FileStore + Clone> {
    offer_id: String,
    expires_at_ms: i64,
    remote_device: PairedDevice,
    code: PairingCode,
    registry: PairingRegistry<F>,
}

impl<F: FileStore + Clone> PairingInitiatorAwaitingConfirmation<F> {
    /// Returns the code that both users must compare.
    #[must_use]
    pub fn code(&self) -> &str {
        self.code.as_str()
    }

    /// Returns the remote device before it is trusted.
    #[must_use]
    pub fn remote_device(&self) -> &PairedDevice {
        &self.remote_device
    }

    /// Commits the pairing result after the user verifies the code.
    pub fn finish(self, confirmation: &str, now_ms: i64) -> Result<(), PairingError> {
        ensure_not_expired(self.expires_at_ms, now_ms)?;
        if !self.code.matches(confirmation) {
            return Err(PairingError::new(
                PairingErrorCode::ConfirmationMismatch,
                "pairing confirmation code does not match",
                false,
            ));
        }
        self.registry.trust_and_consume(
            &self.offer_id,
            self.expires_at_ms,
            self.remote_device,
            now_ms,
        )
    }
}

/// The side that scanned an offer, before the user verifies the code.
pub struct PairingResponder<F: FileStore + Clone> {
    offer: PairingOffer,
    response: PairingResponse,
    remote_device: PairedDevice,
    code: PairingCode,
    registry: PairingRegistry<F>,
}

impl<F: FileStore + Clone> PairingResponder<F> {
    /// Returns the response to send to the offer creator.
    #[must_use]
    pub fn response(&self) -> &PairingResponse {
        &self.response
    }

    /// Returns the code that both users must compare.
    #[must_use]
    pub fn code(&self) -> &str {
        self.code.as_str()
    }

    /// Returns the remote device before it is trusted.
    #[must_use]
    pub fn remote_device(&self) -> &PairedDevice {
        &self.remote_device
    }

    /// Commits the pairing result after the user verifies the code.
    pub fn finish(self, confirmation: &str, now_ms: i64) -> Result<(), PairingError> {
        ensure_not_expired(self.offer.expires_at_ms, now_ms)?;
        if !self.code.matches(confirmation) {
            return Err(PairingError::new(
                PairingErrorCode::ConfirmationMismatch,
                "pairing confirmation code does not match",
                false,
            ));
        }
        self.registry.trust_and_consume(
            &self.offer.offer_id,
            self.offer.expires_at_ms,
            self.remote_device,
            now_ms,
        )
    }
}

/// Durable trusted-device and offer-replay registry.
#[derive(Clone)]
pub struct PairingRegistry<F: FileStore> {
    path: PathBuf,
    files: F,
}

impl<F: FileStore> PairingRegistry<F> {
    /// Creates a registry at one path.
    #[must_use]
    pub fn new(path: impl Into<PathBuf>, files: F) -> Self {
        Self {
            path: path.into(),
            files,
        }
    }

    /// Returns the registry path.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Returns all trusted devices.
    pub fn trusted_devices(&self) -> Result<Vec<PairedDevice>, PairingError> {
        Ok(self.load()?.devices.into_values().collect())
    }

    /// Returns whether a device is currently trusted.
    pub fn is_trusted(&self, device_id: &str) -> Result<bool, PairingError> {
        Ok(self.load()?.devices.contains_key(device_id))
    }

    /// Revokes local trust for one device.
    pub fn revoke(&self, device_id: &str, now_ms: i64) -> Result<(), PairingError> {
        if !is_device_id(device_id) {
            return Err(PairingError::invalid("device id is invalid"));
        }
        let mut state = self.load()?;
        state.devices.remove(device_id);
        prune_revoked_devices(&mut state, now_ms);
        state.revoked_devices.insert(device_id.to_owned(), now_ms);
        self.save(&state)
    }

    fn trust_and_consume(
        &self,
        offer_id: &str,
        expires_at_ms: i64,
        device: PairedDevice,
        now_ms: i64,
    ) -> Result<(), PairingError> {
        ensure_not_expired(expires_at_ms, now_ms)?;
        if decode_fixed::<16>(offer_id).is_none() {
            return Err(PairingError::invalid("pairing offer id is invalid"));
        }
        identity_from_fields(&device.device_id, &device.display_name, &device.public_key)?;
        let mut state = self.load()?;
        prune_consumed_offers(&mut state, now_ms);
        prune_revoked_devices(&mut state, now_ms);
        if state.consumed_offers.contains_key(offer_id) {
            return Err(PairingError::new(
                PairingErrorCode::ReplayDetected,
                "pairing offer was already used",
                false,
            ));
        }
        if !state.devices.contains_key(&device.device_id)
            && state.devices.len() >= MAX_PAIRED_DEVICES
        {
            return Err(PairingError::new(
                PairingErrorCode::RegistryFull,
                "trusted device registry is full",
                false,
            ));
        }
        state.consumed_offers.insert(offer_id.to_owned(), now_ms);
        state.revoked_devices.remove(&device.device_id);
        state.devices.insert(device.device_id.clone(), device);
        validate_registry(&state)?;
        self.save(&state)
    }

    fn load(&self) -> Result<PairingRegistryState, PairingError> {
        if self
            .files
            .metadata_size(&self.path)
            .map_err(PairingError::from_platform)?
            .is_some_and(|size| size > MAX_REGISTRY_BYTES as u64)
        {
            return Err(record_corrupt("pairing registry is too large"));
        }
        let Some(bytes) = self
            .files
            .read(&self.path)
            .map_err(PairingError::from_platform)?
        else {
            return Ok(PairingRegistryState::default());
        };
        if bytes.len() > MAX_REGISTRY_BYTES {
            return Err(record_corrupt("pairing registry is too large"));
        }
        let state: PairingRegistryState = serde_json::from_slice(&bytes).map_err(|_| {
            PairingError::new(
                PairingErrorCode::RecordCorrupt,
                "pairing registry is malformed",
                false,
            )
        })?;
        validate_registry(&state)?;
        Ok(state)
    }

    fn save(&self, state: &PairingRegistryState) -> Result<(), PairingError> {
        let bytes = serde_json::to_vec(state).map_err(|_| {
            PairingError::new(
                PairingErrorCode::Internal,
                "pairing registry serialization failed",
                false,
            )
        })?;
        if bytes.len() > MAX_REGISTRY_BYTES {
            return Err(PairingError::new(
                PairingErrorCode::RegistryFull,
                "pairing registry exceeds its size limit",
                false,
            ));
        }
        self.files
            .write_atomic(&self.path, &bytes)
            .map_err(PairingError::from_platform)
    }
}

#[derive(Debug, Serialize, Deserialize)]
struct PairingRegistryState {
    version: u16,
    devices: BTreeMap<String, PairedDevice>,
    consumed_offers: BTreeMap<String, i64>,
    revoked_devices: BTreeMap<String, i64>,
}

impl Default for PairingRegistryState {
    fn default() -> Self {
        Self {
            version: PAIRING_REGISTRY_VERSION,
            devices: BTreeMap::new(),
            consumed_offers: BTreeMap::new(),
            revoked_devices: BTreeMap::new(),
        }
    }
}

/// Device identity and pairing service backed by one encrypted vault.
pub struct DeviceIdentityService<S: SecretStore, F: FileStore + Clone> {
    vault: CredentialVault<S, F>,
    registry: PairingRegistry<F>,
}

impl<S: SecretStore, F: FileStore + Clone> DeviceIdentityService<S, F> {
    /// Opens an existing vault or creates a new one.
    pub fn open_or_create(
        data_root: impl AsRef<Path>,
        secrets: S,
        files: F,
    ) -> Result<Self, PairingError> {
        let data_root = data_root.as_ref();
        let vault_root = data_root.join("credentials").join("device-identity");
        let vault = CredentialVault::open_or_create(vault_root, secrets, files.clone())
            .map_err(PairingError::from_credential)?;
        let registry_path = data_root.join("pairing").join("registry.json");
        Ok(Self {
            vault,
            registry: PairingRegistry::new(registry_path, files),
        })
    }

    /// Loads the existing device identity.
    pub fn load_identity(&self) -> Result<DevicePublicIdentity, PairingError> {
        let record = read_identity_record(&self.vault)?;
        public_identity_from_record(&record)
    }

    /// Returns the transfer secret to the Rust host composition.
    ///
    /// The value never crosses the UI bridge. The host calls this before it
    /// enters an asynchronous endpoint bind so the credential lock is not held
    /// across an await point.
    pub fn transfer_secret_key(
        &self,
    ) -> Result<iroh::SecretKey, crate::file_transfer::TransferError> {
        let record = read_identity_record(&self.vault).map_err(|error| {
            crate::file_transfer::TransferError::new(
                crate::file_transfer::TransferErrorCode::StorageIoError,
                error.message(),
                error.retryable(),
            )
        })?;
        Ok(iroh::SecretKey::from_bytes(&record.seed))
    }

    /// Binds an iroh endpoint with the same Ed25519 key used for pairing.
    pub async fn bind_transfer_endpoint(
        &self,
    ) -> Result<crate::file_transfer::IrohTransferEndpoint, crate::file_transfer::TransferError>
    {
        crate::file_transfer::IrohTransferEndpoint::bind(self.transfer_secret_key()?).await
    }

    /// Loads the device identity or creates one with a display name.
    pub fn load_or_create_identity(
        &mut self,
        display_name: &str,
        now_ms: i64,
    ) -> Result<DevicePublicIdentity, PairingError> {
        match self.load_identity() {
            Ok(identity) => Ok(identity),
            Err(error) if error.code() == PairingErrorCode::IdentityNotFound => {
                self.create_identity(display_name, now_ms)
            }
            Err(error) => Err(error),
        }
    }

    /// Begins a pairing offer and returns the QR session.
    pub fn begin_pairing(
        &mut self,
        capabilities: &[String],
        now_ms: i64,
    ) -> Result<PairingInitiator<F>, PairingError> {
        let record = read_identity_record(&self.vault)?;
        let identity = public_identity_from_record(&record)?;
        let capabilities = normalize_capabilities(capabilities)?;
        let expires_at_ms = now_ms.checked_add(PAIRING_OFFER_TTL_MS).ok_or_else(|| {
            PairingError::new(
                PairingErrorCode::InvalidArgument,
                "pairing expiry is outside the supported range",
                false,
            )
        })?;
        let mut ephemeral_secret_bytes = random_array::<32>()?;
        let local_ephemeral_secret = StaticSecret::from(ephemeral_secret_bytes);
        ephemeral_secret_bytes.zeroize();
        let local_ephemeral_public = X25519PublicKey::from(&local_ephemeral_secret);
        let mut offer = PairingOffer {
            protocol_version: PAIRING_PROTOCOL_VERSION,
            offer_id: hex_encode(&random_array::<16>()?),
            sender_device_id: identity.device_id.clone(),
            sender_display_name: identity.display_name.clone(),
            sender_public_key: identity.public_key.clone(),
            sender_ephemeral_public_key: hex_encode(local_ephemeral_public.as_bytes()),
            expires_at_ms,
            capabilities,
            signature: String::new(),
        };
        let signing_key = signing_key(&record);
        offer.signature = hex_encode(
            &signing_key
                .sign(&offer_signature_message(&offer))
                .to_bytes(),
        );
        Ok(PairingInitiator {
            offer,
            local_identity: identity,
            local_ephemeral_secret,
            registry: self.registry.clone(),
        })
    }

    /// Accepts a scanned QR offer and creates a response.
    pub fn accept_pairing_offer(
        &mut self,
        offer: &PairingOffer,
        now_ms: i64,
    ) -> Result<PairingResponder<F>, PairingError> {
        verify_offer(offer)?;
        ensure_not_expired(offer.expires_at_ms, now_ms)?;
        let record = read_identity_record(&self.vault)?;
        let identity = public_identity_from_record(&record)?;
        if identity.device_id == offer.sender_device_id {
            return Err(PairingError::new(
                PairingErrorCode::SelfPairing,
                "a device cannot pair with itself",
                false,
            ));
        }
        let remote_ephemeral = decode_x25519_public_key(&offer.sender_ephemeral_public_key)?;
        let mut ephemeral_secret_bytes = random_array::<32>()?;
        let local_ephemeral_secret = StaticSecret::from(ephemeral_secret_bytes);
        ephemeral_secret_bytes.zeroize();
        let local_ephemeral_public = X25519PublicKey::from(&local_ephemeral_secret);
        let shared = local_ephemeral_secret.diffie_hellman(&remote_ephemeral);
        if !shared.was_contributory() {
            return Err(PairingError::new(
                PairingErrorCode::InvalidArgument,
                "pairing produced a non-contributory shared secret",
                false,
            ));
        }
        let mut response = PairingResponse {
            protocol_version: PAIRING_PROTOCOL_VERSION,
            offer_id: offer.offer_id.clone(),
            responder_device_id: identity.device_id.clone(),
            responder_display_name: identity.display_name.clone(),
            responder_public_key: identity.public_key.clone(),
            responder_ephemeral_public_key: hex_encode(local_ephemeral_public.as_bytes()),
            signature: String::new(),
        };
        let signing_key = signing_key(&record);
        response.signature = hex_encode(
            &signing_key
                .sign(&response_signature_message(offer, &response))
                .to_bytes(),
        );
        let code = derive_confirmation_code(offer, &response, &shared.to_bytes())?;
        let remote_device = paired_device_from_identity(identity_from_offer(offer)?, now_ms);
        Ok(PairingResponder {
            offer: offer.clone(),
            response,
            remote_device,
            code,
            registry: self.registry.clone(),
        })
    }

    /// Returns all trusted devices.
    pub fn trusted_devices(&self) -> Result<Vec<PairedDevice>, PairingError> {
        self.registry.trusted_devices()
    }

    /// Returns whether one device is trusted.
    pub fn is_trusted(&self, device_id: &str) -> Result<bool, PairingError> {
        self.registry.is_trusted(device_id)
    }

    /// Revokes local trust for one device.
    pub fn revoke_device(&self, device_id: &str, now_ms: i64) -> Result<(), PairingError> {
        self.registry.revoke(device_id, now_ms)
    }

    fn create_identity(
        &mut self,
        display_name: &str,
        now_ms: i64,
    ) -> Result<DevicePublicIdentity, PairingError> {
        validate_display_name(display_name)?;
        let mut seed = Zeroizing::new(random_array::<32>()?);
        let record = DeviceIdentityRecord {
            display_name: display_name.to_owned(),
            seed: Zeroizing::new(*seed),
        };
        let encoded = Zeroizing::new(encode_identity_record(&record));
        let value = SecretValue::new(encoded.to_vec());
        let record_id = CredentialId::try_new(DEVICE_IDENTITY_RECORD_ID)
            .map_err(PairingError::from_credential)?;
        self.vault
            .put(&record_id, RecordKind::DeviceIdentity, &value, now_ms)
            .map_err(PairingError::from_credential)?;
        seed.zeroize();
        public_identity_from_record(&record)
    }
}

struct DeviceIdentityRecord {
    display_name: String,
    seed: Zeroizing<[u8; 32]>,
}

fn encode_identity_record(record: &DeviceIdentityRecord) -> Vec<u8> {
    let name = record.display_name.as_bytes();
    let mut bytes = Vec::with_capacity(4 + name.len() + 32);
    bytes.extend_from_slice(&DEVICE_IDENTITY_RECORD_VERSION.to_be_bytes());
    bytes.extend_from_slice(&(name.len() as u16).to_be_bytes());
    bytes.extend_from_slice(name);
    bytes.extend_from_slice(record.seed.as_ref());
    bytes
}

fn decode_identity_record(bytes: &[u8]) -> Result<DeviceIdentityRecord, PairingError> {
    if bytes.len() < 4 {
        return Err(record_corrupt("device identity record is truncated"));
    }
    let version = u16::from_be_bytes([bytes[0], bytes[1]]);
    if version != DEVICE_IDENTITY_RECORD_VERSION {
        return Err(PairingError::new(
            PairingErrorCode::ProtocolUnsupported,
            "device identity record version is unsupported",
            false,
        ));
    }
    let name_len = usize::from(u16::from_be_bytes([bytes[2], bytes[3]]));
    if bytes.len() != 4 + name_len + 32 {
        return Err(record_corrupt("device identity record length is invalid"));
    }
    let name = std::str::from_utf8(&bytes[4..4 + name_len])
        .map_err(|_| record_corrupt("device identity name is not UTF-8"))?;
    validate_display_name(name)?;
    let mut seed = [0_u8; 32];
    seed.copy_from_slice(&bytes[4 + name_len..]);
    Ok(DeviceIdentityRecord {
        display_name: name.to_owned(),
        seed: Zeroizing::new(seed),
    })
}

fn read_identity_record<S: SecretStore, F: FileStore>(
    vault: &CredentialVault<S, F>,
) -> Result<DeviceIdentityRecord, PairingError> {
    let record_id =
        CredentialId::try_new(DEVICE_IDENTITY_RECORD_ID).map_err(PairingError::from_credential)?;
    vault
        .with_secret(&record_id, |value| {
            decode_identity_record(value.expose()).map_err(|error| {
                let code = if error.code() == PairingErrorCode::ProtocolUnsupported {
                    CredentialErrorCode::VersionUnsupported
                } else {
                    CredentialErrorCode::RecordCorrupt
                };
                CredentialError::new(code, "device identity record is malformed", false)
            })
        })
        .map_err(PairingError::from_credential)
}

fn signing_key(record: &DeviceIdentityRecord) -> SigningKey {
    SigningKey::from_bytes(&record.seed)
}

fn public_identity_from_record(
    record: &DeviceIdentityRecord,
) -> Result<DevicePublicIdentity, PairingError> {
    let public_key = signing_key(record).verifying_key().to_bytes();
    Ok(DevicePublicIdentity {
        device_id: device_id_for_public_key(&public_key),
        display_name: record.display_name.clone(),
        public_key: hex_encode(&public_key),
    })
}

fn identity_from_offer(offer: &PairingOffer) -> Result<DevicePublicIdentity, PairingError> {
    identity_from_fields(
        &offer.sender_device_id,
        &offer.sender_display_name,
        &offer.sender_public_key,
    )
}

fn identity_from_fields(
    device_id: &str,
    display_name: &str,
    public_key: &str,
) -> Result<DevicePublicIdentity, PairingError> {
    validate_device_id(device_id)?;
    validate_display_name(display_name)?;
    let public_key_bytes = decode_fixed::<32>(public_key)
        .ok_or_else(|| PairingError::invalid("device public key is invalid"))?;
    let expected_id = device_id_for_public_key(&public_key_bytes);
    if device_id != expected_id {
        return Err(PairingError::new(
            PairingErrorCode::InvalidArgument,
            "device id does not match the public key fingerprint",
            false,
        ));
    }
    Ok(DevicePublicIdentity {
        device_id: device_id.to_owned(),
        display_name: display_name.to_owned(),
        public_key: hex_encode(&public_key_bytes),
    })
}

fn paired_device_from_identity(identity: DevicePublicIdentity, now_ms: i64) -> PairedDevice {
    PairedDevice {
        device_id: identity.device_id,
        display_name: identity.display_name,
        public_key: identity.public_key,
        paired_at_ms: now_ms,
        last_seen_ms: now_ms,
    }
}

fn device_id_for_public_key(public_key: &[u8; 32]) -> String {
    let digest = Sha256::digest(public_key);
    format!("sha256:{}", hex_encode(&digest))
}

fn verify_offer(offer: &PairingOffer) -> Result<(), PairingError> {
    if offer.protocol_version != PAIRING_PROTOCOL_VERSION {
        return Err(PairingError::new(
            PairingErrorCode::ProtocolUnsupported,
            "pairing offer protocol version is unsupported",
            false,
        ));
    }
    let identity = identity_from_fields(
        &offer.sender_device_id,
        &offer.sender_display_name,
        &offer.sender_public_key,
    )?;
    decode_fixed::<16>(&offer.offer_id)
        .ok_or_else(|| PairingError::invalid("pairing offer id is invalid"))?;
    decode_x25519_public_key(&offer.sender_ephemeral_public_key)?;
    validate_capabilities(&offer.capabilities)?;
    if offer.capabilities != normalize_capabilities(&offer.capabilities)? {
        return Err(PairingError::invalid(
            "pairing capabilities are not canonical",
        ));
    }
    let signature = decode_fixed::<64>(&offer.signature).ok_or_else(|| {
        PairingError::new(
            PairingErrorCode::OfferInvalidSignature,
            "pairing offer signature is malformed",
            false,
        )
    })?;
    let verifying_key = verify_key(&identity.public_key)?;
    verifying_key
        .verify_strict(
            &offer_signature_message(offer),
            &Signature::from_bytes(&signature),
        )
        .map_err(|_| {
            PairingError::new(
                PairingErrorCode::OfferInvalidSignature,
                "pairing offer signature is invalid",
                false,
            )
        })
}

fn verify_response(offer: &PairingOffer, response: &PairingResponse) -> Result<(), PairingError> {
    if response.protocol_version != PAIRING_PROTOCOL_VERSION {
        return Err(PairingError::new(
            PairingErrorCode::ProtocolUnsupported,
            "pairing response protocol version is unsupported",
            false,
        ));
    }
    let identity = identity_from_fields(
        &response.responder_device_id,
        &response.responder_display_name,
        &response.responder_public_key,
    )?;
    decode_x25519_public_key(&response.responder_ephemeral_public_key)?;
    let signature = decode_fixed::<64>(&response.signature).ok_or_else(|| {
        PairingError::new(
            PairingErrorCode::ResponseInvalidSignature,
            "pairing response signature is malformed",
            false,
        )
    })?;
    let verifying_key = verify_key(&identity.public_key)?;
    verifying_key
        .verify_strict(
            &response_signature_message(offer, response),
            &Signature::from_bytes(&signature),
        )
        .map_err(|_| {
            PairingError::new(
                PairingErrorCode::ResponseInvalidSignature,
                "pairing response signature is invalid",
                false,
            )
        })
}

fn verify_key(public_key: &str) -> Result<VerifyingKey, PairingError> {
    let bytes = decode_fixed::<32>(public_key)
        .ok_or_else(|| PairingError::invalid("device public key is invalid"))?;
    VerifyingKey::from_bytes(&bytes).map_err(|_| {
        PairingError::new(
            PairingErrorCode::InvalidArgument,
            "device public key is invalid",
            false,
        )
    })
}

fn decode_x25519_public_key(value: &str) -> Result<X25519PublicKey, PairingError> {
    let bytes = decode_fixed::<32>(value)
        .ok_or_else(|| PairingError::invalid("X25519 public key is invalid"))?;
    Ok(X25519PublicKey::from(bytes))
}

fn offer_signature_message(offer: &PairingOffer) -> Vec<u8> {
    let mut message = Vec::new();
    append_field(&mut message, PAIRING_OFFER_DOMAIN);
    append_u16(&mut message, offer.protocol_version);
    append_field(&mut message, offer.offer_id.as_bytes());
    append_field(&mut message, offer.sender_device_id.as_bytes());
    append_field(&mut message, offer.sender_display_name.as_bytes());
    append_field(&mut message, offer.sender_public_key.as_bytes());
    append_field(&mut message, offer.sender_ephemeral_public_key.as_bytes());
    append_i64(&mut message, offer.expires_at_ms);
    append_u32(&mut message, offer.capabilities.len() as u32);
    for capability in &offer.capabilities {
        append_field(&mut message, capability.as_bytes());
    }
    message
}

fn response_signature_message(offer: &PairingOffer, response: &PairingResponse) -> Vec<u8> {
    let mut message = Vec::new();
    append_field(&mut message, PAIRING_RESPONSE_DOMAIN);
    append_u16(&mut message, response.protocol_version);
    append_field(&mut message, offer.offer_id.as_bytes());
    append_field(&mut message, response.offer_id.as_bytes());
    append_field(&mut message, response.responder_device_id.as_bytes());
    append_field(&mut message, response.responder_display_name.as_bytes());
    append_field(&mut message, response.responder_public_key.as_bytes());
    append_field(
        &mut message,
        response.responder_ephemeral_public_key.as_bytes(),
    );
    append_field(&mut message, offer.signature.as_bytes());
    message
}

fn derive_confirmation_code(
    offer: &PairingOffer,
    response: &PairingResponse,
    shared_secret: &[u8; 32],
) -> Result<PairingCode, PairingError> {
    let mut transcript = Vec::new();
    append_field(&mut transcript, PAIRING_TRANSCRIPT_DOMAIN);
    append_field(&mut transcript, offer.signature.as_bytes());
    append_field(&mut transcript, response.signature.as_bytes());
    append_field(&mut transcript, offer.offer_id.as_bytes());
    append_field(&mut transcript, offer.sender_public_key.as_bytes());
    append_field(
        &mut transcript,
        offer.sender_ephemeral_public_key.as_bytes(),
    );
    append_field(&mut transcript, response.responder_public_key.as_bytes());
    append_field(
        &mut transcript,
        response.responder_ephemeral_public_key.as_bytes(),
    );
    let transcript_hash = Sha256::digest(&transcript);
    let hkdf = Hkdf::<Sha256>::new(Some(&transcript_hash), shared_secret);
    let mut code_bytes = [0_u8; 8];
    hkdf.expand(PAIRING_CODE_INFO, &mut code_bytes)
        .map_err(|_| {
            PairingError::new(
                PairingErrorCode::Internal,
                "pairing code derivation failed",
                false,
            )
        })?;
    let value = u64::from_be_bytes(code_bytes) % PAIRING_CODE_MODULUS;
    code_bytes.zeroize();
    transcript.zeroize();
    Ok(PairingCode::new(value))
}

fn normalize_capabilities(capabilities: &[String]) -> Result<Vec<String>, PairingError> {
    if capabilities.len() > MAX_CAPABILITIES {
        return Err(PairingError::invalid("too many pairing capabilities"));
    }
    let mut values = BTreeSet::new();
    for capability in capabilities {
        validate_capability(capability)?;
        values.insert(capability.clone());
    }
    Ok(values.into_iter().collect())
}

fn validate_capabilities(capabilities: &[String]) -> Result<(), PairingError> {
    if capabilities.len() > MAX_CAPABILITIES {
        return Err(PairingError::invalid("too many pairing capabilities"));
    }
    for capability in capabilities {
        validate_capability(capability)?;
    }
    Ok(())
}

fn validate_capability(capability: &str) -> Result<(), PairingError> {
    if capability.is_empty()
        || capability.len() > MAX_CAPABILITY_BYTES
        || !capability.bytes().all(|byte| byte.is_ascii_graphic())
    {
        return Err(PairingError::invalid("pairing capability is invalid"));
    }
    Ok(())
}

fn validate_display_name(display_name: &str) -> Result<(), PairingError> {
    if display_name.trim().is_empty()
        || display_name.len() > MAX_DISPLAY_NAME_BYTES
        || display_name.chars().any(char::is_control)
    {
        return Err(PairingError::invalid("device display name is invalid"));
    }
    Ok(())
}

fn validate_device_id(device_id: &str) -> Result<(), PairingError> {
    let Some(hex) = device_id.strip_prefix("sha256:") else {
        return Err(PairingError::invalid("device id prefix is invalid"));
    };
    decode_fixed::<32>(hex)
        .map(|_| ())
        .ok_or_else(|| PairingError::invalid("device id is invalid"))
}

fn is_device_id(device_id: &str) -> bool {
    validate_device_id(device_id).is_ok()
}

fn validate_registry(state: &PairingRegistryState) -> Result<(), PairingError> {
    if state.version != PAIRING_REGISTRY_VERSION {
        return Err(PairingError::new(
            PairingErrorCode::ProtocolUnsupported,
            "pairing registry version is unsupported",
            false,
        ));
    }
    if state.devices.len() > MAX_PAIRED_DEVICES
        || state.consumed_offers.len() > MAX_CONSUMED_OFFERS
        || state.revoked_devices.len() > MAX_REVOKED_DEVICES
    {
        return Err(record_corrupt("pairing registry exceeds its limits"));
    }
    for (device_id, device) in &state.devices {
        if device_id != &device.device_id {
            return Err(record_corrupt("pairing registry device key is invalid"));
        }
        identity_from_fields(&device.device_id, &device.display_name, &device.public_key)?;
    }
    for device_id in state.revoked_devices.keys() {
        validate_device_id(device_id)?;
    }
    for offer_id in state.consumed_offers.keys() {
        if decode_fixed::<16>(offer_id).is_none() {
            return Err(record_corrupt("pairing registry offer id is invalid"));
        }
    }
    Ok(())
}

fn prune_consumed_offers(state: &mut PairingRegistryState, now_ms: i64) {
    state.consumed_offers.retain(|_, consumed_at| {
        now_ms.saturating_sub(*consumed_at) <= CONSUMED_OFFER_RETENTION_MS
    });
    while state.consumed_offers.len() > MAX_CONSUMED_OFFERS {
        if let Some(oldest) = state
            .consumed_offers
            .iter()
            .min_by_key(|(_, consumed_at)| *consumed_at)
            .map(|(offer_id, _)| offer_id.clone())
        {
            state.consumed_offers.remove(&oldest);
        } else {
            break;
        }
    }
}

fn prune_revoked_devices(state: &mut PairingRegistryState, now_ms: i64) {
    state
        .revoked_devices
        .retain(|_, revoked_at| now_ms.saturating_sub(*revoked_at) <= REVOKED_DEVICE_RETENTION_MS);
    while state.revoked_devices.len() > MAX_REVOKED_DEVICES {
        if let Some(oldest) = state
            .revoked_devices
            .iter()
            .min_by_key(|(_, revoked_at)| *revoked_at)
            .map(|(device_id, _)| device_id.clone())
        {
            state.revoked_devices.remove(&oldest);
        } else {
            break;
        }
    }
}

fn ensure_not_expired(expires_at_ms: i64, now_ms: i64) -> Result<(), PairingError> {
    if now_ms > expires_at_ms {
        return Err(PairingError::new(
            PairingErrorCode::OfferExpired,
            "pairing offer has expired",
            false,
        ));
    }
    Ok(())
}

fn build_payload(prefix: &str, json: &str) -> Result<String, PairingError> {
    let payload = format!("{prefix}{json}");
    if payload.len() > MAX_WIRE_PAYLOAD_BYTES {
        return Err(PairingError::invalid("pairing payload is too large"));
    }
    Ok(payload)
}

fn parse_payload<T: for<'de> Deserialize<'de>>(
    prefix: &str,
    payload: &str,
) -> Result<T, PairingError> {
    if payload.len() > MAX_WIRE_PAYLOAD_BYTES || !payload.starts_with(prefix) {
        return Err(PairingError::invalid(
            "pairing payload prefix or size is invalid",
        ));
    }
    serde_json::from_str(&payload[prefix.len()..])
        .map_err(|_| PairingError::invalid("pairing payload is malformed"))
}

fn append_field(buffer: &mut Vec<u8>, value: &[u8]) {
    append_u32(buffer, value.len() as u32);
    buffer.extend_from_slice(value);
}

fn append_u16(buffer: &mut Vec<u8>, value: u16) {
    buffer.extend_from_slice(&value.to_be_bytes());
}

fn append_u32(buffer: &mut Vec<u8>, value: u32) {
    buffer.extend_from_slice(&value.to_be_bytes());
}

fn append_i64(buffer: &mut Vec<u8>, value: i64) {
    buffer.extend_from_slice(&value.to_be_bytes());
}

fn random_array<const N: usize>() -> Result<[u8; N], PairingError> {
    let mut value = [0_u8; N];
    getrandom::getrandom(&mut value).map_err(|_| {
        PairingError::new(
            PairingErrorCode::Internal,
            "pairing random generation failed",
            false,
        )
    })?;
    Ok(value)
}

fn decode_fixed<const N: usize>(value: &str) -> Option<[u8; N]> {
    if value.len() != N * 2 {
        return None;
    }
    let mut bytes = [0_u8; N];
    for (index, byte) in bytes.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&value[index * 2..index * 2 + 2], 16).ok()?;
    }
    Some(bytes)
}

fn hex_encode(value: &[u8]) -> String {
    let mut text = String::with_capacity(value.len() * 2);
    for byte in value {
        use std::fmt::Write;
        let _ = write!(text, "{byte:02x}");
    }
    text
}

fn record_corrupt(message: &str) -> PairingError {
    PairingError::new(PairingErrorCode::RecordCorrupt, message, false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use covio_platform::{FileStore, PlatformError, SecretKey, SecretStore};
    use std::collections::BTreeMap;
    use std::sync::{Arc, Mutex};

    #[derive(Clone, Default)]
    struct MemorySecrets {
        values: Arc<Mutex<BTreeMap<String, Vec<u8>>>>,
    }

    impl SecretStore for MemorySecrets {
        fn read(&self, key: &SecretKey) -> Result<Option<SecretValue>, PlatformError> {
            Ok(self
                .values
                .lock()
                .unwrap()
                .get(key.as_str())
                .cloned()
                .map(SecretValue::new))
        }

        fn write(&self, key: &SecretKey, value: &SecretValue) -> Result<(), PlatformError> {
            self.values
                .lock()
                .unwrap()
                .insert(key.as_str().to_owned(), value.expose().to_vec());
            Ok(())
        }

        fn delete(&self, key: &SecretKey) -> Result<(), PlatformError> {
            self.values.lock().unwrap().remove(key.as_str());
            Ok(())
        }
    }

    #[derive(Clone, Default)]
    struct MemoryFiles {
        values: Arc<Mutex<BTreeMap<PathBuf, Vec<u8>>>>,
    }

    impl FileStore for MemoryFiles {
        fn read(&self, path: &Path) -> Result<Option<Vec<u8>>, PlatformError> {
            Ok(self.values.lock().unwrap().get(path).cloned())
        }

        fn create_dir_all(&self, _path: &Path) -> Result<(), PlatformError> {
            Ok(())
        }

        fn write_atomic(&self, path: &Path, contents: &[u8]) -> Result<(), PlatformError> {
            self.values
                .lock()
                .unwrap()
                .insert(path.to_owned(), contents.to_vec());
            Ok(())
        }

        fn remove_file(&self, path: &Path) -> Result<bool, PlatformError> {
            Ok(self.values.lock().unwrap().remove(path).is_some())
        }

        fn remove_tree(&self, _path: &Path) -> Result<(), PlatformError> {
            Ok(())
        }
    }

    fn service(
        root: &str,
    ) -> (
        DeviceIdentityService<MemorySecrets, MemoryFiles>,
        MemorySecrets,
        MemoryFiles,
    ) {
        let secrets = MemorySecrets::default();
        let files = MemoryFiles::default();
        let service = DeviceIdentityService::open_or_create(root, secrets.clone(), files.clone())
            .expect("service");
        (service, secrets, files)
    }

    fn pair(
        alice: &mut DeviceIdentityService<MemorySecrets, MemoryFiles>,
        bob: &mut DeviceIdentityService<MemorySecrets, MemoryFiles>,
    ) -> (
        PairingInitiatorAwaitingConfirmation<MemoryFiles>,
        PairingResponder<MemoryFiles>,
    ) {
        let alice_identity = alice.load_identity().expect("alice identity");
        let bob_identity = bob.load_identity().expect("bob identity");
        assert_ne!(alice_identity.device_id, bob_identity.device_id);
        let initiator = alice
            .begin_pairing(&["transfer.v1".to_owned()], 1_000)
            .expect("begin");
        let payload = initiator.offer().to_qr_payload().expect("qr payload");
        let offer = PairingOffer::from_qr_payload(&payload).expect("offer");
        let responder = bob.accept_pairing_offer(&offer, 1_001).expect("responder");
        let response = PairingResponse::from_wire_payload(
            &responder
                .response()
                .to_wire_payload()
                .expect("response payload"),
        )
        .expect("response");
        let awaiting = initiator.complete(&response, 1_002).expect("complete");
        assert_eq!(awaiting.code(), responder.code());
        (awaiting, responder)
    }

    #[test]
    fn identity_persists_and_keeps_the_existing_name() {
        let root = "/tmp/covio-device-identity";
        let (mut service, secrets, files) = service(root);
        let first = service
            .load_or_create_identity("Alice", 1)
            .expect("create identity");
        drop(service);

        let mut reopened =
            DeviceIdentityService::open_or_create(root, secrets, files).expect("reopen service");
        let second = reopened
            .load_or_create_identity("Different name", 2)
            .expect("load identity");
        assert_eq!(second, first);
        assert_eq!(second.display_name, "Alice");
        assert!(second.device_id.starts_with("sha256:"));
    }

    #[test]
    fn pairing_persists_on_both_sides_and_produces_the_same_code() {
        let root_a = "/tmp/covio-pair-a";
        let root_b = "/tmp/covio-pair-b";
        let (mut alice, alice_secrets, alice_files) = service(root_a);
        let (mut bob, bob_secrets, bob_files) = service(root_b);
        let alice_identity = alice
            .load_or_create_identity("Alice", 1)
            .expect("alice identity");
        let bob_identity = bob.load_or_create_identity("Bob", 1).expect("bob identity");
        let (initiator, responder) = pair(&mut alice, &mut bob);
        let code = initiator.code().to_owned();
        assert_eq!(code, responder.code());
        initiator.finish(&code, 1_003).expect("finish initiator");
        responder.finish(&code, 1_003).expect("finish responder");

        let alice_devices = alice_files
            .read(&PathBuf::from(root_a).join("pairing/registry.json"))
            .expect("read alice registry");
        assert!(alice_devices.is_some());
        assert!(
            alice
                .trusted_devices()
                .expect("alice devices")
                .iter()
                .any(|device| device.device_id == bob_identity.device_id)
        );
        assert!(
            bob.trusted_devices()
                .expect("bob devices")
                .iter()
                .any(|device| device.device_id == alice_identity.device_id)
        );
        drop(alice);
        drop(bob);

        let reopened = DeviceIdentityService::open_or_create(root_a, alice_secrets, alice_files)
            .expect("reopen alice");
        assert!(
            reopened
                .trusted_devices()
                .expect("reopened devices")
                .iter()
                .any(|device| device.device_id == bob_identity.device_id)
        );
        drop(reopened);
        drop(bob_secrets);
        drop(bob_files);
    }

    #[test]
    fn self_pairing_is_rejected() {
        let (mut alice, _, _) = service("/tmp/covio-self-pair");
        alice.load_or_create_identity("Alice", 1).expect("identity");
        let initiator = alice.begin_pairing(&[], 1_000).expect("begin");
        let payload = initiator.offer().to_qr_payload().expect("payload");
        let offer = PairingOffer::from_qr_payload(&payload).expect("offer");
        let error = alice
            .accept_pairing_offer(&offer, 1_001)
            .map(|_| ())
            .expect_err("self pairing");
        assert_eq!(error.code(), PairingErrorCode::SelfPairing);
    }

    #[test]
    fn response_from_another_offer_is_rejected() {
        let (mut alice, _, _) = service("/tmp/covio-mismatch-a");
        let (mut bob, _, _) = service("/tmp/covio-mismatch-b");
        alice.load_or_create_identity("Alice", 1).expect("alice");
        bob.load_or_create_identity("Bob", 1).expect("bob");
        let first = alice.begin_pairing(&[], 1_000).expect("first offer");
        let second = alice.begin_pairing(&[], 1_000).expect("second offer");
        let second_offer =
            PairingOffer::from_qr_payload(&second.offer().to_qr_payload().expect("second payload"))
                .expect("second offer");
        let responder = bob
            .accept_pairing_offer(&second_offer, 1_001)
            .expect("responder");
        let error = first
            .complete(responder.response(), 1_002)
            .map(|_| ())
            .expect_err("mismatched response");
        assert_eq!(error.code(), PairingErrorCode::ResponseMismatch);
    }

    #[test]
    fn expired_offer_is_rejected() {
        let (mut alice, _, _) = service("/tmp/covio-expired-a");
        let (mut bob, _, _) = service("/tmp/covio-expired-b");
        alice.load_or_create_identity("Alice", 1).expect("alice");
        bob.load_or_create_identity("Bob", 1).expect("bob");
        let initiator = alice.begin_pairing(&[], 1_000).expect("begin");
        let payload = initiator.offer().to_qr_payload().expect("payload");
        let offer = PairingOffer::from_qr_payload(&payload).expect("offer");
        let error = bob
            .accept_pairing_offer(&offer, 1_000 + PAIRING_OFFER_TTL_MS + 1)
            .map(|_| ())
            .expect_err("expired offer");
        assert_eq!(error.code(), PairingErrorCode::OfferExpired);
    }

    #[test]
    fn tampered_offer_and_response_are_rejected() {
        let (mut alice, _, _) = service("/tmp/covio-tamper-a");
        let (mut bob, _, _) = service("/tmp/covio-tamper-b");
        alice.load_or_create_identity("Alice", 1).expect("alice");
        bob.load_or_create_identity("Bob", 1).expect("bob");
        let initiator = alice.begin_pairing(&[], 1_000).expect("begin");
        let payload = initiator.offer().to_qr_payload().expect("payload");
        let mut offer = PairingOffer::from_qr_payload(&payload).expect("offer");
        offer.sender_display_name = "Mallory".to_owned();
        let error = bob
            .accept_pairing_offer(&offer, 1_001)
            .map(|_| ())
            .expect_err("tampered offer");
        assert_eq!(error.code(), PairingErrorCode::OfferInvalidSignature);

        let mut offer = PairingOffer::from_qr_payload(&payload).expect("offer");
        offer.sender_display_name = "Alice".to_owned();
        let responder = bob.accept_pairing_offer(&offer, 1_001).expect("responder");
        let mut response = responder.response().clone();
        response.responder_display_name = "Mallory".to_owned();
        let error = initiator
            .complete(&response, 1_002)
            .map(|_| ())
            .expect_err("tampered response");
        assert_eq!(error.code(), PairingErrorCode::ResponseInvalidSignature);
    }

    #[test]
    fn wrong_confirmation_code_does_not_trust_the_peer() {
        let (mut alice, _, _) = service("/tmp/covio-code-a");
        let (mut bob, _, _) = service("/tmp/covio-code-b");
        alice.load_or_create_identity("Alice", 1).expect("alice");
        bob.load_or_create_identity("Bob", 1).expect("bob");
        let (initiator, responder) = pair(&mut alice, &mut bob);
        let code = initiator.code().to_owned();
        let wrong = if code == "000000" { "000001" } else { "000000" };
        let error = initiator.finish(wrong, 1_003).expect_err("wrong code");
        assert_eq!(error.code(), PairingErrorCode::ConfirmationMismatch);
        assert!(alice.trusted_devices().expect("alice devices").is_empty());
        let error = responder.finish(wrong, 1_003).expect_err("wrong code");
        assert_eq!(error.code(), PairingErrorCode::ConfirmationMismatch);
        assert!(bob.trusted_devices().expect("bob devices").is_empty());
    }

    #[test]
    fn six_digit_code_alone_cannot_create_trust() {
        let (mut alice, _, _) = service("/tmp/covio-code-only-a");
        let (mut bob, _, _) = service("/tmp/covio-code-only-b");
        alice.load_or_create_identity("Alice", 1).expect("alice");
        bob.load_or_create_identity("Bob", 1).expect("bob");
        let initiator = alice.begin_pairing(&[], 1_000).expect("begin");
        assert!(alice.trusted_devices().expect("devices").is_empty());
        let payload = initiator.offer().to_qr_payload().expect("payload");
        let offer = PairingOffer::from_qr_payload(&payload).expect("offer");
        let responder = bob.accept_pairing_offer(&offer, 1_001).expect("responder");
        assert!(bob.trusted_devices().expect("devices").is_empty());
        assert!(responder.code().len() == 6);
    }

    #[test]
    fn consumed_offer_is_rejected_as_replay() {
        let (mut alice, _, _) = service("/tmp/covio-replay-a");
        let (mut bob, _, _) = service("/tmp/covio-replay-b");
        alice.load_or_create_identity("Alice", 1).expect("alice");
        bob.load_or_create_identity("Bob", 1).expect("bob");
        let (initiator, responder) = pair(&mut alice, &mut bob);
        let code = initiator.code().to_owned();
        let offer_id = initiator.offer_id.clone();
        let expires_at_ms = initiator.expires_at_ms;
        let bob_device = initiator.remote_device.clone();
        initiator.finish(&code, 1_003).expect("finish initiator");
        responder.finish(&code, 1_003).expect("finish responder");
        let error = alice
            .registry
            .trust_and_consume(&offer_id, expires_at_ms, bob_device, 1_004)
            .expect_err("replay");
        assert_eq!(error.code(), PairingErrorCode::ReplayDetected);
    }

    #[test]
    fn revocation_survives_registry_reload() {
        let root = "/tmp/covio-revoke-a";
        let (mut alice, secrets, files) = service(root);
        let (mut bob, _, _) = service("/tmp/covio-revoke-b");
        alice.load_or_create_identity("Alice", 1).expect("alice");
        bob.load_or_create_identity("Bob", 1).expect("bob");
        let (initiator, responder) = pair(&mut alice, &mut bob);
        let code = initiator.code().to_owned();
        let bob_id = initiator.remote_device.device_id.clone();
        initiator.finish(&code, 1_003).expect("finish");
        responder.finish(&code, 1_003).expect("finish responder");
        alice.revoke_device(&bob_id, 1_004).expect("revoke");
        assert!(!alice.registry.is_trusted(&bob_id).expect("trust"));
        drop(alice);
        let reopened = DeviceIdentityService::open_or_create(root, secrets, files).expect("reopen");
        assert!(reopened.trusted_devices().expect("devices").is_empty());
    }
}

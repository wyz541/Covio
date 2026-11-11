//! Single-file transfer protocol, durable checkpoints, staging, and iroh transport.
//!
//! The protocol keeps control messages separate from file data. Control messages
//! are length-prefixed CBOR envelopes. File data uses fixed binary headers and
//! chunk frames with BLAKE3 checksums.

mod directory;
mod iroh_transport;
mod receiver;
mod sender;
mod store;

use covio_platform::{FileStore, PlatformError, PlatformErrorCode};
use serde::{Deserialize, Serialize};
use std::error::Error;
use std::fmt;
use std::path::{Component, Path, PathBuf};

pub use directory::{
    CANCELLED_STAGING_RETENTION_MS, DestinationEntry, DestinationEntryKind, DirectoryAcceptResult,
    DirectoryChunkCheckpoint, DirectoryChunkOutcome, DirectoryCompleteOutcome,
    DirectoryConflictAction, DirectoryConflictPlan, DirectoryConflictPolicy, DirectoryEntry,
    DirectoryEntryKind, DirectoryEntryOutcome, DirectoryEntryResume, DirectoryEntryStatus,
    DirectoryManifest, DirectoryMetadata, DirectoryResumePlan, DirectoryRetentionFailure,
    DirectoryRetentionSweep, DirectoryTransferOffer, DirectoryTransferReceiver,
    DirectoryTransferSnapshot, DirectoryTransferSummary, FAILED_STAGING_RETENTION_MS,
    MAX_DIRECTORY_COMPONENT_BYTES, MAX_DIRECTORY_DEPTH, MAX_DIRECTORY_ENTRIES,
    MAX_DIRECTORY_PATH_BYTES, MAX_DIRECTORY_TOTAL_BYTES, PAUSED_STAGING_RETENTION_MS,
    PlannedDirectoryEntry, RetentionDecision, RetentionPlan, RetentionTask,
    TERMINAL_METADATA_RETENTION_MS, TransferRetentionPolicy, is_terminal, path_collision_key,
    plan_directory_conflicts, plan_retention, staging_path_for, validate_component,
    validate_directory_path, validate_retention_policy, verify_directory_resume,
};
pub use iroh_transport::{IrohTransferChannel, IrohTransferEndpoint, endpoint_id_for_public_key};
pub use receiver::{
    ForegroundCheck, ReceiveOutcome, ResumePlan, TransferReceiver, TransferSnapshot,
};
pub use sender::TransferSender;
pub use store::{DirectoryTransferJob, TransferEvent, TransferJob, TransferStore};

/// Version of the Covio single-file transfer protocol.
pub const TRANSFER_PROTOCOL_VERSION: u16 = 1;
/// ALPN used for the iroh transport.
pub const TRANSFER_ALPN: &[u8] = b"covio/transfer/1";
/// Fixed file chunk size.
pub const TRANSFER_CHUNK_SIZE: u32 = 1024 * 1024;
/// Maximum number of unacknowledged bytes read by the sender.
pub const TRANSFER_WINDOW_SIZE: u64 = 8 * 1024 * 1024;
/// Default lifetime of an offer that waits for receiver confirmation.
pub const TRANSFER_OFFER_TTL_MS: i64 = 10 * 60 * 1000;
/// Maximum single-file size in the first protocol version.
pub const MAX_TRANSFER_BYTES: u64 = 10 * 1024 * 1024 * 1024;
/// Maximum encoded control message size.
pub const MAX_CONTROL_MESSAGE_BYTES: usize = 1024 * 1024;

const FILE_STREAM_MAGIC: &[u8; 4] = b"CVFT";
const FILE_STREAM_KIND: u16 = 1;
const MAX_TRANSFER_ID_BYTES: usize = 64;
const FILE_FRAME_HEADER_BYTES: usize = 8 + 4 + 2 + 32;

/// Stable transfer failure categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
#[repr(u32)]
pub enum TransferErrorCode {
    /// The caller supplied invalid input.
    InvalidArgument = 3001,
    /// The peer uses an unsupported protocol version.
    ProtocolVersionUnsupported = 3002,
    /// The receiver offer expired.
    TransferOfferExpired = 3003,
    /// The receiver rejected the offer.
    OfferRejected = 3004,
    /// The file manifest is invalid or changed.
    ManifestInvalid = 3005,
    /// A chunk checksum does not match its payload.
    ChunkHashMismatch = 3006,
    /// The final file checksum does not match the manifest.
    FileHashMismatch = 3007,
    /// The durable checkpoint is invalid.
    ResumeCheckpointInvalid = 3008,
    /// The local storage operation failed.
    StorageIoError = 3009,
    /// No usable network path is available.
    TransportOffline = 3010,
    /// The source file changed after the manifest was created.
    SourceChanged = 3011,
    /// The sender cancelled the transfer.
    CancelledBySender = 3012,
    /// The receiver cancelled the transfer.
    CancelledByReceiver = 3013,
    /// The mobile application moved to the background.
    BackgroundSuspended = 3014,
    /// The final destination already exists.
    TargetExists = 3015,
    /// The trusted peer identity or manifest changed.
    PeerIdentityChanged = 3016,
    /// An uncategorized internal failure occurred.
    Internal = 3017,
    /// A directory entry path is unsafe or unsupported.
    PathInvalid = 3018,
    /// Two directory entry paths collide on a supported platform.
    PathCollision = 3019,
    /// The source contains a symbolic link.
    SymlinkRefused = 3020,
    /// The source contains an unsupported filesystem entry.
    UnsupportedEntryKind = 3021,
}

impl TransferErrorCode {
    /// Returns the stable wire spelling.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::InvalidArgument => "invalid_argument",
            Self::ProtocolVersionUnsupported => "protocol_version_unsupported",
            Self::TransferOfferExpired => "transfer_offer_expired",
            Self::OfferRejected => "offer_rejected",
            Self::ManifestInvalid => "manifest_invalid",
            Self::ChunkHashMismatch => "chunk_hash_mismatch",
            Self::FileHashMismatch => "file_hash_mismatch",
            Self::ResumeCheckpointInvalid => "resume_checkpoint_invalid",
            Self::StorageIoError => "storage_io_error",
            Self::TransportOffline => "transport_offline",
            Self::SourceChanged => "source_changed",
            Self::CancelledBySender => "cancelled_by_sender",
            Self::CancelledByReceiver => "cancelled_by_receiver",
            Self::BackgroundSuspended => "background_suspended",
            Self::TargetExists => "target_exists",
            Self::PeerIdentityChanged => "peer_identity_changed",
            Self::Internal => "internal_error",
            Self::PathInvalid => "path_invalid",
            Self::PathCollision => "path_collision",
            Self::SymlinkRefused => "symlink_refused",
            Self::UnsupportedEntryKind => "unsupported_entry_kind",
        }
    }
}

/// A transfer failure without file contents or secrets.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransferError {
    code: TransferErrorCode,
    message: String,
    retryable: bool,
}

impl TransferError {
    /// Creates a transfer error.
    #[must_use]
    pub fn new(code: TransferErrorCode, message: impl Into<String>, retryable: bool) -> Self {
        Self {
            code,
            message: message.into(),
            retryable,
        }
    }

    /// Creates an invalid-input error.
    #[must_use]
    pub fn invalid(message: impl Into<String>) -> Self {
        Self::new(TransferErrorCode::InvalidArgument, message, false)
    }

    /// Returns the stable error code.
    #[must_use]
    pub const fn code(&self) -> TransferErrorCode {
        self.code
    }

    /// Returns a safe diagnostic message.
    #[must_use]
    pub fn message(&self) -> &str {
        &self.message
    }

    /// Returns whether the operation can be retried.
    #[must_use]
    pub const fn retryable(&self) -> bool {
        self.retryable
    }

    fn storage(message: impl Into<String>, retryable: bool) -> Self {
        Self::new(TransferErrorCode::StorageIoError, message, retryable)
    }

    fn internal(message: impl Into<String>) -> Self {
        Self::new(TransferErrorCode::Internal, message, false)
    }

    fn from_platform(error: PlatformError) -> Self {
        let code = match error.code() {
            PlatformErrorCode::InvalidArgument => TransferErrorCode::InvalidArgument,
            PlatformErrorCode::Cancelled => TransferErrorCode::CancelledByReceiver,
            PlatformErrorCode::PermissionDenied
            | PlatformErrorCode::AuthenticationRequired
            | PlatformErrorCode::Locked
            | PlatformErrorCode::KeyInvalidated
            | PlatformErrorCode::Unavailable
            | PlatformErrorCode::Io => TransferErrorCode::StorageIoError,
        };
        Self::new(code, error.message(), error.retryable())
    }
}

impl fmt::Display for TransferError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for TransferError {}

/// Direction of one transfer job.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferDirection {
    /// Send a local file.
    Send,
    /// Receive a remote file.
    Receive,
}

impl TransferDirection {
    /// Returns the stable database spelling.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Send => "send",
            Self::Receive => "receive",
        }
    }

    fn from_str(value: &str) -> Option<Self> {
        match value {
            "send" => Some(Self::Send),
            "receive" => Some(Self::Receive),
            _ => None,
        }
    }
}

/// Durable task state.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferState {
    /// The offer is waiting for a remote decision.
    OfferWaiting,
    /// The receiver is waiting for a local user decision.
    AwaitingAcceptance,
    /// Data can flow.
    Transferring,
    /// The user paused the task.
    Paused,
    /// A mobile operating system suspended the task.
    BackgroundDeferred,
    /// The transport must reconnect.
    WaitingNetwork,
    /// The receiver is checksumming the staged file.
    Verifying,
    /// The receiver is atomically moving the staged file.
    Committing,
    /// The transfer completed.
    Completed,
    /// The receiver rejected the offer.
    Rejected,
    /// The transfer expired.
    Expired,
    /// The user cancelled the task.
    Cancelled,
    /// The transfer failed.
    Failed,
}

impl TransferState {
    /// Returns the stable database spelling.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::OfferWaiting => "offer_waiting",
            Self::AwaitingAcceptance => "awaiting_acceptance",
            Self::Transferring => "transferring",
            Self::Paused => "paused",
            Self::BackgroundDeferred => "background_deferred",
            Self::WaitingNetwork => "waiting_network",
            Self::Verifying => "verifying",
            Self::Committing => "committing",
            Self::Completed => "completed",
            Self::Rejected => "rejected",
            Self::Expired => "expired",
            Self::Cancelled => "cancelled",
            Self::Failed => "failed",
        }
    }

    fn from_str(value: &str) -> Option<Self> {
        match value {
            "offer_waiting" => Some(Self::OfferWaiting),
            "awaiting_acceptance" => Some(Self::AwaitingAcceptance),
            "transferring" => Some(Self::Transferring),
            "paused" => Some(Self::Paused),
            "background_deferred" => Some(Self::BackgroundDeferred),
            "waiting_network" => Some(Self::WaitingNetwork),
            "verifying" => Some(Self::Verifying),
            "committing" => Some(Self::Committing),
            "completed" => Some(Self::Completed),
            "rejected" => Some(Self::Rejected),
            "expired" => Some(Self::Expired),
            "cancelled" => Some(Self::Cancelled),
            "failed" => Some(Self::Failed),
            _ => None,
        }
    }
}

/// One single-file manifest.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct FileManifest {
    /// Manifest schema version.
    pub manifest_version: u16,
    /// Transfer identifier.
    pub transfer_id: String,
    /// Sender device identifier.
    pub sender_device_id: String,
    /// File name shown to the receiver.
    pub file_name: String,
    /// Exact file size in bytes.
    pub size: u64,
    /// Source modification time in Unix milliseconds.
    pub mtime_ms: i64,
    /// Lowercase BLAKE3 digest of the complete file.
    pub blake3: String,
    /// Fixed chunk size.
    pub chunk_size: u32,
    /// Number of chunks.
    pub total_chunks: u64,
    /// Manifest creation time in Unix milliseconds.
    pub created_at_ms: i64,
    /// Offer expiration time in Unix milliseconds.
    pub expires_at_ms: i64,
}

impl FileManifest {
    /// Creates a manifest for a complete source file.
    pub fn from_source<F: FileStore>(
        files: &F,
        source: &Path,
        transfer_id: impl Into<String>,
        sender_device_id: impl Into<String>,
        now_ms: i64,
        ttl_ms: i64,
    ) -> Result<Self, TransferError> {
        let transfer_id = transfer_id.into();
        validate_identifier("transfer id", &transfer_id)?;
        let sender_device_id = sender_device_id.into();
        if sender_device_id.trim().is_empty() {
            return Err(TransferError::invalid("sender device id is empty"));
        }
        let file_name = source
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or_else(|| TransferError::invalid("source file name is invalid"))?
            .to_owned();
        validate_file_name(&file_name)?;
        let size = files
            .metadata_size(source)
            .map_err(TransferError::from_platform)?
            .ok_or_else(|| {
                TransferError::new(
                    TransferErrorCode::SourceChanged,
                    "source file is missing",
                    true,
                )
            })?;
        if size > MAX_TRANSFER_BYTES {
            return Err(TransferError::invalid(
                "source file exceeds the transfer limit",
            ));
        }
        let mut hasher = blake3::Hasher::new();
        let mut offset = 0_u64;
        while offset < size {
            let length = usize::try_from((size - offset).min(u64::from(TRANSFER_CHUNK_SIZE)))
                .map_err(|_| TransferError::internal("chunk length overflow"))?;
            let bytes = files
                .read_range(source, offset, length)
                .map_err(TransferError::from_platform)?
                .ok_or_else(|| {
                    TransferError::new(
                        TransferErrorCode::SourceChanged,
                        "source file is missing",
                        true,
                    )
                })?;
            if bytes.len() != length {
                return Err(TransferError::new(
                    TransferErrorCode::SourceChanged,
                    "source file changed while creating the manifest",
                    true,
                ));
            }
            hasher.update(&bytes);
            offset = offset
                .checked_add(length as u64)
                .ok_or_else(|| TransferError::internal("source offset overflow"))?;
        }
        let expires_at_ms = now_ms.checked_add(ttl_ms).ok_or_else(|| {
            TransferError::invalid("transfer expiry is outside the supported range")
        })?;
        Ok(Self {
            manifest_version: TRANSFER_PROTOCOL_VERSION,
            transfer_id,
            sender_device_id,
            file_name,
            size,
            mtime_ms: 0,
            blake3: hasher.finalize().to_hex().to_string(),
            chunk_size: TRANSFER_CHUNK_SIZE,
            total_chunks: size.div_ceil(u64::from(TRANSFER_CHUNK_SIZE)),
            created_at_ms: now_ms,
            expires_at_ms,
        })
    }

    /// Validates all manifest constraints.
    pub fn validate(&self) -> Result<(), TransferError> {
        if self.manifest_version != TRANSFER_PROTOCOL_VERSION {
            return Err(TransferError::new(
                TransferErrorCode::ProtocolVersionUnsupported,
                "manifest protocol version is unsupported",
                false,
            ));
        }
        validate_identifier("transfer id", &self.transfer_id)?;
        if self.sender_device_id.trim().is_empty() {
            return Err(TransferError::invalid("sender device id is empty"));
        }
        validate_file_name(&self.file_name)?;
        if self.size > MAX_TRANSFER_BYTES {
            return Err(TransferError::invalid("file exceeds the transfer limit"));
        }
        if self.chunk_size != TRANSFER_CHUNK_SIZE {
            return Err(TransferError::invalid("chunk size is unsupported"));
        }
        let expected_chunks = self.size.div_ceil(u64::from(TRANSFER_CHUNK_SIZE));
        if self.total_chunks != expected_chunks {
            return Err(TransferError::invalid("manifest chunk count is invalid"));
        }
        validate_blake3_hex(&self.blake3)?;
        if self.expires_at_ms <= self.created_at_ms {
            return Err(TransferError::invalid("manifest expiry is invalid"));
        }
        Ok(())
    }

    /// Returns the canonical CBOR manifest digest.
    pub fn digest(&self) -> Result<String, TransferError> {
        self.validate()?;
        let mut encoded = Vec::new();
        ciborium::into_writer(self, &mut encoded)
            .map_err(|_| TransferError::internal("manifest encoding failed"))?;
        Ok(blake3_hex(&encoded))
    }

    /// Encodes the manifest as CBOR.
    pub fn to_cbor(&self) -> Result<Vec<u8>, TransferError> {
        self.validate()?;
        let mut encoded = Vec::new();
        ciborium::into_writer(self, &mut encoded)
            .map_err(|_| TransferError::internal("manifest encoding failed"))?;
        Ok(encoded)
    }

    /// Decodes and validates a CBOR manifest.
    pub fn from_cbor(bytes: &[u8]) -> Result<Self, TransferError> {
        let manifest: Self = ciborium::from_reader(bytes).map_err(|_| {
            TransferError::new(
                TransferErrorCode::ManifestInvalid,
                "manifest decoding failed",
                false,
            )
        })?;
        manifest.validate()?;
        Ok(manifest)
    }
}

/// Receiver-visible file summary.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TransferSummary {
    /// Transfer identifier.
    pub transfer_id: String,
    /// Sending device identifier.
    pub sender_device_id: String,
    /// File name shown to the receiver.
    pub file_name: String,
    /// File size in bytes.
    pub size: u64,
    /// BLAKE3 digest.
    pub blake3: String,
    /// Expiration time in Unix milliseconds.
    pub expires_at_ms: i64,
}

impl From<&FileManifest> for TransferSummary {
    fn from(manifest: &FileManifest) -> Self {
        Self {
            transfer_id: manifest.transfer_id.clone(),
            sender_device_id: manifest.sender_device_id.clone(),
            file_name: manifest.file_name.clone(),
            size: manifest.size,
            blake3: manifest.blake3.clone(),
            expires_at_ms: manifest.expires_at_ms,
        }
    }
}

/// Sender offer sent before any file data.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct FileTransferOffer {
    /// Transfer protocol version.
    pub protocol_version: u16,
    /// Unique offer identifier.
    pub offer_id: String,
    /// Manifest being offered.
    pub manifest: FileManifest,
    /// Canonical manifest digest.
    pub manifest_hash: String,
}

impl FileTransferOffer {
    /// Creates an offer from a validated manifest.
    pub fn new(manifest: FileManifest) -> Result<Self, TransferError> {
        manifest.validate()?;
        let manifest_hash = manifest.digest()?;
        Ok(Self {
            protocol_version: TRANSFER_PROTOCOL_VERSION,
            offer_id: random_hex(16)?,
            manifest,
            manifest_hash,
        })
    }

    /// Validates the offer and its manifest digest.
    pub fn validate(&self) -> Result<(), TransferError> {
        if self.protocol_version != TRANSFER_PROTOCOL_VERSION {
            return Err(TransferError::new(
                TransferErrorCode::ProtocolVersionUnsupported,
                "transfer protocol version is unsupported",
                false,
            ));
        }
        validate_identifier("offer id", &self.offer_id)?;
        self.manifest.validate()?;
        if self.manifest.digest()? != self.manifest_hash {
            return Err(TransferError::new(
                TransferErrorCode::ManifestInvalid,
                "manifest digest does not match the offer",
                false,
            ));
        }
        Ok(())
    }

    /// Returns the receiver-visible summary.
    #[must_use]
    pub fn summary(&self) -> TransferSummary {
        TransferSummary::from(&self.manifest)
    }

    /// Checks whether the offer is still live.
    pub fn ensure_live(&self, now_ms: i64) -> Result<(), TransferError> {
        if now_ms > self.manifest.expires_at_ms {
            return Err(TransferError::new(
                TransferErrorCode::TransferOfferExpired,
                "transfer offer has expired",
                false,
            ));
        }
        Ok(())
    }
}

/// Why a receiver rejected one offer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RejectReason {
    /// The user declined the transfer.
    Declined,
    /// The destination has insufficient space.
    InsufficientSpace,
    /// The receiver cannot write the destination.
    DestinationUnavailable,
}

/// Message sent over the bidirectional control stream.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ControlMessage {
    /// Sender offers a file and asks for the receiver checkpoint.
    Offer {
        /// File offer for this transfer.
        offer: FileTransferOffer,
        /// Sender checkpoint for reconnect.
        resume_from: u64,
    },
    /// Receiver accepts at a durable offset.
    Accept {
        /// Durable receiver offset.
        durable_bytes: u64,
    },
    /// Receiver rejects the offer.
    Reject {
        /// Stable reason.
        reason: RejectReason,
    },
    /// Receiver persisted a new checkpoint.
    Checkpoint {
        /// Durable byte count.
        durable_bytes: u64,
    },
    /// Sender requests the receiver checkpoint after reconnect.
    Resume {
        /// Sender's last known durable offset.
        durable_bytes: u64,
    },
    /// One side cancels the transfer.
    Cancel {
        /// Cancelling side.
        direction: TransferDirection,
    },
    /// Receiver verified the complete file.
    Complete {
        /// Verified file BLAKE3 digest.
        blake3: String,
    },
}

/// Versioned control envelope carried in one CBOR record.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct ControlEnvelope {
    /// Transfer protocol version.
    pub protocol_version: u16,
    /// Monotonic sequence in one transport session.
    pub sequence: u64,
    /// Random nonce for this transport session.
    pub session_nonce: String,
    /// Actual control message.
    pub message: ControlMessage,
}

impl ControlEnvelope {
    /// Creates the first envelope for a fresh transport session.
    pub fn first(message: ControlMessage) -> Result<Self, TransferError> {
        Ok(Self {
            protocol_version: TRANSFER_PROTOCOL_VERSION,
            sequence: 1,
            session_nonce: random_hex(16)?,
            message,
        })
    }

    /// Validates protocol version, sequence, and nonce.
    pub fn validate(&self) -> Result<(), TransferError> {
        if self.protocol_version != TRANSFER_PROTOCOL_VERSION {
            return Err(TransferError::new(
                TransferErrorCode::ProtocolVersionUnsupported,
                "control protocol version is unsupported",
                false,
            ));
        }
        if self.sequence == 0 {
            return Err(TransferError::invalid("control sequence must be positive"));
        }
        validate_identifier("session nonce", &self.session_nonce)?;
        Ok(())
    }
}

/// Encodes one control envelope without its transport length prefix.
pub fn encode_control(envelope: &ControlEnvelope) -> Result<Vec<u8>, TransferError> {
    envelope.validate()?;
    let mut encoded = Vec::new();
    ciborium::into_writer(envelope, &mut encoded)
        .map_err(|_| TransferError::internal("control encoding failed"))?;
    if encoded.len() > MAX_CONTROL_MESSAGE_BYTES {
        return Err(TransferError::invalid(
            "control message exceeds the size limit",
        ));
    }
    Ok(encoded)
}

/// Decodes one control envelope.
pub fn decode_control(bytes: &[u8]) -> Result<ControlEnvelope, TransferError> {
    if bytes.len() > MAX_CONTROL_MESSAGE_BYTES {
        return Err(TransferError::invalid(
            "control message exceeds the size limit",
        ));
    }
    let envelope: ControlEnvelope = ciborium::from_reader(bytes)
        .map_err(|_| TransferError::invalid("control message decoding failed"))?;
    envelope.validate()?;
    Ok(envelope)
}

/// First record on the unidirectional file stream.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileStreamHeader {
    /// Protocol version.
    pub protocol_version: u16,
    /// Transfer identifier.
    pub transfer_id: String,
    /// Exact total file size.
    pub total_size: u64,
    /// Final BLAKE3 digest bytes.
    pub blake3: [u8; 32],
    /// Chunk size.
    pub chunk_size: u32,
}

impl FileStreamHeader {
    /// Creates a header from a manifest.
    pub fn from_manifest(manifest: &FileManifest) -> Result<Self, TransferError> {
        manifest.validate()?;
        Ok(Self {
            protocol_version: TRANSFER_PROTOCOL_VERSION,
            transfer_id: manifest.transfer_id.clone(),
            total_size: manifest.size,
            blake3: decode_blake3(&manifest.blake3)?,
            chunk_size: manifest.chunk_size,
        })
    }

    /// Encodes this header for the file stream.
    pub fn encode(&self) -> Result<Vec<u8>, TransferError> {
        validate_identifier("transfer id", &self.transfer_id)?;
        if self.protocol_version != TRANSFER_PROTOCOL_VERSION {
            return Err(TransferError::new(
                TransferErrorCode::ProtocolVersionUnsupported,
                "file stream protocol version is unsupported",
                false,
            ));
        }
        if self.chunk_size != TRANSFER_CHUNK_SIZE {
            return Err(TransferError::invalid(
                "file stream chunk size is unsupported",
            ));
        }
        let transfer_id = self.transfer_id.as_bytes();
        let transfer_id_len = u8::try_from(transfer_id.len())
            .map_err(|_| TransferError::invalid("transfer id is too long"))?;
        let mut encoded = Vec::with_capacity(4 + 2 + 2 + 8 + 32 + 4 + 1 + transfer_id.len());
        encoded.extend_from_slice(FILE_STREAM_MAGIC);
        encoded.extend_from_slice(&self.protocol_version.to_be_bytes());
        encoded.extend_from_slice(&FILE_STREAM_KIND.to_be_bytes());
        encoded.extend_from_slice(&self.total_size.to_be_bytes());
        encoded.extend_from_slice(&self.blake3);
        encoded.extend_from_slice(&self.chunk_size.to_be_bytes());
        encoded.push(transfer_id_len);
        encoded.extend_from_slice(transfer_id);
        Ok(encoded)
    }

    /// Decodes a file stream header.
    pub fn decode(bytes: &[u8]) -> Result<Self, TransferError> {
        if bytes.len() < 53 || &bytes[..4] != FILE_STREAM_MAGIC {
            return Err(TransferError::invalid("file stream header is invalid"));
        }
        let protocol_version = u16::from_be_bytes([bytes[4], bytes[5]]);
        let kind = u16::from_be_bytes([bytes[6], bytes[7]]);
        if kind != FILE_STREAM_KIND {
            return Err(TransferError::invalid("file stream kind is unsupported"));
        }
        let total_size = u64::from_be_bytes(
            bytes[8..16]
                .try_into()
                .map_err(|_| TransferError::invalid("file size is invalid"))?,
        );
        let blake3 = bytes[16..48]
            .try_into()
            .map_err(|_| TransferError::invalid("file digest is invalid"))?;
        let chunk_size = u32::from_be_bytes(
            bytes[48..52]
                .try_into()
                .map_err(|_| TransferError::invalid("chunk size is invalid"))?,
        );
        let id_len = usize::from(bytes[52]);
        if id_len == 0 || id_len > MAX_TRANSFER_ID_BYTES || bytes.len() != 53 + id_len {
            return Err(TransferError::invalid("file stream transfer id is invalid"));
        }
        let transfer_id = std::str::from_utf8(&bytes[53..])
            .map_err(|_| TransferError::invalid("file stream transfer id is not UTF-8"))?
            .to_owned();
        let header = Self {
            protocol_version,
            transfer_id,
            total_size,
            blake3,
            chunk_size,
        };
        if header.protocol_version != TRANSFER_PROTOCOL_VERSION {
            return Err(TransferError::new(
                TransferErrorCode::ProtocolVersionUnsupported,
                "file stream protocol version is unsupported",
                false,
            ));
        }
        if header.chunk_size != TRANSFER_CHUNK_SIZE {
            return Err(TransferError::invalid(
                "file stream chunk size is unsupported",
            ));
        }
        validate_identifier("transfer id", &header.transfer_id)?;
        if header.total_size > MAX_TRANSFER_BYTES {
            return Err(TransferError::invalid(
                "file stream exceeds the transfer limit",
            ));
        }
        Ok(header)
    }
}

/// One bounded file chunk.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileChunkFrame {
    /// Absolute byte offset.
    pub offset: u64,
    /// Payload length.
    pub length: u32,
    /// Wire flags reserved for future use.
    pub flags: u16,
    /// Lowercase checksum of the payload.
    pub blake3: String,
    /// Chunk payload.
    pub payload: Vec<u8>,
}

impl FileChunkFrame {
    /// Creates a frame and computes its checksum.
    #[must_use]
    pub fn new(offset: u64, payload: Vec<u8>) -> Self {
        let length = u32::try_from(payload.len()).unwrap_or(u32::MAX);
        let blake3 = blake3_hex(&payload);
        Self {
            offset,
            length,
            flags: 0,
            blake3,
            payload,
        }
    }

    /// Checks the declared length and BLAKE3 digest.
    pub fn verify(&self) -> Result<(), TransferError> {
        if self.flags != 0 {
            return Err(TransferError::invalid("chunk flags are unsupported"));
        }
        if self.length == 0
            || self.length > TRANSFER_CHUNK_SIZE
            || usize::try_from(self.length).ok() != Some(self.payload.len())
        {
            return Err(TransferError::invalid("chunk length is invalid"));
        }
        if blake3_hex(&self.payload) != self.blake3 {
            return Err(TransferError::new(
                TransferErrorCode::ChunkHashMismatch,
                "chunk checksum does not match the payload",
                true,
            ));
        }
        Ok(())
    }

    /// Encodes a fixed header followed by the payload.
    pub fn encode(&self) -> Result<Vec<u8>, TransferError> {
        self.verify()?;
        let digest = decode_blake3(&self.blake3)?;
        let mut encoded = Vec::with_capacity(FILE_FRAME_HEADER_BYTES + self.payload.len());
        encoded.extend_from_slice(&self.offset.to_be_bytes());
        encoded.extend_from_slice(&self.length.to_be_bytes());
        encoded.extend_from_slice(&self.flags.to_be_bytes());
        encoded.extend_from_slice(&digest);
        encoded.extend_from_slice(&self.payload);
        Ok(encoded)
    }

    /// Decodes one complete chunk record.
    pub fn decode(bytes: &[u8]) -> Result<Self, TransferError> {
        if bytes.len() < FILE_FRAME_HEADER_BYTES {
            return Err(TransferError::invalid("chunk frame is truncated"));
        }
        let offset = u64::from_be_bytes(
            bytes[..8]
                .try_into()
                .map_err(|_| TransferError::invalid("chunk offset is invalid"))?,
        );
        let length = u32::from_be_bytes(
            bytes[8..12]
                .try_into()
                .map_err(|_| TransferError::invalid("chunk length is invalid"))?,
        );
        let flags = u16::from_be_bytes(
            bytes[12..14]
                .try_into()
                .map_err(|_| TransferError::invalid("chunk flags are invalid"))?,
        );
        let digest: [u8; 32] = bytes[14..46]
            .try_into()
            .map_err(|_| TransferError::invalid("chunk digest is invalid"))?;
        let payload = bytes[46..].to_vec();
        let frame = Self {
            offset,
            length,
            flags,
            blake3: hex_encode(&digest),
            payload,
        };
        frame.verify()?;
        Ok(frame)
    }
}

/// Bounded sender source that reads at most one 8 MiB window before new ACKs.
pub struct SenderSource<F: FileStore> {
    files: F,
    source: PathBuf,
    manifest: FileManifest,
    durable_offset: u64,
    next_offset: u64,
}

impl<F: FileStore> SenderSource<F> {
    /// Creates a sender source and computes the source manifest.
    pub fn open(
        files: F,
        source: PathBuf,
        transfer_id: impl Into<String>,
        sender_device_id: impl Into<String>,
        now_ms: i64,
    ) -> Result<Self, TransferError> {
        let manifest = FileManifest::from_source(
            &files,
            &source,
            transfer_id,
            sender_device_id,
            now_ms,
            TRANSFER_OFFER_TTL_MS,
        )?;
        Ok(Self {
            files,
            source,
            manifest,
            durable_offset: 0,
            next_offset: 0,
        })
    }

    /// Resumes a source from a durable receiver offset.
    pub fn resume(
        files: F,
        source: PathBuf,
        manifest: FileManifest,
        durable_offset: u64,
    ) -> Result<Self, TransferError> {
        manifest.validate()?;
        if durable_offset > manifest.size
            || (!durable_offset.is_multiple_of(u64::from(manifest.chunk_size))
                && durable_offset != manifest.size)
        {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "sender resume offset is invalid",
                false,
            ));
        }
        let current_size = files
            .metadata_size(&source)
            .map_err(TransferError::from_platform)?;
        if current_size != Some(manifest.size) {
            return Err(TransferError::new(
                TransferErrorCode::SourceChanged,
                "source file size changed",
                true,
            ));
        }
        Ok(Self {
            files,
            source,
            manifest,
            durable_offset,
            next_offset: durable_offset,
        })
    }

    /// Returns the source manifest.
    #[must_use]
    pub const fn manifest(&self) -> &FileManifest {
        &self.manifest
    }

    /// Returns the highest acknowledged offset.
    #[must_use]
    pub const fn durable_offset(&self) -> u64 {
        self.durable_offset
    }

    /// Reads all chunks in the next 8 MiB window.
    pub fn read_window(&mut self) -> Result<Vec<FileChunkFrame>, TransferError> {
        let Some(current_size) = self
            .files
            .metadata_size(&self.source)
            .map_err(TransferError::from_platform)?
        else {
            return Err(TransferError::new(
                TransferErrorCode::SourceChanged,
                "source file is missing",
                true,
            ));
        };
        if current_size != self.manifest.size {
            return Err(TransferError::new(
                TransferErrorCode::SourceChanged,
                "source file size changed",
                true,
            ));
        }
        let window_end = self
            .durable_offset
            .saturating_add(TRANSFER_WINDOW_SIZE)
            .min(self.manifest.size);
        let mut frames = Vec::new();
        while self.next_offset < window_end {
            let remaining = self.manifest.size - self.next_offset;
            let expected = usize::try_from(remaining.min(u64::from(TRANSFER_CHUNK_SIZE)))
                .map_err(|_| TransferError::internal("chunk length overflow"))?;
            let payload = self
                .files
                .read_range(&self.source, self.next_offset, expected)
                .map_err(TransferError::from_platform)?
                .ok_or_else(|| {
                    TransferError::new(
                        TransferErrorCode::SourceChanged,
                        "source file is missing",
                        true,
                    )
                })?;
            if payload.len() != expected {
                return Err(TransferError::new(
                    TransferErrorCode::SourceChanged,
                    "source file changed while reading",
                    true,
                ));
            }
            frames.push(FileChunkFrame::new(self.next_offset, payload));
            self.next_offset = self
                .next_offset
                .checked_add(expected as u64)
                .ok_or_else(|| TransferError::internal("source offset overflow"))?;
        }
        Ok(frames)
    }

    /// Advances the durable sender offset after a receiver ACK.
    pub fn acknowledge(&mut self, durable_offset: u64) -> Result<(), TransferError> {
        if durable_offset < self.durable_offset || durable_offset > self.next_offset {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "sender acknowledgement is invalid",
                false,
            ));
        }
        self.durable_offset = durable_offset;
        Ok(())
    }
}

pub(crate) fn validate_file_name(file_name: &str) -> Result<(), TransferError> {
    if file_name.is_empty()
        || file_name.len() > 255
        || file_name.contains('\0')
        || file_name.contains(['/', '\\', ':'])
        || file_name == "."
        || file_name == ".."
    {
        return Err(TransferError::invalid("file name is invalid"));
    }
    let mut components = Path::new(file_name).components();
    if !matches!(components.next(), Some(Component::Normal(_))) || components.next().is_some() {
        return Err(TransferError::invalid(
            "file name must be one relative path component",
        ));
    }
    Ok(())
}

pub(crate) fn validate_identifier(label: &str, value: &str) -> Result<(), TransferError> {
    if value.is_empty()
        || value == "."
        || value == ".."
        || value.len() > MAX_TRANSFER_ID_BYTES
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b':'))
    {
        return Err(TransferError::invalid(format!("{label} is invalid")));
    }
    Ok(())
}

pub(crate) fn random_hex(length: usize) -> Result<String, TransferError> {
    let mut bytes = vec![0_u8; length];
    getrandom::getrandom(&mut bytes)
        .map_err(|_| TransferError::internal("random number generation failed"))?;
    Ok(hex_encode(&bytes))
}

pub(crate) fn blake3_hex(bytes: &[u8]) -> String {
    blake3::hash(bytes).to_hex().to_string()
}

fn validate_blake3_hex(value: &str) -> Result<(), TransferError> {
    decode_blake3(value).map(|_| ())
}

fn decode_blake3(value: &str) -> Result<[u8; 32], TransferError> {
    decode_hex_32(value, "BLAKE3 digest")
}

pub(crate) fn decode_hex_32(value: &str, label: &str) -> Result<[u8; 32], TransferError> {
    if value.len() != 64 {
        return Err(TransferError::invalid(format!("{label} is invalid")));
    }
    let mut bytes = [0_u8; 32];
    for (index, pair) in value.as_bytes().as_chunks::<2>().0.iter().enumerate() {
        let text = std::str::from_utf8(pair)
            .map_err(|_| TransferError::invalid(format!("{label} is invalid")))?;
        bytes[index] = u8::from_str_radix(text, 16)
            .map_err(|_| TransferError::invalid(format!("{label} is invalid")))?;
    }
    Ok(bytes)
}

pub(crate) fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(char::from(HEX[usize::from(byte >> 4)]));
        output.push(char::from(HEX[usize::from(byte & 0x0f)]));
    }
    output
}

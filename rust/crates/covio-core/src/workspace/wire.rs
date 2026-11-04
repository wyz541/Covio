//! Workspace wire envelopes and conversion helpers.

use super::logic::is_valid_entry_id;
use super::models::{WorkspaceAvailability, WorkspaceEntry, WorkspaceKind, normalize_entry_id};
use crate::{CoreError, CoreErrorCode};
use serde::{Deserialize, Serialize};

/// Workspace request and response helpers.
pub struct WorkspaceWire;

impl WorkspaceWire {
    /// List request operation.
    pub const OP_LIST: &'static str = "workspace.list";
    /// Put request operation.
    pub const OP_PUT: &'static str = "workspace.put";
    /// Fetch request operation.
    pub const OP_FETCH: &'static str = "workspace.fetch";
    /// Delete request operation.
    pub const OP_DELETE: &'static str = "workspace.delete";
    /// Stat request operation.
    pub const OP_STAT: &'static str = "workspace.stat";
    /// Chunk request operation.
    pub const OP_CHUNK: &'static str = "transfer.chunk";
    /// Commit request operation.
    pub const OP_COMMIT: &'static str = "transfer.commit";
    /// Cancel request operation.
    pub const OP_CANCEL: &'static str = "transfer.cancel";

    /// Encodes a request with omitted default fields.
    pub fn encode_request(request: &WorkspaceRequest) -> Result<String, CoreError> {
        serde_json::to_string(request).map_err(|_| serialization_error())
    }

    /// Decodes a request.
    pub fn decode_request(text: &str) -> Result<WorkspaceRequest, CoreError> {
        serde_json::from_str(text).map_err(|_| serialization_error())
    }

    /// Encodes a response with omitted default fields.
    pub fn encode_response(response: &WorkspaceResponse) -> Result<String, CoreError> {
        serde_json::to_string(response).map_err(|_| serialization_error())
    }

    /// Decodes a response.
    pub fn decode_response(text: &str) -> Result<WorkspaceResponse, CoreError> {
        serde_json::from_str(text).map_err(|_| serialization_error())
    }

    /// Creates a successful response.
    #[must_use]
    pub fn ok(data: Option<WorkspaceResponseData>) -> WorkspaceResponse {
        WorkspaceResponse {
            ok: true,
            data,
            error_code: None,
            error_message: None,
        }
    }

    /// Creates a failed response.
    #[must_use]
    pub fn failed(error_code: WorkspaceErrorCode, error_message: &str) -> WorkspaceResponse {
        WorkspaceResponse {
            ok: false,
            data: None,
            error_code: Some(error_code.as_wire().to_owned()),
            error_message: Some(error_message.to_owned()),
        }
    }

    /// Converts an entry into request args.
    #[must_use]
    pub fn args_from_entry(entry: &WorkspaceEntry) -> WorkspaceArgs {
        WorkspaceArgs {
            entry_id: Some(entry.entry_id.clone()),
            kind: Some(entry.kind.as_wire().to_owned()),
            display_name: Some(entry.display_name.clone()),
            byte_size: Some(entry.byte_size),
            content_type: Some(entry.content_type.clone()),
            created_at_epoch_millis: Some(entry.created_at_epoch_seconds.saturating_mul(1_000)),
            expires_at_epoch_millis: Some(entry.expires_at_epoch_seconds.saturating_mul(1_000)),
            origin_device_id: Some(entry.origin_device_id.clone()),
            availability: Some(entry.availability.as_wire().to_owned()),
            ..WorkspaceArgs::default()
        }
    }

    /// Converts request args into an entry.
    #[must_use]
    pub fn entry_from_args(args: &WorkspaceArgs) -> WorkspaceEntryParse {
        let id = normalize_entry_id(args.entry_id.as_deref().unwrap_or_default());
        if !is_valid_entry_id(&id) {
            return WorkspaceEntryParse::BadDigest;
        }
        let Some(kind) = WorkspaceKind::from_wire(args.kind.as_deref().unwrap_or_default()) else {
            return WorkspaceEntryParse::BadKind;
        };
        WorkspaceEntryParse::Ok(WorkspaceEntry {
            entry_id: id,
            kind,
            display_name: args.display_name.clone().unwrap_or_default(),
            byte_size: args.byte_size.unwrap_or_default().max(0),
            content_type: args.content_type.clone().unwrap_or_default(),
            created_at_epoch_seconds: args.created_at_epoch_millis.unwrap_or_default().max(0)
                / 1_000,
            origin_device_id: args.origin_device_id.clone().unwrap_or_default(),
            expires_at_epoch_seconds: args.expires_at_epoch_millis.unwrap_or_default().max(0)
                / 1_000,
            availability: WorkspaceAvailability::Local,
            pinned: false,
        })
    }
}

impl WorkspaceKind {
    /// Returns the wire spelling.
    #[must_use]
    pub const fn as_wire(self) -> &'static str {
        match self {
            Self::File => "file",
            Self::Image => "image",
            Self::Audio => "audio",
            Self::Pdf => "pdf",
            Self::Text => "text",
        }
    }

    /// Parses a wire spelling.
    #[must_use]
    pub fn from_wire(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "file" => Some(Self::File),
            "image" => Some(Self::Image),
            "audio" => Some(Self::Audio),
            "pdf" => Some(Self::Pdf),
            "text" => Some(Self::Text),
            _ => None,
        }
    }
}

impl WorkspaceAvailability {
    /// Returns the wire spelling.
    #[must_use]
    pub const fn as_wire(self) -> &'static str {
        match self {
            Self::Local => "local",
            Self::Remote => "remote",
            Self::Fetching => "fetching",
            Self::Evicted => "evicted",
        }
    }
}

/// One workspace request.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceRequest {
    /// Request id.
    pub request_id: String,
    /// Operation name.
    pub op: String,
    /// Operation arguments.
    #[serde(default, skip_serializing_if = "WorkspaceArgs::is_empty")]
    pub args: WorkspaceArgs,
}

/// Arguments shared by workspace operations.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceArgs {
    /// Content id.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entry_id: Option<String>,
    /// Content kind.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    /// Display name.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub display_name: Option<String>,
    /// Content size.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub byte_size: Option<i64>,
    /// MIME type.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_type: Option<String>,
    /// Creation time in milliseconds.
    #[serde(rename = "created_at", skip_serializing_if = "Option::is_none")]
    pub created_at_epoch_millis: Option<i64>,
    /// Expiration time in milliseconds.
    #[serde(rename = "expires_at", skip_serializing_if = "Option::is_none")]
    pub expires_at_epoch_millis: Option<i64>,
    /// Origin device id.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub origin_device_id: Option<String>,
    /// Availability wire value.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub availability: Option<String>,
    /// Transfer task id.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub task_id: Option<String>,
    /// Transfer offset.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
    /// Transfer length.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub length: Option<i64>,
    /// Declared SHA-256.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
    /// List cursor in milliseconds.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub since: Option<i64>,
    /// Result limit.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i32>,
}

impl WorkspaceArgs {
    /// Returns whether all optional fields are absent.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.entry_id.is_none()
            && self.kind.is_none()
            && self.display_name.is_none()
            && self.byte_size.is_none()
            && self.content_type.is_none()
            && self.created_at_epoch_millis.is_none()
            && self.expires_at_epoch_millis.is_none()
            && self.origin_device_id.is_none()
            && self.availability.is_none()
            && self.task_id.is_none()
            && self.offset.is_none()
            && self.length.is_none()
            && self.sha256.is_none()
            && self.since.is_none()
            && self.limit.is_none()
    }
}

/// One workspace response.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceResponse {
    /// Whether the operation succeeded.
    pub ok: bool,
    /// Successful response data.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<WorkspaceResponseData>,
    /// Wire error code.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_code: Option<String>,
    /// Public error message.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_message: Option<String>,
}

/// Successful response data.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct WorkspaceResponseData {
    /// Whether a put was accepted.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub accepted: Option<bool>,
    /// Transfer task id.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub task_id: Option<String>,
    /// Number of received bytes.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub received: Option<i64>,
    /// Listed entries.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entries: Option<Vec<WorkspaceArgs>>,
    /// Total local bytes.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total_bytes: Option<i64>,
    /// Maximum total bytes.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_total_bytes: Option<i64>,
    /// Entry count.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entry_count: Option<i32>,
}

/// Wire error codes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceErrorCode {
    /// The workspace quota would be exceeded.
    QuotaExceeded,
    /// The entry has expired.
    EntryExpired,
    /// The entry does not exist.
    EntryNotFound,
    /// Content is unavailable.
    ContentUnavailable,
    /// The content kind is unsupported.
    UnsupportedKind,
    /// Sharing was denied.
    ShareDenied,
    /// Storage is full.
    StorageFull,
    /// The content digest does not match.
    ChecksumMismatch,
    /// The peer is offline.
    PeerOffline,
    /// Local network access was denied.
    LocalNetworkDenied,
}

impl WorkspaceErrorCode {
    /// Returns the wire spelling.
    #[must_use]
    pub const fn as_wire(self) -> &'static str {
        match self {
            Self::QuotaExceeded => "quota_exceeded",
            Self::EntryExpired => "entry_expired",
            Self::EntryNotFound => "entry_not_found",
            Self::ContentUnavailable => "content_unavailable",
            Self::UnsupportedKind => "unsupported_kind",
            Self::ShareDenied => "share_denied",
            Self::StorageFull => "storage_full",
            Self::ChecksumMismatch => "checksum_mismatch",
            Self::PeerOffline => "peer_offline",
            Self::LocalNetworkDenied => "local_network_denied",
        }
    }

    /// Parses a wire spelling.
    #[must_use]
    pub fn from_wire(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "quota_exceeded" => Some(Self::QuotaExceeded),
            "entry_expired" => Some(Self::EntryExpired),
            "entry_not_found" => Some(Self::EntryNotFound),
            "content_unavailable" => Some(Self::ContentUnavailable),
            "unsupported_kind" => Some(Self::UnsupportedKind),
            "share_denied" => Some(Self::ShareDenied),
            "storage_full" => Some(Self::StorageFull),
            "checksum_mismatch" => Some(Self::ChecksumMismatch),
            "peer_offline" => Some(Self::PeerOffline),
            "local_network_denied" => Some(Self::LocalNetworkDenied),
            _ => None,
        }
    }
}

/// Parsed workspace entry result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WorkspaceEntryParse {
    /// Valid entry.
    Ok(WorkspaceEntry),
    /// Invalid digest.
    BadDigest,
    /// Unsupported kind.
    BadKind,
}

fn serialization_error() -> CoreError {
    CoreError::new(
        CoreErrorCode::Internal,
        "workspace wire serialization failed",
    )
}

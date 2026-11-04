//! Workspace models and persisted state.

use serde::{Deserialize, Serialize};

/// Workspace content kind.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum WorkspaceKind {
    /// Generic file.
    #[default]
    File,
    /// Image.
    Image,
    /// Audio.
    Audio,
    /// PDF.
    Pdf,
    /// Text.
    Text,
}

/// Availability of workspace content on this device.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum WorkspaceAvailability {
    /// Full content is local.
    #[default]
    Local,
    /// Only the index is local.
    Remote,
    /// Content is being fetched.
    Fetching,
    /// Content was evicted.
    Evicted,
}

/// One workspace entry.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct WorkspaceEntry {
    /// SHA-256 content id.
    pub entry_id: String,
    /// Content kind.
    pub kind: WorkspaceKind,
    /// Display name without directory components.
    pub display_name: String,
    /// Content size.
    pub byte_size: i64,
    /// MIME type.
    pub content_type: String,
    /// Creation time in Unix seconds.
    pub created_at_epoch_seconds: i64,
    /// Origin device id.
    pub origin_device_id: String,
    /// Expiration time in Unix seconds. Zero means no expiration.
    pub expires_at_epoch_seconds: i64,
    /// Local content availability.
    pub availability: WorkspaceAvailability,
    /// Whether the item is pinned locally.
    pub pinned: bool,
}

impl WorkspaceEntry {
    /// Returns a normalized copy.
    #[must_use]
    pub fn normalized(&self) -> Self {
        Self {
            entry_id: normalize_entry_id(&self.entry_id),
            kind: self.kind,
            display_name: normalize_display_name(&self.display_name),
            byte_size: self.byte_size.max(0),
            content_type: self.content_type.trim().to_ascii_lowercase(),
            created_at_epoch_seconds: self.created_at_epoch_seconds.max(0),
            origin_device_id: self.origin_device_id.trim().to_owned(),
            expires_at_epoch_seconds: self.expires_at_epoch_seconds.max(0),
            availability: self.availability,
            pinned: self.pinned,
        }
    }

    /// Returns bytes occupied on this device.
    #[must_use]
    pub fn local_bytes(&self) -> i64 {
        match self.availability {
            WorkspaceAvailability::Local | WorkspaceAvailability::Fetching => self.byte_size,
            WorkspaceAvailability::Remote | WorkspaceAvailability::Evicted => 0,
        }
    }
}

/// Workspace retention policy.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct WorkspacePolicy {
    /// Maximum total local bytes.
    pub max_total_bytes: i64,
    /// Maximum bytes per entry.
    pub max_entry_bytes: i64,
    /// Retention days. Zero means no expiration.
    pub retention_days: i32,
    /// Contents above this size are stored as remote index entries.
    pub lazy_fetch_threshold_bytes: i64,
}

impl Default for WorkspacePolicy {
    fn default() -> Self {
        Self {
            max_total_bytes: 5 * 1024 * 1024 * 1024,
            max_entry_bytes: 2 * 1024 * 1024 * 1024,
            retention_days: 30,
            lazy_fetch_threshold_bytes: 50 * 1024 * 1024,
        }
    }
}

impl WorkspacePolicy {
    /// Returns a normalized copy.
    #[must_use]
    pub fn normalized(&self) -> Self {
        let total = self.max_total_bytes.max(0);
        Self {
            max_total_bytes: total,
            max_entry_bytes: self.max_entry_bytes.clamp(0, total),
            retention_days: self.retention_days.clamp(0, 3_650),
            lazy_fetch_threshold_bytes: self.lazy_fetch_threshold_bytes.max(0),
        }
    }
}

/// Persisted workspace index.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct WorkspaceState {
    /// Index schema version.
    pub schema_version: i32,
    /// Workspace entries.
    pub entries: Vec<WorkspaceEntry>,
    /// Retention policy.
    pub policy: WorkspacePolicy,
}

impl Default for WorkspaceState {
    fn default() -> Self {
        Self {
            schema_version: 1,
            entries: Vec::new(),
            policy: WorkspacePolicy::default(),
        }
    }
}

/// One deletion tombstone.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct WorkspaceTombstone {
    /// Deleted SHA-256 content id.
    pub entry_id: String,
    /// Deletion time in Unix seconds.
    pub deleted_at_epoch_seconds: i64,
}

impl WorkspaceTombstone {
    /// Returns a normalized copy.
    #[must_use]
    pub fn normalized(&self) -> Self {
        Self {
            entry_id: normalize_entry_id(&self.entry_id),
            deleted_at_epoch_seconds: self.deleted_at_epoch_seconds.max(0),
        }
    }
}

/// Admission result for a put operation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WorkspaceAdmission {
    /// The entry was accepted.
    Accepted,
    /// The content id already exists.
    Duplicate,
    /// The content id is invalid.
    Invalid,
    /// The entry is larger than the per-entry limit.
    TooLarge,
    /// The entry exceeds the total quota.
    QuotaExceeded,
    /// The source or destination failed.
    Failed,
}

/// Result of one put operation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspacePutResult {
    /// State to use after the operation.
    pub state: WorkspaceState,
    /// Accepted or merged entry.
    pub entry: Option<WorkspaceEntry>,
    /// Admission result.
    pub admission: WorkspaceAdmission,
    /// Whether the index was persisted.
    pub persisted: bool,
}

impl WorkspacePutResult {
    /// Creates a rejected result.
    #[must_use]
    pub fn rejected(state: WorkspaceState, admission: WorkspaceAdmission) -> Self {
        Self {
            state,
            entry: None,
            admission,
            persisted: false,
        }
    }

    /// Returns whether the entry was newly accepted.
    #[must_use]
    pub fn accepted(&self) -> bool {
        self.admission == WorkspaceAdmission::Accepted
    }
}

/// Result of applying retention and eviction.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspacePlan {
    /// Entries retained in the index.
    pub kept: Vec<WorkspaceEntry>,
    /// Entries removed by age.
    pub expired: Vec<WorkspaceEntry>,
    /// Entries removed by quota.
    pub evicted: Vec<WorkspaceEntry>,
    /// Total local bytes in `kept`.
    pub total_bytes: i64,
}

impl WorkspacePlan {
    /// Returns whether the index changed.
    #[must_use]
    pub fn changed(&self) -> bool {
        !self.expired.is_empty() || !self.evicted.is_empty()
    }

    /// Returns content that should be deleted.
    #[must_use]
    pub fn removed(&self) -> Vec<WorkspaceEntry> {
        self.expired.iter().chain(&self.evicted).cloned().collect()
    }
}

/// Lowercase and trim a content id.
#[must_use]
pub fn normalize_entry_id(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}

/// Keep only the final path component of a display name.
#[must_use]
pub fn normalize_display_name(value: &str) -> String {
    value
        .trim()
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or_default()
        .trim()
        .to_owned()
}

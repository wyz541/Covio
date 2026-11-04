//! Receiver-side workspace transfer state machine.

use super::logic::{is_tombstoned, is_valid_entry_id, total_local_bytes};
use super::models::{
    WorkspaceAvailability, WorkspaceEntry, WorkspacePolicy, WorkspaceState, normalize_entry_id,
};
use super::store::WorkspaceStore;
use super::wire::{WorkspaceArgs, WorkspaceEntryParse, WorkspaceErrorCode, WorkspaceWire};
use covio_platform::FileStore;

/// Receiver-side transfer engine.
#[derive(Debug, Clone)]
pub struct WorkspaceTransferEngine<F> {
    store: WorkspaceStore<F>,
}

impl<F: FileStore> WorkspaceTransferEngine<F> {
    /// Creates an engine around a workspace store.
    #[must_use]
    pub fn new(store: WorkspaceStore<F>) -> Self {
        Self { store }
    }

    /// Returns the underlying store.
    #[must_use]
    pub fn store(&self) -> &WorkspaceStore<F> {
        &self.store
    }

    /// Declares a workspace entry for transfer.
    #[must_use]
    pub fn begin(&self, args: &WorkspaceArgs, now_epoch_seconds: i64) -> WorkspaceBeginResult {
        let entry = match WorkspaceWire::entry_from_args(args) {
            WorkspaceEntryParse::BadKind => {
                return WorkspaceBeginResult::rejected(WorkspaceErrorCode::UnsupportedKind);
            }
            WorkspaceEntryParse::BadDigest => {
                return WorkspaceBeginResult::rejected(WorkspaceErrorCode::ChecksumMismatch);
            }
            WorkspaceEntryParse::Ok(entry) => entry.normalized(),
        };
        let state = self.store.load();
        let policy = state.policy.normalized();
        if entry.expires_at_epoch_seconds > 0 && entry.expires_at_epoch_seconds <= now_epoch_seconds
        {
            return WorkspaceBeginResult::rejected(WorkspaceErrorCode::EntryExpired);
        }
        if is_tombstoned(
            &entry.entry_id,
            &self.store.load_tombstones(),
            now_epoch_seconds,
        ) {
            return WorkspaceBeginResult::rejected(WorkspaceErrorCode::EntryNotFound);
        }
        if let Some(existing) = state
            .entries
            .iter()
            .find(|item| item.entry_id == entry.entry_id)
            && self.store.has_content(&entry.entry_id)
        {
            return WorkspaceBeginResult {
                accepted: true,
                task_id: None,
                entry: Some(existing.clone()),
                error_code: None,
                received: existing.byte_size,
            };
        }
        if entry.byte_size > policy.max_entry_bytes {
            return WorkspaceBeginResult::rejected(WorkspaceErrorCode::QuotaExceeded);
        }
        let used = state
            .entries
            .iter()
            .filter(|item| item.entry_id != entry.entry_id)
            .fold(0_i64, |total, item| {
                total.saturating_add(item.local_bytes())
            });
        if used.saturating_add(entry.byte_size) > policy.max_total_bytes {
            return WorkspaceBeginResult::rejected(WorkspaceErrorCode::QuotaExceeded);
        }
        let mut replaced: Vec<_> = state
            .entries
            .iter()
            .filter(|item| item.entry_id != entry.entry_id)
            .cloned()
            .collect();
        if entry.byte_size > policy.lazy_fetch_threshold_bytes {
            let index_only = WorkspaceEntry {
                availability: WorkspaceAvailability::Remote,
                ..entry.clone()
            };
            replaced.push(index_only.clone());
            if self
                .store
                .save(&WorkspaceState {
                    entries: replaced,
                    ..state
                })
                .is_err()
            {
                return WorkspaceBeginResult::rejected(WorkspaceErrorCode::StorageFull);
            }
            return WorkspaceBeginResult {
                accepted: true,
                task_id: None,
                entry: Some(index_only),
                error_code: None,
                received: 0,
            };
        }
        if entry.byte_size == 0 && self.store.append_staging(&entry.entry_id, &[]).is_err() {
            return WorkspaceBeginResult::rejected(WorkspaceErrorCode::StorageFull);
        }
        let fetching = WorkspaceEntry {
            availability: WorkspaceAvailability::Fetching,
            ..entry.clone()
        };
        replaced.push(fetching.clone());
        if self
            .store
            .save(&WorkspaceState {
                entries: replaced,
                ..state
            })
            .is_err()
        {
            return WorkspaceBeginResult::rejected(WorkspaceErrorCode::StorageFull);
        }
        WorkspaceBeginResult {
            accepted: true,
            task_id: Some(entry.entry_id.clone()),
            entry: Some(fetching),
            error_code: None,
            received: self.store.staging_size(&entry.entry_id),
        }
    }

    /// Appends one transfer chunk.
    #[must_use]
    pub fn chunk(&self, task_id: &str, offset: i64, bytes: &[u8]) -> WorkspaceChunkResult {
        let id = normalize_entry_id(task_id);
        let state = self.store.load();
        let Some(entry) = state.entries.iter().find(|entry| entry.entry_id == id) else {
            return WorkspaceChunkResult {
                received: 0,
                error_code: Some(WorkspaceErrorCode::EntryNotFound),
            };
        };
        if entry.availability != WorkspaceAvailability::Fetching {
            return WorkspaceChunkResult {
                received: 0,
                error_code: Some(WorkspaceErrorCode::EntryNotFound),
            };
        }
        let received = self.store.staging_size(&id);
        if offset != received {
            return WorkspaceChunkResult {
                received,
                error_code: None,
            };
        }
        let bytes_len = i64::try_from(bytes.len()).unwrap_or(i64::MAX);
        if received.saturating_add(bytes_len) > entry.byte_size {
            let _ = self.cancel(&id);
            return WorkspaceChunkResult {
                received,
                error_code: Some(WorkspaceErrorCode::ChecksumMismatch),
            };
        }
        if received.saturating_add(bytes_len) > state.policy.normalized().max_entry_bytes {
            let _ = self.cancel(&id);
            return WorkspaceChunkResult {
                received,
                error_code: Some(WorkspaceErrorCode::QuotaExceeded),
            };
        }
        match self.store.append_staging(&id, bytes) {
            Ok(next) => WorkspaceChunkResult {
                received: next,
                error_code: None,
            },
            Err(_) => WorkspaceChunkResult {
                received,
                error_code: Some(WorkspaceErrorCode::StorageFull),
            },
        }
    }

    /// Commits a completed transfer after digest and size verification.
    #[must_use]
    pub fn commit(&self, task_id: &str, sha256: &str) -> WorkspaceCommitResult {
        let id = normalize_entry_id(task_id);
        let state = self.store.load();
        let Some(entry) = state.entries.iter().find(|entry| entry.entry_id == id) else {
            let _ = self.store.delete_staging(&id);
            return WorkspaceCommitResult {
                ok: false,
                error_code: Some(WorkspaceErrorCode::EntryNotFound),
            };
        };
        let digest = self.store.digest_of_staging(&id);
        let declared = normalize_entry_id(sha256);
        let complete = digest.as_deref() == Some(id.as_str())
            && declared == id
            && self.store.staging_size(&id) == entry.byte_size;
        if !complete {
            let _ = self.cancel(&id);
            return WorkspaceCommitResult {
                ok: false,
                error_code: Some(WorkspaceErrorCode::ChecksumMismatch),
            };
        }
        if self.store.commit_staging(&id, &id).unwrap_or(false) {
            let entries = state
                .entries
                .iter()
                .map(|item| {
                    if item.entry_id == id {
                        WorkspaceEntry {
                            availability: WorkspaceAvailability::Local,
                            ..item.clone()
                        }
                    } else {
                        item.clone()
                    }
                })
                .collect();
            if self
                .store
                .save(&WorkspaceState { entries, ..state })
                .is_ok()
            {
                return WorkspaceCommitResult {
                    ok: true,
                    error_code: None,
                };
            }
        } else {
            let _ = self.store.delete_staging(&id);
        }
        WorkspaceCommitResult {
            ok: false,
            error_code: Some(WorkspaceErrorCode::StorageFull),
        }
    }

    /// Cancels one transfer and restores the index entry to remote.
    #[must_use]
    pub fn cancel(&self, task_id: &str) -> bool {
        let id = normalize_entry_id(task_id);
        let _ = self.store.delete_staging(&id);
        let state = self.store.load();
        if !state.entries.iter().any(|entry| entry.entry_id == id) {
            return false;
        }
        let entries = state
            .entries
            .iter()
            .map(|entry| {
                if entry.entry_id == id {
                    WorkspaceEntry {
                        availability: WorkspaceAvailability::Remote,
                        ..entry.clone()
                    }
                } else {
                    entry.clone()
                }
            })
            .collect();
        self.store
            .save(&WorkspaceState { entries, ..state })
            .is_ok()
    }

    /// Deletes one entry and verifies that a tombstone exists.
    #[must_use]
    pub fn delete(&self, entry_id: &str, now_epoch_seconds: i64) -> WorkspaceDeleteResult {
        let id = normalize_entry_id(entry_id);
        if !is_valid_entry_id(&id) {
            return WorkspaceDeleteResult {
                ok: false,
                error_code: Some(WorkspaceErrorCode::EntryNotFound),
            };
        }
        if self
            .store
            .remove(&self.store.load(), &id, now_epoch_seconds)
            .is_err()
        {
            return WorkspaceDeleteResult {
                ok: false,
                error_code: Some(WorkspaceErrorCode::StorageFull),
            };
        }
        if self
            .store
            .load_tombstones()
            .iter()
            .any(|tombstone| tombstone.entry_id == id)
        {
            WorkspaceDeleteResult {
                ok: true,
                error_code: None,
            }
        } else {
            WorkspaceDeleteResult {
                ok: false,
                error_code: Some(WorkspaceErrorCode::StorageFull),
            }
        }
    }

    /// Returns the received byte count for resume.
    #[must_use]
    pub fn resume_offset(&self, task_id: &str) -> i64 {
        self.store.staging_size(&normalize_entry_id(task_id))
    }

    /// Lists entries at or after a millisecond cursor.
    #[must_use]
    pub fn list(&self, since_epoch_millis: i64, limit: i32) -> Vec<WorkspaceEntry> {
        let since_epoch_seconds = since_epoch_millis.max(0) / 1_000;
        let mut entries: Vec<_> = self
            .store
            .load()
            .entries
            .into_iter()
            .filter(|entry| entry.created_at_epoch_seconds >= since_epoch_seconds)
            .collect();
        entries.sort_by(|left, right| {
            right
                .created_at_epoch_seconds
                .cmp(&left.created_at_epoch_seconds)
        });
        if limit > 0 {
            entries.truncate(usize::try_from(limit).unwrap_or_default());
        }
        entries
    }

    /// Returns workspace usage and limits.
    #[must_use]
    pub fn stat(&self) -> WorkspaceStat {
        let state = self.store.load();
        WorkspaceStat {
            total_bytes: total_local_bytes(&state.entries),
            max_total_bytes: state.policy.normalized().max_total_bytes,
            entry_count: state.entries.len(),
        }
    }

    /// Replaces the policy without changing entries.
    pub fn set_policy(&self, policy: &WorkspacePolicy) -> Result<(), crate::CoreError> {
        let state = self.store.load();
        self.store
            .save(&WorkspaceState {
                policy: policy.normalized(),
                ..state
            })
            .map(|_| ())
    }
}

/// One begin result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceBeginResult {
    /// Whether the transfer was accepted.
    pub accepted: bool,
    /// Transfer task id.
    pub task_id: Option<String>,
    /// Entry after admission.
    pub entry: Option<WorkspaceEntry>,
    /// Error code on rejection.
    pub error_code: Option<WorkspaceErrorCode>,
    /// Already received bytes.
    pub received: i64,
}

impl WorkspaceBeginResult {
    /// Creates a rejected result.
    #[must_use]
    pub fn rejected(error_code: WorkspaceErrorCode) -> Self {
        Self {
            accepted: false,
            task_id: None,
            entry: None,
            error_code: Some(error_code),
            received: 0,
        }
    }
}

/// Chunk result.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WorkspaceChunkResult {
    /// Number of received bytes.
    pub received: i64,
    /// Error code on failure.
    pub error_code: Option<WorkspaceErrorCode>,
}

/// Commit result.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WorkspaceCommitResult {
    /// Whether the commit succeeded.
    pub ok: bool,
    /// Error code on failure.
    pub error_code: Option<WorkspaceErrorCode>,
}

/// Delete result.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WorkspaceDeleteResult {
    /// Whether the delete succeeded.
    pub ok: bool,
    /// Error code on failure.
    pub error_code: Option<WorkspaceErrorCode>,
}

/// Workspace usage.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WorkspaceStat {
    /// Total local bytes.
    pub total_bytes: i64,
    /// Configured total limit.
    pub max_total_bytes: i64,
    /// Number of entries.
    pub entry_count: usize,
}

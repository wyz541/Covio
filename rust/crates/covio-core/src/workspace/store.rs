//! Workspace index, content-addressed bytes, staging, and tombstones.

use super::logic::{
    admit, dedupe, expiry_epoch_seconds, is_valid_entry_id, live_tombstones, plan, with_tombstone,
};
use super::models::{
    WorkspaceAdmission, WorkspaceEntry, WorkspacePlan, WorkspacePolicy, WorkspacePutResult,
    WorkspaceState, WorkspaceTombstone, normalize_display_name, normalize_entry_id,
};
use crate::{CoreError, CoreErrorCode};
use covio_platform::{FileStore, temporary_path};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

const CHUNK_BYTES: usize = 64 * 1024;

/// Workspace repository backed by a filesystem capability.
#[derive(Debug, Clone)]
pub struct WorkspaceStore<F> {
    directory: PathBuf,
    files: F,
}

impl<F: FileStore> WorkspaceStore<F> {
    /// Creates a workspace store for one directory.
    #[must_use]
    pub fn new(directory: impl Into<PathBuf>, files: F) -> Self {
        Self {
            directory: directory.into(),
            files,
        }
    }

    /// Returns the workspace directory.
    #[must_use]
    pub fn directory(&self) -> &Path {
        &self.directory
    }

    /// Returns the index path.
    #[must_use]
    pub fn index_path(&self) -> PathBuf {
        self.directory.join("index.json")
    }

    /// Returns the objects directory.
    #[must_use]
    pub fn objects_directory(&self) -> PathBuf {
        self.directory.join("objects")
    }

    /// Returns the incoming directory.
    #[must_use]
    pub fn incoming_directory(&self) -> PathBuf {
        self.directory.join("incoming")
    }

    /// Returns the tombstone path.
    #[must_use]
    pub fn tombstones_path(&self) -> PathBuf {
        self.directory.join("tombstones.json")
    }

    /// Loads and normalizes the index. Invalid data returns defaults.
    #[must_use]
    pub fn load(&self) -> WorkspaceState {
        self.files
            .read(&self.index_path())
            .ok()
            .flatten()
            .and_then(|bytes| serde_json::from_slice::<WorkspaceState>(&bytes).ok())
            .map_or_else(WorkspaceState::default, normalize_state)
    }

    /// Saves normalized workspace state.
    pub fn save(&self, state: &WorkspaceState) -> Result<WorkspaceState, CoreError> {
        let normalized = normalize_state(state.clone());
        self.files
            .create_dir_all(&self.directory)
            .map_err(CoreError::from)?;
        let bytes =
            serde_json::to_vec_pretty(&normalized).map_err(|_| internal("index encoding"))?;
        self.files
            .write_atomic(&self.index_path(), &bytes)
            .map_err(CoreError::from)?;
        Ok(normalized)
    }

    /// Loads valid normalized tombstones.
    #[must_use]
    pub fn load_tombstones(&self) -> Vec<WorkspaceTombstone> {
        self.files
            .read(&self.tombstones_path())
            .ok()
            .flatten()
            .and_then(|bytes| serde_json::from_slice::<Vec<WorkspaceTombstone>>(&bytes).ok())
            .map_or_else(Vec::new, |tombstones| {
                let mut seen = std::collections::HashSet::new();
                tombstones
                    .into_iter()
                    .map(|tombstone| tombstone.normalized())
                    .filter(|tombstone| {
                        is_valid_entry_id(&tombstone.entry_id)
                            && seen.insert(tombstone.entry_id.clone())
                    })
                    .collect()
            })
    }

    /// Saves normalized tombstones.
    pub fn save_tombstones(
        &self,
        tombstones: &[WorkspaceTombstone],
    ) -> Result<Vec<WorkspaceTombstone>, CoreError> {
        let mut seen = std::collections::HashSet::new();
        let normalized: Vec<_> = tombstones
            .iter()
            .map(WorkspaceTombstone::normalized)
            .filter(|tombstone| {
                is_valid_entry_id(&tombstone.entry_id) && seen.insert(tombstone.entry_id.clone())
            })
            .collect();
        self.files
            .create_dir_all(&self.directory)
            .map_err(CoreError::from)?;
        let bytes =
            serde_json::to_vec_pretty(&normalized).map_err(|_| internal("tombstone encoding"))?;
        self.files
            .write_atomic(&self.tombstones_path(), &bytes)
            .map_err(CoreError::from)?;
        Ok(normalized)
    }

    /// Removes index, tombstones, objects, and incoming data.
    pub fn clear(&self) -> Result<bool, CoreError> {
        let index = self.index_path();
        let tombstones = self.tombstones_path();
        let mut changed = false;
        changed |= self.files.remove_file(&index).map_err(CoreError::from)?;
        changed |= self
            .files
            .remove_file(&temporary_path(&index))
            .map_err(CoreError::from)?;
        changed |= self
            .files
            .remove_file(&tombstones)
            .map_err(CoreError::from)?;
        changed |= self
            .files
            .remove_file(&temporary_path(&tombstones))
            .map_err(CoreError::from)?;
        self.files
            .remove_tree(&self.objects_directory())
            .map_err(CoreError::from)?;
        self.files
            .remove_tree(&self.incoming_directory())
            .map_err(CoreError::from)?;
        Ok(changed)
    }

    /// Returns a content path for a valid content id.
    #[must_use]
    pub fn content_path(&self, entry_id: &str) -> Option<PathBuf> {
        let id = normalize_entry_id(entry_id);
        is_valid_entry_id(&id).then(|| self.objects_directory().join(id))
    }

    /// Returns whether content exists.
    #[must_use]
    pub fn has_content(&self, entry_id: &str) -> bool {
        self.content_path(entry_id)
            .is_some_and(|path| self.files.exists(&path).unwrap_or(false))
    }

    /// Reads complete content.
    #[must_use]
    pub fn read_content(&self, entry_id: &str) -> Option<Vec<u8>> {
        let path = self.content_path(entry_id)?;
        self.files.read(&path).ok().flatten()
    }

    /// Writes content after checking the declared digest.
    pub fn put_content(&self, entry_id: &str, bytes: &[u8]) -> Result<bool, CoreError> {
        let id = normalize_entry_id(entry_id);
        if !is_valid_entry_id(&id) || digest_of_bytes(bytes) != id {
            return Ok(false);
        }
        self.persist_content(&id, bytes)
            .map(|()| true)
            .map_err(CoreError::from)
    }

    /// Hashes bytes, writes them, and returns the digest.
    pub fn import_content(&self, bytes: &[u8]) -> Result<String, CoreError> {
        let id = digest_of_bytes(bytes);
        if self.put_content(&id, bytes)? {
            Ok(id)
        } else {
            Err(internal("workspace content write failed"))
        }
    }

    /// Puts UTF-8 text into the workspace.
    pub fn put_text(
        &self,
        state: &WorkspaceState,
        text: &str,
        display_name: &str,
        content_type: &str,
        origin_device_id: &str,
        now_epoch_seconds: i64,
    ) -> WorkspacePutResult {
        self.put_bytes(
            state,
            text.as_bytes(),
            display_name,
            content_type,
            origin_device_id,
            now_epoch_seconds,
        )
    }

    /// Puts an external file into the workspace with bounded range reads.
    pub fn put_file(
        &self,
        state: &WorkspaceState,
        source_path: &str,
        display_name: &str,
        content_type: &str,
        origin_device_id: &str,
        now_epoch_seconds: i64,
    ) -> WorkspacePutResult {
        let policy = state.policy.normalized();
        let source_path = Path::new(source_path.trim());
        let declared_size = match self.files.metadata_size(source_path) {
            Ok(Some(size)) => size,
            Ok(None) | Err(_) => {
                return WorkspacePutResult::rejected(state.clone(), WorkspaceAdmission::Failed);
            }
        };
        if declared_size > u64::try_from(policy.max_entry_bytes).unwrap_or_default() {
            return WorkspacePutResult::rejected(state.clone(), WorkspaceAdmission::TooLarge);
        }
        let Some(staged) = self.stage_file(source_path, &policy) else {
            return WorkspacePutResult::rejected(state.clone(), WorkspaceAdmission::Failed);
        };
        self.settle(
            state,
            staged,
            normalize_display_name(display_name),
            content_type,
            origin_device_id,
            now_epoch_seconds,
        )
    }

    /// Updates the local pinned flag.
    pub fn set_pinned(
        &self,
        state: &WorkspaceState,
        entry_id: &str,
        pinned: bool,
    ) -> Result<WorkspaceState, CoreError> {
        let id = normalize_entry_id(entry_id);
        if !is_valid_entry_id(&id) {
            return Ok(state.clone());
        }
        let entries = state
            .entries
            .iter()
            .map(|entry| {
                if entry.entry_id == id {
                    WorkspaceEntry {
                        pinned,
                        ..entry.clone()
                    }
                } else {
                    entry.clone()
                }
            })
            .collect();
        self.save(&WorkspaceState {
            entries,
            ..state.clone()
        })
    }

    /// Deletes one entry and writes a tombstone before deleting content.
    pub fn remove(
        &self,
        state: &WorkspaceState,
        entry_id: &str,
        now_epoch_seconds: i64,
    ) -> Result<WorkspaceState, CoreError> {
        let id = normalize_entry_id(entry_id);
        if !is_valid_entry_id(&id) || !self.mark_deleted(&id, now_epoch_seconds)? {
            return Ok(state.clone());
        }
        let entries: Vec<_> = state
            .entries
            .iter()
            .filter(|entry| entry.entry_id != id)
            .cloned()
            .collect();
        if entries.len() == state.entries.len() {
            return Ok(state.clone());
        }
        self.delete_content(&id)?;
        self.save(&WorkspaceState {
            entries,
            ..state.clone()
        })
    }

    /// Writes one tombstone.
    pub fn mark_deleted(&self, entry_id: &str, now_epoch_seconds: i64) -> Result<bool, CoreError> {
        let id = normalize_entry_id(entry_id);
        if !is_valid_entry_id(&id) {
            return Ok(false);
        }
        let marked = with_tombstone(&self.load_tombstones(), &id, now_epoch_seconds);
        self.save_tombstones(&marked)?;
        Ok(true)
    }

    /// Recomputes and verifies the stored digest.
    #[must_use]
    pub fn verify_content(&self, entry_id: &str) -> bool {
        let id = normalize_entry_id(entry_id);
        self.content_path(&id).is_some_and(|path| {
            self.files.exists(&path).unwrap_or(false)
                && self
                    .digest_of_file(&path)
                    .is_some_and(|digest| digest == id)
        })
    }

    /// Deletes content for one valid content id.
    pub fn delete_content(&self, entry_id: &str) -> Result<bool, CoreError> {
        let Some(path) = self.content_path(entry_id) else {
            return Ok(false);
        };
        self.files.remove_file(&path).map_err(CoreError::from)
    }

    /// Returns the staging path for one transfer.
    #[must_use]
    pub fn staging_path(&self, task_id: &str) -> Option<PathBuf> {
        let id = normalize_entry_id(task_id);
        is_valid_entry_id(&id).then(|| self.incoming_directory().join(format!("{id}.part")))
    }

    /// Returns the received staging size.
    #[must_use]
    pub fn staging_size(&self, task_id: &str) -> i64 {
        self.staging_path(task_id)
            .and_then(|path| self.files.metadata_size(&path).ok().flatten())
            .and_then(|size| i64::try_from(size).ok())
            .unwrap_or(0)
    }

    /// Appends bytes to the transfer staging file.
    pub fn append_staging(&self, task_id: &str, bytes: &[u8]) -> Result<i64, CoreError> {
        let Some(path) = self.staging_path(task_id) else {
            return Err(CoreError::new(
                CoreErrorCode::InvalidArgument,
                "workspace task id is invalid",
            ));
        };
        if let Some(parent) = path.parent() {
            self.files.create_dir_all(parent).map_err(CoreError::from)?;
        }
        if !self.files.exists(&path).map_err(CoreError::from)? {
            self.files
                .write_atomic(&path, &[])
                .map_err(CoreError::from)?;
        }
        self.files
            .append(&path, bytes)
            .map_err(CoreError::from)
            .and_then(|size| i64::try_from(size).map_err(|_| internal("staging size overflow")))
    }

    /// Returns the staging content digest.
    #[must_use]
    pub fn digest_of_staging(&self, task_id: &str) -> Option<String> {
        self.staging_path(task_id)
            .and_then(|path| self.digest_of_file(&path))
    }

    /// Moves staging content into the objects directory.
    pub fn commit_staging(&self, task_id: &str, entry_id: &str) -> Result<bool, CoreError> {
        let Some(source) = self.staging_path(task_id) else {
            return Ok(false);
        };
        let Some(target) = self.content_path(entry_id) else {
            return Ok(false);
        };
        self.files
            .create_dir_all(&self.objects_directory())
            .map_err(CoreError::from)?;
        if self.files.exists(&target).map_err(CoreError::from)? {
            self.files.remove_file(&source).map_err(CoreError::from)?;
            return Ok(true);
        }
        self.files
            .atomic_move(&source, &target)
            .map_err(CoreError::from)?;
        Ok(true)
    }

    /// Deletes transfer staging.
    pub fn delete_staging(&self, task_id: &str) -> Result<bool, CoreError> {
        let Some(path) = self.staging_path(task_id) else {
            return Ok(false);
        };
        self.files.remove_file(&path).map_err(CoreError::from)
    }

    /// Applies retention and quota rules, then removes affected content.
    pub fn sweep(
        &self,
        policy: &WorkspacePolicy,
        now_epoch_seconds: i64,
    ) -> Result<WorkspacePlan, CoreError> {
        let state = self.load();
        let proposed = plan(&state.entries, policy, now_epoch_seconds);
        for entry in proposed.removed() {
            self.delete_content(&entry.entry_id)?;
        }
        let next = WorkspaceState {
            policy: policy.normalized(),
            entries: proposed.kept.clone(),
            ..state.clone()
        };
        if proposed.changed() || next.policy != state.policy {
            self.save(&next)?;
        }
        let marked = self.load_tombstones();
        let live = live_tombstones(&marked, now_epoch_seconds);
        if live.len() != marked.len() {
            self.save_tombstones(&live)?;
        }
        Ok(proposed)
    }

    fn put_bytes(
        &self,
        state: &WorkspaceState,
        bytes: &[u8],
        display_name: &str,
        content_type: &str,
        origin_device_id: &str,
        now_epoch_seconds: i64,
    ) -> WorkspacePutResult {
        let policy = state.policy.normalized();
        if i64::try_from(bytes.len()).unwrap_or(i64::MAX) > policy.max_entry_bytes {
            return WorkspacePutResult::rejected(state.clone(), WorkspaceAdmission::TooLarge);
        }
        let Some(staged) = self.stage_bytes(bytes, &policy) else {
            return WorkspacePutResult::rejected(state.clone(), WorkspaceAdmission::Failed);
        };
        self.settle(
            state,
            staged,
            normalize_display_name(display_name),
            content_type,
            origin_device_id,
            now_epoch_seconds,
        )
    }

    fn settle(
        &self,
        state: &WorkspaceState,
        staged: Staged,
        name: String,
        content_type: &str,
        origin_device_id: &str,
        now_epoch_seconds: i64,
    ) -> WorkspacePutResult {
        let Staged::Done {
            entry_id,
            byte_size,
        } = staged
        else {
            return WorkspacePutResult::rejected(state.clone(), WorkspaceAdmission::TooLarge);
        };
        let policy = state.policy.normalized();
        let entry = WorkspaceEntry {
            entry_id: entry_id.clone(),
            kind: super::logic::classify(&name, content_type),
            display_name: name,
            byte_size,
            content_type: content_type.trim().to_owned(),
            created_at_epoch_seconds: now_epoch_seconds.max(0),
            origin_device_id: origin_device_id.trim().to_owned(),
            expires_at_epoch_seconds: expiry_epoch_seconds(now_epoch_seconds, &policy),
            availability: super::models::WorkspaceAvailability::Local,
            pinned: false,
        };
        match admit(&entry, &state.entries, &policy) {
            WorkspaceAdmission::Accepted => {
                let mut entries = state.entries.clone();
                entries.push(entry);
                match self.save(&WorkspaceState {
                    entries,
                    ..state.clone()
                }) {
                    Ok(next) => {
                        let settled = next
                            .entries
                            .iter()
                            .find(|item| item.entry_id == entry_id)
                            .cloned();
                        WorkspacePutResult {
                            state: next,
                            entry: settled,
                            admission: WorkspaceAdmission::Accepted,
                            persisted: true,
                        }
                    }
                    Err(_) => WorkspacePutResult {
                        state: state.clone(),
                        entry: None,
                        admission: WorkspaceAdmission::Accepted,
                        persisted: false,
                    },
                }
            }
            WorkspaceAdmission::Duplicate => {
                let existing = dedupe(&state.entries)
                    .into_iter()
                    .find(|item| item.entry_id == entry_id);
                WorkspacePutResult {
                    state: state.clone(),
                    entry: existing,
                    admission: WorkspaceAdmission::Duplicate,
                    persisted: true,
                }
            }
            admission => {
                let _ = self.delete_content(&entry.entry_id);
                WorkspacePutResult::rejected(state.clone(), admission)
            }
        }
    }

    fn stage_bytes(&self, bytes: &[u8], policy: &WorkspacePolicy) -> Option<Staged> {
        if i64::try_from(bytes.len()).ok()? > policy.max_entry_bytes {
            return None;
        }
        self.files.create_dir_all(&self.incoming_directory()).ok()?;
        let partial = self
            .incoming_directory()
            .join(format!("{}.part", unique_staging_name()));
        self.files.write_atomic(&partial, bytes).ok()?;
        let id = digest_of_bytes(bytes);
        self.move_staged_file(&partial, &id)
            .ok()
            .map(|()| Staged::Done {
                entry_id: id,
                byte_size: i64::try_from(bytes.len()).unwrap_or(i64::MAX),
            })
    }

    fn stage_file(&self, source: &Path, policy: &WorkspacePolicy) -> Option<Staged> {
        self.files.create_dir_all(&self.incoming_directory()).ok()?;
        let partial = self
            .incoming_directory()
            .join(format!("{}.part", unique_staging_name()));
        self.files.write_atomic(&partial, &[]).ok()?;
        let mut hasher = Sha256::new();
        let mut offset = 0_u64;
        let mut total = 0_i64;
        loop {
            let chunk = match self.files.read_range(source, offset, CHUNK_BYTES) {
                Ok(Some(chunk)) => chunk,
                Ok(None) | Err(_) => {
                    let _ = self.files.remove_file(&partial);
                    return None;
                }
            };
            if chunk.is_empty() {
                break;
            }
            total = total.saturating_add(i64::try_from(chunk.len()).ok()?);
            if total > policy.max_entry_bytes {
                let _ = self.files.remove_file(&partial);
                return Some(Staged::TooLarge);
            }
            hasher.update(&chunk);
            if self.files.append(&partial, &chunk).is_err() {
                let _ = self.files.remove_file(&partial);
                return None;
            }
            offset = offset.saturating_add(u64::try_from(chunk.len()).ok()?);
        }
        let id = hex_digest(&hasher.finalize());
        self.move_staged_file(&partial, &id)
            .ok()
            .map(|()| Staged::Done {
                entry_id: id,
                byte_size: total,
            })
    }

    fn move_staged_file(
        &self,
        partial: &Path,
        id: &str,
    ) -> Result<(), covio_platform::PlatformError> {
        self.files.create_dir_all(&self.incoming_directory())?;
        let named = self.incoming_directory().join(id);
        self.files.atomic_move(partial, &named)?;
        self.files.create_dir_all(&self.objects_directory())?;
        let target = self.objects_directory().join(id);
        if self.files.exists(&target)? {
            self.files.remove_file(&named)?;
        } else {
            self.files.atomic_move(&named, &target)?;
        }
        Ok(())
    }

    fn persist_content(&self, id: &str, bytes: &[u8]) -> Result<(), covio_platform::PlatformError> {
        self.files.create_dir_all(&self.incoming_directory())?;
        let incoming = self.incoming_directory().join(id);
        self.files.write_atomic(&incoming, bytes)?;
        self.files.create_dir_all(&self.objects_directory())?;
        let target = self.objects_directory().join(id);
        if self.files.exists(&target)? {
            self.files.remove_file(&incoming)?;
        } else {
            self.files.atomic_move(&incoming, &target)?;
        }
        Ok(())
    }

    fn digest_of_file(&self, path: &Path) -> Option<String> {
        let mut hasher = Sha256::new();
        let mut offset = 0_u64;
        loop {
            let chunk = self.files.read_range(path, offset, CHUNK_BYTES).ok()??;
            if chunk.is_empty() {
                break;
            }
            hasher.update(&chunk);
            offset = offset.saturating_add(u64::try_from(chunk.len()).ok()?);
        }
        Some(hex_digest(&hasher.finalize()))
    }
}

#[derive(Debug, Clone)]
enum Staged {
    Done { entry_id: String, byte_size: i64 },
    TooLarge,
}

fn normalize_state(mut state: WorkspaceState) -> WorkspaceState {
    state.schema_version = 1;
    state.entries = dedupe(&state.entries);
    state.policy = state.policy.normalized();
    state
}

fn digest_of_bytes(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex_digest(&hasher.finalize())
}

fn hex_digest(bytes: &[u8]) -> String {
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        use std::fmt::Write;
        let _ = write!(output, "{byte:02x}");
    }
    output
}

fn unique_staging_name() -> String {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let sequence = COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{}-{sequence}", std::process::id())
}

fn internal(message: &'static str) -> CoreError {
    CoreError::new(CoreErrorCode::Internal, message)
}

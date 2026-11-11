//! Receiver-side directory planning, staging, resume, commit, and retention.

use super::super::store::{DirectoryTransferJob, TransferStore};
use super::super::{
    FileChunkFrame, TRANSFER_CHUNK_SIZE, TransferDirection, TransferError, TransferErrorCode,
    TransferState, plan_directory_conflicts, validate_directory_path,
};
use super::conflict::{
    DestinationEntry, DestinationEntryKind, DirectoryConflictAction, DirectoryConflictPlan,
    DirectoryConflictPolicy, DirectoryEntryStatus,
};
use super::manifest::{
    DirectoryEntry, DirectoryEntryKind, DirectoryTransferOffer, DirectoryTransferSummary,
};
use super::recovery::{DirectoryResumePlan, staging_path_for, verify_directory_resume};
use super::retention::{
    RetentionPlan, TransferRetentionPolicy, plan_retention, validate_retention_policy,
};
use covio_platform::{FileEntryKind, FileStore};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// UI-neutral directory transfer snapshot.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryTransferSnapshot {
    /// Durable job.
    pub job: DirectoryTransferJob,
    /// Receiver-visible summary.
    pub summary: DirectoryTransferSummary,
    /// File-byte progress from 0 through 100.
    pub progress_percent: u8,
}

fn scan_existing<F: FileStore>(
    files: &F,
    directory: &Path,
    prefix: &str,
    entries: &mut Vec<DestinationEntry>,
) -> Result<(), TransferError> {
    for name in files
        .directory_entries(directory)
        .map_err(TransferError::from_platform)?
    {
        super::super::validate_component(&name)?;
        let relative_path = if prefix.is_empty() {
            name.clone()
        } else {
            format!("{prefix}/{name}")
        };
        let path = directory.join(&name);
        let metadata = files
            .metadata(&path)
            .map_err(TransferError::from_platform)?
            .ok_or_else(|| TransferError::storage("destination entry disappeared", true))?;
        match metadata.kind {
            FileEntryKind::File => entries.push(DestinationEntry {
                relative_path,
                kind: DestinationEntryKind::File,
            }),
            FileEntryKind::Directory => {
                entries.push(DestinationEntry {
                    relative_path: relative_path.clone(),
                    kind: DestinationEntryKind::Directory,
                });
                scan_existing(files, &path, &relative_path, entries)?;
            }
            FileEntryKind::Symlink => return Err(symlink_refused()),
            FileEntryKind::Other => {
                return Err(TransferError::new(
                    TransferErrorCode::UnsupportedEntryKind,
                    "destination contains an unsupported filesystem entry",
                    false,
                ));
            }
        }
    }
    Ok(())
}

fn digest_file<F: FileStore>(files: &F, path: &Path, size: u64) -> Result<String, TransferError> {
    let mut hasher = blake3::Hasher::new();
    let mut offset = 0_u64;
    while offset < size {
        let length = usize::try_from((size - offset).min(u64::from(TRANSFER_CHUNK_SIZE)))
            .map_err(|_| TransferError::internal("directory digest length overflow"))?;
        let bytes = files
            .read_range(path, offset, length)
            .map_err(TransferError::from_platform)?
            .ok_or_else(|| TransferError::storage("directory file disappeared", true))?;
        if bytes.len() != length {
            return Err(TransferError::storage(
                "directory file read was incomplete",
                true,
            ));
        }
        hasher.update(&bytes);
        offset = offset
            .checked_add(length as u64)
            .ok_or_else(|| TransferError::internal("directory digest offset overflow"))?;
    }
    Ok(hasher.finalize().to_hex().to_string())
}

fn symlink_refused() -> TransferError {
    TransferError::new(
        TransferErrorCode::SymlinkRefused,
        "symbolic links are not supported",
        false,
    )
}

fn snapshot(job: DirectoryTransferJob) -> DirectoryTransferSnapshot {
    let progress_percent = if job.state == TransferState::Completed {
        100
    } else {
        job.durable_bytes
            .saturating_mul(100)
            .checked_div(job.total_bytes)
            .and_then(|value| u8::try_from(value).ok())
            .unwrap_or(0)
    };
    DirectoryTransferSnapshot {
        summary: job.manifest.summary(),
        job,
        progress_percent,
    }
}

/// Result of accepting one directory offer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DirectoryAcceptResult {
    /// Durable snapshot after acceptance.
    pub snapshot: DirectoryTransferSnapshot,
    /// Persisted conflict plan.
    pub plan: DirectoryConflictPlan,
}

/// Result of one received directory file chunk.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DirectoryChunkOutcome {
    /// Aggregate durable bytes after this chunk.
    pub durable_bytes: u64,
    /// Durable bytes for this file entry.
    pub entry_durable_bytes: u64,
    /// Whether the exact chunk was already durable.
    pub duplicate: bool,
}

/// Result of committing one file entry.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DirectoryEntryOutcome {
    /// Source path relative to the transfer root.
    pub relative_path: String,
    /// Final path relative to the transfer root.
    pub target_relative_path: String,
    /// Applied conflict action.
    pub action: DirectoryConflictAction,
    /// Whether the entry was already in its final state.
    pub duplicate: bool,
}

/// Result of completing one directory transfer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DirectoryCompleteOutcome {
    /// Completed snapshot.
    pub snapshot: DirectoryTransferSnapshot,
    /// Number of committed files.
    pub committed_files: usize,
    /// Number of skipped files.
    pub skipped_files: usize,
}

/// One retention cleanup failure.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryRetentionFailure {
    /// Transfer identifier.
    pub transfer_id: String,
    /// Stable error code.
    pub error_code: TransferErrorCode,
}

/// Result of applying a retention plan.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryRetentionSweep {
    /// Number of cleaned staging directories.
    pub cleaned_staging: usize,
    /// Number of purged terminal metadata records.
    pub purged_metadata: usize,
    /// Per-task failures. Final destination files are never removed.
    pub failures: Vec<DirectoryRetentionFailure>,
}

/// Receiver-side directory transfer engine.
pub struct DirectoryTransferReceiver<F: FileStore> {
    store: TransferStore,
    files: F,
    destination_root: PathBuf,
}

impl<F: FileStore> DirectoryTransferReceiver<F> {
    /// Creates a receiver rooted at the final destination volume.
    pub fn new(store: TransferStore, files: F, destination_root: impl Into<PathBuf>) -> Self {
        Self {
            store,
            files,
            destination_root: destination_root.into(),
        }
    }

    /// Returns the durable store.
    #[must_use]
    pub fn store(&self) -> &TransferStore {
        &self.store
    }

    /// Persists an incoming directory offer.
    pub fn receive_offer(
        &self,
        offer: &DirectoryTransferOffer,
        now_ms: i64,
    ) -> Result<DirectoryTransferSnapshot, TransferError> {
        offer.validate()?;
        offer.ensure_live(now_ms)?;
        self.files
            .create_dir_all(&self.destination_root)
            .map_err(TransferError::from_platform)?;
        let job = self.store.create_directory_job(
            offer,
            &offer.manifest.sender_device_id,
            TransferDirection::Receive,
            now_ms,
        )?;
        Ok(snapshot(job))
    }

    /// Builds and persists a conflict plan, then prepares staging files.
    pub fn accept(
        &self,
        transfer_id: &str,
        policy: DirectoryConflictPolicy,
        now_ms: i64,
    ) -> Result<DirectoryAcceptResult, TransferError> {
        let job = self.store.directory_job(transfer_id)?;
        let existing = self.existing_entries(&job.manifest.root_name)?;
        let plan = plan_directory_conflicts(&job.manifest, &existing, policy)?;
        let job = self
            .store
            .accept_directory_job(transfer_id, policy, &plan, now_ms)?;
        let staging_directory = self.files_staging_directory(transfer_id)?;
        self.files
            .create_dir_all(&staging_directory)
            .map_err(TransferError::from_platform)?;
        for planned in &plan.entries {
            if planned.entry.kind == DirectoryEntryKind::File
                && planned.action != DirectoryConflictAction::Skip
            {
                let path = staging_path_for(&staging_directory, &planned.entry.relative_path);
                if self
                    .files
                    .metadata_size(&path)
                    .map_err(TransferError::from_platform)?
                    .is_none()
                {
                    self.files
                        .write_atomic(&path, b"")
                        .map_err(TransferError::from_platform)?;
                }
            }
        }
        Ok(DirectoryAcceptResult {
            snapshot: snapshot(job),
            plan,
        })
    }

    /// Receives one verified chunk for one file entry.
    pub fn receive_chunk(
        &self,
        transfer_id: &str,
        relative_path: &str,
        frame: &FileChunkFrame,
        now_ms: i64,
    ) -> Result<DirectoryChunkOutcome, TransferError> {
        let job = self.store.directory_job(transfer_id)?;
        if job.state != TransferState::Transferring {
            return Err(TransferError::invalid(
                "directory transfer is not receiving data",
            ));
        }
        let plan = job
            .plan
            .as_ref()
            .ok_or_else(|| TransferError::invalid("directory transfer is not accepted"))?;
        let planned = plan
            .file_entry(relative_path)
            .ok_or_else(|| TransferError::invalid("directory file entry does not exist"))?;
        if planned.status != DirectoryEntryStatus::Pending {
            return Ok(DirectoryChunkOutcome {
                durable_bytes: job.durable_bytes,
                entry_durable_bytes: planned.entry.size,
                duplicate: true,
            });
        }
        if planned.action == DirectoryConflictAction::Skip {
            return Err(TransferError::invalid("directory file entry is skipped"));
        }
        frame.verify()?;
        let chunk_size = u64::from(TRANSFER_CHUNK_SIZE);
        if !frame.offset.is_multiple_of(chunk_size) {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "directory chunk offset is not aligned",
                false,
            ));
        }
        let chunks = self.store.directory_chunks(transfer_id)?;
        let entry_chunks = chunks
            .iter()
            .filter(|chunk| chunk.relative_path == relative_path)
            .collect::<Vec<_>>();
        let entry_progress = entry_chunks
            .iter()
            .map(|chunk| chunk.offset.saturating_add(u64::from(chunk.length)))
            .max()
            .unwrap_or(0);
        let chunk_index = frame.offset / chunk_size;
        if let Some(existing) = entry_chunks
            .iter()
            .find(|chunk| chunk.chunk_index == chunk_index)
        {
            if existing.offset == frame.offset
                && existing.length == frame.length
                && existing.blake3 == frame.blake3
            {
                return Ok(DirectoryChunkOutcome {
                    durable_bytes: job.durable_bytes,
                    entry_durable_bytes: entry_progress,
                    duplicate: true,
                });
            }
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "directory chunk conflicts with its checkpoint",
                false,
            ));
        }
        if frame.offset != entry_progress {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "directory chunk is not the next durable chunk",
                true,
            ));
        }
        if entry_progress >= planned.entry.size {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "directory file already has all expected bytes",
                false,
            ));
        }
        let expected_length = (planned.entry.size - entry_progress).min(chunk_size);
        if u64::from(frame.length) != expected_length {
            return Err(TransferError::invalid(
                "directory chunk length is not expected for its offset",
            ));
        }
        let staging_path =
            staging_path_for(&self.files_staging_directory(transfer_id)?, relative_path);
        let staged_size = self
            .files
            .metadata_size(&staging_path)
            .map_err(TransferError::from_platform)?
            .ok_or_else(|| {
                TransferError::new(
                    TransferErrorCode::ResumeCheckpointInvalid,
                    "directory staging file is missing",
                    false,
                )
            })?;
        if staged_size != entry_progress {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "directory staging size does not match the checkpoint",
                false,
            ));
        }
        let appended = self
            .files
            .append(&staging_path, &frame.payload)
            .map_err(TransferError::from_platform)?;
        let expected_end = frame
            .offset
            .checked_add(u64::from(frame.length))
            .ok_or_else(|| TransferError::invalid("directory chunk end offset overflow"))?;
        if appended != expected_end {
            let _ = self.files.truncate(&staging_path, entry_progress);
            let _ = self.store.fail_directory_job(
                transfer_id,
                TransferErrorCode::StorageIoError,
                now_ms,
            );
            return Err(TransferError::storage(
                "directory staging append size mismatch",
                false,
            ));
        }
        let checkpoint =
            match self
                .store
                .checkpoint_directory_chunk(transfer_id, relative_path, frame, now_ms)
            {
                Ok(checkpoint) => checkpoint,
                Err(error) => {
                    let _ = self.files.truncate(&staging_path, entry_progress);
                    return Err(error);
                }
            };
        Ok(DirectoryChunkOutcome {
            durable_bytes: checkpoint.durable_bytes,
            entry_durable_bytes: expected_end,
            duplicate: !checkpoint.inserted,
        })
    }

    /// Verifies durable chunks, removes unverified tails, and resumes the job.
    pub fn resume(
        &self,
        transfer_id: &str,
        now_ms: i64,
    ) -> Result<DirectoryResumePlan, TransferError> {
        let job = self.store.directory_job(transfer_id)?;
        let plan = job
            .plan
            .as_ref()
            .ok_or_else(|| TransferError::invalid("directory transfer is not accepted"))?;
        let resume = verify_directory_resume(
            &self.files,
            &job.manifest,
            plan,
            &self.store.directory_chunks(transfer_id)?,
            &self.files_staging_directory(transfer_id)?,
        )?;
        self.store.resume_directory_job(transfer_id, now_ms)?;
        Ok(resume)
    }

    /// Pauses a directory transfer without deleting staging data.
    pub fn pause(
        &self,
        transfer_id: &str,
        now_ms: i64,
    ) -> Result<DirectoryTransferSnapshot, TransferError> {
        self.store.pause_directory_job(transfer_id, now_ms)?;
        Ok(snapshot(self.store.directory_job(transfer_id)?))
    }

    /// Cancels a directory transfer and retains staging for retention cleanup.
    pub fn cancel(&self, transfer_id: &str, now_ms: i64) -> Result<(), TransferError> {
        self.store
            .cancel_directory_job(transfer_id, TransferDirection::Receive, now_ms)
    }

    /// Verifies and commits one complete file entry.
    pub fn complete_entry(
        &self,
        transfer_id: &str,
        relative_path: &str,
        now_ms: i64,
    ) -> Result<DirectoryEntryOutcome, TransferError> {
        let mut job = self.store.directory_job(transfer_id)?;
        let mut plan = job
            .plan
            .take()
            .ok_or_else(|| TransferError::invalid("directory transfer is not accepted"))?;
        let index = plan
            .entries
            .iter()
            .position(|entry| {
                entry.entry.kind == DirectoryEntryKind::File
                    && entry.entry.relative_path == relative_path
            })
            .ok_or_else(|| TransferError::invalid("directory file entry does not exist"))?;
        let planned = plan.entries[index].clone();
        if planned.status != DirectoryEntryStatus::Pending {
            return Ok(DirectoryEntryOutcome {
                relative_path: planned.entry.relative_path,
                target_relative_path: planned.target_relative_path,
                action: planned.action,
                duplicate: true,
            });
        }
        if planned.action == DirectoryConflictAction::Skip {
            let staging_path =
                staging_path_for(&self.files_staging_directory(transfer_id)?, relative_path);
            let _ = self.files.remove_file(&staging_path);
            plan.entries[index].status = DirectoryEntryStatus::Skipped;
            self.store
                .update_directory_plan(transfer_id, &plan, now_ms)?;
            return Ok(DirectoryEntryOutcome {
                relative_path: planned.entry.relative_path,
                target_relative_path: planned.target_relative_path,
                action: planned.action,
                duplicate: false,
            });
        }
        self.verify_entry_complete(transfer_id, &planned.entry, now_ms)?;
        let staging_path =
            staging_path_for(&self.files_staging_directory(transfer_id)?, relative_path);
        self.files
            .set_permissions(
                &staging_path,
                planned.entry.metadata.readonly,
                planned.entry.metadata.executable,
            )
            .map_err(TransferError::from_platform)?;
        let target_path = self.target_path(&plan.root_name, &planned.target_relative_path)?;
        if let Some(parent) = target_path.parent() {
            self.files
                .create_dir_all(parent)
                .map_err(TransferError::from_platform)?;
        }
        let target_metadata = self
            .files
            .metadata(&target_path)
            .map_err(TransferError::from_platform)?;
        if target_metadata
            .as_ref()
            .is_some_and(|metadata| metadata.kind == FileEntryKind::Symlink)
        {
            return Err(symlink_refused());
        }
        match planned.action {
            DirectoryConflictAction::Replace => self
                .files
                .atomic_replace(&staging_path, &target_path)
                .map_err(TransferError::from_platform)?,
            DirectoryConflictAction::CreateFile | DirectoryConflictAction::KeepBoth => {
                if target_metadata.is_some() {
                    return Err(TransferError::new(
                        TransferErrorCode::PathCollision,
                        "directory target appeared after conflict planning",
                        false,
                    ));
                }
                self.files
                    .atomic_move(&staging_path, &target_path)
                    .map_err(TransferError::from_platform)?;
            }
            DirectoryConflictAction::CreateDirectory
            | DirectoryConflictAction::MergeDirectory
            | DirectoryConflictAction::Skip => {
                return Err(TransferError::invalid(
                    "directory action is invalid for a file entry",
                ));
            }
        }
        self.files
            .set_permissions(
                &target_path,
                planned.entry.metadata.readonly,
                planned.entry.metadata.executable,
            )
            .map_err(TransferError::from_platform)?;
        plan.entries[index].status = DirectoryEntryStatus::Committed;
        self.store
            .update_directory_plan(transfer_id, &plan, now_ms)?;
        Ok(DirectoryEntryOutcome {
            relative_path: planned.entry.relative_path,
            target_relative_path: planned.target_relative_path,
            action: planned.action,
            duplicate: false,
        })
    }

    /// Completes the directory after every file is committed or skipped.
    pub fn complete(
        &self,
        transfer_id: &str,
        now_ms: i64,
    ) -> Result<DirectoryCompleteOutcome, TransferError> {
        let job = self.store.directory_job(transfer_id)?;
        if job.state != TransferState::Transferring {
            return Err(TransferError::invalid(
                "directory transfer is not receiving data",
            ));
        }
        let plan = job
            .plan
            .as_ref()
            .ok_or_else(|| TransferError::invalid("directory transfer is not accepted"))?;
        for planned in &plan.entries {
            if planned.entry.kind == DirectoryEntryKind::File
                && planned.status == DirectoryEntryStatus::Pending
            {
                return Err(TransferError::new(
                    TransferErrorCode::ResumeCheckpointInvalid,
                    "directory file entry is not complete",
                    true,
                ));
            }
        }
        self.store.verifying_directory_job(transfer_id, now_ms)?;
        let root_path = self.target_path(&plan.root_name, "")?;
        self.files
            .create_dir_all(&root_path)
            .map_err(TransferError::from_platform)?;
        for planned in &plan.entries {
            if planned.entry.kind == DirectoryEntryKind::Directory {
                let path = self.target_path(&plan.root_name, &planned.target_relative_path)?;
                let metadata = self
                    .files
                    .metadata(&path)
                    .map_err(TransferError::from_platform)?;
                if metadata
                    .as_ref()
                    .is_some_and(|metadata| metadata.kind != FileEntryKind::Directory)
                {
                    let _ = self.store.fail_directory_job(
                        transfer_id,
                        TransferErrorCode::PathCollision,
                        now_ms,
                    );
                    return Err(TransferError::new(
                        TransferErrorCode::PathCollision,
                        "directory target is not a directory",
                        false,
                    ));
                }
                self.files
                    .create_dir_all(&path)
                    .map_err(TransferError::from_platform)?;
            }
        }
        self.store.committing_directory_job(transfer_id, now_ms)?;
        for planned in &plan.entries {
            if planned.entry.kind == DirectoryEntryKind::Directory {
                let path = self.target_path(&plan.root_name, &planned.target_relative_path)?;
                self.files
                    .set_permissions(&path, planned.entry.metadata.readonly, true)
                    .map_err(TransferError::from_platform)?;
            }
        }
        self.files
            .set_permissions(&root_path, job.manifest.root_metadata.readonly, true)
            .map_err(TransferError::from_platform)?;
        let final_path = root_path.to_string_lossy().into_owned();
        self.store
            .complete_directory_job(transfer_id, &final_path, now_ms)?;
        let _ = self
            .files
            .remove_tree(&self.staging_directory(transfer_id)?);
        let committed_files = plan
            .entries
            .iter()
            .filter(|entry| entry.status == DirectoryEntryStatus::Committed)
            .count();
        let skipped_files = plan
            .entries
            .iter()
            .filter(|entry| entry.status == DirectoryEntryStatus::Skipped)
            .count();
        Ok(DirectoryCompleteOutcome {
            snapshot: snapshot(self.store.directory_job(transfer_id)?),
            committed_files,
            skipped_files,
        })
    }

    /// Returns a UI-neutral snapshot.
    pub fn snapshot(&self, transfer_id: &str) -> Result<DirectoryTransferSnapshot, TransferError> {
        Ok(snapshot(self.store.directory_job(transfer_id)?))
    }

    /// Cleans expired staging and terminal metadata. Final files remain untouched.
    pub fn sweep_retention(
        &self,
        now_ms: i64,
        policy: TransferRetentionPolicy,
    ) -> Result<DirectoryRetentionSweep, TransferError> {
        let policy = validate_retention_policy(policy)?;
        let plan = plan_retention(&self.store.retention_tasks()?, now_ms, policy);
        self.apply_retention(now_ms, &plan)
    }

    /// Returns the same-volume staging file for one source path.
    pub fn staging_path(
        &self,
        transfer_id: &str,
        relative_path: &str,
    ) -> Result<PathBuf, TransferError> {
        super::super::validate_identifier("transfer id", transfer_id)?;
        validate_directory_path(relative_path)?;
        Ok(staging_path_for(
            &self.files_staging_directory(transfer_id)?,
            relative_path,
        ))
    }

    fn apply_retention(
        &self,
        now_ms: i64,
        plan: &RetentionPlan,
    ) -> Result<DirectoryRetentionSweep, TransferError> {
        let mut result = DirectoryRetentionSweep::default();
        for decision in &plan.decisions {
            let transfer_id = &decision.task.transfer_id;
            let mut cleanup_failed = false;
            if decision.clean_staging {
                let staging_removed = self
                    .files
                    .remove_tree(&self.staging_directory(transfer_id)?)
                    .map_err(TransferError::from_platform);
                match staging_removed
                    .and_then(|()| self.store.clear_transfer_checkpoints(transfer_id, now_ms))
                {
                    Ok(()) => result.cleaned_staging += 1,
                    Err(_) => {
                        cleanup_failed = true;
                        result.failures.push(DirectoryRetentionFailure {
                            transfer_id: transfer_id.clone(),
                            error_code: TransferErrorCode::StorageIoError,
                        });
                    }
                }
            }
            if decision.purge_metadata && !cleanup_failed {
                match self.store.purge_terminal_job(transfer_id) {
                    Ok(true) => result.purged_metadata += 1,
                    Ok(false) => {}
                    Err(_) => result.failures.push(DirectoryRetentionFailure {
                        transfer_id: transfer_id.clone(),
                        error_code: TransferErrorCode::StorageIoError,
                    }),
                }
            }
        }
        Ok(result)
    }

    fn verify_entry_complete(
        &self,
        transfer_id: &str,
        entry: &DirectoryEntry,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let staging_path = staging_path_for(
            &self.files_staging_directory(transfer_id)?,
            &entry.relative_path,
        );
        let size = self
            .files
            .metadata_size(&staging_path)
            .map_err(TransferError::from_platform)?
            .ok_or_else(|| {
                TransferError::new(
                    TransferErrorCode::ResumeCheckpointInvalid,
                    "directory staging file is missing",
                    false,
                )
            })?;
        if size != entry.size {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "directory staging size does not match the manifest",
                true,
            ));
        }
        let checkpoint_bytes = self
            .store
            .directory_chunks(transfer_id)?
            .iter()
            .filter(|chunk| chunk.relative_path == entry.relative_path)
            .map(|chunk| chunk.offset.saturating_add(u64::from(chunk.length)))
            .max()
            .unwrap_or(0);
        if checkpoint_bytes != size {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "directory checkpoints do not cover the complete file",
                false,
            ));
        }
        let digest = digest_file(&self.files, &staging_path, size)?;
        if entry.blake3.as_deref() != Some(digest.as_str()) {
            self.store.fail_directory_job(
                transfer_id,
                TransferErrorCode::FileHashMismatch,
                now_ms,
            )?;
            return Err(TransferError::new(
                TransferErrorCode::FileHashMismatch,
                "directory file checksum does not match the manifest",
                true,
            ));
        }
        Ok(())
    }

    fn existing_entries(&self, root_name: &str) -> Result<Vec<DestinationEntry>, TransferError> {
        let root_key = super::super::path_collision_key(root_name);
        for name in self
            .files
            .directory_entries(&self.destination_root)
            .map_err(TransferError::from_platform)?
        {
            if name != root_name && super::super::path_collision_key(&name) == root_key {
                return Err(TransferError::new(
                    TransferErrorCode::PathCollision,
                    "directory root differs only by case from an existing path",
                    false,
                ));
            }
        }
        let root_path = self.destination_root.join(root_name);
        let Some(metadata) = self
            .files
            .metadata(&root_path)
            .map_err(TransferError::from_platform)?
        else {
            return Ok(Vec::new());
        };
        match metadata.kind {
            FileEntryKind::Directory => {
                let mut entries = Vec::new();
                scan_existing(&self.files, &root_path, "", &mut entries)?;
                Ok(entries)
            }
            FileEntryKind::File => Err(TransferError::new(
                TransferErrorCode::PathCollision,
                "directory root collides with an existing file",
                false,
            )),
            FileEntryKind::Symlink => Err(symlink_refused()),
            FileEntryKind::Other => Err(TransferError::new(
                TransferErrorCode::UnsupportedEntryKind,
                "directory root has an unsupported kind",
                false,
            )),
        }
    }

    fn target_path(&self, root_name: &str, relative_path: &str) -> Result<PathBuf, TransferError> {
        let mut path = self.destination_root.join(root_name);
        if !relative_path.is_empty() {
            validate_directory_path(relative_path)?;
            path.push(relative_path);
        }
        Ok(path)
    }

    fn staging_directory(&self, transfer_id: &str) -> Result<PathBuf, TransferError> {
        super::super::validate_identifier("transfer id", transfer_id)?;
        Ok(self
            .destination_root
            .join(".covio")
            .join("staging")
            .join(transfer_id))
    }

    fn files_staging_directory(&self, transfer_id: &str) -> Result<PathBuf, TransferError> {
        Ok(self.staging_directory(transfer_id)?.join("files"))
    }
}

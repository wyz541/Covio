//! Receiver-side staging, checkpoint validation, and atomic commit.

use super::store::{StoredChunk, TransferJob, TransferStore};
use super::{
    FileChunkFrame, FileTransferOffer, TRANSFER_CHUNK_SIZE, TransferDirection, TransferError,
    TransferErrorCode, TransferState, TransferSummary, blake3_hex, validate_file_name,
};
use covio_platform::FileStore;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

/// Verification inputs supplied after a mobile app returns to the foreground.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ForegroundCheck {
    /// Whether the peer is still in the trusted-device registry.
    pub trusted: bool,
    /// Current peer device identifier.
    pub peer_device_id: String,
    /// Current manifest digest supplied by the peer.
    pub manifest_hash: String,
    /// Whether a fresh connection liveness check succeeded.
    pub connection_alive: bool,
}

/// One valid resume checkpoint.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResumePlan {
    /// Current durable job snapshot.
    pub job: TransferJob,
    /// Byte offset from which data can resume.
    pub offset: u64,
    /// Same-volume staging file.
    pub staging_path: PathBuf,
}

/// Result of one received chunk.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiveOutcome {
    /// Durable byte count after this operation.
    pub durable_bytes: u64,
    /// Whether the exact chunk was already durable.
    pub duplicate: bool,
}

/// UI-neutral state snapshot for one transfer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TransferSnapshot {
    /// Durable job.
    pub job: TransferJob,
    /// Receiver-visible summary.
    pub summary: TransferSummary,
    /// Completion percentage from 0 through 100.
    pub progress_percent: u8,
}

/// Receiver-side file transfer engine.
pub struct TransferReceiver<F: FileStore> {
    store: TransferStore,
    files: F,
    destination_root: PathBuf,
}

impl<F: FileStore> TransferReceiver<F> {
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

    /// Persists an incoming offer and exposes its summary to the local user.
    pub fn receive_offer(
        &self,
        offer: &FileTransferOffer,
        now_ms: i64,
    ) -> Result<TransferSnapshot, TransferError> {
        offer.validate()?;
        offer.ensure_live(now_ms)?;
        self.files
            .create_dir_all(&self.destination_root)
            .map_err(TransferError::from_platform)?;
        let job = self.store.create_job(
            offer,
            &offer.manifest.sender_device_id,
            TransferDirection::Receive,
            now_ms,
        )?;
        Ok(snapshot(job))
    }

    /// Accepts an offer and prepares a same-volume staging file.
    pub fn accept(
        &self,
        transfer_id: &str,
        resume_from: u64,
        now_ms: i64,
    ) -> Result<ResumePlan, TransferError> {
        let job = self.store.accept(transfer_id, resume_from, now_ms)?;
        let staging_path = self.staging_path(transfer_id)?;
        let result = if resume_from == 0 {
            self.files
                .create_dir_all(&self.staging_directory(transfer_id)?)
                .map_err(TransferError::from_platform)?;
            let _ = self
                .files
                .remove_file(&staging_path)
                .map_err(TransferError::from_platform)?;
            self.files
                .write_atomic(&staging_path, b"")
                .map_err(TransferError::from_platform)
        } else {
            self.verify_checkpoint(transfer_id)
        };
        if let Err(error) = result {
            let _ = self.store.fail(transfer_id, error.code(), now_ms);
            return Err(error);
        }
        Ok(ResumePlan {
            job,
            offset: resume_from,
            staging_path,
        })
    }

    /// Resumes a background-deferred receiver after peer revalidation.
    pub fn resume(
        &self,
        transfer_id: &str,
        resume_from: u64,
        now_ms: i64,
    ) -> Result<ResumePlan, TransferError> {
        let job = self.store.resume(transfer_id, now_ms)?;
        if resume_from != job.durable_bytes {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "peer checkpoint does not match the receiver",
                false,
            ));
        }
        self.verify_checkpoint(transfer_id)?;
        Ok(ResumePlan {
            job,
            offset: resume_from,
            staging_path: self.staging_path(transfer_id)?,
        })
    }

    /// Receives one chunk, verifies it, appends it, and persists its checkpoint.
    pub fn receive_chunk(
        &self,
        transfer_id: &str,
        frame: &FileChunkFrame,
        now_ms: i64,
    ) -> Result<ReceiveOutcome, TransferError> {
        let job = self.store.job(transfer_id)?;
        if job.direction != TransferDirection::Receive {
            return Err(TransferError::invalid("job is not receiving a file"));
        }
        frame.verify()?;
        let chunk_size = u64::from(job.manifest.chunk_size);
        if !frame.offset.is_multiple_of(chunk_size) {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "chunk offset is not aligned",
                false,
            ));
        }
        let chunk_index = frame.offset / chunk_size;
        if let Some(existing) = self.store.chunk(transfer_id, chunk_index)? {
            if existing.offset == frame.offset
                && existing.length == frame.length
                && existing.blake3 == frame.blake3
            {
                return Ok(ReceiveOutcome {
                    durable_bytes: job.durable_bytes,
                    duplicate: true,
                });
            }
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "duplicate chunk conflicts with the checkpoint",
                false,
            ));
        }
        if frame.offset != job.durable_bytes {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "chunk is not the next durable chunk",
                true,
            ));
        }
        let expected_length = (job.total_bytes - job.durable_bytes).min(chunk_size);
        if u64::from(frame.length) != expected_length {
            return Err(TransferError::invalid(
                "chunk length is not expected for its offset",
            ));
        }
        let staging_path = self.staging_path(transfer_id)?;
        let staged_size = self
            .files
            .metadata_size(&staging_path)
            .map_err(TransferError::from_platform)?
            .ok_or_else(|| {
                TransferError::new(
                    TransferErrorCode::ResumeCheckpointInvalid,
                    "staging file is missing",
                    false,
                )
            })?;
        if staged_size != job.durable_bytes {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "staging size does not match the checkpoint",
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
            .ok_or_else(|| TransferError::invalid("chunk end offset overflow"))?;
        if appended != expected_end {
            let _ = self
                .store
                .fail(transfer_id, TransferErrorCode::StorageIoError, now_ms);
            return Err(TransferError::storage(
                "staging append size mismatch",
                false,
            ));
        }
        let checkpoint = match self.store.checkpoint_chunk(
            transfer_id,
            chunk_index,
            frame.offset,
            frame.length,
            &frame.blake3,
            now_ms,
        ) {
            Ok(checkpoint) => checkpoint,
            Err(error) => {
                let _ = self.store.fail(transfer_id, error.code(), now_ms);
                return Err(error);
            }
        };
        Ok(ReceiveOutcome {
            durable_bytes: checkpoint.durable_bytes,
            duplicate: !checkpoint.inserted,
        })
    }

    /// Verifies and atomically commits a fully received file.
    pub fn complete(
        &self,
        transfer_id: &str,
        now_ms: i64,
    ) -> Result<TransferSnapshot, TransferError> {
        let job = self.store.job(transfer_id)?;
        if job.direction != TransferDirection::Receive {
            return Err(TransferError::invalid("job is not receiving a file"));
        }
        if job.state != TransferState::Transferring {
            return Err(TransferError::invalid("transfer is not receiving data"));
        }
        if job.durable_bytes != job.total_bytes {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "transfer checkpoint is incomplete",
                true,
            ));
        }
        self.store.verifying(transfer_id, now_ms)?;
        let staging_path = self.staging_path(transfer_id)?;
        let actual_digest = self.digest_file(&staging_path)?;
        if actual_digest != job.manifest.blake3 {
            let _ = self
                .store
                .fail(transfer_id, TransferErrorCode::FileHashMismatch, now_ms);
            return Err(TransferError::new(
                TransferErrorCode::FileHashMismatch,
                "staged file checksum does not match the manifest",
                true,
            ));
        }
        self.store.committing(transfer_id, now_ms)?;
        let final_path = self.final_path(&job.manifest.file_name)?;
        if self
            .files
            .exists(&final_path)
            .map_err(TransferError::from_platform)?
        {
            let _ = self
                .store
                .fail(transfer_id, TransferErrorCode::TargetExists, now_ms);
            return Err(TransferError::new(
                TransferErrorCode::TargetExists,
                "final destination already exists",
                false,
            ));
        }
        if let Some(parent) = final_path.parent() {
            self.files
                .create_dir_all(parent)
                .map_err(TransferError::from_platform)?;
        }
        if let Err(error) = self.files.atomic_move(&staging_path, &final_path) {
            let error = TransferError::from_platform(error);
            let _ = self.store.fail(transfer_id, error.code(), now_ms);
            return Err(error);
        }
        let final_path_text = final_path.to_string_lossy().into_owned();
        self.store.complete(transfer_id, &final_path_text, now_ms)?;
        let _ = self
            .files
            .remove_tree(&self.staging_directory(transfer_id)?);
        Ok(snapshot(self.store.job(transfer_id)?))
    }

    /// Pauses a transfer without deleting its staging file.
    pub fn pause(&self, transfer_id: &str, now_ms: i64) -> Result<ResumePlan, TransferError> {
        self.store.pause(transfer_id, now_ms)?;
        let job = self.store.job(transfer_id)?;
        Ok(ResumePlan {
            offset: job.durable_bytes,
            staging_path: self.staging_path(transfer_id)?,
            job,
        })
    }

    /// Records a mobile background transition and its durable checkpoint.
    pub fn background(&self, transfer_id: &str, now_ms: i64) -> Result<ResumePlan, TransferError> {
        self.store.background(transfer_id, now_ms)?;
        let job = self.store.job(transfer_id)?;
        Ok(ResumePlan {
            offset: job.durable_bytes,
            staging_path: self.staging_path(transfer_id)?,
            job,
        })
    }

    /// Revalidates peer identity, manifest, staging bytes, and connection liveness.
    pub fn foreground(
        &self,
        transfer_id: &str,
        check: &ForegroundCheck,
        now_ms: i64,
    ) -> Result<ResumePlan, TransferError> {
        let job = self.store.job(transfer_id)?;
        if check.peer_device_id != job.peer_device_id
            || check.manifest_hash != job.manifest_hash
            || !check.trusted
        {
            let _ = self
                .store
                .fail(transfer_id, TransferErrorCode::PeerIdentityChanged, now_ms);
            return Err(TransferError::new(
                TransferErrorCode::PeerIdentityChanged,
                "peer identity or manifest changed",
                false,
            ));
        }
        if !check.connection_alive {
            let _ = self.store.waiting_network(transfer_id, now_ms);
            return Err(TransferError::new(
                TransferErrorCode::TransportOffline,
                "connection liveness check failed",
                true,
            ));
        }
        self.verify_checkpoint(transfer_id)?;
        let resumed = self.store.resume(transfer_id, now_ms)?;
        Ok(ResumePlan {
            offset: resumed.durable_bytes,
            staging_path: self.staging_path(transfer_id)?,
            job: resumed,
        })
    }

    /// Cancels a transfer while retaining its staging file for retention cleanup.
    pub fn cancel(&self, transfer_id: &str, now_ms: i64) -> Result<(), TransferError> {
        self.store
            .cancel(transfer_id, TransferDirection::Receive, now_ms)
    }

    /// Returns a UI-neutral snapshot.
    pub fn snapshot(&self, transfer_id: &str) -> Result<TransferSnapshot, TransferError> {
        Ok(snapshot(self.store.job(transfer_id)?))
    }

    /// Returns the same-volume staging file for one transfer.
    pub fn staging_path(&self, transfer_id: &str) -> Result<PathBuf, TransferError> {
        super::validate_identifier("transfer id", transfer_id)?;
        let job = self.store.job(transfer_id)?;
        Ok(self
            .staging_directory(transfer_id)?
            .join(format!("{}.part", job.manifest.file_name)))
    }

    fn staging_directory(&self, transfer_id: &str) -> Result<PathBuf, TransferError> {
        super::validate_identifier("transfer id", transfer_id)?;
        Ok(self
            .destination_root
            .join(".covio")
            .join("staging")
            .join(transfer_id))
    }

    fn final_path(&self, file_name: &str) -> Result<PathBuf, TransferError> {
        validate_file_name(file_name)?;
        Ok(self.destination_root.join(file_name))
    }

    fn verify_checkpoint(&self, transfer_id: &str) -> Result<(), TransferError> {
        let job = self.store.job(transfer_id)?;
        if job.durable_bytes > job.total_bytes {
            return Err(invalid_checkpoint("checkpoint exceeds the file size"));
        }
        let staging_path = self.staging_path(transfer_id)?;
        let staged_size = self
            .files
            .metadata_size(&staging_path)
            .map_err(TransferError::from_platform)?
            .ok_or_else(|| invalid_checkpoint("staging file is missing"))?;
        if staged_size != job.durable_bytes {
            return Err(invalid_checkpoint(
                "staging size does not match the checkpoint",
            ));
        }
        let chunks = self.store.chunks(transfer_id)?;
        let mut expected_offset = 0_u64;
        for chunk in &chunks {
            verify_stored_chunk(&self.files, &staging_path, chunk, expected_offset)?;
            expected_offset = expected_offset
                .checked_add(u64::from(chunk.length))
                .ok_or_else(|| invalid_checkpoint("checkpoint offset overflow"))?;
        }
        if expected_offset != job.durable_bytes {
            return Err(invalid_checkpoint("chunk checkpoints are not contiguous"));
        }
        Ok(())
    }

    fn digest_file(&self, path: &Path) -> Result<String, TransferError> {
        let size = self
            .files
            .metadata_size(path)
            .map_err(TransferError::from_platform)?
            .ok_or_else(|| invalid_checkpoint("staged file is missing"))?;
        let mut hasher = blake3::Hasher::new();
        let mut offset = 0_u64;
        while offset < size {
            let length = usize::try_from((size - offset).min(u64::from(TRANSFER_CHUNK_SIZE)))
                .map_err(|_| TransferError::internal("digest chunk length overflow"))?;
            let bytes = self
                .files
                .read_range(path, offset, length)
                .map_err(TransferError::from_platform)?
                .ok_or_else(|| invalid_checkpoint("staged file disappeared"))?;
            if bytes.len() != length {
                return Err(TransferError::storage(
                    "staged file read was incomplete",
                    true,
                ));
            }
            hasher.update(&bytes);
            offset = offset
                .checked_add(length as u64)
                .ok_or_else(|| TransferError::internal("digest offset overflow"))?;
        }
        Ok(hasher.finalize().to_hex().to_string())
    }
}

fn verify_stored_chunk<F: FileStore>(
    files: &F,
    staging_path: &Path,
    chunk: &StoredChunk,
    expected_offset: u64,
) -> Result<(), TransferError> {
    if chunk.offset != expected_offset {
        return Err(invalid_checkpoint("chunk checkpoint is not contiguous"));
    }
    let length =
        usize::try_from(chunk.length).map_err(|_| invalid_checkpoint("chunk length is invalid"))?;
    let bytes = files
        .read_range(staging_path, chunk.offset, length)
        .map_err(TransferError::from_platform)?
        .ok_or_else(|| invalid_checkpoint("staging file is missing"))?;
    if bytes.len() != length || blake3_hex(&bytes) != chunk.blake3 {
        return Err(invalid_checkpoint("durable chunk checksum is invalid"));
    }
    Ok(())
}

fn invalid_checkpoint(message: &'static str) -> TransferError {
    TransferError::new(TransferErrorCode::ResumeCheckpointInvalid, message, false)
}

fn snapshot(job: TransferJob) -> TransferSnapshot {
    let progress_percent = job
        .durable_bytes
        .saturating_mul(100)
        .checked_div(job.total_bytes)
        .and_then(|value| u8::try_from(value).ok())
        .unwrap_or(100);
    TransferSnapshot {
        summary: TransferSummary::from(&job.manifest),
        job,
        progress_percent,
    }
}

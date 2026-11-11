//! Sender-side durable task and bounded window orchestration.

use super::receiver::TransferSnapshot;
use super::store::TransferStore;
use super::{
    FileChunkFrame, FileTransferOffer, SenderSource, TransferDirection, TransferError,
    TransferSummary,
};
use covio_platform::FileStore;
use std::path::{Path, PathBuf};

/// Sender-side transfer task backed by SQLite.
pub struct TransferSender<F: FileStore> {
    store: TransferStore,
    files: F,
    source_path: PathBuf,
    source: SenderSource<F>,
}

impl<F: FileStore + Clone> TransferSender<F> {
    /// Creates one sender job and its short-lived offer.
    pub fn create(
        store: TransferStore,
        files: F,
        source_path: impl Into<PathBuf>,
        transfer_id: impl Into<String>,
        sender_device_id: impl Into<String>,
        peer_device_id: &str,
        now_ms: i64,
    ) -> Result<(Self, FileTransferOffer, TransferSnapshot), TransferError> {
        let source_path = source_path.into();
        let source = SenderSource::open(
            files.clone(),
            source_path.clone(),
            transfer_id,
            sender_device_id,
            now_ms,
        )?;
        let offer = FileTransferOffer::new(source.manifest().clone())?;
        let job = store.create_job(&offer, peer_device_id, TransferDirection::Send, now_ms)?;
        let snapshot = sender_snapshot(job);
        Ok((
            Self {
                store,
                files,
                source_path,
                source,
            },
            offer,
            snapshot,
        ))
    }

    /// Reopens a durable sender job and resumes its source offset.
    pub fn reopen(
        store: TransferStore,
        files: F,
        source_path: impl Into<PathBuf>,
        transfer_id: &str,
    ) -> Result<Self, TransferError> {
        let source_path = source_path.into();
        let job = store.job(transfer_id)?;
        if job.direction != TransferDirection::Send {
            return Err(TransferError::invalid("job is not a sender transfer"));
        }
        let source = SenderSource::resume(
            files.clone(),
            source_path.clone(),
            job.manifest,
            job.durable_bytes,
        )?;
        Ok(Self {
            store,
            files,
            source_path,
            source,
        })
    }

    /// Accepts the remote checkpoint and moves the sender into data transfer.
    pub fn accept(&mut self, durable_bytes: u64, now_ms: i64) -> Result<u64, TransferError> {
        let job = self
            .store
            .accept(&self.source.manifest().transfer_id, durable_bytes, now_ms)?;
        if durable_bytes != self.source.durable_offset() {
            self.source = SenderSource::resume(
                self.files.clone(),
                self.source_path.clone(),
                job.manifest,
                durable_bytes,
            )?;
        }
        Ok(self.source.durable_offset())
    }

    /// Reads the next bounded 8 MiB window.
    pub fn read_window(&mut self) -> Result<Vec<FileChunkFrame>, TransferError> {
        self.source.read_window()
    }

    /// Persists a receiver ACK before reading the next window.
    pub fn acknowledge(&mut self, durable_bytes: u64, now_ms: i64) -> Result<(), TransferError> {
        self.source.acknowledge(durable_bytes)?;
        self.store
            .sender_checkpoint(&self.source.manifest().transfer_id, durable_bytes, now_ms)
    }

    /// Cancels the sender task without deleting the source file.
    pub fn cancel(&self, now_ms: i64) -> Result<(), TransferError> {
        self.store.cancel(
            &self.source.manifest().transfer_id,
            TransferDirection::Send,
            now_ms,
        )
    }

    /// Marks the sender task complete after the receiver confirms verification.
    pub fn complete(&self, now_ms: i64) -> Result<TransferSnapshot, TransferError> {
        let transfer_id = &self.source.manifest().transfer_id;
        self.store.sender_complete(transfer_id, now_ms)?;
        self.snapshot()
    }

    /// Returns the current sender manifest.
    pub fn manifest(&self) -> &super::FileManifest {
        self.source.manifest()
    }

    /// Returns the current UI-neutral sender snapshot.
    pub fn snapshot(&self) -> Result<TransferSnapshot, TransferError> {
        Ok(sender_snapshot(
            self.store.job(&self.source.manifest().transfer_id)?,
        ))
    }

    /// Returns the source path used by this sender task.
    pub fn source_path(&self) -> &Path {
        &self.source_path
    }
}

fn sender_snapshot(job: super::TransferJob) -> TransferSnapshot {
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

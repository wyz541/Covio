//! SQLite persistence for transfer jobs, checkpoints, and audit events.

use super::{
    DirectoryChunkCheckpoint, DirectoryConflictPlan, DirectoryConflictPolicy, DirectoryManifest,
    DirectoryTransferOffer, FileChunkFrame, FileManifest, FileTransferOffer, RetentionTask,
    TransferDirection, TransferError, TransferErrorCode, TransferState,
};
use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::{Arc, Mutex, MutexGuard};

const TRANSFER_DATABASE_VERSION: i64 = 2;

/// One durable transfer job.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct TransferJob {
    /// Transfer identifier.
    pub transfer_id: String,
    /// Offer identifier.
    pub offer_id: String,
    /// Other device identifier.
    pub peer_device_id: String,
    /// Direction from this device.
    pub direction: TransferDirection,
    /// Current durable state.
    pub state: TransferState,
    /// File manifest snapshot.
    pub manifest: FileManifest,
    /// Canonical manifest digest.
    pub manifest_hash: String,
    /// Durable byte count.
    pub durable_bytes: u64,
    /// Total file size.
    pub total_bytes: u64,
    /// Creation time in Unix milliseconds.
    pub created_at_ms: i64,
    /// Last update time in Unix milliseconds.
    pub updated_at_ms: i64,
    /// Stable failure code when present.
    pub error_code: Option<String>,
    /// Final committed path when present.
    pub final_path: Option<String>,
}

/// One durable directory transfer job.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryTransferJob {
    /// Transfer identifier.
    pub transfer_id: String,
    /// Offer identifier.
    pub offer_id: String,
    /// Other device identifier.
    pub peer_device_id: String,
    /// Direction from this device.
    pub direction: TransferDirection,
    /// Current durable state.
    pub state: TransferState,
    /// Directory manifest snapshot.
    pub manifest: DirectoryManifest,
    /// Canonical manifest digest.
    pub manifest_hash: String,
    /// Accepted conflict policy.
    pub conflict_policy: Option<DirectoryConflictPolicy>,
    /// Accepted conflict plan.
    pub plan: Option<DirectoryConflictPlan>,
    /// Durable file byte count.
    pub durable_bytes: u64,
    /// Total file bytes.
    pub total_bytes: u64,
    /// Creation time in Unix milliseconds.
    pub created_at_ms: i64,
    /// Last update time in Unix milliseconds.
    pub updated_at_ms: i64,
    /// Stable failure code when present.
    pub error_code: Option<String>,
    /// Final root path when present.
    pub final_path: Option<String>,
}

/// One durable chunk checkpoint.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StoredChunk {
    /// Zero-based chunk index.
    pub chunk_index: u64,
    /// Absolute file offset.
    pub offset: u64,
    /// Payload length.
    pub length: u32,
    /// Payload BLAKE3 digest.
    pub blake3: String,
}

/// One audit event.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransferEvent {
    /// Monotonic event identifier.
    pub event_id: i64,
    /// Transfer identifier.
    pub transfer_id: String,
    /// Stable event type.
    pub event_type: String,
    /// Event time in Unix milliseconds.
    pub created_at_ms: i64,
}

/// Result of a durable chunk checkpoint.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ChunkCheckpoint {
    pub inserted: bool,
    pub durable_bytes: u64,
}

/// SQLite-backed transfer checkpoint store.
#[derive(Clone)]
pub struct TransferStore {
    connection: Arc<Mutex<Connection>>,
}

impl TransferStore {
    /// Opens a transfer database and applies the versioned schema.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, TransferError> {
        let path = path.as_ref();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|_| {
                TransferError::storage("transfer database directory creation failed", true)
            })?;
        }
        let connection = Connection::open(path)
            .map_err(|_| TransferError::storage("transfer database open failed", true))?;
        Self::from_connection(connection)
    }

    /// Opens an in-memory database for tests and ephemeral workers.
    pub fn open_in_memory() -> Result<Self, TransferError> {
        let connection = Connection::open_in_memory()
            .map_err(|_| TransferError::storage("transfer database open failed", true))?;
        Self::from_connection(connection)
    }

    fn from_connection(connection: Connection) -> Result<Self, TransferError> {
        connection
            .busy_timeout(std::time::Duration::from_secs(5))
            .map_err(db_error)?;
        let journal_mode: String = connection
            .query_row("PRAGMA journal_mode = WAL", [], |row| row.get(0))
            .map_err(db_error)?;
        if !journal_mode.eq_ignore_ascii_case("wal") && !journal_mode.eq_ignore_ascii_case("memory")
        {
            return Err(TransferError::storage(
                "transfer database could not enable WAL",
                false,
            ));
        }
        let existing_version: i64 = connection
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .map_err(db_error)?;
        if existing_version > TRANSFER_DATABASE_VERSION {
            return Err(TransferError::storage(
                "transfer database version is unsupported",
                false,
            ));
        }
        connection
            .execute_batch(
                "PRAGMA foreign_keys = ON;
                 PRAGMA synchronous = FULL;
                 CREATE TABLE IF NOT EXISTS transfer_jobs (
                     transfer_id TEXT PRIMARY KEY,
                     offer_id TEXT NOT NULL UNIQUE,
                     peer_device_id TEXT NOT NULL,
                     direction TEXT NOT NULL,
                     state TEXT NOT NULL,
                     manifest_json TEXT NOT NULL,
                     manifest_hash TEXT NOT NULL,
                     durable_bytes INTEGER NOT NULL,
                     total_bytes INTEGER NOT NULL,
                     created_at_ms INTEGER NOT NULL,
                     updated_at_ms INTEGER NOT NULL,
                     error_code TEXT,
                     final_path TEXT
                 ) STRICT;
                 CREATE TABLE IF NOT EXISTS transfer_chunks (
                     transfer_id TEXT NOT NULL REFERENCES transfer_jobs(transfer_id) ON DELETE CASCADE,
                     chunk_index INTEGER NOT NULL,
                     offset INTEGER NOT NULL,
                     length INTEGER NOT NULL,
                     blake3 TEXT NOT NULL,
                     durable INTEGER NOT NULL,
                     PRIMARY KEY (transfer_id, chunk_index),
                     UNIQUE (transfer_id, offset)
                 ) STRICT;
                 CREATE TABLE IF NOT EXISTS transfer_events (
                     event_id INTEGER PRIMARY KEY AUTOINCREMENT,
                     transfer_id TEXT NOT NULL REFERENCES transfer_jobs(transfer_id) ON DELETE CASCADE,
                     event_type TEXT NOT NULL,
                     created_at_ms INTEGER NOT NULL
                 ) STRICT;
                 CREATE INDEX IF NOT EXISTS transfer_events_by_job
                     ON transfer_events(transfer_id, event_id);
                 CREATE TABLE IF NOT EXISTS directory_jobs (
                     transfer_id TEXT PRIMARY KEY,
                     offer_id TEXT NOT NULL UNIQUE,
                     peer_device_id TEXT NOT NULL,
                     direction TEXT NOT NULL,
                     state TEXT NOT NULL,
                     manifest_json TEXT NOT NULL,
                     manifest_hash TEXT NOT NULL,
                     conflict_policy TEXT,
                     plan_json TEXT,
                     durable_bytes INTEGER NOT NULL,
                     total_bytes INTEGER NOT NULL,
                     created_at_ms INTEGER NOT NULL,
                     updated_at_ms INTEGER NOT NULL,
                     error_code TEXT,
                     final_path TEXT
                 ) STRICT;
                 CREATE TABLE IF NOT EXISTS directory_chunks (
                     transfer_id TEXT NOT NULL REFERENCES directory_jobs(transfer_id) ON DELETE CASCADE,
                     relative_path TEXT NOT NULL,
                     chunk_index INTEGER NOT NULL,
                     offset INTEGER NOT NULL,
                     length INTEGER NOT NULL,
                     blake3 TEXT NOT NULL,
                     durable INTEGER NOT NULL,
                     PRIMARY KEY (transfer_id, relative_path, chunk_index),
                     UNIQUE (transfer_id, relative_path, offset)
                 ) STRICT;
                 CREATE TABLE IF NOT EXISTS directory_events (
                     event_id INTEGER PRIMARY KEY AUTOINCREMENT,
                     transfer_id TEXT NOT NULL REFERENCES directory_jobs(transfer_id) ON DELETE CASCADE,
                     event_type TEXT NOT NULL,
                     created_at_ms INTEGER NOT NULL
                 ) STRICT;
                 CREATE INDEX IF NOT EXISTS directory_events_by_job
                     ON directory_events(transfer_id, event_id);",
            )
            .map_err(db_error)?;
        let version: i64 = connection
            .query_row("PRAGMA user_version", [], |row| row.get(0))
            .map_err(db_error)?;
        if version < TRANSFER_DATABASE_VERSION {
            connection
                .pragma_update(None, "user_version", TRANSFER_DATABASE_VERSION)
                .map_err(db_error)?;
        }
        Ok(Self {
            connection: Arc::new(Mutex::new(connection)),
        })
    }

    /// Creates one durable offer job.
    pub fn create_job(
        &self,
        offer: &FileTransferOffer,
        peer_device_id: &str,
        direction: TransferDirection,
        now_ms: i64,
    ) -> Result<TransferJob, TransferError> {
        offer.validate()?;
        if peer_device_id.trim().is_empty() {
            return Err(TransferError::invalid("peer device id is empty"));
        }
        let state = match direction {
            TransferDirection::Send => TransferState::OfferWaiting,
            TransferDirection::Receive => TransferState::AwaitingAcceptance,
        };
        let manifest_json = serde_json::to_string(&offer.manifest)
            .map_err(|_| TransferError::internal("manifest serialization failed"))?;
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        transaction
            .execute(
                "INSERT INTO transfer_jobs (
                     transfer_id, offer_id, peer_device_id, direction, state,
                     manifest_json, manifest_hash, durable_bytes, total_bytes,
                     created_at_ms, updated_at_ms, error_code, final_path
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 0, ?8, ?9, ?9, NULL, NULL)",
                params![
                    offer.manifest.transfer_id,
                    offer.offer_id,
                    peer_device_id,
                    direction.as_str(),
                    state.as_str(),
                    manifest_json,
                    offer.manifest_hash,
                    i64::try_from(offer.manifest.size)
                        .map_err(|_| TransferError::invalid("file size is too large"))?,
                    now_ms,
                ],
            )
            .map_err(|error| map_insert_error(error, "transfer offer already exists"))?;
        transaction
            .execute(
                "INSERT INTO transfer_events (transfer_id, event_type, created_at_ms)
                 VALUES (?1, ?2, ?3)",
                params![offer.manifest.transfer_id, "offer_created", now_ms],
            )
            .map_err(db_error)?;
        transaction.commit().map_err(db_error)?;
        drop(connection);
        self.job(&offer.manifest.transfer_id)
    }

    /// Creates one durable directory offer job.
    pub fn create_directory_job(
        &self,
        offer: &DirectoryTransferOffer,
        peer_device_id: &str,
        direction: TransferDirection,
        now_ms: i64,
    ) -> Result<DirectoryTransferJob, TransferError> {
        offer.validate()?;
        if peer_device_id.trim().is_empty() {
            return Err(TransferError::invalid("peer device id is empty"));
        }
        let state = match direction {
            TransferDirection::Send => TransferState::OfferWaiting,
            TransferDirection::Receive => TransferState::AwaitingAcceptance,
        };
        let manifest_json = serde_json::to_string(&offer.manifest)
            .map_err(|_| TransferError::internal("directory manifest serialization failed"))?;
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        transaction
            .execute(
                "INSERT INTO directory_jobs (
                     transfer_id, offer_id, peer_device_id, direction, state,
                     manifest_json, manifest_hash, conflict_policy, plan_json,
                     durable_bytes, total_bytes, created_at_ms, updated_at_ms,
                     error_code, final_path
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, NULL, NULL, 0, ?8, ?9, ?9, NULL, NULL)",
                params![
                    offer.manifest.transfer_id,
                    offer.offer_id,
                    peer_device_id,
                    direction.as_str(),
                    state.as_str(),
                    manifest_json,
                    offer.manifest_hash,
                    i64::try_from(offer.manifest.total_bytes)
                        .map_err(|_| TransferError::invalid("directory size is too large"))?,
                    now_ms,
                ],
            )
            .map_err(|error| map_insert_error(error, "directory transfer offer already exists"))?;
        insert_directory_event(
            &transaction,
            &offer.manifest.transfer_id,
            "offer_created",
            now_ms,
        )?;
        transaction.commit().map_err(db_error)?;
        drop(connection);
        self.directory_job(&offer.manifest.transfer_id)
    }

    /// Returns one job.
    pub fn job(&self, transfer_id: &str) -> Result<TransferJob, TransferError> {
        let connection = self.lock()?;
        connection
            .query_row(
                "SELECT transfer_id, offer_id, peer_device_id, direction, state,
                        manifest_json, manifest_hash, durable_bytes, total_bytes,
                        created_at_ms, updated_at_ms, error_code, final_path
                 FROM transfer_jobs WHERE transfer_id = ?1",
                [transfer_id],
                job_from_row,
            )
            .optional()
            .map_err(db_error)?
            .ok_or_else(|| TransferError::invalid("transfer job does not exist"))
    }

    /// Lists recent jobs.
    pub fn jobs(&self, limit: u32) -> Result<Vec<TransferJob>, TransferError> {
        let connection = self.lock()?;
        let mut statement = connection
            .prepare(
                "SELECT transfer_id, offer_id, peer_device_id, direction, state,
                        manifest_json, manifest_hash, durable_bytes, total_bytes,
                        created_at_ms, updated_at_ms, error_code, final_path
                 FROM transfer_jobs ORDER BY updated_at_ms DESC, transfer_id ASC LIMIT ?1",
            )
            .map_err(db_error)?;
        let jobs = statement
            .query_map([i64::from(limit)], job_from_row)
            .map_err(db_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_error)?;
        Ok(jobs)
    }

    /// Returns one directory job.
    pub fn directory_job(&self, transfer_id: &str) -> Result<DirectoryTransferJob, TransferError> {
        let connection = self.lock()?;
        query_directory_job(&connection, transfer_id)
    }

    /// Lists recent directory jobs.
    pub fn directory_jobs(&self, limit: u32) -> Result<Vec<DirectoryTransferJob>, TransferError> {
        let connection = self.lock()?;
        let mut statement = connection
            .prepare(
                "SELECT transfer_id, offer_id, peer_device_id, direction, state,
                        manifest_json, manifest_hash, conflict_policy, plan_json,
                        durable_bytes, total_bytes, created_at_ms, updated_at_ms,
                        error_code, final_path
                 FROM directory_jobs ORDER BY updated_at_ms DESC, transfer_id ASC LIMIT ?1",
            )
            .map_err(db_error)?;
        statement
            .query_map([i64::from(limit)], directory_job_from_row)
            .map_err(db_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_error)
    }

    /// Accepts a directory offer with a persisted conflict plan.
    pub fn accept_directory_job(
        &self,
        transfer_id: &str,
        policy: DirectoryConflictPolicy,
        plan: &DirectoryConflictPlan,
        now_ms: i64,
    ) -> Result<DirectoryTransferJob, TransferError> {
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let job = query_directory_job(&transaction, transfer_id)?;
        if job.state != TransferState::AwaitingAcceptance {
            return Err(TransferError::invalid(
                "directory transfer is not waiting for acceptance",
            ));
        }
        if now_ms > job.manifest.expires_at_ms {
            transaction
                .execute(
                    "UPDATE directory_jobs
                     SET state = ?2, error_code = ?3, updated_at_ms = ?4
                     WHERE transfer_id = ?1",
                    params![
                        transfer_id,
                        TransferState::Expired.as_str(),
                        TransferErrorCode::TransferOfferExpired.as_str(),
                        now_ms,
                    ],
                )
                .map_err(db_error)?;
            transaction.commit().map_err(db_error)?;
            drop(connection);
            return Err(TransferError::new(
                TransferErrorCode::TransferOfferExpired,
                "directory transfer offer has expired",
                false,
            ));
        }
        if plan.root_name != job.manifest.root_name {
            return Err(TransferError::invalid(
                "directory conflict plan does not match the manifest",
            ));
        }
        let plan_json = serde_json::to_string(plan)
            .map_err(|_| TransferError::internal("directory plan serialization failed"))?;
        transaction
            .execute(
                "UPDATE directory_jobs
                 SET state = ?2, conflict_policy = ?3, plan_json = ?4,
                     error_code = NULL, updated_at_ms = ?5
                 WHERE transfer_id = ?1",
                params![
                    transfer_id,
                    TransferState::Transferring.as_str(),
                    conflict_policy_wire(policy),
                    plan_json,
                    now_ms,
                ],
            )
            .map_err(db_error)?;
        insert_directory_event(&transaction, transfer_id, "transfer_accepted", now_ms)?;
        transaction.commit().map_err(db_error)?;
        drop(connection);
        self.directory_job(transfer_id)
    }

    /// Pauses a live directory transfer.
    pub fn pause_directory_job(&self, transfer_id: &str, now_ms: i64) -> Result<(), TransferError> {
        self.directory_transition(
            transfer_id,
            &[TransferState::Transferring, TransferState::WaitingNetwork],
            TransferState::Paused,
            TransferErrorCode::BackgroundSuspended,
            now_ms,
        )
    }

    /// Resumes a paused directory transfer.
    pub fn resume_directory_job(
        &self,
        transfer_id: &str,
        now_ms: i64,
    ) -> Result<DirectoryTransferJob, TransferError> {
        self.directory_transition(
            transfer_id,
            &[
                TransferState::Transferring,
                TransferState::Paused,
                TransferState::BackgroundDeferred,
                TransferState::WaitingNetwork,
            ],
            TransferState::Transferring,
            TransferErrorCode::Internal,
            now_ms,
        )?;
        self.directory_job(transfer_id)
    }

    /// Cancels a non-terminal directory transfer.
    pub fn cancel_directory_job(
        &self,
        transfer_id: &str,
        direction: TransferDirection,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let code = match direction {
            TransferDirection::Send => TransferErrorCode::CancelledBySender,
            TransferDirection::Receive => TransferErrorCode::CancelledByReceiver,
        };
        self.directory_transition(
            transfer_id,
            &[
                TransferState::OfferWaiting,
                TransferState::AwaitingAcceptance,
                TransferState::Transferring,
                TransferState::Paused,
                TransferState::BackgroundDeferred,
                TransferState::WaitingNetwork,
                TransferState::Verifying,
            ],
            TransferState::Cancelled,
            code,
            now_ms,
        )
    }

    /// Marks a directory transfer as failed.
    pub fn fail_directory_job(
        &self,
        transfer_id: &str,
        code: TransferErrorCode,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let connection = self.lock()?;
        let changed = connection
            .execute(
                "UPDATE directory_jobs
                 SET state = ?2, error_code = ?3, updated_at_ms = ?4
                 WHERE transfer_id = ?1",
                params![
                    transfer_id,
                    TransferState::Failed.as_str(),
                    code.as_str(),
                    now_ms
                ],
            )
            .map_err(db_error)?;
        if changed == 0 {
            return Err(TransferError::invalid(
                "directory transfer job does not exist",
            ));
        }
        insert_directory_event(&connection, transfer_id, "transfer_failed", now_ms)
    }

    /// Marks a directory transfer as verifying all committed files.
    pub fn verifying_directory_job(
        &self,
        transfer_id: &str,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        self.directory_transition(
            transfer_id,
            &[TransferState::Transferring],
            TransferState::Verifying,
            TransferErrorCode::Internal,
            now_ms,
        )
    }

    /// Marks a directory transfer as committing the root tree.
    pub fn committing_directory_job(
        &self,
        transfer_id: &str,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        self.directory_transition(
            transfer_id,
            &[TransferState::Verifying],
            TransferState::Committing,
            TransferErrorCode::Internal,
            now_ms,
        )
    }

    /// Marks one directory transfer complete.
    pub fn complete_directory_job(
        &self,
        transfer_id: &str,
        final_path: &str,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let job = query_directory_job(&transaction, transfer_id)?;
        if job.state != TransferState::Committing {
            return Err(TransferError::invalid(
                "directory transfer is not committing",
            ));
        }
        transaction
            .execute(
                "UPDATE directory_jobs
                 SET state = ?2, error_code = NULL, final_path = ?3, updated_at_ms = ?4
                 WHERE transfer_id = ?1",
                params![
                    transfer_id,
                    TransferState::Completed.as_str(),
                    final_path,
                    now_ms,
                ],
            )
            .map_err(db_error)?;
        insert_directory_event(&transaction, transfer_id, "transfer_completed", now_ms)?;
        transaction.commit().map_err(db_error)
    }

    /// Replaces the durable conflict plan after an entry commits.
    pub fn update_directory_plan(
        &self,
        transfer_id: &str,
        plan: &DirectoryConflictPlan,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let plan_json = serde_json::to_string(plan)
            .map_err(|_| TransferError::internal("directory plan serialization failed"))?;
        let connection = self.lock()?;
        let changed = connection
            .execute(
                "UPDATE directory_jobs SET plan_json = ?2, updated_at_ms = ?3
                 WHERE transfer_id = ?1",
                params![transfer_id, plan_json, now_ms],
            )
            .map_err(db_error)?;
        if changed == 0 {
            return Err(TransferError::invalid(
                "directory transfer job does not exist",
            ));
        }
        Ok(())
    }

    /// Accepts an offer at a validated durable offset.
    pub fn accept(
        &self,
        transfer_id: &str,
        durable_bytes: u64,
        now_ms: i64,
    ) -> Result<TransferJob, TransferError> {
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let job = transaction
            .query_row(
                "SELECT transfer_id, offer_id, peer_device_id, direction, state,
                        manifest_json, manifest_hash, durable_bytes, total_bytes,
                        created_at_ms, updated_at_ms, error_code, final_path
                 FROM transfer_jobs WHERE transfer_id = ?1",
                [transfer_id],
                job_from_row,
            )
            .optional()
            .map_err(db_error)?
            .ok_or_else(|| TransferError::invalid("transfer job does not exist"))?;
        if !matches!(
            job.state,
            TransferState::OfferWaiting | TransferState::AwaitingAcceptance
        ) {
            return Err(TransferError::invalid(
                "transfer is not waiting for acceptance",
            ));
        }
        if now_ms > job.manifest.expires_at_ms {
            transaction
                .execute(
                    "UPDATE transfer_jobs
                     SET state = ?2, error_code = ?3, updated_at_ms = ?4
                     WHERE transfer_id = ?1",
                    params![
                        transfer_id,
                        TransferState::Expired.as_str(),
                        TransferErrorCode::TransferOfferExpired.as_str(),
                        now_ms,
                    ],
                )
                .map_err(db_error)?;
            transaction.commit().map_err(db_error)?;
            drop(connection);
            return Err(TransferError::new(
                TransferErrorCode::TransferOfferExpired,
                "transfer offer has expired",
                false,
            ));
        }
        if durable_bytes > job.total_bytes
            || (!durable_bytes.is_multiple_of(u64::from(job.manifest.chunk_size))
                && durable_bytes != job.total_bytes)
        {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "acceptance checkpoint is invalid",
                false,
            ));
        }
        transaction
            .execute(
                "UPDATE transfer_jobs
                 SET state = ?2, durable_bytes = ?3, error_code = NULL, updated_at_ms = ?4
                 WHERE transfer_id = ?1",
                params![
                    transfer_id,
                    TransferState::Transferring.as_str(),
                    i64::try_from(durable_bytes)
                        .map_err(|_| TransferError::invalid("checkpoint is too large"))?,
                    now_ms,
                ],
            )
            .map_err(db_error)?;
        insert_event(&transaction, transfer_id, "transfer_accepted", now_ms)?;
        transaction.commit().map_err(db_error)?;
        drop(connection);
        self.job(transfer_id)
    }

    /// Rejects an offer.
    pub fn reject(&self, transfer_id: &str, now_ms: i64) -> Result<(), TransferError> {
        self.transition(
            transfer_id,
            &[
                TransferState::OfferWaiting,
                TransferState::AwaitingAcceptance,
            ],
            TransferState::Rejected,
            TransferErrorCode::OfferRejected,
            now_ms,
        )
    }

    /// Pauses a live transfer.
    pub fn pause(&self, transfer_id: &str, now_ms: i64) -> Result<(), TransferError> {
        self.transition(
            transfer_id,
            &[TransferState::Transferring, TransferState::WaitingNetwork],
            TransferState::Paused,
            TransferErrorCode::BackgroundSuspended,
            now_ms,
        )
    }

    /// Persists one acknowledged sender offset.
    pub fn sender_checkpoint(
        &self,
        transfer_id: &str,
        durable_bytes: u64,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let connection = self.lock()?;
        let job = query_job(&connection, transfer_id)?;
        if job.direction != TransferDirection::Send || job.state != TransferState::Transferring {
            return Err(TransferError::invalid("sender transfer is not active"));
        }
        if durable_bytes < job.durable_bytes || durable_bytes > job.total_bytes {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "sender checkpoint is invalid",
                false,
            ));
        }
        connection
            .execute(
                "UPDATE transfer_jobs SET durable_bytes = ?2, updated_at_ms = ?3
                 WHERE transfer_id = ?1",
                params![
                    transfer_id,
                    i64::try_from(durable_bytes)
                        .map_err(|_| TransferError::invalid("sender checkpoint is too large"))?,
                    now_ms,
                ],
            )
            .map_err(db_error)?;
        insert_event(&connection, transfer_id, "sender_checkpoint", now_ms)?;
        Ok(())
    }

    /// Marks one sender complete after the receiver reports verification.
    pub fn sender_complete(&self, transfer_id: &str, now_ms: i64) -> Result<(), TransferError> {
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let job = query_job(&transaction, transfer_id)?;
        if job.direction != TransferDirection::Send
            || job.state != TransferState::Transferring
            || job.durable_bytes != job.total_bytes
        {
            return Err(TransferError::invalid("sender transfer is not active"));
        }
        transaction
            .execute(
                "UPDATE transfer_jobs
                 SET state = ?2, durable_bytes = total_bytes, error_code = NULL, updated_at_ms = ?3
                 WHERE transfer_id = ?1",
                params![transfer_id, TransferState::Completed.as_str(), now_ms],
            )
            .map_err(db_error)?;
        insert_event(&transaction, transfer_id, "transfer_completed", now_ms)?;
        transaction.commit().map_err(db_error)?;
        Ok(())
    }

    /// Marks a transfer as deferred by the mobile operating system.
    pub fn background(&self, transfer_id: &str, now_ms: i64) -> Result<(), TransferError> {
        self.transition(
            transfer_id,
            &[TransferState::Transferring],
            TransferState::BackgroundDeferred,
            TransferErrorCode::BackgroundSuspended,
            now_ms,
        )
    }

    /// Marks a transfer as waiting for network connectivity.
    pub fn waiting_network(&self, transfer_id: &str, now_ms: i64) -> Result<(), TransferError> {
        self.transition(
            transfer_id,
            &[
                TransferState::Transferring,
                TransferState::BackgroundDeferred,
            ],
            TransferState::WaitingNetwork,
            TransferErrorCode::TransportOffline,
            now_ms,
        )
    }

    /// Resumes a paused or network-waiting transfer.
    pub fn resume(&self, transfer_id: &str, now_ms: i64) -> Result<TransferJob, TransferError> {
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let job = query_job(&transaction, transfer_id)?;
        if !matches!(
            job.state,
            TransferState::Paused
                | TransferState::BackgroundDeferred
                | TransferState::WaitingNetwork
        ) {
            return Err(TransferError::invalid(
                "transfer cannot resume from its current state",
            ));
        }
        transaction
            .execute(
                "UPDATE transfer_jobs
                 SET state = ?2, error_code = NULL, updated_at_ms = ?3
                 WHERE transfer_id = ?1",
                params![transfer_id, TransferState::Transferring.as_str(), now_ms],
            )
            .map_err(db_error)?;
        insert_event(&transaction, transfer_id, "transfer_resumed", now_ms)?;
        transaction.commit().map_err(db_error)?;
        drop(connection);
        self.job(transfer_id)
    }

    /// Cancels a non-terminal transfer.
    pub fn cancel(
        &self,
        transfer_id: &str,
        direction: TransferDirection,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let code = match direction {
            TransferDirection::Send => TransferErrorCode::CancelledBySender,
            TransferDirection::Receive => TransferErrorCode::CancelledByReceiver,
        };
        self.transition(
            transfer_id,
            &[
                TransferState::OfferWaiting,
                TransferState::AwaitingAcceptance,
                TransferState::Transferring,
                TransferState::Paused,
                TransferState::BackgroundDeferred,
                TransferState::WaitingNetwork,
            ],
            TransferState::Cancelled,
            code,
            now_ms,
        )
    }

    /// Marks the receiver as verifying the complete file.
    pub fn verifying(&self, transfer_id: &str, now_ms: i64) -> Result<(), TransferError> {
        self.transition(
            transfer_id,
            &[TransferState::Transferring],
            TransferState::Verifying,
            TransferErrorCode::Internal,
            now_ms,
        )
    }

    /// Marks the receiver as committing the verified file.
    pub fn committing(&self, transfer_id: &str, now_ms: i64) -> Result<(), TransferError> {
        self.transition(
            transfer_id,
            &[TransferState::Verifying],
            TransferState::Committing,
            TransferErrorCode::Internal,
            now_ms,
        )
    }

    /// Marks one transfer complete.
    pub fn complete(
        &self,
        transfer_id: &str,
        final_path: &str,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let job = query_job(&transaction, transfer_id)?;
        if job.state != TransferState::Committing {
            return Err(TransferError::invalid("transfer is not committing"));
        }
        transaction
            .execute(
                "UPDATE transfer_jobs
                 SET state = ?2, error_code = NULL, final_path = ?3, updated_at_ms = ?4
                 WHERE transfer_id = ?1",
                params![
                    transfer_id,
                    TransferState::Completed.as_str(),
                    final_path,
                    now_ms
                ],
            )
            .map_err(db_error)?;
        insert_event(&transaction, transfer_id, "transfer_completed", now_ms)?;
        transaction.commit().map_err(db_error)?;
        Ok(())
    }

    /// Marks one transfer failed with a stable error code.
    pub fn fail(
        &self,
        transfer_id: &str,
        code: TransferErrorCode,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let connection = self.lock()?;
        let changed = connection
            .execute(
                "UPDATE transfer_jobs
                 SET state = ?2, error_code = ?3, updated_at_ms = ?4
                 WHERE transfer_id = ?1",
                params![
                    transfer_id,
                    TransferState::Failed.as_str(),
                    code.as_str(),
                    now_ms
                ],
            )
            .map_err(db_error)?;
        if changed == 0 {
            return Err(TransferError::invalid("transfer job does not exist"));
        }
        insert_event(&connection, transfer_id, "transfer_failed", now_ms)?;
        Ok(())
    }

    /// Records one durable directory file chunk.
    pub(crate) fn checkpoint_directory_chunk(
        &self,
        transfer_id: &str,
        relative_path: &str,
        frame: &FileChunkFrame,
        now_ms: i64,
    ) -> Result<ChunkCheckpoint, TransferError> {
        let chunk_index = frame.offset / u64::from(super::TRANSFER_CHUNK_SIZE);
        let offset = frame.offset;
        let length = frame.length;
        let blake3 = frame.blake3.as_str();
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let job = query_directory_job(&transaction, transfer_id)?;
        if job.state != TransferState::Transferring {
            return Err(TransferError::invalid(
                "directory transfer is not receiving data",
            ));
        }
        let entry = job
            .manifest
            .entries
            .iter()
            .find(|entry| entry.relative_path == relative_path)
            .ok_or_else(|| TransferError::invalid("directory file entry does not exist"))?;
        let entry_progress =
            query_directory_entry_progress(&transaction, transfer_id, relative_path)?;
        if let Some(existing) =
            query_directory_chunk(&transaction, transfer_id, relative_path, chunk_index)
                .map_err(db_error)?
        {
            if existing.offset == offset
                && existing.length == length
                && existing.blake3 == blake3
                && offset.saturating_add(u64::from(length)) == entry_progress
            {
                return Ok(ChunkCheckpoint {
                    inserted: false,
                    durable_bytes: job.durable_bytes,
                });
            }
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "duplicate directory chunk does not match the checkpoint",
                false,
            ));
        }
        if offset != entry_progress {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "directory chunk offset does not match the durable checkpoint",
                true,
            ));
        }
        let next_offset = offset
            .checked_add(u64::from(length))
            .ok_or_else(|| TransferError::invalid("directory chunk offset overflow"))?;
        if next_offset > entry.size {
            return Err(TransferError::invalid(
                "directory chunk exceeds the file size",
            ));
        }
        transaction
            .execute(
                "INSERT INTO directory_chunks (
                     transfer_id, relative_path, chunk_index, offset, length, blake3, durable
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1)",
                params![
                    transfer_id,
                    relative_path,
                    i64::try_from(chunk_index)
                        .map_err(|_| TransferError::invalid("chunk index is too large"))?,
                    i64::try_from(offset)
                        .map_err(|_| TransferError::invalid("chunk offset is too large"))?,
                    i64::from(length),
                    blake3,
                ],
            )
            .map_err(db_error)?;
        let next_total = job
            .durable_bytes
            .checked_add(u64::from(length))
            .ok_or_else(|| TransferError::invalid("directory durable byte count overflow"))?;
        transaction
            .execute(
                "UPDATE directory_jobs SET durable_bytes = ?2, updated_at_ms = ?3
                 WHERE transfer_id = ?1",
                params![
                    transfer_id,
                    i64::try_from(next_total)
                        .map_err(|_| TransferError::invalid("durable byte count is too large"))?,
                    now_ms,
                ],
            )
            .map_err(db_error)?;
        transaction.commit().map_err(db_error)?;
        Ok(ChunkCheckpoint {
            inserted: true,
            durable_bytes: next_total,
        })
    }

    /// Lists durable directory chunk checkpoints.
    pub fn directory_chunks(
        &self,
        transfer_id: &str,
    ) -> Result<Vec<DirectoryChunkCheckpoint>, TransferError> {
        let connection = self.lock()?;
        let mut statement = connection
            .prepare(
                "SELECT relative_path, chunk_index, offset, length, blake3
                 FROM directory_chunks
                 WHERE transfer_id = ?1 AND durable = 1
                 ORDER BY relative_path ASC, chunk_index ASC",
            )
            .map_err(db_error)?;
        statement
            .query_map([transfer_id], |row| {
                Ok(DirectoryChunkCheckpoint {
                    relative_path: row.get(0)?,
                    chunk_index: row_u64(row, 1)?,
                    offset: row_u64(row, 2)?,
                    length: row_u32(row, 3)?,
                    blake3: row.get(4)?,
                })
            })
            .map_err(db_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_error)
    }

    /// Removes all chunk checkpoints for one task and resets durable bytes.
    pub fn clear_transfer_checkpoints(
        &self,
        transfer_id: &str,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        transaction
            .execute(
                "DELETE FROM transfer_chunks WHERE transfer_id = ?1",
                [transfer_id],
            )
            .map_err(db_error)?;
        transaction
            .execute(
                "DELETE FROM directory_chunks WHERE transfer_id = ?1",
                [transfer_id],
            )
            .map_err(db_error)?;
        transaction
            .execute(
                "UPDATE transfer_jobs SET durable_bytes = 0, updated_at_ms = ?2
                 WHERE transfer_id = ?1",
                params![transfer_id, now_ms],
            )
            .map_err(db_error)?;
        transaction
            .execute(
                "UPDATE directory_jobs SET durable_bytes = 0, updated_at_ms = ?2
                 WHERE transfer_id = ?1",
                params![transfer_id, now_ms],
            )
            .map_err(db_error)?;
        transaction.commit().map_err(db_error)
    }

    /// Returns retention tasks from file and directory databases.
    pub fn retention_tasks(&self) -> Result<Vec<RetentionTask>, TransferError> {
        let connection = self.lock()?;
        let mut statement = connection
            .prepare(
                "SELECT transfer_id, state, updated_at_ms FROM transfer_jobs
                 UNION ALL
                 SELECT transfer_id, state, updated_at_ms FROM directory_jobs
                 ORDER BY updated_at_ms ASC, transfer_id ASC",
            )
            .map_err(db_error)?;
        statement
            .query_map([], |row| {
                let state_text: String = row.get(1)?;
                let state = TransferState::from_str(&state_text).ok_or_else(|| {
                    rusqlite::Error::InvalidColumnType(1, state_text, rusqlite::types::Type::Text)
                })?;
                Ok(RetentionTask {
                    transfer_id: row.get(0)?,
                    state,
                    updated_at_ms: row.get(2)?,
                })
            })
            .map_err(db_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_error)
    }

    /// Removes terminal task metadata without touching any final destination path.
    pub fn purge_terminal_job(&self, transfer_id: &str) -> Result<bool, TransferError> {
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let file_changed = transaction
            .execute(
                "DELETE FROM transfer_jobs
                 WHERE transfer_id = ?1
                   AND state IN ('completed', 'rejected', 'expired', 'cancelled', 'failed')",
                [transfer_id],
            )
            .map_err(db_error)?;
        let directory_changed = transaction
            .execute(
                "DELETE FROM directory_jobs
                 WHERE transfer_id = ?1
                   AND state IN ('completed', 'rejected', 'expired', 'cancelled', 'failed')",
                [transfer_id],
            )
            .map_err(db_error)?;
        transaction.commit().map_err(db_error)?;
        Ok(file_changed + directory_changed > 0)
    }

    /// Records one durable chunk. Duplicate identical chunks become idempotent.
    pub(crate) fn checkpoint_chunk(
        &self,
        transfer_id: &str,
        chunk_index: u64,
        offset: u64,
        length: u32,
        blake3: &str,
        now_ms: i64,
    ) -> Result<ChunkCheckpoint, TransferError> {
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let job = query_job(&transaction, transfer_id)?;
        if job.state != TransferState::Transferring {
            return Err(TransferError::invalid("transfer is not receiving data"));
        }
        if let Some(existing) =
            query_chunk(&transaction, transfer_id, chunk_index).map_err(db_error)?
        {
            if existing.offset == offset
                && existing.length == length
                && existing.blake3 == blake3
                && offset.saturating_add(u64::from(length)) == job.durable_bytes
            {
                return Ok(ChunkCheckpoint {
                    inserted: false,
                    durable_bytes: job.durable_bytes,
                });
            }
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "duplicate chunk does not match the durable checkpoint",
                false,
            ));
        }
        if offset != job.durable_bytes {
            return Err(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "chunk offset does not match the durable checkpoint",
                true,
            ));
        }
        let next_offset = offset
            .checked_add(u64::from(length))
            .ok_or_else(|| TransferError::invalid("chunk offset overflow"))?;
        if next_offset > job.total_bytes {
            return Err(TransferError::invalid("chunk exceeds the file size"));
        }
        transaction
            .execute(
                "INSERT INTO transfer_chunks (
                     transfer_id, chunk_index, offset, length, blake3, durable
                 ) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
                params![
                    transfer_id,
                    i64::try_from(chunk_index)
                        .map_err(|_| TransferError::invalid("chunk index is too large"))?,
                    i64::try_from(offset)
                        .map_err(|_| TransferError::invalid("chunk offset is too large"))?,
                    i64::from(length),
                    blake3,
                ],
            )
            .map_err(db_error)?;
        transaction
            .execute(
                "UPDATE transfer_jobs SET durable_bytes = ?2, updated_at_ms = ?3
                 WHERE transfer_id = ?1",
                params![
                    transfer_id,
                    i64::try_from(next_offset)
                        .map_err(|_| TransferError::invalid("checkpoint is too large"))?,
                    now_ms,
                ],
            )
            .map_err(db_error)?;
        insert_event(&transaction, transfer_id, "checkpoint", now_ms)?;
        transaction.commit().map_err(db_error)?;
        Ok(ChunkCheckpoint {
            inserted: true,
            durable_bytes: next_offset,
        })
    }

    /// Returns one persisted chunk.
    pub(crate) fn chunk(
        &self,
        transfer_id: &str,
        chunk_index: u64,
    ) -> Result<Option<StoredChunk>, TransferError> {
        let connection = self.lock()?;
        query_chunk(&connection, transfer_id, chunk_index).map_err(db_error)
    }

    /// Returns all durable chunks in file order.
    pub fn chunks(&self, transfer_id: &str) -> Result<Vec<StoredChunk>, TransferError> {
        let connection = self.lock()?;
        let mut statement = connection
            .prepare(
                "SELECT chunk_index, offset, length, blake3
                 FROM transfer_chunks
                 WHERE transfer_id = ?1 AND durable = 1
                 ORDER BY chunk_index ASC",
            )
            .map_err(db_error)?;
        let chunks = statement
            .query_map([transfer_id], |row| {
                Ok(StoredChunk {
                    chunk_index: row_u64(row, 0)?,
                    offset: row_u64(row, 1)?,
                    length: row_u32(row, 2)?,
                    blake3: row.get(3)?,
                })
            })
            .map_err(db_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_error)?;
        Ok(chunks)
    }

    /// Lists audit events for one job.
    pub fn events(&self, transfer_id: &str) -> Result<Vec<TransferEvent>, TransferError> {
        let connection = self.lock()?;
        let mut statement = connection
            .prepare(
                "SELECT event_id, transfer_id, event_type, created_at_ms
                 FROM transfer_events WHERE transfer_id = ?1 ORDER BY event_id ASC",
            )
            .map_err(db_error)?;
        let events = statement
            .query_map([transfer_id], |row| {
                Ok(TransferEvent {
                    event_id: row.get(0)?,
                    transfer_id: row.get(1)?,
                    event_type: row.get(2)?,
                    created_at_ms: row.get(3)?,
                })
            })
            .map_err(db_error)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(db_error)?;
        Ok(events)
    }

    fn transition(
        &self,
        transfer_id: &str,
        allowed: &[TransferState],
        next: TransferState,
        code: TransferErrorCode,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let job = query_job(&transaction, transfer_id)?;
        if !allowed.contains(&job.state) {
            return Err(TransferError::invalid(
                "transfer state transition is invalid",
            ));
        }
        transaction
            .execute(
                "UPDATE transfer_jobs
                 SET state = ?2, error_code = ?3, updated_at_ms = ?4
                 WHERE transfer_id = ?1",
                params![transfer_id, next.as_str(), code.as_str(), now_ms],
            )
            .map_err(db_error)?;
        insert_event(&transaction, transfer_id, next.as_str(), now_ms)?;
        transaction.commit().map_err(db_error)?;
        Ok(())
    }

    fn directory_transition(
        &self,
        transfer_id: &str,
        allowed: &[TransferState],
        next: TransferState,
        code: TransferErrorCode,
        now_ms: i64,
    ) -> Result<(), TransferError> {
        let mut connection = self.lock()?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let job = query_directory_job(&transaction, transfer_id)?;
        if !allowed.contains(&job.state) {
            return Err(TransferError::invalid(
                "directory transfer state transition is invalid",
            ));
        }
        transaction
            .execute(
                "UPDATE directory_jobs
                 SET state = ?2, error_code = ?3, updated_at_ms = ?4
                 WHERE transfer_id = ?1",
                params![transfer_id, next.as_str(), code.as_str(), now_ms],
            )
            .map_err(db_error)?;
        insert_directory_event(&transaction, transfer_id, next.as_str(), now_ms)?;
        transaction.commit().map_err(db_error)?;
        Ok(())
    }

    fn lock(&self) -> Result<MutexGuard<'_, Connection>, TransferError> {
        self.connection
            .lock()
            .map_err(|_| TransferError::internal("transfer database lock is poisoned"))
    }
}

fn query_job(connection: &Connection, transfer_id: &str) -> Result<TransferJob, TransferError> {
    connection
        .query_row(
            "SELECT transfer_id, offer_id, peer_device_id, direction, state,
                    manifest_json, manifest_hash, durable_bytes, total_bytes,
                    created_at_ms, updated_at_ms, error_code, final_path
             FROM transfer_jobs WHERE transfer_id = ?1",
            [transfer_id],
            job_from_row,
        )
        .optional()
        .map_err(db_error)?
        .ok_or_else(|| TransferError::invalid("transfer job does not exist"))
}

fn query_directory_job(
    connection: &Connection,
    transfer_id: &str,
) -> Result<DirectoryTransferJob, TransferError> {
    connection
        .query_row(
            "SELECT transfer_id, offer_id, peer_device_id, direction, state,
                    manifest_json, manifest_hash, conflict_policy, plan_json,
                    durable_bytes, total_bytes, created_at_ms, updated_at_ms,
                    error_code, final_path
             FROM directory_jobs WHERE transfer_id = ?1",
            [transfer_id],
            directory_job_from_row,
        )
        .optional()
        .map_err(db_error)?
        .ok_or_else(|| TransferError::invalid("directory transfer job does not exist"))
}

fn query_chunk(
    connection: &Connection,
    transfer_id: &str,
    chunk_index: u64,
) -> rusqlite::Result<Option<StoredChunk>> {
    connection
        .query_row(
            "SELECT chunk_index, offset, length, blake3
             FROM transfer_chunks
             WHERE transfer_id = ?1 AND chunk_index = ?2 AND durable = 1",
            params![
                transfer_id,
                i64::try_from(chunk_index)
                    .map_err(|_| rusqlite::Error::IntegralValueOutOfRange(1, i64::MAX))?,
            ],
            |row| {
                Ok(StoredChunk {
                    chunk_index: row_u64(row, 0)?,
                    offset: row_u64(row, 1)?,
                    length: row_u32(row, 2)?,
                    blake3: row.get(3)?,
                })
            },
        )
        .optional()
}

fn query_directory_chunk(
    connection: &Connection,
    transfer_id: &str,
    relative_path: &str,
    chunk_index: u64,
) -> rusqlite::Result<Option<DirectoryChunkCheckpoint>> {
    connection
        .query_row(
            "SELECT relative_path, chunk_index, offset, length, blake3
             FROM directory_chunks
             WHERE transfer_id = ?1 AND relative_path = ?2
               AND chunk_index = ?3 AND durable = 1",
            params![
                transfer_id,
                relative_path,
                i64::try_from(chunk_index)
                    .map_err(|_| rusqlite::Error::IntegralValueOutOfRange(2, i64::MAX))?,
            ],
            |row| {
                Ok(DirectoryChunkCheckpoint {
                    relative_path: row.get(0)?,
                    chunk_index: row_u64(row, 1)?,
                    offset: row_u64(row, 2)?,
                    length: row_u32(row, 3)?,
                    blake3: row.get(4)?,
                })
            },
        )
        .optional()
}

fn query_directory_entry_progress(
    connection: &Connection,
    transfer_id: &str,
    relative_path: &str,
) -> Result<u64, TransferError> {
    let value: i64 = connection
        .query_row(
            "SELECT COALESCE(MAX(offset + length), 0)
             FROM directory_chunks
             WHERE transfer_id = ?1 AND relative_path = ?2 AND durable = 1",
            params![transfer_id, relative_path],
            |row| row.get(0),
        )
        .map_err(db_error)?;
    u64::try_from(value)
        .map_err(|_| TransferError::storage("directory chunk progress is invalid", false))
}

fn job_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<TransferJob> {
    let direction_text: String = row.get(3)?;
    let direction = TransferDirection::from_str(&direction_text).ok_or_else(|| {
        rusqlite::Error::InvalidColumnType(3, direction_text, rusqlite::types::Type::Text)
    })?;
    let state_text: String = row.get(4)?;
    let state = TransferState::from_str(&state_text).ok_or_else(|| {
        rusqlite::Error::InvalidColumnType(4, state_text, rusqlite::types::Type::Text)
    })?;
    let manifest_json: String = row.get(5)?;
    let manifest: FileManifest = serde_json::from_str(&manifest_json).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(5, rusqlite::types::Type::Text, Box::new(error))
    })?;
    Ok(TransferJob {
        transfer_id: row.get(0)?,
        offer_id: row.get(1)?,
        peer_device_id: row.get(2)?,
        direction,
        state,
        manifest,
        manifest_hash: row.get(6)?,
        durable_bytes: row_u64(row, 7)?,
        total_bytes: row_u64(row, 8)?,
        created_at_ms: row.get(9)?,
        updated_at_ms: row.get(10)?,
        error_code: row.get(11)?,
        final_path: row.get(12)?,
    })
}

fn directory_job_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<DirectoryTransferJob> {
    let direction_text: String = row.get(3)?;
    let direction = TransferDirection::from_str(&direction_text).ok_or_else(|| {
        rusqlite::Error::InvalidColumnType(3, direction_text, rusqlite::types::Type::Text)
    })?;
    let state_text: String = row.get(4)?;
    let state = TransferState::from_str(&state_text).ok_or_else(|| {
        rusqlite::Error::InvalidColumnType(4, state_text, rusqlite::types::Type::Text)
    })?;
    let manifest_json: String = row.get(5)?;
    let manifest: DirectoryManifest = serde_json::from_str(&manifest_json).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(5, rusqlite::types::Type::Text, Box::new(error))
    })?;
    let conflict_policy_text: Option<String> = row.get(7)?;
    let conflict_policy = conflict_policy_text
        .as_deref()
        .map(conflict_policy_from_wire)
        .transpose()
        .map_err(|_| {
            rusqlite::Error::InvalidColumnType(
                7,
                "invalid conflict policy".to_owned(),
                rusqlite::types::Type::Text,
            )
        })?;
    let plan_json: Option<String> = row.get(8)?;
    let plan = plan_json
        .as_deref()
        .map(serde_json::from_str::<DirectoryConflictPlan>)
        .transpose()
        .map_err(|error| {
            rusqlite::Error::FromSqlConversionFailure(
                8,
                rusqlite::types::Type::Text,
                Box::new(error),
            )
        })?;
    Ok(DirectoryTransferJob {
        transfer_id: row.get(0)?,
        offer_id: row.get(1)?,
        peer_device_id: row.get(2)?,
        direction,
        state,
        manifest,
        manifest_hash: row.get(6)?,
        conflict_policy,
        plan,
        durable_bytes: row_u64(row, 9)?,
        total_bytes: row_u64(row, 10)?,
        created_at_ms: row.get(11)?,
        updated_at_ms: row.get(12)?,
        error_code: row.get(13)?,
        final_path: row.get(14)?,
    })
}

fn insert_event(
    connection: &Connection,
    transfer_id: &str,
    event_type: &str,
    now_ms: i64,
) -> Result<(), TransferError> {
    connection
        .execute(
            "INSERT INTO transfer_events (transfer_id, event_type, created_at_ms)
             VALUES (?1, ?2, ?3)",
            params![transfer_id, event_type, now_ms],
        )
        .map_err(db_error)?;
    Ok(())
}

fn insert_directory_event(
    connection: &Connection,
    transfer_id: &str,
    event_type: &str,
    now_ms: i64,
) -> Result<(), TransferError> {
    connection
        .execute(
            "INSERT INTO directory_events (transfer_id, event_type, created_at_ms)
             VALUES (?1, ?2, ?3)",
            params![transfer_id, event_type, now_ms],
        )
        .map_err(db_error)?;
    Ok(())
}

fn conflict_policy_wire(policy: DirectoryConflictPolicy) -> &'static str {
    match policy {
        DirectoryConflictPolicy::KeepBoth => "keep_both",
        DirectoryConflictPolicy::Replace => "replace",
        DirectoryConflictPolicy::Skip => "skip",
    }
}

fn conflict_policy_from_wire(value: &str) -> Result<DirectoryConflictPolicy, ()> {
    match value {
        "keep_both" => Ok(DirectoryConflictPolicy::KeepBoth),
        "replace" => Ok(DirectoryConflictPolicy::Replace),
        "skip" => Ok(DirectoryConflictPolicy::Skip),
        _ => Err(()),
    }
}

fn row_u64(row: &rusqlite::Row<'_>, index: usize) -> rusqlite::Result<u64> {
    let value: i64 = row.get(index)?;
    u64::try_from(value).map_err(|_| rusqlite::Error::IntegralValueOutOfRange(index, value))
}

fn row_u32(row: &rusqlite::Row<'_>, index: usize) -> rusqlite::Result<u32> {
    let value: i64 = row.get(index)?;
    u32::try_from(value).map_err(|_| rusqlite::Error::IntegralValueOutOfRange(index, value))
}

fn map_insert_error(error: rusqlite::Error, duplicate_message: &'static str) -> TransferError {
    if matches!(
        error,
        rusqlite::Error::SqliteFailure(
            rusqlite::ffi::Error {
                code: rusqlite::ErrorCode::ConstraintViolation,
                ..
            },
            _
        )
    ) {
        TransferError::invalid(duplicate_message)
    } else {
        db_error(error)
    }
}

fn db_error(_error: rusqlite::Error) -> TransferError {
    TransferError::storage("transfer database operation failed", true)
}

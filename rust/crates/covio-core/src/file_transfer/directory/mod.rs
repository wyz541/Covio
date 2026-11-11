//! Directory snapshots, conflict planning, verified resumes, and retention.

mod conflict;
mod manifest;
mod path;
mod receiver;
mod recovery;
mod retention;

pub use conflict::{
    DestinationEntry, DestinationEntryKind, DirectoryConflictAction, DirectoryConflictPlan,
    DirectoryConflictPolicy, DirectoryEntryStatus, PlannedDirectoryEntry, plan_directory_conflicts,
};
pub use manifest::{
    DirectoryEntry, DirectoryEntryKind, DirectoryManifest, DirectoryMetadata,
    DirectoryTransferOffer, DirectoryTransferSummary, MAX_DIRECTORY_ENTRIES,
    MAX_DIRECTORY_TOTAL_BYTES,
};
pub use path::{
    MAX_DIRECTORY_COMPONENT_BYTES, MAX_DIRECTORY_DEPTH, MAX_DIRECTORY_PATH_BYTES,
    path_collision_key, validate_component, validate_directory_path,
};
pub use receiver::{
    DirectoryAcceptResult, DirectoryChunkOutcome, DirectoryCompleteOutcome, DirectoryEntryOutcome,
    DirectoryRetentionFailure, DirectoryRetentionSweep, DirectoryTransferReceiver,
    DirectoryTransferSnapshot,
};
pub use recovery::{
    DirectoryChunkCheckpoint, DirectoryEntryResume, DirectoryResumePlan, staging_path_for,
    verify_directory_resume,
};
pub use retention::{
    CANCELLED_STAGING_RETENTION_MS, FAILED_STAGING_RETENTION_MS, PAUSED_STAGING_RETENTION_MS,
    RetentionDecision, RetentionPlan, RetentionTask, TERMINAL_METADATA_RETENTION_MS,
    TransferRetentionPolicy, is_terminal, plan_retention, validate_retention_policy,
};

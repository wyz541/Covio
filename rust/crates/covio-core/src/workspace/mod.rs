//! Workspace models, storage, wire format, and transfer state machine.

mod logic;
mod models;
mod store;
mod transfer;
mod wire;

pub use logic::{
    TOMBSTONE_RETENTION_DAYS, admit, classify, dedupe, display_order, expiry_epoch_seconds,
    is_tombstoned, is_valid_entry_id, live_tombstones, plan, suggested_text_name,
    total_local_bytes, with_tombstone,
};
pub use models::{
    WorkspaceAdmission, WorkspaceAvailability, WorkspaceEntry, WorkspaceKind, WorkspacePlan,
    WorkspacePolicy, WorkspacePutResult, WorkspaceState, WorkspaceTombstone,
    normalize_display_name, normalize_entry_id,
};
pub use store::WorkspaceStore;
pub use transfer::{
    WorkspaceBeginResult, WorkspaceChunkResult, WorkspaceCommitResult, WorkspaceDeleteResult,
    WorkspaceStat, WorkspaceTransferEngine,
};
pub use wire::{
    WorkspaceArgs, WorkspaceEntryParse, WorkspaceErrorCode, WorkspaceRequest, WorkspaceResponse,
    WorkspaceResponseData, WorkspaceWire,
};

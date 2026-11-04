//! Power, sleep, lid, and privileged helper contracts.

pub mod engine;
pub mod helper_lease;
pub mod helper_release;
pub mod helper_wire;
pub mod hold_leases;
pub mod models;
pub mod pmset;
pub mod policy;
pub mod ports;

pub use engine::{Engine, EngineDependencies};
pub use helper_lease::{
    HELPER_LEASE_MAX_ACTIVE as HELPER_BOOK_LEASE_MAX_ACTIVE, HelperLeaseBook, HelperLeaseSnapshot,
    HelperStatusPolling,
};
pub use helper_release::{HelperReleaseHandshake, HelperReleaseIdentity};
pub use hold_leases::HoldLeaseManager;
pub use models::*;
pub use pmset::{PmsetConfigParser, PmsetWakeLogParser};
pub use policy::decide;

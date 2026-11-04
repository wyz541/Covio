//! Helper-side bounded lease book.

use std::collections::BTreeMap;

/// Maximum active helper leases.
pub const HELPER_LEASE_MAX_ACTIVE: usize = 16;

/// Minimal helper lease snapshot.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct HelperLeaseSnapshot {
    /// Active lease ids sorted lexically.
    pub active_lease_ids: Vec<String>,
    /// Earliest expiration.
    pub expires_at_epoch_seconds: Option<i64>,
}

impl HelperLeaseSnapshot {
    /// Returns the active count.
    #[must_use]
    pub fn active_count(&self) -> usize {
        self.active_lease_ids.len()
    }

    /// Returns whether any lease is active.
    #[must_use]
    pub fn has_active_lease(&self) -> bool {
        !self.active_lease_ids.is_empty()
    }
}

/// Helper process lease ledger.
#[derive(Debug, Clone, Default)]
pub struct HelperLeaseBook {
    leases: BTreeMap<String, i64>,
}

impl HelperLeaseBook {
    /// Adds or renews a lease. `false` means the active limit was reached.
    pub fn upsert(
        &mut self,
        lease_id: &str,
        now_epoch_seconds: i64,
        expires_at_epoch_seconds: i64,
    ) -> bool {
        if lease_id.trim().is_empty() {
            return false;
        }
        self.prune(now_epoch_seconds);
        if !self.leases.contains_key(lease_id) && self.leases.len() >= HELPER_LEASE_MAX_ACTIVE {
            return false;
        }
        if expires_at_epoch_seconds <= now_epoch_seconds {
            self.leases.remove(lease_id);
        } else {
            self.leases
                .insert(lease_id.to_owned(), expires_at_epoch_seconds);
        }
        true
    }

    /// Releases one lease.
    pub fn release(&mut self, lease_id: &str, now_epoch_seconds: i64) -> HelperLeaseSnapshot {
        self.prune(now_epoch_seconds);
        self.leases.remove(lease_id);
        self.snapshot()
    }

    /// Removes expired leases.
    pub fn prune(&mut self, now_epoch_seconds: i64) -> HelperLeaseSnapshot {
        self.leases
            .retain(|_, expires_at| *expires_at > now_epoch_seconds);
        self.snapshot()
    }

    /// Clears all leases.
    pub fn clear(&mut self) -> HelperLeaseSnapshot {
        self.leases.clear();
        self.snapshot()
    }

    /// Returns the current snapshot.
    #[must_use]
    pub fn snapshot(&self) -> HelperLeaseSnapshot {
        HelperLeaseSnapshot {
            active_lease_ids: self.leases.keys().cloned().collect(),
            expires_at_epoch_seconds: self.leases.values().min().copied(),
        }
    }
}

/// Helper install status polling cadence.
pub struct HelperStatusPolling;

impl HelperStatusPolling {
    /// Maximum wait in milliseconds.
    pub const TIMEOUT_MILLIS: i64 = 5_000;
    /// Poll interval in milliseconds.
    pub const POLL_INTERVAL_MILLIS: i64 = 200;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renew_updates_one_lease_without_changing_another() {
        let mut book = HelperLeaseBook::default();
        assert!(book.upsert("a", 10, 70));
        assert!(book.upsert("b", 10, 20));
        assert!(book.upsert("b", 15, 75));
        let snapshot = book.snapshot();
        assert_eq!(snapshot.active_lease_ids, ["a", "b"]);
        assert_eq!(snapshot.expires_at_epoch_seconds, Some(70));
    }

    #[test]
    fn prune_removes_only_expired_leases() {
        let mut book = HelperLeaseBook::default();
        assert!(book.upsert("short", 10, 20));
        assert!(book.upsert("long", 10, 70));
        let snapshot = book.prune(20);
        assert_eq!(snapshot.active_lease_ids, ["long"]);
        assert_eq!(snapshot.expires_at_epoch_seconds, Some(70));
    }

    #[test]
    fn release_leaves_other_leases_active() {
        let mut book = HelperLeaseBook::default();
        assert!(book.upsert("a", 10, 70));
        assert!(book.upsert("b", 10, 70));
        let snapshot = book.release("a", 20);
        assert_eq!(snapshot.active_lease_ids, ["b"]);
        assert!(snapshot.has_active_lease());
    }

    #[test]
    fn active_lease_count_is_bounded() {
        let mut book = HelperLeaseBook::default();
        for index in 0..HELPER_LEASE_MAX_ACTIVE {
            assert!(book.upsert(&format!("lease-{index}"), 10, 70));
        }
        assert!(!book.upsert("too-many", 10, 70));
        assert_eq!(book.snapshot().active_count(), HELPER_LEASE_MAX_ACTIVE);
    }

    #[test]
    fn blank_and_already_expired_upserts_do_not_create_leases() {
        let mut book = HelperLeaseBook::default();
        assert!(!book.upsert(" ", 10, 70));
        assert!(book.upsert("expired", 10, 10));
        assert!(!book.snapshot().has_active_lease());
    }
}

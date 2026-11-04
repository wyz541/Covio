//! Runtime hold leases and idle-sleep assertion reconciliation.

use super::models::{
    HoldLease, HoldLeaseLevel, HoldLeaseSnapshot, HoldLeaseSource, IdleSleepAssertionResult,
    IdleSleepPrevention,
};
use super::ports::SleepController;
use crate::{CoreError, CoreErrorCode};
use std::collections::BTreeMap;

/// Manages runtime hold leases and Covio idle-sleep assertions.
#[derive(Debug, Clone, Default)]
pub struct HoldLeaseManager {
    leases: BTreeMap<String, HoldLease>,
    suspended: bool,
    actual_prevention: IdleSleepPrevention,
    last_error: Option<String>,
}

impl HoldLeaseManager {
    /// Creates an empty manager.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Adds or replaces one lease.
    pub fn upsert(
        &mut self,
        lease: HoldLease,
        sleep: &dyn SleepController,
        now_millis: i64,
    ) -> Result<HoldLeaseSnapshot, CoreError> {
        if lease.id.trim().is_empty() {
            return Err(CoreError::new(
                CoreErrorCode::InvalidArgument,
                "lease id must not be blank",
            ));
        }
        self.leases.insert(lease.id.clone(), lease);
        self.reconcile(sleep, now_millis)
    }

    /// Extends an existing lease.
    pub fn extend(
        &mut self,
        id: &str,
        expires_at_epoch_seconds: i64,
        sleep: &dyn SleepController,
        now_millis: i64,
    ) -> Result<HoldLeaseSnapshot, CoreError> {
        if let Some(current) = self.leases.get(id) {
            self.leases.insert(
                id.to_owned(),
                HoldLease {
                    expires_at_epoch_seconds: Some(expires_at_epoch_seconds),
                    ..current.clone()
                },
            );
            self.reconcile(sleep, now_millis)
        } else {
            Ok(self.current_snapshot())
        }
    }

    /// Cancels one lease.
    pub fn cancel(
        &mut self,
        id: &str,
        sleep: &dyn SleepController,
        now_millis: i64,
    ) -> Result<HoldLeaseSnapshot, CoreError> {
        self.leases.remove(id);
        self.reconcile(sleep, now_millis)
    }

    /// Cancels all leases from one source.
    pub fn cancel_source(
        &mut self,
        source: HoldLeaseSource,
        sleep: &dyn SleepController,
        now_millis: i64,
    ) -> Result<HoldLeaseSnapshot, CoreError> {
        self.leases.retain(|_, lease| lease.source != source);
        self.reconcile(sleep, now_millis)
    }

    /// Replaces all leases from one source.
    pub fn replace_source(
        &mut self,
        source: HoldLeaseSource,
        next_leases: &[HoldLease],
        sleep: &dyn SleepController,
        now_millis: i64,
    ) -> Result<HoldLeaseSnapshot, CoreError> {
        self.leases.retain(|_, lease| lease.source != source);
        for lease in next_leases {
            if !lease.id.trim().is_empty() {
                self.leases.insert(
                    lease.id.clone(),
                    HoldLease {
                        source,
                        ..lease.clone()
                    },
                );
            }
        }
        self.reconcile(sleep, now_millis)
    }

    /// Cancels leases from several sources.
    pub fn cancel_sources(
        &mut self,
        sources: &[HoldLeaseSource],
        sleep: &dyn SleepController,
        now_millis: i64,
    ) -> Result<HoldLeaseSnapshot, CoreError> {
        self.leases
            .retain(|_, lease| !sources.contains(&lease.source));
        self.reconcile(sleep, now_millis)
    }

    /// Prunes expired leases and reconciles.
    pub fn tick(
        &mut self,
        sleep: &dyn SleepController,
        now_millis: i64,
    ) -> Result<HoldLeaseSnapshot, CoreError> {
        self.reconcile(sleep, now_millis)
    }

    /// Releases assertions while retaining lease intent.
    pub fn suspend(
        &mut self,
        sleep: &dyn SleepController,
        now_millis: i64,
    ) -> Result<HoldLeaseSnapshot, CoreError> {
        self.suspended = true;
        self.reconcile(sleep, now_millis)
    }

    /// Restores assertions for active leases.
    pub fn resume(
        &mut self,
        sleep: &dyn SleepController,
        now_millis: i64,
    ) -> Result<HoldLeaseSnapshot, CoreError> {
        self.suspended = false;
        self.reconcile(sleep, now_millis)
    }

    /// Clears all leases and resumes assertions.
    pub fn clear(
        &mut self,
        sleep: &dyn SleepController,
        now_millis: i64,
    ) -> Result<HoldLeaseSnapshot, CoreError> {
        self.leases.clear();
        self.suspended = false;
        self.reconcile(sleep, now_millis)
    }

    /// Reads the actual assertion without changing leases.
    pub fn refresh(&mut self, sleep: &dyn SleepController) -> Result<HoldLeaseSnapshot, CoreError> {
        let desired = self.desired_prevention();
        let actual = sleep
            .read_idle_sleep_prevention()
            .unwrap_or(IdleSleepPrevention::Unknown);
        self.actual_prevention = actual;
        self.last_error = if actual == IdleSleepPrevention::Unknown {
            Some("Cannot read idle sleep assertion state".to_owned())
        } else if actual != desired {
            Some(format!(
                "Assertion state mismatch: requested {desired:?}, actual {actual:?}"
            ))
        } else {
            None
        };
        Ok(self.snapshot(desired))
    }

    /// Returns the current snapshot without I/O.
    #[must_use]
    pub fn current_snapshot(&self) -> HoldLeaseSnapshot {
        self.snapshot(self.desired_prevention())
    }

    fn reconcile(
        &mut self,
        sleep: &dyn SleepController,
        now_millis: i64,
    ) -> Result<HoldLeaseSnapshot, CoreError> {
        self.prune_expired(now_millis);
        let desired = self.desired_prevention();
        let result = sleep
            .apply_idle_sleep_prevention(desired)
            .unwrap_or_else(|error| IdleSleepAssertionResult {
                requested: desired,
                actual: IdleSleepPrevention::Unknown,
                success: false,
                error: Some(error.message().to_owned()),
            });
        let readback_error = if !result.success {
            Some(
                result
                    .error
                    .clone()
                    .unwrap_or_else(|| "Idle sleep assertion request failed".to_owned()),
            )
        } else if result.actual != desired {
            Some(format!(
                "Assertion readback mismatch: requested {desired:?}, actual {:?}",
                result.actual
            ))
        } else {
            None
        };
        self.actual_prevention = result.actual;
        self.last_error = readback_error;
        Ok(self.snapshot(desired))
    }

    fn prune_expired(&mut self, now_millis: i64) {
        self.leases.retain(|_, lease| {
            lease
                .expires_at_epoch_seconds
                .is_none_or(|expires_at| expires_at.saturating_mul(1_000) > now_millis)
        });
    }

    fn desired_prevention(&self) -> IdleSleepPrevention {
        if self.suspended {
            return IdleSleepPrevention::None;
        }
        if self
            .leases
            .values()
            .any(|lease| lease.level == HoldLeaseLevel::SystemAndDisplay)
        {
            IdleSleepPrevention::SystemAndDisplay
        } else if self.leases.values().any(|lease| {
            matches!(
                lease.level,
                HoldLeaseLevel::System | HoldLeaseLevel::ClosedLid
            )
        }) {
            IdleSleepPrevention::System
        } else {
            IdleSleepPrevention::None
        }
    }

    fn snapshot(&self, desired: IdleSleepPrevention) -> HoldLeaseSnapshot {
        let mut leases: Vec<_> = self.leases.values().cloned().collect();
        leases.sort_by(|left, right| {
            left.created_at_epoch_seconds
                .cmp(&right.created_at_epoch_seconds)
                .then_with(|| left.id.cmp(&right.id))
        });
        HoldLeaseSnapshot {
            leases,
            desired_prevention: desired,
            actual_prevention: self.actual_prevention,
            suspended: self.suspended,
            last_error: self.last_error.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use covio_platform::PlatformError;
    use std::cell::{Cell, RefCell};

    const NOW_MILLIS: i64 = 1_000;

    struct FakeController {
        actual: Cell<IdleSleepPrevention>,
        active_assertions: Cell<usize>,
        failures_remaining: Cell<usize>,
        wrong_readback: bool,
        applied: RefCell<Vec<IdleSleepPrevention>>,
    }

    impl Default for FakeController {
        fn default() -> Self {
            Self {
                actual: Cell::new(IdleSleepPrevention::None),
                active_assertions: Cell::new(0),
                failures_remaining: Cell::new(0),
                wrong_readback: false,
                applied: RefCell::new(Vec::new()),
            }
        }
    }

    impl FakeController {
        fn failing() -> Self {
            Self {
                failures_remaining: Cell::new(1),
                ..Self::default()
            }
        }

        fn wrong_readback() -> Self {
            Self {
                wrong_readback: true,
                ..Self::default()
            }
        }
    }

    impl SleepController for FakeController {
        fn sleep(&self) -> Result<(), PlatformError> {
            Ok(())
        }

        fn display_sleep(&self) -> Result<(), PlatformError> {
            Ok(())
        }

        fn apply_idle_sleep_prevention(
            &self,
            prevention: IdleSleepPrevention,
        ) -> Result<IdleSleepAssertionResult, PlatformError> {
            self.applied.borrow_mut().push(prevention);
            if self.failures_remaining.get() > 0 {
                self.failures_remaining
                    .set(self.failures_remaining.get() - 1);
                return Ok(IdleSleepAssertionResult {
                    requested: prevention,
                    actual: self.actual.get(),
                    success: false,
                    error: Some("assertion failure".to_owned()),
                });
            }
            let actual = if self.wrong_readback && prevention == IdleSleepPrevention::System {
                IdleSleepPrevention::SystemAndDisplay
            } else {
                prevention
            };
            self.actual.set(actual);
            self.active_assertions.set(usize::from(actual.is_active()));
            Ok(IdleSleepAssertionResult {
                requested: prevention,
                actual,
                success: true,
                error: None,
            })
        }

        fn read_idle_sleep_prevention(&self) -> Result<IdleSleepPrevention, PlatformError> {
            Ok(self.actual.get())
        }

        fn system_idle_sleep_timeout_seconds(&self) -> Result<Option<i64>, PlatformError> {
            Ok(Some(600))
        }
    }

    fn lease(level: HoldLeaseLevel, id: &str) -> HoldLease {
        HoldLease {
            id: id.to_owned(),
            level,
            source: HoldLeaseSource::Manual,
            reason: String::new(),
            created_at_epoch_seconds: 1,
            expires_at_epoch_seconds: None,
        }
    }

    #[test]
    fn display_lease_requests_the_display_assertion() {
        let controller = FakeController::default();
        let mut manager = HoldLeaseManager::new();
        let snapshot = manager
            .upsert(
                lease(HoldLeaseLevel::SystemAndDisplay, "display"),
                &controller,
                NOW_MILLIS,
            )
            .expect("upsert");
        assert_eq!(
            controller.applied.borrow().as_slice(),
            [IdleSleepPrevention::SystemAndDisplay]
        );
        assert_eq!(
            snapshot.actual_prevention,
            IdleSleepPrevention::SystemAndDisplay
        );
        assert_eq!(controller.active_assertions.get(), 1);
    }

    #[test]
    fn ending_one_lease_keeps_the_other_active() {
        let controller = FakeController::default();
        let mut manager = HoldLeaseManager::new();
        manager
            .upsert(
                lease(HoldLeaseLevel::System, "manual"),
                &controller,
                NOW_MILLIS,
            )
            .unwrap();
        let mut display = lease(HoldLeaseLevel::SystemAndDisplay, "timer");
        display.source = HoldLeaseSource::Timer;
        manager.upsert(display, &controller, NOW_MILLIS).unwrap();
        let after_timer = manager.cancel("timer", &controller, NOW_MILLIS).unwrap();
        assert_eq!(after_timer.actual_prevention, IdleSleepPrevention::System);
        assert_eq!(after_timer.leases[0].id, "manual");
        assert_eq!(controller.active_assertions.get(), 1);
        let after_manual = manager.cancel("manual", &controller, NOW_MILLIS).unwrap();
        assert_eq!(after_manual.actual_prevention, IdleSleepPrevention::None);
        assert!(after_manual.leases.is_empty());
        assert_eq!(controller.active_assertions.get(), 0);
    }

    #[test]
    fn replace_source_keeps_other_sources_and_overrides_the_new_source() {
        let controller = FakeController::default();
        let mut manager = HoldLeaseManager::new();
        manager
            .upsert(
                lease(HoldLeaseLevel::System, "manual"),
                &controller,
                NOW_MILLIS,
            )
            .unwrap();
        let mut agent = lease(HoldLeaseLevel::SystemAndDisplay, "agent");
        agent.source = HoldLeaseSource::Manual;
        manager
            .replace_source(HoldLeaseSource::Agent, &[agent], &controller, NOW_MILLIS)
            .unwrap();
        let snapshot = manager
            .replace_source(HoldLeaseSource::Agent, &[], &controller, NOW_MILLIS)
            .unwrap();
        assert_eq!(snapshot.leases.len(), 1);
        assert_eq!(snapshot.leases[0].id, "manual");
        assert_eq!(snapshot.actual_prevention, IdleSleepPrevention::System);
    }

    #[test]
    fn expired_timer_does_not_clear_a_manual_lease() {
        let controller = FakeController::default();
        let mut manager = HoldLeaseManager::new();
        manager
            .upsert(
                lease(HoldLeaseLevel::System, "manual"),
                &controller,
                NOW_MILLIS,
            )
            .unwrap();
        let mut timer = lease(HoldLeaseLevel::System, "timer");
        timer.source = HoldLeaseSource::Timer;
        timer.expires_at_epoch_seconds = Some(2);
        manager.upsert(timer, &controller, NOW_MILLIS).unwrap();
        let snapshot = manager.tick(&controller, 2_000).unwrap();
        assert_eq!(snapshot.leases.len(), 1);
        assert_eq!(snapshot.leases[0].id, "manual");
        assert_eq!(snapshot.actual_prevention, IdleSleepPrevention::System);
    }

    #[test]
    fn extend_moves_the_expiry_without_replacing_the_lease() {
        let controller = FakeController::default();
        let mut manager = HoldLeaseManager::new();
        let mut timer = lease(HoldLeaseLevel::System, "timer");
        timer.source = HoldLeaseSource::Timer;
        timer.expires_at_epoch_seconds = Some(2);
        manager.upsert(timer, &controller, NOW_MILLIS).unwrap();
        assert_eq!(manager.tick(&controller, 1_500).unwrap().leases.len(), 1);
        manager.extend("timer", 4, &controller, NOW_MILLIS).unwrap();
        let still_active = manager.tick(&controller, 2_500).unwrap();
        assert_eq!(still_active.leases.len(), 1);
        assert_eq!(still_active.actual_prevention, IdleSleepPrevention::System);
    }

    #[test]
    fn suspend_releases_the_assertion_and_resume_restores_the_lease() {
        let controller = FakeController::default();
        let mut manager = HoldLeaseManager::new();
        manager
            .upsert(
                lease(HoldLeaseLevel::SystemAndDisplay, "display"),
                &controller,
                NOW_MILLIS,
            )
            .unwrap();
        let suspended = manager.suspend(&controller, NOW_MILLIS).unwrap();
        assert!(suspended.suspended);
        assert_eq!(suspended.actual_prevention, IdleSleepPrevention::None);
        assert_eq!(suspended.leases.len(), 1);
        let resumed = manager.resume(&controller, NOW_MILLIS).unwrap();
        assert!(!resumed.suspended);
        assert_eq!(
            resumed.actual_prevention,
            IdleSleepPrevention::SystemAndDisplay
        );
    }

    #[test]
    fn failed_assertion_reports_actual_state_and_can_retry() {
        let controller = FakeController::failing();
        let mut manager = HoldLeaseManager::new();
        let failed = manager
            .upsert(
                lease(HoldLeaseLevel::System, "manual"),
                &controller,
                NOW_MILLIS,
            )
            .unwrap();
        assert_eq!(failed.actual_prevention, IdleSleepPrevention::None);
        assert_eq!(failed.last_error.as_deref(), Some("assertion failure"));
        assert_eq!(failed.desired_prevention, IdleSleepPrevention::System);
        let retried = manager.tick(&controller, NOW_MILLIS).unwrap();
        assert_eq!(retried.actual_prevention, IdleSleepPrevention::System);
        assert_eq!(retried.last_error, None);
    }

    #[test]
    fn readback_mismatch_is_an_error_even_when_the_driver_claims_success() {
        let controller = FakeController::wrong_readback();
        let mut manager = HoldLeaseManager::new();
        let snapshot = manager
            .upsert(
                lease(HoldLeaseLevel::System, "manual"),
                &controller,
                NOW_MILLIS,
            )
            .unwrap();
        assert_eq!(
            snapshot.actual_prevention,
            IdleSleepPrevention::SystemAndDisplay
        );
        assert!(snapshot.last_error.unwrap().contains("mismatch"));
    }

    #[test]
    fn closed_lid_maps_to_system_and_keeps_a_display_lease() {
        let controller = FakeController::default();
        let mut manager = HoldLeaseManager::new();
        let closed = manager
            .upsert(
                lease(HoldLeaseLevel::ClosedLid, "lid"),
                &controller,
                NOW_MILLIS,
            )
            .unwrap();
        assert_eq!(closed.desired_prevention, IdleSleepPrevention::System);
        assert_eq!(closed.actual_prevention, IdleSleepPrevention::System);
        manager
            .upsert(
                lease(HoldLeaseLevel::SystemAndDisplay, "display"),
                &controller,
                NOW_MILLIS,
            )
            .unwrap();
        let snapshot = manager.current_snapshot();
        assert_eq!(
            snapshot.desired_prevention,
            IdleSleepPrevention::SystemAndDisplay
        );
        assert_eq!(
            snapshot.actual_prevention,
            IdleSleepPrevention::SystemAndDisplay
        );
    }

    #[test]
    fn blank_lease_id_is_invalid() {
        let controller = FakeController::default();
        let mut manager = HoldLeaseManager::new();
        let error = manager
            .upsert(lease(HoldLeaseLevel::System, " "), &controller, NOW_MILLIS)
            .unwrap_err();
        assert_eq!(error.code(), CoreErrorCode::InvalidArgument);
    }

    struct UnavailableController;

    impl SleepController for UnavailableController {
        fn sleep(&self) -> Result<(), PlatformError> {
            Err(PlatformError::unavailable("sleep unavailable"))
        }
        fn display_sleep(&self) -> Result<(), PlatformError> {
            Err(PlatformError::unavailable("display sleep unavailable"))
        }
        fn apply_idle_sleep_prevention(
            &self,
            _prevention: IdleSleepPrevention,
        ) -> Result<IdleSleepAssertionResult, PlatformError> {
            Err(PlatformError::unavailable("idle assertion unavailable"))
        }
        fn read_idle_sleep_prevention(&self) -> Result<IdleSleepPrevention, PlatformError> {
            Err(PlatformError::unavailable("idle read unavailable"))
        }
        fn system_idle_sleep_timeout_seconds(&self) -> Result<Option<i64>, PlatformError> {
            Err(PlatformError::unavailable("timeout unavailable"))
        }
    }

    #[test]
    fn unavailable_platform_error_is_typed_and_redacted() {
        let error = CoreError::from(PlatformError::unavailable("private adapter detail"));
        assert_eq!(error.code(), CoreErrorCode::Unsupported);
        assert!(!error.message().contains("private adapter detail"));
        let mut manager = HoldLeaseManager::new();
        let snapshot = manager
            .upsert(
                lease(HoldLeaseLevel::System, "manual"),
                &UnavailableController,
                NOW_MILLIS,
            )
            .unwrap();
        assert_eq!(snapshot.actual_prevention, IdleSleepPrevention::Unknown);
        assert!(snapshot.last_error.is_some());
    }
}

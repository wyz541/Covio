//! Power, sleep, lid, and wake state machine.

use super::hold_leases::HoldLeaseManager;
use super::models::{
    AppState, BatteryStatus, DarkWakeStatus, HelperStatus, HoldLease, HoldLeaseLevel,
    HoldLeaseSnapshot, HoldLeaseSource, IdleSleepPrevention, LidLeaseStatus, LidState, SleepEvent,
    WakeEvent, WakeKind, WakeLogSnapshot, low_battery_sleep_required,
};
use super::ports::{
    AppLogger, IdleSensor, LidSensor, PowerSource, PrivilegedOps, SleepController, StateListener,
    WakeLogReader,
};
use crate::AppConfig;

const WAKE_LOG_CACHE_MILLIS: i64 = 60_000;
const LID_LEASE_STATUS_REFRESH_MILLIS: i64 = 5_000;
const IDLE_MANUAL_LEASE_ID: &str = "idle/manual";
const IDLE_TIMER_LEASE_ID: &str = "idle/timer";
const IDLE_CHARGING_RULE_LEASE_ID: &str = "idle/rule/charging";

/// Engine dependencies supplied by platform adapters.
pub struct EngineDependencies {
    /// Battery source.
    pub power: Box<dyn PowerSource>,
    /// Lid source.
    pub lid: Box<dyn LidSensor>,
    /// Idle-time source.
    pub idle: Box<dyn IdleSensor>,
    /// Sleep and assertion controller.
    pub sleep_controller: Box<dyn SleepController>,
    /// Privileged helper operations.
    pub privileged: Box<dyn PrivilegedOps>,
    /// Wake log reader.
    pub wake_log_reader: Box<dyn WakeLogReader>,
    /// Logger.
    pub logger: Box<dyn AppLogger>,
    /// State listener.
    pub state_listener: Box<dyn StateListener>,
    /// Wall clock in Unix milliseconds.
    pub now_millis: Box<dyn Fn() -> i64>,
    /// Delay used between wake-log retries.
    pub wake_delay: Box<dyn Fn(i64)>,
    /// Delay between wake-log retries.
    pub wake_retry_delay_millis: i64,
    /// Number of wake-log retries.
    pub wake_retry_count: usize,
    /// Clock used for wake-log cache age.
    pub wake_cache_now_millis: Box<dyn Fn() -> i64>,
}

/// Covio power engine.
pub struct Engine {
    config: AppConfig,
    state: AppState,
    started: bool,
    previous_power_state: Option<super::models::PowerState>,
    idle_cancel_at_millis: Option<i64>,
    lid_cancel_at_millis: Option<i64>,
    restore_after_sleep: Option<RestorePoint>,
    restore_due_at_millis: Option<i64>,
    manual_lid_hold: bool,
    power_lid_hold: bool,
    power_lid_display_off_enabled: bool,
    low_battery_sleep_latched: bool,
    last_wake_event: Option<WakeEvent>,
    wake_scan_scheduled: bool,
    cached_wake_log: Option<WakeLogCache>,
    last_lid_lease_status_at_millis: Option<i64>,
    hold_leases: HoldLeaseManager,
    power: Box<dyn PowerSource>,
    lid: Box<dyn LidSensor>,
    idle: Box<dyn IdleSensor>,
    sleep_controller: Box<dyn SleepController>,
    privileged: Box<dyn PrivilegedOps>,
    wake_log_reader: Box<dyn WakeLogReader>,
    logger: Box<dyn AppLogger>,
    state_listener: Box<dyn StateListener>,
    now_millis: Box<dyn Fn() -> i64>,
    wake_delay: Box<dyn Fn(i64)>,
    wake_retry_delay_millis: i64,
    wake_retry_count: usize,
    wake_cache_now_millis: Box<dyn Fn() -> i64>,
}

impl Engine {
    /// Creates an engine.
    #[must_use]
    pub fn new(initial_config: AppConfig, dependencies: EngineDependencies) -> Self {
        let config = initial_config.normalized();
        let state = AppState {
            enabled: config.enabled,
            ..AppState::default()
        };
        Self {
            config,
            state,
            started: false,
            previous_power_state: None,
            idle_cancel_at_millis: None,
            lid_cancel_at_millis: None,
            restore_after_sleep: None,
            restore_due_at_millis: None,
            manual_lid_hold: false,
            power_lid_hold: false,
            power_lid_display_off_enabled: true,
            low_battery_sleep_latched: false,
            last_wake_event: None,
            wake_scan_scheduled: false,
            cached_wake_log: None,
            last_lid_lease_status_at_millis: None,
            hold_leases: HoldLeaseManager::new(),
            power: dependencies.power,
            lid: dependencies.lid,
            idle: dependencies.idle,
            sleep_controller: dependencies.sleep_controller,
            privileged: dependencies.privileged,
            wake_log_reader: dependencies.wake_log_reader,
            logger: dependencies.logger,
            state_listener: dependencies.state_listener,
            now_millis: dependencies.now_millis,
            wake_delay: dependencies.wake_delay,
            wake_retry_delay_millis: dependencies.wake_retry_delay_millis,
            wake_retry_count: dependencies.wake_retry_count,
            wake_cache_now_millis: dependencies.wake_cache_now_millis,
        }
    }

    /// Returns the current state.
    #[must_use]
    pub fn current_state(&self) -> &AppState {
        &self.state
    }

    /// Returns the current config.
    #[must_use]
    pub fn current_config(&self) -> &AppConfig {
        &self.config
    }

    /// Starts the engine.
    pub fn start(&mut self) {
        if self.started {
            return;
        }
        self.started = true;
        let initial_lid = self.lid.read().unwrap_or(LidState::Unknown);
        let initial_battery = self.power.read().ok().flatten();
        let helper_status = self.privileged.status().unwrap_or(HelperStatus::Untrusted);
        self.state.lid = initial_lid;
        self.state.battery = initial_battery;
        self.state.helper_status = helper_status;
        let snapshot = self
            .hold_leases
            .refresh(self.sleep_controller.as_ref())
            .unwrap_or_default();
        self.sync_idle_state(snapshot);
        self.start_initial_wake_scan();
        self.reconcile_policy(true);
        self.publish();
    }

    /// Stops the engine and clears temporary assertions.
    pub fn stop(&mut self) {
        if !self.started {
            return;
        }
        self.started = false;
        self.idle_cancel_at_millis = None;
        self.lid_cancel_at_millis = None;
        self.restore_after_sleep = None;
        self.restore_due_at_millis = None;
        self.manual_lid_hold = false;
        self.power_lid_hold = false;
        self.power_lid_display_off_enabled = true;
        self.low_battery_sleep_latched = false;
        self.wake_scan_scheduled = false;
        self.state.dark_wake.scanning = false;
        let snapshot = self
            .hold_leases
            .clear(self.sleep_controller.as_ref(), (self.now_millis)())
            .unwrap_or_default();
        self.sync_idle_state(snapshot);
        if !self.state.lid_sleep_available || self.privileged.is_installed().unwrap_or(false) {
            let _ = self.privileged.set_disable_sleep(false);
        }
        self.state.lid_sleep_available = true;
        self.state.idle_cancel_remaining_seconds = None;
        self.state.lid_cancel_remaining_seconds = None;
        self.publish();
    }

    /// Applies a new configuration.
    pub fn update_config(&mut self, new_config: &AppConfig) -> bool {
        let normalized = new_config.normalized();
        let previous = self.config.clone();
        let enabled_changed = previous.enabled != normalized.enabled;
        let dark_wake_changed =
            previous.dark_wake_awareness_enabled != normalized.dark_wake_awareness_enabled;
        self.config = normalized.clone();
        self.state.enabled = normalized.enabled;
        let success = if enabled_changed {
            self.set_enabled(normalized.enabled)
        } else {
            if dark_wake_changed {
                if normalized.dark_wake_awareness_enabled {
                    self.start_initial_wake_scan();
                } else {
                    self.state.dark_wake.scanning = false;
                    self.publish();
                }
            }
            self.reconcile_policy(false)
        };
        if !success {
            self.config = previous;
            self.state.enabled = self.config.enabled;
        }
        self.publish();
        success
    }

    /// Advances timers and refreshes helper state.
    pub fn tick(&mut self) {
        let now = (self.now_millis)();
        if self
            .restore_due_at_millis
            .is_some_and(|deadline| deadline <= now)
            && self.restore_after_sleep.is_some()
        {
            self.restore_after_sleep();
        }
        let idle_deadline = self.idle_cancel_at_millis;
        if idle_deadline.is_some_and(|deadline| deadline <= now) {
            self.idle_cancel_at_millis = None;
            if let Ok(snapshot) =
                self.hold_leases
                    .cancel(IDLE_TIMER_LEASE_ID, self.sleep_controller.as_ref(), now)
            {
                self.sync_idle_state(snapshot);
            }
        } else if let Ok(snapshot) = self.hold_leases.tick(self.sleep_controller.as_ref(), now) {
            self.sync_idle_state(snapshot);
        }
        if let Some(deadline) = self.lid_cancel_at_millis {
            if deadline <= now {
                self.lid_cancel_at_millis = None;
                self.reconcile_policy(false);
            } else {
                self.update_countdowns(now);
            }
        }
        let lease_status_changed = self.refresh_lid_lease_status_if_due(now);
        if lease_status_changed && self.state.enabled {
            self.reconcile_policy(false);
        }
        if self.state.enabled && !self.state.lid_sleep_available {
            let idle_seconds = self.idle.idle_seconds().unwrap_or_default();
            let timeout = self
                .sleep_controller
                .system_idle_sleep_timeout_seconds()
                .ok()
                .flatten();
            if timeout.is_some_and(|seconds| seconds > 0 && idle_seconds >= seconds) {
                self.logger
                    .info("Idle timeout reached while lid sleep is prevented; sleeping manually.");
                self.request_sleep(true);
            }
        }
    }

    /// Enables or disables the engine.
    pub fn set_enabled(&mut self, enabled: bool) -> bool {
        if self.config.enabled == enabled && self.state.enabled == enabled {
            return true;
        }
        self.config.enabled = enabled;
        self.state.enabled = enabled;
        if !enabled {
            self.idle_cancel_at_millis = None;
            self.lid_cancel_at_millis = None;
            self.manual_lid_hold = false;
            self.power_lid_hold = false;
            self.low_battery_sleep_latched = false;
        }
        let success = if enabled {
            self.reconcile_policy(false)
        } else {
            let snapshot = self
                .hold_leases
                .clear(self.sleep_controller.as_ref(), (self.now_millis)())
                .unwrap_or_default();
            self.sync_idle_state(snapshot);
            let idle_success = self.state.last_error.is_none();
            idle_success && self.apply_desired_lid_hold(true).success
        };
        self.publish();
        success
    }

    /// Sets manual idle-sleep prevention.
    pub fn set_idle_sleep_prevention(&mut self, prevention: IdleSleepPrevention) -> bool {
        if prevention == IdleSleepPrevention::Unknown {
            return false;
        }
        let now = (self.now_millis)();
        let snapshot = match prevention {
            IdleSleepPrevention::None => {
                self.idle_cancel_at_millis = None;
                self.hold_leases.cancel_sources(
                    &[HoldLeaseSource::Manual, HoldLeaseSource::Timer],
                    self.sleep_controller.as_ref(),
                    now,
                )
            }
            IdleSleepPrevention::System | IdleSleepPrevention::SystemAndDisplay => {
                self.hold_leases.upsert(
                    HoldLease {
                        id: IDLE_MANUAL_LEASE_ID.to_owned(),
                        level: if prevention == IdleSleepPrevention::System {
                            HoldLeaseLevel::System
                        } else {
                            HoldLeaseLevel::SystemAndDisplay
                        },
                        source: HoldLeaseSource::Manual,
                        reason: "Manual idle hold".to_owned(),
                        created_at_epoch_seconds: now / 1_000,
                        expires_at_epoch_seconds: None,
                    },
                    self.sleep_controller.as_ref(),
                    now,
                )
            }
            IdleSleepPrevention::Unknown => unreachable!(),
        };
        let snapshot = match snapshot {
            Ok(snapshot) => snapshot,
            Err(error) => {
                self.state.last_error = Some(error.message().to_owned());
                self.publish();
                return false;
            }
        };
        self.sync_idle_state(snapshot);
        self.publish();
        self.state.last_error.is_none()
    }

    /// Compatibility helper for the old settings page.
    pub fn set_idle_sleep_available(&mut self, available: bool) {
        let _ = self.set_idle_sleep_prevention(if available {
            IdleSleepPrevention::None
        } else {
            IdleSleepPrevention::System
        });
    }

    /// Writes or clears helper SleepDisabled.
    pub fn set_lid_sleep_available(&mut self, available: bool) -> bool {
        let installed = self.privileged.is_installed().unwrap_or(false);
        let status = self.privileged.status().unwrap_or(HelperStatus::Untrusted);
        let success = if available && !installed {
            true
        } else if !status.allows_privileged_writes() {
            false
        } else {
            self.privileged
                .set_disable_sleep(!available)
                .unwrap_or(false)
        };
        if success {
            self.state.lid_sleep_available = available;
            if available {
                self.lid_cancel_at_millis = None;
            }
            self.refresh_lid_lease_status();
        }
        self.publish();
        success
    }

    /// Replaces Power-policy idle leases.
    pub fn replace_power_leases(&mut self, leases: &[HoldLease]) -> bool {
        let now = (self.now_millis)();
        let result = self.hold_leases.replace_source(
            HoldLeaseSource::Agent,
            leases,
            self.sleep_controller.as_ref(),
            now,
        );
        match result {
            Ok(snapshot) => {
                self.sync_idle_state(snapshot);
                self.publish();
                self.state.last_error.is_none()
            }
            Err(error) => {
                self.logger.warn(&format!(
                    "Cannot apply power policy leases: {}",
                    error.message()
                ));
                false
            }
        }
    }

    /// Merges Power-policy closed-lid hold.
    pub fn set_power_lid_hold(&mut self, required: bool) -> bool {
        self.power_lid_hold = required;
        let result = self.apply_desired_lid_hold(false);
        if result.released
            && self.state.lid == LidState::Closed
            && self.config.lid_sleep_immediate_on_close
        {
            self.request_sleep(true);
        }
        if result.success && required {
            self.refresh_lid_lease_status();
        }
        self.publish();
        if !result.success || !required {
            return result.success;
        }
        self.state.lid_lease_status.sleep_disabled == Some(true)
            && self.state.lid_lease_status.covio_owned == Some(true)
    }

    /// Selects who turns the display off during a closed-lid hold.
    pub fn set_power_lid_display_off_enabled(&mut self, enabled: bool) {
        self.power_lid_display_off_enabled = enabled;
    }

    /// Sets the manual closed-lid hold.
    pub fn set_manual_lid_sleep_available(&mut self, available: bool) {
        self.manual_lid_hold = !available;
        let released = self.apply_desired_lid_hold(false).released;
        if released && self.state.lid == LidState::Closed {
            self.request_sleep(true);
        }
        self.publish();
    }

    /// Schedules an idle-sleep hold cancellation.
    pub fn schedule_cancel_idle(&mut self, after_seconds: i64) {
        if after_seconds <= 0 {
            return;
        }
        let now = (self.now_millis)();
        let deadline = now.saturating_add(after_seconds.saturating_mul(1_000));
        let expires_at_epoch_seconds = (deadline.saturating_add(999)) / 1_000;
        if let Ok(snapshot) = self.hold_leases.upsert(
            HoldLease {
                id: IDLE_TIMER_LEASE_ID.to_owned(),
                level: HoldLeaseLevel::System,
                source: HoldLeaseSource::Timer,
                reason: "Timed idle hold".to_owned(),
                created_at_epoch_seconds: now / 1_000,
                expires_at_epoch_seconds: Some(expires_at_epoch_seconds),
            },
            self.sleep_controller.as_ref(),
            now,
        ) {
            self.idle_cancel_at_millis = Some(deadline);
            self.sync_idle_state(snapshot);
            self.update_countdowns(now);
            self.publish();
        }
    }

    /// Schedules a closed-lid hold cancellation.
    pub fn schedule_cancel_lid(&mut self, after_seconds: i64) {
        if after_seconds <= 0 {
            return;
        }
        let now = (self.now_millis)();
        self.lid_cancel_at_millis = Some(now.saturating_add(after_seconds.saturating_mul(1_000)));
        let released = self.apply_desired_lid_hold(false).released;
        if released && self.state.lid == LidState::Closed {
            self.request_sleep(true);
        }
        self.update_countdowns(now);
        self.publish();
    }

    /// Requests sleep immediately.
    pub fn sleep_now(&mut self) {
        self.request_sleep(true);
    }

    /// Requests display sleep.
    pub fn display_sleep_now(&mut self) {
        if let Err(error) = self.sleep_controller.display_sleep() {
            self.logger.error(&format!(
                "Display sleep request failed: {}",
                error.message()
            ));
        }
    }

    /// Handles a power source change.
    pub fn on_power_changed(&mut self) {
        let Some(battery) = self.power.read().ok().flatten() else {
            return;
        };
        let previous = self.previous_power_state.replace(battery.state);
        self.state.battery = Some(battery);
        self.publish();
        if previous != Some(battery.state) || self.state.enabled {
            self.reconcile_policy(false);
        }
    }

    /// Handles a lid state change.
    pub fn on_lid_changed(&mut self, lid_state: LidState) {
        let previous = self.state.lid;
        self.state.lid = lid_state;
        self.publish();
        if lid_state == LidState::Unknown || previous == lid_state || !self.state.enabled {
            return;
        }
        if lid_state == LidState::Closed {
            if !self.state.lid_sleep_available {
                if self.power_lid_display_off_enabled {
                    self.display_sleep_now();
                }
            } else if self.config.lid_sleep_immediate_on_close {
                self.request_sleep(true);
            }
        }
    }

    /// Handles a sleep/wake lifecycle event.
    pub fn on_sleep_event(&mut self, event: SleepEvent) {
        match event {
            SleepEvent::WillSleep => self.logger.info("System will sleep."),
            SleepEvent::WakeSignal => {
                if self.config.dark_wake_awareness_enabled {
                    self.schedule_wake_scan(false);
                } else {
                    self.handle_full_wake("DarkWake awareness is disabled");
                }
            }
        }
    }

    /// Runs one wake scan synchronously.
    pub fn run_wake_scan(&mut self, initial: bool) {
        if !self.config.dark_wake_awareness_enabled {
            self.state.dark_wake.scanning = false;
            self.publish();
            return;
        }
        self.state.dark_wake.scanning = true;
        self.publish();
        let baseline = self.last_wake_event.clone();
        if !initial {
            (self.wake_delay)(self.wake_retry_delay_millis);
        }
        let mut snapshot = if initial {
            self.read_wake_log_cached()
        } else {
            self.read_wake_log_fresh()
        };
        let mut retries = 0;
        if !initial {
            while snapshot.as_ref().and_then(WakeLogSnapshot::latest) == baseline.as_ref()
                && retries < self.wake_retry_count
            {
                retries += 1;
                (self.wake_delay)(self.wake_retry_delay_millis);
                if let Some(fresh) = self.read_wake_log_fresh() {
                    snapshot = Some(fresh);
                }
            }
        }
        self.apply_wake_snapshot(snapshot, initial);
        self.wake_scan_scheduled = false;
        if self.started {
            self.state.dark_wake.scanning = false;
            self.publish();
        }
    }

    fn apply_desired_lid_hold(&mut self, force_clear: bool) -> LidHoldResult {
        let desired = self.desired_lid_hold();
        let was_held = !self.state.lid_sleep_available;
        if desired {
            if was_held {
                return LidHoldResult {
                    released: false,
                    success: true,
                };
            }
            let success = self.set_lid_sleep_available(false);
            return LidHoldResult {
                released: false,
                success,
            };
        }
        let helper_installed = self.privileged.is_installed().unwrap_or(false);
        if !was_held && !(force_clear && helper_installed) {
            return LidHoldResult {
                released: false,
                success: true,
            };
        }
        if !helper_installed {
            return LidHoldResult {
                released: false,
                success: false,
            };
        }
        let success = self.set_lid_sleep_available(true);
        LidHoldResult {
            released: success && was_held,
            success,
        }
    }

    fn desired_lid_hold(&self) -> bool {
        if !self.state.enabled || self.restore_after_sleep.is_some() || !self.helper_ready() {
            return false;
        }
        if self
            .state
            .battery
            .is_some_and(|battery| low_battery_sleep_required(&self.config, battery))
        {
            return false;
        }
        self.manual_lid_hold || self.power_lid_hold || self.lid_cancel_at_millis.is_some()
    }

    fn helper_ready(&self) -> bool {
        self.privileged.is_installed().unwrap_or(false)
            && self
                .privileged
                .status()
                .is_ok_and(|status| status == HelperStatus::Match)
    }

    fn reconcile_policy(&mut self, clear_stale_lid_flag: bool) -> bool {
        if !self.state.enabled {
            let snapshot = self
                .hold_leases
                .clear(self.sleep_controller.as_ref(), (self.now_millis)())
                .unwrap_or_default();
            self.sync_idle_state(snapshot);
            return self.state.last_error.is_none()
                && self.apply_desired_lid_hold(clear_stale_lid_flag).success;
        }
        let battery = self.state.battery.or_else(|| self.read_battery());
        let Some(battery) = battery else {
            return self.apply_desired_lid_hold(clear_stale_lid_flag).success;
        };
        let idle_success = self.apply_charging_idle_rule(
            self.config.disable_idle_sleep_in_charging && battery.state.is_charging(),
        );
        if low_battery_sleep_required(&self.config, battery) {
            let result = self.apply_desired_lid_hold(clear_stale_lid_flag);
            if !self.low_battery_sleep_latched {
                self.low_battery_sleep_latched = true;
                self.request_sleep(false);
            }
            return idle_success && result.success;
        }
        self.low_battery_sleep_latched = false;
        let result = self.apply_desired_lid_hold(clear_stale_lid_flag);
        if result.released
            && self.state.lid == LidState::Closed
            && self.config.lid_sleep_immediate_on_close
        {
            self.request_sleep(true);
        }
        idle_success && result.success
    }

    fn request_sleep(&mut self, restore_after_wake: bool) {
        let fix_idle = !self.state.idle_sleep_available;
        let fix_lid = !self.state.lid_sleep_available;
        let should_restore = restore_after_wake && (fix_idle || fix_lid);
        self.restore_after_sleep = should_restore.then_some(RestorePoint {
            restore_idle: fix_idle,
            restore_lid: fix_lid,
            lid_deadline: self.lid_cancel_at_millis,
        });
        if fix_idle {
            let now = (self.now_millis)();
            let result = if restore_after_wake {
                self.hold_leases
                    .suspend(self.sleep_controller.as_ref(), now)
            } else {
                self.hold_leases.clear(self.sleep_controller.as_ref(), now)
            };
            if let Ok(snapshot) = result {
                self.sync_idle_state(snapshot);
            }
        }
        if fix_lid {
            let _ = self.set_lid_sleep_available(true);
        }
        if let Err(error) = self.sleep_controller.sleep() {
            self.logger
                .error(&format!("Sleep request failed: {}", error.message()));
        }
        self.restore_due_at_millis =
            should_restore.then(|| (self.now_millis)().saturating_add(2_000));
    }

    fn restore_after_sleep(&mut self) -> bool {
        let Some(restore) = self.restore_after_sleep.take() else {
            return false;
        };
        self.restore_due_at_millis = None;
        if restore.restore_idle {
            let now = (self.now_millis)();
            if let Ok(snapshot) = self.hold_leases.resume(self.sleep_controller.as_ref(), now) {
                self.sync_idle_state(snapshot);
            }
        }
        if restore.lid_deadline.is_some() {
            self.lid_cancel_at_millis = restore.lid_deadline;
        }
        self.reconcile_policy(false);
        if restore.restore_lid
            && self
                .state
                .battery
                .is_some_and(|battery| !low_battery_sleep_required(&self.config, battery))
        {
            let _ = self.set_lid_sleep_available(false);
        }
        self.update_countdowns((self.now_millis)());
        self.publish();
        true
    }

    fn apply_charging_idle_rule(&mut self, active: bool) -> bool {
        let now = (self.now_millis)();
        let snapshot = if active {
            self.hold_leases.upsert(
                HoldLease {
                    id: IDLE_CHARGING_RULE_LEASE_ID.to_owned(),
                    level: HoldLeaseLevel::System,
                    source: HoldLeaseSource::Rule,
                    reason: "Adapter idle rule".to_owned(),
                    created_at_epoch_seconds: now / 1_000,
                    expires_at_epoch_seconds: None,
                },
                self.sleep_controller.as_ref(),
                now,
            )
        } else {
            self.hold_leases.cancel_source(
                HoldLeaseSource::Rule,
                self.sleep_controller.as_ref(),
                now,
            )
        };
        match snapshot {
            Ok(snapshot) => {
                self.sync_idle_state(snapshot);
                self.state.last_error.is_none()
            }
            Err(error) => {
                self.state.last_error = Some(error.message().to_owned());
                false
            }
        }
    }

    fn sync_idle_state(&mut self, snapshot: HoldLeaseSnapshot) {
        self.state.idle_sleep_available = matches!(
            snapshot.actual_prevention,
            IdleSleepPrevention::None | IdleSleepPrevention::Unknown
        );
        self.state.idle_sleep_prevention = snapshot.actual_prevention;
        self.state.last_error = snapshot.last_error;
    }

    fn read_battery(&mut self) -> Option<BatteryStatus> {
        let battery = self.power.read().ok().flatten()?;
        self.state.battery = Some(battery);
        Some(battery)
    }

    fn refresh_lid_lease_status_if_due(&mut self, now_millis: i64) -> bool {
        if self
            .last_lid_lease_status_at_millis
            .is_some_and(|last| now_millis - last < LID_LEASE_STATUS_REFRESH_MILLIS)
        {
            return false;
        }
        self.last_lid_lease_status_at_millis = Some(now_millis);
        self.refresh_lid_lease_status()
    }

    fn refresh_lid_lease_status(&mut self) -> bool {
        let status = self
            .privileged
            .lid_lease_status()
            .unwrap_or_else(|error| LidLeaseStatus {
                available: false,
                error: Some(error.message().to_owned()),
                ..LidLeaseStatus::default()
            });
        let available = status.sleep_disabled != Some(true);
        let changed =
            self.state.lid_lease_status != status || self.state.lid_sleep_available != available;
        self.state.lid_lease_status = status;
        self.state.lid_sleep_available = available;
        changed
    }

    fn schedule_wake_scan(&mut self, initial: bool) {
        if !self.started || !self.config.dark_wake_awareness_enabled || self.wake_scan_scheduled {
            return;
        }
        self.wake_scan_scheduled = true;
        self.state.dark_wake.scanning = true;
        self.publish();
        self.run_wake_scan(initial);
    }

    fn start_initial_wake_scan(&mut self) {
        if self.config.dark_wake_awareness_enabled {
            self.schedule_wake_scan(true);
        }
    }

    fn read_wake_log_cached(&mut self) -> Option<WakeLogSnapshot> {
        if let Some(cached) = &self.cached_wake_log {
            let age = (self.wake_cache_now_millis)().saturating_sub(cached.read_at_millis);
            if (0..WAKE_LOG_CACHE_MILLIS).contains(&age) {
                return Some(cached.snapshot.clone());
            }
        }
        self.read_wake_log_fresh()
    }

    fn read_wake_log_fresh(&mut self) -> Option<WakeLogSnapshot> {
        let snapshot = self.wake_log_reader.read().ok().flatten();
        if let Some(snapshot) = &snapshot {
            self.cached_wake_log = Some(WakeLogCache {
                snapshot: snapshot.clone(),
                read_at_millis: (self.wake_cache_now_millis)(),
            });
        }
        snapshot
    }

    fn apply_wake_snapshot(&mut self, snapshot: Option<WakeLogSnapshot>, initial: bool) {
        if !self.config.dark_wake_awareness_enabled {
            return;
        }
        let Some(snapshot) = snapshot else {
            self.logger
                .warn("Wake log parsing failed. Using FULL wake behavior.");
            self.state.dark_wake.available = false;
            self.state.dark_wake.scanning = false;
            if !initial {
                self.last_wake_event = None;
                self.publish();
                self.handle_full_wake("Wake log is unavailable");
            } else {
                self.publish();
            }
            return;
        };
        let latest = snapshot.latest().cloned();
        self.state.dark_wake = DarkWakeStatus {
            available: true,
            scanning: false,
            last_at_epoch_seconds: latest.as_ref().map(|event| event.at_epoch_seconds),
            last_kind: latest.as_ref().map(|event| event.kind),
            last_reason: latest
                .as_ref()
                .map(|event| event.reason.clone())
                .filter(|reason| !reason.is_empty()),
            count_24h: snapshot.dark_wake_count_24h,
        };
        self.publish();
        if initial {
            self.last_wake_event = latest;
            return;
        }
        let baseline = self.last_wake_event.clone();
        let Some(latest) = latest else {
            return;
        };
        if Some(&latest) == baseline.as_ref() {
            return;
        }
        self.last_wake_event = Some(latest.clone());
        match latest.kind {
            WakeKind::Dark => self.handle_dark_wake(&latest.reason),
            WakeKind::Full => self.handle_full_wake(&latest.reason),
        }
    }

    fn handle_dark_wake(&mut self, reason: &str) {
        self.logger
            .info(&format!("DarkWake detected{}.", reason_suffix(reason)));
        if self.restore_after_sleep.is_none() {
            self.reconcile_policy(false);
        }
    }

    fn handle_full_wake(&mut self, reason: &str) {
        self.logger
            .info(&format!("Full wake detected{}.", reason_suffix(reason)));
        if !self.restore_after_sleep() {
            self.reconcile_policy(false);
        }
    }

    fn update_countdowns(&mut self, now_millis: i64) {
        self.state.idle_cancel_remaining_seconds = self
            .idle_cancel_at_millis
            .map(|deadline| ((deadline - now_millis) / 1_000).max(0));
        self.state.lid_cancel_remaining_seconds = self
            .lid_cancel_at_millis
            .map(|deadline| ((deadline - now_millis) / 1_000).max(0));
        self.publish();
    }

    fn publish(&self) {
        self.state_listener.on_state(&self.state);
    }
}

#[derive(Debug, Clone)]
struct RestorePoint {
    restore_idle: bool,
    restore_lid: bool,
    lid_deadline: Option<i64>,
}

#[derive(Debug, Clone)]
struct WakeLogCache {
    snapshot: WakeLogSnapshot,
    read_at_millis: i64,
}

#[derive(Debug, Clone, Copy)]
struct LidHoldResult {
    released: bool,
    success: bool,
}

fn reason_suffix(reason: &str) -> String {
    if reason.trim().is_empty() {
        String::new()
    } else {
        format!(": {reason}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::power::models::{IdleSleepAssertionResult, LidLeaseStatus, WakeLogSnapshot};
    use covio_platform::PlatformError;
    use std::collections::VecDeque;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex};

    #[derive(Default)]
    struct FakePower {
        value: Mutex<Option<BatteryStatus>>,
    }

    impl FakePower {
        fn set(&self, value: Option<BatteryStatus>) {
            *self.value.lock().unwrap() = value;
        }
    }

    impl PowerSource for FakePower {
        fn read(&self) -> Result<Option<BatteryStatus>, PlatformError> {
            Ok(*self.value.lock().unwrap())
        }
    }

    struct FakeLid {
        state: Mutex<LidState>,
    }

    impl Default for FakeLid {
        fn default() -> Self {
            Self {
                state: Mutex::new(LidState::Open),
            }
        }
    }

    impl FakeLid {
        fn set(&self, state: LidState) {
            *self.state.lock().unwrap() = state;
        }
    }

    impl LidSensor for FakeLid {
        fn read(&self) -> Result<LidState, PlatformError> {
            Ok(*self.state.lock().unwrap())
        }
    }

    #[derive(Default)]
    struct FakeIdle {
        seconds: Mutex<i64>,
    }

    impl FakeIdle {
        fn set(&self, seconds: i64) {
            *self.seconds.lock().unwrap() = seconds;
        }
    }

    impl IdleSensor for FakeIdle {
        fn idle_seconds(&self) -> Result<i64, PlatformError> {
            Ok(*self.seconds.lock().unwrap())
        }
    }

    struct FakeSleep {
        sleep_calls: AtomicUsize,
        display_calls: AtomicUsize,
        prevention: Mutex<IdleSleepPrevention>,
        fail_assertion: AtomicBool,
        timeout_seconds: Mutex<Option<i64>>,
    }

    impl Default for FakeSleep {
        fn default() -> Self {
            Self {
                sleep_calls: AtomicUsize::new(0),
                display_calls: AtomicUsize::new(0),
                prevention: Mutex::new(IdleSleepPrevention::None),
                fail_assertion: AtomicBool::new(false),
                timeout_seconds: Mutex::new(None),
            }
        }
    }

    impl FakeSleep {
        fn sleep_calls(&self) -> usize {
            self.sleep_calls.load(Ordering::SeqCst)
        }

        fn display_calls(&self) -> usize {
            self.display_calls.load(Ordering::SeqCst)
        }

        fn prevention(&self) -> IdleSleepPrevention {
            *self.prevention.lock().unwrap()
        }

        fn set_fail_assertion(&self, fail: bool) {
            self.fail_assertion.store(fail, Ordering::SeqCst);
        }

        fn set_timeout(&self, timeout: Option<i64>) {
            *self.timeout_seconds.lock().unwrap() = timeout;
        }
    }

    impl SleepController for FakeSleep {
        fn sleep(&self) -> Result<(), PlatformError> {
            self.sleep_calls.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }

        fn display_sleep(&self) -> Result<(), PlatformError> {
            self.display_calls.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }

        fn apply_idle_sleep_prevention(
            &self,
            prevention: IdleSleepPrevention,
        ) -> Result<IdleSleepAssertionResult, PlatformError> {
            if self.fail_assertion.load(Ordering::SeqCst) {
                return Ok(IdleSleepAssertionResult {
                    requested: prevention,
                    actual: self.prevention(),
                    success: false,
                    error: Some("assertion failure".to_owned()),
                });
            }
            *self.prevention.lock().unwrap() = prevention;
            Ok(IdleSleepAssertionResult {
                requested: prevention,
                actual: prevention,
                success: true,
                error: None,
            })
        }

        fn read_idle_sleep_prevention(&self) -> Result<IdleSleepPrevention, PlatformError> {
            Ok(self.prevention())
        }

        fn system_idle_sleep_timeout_seconds(&self) -> Result<Option<i64>, PlatformError> {
            Ok(*self.timeout_seconds.lock().unwrap())
        }
    }

    struct FakePrivileged {
        installed: AtomicBool,
        helper_status: Mutex<Option<HelperStatus>>,
        disable_sleep_result: AtomicBool,
        sleep_disabled: AtomicBool,
        disable_sleep_values: Mutex<Vec<bool>>,
    }

    impl Default for FakePrivileged {
        fn default() -> Self {
            Self {
                installed: AtomicBool::new(false),
                helper_status: Mutex::new(None),
                disable_sleep_result: AtomicBool::new(true),
                sleep_disabled: AtomicBool::new(false),
                disable_sleep_values: Mutex::new(Vec::new()),
            }
        }
    }

    impl FakePrivileged {
        fn set_installed(&self, installed: bool) {
            self.installed.store(installed, Ordering::SeqCst);
        }

        fn set_status(&self, status: Option<HelperStatus>) {
            *self.helper_status.lock().unwrap() = status;
        }

        fn set_disable_sleep_result(&self, result: bool) {
            self.disable_sleep_result.store(result, Ordering::SeqCst);
        }

        fn set_sleep_disabled(&self, disabled: bool) {
            self.sleep_disabled.store(disabled, Ordering::SeqCst);
        }

        fn disable_sleep_values(&self) -> Vec<bool> {
            self.disable_sleep_values.lock().unwrap().clone()
        }
    }

    impl PrivilegedOps for FakePrivileged {
        fn is_installed(&self) -> Result<bool, PlatformError> {
            Ok(self.installed.load(Ordering::SeqCst))
        }

        fn status(&self) -> Result<HelperStatus, PlatformError> {
            Ok(self.helper_status.lock().unwrap().unwrap_or_else(|| {
                if self.installed.load(Ordering::SeqCst) {
                    HelperStatus::Match
                } else {
                    HelperStatus::Missing
                }
            }))
        }

        fn helper_version(&self) -> Result<Option<String>, PlatformError> {
            Ok(Some("1.0.0".to_owned()))
        }

        fn install(&self) -> Result<bool, PlatformError> {
            Ok(true)
        }

        fn uninstall(&self) -> Result<bool, PlatformError> {
            Ok(true)
        }

        fn set_disable_sleep(&self, disabled: bool) -> Result<bool, PlatformError> {
            self.disable_sleep_values.lock().unwrap().push(disabled);
            let success = self.disable_sleep_result.load(Ordering::SeqCst);
            if success {
                self.set_sleep_disabled(disabled);
            }
            Ok(success)
        }

        fn lid_lease_status(&self) -> Result<LidLeaseStatus, PlatformError> {
            let installed = self.installed.load(Ordering::SeqCst);
            let disabled = self.sleep_disabled.load(Ordering::SeqCst);
            Ok(LidLeaseStatus {
                available: installed,
                protocol_version: installed.then(|| "10".to_owned()),
                sleep_disabled: Some(disabled),
                covio_owned: Some(disabled),
                active_lease_count: i32::from(disabled),
                expires_at_epoch_seconds: disabled.then_some(i64::MAX),
                error: None,
            })
        }

        fn hibernate_mode(&self) -> Result<Option<i32>, PlatformError> {
            Ok(None)
        }

        fn set_hibernate_mode(&self, _mode: i32) -> Result<bool, PlatformError> {
            Ok(true)
        }
    }

    #[derive(Default)]
    struct FakeWakeLog {
        queue: Mutex<VecDeque<Option<WakeLogSnapshot>>>,
        fallback: Mutex<Option<WakeLogSnapshot>>,
        reads: AtomicUsize,
    }

    impl FakeWakeLog {
        fn push(&self, snapshot: Option<WakeLogSnapshot>) {
            self.queue.lock().unwrap().push_back(snapshot);
        }

        fn set_fallback(&self, snapshot: Option<WakeLogSnapshot>) {
            *self.fallback.lock().unwrap() = snapshot;
        }

        fn reads(&self) -> usize {
            self.reads.load(Ordering::SeqCst)
        }
    }

    impl WakeLogReader for FakeWakeLog {
        fn read(&self) -> Result<Option<WakeLogSnapshot>, PlatformError> {
            self.reads.fetch_add(1, Ordering::SeqCst);
            Ok(self
                .queue
                .lock()
                .unwrap()
                .pop_front()
                .unwrap_or_else(|| self.fallback.lock().unwrap().clone()))
        }
    }

    #[derive(Default)]
    struct MemoryLogger {
        messages: Mutex<Vec<String>>,
    }

    impl MemoryLogger {
        fn has(&self, text: &str) -> bool {
            self.messages
                .lock()
                .unwrap()
                .iter()
                .any(|message| message.contains(text))
        }
    }

    impl AppLogger for MemoryLogger {
        fn info(&self, message: &str) {
            self.messages.lock().unwrap().push(message.to_owned());
        }

        fn warn(&self, message: &str) {
            self.messages.lock().unwrap().push(message.to_owned());
        }

        fn error(&self, message: &str) {
            self.messages.lock().unwrap().push(message.to_owned());
        }
    }

    #[derive(Default)]
    struct NoopListener;

    impl StateListener for NoopListener {
        fn on_state(&self, _state: &AppState) {}
    }

    struct Fixture {
        engine: Engine,
        power: Arc<FakePower>,
        lid: Arc<FakeLid>,
        idle: Arc<FakeIdle>,
        sleep: Arc<FakeSleep>,
        privileged: Arc<FakePrivileged>,
        wake: Arc<FakeWakeLog>,
        logger: Arc<MemoryLogger>,
        now_millis: Arc<Mutex<i64>>,
        wake_cache_now: Arc<Mutex<i64>>,
        wake_delays: Arc<AtomicUsize>,
    }

    impl Fixture {
        fn new(config: AppConfig) -> Self {
            Self::with_clock_and_wake(config, 1_000, None)
        }

        fn with_clock(config: AppConfig, now_millis: i64) -> Self {
            Self::with_clock_and_wake(config, now_millis, None)
        }

        fn with_wake(config: AppConfig, initial: Option<WakeLogSnapshot>) -> Self {
            Self::with_clock_and_wake(config, 1_000, initial)
        }

        fn with_clock_and_wake(
            config: AppConfig,
            now_millis: i64,
            initial: Option<WakeLogSnapshot>,
        ) -> Self {
            let power = Arc::new(FakePower::default());
            let lid = Arc::new(FakeLid::default());
            let idle = Arc::new(FakeIdle::default());
            let sleep = Arc::new(FakeSleep {
                timeout_seconds: Mutex::new(Some(600)),
                ..FakeSleep::default()
            });
            let privileged = Arc::new(FakePrivileged::default());
            let wake = Arc::new(FakeWakeLog::default());
            if let Some(snapshot) = initial {
                wake.push(Some(snapshot));
            }
            let logger = Arc::new(MemoryLogger::default());
            let now_millis = Arc::new(Mutex::new(now_millis));
            let wake_cache_now = now_millis.clone();
            let wake_delays = Arc::new(AtomicUsize::new(0));

            let power_dep = power.clone();
            let lid_dep = lid.clone();
            let idle_dep = idle.clone();
            let sleep_dep = sleep.clone();
            let privileged_dep = privileged.clone();
            let wake_dep = wake.clone();
            let logger_dep = logger.clone();
            let now_dep = now_millis.clone();
            let delay_counter = wake_delays.clone();
            let cache_dep = wake_cache_now.clone();
            let engine = Engine::new(
                config,
                EngineDependencies {
                    power: Box::new(PowerDependency(power_dep)),
                    lid: Box::new(LidDependency(lid_dep)),
                    idle: Box::new(IdleDependency(idle_dep)),
                    sleep_controller: Box::new(SleepDependency(sleep_dep)),
                    privileged: Box::new(PrivilegedDependency(privileged_dep)),
                    wake_log_reader: Box::new(WakeDependency(wake_dep)),
                    logger: Box::new(LoggerDependency(logger_dep)),
                    state_listener: Box::new(NoopListener),
                    now_millis: Box::new(move || *now_dep.lock().unwrap()),
                    wake_delay: Box::new(move |_| {
                        delay_counter.fetch_add(1, Ordering::SeqCst);
                    }),
                    wake_retry_delay_millis: 1_000,
                    wake_retry_count: 3,
                    wake_cache_now_millis: Box::new(move || *cache_dep.lock().unwrap()),
                },
            );
            Self {
                engine,
                power,
                lid,
                idle,
                sleep,
                privileged,
                wake,
                logger,
                now_millis,
                wake_cache_now,
                wake_delays,
            }
        }

        fn set_now(&self, value: i64) {
            *self.now_millis.lock().unwrap() = value;
        }

        fn set_wake_cache_now(&self, value: i64) {
            *self.wake_cache_now.lock().unwrap() = value;
        }

        fn set_battery(&self, battery: BatteryStatus) {
            self.power.set(Some(battery));
        }
    }

    struct PowerDependency(Arc<FakePower>);
    impl PowerSource for PowerDependency {
        fn read(&self) -> Result<Option<BatteryStatus>, PlatformError> {
            self.0.read()
        }
    }

    struct LidDependency(Arc<FakeLid>);
    impl LidSensor for LidDependency {
        fn read(&self) -> Result<LidState, PlatformError> {
            self.0.read()
        }
    }

    struct IdleDependency(Arc<FakeIdle>);
    impl IdleSensor for IdleDependency {
        fn idle_seconds(&self) -> Result<i64, PlatformError> {
            self.0.idle_seconds()
        }
    }

    struct SleepDependency(Arc<FakeSleep>);
    impl SleepController for SleepDependency {
        fn sleep(&self) -> Result<(), PlatformError> {
            self.0.sleep()
        }
        fn display_sleep(&self) -> Result<(), PlatformError> {
            self.0.display_sleep()
        }
        fn apply_idle_sleep_prevention(
            &self,
            prevention: IdleSleepPrevention,
        ) -> Result<IdleSleepAssertionResult, PlatformError> {
            self.0.apply_idle_sleep_prevention(prevention)
        }
        fn read_idle_sleep_prevention(&self) -> Result<IdleSleepPrevention, PlatformError> {
            self.0.read_idle_sleep_prevention()
        }
        fn system_idle_sleep_timeout_seconds(&self) -> Result<Option<i64>, PlatformError> {
            self.0.system_idle_sleep_timeout_seconds()
        }
    }

    struct PrivilegedDependency(Arc<FakePrivileged>);
    impl PrivilegedOps for PrivilegedDependency {
        fn is_installed(&self) -> Result<bool, PlatformError> {
            self.0.is_installed()
        }
        fn status(&self) -> Result<HelperStatus, PlatformError> {
            self.0.status()
        }
        fn helper_version(&self) -> Result<Option<String>, PlatformError> {
            self.0.helper_version()
        }
        fn install(&self) -> Result<bool, PlatformError> {
            self.0.install()
        }
        fn uninstall(&self) -> Result<bool, PlatformError> {
            self.0.uninstall()
        }
        fn set_disable_sleep(&self, disabled: bool) -> Result<bool, PlatformError> {
            self.0.set_disable_sleep(disabled)
        }
        fn lid_lease_status(&self) -> Result<LidLeaseStatus, PlatformError> {
            self.0.lid_lease_status()
        }
        fn hibernate_mode(&self) -> Result<Option<i32>, PlatformError> {
            self.0.hibernate_mode()
        }
        fn set_hibernate_mode(&self, mode: i32) -> Result<bool, PlatformError> {
            self.0.set_hibernate_mode(mode)
        }
    }

    struct WakeDependency(Arc<FakeWakeLog>);
    impl WakeLogReader for WakeDependency {
        fn read(&self) -> Result<Option<WakeLogSnapshot>, PlatformError> {
            self.0.read()
        }
    }

    struct LoggerDependency(Arc<MemoryLogger>);
    impl AppLogger for LoggerDependency {
        fn info(&self, message: &str) {
            self.0.info(message);
        }
        fn warn(&self, message: &str) {
            self.0.warn(message);
        }
        fn error(&self, message: &str) {
            self.0.error(message);
        }
    }

    fn battery(
        percent: i32,
        state: crate::power::models::PowerState,
        remaining: Option<i64>,
    ) -> BatteryStatus {
        BatteryStatus {
            percent,
            state,
            remaining_seconds: remaining,
        }
    }

    fn snapshot(kind: WakeKind, at: i64, reason: &str) -> WakeLogSnapshot {
        WakeLogSnapshot {
            events: vec![WakeEvent {
                kind,
                at_epoch_seconds: at,
                reason: reason.to_owned(),
            }],
            dark_wake_count_24h: i32::from(kind == WakeKind::Dark),
        }
    }

    fn holding_config() -> AppConfig {
        AppConfig {
            lid_sleep_immediate_on_close: false,
            ..AppConfig::default()
        }
    }

    #[test]
    fn start_scans_wake_log_and_updates_dark_wake_status() {
        let mut fixture = Fixture::with_wake(
            AppConfig::default(),
            Some(snapshot(WakeKind::Dark, 1_000, "RTC")),
        );
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Discharging,
            None,
        ));
        fixture.engine.start();
        assert_eq!(fixture.wake.reads(), 1);
        let status = &fixture.engine.current_state().dark_wake;
        assert!(status.available);
        assert_eq!(status.last_at_epoch_seconds, Some(1_000));
        assert_eq!(status.last_kind, Some(WakeKind::Dark));
        assert_eq!(status.last_reason.as_deref(), Some("RTC"));
        assert_eq!(status.count_24h, 1);
    }

    #[test]
    fn dark_wake_does_not_restore_sleep_now_restrictions() {
        let mut fixture = Fixture::with_wake(
            AppConfig::default(),
            Some(snapshot(WakeKind::Dark, 1_000, "Initial")),
        );
        fixture.privileged.set_installed(true);
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Discharging,
            None,
        ));
        fixture.engine.start();
        fixture.engine.set_idle_sleep_available(false);
        assert!(fixture.engine.set_lid_sleep_available(false));
        fixture.engine.sleep_now();
        assert!(fixture.engine.current_state().idle_sleep_available);
        assert!(fixture.engine.current_state().lid_sleep_available);
        fixture
            .wake
            .set_fallback(Some(snapshot(WakeKind::Dark, 2_000, "RTC")));
        fixture.engine.on_sleep_event(SleepEvent::WakeSignal);
        assert!(fixture.engine.current_state().idle_sleep_available);
        assert!(fixture.engine.current_state().lid_sleep_available);
        assert_eq!(
            fixture
                .engine
                .current_state()
                .dark_wake
                .last_at_epoch_seconds,
            Some(2_000)
        );
    }

    #[test]
    fn full_wake_restores_sleep_now_restrictions() {
        let mut fixture = Fixture::with_wake(
            AppConfig::default(),
            Some(snapshot(WakeKind::Dark, 1_000, "Initial")),
        );
        fixture.privileged.set_installed(true);
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Discharging,
            None,
        ));
        fixture.engine.start();
        fixture.engine.set_idle_sleep_available(false);
        assert!(fixture.engine.set_lid_sleep_available(false));
        fixture.engine.sleep_now();
        fixture
            .wake
            .set_fallback(Some(snapshot(WakeKind::Full, 2_000, "UserActivity")));
        fixture.engine.on_sleep_event(SleepEvent::WakeSignal);
        assert!(!fixture.engine.current_state().idle_sleep_available);
        assert!(!fixture.engine.current_state().lid_sleep_available);
    }

    #[test]
    fn wake_scan_retries_an_unchanged_log_snapshot() {
        let initial = snapshot(WakeKind::Dark, 1_000, "Initial");
        let updated = snapshot(WakeKind::Dark, 2_000, "RTC");
        let mut fixture = Fixture::with_wake(AppConfig::default(), None);
        fixture.wake.push(Some(initial.clone()));
        fixture.wake.push(Some(initial));
        fixture.wake.push(Some(updated));
        fixture.engine.start();
        fixture.engine.on_sleep_event(SleepEvent::WakeSignal);
        assert_eq!(fixture.wake.reads(), 3);
        assert_eq!(fixture.wake_delays.load(Ordering::SeqCst), 2);
        assert_eq!(
            fixture
                .engine
                .current_state()
                .dark_wake
                .last_at_epoch_seconds,
            Some(2_000)
        );
    }

    #[test]
    fn wake_log_failure_restores_restrictions_and_marks_status_unavailable() {
        let mut fixture = Fixture::with_wake(
            AppConfig::default(),
            Some(snapshot(WakeKind::Dark, 1_000, "Initial")),
        );
        fixture.privileged.set_installed(true);
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Discharging,
            None,
        ));
        fixture.engine.start();
        fixture.engine.set_idle_sleep_available(false);
        assert!(fixture.engine.set_lid_sleep_available(false));
        fixture.engine.sleep_now();
        fixture.wake.set_fallback(None);
        fixture.engine.on_sleep_event(SleepEvent::WakeSignal);
        assert!(!fixture.engine.current_state().dark_wake.available);
        assert!(!fixture.engine.current_state().idle_sleep_available);
        assert!(!fixture.engine.current_state().lid_sleep_available);
        assert!(fixture.logger.has("Wake log parsing failed"));
    }

    #[test]
    fn wake_log_refresh_is_cached_for_sixty_seconds() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture
            .wake
            .push(Some(snapshot(WakeKind::Dark, 1_000, "Initial")));
        fixture
            .wake
            .set_fallback(Some(snapshot(WakeKind::Dark, 2_000, "RTC")));
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Discharging,
            None,
        ));
        fixture.engine.start();
        assert_eq!(fixture.wake.reads(), 1);
        fixture.engine.stop();
        fixture.set_wake_cache_now(1_061_000);
        fixture.engine.start();
        assert_eq!(fixture.wake.reads(), 2);
        assert_eq!(
            fixture
                .engine
                .current_state()
                .dark_wake
                .last_at_epoch_seconds,
            Some(2_000)
        );
    }

    #[test]
    fn new_wake_event_bypasses_the_cache_and_failure_keeps_previous_status() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture
            .wake
            .set_fallback(Some(snapshot(WakeKind::Dark, 1_000, "Initial")));
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Discharging,
            None,
        ));
        fixture.engine.start();
        fixture.wake.set_fallback(Some(WakeLogSnapshot {
            events: vec![
                WakeEvent {
                    kind: WakeKind::Dark,
                    at_epoch_seconds: 1_000,
                    reason: "Initial".to_owned(),
                },
                WakeEvent {
                    kind: WakeKind::Full,
                    at_epoch_seconds: 2_000,
                    reason: "UserActivity".to_owned(),
                },
            ],
            dark_wake_count_24h: 1,
        }));
        fixture.engine.on_sleep_event(SleepEvent::WakeSignal);
        assert_eq!(
            fixture
                .engine
                .current_state()
                .dark_wake
                .last_reason
                .as_deref(),
            Some("UserActivity")
        );
        fixture.wake.set_fallback(None);
        fixture.engine.on_sleep_event(SleepEvent::WakeSignal);
        let status = &fixture.engine.current_state().dark_wake;
        assert!(!status.available);
        assert_eq!(status.last_at_epoch_seconds, Some(2_000));
        assert_eq!(status.last_reason.as_deref(), Some("UserActivity"));
        assert_eq!(status.count_24h, 1);
    }

    #[test]
    fn power_runtime_holds_lid_sleep() {
        let mut fixture = Fixture::new(holding_config());
        fixture.privileged.set_installed(true);
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Discharging,
            Some(3_600),
        ));
        fixture.engine.start();
        assert!(fixture.engine.set_power_lid_hold(true));
        assert!(!fixture.engine.current_state().lid_sleep_available);
        assert!(fixture.privileged.disable_sleep_values().contains(&true));
    }

    #[test]
    fn manual_lid_hold_is_released_on_request() {
        let mut fixture = Fixture::new(holding_config());
        fixture.privileged.set_installed(true);
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Discharging,
            Some(3_600),
        ));
        fixture.engine.start();
        fixture.engine.set_manual_lid_sleep_available(false);
        assert!(!fixture.engine.current_state().lid_sleep_available);
        fixture.engine.set_manual_lid_sleep_available(true);
        assert!(fixture.engine.current_state().lid_sleep_available);
    }

    #[test]
    fn low_battery_policy_overrides_power_runtime_lid_hold() {
        let config = AppConfig {
            low_battery_capacity: 10,
            lid_sleep_immediate_on_close: false,
            ..AppConfig::default()
        };
        let mut fixture = Fixture::new(config);
        fixture.privileged.set_installed(true);
        fixture.set_battery(battery(
            5,
            crate::power::models::PowerState::Discharging,
            Some(3_600),
        ));
        fixture.engine.start();
        assert!(!fixture.engine.set_power_lid_hold(true));
        assert_eq!(fixture.sleep.sleep_calls(), 1);
        assert!(fixture.engine.current_state().lid_sleep_available);
        assert!(!fixture.privileged.disable_sleep_values().contains(&true));
    }

    #[test]
    fn helper_failure_keeps_lid_sleep_available() {
        let mut fixture = Fixture::new(holding_config());
        fixture.privileged.set_installed(true);
        fixture.privileged.set_disable_sleep_result(false);
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Discharging,
            Some(3_600),
        ));
        fixture.engine.start();
        assert!(!fixture.engine.set_power_lid_hold(true));
        assert!(fixture.engine.current_state().lid_sleep_available);
    }

    #[test]
    fn low_battery_capacity_triggers_sleep_only_while_discharging() {
        let config = AppConfig {
            low_battery_capacity: 6,
            ..AppConfig::default()
        };
        let mut fixture = Fixture::new(config);
        fixture.set_battery(battery(
            6,
            crate::power::models::PowerState::Discharging,
            None,
        ));
        fixture.engine.start();
        assert_eq!(fixture.sleep.sleep_calls(), 1);
        fixture.set_battery(battery(5, crate::power::models::PowerState::Charging, None));
        fixture.engine.on_power_changed();
        assert_eq!(fixture.sleep.sleep_calls(), 1);
    }

    #[test]
    fn low_remaining_time_triggers_sleep() {
        let config = AppConfig {
            low_time_remaining_minutes: 10,
            ..AppConfig::default()
        };
        let mut fixture = Fixture::new(config);
        fixture.set_battery(battery(
            50,
            crate::power::models::PowerState::Discharging,
            Some(600),
        ));
        fixture.engine.start();
        assert_eq!(fixture.sleep.sleep_calls(), 1);
    }

    #[test]
    fn charging_rule_prevents_and_restores_idle_sleep() {
        let config = AppConfig {
            disable_idle_sleep_in_charging: true,
            ..AppConfig::default()
        };
        let mut fixture = Fixture::new(config);
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Charging,
            None,
        ));
        fixture.engine.start();
        assert!(!fixture.engine.current_state().idle_sleep_available);
        fixture.set_battery(battery(
            75,
            crate::power::models::PowerState::Discharging,
            Some(3_600),
        ));
        fixture.engine.on_power_changed();
        assert!(fixture.engine.current_state().idle_sleep_available);
    }

    #[test]
    fn power_lid_hold_is_skipped_when_helper_is_not_installed() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Charging,
            None,
        ));
        fixture.engine.start();
        assert!(!fixture.engine.set_power_lid_hold(true));
        assert!(fixture.engine.current_state().lid_sleep_available);
        assert!(fixture.privileged.disable_sleep_values().is_empty());
    }

    #[test]
    fn start_does_not_touch_sleep_disabled_when_helper_is_not_installed() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture.set_battery(battery(
            90,
            crate::power::models::PowerState::Discharging,
            None,
        ));
        fixture.engine.start();
        assert!(fixture.privileged.disable_sleep_values().is_empty());
    }

    #[test]
    fn helper_safe_mode_blocks_every_sleep_disabled_write() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture.privileged.set_installed(true);
        fixture
            .privileged
            .set_status(Some(HelperStatus::IdentityMismatch));
        assert!(!fixture.engine.set_lid_sleep_available(false));
        assert!(!fixture.engine.set_lid_sleep_available(true));
        assert!(fixture.privileged.disable_sleep_values().is_empty());
    }

    #[test]
    fn lid_close_sleeps_immediately_when_available() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Discharging,
            None,
        ));
        fixture.engine.start();
        fixture.lid.set(LidState::Closed);
        fixture.engine.on_lid_changed(LidState::Closed);
        assert_eq!(fixture.sleep.sleep_calls(), 1);
    }

    #[test]
    fn lid_close_only_turns_display_off_while_sleep_is_prevented() {
        let mut fixture = Fixture::new(holding_config());
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Charging,
            None,
        ));
        fixture.privileged.set_installed(true);
        fixture.engine.start();
        assert!(fixture.engine.set_lid_sleep_available(false));
        fixture.engine.on_lid_changed(LidState::Closed);
        assert_eq!(fixture.sleep.display_calls(), 1);
        assert_eq!(fixture.sleep.sleep_calls(), 0);
    }

    #[test]
    fn idle_compensation_sleeps_after_system_timeout() {
        let mut fixture = Fixture::new(holding_config());
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Charging,
            None,
        ));
        fixture.privileged.set_installed(true);
        fixture.engine.start();
        assert!(fixture.engine.set_lid_sleep_available(false));
        fixture.sleep.set_timeout(Some(60));
        fixture.idle.set(61);
        fixture.engine.tick();
        assert_eq!(fixture.sleep.sleep_calls(), 1);
    }

    #[test]
    fn cancel_timer_restores_idle_availability() {
        let mut fixture = Fixture::with_clock(AppConfig::default(), 1_000);
        fixture.engine.schedule_cancel_idle(300);
        assert!(!fixture.engine.current_state().idle_sleep_available);
        fixture.set_now(302_000);
        fixture.engine.tick();
        assert!(fixture.engine.current_state().idle_sleep_available);
    }

    #[test]
    fn display_idle_hold_exposes_the_readback_level() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture.engine.start();
        assert!(
            fixture
                .engine
                .set_idle_sleep_prevention(IdleSleepPrevention::SystemAndDisplay)
        );
        assert!(!fixture.engine.current_state().idle_sleep_available);
        assert_eq!(
            fixture.engine.current_state().idle_sleep_prevention,
            IdleSleepPrevention::SystemAndDisplay
        );
        assert_eq!(
            fixture.sleep.prevention(),
            IdleSleepPrevention::SystemAndDisplay
        );
    }

    #[test]
    fn assertion_failure_leaves_real_state_available_and_records_error() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture.engine.start();
        fixture.sleep.set_fail_assertion(true);
        assert!(
            !fixture
                .engine
                .set_idle_sleep_prevention(IdleSleepPrevention::System)
        );
        assert!(fixture.engine.current_state().idle_sleep_available);
        assert_eq!(
            fixture.engine.current_state().idle_sleep_prevention,
            IdleSleepPrevention::None
        );
        assert_eq!(
            fixture.engine.current_state().last_error.as_deref(),
            Some("assertion failure")
        );
    }

    #[test]
    fn idle_timer_expiry_keeps_a_separate_manual_hold() {
        let mut fixture = Fixture::with_clock(AppConfig::default(), 1_000);
        fixture.engine.start();
        fixture.engine.set_idle_sleep_available(false);
        fixture.engine.schedule_cancel_idle(300);
        fixture.set_now(302_000);
        fixture.engine.tick();
        assert!(!fixture.engine.current_state().idle_sleep_available);
        assert_eq!(
            fixture.engine.current_state().idle_sleep_prevention,
            IdleSleepPrevention::System
        );
    }

    #[test]
    fn manual_idle_off_leaves_the_charging_rule_active() {
        let config = AppConfig {
            disable_idle_sleep_in_charging: true,
            ..AppConfig::default()
        };
        let mut fixture = Fixture::new(config);
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Charging,
            None,
        ));
        fixture.engine.start();
        assert!(!fixture.engine.current_state().idle_sleep_available);
        fixture.engine.set_idle_sleep_available(false);
        fixture.engine.set_idle_sleep_available(true);
        assert!(!fixture.engine.current_state().idle_sleep_available);
        assert_eq!(
            fixture.engine.current_state().idle_sleep_prevention,
            IdleSleepPrevention::System
        );
    }

    #[test]
    fn sleep_now_temporarily_restores_restrictions_and_wake_restores_them() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture.privileged.set_installed(true);
        fixture.set_battery(battery(
            90,
            crate::power::models::PowerState::Charging,
            None,
        ));
        fixture.engine.start();
        fixture.engine.set_idle_sleep_available(false);
        assert!(fixture.engine.set_lid_sleep_available(false));
        assert!(!fixture.engine.current_state().idle_sleep_available);
        fixture.engine.sleep_now();
        assert_eq!(fixture.sleep.sleep_calls(), 1);
        assert!(fixture.engine.current_state().idle_sleep_available);
        assert!(fixture.engine.current_state().lid_sleep_available);
        fixture.engine.on_sleep_event(SleepEvent::WakeSignal);
        assert!(!fixture.engine.current_state().idle_sleep_available);
        assert!(!fixture.engine.current_state().lid_sleep_available);
    }

    #[test]
    fn power_leases_do_not_replace_a_manual_idle_hold() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture.engine.start();
        fixture.engine.set_idle_sleep_available(false);
        assert!(fixture.engine.replace_power_leases(&[HoldLease {
            id: "power".to_owned(),
            level: HoldLeaseLevel::SystemAndDisplay,
            source: HoldLeaseSource::Agent,
            reason: String::new(),
            created_at_epoch_seconds: 1,
            expires_at_epoch_seconds: None,
        }]));
        assert!(!fixture.engine.current_state().idle_sleep_available);
        assert!(fixture.engine.replace_power_leases(&[]));
        assert!(!fixture.engine.current_state().idle_sleep_available);
        assert_eq!(
            fixture.engine.current_state().idle_sleep_prevention,
            IdleSleepPrevention::System
        );
    }

    #[test]
    fn power_lid_hold_does_not_clear_a_manual_lid_hold() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture.privileged.set_installed(true);
        fixture.engine.start();
        fixture.engine.set_manual_lid_sleep_available(false);
        assert!(!fixture.engine.current_state().lid_sleep_available);
        fixture.engine.set_power_lid_hold(true);
        fixture.engine.set_power_lid_hold(false);
        assert!(!fixture.engine.current_state().lid_sleep_available);
    }

    #[test]
    fn helper_lease_expiry_updates_lid_availability() {
        let mut fixture = Fixture::with_clock(AppConfig::default(), 1_000);
        fixture.privileged.set_installed(true);
        fixture.engine.start();
        assert!(fixture.engine.set_lid_sleep_available(false));
        assert!(!fixture.engine.current_state().lid_sleep_available);
        fixture.privileged.set_sleep_disabled(false);
        fixture.set_now(6_000);
        fixture.engine.tick();
        assert!(fixture.engine.current_state().lid_sleep_available);
        assert_eq!(
            fixture
                .engine
                .current_state()
                .lid_lease_status
                .active_lease_count,
            0
        );
    }

    #[test]
    fn cancel_timer_restores_lid_availability() {
        let mut fixture = Fixture::with_clock(AppConfig::default(), 5_000);
        fixture.privileged.set_installed(true);
        fixture.engine.schedule_cancel_lid(600);
        assert!(!fixture.engine.current_state().lid_sleep_available);
        fixture.set_now(606_000);
        fixture.engine.tick();
        assert!(fixture.engine.current_state().lid_sleep_available);
    }

    #[test]
    fn stop_restores_sleep_availability_and_clears_sleep_disabled() {
        let mut fixture = Fixture::new(holding_config());
        fixture.privileged.set_installed(true);
        fixture.set_battery(battery(
            90,
            crate::power::models::PowerState::Charging,
            None,
        ));
        fixture.engine.start();
        fixture.engine.set_idle_sleep_available(false);
        assert!(fixture.engine.set_lid_sleep_available(false));
        assert!(fixture.privileged.disable_sleep_values().contains(&true));
        fixture.engine.stop();
        assert!(fixture.engine.current_state().idle_sleep_available);
        assert!(fixture.engine.current_state().lid_sleep_available);
        assert_eq!(fixture.sleep.prevention(), IdleSleepPrevention::None);
        assert_eq!(
            fixture.privileged.disable_sleep_values().last(),
            Some(&false)
        );
    }

    #[test]
    fn start_removes_a_stale_sleep_disabled_flag() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture.set_battery(battery(
            90,
            crate::power::models::PowerState::Discharging,
            None,
        ));
        fixture.privileged.set_installed(true);
        fixture.engine.start();
        assert!(fixture.privileged.disable_sleep_values().contains(&false));
    }

    #[test]
    fn unavailable_power_reading_degrades_to_unknown_without_fake_success() {
        let mut fixture = Fixture::new(AppConfig::default());
        fixture.set_battery(battery(
            80,
            crate::power::models::PowerState::Discharging,
            None,
        ));
        fixture.engine.start();
        fixture.engine.set_enabled(false);
        fixture.engine.set_enabled(true);
        assert!(fixture.engine.current_state().last_error.is_none());
    }
}

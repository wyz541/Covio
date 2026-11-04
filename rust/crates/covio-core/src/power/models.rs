//! Power, sleep, wake, lease, and engine state models.

use crate::AppConfig;

/// Battery power state.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum PowerState {
    /// Running on battery.
    Discharging,
    /// Charging.
    Charging,
    /// Fully charged.
    Charged,
    /// Connected to adapter power.
    AcPower,
    /// State is unknown.
    #[default]
    Unknown,
}

impl PowerState {
    /// Returns whether this state means adapter power is present.
    #[must_use]
    pub const fn is_charging(self) -> bool {
        matches!(self, Self::Charging | Self::Charged | Self::AcPower)
    }
}

/// Battery observation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BatteryStatus {
    /// Battery percentage.
    pub percent: i32,
    /// Power state.
    pub state: PowerState,
    /// Remaining seconds.
    pub remaining_seconds: Option<i64>,
}

impl BatteryStatus {
    /// Returns whether the battery is discharging.
    #[must_use]
    pub const fn is_discharging(self) -> bool {
        matches!(self.state, PowerState::Discharging)
    }
}

/// Lid state.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum LidState {
    /// State is unknown.
    #[default]
    Unknown,
    /// Lid is open.
    Open,
    /// Lid is closed.
    Closed,
}

/// App and helper release identity status.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum HelperStatus {
    /// App and helper identities match.
    Match,
    /// Helper is not installed.
    #[default]
    Missing,
    /// Helper version is old.
    Outdated,
    /// Helper identity does not match.
    IdentityMismatch,
    /// Helper trust cannot be established.
    Untrusted,
}

impl HelperStatus {
    /// Returns whether privileged writes are allowed.
    #[must_use]
    pub const fn allows_privileged_writes(self) -> bool {
        matches!(self, Self::Match)
    }
}

/// Sleep lifecycle event.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SleepEvent {
    /// System is about to sleep.
    WillSleep,
    /// System sent a wake signal.
    WakeSignal,
}

/// Wake event kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WakeKind {
    /// DarkWake event.
    Dark,
    /// Full wake event.
    Full,
}

/// One parsed wake event.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WakeEvent {
    /// Event kind.
    pub kind: WakeKind,
    /// Event time in Unix seconds.
    pub at_epoch_seconds: i64,
    /// Parsed reason.
    pub reason: String,
}

/// Parsed wake log.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct WakeLogSnapshot {
    /// Events in chronological order.
    pub events: Vec<WakeEvent>,
    /// Number of DarkWake events in the 24-hour window.
    pub dark_wake_count_24h: i32,
}

impl WakeLogSnapshot {
    /// Returns the newest event.
    #[must_use]
    pub fn latest(&self) -> Option<&WakeEvent> {
        self.events.last()
    }
}

/// DarkWake status exposed by the engine.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DarkWakeStatus {
    /// Whether the wake log is available.
    pub available: bool,
    /// Whether a scan is active.
    pub scanning: bool,
    /// Last event time.
    pub last_at_epoch_seconds: Option<i64>,
    /// Last event kind.
    pub last_kind: Option<WakeKind>,
    /// Last event reason.
    pub last_reason: Option<String>,
    /// DarkWake count in the last 24 hours.
    pub count_24h: i32,
}

/// Thermal state.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ThermalState {
    /// Nominal.
    Nominal,
    /// Fair.
    Fair,
    /// Serious.
    Serious,
    /// Critical.
    Critical,
    /// Unknown.
    #[default]
    Unknown,
}

/// One power observation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PowerObservation {
    /// Battery percentage.
    pub battery_percent: Option<i32>,
    /// Whether a battery exists.
    pub has_battery: Option<bool>,
    /// Power state.
    pub power_state: PowerState,
    /// External display count.
    pub external_display_count: Option<i32>,
    /// Lid state.
    pub lid_state: LidState,
    /// Thermal state.
    pub thermal_state: ThermalState,
    /// Low Power Mode.
    pub low_power_mode_enabled: Option<bool>,
}

impl Default for PowerObservation {
    fn default() -> Self {
        Self {
            battery_percent: None,
            has_battery: None,
            power_state: PowerState::Unknown,
            external_display_count: None,
            lid_state: LidState::Unknown,
            thermal_state: ThermalState::Unknown,
            low_power_mode_enabled: None,
        }
    }
}

impl PowerObservation {
    /// Returns a normalized copy.
    #[must_use]
    pub fn normalized(&self) -> Self {
        let valid_percent = self
            .battery_percent
            .filter(|percent| (0..=100).contains(percent))
            .filter(|_| self.has_battery != Some(false));
        Self {
            battery_percent: valid_percent,
            external_display_count: self.external_display_count.filter(|count| *count >= 0),
            ..self.clone()
        }
    }
}

/// Complete policy input.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PowerSnapshot {
    /// OS observation.
    pub observation: PowerObservation,
    /// Helper identity status.
    pub helper_status: HelperStatus,
    /// Current SleepDisabled value.
    pub sleep_disabled: Option<bool>,
    /// Whether Covio owns SleepDisabled.
    pub covio_owns_sleep_disabled: Option<bool>,
}

impl PowerSnapshot {
    /// Returns a normalized copy.
    #[must_use]
    pub fn normalized(&self) -> Self {
        Self {
            observation: self.observation.normalized(),
            ..self.clone()
        }
    }
}

/// Lease source.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HoldLeaseSource {
    /// Manual user action.
    Manual,
    /// Timed action.
    Timer,
    /// Automatic rule.
    Rule,
    /// Power policy agent.
    Agent,
    /// Test source.
    Test,
}

/// Lease strength.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum HoldLeaseLevel {
    /// System idle sleep prevention.
    System,
    /// System and display idle sleep prevention.
    SystemAndDisplay,
    /// Closed-lid prevention.
    ClosedLid,
}

/// One runtime hold lease.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HoldLease {
    /// Lease id.
    pub id: String,
    /// Lease strength.
    pub level: HoldLeaseLevel,
    /// Lease source.
    pub source: HoldLeaseSource,
    /// Human-readable reason.
    pub reason: String,
    /// Creation time in Unix seconds.
    pub created_at_epoch_seconds: i64,
    /// Expiration time in Unix seconds.
    pub expires_at_epoch_seconds: Option<i64>,
}

/// Covio idle-sleep assertion.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum IdleSleepPrevention {
    /// Readback unknown.
    #[default]
    Unknown,
    /// No prevention.
    None,
    /// System idle sleep prevention.
    System,
    /// System and display idle sleep prevention.
    SystemAndDisplay,
}

impl IdleSleepPrevention {
    /// Returns whether any prevention is active.
    #[must_use]
    pub const fn is_active(self) -> bool {
        matches!(self, Self::System | Self::SystemAndDisplay)
    }
}

/// Result of applying one idle-sleep assertion.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IdleSleepAssertionResult {
    /// Requested assertion.
    pub requested: IdleSleepPrevention,
    /// Actual assertion.
    pub actual: IdleSleepPrevention,
    /// Whether the request succeeded.
    pub success: bool,
    /// Failure reason.
    pub error: Option<String>,
}

/// Complete hold-lease manager snapshot.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct HoldLeaseSnapshot {
    /// Active leases sorted by creation time and id.
    pub leases: Vec<HoldLease>,
    /// Desired assertion.
    pub desired_prevention: IdleSleepPrevention,
    /// Actual assertion.
    pub actual_prevention: IdleSleepPrevention,
    /// Whether assertions are suspended.
    pub suspended: bool,
    /// Last operation error.
    pub last_error: Option<String>,
}

/// Helper lid-lease status.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct LidLeaseStatus {
    /// Whether helper status is available.
    pub available: bool,
    /// Helper protocol version.
    pub protocol_version: Option<String>,
    /// SleepDisabled value.
    pub sleep_disabled: Option<bool>,
    /// Whether Covio owns SleepDisabled.
    pub covio_owned: Option<bool>,
    /// Active helper lease count.
    pub active_lease_count: i32,
    /// Earliest expiry.
    pub expires_at_epoch_seconds: Option<i64>,
    /// Error text.
    pub error: Option<String>,
}

impl LidLeaseStatus {
    /// Returns whether a Covio-owned lease is active.
    #[must_use]
    pub fn lease_active(&self) -> bool {
        self.active_lease_count > 0 && self.covio_owned == Some(true)
    }
}

/// Safety reason that blocks a power decision.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SafetyVeto {
    /// Power management is disabled.
    PowerDisabled,
    /// The user paused power management.
    ExplicitlyPaused,
    /// Battery floor reached.
    BatteryFloor,
    /// Thermal state is serious.
    ThermalSerious,
    /// Thermal state is critical.
    ThermalCritical,
    /// Low Power Mode is active.
    LowPowerMode,
    /// Closed-lid time cap reached.
    ClosedLidTimeCap,
    /// Closed-lid behavior is disabled.
    ClosedLidDisabled,
    /// Helper is unavailable.
    HelperUnavailable,
    /// Battery state is unknown.
    BatteryStateUnknown,
    /// External display is connected.
    ExternalDisplayConnected,
    /// External display state is unknown.
    ExternalDisplayUnknown,
    /// SleepDisabled state is unknown.
    SleepDisabledStateUnknown,
    /// External tool owns SleepDisabled.
    ExternalSleepDisabledConflict,
}

/// One pure power-policy decision.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PowerDecision {
    /// Prevent system idle sleep.
    pub prevent_user_idle_system_sleep: bool,
    /// Prevent display idle sleep.
    pub prevent_user_idle_display_sleep: bool,
    /// Prevent lid sleep.
    pub prevent_lid_sleep: bool,
    /// Applied lease level.
    pub applied_lease_level: Option<HoldLeaseLevel>,
    /// Active lease ids.
    pub active_lease_ids: Vec<String>,
    /// Whether the automatic power rule is active.
    pub automatic_rule_applied: bool,
    /// Safety veto reasons.
    pub safety_vetoes: Vec<SafetyVeto>,
    /// Battery guard latch for the next decision.
    pub battery_guard_latched: bool,
}

impl PowerDecision {
    /// Returns whether all sleep prevention is released.
    #[must_use]
    pub const fn sleep_allowed(&self) -> bool {
        !self.prevent_user_idle_system_sleep
            && !self.prevent_user_idle_display_sleep
            && !self.prevent_lid_sleep
    }
}

/// Runtime state exposed by the engine.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppState {
    /// Last battery reading.
    pub battery: Option<BatteryStatus>,
    /// Last lid state.
    pub lid: LidState,
    /// Whether power management is enabled.
    pub enabled: bool,
    /// Whether idle sleep is currently available.
    pub idle_sleep_available: bool,
    /// Actual idle sleep prevention.
    pub idle_sleep_prevention: IdleSleepPrevention,
    /// Whether lid sleep is currently available.
    pub lid_sleep_available: bool,
    /// Idle timer remaining seconds.
    pub idle_cancel_remaining_seconds: Option<i64>,
    /// Lid timer remaining seconds.
    pub lid_cancel_remaining_seconds: Option<i64>,
    /// DarkWake status.
    pub dark_wake: DarkWakeStatus,
    /// Helper identity status.
    pub helper_status: HelperStatus,
    /// Helper lid-lease status.
    pub lid_lease_status: LidLeaseStatus,
    /// Last error.
    pub last_error: Option<String>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            battery: None,
            lid: LidState::Unknown,
            enabled: true,
            idle_sleep_available: true,
            idle_sleep_prevention: IdleSleepPrevention::None,
            lid_sleep_available: true,
            idle_cancel_remaining_seconds: None,
            lid_cancel_remaining_seconds: None,
            dark_wake: DarkWakeStatus::default(),
            helper_status: HelperStatus::Missing,
            lid_lease_status: LidLeaseStatus::default(),
            last_error: None,
        }
    }
}

/// Returns whether the battery triggers the low-battery policy.
#[must_use]
pub fn low_battery_sleep_required(config: &AppConfig, battery: BatteryStatus) -> bool {
    if !config.low_battery_capacity_sleep || !battery.is_discharging() {
        return false;
    }
    let low_capacity = battery.percent <= config.low_battery_capacity;
    let low_remaining = battery
        .remaining_seconds
        .is_some_and(|remaining| remaining <= i64::from(config.low_time_remaining_minutes) * 60);
    low_capacity || low_remaining
}

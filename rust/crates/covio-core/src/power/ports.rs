//! OS capability ports consumed by the power engine.

use super::models::{
    AppState, BatteryStatus, IdleSleepAssertionResult, IdleSleepPrevention, LidLeaseStatus,
    LidState, SleepEvent, WakeLogSnapshot,
};
use covio_platform::PlatformError;

/// Battery observation capability.
pub trait PowerSource {
    /// Reads the current battery state.
    fn read(&self) -> Result<Option<BatteryStatus>, PlatformError>;
}

/// Lid state capability.
pub trait LidSensor {
    /// Reads the current lid state.
    fn read(&self) -> Result<LidState, PlatformError>;
}

/// Idle-time capability.
pub trait IdleSensor {
    /// Returns system idle seconds.
    fn idle_seconds(&self) -> Result<i64, PlatformError>;
}

/// Sleep and idle assertion capability.
pub trait SleepController {
    /// Requests system sleep.
    fn sleep(&self) -> Result<(), PlatformError>;
    /// Requests display sleep.
    fn display_sleep(&self) -> Result<(), PlatformError>;
    /// Applies and reads back an idle assertion.
    fn apply_idle_sleep_prevention(
        &self,
        prevention: IdleSleepPrevention,
    ) -> Result<IdleSleepAssertionResult, PlatformError>;
    /// Reads the current Covio assertion.
    fn read_idle_sleep_prevention(&self) -> Result<IdleSleepPrevention, PlatformError>;
    /// Returns the system idle timeout in seconds.
    fn system_idle_sleep_timeout_seconds(&self) -> Result<Option<i64>, PlatformError>;
}

/// Privileged helper capability.
pub trait PrivilegedOps {
    /// Returns whether the helper is installed.
    fn is_installed(&self) -> Result<bool, PlatformError>;
    /// Returns release identity status.
    fn status(&self) -> Result<super::models::HelperStatus, PlatformError>;
    /// Returns helper version.
    fn helper_version(&self) -> Result<Option<String>, PlatformError>;
    /// Installs the helper.
    fn install(&self) -> Result<bool, PlatformError>;
    /// Uninstalls the helper.
    fn uninstall(&self) -> Result<bool, PlatformError>;
    /// Writes SleepDisabled.
    fn set_disable_sleep(&self, disabled: bool) -> Result<bool, PlatformError>;
    /// Reads helper lid-lease status.
    fn lid_lease_status(&self) -> Result<LidLeaseStatus, PlatformError>;
    /// Reads hibernate mode.
    fn hibernate_mode(&self) -> Result<Option<i32>, PlatformError>;
    /// Writes hibernate mode.
    fn set_hibernate_mode(&self, mode: i32) -> Result<bool, PlatformError>;
}

/// Wake log capability.
pub trait WakeLogReader {
    /// Reads and parses the wake log.
    fn read(&self) -> Result<Option<WakeLogSnapshot>, PlatformError>;
}

/// Logging capability.
pub trait AppLogger {
    /// Logs an informational message.
    fn info(&self, message: &str);
    /// Logs a warning.
    fn warn(&self, message: &str);
    /// Logs an error.
    fn error(&self, message: &str);
}

/// Engine state listener.
pub trait StateListener {
    /// Receives a state snapshot.
    fn on_state(&self, state: &AppState);
}

/// Sleep event source contract. Platform hosts call `Engine::on_sleep_event`.
pub trait SleepWatcher {
    /// Handles one sleep event.
    fn on_event(&self, event: SleepEvent);
}

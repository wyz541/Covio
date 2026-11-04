//! Pure charge-limit state machine.

use serde::{Deserialize, Serialize};

/// Minimum selectable charge limit.
pub const CHARGE_LIMIT_MIN_PERCENT: i32 = 40;
/// Maximum selectable charge limit.
pub const CHARGE_LIMIT_MAX_PERCENT: i32 = 100;
/// Charge-limit step.
pub const CHARGE_LIMIT_STEP_PERCENT: i32 = 5;
/// Hysteresis from the limit back to charging.
pub const CHARGE_LIMIT_HYSTERESIS_PERCENT: i32 = 5;
/// Lowest resume threshold.
pub const CHARGE_LIMIT_MIN_RESUME_PERCENT: i32 = 35;
/// Default charge limit.
pub const DEFAULT_CHARGE_LIMIT_PERCENT: i32 = 70;

/// MCL support state.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ChargeLimitSupport {
    /// Supported.
    #[default]
    Supported,
    /// Unsupported.
    Unsupported,
    /// Unknown.
    Unknown,
}

/// User-visible policy phase.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ChargeLimitPhase {
    /// Disabled.
    Off,
    /// No battery.
    NoBattery,
    /// Adapter is disconnected.
    Unplugged,
    /// A write is pending.
    Applying,
    /// Active discharge is running.
    Discharging,
    /// Active discharge is stopping.
    StoppingDischarge,
    /// Charging toward the limit.
    Charging,
    /// Holding without charging.
    Sailing,
    /// At the limit.
    Holding,
    /// Above the limit without active discharge.
    AboveLimit,
    /// Battery is full.
    Full,
    /// Calibration is active.
    Calibration,
    /// System protection is active.
    SystemProtection,
    /// External conflict.
    Conflict,
    /// Error.
    Error,
    /// Unsupported.
    Unsupported,
    /// Helper missing.
    HelperMissing,
}

/// Helper write action.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ChargeLimitAction {
    /// No write.
    None,
    /// Set a target.
    SetTarget,
    /// Release the target.
    ReleaseTarget,
}

/// Charge-limit observation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChargeLimitObservation {
    /// Policy enabled.
    pub enabled: bool,
    /// Upper limit.
    pub upper_limit_percent: i32,
    /// Adapter present.
    pub adapter_connected: bool,
    /// Raw state of charge.
    pub current_percent: Option<i32>,
    /// Helper installed.
    #[serde(default = "default_true")]
    pub helper_installed: bool,
    /// MCL support.
    #[serde(default)]
    pub support: ChargeLimitSupport,
    /// Battery exists.
    #[serde(default = "default_true")]
    pub battery_present: bool,
    /// Charged flag.
    #[serde(default)]
    pub is_charged: bool,
    /// Calibration flag.
    #[serde(default)]
    pub calibration_active: bool,
    /// System protection flag.
    #[serde(default)]
    pub system_protection_active: bool,
    /// External conflict.
    #[serde(default)]
    pub conflict: bool,
    /// Error text.
    pub error_message: Option<String>,
    /// Observed target.
    pub observed_target_percent: Option<i32>,
    /// Write in progress.
    #[serde(default)]
    pub write_pending: bool,
    /// Bypass was engaged.
    #[serde(default)]
    pub bypass_engaged: bool,
    /// Active discharge enabled.
    #[serde(default)]
    pub active_discharge_enabled: bool,
    /// Active discharge running.
    #[serde(default)]
    pub actively_discharging: bool,
}

const fn default_true() -> bool {
    true
}

/// Persisted policy latch.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChargeLimitPolicyState {
    /// Charging latch.
    pub charging_latch: bool,
}

/// One policy decision.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChargeLimitDecision {
    /// Phase.
    pub phase: ChargeLimitPhase,
    /// Action.
    pub action: ChargeLimitAction,
    /// Target.
    pub target_percent: Option<i32>,
    /// Resume threshold.
    pub resume_threshold_percent: i32,
    /// Charging latch.
    pub charging_latch: bool,
    /// Bypass engaged.
    pub bypass_engaged: bool,
    /// Error text.
    pub error_message: Option<String>,
}

/// Returns whether a limit is valid.
#[must_use]
pub const fn is_valid_upper_limit(percent: i32) -> bool {
    percent >= CHARGE_LIMIT_MIN_PERCENT
        && percent <= CHARGE_LIMIT_MAX_PERCENT
        && percent % CHARGE_LIMIT_STEP_PERCENT == 0
}

/// Falls invalid values back to the default.
#[must_use]
pub const fn normalize_upper_limit(percent: i32) -> i32 {
    if is_valid_upper_limit(percent) {
        percent
    } else {
        DEFAULT_CHARGE_LIMIT_PERCENT
    }
}

/// Returns the charging resume threshold.
#[must_use]
pub const fn resume_threshold(upper_limit_percent: i32) -> i32 {
    let candidate = upper_limit_percent - CHARGE_LIMIT_HYSTERESIS_PERCENT;
    if candidate > CHARGE_LIMIT_MIN_RESUME_PERCENT {
        candidate
    } else {
        CHARGE_LIMIT_MIN_RESUME_PERCENT
    }
}

/// Evaluates one policy observation.
#[must_use]
pub fn evaluate(
    observation: &ChargeLimitObservation,
    previous: ChargeLimitPolicyState,
) -> ChargeLimitDecision {
    let upper = observation.upper_limit_percent;
    let resume = if is_valid_upper_limit(upper) {
        resume_threshold(upper)
    } else {
        0
    };
    let make = |phase,
                latch: bool,
                action: ChargeLimitAction,
                target_percent: Option<i32>,
                error_message: Option<String>| ChargeLimitDecision {
        phase,
        action,
        target_percent,
        resume_threshold_percent: resume,
        charging_latch: latch,
        bypass_engaged: false,
        error_message,
    };

    if !is_valid_upper_limit(upper) {
        return make(
            ChargeLimitPhase::Error,
            previous.charging_latch,
            ChargeLimitAction::None,
            None,
            Some("充电上限必须是 40 到 100 之间的 5% 档位".to_owned()),
        );
    }
    if !observation.enabled {
        return make(
            ChargeLimitPhase::Off,
            false,
            ChargeLimitAction::None,
            None,
            None,
        );
    }
    if !observation.helper_installed {
        return make(
            ChargeLimitPhase::HelperMissing,
            previous.charging_latch,
            ChargeLimitAction::None,
            None,
            None,
        );
    }
    if observation.support == ChargeLimitSupport::Unsupported {
        return make(
            ChargeLimitPhase::Unsupported,
            previous.charging_latch,
            ChargeLimitAction::None,
            None,
            None,
        );
    }
    if observation.support == ChargeLimitSupport::Unknown {
        return make(
            ChargeLimitPhase::Error,
            previous.charging_latch,
            ChargeLimitAction::None,
            None,
            Some("无法确认 MCL 能力".to_owned()),
        );
    }
    if let Some(message) = &observation.error_message {
        return make(
            ChargeLimitPhase::Error,
            previous.charging_latch,
            ChargeLimitAction::None,
            None,
            Some(message.clone()),
        );
    }
    if !observation.battery_present {
        return make(
            ChargeLimitPhase::NoBattery,
            false,
            ChargeLimitAction::None,
            None,
            None,
        );
    }
    if observation.system_protection_active {
        return make(
            ChargeLimitPhase::SystemProtection,
            previous.charging_latch,
            ChargeLimitAction::None,
            None,
            None,
        );
    }
    if observation.calibration_active {
        return make(
            ChargeLimitPhase::Calibration,
            previous.charging_latch,
            ChargeLimitAction::None,
            None,
            None,
        );
    }
    let Some(current) = observation.current_percent else {
        return make(
            ChargeLimitPhase::Error,
            previous.charging_latch,
            ChargeLimitAction::None,
            None,
            Some("无法读取电池电量".to_owned()),
        );
    };
    if !observation.adapter_connected {
        return make(
            ChargeLimitPhase::Unplugged,
            false,
            ChargeLimitAction::None,
            None,
            None,
        );
    }
    if observation.conflict {
        return make(
            ChargeLimitPhase::Conflict,
            previous.charging_latch,
            ChargeLimitAction::None,
            None,
            None,
        );
    }

    let current = current.clamp(0, 100);
    let raw = if upper == CHARGE_LIMIT_MAX_PERCENT {
        let full = observation.is_charged || current >= CHARGE_LIMIT_MAX_PERCENT;
        make(
            if full {
                ChargeLimitPhase::Full
            } else {
                ChargeLimitPhase::Charging
            },
            false,
            ChargeLimitAction::ReleaseTarget,
            None,
            None,
        )
    } else if current > upper {
        let target = if observation.active_discharge_enabled {
            upper
        } else {
            current
        };
        let phase = if observation.active_discharge_enabled {
            ChargeLimitPhase::Discharging
        } else if observation.actively_discharging {
            ChargeLimitPhase::StoppingDischarge
        } else {
            ChargeLimitPhase::AboveLimit
        };
        make(
            phase,
            false,
            ChargeLimitAction::SetTarget,
            Some(target),
            None,
        )
    } else if current == upper {
        make(
            ChargeLimitPhase::Holding,
            false,
            ChargeLimitAction::SetTarget,
            Some(current),
            None,
        )
    } else if previous.charging_latch || current <= resume {
        make(
            ChargeLimitPhase::Charging,
            true,
            ChargeLimitAction::SetTarget,
            Some(upper),
            None,
        )
    } else {
        make(
            ChargeLimitPhase::Sailing,
            false,
            ChargeLimitAction::SetTarget,
            Some(current),
            None,
        )
    };

    let action = if observation.write_pending {
        ChargeLimitAction::None
    } else {
        match raw.action {
            ChargeLimitAction::ReleaseTarget if observation.observed_target_percent.is_none() => {
                ChargeLimitAction::None
            }
            ChargeLimitAction::SetTarget
                if observation.observed_target_percent == raw.target_percent =>
            {
                ChargeLimitAction::None
            }
            action => action,
        }
    };
    let phase = if observation.write_pending || action != ChargeLimitAction::None {
        ChargeLimitPhase::Applying
    } else {
        raw.phase
    };
    let holding = matches!(
        phase,
        ChargeLimitPhase::Sailing | ChargeLimitPhase::Holding | ChargeLimitPhase::AboveLimit
    );
    ChargeLimitDecision {
        phase,
        action,
        bypass_engaged: observation.bypass_engaged && holding,
        ..raw
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn observation(upper: i32, current: i32) -> ChargeLimitObservation {
        ChargeLimitObservation {
            enabled: true,
            upper_limit_percent: upper,
            adapter_connected: true,
            current_percent: Some(current),
            helper_installed: true,
            support: ChargeLimitSupport::Supported,
            battery_present: true,
            is_charged: false,
            calibration_active: false,
            system_protection_active: false,
            conflict: false,
            error_message: None,
            observed_target_percent: None,
            write_pending: false,
            bypass_engaged: false,
            active_discharge_enabled: false,
            actively_discharging: false,
        }
    }

    #[test]
    fn limits_use_five_point_steps_from_forty_to_one_hundred() {
        for percent in 40..=100 {
            assert_eq!(is_valid_upper_limit(percent), percent % 5 == 0);
        }
        assert_eq!(normalize_upper_limit(79), 70);
        assert_eq!(resume_threshold(40), 35);
        assert_eq!(resume_threshold(70), 65);
    }

    #[test]
    fn policy_applies_charging_hysteresis_and_write_deduplication() {
        let mut value = observation(70, 64);
        value.observed_target_percent = Some(70);
        let decision = evaluate(
            &value,
            ChargeLimitPolicyState {
                charging_latch: true,
            },
        );
        assert_eq!(decision.phase, ChargeLimitPhase::Charging);
        assert_eq!(decision.action, ChargeLimitAction::None);
        assert!(decision.charging_latch);

        value.current_percent = Some(70);
        let decision = evaluate(
            &value,
            ChargeLimitPolicyState {
                charging_latch: true,
            },
        );
        assert_eq!(decision.phase, ChargeLimitPhase::Holding);
    }

    #[test]
    fn safety_states_precede_normal_charging() {
        let mut value = observation(70, 50);
        value.system_protection_active = true;
        assert_eq!(
            evaluate(&value, ChargeLimitPolicyState::default()).phase,
            ChargeLimitPhase::SystemProtection
        );
        value.system_protection_active = false;
        value.conflict = true;
        assert_eq!(
            evaluate(&value, ChargeLimitPolicyState::default()).phase,
            ChargeLimitPhase::Conflict
        );
    }
}

//! Pure power policy evaluation.

use super::models::{
    HoldLease, HoldLeaseLevel, IdleSleepPrevention, PowerDecision, PowerObservation, PowerSnapshot,
    PowerState, SafetyVeto, ThermalState,
};
use crate::PowerConfig;

/// Evaluates the current power policy.
#[must_use]
pub fn decide(
    config: &PowerConfig,
    snapshot: &PowerSnapshot,
    leases: &[HoldLease],
    now_epoch_seconds: i64,
    paused: bool,
    battery_guard_latched: bool,
) -> PowerDecision {
    let config = config.normalized();
    let snapshot = snapshot.normalized();
    let observation = &snapshot.observation;
    let next_battery_guard_latched =
        next_battery_guard_latched(&config, observation, battery_guard_latched);

    if !config.enabled {
        return blocked(vec![SafetyVeto::PowerDisabled], next_battery_guard_latched);
    }
    if paused {
        return blocked(
            vec![SafetyVeto::ExplicitlyPaused],
            next_battery_guard_latched,
        );
    }
    let safety_vetoes = safety_vetoes(&config, observation, next_battery_guard_latched);
    if !safety_vetoes.is_empty() {
        return blocked(safety_vetoes, next_battery_guard_latched);
    }

    let cap_reached = leases.iter().any(|lease| {
        lease.level == HoldLeaseLevel::ClosedLid
            && !deadline_reached(lease, now_epoch_seconds)
            && closed_lid_cap_reached(lease, &config, now_epoch_seconds)
    });
    let active_leases: Vec<_> = leases
        .iter()
        .filter(|lease| is_lease_active(lease, &config, now_epoch_seconds))
        .cloned()
        .collect();
    let lid_veto = if active_leases
        .iter()
        .any(|lease| lease.level == HoldLeaseLevel::ClosedLid)
    {
        closed_lid_veto(&config, &snapshot)
    } else {
        None
    };
    let usable_leases: Vec<_> = active_leases
        .iter()
        .filter(|lease| !(lease.level == HoldLeaseLevel::ClosedLid && lid_veto.is_some()))
        .cloned()
        .collect();
    let has_closed_lid = usable_leases
        .iter()
        .any(|lease| lease.level == HoldLeaseLevel::ClosedLid);
    let has_display = usable_leases
        .iter()
        .any(|lease| lease.level == HoldLeaseLevel::SystemAndDisplay);
    let applied_level = if has_closed_lid {
        Some(HoldLeaseLevel::ClosedLid)
    } else if has_display {
        Some(HoldLeaseLevel::SystemAndDisplay)
    } else if !usable_leases.is_empty() {
        Some(HoldLeaseLevel::System)
    } else {
        None
    };
    let mut vetoes = Vec::new();
    if cap_reached {
        vetoes.push(SafetyVeto::ClosedLidTimeCap);
    }
    if let Some(veto) = lid_veto {
        vetoes.push(veto);
    }

    if let Some(level) = applied_level {
        return decision_for(
            level,
            has_display,
            active_leases
                .iter()
                .map(|lease| lease.id.clone())
                .filter(|id| !id.is_empty())
                .collect(),
            false,
            vetoes,
            next_battery_guard_latched,
        );
    }
    if automatic_rule_applies(&config, observation) {
        return decision_for(
            HoldLeaseLevel::System,
            false,
            Vec::new(),
            true,
            vetoes,
            next_battery_guard_latched,
        );
    }
    PowerDecision {
        safety_vetoes: vetoes,
        battery_guard_latched: next_battery_guard_latched,
        ..PowerDecision::default()
    }
}

fn safety_vetoes(
    config: &PowerConfig,
    observation: &PowerObservation,
    battery_guard_latched: bool,
) -> Vec<SafetyVeto> {
    let mut vetoes = Vec::new();
    if battery_guard_latched {
        vetoes.push(SafetyVeto::BatteryFloor);
    }
    if config.heat_guard_enabled && observation.thermal_state == ThermalState::Serious {
        vetoes.push(SafetyVeto::ThermalSerious);
    }
    if observation.thermal_state == ThermalState::Critical {
        vetoes.push(SafetyVeto::ThermalCritical);
    }
    if config.yield_on_low_power_mode && observation.low_power_mode_enabled == Some(true) {
        vetoes.push(SafetyVeto::LowPowerMode);
    }
    vetoes
}

fn next_battery_guard_latched(
    config: &PowerConfig,
    observation: &PowerObservation,
    previous: bool,
) -> bool {
    let Some(percent) = observation.battery_percent else {
        return false;
    };
    if observation.power_state.is_charging() {
        return false;
    }
    if percent <= config.battery_floor_percent {
        return true;
    }
    previous && percent < config.battery_floor_recovery_percent
}

fn closed_lid_veto(config: &PowerConfig, snapshot: &PowerSnapshot) -> Option<SafetyVeto> {
    let observation = &snapshot.observation;
    if !config.allow_closed_lid {
        return Some(SafetyVeto::ClosedLidDisabled);
    }
    if snapshot.helper_status != super::models::HelperStatus::Match {
        return Some(SafetyVeto::HelperUnavailable);
    }
    if observation.has_battery != Some(false) && observation.battery_percent.is_none() {
        return Some(SafetyVeto::BatteryStateUnknown);
    }
    if config.pause_closed_lid_with_external_display {
        match observation.external_display_count {
            None => return Some(SafetyVeto::ExternalDisplayUnknown),
            Some(count) if count > 0 => return Some(SafetyVeto::ExternalDisplayConnected),
            Some(_) => {}
        }
    }
    match snapshot.sleep_disabled {
        None => Some(SafetyVeto::SleepDisabledStateUnknown),
        Some(true) if snapshot.covio_owns_sleep_disabled != Some(true) => {
            Some(SafetyVeto::ExternalSleepDisabledConflict)
        }
        Some(_) => None,
    }
}

fn is_lease_active(lease: &HoldLease, config: &PowerConfig, now_epoch_seconds: i64) -> bool {
    !lease.id.trim().is_empty()
        && !deadline_reached(lease, now_epoch_seconds)
        && !(lease.level == HoldLeaseLevel::ClosedLid
            && closed_lid_cap_reached(lease, config, now_epoch_seconds))
}

fn deadline_reached(lease: &HoldLease, now_epoch_seconds: i64) -> bool {
    lease
        .expires_at_epoch_seconds
        .is_some_and(|expires| expires <= now_epoch_seconds)
}

fn closed_lid_cap_reached(lease: &HoldLease, config: &PowerConfig, now_epoch_seconds: i64) -> bool {
    if lease.level != HoldLeaseLevel::ClosedLid {
        return false;
    }
    let created_at = lease.created_at_epoch_seconds;
    if created_at <= 0 || now_epoch_seconds < created_at {
        return true;
    }
    now_epoch_seconds - created_at >= i64::from(config.closed_lid_time_cap_minutes) * 60
}

fn automatic_rule_applies(config: &PowerConfig, observation: &PowerObservation) -> bool {
    match observation.power_state {
        PowerState::Discharging => config.keep_awake_on_battery,
        PowerState::Charging | PowerState::Charged | PowerState::AcPower => {
            config.keep_awake_on_adapter
        }
        PowerState::Unknown => false,
    }
}

fn decision_for(
    level: HoldLeaseLevel,
    display_sleep_prevention: bool,
    active_lease_ids: Vec<String>,
    automatic_rule_applied: bool,
    safety_vetoes: Vec<SafetyVeto>,
    battery_guard_latched: bool,
) -> PowerDecision {
    PowerDecision {
        prevent_user_idle_system_sleep: true,
        prevent_user_idle_display_sleep: display_sleep_prevention,
        prevent_lid_sleep: level == HoldLeaseLevel::ClosedLid,
        applied_lease_level: if automatic_rule_applied {
            None
        } else {
            Some(level)
        },
        active_lease_ids,
        automatic_rule_applied,
        safety_vetoes,
        battery_guard_latched,
    }
}

fn blocked(safety_vetoes: Vec<SafetyVeto>, battery_guard_latched: bool) -> PowerDecision {
    PowerDecision {
        safety_vetoes,
        battery_guard_latched,
        ..PowerDecision::default()
    }
}

/// Returns the dormant prevention when an engine is stopped.
#[must_use]
pub const fn no_prevention() -> IdleSleepPrevention {
    IdleSleepPrevention::None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::PowerConfig;

    const NOW: i64 = 2_000;

    fn config() -> PowerConfig {
        PowerConfig::default()
    }

    fn base_snapshot() -> PowerSnapshot {
        PowerSnapshot {
            observation: PowerObservation {
                battery_percent: Some(80),
                has_battery: Some(true),
                power_state: PowerState::Charging,
                external_display_count: Some(0),
                lid_state: crate::power::models::LidState::Open,
                thermal_state: ThermalState::Nominal,
                low_power_mode_enabled: Some(false),
            },
            helper_status: crate::power::models::HelperStatus::Match,
            sleep_disabled: Some(false),
            covio_owns_sleep_disabled: None,
        }
    }

    fn battery_snapshot(percent: i32) -> PowerSnapshot {
        let mut snapshot = base_snapshot();
        snapshot.observation.battery_percent = Some(percent);
        snapshot.observation.power_state = PowerState::Discharging;
        snapshot
    }

    fn lease(level: HoldLeaseLevel) -> HoldLease {
        HoldLease {
            id: "lease".to_owned(),
            level,
            source: crate::power::models::HoldLeaseSource::Manual,
            reason: String::new(),
            created_at_epoch_seconds: 1_000,
            expires_at_epoch_seconds: None,
        }
    }

    fn named_lease(level: HoldLeaseLevel, id: &str) -> HoldLease {
        HoldLease {
            id: id.to_owned(),
            ..lease(level)
        }
    }

    fn evaluate(
        config: &PowerConfig,
        snapshot: &PowerSnapshot,
        leases: &[HoldLease],
        now: i64,
        paused: bool,
        battery_guard_latched: bool,
    ) -> PowerDecision {
        decide(config, snapshot, leases, now, paused, battery_guard_latched)
    }

    fn decide_one(
        config: &PowerConfig,
        snapshot: &PowerSnapshot,
        lease: HoldLease,
    ) -> PowerDecision {
        evaluate(config, snapshot, &[lease], NOW, false, false)
    }

    #[test]
    fn power_defaults_match_the_reviewed_surface() {
        let value = PowerConfig::default();
        assert!(value.enabled);
        assert!(value.keep_awake_on_adapter);
        assert!(!value.keep_awake_on_battery);
        assert!(value.allow_closed_lid);
        assert!(value.pause_closed_lid_with_external_display);
        assert_eq!(value.battery_floor_percent, 15);
        assert_eq!(value.battery_floor_recovery_percent, 20);
        assert!(value.yield_on_low_power_mode);
        assert!(value.heat_guard_enabled);
        assert_eq!(value.closed_lid_time_cap_minutes, 240);
    }

    #[test]
    fn disabled_power_blocks_leases_and_automatic_rules() {
        let value = PowerConfig {
            enabled: false,
            ..config()
        };
        let decision = decide_one(
            &value,
            &base_snapshot(),
            lease(HoldLeaseLevel::SystemAndDisplay),
        );
        assert!(decision.sleep_allowed());
        assert_eq!(decision.safety_vetoes, [SafetyVeto::PowerDisabled]);
    }

    #[test]
    fn runtime_pause_blocks_leases_and_automatic_rules() {
        let decision = evaluate(
            &config(),
            &base_snapshot(),
            &[lease(HoldLeaseLevel::ClosedLid)],
            NOW,
            true,
            false,
        );
        assert!(decision.sleep_allowed());
        assert_eq!(decision.safety_vetoes, [SafetyVeto::ExplicitlyPaused]);
    }

    #[test]
    fn multiple_leases_merge_at_the_highest_level() {
        let decision = evaluate(
            &config(),
            &base_snapshot(),
            &[
                named_lease(HoldLeaseLevel::System, "manual"),
                named_lease(HoldLeaseLevel::SystemAndDisplay, "timer"),
            ],
            NOW,
            false,
            false,
        );
        assert!(decision.prevent_user_idle_system_sleep);
        assert!(decision.prevent_user_idle_display_sleep);
        assert!(!decision.prevent_lid_sleep);
        assert_eq!(
            decision.applied_lease_level,
            Some(HoldLeaseLevel::SystemAndDisplay)
        );
        assert_eq!(decision.active_lease_ids, ["manual", "timer"]);
    }

    #[test]
    fn closed_lid_holds_system_and_lid_but_not_display() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let decision = decide_one(&value, &base_snapshot(), lease(HoldLeaseLevel::ClosedLid));
        assert!(decision.prevent_user_idle_system_sleep);
        assert!(!decision.prevent_user_idle_display_sleep);
        assert!(decision.prevent_lid_sleep);
        assert_eq!(
            decision.applied_lease_level,
            Some(HoldLeaseLevel::ClosedLid)
        );
        assert!(decision.safety_vetoes.is_empty());
    }

    #[test]
    fn closed_lid_keeps_a_separate_display_lease() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let decision = evaluate(
            &value,
            &base_snapshot(),
            &[
                named_lease(HoldLeaseLevel::SystemAndDisplay, "display"),
                named_lease(HoldLeaseLevel::ClosedLid, "lid"),
            ],
            NOW,
            false,
            false,
        );
        assert!(decision.prevent_user_idle_system_sleep);
        assert!(decision.prevent_user_idle_display_sleep);
        assert!(decision.prevent_lid_sleep);
        assert_eq!(
            decision.applied_lease_level,
            Some(HoldLeaseLevel::ClosedLid)
        );
        assert_eq!(decision.active_lease_ids, ["display", "lid"]);
    }

    #[test]
    fn expired_lease_falls_back_to_an_automatic_rule() {
        let mut expired = lease(HoldLeaseLevel::SystemAndDisplay);
        expired.expires_at_epoch_seconds = Some(NOW);
        let decision = decide_one(&config(), &base_snapshot(), expired);
        assert!(decision.prevent_user_idle_system_sleep);
        assert!(!decision.prevent_user_idle_display_sleep);
        assert!(decision.automatic_rule_applied);
        assert_eq!(decision.applied_lease_level, None);
    }

    #[test]
    fn closed_lid_requires_the_installed_helper() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let mut snapshot = base_snapshot();
        snapshot.helper_status = crate::power::models::HelperStatus::Missing;
        let decision = decide_one(&value, &snapshot, lease(HoldLeaseLevel::ClosedLid));
        assert!(decision.sleep_allowed());
        assert_eq!(decision.safety_vetoes, [SafetyVeto::HelperUnavailable]);
    }

    #[test]
    fn every_helper_safe_mode_blocks_closed_lid_writes() {
        use crate::power::models::HelperStatus;
        for status in [
            HelperStatus::Missing,
            HelperStatus::Outdated,
            HelperStatus::IdentityMismatch,
            HelperStatus::Untrusted,
        ] {
            let value = PowerConfig {
                keep_awake_on_adapter: false,
                ..config()
            };
            let mut snapshot = base_snapshot();
            snapshot.helper_status = status;
            let decision = decide_one(&value, &snapshot, lease(HoldLeaseLevel::ClosedLid));
            assert!(decision.sleep_allowed(), "{status:?}");
            assert_eq!(
                decision.safety_vetoes,
                [SafetyVeto::HelperUnavailable],
                "{status:?}"
            );
        }
    }

    #[test]
    fn closed_lid_rule_can_disable_a_closed_lid_lease() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            allow_closed_lid: false,
            ..config()
        };
        let decision = decide_one(&value, &base_snapshot(), lease(HoldLeaseLevel::ClosedLid));
        assert!(decision.sleep_allowed());
        assert_eq!(decision.safety_vetoes, [SafetyVeto::ClosedLidDisabled]);
    }

    #[test]
    fn external_display_pauses_a_closed_lid_lease() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let mut snapshot = base_snapshot();
        snapshot.observation.external_display_count = Some(1);
        let decision = decide_one(&value, &snapshot, lease(HoldLeaseLevel::ClosedLid));
        assert!(decision.sleep_allowed());
        assert_eq!(
            decision.safety_vetoes,
            [SafetyVeto::ExternalDisplayConnected]
        );
    }

    #[test]
    fn unknown_external_display_state_fails_closed() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let mut snapshot = base_snapshot();
        snapshot.observation.external_display_count = None;
        let decision = decide_one(&value, &snapshot, lease(HoldLeaseLevel::ClosedLid));
        assert!(decision.sleep_allowed());
        assert_eq!(decision.safety_vetoes, [SafetyVeto::ExternalDisplayUnknown]);
    }

    #[test]
    fn lower_lease_remains_active_when_a_closed_lid_lease_is_vetoed() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let mut snapshot = base_snapshot();
        snapshot.observation.external_display_count = Some(1);
        let decision = evaluate(
            &value,
            &snapshot,
            &[
                named_lease(HoldLeaseLevel::System, "system"),
                named_lease(HoldLeaseLevel::ClosedLid, "lid"),
            ],
            NOW,
            false,
            false,
        );
        assert!(decision.prevent_user_idle_system_sleep);
        assert!(!decision.prevent_lid_sleep);
        assert_eq!(decision.applied_lease_level, Some(HoldLeaseLevel::System));
        assert_eq!(
            decision.safety_vetoes,
            [SafetyVeto::ExternalDisplayConnected]
        );
    }

    #[test]
    fn closed_lid_state_is_unknown_until_sleep_disabled_is_readable() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let mut snapshot = base_snapshot();
        snapshot.sleep_disabled = None;
        let decision = decide_one(&value, &snapshot, lease(HoldLeaseLevel::ClosedLid));
        assert!(decision.sleep_allowed());
        assert_eq!(
            decision.safety_vetoes,
            [SafetyVeto::SleepDisabledStateUnknown]
        );
    }

    #[test]
    fn external_sleep_disabled_state_is_not_covio_ownership() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let mut snapshot = base_snapshot();
        snapshot.sleep_disabled = Some(true);
        snapshot.covio_owns_sleep_disabled = Some(false);
        let decision = decide_one(&value, &snapshot, lease(HoldLeaseLevel::ClosedLid));
        assert!(decision.sleep_allowed());
        assert_eq!(
            decision.safety_vetoes,
            [SafetyVeto::ExternalSleepDisabledConflict]
        );
    }

    #[test]
    fn covio_owned_sleep_disabled_permits_a_closed_lid_lease() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let mut snapshot = base_snapshot();
        snapshot.sleep_disabled = Some(true);
        snapshot.covio_owns_sleep_disabled = Some(true);
        let decision = decide_one(&value, &snapshot, lease(HoldLeaseLevel::ClosedLid));
        assert!(decision.prevent_lid_sleep);
        assert!(decision.safety_vetoes.is_empty());
    }

    #[test]
    fn unknown_battery_capacity_prevents_a_closed_lid_lease() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let mut snapshot = base_snapshot();
        snapshot.observation.battery_percent = None;
        snapshot.observation.has_battery = Some(true);
        let decision = decide_one(&value, &snapshot, lease(HoldLeaseLevel::ClosedLid));
        assert!(decision.sleep_allowed());
        assert_eq!(decision.safety_vetoes, [SafetyVeto::BatteryStateUnknown]);
    }

    #[test]
    fn battery_guard_latches_at_the_floor_and_clears_only_at_recovery() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let system = lease(HoldLeaseLevel::System);
        let at_floor = decide_one(&value, &battery_snapshot(15), system.clone());
        assert!(at_floor.sleep_allowed());
        assert!(at_floor.battery_guard_latched);
        assert_eq!(at_floor.safety_vetoes, [SafetyVeto::BatteryFloor]);
        let below_recovery = evaluate(
            &value,
            &battery_snapshot(19),
            std::slice::from_ref(&system),
            NOW,
            false,
            at_floor.battery_guard_latched,
        );
        assert!(below_recovery.sleep_allowed());
        assert!(below_recovery.battery_guard_latched);
        let at_recovery = evaluate(
            &value,
            &battery_snapshot(20),
            &[system],
            NOW,
            false,
            below_recovery.battery_guard_latched,
        );
        assert!(at_recovery.prevent_user_idle_system_sleep);
        assert!(!at_recovery.battery_guard_latched);
        assert!(at_recovery.safety_vetoes.is_empty());
    }

    #[test]
    fn adapter_power_clears_a_latched_battery_guard() {
        let mut snapshot = battery_snapshot(5);
        snapshot.observation.power_state = PowerState::Charging;
        let decision = evaluate(
            &config(),
            &snapshot,
            &[lease(HoldLeaseLevel::System)],
            NOW,
            false,
            true,
        );
        assert!(decision.prevent_user_idle_system_sleep);
        assert!(!decision.battery_guard_latched);
        assert!(decision.safety_vetoes.is_empty());
    }

    #[test]
    fn thermal_critical_always_releases_every_lease() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            heat_guard_enabled: false,
            ..config()
        };
        let mut snapshot = base_snapshot();
        snapshot.observation.thermal_state = ThermalState::Critical;
        let decision = decide_one(&value, &snapshot, lease(HoldLeaseLevel::SystemAndDisplay));
        assert!(decision.sleep_allowed());
        assert_eq!(decision.safety_vetoes, [SafetyVeto::ThermalCritical]);
    }

    #[test]
    fn thermal_serious_applies_only_when_the_heat_guard_is_enabled() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let mut snapshot = base_snapshot();
        snapshot.observation.thermal_state = ThermalState::Serious;
        let blocked = decide_one(&value, &snapshot, lease(HoldLeaseLevel::System));
        assert!(blocked.sleep_allowed());
        assert_eq!(blocked.safety_vetoes, [SafetyVeto::ThermalSerious]);
        let allowed = decide_one(
            &PowerConfig {
                heat_guard_enabled: false,
                ..value
            },
            &snapshot,
            lease(HoldLeaseLevel::System),
        );
        assert!(allowed.prevent_user_idle_system_sleep);
    }

    #[test]
    fn low_power_mode_yields_when_configured() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let mut snapshot = base_snapshot();
        snapshot.observation.low_power_mode_enabled = Some(true);
        let blocked = decide_one(&value, &snapshot, lease(HoldLeaseLevel::System));
        assert!(blocked.sleep_allowed());
        assert_eq!(blocked.safety_vetoes, [SafetyVeto::LowPowerMode]);
        let allowed = decide_one(
            &PowerConfig {
                yield_on_low_power_mode: false,
                ..value
            },
            &snapshot,
            lease(HoldLeaseLevel::System),
        );
        assert!(allowed.prevent_user_idle_system_sleep);
    }

    #[test]
    fn automatic_adapter_and_battery_rules_create_a_system_hold() {
        let adapter = evaluate(
            &PowerConfig {
                keep_awake_on_adapter: true,
                keep_awake_on_battery: false,
                ..config()
            },
            &base_snapshot(),
            &[],
            NOW,
            false,
            false,
        );
        assert!(adapter.prevent_user_idle_system_sleep);
        assert!(!adapter.prevent_user_idle_display_sleep);
        assert!(adapter.automatic_rule_applied);
        let battery = evaluate(
            &PowerConfig {
                keep_awake_on_adapter: false,
                keep_awake_on_battery: true,
                ..config()
            },
            &battery_snapshot(80),
            &[],
            NOW,
            false,
            false,
        );
        assert!(battery.prevent_user_idle_system_sleep);
        assert!(battery.automatic_rule_applied);
    }

    #[test]
    fn unknown_state_defaults_to_allowing_sleep() {
        let decision = evaluate(&config(), &PowerSnapshot::default(), &[], NOW, false, false);
        assert!(decision.sleep_allowed());
        assert!(!decision.automatic_rule_applied);
        assert_eq!(decision.applied_lease_level, None);
    }

    #[test]
    fn ordinary_lease_expiry_is_not_reported_as_a_safety_cap() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            ..config()
        };
        let mut expired = lease(HoldLeaseLevel::ClosedLid);
        expired.expires_at_epoch_seconds = Some(NOW);
        let decision = decide_one(&value, &base_snapshot(), expired);
        assert!(decision.sleep_allowed());
        assert!(decision.safety_vetoes.is_empty());
    }

    #[test]
    fn closed_lid_time_cap_expires_the_lease() {
        let value = PowerConfig {
            keep_awake_on_adapter: false,
            closed_lid_time_cap_minutes: 1,
            ..config()
        };
        let mut closed = lease(HoldLeaseLevel::ClosedLid);
        closed.created_at_epoch_seconds = 1_000;
        let decision = evaluate(&value, &base_snapshot(), &[closed], 1_060, false, false);
        assert!(decision.sleep_allowed());
        assert_eq!(decision.safety_vetoes, [SafetyVeto::ClosedLidTimeCap]);
    }

    #[test]
    fn invalid_observations_become_unknown_instead_of_clamped_values() {
        let normalized = PowerObservation {
            battery_percent: Some(101),
            has_battery: Some(true),
            external_display_count: Some(-1),
            ..PowerObservation::default()
        }
        .normalized();
        assert_eq!(normalized.battery_percent, None);
        assert_eq!(normalized.external_display_count, None);
        let no_battery = PowerObservation {
            battery_percent: Some(80),
            has_battery: Some(false),
            ..PowerObservation::default()
        }
        .normalized();
        assert_eq!(no_battery.battery_percent, None);
    }

    #[test]
    fn normalization_keeps_a_recovery_gap_and_valid_time_cap() {
        let normalized = PowerConfig {
            battery_floor_percent: 105,
            battery_floor_recovery_percent: -1,
            closed_lid_time_cap_minutes: 0,
            ..config()
        }
        .normalized();
        assert_eq!(normalized.battery_floor_percent, 99);
        assert_eq!(normalized.battery_floor_recovery_percent, 100);
        assert_eq!(normalized.closed_lid_time_cap_minutes, 1);
    }
}

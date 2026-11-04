//! Pure parsers for `pmset` output.

use super::models::{WakeEvent, WakeKind, WakeLogSnapshot};
use regex::Regex;
use std::sync::OnceLock;

/// Parses current `pmset -g` settings.
pub struct PmsetConfigParser;

impl PmsetConfigParser {
    /// Returns the smallest non-zero sleep timeout in seconds.
    #[must_use]
    pub fn sleep_timeout_seconds(text: Option<&str>) -> Option<i64> {
        let pattern = Regex::new(r"(?m)^\s*sleep\s+(\d+)\s*$").ok()?;
        let smallest = pattern
            .captures_iter(text?)
            .filter_map(|capture| capture.get(1)?.as_str().parse::<i64>().ok())
            .min()?;
        let seconds = smallest.saturating_mul(60);
        (seconds > 0).then_some(seconds)
    }

    /// Returns the first hibernate mode.
    #[must_use]
    pub fn hibernate_mode(text: Option<&str>) -> Option<i32> {
        let pattern = Regex::new(r"(?m)^\s*hibernatemode\s+(\d+)\s*$").ok()?;
        pattern.captures(text?)?.get(1)?.as_str().parse().ok()
    }

    /// Returns the first SleepDisabled value.
    #[must_use]
    pub fn sleep_disabled(text: Option<&str>) -> Option<bool> {
        let pattern = Regex::new(r"(?im)^\s*(?:disablesleep|sleepdisabled)\s+([01])\s*$").ok()?;
        match pattern.captures(text?)?.get(1)?.as_str() {
            "0" => Some(false),
            "1" => Some(true),
            _ => None,
        }
    }
}

/// Parses `pmset -g log` wake entries.
pub struct PmsetWakeLogParser;

impl PmsetWakeLogParser {
    /// Parses wake events retained by the 24-hour window.
    #[must_use]
    pub fn parse(text: &str, now_epoch_seconds: i64) -> WakeLogSnapshot {
        let cutoff = now_epoch_seconds.saturating_sub(24 * 60 * 60);
        let future_limit = now_epoch_seconds.saturating_add(5 * 60);
        let timestamp_pattern = timestamp_pattern();
        let reason_pattern = reason_pattern();
        let mut events = Vec::new();
        for raw_line in text.lines() {
            let line = raw_line.trim();
            let Some(captures) = timestamp_pattern.captures(line) else {
                continue;
            };
            let Some(timestamp) = captures.get(1).map(|value| value.as_str()) else {
                continue;
            };
            let Some(at_epoch_seconds) = Self::parse_timestamp(timestamp) else {
                continue;
            };
            if at_epoch_seconds < cutoff || at_epoch_seconds > future_limit {
                continue;
            }
            let Some(remainder) = captures.get(2).map(|value| value.as_str()) else {
                continue;
            };
            let Some(kind) = classify(remainder) else {
                continue;
            };
            let reason = reason_pattern
                .captures(remainder)
                .and_then(|capture| capture.get(1))
                .map_or("", |value| value.as_str())
                .trim()
                .to_owned();
            events.push(WakeEvent {
                kind,
                at_epoch_seconds,
                reason,
            });
        }
        events.sort_by_key(|event| event.at_epoch_seconds);
        let dark_wake_count_24h = events
            .iter()
            .filter(|event| event.kind == WakeKind::Dark)
            .count() as i32;
        WakeLogSnapshot {
            events,
            dark_wake_count_24h,
        }
    }

    /// Parses `yyyy-MM-dd HH:mm:ss +0800` into Unix seconds.
    #[must_use]
    pub fn parse_timestamp(value: &str) -> Option<i64> {
        let pattern = raw_timestamp_pattern();
        let captures = pattern.captures(value.trim())?;
        let number =
            |index: usize| -> Option<i64> { captures.get(index)?.as_str().parse::<i64>().ok() };
        let year = i32::try_from(number(1)?).ok()?;
        let month = i32::try_from(number(2)?).ok()?;
        let day = i32::try_from(number(3)?).ok()?;
        let hour = number(4)?;
        let minute = number(5)?;
        let second = number(6)?;
        let offset_hours = number(8)?;
        let offset_minutes = number(9)?;
        if !(1..=12).contains(&month)
            || !(1..=days_in_month(year, month)).contains(&day)
            || !(0..=23).contains(&hour)
            || !(0..=59).contains(&minute)
            || !(0..=60).contains(&second)
            || !(0..=23).contains(&offset_hours)
            || !(0..=59).contains(&offset_minutes)
        {
            return None;
        }
        let local_seconds = days_from_civil(year, month, day)
            .saturating_mul(86_400)
            .saturating_add(hour * 3_600)
            .saturating_add(minute * 60)
            .saturating_add(second);
        let sign = if captures.get(7)?.as_str() == "-" {
            -1
        } else {
            1
        };
        let offset_seconds = (offset_hours * 3_600 + offset_minutes * 60) * sign;
        Some(local_seconds - offset_seconds)
    }
}

fn timestamp_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        Regex::new(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4})\s+(.+)$")
            .expect("timestamp regex")
    })
}

fn raw_timestamp_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| {
        Regex::new(r"^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})$")
            .expect("raw timestamp regex")
    })
}

fn reason_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN
        .get_or_init(|| Regex::new(r"(?i)\bdue to\s+(.+?)(?:\s+Using\s|$)").expect("reason regex"))
}

fn classify(remainder: &str) -> Option<WakeKind> {
    let event_text = remainder.split(" from ").next().unwrap_or(remainder).trim();
    let dark_to_full = Regex::new(r"(?i)\bDarkWake\s+to\s+FullWake\b").ok()?;
    let full_wake = Regex::new(r"(?i)(?:^|\s)Wake(?:\s|\[|$)").ok()?;
    let dark_wake = Regex::new(r"(?i)(?:^|\s)DarkWake(?:\s|\[|$)").ok()?;
    if dark_to_full.is_match(event_text) || full_wake.is_match(event_text) {
        Some(WakeKind::Full)
    } else if dark_wake.is_match(event_text) {
        Some(WakeKind::Dark)
    } else {
        None
    }
}

fn is_leap_year(year: i32) -> bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

fn days_in_month(year: i32, month: i32) -> i32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if is_leap_year(year) => 29,
        2 => 28,
        _ => 0,
    }
}

fn days_from_civil(year: i32, month: i32, day: i32) -> i64 {
    let adjusted_year = if month <= 2 { year - 1 } else { year };
    let era = if adjusted_year >= 0 {
        adjusted_year
    } else {
        adjusted_year - 399
    } / 400;
    let year_of_era = adjusted_year - era * 400;
    let day_of_year = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    i64::from(era) * 146_097 + i64::from(day_of_era) - 719_468
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: i64 = 1_791_439_200;

    #[test]
    fn config_parser_reads_the_smallest_non_zero_sleep_timeout() {
        let real_output = r#"System-wide power settings:
Currently in use:
 lidwake              1
 sleep                10
 hibernatemode        3
 disksleep            10
AC Power:
 sleep                1
 hibernatemode        3"#;
        assert_eq!(
            PmsetConfigParser::sleep_timeout_seconds(Some(" sleep                10\n")),
            Some(600)
        );
        assert_eq!(
            PmsetConfigParser::sleep_timeout_seconds(Some(real_output)),
            Some(60)
        );
        assert_eq!(
            PmsetConfigParser::sleep_timeout_seconds(Some("\t  sleep\t5\t\n")),
            Some(300)
        );
        assert_eq!(PmsetConfigParser::sleep_timeout_seconds(None), None);
        assert_eq!(
            PmsetConfigParser::sleep_timeout_seconds(Some(" sleep                0\n")),
            None
        );
        assert_eq!(
            PmsetConfigParser::sleep_timeout_seconds(Some(" disksleep            10\n")),
            None
        );
        assert_eq!(
            PmsetConfigParser::sleep_timeout_seconds(Some(
                " sleep                1 (sleep prevented by powerd)\n"
            )),
            None
        );
        assert_eq!(
            PmsetConfigParser::sleep_timeout_seconds(Some(" sleep                2")),
            Some(120)
        );
    }

    #[test]
    fn config_parser_reads_hibernate_and_sleep_disabled_values() {
        let real_output = " sleep 10\n hibernatemode 3\n SleepDisabled\t\t0\n";
        assert_eq!(
            PmsetConfigParser::hibernate_mode(Some(real_output)),
            Some(3)
        );
        assert_eq!(PmsetConfigParser::hibernate_mode(None), None);
        assert_eq!(PmsetConfigParser::hibernate_mode(Some(" sleep 10\n")), None);
        assert_eq!(
            PmsetConfigParser::sleep_disabled(Some(real_output)),
            Some(false)
        );
        assert_eq!(
            PmsetConfigParser::sleep_disabled(Some(" disablesleep         1\n")),
            Some(true)
        );
        assert_eq!(
            PmsetConfigParser::sleep_disabled(Some(" disablesleep         0")),
            Some(false)
        );
        assert_eq!(
            PmsetConfigParser::sleep_disabled(Some(" disablesleep         yes\n")),
            None
        );
        assert_eq!(PmsetConfigParser::sleep_disabled(None), None);
    }

    #[test]
    fn wake_parser_classifies_events_and_extracts_reasons() {
        let text = r#"2026-10-08 11:18:14 +0800 DarkWake DarkWake from Deep Idle [CDNP] : due to NUB.SPMISw3IRQ Using BATT (Charge:80%) 2 secs
2026-10-08 12:20:00 +0800 Wake Wake from Deep Idle [CDNVA] : due to USB-C_plug Using AC (Charge:80%)
2026-10-08 13:34:53 +0800 Wake DarkWake to FullWake from Deep Idle [CDNVA] : due to UserActivity Assertion Using AC (Charge:80%) 141 secs"#;
        let snapshot = PmsetWakeLogParser::parse(text, NOW);
        assert_eq!(snapshot.events.len(), 3);
        assert_eq!(snapshot.events[0].kind, WakeKind::Dark);
        assert_eq!(snapshot.events[0].reason, "NUB.SPMISw3IRQ");
        assert_eq!(snapshot.events[1].kind, WakeKind::Full);
        assert_eq!(snapshot.events[1].reason, "USB-C_plug");
        assert_eq!(snapshot.events[2].kind, WakeKind::Full);
        assert_eq!(snapshot.events[2].reason, "UserActivity Assertion");
        assert_eq!(snapshot.dark_wake_count_24h, 1);
    }

    #[test]
    fn wake_parser_accepts_real_tab_separated_lines() {
        let text = "2026-10-08 11:01:01 +0800 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to NUB.SPMISw3IRQ nub-spmi0.0x02 rtc/Maintenance Using BATT (Charge:80%) 6 secs\n2026-10-08 13:34:53 +0800 Wake                \tWake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) USB-C_plug SMC.OutboxNotEmpty/Notification Using AC (Charge:80%)";
        let snapshot = PmsetWakeLogParser::parse(text, NOW);
        assert_eq!(snapshot.events.len(), 2);
        assert_eq!(
            snapshot.events[0].reason,
            "NUB.SPMISw3IRQ nub-spmi0.0x02 rtc/Maintenance"
        );
        assert_eq!(
            snapshot.events[1].reason,
            "smc.sysState.Wake(0x70070000) USB-C_plug SMC.OutboxNotEmpty/Notification"
        );
        assert_eq!(snapshot.dark_wake_count_24h, 1);
    }

    #[test]
    fn wake_parser_uses_an_inclusive_twenty_four_hour_window() {
        let now = 1_791_475_200;
        let text = "2026-10-07 23:59:59 +0800 DarkWake DarkWake from Deep Idle : due to Old\n2026-10-08 00:00:00 +0800 DarkWake DarkWake from Deep Idle : due to Boundary";
        let snapshot = PmsetWakeLogParser::parse(text, now);
        assert_eq!(snapshot.events.len(), 1);
        assert_eq!(snapshot.events[0].reason, "Boundary");
        assert_eq!(snapshot.dark_wake_count_24h, 1);
    }

    #[test]
    fn wake_parser_ignores_malformed_sleep_and_future_lines() {
        let text = "not a timestamp\n2026-10-08 13:00:00 +0800 Sleep Sleep from Idle : due to Idle\n2026-10-08 13:01:00 +0800 Wake Wake from Deep Idle : due to User\n2026-10-08 14:06:00 +0800 Wake Wake from Deep Idle : due to Future";
        let snapshot = PmsetWakeLogParser::parse(text, NOW);
        assert_eq!(snapshot.events.len(), 1);
        assert_eq!(snapshot.events[0].kind, WakeKind::Full);
        assert_eq!(
            PmsetWakeLogParser::parse("�\nnoise\n", NOW),
            WakeLogSnapshot::default()
        );
    }

    #[test]
    fn timestamp_conversion_matches_reference_values() {
        let cases = [
            ("2026-10-08 14:00:00 +0800", 1_791_439_200),
            ("1970-01-01 00:00:00 +0000", 0),
            ("2024-02-29 12:00:00 -0500", 1_709_226_000),
            ("2000-03-01 00:00:00 +0000", 951_868_800),
            ("2026-01-01 00:00:00 -0800", 1_767_254_400),
            ("1969-12-31 23:59:59 +0000", -1),
            ("1900-01-01 00:00:00 +0000", -2_208_988_800),
        ];
        for (value, expected) in cases {
            assert_eq!(PmsetWakeLogParser::parse_timestamp(value), Some(expected));
        }
    }

    #[test]
    fn timestamp_conversion_validates_calendar_and_format() {
        for value in [
            "1900-02-29 00:00:00 +0000",
            "2026-02-29 00:00:00 +0000",
            "2026-02-30 00:00:00 +0000",
            "2026-13-01 00:00:00 +0000",
            "2026-00-10 00:00:00 +0000",
            "2026-10-00 00:00:00 +0000",
            "2026-10-08 24:00:00 +0000",
            "2026-10-08 00:60:00 +0000",
            "",
            "not a timestamp",
            "2026-10-08 00:00:00",
            "2026-10-08 00:00:00 Z",
            "2026-10-08T00:00:00+0000",
            "20261008 000000 +0000",
        ] {
            assert_eq!(PmsetWakeLogParser::parse_timestamp(value), None);
        }
        assert_eq!(
            PmsetWakeLogParser::parse_timestamp("2000-03-01 00:00:00 +0000"),
            Some(
                PmsetWakeLogParser::parse_timestamp("2000-02-29 00:00:00 +0000").unwrap() + 86_400
            )
        );
    }

    #[test]
    fn timestamp_conversion_applies_the_offset_sign() {
        let utc = PmsetWakeLogParser::parse_timestamp("2026-10-08 12:00:00 +0000").unwrap();
        assert_eq!(
            PmsetWakeLogParser::parse_timestamp("2026-10-08 12:00:00 +0800"),
            Some(utc - 8 * 3_600)
        );
        assert_eq!(
            PmsetWakeLogParser::parse_timestamp("2026-10-08 12:00:00 -0500"),
            Some(utc + 5 * 3_600)
        );
        assert_eq!(
            PmsetWakeLogParser::parse_timestamp("2026-10-08 12:00:00 +0530"),
            Some(utc - 11 * 1_800)
        );
    }
}

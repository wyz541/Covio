//! Privileged helper JSON wire contract.

use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Map;
use std::fmt;

/// Helper protocol version.
pub const HELPER_PROTOCOL_VERSION: &str = "10";
/// Maximum request bytes.
pub const MAX_REQUEST_BYTES: usize = 64 * 1024;
/// Maximum reply bytes.
pub const MAX_REPLY_BYTES: usize = 64 * 1024;
/// Socket mode bits.
pub const SOCKET_PERMISSIONS: u32 = 0x1b6;
/// Maximum helper lease id length.
pub const HELPER_LEASE_ID_MAX_LENGTH: usize = 128;
/// Maximum active helper leases.
pub const HELPER_LEASE_MAX_ACTIVE: usize = 16;
/// Default lease duration in seconds.
pub const HELPER_LEASE_DURATION_SECONDS: i64 = 60;
/// Lease renewal interval in seconds.
pub const HELPER_LEASE_RENEW_SECONDS: i64 = 15;

/// Version command.
pub const COMMAND_VERSION: &str = "version";
/// Disable sleep command.
pub const COMMAND_SET_DISABLE_SLEEP: &str = "setDisableSleep";
/// Hibernate mode command.
pub const COMMAND_SET_HIBERNATE_MODE: &str = "setHibernateMode";
/// Lid lease acquire command.
pub const COMMAND_LID_LEASE_ACQUIRE: &str = "lidLeaseAcquire";
/// Lid lease renew command.
pub const COMMAND_LID_LEASE_RENEW: &str = "lidLeaseRenew";
/// Lid lease release command.
pub const COMMAND_LID_LEASE_RELEASE: &str = "lidLeaseRelease";
/// Lid lease status command.
pub const COMMAND_LID_LEASE_STATUS: &str = "lidLeaseStatus";
/// Charge-limit status command.
pub const COMMAND_CHARGE_LIMIT_STATUS: &str = "chargeLimitStatus";
/// Charge-limit configure command.
pub const COMMAND_CHARGE_LIMIT_CONFIGURE: &str = "chargeLimitConfigure";
/// Charge-limit restore command.
pub const COMMAND_CHARGE_LIMIT_RESTORE: &str = "chargeLimitRestore";
/// Fan status command.
pub const COMMAND_FAN_CONTROL_STATUS: &str = "fanControlStatus";
/// Fan configure command.
pub const COMMAND_FAN_CONTROL_CONFIGURE: &str = "fanControlConfigure";
/// Fan keep-alive command.
pub const COMMAND_FAN_CONTROL_KEEP_ALIVE: &str = "fanControlKeepAlive";
/// Fan restore command.
pub const COMMAND_FAN_CONTROL_RESTORE: &str = "fanControlRestore";
/// Install transaction preparation command.
pub const COMMAND_PREPARE_INSTALL_TRANSACTION: &str = "prepareInstallTransaction";

/// Wire error: unsupported protocol.
pub const ERROR_UNSUPPORTED_PROTOCOL: &str = "Unsupported protocol version";
/// Wire error: external display blocks a closed-lid lease.
pub const ERROR_EXTERNAL_DISPLAY: &str =
    "Closed lid lease is blocked while an external display is connected";
/// Wire error: cannot read external display count.
pub const ERROR_CANNOT_READ_EXTERNAL_DISPLAY: &str = "Cannot read external display count";
/// Wire error: external SleepDisabled owner.
pub const ERROR_EXTERNAL_SLEEP_CONFLICT: &str = "SleepDisabled is owned by an external tool";
/// Wire error: cannot read SleepDisabled.
pub const ERROR_CANNOT_READ_SLEEP_DISABLED: &str = "Cannot read SleepDisabled";
/// Wire error: cannot write SleepDisabled.
pub const ERROR_CANNOT_WRITE_SLEEP_DISABLED: &str = "Cannot write SleepDisabled";
/// Wire error: cannot read ownership.
pub const ERROR_CANNOT_READ_OWNERSHIP: &str = "Cannot read SleepDisabled ownership";
/// Wire error: too many leases.
pub const ERROR_TOO_MANY_LEASES: &str = "Too many active lid leases";

/// Helper command allow list.
pub const ALLOWED_COMMANDS: [&str; 15] = [
    COMMAND_VERSION,
    COMMAND_SET_DISABLE_SLEEP,
    COMMAND_SET_HIBERNATE_MODE,
    COMMAND_CHARGE_LIMIT_STATUS,
    COMMAND_CHARGE_LIMIT_CONFIGURE,
    COMMAND_CHARGE_LIMIT_RESTORE,
    COMMAND_LID_LEASE_ACQUIRE,
    COMMAND_LID_LEASE_RENEW,
    COMMAND_LID_LEASE_RELEASE,
    COMMAND_LID_LEASE_STATUS,
    COMMAND_FAN_CONTROL_STATUS,
    COMMAND_FAN_CONTROL_CONFIGURE,
    COMMAND_FAN_CONTROL_KEEP_ALIVE,
    COMMAND_FAN_CONTROL_RESTORE,
    COMMAND_PREPARE_INSTALL_TRANSACTION,
];

/// Helper request.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HelperRequest {
    /// Protocol version.
    pub version: String,
    /// Request id.
    #[serde(rename = "requestId")]
    pub request_id: String,
    /// Command name.
    pub command: String,
    /// String payload.
    #[serde(
        default,
        deserialize_with = "deserialize_string_map",
        skip_serializing_if = "Map::is_empty"
    )]
    pub payload: Map<String, serde_json::Value>,
}

/// Helper reply.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HelperReply {
    /// Protocol version.
    pub version: String,
    /// Request id.
    #[serde(rename = "requestId")]
    pub request_id: String,
    /// Success flag. The historical decoder accepts `"true"` and `"false"`.
    #[serde(deserialize_with = "deserialize_lenient_bool")]
    pub ok: bool,
    /// Result values.
    #[serde(
        default,
        deserialize_with = "deserialize_optional_string_map",
        skip_serializing_if = "Option::is_none"
    )]
    pub result: Option<Map<String, serde_json::Value>>,
    /// Failure message.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Encodes a helper request.
pub fn encode_request(request: &HelperRequest) -> Result<String, serde_json::Error> {
    serde_json::to_string(request)
}

/// Decodes a helper request. Non-string payload values fail decoding.
#[must_use]
pub fn decode_request(line: &str) -> Option<HelperRequest> {
    serde_json::from_str(line).ok()
}

/// Encodes a helper reply.
pub fn encode_reply(reply: &HelperReply) -> Result<String, serde_json::Error> {
    serde_json::to_string(reply)
}

/// Decodes a helper reply.
#[must_use]
pub fn decode_reply(line: &str) -> Option<HelperReply> {
    serde_json::from_str(line).ok()
}

/// Creates a successful helper reply.
#[must_use]
pub fn success(request_id: &str, result: Option<Map<String, serde_json::Value>>) -> HelperReply {
    HelperReply {
        version: HELPER_PROTOCOL_VERSION.to_owned(),
        request_id: request_id.to_owned(),
        ok: true,
        result: result.filter(|values| !values.is_empty()),
        error: None,
    }
}

/// Creates a failed helper reply.
#[must_use]
pub fn failure(request_id: &str, message: &str) -> HelperReply {
    HelperReply {
        version: HELPER_PROTOCOL_VERSION.to_owned(),
        request_id: request_id.to_owned(),
        ok: false,
        result: None,
        error: Some(message.to_owned()),
    }
}

/// Creates a version reply.
#[must_use]
pub fn version_reply(request_id: &str, app_version: &str) -> HelperReply {
    let mut result = Map::new();
    result.insert(
        "version".to_owned(),
        serde_json::Value::String(app_version.to_owned()),
    );
    result.insert(
        "protocolVersion".to_owned(),
        serde_json::Value::String(HELPER_PROTOCOL_VERSION.to_owned()),
    );
    success(request_id, Some(result))
}

/// Creates a helper lease status reply.
#[must_use]
pub fn lease_status_reply(
    request_id: &str,
    sleep_disabled: Option<bool>,
    covio_owned: Option<bool>,
    active_lease_count: i32,
    expires_at_epoch_seconds: Option<i64>,
) -> HelperReply {
    let mut result = Map::new();
    result.insert(
        "activeLeaseCount".to_owned(),
        serde_json::Value::String(active_lease_count.max(0).to_string()),
    );
    result.insert(
        "sleepDisabled".to_owned(),
        serde_json::Value::String(
            sleep_disabled.map_or_else(|| "unknown".to_owned(), |value| value.to_string()),
        ),
    );
    result.insert(
        "covioOwned".to_owned(),
        serde_json::Value::String(
            covio_owned.map_or_else(|| "unknown".to_owned(), |value| value.to_string()),
        ),
    );
    if let Some(expires_at) = expires_at_epoch_seconds {
        result.insert(
            "expiresAtEpochSeconds".to_owned(),
            serde_json::Value::String(expires_at.to_string()),
        );
    }
    success(request_id, Some(result))
}

/// Validates one helper request. `None` means valid.
#[must_use]
pub fn validate(request: &HelperRequest) -> Option<String> {
    let legacy_version_probe = request.version == "1" && request.command == COMMAND_VERSION;
    if request.version != HELPER_PROTOCOL_VERSION && !legacy_version_probe {
        return Some(ERROR_UNSUPPORTED_PROTOCOL.to_owned());
    }
    if request.request_id.trim().is_empty() {
        return Some("Missing requestId".to_owned());
    }
    if !ALLOWED_COMMANDS.contains(&request.command.as_str()) {
        return Some("Command is not allowed".to_owned());
    }
    match request.command.as_str() {
        COMMAND_SET_DISABLE_SLEEP => {
            let Some(value) = payload_string(&request.payload, "disabled") else {
                return Some("Missing disabled value".to_owned());
            };
            if value != "true" && value != "false" {
                return Some("Invalid disabled value".to_owned());
            }
        }
        COMMAND_SET_HIBERNATE_MODE => {
            let Some(mode) = payload_string(&request.payload, "mode")
                .and_then(|value| value.parse::<i32>().ok())
            else {
                return Some("Missing hibernate mode".to_owned());
            };
            if !SUPPORTED_HIBERNATE_MODES.contains(&mode) {
                return Some("Invalid hibernate mode".to_owned());
            }
        }
        COMMAND_LID_LEASE_ACQUIRE | COMMAND_LID_LEASE_RENEW => {
            let Some(lease_id) = payload_string(&request.payload, "leaseId") else {
                return Some("Missing leaseId".to_owned());
            };
            if lease_id.trim().is_empty() || lease_id.len() > HELPER_LEASE_ID_MAX_LENGTH {
                return Some("Invalid leaseId".to_owned());
            }
            let Some(display_count) = payload_string(&request.payload, "externalDisplayCount")
                .and_then(|value| value.parse::<i32>().ok())
            else {
                return Some("Missing external display count".to_owned());
            };
            if display_count < 0 {
                return Some("Invalid external display count".to_owned());
            }
        }
        COMMAND_LID_LEASE_RELEASE => {
            let Some(lease_id) = payload_string(&request.payload, "leaseId") else {
                return Some("Missing leaseId".to_owned());
            };
            if lease_id.trim().is_empty() || lease_id.len() > HELPER_LEASE_ID_MAX_LENGTH {
                return Some("Invalid leaseId".to_owned());
            }
        }
        _ => {}
    }
    if request.command == COMMAND_CHARGE_LIMIT_CONFIGURE {
        let Some(percent) =
            payload_string(&request.payload, "percent").and_then(|value| value.parse::<i32>().ok())
        else {
            return Some("Missing charge limit".to_owned());
        };
        if !(40..=100).contains(&percent) || percent % 5 != 0 {
            return Some("Invalid charge limit".to_owned());
        }
        if let Some(active_discharge) = payload_string(&request.payload, "activeDischarge")
            && active_discharge != "true"
            && active_discharge != "false"
        {
            return Some("Invalid active discharge value".to_owned());
        }
    }
    if request.command == COMMAND_FAN_CONTROL_CONFIGURE {
        if payload_string(&request.payload, "enabled") != Some("true") {
            return Some("Fan control must be enabled".to_owned());
        }
        let mode = payload_string(&request.payload, "mode").unwrap_or_default();
        if !matches!(mode, "auto" | "curve" | "manual") {
            return Some("Invalid fan control mode".to_owned());
        }
        let start =
            payload_string(&request.payload, "start").and_then(|value| value.parse::<f64>().ok());
        let full =
            payload_string(&request.payload, "full").and_then(|value| value.parse::<f64>().ok());
        let (Some(start), Some(full)) = (start, full) else {
            return Some("Missing fan start temperature".to_owned());
        };
        if !start.is_finite()
            || !full.is_finite()
            || !(35.0..=80.0).contains(&start)
            || !((start + 5.0)..=105.0).contains(&full)
        {
            return Some("Invalid fan curve".to_owned());
        }
        let sensors = payload_string(&request.payload, "sensors").unwrap_or_default();
        if sensors.len() > 512 {
            return Some("Fan sensor list is too long".to_owned());
        }
        let sensor_keys: Vec<_> = sensors
            .split(',')
            .filter(|value| !value.trim().is_empty())
            .collect();
        if sensor_keys.len() > 32 {
            return Some("Too many fan sensors".to_owned());
        }
        if sensor_keys.iter().any(|key| key.len() != 4) {
            return Some("Invalid fan sensor key".to_owned());
        }
        let manual = payload_string(&request.payload, "manualRPM").unwrap_or_default();
        if manual.len() > 1_024 {
            return Some("Fan RPM list is too long".to_owned());
        }
        let manual_modes = payload_string(&request.payload, "manualModes").unwrap_or_default();
        if manual_modes.len() > 1_024 {
            return Some("Fan mode list is too long".to_owned());
        }
        if has_unsafe_control(manual_modes) {
            return Some("Invalid fan mode list".to_owned());
        }
        let curves = payload_string(&request.payload, "curves").unwrap_or_default();
        if curves.len() > 8_192 {
            return Some("Fan curve list is too long".to_owned());
        }
        if has_unsafe_control(curves) {
            return Some("Invalid fan curve list".to_owned());
        }
        let temperature_rules =
            payload_string(&request.payload, "temperatureRules").unwrap_or_default();
        if temperature_rules.len() > 4_096 {
            return Some("Fan temperature rules are too long".to_owned());
        }
        if has_unsafe_control(temperature_rules) {
            return Some("Invalid fan temperature rules".to_owned());
        }
        for pair in manual.split(',').filter(|value| !value.trim().is_empty()) {
            let parts: Vec<_> = pair.splitn(2, ':').collect();
            if parts.len() != 2 {
                return Some("Invalid fan RPM".to_owned());
            }
            let Some(fan) = parts[0].parse::<i32>().ok() else {
                return Some("Invalid fan index".to_owned());
            };
            let Some(rpm) = parts[1].parse::<f64>().ok() else {
                return Some("Invalid fan RPM".to_owned());
            };
            if !(0..=15).contains(&fan) || !rpm.is_finite() || !(0.0..=15_000.0).contains(&rpm) {
                return Some("Invalid fan RPM".to_owned());
            }
        }
    }
    None
}

/// Returns whether this is a charge-limit command.
#[must_use]
pub fn is_charge_limit_command(command: &str) -> bool {
    matches!(
        command,
        COMMAND_CHARGE_LIMIT_STATUS | COMMAND_CHARGE_LIMIT_CONFIGURE | COMMAND_CHARGE_LIMIT_RESTORE
    )
}

/// Returns whether this is a fan command.
#[must_use]
pub fn is_fan_control_command(command: &str) -> bool {
    matches!(
        command,
        COMMAND_FAN_CONTROL_STATUS
            | COMMAND_FAN_CONTROL_CONFIGURE
            | COMMAND_FAN_CONTROL_KEEP_ALIVE
            | COMMAND_FAN_CONTROL_RESTORE
    )
}

/// Returns whether the command requires a signed client.
#[must_use]
pub fn requires_client_signature(command: &str) -> bool {
    is_charge_limit_command(command)
        || is_fan_control_command(command)
        || command == COMMAND_PREPARE_INSTALL_TRANSACTION
}

/// Returns pmset arguments for one request.
#[must_use]
pub fn pmset_arguments(request: &HelperRequest) -> Option<Vec<String>> {
    match request.command.as_str() {
        COMMAND_SET_DISABLE_SLEEP => Some(vec![
            "-a".to_owned(),
            "disablesleep".to_owned(),
            if payload_string(&request.payload, "disabled") == Some("true") {
                "1".to_owned()
            } else {
                "0".to_owned()
            },
        ]),
        COMMAND_SET_HIBERNATE_MODE => payload_string(&request.payload, "mode")
            .and_then(|value| value.parse::<i32>().ok())
            .map(|mode| {
                vec![
                    "-a".to_owned(),
                    "hibernatemode".to_owned(),
                    mode.to_string(),
                ]
            }),
        _ => None,
    }
}

/// Returns direct SleepDisabled pmset arguments.
#[must_use]
pub fn disable_sleep_arguments(disabled: bool) -> Vec<String> {
    vec![
        "-a".to_owned(),
        "disablesleep".to_owned(),
        if disabled { "1" } else { "0" }.to_owned(),
    ]
}

/// Creates a reply from a pmset execution.
#[must_use]
pub fn pmset_reply(request_id: &str, exit_code: i32, output: &str) -> HelperReply {
    if exit_code == 0 {
        return success(request_id, None);
    }
    let text = output.trim();
    if text.is_empty() {
        failure(request_id, &format!("pmset exited with {exit_code}"))
    } else {
        failure(request_id, text)
    }
}

fn payload_string<'a>(payload: &'a Map<String, serde_json::Value>, key: &str) -> Option<&'a str> {
    payload.get(key)?.as_str()
}

fn has_unsafe_control(value: &str) -> bool {
    value
        .chars()
        .any(|character| matches!(character, '\0' | '\n' | '\r'))
}

fn deserialize_string_map<'de, D>(
    deserializer: D,
) -> Result<Map<String, serde_json::Value>, D::Error>
where
    D: Deserializer<'de>,
{
    use serde::de::Error;

    let value = serde_json::Value::deserialize(deserializer)?;
    let values = value
        .as_object()
        .ok_or_else(|| D::Error::custom("payload must be an object"))?;
    if values.values().any(|value| !value.is_string()) {
        return Err(D::Error::custom("payload values must be strings"));
    }
    Ok(values.clone())
}

fn deserialize_optional_string_map<'de, D>(
    deserializer: D,
) -> Result<Option<Map<String, serde_json::Value>>, D::Error>
where
    D: Deserializer<'de>,
{
    use serde::de::Error;

    let value = Option::<serde_json::Value>::deserialize(deserializer)?;
    let Some(value) = value else {
        return Ok(None);
    };
    let values = value
        .as_object()
        .ok_or_else(|| D::Error::custom("result must be an object"))?;
    if values.values().any(|value| !value.is_string()) {
        return Err(D::Error::custom("result values must be strings"));
    }
    Ok(Some(values.clone()))
}

fn deserialize_lenient_bool<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    struct LenientBool;
    impl<'de> serde::de::Visitor<'de> for LenientBool {
        type Value = bool;

        fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
            formatter.write_str("a boolean or the string true/false")
        }

        fn visit_bool<E>(self, value: bool) -> Result<Self::Value, E> {
            Ok(value)
        }

        fn visit_str<E>(self, value: &str) -> Result<Self::Value, E>
        where
            E: serde::de::Error,
        {
            match value {
                "true" => Ok(true),
                "false" => Ok(false),
                _ => Err(E::custom("invalid boolean string")),
            }
        }
    }
    deserializer.deserialize_any(LenientBool)
}

const SUPPORTED_HIBERNATE_MODES: [i32; 3] = [0, 3, 25];

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Value, json};

    fn string_map(entries: &[(&str, &str)]) -> Map<String, Value> {
        entries
            .iter()
            .map(|(key, value)| ((*key).to_owned(), Value::String((*value).to_owned())))
            .collect()
    }

    fn request(command: &str, payload: Map<String, Value>) -> HelperRequest {
        HelperRequest {
            version: HELPER_PROTOCOL_VERSION.to_owned(),
            request_id: "r1".to_owned(),
            command: command.to_owned(),
            payload,
        }
    }

    fn lease_payload() -> Map<String, Value> {
        string_map(&[("leaseId", "lease"), ("externalDisplayCount", "0")])
    }

    fn fan_payload() -> Map<String, Value> {
        string_map(&[
            ("enabled", "true"),
            ("mode", "auto"),
            ("start", "58"),
            ("full", "86"),
            ("sensors", "TCMz,TG0D"),
            ("manualRPM", "0:2200,1:2400"),
        ])
    }

    fn fixture() -> Value {
        serde_json::from_str(include_str!(
            "../../../../../kmpDomain/test/fixtures/helper-wire-vectors.json"
        ))
        .expect("helper wire fixture")
    }

    fn fixture_map(vector: &Value, key: &str) -> Map<String, Value> {
        vector
            .get(key)
            .and_then(Value::as_object)
            .map(|values| {
                values
                    .iter()
                    .map(|(key, value)| {
                        assert!(
                            value.is_string(),
                            "fixture field {key} must be a string, got {value}"
                        );
                        (key.clone(), value.clone())
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    fn fixture_string_array(value: Option<&Value>) -> Option<Vec<String>> {
        value.and_then(Value::as_array).map(|values| {
            values
                .iter()
                .map(|value| value.as_str().expect("string argument").to_owned())
                .collect()
        })
    }

    #[test]
    fn protocol_versions_and_request_ids_are_bounded() {
        let mut value = request(COMMAND_VERSION, Map::new());
        value.version = "3".to_owned();
        assert_eq!(
            validate(&value).as_deref(),
            Some(ERROR_UNSUPPORTED_PROTOCOL)
        );

        value.version = "1".to_owned();
        assert_eq!(validate(&value), None);
        value.command = COMMAND_LID_LEASE_ACQUIRE.to_owned();
        value.payload = lease_payload();
        assert_eq!(
            validate(&value).as_deref(),
            Some(ERROR_UNSUPPORTED_PROTOCOL)
        );

        let value = request(COMMAND_VERSION, Map::new());
        let mut blank = value.clone();
        blank.request_id = "".to_owned();
        assert_eq!(validate(&blank).as_deref(), Some("Missing requestId"));
        blank.request_id = " \n ".to_owned();
        assert_eq!(validate(&blank).as_deref(), Some("Missing requestId"));
        assert_eq!(
            validate(&request("runShell", Map::new())).as_deref(),
            Some("Command is not allowed")
        );
    }

    #[test]
    fn lease_commands_validate_the_id_and_display_count() {
        for command in [COMMAND_LID_LEASE_ACQUIRE, COMMAND_LID_LEASE_RENEW] {
            assert_eq!(
                validate(&request(command, Map::new())).as_deref(),
                Some("Missing leaseId")
            );
            assert_eq!(
                validate(&request(command, string_map(&[("leaseId", " ")]))).as_deref(),
                Some("Invalid leaseId")
            );
            assert_eq!(
                validate(&request(command, string_map(&[("leaseId", "lease")]))).as_deref(),
                Some("Missing external display count")
            );
            assert_eq!(
                validate(&request(
                    command,
                    string_map(&[("leaseId", "lease"), ("externalDisplayCount", "-1")])
                ))
                .as_deref(),
                Some("Invalid external display count")
            );
            assert_eq!(validate(&request(command, lease_payload())), None);
        }
    }

    #[test]
    fn hibernate_and_charge_limits_use_the_reviewed_values() {
        for mode in ["0", "3", "25"] {
            assert_eq!(
                validate(&request(
                    COMMAND_SET_HIBERNATE_MODE,
                    string_map(&[("mode", mode)])
                )),
                None
            );
        }
        for mode in ["1", "2", "4", "57"] {
            assert_eq!(
                validate(&request(
                    COMMAND_SET_HIBERNATE_MODE,
                    string_map(&[("mode", mode)])
                ))
                .as_deref(),
                Some("Invalid hibernate mode")
            );
        }
        assert_eq!(
            validate(&request(
                COMMAND_SET_HIBERNATE_MODE,
                string_map(&[("mode", "abc")])
            ))
            .as_deref(),
            Some("Missing hibernate mode")
        );
        assert_eq!(
            validate(&request(COMMAND_SET_HIBERNATE_MODE, Map::new())).as_deref(),
            Some("Missing hibernate mode")
        );

        for percent in ["40", "70", "100"] {
            assert_eq!(
                validate(&request(
                    COMMAND_CHARGE_LIMIT_CONFIGURE,
                    string_map(&[("percent", percent), ("activeDischarge", "true")])
                )),
                None
            );
        }
        for percent in ["39", "41", "79", "101"] {
            assert_eq!(
                validate(&request(
                    COMMAND_CHARGE_LIMIT_CONFIGURE,
                    string_map(&[("percent", percent)])
                ))
                .as_deref(),
                Some("Invalid charge limit")
            );
        }
        assert_eq!(
            validate(&request(
                COMMAND_CHARGE_LIMIT_CONFIGURE,
                string_map(&[("percent", "abc")])
            ))
            .as_deref(),
            Some("Missing charge limit")
        );
        assert_eq!(
            validate(&request(
                COMMAND_CHARGE_LIMIT_CONFIGURE,
                string_map(&[("percent", "70"), ("activeDischarge", "yes")])
            ))
            .as_deref(),
            Some("Invalid active discharge value")
        );
    }

    #[test]
    fn fan_configuration_rejects_unsafe_or_out_of_range_values() {
        assert_eq!(
            validate(&request(COMMAND_FAN_CONTROL_CONFIGURE, fan_payload())),
            None
        );

        let mut payload = fan_payload();
        payload.insert("enabled".to_owned(), Value::String("false".to_owned()));
        assert_eq!(
            validate(&request(COMMAND_FAN_CONTROL_CONFIGURE, payload)).as_deref(),
            Some("Fan control must be enabled")
        );

        let mut payload = fan_payload();
        payload.insert("start".to_owned(), Value::String("81".to_owned()));
        assert_eq!(
            validate(&request(COMMAND_FAN_CONTROL_CONFIGURE, payload)).as_deref(),
            Some("Invalid fan curve")
        );

        let mut payload = fan_payload();
        payload.insert("manualRPM".to_owned(), Value::String("16:2200".to_owned()));
        assert_eq!(
            validate(&request(COMMAND_FAN_CONTROL_CONFIGURE, payload)).as_deref(),
            Some("Invalid fan RPM")
        );

        for key in ["manualModes", "curves", "temperatureRules"] {
            let mut payload = fan_payload();
            payload.insert(key.to_owned(), Value::String("bad\nvalue".to_owned()));
            assert!(validate(&request(COMMAND_FAN_CONTROL_CONFIGURE, payload)).is_some());
        }
    }

    #[test]
    fn command_classes_keep_the_signature_boundary() {
        assert!(is_charge_limit_command(COMMAND_CHARGE_LIMIT_STATUS));
        assert!(is_fan_control_command(COMMAND_FAN_CONTROL_KEEP_ALIVE));
        assert!(requires_client_signature(
            COMMAND_PREPARE_INSTALL_TRANSACTION
        ));
        assert!(!requires_client_signature(COMMAND_VERSION));
        assert!(!requires_client_signature(COMMAND_SET_DISABLE_SLEEP));
    }

    #[test]
    fn non_string_payload_and_result_values_fail_decode() {
        assert!(
            decode_request(
                r#"{"version":"10","requestId":"r","command":"version","payload":{"anything":1}}"#
            )
            .is_none()
        );
        assert!(
            decode_request(r#"{"version":"10","requestId":"r","command":"version","payload":[]}"#)
                .is_none()
        );
        assert!(
            decode_reply(r#"{"version":"3","requestId":"r","ok":true,"result":{"version":3}}"#)
                .is_none()
        );
    }

    #[test]
    fn unknown_keys_are_ignored_and_empty_defaults_are_omitted() {
        let request =
            decode_request(r#"{"version":"10","requestId":"r","command":"version","future":1}"#)
                .expect("request");
        assert!(request.payload.is_empty());
        assert_eq!(
            encode_request(&request).expect("encode"),
            r#"{"version":"10","requestId":"r","command":"version"}"#
        );

        let reply =
            decode_reply(r#"{"version":"3","requestId":"r","ok":true,"future":1}"#).expect("reply");
        assert_eq!(
            encode_reply(&reply).expect("encode"),
            r#"{"version":"3","requestId":"r","ok":true}"#
        );
    }

    #[test]
    fn replies_and_pmset_results_keep_the_wire_shape() {
        let successful = success("r", Some(string_map(&[("a", "b")])));
        assert_eq!(
            encode_reply(&successful).expect("encode"),
            r#"{"version":"10","requestId":"r","ok":true,"result":{"a":"b"}}"#
        );
        assert_eq!(
            encode_reply(&success("r", Some(Map::new()))).expect("encode"),
            r#"{"version":"10","requestId":"r","ok":true}"#
        );
        let failed = pmset_reply("r", 1, "pmset: bad\n");
        assert_eq!(failed.error.as_deref(), Some("pmset: bad"));
        assert_eq!(
            pmset_reply("r", 3, "  \n").error.as_deref(),
            Some("pmset exited with 3")
        );
        assert!(pmset_reply("r", 0, "ignored").ok);
    }

    #[test]
    fn version_reply_carries_both_protocol_versions() {
        let reply = version_reply("r", "1.2.3");
        assert!(reply.ok);
        let result = reply.result.expect("result");
        assert_eq!(result.get("version").and_then(Value::as_str), Some("1.2.3"));
        assert_eq!(
            result.get("protocolVersion").and_then(Value::as_str),
            Some(HELPER_PROTOCOL_VERSION)
        );
    }

    #[test]
    fn every_request_vector_matches_the_shared_fixture() {
        let fixture = fixture();
        for vector in fixture["requests"].as_array().expect("requests") {
            let name = vector["name"].as_str().unwrap_or("request");
            let line = vector["line"].as_str().expect("line");
            let decoded = decode_request(line);
            if vector["decode"] != "ok" {
                assert!(decoded.is_none(), "{name}");
                continue;
            }
            let request = decoded.unwrap_or_else(|| panic!("{name}: decode failed"));
            assert_eq!(
                validate(&request).as_deref(),
                vector["validate"].as_str(),
                "{name}: validate"
            );
            assert_eq!(
                pmset_arguments(&request),
                fixture_string_array(vector.get("pmsetArguments")),
                "{name}: pmset"
            );
            assert_eq!(
                encode_request(&request).expect("encode"),
                vector["reencoded"].as_str().expect("reencoded"),
                "{name}: reencoded"
            );
        }
    }

    #[test]
    fn every_reply_vector_matches_the_shared_fixture() {
        let fixture = fixture();
        for vector in fixture["replies"].as_array().expect("replies") {
            let name = vector["name"].as_str().unwrap_or("reply");
            let line = vector["line"].as_str().expect("line");
            let decoded = decode_reply(line);
            if vector["decode"] != "ok" {
                assert!(decoded.is_none(), "{name}");
                continue;
            }
            let reply = decoded.unwrap_or_else(|| panic!("{name}: decode failed"));
            assert_eq!(Some(reply.ok), vector["ok"].as_bool(), "{name}: ok");
            assert_eq!(
                reply
                    .result
                    .as_ref()
                    .and_then(|result| result.get("version"))
                    .and_then(Value::as_str),
                vector["resultVersion"].as_str(),
                "{name}: result"
            );
            assert_eq!(
                reply.error.as_deref(),
                vector["error"].as_str(),
                "{name}: error"
            );
            assert_eq!(
                encode_reply(&reply).expect("encode"),
                vector["reencoded"].as_str().expect("reencoded"),
                "{name}: reencoded"
            );
        }
    }

    #[test]
    fn every_constructed_reply_matches_the_shared_fixture() {
        let fixture = fixture();
        for vector in fixture["constructed"].as_array().expect("constructed") {
            let name = vector["name"].as_str().unwrap_or("constructed");
            let request_id = vector["requestId"].as_str().expect("requestId");
            let reply = match vector["call"].as_str() {
                Some("success") => success(
                    request_id,
                    vector
                        .get("result")
                        .filter(|value| !value.is_null())
                        .map(|_| fixture_map(vector, "result")),
                ),
                Some("failure") => {
                    failure(request_id, vector["message"].as_str().expect("message"))
                }
                Some("pmsetReply") => pmset_reply(
                    request_id,
                    vector["exitCode"].as_i64().expect("exitCode") as i32,
                    vector["output"].as_str().expect("output"),
                ),
                call => panic!("{name}: unknown call {call:?}"),
            };
            assert_eq!(
                encode_reply(&reply).expect("encode"),
                vector["expected"].as_str().expect("expected"),
                "{name}"
            );
        }
    }

    #[test]
    fn constants_and_empty_defaults_keep_shipped_values() {
        assert_eq!(MAX_REQUEST_BYTES, 64 * 1024);
        assert_eq!(MAX_REPLY_BYTES, 64 * 1024);
        assert_eq!(SOCKET_PERMISSIONS, 0x1b6);
        assert_eq!(HELPER_LEASE_DURATION_SECONDS, 60);
        assert_eq!(HELPER_LEASE_RENEW_SECONDS, 15);
        assert_eq!(ALLOWED_COMMANDS.len(), 15);
        let encoded = encode_request(&request(COMMAND_VERSION, Map::new())).expect("encode");
        assert_eq!(
            encoded,
            r#"{"version":"10","requestId":"r1","command":"version"}"#
        );
        assert_eq!(
            decode_request(r#"{"version":"10","requestId":"r1","command":"version","payload":{}}"#),
            Some(request(COMMAND_VERSION, Map::new()))
        );
        let _ = json!({});
    }
}

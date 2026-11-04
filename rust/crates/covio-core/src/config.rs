//! Configuration model and compatibility codec.
//!
//! The codec reads each field independently. One invalid field does not reject
//! the whole configuration. Saves merge current fields into the existing JSON
//! object, including the nested `power`, `display`, and `fileNaming` objects.

use crate::{CoreError, CoreErrorCode};
use covio_platform::{FileStore, temporary_path};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::path::{Path, PathBuf};

/// Current configuration schema version.
pub const CONFIG_SCHEMA_VERSION: i32 = 3;

/// Supported hibernate mode values.
pub const SUPPORTED_HIBERNATE_MODES: [i32; 3] = [0, 3, 25];

/// Default paste-stack shortcut.
pub const DEFAULT_PASTE_STACK_HOT_KEY: &str = "shift+cmd+V";

/// Default selected-text capture shortcut.
pub const DEFAULT_CAPTURE_HOT_KEY: &str = "shift+cmd+C";

/// Default charge limit.
pub const DEFAULT_CHARGE_LIMIT_PERCENT: i32 = 70;

/// File-naming schema version.
pub const FILE_NAMING_SCHEMA_VERSION: i32 = 1;

/// Default file-naming template.
pub const DEFAULT_FILE_NAMING_TEMPLATE: &str = "{title}";

/// Default file-naming maximum UTF-8 size.
pub const DEFAULT_FILE_NAMING_MAX_UTF8_BYTES: i32 = 240;

/// Default file-naming confidence threshold.
pub const DEFAULT_FILE_NAMING_MIN_CONFIDENCE: f64 = 0.65;

/// Power-management preferences.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PowerConfig {
    /// Whether power rules are enabled.
    pub enabled: bool,
    /// Whether Covio keeps the Mac awake on adapter power.
    pub keep_awake_on_adapter: bool,
    /// Whether Covio keeps the Mac awake on battery power.
    pub keep_awake_on_battery: bool,
    /// Whether closed-lid keep-awake is allowed.
    pub allow_closed_lid: bool,
    /// Whether closed-lid keep-awake pauses with an external display.
    pub pause_closed_lid_with_external_display: bool,
    /// Battery floor percentage.
    pub battery_floor_percent: i32,
    /// Battery recovery percentage.
    pub battery_floor_recovery_percent: i32,
    /// Whether Low Power Mode suspends Covio rules.
    pub yield_on_low_power_mode: bool,
    /// Whether heat protection is enabled.
    pub heat_guard_enabled: bool,
    /// Maximum closed-lid session duration.
    pub closed_lid_time_cap_minutes: i32,
    /// Whether the black-screen pipeline is enabled.
    pub closed_lid_zero_brightness: bool,
}

impl Default for PowerConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            keep_awake_on_adapter: true,
            keep_awake_on_battery: false,
            allow_closed_lid: true,
            pause_closed_lid_with_external_display: true,
            battery_floor_percent: 15,
            battery_floor_recovery_percent: 20,
            yield_on_low_power_mode: true,
            heat_guard_enabled: true,
            closed_lid_time_cap_minutes: 240,
            closed_lid_zero_brightness: true,
        }
    }
}

impl PowerConfig {
    /// Returns a normalized copy.
    #[must_use]
    pub fn normalized(&self) -> Self {
        let mut value = self.clone();
        value.battery_floor_percent = value.battery_floor_percent.clamp(0, 99);
        value.battery_floor_recovery_percent = value
            .battery_floor_recovery_percent
            .clamp(value.battery_floor_percent + 1, 100);
        value.closed_lid_time_cap_minutes = value.closed_lid_time_cap_minutes.clamp(1, 1_440);
        value
    }
}

/// Power condition used for closed-lid keep-awake.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ClosedLidPowerPolicy {
    /// Sleep when the lid closes.
    Sleep,
    /// Keep awake on adapter power.
    #[default]
    Adapter,
    /// Keep awake on battery power.
    Battery,
    /// Keep awake on any power source.
    Any,
}

impl ClosedLidPowerPolicy {
    /// Returns whether this policy keeps the system awake.
    #[must_use]
    pub const fn keeps_awake(self) -> bool {
        !matches!(self, Self::Sleep)
    }

    /// Returns whether this policy keeps the system awake on adapter power.
    #[must_use]
    pub const fn keeps_awake_on_adapter(self) -> bool {
        matches!(self, Self::Adapter | Self::Any)
    }

    /// Returns whether this policy keeps the system awake on battery power.
    #[must_use]
    pub const fn keeps_awake_on_battery(self) -> bool {
        matches!(self, Self::Battery | Self::Any)
    }

    fn resolve(keep_awake: bool, on_adapter: bool, on_battery: bool) -> Self {
        if !keep_awake {
            Self::Sleep
        } else if on_adapter && on_battery {
            Self::Any
        } else if on_battery {
            Self::Battery
        } else {
            Self::Adapter
        }
    }

    fn from_wire(value: Option<&Value>) -> Option<Self> {
        match value?.as_str()? {
            "sleep" => Some(Self::Sleep),
            "adapter" => Some(Self::Adapter),
            "battery" => Some(Self::Battery),
            "any" => Some(Self::Any),
            _ => None,
        }
    }
}

/// Display behavior during a closed-lid session.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ClosedLidDisplayMode {
    /// Use the system default.
    System,
    /// Turn the display off.
    DisplayOff,
    /// Keep the panel online with the black-screen pipeline.
    #[default]
    BlackScreenPipeline,
}

impl ClosedLidDisplayMode {
    fn from_wire(value: Option<&Value>) -> Option<Self> {
        match value?.as_str()? {
            "system" => Some(Self::System),
            "displayOff" => Some(Self::DisplayOff),
            "blackScreenPipeline" => Some(Self::BlackScreenPipeline),
            _ => None,
        }
    }
}

/// Display preferences persisted in `config.json`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct DisplayConfig {
    /// Display schema version.
    pub schema_version: i32,
    /// Compatibility mirror for the selected power policy.
    pub keep_awake_when_lid_closed: bool,
    /// Closed-lid power condition.
    pub closed_lid_power_policy: ClosedLidPowerPolicy,
    /// Closed-lid display behavior.
    pub closed_lid_display_mode: ClosedLidDisplayMode,
    /// Whether the session pauses with an external display.
    pub pause_when_external_display_connected: bool,
}

impl Default for DisplayConfig {
    fn default() -> Self {
        Self::from_legacy(&PowerConfig::default(), false, false)
    }
}

impl DisplayConfig {
    /// Returns a normalized copy.
    #[must_use]
    pub fn normalized(&self) -> Self {
        Self {
            schema_version: 2,
            keep_awake_when_lid_closed: self.closed_lid_power_policy.keeps_awake(),
            ..self.clone()
        }
    }

    fn from_legacy(
        power: &PowerConfig,
        keeps_awake_on_adapter: bool,
        keeps_awake_on_battery: bool,
    ) -> Self {
        let policy = ClosedLidPowerPolicy::resolve(
            power.allow_closed_lid,
            keeps_awake_on_adapter,
            keeps_awake_on_battery,
        );
        Self {
            schema_version: 2,
            keep_awake_when_lid_closed: policy.keeps_awake(),
            closed_lid_power_policy: policy,
            closed_lid_display_mode: if power.closed_lid_zero_brightness {
                ClosedLidDisplayMode::BlackScreenPipeline
            } else {
                ClosedLidDisplayMode::DisplayOff
            },
            pause_when_external_display_connected: power.pause_closed_lid_with_external_display,
        }
    }
}

/// Source used for a file-name date value.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FileNamingDateSource {
    /// Do not use a date.
    #[default]
    None,
    /// Use a date from the content.
    Content,
    /// Use the file creation date.
    FileCreated,
}

impl FileNamingDateSource {
    fn from_wire(value: Option<&Value>) -> Option<Self> {
        match value?.as_str()? {
            "none" => Some(Self::None),
            "content" => Some(Self::Content),
            "fileCreated" => Some(Self::FileCreated),
            _ => None,
        }
    }
}

/// Policy used when a prospective file name conflicts.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FileNamingConflictPolicy {
    /// Append a bounded number.
    #[default]
    AppendNumber,
    /// Block the rename.
    Block,
}

impl FileNamingConflictPolicy {
    fn from_wire(value: Option<&Value>) -> Option<Self> {
        match value?.as_str()? {
            "appendNumber" => Some(Self::AppendNumber),
            "block" => Some(Self::Block),
            _ => None,
        }
    }
}

/// File auto-naming policy.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct FileNamingPolicy {
    /// Policy schema version.
    pub schema_version: i32,
    /// Name template.
    pub template: String,
    /// Maximum UTF-8 bytes.
    #[serde(rename = "maxUTF8Bytes")]
    pub max_utf8_bytes: i32,
    /// Name part separator.
    pub separator: String,
    /// Whether leading Latin letters become lowercase.
    pub lowercase_latin: bool,
    /// Whether the file extension is preserved.
    pub preserve_extension: bool,
    /// Date-value source.
    pub date_source: FileNamingDateSource,
    /// Conflict policy.
    pub conflict_policy: FileNamingConflictPolicy,
    /// Conflict suffix template.
    pub conflict_suffix: String,
    /// Minimum model confidence.
    pub min_confidence: f64,
    /// Whether preview is required.
    pub require_preview: bool,
    /// Whether vision input is allowed.
    pub allow_vision: bool,
}

impl Default for FileNamingPolicy {
    fn default() -> Self {
        Self {
            schema_version: FILE_NAMING_SCHEMA_VERSION,
            template: DEFAULT_FILE_NAMING_TEMPLATE.to_owned(),
            max_utf8_bytes: DEFAULT_FILE_NAMING_MAX_UTF8_BYTES,
            separator: "-".to_owned(),
            lowercase_latin: false,
            preserve_extension: true,
            date_source: FileNamingDateSource::None,
            conflict_policy: FileNamingConflictPolicy::AppendNumber,
            conflict_suffix: " ({n})".to_owned(),
            min_confidence: DEFAULT_FILE_NAMING_MIN_CONFIDENCE,
            require_preview: true,
            allow_vision: true,
        }
    }
}

impl FileNamingPolicy {
    /// Returns a normalized copy.
    #[must_use]
    pub fn normalized(&self) -> Self {
        let mut value = self.clone();
        value.schema_version = FILE_NAMING_SCHEMA_VERSION;
        value.template = value.template.trim().to_owned();
        value.max_utf8_bytes = value.max_utf8_bytes.clamp(1, 255);
        value.separator = value.separator.trim().to_owned();
        value.preserve_extension = true;
        value.conflict_suffix = value.conflict_suffix.trim_end().to_owned();
        value.min_confidence = if value.min_confidence.is_finite() {
            value.min_confidence.clamp(0.0, 1.0)
        } else {
            DEFAULT_FILE_NAMING_MIN_CONFIDENCE
        };
        value.require_preview = true;
        value
    }
}

/// Covio configuration persisted in `config.json`.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppConfig {
    /// Configuration schema version.
    pub schema_version: i32,
    /// Preferred language code.
    pub language: String,
    /// Whether core features are enabled.
    pub enabled: bool,
    /// Whether Covio starts at login.
    pub launch_at_login: bool,
    /// Whether low battery capacity triggers sleep.
    pub low_battery_capacity_sleep: bool,
    /// Low battery capacity threshold.
    pub low_battery_capacity: i32,
    /// Low battery time threshold.
    #[serde(rename = "lowTimeRemaining")]
    pub low_time_remaining_minutes: i32,
    /// Whether idle sleep prevention applies while charging.
    pub disable_idle_sleep_in_charging: bool,
    /// Legacy adapter-power mirror.
    pub disable_lid_sleep_in_charging: bool,
    /// Legacy battery-power mirror.
    pub disable_lid_sleep_on_battery: bool,
    /// Whether DarkWake events are tracked.
    pub dark_wake_awareness_enabled: bool,
    /// Whether closing the lid sleeps immediately.
    pub lid_sleep_immediate_on_close: bool,
    /// Whether notifications are enabled.
    pub notifications_enabled: bool,
    /// Whether update checks are enabled.
    pub update_check_enabled: bool,
    /// Update-check interval in hours.
    pub update_check_interval_hours: i32,
    /// Unix timestamp of the last update check.
    pub last_update_check_epoch_seconds: i64,
    /// Selected hibernate mode.
    pub hibernate_mode: Option<i32>,
    /// Whether this is the first run.
    pub first_run: bool,
    /// Deprecated screenshot takeover switch.
    pub shelf_enabled: bool,
    /// Deprecated screenshot inbox switch.
    pub screenshot_inbox_enabled: bool,
    /// Deprecated shelf sound switch.
    pub shelf_sounds_enabled: bool,
    /// Whether clipboard history is enabled.
    pub clipboard_enabled: bool,
    /// Paste-stack shortcut.
    pub clipboard_paste_stack_hot_key: String,
    /// Selected-text capture shortcut.
    pub clipboard_capture_hot_key: String,
    /// Power-management preferences.
    pub power: PowerConfig,
    /// Display preferences.
    pub display: Option<DisplayConfig>,
    /// Whether the charge limit is enabled.
    pub charge_limit_enabled: bool,
    /// Charge limit percentage.
    pub charge_limit_percent: i32,
    /// Whether active discharge is enabled.
    pub charge_limit_active_discharge: bool,
    /// File auto-naming policy.
    pub file_naming: FileNamingPolicy,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            schema_version: CONFIG_SCHEMA_VERSION,
            language: String::new(),
            enabled: true,
            launch_at_login: false,
            low_battery_capacity_sleep: true,
            low_battery_capacity: 6,
            low_time_remaining_minutes: 10,
            disable_idle_sleep_in_charging: false,
            disable_lid_sleep_in_charging: false,
            disable_lid_sleep_on_battery: false,
            dark_wake_awareness_enabled: true,
            lid_sleep_immediate_on_close: true,
            notifications_enabled: true,
            update_check_enabled: true,
            update_check_interval_hours: 24,
            last_update_check_epoch_seconds: 0,
            hibernate_mode: None,
            first_run: true,
            shelf_enabled: false,
            screenshot_inbox_enabled: false,
            shelf_sounds_enabled: false,
            clipboard_enabled: true,
            clipboard_paste_stack_hot_key: DEFAULT_PASTE_STACK_HOT_KEY.to_owned(),
            clipboard_capture_hot_key: DEFAULT_CAPTURE_HOT_KEY.to_owned(),
            power: PowerConfig::default(),
            display: None,
            charge_limit_enabled: true,
            charge_limit_percent: DEFAULT_CHARGE_LIMIT_PERCENT,
            charge_limit_active_discharge: false,
            file_naming: FileNamingPolicy::default(),
        }
    }
}

impl AppConfig {
    /// Returns a normalized copy with the current schema and bounded values.
    #[must_use]
    pub fn normalized(&self) -> Self {
        let normalized_power = self.power.normalized();
        let normalized_display = self
            .display
            .clone()
            .unwrap_or_else(|| {
                DisplayConfig::from_legacy(
                    &normalized_power,
                    self.disable_lid_sleep_in_charging,
                    self.disable_lid_sleep_on_battery,
                )
            })
            .normalized();
        let policy = normalized_display.closed_lid_power_policy;
        let mut value = self.clone();
        value.schema_version = CONFIG_SCHEMA_VERSION;
        value.low_battery_capacity = value.low_battery_capacity.clamp(0, 100);
        value.low_time_remaining_minutes = value.low_time_remaining_minutes.max(0);
        value.update_check_interval_hours = value.update_check_interval_hours.clamp(1, 168);
        value.last_update_check_epoch_seconds = value.last_update_check_epoch_seconds.max(0);
        value.hibernate_mode = value
            .hibernate_mode
            .filter(|mode| SUPPORTED_HIBERNATE_MODES.contains(mode));
        value.clipboard_paste_stack_hot_key = normalize_hot_key(
            &value.clipboard_paste_stack_hot_key,
            DEFAULT_PASTE_STACK_HOT_KEY,
        );
        value.clipboard_capture_hot_key =
            normalize_hot_key(&value.clipboard_capture_hot_key, DEFAULT_CAPTURE_HOT_KEY);
        value.shelf_enabled = false;
        value.screenshot_inbox_enabled = false;
        value.shelf_sounds_enabled = false;
        value.disable_lid_sleep_in_charging = policy.keeps_awake_on_adapter();
        value.disable_lid_sleep_on_battery = policy.keeps_awake_on_battery();
        value.lid_sleep_immediate_on_close = true;
        value.power = PowerConfig {
            allow_closed_lid: normalized_display.keep_awake_when_lid_closed,
            pause_closed_lid_with_external_display: normalized_display
                .pause_when_external_display_connected,
            closed_lid_zero_brightness: normalized_display.closed_lid_display_mode
                == ClosedLidDisplayMode::BlackScreenPipeline,
            ..normalized_power
        };
        value.display = Some(normalized_display);
        value.charge_limit_percent = normalize_charge_limit(value.charge_limit_percent);
        value.file_naming = value.file_naming.normalized();
        value
    }

    /// Decodes a JSON value with the same per-field fallback as the file codec.
    #[must_use]
    pub fn from_json_value(value: &Value) -> Self {
        let Value::Object(root) = value else {
            return Self::default().normalized();
        };
        decode_config(root).normalized()
    }
}

/// Where a loaded configuration came from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfigLoadSource {
    /// The existing file decoded successfully.
    Loaded,
    /// The file did not exist, so defaults were written.
    DefaultsCreated,
    /// The file could not be used, so defaults were returned.
    DefaultsRecovered,
}

/// A non-fatal warning from configuration loading.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfigLoadWarning {
    /// Reading the file failed.
    ReadFailed,
    /// The file was not valid UTF-8.
    InvalidUtf8,
    /// The file was not valid JSON.
    InvalidJson,
    /// The JSON root was not an object.
    NonObjectRoot,
    /// Writing the missing default file failed.
    DefaultWriteFailed,
}

/// Result of loading configuration.
#[derive(Debug, Clone, PartialEq)]
pub struct ConfigLoadResult {
    /// Normalized configuration.
    pub config: AppConfig,
    /// Source of the returned configuration.
    pub source: ConfigLoadSource,
    /// Optional compatibility warning.
    pub warning: Option<ConfigLoadWarning>,
}

/// Configuration repository backed by a filesystem capability.
#[derive(Debug, Clone)]
pub struct ConfigStore<F> {
    path: PathBuf,
    files: F,
}

impl<F: FileStore> ConfigStore<F> {
    /// Creates a configuration store for one path.
    #[must_use]
    pub fn new(path: impl Into<PathBuf>, files: F) -> Self {
        Self {
            path: path.into(),
            files,
        }
    }

    /// Returns the configuration path.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Loads configuration without failing the product path.
    ///
    /// A missing file creates normalized defaults. Invalid or unreadable input
    /// falls back to normalized defaults and records a typed warning.
    #[must_use]
    pub fn load(&self) -> ConfigLoadResult {
        let bytes = match self.files.read(&self.path) {
            Ok(Some(bytes)) => bytes,
            Ok(None) => {
                let config = AppConfig::default().normalized();
                let warning = self
                    .save(&config)
                    .err()
                    .map(|_| ConfigLoadWarning::DefaultWriteFailed);
                return ConfigLoadResult {
                    config,
                    source: ConfigLoadSource::DefaultsCreated,
                    warning,
                };
            }
            Err(_) => {
                return recovered(ConfigLoadWarning::ReadFailed);
            }
        };

        let text = match String::from_utf8(bytes) {
            Ok(text) => text,
            Err(_) => return recovered(ConfigLoadWarning::InvalidUtf8),
        };
        let value = match serde_json::from_str::<Value>(&text) {
            Ok(value) => value,
            Err(_) => return recovered(ConfigLoadWarning::InvalidJson),
        };
        let Value::Object(root) = value else {
            return recovered(ConfigLoadWarning::NonObjectRoot);
        };
        ConfigLoadResult {
            config: decode_config(&root),
            source: ConfigLoadSource::Loaded,
            warning: None,
        }
    }

    /// Saves normalized configuration and preserves unknown root and nested keys.
    pub fn save(&self, config: &AppConfig) -> Result<AppConfig, CoreError> {
        let normalized = config.normalized();
        if let Some(parent) = self.path.parent() {
            self.files.create_dir_all(parent).map_err(CoreError::from)?;
        }

        let mut root = self.existing_object();
        let previous_power = root.get("power").and_then(Value::as_object).cloned();
        let previous_display = root.get("display").and_then(Value::as_object).cloned();
        let previous_file_naming = root.get("fileNaming").and_then(Value::as_object).cloned();
        let Value::Object(current) = serde_json::to_value(&normalized)
            .map_err(|_| CoreError::new(CoreErrorCode::Internal, "config serialization failed"))?
        else {
            return Err(CoreError::new(
                CoreErrorCode::Internal,
                "config serialization returned a non-object",
            ));
        };
        root.extend(
            current
                .iter()
                .map(|(key, value)| (key.clone(), value.clone())),
        );
        merge_nested(&mut root, &current, "power", previous_power);
        merge_nested(&mut root, &current, "display", previous_display);
        merge_nested(&mut root, &current, "fileNaming", previous_file_naming);
        let bytes = serde_json::to_vec_pretty(&Value::Object(root))
            .map_err(|_| CoreError::new(CoreErrorCode::Internal, "config encoding failed"))?;
        self.files
            .write_atomic(&self.path, &bytes)
            .map_err(CoreError::from)?;
        Ok(normalized)
    }

    /// Removes the configuration file and its compatibility temporary file.
    pub fn clear(&self) -> Result<bool, CoreError> {
        let target = self.files.remove_file(&self.path);
        let temporary = self.files.remove_file(&temporary_path(&self.path));
        match (target, temporary) {
            (Ok(target), Ok(temporary)) => Ok(target || temporary),
            (Err(error), _) | (_, Err(error)) => Err(error.into()),
        }
    }

    fn existing_object(&self) -> Map<String, Value> {
        self.files
            .read(&self.path)
            .ok()
            .flatten()
            .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
            .and_then(|value| match value {
                Value::Object(root) => Some(root),
                _ => None,
            })
            .unwrap_or_default()
    }
}

fn recovered(warning: ConfigLoadWarning) -> ConfigLoadResult {
    ConfigLoadResult {
        config: AppConfig::default(),
        source: ConfigLoadSource::DefaultsRecovered,
        warning: Some(warning),
    }
}

fn merge_nested(
    root: &mut Map<String, Value>,
    current: &Map<String, Value>,
    key: &str,
    previous: Option<Map<String, Value>>,
) {
    if let (Some(mut previous), Some(next)) =
        (previous, current.get(key).and_then(Value::as_object))
    {
        previous.extend(next.clone());
        root.insert(key.to_owned(), Value::Object(previous));
    }
}

fn decode_config(root: &Map<String, Value>) -> AppConfig {
    let defaults = AppConfig::default();
    let power = decode_power(root.get("power"));
    let legacy_keeps_awake_on_adapter = bool_value(root, "disableLidSleepInCharging")
        .unwrap_or(defaults.disable_lid_sleep_in_charging);
    let legacy_keeps_awake_on_battery = bool_value(root, "disableLidSleepOnBattery")
        .unwrap_or(defaults.disable_lid_sleep_on_battery);
    let display = decode_display(
        root.get("display"),
        &power,
        legacy_keeps_awake_on_adapter,
        legacy_keeps_awake_on_battery,
    );
    AppConfig {
        schema_version: int_value(root, "schemaVersion").unwrap_or(defaults.schema_version),
        language: text_value(root, "language").unwrap_or(defaults.language),
        enabled: bool_value(root, "enabled").unwrap_or(defaults.enabled),
        launch_at_login: bool_value(root, "launchAtLogin").unwrap_or(defaults.launch_at_login),
        low_battery_capacity_sleep: bool_value(root, "lowBatteryCapacitySleep")
            .unwrap_or(defaults.low_battery_capacity_sleep),
        low_battery_capacity: int_value(root, "lowBatteryCapacity")
            .unwrap_or(defaults.low_battery_capacity),
        low_time_remaining_minutes: int_value(root, "lowTimeRemaining")
            .unwrap_or(defaults.low_time_remaining_minutes),
        disable_idle_sleep_in_charging: bool_value(root, "disableIdleSleepInCharging")
            .unwrap_or(defaults.disable_idle_sleep_in_charging),
        disable_lid_sleep_in_charging: legacy_keeps_awake_on_adapter,
        disable_lid_sleep_on_battery: legacy_keeps_awake_on_battery,
        dark_wake_awareness_enabled: bool_value(root, "darkWakeAwarenessEnabled")
            .unwrap_or(defaults.dark_wake_awareness_enabled),
        lid_sleep_immediate_on_close: bool_value(root, "lidSleepImmediateOnClose")
            .unwrap_or(defaults.lid_sleep_immediate_on_close),
        notifications_enabled: bool_value(root, "notificationsEnabled")
            .unwrap_or(defaults.notifications_enabled),
        update_check_enabled: bool_value(root, "updateCheckEnabled")
            .unwrap_or(defaults.update_check_enabled),
        update_check_interval_hours: int_value(root, "updateCheckIntervalHours")
            .unwrap_or(defaults.update_check_interval_hours),
        last_update_check_epoch_seconds: long_value(root, "lastUpdateCheckEpochSeconds")
            .unwrap_or(defaults.last_update_check_epoch_seconds),
        hibernate_mode: int_value(root, "hibernateMode")
            .filter(|mode| SUPPORTED_HIBERNATE_MODES.contains(mode)),
        first_run: bool_value(root, "firstRun").unwrap_or(defaults.first_run),
        shelf_enabled: bool_value(root, "shelfEnabled").unwrap_or(defaults.shelf_enabled),
        screenshot_inbox_enabled: bool_value(root, "screenshotInboxEnabled")
            .unwrap_or(defaults.screenshot_inbox_enabled),
        shelf_sounds_enabled: bool_value(root, "shelfSoundsEnabled")
            .unwrap_or(defaults.shelf_sounds_enabled),
        clipboard_enabled: bool_value(root, "clipboardEnabled")
            .unwrap_or(defaults.clipboard_enabled),
        clipboard_paste_stack_hot_key: text_value(root, "clipboardPasteStackHotKey")
            .unwrap_or(defaults.clipboard_paste_stack_hot_key),
        clipboard_capture_hot_key: text_value(root, "clipboardCaptureHotKey")
            .unwrap_or(defaults.clipboard_capture_hot_key),
        power,
        display,
        charge_limit_enabled: bool_value(root, "chargeLimitEnabled")
            .unwrap_or(defaults.charge_limit_enabled),
        charge_limit_percent: int_value(root, "chargeLimitPercent")
            .unwrap_or(defaults.charge_limit_percent),
        charge_limit_active_discharge: bool_value(root, "chargeLimitActiveDischarge")
            .unwrap_or(defaults.charge_limit_active_discharge),
        file_naming: decode_file_naming(root.get("fileNaming")),
    }
    .normalized()
}

fn decode_power(value: Option<&Value>) -> PowerConfig {
    let defaults = PowerConfig::default();
    let Some(root) = value.and_then(Value::as_object) else {
        return defaults;
    };
    PowerConfig {
        enabled: bool_value(root, "enabled").unwrap_or(defaults.enabled),
        keep_awake_on_adapter: bool_value(root, "keepAwakeOnAdapter")
            .unwrap_or(defaults.keep_awake_on_adapter),
        keep_awake_on_battery: bool_value(root, "keepAwakeOnBattery")
            .unwrap_or(defaults.keep_awake_on_battery),
        allow_closed_lid: bool_value(root, "allowClosedLid").unwrap_or(defaults.allow_closed_lid),
        pause_closed_lid_with_external_display: bool_value(
            root,
            "pauseClosedLidWithExternalDisplay",
        )
        .unwrap_or(defaults.pause_closed_lid_with_external_display),
        battery_floor_percent: int_value(root, "batteryFloorPercent")
            .unwrap_or(defaults.battery_floor_percent),
        battery_floor_recovery_percent: int_value(root, "batteryFloorRecoveryPercent")
            .unwrap_or(defaults.battery_floor_recovery_percent),
        yield_on_low_power_mode: bool_value(root, "yieldOnLowPowerMode")
            .unwrap_or(defaults.yield_on_low_power_mode),
        heat_guard_enabled: bool_value(root, "heatGuardEnabled")
            .unwrap_or(defaults.heat_guard_enabled),
        closed_lid_time_cap_minutes: int_value(root, "closedLidTimeCapMinutes")
            .unwrap_or(defaults.closed_lid_time_cap_minutes),
        closed_lid_zero_brightness: bool_value(root, "closedLidZeroBrightness")
            .unwrap_or(defaults.closed_lid_zero_brightness),
    }
}

fn decode_display(
    value: Option<&Value>,
    power: &PowerConfig,
    keeps_awake_on_adapter: bool,
    keeps_awake_on_battery: bool,
) -> Option<DisplayConfig> {
    let root = value?.as_object()?;
    let defaults =
        DisplayConfig::from_legacy(power, keeps_awake_on_adapter, keeps_awake_on_battery);
    let keep_awake_when_lid_closed =
        bool_value(root, "keepAwakeWhenLidClosed").unwrap_or(defaults.keep_awake_when_lid_closed);
    let fallback_policy = if keep_awake_when_lid_closed {
        defaults.closed_lid_power_policy
    } else {
        ClosedLidPowerPolicy::Sleep
    };
    let policy = ClosedLidPowerPolicy::from_wire(root.get("closedLidPowerPolicy"))
        .unwrap_or(fallback_policy);
    let mode = ClosedLidDisplayMode::from_wire(root.get("closedLidDisplayMode"))
        .unwrap_or(defaults.closed_lid_display_mode);
    Some(DisplayConfig {
        schema_version: int_value(root, "schemaVersion").unwrap_or(defaults.schema_version),
        keep_awake_when_lid_closed,
        closed_lid_power_policy: policy,
        closed_lid_display_mode: mode,
        pause_when_external_display_connected: bool_value(
            root,
            "pauseWhenExternalDisplayConnected",
        )
        .unwrap_or(defaults.pause_when_external_display_connected),
    })
}

fn decode_file_naming(value: Option<&Value>) -> FileNamingPolicy {
    let defaults = FileNamingPolicy::default();
    let Some(root) = value.and_then(Value::as_object) else {
        return defaults;
    };
    FileNamingPolicy {
        schema_version: int_value(root, "schemaVersion").unwrap_or(defaults.schema_version),
        template: text_value(root, "template").unwrap_or(defaults.template),
        max_utf8_bytes: int_value(root, "maxUTF8Bytes").unwrap_or(defaults.max_utf8_bytes),
        separator: text_value(root, "separator").unwrap_or(defaults.separator),
        lowercase_latin: bool_value(root, "lowercaseLatin").unwrap_or(defaults.lowercase_latin),
        preserve_extension: bool_value(root, "preserveExtension")
            .unwrap_or(defaults.preserve_extension),
        date_source: FileNamingDateSource::from_wire(root.get("dateSource"))
            .unwrap_or(defaults.date_source),
        conflict_policy: FileNamingConflictPolicy::from_wire(root.get("conflictPolicy"))
            .unwrap_or(defaults.conflict_policy),
        conflict_suffix: text_value(root, "conflictSuffix").unwrap_or(defaults.conflict_suffix),
        min_confidence: double_value(root, "minConfidence").unwrap_or(defaults.min_confidence),
        require_preview: bool_value(root, "requirePreview").unwrap_or(defaults.require_preview),
        allow_vision: bool_value(root, "allowVision").unwrap_or(defaults.allow_vision),
    }
}

fn bool_value(root: &Map<String, Value>, key: &str) -> Option<bool> {
    root.get(key)?.as_bool()
}

fn int_value(root: &Map<String, Value>, key: &str) -> Option<i32> {
    i32::try_from(root.get(key)?.as_i64()?).ok()
}

fn long_value(root: &Map<String, Value>, key: &str) -> Option<i64> {
    root.get(key)?.as_i64()
}

fn double_value(root: &Map<String, Value>, key: &str) -> Option<f64> {
    root.get(key)?.as_f64()
}

fn text_value(root: &Map<String, Value>, key: &str) -> Option<String> {
    match root.get(key)? {
        Value::String(value) => Some(value.clone()),
        Value::Number(value) => Some(value.to_string()),
        Value::Bool(value) => Some(value.to_string()),
        Value::Null | Value::Array(_) | Value::Object(_) => None,
    }
}

fn normalize_hot_key(value: &str, fallback: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() || trimmed.encode_utf16().count() > 32 {
        fallback.to_owned()
    } else {
        trimmed.to_owned()
    }
}

fn normalize_charge_limit(percent: i32) -> i32 {
    if (40..=100).contains(&percent) && percent % 5 == 0 {
        percent
    } else {
        DEFAULT_CHARGE_LIMIT_PERCENT
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalization_matches_current_rules() {
        let mut config = AppConfig {
            low_battery_capacity: 999,
            low_time_remaining_minutes: -2,
            update_check_interval_hours: 0,
            last_update_check_epoch_seconds: -10,
            hibernate_mode: Some(7),
            clipboard_paste_stack_hot_key: " control+shift+B ".to_owned(),
            clipboard_capture_hot_key: "x".repeat(64),
            charge_limit_percent: 79,
            ..AppConfig::default()
        };
        config.power.battery_floor_percent = 120;
        config.power.battery_floor_recovery_percent = 0;
        config.power.closed_lid_time_cap_minutes = 0;
        config.file_naming.template = "  {category}-{title}  ".to_owned();
        config.file_naming.max_utf8_bytes = 999;
        config.file_naming.min_confidence = f64::NAN;
        config.file_naming.preserve_extension = false;
        config.file_naming.require_preview = false;
        let config = config.normalized();
        assert_eq!(config.low_battery_capacity, 100);
        assert_eq!(config.low_time_remaining_minutes, 0);
        assert_eq!(config.update_check_interval_hours, 1);
        assert_eq!(config.last_update_check_epoch_seconds, 0);
        assert_eq!(config.hibernate_mode, None);
        assert_eq!(config.clipboard_paste_stack_hot_key, "control+shift+B");
        assert_eq!(config.clipboard_capture_hot_key, DEFAULT_CAPTURE_HOT_KEY);
        assert_eq!(config.charge_limit_percent, DEFAULT_CHARGE_LIMIT_PERCENT);
        assert_eq!(config.power.battery_floor_percent, 99);
        assert_eq!(config.power.battery_floor_recovery_percent, 100);
        assert_eq!(config.power.closed_lid_time_cap_minutes, 1);
        assert_eq!(config.file_naming.template, "{category}-{title}");
        assert_eq!(config.file_naming.max_utf8_bytes, 255);
        assert_eq!(
            config.file_naming.min_confidence,
            DEFAULT_FILE_NAMING_MIN_CONFIDENCE
        );
        assert!(config.file_naming.preserve_extension);
        assert!(config.file_naming.require_preview);
        assert!(config.display.is_some());
    }

    #[test]
    fn numeric_and_boolean_strings_follow_kotlin_content_rules() {
        let mut root = Map::new();
        root.insert("language".to_owned(), Value::from(42));
        root.insert("enabled".to_owned(), Value::from("yes"));
        let config = decode_config(&root);
        assert_eq!(config.language, "42");
        assert!(config.enabled);
    }

    #[test]
    fn legacy_display_values_create_the_same_policy() {
        let policy = ClosedLidPowerPolicy::resolve(true, true, false);
        assert_eq!(policy, ClosedLidPowerPolicy::Adapter);
        assert!(policy.keeps_awake_on_adapter());
        assert!(!policy.keeps_awake_on_battery());
    }
}

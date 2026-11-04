use covio_core::{
    AppConfig, ConfigLoadSource, ConfigLoadWarning, ConfigStore, DEFAULT_CAPTURE_HOT_KEY,
    DEFAULT_PASTE_STACK_HOT_KEY,
};
use covio_platform::{FileStore, PlatformError};
use serde_json::Value;
use std::cell::{Cell, RefCell};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;

const CONFIG_PATH: &str = "/tmp/covio/config.json";
const LEGACY_FIXTURE: &str = include_str!("fixtures/config-v3-legacy-21.json");
const CURRENT_FIXTURE: &str = include_str!("fixtures/config-v3-current.json");

#[derive(Default)]
struct MemoryInner {
    files: RefCell<BTreeMap<PathBuf, Vec<u8>>>,
    fail_read: Cell<bool>,
    fail_write: Cell<bool>,
    atomic_writes: RefCell<Vec<PathBuf>>,
    created_directories: RefCell<Vec<PathBuf>>,
}

#[derive(Clone, Default)]
struct MemoryFiles(Rc<MemoryInner>);

impl MemoryFiles {
    fn with_file(path: &str, contents: &str) -> Self {
        let files = Self::default();
        files
            .0
            .files
            .borrow_mut()
            .insert(PathBuf::from(path), contents.as_bytes().to_vec());
        files
    }

    fn text(&self, path: &str) -> String {
        let files = self.0.files.borrow();
        String::from_utf8(files[&PathBuf::from(path)].clone()).expect("utf-8 test file")
    }

    fn set_fail_read(&self, fail: bool) {
        self.0.fail_read.set(fail);
    }

    fn set_fail_write(&self, fail: bool) {
        self.0.fail_write.set(fail);
    }

    fn atomic_writes(&self) -> Vec<PathBuf> {
        self.0.atomic_writes.borrow().clone()
    }

    fn created_directories(&self) -> Vec<PathBuf> {
        self.0.created_directories.borrow().clone()
    }
}

impl FileStore for MemoryFiles {
    fn read(&self, path: &Path) -> Result<Option<Vec<u8>>, PlatformError> {
        if self.0.fail_read.get() {
            return Err(PlatformError::io("read failed", false));
        }
        Ok(self.0.files.borrow().get(path).cloned())
    }

    fn create_dir_all(&self, path: &Path) -> Result<(), PlatformError> {
        self.0
            .created_directories
            .borrow_mut()
            .push(path.to_path_buf());
        Ok(())
    }

    fn write_atomic(&self, path: &Path, contents: &[u8]) -> Result<(), PlatformError> {
        if self.0.fail_write.get() {
            return Err(PlatformError::io("write failed", false));
        }
        self.0.atomic_writes.borrow_mut().push(path.to_path_buf());
        self.0
            .files
            .borrow_mut()
            .insert(path.to_path_buf(), contents.to_vec());
        Ok(())
    }

    fn remove_file(&self, path: &Path) -> Result<bool, PlatformError> {
        Ok(self.0.files.borrow_mut().remove(path).is_some())
    }
}

fn store_with_fixture(fixture: &str) -> (ConfigStore<MemoryFiles>, MemoryFiles) {
    let files = MemoryFiles::with_file(CONFIG_PATH, fixture);
    (ConfigStore::new(CONFIG_PATH, files.clone()), files)
}

#[test]
fn legacy_fixture_loads_every_old_field_and_adds_clipboard_defaults() {
    let (store, _) = store_with_fixture(LEGACY_FIXTURE);
    let loaded = store.load();
    assert_eq!(loaded.source, ConfigLoadSource::Loaded);
    assert_eq!(loaded.warning, None);
    let config = loaded.config;
    assert_eq!(config.schema_version, 3);
    assert_eq!(config.language, "zh-Hans");
    assert!(!config.enabled);
    assert!(config.launch_at_login);
    assert!(!config.low_battery_capacity_sleep);
    assert_eq!(config.low_battery_capacity, 15);
    assert_eq!(config.low_time_remaining_minutes, 25);
    assert!(config.disable_idle_sleep_in_charging);
    assert!(config.disable_lid_sleep_in_charging);
    assert!(config.disable_lid_sleep_on_battery);
    assert!(!config.dark_wake_awareness_enabled);
    assert!(config.lid_sleep_immediate_on_close);
    assert!(!config.notifications_enabled);
    assert!(!config.update_check_enabled);
    assert_eq!(config.update_check_interval_hours, 12);
    assert_eq!(config.last_update_check_epoch_seconds, 1_700_000_000);
    assert_eq!(config.hibernate_mode, Some(3));
    assert!(!config.first_run);
    assert!(!config.shelf_enabled);
    assert!(!config.screenshot_inbox_enabled);
    assert!(!config.shelf_sounds_enabled);
    assert!(config.clipboard_enabled);
    assert!(config.lid_sleep_immediate_on_close);
    assert_eq!(
        config
            .display
            .as_ref()
            .map(|display| display.closed_lid_power_policy),
        Some(covio_core::ClosedLidPowerPolicy::Any)
    );
    assert_eq!(config.charge_limit_percent, 70);
    assert_eq!(config.file_naming, covio_core::FileNamingPolicy::default());
    assert_eq!(
        config.clipboard_paste_stack_hot_key,
        DEFAULT_PASTE_STACK_HOT_KEY
    );
    assert_eq!(config.clipboard_capture_hot_key, DEFAULT_CAPTURE_HOT_KEY);
}

#[test]
fn legacy_fixture_round_trips_to_the_current_fixture() {
    let (store, files) = store_with_fixture(LEGACY_FIXTURE);
    let loaded = store.load();
    store.save(&loaded.config).expect("save fixture");

    let actual: Value = serde_json::from_str(&files.text(CONFIG_PATH)).expect("saved json");
    let expected: Value = serde_json::from_str(CURRENT_FIXTURE).expect("current fixture");
    assert_eq!(actual, expected);
}

#[test]
fn current_fixture_round_trips_without_change() {
    let (store, files) = store_with_fixture(CURRENT_FIXTURE);
    let loaded = store.load();
    store.save(&loaded.config).expect("save fixture");

    let actual: Value = serde_json::from_str(&files.text(CONFIG_PATH)).expect("saved json");
    let expected: Value = serde_json::from_str(CURRENT_FIXTURE).expect("current fixture");
    assert_eq!(actual, expected);
}

#[test]
fn one_bad_key_falls_back_without_affecting_other_keys() {
    let files = MemoryFiles::with_file(
        CONFIG_PATH,
        r#"{"enabled":"yes","lowBatteryCapacity":15,"language":42}"#,
    );
    let store = ConfigStore::new(CONFIG_PATH, files);
    let config = store.load().config;
    assert!(config.enabled);
    assert_eq!(config.low_battery_capacity, 15);
    assert_eq!(config.language, "42");
}

#[test]
fn unknown_keys_and_values_survive_save() {
    let files = MemoryFiles::with_file(
        CONFIG_PATH,
        r#"{"enabled":true,"someFutureKey":{"keep":true},"anotherOne":42}"#,
    );
    let store = ConfigStore::new(CONFIG_PATH, files.clone());
    let config = AppConfig {
        enabled: false,
        ..AppConfig::default()
    };
    store.save(&config).expect("save");

    let saved: Value = serde_json::from_str(&files.text(CONFIG_PATH)).expect("saved json");
    assert_eq!(saved["enabled"], false);
    assert_eq!(saved["someFutureKey"]["keep"], true);
    assert_eq!(saved["anotherOne"], 42);
}

#[test]
fn unknown_nested_keys_survive_save() {
    let files = MemoryFiles::with_file(
        CONFIG_PATH,
        r#"{"power":{"futurePower":1},"display":{"futureDisplay":2},"fileNaming":{"futureNaming":3}}"#,
    );
    let store = ConfigStore::new(CONFIG_PATH, files.clone());
    store
        .save(&AppConfig::default().normalized())
        .expect("save");

    let saved: Value = serde_json::from_str(&files.text(CONFIG_PATH)).expect("saved json");
    assert_eq!(saved["power"]["futurePower"], 1);
    assert_eq!(saved["display"]["futureDisplay"], 2);
    assert_eq!(saved["fileNaming"]["futureNaming"], 3);
}

#[test]
fn malformed_nested_fields_only_fall_back_that_field() {
    let files = MemoryFiles::with_file(
        CONFIG_PATH,
        r#"{"enabled":false,"power":{"enabled":"yes","batteryFloorPercent":25},"display":{"closedLidPowerPolicy":"battery"},"fileNaming":{"template":"{category}-{title}","maxUTF8Bytes":"bad","minConfidence":0.8}}"#,
    );
    let config = ConfigStore::new(CONFIG_PATH, files).load().config;
    assert!(!config.enabled);
    assert!(config.power.enabled);
    assert_eq!(config.power.battery_floor_percent, 25);
    assert_eq!(
        config.display.as_ref().unwrap().closed_lid_power_policy,
        covio_core::ClosedLidPowerPolicy::Battery
    );
    assert_eq!(config.file_naming.template, "{category}-{title}");
    assert_eq!(
        config.file_naming.max_utf8_bytes,
        covio_core::DEFAULT_FILE_NAMING_MAX_UTF8_BYTES
    );
    assert_eq!(config.file_naming.min_confidence, 0.8);
}

#[test]
fn missing_file_creates_a_full_default_config() {
    let files = MemoryFiles::default();
    let store = ConfigStore::new(CONFIG_PATH, files.clone());
    let loaded = store.load();
    assert_eq!(loaded.source, ConfigLoadSource::DefaultsCreated);
    assert_eq!(loaded.warning, None);
    assert_eq!(loaded.config, AppConfig::default().normalized());
    assert_eq!(
        files.created_directories(),
        vec![PathBuf::from("/tmp/covio")]
    );
    assert_eq!(files.atomic_writes(), vec![PathBuf::from(CONFIG_PATH)]);

    let saved: Value = serde_json::from_str(&files.text(CONFIG_PATH)).expect("saved json");
    for key in [
        "schemaVersion",
        "language",
        "enabled",
        "launchAtLogin",
        "lowBatteryCapacitySleep",
        "lowBatteryCapacity",
        "lowTimeRemaining",
        "disableIdleSleepInCharging",
        "disableLidSleepInCharging",
        "disableLidSleepOnBattery",
        "darkWakeAwarenessEnabled",
        "lidSleepImmediateOnClose",
        "notificationsEnabled",
        "updateCheckEnabled",
        "updateCheckIntervalHours",
        "lastUpdateCheckEpochSeconds",
        "hibernateMode",
        "firstRun",
        "shelfEnabled",
        "screenshotInboxEnabled",
        "shelfSoundsEnabled",
        "clipboardEnabled",
        "clipboardPasteStackHotKey",
        "clipboardCaptureHotKey",
        "power",
        "display",
        "chargeLimitEnabled",
        "chargeLimitPercent",
        "chargeLimitActiveDischarge",
        "fileNaming",
    ] {
        assert!(saved.get(key).is_some(), "missing key {key}");
    }
}

#[test]
fn broken_and_unreadable_files_recover_to_defaults() {
    let files = MemoryFiles::with_file(CONFIG_PATH, "{");
    let loaded = ConfigStore::new(CONFIG_PATH, files.clone()).load();
    assert_eq!(loaded.config, AppConfig::default());
    assert_eq!(loaded.source, ConfigLoadSource::DefaultsRecovered);
    assert_eq!(loaded.warning, Some(ConfigLoadWarning::InvalidJson));

    files.set_fail_read(true);
    let loaded = ConfigStore::new(CONFIG_PATH, files).load();
    assert_eq!(loaded.source, ConfigLoadSource::DefaultsRecovered);
    assert_eq!(loaded.warning, Some(ConfigLoadWarning::ReadFailed));
}

#[test]
fn write_failure_returns_a_typed_error() {
    let files = MemoryFiles::default();
    files.set_fail_write(true);
    let store = ConfigStore::new(CONFIG_PATH, files);
    let error = store
        .save(&AppConfig::default())
        .expect_err("write failure");
    assert_eq!(error.code(), covio_core::CoreErrorCode::Io);
}

#[test]
fn clear_removes_the_config_and_temporary_file() {
    let files = MemoryFiles::with_file(CONFIG_PATH, CURRENT_FIXTURE);
    files
        .0
        .files
        .borrow_mut()
        .insert(PathBuf::from(format!("{CONFIG_PATH}.tmp")), b"{}".to_vec());
    let probe = files.clone();
    let store = ConfigStore::new(CONFIG_PATH, files);
    assert!(store.clear().expect("clear"));
    let remaining = probe.0.files.borrow();
    assert!(!remaining.contains_key(&PathBuf::from(CONFIG_PATH)));
    assert!(!remaining.contains_key(&PathBuf::from(format!("{CONFIG_PATH}.tmp"))));
}

#[test]
fn save_uses_the_atomic_file_capability() {
    let files = MemoryFiles::default();
    let store = ConfigStore::new(CONFIG_PATH, files.clone());
    store.save(&AppConfig::default()).expect("save");
    assert_eq!(files.atomic_writes(), vec![PathBuf::from(CONFIG_PATH)]);
}

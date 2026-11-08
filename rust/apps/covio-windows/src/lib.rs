//! Platform-neutral host state and Windows application entry points.

#![forbid(unsafe_code)]

mod core_runtime;
mod host_model;

pub use core_runtime::{
    CORE_PROTOCOL_VERSION, CoreResponse, CoreRuntime, CoreRuntimeError, HostCoreError, HostSnapshot,
};
pub use host_model::{CloseDisposition, HostModel, HostStatus, HostView, ThemePreference};

use covio_core::AppConfig;
use covio_core::workspace::WorkspaceStore;
use covio_ffi::AppCore;
use covio_platform::{DataPaths, StdFileStore};
use serde::Serialize;
use serde_json::json;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Paths used by the Windows host before the capability adapter is installed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WindowsDataPaths {
    paths: DataPaths,
}

impl WindowsDataPaths {
    /// Builds the Windows data layout under one root.
    #[must_use]
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self {
            paths: DataPaths::windows(root),
        }
    }

    /// Builds an application core with these paths.
    #[must_use]
    pub fn app_core(&self) -> AppCore {
        AppCore::with_paths(
            self.paths.config_file.clone(),
            self.paths.shelf_file.clone(),
            self.paths.clipboard_file(),
            self.paths.workspace_directory.clone(),
        )
    }

    /// Returns the Windows host UI settings file.
    #[must_use]
    pub fn ui_settings_file(&self) -> PathBuf {
        self.paths.config_file.with_file_name("windows-ui.json")
    }

    /// Returns the local content path for one workspace entry.
    #[must_use]
    pub fn workspace_content_path(&self, entry_id: &str) -> Option<PathBuf> {
        WorkspaceStore::new(self.paths.workspace_directory.clone(), StdFileStore::new())
            .content_path(entry_id)
    }
}

/// Result written by the headless Windows host smoke command.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HeadlessSmokeReport {
    /// Core protocol checked by the smoke run.
    pub protocol_version: u32,
    /// First snapshot loaded from the temporary data root.
    pub initial_snapshot: HostSnapshot,
    /// Snapshot loaded after the first runtime shuts down.
    pub restarted_snapshot: HostSnapshot,
    /// Whether the changed setting survived the restart.
    pub restart_preserved: bool,
    /// Whether shutdown rejected a later request.
    pub shutdown_closed_submissions: bool,
}

/// Result written by the Windows capability smoke command.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CapabilitySmokeReport {
    /// The Windows app-data directory was resolved from the environment.
    pub app_data_available: bool,
    /// An existing file was atomically replaced and read back.
    pub atomic_write: bool,
    /// Credential Manager write, read, replace, and delete all succeeded.
    pub credential_manager: bool,
    /// Clipboard text round-tripped and the previous value was restored.
    pub clipboard: bool,
    /// Current-user startup registration enabled, reported enabled, and disabled.
    pub startup: bool,
    /// A screenshot directory was discovered.
    pub screenshot_directory: bool,
    /// File-picker request validation succeeded.
    pub file_picker: bool,
    /// Notification request validation succeeded.
    pub notification: bool,
    /// A copied updater executable started and produced a marker.
    pub update_handoff: bool,
    /// Power capability returned a typed unavailable error.
    pub power_unavailable: bool,
}

/// Seeds bounded demo state for Windows screenshot smoke runs.
pub fn seed_screenshot_smoke_data(root: &Path) -> Result<(), String> {
    use covio_core::clipboard::{ClipItem, ClipKind, ClipboardState};
    use covio_core::shelf::{ShelfItem, ShelfStoreState};
    use covio_core::workspace::WorkspaceState;

    let paths = WindowsDataPaths::new(root);
    let core = paths.app_core();
    let now = now_epoch_seconds();
    let screenshot = root.join("Screenshots").join("Covio demo.png");
    if let Some(parent) = screenshot.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|_| "cannot create screenshot smoke data".to_owned())?;
    }
    std::fs::write(&screenshot, b"png")
        .map_err(|_| "cannot write screenshot smoke data".to_owned())?;
    let shelf = ShelfStoreState {
        items: vec![ShelfItem {
            path: screenshot.to_string_lossy().into_owned(),
            added_at_epoch_seconds: now,
        }],
        ..ShelfStoreState::default()
    };
    core.call("shelf.save", &json!({"state": shelf}), now)
        .map_err(|error| format!("cannot seed shelf smoke data: {error}"))?;

    let clipboard = ClipboardState {
        items: vec![
            ClipItem {
                id: "smoke-text".to_owned(),
                kind: ClipKind::Text,
                text: "A captured note".to_owned(),
                byte_size: 15,
                created_at_epoch_seconds: now,
                source_bundle_id: "windows.smoke".to_owned(),
                ..ClipItem::default()
            },
            ClipItem {
                id: "smoke-link".to_owned(),
                kind: ClipKind::Link,
                text: "https://github.com/wyz541/kmp-Covio".to_owned(),
                byte_size: 36,
                created_at_epoch_seconds: now.saturating_sub(1),
                source_bundle_id: "windows.smoke".to_owned(),
                ..ClipItem::default()
            },
        ],
        ..ClipboardState::default()
    };
    core.call("clipboard.save", &json!({"state": clipboard}), now)
        .map_err(|error| format!("cannot seed clipboard smoke data: {error}"))?;
    core.call(
        "workspace.putText",
        &json!({
            "state": WorkspaceState::default(),
            "text": "Workspace smoke note",
            "displayName": "Screenshot notes.txt",
            "contentType": "text/plain",
            "originDeviceId": "windows:smoke",
        }),
        now,
    )
    .map_err(|error| format!("cannot seed workspace smoke data: {error}"))?;
    Ok(())
}

/// Runs a core restart smoke without opening a GUI.
pub fn run_headless_smoke() -> Result<HeadlessSmokeReport, String> {
    let root = smoke_root();
    let result = run_headless_smoke_at(&root);
    let _ = std::fs::remove_dir_all(&root);
    result
}

/// Runs the native Windows capability smoke without opening a GUI.
#[cfg(target_os = "windows")]
pub fn run_capability_smoke() -> Result<CapabilitySmokeReport, String> {
    let root = smoke_root();
    let result = run_capability_smoke_at(&root);
    let _ = std::fs::remove_dir_all(&root);
    result
}

/// Rejects the Windows capability smoke on non-Windows hosts.
#[cfg(not(target_os = "windows"))]
pub fn run_capability_smoke() -> Result<CapabilitySmokeReport, String> {
    Err("Windows capability smoke requires Windows".to_owned())
}

#[cfg(target_os = "windows")]
fn run_capability_smoke_at(root: &Path) -> Result<CapabilitySmokeReport, String> {
    use covio_platform::{
        CapabilityKind, Clipboard, FilePickerRequest, FileStore, NotificationRequest,
        ScreenshotDirectory, SecretKey, SecretStore, SecretValue, StartupRegistration, StartupSpec,
        UpdateHandoff, UpdateHandoffRequest, WindowsAppDataDirectory, WindowsPlatformAdapters,
    };

    let adapters = WindowsPlatformAdapters::default();
    for kind in [
        CapabilityKind::Filesystem,
        CapabilityKind::Process,
        CapabilityKind::Notification,
        CapabilityKind::Update,
        CapabilityKind::SecureStorage,
        CapabilityKind::Clipboard,
        CapabilityKind::Screenshot,
        CapabilityKind::Startup,
        CapabilityKind::FilePicker,
    ] {
        adapters
            .capabilities
            .status(kind)
            .require()
            .map_err(|error| error.message().to_owned())?;
    }
    let power_error = adapters
        .capabilities
        .status(CapabilityKind::Power)
        .require()
        .expect_err("Windows must not claim macOS power capability");
    let power_unavailable = power_error.code() == covio_platform::PlatformErrorCode::Unavailable;

    let app_data =
        WindowsAppDataDirectory::from_environment().map_err(|error| error.message().to_owned())?;
    let app_data_available = app_data
        .file_name()
        .is_some_and(|name| name == covio_platform::APP_NAME);

    let state_file = root.join("capability/state.json");
    adapters
        .filesystem
        .write_atomic(&state_file, b"first")
        .map_err(|error| error.message().to_owned())?;
    adapters
        .filesystem
        .write_atomic(&state_file, b"second")
        .map_err(|error| error.message().to_owned())?;
    let atomic_write = adapters
        .filesystem
        .read(&state_file)
        .map_err(|error| error.message().to_owned())?
        .is_some_and(|value| value == b"second");

    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| "system clock is before the Unix epoch".to_owned())?
        .as_nanos();
    let secret_key = SecretKey::try_new(format!("capability-smoke-{}-{nonce}", std::process::id()))
        .map_err(|error| error.message().to_owned())?;
    adapters
        .credentials
        .write(&secret_key, &SecretValue::new(b"first-secret".to_vec()))
        .map_err(|error| error.message().to_owned())?;
    let credential_written = adapters
        .credentials
        .read(&secret_key)
        .map_err(|error| error.message().to_owned())?
        .is_some_and(|value| value.expose() == b"first-secret");
    adapters
        .credentials
        .write(&secret_key, &SecretValue::new(b"second-secret".to_vec()))
        .map_err(|error| error.message().to_owned())?;
    let credential_replaced = adapters
        .credentials
        .read(&secret_key)
        .map_err(|error| error.message().to_owned())?
        .is_some_and(|value| value.expose() == b"second-secret");
    adapters
        .credentials
        .delete(&secret_key)
        .map_err(|error| error.message().to_owned())?;
    let credential_deleted = adapters
        .credentials
        .read(&secret_key)
        .map_err(|error| error.message().to_owned())?
        .is_none();
    let credential_manager = credential_written && credential_replaced && credential_deleted;

    let previous_clipboard = adapters
        .clipboard
        .read_text()
        .map_err(|error| error.message().to_owned())?;
    let clipboard_marker = format!("Covio capability smoke {nonce}");
    adapters
        .clipboard
        .write_text(&clipboard_marker)
        .map_err(|error| error.message().to_owned())?;
    let clipboard_round_trip = adapters
        .clipboard
        .read_text()
        .map_err(|error| error.message().to_owned())?
        .is_some_and(|value| value == clipboard_marker);
    if let Some(previous) = previous_clipboard {
        adapters
            .clipboard
            .write_text(&previous)
            .map_err(|error| error.message().to_owned())?;
    } else {
        adapters
            .clipboard
            .clear()
            .map_err(|error| error.message().to_owned())?;
    }

    let executable =
        std::env::current_exe().map_err(|_| "current executable is unavailable".to_owned())?;
    let startup_spec = StartupSpec::new(
        format!("CovioCapabilitySmoke-{}", std::process::id()),
        executable,
    )
    .with_arguments(["--background"]);
    adapters
        .startup
        .enable(&startup_spec)
        .map_err(|error| error.message().to_owned())?;
    let startup_enabled = adapters
        .startup
        .is_enabled(&startup_spec)
        .map_err(|error| error.message().to_owned());
    let startup_disabled = adapters
        .startup
        .disable(&startup_spec)
        .map_err(|error| error.message().to_owned());
    let startup = startup_enabled? && startup_disabled.is_ok();

    let screenshot_candidate = root.join("Screenshots");
    std::fs::create_dir_all(&screenshot_candidate)
        .map_err(|_| "cannot create the screenshot smoke directory".to_owned())?;
    let screenshot_directory =
        covio_platform::WindowsScreenshotDirectory::with_candidates([screenshot_candidate])
            .directory()
            .is_ok();
    let file_picker = FilePickerRequest::new("Open file")
        .with_extensions(["png", "jpg"])
        .multiple(true)
        .validate()
        .is_ok();
    let notification = NotificationRequest::new("Covio", "Capability smoke")
        .validate()
        .is_ok();

    let updater = root.join("CovioUpdater.exe");
    std::fs::copy(
        &std::env::current_exe().map_err(|_| "current executable is unavailable".to_owned())?,
        &updater,
    )
    .map_err(|_| "cannot stage the updater smoke executable".to_owned())?;
    let marker = root.join("update-handoff.marker");
    let update_request = UpdateHandoffRequest::new(&updater).with_arguments([
        "--capability-smoke-helper".to_owned(),
        marker.to_string_lossy().into_owned(),
    ]);
    adapters
        .update_handoff
        .launch(&update_request)
        .map_err(|error| error.message().to_owned())?;
    let update_deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    while std::time::Instant::now() < update_deadline && !marker.is_file() {
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    let update_handoff = marker.is_file();

    Ok(CapabilitySmokeReport {
        app_data_available,
        atomic_write,
        credential_manager,
        clipboard: clipboard_round_trip,
        startup,
        screenshot_directory,
        file_picker,
        notification,
        update_handoff,
        power_unavailable,
    })
}

/// Runs the core restart smoke at one explicit data root.
pub fn run_headless_smoke_at(root: &Path) -> Result<HeadlessSmokeReport, String> {
    let paths = WindowsDataPaths::new(root);
    let mut runtime = CoreRuntime::new(paths.app_core());
    let initial_id = runtime.request_snapshot(now_epoch_seconds())?;
    let initial = runtime
        .wait_for_response(initial_id, Duration::from_secs(5))
        .ok_or_else(|| "initial snapshot timed out".to_owned())?;
    if !initial.ok {
        return Err(initial.error.map_or_else(
            || "initial snapshot failed".to_owned(),
            |error| error.message,
        ));
    }
    let initial_snapshot = HostSnapshot::from_value(&initial.result)?;

    let mut config = AppConfig::from_json_value(&initial_snapshot.config);
    config.launch_at_login = true;
    config.clipboard_enabled = false;
    let save_id = runtime.request(
        "config.save",
        json!({"config": config}),
        now_epoch_seconds(),
    )?;
    let saved = runtime
        .wait_for_response(save_id, Duration::from_secs(5))
        .ok_or_else(|| "config save timed out".to_owned())?;
    if !saved.ok {
        return Err(saved
            .error
            .map_or_else(|| "config save failed".to_owned(), |error| error.message));
    }
    runtime.shutdown();
    let shutdown_closed_submissions = runtime
        .request("config.load", json!({}), now_epoch_seconds())
        .is_err();

    let mut restarted = CoreRuntime::new(paths.app_core());
    let restarted_id = restarted.request_snapshot(now_epoch_seconds())?;
    let restarted_response = restarted
        .wait_for_response(restarted_id, Duration::from_secs(5))
        .ok_or_else(|| "restarted snapshot timed out".to_owned())?;
    if !restarted_response.ok {
        return Err(restarted_response.error.map_or_else(
            || "restarted snapshot failed".to_owned(),
            |error| error.message,
        ));
    }
    let restarted_snapshot = HostSnapshot::from_value(&restarted_response.result)?;
    let restarted_config = AppConfig::from_json_value(&restarted_snapshot.config);
    let restart_preserved = restarted_config.launch_at_login && !restarted_config.clipboard_enabled;
    restarted.shutdown();

    Ok(HeadlessSmokeReport {
        protocol_version: CORE_PROTOCOL_VERSION,
        initial_snapshot,
        restarted_snapshot,
        restart_preserved,
        shutdown_closed_submissions,
    })
}

/// Returns the current Unix timestamp in seconds.
#[must_use]
pub fn now_epoch_seconds() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs() as i64)
}

fn smoke_root() -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_nanos());
    std::env::temp_dir().join(format!(
        "covio-windows-smoke-{}-{nonce}",
        std::process::id()
    ))
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ui_settings_file_lives_in_the_windows_data_root() {
        let root = PathBuf::from("CovioTest");
        let paths = WindowsDataPaths::new(root.clone());
        assert_eq!(paths.ui_settings_file(), root.join("windows-ui.json"));
    }
}

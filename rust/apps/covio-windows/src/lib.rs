//! Platform-neutral host state and Windows application entry points.

#![forbid(unsafe_code)]

mod core_runtime;
mod host_model;

pub use core_runtime::{
    CORE_PROTOCOL_VERSION, CoreResponse, CoreRuntime, CoreRuntimeError, HostCoreError, HostSnapshot,
};
pub use host_model::{CloseDisposition, HostModel, HostStatus, HostView, ThemePreference};

use covio_core::AppConfig;
use covio_ffi::AppCore;
use serde::Serialize;
use serde_json::json;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Paths used by the Windows host before the capability adapter is installed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WindowsDataPaths {
    /// The root of the Windows application data directory.
    pub root: PathBuf,
    /// The configuration file.
    pub config_file: PathBuf,
    /// The screenshot shelf file.
    pub shelf_file: PathBuf,
    /// The clipboard state file.
    pub clipboard_file: PathBuf,
    /// The workspace directory.
    pub workspace_directory: PathBuf,
}

impl WindowsDataPaths {
    /// Builds the Windows data layout under one root.
    #[must_use]
    pub fn new(root: impl Into<PathBuf>) -> Self {
        let root = root.into();
        Self {
            config_file: root.join("config.json"),
            shelf_file: root.join("Screenshots").join("shelf.json"),
            clipboard_file: root.join("Clipboard").join("clipboard.json"),
            workspace_directory: root.join("Workspace"),
            root,
        }
    }

    /// Builds an application core with these paths.
    #[must_use]
    pub fn app_core(&self) -> AppCore {
        AppCore::with_paths(
            self.config_file.clone(),
            self.shelf_file.clone(),
            self.clipboard_file.clone(),
            self.workspace_directory.clone(),
        )
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

/// Runs a core restart smoke without opening a GUI.
pub fn run_headless_smoke() -> Result<HeadlessSmokeReport, String> {
    let root = smoke_root();
    let result = run_headless_smoke_at(&root);
    let _ = std::fs::remove_dir_all(&root);
    result
}

fn run_headless_smoke_at(root: &Path) -> Result<HeadlessSmokeReport, String> {
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

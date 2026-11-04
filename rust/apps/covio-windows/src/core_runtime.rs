//! Bounded worker for Rust application commands.

use covio_core::clipboard::ClipboardState;
use covio_core::shelf::ShelfStoreState;
use covio_core::workspace::WorkspaceState;
use covio_ffi::AppCore;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::BTreeSet;
use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

/// Host-to-core protocol version.
pub const CORE_PROTOCOL_VERSION: u32 = 1;

/// A typed error returned by the core worker.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HostCoreError {
    /// Stable error category.
    pub code: String,
    /// User-safe error message.
    pub message: String,
}

impl HostCoreError {
    fn new(code: &str, message: impl Into<String>) -> Self {
        Self {
            code: code.to_owned(),
            message: message.into(),
        }
    }
}

/// One response from the core worker.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreResponse {
    /// Request id assigned by the host.
    pub request_id: u64,
    /// Command that produced the response.
    pub command: String,
    /// Whether the command succeeded.
    pub ok: bool,
    /// JSON result. Errors use an empty object.
    pub result: Value,
    /// Typed error for a failed command.
    pub error: Option<HostCoreError>,
}

/// Snapshot displayed by the Windows host.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HostSnapshot {
    /// Raw configuration object.
    pub config: Value,
    /// Number of screenshot shelf entries.
    pub shelf_item_count: usize,
    /// Number of clipboard entries.
    pub clipboard_item_count: usize,
    /// Number of workspace entries.
    pub workspace_entry_count: usize,
    /// Screenshot shelf state.
    pub shelf: ShelfStoreState,
    /// Clipboard history state.
    pub clipboard: ClipboardState,
    /// Workspace state.
    pub workspace: WorkspaceState,
    /// Time at which the worker loaded the snapshot.
    pub loaded_at_epoch_seconds: i64,
}

impl HostSnapshot {
    /// Parses one snapshot result from the worker.
    pub fn from_value(value: &Value) -> Result<Self, String> {
        serde_json::from_value(value.clone()).map_err(|error| error.to_string())
    }
}

/// Errors raised before a command reaches the worker.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CoreRuntimeError {
    /// The worker has already shut down.
    ShuttingDown,
    /// The worker channel is unavailable.
    WorkerUnavailable,
}

impl fmt::Display for CoreRuntimeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ShuttingDown => formatter.write_str("core runtime is shutting down"),
            Self::WorkerUnavailable => formatter.write_str("core worker is unavailable"),
        }
    }
}

impl std::error::Error for CoreRuntimeError {}

enum WorkerMessage {
    Execute {
        request_id: u64,
        command: String,
        payload: Value,
        now_epoch_seconds: i64,
        delay: Duration,
    },
    Shutdown,
}

/// A bounded worker that owns the Rust application service.
pub struct CoreRuntime {
    request_tx: Sender<WorkerMessage>,
    response_rx: Receiver<CoreResponse>,
    cancelled: Arc<Mutex<BTreeSet<u64>>>,
    shutdown_flag: Arc<AtomicBool>,
    pending: BTreeSet<u64>,
    next_request_id: u64,
    stopped: bool,
    worker: Option<JoinHandle<()>>,
}

impl CoreRuntime {
    /// Starts one core worker.
    #[must_use]
    pub fn new(core: AppCore) -> Self {
        let (request_tx, request_rx) = mpsc::channel();
        let (response_tx, response_rx) = mpsc::channel();
        let cancelled = Arc::new(Mutex::new(BTreeSet::new()));
        let shutdown_flag = Arc::new(AtomicBool::new(false));
        let worker_cancelled = Arc::clone(&cancelled);
        let worker_shutdown = Arc::clone(&shutdown_flag);
        let worker = thread::Builder::new()
            .name("covio-core-worker".to_owned())
            .spawn(move || {
                worker_loop(
                    core,
                    request_rx,
                    response_tx,
                    worker_cancelled,
                    worker_shutdown,
                );
            })
            .expect("core worker thread should start");
        Self {
            request_tx,
            response_rx,
            cancelled,
            shutdown_flag,
            pending: BTreeSet::new(),
            next_request_id: 1,
            stopped: false,
            worker: Some(worker),
        }
    }

    /// Submits one application command.
    pub fn request(
        &mut self,
        command: &str,
        payload: Value,
        now_epoch_seconds: i64,
    ) -> Result<u64, String> {
        self.submit(command, payload, now_epoch_seconds, Duration::ZERO)
    }

    /// Submits the standard host snapshot command.
    pub fn request_snapshot(&mut self, now_epoch_seconds: i64) -> Result<u64, String> {
        self.request("host.snapshot", json!({}), now_epoch_seconds)
    }

    /// Cancels a request that has not yet delivered a response.
    pub fn cancel(&mut self, request_id: u64) -> bool {
        if !self.pending.remove(&request_id) {
            return false;
        }
        self.cancelled
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(request_id);
        true
    }

    /// Receives one non-blocking response.
    pub fn try_response(&mut self) -> Option<CoreResponse> {
        loop {
            match self.response_rx.try_recv() {
                Ok(response) => {
                    if self.pending.remove(&response.request_id) {
                        return Some(response);
                    }
                }
                Err(TryRecvError::Empty | TryRecvError::Disconnected) => return None,
            }
        }
    }

    /// Waits for one response until the timeout expires.
    pub fn wait_for_response(
        &mut self,
        request_id: u64,
        timeout: Duration,
    ) -> Option<CoreResponse> {
        let deadline = Instant::now() + timeout;
        loop {
            if let Some(response) = self.try_response() {
                if response.request_id == request_id {
                    return Some(response);
                }
            }
            if Instant::now() >= deadline {
                return None;
            }
            thread::sleep(Duration::from_millis(5));
        }
    }

    /// Returns whether the runtime has begun shutdown.
    #[must_use]
    pub fn is_shutting_down(&self) -> bool {
        self.stopped || self.shutdown_flag.load(Ordering::Acquire)
    }

    /// Requests worker shutdown and joins the worker thread.
    pub fn shutdown(&mut self) {
        if self.stopped {
            return;
        }
        self.stopped = true;
        self.shutdown_flag.store(true, Ordering::Release);
        let mut cancelled = self
            .cancelled
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for request_id in std::mem::take(&mut self.pending) {
            cancelled.insert(request_id);
        }
        drop(cancelled);
        let _ = self.request_tx.send(WorkerMessage::Shutdown);
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }

    fn submit(
        &mut self,
        command: &str,
        payload: Value,
        now_epoch_seconds: i64,
        delay: Duration,
    ) -> Result<u64, String> {
        if self.is_shutting_down() {
            return Err(CoreRuntimeError::ShuttingDown.to_string());
        }
        let request_id = self.next_request_id;
        self.next_request_id = self.next_request_id.saturating_add(1);
        self.pending.insert(request_id);
        self.request_tx
            .send(WorkerMessage::Execute {
                request_id,
                command: command.to_owned(),
                payload,
                now_epoch_seconds,
                delay,
            })
            .map_err(|_| CoreRuntimeError::WorkerUnavailable.to_string())?;
        Ok(request_id)
    }

    #[cfg(test)]
    fn request_with_delay(
        &mut self,
        command: &str,
        payload: Value,
        now_epoch_seconds: i64,
        delay: Duration,
    ) -> Result<u64, String> {
        self.submit(command, payload, now_epoch_seconds, delay)
    }
}

impl Drop for CoreRuntime {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn worker_loop(
    core: AppCore,
    request_rx: Receiver<WorkerMessage>,
    response_tx: Sender<CoreResponse>,
    cancelled: Arc<Mutex<BTreeSet<u64>>>,
    shutdown_flag: Arc<AtomicBool>,
) {
    while let Ok(message) = request_rx.recv() {
        if shutdown_flag.load(Ordering::Acquire) {
            break;
        }
        let WorkerMessage::Execute {
            request_id,
            command,
            payload,
            now_epoch_seconds,
            delay,
        } = message
        else {
            break;
        };
        if !delay.is_zero() {
            thread::sleep(delay);
        }
        if take_cancelled(&cancelled, request_id) || shutdown_flag.load(Ordering::Acquire) {
            continue;
        }
        let response = execute_request(&core, request_id, &command, &payload, now_epoch_seconds);
        if take_cancelled(&cancelled, request_id) || shutdown_flag.load(Ordering::Acquire) {
            continue;
        }
        if response_tx.send(response).is_err() {
            break;
        }
    }
}

fn execute_request(
    core: &AppCore,
    request_id: u64,
    command: &str,
    payload: &Value,
    now_epoch_seconds: i64,
) -> CoreResponse {
    let result = if command == "host.snapshot" {
        build_snapshot(core, now_epoch_seconds)
    } else {
        core.call(command, payload, now_epoch_seconds)
            .map_err(|message| HostCoreError::new("core_request_failed", message))
    };
    match result {
        Ok(result) => CoreResponse {
            request_id,
            command: command.to_owned(),
            ok: true,
            result,
            error: None,
        },
        Err(error) => CoreResponse {
            request_id,
            command: command.to_owned(),
            ok: false,
            result: json!({}),
            error: Some(error),
        },
    }
}

fn build_snapshot(core: &AppCore, now_epoch_seconds: i64) -> Result<Value, HostCoreError> {
    let config = core
        .call("config.load", &json!({}), now_epoch_seconds)
        .map_err(|message| HostCoreError::new("config_load_failed", message))?;
    let shelf = core
        .call("shelf.load", &json!({}), now_epoch_seconds)
        .map_err(|message| HostCoreError::new("shelf_load_failed", message))?;
    let clipboard = core
        .call("clipboard.load", &json!({}), now_epoch_seconds)
        .map_err(|message| HostCoreError::new("clipboard_load_failed", message))?;
    let workspace = core
        .call("workspace.load", &json!({}), now_epoch_seconds)
        .map_err(|message| HostCoreError::new("workspace_load_failed", message))?;
    Ok(json!({
        "config": config.get("config").cloned().unwrap_or(Value::Null),
        "shelfItemCount": nested_array_len(&shelf, &["state", "items"]),
        "clipboardItemCount": nested_array_len(&clipboard, &["state", "items"]),
        "workspaceEntryCount": nested_array_len(&workspace, &["state", "entries"]),
        "shelf": shelf.get("state").cloned().unwrap_or_else(|| json!(ShelfStoreState::default())),
        "clipboard": clipboard.get("state").cloned().unwrap_or_else(|| json!(ClipboardState::default())),
        "workspace": workspace.get("state").cloned().unwrap_or_else(|| json!(WorkspaceState::default())),
        "loadedAtEpochSeconds": now_epoch_seconds,
    }))
}

fn nested_array_len(value: &Value, path: &[&str]) -> usize {
    let mut current = value;
    for part in path {
        let Some(next) = current.get(*part) else {
            return 0;
        };
        current = next;
    }
    current.as_array().map_or(0, Vec::len)
}

fn take_cancelled(cancelled: &Mutex<BTreeSet<u64>>, request_id: u64) -> bool {
    cancelled
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .remove(&request_id)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::WindowsDataPaths;
    use covio_core::AppConfig;
    use std::path::PathBuf;
    use std::time::UNIX_EPOCH;

    fn temp_root() -> PathBuf {
        let nonce = std::time::SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        std::env::temp_dir().join(format!(
            "covio-windows-core-test-{}-{nonce}",
            std::process::id()
        ))
    }

    fn runtime_at(root: &std::path::Path) -> CoreRuntime {
        CoreRuntime::new(WindowsDataPaths::new(root).app_core())
    }

    #[test]
    fn snapshot_loads_all_core_state() {
        let root = temp_root();
        let mut runtime = runtime_at(&root);
        let request_id = runtime.request_snapshot(42).expect("submit snapshot");
        let response = runtime
            .wait_for_response(request_id, Duration::from_secs(2))
            .expect("snapshot response");
        assert!(response.ok, "{response:?}");
        let snapshot = HostSnapshot::from_value(&response.result).expect("snapshot");
        assert_eq!(snapshot.shelf_item_count, 0);
        assert_eq!(snapshot.clipboard_item_count, 0);
        assert_eq!(snapshot.workspace_entry_count, 0);
        assert!(snapshot.shelf.items.is_empty());
        assert!(snapshot.clipboard.items.is_empty());
        assert!(snapshot.workspace.entries.is_empty());
        assert_eq!(snapshot.loaded_at_epoch_seconds, 42);
        runtime.shutdown();
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn configuration_survives_worker_restart() {
        let root = temp_root();
        let mut runtime = runtime_at(&root);
        let id = runtime.request_snapshot(1).expect("snapshot request");
        let response = runtime
            .wait_for_response(id, Duration::from_secs(2))
            .expect("snapshot response");
        let snapshot = HostSnapshot::from_value(&response.result).expect("snapshot");
        let mut config = AppConfig::from_json_value(&snapshot.config);
        config.launch_at_login = true;
        let save_id = runtime
            .request("config.save", json!({"config": config}), 2)
            .expect("save request");
        let saved = runtime
            .wait_for_response(save_id, Duration::from_secs(2))
            .expect("save response");
        assert!(saved.ok, "{saved:?}");
        runtime.shutdown();

        let mut restarted = runtime_at(&root);
        let reload_id = restarted.request_snapshot(3).expect("reload request");
        let reloaded = restarted
            .wait_for_response(reload_id, Duration::from_secs(2))
            .expect("reload response");
        let snapshot = HostSnapshot::from_value(&reloaded.result).expect("reload snapshot");
        let config = AppConfig::from_json_value(&snapshot.config);
        assert!(config.launch_at_login);
        restarted.shutdown();
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn cancelled_request_does_not_deliver_a_response() {
        let root = temp_root();
        let mut runtime = runtime_at(&root);
        let request_id = runtime
            .request_with_delay("config.load", json!({}), 1, Duration::from_millis(120))
            .expect("delayed request");
        assert!(runtime.cancel(request_id));
        thread::sleep(Duration::from_millis(180));
        assert!(runtime.try_response().is_none());
        runtime.shutdown();
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn shutdown_rejects_later_requests() {
        let root = temp_root();
        let mut runtime = runtime_at(&root);
        runtime.shutdown();
        assert_eq!(
            runtime.request("config.load", json!({}), 1),
            Err(CoreRuntimeError::ShuttingDown.to_string())
        );
        let _ = std::fs::remove_dir_all(root);
    }
}

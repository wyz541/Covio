//! JSON application service facade used by the macOS Swift host.
//!
//! The facade composes existing Rust stores. It does not implement UI or OS
//! capability behavior.

use covio_core::charge_limit::{
    ChargeLimitObservation, ChargeLimitPolicyState, evaluate as evaluate_charge_limit,
    is_valid_upper_limit, normalize_upper_limit, resume_threshold,
};
use covio_core::clipboard::{
    ClipItem, ClipPolicy, ClipboardState, ClipboardStore, classify, next_paste, prune,
    push_paste_stack,
};
use covio_core::path_policy::canonical_path;
use covio_core::power::helper_release::{HelperReleaseHandshake, HelperReleaseIdentity};
use covio_core::power::helper_wire::{
    ALLOWED_COMMANDS, COMMAND_SET_DISABLE_SLEEP, COMMAND_SET_HIBERNATE_MODE, HelperReply,
    HelperRequest, disable_sleep_arguments, encode_reply, encode_request, failure, pmset_arguments,
    pmset_reply, success, validate,
};
use covio_core::screenshot_preferences::{
    delete_is_success, parse_boolean, parse_string, write_argument,
};
use covio_core::shelf::{ShelfItem, ShelfStore, ShelfStoreState, normalize_items};
use covio_core::workspace::{WorkspaceState, WorkspaceStore};
use covio_core::{
    AppConfig, ConfigStore, DesignContractReader, is_newer_version, is_stable_version,
    select_update, should_check,
};
use covio_platform::{DataPaths, StdFileStore};
use serde::de::DeserializeOwned;
use serde_json::{Value, json};
use std::path::Path;

/// Application service handle for one data root.
#[derive(Debug, Clone)]
pub struct AppCore {
    config_file: std::path::PathBuf,
    shelf_file: std::path::PathBuf,
    clipboard_file: std::path::PathBuf,
    workspace_directory: std::path::PathBuf,
    files: StdFileStore,
}

impl AppCore {
    /// Creates an application service handle.
    #[must_use]
    pub fn new(application_support_root: impl AsRef<Path>) -> Self {
        let paths = DataPaths::apple(application_support_root.as_ref());
        let clipboard_file = paths.clipboard_file();
        Self::with_paths(
            paths.config_file,
            paths.shelf_file,
            clipboard_file,
            paths.workspace_directory,
        )
    }

    /// Creates a service handle with explicit compatibility paths.
    #[must_use]
    pub fn with_paths(
        config_file: impl Into<std::path::PathBuf>,
        shelf_file: impl Into<std::path::PathBuf>,
        clipboard_file: impl Into<std::path::PathBuf>,
        workspace_directory: impl Into<std::path::PathBuf>,
    ) -> Self {
        Self {
            config_file: config_file.into(),
            shelf_file: shelf_file.into(),
            clipboard_file: clipboard_file.into(),
            workspace_directory: workspace_directory.into(),
            files: StdFileStore::new(),
        }
    }

    /// Executes one bounded application command and returns JSON data.
    pub fn call(
        &self,
        command: &str,
        payload: &Value,
        now_epoch_seconds: i64,
    ) -> Result<Value, String> {
        match command {
            "config.load" => {
                let loaded = ConfigStore::new(self.config_file.clone(), self.files).load();
                Ok(json!({"config": loaded.config}))
            }
            "config.save" => {
                let config = payload
                    .get("config")
                    .or_else(|| payload.get("value"))
                    .map(AppConfig::from_json_value)
                    .unwrap_or_default();
                let saved = ConfigStore::new(self.config_file.clone(), self.files)
                    .save(&config)
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"config": saved}))
            }
            "config.normalize" => {
                let config = payload
                    .get("config")
                    .or_else(|| payload.get("value"))
                    .map(AppConfig::from_json_value)
                    .unwrap_or_default();
                Ok(json!({"config": config.normalized()}))
            }
            "config.clear" => {
                let removed = ConfigStore::new(self.config_file.clone(), self.files)
                    .clear()
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"removed": removed}))
            }
            "screenshotPreference.parseString" => {
                let exit_code = i32::try_from(integer_field(payload, "exitCode")?)
                    .map_err(|_| "exitCode is outside the supported range".to_owned())?;
                Ok(json!({
                    "value": parse_string(exit_code, string_field(payload, "output")?)
                        .map(Value::String)
                        .unwrap_or(Value::Null)
                }))
            }
            "screenshotPreference.parseBoolean" => {
                let exit_code = i32::try_from(integer_field(payload, "exitCode")?)
                    .map_err(|_| "exitCode is outside the supported range".to_owned())?;
                Ok(json!({
                    "value": parse_boolean(exit_code, string_field(payload, "output")?)
                        .map(Value::Bool)
                        .unwrap_or(Value::Null)
                }))
            }
            "screenshotPreference.writeArgument" => Ok(json!({
                "value": write_argument(
                    string_field(payload, "value")?,
                    boolean_field(payload, "isString")?,
                )
            })),
            "screenshotPreference.deleteIsSuccess" => {
                let exit_code = i32::try_from(integer_field(payload, "exitCode")?)
                    .map_err(|_| "exitCode is outside the supported range".to_owned())?;
                Ok(json!({
                    "result": delete_is_success(exit_code, string_field(payload, "output")?)
                }))
            }
            "shelf.acceptsFile" => Ok(json!({
                "result": covio_core::path_policy::accepts_shelf_file(
                    string_field(payload, "path")?,
                    string_field(payload, "dedicatedDirectory")?,
                    |_| boolean_field(payload, "hasScreenCaptureAttribute").unwrap_or(false),
                )
            })),
            "shelf.load" => {
                let state = ShelfStore::new(self.shelf_file.clone(), self.files).load();
                Ok(json!({"state": state}))
            }
            "shelf.save" => {
                let state: ShelfStoreState = decode_field(payload, "state")?;
                let saved = ShelfStore::new(self.shelf_file.clone(), self.files)
                    .save(&state)
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"state": saved}))
            }
            "shelf.clear" => {
                let removed = ShelfStore::new(self.shelf_file.clone(), self.files)
                    .clear()
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"removed": removed}))
            }
            "shelf.canonicalPath" => Ok(json!({
                "value": canonical_path(string_field(payload, "value")?)
            })),
            "shelf.normalizeItems" => {
                let items: Vec<ShelfItem> = decode_field(payload, "items")?;
                let existing: Vec<String> = decode_field(payload, "existingPaths")?;
                let existing: std::collections::HashSet<_> = existing
                    .into_iter()
                    .map(|path| canonical_path(&path))
                    .collect();
                let limit = payload
                    .get("limit")
                    .and_then(Value::as_u64)
                    .unwrap_or(covio_core::shelf::MAX_SHELF_ITEMS as u64)
                    as usize;
                Ok(json!({
                    "items": normalize_items(items, limit, |path| existing.contains(&canonical_path(path)))
                }))
            }
            "clipboard.classify" => Ok(json!({
                "kind": classify(string_field(payload, "text")?)
            })),
            "clipboard.prune" => {
                let items: Vec<ClipItem> = decode_field(payload, "items")?;
                let policy: ClipPolicy = decode_field(payload, "policy")?;
                let existing: Vec<String> = decode_field(payload, "existingPaths")?;
                let existing: std::collections::HashSet<_> = existing
                    .into_iter()
                    .map(|path| canonical_path(&path))
                    .collect();
                Ok(json!({
                    "items": prune(
                        &items,
                        &policy,
                        now_epoch_seconds,
                        |path| existing.contains(&canonical_path(path)),
                    )
                }))
            }
            "clipboard.nextPaste" => {
                let state: ClipboardState = decode_field(payload, "state")?;
                let (state, item) = next_paste(&state);
                Ok(json!({"state": state, "item": item}))
            }
            "clipboard.pushPaste" => {
                let stack: Vec<String> = decode_field(payload, "stack")?;
                Ok(json!({
                    "stack": push_paste_stack(&stack, string_field(payload, "id")?)
                }))
            }
            "clipboard.load" => {
                let state = ClipboardStore::new(self.clipboard_file.clone(), self.files).load();
                Ok(json!({"state": state}))
            }
            "clipboard.save" => {
                let state: ClipboardState = decode_field(payload, "state")?;
                let saved = ClipboardStore::new(self.clipboard_file.clone(), self.files)
                    .save(&state)
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"state": saved}))
            }
            "clipboard.clear" => {
                let removed = ClipboardStore::new(self.clipboard_file.clone(), self.files)
                    .clear()
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"removed": removed}))
            }
            "workspace.load" => {
                let state =
                    WorkspaceStore::new(self.workspace_directory.clone(), self.files).load();
                Ok(json!({"state": state}))
            }
            "workspace.save" => {
                let state: WorkspaceState = decode_field(payload, "state")?;
                let saved = WorkspaceStore::new(self.workspace_directory.clone(), self.files)
                    .save(&state)
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"state": saved}))
            }
            "workspace.loadTombstones" => {
                let tombstones = WorkspaceStore::new(self.workspace_directory.clone(), self.files)
                    .load_tombstones();
                Ok(json!({"tombstones": tombstones}))
            }
            "workspace.putFile" => {
                let state: WorkspaceState = decode_field(payload, "state")?;
                let result = WorkspaceStore::new(self.workspace_directory.clone(), self.files)
                    .put_file(
                        &state,
                        string_field(payload, "sourcePath")?,
                        string_field(payload, "displayName")?,
                        string_field(payload, "contentType")?,
                        string_field(payload, "originDeviceId")?,
                        now_epoch_seconds,
                    );
                Ok(json!(result))
            }
            "workspace.putText" => {
                let state: WorkspaceState = decode_field(payload, "state")?;
                let result = WorkspaceStore::new(self.workspace_directory.clone(), self.files)
                    .put_text(
                        &state,
                        string_field(payload, "text")?,
                        string_field(payload, "displayName")?,
                        string_field(payload, "contentType")?,
                        string_field(payload, "originDeviceId")?,
                        now_epoch_seconds,
                    );
                Ok(json!(result))
            }
            "workspace.setPinned" => {
                let state: WorkspaceState = decode_field(payload, "state")?;
                let pinned = payload
                    .get("pinned")
                    .and_then(Value::as_bool)
                    .ok_or_else(|| "pinned must be a bool".to_owned())?;
                let next = WorkspaceStore::new(self.workspace_directory.clone(), self.files)
                    .set_pinned(&state, string_field(payload, "entryId")?, pinned)
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"state": next}))
            }
            "workspace.remove" => {
                let state: WorkspaceState = decode_field(payload, "state")?;
                let next = WorkspaceStore::new(self.workspace_directory.clone(), self.files)
                    .remove(&state, string_field(payload, "entryId")?, now_epoch_seconds)
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"state": next}))
            }
            "workspace.sweep" => {
                let policy: covio_core::workspace::WorkspacePolicy =
                    decode_field(payload, "policy")?;
                let plan = WorkspaceStore::new(self.workspace_directory.clone(), self.files)
                    .sweep(&policy, now_epoch_seconds)
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"plan": plan}))
            }
            "workspace.contentPath" => {
                let store = WorkspaceStore::new(self.workspace_directory.clone(), self.files);
                let entry_id = string_field(payload, "entryId")?;
                let path = if store.has_content(entry_id) {
                    store
                        .content_path(entry_id)
                        .map(|path| path.to_string_lossy().into_owned())
                } else {
                    None
                };
                Ok(json!({"path": path}))
            }
            "workspace.displayOrder" => {
                let entries: Vec<covio_core::workspace::WorkspaceEntry> =
                    decode_field(payload, "entries")?;
                Ok(json!({"entries": covio_core::workspace::display_order(&entries)}))
            }
            "workspace.localBytes" => {
                let entries: Vec<covio_core::workspace::WorkspaceEntry> =
                    decode_field(payload, "entries")?;
                Ok(json!({"bytes": covio_core::workspace::total_local_bytes(&entries)}))
            }
            "workspace.setAvailability" => {
                let state: WorkspaceState = decode_field(payload, "state")?;
                let entry_id = string_field(payload, "entryId")?;
                let availability: covio_core::workspace::WorkspaceAvailability =
                    decode_field(payload, "availability")?;
                let entries = state
                    .entries
                    .iter()
                    .map(|entry| {
                        if entry.entry_id == entry_id {
                            covio_core::workspace::WorkspaceEntry {
                                availability,
                                ..entry.clone()
                            }
                        } else {
                            entry.clone()
                        }
                    })
                    .collect();
                let next = WorkspaceStore::new(self.workspace_directory.clone(), self.files)
                    .save(&WorkspaceState { entries, ..state })
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"state": next}))
            }
            "workspace.clearOrphanedFetching" => {
                let state: WorkspaceState = decode_field(payload, "state")?;
                let active: Vec<String> = decode_field(payload, "activeEntryIds")?;
                let active: std::collections::HashSet<_> = active.into_iter().collect();
                let mut changed = false;
                let entries = state
                    .entries
                    .iter()
                    .map(|entry| {
                        if entry.availability
                            == covio_core::workspace::WorkspaceAvailability::Fetching
                            && !active.contains(&entry.entry_id)
                        {
                            changed = true;
                            covio_core::workspace::WorkspaceEntry {
                                availability: covio_core::workspace::WorkspaceAvailability::Remote,
                                ..entry.clone()
                            }
                        } else {
                            entry.clone()
                        }
                    })
                    .collect();
                let next = if changed {
                    WorkspaceStore::new(self.workspace_directory.clone(), self.files)
                        .save(&WorkspaceState { entries, ..state })
                        .map_err(|error| error.message().to_owned())?
                } else {
                    state
                };
                Ok(json!({"state": next}))
            }
            "workspace.verifyContent" => Ok(json!({
                "valid": WorkspaceStore::new(self.workspace_directory.clone(), self.files)
                    .verify_content(string_field(payload, "entryId")?)
            })),
            "workspace.clear" => {
                let removed = WorkspaceStore::new(self.workspace_directory.clone(), self.files)
                    .clear()
                    .map_err(|error| error.message().to_owned())?;
                Ok(json!({"removed": removed}))
            }
            "version.parse" => {
                let value = string_field(payload, "value")?;
                Ok(json!({"version": covio_core::SemanticVersion::parse(value)}))
            }
            "version.isStable" => Ok(json!({
                "result": is_stable_version(string_field(payload, "value")?)
            })),
            "version.isNewer" => Ok(json!({
                "result": is_newer_version(
                    string_field(payload, "candidate")?,
                    string_field(payload, "current")?
                )
            })),
            "update.shouldCheck" => {
                let config = payload
                    .get("config")
                    .map(AppConfig::from_json_value)
                    .unwrap_or_default();
                Ok(json!({"result": should_check(&config, now_epoch_seconds)}))
            }
            "update.select" => {
                let candidate = payload
                    .get("candidate")
                    .filter(|value| !value.is_null())
                    .cloned()
                    .map(serde_json::from_value::<covio_core::UpdateInfo>)
                    .transpose()
                    .map_err(|_| "candidate is invalid".to_owned())?;
                Ok(json!({
                    "result": select_update(
                        candidate.as_ref(),
                        string_field(payload, "currentVersion")?
                    )
                }))
            }
            "helper.release.parse" => {
                let result: std::collections::BTreeMap<String, String> =
                    decode_field(payload, "result")?;
                Ok(json!({"identity": HelperReleaseHandshake::parse(&result)}))
            }
            "helper.release.hasIdentityFields" => {
                let result: std::collections::BTreeMap<String, String> =
                    decode_field(payload, "result")?;
                Ok(json!({"result": HelperReleaseHandshake::has_identity_fields(&result)}))
            }
            "helper.release.classify" => {
                let expected: HelperReleaseIdentity = decode_field(payload, "expected")?;
                let observed: HelperReleaseIdentity = decode_field(payload, "observed")?;
                let trusted = payload
                    .get("signatureTrusted")
                    .and_then(Value::as_bool)
                    .ok_or_else(|| "signatureTrusted must be a bool".to_owned())?;
                Ok(json!({
                    "status": HelperReleaseHandshake::classify(&expected, &observed, trusted)
                }))
            }
            "helper.decodeRequest" => Ok(json!({
                "request": covio_core::power::helper_wire::decode_request(
                    string_field(payload, "line")?
                )
            })),
            "helper.reencodeRequest" => {
                let line = string_field(payload, "line")?;
                let request = covio_core::power::helper_wire::decode_request(line)
                    .ok_or_else(|| "request is invalid".to_owned())?;
                Ok(json!({
                    "line": encode_request(&request)
                        .map_err(|_| "request encoding failed".to_owned())?
                }))
            }
            "helper.encodeRequest" => {
                let request: HelperRequest = decode_field(payload, "request")?;
                Ok(
                    json!({"line": encode_request(&request).map_err(|_| "request encoding failed".to_owned())?}),
                )
            }
            "helper.decodeReply" => Ok(json!({
                "reply": covio_core::power::helper_wire::decode_reply(
                    string_field(payload, "line")?
                )
            })),
            "helper.encodeReply" => {
                let reply: HelperReply = decode_field(payload, "reply")?;
                Ok(
                    json!({"line": encode_reply(&reply).map_err(|_| "reply encoding failed".to_owned())?}),
                )
            }
            "helper.validate" => {
                let request: HelperRequest = decode_field(payload, "request")?;
                Ok(json!({"error": validate(&request)}))
            }
            "helper.pmsetArguments" => {
                let request: HelperRequest = decode_field(payload, "request")?;
                Ok(json!({"arguments": pmset_arguments(&request)}))
            }
            "helper.disableSleepArguments" => {
                let disabled = payload
                    .get("disabled")
                    .and_then(Value::as_bool)
                    .ok_or_else(|| "disabled must be a bool".to_owned())?;
                Ok(json!({"arguments": disable_sleep_arguments(disabled)}))
            }
            "helper.success" => {
                let result = payload.get("result").and_then(Value::as_object).cloned();
                Ok(json!({"reply": success(string_field(payload, "requestId")?, result)}))
            }
            "helper.versionReply" => {
                let reply = covio_core::power::helper_wire::version_reply(
                    string_field(payload, "requestId")?,
                    string_field(payload, "appVersion")?,
                );
                Ok(json!({
                    "reply": reply,
                    "line": encode_reply(&reply)
                        .map_err(|_| "reply encoding failed".to_owned())?
                }))
            }
            "helper.failure" => Ok(json!({
                "reply": failure(
                    string_field(payload, "requestId")?,
                    string_field(payload, "message")?
                )
            })),
            "helper.pmsetReply" => {
                let exit_code = payload
                    .get("exitCode")
                    .and_then(Value::as_i64)
                    .ok_or_else(|| "exitCode must be an integer".to_owned())?;
                Ok(json!({
                    "reply": pmset_reply(
                        string_field(payload, "requestId")?,
                        i32::try_from(exit_code).map_err(|_| "exitCode is out of range".to_owned())?,
                        string_field(payload, "output")?
                    )
                }))
            }
            "helper.constants" => Ok(json!({
                "helperArgument": "--helper",
                "helperExecutableName": "CovioHelper",
                "helperExecutableBundlePath": "Contents/MacOS/CovioHelper",
                "daemonPlistName": "com.wyz.covio.helper.plist",
                "xpcServiceName": "com.wyz.covio.helper.xpc",
                "socketPath": "/Library/Application Support/Covio/helper.sock",
                "helperDirectory": "/Library/Application Support/Covio",
                "binaryDirectory": "/Library/Application Support/Covio/bin",
                "helperBinaryPath": "/Library/Application Support/Covio/bin/CovioHelper",
                "chargeLimitDirectory": "/Library/Application Support/Covio/charge-limit",
                "chargeLimitStatePath": "/Library/Application Support/Covio/charge-limit/state.json",
                "chargeLimitRuntimePath": "/Library/Application Support/Covio/charge-limit/runtime.json",
                "allowedUidPath": "/Library/Application Support/Covio/allowed_uid",
                "clientRequirementPath": "/Library/Application Support/Covio/client-requirement",
                "versionPath": "/Library/Application Support/Covio/version",
                "appPathFile": "/Library/Application Support/Covio/Covio.app",
                "sleepOwnerPath": "/Library/Application Support/Covio/sleep_owner",
                "sleepOwnerValue": "covio-sleep-disabled-v2",
                "logPath": "/Library/Application Support/Covio/helper.log",
                "plistPath": "/Library/LaunchDaemons/com.wyz.covio.helper.plist",
                "launchDaemonLabel": "com.wyz.covio.helper",
                "protocolVersion": covio_core::power::helper_wire::HELPER_PROTOCOL_VERSION,
                "maxRequestBytes": covio_core::power::helper_wire::MAX_REQUEST_BYTES,
                "maxReplyBytes": covio_core::power::helper_wire::MAX_REPLY_BYTES,
                "socketPermissions": covio_core::power::helper_wire::SOCKET_PERMISSIONS,
                "leaseIdMaxLength": covio_core::power::helper_wire::HELPER_LEASE_ID_MAX_LENGTH,
                "leaseMaxActive": covio_core::power::helper_wire::HELPER_LEASE_MAX_ACTIVE,
                "leaseDurationSeconds": covio_core::power::helper_wire::HELPER_LEASE_DURATION_SECONDS,
                "leaseRenewSeconds": covio_core::power::helper_wire::HELPER_LEASE_RENEW_SECONDS,
                "allowedCommands": ALLOWED_COMMANDS,
                "commands": {
                    "version": covio_core::power::helper_wire::COMMAND_VERSION,
                    "setDisableSleep": COMMAND_SET_DISABLE_SLEEP,
                    "setHibernateMode": COMMAND_SET_HIBERNATE_MODE,
                    "lidLeaseAcquire": covio_core::power::helper_wire::COMMAND_LID_LEASE_ACQUIRE,
                    "lidLeaseRenew": covio_core::power::helper_wire::COMMAND_LID_LEASE_RENEW,
                    "lidLeaseRelease": covio_core::power::helper_wire::COMMAND_LID_LEASE_RELEASE,
                    "lidLeaseStatus": covio_core::power::helper_wire::COMMAND_LID_LEASE_STATUS,
                    "chargeLimitStatus": covio_core::power::helper_wire::COMMAND_CHARGE_LIMIT_STATUS,
                    "chargeLimitConfigure": covio_core::power::helper_wire::COMMAND_CHARGE_LIMIT_CONFIGURE,
                    "chargeLimitRestore": covio_core::power::helper_wire::COMMAND_CHARGE_LIMIT_RESTORE,
                    "fanControlStatus": covio_core::power::helper_wire::COMMAND_FAN_CONTROL_STATUS,
                    "fanControlConfigure": covio_core::power::helper_wire::COMMAND_FAN_CONTROL_CONFIGURE,
                    "fanControlKeepAlive": covio_core::power::helper_wire::COMMAND_FAN_CONTROL_KEEP_ALIVE,
                    "fanControlRestore": covio_core::power::helper_wire::COMMAND_FAN_CONTROL_RESTORE,
                    "prepareInstallTransaction": covio_core::power::helper_wire::COMMAND_PREPARE_INSTALL_TRANSACTION,
                }
            })),
            "chargeLimit.isValidUpperLimit" => {
                let percent = payload
                    .get("percent")
                    .and_then(Value::as_i64)
                    .ok_or_else(|| "percent must be an integer".to_owned())?;
                Ok(json!({"result": is_valid_upper_limit(percent as i32)}))
            }
            "chargeLimit.normalizeUpperLimit" => {
                let percent = payload
                    .get("percent")
                    .and_then(Value::as_i64)
                    .ok_or_else(|| "percent must be an integer".to_owned())?;
                Ok(json!({"percent": normalize_upper_limit(percent as i32)}))
            }
            "chargeLimit.resumeThreshold" => {
                let percent = payload
                    .get("upperLimitPercent")
                    .and_then(Value::as_i64)
                    .ok_or_else(|| "upperLimitPercent must be an integer".to_owned())?;
                Ok(json!({"percent": resume_threshold(percent as i32)}))
            }
            "chargeLimit.evaluate" => {
                let observation: ChargeLimitObservation = decode_field(payload, "observation")?;
                let previous: ChargeLimitPolicyState =
                    decode_field(payload, "previous").unwrap_or_default();
                Ok(json!({
                    "decision": evaluate_charge_limit(&observation, previous)
                }))
            }
            "power.decide" => {
                let config: covio_core::PowerConfig = decode_field(payload, "config")?;
                let snapshot: covio_core::power::PowerSnapshot = decode_field(payload, "snapshot")?;
                let leases: Vec<covio_core::power::HoldLease> = decode_field(payload, "leases")?;
                let now = payload
                    .get("nowEpochSeconds")
                    .and_then(Value::as_i64)
                    .unwrap_or(now_epoch_seconds);
                let paused = boolean_field(payload, "paused")?;
                let battery_guard_latched = boolean_field(payload, "batteryGuardLatched")?;
                Ok(json!({
                    "decision": covio_core::power::decide(
                        &config,
                        &snapshot,
                        &leases,
                        now,
                        paused,
                        battery_guard_latched,
                    )
                }))
            }
            "pmset.config.sleepTimeoutSeconds" => Ok(json!({
                "seconds": covio_core::power::PmsetConfigParser::sleep_timeout_seconds(
                    payload.get("text").and_then(Value::as_str)
                )
            })),
            "pmset.config.hibernateMode" => Ok(json!({
                "mode": covio_core::power::PmsetConfigParser::hibernate_mode(
                    payload.get("text").and_then(Value::as_str)
                )
            })),
            "pmset.config.sleepDisabled" => Ok(json!({
                "disabled": covio_core::power::PmsetConfigParser::sleep_disabled(
                    payload.get("text").and_then(Value::as_str)
                )
            })),
            "pmset.wake.parse" => Ok(json!({
                "snapshot": covio_core::power::PmsetWakeLogParser::parse(
                    string_field(payload, "text")?,
                    now_epoch_seconds,
                )
            })),
            "pmset.wake.parseTimestamp" => Ok(json!({
                "seconds": covio_core::power::PmsetWakeLogParser::parse_timestamp(
                    string_field(payload, "value")?
                )
            })),
            "design.parse" => {
                let text = string_field(payload, "text")?;
                let result = DesignContractReader::parse(text);
                Ok(json!({
                    "contract": result.contract,
                    "diagnostics": result.diagnostics,
                    "isValid": result.is_valid(),
                }))
            }
            _ => Err(format!("unknown command: {command}")),
        }
    }
}

fn string_field<'a>(payload: &'a Value, key: &str) -> Result<&'a str, String> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("{key} must be a string"))
}

fn integer_field(payload: &Value, key: &str) -> Result<i64, String> {
    payload
        .get(key)
        .and_then(Value::as_i64)
        .ok_or_else(|| format!("{key} must be an integer"))
}

fn boolean_field(payload: &Value, key: &str) -> Result<bool, String> {
    payload
        .get(key)
        .and_then(Value::as_bool)
        .ok_or_else(|| format!("{key} must be a bool"))
}

fn decode_field<T: DeserializeOwned>(payload: &Value, key: &str) -> Result<T, String> {
    serde_json::from_value(
        payload
            .get(key)
            .cloned()
            .ok_or_else(|| format!("{key} is required"))?,
    )
    .map_err(|_| format!("{key} is invalid"))
}

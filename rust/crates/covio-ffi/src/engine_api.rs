//! C ABI application-service facade for the Rust power engine.

use super::{
    CovioError, CovioOwnedBytes, CovioStatusCode, FfiFailure, copy_input, copy_utf8, ffi_guard,
    owned_bytes,
};
use covio_core::AppConfig;
use covio_core::power::engine::{Engine, EngineDependencies};
use covio_core::power::models::{
    AppState, BatteryStatus, HelperStatus, IdleSleepAssertionResult, IdleSleepPrevention,
    LidLeaseStatus, LidState, SleepEvent, WakeLogSnapshot,
};
use covio_core::power::ports::{
    AppLogger, IdleSensor, LidSensor, PowerSource, PrivilegedOps, SleepController, StateListener,
    WakeLogReader,
};
use covio_platform::PlatformError;
use serde_json::{Value, json};
use std::ffi::c_void;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::slice;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

/// Synchronous platform capability callback.
pub type EngineCapabilityCallback =
    extern "C-unwind" fn(*mut c_void, *const u8, usize, *mut CovioError) -> CovioOwnedBytes;

struct CallbackBridge {
    callback: EngineCapabilityCallback,
    context: *mut c_void,
}

// The C handle contract is single-threaded. Rust Engine callbacks execute on the
// caller's thread and the pointer is not shared by this crate.
unsafe impl Send for CallbackBridge {}
unsafe impl Sync for CallbackBridge {}

impl CallbackBridge {
    fn call(&self, operation: &str, payload: Value) -> Result<Value, PlatformError> {
        let request = serde_json::to_vec(&json!({"op": operation, "payload": payload}))
            .map_err(|_| platform_error())?;
        let mut error = CovioError {
            code: CovioStatusCode::Ok as u32,
            message: CovioOwnedBytes::EMPTY,
        };
        let response = catch_unwind(AssertUnwindSafe(|| {
            (self.callback)(self.context, request.as_ptr(), request.len(), &mut error)
        }))
        .map_err(|_| platform_error())?;
        let response = unsafe { response.take_bytes() }.map_err(|_| platform_error())?;
        if error.code != 0 {
            unsafe { error.free_message() };
            return Err(platform_error());
        }
        unsafe { error.free_message() };
        let value: Value = serde_json::from_slice(&response).map_err(|_| platform_error())?;
        if value.get("ok").and_then(Value::as_bool) == Some(false) {
            return Err(platform_error());
        }
        Ok(value.get("data").cloned().unwrap_or(Value::Null))
    }

    fn log(&self, level: &str, message: &str) {
        let _ = self.call("log", json!({"level": level, "message": message}));
    }
}

#[derive(Clone)]
struct PowerPort {
    bridge: std::sync::Arc<CallbackBridge>,
}
impl PowerSource for PowerPort {
    fn read(&self) -> Result<Option<BatteryStatus>, PlatformError> {
        let value = self.bridge.call("power.read", json!({}))?;
        let battery = value.get("battery").cloned().unwrap_or(Value::Null);
        if battery.is_null() {
            Ok(None)
        } else {
            serde_json::from_value(battery)
                .map(Some)
                .map_err(|_| platform_error())
        }
    }
}

#[derive(Clone)]
struct LidPort {
    bridge: std::sync::Arc<CallbackBridge>,
}
impl LidSensor for LidPort {
    fn read(&self) -> Result<LidState, PlatformError> {
        let value = self.bridge.call("lid.read", json!({}))?;
        serde_json::from_value(value.get("state").cloned().unwrap_or(Value::Null))
            .map_err(|_| platform_error())
    }
}

#[derive(Clone)]
struct IdlePort {
    bridge: std::sync::Arc<CallbackBridge>,
}
impl IdleSensor for IdlePort {
    fn idle_seconds(&self) -> Result<i64, PlatformError> {
        let value = self.bridge.call("idle.seconds", json!({}))?;
        value
            .get("seconds")
            .and_then(Value::as_i64)
            .ok_or_else(platform_error)
    }
}

#[derive(Clone)]
struct SleepPort {
    bridge: std::sync::Arc<CallbackBridge>,
}
impl SleepController for SleepPort {
    fn sleep(&self) -> Result<(), PlatformError> {
        self.bridge.call("sleep.request", json!({})).map(|_| ())
    }
    fn display_sleep(&self) -> Result<(), PlatformError> {
        self.bridge
            .call("displaySleep.request", json!({}))
            .map(|_| ())
    }
    fn apply_idle_sleep_prevention(
        &self,
        prevention: IdleSleepPrevention,
    ) -> Result<IdleSleepAssertionResult, PlatformError> {
        let value = self
            .bridge
            .call("assertion.apply", json!({"prevention": prevention}))?;
        serde_json::from_value(value).map_err(|_| platform_error())
    }
    fn read_idle_sleep_prevention(&self) -> Result<IdleSleepPrevention, PlatformError> {
        let value = self.bridge.call("assertion.read", json!({}))?;
        serde_json::from_value(value.get("prevention").cloned().unwrap_or(Value::Null))
            .map_err(|_| platform_error())
    }
    fn system_idle_sleep_timeout_seconds(&self) -> Result<Option<i64>, PlatformError> {
        let value = self.bridge.call("assertion.timeout", json!({}))?;
        Ok(value.get("seconds").and_then(Value::as_i64))
    }
}

#[derive(Clone)]
struct PrivilegedPort {
    bridge: std::sync::Arc<CallbackBridge>,
}
impl PrivilegedOps for PrivilegedPort {
    fn is_installed(&self) -> Result<bool, PlatformError> {
        let value = self.bridge.call("privileged.isInstalled", json!({}))?;
        value
            .get("installed")
            .and_then(Value::as_bool)
            .ok_or_else(platform_error)
    }
    fn status(&self) -> Result<HelperStatus, PlatformError> {
        let value = self.bridge.call("privileged.status", json!({}))?;
        serde_json::from_value(value.get("status").cloned().unwrap_or(Value::Null))
            .map_err(|_| platform_error())
    }
    fn helper_version(&self) -> Result<Option<String>, PlatformError> {
        let value = self.bridge.call("privileged.helperVersion", json!({}))?;
        Ok(value
            .get("version")
            .and_then(Value::as_str)
            .map(str::to_owned))
    }
    fn install(&self) -> Result<bool, PlatformError> {
        let value = self.bridge.call("privileged.install", json!({}))?;
        value
            .get("result")
            .and_then(Value::as_bool)
            .ok_or_else(platform_error)
    }
    fn uninstall(&self) -> Result<bool, PlatformError> {
        let value = self.bridge.call("privileged.uninstall", json!({}))?;
        value
            .get("result")
            .and_then(Value::as_bool)
            .ok_or_else(platform_error)
    }
    fn set_disable_sleep(&self, disabled: bool) -> Result<bool, PlatformError> {
        let value = self
            .bridge
            .call("privileged.setDisableSleep", json!({"disabled": disabled}))?;
        value
            .get("result")
            .and_then(Value::as_bool)
            .ok_or_else(platform_error)
    }
    fn lid_lease_status(&self) -> Result<LidLeaseStatus, PlatformError> {
        let value = self.bridge.call("privileged.lidLeaseStatus", json!({}))?;
        serde_json::from_value(value.get("status").cloned().unwrap_or(Value::Null))
            .map_err(|_| platform_error())
    }
    fn hibernate_mode(&self) -> Result<Option<i32>, PlatformError> {
        let value = self.bridge.call("privileged.hibernateMode", json!({}))?;
        Ok(value
            .get("mode")
            .and_then(Value::as_i64)
            .and_then(|value| i32::try_from(value).ok()))
    }
    fn set_hibernate_mode(&self, mode: i32) -> Result<bool, PlatformError> {
        let value = self
            .bridge
            .call("privileged.setHibernateMode", json!({"mode": mode}))?;
        value
            .get("result")
            .and_then(Value::as_bool)
            .ok_or_else(platform_error)
    }
}

#[derive(Clone)]
struct WakePort {
    bridge: std::sync::Arc<CallbackBridge>,
}
impl WakeLogReader for WakePort {
    fn read(&self) -> Result<Option<WakeLogSnapshot>, PlatformError> {
        let value = self.bridge.call("wake.read", json!({}))?;
        let snapshot = value.get("snapshot").cloned().unwrap_or(Value::Null);
        if snapshot.is_null() {
            Ok(None)
        } else {
            serde_json::from_value(snapshot)
                .map(Some)
                .map_err(|_| platform_error())
        }
    }
}

#[derive(Clone)]
struct LoggerPort {
    bridge: std::sync::Arc<CallbackBridge>,
}
impl AppLogger for LoggerPort {
    fn info(&self, message: &str) {
        self.bridge.log("info", message);
    }
    fn warn(&self, message: &str) {
        self.bridge.log("warn", message);
    }
    fn error(&self, message: &str) {
        self.bridge.log("error", message);
    }
}

#[derive(Clone)]
struct ListenerPort {
    bridge: std::sync::Arc<CallbackBridge>,
}
impl StateListener for ListenerPort {
    fn on_state(&self, state: &AppState) {
        let _ = self.bridge.call("state.changed", json!(state));
    }
}

/// Opaque engine handle.
pub struct CovioEngineHandle {
    engine: Mutex<Engine>,
}

impl CovioEngineHandle {
    fn call(&self, command: &str, payload: &Value, now: i64) -> Result<Value, FfiFailure> {
        let mut engine = self
            .engine
            .lock()
            .map_err(|_| FfiFailure::new(CovioStatusCode::Internal, "engine lock is poisoned"))?;
        match command {
            "start" => {
                engine.start();
                Ok(json!({}))
            }
            "stop" => {
                engine.stop();
                Ok(json!({}))
            }
            "tick" => {
                let now_millis = payload
                    .get("nowMillis")
                    .and_then(Value::as_i64)
                    .unwrap_or_else(|| now.saturating_mul(1_000));
                engine.tick_at(now_millis);
                Ok(json!({}))
            }
            "currentState" => Ok(json!({"state": engine.current_state()})),
            "updateConfig" => {
                let config = payload
                    .get("config")
                    .cloned()
                    .ok_or_else(|| invalid("config is required"))?;
                let config = AppConfig::from_json_value(&config);
                Ok(json!({"result": engine.update_config(&config)}))
            }
            "setEnabled" => {
                let enabled = bool_field(payload, "enabled")?;
                Ok(json!({"result": engine.set_enabled(enabled)}))
            }
            "setIdleSleepPrevention" => {
                let prevention: IdleSleepPrevention = decode_field(payload, "prevention")?;
                Ok(json!({"result": engine.set_idle_sleep_prevention(prevention)}))
            }
            "setIdleSleepAvailable" => {
                engine.set_idle_sleep_available(bool_field(payload, "available")?);
                Ok(json!({}))
            }
            "setLidSleepAvailable" => Ok(
                json!({"result": engine.set_lid_sleep_available(bool_field(payload, "available")?)}),
            ),
            "replacePowerLeases" => {
                let leases: Vec<covio_core::power::models::HoldLease> =
                    decode_field(payload, "leases")?;
                Ok(json!({"result": engine.replace_power_leases(&leases)}))
            }
            "setPowerLidHold" => {
                Ok(json!({"result": engine.set_power_lid_hold(bool_field(payload, "required")?)}))
            }
            "setPowerLidDisplayOffEnabled" => {
                engine.set_power_lid_display_off_enabled(bool_field(payload, "enabled")?);
                Ok(json!({}))
            }
            "setManualLidSleepAvailable" => {
                engine.set_manual_lid_sleep_available(bool_field(payload, "available")?);
                Ok(json!({}))
            }
            "scheduleCancelIdle" => {
                engine.schedule_cancel_idle(int_field(payload, "seconds")?);
                Ok(json!({}))
            }
            "scheduleCancelLid" => {
                engine.schedule_cancel_lid(int_field(payload, "seconds")?);
                Ok(json!({}))
            }
            "sleepNow" => {
                engine.sleep_now();
                Ok(json!({}))
            }
            "displaySleepNow" => {
                engine.display_sleep_now();
                Ok(json!({}))
            }
            "onPowerChanged" => {
                engine.on_power_changed();
                Ok(json!({}))
            }
            "onLidChanged" => {
                let state: LidState = decode_field(payload, "state")?;
                engine.on_lid_changed(state);
                Ok(json!({}))
            }
            "onSleepEvent" => {
                let event: SleepEvent = decode_field(payload, "event")?;
                engine.on_sleep_event(event);
                Ok(json!({}))
            }
            "runWakeScan" => {
                engine.run_wake_scan(bool_field(payload, "initial")?);
                Ok(json!({}))
            }
            _ => Err(invalid("unknown engine command")),
        }
    }
}

/// Creates one Rust power engine with a platform capability callback.
///
/// # Safety
///
/// Pointer ranges must be valid. The callback and context must remain valid
/// until the returned handle is released.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_engine_create(
    config_json: *const u8,
    config_len: usize,
    callback: Option<EngineCapabilityCallback>,
    context: *mut c_void,
    error: *mut CovioError,
) -> *mut CovioEngineHandle {
    let result = ffi_guard(error, || {
        let callback = callback.ok_or_else(|| invalid("engine callback is required"))?;
        let config_bytes = unsafe { copy_input(config_json, config_len) }?;
        let config: Value = serde_json::from_slice(&config_bytes)
            .map_err(|_| invalid("engine config is not valid JSON"))?;
        let config = AppConfig::from_json_value(&config);
        let bridge = std::sync::Arc::new(CallbackBridge { callback, context });
        let clock_bridge = bridge.clone();
        let cache_clock_bridge = bridge.clone();
        let delay_bridge = bridge.clone();
        let schedule_bridge = bridge.clone();
        let engine = Engine::new(
            config,
            EngineDependencies {
                power: Box::new(PowerPort {
                    bridge: bridge.clone(),
                }),
                lid: Box::new(LidPort {
                    bridge: bridge.clone(),
                }),
                idle: Box::new(IdlePort {
                    bridge: bridge.clone(),
                }),
                sleep_controller: Box::new(SleepPort {
                    bridge: bridge.clone(),
                }),
                privileged: Box::new(PrivilegedPort {
                    bridge: bridge.clone(),
                }),
                wake_log_reader: Box::new(WakePort {
                    bridge: bridge.clone(),
                }),
                logger: Box::new(LoggerPort {
                    bridge: bridge.clone(),
                }),
                state_listener: Box::new(ListenerPort { bridge }),
                now_millis: Box::new(move || {
                    clock_bridge
                        .call("clock.nowMillis", json!({}))
                        .ok()
                        .and_then(|value| value.get("millis").and_then(Value::as_i64))
                        .unwrap_or_else(now_millis)
                }),
                wake_delay: Box::new(move |millis| {
                    let _ = delay_bridge.call("wake.delay", json!({"millis": millis}));
                }),
                wake_scan_executor: Some(Box::new(move |initial| {
                    let _ = schedule_bridge.call("wake.schedule", json!({"initial": initial}));
                })),
                wake_retry_delay_millis: 1_000,
                wake_retry_count: 3,
                wake_cache_now_millis: Box::new(move || {
                    cache_clock_bridge
                        .call("clock.wakeCacheNowMillis", json!({}))
                        .ok()
                        .and_then(|value| value.get("millis").and_then(Value::as_i64))
                        .unwrap_or_else(now_millis)
                }),
            },
        );
        Ok(Box::into_raw(Box::new(CovioEngineHandle {
            engine: Mutex::new(engine),
        })))
    });
    result.unwrap_or(std::ptr::null_mut())
}

/// Releases one engine handle.
///
/// # Safety
///
/// `handle` must come from [`covio_engine_create`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_engine_release(handle: *mut CovioEngineHandle) {
    if handle.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(handle));
    }));
}

/// Executes one engine command.
///
/// # Safety
///
/// Pointer ranges must be valid and `out_data` writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_engine_call(
    handle: *mut CovioEngineHandle,
    command: *const u8,
    command_len: usize,
    payload_json: *const u8,
    payload_len: usize,
    now_epoch_seconds: i64,
    out_data: *mut CovioOwnedBytes,
    error: *mut CovioError,
) -> u32 {
    if !out_data.is_null() {
        unsafe { out_data.write(CovioOwnedBytes::EMPTY) };
    }
    let result = ffi_guard(error, || {
        let handle = unsafe { handle.as_ref() }.ok_or_else(|| invalid("engine handle is null"))?;
        if out_data.is_null() {
            return Err(invalid("output buffer is null"));
        }
        let command = unsafe { copy_utf8(command, command_len, "command") }?;
        let payload = unsafe { copy_input(payload_json, payload_len) }?;
        let payload: Value = if payload.is_empty() {
            json!({})
        } else {
            serde_json::from_slice(&payload).map_err(|_| invalid("payload is not valid JSON"))?
        };
        let value = handle
            .call(&command, &payload, now_epoch_seconds)
            .map_err(|failure| FfiFailure::new(failure.status, failure.message))?;
        let bytes = serde_json::to_vec(&value)
            .map_err(|_| FfiFailure::new(CovioStatusCode::Internal, "response encoding failed"))?;
        unsafe { out_data.write(owned_bytes(bytes)) };
        Ok(())
    });
    result.map_or_else(|status| status as u32, |()| CovioStatusCode::Ok as u32)
}

/// Allocates bytes for a callback response.
///
/// # Safety
///
/// The input range must be valid and the returned allocation must be freed
/// through `covio_owned_bytes_free`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_owned_bytes_copy(data: *const u8, len: usize) -> CovioOwnedBytes {
    if len == 0 {
        return CovioOwnedBytes::EMPTY;
    }
    if data.is_null() {
        return CovioOwnedBytes::EMPTY;
    }
    let bytes = unsafe { slice::from_raw_parts(data, len) }.to_vec();
    owned_bytes(bytes)
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .and_then(|duration| i64::try_from(duration.as_millis()).ok())
        .unwrap_or(0)
}

fn invalid(message: &str) -> FfiFailure {
    FfiFailure::new(CovioStatusCode::InvalidArgument, message)
}

fn platform_error() -> PlatformError {
    PlatformError::unavailable("platform capability failed")
}

fn bool_field(payload: &Value, key: &str) -> Result<bool, FfiFailure> {
    payload
        .get(key)
        .and_then(Value::as_bool)
        .ok_or_else(|| invalid(&format!("{key} must be a bool")))
}

fn int_field(payload: &Value, key: &str) -> Result<i64, FfiFailure> {
    payload
        .get(key)
        .and_then(Value::as_i64)
        .ok_or_else(|| invalid(&format!("{key} must be an integer")))
}

fn decode_field<T: serde::de::DeserializeOwned>(
    payload: &Value,
    key: &str,
) -> Result<T, FfiFailure> {
    serde_json::from_value(
        payload
            .get(key)
            .cloned()
            .ok_or_else(|| invalid(&format!("{key} is required")))?,
    )
    .map_err(|_| invalid(&format!("{key} is invalid")))
}

//! Versioned C ABI for the macOS Covio host.
//!
//! This crate only converts boundary data. Business state machines and platform
//! policies remain in `covio-core` and `covio-platform`.

#![allow(unsafe_code)]
#![recursion_limit = "256"]
#![deny(unsafe_op_in_unsafe_fn)]

use covio_bridge::{
    BridgeLifecycle, BridgeLimits, BridgeMessage, BridgeValidator, CancelEnvelope, CancelReason,
    DEFAULT_MAX_CONTROL_BYTES, PROTOCOL_VERSION, ShutdownEnvelope, ShutdownMode, WireError,
    WireErrorCode, decode_message, encode_message,
};
use covio_core::{
    CredentialId, CredentialVault, Deadline, Generation, RecordKind, RequestId, Revision,
};
use covio_platform::{CapabilityKind, MacCapabilitySet};
use zeroize::Zeroize;

mod app_api;
mod engine_api;
pub use app_api::AppCore;
pub use engine_api::CovioEngineHandle;
use std::collections::BTreeSet;
use std::ffi::c_void;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;
use std::slice;

/// C ABI version.
pub const ABI_VERSION: u32 = 2;

/// C ABI status code.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum CovioStatusCode {
    /// Success.
    Ok = 0,
    /// Invalid pointer, length, or text value.
    InvalidArgument = 1,
    /// Input is not valid UTF-8.
    InvalidUtf8 = 2,
    /// Control payload exceeds the configured limit.
    PayloadTooLarge = 3,
    /// JSON or envelope shape is malformed.
    MalformedMessage = 4,
    /// Protocol version is unsupported.
    ProtocolVersion = 5,
    /// Generation is stale.
    StaleGeneration = 6,
    /// Revision is stale.
    StaleRevision = 7,
    /// Revision is invalid.
    InvalidRevision = 8,
    /// Deadline is invalid or expired.
    DeadlineExceeded = 9,
    /// Operation was cancelled.
    Cancelled = 10,
    /// Session is draining or stopped.
    ShuttingDown = 11,
    /// Capability or operation is unavailable.
    Unsupported = 12,
    /// Object was not found.
    NotFound = 13,
    /// State conflict.
    Conflict = 14,
    /// Platform I/O failed.
    Io = 15,
    /// Internal failure.
    Internal = 16,
    /// Native boundary panic.
    Panic = 17,
}

impl From<WireErrorCode> for CovioStatusCode {
    fn from(code: WireErrorCode) -> Self {
        match code {
            WireErrorCode::ProtocolVersion => Self::ProtocolVersion,
            WireErrorCode::PayloadTooLarge => Self::PayloadTooLarge,
            WireErrorCode::MalformedMessage => Self::MalformedMessage,
            WireErrorCode::InvalidRequestId
            | WireErrorCode::InvalidCommand
            | WireErrorCode::InvalidEvent
            | WireErrorCode::InvalidSnapshot
            | WireErrorCode::InvalidArgument => Self::InvalidArgument,
            WireErrorCode::StaleGeneration => Self::StaleGeneration,
            WireErrorCode::StaleRevision => Self::StaleRevision,
            WireErrorCode::InvalidRevision => Self::InvalidRevision,
            WireErrorCode::DeadlineExceeded => Self::DeadlineExceeded,
            WireErrorCode::Cancelled => Self::Cancelled,
            WireErrorCode::ShuttingDown => Self::ShuttingDown,
            WireErrorCode::Unsupported => Self::Unsupported,
            WireErrorCode::NotFound => Self::NotFound,
            WireErrorCode::Conflict => Self::Conflict,
            WireErrorCode::Io => Self::Io,
            WireErrorCode::Internal => Self::Internal,
        }
    }
}

/// One accepted bridge message.
#[derive(Debug, Clone, PartialEq)]
pub struct DispatchResult {
    /// Re-encoded validated message.
    pub message: Vec<u8>,
    /// Whether the host callback must receive this message.
    pub notify: bool,
}

/// Stateful boundary session used by the opaque C handle.
pub struct BridgeSession {
    generation: Generation,
    revision: Revision,
    limits: BridgeLimits,
    validator: BridgeValidator,
    lifecycle: BridgeLifecycle,
    active_requests: BTreeSet<String>,
}

impl BridgeSession {
    /// Creates a running session.
    #[must_use]
    pub fn new(generation: Generation, revision: Revision, limits: BridgeLimits) -> Self {
        Self {
            generation,
            revision,
            limits,
            validator: BridgeValidator::new(generation, revision, BridgeLifecycle::Running, limits),
            lifecycle: BridgeLifecycle::Running,
            active_requests: BTreeSet::new(),
        }
    }

    /// Validates and records one bridge message.
    pub fn dispatch(
        &mut self,
        message: &[u8],
        now_unix_millis: u64,
    ) -> Result<DispatchResult, FfiFailure> {
        if message.is_empty() {
            return Err(FfiFailure::new(
                CovioStatusCode::MalformedMessage,
                "bridge message is empty",
            ));
        }
        if message.len() > self.limits.max_control_bytes {
            return Err(FfiFailure::new(
                CovioStatusCode::PayloadTooLarge,
                "bridge payload exceeds the configured limit",
            ));
        }
        std::str::from_utf8(message).map_err(|_| {
            FfiFailure::new(CovioStatusCode::InvalidUtf8, "bridge message is not UTF-8")
        })?;
        let decoded = decode_message(message, self.limits).map_err(FfiFailure::from_wire)?;
        self.validator
            .validate_message(&decoded, now_unix_millis)
            .map_err(FfiFailure::from_wire)?;

        let notify = matches!(
            decoded,
            BridgeMessage::Event(_) | BridgeMessage::Snapshot(_)
        );
        match &decoded {
            BridgeMessage::Request(request) => {
                self.active_requests
                    .insert(request.request_id.as_str().to_owned());
            }
            BridgeMessage::Response(response) => {
                self.active_requests.remove(response.request_id.as_str());
            }
            BridgeMessage::Cancel(cancel) => {
                self.active_requests.remove(cancel.request_id.as_str());
            }
            BridgeMessage::Shutdown(shutdown) => {
                self.lifecycle = match shutdown.mode {
                    ShutdownMode::Graceful => BridgeLifecycle::Draining,
                    ShutdownMode::Immediate => {
                        self.active_requests.clear();
                        BridgeLifecycle::Stopped
                    }
                };
                self.validator = BridgeValidator::new(
                    self.generation,
                    self.revision,
                    self.lifecycle,
                    self.limits,
                );
            }
            BridgeMessage::Event(_) | BridgeMessage::Snapshot(_) => {}
        }

        let message = encode_message(&decoded, self.limits).map_err(FfiFailure::from_wire)?;
        Ok(DispatchResult { message, notify })
    }

    /// Cancels one request by id.
    pub fn cancel(
        &mut self,
        request_id: &str,
        reason: CancelReason,
        now_unix_millis: u64,
    ) -> Result<DispatchResult, FfiFailure> {
        let cancel = CancelEnvelope {
            protocol_version: PROTOCOL_VERSION,
            generation: self.generation,
            request_id: RequestId::try_new(request_id).map_err(|_| {
                FfiFailure::new(CovioStatusCode::InvalidArgument, "request id is invalid")
            })?,
            reason,
        };
        let message = encode_message(&BridgeMessage::Cancel(cancel), self.limits)
            .map_err(FfiFailure::from_wire)?;
        self.dispatch(&message, now_unix_millis)
    }

    /// Shuts down the boundary session.
    pub fn shutdown(
        &mut self,
        mode: ShutdownMode,
        deadline: Option<Deadline>,
        now_unix_millis: u64,
    ) -> Result<DispatchResult, FfiFailure> {
        let shutdown = ShutdownEnvelope {
            protocol_version: PROTOCOL_VERSION,
            generation: self.generation,
            mode,
            deadline,
        };
        let message = encode_message(&BridgeMessage::Shutdown(shutdown), self.limits)
            .map_err(FfiFailure::from_wire)?;
        self.dispatch(&message, now_unix_millis)
    }

    /// Returns the lifecycle state.
    #[must_use]
    pub const fn lifecycle(&self) -> BridgeLifecycle {
        self.lifecycle
    }

    /// Returns the number of accepted requests that have no response yet.
    #[must_use]
    pub fn active_request_count(&self) -> usize {
        self.active_requests.len()
    }

    /// Returns the generation used by this session.
    #[must_use]
    pub const fn generation(&self) -> Generation {
        self.generation
    }

    /// Returns the current revision.
    #[must_use]
    pub const fn revision(&self) -> Revision {
        self.revision
    }

    /// Returns the session limits.
    #[must_use]
    pub const fn limits(&self) -> BridgeLimits {
        self.limits
    }
}

/// Native boundary failure.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FfiFailure {
    /// Stable status category.
    pub status: CovioStatusCode,
    /// Public, redacted message.
    pub message: String,
}

impl FfiFailure {
    /// Creates a boundary failure.
    #[must_use]
    pub fn new(status: CovioStatusCode, message: impl Into<String>) -> Self {
        Self {
            status,
            message: message.into(),
        }
    }

    fn from_wire(error: WireError) -> Self {
        Self {
            status: CovioStatusCode::from(error.code),
            message: error.message,
        }
    }
}

/// Owned bytes returned across the C ABI.
#[derive(Debug, Clone, Copy)]
#[repr(C)]
pub struct CovioOwnedBytes {
    /// Allocation pointer. Null means empty.
    pub data: *mut u8,
    /// Number of initialized bytes.
    pub len: usize,
    /// Allocation capacity.
    pub capacity: usize,
}

impl CovioOwnedBytes {
    const EMPTY: Self = Self {
        data: ptr::null_mut(),
        len: 0,
        capacity: 0,
    };
}

impl CovioOwnedBytes {
    pub(crate) unsafe fn take_bytes(self) -> Result<Vec<u8>, ()> {
        if self.data.is_null() {
            return Ok(Vec::new());
        }
        if self.capacity < self.len {
            return Err(());
        }
        Ok(unsafe { Vec::from_raw_parts(self.data, self.len, self.capacity) })
    }

    unsafe fn free_zeroized(self) {
        if self.data.is_null() || self.capacity < self.len {
            return;
        }
        let mut bytes = unsafe { Vec::from_raw_parts(self.data, self.len, self.capacity) };
        bytes.zeroize();
    }
}

/// Error returned across the C ABI.
#[derive(Debug, Clone, Copy)]
#[repr(C)]
pub struct CovioError {
    /// Stable status code.
    pub code: u32,
    /// Public error message. Caller must free through [`covio_error_free`].
    pub message: CovioOwnedBytes,
}

impl CovioError {
    pub(crate) unsafe fn free_message(&mut self) {
        unsafe { self.message.free_zeroized() };
        self.message = CovioOwnedBytes::EMPTY;
    }
}

/// Callback for core events and snapshots.
pub type CovioEventCallback = extern "C-unwind" fn(*mut c_void, *const u8, usize);

/// Opaque C session handle.
pub struct CovioHandle {
    session: BridgeSession,
    callback: Option<CovioEventCallback>,
    context: *mut c_void,
}

/// Opaque application service handle.
pub struct CovioAppHandle {
    core: AppCore,
}

/// macOS adapter composition used before the product host wires all capabilities.
pub struct MacPlatformAdapters {
    /// Filesystem adapter.
    pub filesystem: covio_platform::StdFileStore,
    /// Keychain adapter on macOS.
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    pub secrets: covio_platform::KeychainSecretStore,
    /// Capability inventory.
    pub capabilities: MacCapabilitySet,
}

impl Default for MacPlatformAdapters {
    fn default() -> Self {
        Self {
            filesystem: covio_platform::StdFileStore::new(),
            #[cfg(any(target_os = "macos", target_os = "ios"))]
            secrets: covio_platform::KeychainSecretStore::default(),
            capabilities: MacCapabilitySet::default(),
        }
    }
}

/// Creates one application service handle for a data root.
///
/// # Safety
///
/// The data-root byte range must describe valid readable memory.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_app_create(
    data_root: *const u8,
    data_root_len: usize,
    error: *mut CovioError,
) -> *mut CovioAppHandle {
    let result = ffi_guard(error, || {
        let data_root = unsafe { copy_utf8(data_root, data_root_len, "data root") }?;
        Ok(Box::into_raw(Box::new(CovioAppHandle {
            core: AppCore::new(data_root),
        })))
    });
    result.unwrap_or(ptr::null_mut())
}

/// Creates one application service handle with explicit compatibility paths.
///
/// # Safety
///
/// Every path byte range must describe valid readable memory.
#[unsafe(no_mangle)]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn covio_app_create_with_paths(
    config_path: *const u8,
    config_len: usize,
    shelf_path: *const u8,
    shelf_len: usize,
    clipboard_path: *const u8,
    clipboard_len: usize,
    workspace_path: *const u8,
    workspace_len: usize,
    error: *mut CovioError,
) -> *mut CovioAppHandle {
    let result = ffi_guard(error, || {
        let config_path = unsafe { copy_utf8(config_path, config_len, "config path") }?;
        let shelf_path = unsafe { copy_utf8(shelf_path, shelf_len, "shelf path") }?;
        let clipboard_path = unsafe { copy_utf8(clipboard_path, clipboard_len, "clipboard path") }?;
        let workspace_path = unsafe { copy_utf8(workspace_path, workspace_len, "workspace path") }?;
        Ok(Box::into_raw(Box::new(CovioAppHandle {
            core: AppCore::with_paths(config_path, shelf_path, clipboard_path, workspace_path),
        })))
    });
    result.unwrap_or(ptr::null_mut())
}

/// Releases one application service handle.
///
/// # Safety
///
/// `handle` must be a pointer returned by [`covio_app_create`].
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_app_release(handle: *mut CovioAppHandle) {
    if handle.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(handle));
    }));
}

/// Executes one application command.
///
/// # Safety
///
/// Pointer and length pairs must describe valid readable memory. `out_data`
/// must be writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_app_call(
    handle: *mut CovioAppHandle,
    command: *const u8,
    command_len: usize,
    payload: *const u8,
    payload_len: usize,
    now_epoch_seconds: i64,
    out_data: *mut CovioOwnedBytes,
    error: *mut CovioError,
) -> u32 {
    if !out_data.is_null() {
        unsafe { out_data.write(CovioOwnedBytes::EMPTY) };
    }
    let result = ffi_guard(error, || {
        let handle = unsafe { handle.as_ref() }.ok_or_else(|| {
            FfiFailure::new(CovioStatusCode::InvalidArgument, "app handle is null")
        })?;
        if out_data.is_null() {
            return Err(FfiFailure::new(
                CovioStatusCode::InvalidArgument,
                "output buffer is null",
            ));
        }
        let command = unsafe { copy_utf8(command, command_len, "command") }?;
        let payload_bytes = unsafe { copy_input(payload, payload_len) }?;
        let payload: serde_json::Value = if payload_bytes.is_empty() {
            serde_json::json!({})
        } else {
            serde_json::from_slice(&payload_bytes).map_err(|_| {
                FfiFailure::new(
                    CovioStatusCode::MalformedMessage,
                    "payload is not valid JSON",
                )
            })?
        };
        let value = handle
            .core
            .call(&command, &payload, now_epoch_seconds)
            .map_err(|message| FfiFailure::new(CovioStatusCode::InvalidArgument, message))?;
        let bytes = serde_json::to_vec(&value).map_err(|_| {
            FfiFailure::new(CovioStatusCode::Internal, "response serialization failed")
        })?;
        unsafe { out_data.write(owned_bytes(bytes)) };
        Ok(())
    });
    result.map_or_else(|status| status as u32, |()| CovioStatusCode::Ok as u32)
}

/// Returns the ABI version for runtime loader checks.
#[unsafe(no_mangle)]
pub extern "C" fn covio_ffi_abi_version() -> u32 {
    ABI_VERSION
}

/// Returns the bridge protocol version for platform loader checks.
#[unsafe(no_mangle)]
pub extern "C" fn covio_bridge_protocol_version() -> u32 {
    u32::from(PROTOCOL_VERSION)
}

/// Creates one opaque session handle.
///
/// The caller must call [`covio_handle_release`] exactly once.
///
/// # Safety
///
/// `callback` and `context` must remain valid for the handle lifetime.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_handle_create(
    generation: u64,
    revision: u64,
    max_control_bytes: u32,
    callback: Option<CovioEventCallback>,
    context: *mut c_void,
    error: *mut CovioError,
) -> *mut CovioHandle {
    let result = ffi_guard(error, || {
        let limits = BridgeLimits {
            max_control_bytes: if max_control_bytes == 0 {
                DEFAULT_MAX_CONTROL_BYTES
            } else {
                max_control_bytes as usize
            },
            ..BridgeLimits::default()
        };
        let handle = CovioHandle {
            session: BridgeSession::new(
                Generation::new(generation),
                Revision::new(revision),
                limits,
            ),
            callback,
            context,
        };
        Ok(Box::into_raw(Box::new(handle)))
    });
    result.unwrap_or(ptr::null_mut())
}

/// Releases one opaque session handle.
///
/// # Safety
///
/// `handle` must be a pointer returned by [`covio_handle_create`] and must not be used again.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_handle_release(handle: *mut CovioHandle) {
    if handle.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(handle));
    }));
}

/// Validates and dispatches one bridge JSON message.
///
/// # Safety
///
/// Pointer and length pairs must describe valid readable memory. `out_message`
/// must be writable and must not contain an allocation that has not been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_handle_dispatch(
    handle: *mut CovioHandle,
    message: *const u8,
    message_len: usize,
    now_unix_millis: u64,
    out_message: *mut CovioOwnedBytes,
    error: *mut CovioError,
) -> u32 {
    if !out_message.is_null() {
        unsafe { out_message.write(CovioOwnedBytes::EMPTY) };
    }
    let result = ffi_guard(error, || {
        let handle = unsafe { handle.as_mut() }
            .ok_or_else(|| FfiFailure::new(CovioStatusCode::InvalidArgument, "handle is null"))?;
        if out_message.is_null() {
            return Err(FfiFailure::new(
                CovioStatusCode::InvalidArgument,
                "output buffer is null",
            ));
        }
        let message = unsafe { copy_input(message, message_len) }?;
        let result = handle.session.dispatch(&message, now_unix_millis)?;
        if result.notify
            && let Some(callback) = handle.callback
        {
            let callback_result = catch_unwind(AssertUnwindSafe(|| {
                callback(
                    handle.context,
                    result.message.as_ptr(),
                    result.message.len(),
                );
            }));
            if callback_result.is_err() {
                // A host callback panic must not unwind through the C ABI.
            }
        }
        unsafe { out_message.write(owned_bytes(result.message)) };
        Ok(())
    });
    result.map_or_else(|status| status as u32, |()| CovioStatusCode::Ok as u32)
}

/// Cancels one active request.
///
/// # Safety
///
/// `handle` and the request id byte range must be valid for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_handle_cancel(
    handle: *mut CovioHandle,
    request_id: *const u8,
    request_id_len: usize,
    reason: u32,
    now_unix_millis: u64,
    error: *mut CovioError,
) -> u32 {
    let result = ffi_guard(error, || {
        let handle = unsafe { handle.as_mut() }
            .ok_or_else(|| FfiFailure::new(CovioStatusCode::InvalidArgument, "handle is null"))?;
        let request_id = unsafe { copy_utf8(request_id, request_id_len, "request id") }?;
        let reason = match reason {
            0 => CancelReason::Host,
            1 => CancelReason::Deadline,
            2 => CancelReason::Shutdown,
            _ => {
                return Err(FfiFailure::new(
                    CovioStatusCode::InvalidArgument,
                    "cancel reason is invalid",
                ));
            }
        };
        handle
            .session
            .cancel(&request_id, reason, now_unix_millis)?;
        Ok(())
    });
    result.map_or_else(|status| status as u32, |()| CovioStatusCode::Ok as u32)
}

/// Shuts down one bridge session.
///
/// # Safety
///
/// `handle` must be valid for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_handle_shutdown(
    handle: *mut CovioHandle,
    immediate: bool,
    has_deadline: bool,
    deadline_unix_millis: u64,
    now_unix_millis: u64,
    error: *mut CovioError,
) -> u32 {
    let result = ffi_guard(error, || {
        let handle = unsafe { handle.as_mut() }
            .ok_or_else(|| FfiFailure::new(CovioStatusCode::InvalidArgument, "handle is null"))?;
        let mode = if immediate {
            ShutdownMode::Immediate
        } else {
            ShutdownMode::Graceful
        };
        let deadline = has_deadline.then(|| Deadline::from_unix_millis(deadline_unix_millis));
        handle.session.shutdown(mode, deadline, now_unix_millis)?;
        Ok(())
    });
    result.map_or_else(|status| status as u32, |()| CovioStatusCode::Ok as u32)
}

/// Returns one lifecycle value.
///
/// # Safety
///
/// `handle` must be valid for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_handle_lifecycle(handle: *const CovioHandle) -> u32 {
    let Some(handle) = (unsafe { handle.as_ref() }) else {
        return CovioLifecycleWire::Running as u32;
    };
    match handle.session.lifecycle() {
        BridgeLifecycle::Running => CovioLifecycleWire::Running as u32,
        BridgeLifecycle::Draining => CovioLifecycleWire::Draining as u32,
        BridgeLifecycle::Stopped => CovioLifecycleWire::Stopped as u32,
    }
}

/// Returns the number of requests that have no response yet.
///
/// # Safety
///
/// `handle` must be valid for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_handle_active_request_count(handle: *const CovioHandle) -> u64 {
    unsafe { handle.as_ref() }.map_or(0, |handle| handle.session.active_request_count() as u64)
}

const AGENT_TOKEN_SERVICE_PREFIX: &str = "com.wyz.covio.agent.";
const AGENT_TOKEN_ACCOUNT: &str = "mcp-bearer-token";
#[cfg(any(target_os = "macos", target_os = "ios"))]
const AGENT_VAULT_SERVICE: &str = "com.wyz.covio.credentials";
#[cfg(all(any(target_os = "macos", target_os = "ios"), debug_assertions))]
const AGENT_VAULT_SERVICE_ENV: &str = "COVIO_AGENT_VAULT_SERVICE";

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn agent_vault_service() -> String {
    #[cfg(debug_assertions)]
    if let Ok(service) = std::env::var(AGENT_VAULT_SERVICE_ENV)
        && !service.is_empty()
        && service.len() <= 255
        && service.bytes().all(|byte| byte.is_ascii_graphic())
    {
        return service;
    }
    AGENT_VAULT_SERVICE.to_owned()
}

/// Reads the product Agent token through the Rust credential vault.
///
/// # Safety
///
/// Pointer and length pairs must describe valid readable memory. `out_value`
/// must be writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_agent_token_read(
    data_root: *const u8,
    data_root_len: usize,
    service: *const u8,
    service_len: usize,
    account: *const u8,
    account_len: usize,
    out_value: *mut CovioOwnedBytes,
    error: *mut CovioError,
) -> u32 {
    if !out_value.is_null() {
        unsafe { out_value.write(CovioOwnedBytes::EMPTY) };
    }
    let result = ffi_guard(error, || {
        if out_value.is_null() {
            return Err(FfiFailure::new(
                CovioStatusCode::InvalidArgument,
                "output buffer is null",
            ));
        }
        let data_root = unsafe { copy_utf8(data_root, data_root_len, "data root") }?;
        let (_service, record_id) =
            unsafe { agent_token_target(service, service_len, account, account_len) }?;
        let value = with_agent_token_vault(&data_root, |vault| {
            vault.with_secret(&record_id, |secret| Ok(secret.expose().to_vec()))
        })?;
        unsafe { out_value.write(owned_bytes(value)) };
        Ok(())
    });
    result.map_or_else(|status| status as u32, |()| CovioStatusCode::Ok as u32)
}

/// Writes or replaces the product Agent token through the Rust credential vault.
///
/// # Safety
///
/// Pointer and length pairs must describe valid readable memory.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_agent_token_write(
    data_root: *const u8,
    data_root_len: usize,
    service: *const u8,
    service_len: usize,
    account: *const u8,
    account_len: usize,
    value: *const u8,
    value_len: usize,
    error: *mut CovioError,
) -> u32 {
    let result = ffi_guard(error, || {
        let data_root = unsafe { copy_utf8(data_root, data_root_len, "data root") }?;
        let (_service, record_id) =
            unsafe { agent_token_target(service, service_len, account, account_len) }?;
        let value = unsafe { copy_input(value, value_len) }?;
        with_agent_token_vault(&data_root, |vault| {
            vault.put(
                &record_id,
                RecordKind::AgentToken,
                &covio_platform::SecretValue::new(value),
                0,
            )?;
            Ok(())
        })
    });
    result.map_or_else(|status| status as u32, |()| CovioStatusCode::Ok as u32)
}

/// Deletes the product Agent token from the Rust credential vault.
///
/// # Safety
///
/// Pointer and length pairs must describe valid readable memory.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_agent_token_delete(
    data_root: *const u8,
    data_root_len: usize,
    service: *const u8,
    service_len: usize,
    account: *const u8,
    account_len: usize,
    error: *mut CovioError,
) -> u32 {
    let result = ffi_guard(error, || {
        let data_root = unsafe { copy_utf8(data_root, data_root_len, "data root") }?;
        let (_service, record_id) =
            unsafe { agent_token_target(service, service_len, account, account_len) }?;
        with_agent_token_vault(&data_root, |vault| {
            vault.delete(&record_id)?;
            Ok(())
        })
    });
    result.map_or_else(|status| status as u32, |()| CovioStatusCode::Ok as u32)
}

/// Resets the product Agent credential vault.
///
/// # Safety
///
/// The data-root byte range must describe valid readable memory.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_agent_token_reset(
    data_root: *const u8,
    data_root_len: usize,
    error: *mut CovioError,
) -> u32 {
    let result = ffi_guard(error, || {
        let data_root = unsafe { copy_utf8(data_root, data_root_len, "data root") }?;
        reset_agent_token_vault(&data_root)
    });
    result.map_or_else(|status| status as u32, |()| CovioStatusCode::Ok as u32)
}

/// Probes one capability. Unsupported adapters return `Unsupported`.
#[unsafe(no_mangle)]
pub extern "C" fn covio_capability_status(capability: u32, error: *mut CovioError) -> u32 {
    let result = ffi_guard(error, || {
        let kind = CapabilityKind::from_wire(capability).ok_or_else(|| {
            FfiFailure::new(CovioStatusCode::InvalidArgument, "capability is invalid")
        })?;
        if MacCapabilitySet::default().status(kind).available {
            Ok(())
        } else {
            Err(FfiFailure::new(
                CovioStatusCode::Unsupported,
                "platform capability is unavailable",
            ))
        }
    });
    result.map_or_else(|status| status as u32, |()| CovioStatusCode::Ok as u32)
}

/// Frees bytes returned by this ABI.
///
/// # Safety
///
/// `bytes` must come from this ABI and must not be freed twice.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_owned_bytes_free(bytes: *mut CovioOwnedBytes) {
    if bytes.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let value = bytes.read();
        value.free_zeroized();
        bytes.write(CovioOwnedBytes::EMPTY);
    }));
}

/// Frees one error message.
///
/// # Safety
///
/// `error` must come from this ABI and must not be freed twice.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn covio_error_free(error: *mut CovioError) {
    if error.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let mut value = error.read();
        covio_owned_bytes_free(&mut value.message);
        value.code = 0;
        error.write(value);
    }));
}

#[repr(u32)]
enum CovioLifecycleWire {
    Running = 0,
    Draining = 1,
    Stopped = 2,
}

fn ffi_guard<T>(
    error: *mut CovioError,
    operation: impl FnOnce() -> Result<T, FfiFailure>,
) -> Result<T, CovioStatusCode> {
    unsafe { clear_error(error) };
    match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(failure)) => {
            unsafe {
                write_error(error, failure.status, &failure.message);
            }
            Err(failure.status)
        }
        Err(_) => {
            unsafe {
                write_error(error, CovioStatusCode::Panic, "native boundary panic");
            }
            Err(CovioStatusCode::Panic)
        }
    }
}

unsafe fn copy_input(pointer: *const u8, length: usize) -> Result<Vec<u8>, FfiFailure> {
    if length == 0 {
        return Ok(Vec::new());
    }
    if pointer.is_null() {
        return Err(FfiFailure::new(
            CovioStatusCode::InvalidArgument,
            "input pointer is null",
        ));
    }
    Ok(unsafe { slice::from_raw_parts(pointer, length) }.to_vec())
}

unsafe fn copy_utf8(pointer: *const u8, length: usize, field: &str) -> Result<String, FfiFailure> {
    let bytes = unsafe { copy_input(pointer, length) }?;
    String::from_utf8(bytes).map_err(|_| {
        FfiFailure::new(
            CovioStatusCode::InvalidUtf8,
            format!("{field} is not valid UTF-8"),
        )
    })
}

fn owned_bytes(mut value: Vec<u8>) -> CovioOwnedBytes {
    if value.is_empty() {
        return CovioOwnedBytes::EMPTY;
    }
    let bytes = CovioOwnedBytes {
        data: value.as_mut_ptr(),
        len: value.len(),
        capacity: value.capacity(),
    };
    std::mem::forget(value);
    bytes
}

unsafe fn write_error(error: *mut CovioError, status: CovioStatusCode, message: &str) {
    if error.is_null() {
        return;
    }
    unsafe {
        error.write(CovioError {
            code: status as u32,
            message: owned_bytes(message.as_bytes().to_vec()),
        });
    }
}

unsafe fn clear_error(error: *mut CovioError) {
    if error.is_null() {
        return;
    }
    unsafe {
        error.write(CovioError {
            code: 0,
            message: CovioOwnedBytes::EMPTY,
        });
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
type AgentVault =
    CredentialVault<covio_platform::KeychainSecretStore, covio_platform::StdFileStore>;

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
type AgentVault =
    CredentialVault<covio_platform::UnavailableSecretStore, covio_platform::StdFileStore>;

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn with_agent_token_vault<T>(
    data_root: &str,
    operation: impl FnOnce(&mut AgentVault) -> Result<T, covio_core::CredentialError>,
) -> Result<T, FfiFailure> {
    let root = std::path::PathBuf::from(data_root).join("credentials");
    let open = || {
        CredentialVault::open(
            root.clone(),
            covio_platform::KeychainSecretStore::new(agent_vault_service()),
            covio_platform::StdFileStore::new(),
        )
    };
    let mut vault = match open() {
        Ok(vault) => vault,
        Err(error) if error.code() == covio_core::CredentialErrorCode::NotFound => {
            CredentialVault::create(
                root,
                covio_platform::KeychainSecretStore::new(agent_vault_service()),
                covio_platform::StdFileStore::new(),
            )
            .map_err(credential_failure)?
        }
        Err(error) => return Err(credential_failure(error)),
    };
    operation(&mut vault).map_err(credential_failure)
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn reset_agent_token_vault(data_root: &str) -> Result<(), FfiFailure> {
    let root = std::path::PathBuf::from(data_root).join("credentials");
    match CredentialVault::open(
        root,
        covio_platform::KeychainSecretStore::new(agent_vault_service()),
        covio_platform::StdFileStore::new(),
    ) {
        Ok(vault) => vault.destroy().map_err(credential_failure),
        Err(error) if error.code() == covio_core::CredentialErrorCode::NotFound => Ok(()),
        Err(error) => Err(credential_failure(error)),
    }
}

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
fn reset_agent_token_vault(_data_root: &str) -> Result<(), FfiFailure> {
    Err(unsupported_secret_storage())
}

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
fn with_agent_token_vault<T>(
    _data_root: &str,
    _operation: impl FnOnce(&mut AgentVault) -> Result<T, covio_core::CredentialError>,
) -> Result<T, FfiFailure> {
    Err(unsupported_secret_storage())
}

fn credential_failure(error: covio_core::CredentialError) -> FfiFailure {
    let status = match error.code() {
        covio_core::CredentialErrorCode::NotFound => CovioStatusCode::NotFound,
        covio_core::CredentialErrorCode::InvalidArgument => CovioStatusCode::InvalidArgument,
        covio_core::CredentialErrorCode::AlreadyExists => CovioStatusCode::Conflict,
        covio_core::CredentialErrorCode::UserCancelled => CovioStatusCode::Cancelled,
        covio_core::CredentialErrorCode::AuthenticationRequired
        | covio_core::CredentialErrorCode::DeviceLocked
        | covio_core::CredentialErrorCode::KeyInvalidated
        | covio_core::CredentialErrorCode::BackendUnavailable => CovioStatusCode::Io,
        covio_core::CredentialErrorCode::IntegrityFailed
        | covio_core::CredentialErrorCode::RecordCorrupt
        | covio_core::CredentialErrorCode::VersionUnsupported
        | covio_core::CredentialErrorCode::RecoveryRequired
        | covio_core::CredentialErrorCode::Internal => CovioStatusCode::Internal,
    };
    FfiFailure::new(status, error.message())
}

unsafe fn agent_token_target(
    service: *const u8,
    service_len: usize,
    account: *const u8,
    account_len: usize,
) -> Result<(String, CredentialId), FfiFailure> {
    let service = unsafe { copy_keychain_service(service, service_len) }?;
    if !service.starts_with(AGENT_TOKEN_SERVICE_PREFIX) {
        return Err(FfiFailure::new(
            CovioStatusCode::InvalidArgument,
            "Agent token service is outside the allowed namespace",
        ));
    }
    let account = unsafe { copy_utf8(account, account_len, "Agent token account") }?;
    if account != AGENT_TOKEN_ACCOUNT {
        return Err(FfiFailure::new(
            CovioStatusCode::InvalidArgument,
            "Agent token account is invalid",
        ));
    }
    let record_id = CredentialId::try_new(format!("agent/external/{service}/{account}"))
        .map_err(credential_failure)?;
    Ok((service, record_id))
}

unsafe fn copy_keychain_service(
    service: *const u8,
    service_len: usize,
) -> Result<String, FfiFailure> {
    let service = unsafe { copy_utf8(service, service_len, "keychain service") }?;
    if service.is_empty()
        || service.len() > 255
        || !service.bytes().all(|byte| byte.is_ascii_graphic())
    {
        return Err(FfiFailure::new(
            CovioStatusCode::InvalidArgument,
            "keychain service is invalid",
        ));
    }
    Ok(service)
}

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
fn unsupported_secret_storage() -> FfiFailure {
    FfiFailure::new(
        CovioStatusCode::Unsupported,
        "secure storage is unavailable",
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::Mutex;

    #[derive(Default)]
    struct Capture {
        messages: Mutex<Vec<Vec<u8>>>,
    }

    extern "C-unwind" fn capture_callback(context: *mut c_void, data: *const u8, len: usize) {
        let capture = unsafe { &*(context.cast::<Capture>()) };
        let bytes = unsafe { slice::from_raw_parts(data, len) }.to_vec();
        capture.messages.lock().unwrap().push(bytes);
    }

    extern "C-unwind" fn panic_callback(_context: *mut c_void, _data: *const u8, _len: usize) {
        panic!("callback panic");
    }

    fn request(id: &str) -> Vec<u8> {
        serde_json::to_vec(&json!({
            "kind": "request",
            "body": {
                "protocol_version": PROTOCOL_VERSION,
                "request_id": id,
                "generation": 1,
                "command": "settings.load",
                "deadline": null,
                "payload": {}
            }
        }))
        .expect("request json")
    }

    fn response(id: &str) -> Vec<u8> {
        serde_json::to_vec(&json!({
            "kind": "response",
            "body": {
                "protocol_version": PROTOCOL_VERSION,
                "request_id": id,
                "generation": 1,
                "revision": null,
                "result": {"status": "ok", "data": {}}
            }
        }))
        .expect("response json")
    }

    fn event() -> Vec<u8> {
        serde_json::to_vec(&json!({
            "kind": "event",
            "body": {
                "protocol_version": PROTOCOL_VERSION,
                "generation": 1,
                "revision": 0,
                "event": "app.ready",
                "payload": {}
            }
        }))
        .expect("event json")
    }

    fn snapshot() -> Vec<u8> {
        serde_json::to_vec(&json!({
            "kind": "snapshot",
            "body": {
                "protocol_version": PROTOCOL_VERSION,
                "generation": 1,
                "revision": 0,
                "snapshot": "app.state",
                "payload": {"ready": true}
            }
        }))
        .expect("snapshot json")
    }

    fn empty_error() -> CovioError {
        CovioError {
            code: 0,
            message: CovioOwnedBytes::EMPTY,
        }
    }

    fn empty_bytes() -> CovioOwnedBytes {
        CovioOwnedBytes::EMPTY
    }

    #[test]
    fn session_tracks_requests_responses_and_snapshot_notifications() {
        let mut session = BridgeSession::new(
            Generation::new(1),
            Revision::INITIAL,
            BridgeLimits::default(),
        );
        let request_result = session.dispatch(&request("request-1"), 50).unwrap();
        assert!(!request_result.notify);
        assert_eq!(session.active_request_count(), 1);

        let response_result = session.dispatch(&response("request-1"), 50).unwrap();
        assert!(!response_result.notify);
        assert_eq!(session.active_request_count(), 0);

        let event_result = session.dispatch(&event(), 50).unwrap();
        assert!(event_result.notify);
        let snapshot_result = session.dispatch(&snapshot(), 50).unwrap();
        assert!(snapshot_result.notify);
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(&snapshot_result.message).expect("message")
                ["kind"],
            "snapshot"
        );
    }

    #[test]
    fn cancellation_and_shutdown_change_lifecycle_without_business_fallback() {
        let mut session = BridgeSession::new(
            Generation::new(1),
            Revision::INITIAL,
            BridgeLimits::default(),
        );
        session.dispatch(&request("request-1"), 50).unwrap();
        session.cancel("request-1", CancelReason::Host, 50).unwrap();
        assert_eq!(session.active_request_count(), 0);

        session.shutdown(ShutdownMode::Graceful, None, 50).unwrap();
        assert_eq!(session.lifecycle(), BridgeLifecycle::Draining);
        let error = session.dispatch(&request("request-2"), 50).unwrap_err();
        assert_eq!(error.status, CovioStatusCode::ShuttingDown);

        session.shutdown(ShutdownMode::Immediate, None, 50).unwrap();
        assert_eq!(session.lifecycle(), BridgeLifecycle::Stopped);
    }

    #[test]
    fn payload_bound_and_stale_generation_are_typed() {
        let limits = BridgeLimits {
            max_control_bytes: 32,
            ..BridgeLimits::default()
        };
        let mut session = BridgeSession::new(Generation::new(1), Revision::INITIAL, limits);
        let error = session.dispatch(&[b'x'; 33], 50).unwrap_err();
        assert_eq!(error.status, CovioStatusCode::PayloadTooLarge);

        let mut stale_session = BridgeSession::new(
            Generation::new(1),
            Revision::INITIAL,
            BridgeLimits::default(),
        );
        let mut stale = request("request-1");
        stale = String::from_utf8(stale)
            .unwrap()
            .replace("\"generation\":1", "\"generation\":2")
            .into_bytes();
        let error = stale_session.dispatch(&stale, 50).unwrap_err();
        assert_eq!(error.status, CovioStatusCode::StaleGeneration);
    }

    #[test]
    fn c_handle_round_trip_delivers_snapshot_and_rejects_after_shutdown() {
        let capture = Capture::default();
        let context = (&capture as *const Capture).cast_mut().cast::<c_void>();
        let mut error = empty_error();
        let handle =
            unsafe { covio_handle_create(1, 0, 0, Some(capture_callback), context, &mut error) };
        assert!(!handle.is_null());
        assert_eq!(error.code, CovioStatusCode::Ok as u32);

        let request_bytes = request("request-1");
        let mut output = empty_bytes();
        assert_eq!(
            unsafe {
                covio_handle_dispatch(
                    handle,
                    request_bytes.as_ptr(),
                    request_bytes.len(),
                    50,
                    &mut output,
                    &mut error,
                )
            },
            CovioStatusCode::Ok as u32
        );
        assert_eq!(unsafe { covio_handle_active_request_count(handle) }, 1);
        unsafe { covio_owned_bytes_free(&mut output) };

        let snapshot_bytes = snapshot();
        assert_eq!(
            unsafe {
                covio_handle_dispatch(
                    handle,
                    snapshot_bytes.as_ptr(),
                    snapshot_bytes.len(),
                    50,
                    &mut output,
                    &mut error,
                )
            },
            CovioStatusCode::Ok as u32
        );
        assert_eq!(capture.messages.lock().unwrap().len(), 1);
        assert!(
            String::from_utf8(capture.messages.lock().unwrap()[0].clone())
                .unwrap()
                .contains("app.state")
        );
        unsafe { covio_owned_bytes_free(&mut output) };

        let request_id = b"request-1";
        assert_eq!(
            unsafe {
                covio_handle_cancel(
                    handle,
                    request_id.as_ptr(),
                    request_id.len(),
                    0,
                    50,
                    &mut error,
                )
            },
            CovioStatusCode::Ok as u32
        );
        assert_eq!(unsafe { covio_handle_active_request_count(handle) }, 0);

        assert_eq!(
            unsafe { covio_handle_shutdown(handle, true, false, 0, 50, &mut error) },
            CovioStatusCode::Ok as u32
        );
        assert_eq!(
            unsafe { covio_handle_lifecycle(handle) },
            CovioLifecycleWire::Stopped as u32
        );
        assert_eq!(
            unsafe {
                covio_handle_dispatch(
                    handle,
                    request_bytes.as_ptr(),
                    request_bytes.len(),
                    50,
                    &mut output,
                    &mut error,
                )
            },
            CovioStatusCode::ShuttingDown as u32
        );
        unsafe {
            covio_error_free(&mut error);
            covio_handle_release(handle);
        }
    }

    #[test]
    fn callback_panic_is_contained_and_payload_bound_is_enforced() {
        let mut error = empty_error();
        let handle = unsafe {
            covio_handle_create(1, 0, 16, Some(panic_callback), ptr::null_mut(), &mut error)
        };
        assert!(!handle.is_null());
        let oversized = [b'x'; 17];
        let mut output = empty_bytes();
        assert_eq!(
            unsafe {
                covio_handle_dispatch(
                    handle,
                    oversized.as_ptr(),
                    oversized.len(),
                    50,
                    &mut output,
                    &mut error,
                )
            },
            CovioStatusCode::PayloadTooLarge as u32
        );
        assert_eq!(error.code, CovioStatusCode::PayloadTooLarge as u32);
        unsafe {
            covio_error_free(&mut error);
            covio_handle_release(handle);
        }

        let mut normal_error = empty_error();
        let normal_handle = unsafe {
            covio_handle_create(
                1,
                0,
                0,
                Some(panic_callback),
                ptr::null_mut(),
                &mut normal_error,
            )
        };
        let snapshot_bytes = snapshot();
        assert_eq!(
            unsafe {
                covio_handle_dispatch(
                    normal_handle,
                    snapshot_bytes.as_ptr(),
                    snapshot_bytes.len(),
                    50,
                    &mut output,
                    &mut normal_error,
                )
            },
            CovioStatusCode::Ok as u32
        );
        unsafe {
            covio_owned_bytes_free(&mut output);
            covio_error_free(&mut normal_error);
            covio_handle_release(normal_handle);
        }
    }

    #[test]
    fn ffi_guard_turns_panics_into_a_typed_error() {
        let mut error = empty_error();
        let result: Result<(), CovioStatusCode> =
            ffi_guard(&mut error, || -> Result<(), FfiFailure> {
                panic!("boundary panic");
            });
        assert_eq!(result, Err(CovioStatusCode::Panic));
        assert_eq!(error.code, CovioStatusCode::Panic as u32);
        unsafe { covio_error_free(&mut error) };
    }

    #[test]
    fn capability_probe_does_not_claim_unwired_adapters() {
        let mut error = empty_error();
        assert_eq!(
            covio_capability_status(CapabilityKind::Filesystem as u32, &mut error),
            CovioStatusCode::Ok as u32
        );
        assert_eq!(
            covio_capability_status(CapabilityKind::Power as u32, &mut error),
            CovioStatusCode::Unsupported as u32
        );
        assert_eq!(
            covio_capability_status(99, &mut error),
            CovioStatusCode::InvalidArgument as u32
        );
        unsafe { covio_error_free(&mut error) };
    }

    #[test]
    fn agent_token_abi_rejects_other_namespaces() {
        let data_root = b"/tmp/covio-agent-token-test";
        let service = b"com.example.agent";
        let account = b"mcp-bearer-token";
        let mut error = empty_error();
        let mut output = empty_bytes();
        assert_eq!(
            unsafe {
                covio_agent_token_read(
                    data_root.as_ptr(),
                    data_root.len(),
                    service.as_ptr(),
                    service.len(),
                    account.as_ptr(),
                    account.len(),
                    &mut output,
                    &mut error,
                )
            },
            CovioStatusCode::InvalidArgument as u32
        );
        assert_eq!(
            unsafe {
                covio_agent_token_delete(
                    data_root.as_ptr(),
                    data_root.len(),
                    service.as_ptr(),
                    service.len(),
                    account.as_ptr(),
                    account.len(),
                    &mut error,
                )
            },
            CovioStatusCode::InvalidArgument as u32
        );
        let valid_service = b"com.wyz.covio.agent.ffi.test";
        let invalid_account = b"other-account";
        assert_eq!(
            unsafe {
                covio_agent_token_delete(
                    data_root.as_ptr(),
                    data_root.len(),
                    valid_service.as_ptr(),
                    valid_service.len(),
                    invalid_account.as_ptr(),
                    invalid_account.len(),
                    &mut error,
                )
            },
            CovioStatusCode::InvalidArgument as u32
        );
        unsafe { covio_error_free(&mut error) };
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn agent_token_wrappers_read_write_replace_and_delete() {
        use std::time::{SystemTime, UNIX_EPOCH};
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let data_root = std::env::temp_dir().join(format!(
            "covio-agent-token-ffi-{}-{nonce}",
            std::process::id()
        ));
        let data_root = data_root.to_string_lossy().into_owned();
        let service = format!(
            "com.wyz.covio.agent.ffi.test.{}.{nonce}",
            std::process::id()
        );
        let key = "mcp-bearer-token";
        let vault_service = format!(
            "com.wyz.covio.credentials.test.{}.{nonce}",
            std::process::id()
        );
        unsafe { std::env::set_var(AGENT_VAULT_SERVICE_ENV, vault_service) };
        let mut error = empty_error();
        unsafe {
            assert_eq!(
                covio_agent_token_delete(
                    data_root.as_ptr(),
                    data_root.len(),
                    service.as_ptr(),
                    service.len(),
                    key.as_ptr(),
                    key.len(),
                    &mut error,
                ),
                CovioStatusCode::Ok as u32
            );
            assert_eq!(
                covio_agent_token_write(
                    data_root.as_ptr(),
                    data_root.len(),
                    service.as_ptr(),
                    service.len(),
                    key.as_ptr(),
                    key.len(),
                    b"first".as_ptr(),
                    b"first".len(),
                    &mut error,
                ),
                CovioStatusCode::Ok as u32
            );
        }
        let mut value = empty_bytes();
        assert_eq!(
            unsafe {
                covio_agent_token_read(
                    data_root.as_ptr(),
                    data_root.len(),
                    service.as_ptr(),
                    service.len(),
                    key.as_ptr(),
                    key.len(),
                    &mut value,
                    &mut error,
                )
            },
            CovioStatusCode::Ok as u32
        );
        let first = unsafe { slice::from_raw_parts(value.data, value.len) }.to_vec();
        assert_eq!(first, b"first");
        unsafe { covio_owned_bytes_free(&mut value) };

        assert_eq!(
            unsafe {
                covio_agent_token_write(
                    data_root.as_ptr(),
                    data_root.len(),
                    service.as_ptr(),
                    service.len(),
                    key.as_ptr(),
                    key.len(),
                    b"second".as_ptr(),
                    b"second".len(),
                    &mut error,
                )
            },
            CovioStatusCode::Ok as u32
        );
        assert_eq!(
            unsafe {
                covio_agent_token_read(
                    data_root.as_ptr(),
                    data_root.len(),
                    service.as_ptr(),
                    service.len(),
                    key.as_ptr(),
                    key.len(),
                    &mut value,
                    &mut error,
                )
            },
            CovioStatusCode::Ok as u32
        );
        let second = unsafe { slice::from_raw_parts(value.data, value.len) }.to_vec();
        assert_eq!(second, b"second");
        unsafe { covio_owned_bytes_free(&mut value) };

        assert_eq!(
            unsafe {
                covio_agent_token_delete(
                    data_root.as_ptr(),
                    data_root.len(),
                    service.as_ptr(),
                    service.len(),
                    key.as_ptr(),
                    key.len(),
                    &mut error,
                )
            },
            CovioStatusCode::Ok as u32
        );
        assert_eq!(
            unsafe {
                covio_agent_token_read(
                    data_root.as_ptr(),
                    data_root.len(),
                    service.as_ptr(),
                    service.len(),
                    key.as_ptr(),
                    key.len(),
                    &mut value,
                    &mut error,
                )
            },
            CovioStatusCode::NotFound as u32
        );
        unsafe { covio_error_free(&mut error) };

        let vault_root = std::path::PathBuf::from(&data_root).join("credentials");
        let vault = covio_core::CredentialVault::open(
            &vault_root,
            covio_platform::KeychainSecretStore::new(agent_vault_service()),
            covio_platform::StdFileStore::new(),
        )
        .expect("open test vault");
        vault.destroy().expect("destroy test vault");
        let _ = std::fs::remove_dir_all(&data_root);
    }

    #[test]
    fn generated_bridge_contract_matches_ffi_types() {
        let contract: serde_json::Value =
            serde_json::from_str(include_str!("../bridge/bridge_contract.json"))
                .expect("bridge contract json");

        assert_eq!(
            contract["abiVersion"].as_u64(),
            Some(u64::from(ABI_VERSION))
        );
        assert_eq!(
            contract["protocolVersion"].as_u64(),
            Some(u64::from(PROTOCOL_VERSION))
        );
        assert_eq!(
            contract["defaultMaxControlBytes"].as_u64(),
            Some(DEFAULT_MAX_CONTROL_BYTES as u64)
        );
        assert_eq!(
            contract["contentTransport"].as_str(),
            Some("opaque_handle_or_stream")
        );

        let statuses = contract["statusCodes"]
            .as_array()
            .expect("status codes array");
        let expected_statuses = [
            ("Ok", CovioStatusCode::Ok as u32),
            ("InvalidArgument", CovioStatusCode::InvalidArgument as u32),
            ("InvalidUtf8", CovioStatusCode::InvalidUtf8 as u32),
            ("PayloadTooLarge", CovioStatusCode::PayloadTooLarge as u32),
            ("MalformedMessage", CovioStatusCode::MalformedMessage as u32),
            ("ProtocolVersion", CovioStatusCode::ProtocolVersion as u32),
            ("StaleGeneration", CovioStatusCode::StaleGeneration as u32),
            ("StaleRevision", CovioStatusCode::StaleRevision as u32),
            ("InvalidRevision", CovioStatusCode::InvalidRevision as u32),
            ("DeadlineExceeded", CovioStatusCode::DeadlineExceeded as u32),
            ("Cancelled", CovioStatusCode::Cancelled as u32),
            ("ShuttingDown", CovioStatusCode::ShuttingDown as u32),
            ("Unsupported", CovioStatusCode::Unsupported as u32),
            ("NotFound", CovioStatusCode::NotFound as u32),
            ("Conflict", CovioStatusCode::Conflict as u32),
            ("Io", CovioStatusCode::Io as u32),
            ("Internal", CovioStatusCode::Internal as u32),
            ("Panic", CovioStatusCode::Panic as u32),
        ];
        assert_eq!(statuses.len(), expected_statuses.len());
        for (name, value) in expected_statuses {
            let entry = statuses
                .iter()
                .find(|entry| entry["name"] == name)
                .expect("status code entry");
            assert_eq!(entry["value"].as_u64(), Some(u64::from(value)), "{name}");
        }

        let lifecycle = contract["lifecycle"].as_array().expect("lifecycle array");
        let expected_lifecycle = [
            ("Running", CovioLifecycleWire::Running as u32),
            ("Draining", CovioLifecycleWire::Draining as u32),
            ("Stopped", CovioLifecycleWire::Stopped as u32),
        ];
        assert_eq!(lifecycle.len(), expected_lifecycle.len());
        for (name, value) in expected_lifecycle {
            let entry = lifecycle
                .iter()
                .find(|entry| entry["name"] == name)
                .expect("lifecycle entry");
            assert_eq!(entry["value"].as_u64(), Some(u64::from(value)), "{name}");
        }

        let cancel_reasons = contract["cancelReasons"]
            .as_array()
            .expect("cancel reasons array");
        let expected_cancel_reasons = [("Host", 0_u64), ("Deadline", 1), ("Shutdown", 2)];
        assert_eq!(cancel_reasons.len(), expected_cancel_reasons.len());
        for (name, value) in expected_cancel_reasons {
            let entry = cancel_reasons
                .iter()
                .find(|entry| entry["name"] == name)
                .expect("cancel reason entry");
            assert_eq!(entry["value"].as_u64(), Some(value), "{name}");
        }

        let jni_functions = contract["jniFunctions"]
            .as_array()
            .expect("JNI functions array");
        assert!(
            jni_functions
                .iter()
                .any(|entry| { entry["name"] == "covio_jni_handle_dispatch" })
        );
    }
}

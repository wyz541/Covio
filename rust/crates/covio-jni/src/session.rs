//! Stateful JNI session and bounded event queue.

use crate::commands::{CommandContext, CommandError, ComposeConfig, ComposeCore};
use covio_bridge::{BridgeLifecycle, RequestEnvelope};
use covio_bridge::{
    BridgeLimits, BridgeMessage, CancelReason, EventEnvelope, EventName, ResponseEnvelope,
    ResponseResult, ShutdownMode, WireError, WireErrorCode, decode_message, encode_message,
};
use covio_core::{Generation, Revision};
use covio_ffi::{BridgeSession, CovioStatusCode, FfiFailure};
use serde_json::{Value, json};
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;
#[cfg(test)]
use std::time::{SystemTime, UNIX_EPOCH};

const MAX_EVENT_COUNT: usize = 256;

/// One JNI session failure.
#[derive(Debug, Clone)]
pub struct SessionError {
    /// Stable status code shared with the C ABI.
    pub status: u32,
    /// Public diagnostic message.
    pub message: String,
}

impl SessionError {
    fn new(status: CovioStatusCode, message: impl Into<String>) -> Self {
        Self {
            status: status as u32,
            message: message.into(),
        }
    }

    fn invalid(message: impl Into<String>) -> Self {
        Self::new(CovioStatusCode::InvalidArgument, message)
    }

    fn shutting_down() -> Self {
        Self::new(CovioStatusCode::ShuttingDown, "session is shutting down")
    }

    fn internal(message: impl Into<String>) -> Self {
        Self::new(CovioStatusCode::Internal, message)
    }
}

impl From<FfiFailure> for SessionError {
    fn from(error: FfiFailure) -> Self {
        Self {
            status: error.status as u32,
            message: error.message,
        }
    }
}

impl From<CommandError> for SessionError {
    fn from(error: CommandError) -> Self {
        Self {
            status: status_from_wire(error.code),
            message: error.message,
        }
    }
}

impl From<WireError> for SessionError {
    fn from(error: WireError) -> Self {
        Self {
            status: status_from_wire(error.code),
            message: error.message,
        }
    }
}

struct EventRecord {
    bytes: Vec<u8>,
    terminal: bool,
}

struct EventState {
    events: VecDeque<EventRecord>,
    closed: bool,
}

struct EventBus {
    state: Mutex<EventState>,
    ready: Condvar,
}

impl EventBus {
    fn new() -> Self {
        Self {
            state: Mutex::new(EventState {
                events: VecDeque::new(),
                closed: false,
            }),
            ready: Condvar::new(),
        }
    }

    fn push<F>(
        &self,
        bytes: Vec<u8>,
        terminal: bool,
        snapshot_required: F,
    ) -> Result<(), SessionError>
    where
        F: FnOnce() -> Result<Vec<u8>, SessionError>,
    {
        let mut state = self
            .state
            .lock()
            .map_err(|_| SessionError::internal("event lock failed"))?;
        if state.closed {
            return Err(SessionError::shutting_down());
        }
        let notice = if state.events.len() >= MAX_EVENT_COUNT {
            let drop_count = state
                .events
                .len()
                .saturating_sub(MAX_EVENT_COUNT.saturating_sub(2));
            let non_terminal_count = state.events.iter().filter(|event| !event.terminal).count();
            if non_terminal_count < drop_count {
                return Err(SessionError::internal(
                    "event queue has no room for terminal events",
                ));
            }
            let notice = snapshot_required()?;
            for _ in 0..drop_count {
                let drop_index = state
                    .events
                    .iter()
                    .position(|event| !event.terminal)
                    .ok_or_else(|| {
                        SessionError::internal("event queue has no droppable progress event")
                    })?;
                state.events.remove(drop_index);
            }
            Some(notice)
        } else {
            None
        };
        if let Some(notice) = notice {
            state.events.push_front(EventRecord {
                bytes: notice,
                terminal: false,
            });
        }
        state.events.push_back(EventRecord { bytes, terminal });
        self.ready.notify_all();
        Ok(())
    }

    fn next(&self, timeout_ms: u32) -> Result<Option<Vec<u8>>, SessionError> {
        let mut state = self
            .state
            .lock()
            .map_err(|_| SessionError::internal("event lock failed"))?;
        if state.events.is_empty() && !state.closed && timeout_ms > 0 {
            let (next, _) = self
                .ready
                .wait_timeout(state, Duration::from_millis(u64::from(timeout_ms)))
                .map_err(|_| SessionError::internal("event lock failed"))?;
            state = next;
        }
        if let Some(event) = state.events.pop_front() {
            Ok(Some(event.bytes))
        } else if state.closed {
            Err(SessionError::shutting_down())
        } else {
            Ok(None)
        }
    }

    fn close(&self) {
        if let Ok(mut state) = self.state.lock() {
            state.closed = true;
            self.ready.notify_all();
        }
    }
}

struct BridgeState {
    bridge: BridgeSession,
    configured: bool,
}

/// One JNI bridge session.
pub struct JniSession {
    bridge: Mutex<BridgeState>,
    core: Mutex<Option<ComposeCore>>,
    cancellations: Mutex<HashMap<String, Arc<AtomicBool>>>,
    events: Arc<EventBus>,
}

impl JniSession {
    /// Creates a running session.
    pub fn new(generation: u64, revision: u64, max_control_bytes: u32) -> Self {
        let limits = BridgeLimits {
            max_control_bytes: max_control_bytes as usize,
            ..BridgeLimits::default()
        };
        let bridge =
            BridgeSession::new(Generation::new(generation), Revision::new(revision), limits);
        Self {
            bridge: Mutex::new(BridgeState {
                bridge,
                configured: false,
            }),
            core: Mutex::new(None),
            cancellations: Mutex::new(HashMap::new()),
            events: Arc::new(EventBus::new()),
        }
    }

    /// Configures the application data root and host facts.
    pub fn configure(&self, config_json: &[u8]) -> Result<(), SessionError> {
        if config_json.is_empty() {
            return Err(SessionError::invalid("session configuration is empty"));
        }
        let value: Value = serde_json::from_slice(config_json)
            .map_err(|_| SessionError::invalid("session configuration is not valid JSON"))?;
        let config = ComposeConfig::from_json(&value).map_err(SessionError::from)?;
        let core = ComposeCore::open(config).map_err(SessionError::from)?;
        {
            let mut state = self
                .bridge
                .lock()
                .map_err(|_| SessionError::internal("bridge lock failed"))?;
            if state.bridge.lifecycle() == BridgeLifecycle::Stopped {
                return Err(SessionError::shutting_down());
            }
            state.configured = true;
        }
        *self
            .core
            .lock()
            .map_err(|_| SessionError::internal("core lock failed"))? = Some(core);
        self.emit("session.ready", json!({"configured": true}), false)
    }

    /// Validates and executes one bridge control message.
    pub fn dispatch(&self, message: &[u8], now_unix_millis: u64) -> Result<Vec<u8>, SessionError> {
        let (validated, decoded) = {
            let mut state = self
                .bridge
                .lock()
                .map_err(|_| SessionError::internal("bridge lock failed"))?;
            if !state.configured {
                return Err(SessionError::new(
                    CovioStatusCode::Conflict,
                    "session is not configured",
                ));
            }
            let result = state
                .bridge
                .dispatch(message, now_unix_millis)
                .map_err(SessionError::from)?;
            let decoded =
                decode_message(message, state.bridge.limits()).map_err(SessionError::from)?;
            (result.message, decoded)
        };

        match decoded {
            BridgeMessage::Request(request) => self.execute_request(request, now_unix_millis),
            _ => Ok(validated),
        }
    }

    fn execute_request(
        &self,
        request: RequestEnvelope,
        now_unix_millis: u64,
    ) -> Result<Vec<u8>, SessionError> {
        let request_id = request.request_id.as_str().to_owned();
        let cancelled = Arc::new(AtomicBool::new(false));
        self.cancellations
            .lock()
            .map_err(|_| SessionError::internal("cancellation lock failed"))?
            .insert(request_id.clone(), Arc::clone(&cancelled));
        self.emit(
            "request.started",
            json!({"request_id": request_id, "command": request.command.as_str()}),
            false,
        )?;

        let (generation, revision, limits) = {
            let state = self
                .bridge
                .lock()
                .map_err(|_| SessionError::internal("bridge lock failed"))?;
            (
                state.bridge.generation(),
                state.bridge.revision(),
                state.bridge.limits(),
            )
        };
        let emit = |name: &str, payload: Value| {
            self.emit(name, payload, false).map_err(|error| {
                CommandError::new(wire_from_status(error.status), error.message, false)
            })
        };
        let context = CommandContext {
            now_ms: i64::try_from(now_unix_millis).unwrap_or(i64::MAX),
            deadline_ms: request.deadline.map(|deadline| deadline.as_unix_millis()),
            cancelled: &cancelled,
            emit: &emit,
        };
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let core = self
                .core
                .lock()
                .map_err(|_| SessionError::internal("core lock failed"))?;
            let core = core.as_ref().ok_or_else(|| {
                SessionError::new(CovioStatusCode::Conflict, "session is not configured")
            })?;
            core.call(request.command.as_str(), &request.payload, &context)
                .map_err(SessionError::from)
        }))
        .unwrap_or_else(|_| {
            Err(SessionError::new(
                CovioStatusCode::Panic,
                "native command panicked",
            ))
        });

        self.cancellations
            .lock()
            .map_err(|_| SessionError::internal("cancellation lock failed"))?
            .remove(&request_id);

        let response = ResponseEnvelope {
            protocol_version: covio_bridge::PROTOCOL_VERSION,
            request_id: request.request_id.clone(),
            generation,
            revision: None,
            result: match &result {
                Ok(value) => ResponseResult::Ok(value.clone()),
                Err(error) => ResponseResult::Error(WireError::new(
                    wire_from_status(error.status),
                    error.message.clone(),
                    error.status == CovioStatusCode::DeadlineExceeded as u32
                        || error.status == CovioStatusCode::Io as u32,
                )),
            },
        };
        let response_message = encode_message(&BridgeMessage::Response(response), limits)
            .map_err(SessionError::from)?;
        {
            let mut state = self
                .bridge
                .lock()
                .map_err(|_| SessionError::internal("bridge lock failed"))?;
            state
                .bridge
                .dispatch(&response_message, now_unix_millis)
                .map_err(SessionError::from)?;
        }
        let event_payload = match &result {
            Ok(value) => json!({
                "request_id": request_id,
                "status": "ok",
                "payload": value,
            }),
            Err(error) => json!({
                "request_id": request_id,
                "status": "error",
                "error": {
                    "code": error.status,
                    "message": error.message,
                },
            }),
        };
        self.emit("request.completed", event_payload, true)?;
        if result.is_err() {
            // The response envelope carries the typed error. The native call
            // itself succeeded once the request reached the business layer.
        }
        let _ = (revision, generation);
        Ok(response_message)
    }

    /// Cancels one active request.
    pub fn cancel(
        &self,
        request_id: &str,
        reason: u32,
        now_unix_millis: u64,
    ) -> Result<(), SessionError> {
        let reason = match reason {
            0 => CancelReason::Host,
            1 => CancelReason::Deadline,
            2 => CancelReason::Shutdown,
            _ => return Err(SessionError::invalid("cancel reason is invalid")),
        };
        if let Some(flag) = self
            .cancellations
            .lock()
            .map_err(|_| SessionError::internal("cancellation lock failed"))?
            .get(request_id)
        {
            flag.store(true, Ordering::Release);
        }
        let mut state = self
            .bridge
            .lock()
            .map_err(|_| SessionError::internal("bridge lock failed"))?;
        state
            .bridge
            .cancel(request_id, reason, now_unix_millis)
            .map_err(SessionError::from)?;
        drop(state);
        self.emit(
            "request.cancelled",
            json!({"request_id": request_id, "reason": reason}),
            false,
        )
    }

    /// Shuts down the bridge session.
    pub fn shutdown(
        &self,
        immediate: bool,
        has_deadline: bool,
        deadline_unix_millis: u64,
        now_unix_millis: u64,
    ) -> Result<(), SessionError> {
        let mode = if immediate {
            ShutdownMode::Immediate
        } else {
            ShutdownMode::Graceful
        };
        let deadline =
            has_deadline.then(|| covio_core::Deadline::from_unix_millis(deadline_unix_millis));
        {
            let mut state = self
                .bridge
                .lock()
                .map_err(|_| SessionError::internal("bridge lock failed"))?;
            state
                .bridge
                .shutdown(mode, deadline, now_unix_millis)
                .map_err(SessionError::from)?;
        }
        if immediate {
            for flag in self
                .cancellations
                .lock()
                .map_err(|_| SessionError::internal("cancellation lock failed"))?
                .values()
            {
                flag.store(true, Ordering::Release);
            }
        }
        self.emit(
            "session.shutdown",
            json!({"mode": if immediate { "immediate" } else { "graceful" }}),
            true,
        )
    }

    /// Reads the next event, blocking up to `timeout_ms`.
    pub fn next_event(&self, timeout_ms: u32) -> Result<Option<Vec<u8>>, SessionError> {
        self.events.next(timeout_ms)
    }

    /// Returns the wire lifecycle value.
    pub fn lifecycle(&self) -> Result<u32, SessionError> {
        let state = self
            .bridge
            .lock()
            .map_err(|_| SessionError::internal("bridge lock failed"))?;
        Ok(match state.bridge.lifecycle() {
            BridgeLifecycle::Running => 0,
            BridgeLifecycle::Draining => 1,
            BridgeLifecycle::Stopped => 2,
        })
    }

    /// Returns the current active-request count.
    pub fn active_request_count(&self) -> Result<u64, SessionError> {
        let state = self
            .bridge
            .lock()
            .map_err(|_| SessionError::internal("bridge lock failed"))?;
        Ok(state.bridge.active_request_count() as u64)
    }

    /// Closes the session and releases waiting event readers.
    pub fn close(&self) {
        for flag in self
            .cancellations
            .lock()
            .map(|state| state.values().cloned().collect::<Vec<_>>())
            .unwrap_or_default()
        {
            flag.store(true, Ordering::Release);
        }
        self.events.close();
    }

    fn emit(&self, name: &str, payload: Value, terminal: bool) -> Result<(), SessionError> {
        let (generation, revision, limits) = {
            let state = self
                .bridge
                .lock()
                .map_err(|_| SessionError::internal("bridge lock failed"))?;
            (
                state.bridge.generation(),
                state.bridge.revision(),
                state.bridge.limits(),
            )
        };
        let event = EventEnvelope {
            protocol_version: covio_bridge::PROTOCOL_VERSION,
            generation,
            revision,
            event: EventName::try_new(name).map_err(SessionError::from)?,
            payload,
        };
        let bytes =
            encode_message(&BridgeMessage::Event(event), limits).map_err(SessionError::from)?;
        self.events.push(bytes, terminal, || {
            let event = EventEnvelope {
                protocol_version: covio_bridge::PROTOCOL_VERSION,
                generation,
                revision,
                event: EventName::try_new("snapshot_required").map_err(SessionError::from)?,
                payload: json!({"reason": "event_queue_overflow"}),
            };
            encode_message(&BridgeMessage::Event(event), limits).map_err(SessionError::from)
        })
    }
}

#[cfg(test)]
fn now_unix_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| u64::try_from(duration.as_millis()).unwrap_or(u64::MAX))
        .unwrap_or(0)
}

fn status_from_wire(code: WireErrorCode) -> u32 {
    match code {
        WireErrorCode::ProtocolVersion => CovioStatusCode::ProtocolVersion as u32,
        WireErrorCode::PayloadTooLarge => CovioStatusCode::PayloadTooLarge as u32,
        WireErrorCode::MalformedMessage => CovioStatusCode::MalformedMessage as u32,
        WireErrorCode::InvalidRequestId
        | WireErrorCode::InvalidCommand
        | WireErrorCode::InvalidEvent
        | WireErrorCode::InvalidSnapshot
        | WireErrorCode::InvalidArgument => CovioStatusCode::InvalidArgument as u32,
        WireErrorCode::StaleGeneration => CovioStatusCode::StaleGeneration as u32,
        WireErrorCode::StaleRevision => CovioStatusCode::StaleRevision as u32,
        WireErrorCode::InvalidRevision => CovioStatusCode::InvalidRevision as u32,
        WireErrorCode::DeadlineExceeded => CovioStatusCode::DeadlineExceeded as u32,
        WireErrorCode::Cancelled => CovioStatusCode::Cancelled as u32,
        WireErrorCode::ShuttingDown => CovioStatusCode::ShuttingDown as u32,
        WireErrorCode::Unsupported => CovioStatusCode::Unsupported as u32,
        WireErrorCode::NotFound => CovioStatusCode::NotFound as u32,
        WireErrorCode::Conflict => CovioStatusCode::Conflict as u32,
        WireErrorCode::Io => CovioStatusCode::Io as u32,
        WireErrorCode::Internal => CovioStatusCode::Internal as u32,
    }
}

fn wire_from_status(status: u32) -> WireErrorCode {
    match status {
        1 | 2 | 4 => WireErrorCode::InvalidArgument,
        3 => WireErrorCode::PayloadTooLarge,
        5 => WireErrorCode::ProtocolVersion,
        6 => WireErrorCode::StaleGeneration,
        7 => WireErrorCode::StaleRevision,
        8 => WireErrorCode::InvalidRevision,
        9 => WireErrorCode::DeadlineExceeded,
        10 => WireErrorCode::Cancelled,
        11 => WireErrorCode::ShuttingDown,
        12 => WireErrorCode::Unsupported,
        13 => WireErrorCode::NotFound,
        14 => WireErrorCode::Conflict,
        15 => WireErrorCode::Io,
        _ => WireErrorCode::Internal,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::thread;

    fn configured_session() -> JniSession {
        let session = JniSession::new(1, 0, 1024 * 1024);
        let root = std::env::temp_dir().join(format!(
            "covio-jni-session-{}-{}",
            std::process::id(),
            uuid::Uuid::new_v4().simple()
        ));
        let config = serde_json::to_vec(&json!({
            "dataRoot": root.to_string_lossy(),
            "displayName": "Test compose host",
            "systemName": "Windows 11",
            "systemVersion": "10.0.26100",
            "appVersion": "0.1.0",
            "hostAdapters": ["file_picker", "notification", "background_task", "app_lifecycle"]
        }))
        .expect("config");
        session.configure(&config).expect("configure");
        session
    }

    fn request(id: &str, command: &str, payload: Value) -> Vec<u8> {
        serde_json::to_vec(&json!({
            "kind": "request",
            "body": {
                "protocol_version": 1,
                "request_id": id,
                "generation": 1,
                "command": command,
                "deadline": null,
                "payload": payload
            }
        }))
        .expect("request")
    }

    #[test]
    fn request_and_event_round_trip() {
        let session = configured_session();
        let response = session
            .dispatch(
                &request("req-1", "diagnostics.echo", json!({"value": 7})),
                now_unix_millis(),
            )
            .expect("dispatch");
        let decoded = decode_message(&response, BridgeLimits::default()).expect("response");
        assert!(matches!(decoded, BridgeMessage::Response(_)));
        let event = session.next_event(0).expect("event").expect("queued event");
        let decoded = decode_message(&event, BridgeLimits::default()).expect("event");
        assert!(matches!(decoded, BridgeMessage::Event(_)));
    }

    #[test]
    fn error_and_shutdown_round_trip() {
        let session = configured_session();
        let error = session
            .dispatch(b"not-json", now_unix_millis())
            .expect_err("malformed input");
        assert_eq!(error.status, CovioStatusCode::MalformedMessage as u32);
        session
            .shutdown(true, false, 0, now_unix_millis())
            .expect("shutdown");
        assert_eq!(session.lifecycle().expect("lifecycle"), 2);
        let error = session
            .dispatch(
                &request("req-2", "diagnostics.echo", json!({})),
                now_unix_millis(),
            )
            .expect_err("stopped");
        assert_eq!(error.status, CovioStatusCode::ShuttingDown as u32);
    }

    #[test]
    fn event_overflow_emits_snapshot_required_and_preserves_terminal_events() {
        let session = configured_session();
        session
            .next_event(0)
            .expect("ready event")
            .expect("ready event");

        for index in 0..MAX_EVENT_COUNT - 1 {
            session
                .emit("test.progress", json!({"index": index}), false)
                .expect("progress event");
        }
        session
            .emit("test.terminal", json!({}), true)
            .expect("terminal event");
        session
            .emit("test.progress", json!({"index": MAX_EVENT_COUNT}), false)
            .expect("overflow event");

        let mut names = Vec::new();
        for _ in 0..MAX_EVENT_COUNT {
            let bytes = session
                .next_event(0)
                .expect("queued event")
                .expect("queued event");
            let BridgeMessage::Event(event) =
                decode_message(&bytes, BridgeLimits::default()).expect("event")
            else {
                panic!("expected event");
            };
            names.push(event.event.as_str().to_owned());
        }

        assert_eq!(names.first().map(String::as_str), Some("snapshot_required"));
        assert!(names.iter().any(|name| name == "test.terminal"));
        assert_eq!(names.len(), MAX_EVENT_COUNT);
        assert!(session.next_event(0).expect("empty queue").is_none());
    }

    #[test]
    fn cancellation_stops_a_wait_request() {
        let session = Arc::new(configured_session());
        let request_bytes = request(
            "req-cancel",
            "diagnostics.wait",
            json!({"milliseconds": 2000}),
        );
        let worker = {
            let session = Arc::clone(&session);
            thread::spawn(move || {
                session
                    .dispatch(&request_bytes, now_unix_millis())
                    .expect("dispatch")
            })
        };
        thread::sleep(Duration::from_millis(50));
        session
            .cancel("req-cancel", 0, now_unix_millis())
            .expect("cancel");
        let response = worker.join().expect("worker");
        let decoded = decode_message(&response, BridgeLimits::default()).expect("response");
        let BridgeMessage::Response(response) = decoded else {
            panic!("response");
        };
        assert!(matches!(
            response.result,
            ResponseResult::Error(WireError {
                code: WireErrorCode::Cancelled,
                ..
            })
        ));
    }
}

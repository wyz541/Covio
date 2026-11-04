//! Versioned control protocol between the Covio Rust core and platform hosts.
//!
//! The bridge transports bounded commands, responses, events, snapshots,
//! cancellation, and shutdown messages. Business payloads remain opaque here.

#![forbid(unsafe_code)]

use covio_core::{CoreError, CoreErrorCode, Deadline, Generation, RequestId, Revision};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::error::Error;
use std::fmt;

/// Current bridge protocol version.
pub const PROTOCOL_VERSION: u16 = 1;

/// Default maximum size of one serialized control message.
pub const DEFAULT_MAX_CONTROL_BYTES: usize = 1024 * 1024;

/// Default maximum size of a request, event, or snapshot name.
pub const DEFAULT_MAX_NAME_BYTES: usize = 96;

/// Default maximum size of a public error message.
pub const DEFAULT_MAX_ERROR_MESSAGE_BYTES: usize = 512;

/// Limits applied at the bridge boundary.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeLimits {
    /// Maximum serialized control-message bytes.
    pub max_control_bytes: usize,
    /// Maximum name bytes.
    pub max_name_bytes: usize,
    /// Maximum public error-message bytes.
    pub max_error_message_bytes: usize,
}

impl Default for BridgeLimits {
    fn default() -> Self {
        Self {
            max_control_bytes: DEFAULT_MAX_CONTROL_BYTES,
            max_name_bytes: DEFAULT_MAX_NAME_BYTES,
            max_error_message_bytes: DEFAULT_MAX_ERROR_MESSAGE_BYTES,
        }
    }
}

/// The lifecycle state of one bridge session.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum BridgeLifecycle {
    /// New commands are accepted.
    #[default]
    Running,
    /// The session drains active work and rejects new commands.
    Draining,
    /// The session is stopped.
    Stopped,
}

/// A validated command name.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct CommandName(String);

impl CommandName {
    /// Creates a command name after checking the default name rules.
    pub fn try_new(value: impl Into<String>) -> Result<Self, WireError> {
        let value = value.into();
        validate_control_name(
            &value,
            DEFAULT_MAX_NAME_BYTES,
            WireErrorCode::InvalidCommand,
        )?;
        Ok(Self(value))
    }

    /// Returns the command name.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// A validated event name.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct EventName(String);

impl EventName {
    /// Creates an event name after checking the default name rules.
    pub fn try_new(value: impl Into<String>) -> Result<Self, WireError> {
        let value = value.into();
        validate_control_name(&value, DEFAULT_MAX_NAME_BYTES, WireErrorCode::InvalidEvent)?;
        Ok(Self(value))
    }

    /// Returns the event name.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// A validated snapshot name.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct SnapshotName(String);

impl SnapshotName {
    /// Creates a snapshot name after checking the default name rules.
    pub fn try_new(value: impl Into<String>) -> Result<Self, WireError> {
        let value = value.into();
        validate_control_name(
            &value,
            DEFAULT_MAX_NAME_BYTES,
            WireErrorCode::InvalidSnapshot,
        )?;
        Ok(Self(value))
    }

    /// Returns the snapshot name.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// A top-level bridge message.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "body", rename_all = "snake_case")]
pub enum BridgeMessage {
    /// A host command.
    Request(RequestEnvelope),
    /// A completed command.
    Response(ResponseEnvelope),
    /// A core event.
    Event(EventEnvelope),
    /// A core snapshot.
    Snapshot(SnapshotEnvelope),
    /// A request cancellation.
    Cancel(CancelEnvelope),
    /// A session shutdown.
    Shutdown(ShutdownEnvelope),
}

/// A host command envelope.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RequestEnvelope {
    /// Protocol version.
    pub protocol_version: u16,
    /// Request identifier.
    pub request_id: RequestId,
    /// Generation observed by the host.
    pub generation: Generation,
    /// Command name.
    pub command: CommandName,
    /// Absolute deadline in Unix milliseconds.
    pub deadline: Option<Deadline>,
    /// Opaque business payload.
    pub payload: Value,
}

/// The result of one command.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "status", content = "data", rename_all = "snake_case")]
pub enum ResponseResult {
    /// A successful response payload.
    Ok(Value),
    /// A typed public error.
    Error(WireError),
}

/// A completed command envelope.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResponseEnvelope {
    /// Protocol version.
    pub protocol_version: u16,
    /// Request identifier from the command.
    pub request_id: RequestId,
    /// Generation observed by the core.
    pub generation: Generation,
    /// Revision after the command, when the command changed state.
    pub revision: Option<Revision>,
    /// Command result.
    pub result: ResponseResult,
}

/// A core event envelope.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EventEnvelope {
    /// Protocol version.
    pub protocol_version: u16,
    /// Generation observed by the core.
    pub generation: Generation,
    /// Revision observed by the core.
    pub revision: Revision,
    /// Event name.
    pub event: EventName,
    /// Opaque event payload.
    pub payload: Value,
}

/// A complete or incremental core snapshot.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SnapshotEnvelope {
    /// Protocol version.
    pub protocol_version: u16,
    /// Generation observed by the core.
    pub generation: Generation,
    /// Snapshot revision.
    pub revision: Revision,
    /// Snapshot name.
    pub snapshot: SnapshotName,
    /// Opaque snapshot payload.
    pub payload: Value,
}

/// Why a request was cancelled.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CancelReason {
    /// The platform host cancelled the request.
    Host,
    /// The request deadline expired.
    Deadline,
    /// The session is shutting down.
    Shutdown,
}

/// A request cancellation envelope.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CancelEnvelope {
    /// Protocol version.
    pub protocol_version: u16,
    /// Generation observed by the host.
    pub generation: Generation,
    /// Request identifier to cancel.
    pub request_id: RequestId,
    /// Cancellation cause.
    pub reason: CancelReason,
}

/// Shutdown behavior.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShutdownMode {
    /// Stop accepting new work, drain active work, then stop.
    Graceful,
    /// Stop accepting new work and cancel active work as soon as possible.
    Immediate,
}

/// A session shutdown envelope.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ShutdownEnvelope {
    /// Protocol version.
    pub protocol_version: u16,
    /// Generation observed by the host.
    pub generation: Generation,
    /// Shutdown behavior.
    pub mode: ShutdownMode,
    /// Optional shutdown deadline.
    pub deadline: Option<Deadline>,
}

/// Stable public bridge and core error categories.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WireErrorCode {
    /// The protocol version is unsupported.
    ProtocolVersion,
    /// The serialized message exceeds the configured limit.
    PayloadTooLarge,
    /// The serialized message is malformed.
    MalformedMessage,
    /// The request identifier is invalid.
    InvalidRequestId,
    /// The command name is invalid.
    InvalidCommand,
    /// The event name is invalid.
    InvalidEvent,
    /// The snapshot name is invalid.
    InvalidSnapshot,
    /// The request used an outdated generation.
    StaleGeneration,
    /// The message used an outdated revision.
    StaleRevision,
    /// The revision is invalid for this message.
    InvalidRevision,
    /// The deadline has expired or is invalid.
    DeadlineExceeded,
    /// The operation was cancelled.
    Cancelled,
    /// The session rejects new work while draining or stopped.
    ShuttingDown,
    /// The operation is unsupported.
    Unsupported,
    /// The requested object does not exist.
    NotFound,
    /// The operation conflicts with current state.
    Conflict,
    /// The caller supplied invalid input.
    InvalidArgument,
    /// A platform capability failed.
    Io,
    /// An unexpected internal failure occurred.
    Internal,
}

/// A typed public error safe to cross the bridge.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WireError {
    /// Stable error category.
    pub code: WireErrorCode,
    /// Public message. It must not contain secrets or user content.
    pub message: String,
    /// Whether the caller may retry.
    pub retryable: bool,
}

impl WireError {
    /// Creates a public bridge error.
    #[must_use]
    pub fn new(code: WireErrorCode, message: impl Into<String>, retryable: bool) -> Self {
        Self {
            code,
            message: message.into(),
            retryable,
        }
    }

    /// Creates a protocol-version error.
    #[must_use]
    pub fn protocol_version() -> Self {
        Self::new(
            WireErrorCode::ProtocolVersion,
            "unsupported bridge protocol version",
            false,
        )
    }

    /// Creates a payload-size error.
    #[must_use]
    pub fn payload_too_large() -> Self {
        Self::new(
            WireErrorCode::PayloadTooLarge,
            "bridge payload exceeds the configured limit",
            false,
        )
    }

    /// Creates a malformed-message error.
    #[must_use]
    pub fn malformed_message() -> Self {
        Self::new(
            WireErrorCode::MalformedMessage,
            "bridge message is malformed",
            false,
        )
    }

    /// Creates a stale-generation error.
    #[must_use]
    pub fn stale_generation() -> Self {
        Self::new(
            WireErrorCode::StaleGeneration,
            "bridge generation is stale",
            true,
        )
    }
}

impl From<&CoreError> for WireError {
    fn from(error: &CoreError) -> Self {
        let code = match error.code() {
            CoreErrorCode::InvalidArgument => WireErrorCode::InvalidArgument,
            CoreErrorCode::NotFound => WireErrorCode::NotFound,
            CoreErrorCode::Conflict => WireErrorCode::Conflict,
            CoreErrorCode::Unsupported => WireErrorCode::Unsupported,
            CoreErrorCode::StaleGeneration => WireErrorCode::StaleGeneration,
            CoreErrorCode::StaleRevision => WireErrorCode::StaleRevision,
            CoreErrorCode::Cancelled => WireErrorCode::Cancelled,
            CoreErrorCode::DeadlineExceeded => WireErrorCode::DeadlineExceeded,
            CoreErrorCode::ShuttingDown => WireErrorCode::ShuttingDown,
            CoreErrorCode::Io => WireErrorCode::Io,
            CoreErrorCode::Internal => WireErrorCode::Internal,
        };
        Self::new(code, public_message(code), error.retryable())
    }
}

impl From<CoreError> for WireError {
    fn from(error: CoreError) -> Self {
        Self::from(&error)
    }
}

impl fmt::Display for WireError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for WireError {}

/// Semantic validation for one bridge session snapshot.
#[derive(Debug, Clone, Copy)]
pub struct BridgeValidator {
    limits: BridgeLimits,
    protocol_version: u16,
    generation: Generation,
    revision: Revision,
    lifecycle: BridgeLifecycle,
}

impl Default for BridgeValidator {
    fn default() -> Self {
        Self::new(
            Generation::INITIAL,
            Revision::INITIAL,
            BridgeLifecycle::Running,
            BridgeLimits::default(),
        )
    }
}

impl BridgeValidator {
    /// Creates a validator for the current session state.
    #[must_use]
    pub const fn new(
        generation: Generation,
        revision: Revision,
        lifecycle: BridgeLifecycle,
        limits: BridgeLimits,
    ) -> Self {
        Self {
            limits,
            protocol_version: PROTOCOL_VERSION,
            generation,
            revision,
            lifecycle,
        }
    }

    /// Validates one decoded message at a known time.
    pub fn validate_message(
        &self,
        message: &BridgeMessage,
        now_unix_millis: u64,
    ) -> Result<(), WireError> {
        match message {
            BridgeMessage::Request(request) => self.validate_request(request, now_unix_millis),
            BridgeMessage::Response(response) => self.validate_response(response),
            BridgeMessage::Event(event) => self.validate_event(event),
            BridgeMessage::Snapshot(snapshot) => self.validate_snapshot(snapshot),
            BridgeMessage::Cancel(cancel) => self.validate_cancel(cancel),
            BridgeMessage::Shutdown(shutdown) => self.validate_shutdown(shutdown, now_unix_millis),
        }
    }

    /// Validates a command envelope.
    pub fn validate_request(
        &self,
        request: &RequestEnvelope,
        now_unix_millis: u64,
    ) -> Result<(), WireError> {
        self.require_running()?;
        self.validate_version(request.protocol_version)?;
        self.validate_generation(request.generation)?;
        self.validate_request_id(&request.request_id)?;
        validate_control_name(
            request.command.as_str(),
            self.limits.max_name_bytes,
            WireErrorCode::InvalidCommand,
        )?;
        self.validate_payload(&request.payload)?;
        self.validate_deadline(request.deadline, now_unix_millis)
    }

    /// Validates a response envelope.
    pub fn validate_response(&self, response: &ResponseEnvelope) -> Result<(), WireError> {
        self.require_not_stopped()?;
        self.validate_version(response.protocol_version)?;
        self.validate_generation(response.generation)?;
        self.validate_request_id(&response.request_id)?;
        if let Some(revision) = response.revision {
            if revision < self.revision {
                return Err(stale_revision());
            }
            if revision > self.revision {
                return Err(invalid_revision());
            }
        }
        match &response.result {
            ResponseResult::Ok(payload) => self.validate_payload(payload),
            ResponseResult::Error(error) => self.validate_wire_error(error),
        }
    }

    /// Validates an event envelope.
    pub fn validate_event(&self, event: &EventEnvelope) -> Result<(), WireError> {
        self.require_not_stopped()?;
        self.validate_version(event.protocol_version)?;
        self.validate_generation(event.generation)?;
        validate_control_name(
            event.event.as_str(),
            self.limits.max_name_bytes,
            WireErrorCode::InvalidEvent,
        )?;
        self.validate_revision(event.revision)?;
        self.validate_payload(&event.payload)
    }

    /// Validates a snapshot envelope.
    pub fn validate_snapshot(&self, snapshot: &SnapshotEnvelope) -> Result<(), WireError> {
        self.require_not_stopped()?;
        self.validate_version(snapshot.protocol_version)?;
        self.validate_generation(snapshot.generation)?;
        validate_control_name(
            snapshot.snapshot.as_str(),
            self.limits.max_name_bytes,
            WireErrorCode::InvalidSnapshot,
        )?;
        if snapshot.revision < self.revision {
            return Err(stale_revision());
        }
        if snapshot.revision > self.revision {
            return Err(invalid_revision());
        }
        self.validate_payload(&snapshot.payload)
    }

    /// Validates a cancellation envelope.
    pub fn validate_cancel(&self, cancel: &CancelEnvelope) -> Result<(), WireError> {
        self.require_not_stopped()?;
        self.validate_version(cancel.protocol_version)?;
        self.validate_generation(cancel.generation)?;
        self.validate_request_id(&cancel.request_id)
    }

    /// Validates a shutdown envelope.
    pub fn validate_shutdown(
        &self,
        shutdown: &ShutdownEnvelope,
        now_unix_millis: u64,
    ) -> Result<(), WireError> {
        self.require_not_stopped()?;
        self.validate_version(shutdown.protocol_version)?;
        self.validate_generation(shutdown.generation)?;
        self.validate_deadline(shutdown.deadline, now_unix_millis)
    }

    fn validate_version(&self, version: u16) -> Result<(), WireError> {
        if version == self.protocol_version {
            Ok(())
        } else {
            Err(WireError::protocol_version())
        }
    }

    fn validate_generation(&self, generation: Generation) -> Result<(), WireError> {
        if generation == self.generation {
            Ok(())
        } else {
            Err(WireError::stale_generation())
        }
    }

    fn validate_revision(&self, revision: Revision) -> Result<(), WireError> {
        if revision < self.revision {
            return Err(stale_revision());
        }
        if revision > self.revision {
            return Err(invalid_revision());
        }
        Ok(())
    }

    fn validate_request_id(&self, request_id: &RequestId) -> Result<(), WireError> {
        if request_id.as_str().is_empty()
            || request_id.as_str().len() > covio_core::MAX_REQUEST_ID_BYTES
            || !request_id.as_str().bytes().all(is_request_id_byte)
        {
            return Err(WireError::new(
                WireErrorCode::InvalidRequestId,
                "request id is invalid",
                false,
            ));
        }
        Ok(())
    }

    fn validate_payload(&self, payload: &Value) -> Result<(), WireError> {
        let encoded = serde_json::to_vec(payload).map_err(|_| WireError::malformed_message())?;
        if encoded.len() > self.limits.max_control_bytes {
            return Err(WireError::payload_too_large());
        }
        Ok(())
    }

    fn validate_deadline(
        &self,
        deadline: Option<Deadline>,
        now_unix_millis: u64,
    ) -> Result<(), WireError> {
        if deadline.is_some_and(|deadline| {
            deadline.as_unix_millis() == 0 || deadline.is_reached(now_unix_millis)
        }) {
            return Err(WireError::new(
                WireErrorCode::DeadlineExceeded,
                "bridge deadline has been reached",
                true,
            ));
        }
        Ok(())
    }

    fn validate_wire_error(&self, error: &WireError) -> Result<(), WireError> {
        if error.message.len() > self.limits.max_error_message_bytes {
            return Err(WireError::new(
                WireErrorCode::PayloadTooLarge,
                "bridge error message exceeds the configured limit",
                false,
            ));
        }
        Ok(())
    }

    fn require_running(&self) -> Result<(), WireError> {
        if self.lifecycle == BridgeLifecycle::Running {
            Ok(())
        } else {
            Err(shutting_down())
        }
    }

    fn require_not_stopped(&self) -> Result<(), WireError> {
        if self.lifecycle == BridgeLifecycle::Stopped {
            Err(shutting_down())
        } else {
            Ok(())
        }
    }
}

/// Encodes one bridge message with the configured size limit.
pub fn encode_message(message: &BridgeMessage, limits: BridgeLimits) -> Result<Vec<u8>, WireError> {
    let bytes = serde_json::to_vec(message).map_err(|_| WireError::malformed_message())?;
    if bytes.len() > limits.max_control_bytes {
        return Err(WireError::payload_too_large());
    }
    Ok(bytes)
}

/// Decodes one bridge message without interpreting its business payload.
pub fn decode_message(bytes: &[u8], limits: BridgeLimits) -> Result<BridgeMessage, WireError> {
    if bytes.len() > limits.max_control_bytes {
        return Err(WireError::payload_too_large());
    }
    serde_json::from_slice(bytes).map_err(|_| WireError::malformed_message())
}

fn validate_control_name(
    value: &str,
    max_name_bytes: usize,
    code: WireErrorCode,
) -> Result<(), WireError> {
    let mut bytes = value.bytes();
    let Some(first) = bytes.next() else {
        return Err(invalid_name(code));
    };
    if !first.is_ascii_lowercase()
        || value.len() > max_name_bytes
        || !bytes.all(is_control_name_byte)
    {
        return Err(invalid_name(code));
    }
    Ok(())
}

const fn is_control_name_byte(byte: u8) -> bool {
    byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'-' | b'_' | b'.' | b':')
}

const fn is_request_id_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b':' | b'/')
}

fn invalid_name(code: WireErrorCode) -> WireError {
    WireError::new(code, "bridge name is invalid", false)
}

fn stale_revision() -> WireError {
    WireError::new(
        WireErrorCode::StaleRevision,
        "bridge revision is stale",
        true,
    )
}

fn invalid_revision() -> WireError {
    WireError::new(
        WireErrorCode::InvalidRevision,
        "bridge revision is not available",
        false,
    )
}

fn shutting_down() -> WireError {
    WireError::new(
        WireErrorCode::ShuttingDown,
        "bridge session is shutting down",
        true,
    )
}

const fn public_message(code: WireErrorCode) -> &'static str {
    match code {
        WireErrorCode::ProtocolVersion => "unsupported bridge protocol version",
        WireErrorCode::PayloadTooLarge => "bridge payload exceeds the configured limit",
        WireErrorCode::MalformedMessage => "bridge message is malformed",
        WireErrorCode::InvalidRequestId => "request id is invalid",
        WireErrorCode::InvalidCommand => "command name is invalid",
        WireErrorCode::InvalidEvent => "event name is invalid",
        WireErrorCode::InvalidSnapshot => "snapshot name is invalid",
        WireErrorCode::StaleGeneration => "bridge generation is stale",
        WireErrorCode::StaleRevision => "bridge revision is stale",
        WireErrorCode::InvalidRevision => "bridge revision is not available",
        WireErrorCode::DeadlineExceeded => "operation deadline has been reached",
        WireErrorCode::Cancelled => "operation was cancelled",
        WireErrorCode::ShuttingDown => "bridge session is shutting down",
        WireErrorCode::Unsupported => "operation is unsupported",
        WireErrorCode::NotFound => "requested object was not found",
        WireErrorCode::Conflict => "operation conflicts with current state",
        WireErrorCode::InvalidArgument => "operation input is invalid",
        WireErrorCode::Io => "platform capability failed",
        WireErrorCode::Internal => "internal core failure",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn request(generation: u64) -> RequestEnvelope {
        RequestEnvelope {
            protocol_version: PROTOCOL_VERSION,
            request_id: RequestId::try_new("request-1").expect("valid request id"),
            generation: Generation::new(generation),
            command: CommandName::try_new("settings.load").expect("valid command"),
            deadline: None,
            payload: json!({"key": "value"}),
        }
    }

    fn event(generation: u64, revision: u64) -> EventEnvelope {
        EventEnvelope {
            protocol_version: PROTOCOL_VERSION,
            generation: Generation::new(generation),
            revision: Revision::new(revision),
            event: EventName::try_new("state.changed").expect("valid event"),
            payload: json!({"state": "ready"}),
        }
    }

    fn validator() -> BridgeValidator {
        BridgeValidator::new(
            Generation::new(7),
            Revision::new(11),
            BridgeLifecycle::Running,
            BridgeLimits::default(),
        )
    }

    #[test]
    fn request_round_trip_uses_stable_fields() {
        let message = BridgeMessage::Request(request(7));
        let encoded = encode_message(&message, BridgeLimits::default()).expect("encode");
        let decoded = decode_message(&encoded, BridgeLimits::default()).expect("decode");
        assert_eq!(decoded, message);

        let value: Value = serde_json::from_slice(&encoded).expect("json");
        assert_eq!(value["kind"], "request");
        assert_eq!(value["body"]["protocol_version"], PROTOCOL_VERSION);
        assert_eq!(value["body"]["command"], "settings.load");
        assert_eq!(value["body"]["generation"], 7);
        assert!(value["body"].get("deadline").is_some());
    }

    #[test]
    fn event_and_snapshot_round_trip() {
        let event_message = BridgeMessage::Event(event(7, 11));
        let bytes = encode_message(&event_message, BridgeLimits::default()).expect("encode");
        assert_eq!(
            decode_message(&bytes, BridgeLimits::default()).expect("decode"),
            event_message
        );

        let snapshot_message = BridgeMessage::Snapshot(SnapshotEnvelope {
            protocol_version: PROTOCOL_VERSION,
            generation: Generation::new(7),
            revision: Revision::new(11),
            snapshot: SnapshotName::try_new("session.state").expect("valid snapshot"),
            payload: json!({"items": []}),
        });
        let bytes = encode_message(&snapshot_message, BridgeLimits::default()).expect("encode");
        assert_eq!(
            decode_message(&bytes, BridgeLimits::default()).expect("decode"),
            snapshot_message
        );
    }

    #[test]
    fn response_error_and_shutdown_round_trip() {
        let response = BridgeMessage::Response(ResponseEnvelope {
            protocol_version: PROTOCOL_VERSION,
            request_id: RequestId::try_new("request-2").expect("valid request id"),
            generation: Generation::new(7),
            revision: Some(Revision::new(11)),
            result: ResponseResult::Error(WireError::new(
                WireErrorCode::Unsupported,
                "operation is unsupported",
                false,
            )),
        });
        let bytes = encode_message(&response, BridgeLimits::default()).expect("encode");
        assert_eq!(
            decode_message(&bytes, BridgeLimits::default()).expect("decode"),
            response
        );

        let shutdown = BridgeMessage::Shutdown(ShutdownEnvelope {
            protocol_version: PROTOCOL_VERSION,
            generation: Generation::new(7),
            mode: ShutdownMode::Graceful,
            deadline: Some(Deadline::from_unix_millis(100)),
        });
        let bytes = encode_message(&shutdown, BridgeLimits::default()).expect("encode");
        assert_eq!(
            decode_message(&bytes, BridgeLimits::default()).expect("decode"),
            shutdown
        );
    }

    #[test]
    fn version_mismatch_is_typed() {
        let mut request = request(7);
        request.protocol_version = PROTOCOL_VERSION + 1;
        let error = validator()
            .validate_request(&request, 50)
            .expect_err("version");
        assert_eq!(error.code, WireErrorCode::ProtocolVersion);
    }

    #[test]
    fn stale_generation_is_typed() {
        let error = validator()
            .validate_request(&request(6), 50)
            .expect_err("generation");
        assert_eq!(error.code, WireErrorCode::StaleGeneration);
        assert!(error.retryable);
    }

    #[test]
    fn oversized_payload_is_typed() {
        let limits = BridgeLimits {
            max_control_bytes: 8,
            ..BridgeLimits::default()
        };
        let validator = BridgeValidator::new(
            Generation::new(7),
            Revision::new(11),
            BridgeLifecycle::Running,
            limits,
        );
        let error = validator
            .validate_request(&request(7), 50)
            .expect_err("payload size");
        assert_eq!(error.code, WireErrorCode::PayloadTooLarge);
    }

    #[test]
    fn oversized_raw_message_is_rejected_before_parse() {
        let limits = BridgeLimits {
            max_control_bytes: 4,
            ..BridgeLimits::default()
        };
        let error = decode_message(br#"{"kind":"request"}"#, limits).expect_err("message size");
        assert_eq!(error.code, WireErrorCode::PayloadTooLarge);
    }

    #[test]
    fn malformed_json_is_typed() {
        let error = decode_message(b"{", BridgeLimits::default()).expect_err("malformed");
        assert_eq!(error.code, WireErrorCode::MalformedMessage);
    }

    #[test]
    fn invalid_command_name_and_request_id_are_typed() {
        let mut request = request(7);
        request.command = CommandName("Settings Load".to_owned());
        let error = validator()
            .validate_request(&request, 50)
            .expect_err("command");
        assert_eq!(error.code, WireErrorCode::InvalidCommand);

        let invalid_request: RequestEnvelope = serde_json::from_value(json!({
            "protocol_version": PROTOCOL_VERSION,
            "request_id": "has space",
            "generation": 7,
            "command": "settings.load",
            "deadline": null,
            "payload": {}
        }))
        .expect("invalid request id still decodes for typed validation");
        let error = validator()
            .validate_request(&invalid_request, 50)
            .expect_err("request id");
        assert_eq!(error.code, WireErrorCode::InvalidRequestId);
    }

    #[test]
    fn deadlines_are_inclusive() {
        let mut request = request(7);
        request.deadline = Some(Deadline::from_unix_millis(100));
        let error = validator()
            .validate_request(&request, 100)
            .expect_err("deadline");
        assert_eq!(error.code, WireErrorCode::DeadlineExceeded);
    }

    #[test]
    fn stale_or_future_revision_is_typed() {
        let stale = validator()
            .validate_event(&event(7, 10))
            .expect_err("stale");
        assert_eq!(stale.code, WireErrorCode::StaleRevision);

        let future = validator()
            .validate_event(&event(7, 12))
            .expect_err("future");
        assert_eq!(future.code, WireErrorCode::InvalidRevision);
    }

    #[test]
    fn draining_rejects_new_requests_but_allows_cancellation() {
        let validator = BridgeValidator::new(
            Generation::new(7),
            Revision::new(11),
            BridgeLifecycle::Draining,
            BridgeLimits::default(),
        );
        let error = validator
            .validate_request(&request(7), 50)
            .expect_err("new request");
        assert_eq!(error.code, WireErrorCode::ShuttingDown);

        let cancel = CancelEnvelope {
            protocol_version: PROTOCOL_VERSION,
            generation: Generation::new(7),
            request_id: RequestId::try_new("request-1").expect("valid request id"),
            reason: CancelReason::Shutdown,
        };
        validator
            .validate_cancel(&cancel)
            .expect("cancellation during draining");
    }

    #[test]
    fn core_error_is_redacted() {
        let core_error = CoreError::new(
            CoreErrorCode::Io,
            "failed for /Users/alice/private/secret.txt",
        );
        let error = WireError::from(&core_error);
        assert_eq!(error.code, WireErrorCode::Io);
        assert_eq!(error.message, "platform capability failed");
        assert!(!error.message.contains("/Users/alice"));
        assert!(error.retryable);
    }

    #[test]
    fn oversized_public_error_is_typed() {
        let limits = BridgeLimits {
            max_error_message_bytes: 4,
            ..BridgeLimits::default()
        };
        let validator = BridgeValidator::new(
            Generation::new(7),
            Revision::new(11),
            BridgeLifecycle::Running,
            limits,
        );
        let response = ResponseEnvelope {
            protocol_version: PROTOCOL_VERSION,
            request_id: RequestId::try_new("request-1").expect("valid request id"),
            generation: Generation::new(7),
            revision: None,
            result: ResponseResult::Error(WireError::new(
                WireErrorCode::Internal,
                "too long",
                false,
            )),
        };
        let error = validator
            .validate_response(&response)
            .expect_err("error message size");
        assert_eq!(error.code, WireErrorCode::PayloadTooLarge);
    }

    #[test]
    fn wire_error_serialization_is_stable() {
        let error = WireError::new(WireErrorCode::Conflict, "operation conflicts", false);
        let value = serde_json::to_value(error).expect("serialize");
        assert_eq!(value["code"], "conflict");
        assert_eq!(value["message"], "operation conflicts");
        assert_eq!(value["retryable"], false);
    }

    #[test]
    fn command_name_rules_are_enforced() {
        assert!(CommandName::try_new("settings.load").is_ok());
        assert!(CommandName::try_new("Settings.load").is_err());
        assert!(CommandName::try_new("settings load").is_err());
        assert!(CommandName::try_new("").is_err());
        assert!(CommandName::try_new("a".repeat(DEFAULT_MAX_NAME_BYTES + 1)).is_err());
    }
}

//! Business commands exposed by the JNI bridge for the Compose host.
//!
//! UI hosts report platform facts. This module validates those facts, owns the
//! cross-device state that is not already in `covio-core`, and composes the
//! pairing and transfer primitives.

use covio_bridge::WireErrorCode;
use covio_core::device_pairing::{
    DeviceIdentityService, PairingError, PairingErrorCode, PairingInitiator,
    PairingInitiatorAwaitingConfirmation, PairingOffer, PairingResponder, PairingResponse,
};
use covio_core::file_transfer::{
    ControlMessage, FileStreamHeader, IrohTransferEndpoint, RejectReason, TRANSFER_WINDOW_SIZE,
    TransferError, TransferErrorCode, TransferReceiver, TransferSender, TransferStore,
};
use covio_platform::{CapabilityKind, StdFileStore, WindowsCapabilitySet};
use serde_json::{Value, json};
#[cfg(any(not(target_os = "windows"), test))]
use std::collections::BTreeMap;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
#[cfg(any(not(target_os = "windows"), test))]
use std::sync::Arc;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::runtime::Runtime;

#[cfg(all(target_os = "windows", not(test)))]
type PlatformSecrets = covio_platform::WindowsCredentialStore;
#[cfg(any(not(target_os = "windows"), test))]
type PlatformSecrets = MemorySecretStore;

/// Result returned by one Compose command.
pub type CommandResult<T> = Result<T, CommandError>;

/// One typed command failure safe to cross the bridge.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandError {
    /// Stable bridge error category.
    pub code: WireErrorCode,
    /// Public diagnostic message.
    pub message: String,
    /// Whether retrying can succeed.
    pub retryable: bool,
}

impl CommandError {
    pub(crate) fn new(code: WireErrorCode, message: impl Into<String>, retryable: bool) -> Self {
        Self {
            code,
            message: message.into(),
            retryable,
        }
    }

    fn invalid(message: impl Into<String>) -> Self {
        Self::new(WireErrorCode::InvalidArgument, message, false)
    }

    fn unsupported(message: impl Into<String>) -> Self {
        Self::new(WireErrorCode::Unsupported, message, false)
    }

    fn cancelled() -> Self {
        Self::new(WireErrorCode::Cancelled, "operation was cancelled", false)
    }

    fn deadline() -> Self {
        Self::new(
            WireErrorCode::DeadlineExceeded,
            "operation deadline expired",
            true,
        )
    }

    fn internal(message: impl Into<String>) -> Self {
        Self::new(WireErrorCode::Internal, message, false)
    }

    fn io(message: impl Into<String>, retryable: bool) -> Self {
        Self::new(WireErrorCode::Io, message, retryable)
    }
}

impl From<serde_json::Error> for CommandError {
    fn from(_: serde_json::Error) -> Self {
        Self::invalid("command payload is not valid")
    }
}

impl From<PairingError> for CommandError {
    fn from(error: PairingError) -> Self {
        let code = match error.code() {
            PairingErrorCode::InvalidArgument => WireErrorCode::InvalidArgument,
            PairingErrorCode::IdentityNotFound
            | PairingErrorCode::ResponseMismatch
            | PairingErrorCode::SelfPairing
            | PairingErrorCode::ConfirmationMismatch
            | PairingErrorCode::ReplayDetected => WireErrorCode::Conflict,
            PairingErrorCode::ProtocolUnsupported => WireErrorCode::ProtocolVersion,
            PairingErrorCode::OfferExpired => WireErrorCode::DeadlineExceeded,
            PairingErrorCode::OfferInvalidSignature
            | PairingErrorCode::ResponseInvalidSignature => WireErrorCode::InvalidArgument,
            PairingErrorCode::RegistryFull => WireErrorCode::Conflict,
            PairingErrorCode::StorageFailure => WireErrorCode::Io,
            PairingErrorCode::RecordCorrupt | PairingErrorCode::Internal => WireErrorCode::Internal,
            PairingErrorCode::CredentialUnavailable => WireErrorCode::Io,
        };
        Self::new(code, error.message(), error.retryable())
    }
}

impl From<TransferError> for CommandError {
    fn from(error: TransferError) -> Self {
        let code = match error.code() {
            TransferErrorCode::InvalidArgument
            | TransferErrorCode::ManifestInvalid
            | TransferErrorCode::ResumeCheckpointInvalid
            | TransferErrorCode::TargetExists
            | TransferErrorCode::PeerIdentityChanged => WireErrorCode::InvalidArgument,
            TransferErrorCode::ProtocolVersionUnsupported => WireErrorCode::ProtocolVersion,
            TransferErrorCode::TransferOfferExpired => WireErrorCode::DeadlineExceeded,
            TransferErrorCode::OfferRejected => WireErrorCode::Conflict,
            TransferErrorCode::CancelledBySender | TransferErrorCode::CancelledByReceiver => {
                WireErrorCode::Cancelled
            }
            TransferErrorCode::TransportOffline => WireErrorCode::Io,
            TransferErrorCode::StorageIoError => WireErrorCode::Io,
            TransferErrorCode::ChunkHashMismatch
            | TransferErrorCode::FileHashMismatch
            | TransferErrorCode::SourceChanged
            | TransferErrorCode::PathCollision => WireErrorCode::Conflict,
            TransferErrorCode::PathInvalid | TransferErrorCode::UnsupportedEntryKind => {
                WireErrorCode::InvalidArgument
            }
            TransferErrorCode::SymlinkRefused | TransferErrorCode::BackgroundSuspended => {
                WireErrorCode::Unsupported
            }
            TransferErrorCode::Internal => WireErrorCode::Internal,
        };
        Self::new(code, error.message(), error.retryable())
    }
}

impl From<covio_platform::PlatformError> for CommandError {
    fn from(error: covio_platform::PlatformError) -> Self {
        let code = match error.code() {
            covio_platform::PlatformErrorCode::InvalidArgument => WireErrorCode::InvalidArgument,
            covio_platform::PlatformErrorCode::Cancelled => WireErrorCode::Cancelled,
            covio_platform::PlatformErrorCode::Unavailable => WireErrorCode::Unsupported,
            covio_platform::PlatformErrorCode::Io
            | covio_platform::PlatformErrorCode::PermissionDenied
            | covio_platform::PlatformErrorCode::AuthenticationRequired
            | covio_platform::PlatformErrorCode::Locked
            | covio_platform::PlatformErrorCode::KeyInvalidated => WireErrorCode::Io,
        };
        Self::new(code, error.message(), error.retryable())
    }
}

/// Facts supplied by the JNI host when it configures a session.
#[derive(Debug, Clone)]
pub struct ComposeConfig {
    /// Application data root.
    pub data_root: PathBuf,
    /// This device's display name.
    pub display_name: String,
    /// Operating system display name.
    pub system_name: String,
    /// Operating system version.
    pub system_version: String,
    /// Product version.
    pub app_version: String,
    /// Host adapters the Compose executable has installed.
    pub host_adapters: Vec<String>,
}

impl ComposeConfig {
    /// Parses the configuration supplied by the Kotlin host.
    pub fn from_json(value: &Value) -> CommandResult<Self> {
        let data_root = string_field(value, "dataRoot")?;
        let path = PathBuf::from(data_root);
        if !path.is_absolute() {
            return Err(CommandError::invalid("dataRoot must be absolute"));
        }
        Ok(Self {
            data_root: path,
            display_name: string_field(value, "displayName")?.to_owned(),
            system_name: optional_string(value, "systemName")
                .map(ToOwned::to_owned)
                .unwrap_or_else(|| std::env::consts::OS.to_owned()),
            system_version: optional_string(value, "systemVersion")
                .map(ToOwned::to_owned)
                .unwrap_or_else(|| "unknown".to_owned()),
            app_version: optional_string(value, "appVersion")
                .map(ToOwned::to_owned)
                .unwrap_or_else(|| env!("CARGO_PKG_VERSION").to_owned()),
            host_adapters: string_array(value, "hostAdapters")?,
        })
    }
}

impl Default for ComposeConfig {
    fn default() -> Self {
        let data_root = std::env::var_os("LOCALAPPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir)
            .join("Covio");
        Self {
            data_root,
            display_name: std::env::var("COMPUTERNAME")
                .or_else(|_| std::env::var("HOSTNAME"))
                .unwrap_or_else(|_| "Covio device".to_owned()),
            system_name: std::env::consts::OS.to_owned(),
            system_version: "unknown".to_owned(),
            app_version: env!("CARGO_PKG_VERSION").to_owned(),
            host_adapters: Vec::new(),
        }
    }
}

/// Per-command cancellation, deadline, and event context.
pub struct CommandContext<'a> {
    /// Current Unix time in milliseconds.
    pub now_ms: i64,
    /// Absolute request deadline in Unix milliseconds.
    pub deadline_ms: Option<u64>,
    /// Cooperative cancellation flag.
    pub cancelled: &'a AtomicBool,
    /// Event sink.
    pub emit: &'a dyn Fn(&str, Value) -> CommandResult<()>,
}

impl CommandContext<'_> {
    fn check(&self) -> CommandResult<()> {
        if self.cancelled.load(Ordering::Acquire) {
            return Err(CommandError::cancelled());
        }
        if self
            .deadline_ms
            .is_some_and(|deadline| now_unix_millis() as u64 >= deadline)
        {
            return Err(CommandError::deadline());
        }
        Ok(())
    }

    fn emit_progress(&self, snapshot: &impl serde::Serialize) -> CommandResult<()> {
        (self.emit)(
            "transfer.progress",
            serde_json::to_value(snapshot)
                .map_err(|_| CommandError::internal("progress event serialization failed"))?,
        )
    }
}

struct CapabilityRequest {
    kind: CapabilityKind,
    purpose: String,
}

#[derive(Clone)]
struct CapabilityLease {
    kind: CapabilityKind,
    purpose: String,
    path: PathBuf,
}

enum PendingPairing {
    Initiator(PairingInitiator<StdFileStore>),
    InitiatorAwaiting(PairingInitiatorAwaitingConfirmation<StdFileStore>),
    Responder(PairingResponder<StdFileStore>),
}

/// Cross-device application service owned by the JNI bridge.
pub struct ComposeCore {
    config: ComposeConfig,
    identity: Mutex<DeviceIdentityService<PlatformSecrets, StdFileStore>>,
    capabilities: Mutex<WindowsCapabilitySet>,
    online: AtomicBool,
    foreground: AtomicBool,
    pending_pairing: Mutex<Option<PendingPairing>>,
    pending_capabilities: Mutex<HashMap<String, CapabilityRequest>>,
    leases: Mutex<HashMap<String, CapabilityLease>>,
}

impl ComposeCore {
    /// Opens the core service for one host configuration.
    pub fn open(config: ComposeConfig) -> CommandResult<Self> {
        let files = StdFileStore::new();
        let secrets = platform_secrets();
        let mut identity =
            DeviceIdentityService::open_or_create(&config.data_root, secrets, files)?;
        identity.load_or_create_identity(&config.display_name, now_unix_millis())?;
        let capabilities = WindowsCapabilitySet::default()
            .with_host_adapters(config.host_adapters.iter().map(String::as_str));
        for required in [CapabilityKind::Filesystem, CapabilityKind::SecureStorage] {
            if !capabilities.status(required).available {
                return Err(CommandError::unsupported(format!(
                    "required capability is unavailable: {}",
                    required.as_str()
                )));
            }
        }
        Ok(Self {
            config,
            identity: Mutex::new(identity),
            capabilities: Mutex::new(capabilities),
            online: AtomicBool::new(false),
            foreground: AtomicBool::new(true),
            pending_pairing: Mutex::new(None),
            pending_capabilities: Mutex::new(HashMap::new()),
            leases: Mutex::new(HashMap::new()),
        })
    }

    /// Executes one command.
    pub fn call(
        &self,
        command: &str,
        payload: &Value,
        context: &CommandContext<'_>,
    ) -> CommandResult<Value> {
        context.check()?;
        match command {
            "app.snapshot" | "device.snapshot" => self.snapshot(),
            "diagnostics.echo" => Ok(json!({"payload": payload})),
            "diagnostics.wait" => self.wait_command(payload, context),
            "network.status" => {
                let online = bool_field(payload, "online")?;
                self.online.store(online, Ordering::Release);
                Ok(json!({"online": online}))
            }
            "lifecycle.foreground" => {
                self.foreground.store(true, Ordering::Release);
                Ok(json!({"lifecycle": "foreground"}))
            }
            "lifecycle.background" => {
                self.foreground.store(false, Ordering::Release);
                Ok(json!({"lifecycle": "background"}))
            }
            "capabilities.report" => self.report_capabilities(payload),
            "capability.request" | "file_picker.open" | "share.present" | "notification.post"
            | "background.acquire" | "background.release" => {
                self.request_platform_capability(command, payload)
            }
            "capability.complete" => self.complete_capability(payload),
            "pairing.start" => self.start_pairing(),
            "pairing.accept_offer" => self.accept_pairing_offer(payload),
            "pairing.accept_response" => self.accept_pairing_response(payload),
            "pairing.confirm" => self.confirm_pairing(payload),
            "pairing.cancel" => {
                *self.pending_pairing.lock().map_err(lock_error)? = None;
                Ok(json!({}))
            }
            "pairing.revoke" => self.revoke_pairing(payload),
            "transfer.send" => self.send_transfer(payload, context),
            "transfer.receive" => self.receive_transfer(payload, context),
            "transfer.snapshot" => self.transfer_snapshot(payload),
            _ => Err(CommandError::invalid("unknown command")),
        }
    }

    fn snapshot(&self) -> CommandResult<Value> {
        let identity = self.identity.lock().map_err(lock_error)?;
        let local = identity.load_identity()?;
        let trusted = identity.trusted_devices()?;
        let capabilities = *self.capabilities.lock().map_err(lock_error)?;
        let transfers = TransferStore::open(self.transfer_database())
            .and_then(|store| store.jobs(20))
            .unwrap_or_default();
        let pending_pairing = match self.pending_pairing.lock().map_err(lock_error)?.as_ref() {
            Some(PendingPairing::Initiator(_)) => "offer",
            Some(PendingPairing::InitiatorAwaiting(_)) => "confirm_initiator",
            Some(PendingPairing::Responder(_)) => "confirm_responder",
            None => "none",
        };
        Ok(json!({
            "device": {
                "identity": local,
                "system_name": self.config.system_name,
                "system_version": self.config.system_version,
                "app_version": self.config.app_version,
                "online": self.online.load(Ordering::Acquire),
                "lifecycle": if self.foreground.load(Ordering::Acquire) { "foreground" } else { "background" },
            },
            "capabilities": capability_json(capabilities),
            "trusted_devices": trusted,
            "transfers": transfers,
            "pending_pairing": pending_pairing,
        }))
    }

    fn wait_command(&self, payload: &Value, context: &CommandContext<'_>) -> CommandResult<Value> {
        let milliseconds = integer_field(payload, "milliseconds")?;
        if !(0..=30_000).contains(&milliseconds) {
            return Err(CommandError::invalid(
                "milliseconds must be between 0 and 30000",
            ));
        }
        let start = std::time::Instant::now();
        while start.elapsed() < Duration::from_millis(milliseconds as u64) {
            context.check()?;
            std::thread::sleep(Duration::from_millis(20));
        }
        Ok(json!({"waited_ms": start.elapsed().as_millis()}))
    }

    fn report_capabilities(&self, payload: &Value) -> CommandResult<Value> {
        let adapters = string_array(payload, "adapters")?;
        let capabilities =
            WindowsCapabilitySet::default().with_host_adapters(adapters.iter().map(String::as_str));
        *self.capabilities.lock().map_err(lock_error)? = capabilities;
        Ok(json!({"capabilities": capability_json(capabilities)}))
    }

    fn request_platform_capability(&self, command: &str, payload: &Value) -> CommandResult<Value> {
        let (kind, purpose) = match command {
            "file_picker.open" => ("file_picker", "send_file"),
            "share.present" => ("share_sheet", "share"),
            "notification.post" => ("notification", "transfer"),
            "background.acquire" => ("background_task", "transfer"),
            "background.release" => ("background_task", "release"),
            _ => {
                return self.request_capability(payload);
            }
        };
        let mut request = payload.clone();
        if let Some(object) = request.as_object_mut() {
            object.insert("kind".to_owned(), Value::String(kind.to_owned()));
            object
                .entry("purpose".to_owned())
                .or_insert_with(|| Value::String(purpose.to_owned()));
        }
        self.request_capability(&request)
    }

    fn request_capability(&self, payload: &Value) -> CommandResult<Value> {
        let kind_name = string_field(payload, "kind")?;
        let kind = CapabilityKind::from_name(kind_name)
            .ok_or_else(|| CommandError::invalid("capability kind is invalid"))?;
        let status = self.capabilities.lock().map_err(lock_error)?.status(kind);
        if !status.available {
            return Err(CommandError::unsupported(format!(
                "capability is unavailable: {}",
                kind.as_str()
            )));
        }
        let purpose = optional_string(payload, "purpose").unwrap_or("").to_owned();
        if kind == CapabilityKind::FilePicker && purpose.is_empty() {
            return Err(CommandError::invalid("file picker purpose is required"));
        }
        let request_id = format!("cap-{}", uuid::Uuid::new_v4().simple());
        self.pending_capabilities
            .lock()
            .map_err(lock_error)?
            .insert(
                request_id.clone(),
                CapabilityRequest {
                    kind,
                    purpose: purpose.clone(),
                },
            );
        Ok(json!({
            "request_id": request_id,
            "kind": kind.as_str(),
            "purpose": purpose,
            "parameters": payload.get("parameters").cloned().unwrap_or_else(|| json!({})),
        }))
    }

    fn complete_capability(&self, payload: &Value) -> CommandResult<Value> {
        let request_id = string_field(payload, "requestId")?;
        let request = self
            .pending_capabilities
            .lock()
            .map_err(lock_error)?
            .remove(request_id)
            .ok_or_else(|| CommandError::invalid("capability request is unknown or completed"))?;
        let outcome = string_field(payload, "outcome")?;
        if outcome == "cancelled" {
            return Err(CommandError::cancelled());
        }
        if outcome != "selected" && outcome != "completed" {
            return Err(CommandError::invalid("capability outcome is invalid"));
        }
        if request.kind == CapabilityKind::FilePicker {
            let selected_path = string_field(payload, "path")?;
            let path = PathBuf::from(selected_path);
            if !path.is_absolute() {
                return Err(CommandError::invalid("selected path must be absolute"));
            }
            let metadata = std::fs::metadata(&path)
                .map_err(|_| CommandError::io("selected path is unavailable", true))?;
            let needs_directory = request.purpose == "destination_directory";
            if needs_directory && !metadata.is_dir() {
                return Err(CommandError::invalid("selected path is not a directory"));
            }
            if !needs_directory && !metadata.is_file() {
                return Err(CommandError::invalid("selected path is not a file"));
            }
            let lease_id = format!("lease-{}", uuid::Uuid::new_v4().simple());
            self.leases.lock().map_err(lock_error)?.insert(
                lease_id.clone(),
                CapabilityLease {
                    kind: request.kind,
                    purpose: request.purpose.clone(),
                    path,
                },
            );
            return Ok(
                json!({"lease_id": lease_id, "kind": request.kind.as_str(), "purpose": request.purpose}),
            );
        }
        Ok(json!({"kind": request.kind.as_str(), "purpose": request.purpose, "completed": true}))
    }

    fn start_pairing(&self) -> CommandResult<Value> {
        let capabilities = self
            .capabilities
            .lock()
            .map_err(lock_error)?
            .statuses()
            .into_iter()
            .filter(|status| status.available)
            .map(|status| status.kind.as_str().to_owned())
            .collect::<Vec<_>>();
        let mut identity = self.identity.lock().map_err(lock_error)?;
        let initiator = identity.begin_pairing(&capabilities, now_unix_millis())?;
        let offer = initiator.offer().clone();
        let qr_payload = offer.to_qr_payload()?;
        *self.pending_pairing.lock().map_err(lock_error)? =
            Some(PendingPairing::Initiator(initiator));
        Ok(json!({"qr_payload": qr_payload, "offer": offer}))
    }

    fn accept_pairing_offer(&self, payload: &Value) -> CommandResult<Value> {
        let qr_payload = string_field(payload, "qrPayload")?;
        let offer = PairingOffer::from_qr_payload(qr_payload)?;
        let mut identity = self.identity.lock().map_err(lock_error)?;
        let responder = identity.accept_pairing_offer(&offer, now_unix_millis())?;
        let response = responder.response().clone();
        let response_payload = response.to_wire_payload()?;
        let code = responder.code().to_owned();
        let remote = responder.remote_device().clone();
        *self.pending_pairing.lock().map_err(lock_error)? =
            Some(PendingPairing::Responder(responder));
        Ok(json!({
            "response_payload": response_payload,
            "response": response,
            "code": code,
            "remote_device": remote,
        }))
    }

    fn accept_pairing_response(&self, payload: &Value) -> CommandResult<Value> {
        let response_payload = string_field(payload, "responsePayload")?;
        let response = PairingResponse::from_wire_payload(response_payload)?;
        let pending = self
            .pending_pairing
            .lock()
            .map_err(lock_error)?
            .take()
            .ok_or_else(|| {
                CommandError::new(WireErrorCode::Conflict, "no pairing offer is active", false)
            })?;
        let PendingPairing::Initiator(initiator) = pending else {
            return Err(CommandError::new(
                WireErrorCode::Conflict,
                "pairing session is not waiting for a response",
                false,
            ));
        };
        let awaiting = initiator.complete(&response, now_unix_millis())?;
        let code = awaiting.code().to_owned();
        let remote = awaiting.remote_device().clone();
        *self.pending_pairing.lock().map_err(lock_error)? =
            Some(PendingPairing::InitiatorAwaiting(awaiting));
        Ok(json!({"code": code, "remote_device": remote}))
    }

    fn confirm_pairing(&self, payload: &Value) -> CommandResult<Value> {
        let code = string_field(payload, "code")?;
        let pending = self
            .pending_pairing
            .lock()
            .map_err(lock_error)?
            .take()
            .ok_or_else(|| {
                CommandError::new(
                    WireErrorCode::Conflict,
                    "no pairing confirmation is active",
                    false,
                )
            })?;
        match pending {
            PendingPairing::InitiatorAwaiting(awaiting) => {
                awaiting.finish(code, now_unix_millis())?;
            }
            PendingPairing::Responder(responder) => {
                responder.finish(code, now_unix_millis())?;
            }
            PendingPairing::Initiator(_) => {
                return Err(CommandError::new(
                    WireErrorCode::Conflict,
                    "pairing response has not been accepted",
                    false,
                ));
            }
        }
        Ok(json!({"confirmed": true}))
    }

    fn revoke_pairing(&self, payload: &Value) -> CommandResult<Value> {
        let device_id = string_field(payload, "deviceId")?;
        let identity = self.identity.lock().map_err(lock_error)?;
        identity.revoke_device(device_id, now_unix_millis())?;
        Ok(json!({"revoked": true}))
    }

    fn send_transfer(&self, payload: &Value, context: &CommandContext<'_>) -> CommandResult<Value> {
        let peer_device_id = string_field(payload, "peerDeviceId")?;
        let file_lease = string_field(payload, "fileLease")?;
        let source_path = self.lease_path(file_lease, CapabilityKind::FilePicker, "send_file")?;
        let runtime = transfer_runtime()?;
        runtime.block_on(async {
            let (local, peer, transfer_secret) = {
                let identity = self.identity.lock().map_err(lock_error)?;
                let local = identity.load_identity()?;
                let peer = identity
                    .trusted_devices()?
                    .into_iter()
                    .find(|device| device.device_id == peer_device_id)
                    .ok_or_else(|| {
                        CommandError::new(
                            WireErrorCode::NotFound,
                            "trusted device was not found",
                            false,
                        )
                    })?;
                (local, peer, identity.transfer_secret_key()?)
            };
            let endpoint = IrohTransferEndpoint::bind(transfer_secret).await?;
            endpoint.wait_online().await;
            let public_key = iroh_public_key(&peer.public_key)?;
            let address = iroh::EndpointAddr::new(public_key);
            let mut channel = endpoint.connect_trusted(address, &peer.public_key).await?;
            let store = open_transfer_store(&self.transfer_database())?;
            let files = StdFileStore::new();
            let transfer_id = format!("tx-{}", uuid::Uuid::new_v4().simple());
            let (mut sender, offer, initial) = TransferSender::create(
                store,
                files,
                &source_path,
                transfer_id,
                local.device_id,
                peer_device_id,
                context.now_ms,
            )?;
            context.emit_progress(&initial)?;
            channel
                .send_control(ControlMessage::Offer {
                    offer,
                    resume_from: 0,
                })
                .await?;
            context.check()?;
            let accepted = channel.receive_control().await?;
            let durable = match accepted.message {
                ControlMessage::Accept { durable_bytes } => durable_bytes,
                ControlMessage::Reject { reason } => {
                    return Err(CommandError::new(
                        WireErrorCode::Conflict,
                        reject_message(reason),
                        false,
                    ));
                }
                _ => {
                    return Err(CommandError::invalid(
                        "receiver did not accept the transfer",
                    ));
                }
            };
            sender.accept(durable, context.now_ms)?;
            channel
                .send_file_header(&FileStreamHeader::from_manifest(sender.manifest())?)
                .await?;
            loop {
                context.check()?;
                let frames = sender.read_window()?;
                if frames.is_empty() {
                    break;
                }
                for frame in frames {
                    context.check()?;
                    channel.send_chunk(&frame).await?;
                }
                context.check()?;
                let checkpoint = channel.receive_control().await?;
                let acknowledged = match checkpoint.message {
                    ControlMessage::Checkpoint { durable_bytes } => durable_bytes,
                    _ => return Err(CommandError::invalid("receiver checkpoint is invalid")),
                };
                sender.acknowledge(acknowledged, context.now_ms)?;
                context.emit_progress(&sender.snapshot()?)?;
                if acknowledged == sender.manifest().size {
                    break;
                }
            }
            channel.finish_file()?;
            let complete = channel.receive_control().await?;
            match complete.message {
                ControlMessage::Complete { blake3 } if blake3 == sender.manifest().blake3 => {}
                _ => return Err(CommandError::invalid("receiver completion is invalid")),
            }
            let snapshot = sender.complete(context.now_ms)?;
            context.emit_progress(&snapshot)?;
            channel.close();
            endpoint.close().await;
            Ok(json!({"transfer": snapshot, "peer_device": peer}))
        })
    }

    fn receive_transfer(
        &self,
        payload: &Value,
        context: &CommandContext<'_>,
    ) -> CommandResult<Value> {
        let destination_lease = string_field(payload, "destinationLease")?;
        let destination = self.lease_path(
            destination_lease,
            CapabilityKind::FilePicker,
            "destination_directory",
        )?;
        let runtime = transfer_runtime()?;
        runtime.block_on(async {
            let (trusted, transfer_secret) = {
                let identity = self.identity.lock().map_err(lock_error)?;
                (identity.trusted_devices()?, identity.transfer_secret_key()?)
            };
            let endpoint = IrohTransferEndpoint::bind(transfer_secret).await?;
            endpoint.wait_online().await;
            let mut channel = endpoint.accept_one().await?;
            let remote_public_key = channel.remote_public_key_hex();
            let peer = trusted
                .into_iter()
                .find(|device| device.public_key.eq_ignore_ascii_case(&remote_public_key))
                .ok_or_else(|| {
                    CommandError::new(
                        WireErrorCode::Conflict,
                        "incoming device is not trusted",
                        false,
                    )
                })?;
            channel.ensure_trusted_public_key(&peer.public_key)?;
            let first = channel.receive_control().await?;
            let (offer, resume_from) = match first.message {
                ControlMessage::Offer { offer, resume_from } => (offer, resume_from),
                _ => return Err(CommandError::invalid("incoming transfer offer is invalid")),
            };
            offer.validate()?;
            if offer.manifest.sender_device_id != peer.device_id {
                return Err(CommandError::new(
                    WireErrorCode::Conflict,
                    "offer sender does not match the trusted device",
                    false,
                ));
            }
            let store = open_transfer_store(&self.transfer_database())?;
            let receiver = TransferReceiver::new(store, StdFileStore::new(), &destination);
            let initial = receiver.receive_offer(&offer, context.now_ms)?;
            context.emit_progress(&initial)?;
            let plan = receiver.accept(&offer.manifest.transfer_id, resume_from, context.now_ms)?;
            channel
                .send_control(ControlMessage::Accept {
                    durable_bytes: plan.offset,
                })
                .await?;
            let header = channel.receive_file_header().await?;
            validate_file_header(&header, &offer.manifest)?;
            let mut durable = plan.offset;
            while durable < offer.manifest.size {
                context.check()?;
                let frame = channel.receive_chunk().await?;
                let outcome =
                    receiver.receive_chunk(&offer.manifest.transfer_id, &frame, context.now_ms)?;
                durable = outcome.durable_bytes;
                if durable % TRANSFER_WINDOW_SIZE == 0 || durable == offer.manifest.size {
                    channel
                        .send_control(ControlMessage::Checkpoint {
                            durable_bytes: durable,
                        })
                        .await?;
                    context.emit_progress(&receiver.snapshot(&offer.manifest.transfer_id)?)?;
                }
            }
            let completed = receiver.complete(&offer.manifest.transfer_id, context.now_ms)?;
            channel
                .send_control(ControlMessage::Complete {
                    blake3: completed.summary.blake3.clone(),
                })
                .await?;
            context.emit_progress(&completed)?;
            channel.close();
            endpoint.close().await;
            Ok(json!({"transfer": completed, "peer_device": peer}))
        })
    }

    fn transfer_snapshot(&self, payload: &Value) -> CommandResult<Value> {
        let transfer_id = string_field(payload, "transferId")?;
        let store = open_transfer_store(&self.transfer_database())?;
        Ok(json!({"transfer": store.job(transfer_id)?}))
    }

    fn lease_path(
        &self,
        lease_id: &str,
        kind: CapabilityKind,
        purpose: &str,
    ) -> CommandResult<PathBuf> {
        let leases = self.leases.lock().map_err(lock_error)?;
        let lease = leases.get(lease_id).ok_or_else(|| {
            CommandError::new(
                WireErrorCode::NotFound,
                "capability lease was not found",
                false,
            )
        })?;
        if lease.kind != kind || lease.purpose != purpose {
            return Err(CommandError::invalid(
                "capability lease does not match the operation",
            ));
        }
        Ok(lease.path.clone())
    }

    fn transfer_database(&self) -> PathBuf {
        self.config.data_root.join("transfers").join("transfers.db")
    }
}

fn capability_json(capabilities: WindowsCapabilitySet) -> Value {
    Value::Array(
        capabilities
            .statuses()
            .into_iter()
            .map(|status| {
                json!({
                    "kind": status.kind.as_str(),
                    "available": status.available,
                })
            })
            .collect(),
    )
}

fn transfer_runtime() -> CommandResult<Runtime> {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .worker_threads(2)
        .thread_name("covio-jni-transfer")
        .build()
        .map_err(|_| CommandError::internal("transfer runtime could not start"))
}

fn open_transfer_store(path: &Path) -> CommandResult<TransferStore> {
    TransferStore::open(path).map_err(Into::into)
}

fn iroh_public_key(public_key_hex: &str) -> CommandResult<iroh::PublicKey> {
    let bytes = hex::decode(public_key_hex)
        .map_err(|_| CommandError::invalid("trusted public key is not hex"))?;
    let key: [u8; 32] = bytes
        .try_into()
        .map_err(|_| CommandError::invalid("trusted public key has the wrong length"))?;
    iroh::PublicKey::from_bytes(&key)
        .map_err(|_| CommandError::invalid("trusted public key is invalid"))
}

fn validate_file_header(
    header: &FileStreamHeader,
    manifest: &covio_core::file_transfer::FileManifest,
) -> CommandResult<()> {
    let digest = hex::decode(&manifest.blake3)
        .map_err(|_| CommandError::invalid("manifest digest is not hex"))?;
    if header.transfer_id != manifest.transfer_id
        || header.total_size != manifest.size
        || header.chunk_size != manifest.chunk_size
        || header.blake3.as_slice() != digest.as_slice()
    {
        return Err(CommandError::invalid(
            "file stream header does not match the manifest",
        ));
    }
    Ok(())
}

fn reject_message(reason: RejectReason) -> &'static str {
    match reason {
        RejectReason::Declined => "receiver declined the transfer",
        RejectReason::InsufficientSpace => "receiver has insufficient space",
        RejectReason::DestinationUnavailable => "receiver destination is unavailable",
    }
}

fn string_field<'a>(value: &'a Value, name: &str) -> CommandResult<&'a str> {
    value
        .get(name)
        .and_then(Value::as_str)
        .ok_or_else(|| CommandError::invalid(format!("{name} must be a string")))
}

fn optional_string<'a>(value: &'a Value, name: &str) -> Option<&'a str> {
    value.get(name).and_then(Value::as_str)
}

fn bool_field(value: &Value, name: &str) -> CommandResult<bool> {
    value
        .get(name)
        .and_then(Value::as_bool)
        .ok_or_else(|| CommandError::invalid(format!("{name} must be a bool")))
}

fn integer_field(value: &Value, name: &str) -> CommandResult<i64> {
    value
        .get(name)
        .and_then(Value::as_i64)
        .ok_or_else(|| CommandError::invalid(format!("{name} must be an integer")))
}

fn string_array(value: &Value, name: &str) -> CommandResult<Vec<String>> {
    let values = value
        .get(name)
        .and_then(Value::as_array)
        .ok_or_else(|| CommandError::invalid(format!("{name} must be an array")))?;
    values
        .iter()
        .map(|item| {
            item.as_str()
                .map(ToOwned::to_owned)
                .ok_or_else(|| CommandError::invalid(format!("{name} must contain strings")))
        })
        .collect()
}

fn lock_error<T>(_: std::sync::PoisonError<T>) -> CommandError {
    CommandError::internal("core state lock failed")
}

fn now_unix_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| i64::try_from(duration.as_millis()).unwrap_or(i64::MAX))
        .unwrap_or(0)
}

#[cfg(all(target_os = "windows", not(test)))]
fn platform_secrets() -> PlatformSecrets {
    covio_platform::WindowsCredentialStore::default()
}

#[cfg(any(not(target_os = "windows"), test))]
fn platform_secrets() -> PlatformSecrets {
    MemorySecretStore::default()
}

#[cfg(any(not(target_os = "windows"), test))]
#[derive(Clone, Default)]
struct MemorySecretStore {
    values: Arc<Mutex<BTreeMap<String, Vec<u8>>>>,
}

#[cfg(any(not(target_os = "windows"), test))]
impl covio_platform::SecretStore for MemorySecretStore {
    fn read(
        &self,
        key: &covio_platform::SecretKey,
    ) -> Result<Option<covio_platform::SecretValue>, covio_platform::PlatformError> {
        let values = self
            .values
            .lock()
            .map_err(|_| covio_platform::PlatformError::io("test secret lock failed", false))?;
        Ok(values
            .get(key.as_str())
            .cloned()
            .map(covio_platform::SecretValue::new))
    }

    fn write(
        &self,
        key: &covio_platform::SecretKey,
        value: &covio_platform::SecretValue,
    ) -> Result<(), covio_platform::PlatformError> {
        self.values
            .lock()
            .map_err(|_| covio_platform::PlatformError::io("test secret lock failed", false))?
            .insert(key.as_str().to_owned(), value.expose().to_vec());
        Ok(())
    }

    fn delete(&self, key: &covio_platform::SecretKey) -> Result<(), covio_platform::PlatformError> {
        self.values
            .lock()
            .map_err(|_| covio_platform::PlatformError::io("test secret lock failed", false))?
            .remove(key.as_str());
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_core() -> ComposeCore {
        let root = std::env::temp_dir().join(format!(
            "covio-jni-core-{}-{}",
            std::process::id(),
            uuid::Uuid::new_v4().simple()
        ));
        ComposeCore::open(ComposeConfig {
            data_root: root,
            display_name: "Test Windows".to_owned(),
            system_name: "Windows 11".to_owned(),
            system_version: "10.0.26100".to_owned(),
            app_version: "0.1.0".to_owned(),
            host_adapters: vec![
                "file_picker".to_owned(),
                "notification".to_owned(),
                "background_task".to_owned(),
                "app_lifecycle".to_owned(),
            ],
        })
        .expect("core")
    }

    fn context<'a>(
        cancelled: &'a AtomicBool,
        emit: &'a dyn Fn(&str, Value) -> CommandResult<()>,
    ) -> CommandContext<'a> {
        CommandContext {
            now_ms: now_unix_millis(),
            deadline_ms: None,
            cancelled,
            emit,
        }
    }

    #[test]
    fn snapshot_is_read_only_and_reports_reported_adapters() {
        let core = test_core();
        let cancelled = AtomicBool::new(false);
        let emit = |_: &str, _: Value| Ok(());
        let value = core
            .call("device.snapshot", &json!({}), &context(&cancelled, &emit))
            .expect("snapshot");
        assert_eq!(value["device"]["identity"]["display_name"], "Test Windows");
        assert!(value["capabilities"].as_array().is_some_and(|items| {
            items
                .iter()
                .any(|item| item["kind"] == "background_task" && item["available"] == true)
        }));
    }

    #[test]
    fn command_wait_honors_cancellation() {
        let core = test_core();
        let cancelled = Arc::new(AtomicBool::new(false));
        let flag = cancelled.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(20));
            flag.store(true, Ordering::Release);
        });
        let emit = |_: &str, _: Value| Ok(());
        let error = core
            .call(
                "diagnostics.wait",
                &json!({"milliseconds": 1000}),
                &context(&cancelled, &emit),
            )
            .expect_err("cancelled");
        assert_eq!(error.code, WireErrorCode::Cancelled);
    }
    #[test]
    #[ignore = "requires iroh relay and discovery"]
    fn iroh_pairing_and_file_transfer_round_trip() {
        let root = std::env::temp_dir().join(format!(
            "covio-jni-iroh-{}-{}",
            std::process::id(),
            uuid::Uuid::new_v4().simple()
        ));
        let sender_root = root.join("sender");
        let receiver_root = root.join("receiver");
        let destination = root.join("received");
        std::fs::create_dir_all(&destination).expect("destination");
        let source = root.join("source.txt");
        std::fs::write(&source, b"covio cross-device round trip").expect("source");
        let sender = Arc::new(
            ComposeCore::open(ComposeConfig {
                data_root: sender_root,
                display_name: "Sender".to_owned(),
                system_name: "Windows 11".to_owned(),
                system_version: "10.0.26100".to_owned(),
                app_version: "test".to_owned(),
                host_adapters: vec!["file_picker".to_owned()],
            })
            .expect("sender core"),
        );
        let receiver = Arc::new(
            ComposeCore::open(ComposeConfig {
                data_root: receiver_root,
                display_name: "Receiver".to_owned(),
                system_name: "Windows 11".to_owned(),
                system_version: "10.0.26100".to_owned(),
                app_version: "test".to_owned(),
                host_adapters: vec!["file_picker".to_owned()],
            })
            .expect("receiver core"),
        );
        let cancelled = AtomicBool::new(false);
        let emit = |_: &str, _: Value| Ok(());
        let command_context = context(&cancelled, &emit);

        let offer = sender
            .call("pairing.start", &json!({}), &command_context)
            .expect("offer");
        let qr_payload = string(&offer, "qr_payload");
        let accepted = receiver
            .call(
                "pairing.accept_offer",
                &json!({"qrPayload": qr_payload}),
                &command_context,
            )
            .expect("accept offer");
        let response_payload = string(&accepted, "response_payload");
        let receiver_code = string(&accepted, "code");
        let initiator = sender
            .call(
                "pairing.accept_response",
                &json!({"responsePayload": response_payload}),
                &command_context,
            )
            .expect("accept response");
        let sender_code = string(&initiator, "code");
        assert_eq!(sender_code, receiver_code);
        sender
            .call(
                "pairing.confirm",
                &json!({"code": sender_code}),
                &command_context,
            )
            .expect("sender confirm");
        receiver
            .call(
                "pairing.confirm",
                &json!({"code": receiver_code}),
                &command_context,
            )
            .expect("receiver confirm");

        let receiver_device_id = receiver
            .call("device.snapshot", &json!({}), &command_context)
            .expect("receiver snapshot")["device"]["identity"]["device_id"]
            .as_str()
            .expect("receiver id")
            .to_owned();
        let send_lease = lease(
            sender.as_ref(),
            &command_context,
            "send_file",
            source.to_string_lossy().as_ref(),
        );
        let receive_lease = lease(
            receiver.as_ref(),
            &command_context,
            "destination_directory",
            destination.to_string_lossy().as_ref(),
        );

        let receiving = {
            let receiver = Arc::clone(&receiver);
            let cancelled = AtomicBool::new(false);
            let emit = |_: &str, _: Value| Ok(());
            std::thread::spawn(move || {
                let context = context(&cancelled, &emit);
                receiver.call(
                    "transfer.receive",
                    &json!({"destinationLease": receive_lease}),
                    &context,
                )
            })
        };
        std::thread::sleep(Duration::from_millis(500));
        let sending = {
            let sender = Arc::clone(&sender);
            let cancelled = AtomicBool::new(false);
            let emit = |_: &str, _: Value| Ok(());
            std::thread::spawn(move || {
                let context = context(&cancelled, &emit);
                sender.call(
                    "transfer.send",
                    &json!({"peerDeviceId": receiver_device_id, "fileLease": send_lease}),
                    &context,
                )
            })
        };
        let sent = sending.join().expect("sender thread").expect("send");
        let received = receiving.join().expect("receiver thread").expect("receive");
        assert_eq!(sent["transfer"]["job"]["state"], "completed");
        assert_eq!(received["transfer"]["job"]["state"], "completed");
        assert_eq!(
            std::fs::read(destination.join("source.txt")).expect("received file"),
            b"covio cross-device round trip"
        );
        std::fs::remove_dir_all(root).expect("cleanup");
    }

    fn lease(
        core: &ComposeCore,
        context: &CommandContext<'_>,
        purpose: &str,
        path: &str,
    ) -> String {
        let request = core
            .call(
                "capability.request",
                &json!({"kind": "file_picker", "purpose": purpose}),
                context,
            )
            .expect("capability request");
        core.call(
            "capability.complete",
            &json!({
                "requestId": request["request_id"],
                "outcome": "selected",
                "path": path,
            }),
            context,
        )
        .expect("capability complete")["lease_id"]
            .as_str()
            .expect("lease")
            .to_owned()
    }

    fn string(value: &Value, key: &str) -> String {
        value
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or_else(|| panic!("missing {key}"))
            .to_owned()
    }
}

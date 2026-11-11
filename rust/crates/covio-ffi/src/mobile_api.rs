//! JSON facade used by the iOS SwiftUI host.
//!
//! The facade stores device identity in the Rust credential vault. On Apple
//! platforms the vault root key is protected by Keychain. File transfer state
//! and checkpoints remain owned by `covio-core`.

use crate::{CovioStatusCode, FfiFailure};
use covio_core::device_pairing::{
    DeviceIdentityService, DevicePublicIdentity, PairedDevice, PairingError, PairingErrorCode,
    PairingInitiator, PairingInitiatorAwaitingConfirmation, PairingOffer, PairingResponder,
    PairingResponse,
};
use covio_core::file_transfer::{
    ControlMessage, FileStreamHeader, FileTransferOffer, IrohTransferChannel, IrohTransferEndpoint,
    RejectReason, TransferDirection, TransferError, TransferErrorCode, TransferJob,
    TransferReceiver, TransferSender, TransferSnapshot, TransferState, TransferStore,
    TransferSummary,
};
use covio_platform::{FileStore, SecretStore, StdFileStore};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::runtime::{Builder, Runtime};

#[cfg(any(target_os = "macos", target_os = "ios"))]
const DEVICE_SECRET_SERVICE: &str = "com.wyz.covio.device-identity";
const MOBILE_DIRECTORY: &str = "mobile";
const LOCAL_PROFILE_FILE: &str = "device-profile.json";
const REMOTE_PROFILES_FILE: &str = "paired-device-profiles.json";
const TRANSFER_CONTEXTS_FILE: &str = "transfer-contexts.json";
const MAX_REMOTE_PROFILES: usize = 256;
const MAX_TRANSFER_CONTEXTS: usize = 256;
const MAX_TRANSFER_HISTORY: u32 = 100;
const NETWORK_TIMEOUT: Duration = Duration::from_secs(30);
const LISTEN_POLL_TIMEOUT: Duration = Duration::from_secs(1);

type DeviceSecretStore = Box<dyn SecretStore + Send + Sync>;
type SecretFactory = Arc<dyn Fn() -> DeviceSecretStore + Send + Sync>;
type IdentityService = DeviceIdentityService<DeviceSecretStore, StdFileStore>;

/// Opaque mobile host state shared by one or more C calls.
pub struct MobileCore {
    root: PathBuf,
    files: StdFileStore,
    secret_factory: SecretFactory,
    pairing: Mutex<PairingState>,
    transfers: Mutex<BTreeMap<String, Arc<Mutex<TransferRecord>>>>,
    contexts: Mutex<BTreeMap<String, TransferContext>>,
    inbound: Mutex<Option<InboundSession>>,
    online_peers: Mutex<BTreeSet<String>>,
    listener_error: Mutex<Option<String>>,
    foreground: AtomicBool,
    shutdown: AtomicBool,
    listener_active: AtomicBool,
    generation: AtomicU64,
}

/// One C handle for the mobile JSON facade.
pub struct CovioMobileHandle {
    pub(crate) core: Arc<MobileCore>,
}

struct PairingState {
    pending: Option<PendingPairing>,
    remote_profile: Option<RemoteDeviceProfile>,
}

enum PendingPairing {
    Initiator(Box<PairingInitiator<StdFileStore>>),
    AwaitingConfirmation(Box<PairingInitiatorAwaitingConfirmation<StdFileStore>>),
    Responder(Box<PairingResponder<StdFileStore>>),
}

struct InboundSession {
    runtime: Arc<Runtime>,
    endpoint: IrohTransferEndpoint,
    channel: IrohTransferChannel,
    receiver: TransferReceiver<StdFileStore>,
    offer: FileTransferOffer,
}

#[derive(Clone)]
struct TransferRecord {
    context: TransferContext,
    state: String,
    durable_bytes: u64,
    total_bytes: u64,
    progress_percent: u8,
    error_code: Option<String>,
    error_message: Option<String>,
    final_path: Option<String>,
    pause_requested: Arc<AtomicBool>,
    generation: u64,
    updated_at_ms: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TransferContext {
    transfer_id: String,
    direction: TransferDirection,
    peer_device_id: String,
    source_path: Option<String>,
    destination_root: Option<String>,
    offer: Option<covio_core::file_transfer::FileTransferOffer>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LocalDeviceProfile {
    display_name: String,
    system_name: String,
    system_version: String,
    model: String,
    capabilities: Vec<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RemoteDeviceProfile {
    #[serde(default)]
    capabilities: Vec<String>,
    #[serde(default)]
    system_name: String,
    #[serde(default)]
    system_version: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TransferContextFile {
    version: u16,
    contexts: BTreeMap<String, TransferContext>,
}

impl Default for TransferContextFile {
    fn default() -> Self {
        Self {
            version: 1,
            contexts: BTreeMap::new(),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RemoteProfileFile {
    version: u16,
    profiles: BTreeMap<String, RemoteDeviceProfile>,
}

impl Default for RemoteProfileFile {
    fn default() -> Self {
        Self {
            version: 1,
            profiles: BTreeMap::new(),
        }
    }
}

enum WorkerOutcome {
    Completed(Box<TransferSnapshot>),
    Paused,
    Failed(TransferError),
}

enum ListenerOutcome {
    Offered(Box<(InboundSession, TransferSnapshot, TransferContext)>),
    Paused,
}

impl MobileCore {
    /// Creates mobile state rooted at one application-support directory.
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self::with_secret_factory(root, default_secret_factory())
    }

    fn with_secret_factory(root: impl Into<PathBuf>, secret_factory: SecretFactory) -> Self {
        let root = root.into();
        let files = StdFileStore::new();
        let contexts = load_contexts(&files, &root).unwrap_or_default();
        Self {
            root,
            files,
            secret_factory,
            pairing: Mutex::new(PairingState {
                pending: None,
                remote_profile: None,
            }),
            transfers: Mutex::new(BTreeMap::new()),
            contexts: Mutex::new(contexts),
            inbound: Mutex::new(None),
            online_peers: Mutex::new(BTreeSet::new()),
            listener_error: Mutex::new(None),
            foreground: AtomicBool::new(true),
            shutdown: AtomicBool::new(false),
            listener_active: AtomicBool::new(false),
            generation: AtomicU64::new(1),
        }
    }

    /// Executes one bounded mobile command.
    pub fn call(
        self: &Arc<Self>,
        command: &str,
        payload: &Value,
        now_ms: i64,
    ) -> Result<Value, FfiFailure> {
        if self.shutdown.load(Ordering::Acquire) && command != "mobile.status" {
            return Err(status_failure(
                CovioStatusCode::ShuttingDown,
                "mobile host is shut down",
            ));
        }
        match command {
            "mobile.bootstrap" => self.bootstrap(payload, now_ms),
            "mobile.status" => Ok(self.status()),
            "mobile.devices.list" => self.devices_list(),
            "mobile.pairing.begin" => self.pairing_begin(now_ms),
            "mobile.pairing.acceptOffer" => self.pairing_accept_offer(payload, now_ms),
            "mobile.pairing.completeInitiator" => self.pairing_complete_initiator(payload, now_ms),
            "mobile.pairing.confirmInitiator" => self.pairing_confirm_initiator(payload, now_ms),
            "mobile.pairing.confirmResponder" => self.pairing_confirm_responder(payload, now_ms),
            "mobile.pairing.cancel" => self.pairing_cancel(),
            "mobile.transfer.send" => self.transfer_send(payload, now_ms),
            "mobile.transfer.listen" => self.transfer_listen(payload),
            "mobile.transfer.accept" => self.transfer_accept(payload, now_ms),
            "mobile.transfer.reject" => self.transfer_reject(payload, now_ms),
            "mobile.transfer.pause" => self.transfer_pause(payload, now_ms),
            "mobile.transfer.resume" => self.transfer_resume(payload, now_ms),
            "mobile.transfer.cancel" => self.transfer_cancel(payload, now_ms),
            "mobile.transfer.list" => Ok(self.transfer_list()),
            "mobile.lifecycle.background" => self.lifecycle_background(now_ms),
            "mobile.lifecycle.foreground" => self.lifecycle_foreground(now_ms),
            "mobile.shutdown" => self.shutdown(now_ms),
            _ => Err(status_failure(
                CovioStatusCode::InvalidArgument,
                "unknown mobile command",
            )),
        }
    }

    fn bootstrap(&self, payload: &Value, now_ms: i64) -> Result<Value, FfiFailure> {
        let mut profile = local_profile_from_payload(payload)?;
        if profile.display_name.is_empty() {
            profile.display_name = "iOS Device".to_owned();
        }
        let mut identity_service = self.identity_service()?;
        let identity = identity_service
            .load_or_create_identity(&profile.display_name, now_ms)
            .map_err(pairing_failure)?;
        profile.display_name = identity.display_name.clone();
        write_json_atomic(&self.files, &self.local_profile_path(), &profile)?;
        self.sync_records(now_ms)?;
        Ok(json!({
            "identity": identity_json(&identity),
            "localDevice": profile,
            "devices": self.device_views()?,
            "status": self.status(),
        }))
    }

    fn status(&self) -> Value {
        let pending_incoming = self
            .inbound
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .as_ref()
            .map(|session| session.offer.manifest.transfer_id.clone());
        json!({
            "lifecycle": if self.shutdown.load(Ordering::Acquire) {
                "stopped"
            } else if self.foreground.load(Ordering::Acquire) {
                "foreground"
            } else {
                "background"
            },
            "listenerActive": self.listener_active.load(Ordering::Acquire),
            "listenerError": lock(&self.listener_error).clone(),
            "pendingIncomingTransferId": pending_incoming,
            "transfers": self.transfer_list()["transfers"].clone(),
        })
    }

    fn devices_list(&self) -> Result<Value, FfiFailure> {
        Ok(json!({"devices": self.device_views()?}))
    }

    fn device_views(&self) -> Result<Vec<Value>, FfiFailure> {
        let service = self.identity_service()?;
        let paired = service.trusted_devices().map_err(pairing_failure)?;
        let profiles = self.remote_profiles()?;
        let online = self
            .online_peers
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .clone();
        Ok(paired
            .into_iter()
            .map(|device| device_view(&device, profiles.get(&device.device_id), &online))
            .collect())
    }

    fn pairing_begin(&self, now_ms: i64) -> Result<Value, FfiFailure> {
        let profile = self.local_profile()?;
        let mut service = self.identity_service()?;
        let _identity = service.load_identity().map_err(pairing_failure)?;
        let initiator = service
            .begin_pairing_with_profile(
                &profile.capabilities,
                &profile.system_name,
                &profile.system_version,
                now_ms,
            )
            .map_err(pairing_failure)?;
        let qr_payload = initiator.offer().to_qr_payload().map_err(pairing_failure)?;
        let offer = initiator.offer().clone();
        let expires_at_ms = offer.expires_at_ms;
        let mut pairing = lock(&self.pairing);
        pairing.pending = Some(PendingPairing::Initiator(Box::new(initiator)));
        pairing.remote_profile = None;
        Ok(json!({
            "offer": offer,
            "qrPayload": qr_payload,
            "expiresAtMs": expires_at_ms,
        }))
    }

    fn pairing_accept_offer(&self, payload: &Value, now_ms: i64) -> Result<Value, FfiFailure> {
        let qr_payload = string_field(payload, "qrPayload")?;
        let offer = PairingOffer::from_qr_payload(qr_payload).map_err(pairing_failure)?;
        let remote_profile = RemoteDeviceProfile {
            capabilities: offer.capabilities.clone(),
            system_name: offer.sender_system_name.clone(),
            system_version: offer.sender_system_version.clone(),
        };
        let mut service = self.identity_service()?;
        let local_profile = self.local_profile()?;
        let _identity = service.load_identity().map_err(pairing_failure)?;
        let responder = service
            .accept_pairing_offer_with_profile(
                &offer,
                &local_profile.capabilities,
                &local_profile.system_name,
                &local_profile.system_version,
                now_ms,
            )
            .map_err(pairing_failure)?;
        let response_payload = responder
            .response()
            .to_wire_payload()
            .map_err(pairing_failure)?;
        let confirmation_code = responder.code().to_owned();
        let remote_device = responder.remote_device().clone();
        let mut pairing = lock(&self.pairing);
        pairing.pending = Some(PendingPairing::Responder(Box::new(responder)));
        pairing.remote_profile = Some(remote_profile.clone());
        Ok(json!({
            "responsePayload": response_payload,
            "confirmationCode": confirmation_code,
            "remoteDevice": paired_device_json(&remote_device),
            "remoteCapabilities": remote_profile.capabilities,
            "remoteSystemName": remote_profile.system_name,
            "remoteSystemVersion": remote_profile.system_version,
        }))
    }

    fn pairing_complete_initiator(
        &self,
        payload: &Value,
        now_ms: i64,
    ) -> Result<Value, FfiFailure> {
        let response_payload = string_field(payload, "responsePayload")?;
        let response =
            PairingResponse::from_wire_payload(response_payload).map_err(pairing_failure)?;
        let mut pairing = lock(&self.pairing);
        let pending = pairing.pending.take().ok_or_else(|| {
            status_failure(CovioStatusCode::Conflict, "no pairing session is active")
        })?;
        let PendingPairing::Initiator(initiator) = pending else {
            pairing.pending = Some(pending);
            return Err(status_failure(
                CovioStatusCode::Conflict,
                "pairing session is not waiting for a response",
            ));
        };
        let awaiting = (*initiator)
            .complete(&response, now_ms)
            .map_err(pairing_failure)?;
        let confirmation_code = awaiting.code().to_owned();
        let remote_device = awaiting.remote_device().clone();
        pairing.pending = Some(PendingPairing::AwaitingConfirmation(Box::new(awaiting)));
        pairing.remote_profile = Some(RemoteDeviceProfile {
            capabilities: response.responder_capabilities,
            system_name: response.responder_system_name,
            system_version: response.responder_system_version,
        });
        Ok(json!({
            "confirmationCode": confirmation_code,
            "remoteDevice": paired_device_json(&remote_device),
        }))
    }

    fn pairing_confirm_initiator(&self, payload: &Value, now_ms: i64) -> Result<Value, FfiFailure> {
        let confirmation_code = string_field(payload, "confirmationCode")?;
        let mut pairing = lock(&self.pairing);
        let pending = pairing.pending.take().ok_or_else(|| {
            status_failure(CovioStatusCode::Conflict, "no pairing session is active")
        })?;
        let PendingPairing::AwaitingConfirmation(awaiting) = pending else {
            pairing.pending = Some(pending);
            return Err(status_failure(
                CovioStatusCode::Conflict,
                "pairing session is not awaiting confirmation",
            ));
        };
        let remote_device = awaiting.remote_device().clone();
        (*awaiting)
            .finish(confirmation_code, now_ms)
            .map_err(pairing_failure)?;
        let remote_profile = pairing.remote_profile.clone().unwrap_or_default();
        drop(pairing);
        self.save_remote_profile(&remote_device.device_id, remote_profile)?;
        Ok(json!({"device": paired_device_json(&remote_device), "devices": self.device_views()?}))
    }

    fn pairing_confirm_responder(&self, payload: &Value, now_ms: i64) -> Result<Value, FfiFailure> {
        let confirmation_code = string_field(payload, "confirmationCode")?;
        let mut pairing = lock(&self.pairing);
        let pending = pairing.pending.take().ok_or_else(|| {
            status_failure(CovioStatusCode::Conflict, "no pairing session is active")
        })?;
        let PendingPairing::Responder(responder) = pending else {
            pairing.pending = Some(pending);
            return Err(status_failure(
                CovioStatusCode::Conflict,
                "pairing session is not waiting for responder confirmation",
            ));
        };
        let remote_device = responder.remote_device().clone();
        (*responder)
            .finish(confirmation_code, now_ms)
            .map_err(pairing_failure)?;
        let remote_profile = pairing.remote_profile.clone().unwrap_or_default();
        drop(pairing);
        self.save_remote_profile(&remote_device.device_id, remote_profile)?;
        Ok(json!({"device": paired_device_json(&remote_device), "devices": self.device_views()?}))
    }

    fn pairing_cancel(&self) -> Result<Value, FfiFailure> {
        let mut pairing = lock(&self.pairing);
        pairing.pending = None;
        pairing.remote_profile = None;
        Ok(json!({"cancelled": true}))
    }

    fn transfer_send(self: &Arc<Self>, payload: &Value, now_ms: i64) -> Result<Value, FfiFailure> {
        if !self.foreground.load(Ordering::Acquire) {
            return Err(status_failure(
                CovioStatusCode::Unsupported,
                "start a transfer while the host is in the foreground",
            ));
        }
        let source_path = string_field(payload, "sourcePath")?.to_owned();
        let peer_device_id = string_field(payload, "peerDeviceId")?.to_owned();
        let service = self.identity_service()?;
        let identity = service.load_identity().map_err(pairing_failure)?;
        let trusted = service
            .is_trusted(&peer_device_id)
            .map_err(pairing_failure)?;
        if !trusted {
            return Err(status_failure(
                CovioStatusCode::InvalidArgument,
                "peer device is not trusted",
            ));
        }
        let store = self.transfer_store()?;
        let transfer_id = random_transfer_id()?;
        let (sender, offer, snapshot) = TransferSender::create(
            store,
            self.files,
            &source_path,
            &transfer_id,
            identity.device_id,
            &peer_device_id,
            now_ms,
        )
        .map_err(transfer_failure)?;
        drop(sender);
        let context = TransferContext {
            transfer_id: transfer_id.clone(),
            direction: TransferDirection::Send,
            peer_device_id,
            source_path: Some(source_path),
            destination_root: None,
            offer: Some(offer),
        };
        self.put_context(context.clone())?;
        let record = self.insert_record(context, snapshot, now_ms)?;
        self.spawn_send(Arc::clone(&record))?;
        Ok(record_json(&lock(&record)))
    }

    fn transfer_listen(self: &Arc<Self>, payload: &Value) -> Result<Value, FfiFailure> {
        if !self.foreground.load(Ordering::Acquire) {
            return Err(status_failure(
                CovioStatusCode::Unsupported,
                "start receiving while the host is in the foreground",
            ));
        }
        let destination_root = string_field(payload, "destinationPath")?.to_owned();
        if self
            .listener_active
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            return Err(status_failure(
                CovioStatusCode::Conflict,
                "a receive listener is already active",
            ));
        }
        let core = Arc::clone(self);
        let spawn_result = std::thread::Builder::new()
            .name("covio-ios-receive-listener".to_owned())
            .spawn(move || core.run_listener(destination_root));
        if spawn_result.is_err() {
            self.listener_active.store(false, Ordering::Release);
            return Err(status_failure(
                CovioStatusCode::Internal,
                "receive listener thread could not start",
            ));
        }
        Ok(json!({"listenerActive": true}))
    }

    fn transfer_accept(
        self: &Arc<Self>,
        payload: &Value,
        now_ms: i64,
    ) -> Result<Value, FfiFailure> {
        if !self.foreground.load(Ordering::Acquire) {
            return Err(status_failure(
                CovioStatusCode::Unsupported,
                "accept a transfer while the host is in the foreground",
            ));
        }
        let transfer_id = string_field(payload, "transferId")?.to_owned();
        let mut inbound = lock(&self.inbound);
        let session = inbound.take().ok_or_else(|| {
            status_failure(CovioStatusCode::Conflict, "no incoming offer is pending")
        })?;
        if session.offer.manifest.transfer_id != transfer_id {
            *inbound = Some(session);
            return Err(status_failure(
                CovioStatusCode::Conflict,
                "pending offer does not match the transfer",
            ));
        }
        drop(inbound);
        let record = self.record(&transfer_id)?;
        let generation = self.next_generation();
        {
            let mut value = lock(&record);
            value.state = TransferState::Transferring.as_str().to_owned();
            value.generation = generation;
            value.pause_requested = Arc::new(AtomicBool::new(false));
            value.updated_at_ms = now_ms;
        }
        let core = Arc::clone(self);
        std::thread::Builder::new()
            .name("covio-ios-receive-transfer".to_owned())
            .spawn(move || core.run_receive(session, transfer_id, generation))
            .map_err(|_| {
                status_failure(
                    CovioStatusCode::Internal,
                    "receive transfer thread could not start",
                )
            })?;
        Ok(record_json(&lock(&record)))
    }

    fn transfer_reject(
        self: &Arc<Self>,
        payload: &Value,
        now_ms: i64,
    ) -> Result<Value, FfiFailure> {
        let transfer_id = string_field(payload, "transferId")?.to_owned();
        let mut inbound = lock(&self.inbound);
        let session = inbound.take().ok_or_else(|| {
            status_failure(CovioStatusCode::Conflict, "no incoming offer is pending")
        })?;
        if session.offer.manifest.transfer_id != transfer_id {
            *inbound = Some(session);
            return Err(status_failure(
                CovioStatusCode::Conflict,
                "pending offer does not match the transfer",
            ));
        }
        drop(inbound);
        let InboundSession {
            runtime,
            endpoint,
            mut channel,
            ..
        } = session;
        runtime.block_on(async {
            send_control_bounded(
                &mut channel,
                ControlMessage::Reject {
                    reason: RejectReason::Declined,
                },
            )
            .await
            .map_err(transfer_failure)?;
            channel.close();
            endpoint.close().await;
            Ok::<(), FfiFailure>(())
        })?;
        let store = self.transfer_store()?;
        store
            .reject(&transfer_id, now_ms)
            .map_err(transfer_failure)?;
        let record = self.record(&transfer_id)?;
        let mut value = lock(&record);
        value.state = TransferState::Rejected.as_str().to_owned();
        value.updated_at_ms = now_ms;
        Ok(record_json(&value))
    }

    fn transfer_pause(&self, payload: &Value, now_ms: i64) -> Result<Value, FfiFailure> {
        let transfer_id = string_field(payload, "transferId")?;
        let record = self.record(transfer_id)?;
        let generation = self.next_generation();
        let mut inbound = lock(&self.inbound);
        if inbound
            .as_ref()
            .is_some_and(|session| session.offer.manifest.transfer_id == transfer_id)
            && let Some(session) = inbound.take()
        {
            session.channel.close();
        }
        drop(inbound);
        self.pause_record(&record, generation, now_ms, false)?;
        Ok(record_json(&lock(&record)))
    }

    fn transfer_resume(
        self: &Arc<Self>,
        payload: &Value,
        now_ms: i64,
    ) -> Result<Value, FfiFailure> {
        if !self.foreground.load(Ordering::Acquire) {
            return Err(status_failure(
                CovioStatusCode::Unsupported,
                "resume a transfer while the host is in the foreground",
            ));
        }
        let transfer_id = string_field(payload, "transferId")?;
        let record = self.record(transfer_id)?;
        self.resume_record(record, now_ms, false)?;
        let record = self.record(transfer_id)?;
        Ok(record_json(&lock(&record)))
    }

    fn transfer_cancel(&self, payload: &Value, now_ms: i64) -> Result<Value, FfiFailure> {
        let transfer_id = string_field(payload, "transferId")?;
        let record = self.record(transfer_id)?;
        let context = lock(&record).context.clone();
        let generation = self.next_generation();
        {
            let mut value = lock(&record);
            value.generation = generation;
            value.pause_requested.store(true, Ordering::Release);
        }
        let mut inbound = lock(&self.inbound);
        if inbound
            .as_ref()
            .is_some_and(|session| session.offer.manifest.transfer_id == transfer_id)
            && let Some(session) = inbound.take()
        {
            session.channel.close();
        }
        drop(inbound);
        let store = self.transfer_store()?;
        store
            .cancel(transfer_id, context.direction, now_ms)
            .map_err(transfer_failure)?;
        let mut value = lock(&record);
        value.state = TransferState::Cancelled.as_str().to_owned();
        value.updated_at_ms = now_ms;
        Ok(record_json(&value))
    }

    fn transfer_list(&self) -> Value {
        let mut transfers = self
            .transfers
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .values()
            .map(|record| record_json(&lock(record)))
            .collect::<Vec<_>>();
        transfers.sort_by(|left, right| {
            right
                .get("updatedAtMs")
                .and_then(Value::as_i64)
                .cmp(&left.get("updatedAtMs").and_then(Value::as_i64))
        });
        json!({"transfers": transfers})
    }

    fn lifecycle_background(&self, now_ms: i64) -> Result<Value, FfiFailure> {
        if self.shutdown.load(Ordering::Acquire) {
            return Ok(self.status());
        }
        self.foreground.store(false, Ordering::Release);
        let records = self
            .transfers
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .values()
            .cloned()
            .collect::<Vec<_>>();
        for record in records {
            if is_terminal(&lock(&record).state) {
                continue;
            }
            let generation = self.next_generation();
            self.pause_record(&record, generation, now_ms, true)?;
        }
        if let Some(session) = lock(&self.inbound).take() {
            session.channel.close();
        }
        Ok(self.status())
    }

    fn lifecycle_foreground(self: &Arc<Self>, now_ms: i64) -> Result<Value, FfiFailure> {
        if self.shutdown.load(Ordering::Acquire) {
            return Ok(self.status());
        }
        if self.foreground.swap(true, Ordering::AcqRel) {
            return Ok(json!({"status": self.status(), "resumedTransferIds": []}));
        }
        let records = self
            .transfers
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .values()
            .cloned()
            .collect::<Vec<_>>();
        let mut resumed = Vec::new();
        for record in records {
            let (state, transfer_id) = {
                let value = lock(&record);
                (value.state.clone(), value.context.transfer_id.clone())
            };
            if matches!(
                state.as_str(),
                "paused" | "background_deferred" | "waiting_network" | "offer_waiting"
            ) && self
                .resume_record(Arc::clone(&record), now_ms, true)
                .is_ok()
            {
                resumed.push(transfer_id);
            }
        }
        Ok(json!({"status": self.status(), "resumedTransferIds": resumed}))
    }

    fn shutdown(&self, now_ms: i64) -> Result<Value, FfiFailure> {
        self.foreground.store(false, Ordering::Release);
        let records = self
            .transfers
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .values()
            .cloned()
            .collect::<Vec<_>>();
        for record in records {
            if !is_terminal(&lock(&record).state) {
                let generation = self.next_generation();
                let _ = self.pause_record(&record, generation, now_ms, true);
            }
        }
        if let Some(session) = lock(&self.inbound).take() {
            session.channel.close();
        }
        self.shutdown.store(true, Ordering::Release);
        Ok(self.status())
    }

    fn pause_record(
        &self,
        record: &Arc<Mutex<TransferRecord>>,
        generation: u64,
        now_ms: i64,
        background: bool,
    ) -> Result<(), FfiFailure> {
        let context = lock(record).context.clone();
        let store = self.transfer_store()?;
        if let Ok(job) = store.job(&context.transfer_id)
            && job.state == TransferState::Transferring
        {
            if background {
                store
                    .background(&context.transfer_id, now_ms)
                    .map_err(transfer_failure)?;
            } else {
                store
                    .pause(&context.transfer_id, now_ms)
                    .map_err(transfer_failure)?;
            }
        }
        let mut value = lock(record);
        value.generation = generation;
        value.pause_requested.store(true, Ordering::Release);
        value.state = if background {
            TransferState::BackgroundDeferred.as_str().to_owned()
        } else {
            TransferState::Paused.as_str().to_owned()
        };
        value.updated_at_ms = now_ms;
        Ok(())
    }

    fn resume_record(
        self: &Arc<Self>,
        record: Arc<Mutex<TransferRecord>>,
        now_ms: i64,
        automatic: bool,
    ) -> Result<(), FfiFailure> {
        let context = lock(&record).context.clone();
        let store = self.transfer_store()?;
        let job = store.job(&context.transfer_id).map_err(transfer_failure)?;
        if is_terminal(job.state.as_str()) {
            return Err(status_failure(
                CovioStatusCode::Conflict,
                "completed or closed transfer cannot resume",
            ));
        }
        {
            let mut value = lock(&record);
            value.state = if context.direction == TransferDirection::Send {
                TransferState::OfferWaiting.as_str().to_owned()
            } else {
                TransferState::AwaitingAcceptance.as_str().to_owned()
            };
            value.updated_at_ms = now_ms;
        }
        match context.direction {
            TransferDirection::Send => self.spawn_send(record),
            TransferDirection::Receive => {
                if automatic && self.listener_active.load(Ordering::Acquire) {
                    return Ok(());
                }
                let destination = context.destination_root.clone().ok_or_else(|| {
                    status_failure(
                        CovioStatusCode::Internal,
                        "receive context has no destination",
                    )
                })?;
                self.transfer_listen(&json!({"destinationPath": destination}))
                    .map(|_| ())
            }
        }
    }

    fn spawn_send(self: &Arc<Self>, record: Arc<Mutex<TransferRecord>>) -> Result<(), FfiFailure> {
        let generation = self.next_generation();
        {
            let mut value = lock(&record);
            value.generation = generation;
            value.pause_requested = Arc::new(AtomicBool::new(false));
            value.state = TransferState::OfferWaiting.as_str().to_owned();
        }
        let core = Arc::clone(self);
        let transfer_id = lock(&record).context.transfer_id.clone();
        std::thread::Builder::new()
            .name("covio-ios-send-transfer".to_owned())
            .spawn(move || core.run_send(record, transfer_id, generation))
            .map_err(|_| {
                status_failure(
                    CovioStatusCode::Internal,
                    "send transfer thread could not start",
                )
            })?;
        Ok(())
    }

    fn run_send(
        self: Arc<Self>,
        record: Arc<Mutex<TransferRecord>>,
        transfer_id: String,
        generation: u64,
    ) {
        let outcome = match mobile_runtime() {
            Ok(runtime) => runtime.block_on(self.send_transfer(&record, &transfer_id)),
            Err(error) => WorkerOutcome::Failed(error),
        };
        self.finish_worker(&record, &transfer_id, generation, outcome);
    }

    async fn send_transfer(
        self: &Arc<Self>,
        record: &Arc<Mutex<TransferRecord>>,
        transfer_id: &str,
    ) -> WorkerOutcome {
        let context = lock(record).context.clone();
        let pause_requested = lock(record).pause_requested.clone();
        if pause_requested.load(Ordering::Acquire) {
            return WorkerOutcome::Paused;
        }
        let offer = match context.offer.clone() {
            Some(offer) => offer,
            None => {
                return WorkerOutcome::Failed(TransferError::new(
                    TransferErrorCode::Internal,
                    "send context has no offer",
                    false,
                ));
            }
        };
        let source_path = match context.source_path.as_ref() {
            Some(path) => PathBuf::from(path),
            None => {
                return WorkerOutcome::Failed(TransferError::new(
                    TransferErrorCode::Internal,
                    "send context has no source path",
                    false,
                ));
            }
        };
        let peer_public_key = match self.peer_public_key(&context.peer_device_id) {
            Ok(key) => key,
            Err(error) => return WorkerOutcome::Failed(error),
        };
        let service = match self.identity_service() {
            Ok(service) => service,
            Err(error) => return WorkerOutcome::Failed(transfer_error_from_ffi(&error)),
        };
        let endpoint =
            match tokio::time::timeout(NETWORK_TIMEOUT, service.bind_transfer_endpoint()).await {
                Ok(Ok(endpoint)) => endpoint,
                Ok(Err(error)) => return WorkerOutcome::Failed(error),
                Err(_) => return WorkerOutcome::Failed(transport_timeout()),
            };
        let _ = tokio::time::timeout(NETWORK_TIMEOUT, endpoint.wait_online()).await;
        if pause_requested.load(Ordering::Acquire) {
            endpoint.close().await;
            return WorkerOutcome::Paused;
        }
        let mut channel = match tokio::time::timeout(
            NETWORK_TIMEOUT,
            endpoint.connect_trusted_public_key(&peer_public_key),
        )
        .await
        {
            Ok(Ok(channel)) => channel,
            Ok(Err(error)) => {
                endpoint.close().await;
                return WorkerOutcome::Failed(error);
            }
            Err(_) => {
                endpoint.close().await;
                return WorkerOutcome::Failed(transport_timeout());
            }
        };
        lock(&self.online_peers).insert(context.peer_device_id.clone());
        let store = match self.transfer_store() {
            Ok(store) => store,
            Err(error) => return WorkerOutcome::Failed(transfer_error_from_ffi(&error)),
        };
        let mut sender =
            match TransferSender::reopen(store.clone(), self.files, &source_path, transfer_id) {
                Ok(sender) => sender,
                Err(error) => return WorkerOutcome::Failed(error),
            };
        let job = match store.job(transfer_id) {
            Ok(job) => job,
            Err(error) => return WorkerOutcome::Failed(error),
        };
        let resume_from = job.durable_bytes;
        if let Err(error) =
            send_control_bounded(&mut channel, ControlMessage::Offer { offer, resume_from }).await
        {
            return WorkerOutcome::Failed(error);
        }
        let accepted = match receive_control_bounded(&mut channel).await {
            Ok(envelope) => envelope.message,
            Err(error) => return WorkerOutcome::Failed(error),
        };
        let durable_bytes = match accepted {
            ControlMessage::Accept { durable_bytes } => durable_bytes,
            ControlMessage::Reject { .. } => {
                let _ = store.reject(transfer_id, now_ms());
                return WorkerOutcome::Failed(TransferError::new(
                    TransferErrorCode::OfferRejected,
                    "receiver rejected the transfer",
                    false,
                ));
            }
            _ => {
                return WorkerOutcome::Failed(TransferError::new(
                    TransferErrorCode::ManifestInvalid,
                    "receiver sent an unexpected response",
                    false,
                ));
            }
        };
        let accepted_offset = if job.state == TransferState::OfferWaiting {
            sender.accept(durable_bytes, now_ms())
        } else {
            sender.resume(durable_bytes, now_ms())
        };
        let accepted_offset = match accepted_offset {
            Ok(offset) => offset,
            Err(error) => return WorkerOutcome::Failed(error),
        };
        {
            let mut value = lock(record);
            self.update_from_job(&mut value, store.job(transfer_id).ok().as_ref());
        }
        let manifest = sender.manifest().clone();
        let header = match FileStreamHeader::from_manifest(&manifest) {
            Ok(header) => header,
            Err(error) => return WorkerOutcome::Failed(error),
        };
        if let Err(error) = send_file_header_bounded(&mut channel, &header).await {
            return WorkerOutcome::Failed(error);
        }
        let mut last_offset = accepted_offset;
        loop {
            if pause_requested.load(Ordering::Acquire) {
                let _ = sender.background(now_ms());
                channel.close();
                endpoint.close().await;
                return WorkerOutcome::Paused;
            }
            let frames = match sender.read_window() {
                Ok(frames) => frames,
                Err(error) => return WorkerOutcome::Failed(error),
            };
            if frames.is_empty() {
                break;
            }
            for frame in frames {
                if pause_requested.load(Ordering::Acquire) {
                    let _ = sender.background(now_ms());
                    channel.close();
                    endpoint.close().await;
                    return WorkerOutcome::Paused;
                }
                if let Err(error) = send_chunk_bounded(&mut channel, &frame).await {
                    return WorkerOutcome::Failed(error);
                }
                let envelope = match receive_control_bounded(&mut channel).await {
                    Ok(envelope) => envelope,
                    Err(error) => return WorkerOutcome::Failed(error),
                };
                let checkpoint = match envelope.message {
                    ControlMessage::Checkpoint { durable_bytes } => durable_bytes,
                    ControlMessage::Cancel { .. } => {
                        let _ = store.cancel(transfer_id, TransferDirection::Send, now_ms());
                        return WorkerOutcome::Failed(TransferError::new(
                            TransferErrorCode::CancelledByReceiver,
                            "receiver cancelled the transfer",
                            false,
                        ));
                    }
                    _ => {
                        return WorkerOutcome::Failed(TransferError::new(
                            TransferErrorCode::ManifestInvalid,
                            "receiver sent an unexpected checkpoint",
                            false,
                        ));
                    }
                };
                if let Err(error) = sender.acknowledge(checkpoint, now_ms()) {
                    return WorkerOutcome::Failed(error);
                }
                last_offset = checkpoint;
                {
                    let mut value = lock(record);
                    self.update_progress(&mut value, checkpoint, manifest.size);
                }
            }
        }
        if let Err(error) = channel.finish_file() {
            return WorkerOutcome::Failed(error);
        }
        let completed = match receive_control_bounded(&mut channel).await {
            Ok(envelope) => envelope.message,
            Err(error) => return WorkerOutcome::Failed(error),
        };
        let digest = match completed {
            ControlMessage::Complete { blake3 } => blake3,
            _ => {
                return WorkerOutcome::Failed(TransferError::new(
                    TransferErrorCode::ManifestInvalid,
                    "receiver sent an unexpected completion",
                    false,
                ));
            }
        };
        if digest != manifest.blake3 {
            return WorkerOutcome::Failed(TransferError::new(
                TransferErrorCode::FileHashMismatch,
                "receiver reported a different file digest",
                false,
            ));
        }
        if last_offset != manifest.size {
            return WorkerOutcome::Failed(TransferError::new(
                TransferErrorCode::ResumeCheckpointInvalid,
                "sender finished before the receiver checkpoint",
                false,
            ));
        }
        let snapshot = match sender.complete(now_ms()) {
            Ok(snapshot) => snapshot,
            Err(error) => return WorkerOutcome::Failed(error),
        };
        channel.close();
        endpoint.close().await;
        WorkerOutcome::Completed(Box::new(snapshot))
    }

    fn run_listener(self: Arc<Self>, destination_root: String) {
        lock(&self.listener_error).take();
        let result = self.listen_once(&destination_root);
        self.listener_active.store(false, Ordering::Release);
        match result {
            Ok(ListenerOutcome::Offered(payload)) => {
                let (session, snapshot, context) = *payload;
                let transfer_id = context.transfer_id.clone();
                if self
                    .insert_record(context, snapshot, now_ms())
                    .map(|record| {
                        let mut value = lock(&record);
                        value.state = TransferState::AwaitingAcceptance.as_str().to_owned();
                    })
                    .is_err()
                {
                    session.channel.close();
                    let runtime = Arc::clone(&session.runtime);
                    runtime.block_on(session.endpoint.close());
                    return;
                }
                if let Some(previous) = lock(&self.inbound).replace(session) {
                    previous.channel.close();
                    let runtime = Arc::clone(&previous.runtime);
                    runtime.block_on(previous.endpoint.close());
                }
                if let Ok(record) = self.record(&transfer_id) {
                    let peer = lock(&record).context.peer_device_id.clone();
                    lock(&self.online_peers).insert(peer);
                }
            }
            Ok(ListenerOutcome::Paused) => {}
            Err(error) => {
                *lock(&self.listener_error) =
                    Some(format!("{}: {}", error.code().as_str(), error.message()));
            }
        }
    }

    fn listen_once(&self, destination_root: &str) -> Result<ListenerOutcome, TransferError> {
        let runtime = mobile_runtime()?;
        let service = self
            .identity_service()
            .map_err(|error| transfer_error_from_ffi(&error))?;
        let trusted = service.trusted_devices().map_err(pairing_to_transfer)?;
        let endpoint = runtime.block_on(async {
            let endpoint = service.bind_transfer_endpoint().await?;
            let _ = tokio::time::timeout(NETWORK_TIMEOUT, endpoint.wait_online()).await;
            Ok::<IrohTransferEndpoint, TransferError>(endpoint)
        })?;
        let mut channel = loop {
            if !self.foreground.load(Ordering::Acquire) || self.shutdown.load(Ordering::Acquire) {
                runtime.block_on(endpoint.close());
                return Ok(ListenerOutcome::Paused);
            }
            match runtime.block_on(endpoint.accept_one_with_timeout(LISTEN_POLL_TIMEOUT)) {
                Ok(Some(channel)) => break channel,
                Ok(None) => continue,
                Err(error) => {
                    runtime.block_on(endpoint.close());
                    return Err(error);
                }
            }
        };
        let remote_key = channel.remote_public_key_hex();
        let Some(peer) = trusted
            .into_iter()
            .find(|device| device.public_key == remote_key)
        else {
            channel.close();
            runtime.block_on(endpoint.close());
            return Err(TransferError::new(
                TransferErrorCode::PeerIdentityChanged,
                "incoming peer is not a trusted device",
                false,
            ));
        };
        let envelope = match runtime.block_on(async {
            tokio::time::timeout(NETWORK_TIMEOUT, channel.receive_control()).await
        }) {
            Ok(Ok(envelope)) => envelope,
            Ok(Err(error)) => {
                channel.close();
                runtime.block_on(endpoint.close());
                return Err(error);
            }
            Err(_) => {
                channel.close();
                runtime.block_on(endpoint.close());
                return Err(transport_timeout());
            }
        };
        let offer = match envelope.message {
            ControlMessage::Offer { offer, .. } => offer,
            _ => {
                channel.close();
                runtime.block_on(endpoint.close());
                return Err(TransferError::new(
                    TransferErrorCode::ManifestInvalid,
                    "peer did not send a file offer",
                    false,
                ));
            }
        };
        if offer.manifest.sender_device_id != peer.device_id {
            channel.close();
            runtime.block_on(endpoint.close());
            return Err(TransferError::new(
                TransferErrorCode::PeerIdentityChanged,
                "offer sender does not match the trusted peer",
                false,
            ));
        }
        let store = self
            .transfer_store()
            .map_err(|error| transfer_error_from_ffi(&error))?;
        let receiver = TransferReceiver::new(store.clone(), self.files, destination_root);
        let snapshot = match store.job(&offer.manifest.transfer_id) {
            Ok(job) => {
                if job.manifest_hash != offer.manifest_hash || job.peer_device_id != peer.device_id
                {
                    channel.close();
                    runtime.block_on(endpoint.close());
                    return Err(TransferError::new(
                        TransferErrorCode::ManifestInvalid,
                        "resumed offer does not match the durable transfer",
                        false,
                    ));
                }
                snapshot_from_job(job)
            }
            Err(_) => receiver.receive_offer(&offer, now_ms())?,
        };
        let context = TransferContext {
            transfer_id: offer.manifest.transfer_id.clone(),
            direction: TransferDirection::Receive,
            peer_device_id: peer.device_id,
            source_path: None,
            destination_root: Some(destination_root.to_owned()),
            offer: Some(offer.clone()),
        };
        Ok(ListenerOutcome::Offered(Box::new((
            InboundSession {
                runtime: Arc::new(runtime),
                endpoint,
                channel,
                receiver,
                offer,
            },
            snapshot,
            context,
        ))))
    }

    fn run_receive(self: Arc<Self>, session: InboundSession, transfer_id: String, generation: u64) {
        let record = match self.record(&transfer_id) {
            Ok(record) => record,
            Err(error) => {
                session.channel.close();
                let runtime = Arc::clone(&session.runtime);
                runtime.block_on(session.endpoint.close());
                let _ = error;
                return;
            }
        };
        let runtime = Arc::clone(&session.runtime);
        let outcome =
            runtime.block_on(self.receive_transfer(record.clone(), &transfer_id, session));
        self.finish_worker(&record, &transfer_id, generation, outcome);
    }

    async fn receive_transfer(
        self: &Arc<Self>,
        record: Arc<Mutex<TransferRecord>>,
        transfer_id: &str,
        session: InboundSession,
    ) -> WorkerOutcome {
        let InboundSession {
            endpoint,
            mut channel,
            receiver,
            offer,
            runtime: _,
        } = session;
        let pause_requested = lock(&record).pause_requested.clone();
        let job = match receiver.store().job(transfer_id) {
            Ok(job) => job,
            Err(error) => return WorkerOutcome::Failed(error),
        };
        let resume_from = job.durable_bytes;
        let plan = if job.state == TransferState::AwaitingAcceptance {
            receiver.accept(transfer_id, resume_from, now_ms())
        } else {
            receiver.resume(transfer_id, resume_from, now_ms())
        };
        if let Err(error) = plan {
            channel.close();
            endpoint.close().await;
            return WorkerOutcome::Failed(error);
        }
        if let Err(error) = send_control_bounded(
            &mut channel,
            ControlMessage::Accept {
                durable_bytes: resume_from,
            },
        )
        .await
        {
            channel.close();
            endpoint.close().await;
            return WorkerOutcome::Failed(error);
        }
        let header = match receive_file_header_bounded(&mut channel).await {
            Ok(header) => header,
            Err(error) => {
                channel.close();
                endpoint.close().await;
                return WorkerOutcome::Failed(error);
            }
        };
        if header.transfer_id != transfer_id
            || header.total_size != offer.manifest.size
            || hex(&header.blake3) != offer.manifest.blake3
            || header.chunk_size != offer.manifest.chunk_size
        {
            channel.close();
            endpoint.close().await;
            return WorkerOutcome::Failed(TransferError::new(
                TransferErrorCode::ManifestInvalid,
                "file stream header does not match the offer",
                false,
            ));
        }
        let mut durable_bytes = resume_from;
        while durable_bytes < offer.manifest.size {
            if pause_requested.load(Ordering::Acquire) {
                let _ = receiver.background(transfer_id, now_ms());
                channel.close();
                endpoint.close().await;
                return WorkerOutcome::Paused;
            }
            let frame = match receive_chunk_bounded(&mut channel).await {
                Ok(frame) => frame,
                Err(error) => {
                    channel.close();
                    endpoint.close().await;
                    return WorkerOutcome::Failed(error);
                }
            };
            let outcome = match receiver.receive_chunk(transfer_id, &frame, now_ms()) {
                Ok(outcome) => outcome,
                Err(error) => {
                    channel.close();
                    endpoint.close().await;
                    return WorkerOutcome::Failed(error);
                }
            };
            durable_bytes = outcome.durable_bytes;
            if let Err(error) =
                send_control_bounded(&mut channel, ControlMessage::Checkpoint { durable_bytes })
                    .await
            {
                channel.close();
                endpoint.close().await;
                return WorkerOutcome::Failed(error);
            }
            {
                let mut value = lock(&record);
                self.update_progress(&mut value, durable_bytes, offer.manifest.size);
            }
        }
        let snapshot = match receiver.complete(transfer_id, now_ms()) {
            Ok(snapshot) => snapshot,
            Err(error) => {
                channel.close();
                endpoint.close().await;
                return WorkerOutcome::Failed(error);
            }
        };
        let digest = snapshot.job.manifest.blake3.clone();
        if let Err(error) =
            send_control_bounded(&mut channel, ControlMessage::Complete { blake3: digest }).await
        {
            channel.close();
            endpoint.close().await;
            return WorkerOutcome::Failed(error);
        }
        channel.close();
        endpoint.close().await;
        WorkerOutcome::Completed(Box::new(snapshot))
    }

    fn finish_worker(
        &self,
        record: &Arc<Mutex<TransferRecord>>,
        transfer_id: &str,
        generation: u64,
        outcome: WorkerOutcome,
    ) {
        if lock(record).generation != generation {
            return;
        }
        let peer_device_id = lock(record).context.peer_device_id.clone();
        match outcome {
            WorkerOutcome::Completed(snapshot) => {
                let mut value = lock(record);
                self.apply_snapshot(&mut value, *snapshot);
            }
            WorkerOutcome::Paused => {
                let mut value = lock(record);
                if !is_terminal(&value.state) {
                    value.state = TransferState::BackgroundDeferred.as_str().to_owned();
                    value.updated_at_ms = now_ms();
                }
            }
            WorkerOutcome::Failed(error) => {
                let now = now_ms();
                if error.code() == TransferErrorCode::TransportOffline {
                    if let Ok(store) = self.transfer_store() {
                        let _ = store.waiting_network(transfer_id, now);
                    }
                    let mut value = lock(record);
                    value.state = TransferState::WaitingNetwork.as_str().to_owned();
                    value.error_code = Some(error.code().as_str().to_owned());
                    value.error_message = Some(error.message().to_owned());
                    value.updated_at_ms = now;
                } else {
                    if let Ok(store) = self.transfer_store() {
                        let _ = store.fail(transfer_id, error.code(), now);
                    }
                    self.mark_error(record, &error);
                }
            }
        }
        lock(&self.online_peers).remove(&peer_device_id);
    }

    fn mark_error(&self, record: &Arc<Mutex<TransferRecord>>, error: &TransferError) {
        let mut value = lock(record);
        value.state = TransferState::Failed.as_str().to_owned();
        value.error_code = Some(error.code().as_str().to_owned());
        value.error_message = Some(error.message().to_owned());
        value.updated_at_ms = now_ms();
    }

    fn insert_record(
        &self,
        context: TransferContext,
        snapshot: TransferSnapshot,
        now_ms: i64,
    ) -> Result<Arc<Mutex<TransferRecord>>, FfiFailure> {
        let record = Arc::new(Mutex::new(TransferRecord {
            context,
            state: snapshot.job.state.as_str().to_owned(),
            durable_bytes: snapshot.job.durable_bytes,
            total_bytes: snapshot.job.total_bytes,
            progress_percent: snapshot.progress_percent,
            error_code: snapshot.job.error_code.clone(),
            error_message: None,
            final_path: snapshot.job.final_path.clone(),
            pause_requested: Arc::new(AtomicBool::new(false)),
            generation: 0,
            updated_at_ms: now_ms,
        }));
        let transfer_id = lock(&record).context.transfer_id.clone();
        lock(&self.transfers).insert(transfer_id, Arc::clone(&record));
        Ok(record)
    }

    fn apply_snapshot(&self, record: &mut TransferRecord, snapshot: TransferSnapshot) {
        record.state = snapshot.job.state.as_str().to_owned();
        record.durable_bytes = snapshot.job.durable_bytes;
        record.total_bytes = snapshot.job.total_bytes;
        record.progress_percent = snapshot.progress_percent;
        record.error_code = snapshot.job.error_code.clone();
        record.error_message = None;
        record.final_path = snapshot.job.final_path;
        record.updated_at_ms = snapshot.job.updated_at_ms;
    }

    fn update_from_job(&self, record: &mut TransferRecord, job: Option<&TransferJob>) {
        let Some(job) = job else {
            return;
        };
        record.state = job.state.as_str().to_owned();
        record.durable_bytes = job.durable_bytes;
        record.total_bytes = job.total_bytes;
        record.progress_percent = progress_percent(job.total_bytes, job.durable_bytes);
        record.error_code = job.error_code.clone();
        record.final_path = job.final_path.clone();
        record.updated_at_ms = job.updated_at_ms;
    }

    fn update_progress(&self, record: &mut TransferRecord, durable: u64, total: u64) {
        record.state = TransferState::Transferring.as_str().to_owned();
        record.durable_bytes = durable;
        record.total_bytes = total;
        record.progress_percent = progress_percent(total, durable);
        record.updated_at_ms = now_ms();
    }

    fn record(&self, transfer_id: &str) -> Result<Arc<Mutex<TransferRecord>>, FfiFailure> {
        lock(&self.transfers)
            .get(transfer_id)
            .cloned()
            .ok_or_else(|| status_failure(CovioStatusCode::NotFound, "transfer does not exist"))
    }

    fn sync_records(&self, now_ms: i64) -> Result<(), FfiFailure> {
        let store = self.transfer_store()?;
        let jobs = store.jobs(MAX_TRANSFER_HISTORY).map_err(transfer_failure)?;
        let contexts = lock(&self.contexts).clone();
        let mut records = lock(&self.transfers);
        for job in jobs {
            if records.contains_key(&job.transfer_id) {
                continue;
            }
            let Some(context) = contexts.get(&job.transfer_id).cloned() else {
                continue;
            };
            let state = match job.state {
                TransferState::Transferring => {
                    let _ = store.waiting_network(&job.transfer_id, now_ms);
                    TransferState::WaitingNetwork.as_str()
                }
                other => other.as_str(),
            };
            let record = Arc::new(Mutex::new(TransferRecord {
                context,
                state: state.to_owned(),
                durable_bytes: job.durable_bytes,
                total_bytes: job.total_bytes,
                progress_percent: progress_percent(job.total_bytes, job.durable_bytes),
                error_code: job.error_code.clone(),
                error_message: None,
                final_path: job.final_path.clone(),
                pause_requested: Arc::new(AtomicBool::new(false)),
                generation: 0,
                updated_at_ms: now_ms,
            }));
            records.insert(job.transfer_id, record);
        }
        Ok(())
    }

    fn identity_service(&self) -> Result<IdentityService, FfiFailure> {
        DeviceIdentityService::open_or_create(&self.root, (self.secret_factory)(), self.files)
            .map_err(pairing_failure)
    }

    fn local_profile(&self) -> Result<LocalDeviceProfile, FfiFailure> {
        let path = self.local_profile_path();
        let bytes = self
            .files
            .read(&path)
            .map_err(|error| status_failure(CovioStatusCode::Io, error.message()))?;
        let Some(bytes) = bytes else {
            return Err(status_failure(
                CovioStatusCode::NotFound,
                "device profile is not initialized",
            ));
        };
        serde_json::from_slice(&bytes)
            .map_err(|_| status_failure(CovioStatusCode::Internal, "device profile is malformed"))
    }

    fn remote_profiles(&self) -> Result<BTreeMap<String, RemoteDeviceProfile>, FfiFailure> {
        let path = self.root.join(MOBILE_DIRECTORY).join(REMOTE_PROFILES_FILE);
        let bytes = self
            .files
            .read(&path)
            .map_err(|error| status_failure(CovioStatusCode::Io, error.message()))?;
        let Some(bytes) = bytes else {
            return Ok(BTreeMap::new());
        };
        let file: RemoteProfileFile = serde_json::from_slice(&bytes).map_err(|_| {
            status_failure(
                CovioStatusCode::Internal,
                "paired device profiles are malformed",
            )
        })?;
        Ok(file.profiles)
    }

    fn save_remote_profile(
        &self,
        device_id: &str,
        profile: RemoteDeviceProfile,
    ) -> Result<(), FfiFailure> {
        let mut profiles = self.remote_profiles()?;
        profiles.insert(device_id.to_owned(), profile);
        if profiles.len() > MAX_REMOTE_PROFILES {
            let excess = profiles.len() - MAX_REMOTE_PROFILES;
            for key in profiles.keys().take(excess).cloned().collect::<Vec<_>>() {
                profiles.remove(&key);
            }
        }
        write_json_atomic(
            &self.files,
            &self.root.join(MOBILE_DIRECTORY).join(REMOTE_PROFILES_FILE),
            &RemoteProfileFile {
                version: 1,
                profiles,
            },
        )
    }

    fn put_context(&self, context: TransferContext) -> Result<(), FfiFailure> {
        let mut contexts = lock(&self.contexts);
        contexts.insert(context.transfer_id.clone(), context);
        while contexts.len() > MAX_TRANSFER_CONTEXTS {
            if let Some(key) = contexts.keys().next().cloned() {
                contexts.remove(&key);
            }
        }
        write_json_atomic(
            &self.files,
            &self.transfer_contexts_path(),
            &TransferContextFile {
                version: 1,
                contexts: contexts.clone(),
            },
        )
    }

    fn peer_public_key(&self, device_id: &str) -> Result<String, TransferError> {
        let service = self
            .identity_service()
            .map_err(|error| transfer_error_from_ffi(&error))?;
        service
            .trusted_devices()
            .map_err(pairing_to_transfer)?
            .into_iter()
            .find(|device| device.device_id == device_id)
            .map(|device| device.public_key)
            .ok_or_else(|| {
                TransferError::new(
                    TransferErrorCode::PeerIdentityChanged,
                    "peer device is not trusted",
                    false,
                )
            })
    }

    fn transfer_store(&self) -> Result<TransferStore, FfiFailure> {
        TransferStore::open(self.transfer_store_path()).map_err(transfer_failure)
    }

    fn next_generation(&self) -> u64 {
        self.generation.fetch_add(1, Ordering::AcqRel)
    }

    fn local_profile_path(&self) -> PathBuf {
        self.root.join(MOBILE_DIRECTORY).join(LOCAL_PROFILE_FILE)
    }

    fn transfer_contexts_path(&self) -> PathBuf {
        self.root
            .join(MOBILE_DIRECTORY)
            .join(TRANSFER_CONTEXTS_FILE)
    }

    fn transfer_store_path(&self) -> PathBuf {
        self.root.join(MOBILE_DIRECTORY).join("transfers.sqlite3")
    }
}

fn local_profile_from_payload(payload: &Value) -> Result<LocalDeviceProfile, FfiFailure> {
    let capabilities = payload
        .get("capabilities")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(ToOwned::to_owned)
                .collect::<Vec<_>>()
        })
        .unwrap_or_else(|| vec!["file.transfer".to_owned()]);
    Ok(LocalDeviceProfile {
        display_name: optional_string(payload, "displayName").unwrap_or_default(),
        system_name: optional_string(payload, "systemName").unwrap_or_default(),
        system_version: optional_string(payload, "systemVersion").unwrap_or_default(),
        model: optional_string(payload, "model").unwrap_or_default(),
        capabilities,
    })
}

fn device_view(
    device: &PairedDevice,
    profile: Option<&RemoteDeviceProfile>,
    online: &BTreeSet<String>,
) -> Value {
    json!({
        "deviceId": device.device_id.clone(),
        "displayName": device.display_name.clone(),
        "publicKey": device.public_key.clone(),
        "pairedAtMs": device.paired_at_ms,
        "lastSeenMs": device.last_seen_ms,
        "online": online.contains(&device.device_id),
        "systemName": profile.map_or(Value::Null, |value| Value::String(value.system_name.clone())),
        "systemVersion": profile.map_or(Value::Null, |value| Value::String(value.system_version.clone())),
        "capabilities": profile.map_or_else(Vec::new, |value| value.capabilities.clone()),
    })
}

fn identity_json(identity: &DevicePublicIdentity) -> Value {
    json!({
        "deviceId": identity.device_id,
        "displayName": identity.display_name,
        "publicKey": identity.public_key,
    })
}

fn paired_device_json(device: &PairedDevice) -> Value {
    json!({
        "deviceId": device.device_id,
        "displayName": device.display_name,
        "publicKey": device.public_key,
        "pairedAtMs": device.paired_at_ms,
        "lastSeenMs": device.last_seen_ms,
    })
}

fn record_json(record: &TransferRecord) -> Value {
    let offer = record.context.offer.as_ref();
    let file_name = offer.map(|value| value.manifest.file_name.clone());
    let summary = offer.map(FileTransferOffer::summary);
    json!({
        "transferId": record.context.transfer_id,
        "direction": record.context.direction,
        "peerDeviceId": record.context.peer_device_id,
        "state": record.state,
        "fileName": file_name,
        "totalBytes": record.total_bytes,
        "durableBytes": record.durable_bytes,
        "progressPercent": record.progress_percent,
        "errorCode": record.error_code,
        "errorMessage": record.error_message,
        "finalPath": record.final_path,
        "updatedAtMs": record.updated_at_ms,
        "offer": summary,
    })
}

fn snapshot_from_job(job: TransferJob) -> TransferSnapshot {
    let progress_percent = progress_percent(job.total_bytes, job.durable_bytes);
    let summary = TransferSummary::from(&job.manifest);
    TransferSnapshot {
        job,
        summary,
        progress_percent,
    }
}

fn progress_percent(total: u64, durable: u64) -> u8 {
    durable
        .saturating_mul(100)
        .checked_div(total)
        .and_then(|value| u8::try_from(value).ok())
        .unwrap_or(100)
}

fn is_terminal(state: &str) -> bool {
    matches!(
        state,
        "completed" | "rejected" | "expired" | "cancelled" | "failed"
    )
}

fn load_contexts(
    files: &StdFileStore,
    root: &Path,
) -> Result<BTreeMap<String, TransferContext>, FfiFailure> {
    let path = root.join(MOBILE_DIRECTORY).join(TRANSFER_CONTEXTS_FILE);
    let bytes = files
        .read(&path)
        .map_err(|error| status_failure(CovioStatusCode::Io, error.message()))?;
    let Some(bytes) = bytes else {
        return Ok(BTreeMap::new());
    };
    let file: TransferContextFile = serde_json::from_slice(&bytes).map_err(|_| {
        status_failure(CovioStatusCode::Internal, "transfer contexts are malformed")
    })?;
    Ok(file.contexts)
}

fn write_json_atomic<T: Serialize>(
    files: &StdFileStore,
    path: &Path,
    value: &T,
) -> Result<(), FfiFailure> {
    let bytes = serde_json::to_vec(value)
        .map_err(|_| status_failure(CovioStatusCode::Internal, "JSON encoding failed"))?;
    files
        .write_atomic(path, &bytes)
        .map_err(|error| status_failure(CovioStatusCode::Io, error.message()))
}

fn mobile_runtime() -> Result<Runtime, TransferError> {
    Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .map_err(|_| {
            TransferError::new(
                TransferErrorCode::Internal,
                "mobile async runtime could not start",
                false,
            )
        })
}

fn transport_timeout() -> TransferError {
    TransferError::new(
        TransferErrorCode::TransportOffline,
        "peer connection timed out",
        true,
    )
}

async fn send_control_bounded(
    channel: &mut IrohTransferChannel,
    message: ControlMessage,
) -> Result<(), TransferError> {
    match tokio::time::timeout(NETWORK_TIMEOUT, channel.send_control(message)).await {
        Ok(result) => result,
        Err(_) => Err(transport_timeout()),
    }
}

async fn receive_control_bounded(
    channel: &mut IrohTransferChannel,
) -> Result<covio_core::file_transfer::ControlEnvelope, TransferError> {
    match tokio::time::timeout(NETWORK_TIMEOUT, channel.receive_control()).await {
        Ok(result) => result,
        Err(_) => Err(transport_timeout()),
    }
}

async fn send_file_header_bounded(
    channel: &mut IrohTransferChannel,
    header: &FileStreamHeader,
) -> Result<(), TransferError> {
    match tokio::time::timeout(NETWORK_TIMEOUT, channel.send_file_header(header)).await {
        Ok(result) => result,
        Err(_) => Err(transport_timeout()),
    }
}

async fn receive_file_header_bounded(
    channel: &mut IrohTransferChannel,
) -> Result<FileStreamHeader, TransferError> {
    match tokio::time::timeout(NETWORK_TIMEOUT, channel.receive_file_header()).await {
        Ok(result) => result,
        Err(_) => Err(transport_timeout()),
    }
}

async fn send_chunk_bounded(
    channel: &mut IrohTransferChannel,
    frame: &covio_core::file_transfer::FileChunkFrame,
) -> Result<(), TransferError> {
    match tokio::time::timeout(NETWORK_TIMEOUT, channel.send_chunk(frame)).await {
        Ok(result) => result,
        Err(_) => Err(transport_timeout()),
    }
}

async fn receive_chunk_bounded(
    channel: &mut IrohTransferChannel,
) -> Result<covio_core::file_transfer::FileChunkFrame, TransferError> {
    match tokio::time::timeout(NETWORK_TIMEOUT, channel.receive_chunk()).await {
        Ok(result) => result,
        Err(_) => Err(transport_timeout()),
    }
}

fn random_transfer_id() -> Result<String, FfiFailure> {
    let mut bytes = [0_u8; 16];
    getrandom::getrandom(&mut bytes)
        .map_err(|_| status_failure(CovioStatusCode::Internal, "random transfer id failed"))?;
    Ok(format!("tr-{}", hex(&bytes)))
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(char::from(DIGITS[usize::from(byte >> 4)]));
        output.push(char::from(DIGITS[usize::from(byte & 0x0f)]));
    }
    output
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .and_then(|duration| i64::try_from(duration.as_millis()).ok())
        .unwrap_or(0)
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn string_field<'a>(payload: &'a Value, name: &str) -> Result<&'a str, FfiFailure> {
    payload.get(name).and_then(Value::as_str).ok_or_else(|| {
        status_failure(
            CovioStatusCode::InvalidArgument,
            format!("{name} must be a string"),
        )
    })
}

fn optional_string(payload: &Value, name: &str) -> Option<String> {
    payload
        .get(name)
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

fn status_failure(status: CovioStatusCode, message: impl Into<String>) -> FfiFailure {
    FfiFailure::new(status, message)
}

fn pairing_failure(error: PairingError) -> FfiFailure {
    let status = match error.code() {
        PairingErrorCode::InvalidArgument
        | PairingErrorCode::OfferInvalidSignature
        | PairingErrorCode::ResponseInvalidSignature
        | PairingErrorCode::ResponseMismatch
        | PairingErrorCode::SelfPairing
        | PairingErrorCode::ConfirmationMismatch
        | PairingErrorCode::ReplayDetected => CovioStatusCode::InvalidArgument,
        PairingErrorCode::IdentityNotFound => CovioStatusCode::NotFound,
        PairingErrorCode::ProtocolUnsupported => CovioStatusCode::ProtocolVersion,
        PairingErrorCode::OfferExpired => CovioStatusCode::DeadlineExceeded,
        PairingErrorCode::RegistryFull => CovioStatusCode::Conflict,
        PairingErrorCode::StorageFailure | PairingErrorCode::CredentialUnavailable => {
            CovioStatusCode::Io
        }
        PairingErrorCode::RecordCorrupt | PairingErrorCode::Internal => CovioStatusCode::Internal,
    };
    FfiFailure::new(status, error.message())
}

fn pairing_to_transfer(error: PairingError) -> TransferError {
    let code = match error.code() {
        PairingErrorCode::IdentityNotFound => TransferErrorCode::PeerIdentityChanged,
        PairingErrorCode::InvalidArgument
        | PairingErrorCode::OfferInvalidSignature
        | PairingErrorCode::ResponseInvalidSignature
        | PairingErrorCode::ResponseMismatch
        | PairingErrorCode::SelfPairing
        | PairingErrorCode::ConfirmationMismatch
        | PairingErrorCode::ReplayDetected => TransferErrorCode::InvalidArgument,
        PairingErrorCode::ProtocolUnsupported => TransferErrorCode::ProtocolVersionUnsupported,
        PairingErrorCode::OfferExpired => TransferErrorCode::TransferOfferExpired,
        PairingErrorCode::StorageFailure | PairingErrorCode::CredentialUnavailable => {
            TransferErrorCode::StorageIoError
        }
        PairingErrorCode::RegistryFull
        | PairingErrorCode::RecordCorrupt
        | PairingErrorCode::Internal => TransferErrorCode::Internal,
    };
    TransferError::new(code, error.message(), error.retryable())
}

fn transfer_failure(error: TransferError) -> FfiFailure {
    let status = match error.code() {
        TransferErrorCode::InvalidArgument
        | TransferErrorCode::ManifestInvalid
        | TransferErrorCode::ChunkHashMismatch
        | TransferErrorCode::FileHashMismatch
        | TransferErrorCode::ResumeCheckpointInvalid
        | TransferErrorCode::PathInvalid
        | TransferErrorCode::PathCollision
        | TransferErrorCode::SymlinkRefused
        | TransferErrorCode::UnsupportedEntryKind => CovioStatusCode::InvalidArgument,
        TransferErrorCode::ProtocolVersionUnsupported => CovioStatusCode::ProtocolVersion,
        TransferErrorCode::TransferOfferExpired => CovioStatusCode::DeadlineExceeded,
        TransferErrorCode::OfferRejected | TransferErrorCode::TargetExists => {
            CovioStatusCode::Conflict
        }
        TransferErrorCode::StorageIoError => CovioStatusCode::Io,
        TransferErrorCode::TransportOffline | TransferErrorCode::BackgroundSuspended => {
            CovioStatusCode::Unsupported
        }
        TransferErrorCode::SourceChanged | TransferErrorCode::PeerIdentityChanged => {
            CovioStatusCode::Conflict
        }
        TransferErrorCode::CancelledBySender | TransferErrorCode::CancelledByReceiver => {
            CovioStatusCode::Cancelled
        }
        TransferErrorCode::Internal => CovioStatusCode::Internal,
    };
    FfiFailure::new(status, error.message())
}

fn transfer_error_from_ffi(error: &FfiFailure) -> TransferError {
    let code = match error.status {
        CovioStatusCode::InvalidArgument => TransferErrorCode::InvalidArgument,
        CovioStatusCode::ProtocolVersion => TransferErrorCode::ProtocolVersionUnsupported,
        CovioStatusCode::DeadlineExceeded => TransferErrorCode::TransferOfferExpired,
        CovioStatusCode::Cancelled => TransferErrorCode::CancelledBySender,
        CovioStatusCode::Unsupported => TransferErrorCode::TransportOffline,
        CovioStatusCode::Conflict => TransferErrorCode::PeerIdentityChanged,
        CovioStatusCode::Io => TransferErrorCode::StorageIoError,
        _ => TransferErrorCode::Internal,
    };
    TransferError::new(code, error.message.clone(), false)
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
fn default_secret_factory() -> SecretFactory {
    Arc::new(|| {
        Box::new(covio_platform::KeychainSecretStore::new(
            DEVICE_SECRET_SERVICE,
        ))
    })
}

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
fn default_secret_factory() -> SecretFactory {
    Arc::new(|| Box::new(covio_platform::UnavailableSecretStore))
}

#[cfg(test)]
mod tests {
    use super::*;
    use covio_platform::{PlatformError, SecretKey, SecretValue};
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_DIRECTORY: AtomicU64 = AtomicU64::new(0);

    #[derive(Clone, Default)]
    struct MemorySecretStore {
        values: Arc<Mutex<BTreeMap<String, Vec<u8>>>>,
    }

    impl SecretStore for MemorySecretStore {
        fn read(&self, key: &SecretKey) -> Result<Option<SecretValue>, PlatformError> {
            Ok(lock(&self.values)
                .get(key.as_str())
                .cloned()
                .map(SecretValue::new))
        }

        fn write(&self, key: &SecretKey, value: &SecretValue) -> Result<(), PlatformError> {
            lock(&self.values).insert(key.as_str().to_owned(), value.expose().to_vec());
            Ok(())
        }

        fn delete(&self, key: &SecretKey) -> Result<(), PlatformError> {
            lock(&self.values).remove(key.as_str());
            Ok(())
        }
    }

    fn temporary_root(label: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let sequence = NEXT_DIRECTORY.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!(
            "covio-mobile-{label}-{}-{nonce}-{sequence}",
            std::process::id()
        ))
    }

    fn core(root: &Path) -> Arc<MobileCore> {
        let secrets = MemorySecretStore::default();
        let factory =
            Arc::new(move || Box::new(secrets.clone()) as Box<dyn SecretStore + Send + Sync>);
        Arc::new(MobileCore::with_secret_factory(root, factory))
    }

    fn bootstrap(mobile: &Arc<MobileCore>, name: &str, now_ms: i64) -> String {
        let response = mobile
            .call(
                "mobile.bootstrap",
                &json!({
                    "displayName": name,
                    "systemName": "iOS",
                    "systemVersion": "26.1",
                    "model": "iPhone",
                    "capabilities": ["file.transfer", "device.info"]
                }),
                now_ms,
            )
            .expect("bootstrap");
        response["identity"]["deviceId"]
            .as_str()
            .expect("identity device id")
            .to_owned()
    }

    fn pair(alice: &Arc<MobileCore>, bob: &Arc<MobileCore>, now_ms: i64) {
        let begin = alice
            .call("mobile.pairing.begin", &json!({}), now_ms)
            .expect("pairing begin");
        let qr_payload = begin["qrPayload"].as_str().expect("qr payload");
        let accepted = bob
            .call(
                "mobile.pairing.acceptOffer",
                &json!({"qrPayload": qr_payload}),
                now_ms + 1,
            )
            .expect("accept offer");
        let response_payload = accepted["responsePayload"]
            .as_str()
            .expect("response payload");
        let code = accepted["confirmationCode"]
            .as_str()
            .expect("confirmation code");
        let completed = alice
            .call(
                "mobile.pairing.completeInitiator",
                &json!({"responsePayload": response_payload}),
                now_ms + 2,
            )
            .expect("complete initiator");
        assert_eq!(completed["confirmationCode"], code);
        alice
            .call(
                "mobile.pairing.confirmInitiator",
                &json!({"confirmationCode": code}),
                now_ms + 3,
            )
            .expect("confirm initiator");
        bob.call(
            "mobile.pairing.confirmResponder",
            &json!({"confirmationCode": code}),
            now_ms + 3,
        )
        .expect("confirm responder");
    }

    #[test]
    fn bootstrap_and_qr_pairing_persist_trusted_devices() {
        let alice_root = temporary_root("alice");
        let bob_root = temporary_root("bob");
        let alice = core(&alice_root);
        let bob = core(&bob_root);
        alice
            .call(
                "mobile.bootstrap",
                &json!({
                    "displayName": "Alice iPhone",
                    "systemName": "iOS",
                    "systemVersion": "26.1",
                    "model": "iPhone",
                    "capabilities": ["file.transfer", "device.info"]
                }),
                1_800_000_000_000,
            )
            .expect("alice bootstrap");
        bob.call(
            "mobile.bootstrap",
            &json!({
                "displayName": "Bob iPhone",
                "systemName": "iOS",
                "systemVersion": "26.1",
                "model": "iPhone",
                "capabilities": ["file.transfer", "device.info"]
            }),
            1_800_000_000_001,
        )
        .expect("bob bootstrap");

        let begin = alice
            .call("mobile.pairing.begin", &json!({}), 1_800_000_000_010)
            .expect("pairing begin");
        let qr_payload = begin["qrPayload"].as_str().expect("qr payload");
        let accepted = bob
            .call(
                "mobile.pairing.acceptOffer",
                &json!({"qrPayload": qr_payload}),
                1_800_000_000_011,
            )
            .expect("accept offer");
        let response_payload = accepted["responsePayload"]
            .as_str()
            .expect("response payload");
        let responder_code = accepted["confirmationCode"]
            .as_str()
            .expect("responder code");
        let completed = alice
            .call(
                "mobile.pairing.completeInitiator",
                &json!({"responsePayload": response_payload}),
                1_800_000_000_012,
            )
            .expect("complete initiator");
        assert_eq!(completed["confirmationCode"], responder_code);
        alice
            .call(
                "mobile.pairing.confirmInitiator",
                &json!({"confirmationCode": responder_code}),
                1_800_000_000_013,
            )
            .expect("confirm initiator");
        bob.call(
            "mobile.pairing.confirmResponder",
            &json!({"confirmationCode": responder_code}),
            1_800_000_000_013,
        )
        .expect("confirm responder");

        let alice_devices = alice
            .call("mobile.devices.list", &json!({}), 1_800_000_000_014)
            .expect("alice devices");
        let bob_devices = bob
            .call("mobile.devices.list", &json!({}), 1_800_000_000_014)
            .expect("bob devices");
        assert_eq!(alice_devices["devices"].as_array().unwrap().len(), 1);
        assert_eq!(bob_devices["devices"].as_array().unwrap().len(), 1);
        assert_eq!(alice_devices["devices"][0]["systemName"], "iOS");
        assert_eq!(alice_devices["devices"][0]["systemVersion"], "26.1");
        assert_eq!(bob_devices["devices"][0]["systemName"], "iOS");
        assert_eq!(bob_devices["devices"][0]["systemVersion"], "26.1");
        assert!(
            bob_devices["devices"][0]["capabilities"]
                .as_array()
                .is_some_and(|values| values.iter().any(|value| value == "file.transfer"))
        );
        assert!(
            alice_devices["devices"][0]["capabilities"]
                .as_array()
                .is_some_and(|values| values.iter().any(|value| value == "file.transfer"))
        );

        let _ = std::fs::remove_dir_all(alice_root);
        let _ = std::fs::remove_dir_all(bob_root);
    }

    #[test]
    fn lifecycle_commands_report_foreground_and_background() {
        let root = temporary_root("lifecycle");
        let mobile = core(&root);
        mobile
            .call(
                "mobile.bootstrap",
                &json!({
                    "displayName": "Lifecycle iPhone",
                    "systemName": "iOS",
                    "systemVersion": "26.1",
                    "model": "iPhone",
                    "capabilities": ["file.transfer"]
                }),
                10,
            )
            .expect("bootstrap");
        let background = mobile
            .call("mobile.lifecycle.background", &json!({}), 11)
            .expect("background");
        assert_eq!(background["lifecycle"], "background");
        let foreground = mobile
            .call("mobile.lifecycle.foreground", &json!({}), 12)
            .expect("foreground");
        assert_eq!(foreground["status"]["lifecycle"], "foreground");
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn unknown_command_returns_invalid_argument() {
        let root = temporary_root("unknown");
        let mobile = core(&root);
        let error = mobile
            .call("mobile.unknown", &json!({}), 1)
            .expect_err("unknown command");
        assert_eq!(error.status, CovioStatusCode::InvalidArgument);
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    #[ignore = "requires iroh relay or local network discovery"]
    fn loopback_transfer_completes_and_preserves_bytes() {
        let alice_root = temporary_root("transfer-alice");
        let bob_root = temporary_root("transfer-bob");
        let alice = core(&alice_root);
        let bob = core(&bob_root);
        let now = 1_800_000_000_000;
        bootstrap(&alice, "Transfer Alice", now);
        let bob_id = bootstrap(&bob, "Transfer Bob", now + 1);
        pair(&alice, &bob, now + 2);
        let destination = bob_root.join("received");
        std::fs::create_dir_all(&destination).expect("destination");
        bob.call(
            "mobile.transfer.listen",
            &json!({"destinationPath": destination}),
            now + 11,
        )
        .expect("listen");

        let source = alice_root.join("report.txt");
        let expected = b"covio mobile loopback transfer\n".repeat(70_000);
        std::fs::write(&source, &expected).expect("source");
        alice
            .call(
                "mobile.transfer.send",
                &json!({"sourcePath": source, "peerDeviceId": bob_id}),
                now + 12,
            )
            .expect("send");

        let deadline = std::time::Instant::now() + Duration::from_secs(60);
        let mut accepted_transfer_id: Option<String> = None;
        let final_path = destination.join("report.txt");
        loop {
            let status = bob
                .call("mobile.status", &json!({}), now_ms())
                .expect("receiver status");
            if accepted_transfer_id.is_none()
                && let Some(transfer_id) = status["pendingIncomingTransferId"].as_str()
            {
                bob.call(
                    "mobile.transfer.accept",
                    &json!({"transferId": transfer_id}),
                    now_ms(),
                )
                .expect("accept transfer");
                accepted_transfer_id = Some(transfer_id.to_owned());
            }
            let completed = status["transfers"].as_array().is_some_and(|transfers| {
                transfers.iter().any(|transfer| {
                    Some(transfer["transferId"].as_str().unwrap_or_default())
                        == accepted_transfer_id.as_deref()
                        && transfer["state"] == "completed"
                })
            });
            if completed && final_path.is_file() {
                let actual = std::fs::read(&final_path).expect("received file");
                assert_eq!(actual, expected);
                break;
            }
            if let Some(error) = status["listenerError"].as_str() {
                panic!("listener failed: {error}");
            }
            if status["transfers"].as_array().is_some_and(|transfers| {
                transfers
                    .iter()
                    .any(|transfer| transfer["state"] == "failed")
            }) {
                panic!("transfer failed: {status}");
            }
            assert!(
                std::time::Instant::now() < deadline,
                "transfer timed out: sender={} receiver={status}",
                alice
                    .call("mobile.status", &json!({}), now_ms())
                    .expect("sender status")
            );
            std::thread::sleep(Duration::from_millis(100));
        }

        let _ = std::fs::remove_dir_all(alice_root);
        let _ = std::fs::remove_dir_all(bob_root);
    }
}

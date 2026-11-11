use covio_core::file_transfer::{
    ControlEnvelope, ControlMessage, FileChunkFrame, FileManifest, FileTransferOffer,
    ForegroundCheck, SenderSource, TRANSFER_CHUNK_SIZE, TRANSFER_OFFER_TTL_MS,
    TRANSFER_WINDOW_SIZE, TransferDirection, TransferErrorCode, TransferReceiver, TransferSender,
    TransferState, TransferStore, decode_control, encode_control, endpoint_id_for_public_key,
};
use covio_platform::StdFileStore;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

const NOW_MS: i64 = 1_800_000_000_000;
const TRANSFER_ID: &str = "tr-00000000000000000000000000000001";
const SENDER_ID: &str = "device-sender";
static NEXT_TEMPORARY_DIRECTORY: AtomicU64 = AtomicU64::new(0);

struct TempDir(PathBuf);

impl TempDir {
    fn new() -> Self {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let sequence = NEXT_TEMPORARY_DIRECTORY.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "covio-file-transfer-{}-{nonce}-{sequence}",
            std::process::id()
        ));
        std::fs::create_dir_all(&path).expect("temporary directory");
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

struct Harness {
    _temporary: TempDir,
    source: PathBuf,
    expected: Vec<u8>,
    sender: SenderSource<StdFileStore>,
    offer: FileTransferOffer,
    receiver: TransferReceiver<StdFileStore>,
    destination: PathBuf,
}

impl Harness {
    fn new(size: usize) -> Self {
        Self::new_with_store(size, None)
    }

    fn new_with_database(size: usize, database: Option<&Path>) -> Self {
        Self::new_with_store(size, database)
    }

    fn new_with_store(size: usize, database: Option<&Path>) -> Self {
        let temporary = TempDir::new();
        let root = temporary.path().to_path_buf();
        let source = root.join("report.bin");
        let destination = root.join("destination");
        let expected = (0..size)
            .map(|index| u8::try_from(index % 251).expect("byte"))
            .collect::<Vec<_>>();
        std::fs::write(&source, &expected).expect("source file");
        let sender = SenderSource::open(
            StdFileStore::new(),
            source.clone(),
            TRANSFER_ID,
            SENDER_ID,
            NOW_MS,
        )
        .expect("sender");
        let offer = FileTransferOffer::new(sender.manifest().clone()).expect("offer");
        let store = database
            .map(|path| TransferStore::open(path).expect("database"))
            .unwrap_or_else(|| TransferStore::open_in_memory().expect("memory database"));
        let receiver = TransferReceiver::new(store, StdFileStore::new(), &destination);
        Self {
            _temporary: temporary,
            source,
            expected,
            sender,
            offer,
            receiver,
            destination,
        }
    }

    fn accept(&mut self) -> u64 {
        let snapshot = self
            .receiver
            .receive_offer(&self.offer, NOW_MS)
            .expect("offer");
        assert_eq!(snapshot.summary.file_name, "report.bin");
        assert_eq!(
            snapshot.progress_percent,
            if self.expected.is_empty() { 100 } else { 0 }
        );
        self.receiver
            .accept(&self.offer.manifest.transfer_id, 0, NOW_MS)
            .expect("accept")
            .offset
    }

    fn send_all(&mut self) {
        loop {
            let frames = self.sender.read_window().expect("sender window");
            if frames.is_empty() {
                break;
            }
            for frame in frames {
                let outcome = self
                    .receiver
                    .receive_chunk(&self.offer.manifest.transfer_id, &frame, NOW_MS)
                    .expect("receive chunk");
                self.sender
                    .acknowledge(outcome.durable_bytes)
                    .expect("acknowledge");
            }
        }
    }

    fn final_path(&self) -> PathBuf {
        self.destination.join("report.bin")
    }
}

#[test]
fn round_trip_uses_staging_and_atomic_commit() {
    let mut harness = Harness::new((TRANSFER_CHUNK_SIZE as usize * 2) + 123);
    harness.accept();
    harness.send_all();
    let snapshot = harness
        .receiver
        .complete(TRANSFER_ID, NOW_MS)
        .expect("complete");

    assert_eq!(snapshot.job.state, TransferState::Completed);
    assert_eq!(snapshot.progress_percent, 100);
    let final_bytes = std::fs::read(harness.final_path()).expect("final file");
    assert_eq!(final_bytes, harness.expected);
    assert!(
        !std::fs::read_dir(harness.destination.join(".covio/staging"))
            .expect("staging root")
            .any(|entry| entry.expect("entry").path().ends_with(TRANSFER_ID))
    );
    let events = harness
        .receiver
        .store()
        .events(TRANSFER_ID)
        .expect("events");
    assert!(
        events
            .iter()
            .any(|event| event.event_type == "transfer_completed")
    );
}

#[test]
fn corrupt_chunk_is_rejected_without_advancing_the_checkpoint() {
    let mut harness = Harness::new(1024);
    harness.accept();
    let mut frame = harness.sender.read_window().expect("window").remove(0);
    frame.payload[0] ^= 0xff;

    let error = harness
        .receiver
        .receive_chunk(TRANSFER_ID, &frame, NOW_MS)
        .expect_err("corrupt chunk");
    assert_eq!(error.code(), TransferErrorCode::ChunkHashMismatch);
    assert_eq!(
        harness
            .receiver
            .snapshot(TRANSFER_ID)
            .expect("snapshot")
            .job
            .durable_bytes,
        0
    );
    assert_eq!(
        std::fs::metadata(harness.receiver.staging_path(TRANSFER_ID).expect("staging"))
            .expect("metadata")
            .len(),
        0
    );
}

#[test]
fn duplicate_chunk_is_idempotent() {
    let mut harness = Harness::new((TRANSFER_CHUNK_SIZE as usize * 2) + 1);
    harness.accept();
    let frame = harness.sender.read_window().expect("window").remove(0);
    let first = harness
        .receiver
        .receive_chunk(TRANSFER_ID, &frame, NOW_MS)
        .expect("first chunk");
    let duplicate = harness
        .receiver
        .receive_chunk(TRANSFER_ID, &frame, NOW_MS)
        .expect("duplicate chunk");

    assert!(!first.duplicate);
    assert!(duplicate.duplicate);
    assert_eq!(first.durable_bytes, duplicate.durable_bytes);
    assert_eq!(
        std::fs::metadata(harness.receiver.staging_path(TRANSFER_ID).expect("staging"))
            .expect("metadata")
            .len(),
        u64::from(TRANSFER_CHUNK_SIZE)
    );
}

#[test]
fn cancel_keeps_staging_and_never_exposes_a_final_file() {
    let mut harness = Harness::new((TRANSFER_CHUNK_SIZE as usize * 2) + 1);
    harness.accept();
    let frame = harness.sender.read_window().expect("window").remove(0);
    harness
        .receiver
        .receive_chunk(TRANSFER_ID, &frame, NOW_MS)
        .expect("chunk");
    harness
        .receiver
        .cancel(TRANSFER_ID, NOW_MS)
        .expect("cancel");

    assert!(!harness.final_path().exists());
    assert!(
        harness
            .receiver
            .staging_path(TRANSFER_ID)
            .expect("staging")
            .exists()
    );
    let snapshot = harness.receiver.snapshot(TRANSFER_ID).expect("snapshot");
    assert_eq!(snapshot.job.state, TransferState::Cancelled);
    assert_eq!(
        snapshot.job.error_code.as_deref(),
        Some(TransferErrorCode::CancelledByReceiver.as_str())
    );
}

#[test]
fn expired_offer_is_rejected_before_any_data_is_written() {
    let harness = Harness::new(1024);
    harness
        .receiver
        .receive_offer(&harness.offer, NOW_MS)
        .expect("offer");
    let expired_at = NOW_MS + TRANSFER_OFFER_TTL_MS + 1;
    let error = harness
        .receiver
        .accept(TRANSFER_ID, 0, expired_at)
        .expect_err("expired offer");
    assert_eq!(error.code(), TransferErrorCode::TransferOfferExpired);
    assert_eq!(
        harness
            .receiver
            .snapshot(TRANSFER_ID)
            .expect("snapshot")
            .job
            .state,
        TransferState::Expired
    );
    assert!(
        !harness
            .receiver
            .staging_path(TRANSFER_ID)
            .expect("staging")
            .exists()
    );
}

#[test]
fn background_restart_and_foreground_resume_from_the_same_checkpoint() {
    let temporary = TempDir::new();
    let database = temporary.path().join("transfer.db");
    let mut harness =
        Harness::new_with_database((TRANSFER_CHUNK_SIZE as usize * 3) + 17, Some(&database));
    harness.accept();
    let first_window = harness.sender.read_window().expect("window");
    let first_frame = &first_window[0];
    let first = harness
        .receiver
        .receive_chunk(TRANSFER_ID, first_frame, NOW_MS)
        .expect("first chunk");
    harness
        .sender
        .acknowledge(first.durable_bytes)
        .expect("ack");
    let plan = harness
        .receiver
        .background(TRANSFER_ID, NOW_MS + 1)
        .expect("background");
    assert_eq!(plan.offset, first.durable_bytes);
    let final_path = harness.final_path();
    drop(harness.receiver);

    let receiver = TransferReceiver::new(
        TransferStore::open(&database).expect("reopened database"),
        StdFileStore::new(),
        &harness.destination,
    );
    let hash = harness.offer.manifest.digest().expect("manifest hash");
    let resumed = receiver
        .foreground(
            TRANSFER_ID,
            &ForegroundCheck {
                trusted: true,
                peer_device_id: SENDER_ID.to_owned(),
                manifest_hash: hash,
                connection_alive: true,
            },
            NOW_MS + 2,
        )
        .expect("foreground resume");
    assert_eq!(resumed.offset, first_frame.payload.len() as u64);

    let mut sender = SenderSource::resume(
        StdFileStore::new(),
        harness.source.clone(),
        harness.offer.manifest.clone(),
        resumed.offset,
    )
    .expect("sender resume");
    loop {
        let frames = sender.read_window().expect("resumed window");
        if frames.is_empty() {
            break;
        }
        for frame in frames {
            let outcome = receiver
                .receive_chunk(TRANSFER_ID, &frame, NOW_MS + 2)
                .expect("resumed chunk");
            sender.acknowledge(outcome.durable_bytes).expect("ack");
        }
    }
    receiver
        .complete(TRANSFER_ID, NOW_MS + 3)
        .expect("resumed complete");
    assert_eq!(
        std::fs::read(final_path).expect("final file"),
        harness.expected
    );
}

#[test]
fn file_hash_mismatch_does_not_commit_the_staged_file() {
    let mut harness = Harness::new(TRANSFER_CHUNK_SIZE as usize + 3);
    let mut offer = harness.offer.clone();
    offer.manifest.blake3 = blake3::hash(b"different").to_hex().to_string();
    offer.manifest_hash = offer.manifest.digest().expect("manifest hash");
    harness.offer = offer;
    harness.accept();
    harness.send_all();
    let error = harness
        .receiver
        .complete(TRANSFER_ID, NOW_MS)
        .expect_err("digest mismatch");
    assert_eq!(error.code(), TransferErrorCode::FileHashMismatch);
    assert!(!harness.final_path().exists());
    assert!(
        harness
            .receiver
            .staging_path(TRANSFER_ID)
            .expect("staging")
            .exists()
    );
}

#[test]
fn eight_mib_window_blocks_more_reads_until_acknowledged() {
    let mut harness = Harness::new((TRANSFER_WINDOW_SIZE + TRANSFER_CHUNK_SIZE as u64) as usize);
    let first = harness.sender.read_window().expect("first window");
    assert_eq!(
        first.iter().map(|frame| frame.length as u64).sum::<u64>(),
        TRANSFER_WINDOW_SIZE
    );
    assert!(
        harness
            .sender
            .read_window()
            .expect("blocked window")
            .is_empty()
    );
    harness
        .sender
        .acknowledge(TRANSFER_WINDOW_SIZE)
        .expect("ack window");
    let second = harness.sender.read_window().expect("second window");
    assert_eq!(
        second.iter().map(|frame| frame.length as u64).sum::<u64>(),
        TRANSFER_CHUNK_SIZE as u64
    );
}

#[test]
fn control_envelope_and_chunk_frame_round_trip() {
    let manifest = FileManifest {
        manifest_version: 1,
        transfer_id: TRANSFER_ID.to_owned(),
        sender_device_id: SENDER_ID.to_owned(),
        file_name: "one.bin".to_owned(),
        size: 3,
        mtime_ms: 0,
        blake3: blake3::hash(b"abc").to_hex().to_string(),
        chunk_size: TRANSFER_CHUNK_SIZE,
        total_chunks: 1,
        created_at_ms: NOW_MS,
        expires_at_ms: NOW_MS + TRANSFER_OFFER_TTL_MS,
    };
    let offer = FileTransferOffer::new(manifest).expect("offer");
    let envelope = ControlEnvelope::first(ControlMessage::Offer {
        offer,
        resume_from: 0,
    })
    .expect("envelope");
    let encoded = encode_control(&envelope).expect("encode");
    assert_eq!(decode_control(&encoded).expect("decode"), envelope);

    let frame = FileChunkFrame::new(0, b"abc".to_vec());
    assert_eq!(
        FileChunkFrame::decode(&frame.encode().expect("frame")).expect("decode"),
        frame
    );
}

#[test]
fn empty_files_complete_without_a_chunk_record() {
    let mut harness = Harness::new(0);
    harness.accept();
    harness.send_all();
    let snapshot = harness
        .receiver
        .complete(TRANSFER_ID, NOW_MS)
        .expect("empty file");
    assert_eq!(snapshot.job.state, TransferState::Completed);
    assert_eq!(snapshot.progress_percent, 100);
    assert_eq!(
        std::fs::read(harness.final_path()).expect("empty file"),
        b""
    );
    assert!(
        harness
            .receiver
            .store()
            .chunks(TRANSFER_ID)
            .expect("chunks")
            .is_empty()
    );
}

#[test]
fn path_traversal_in_a_manifest_is_rejected() {
    let mut manifest = FileManifest {
        manifest_version: 1,
        transfer_id: TRANSFER_ID.to_owned(),
        sender_device_id: SENDER_ID.to_owned(),
        file_name: "../escape.bin".to_owned(),
        size: 0,
        mtime_ms: 0,
        blake3: blake3::hash(b"").to_hex().to_string(),
        chunk_size: TRANSFER_CHUNK_SIZE,
        total_chunks: 0,
        created_at_ms: NOW_MS,
        expires_at_ms: NOW_MS + TRANSFER_OFFER_TTL_MS,
    };
    let error = manifest.validate().expect_err("path traversal");
    assert_eq!(error.code(), TransferErrorCode::InvalidArgument);
    manifest.file_name = "..\\escape.bin".to_owned();
    assert_eq!(
        manifest
            .validate()
            .expect_err("windows path traversal")
            .code(),
        TransferErrorCode::InvalidArgument
    );
    assert_eq!(TransferDirection::Receive.as_str(), "receive");
}

#[test]
fn sender_checkpoint_survives_database_reopen() {
    let temporary = TempDir::new();
    let source = temporary.path().join("small.bin");
    let database = temporary.path().join("transfer.db");
    std::fs::write(&source, b"small file").expect("source");
    let (mut sender, _offer, _) = TransferSender::create(
        TransferStore::open(&database).expect("database"),
        StdFileStore::new(),
        &source,
        TRANSFER_ID,
        SENDER_ID,
        "device-receiver",
        NOW_MS,
    )
    .expect("sender");
    sender.accept(0, NOW_MS).expect("accept");
    let frames = sender.read_window().expect("window");
    let acknowledged = frames
        .iter()
        .map(|frame| u64::from(frame.length))
        .sum::<u64>();
    sender
        .acknowledge(acknowledged, NOW_MS + 1)
        .expect("checkpoint");
    drop(sender);

    let reopened = TransferSender::reopen(
        TransferStore::open(&database).expect("reopened database"),
        StdFileStore::new(),
        &source,
        TRANSFER_ID,
    )
    .expect("reopen sender");
    assert_eq!(reopened.manifest().size, acknowledged);
    assert_eq!(
        reopened.snapshot().expect("snapshot").job.durable_bytes,
        acknowledged
    );
    let completed = reopened.complete(NOW_MS + 2).expect("complete sender");
    assert_eq!(completed.job.state, TransferState::Completed);
}

#[test]
fn paired_device_public_key_maps_to_a_stable_iroh_endpoint_id() {
    let key = ed25519_dalek::SigningKey::from_bytes(&[7_u8; 32]);
    let public_key_hex = key
        .verifying_key()
        .to_bytes()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    let endpoint_id = endpoint_id_for_public_key(&public_key_hex).expect("endpoint id");
    assert!(!endpoint_id.is_empty());
    assert_eq!(
        endpoint_id_for_public_key("not-a-key")
            .expect_err("invalid key")
            .code(),
        TransferErrorCode::InvalidArgument
    );
}

use covio_core::file_transfer::{
    DirectoryConflictPolicy, DirectoryEntry, DirectoryEntryKind, DirectoryManifest,
    DirectoryMetadata, DirectoryTransferOffer, DirectoryTransferReceiver, FileChunkFrame,
    TRANSFER_CHUNK_SIZE, TRANSFER_OFFER_TTL_MS, TransferErrorCode, TransferRetentionPolicy,
    TransferState, TransferStore,
};
use covio_platform::StdFileStore;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

const NOW_MS: i64 = 1_800_000_000_000;
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
            "covio-directory-integration-{}-{nonce}-{sequence}",
            std::process::id()
        ));
        std::fs::create_dir_all(&path).expect("temporary directory");
        Self(path)
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn bytes(size: usize) -> Vec<u8> {
    (0..size)
        .map(|index| u8::try_from(index % 251).expect("byte"))
        .collect()
}

fn metadata() -> DirectoryMetadata {
    DirectoryMetadata {
        modified_at_ms: NOW_MS,
        readonly: false,
        executable: false,
    }
}

fn offer(root_name: &str, file_name: &str, content: &[u8]) -> DirectoryTransferOffer {
    let manifest = DirectoryManifest::from_entries(
        "tr-directory-integration",
        "device-sender",
        root_name,
        metadata(),
        vec![
            DirectoryEntry::directory("empty", metadata()),
            DirectoryEntry::directory("nested", metadata()),
            DirectoryEntry::file(
                format!("nested/{file_name}"),
                content.len() as u64,
                blake3::hash(content).to_hex().to_string(),
                metadata(),
            ),
        ],
        NOW_MS,
        NOW_MS + TRANSFER_OFFER_TTL_MS,
    )
    .expect("manifest");
    DirectoryTransferOffer::new(manifest).expect("offer")
}

fn open_receiver(root: &Path, database: &Path) -> DirectoryTransferReceiver<StdFileStore> {
    DirectoryTransferReceiver::new(
        TransferStore::open(database).expect("database"),
        StdFileStore::new(),
        root,
    )
}

#[test]
fn manifest_scan_preserves_nested_files_empty_directories_and_metadata() {
    let temporary = TempDir::new();
    let source = temporary.0.join("source");
    std::fs::create_dir_all(source.join("nested/empty")).expect("source directories");
    std::fs::write(source.join("nested/report.txt"), b"report").expect("source file");
    let manifest = DirectoryManifest::from_directory(
        &StdFileStore::new(),
        &source,
        "tr-directory-scan",
        "device-sender",
        NOW_MS,
        TRANSFER_OFFER_TTL_MS,
    )
    .expect("manifest");
    assert_eq!(manifest.root_name, "source");
    assert_eq!(manifest.file_count, 1);
    assert_eq!(manifest.directory_count, 2);
    assert!(manifest.entries.iter().any(|entry| {
        entry.relative_path == "nested/empty" && entry.kind == DirectoryEntryKind::Directory
    }));
    let file = manifest
        .entries
        .iter()
        .find(|entry| entry.relative_path == "nested/report.txt")
        .expect("file entry");
    assert_eq!(file.size, 6);
    assert!(file.metadata.modified_at_ms > 0);
    assert_eq!(manifest.digest().expect("digest").len(), 64);
}

#[cfg(unix)]
#[test]
fn manifest_scan_refuses_symbolic_links_without_following_them() {
    use std::os::unix::fs::symlink;

    let temporary = TempDir::new();
    let source = temporary.0.join("source");
    std::fs::create_dir_all(&source).expect("source");
    std::fs::write(temporary.0.join("outside.txt"), b"outside").expect("outside file");
    symlink(temporary.0.join("outside.txt"), source.join("link")).expect("symlink");
    let error = DirectoryManifest::from_directory(
        &StdFileStore::new(),
        &source,
        "tr-directory-link",
        "device-sender",
        NOW_MS,
        TRANSFER_OFFER_TTL_MS,
    )
    .expect_err("symlink");
    assert_eq!(error.code(), TransferErrorCode::SymlinkRefused);
}

#[test]
fn damaged_offer_manifest_is_rejected() {
    let mut offer = offer("incoming", "small.bin", b"content");
    offer.manifest.entries[2].size = 1;
    assert_eq!(
        offer.validate().expect_err("changed manifest").code(),
        TransferErrorCode::ManifestInvalid
    );
}

#[test]
fn interrupted_directory_transfer_resumes_from_verified_chunks() {
    let temporary = TempDir::new();
    let destination = temporary.0.join("destination");
    let database = temporary.0.join("transfer.db");
    let content = bytes(TRANSFER_CHUNK_SIZE as usize + 20);
    let offer = offer("incoming", "large.bin", &content);
    let receiver = open_receiver(&destination, &database);
    receiver.receive_offer(&offer, NOW_MS).expect("offer");
    receiver
        .accept(
            &offer.manifest.transfer_id,
            DirectoryConflictPolicy::KeepBoth,
            NOW_MS,
        )
        .expect("accept");
    let first = FileChunkFrame::new(0, content[..TRANSFER_CHUNK_SIZE as usize].to_vec());
    receiver
        .receive_chunk(
            &offer.manifest.transfer_id,
            "nested/large.bin",
            &first,
            NOW_MS,
        )
        .expect("first chunk");
    drop(receiver);

    let receiver = open_receiver(&destination, &database);
    let resume = receiver
        .resume(&offer.manifest.transfer_id, NOW_MS + 1)
        .expect("resume");
    assert_eq!(
        resume
            .entry("nested/large.bin")
            .expect("entry")
            .verified_bytes,
        u64::from(TRANSFER_CHUNK_SIZE)
    );
    let second = FileChunkFrame::new(
        u64::from(TRANSFER_CHUNK_SIZE),
        content[TRANSFER_CHUNK_SIZE as usize..].to_vec(),
    );
    receiver
        .receive_chunk(
            &offer.manifest.transfer_id,
            "nested/large.bin",
            &second,
            NOW_MS + 2,
        )
        .expect("second chunk");
    receiver
        .complete_entry(&offer.manifest.transfer_id, "nested/large.bin", NOW_MS + 3)
        .expect("complete entry");
    let completed = receiver
        .complete(&offer.manifest.transfer_id, NOW_MS + 4)
        .expect("complete directory");
    assert_eq!(completed.committed_files, 1);
    assert!(destination.join("incoming/empty").is_dir());
    assert_eq!(
        std::fs::read(destination.join("incoming/nested/large.bin")).expect("final file"),
        content
    );
    assert!(
        !destination
            .join(".covio/staging/tr-directory-integration")
            .exists()
    );
}

#[test]
fn keep_both_commits_a_new_name_without_changing_the_existing_file() {
    let temporary = TempDir::new();
    let destination = temporary.0.join("destination");
    std::fs::create_dir_all(destination.join("incoming/nested")).expect("existing tree");
    let existing = destination.join("incoming/nested/report.bin");
    std::fs::write(&existing, b"old").expect("existing file");
    let database = temporary.0.join("transfer.db");
    let content = b"new";
    let offer = offer("incoming", "report.bin", content);
    let receiver = open_receiver(&destination, &database);
    receiver.receive_offer(&offer, NOW_MS).expect("offer");
    let accepted = receiver
        .accept(
            &offer.manifest.transfer_id,
            DirectoryConflictPolicy::KeepBoth,
            NOW_MS,
        )
        .expect("accept");
    assert_eq!(
        accepted
            .plan
            .file_entry("nested/report.bin")
            .expect("plan")
            .target_relative_path,
        "nested/report (1).bin"
    );
    receiver
        .receive_chunk(
            &offer.manifest.transfer_id,
            "nested/report.bin",
            &FileChunkFrame::new(0, content.to_vec()),
            NOW_MS,
        )
        .expect("chunk");
    receiver
        .complete_entry(&offer.manifest.transfer_id, "nested/report.bin", NOW_MS)
        .expect("commit");
    assert_eq!(std::fs::read(&existing).expect("old file"), b"old");
    assert_eq!(
        std::fs::read(destination.join("incoming/nested/report (1).bin")).expect("new file"),
        content
    );
}

#[test]
fn retention_removes_cancelled_staging_and_checkpoints_but_keeps_metadata() {
    let temporary = TempDir::new();
    let destination = temporary.0.join("destination");
    let database = temporary.0.join("transfer.db");
    let content = bytes(16);
    let offer = offer("incoming", "small.bin", &content);
    let receiver = open_receiver(&destination, &database);
    receiver.receive_offer(&offer, NOW_MS).expect("offer");
    receiver
        .accept(
            &offer.manifest.transfer_id,
            DirectoryConflictPolicy::KeepBoth,
            NOW_MS,
        )
        .expect("accept");
    receiver
        .receive_chunk(
            &offer.manifest.transfer_id,
            "nested/small.bin",
            &FileChunkFrame::new(0, content),
            NOW_MS,
        )
        .expect("chunk");
    receiver
        .cancel(&offer.manifest.transfer_id, NOW_MS + 1)
        .expect("cancel");
    let sweep = receiver
        .sweep_retention(
            NOW_MS + 1 + 24 * 60 * 60 * 1_000,
            TransferRetentionPolicy::default(),
        )
        .expect("retention");
    assert_eq!(sweep.cleaned_staging, 1);
    assert!(
        !destination
            .join(".covio/staging/tr-directory-integration")
            .exists()
    );
    assert!(
        receiver
            .store()
            .directory_chunks(&offer.manifest.transfer_id)
            .expect("chunks")
            .is_empty()
    );
    assert_eq!(
        receiver
            .snapshot(&offer.manifest.transfer_id)
            .expect("snapshot")
            .job
            .state,
        TransferState::Cancelled
    );
}

#[test]
fn completed_metadata_retention_never_deletes_the_final_file() {
    let temporary = TempDir::new();
    let destination = temporary.0.join("destination");
    let database = temporary.0.join("transfer.db");
    let content = b"keep me";
    let offer = offer("incoming", "small.bin", content);
    let receiver = open_receiver(&destination, &database);
    receiver.receive_offer(&offer, NOW_MS).expect("offer");
    receiver
        .accept(
            &offer.manifest.transfer_id,
            DirectoryConflictPolicy::KeepBoth,
            NOW_MS,
        )
        .expect("accept");
    receiver
        .receive_chunk(
            &offer.manifest.transfer_id,
            "nested/small.bin",
            &FileChunkFrame::new(0, content.to_vec()),
            NOW_MS,
        )
        .expect("chunk");
    receiver
        .complete_entry(&offer.manifest.transfer_id, "nested/small.bin", NOW_MS)
        .expect("complete entry");
    receiver
        .complete(&offer.manifest.transfer_id, NOW_MS + 1)
        .expect("complete");
    let final_path = destination.join("incoming/nested/small.bin");
    assert_eq!(std::fs::read(&final_path).expect("final file"), content);
    let sweep = receiver
        .sweep_retention(
            NOW_MS + 1 + 30 * 24 * 60 * 60 * 1_000,
            TransferRetentionPolicy::default(),
        )
        .expect("retention");
    assert_eq!(sweep.purged_metadata, 1);
    assert_eq!(std::fs::read(&final_path).expect("retained file"), content);
    assert!(receiver.snapshot(&offer.manifest.transfer_id).is_err());
}

#[test]
fn replace_overwrites_only_after_chunk_verification() {
    let temporary = TempDir::new();
    let destination = temporary.0.join("destination");
    std::fs::create_dir_all(destination.join("incoming/nested")).expect("existing tree");
    let target = destination.join("incoming/nested/report.bin");
    std::fs::write(&target, b"old").expect("existing file");
    let database = temporary.0.join("transfer.db");
    let content = b"replacement";
    let offer = offer("incoming", "report.bin", content);
    let receiver = open_receiver(&destination, &database);
    receiver.receive_offer(&offer, NOW_MS).expect("offer");
    receiver
        .accept(
            &offer.manifest.transfer_id,
            DirectoryConflictPolicy::Replace,
            NOW_MS,
        )
        .expect("accept");
    receiver
        .receive_chunk(
            &offer.manifest.transfer_id,
            "nested/report.bin",
            &FileChunkFrame::new(0, content.to_vec()),
            NOW_MS,
        )
        .expect("chunk");
    receiver
        .complete_entry(&offer.manifest.transfer_id, "nested/report.bin", NOW_MS)
        .expect("replace");
    assert_eq!(std::fs::read(&target).expect("replaced file"), content);
}

#[test]
fn skip_keeps_the_existing_file_and_continues_with_other_entries() {
    let temporary = TempDir::new();
    let destination = temporary.0.join("destination");
    std::fs::create_dir_all(destination.join("incoming/nested")).expect("existing tree");
    let target = destination.join("incoming/nested/report.bin");
    std::fs::write(&target, b"old").expect("existing file");
    let database = temporary.0.join("transfer.db");
    let offer = offer("incoming", "report.bin", b"new");
    let receiver = open_receiver(&destination, &database);
    receiver.receive_offer(&offer, NOW_MS).expect("offer");
    let accepted = receiver
        .accept(
            &offer.manifest.transfer_id,
            DirectoryConflictPolicy::Skip,
            NOW_MS,
        )
        .expect("accept");
    assert_eq!(accepted.plan.skipped_count(), 1);
    let outcome = receiver
        .complete_entry(&offer.manifest.transfer_id, "nested/report.bin", NOW_MS)
        .expect("skip");
    assert!(!outcome.duplicate);
    let completed = receiver
        .complete(&offer.manifest.transfer_id, NOW_MS + 1)
        .expect("complete directory");
    assert_eq!(completed.skipped_files, 1);
    assert_eq!(std::fs::read(&target).expect("existing file"), b"old");
    assert!(destination.join("incoming/empty").is_dir());
}

#[test]
fn version_one_database_migrates_to_the_directory_schema() {
    let temporary = TempDir::new();
    let database = temporary.0.join("transfer.db");
    let connection = rusqlite::Connection::open(&database).expect("database");
    connection
        .execute_batch("PRAGMA user_version = 1;")
        .expect("version");
    drop(connection);
    let store = TransferStore::open(&database).expect("migrated store");
    let offer = offer("incoming", "small.bin", b"small");
    store
        .create_directory_job(
            &offer,
            "device-sender",
            covio_core::file_transfer::TransferDirection::Receive,
            NOW_MS,
        )
        .expect("directory job");
    let connection = rusqlite::Connection::open(&database).expect("reopened database");
    let version: i64 = connection
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .expect("schema version");
    assert_eq!(version, 2);
}

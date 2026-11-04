use covio_core::workspace::{
    WorkspaceAvailability, WorkspaceEntry, WorkspaceErrorCode, WorkspaceKind, WorkspacePolicy,
    WorkspaceState, WorkspaceStore, WorkspaceTombstone, WorkspaceTransferEngine, WorkspaceWire,
};
use covio_platform::{FileStore, PlatformError};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;

const WORKSPACE_DIR: &str = "/tmp/covio/workspace";
const INDEX_PATH: &str = "/tmp/covio/workspace/index.json";
const TOMBSTONES_PATH: &str = "/tmp/covio/workspace/tombstones.json";
const INDEX_FIXTURE: &str = include_str!("fixtures/workspace-index.json");
const TOMBSTONES_FIXTURE: &str = include_str!("fixtures/workspace-tombstones.json");
const REQUEST_FIXTURE: &str = include_str!("fixtures/workspace-request.json");
const RESPONSE_FIXTURE: &str = include_str!("fixtures/workspace-response.json");

#[derive(Default)]
struct MemoryInner {
    files: RefCell<BTreeMap<PathBuf, Vec<u8>>>,
    fail_write: RefCell<bool>,
}

#[derive(Clone, Default)]
struct MemoryFiles(Rc<MemoryInner>);

impl MemoryFiles {
    fn with_file(path: &str, text: &str) -> Self {
        let files = Self::default();
        files
            .0
            .files
            .borrow_mut()
            .insert(PathBuf::from(path), text.as_bytes().to_vec());
        files
    }

    fn text(&self, path: &str) -> String {
        String::from_utf8(self.0.files.borrow()[&PathBuf::from(path)].clone()).expect("utf-8")
    }
}

impl FileStore for MemoryFiles {
    fn read(&self, path: &Path) -> Result<Option<Vec<u8>>, PlatformError> {
        Ok(self.0.files.borrow().get(path).cloned())
    }

    fn exists(&self, path: &Path) -> Result<bool, PlatformError> {
        Ok(self.0.files.borrow().contains_key(path))
    }

    fn metadata_size(&self, path: &Path) -> Result<Option<u64>, PlatformError> {
        Ok(self
            .0
            .files
            .borrow()
            .get(path)
            .map(|contents| contents.len() as u64))
    }

    fn read_range(
        &self,
        path: &Path,
        offset: u64,
        length: usize,
    ) -> Result<Option<Vec<u8>>, PlatformError> {
        Ok(self.0.files.borrow().get(path).map(|contents| {
            let start = usize::try_from(offset)
                .unwrap_or(usize::MAX)
                .min(contents.len());
            let end = start.saturating_add(length).min(contents.len());
            contents[start..end].to_vec()
        }))
    }

    fn create_dir_all(&self, _path: &Path) -> Result<(), PlatformError> {
        Ok(())
    }

    fn write_atomic(&self, path: &Path, contents: &[u8]) -> Result<(), PlatformError> {
        if *self.0.fail_write.borrow() {
            return Err(PlatformError::io("write failed", false));
        }
        self.0
            .files
            .borrow_mut()
            .insert(path.to_path_buf(), contents.to_vec());
        Ok(())
    }

    fn append(&self, path: &Path, contents: &[u8]) -> Result<u64, PlatformError> {
        if *self.0.fail_write.borrow() {
            return Err(PlatformError::io("append failed", false));
        }
        let mut files = self.0.files.borrow_mut();
        let value = files.entry(path.to_path_buf()).or_default();
        value.extend_from_slice(contents);
        Ok(value.len() as u64)
    }

    fn atomic_move(&self, source: &Path, target: &Path) -> Result<(), PlatformError> {
        if *self.0.fail_write.borrow() {
            return Err(PlatformError::io("move failed", false));
        }
        let mut files = self.0.files.borrow_mut();
        let contents = files
            .remove(source)
            .ok_or_else(|| PlatformError::io("source missing", false))?;
        files.insert(target.to_path_buf(), contents);
        Ok(())
    }

    fn remove_file(&self, path: &Path) -> Result<bool, PlatformError> {
        Ok(self.0.files.borrow_mut().remove(path).is_some())
    }

    fn remove_tree(&self, path: &Path) -> Result<(), PlatformError> {
        self.0
            .files
            .borrow_mut()
            .retain(|candidate, _| !candidate.starts_with(path));
        Ok(())
    }
}

fn digest(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hasher
        .finalize()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

fn entry(id: &str, size: i64, at: i64) -> WorkspaceEntry {
    WorkspaceEntry {
        entry_id: id.to_owned(),
        kind: WorkspaceKind::Text,
        display_name: "notes.txt".to_owned(),
        byte_size: size,
        content_type: "text/plain".to_owned(),
        created_at_epoch_seconds: at,
        origin_device_id: "device-a".to_owned(),
        expires_at_epoch_seconds: 0,
        availability: WorkspaceAvailability::Local,
        pinned: false,
    }
}

#[test]
fn workspace_index_fixture_round_trips() {
    let files = MemoryFiles::with_file(INDEX_PATH, INDEX_FIXTURE);
    let store = WorkspaceStore::new(WORKSPACE_DIR, files.clone());
    let state = store.load();
    assert_eq!(state.entries.len(), 2);
    store.save(&state).expect("save index");

    let actual: Value = serde_json::from_str(&files.text(INDEX_PATH)).expect("saved index");
    let expected: Value = serde_json::from_str(INDEX_FIXTURE).expect("fixture");
    assert_eq!(actual, expected);
}

#[test]
fn tombstones_fixture_round_trips() {
    let files = MemoryFiles::with_file(TOMBSTONES_PATH, TOMBSTONES_FIXTURE);
    let store = WorkspaceStore::new(WORKSPACE_DIR, files.clone());
    let tombstones = store.load_tombstones();
    assert_eq!(tombstones.len(), 1);
    store.save_tombstones(&tombstones).expect("save tombstones");
    let actual: Value = serde_json::from_str(&files.text(TOMBSTONES_PATH)).expect("saved");
    let expected: Value = serde_json::from_str(TOMBSTONES_FIXTURE).expect("fixture");
    assert_eq!(actual, expected);
}

#[test]
fn wire_request_and_response_fixtures_keep_their_shape() {
    let request = WorkspaceWire::decode_request(REQUEST_FIXTURE).expect("request");
    let encoded = WorkspaceWire::encode_request(&request).expect("encode");
    assert_eq!(
        serde_json::from_str::<Value>(&encoded).expect("encoded json"),
        serde_json::from_str::<Value>(REQUEST_FIXTURE).expect("fixture json")
    );
    assert!(matches!(
        WorkspaceWire::entry_from_args(&request.args),
        covio_core::workspace::WorkspaceEntryParse::Ok(_)
    ));

    let response = WorkspaceWire::decode_response(RESPONSE_FIXTURE).expect("response");
    let encoded = WorkspaceWire::encode_response(&response).expect("encode");
    assert_eq!(
        serde_json::from_str::<Value>(&encoded).expect("encoded json"),
        serde_json::from_str::<Value>(RESPONSE_FIXTURE).expect("fixture json")
    );
}

#[test]
fn content_is_content_addressed_and_digest_checked() {
    let files = MemoryFiles::default();
    let store = WorkspaceStore::new(WORKSPACE_DIR, files.clone());
    let content = b"hello workspace";
    let id = digest(content);
    assert!(store.put_content(&id, content).expect("put"));
    assert!(store.has_content(&id));
    assert_eq!(store.read_content(&id).as_deref(), Some(content.as_slice()));
    assert!(store.verify_content(&id));
    assert!(
        !store
            .put_content(&digest(b"other"), content)
            .expect("mismatch")
    );
}

#[test]
fn corrupted_index_returns_defaults() {
    let files = MemoryFiles::with_file(INDEX_PATH, "{");
    let store = WorkspaceStore::new(WORKSPACE_DIR, files);
    assert_eq!(store.load(), WorkspaceState::default());
}

#[test]
fn put_file_reads_and_commits_content_through_the_filesystem_port() {
    let source = "/tmp/covio/source.txt";
    let files = MemoryFiles::with_file(source, "file content");
    let store = WorkspaceStore::new(WORKSPACE_DIR, files);
    let result = store.put_file(
        &WorkspaceState::default(),
        source,
        "folder/source.txt",
        "text/plain",
        "device-a",
        10,
    );
    assert!(result.accepted());
    let entry = result.entry.expect("entry");
    assert_eq!(entry.display_name, "source.txt");
    assert_eq!(entry.byte_size, 12);
    assert_eq!(
        store.read_content(&entry.entry_id).as_deref(),
        Some(b"file content".as_slice())
    );
}

#[test]
fn transfer_resume_commit_and_delete_follow_the_contract() {
    let files = MemoryFiles::default();
    let store = WorkspaceStore::new(WORKSPACE_DIR, files);
    let transfer = WorkspaceTransferEngine::new(store);
    let content = b"transfer content";
    let id = digest(content);
    let args = WorkspaceWire::args_from_entry(&entry(&id, content.len() as i64, 10));
    let begin = transfer.begin(&args, 10);
    assert!(begin.accepted);
    assert_eq!(begin.task_id.as_deref(), Some(id.as_str()));
    assert_eq!(begin.received, 0);

    let split = content.len() / 2;
    assert_eq!(
        transfer.chunk(&id, 0, &content[..split]),
        covio_core::workspace::WorkspaceChunkResult {
            received: split as i64,
            error_code: None
        }
    );
    assert_eq!(
        transfer.chunk(&id, 0, &content[split..]).received,
        split as i64
    );
    assert!(
        transfer
            .chunk(&id, split as i64, &content[split..])
            .error_code
            .is_none()
    );
    assert!(transfer.commit(&id, &id).ok);
    assert_eq!(
        transfer.store().read_content(&id).as_deref(),
        Some(content.as_slice())
    );
    assert!(transfer.delete(&id, 20).ok);
    assert!(!transfer.store().has_content(&id));
}

#[test]
fn transfer_cancel_resume_list_and_stat_report_stale_state() {
    let files = MemoryFiles::default();
    let store = WorkspaceStore::new(WORKSPACE_DIR, files);
    let transfer = WorkspaceTransferEngine::new(store);
    let content = b"abcdef";
    let id = digest(content);
    assert!(
        transfer
            .begin(
                &WorkspaceWire::args_from_entry(&entry(&id, content.len() as i64, 10)),
                10,
            )
            .accepted
    );
    assert_eq!(transfer.chunk(&id, 0, &content[..3]).received, 3);
    assert_eq!(transfer.resume_offset(&id), 3);
    assert_eq!(transfer.list(0, 10)[0].entry_id, id);
    let stat = transfer.stat();
    assert_eq!(stat.total_bytes, content.len() as i64);
    assert_eq!(stat.entry_count, 1);
    assert!(transfer.cancel(&id));
    assert_eq!(
        transfer.store().load().entries[0].availability,
        WorkspaceAvailability::Remote
    );
    assert_eq!(transfer.resume_offset(&id), 0);
    assert_eq!(transfer.stat().total_bytes, 0);
    assert_eq!(
        transfer.chunk(&id, 0, content).error_code,
        Some(WorkspaceErrorCode::EntryNotFound)
    );
}

#[test]
fn empty_transfer_commits() {
    let files = MemoryFiles::default();
    let store = WorkspaceStore::new(WORKSPACE_DIR, files);
    let transfer = WorkspaceTransferEngine::new(store);
    let id = digest(b"");
    let begin = transfer.begin(&WorkspaceWire::args_from_entry(&entry(&id, 0, 10)), 10);
    assert!(begin.accepted);
    assert!(transfer.commit(&id, &id).ok);
}

#[test]
fn transfer_rejects_bad_checksum_quota_and_tombstones() {
    let files = MemoryFiles::default();
    let store = WorkspaceStore::new(WORKSPACE_DIR, files);
    let transfer = WorkspaceTransferEngine::new(store);
    let content = b"bad";
    let id = digest(content);
    let args = WorkspaceWire::args_from_entry(&entry(&id, content.len() as i64, 10));
    assert!(transfer.begin(&args, 10).accepted);
    let _ = transfer.chunk(&id, 0, content);
    assert_eq!(
        transfer.commit(&id, &digest(b"wrong")).error_code,
        Some(WorkspaceErrorCode::ChecksumMismatch)
    );

    let tombstoned = entry(&digest(b"tombstoned"), 1, 10);
    transfer
        .store()
        .save_tombstones(&[WorkspaceTombstone {
            entry_id: tombstoned.entry_id.clone(),
            deleted_at_epoch_seconds: 10,
        }])
        .expect("save tombstone");
    assert_eq!(
        transfer
            .begin(&WorkspaceWire::args_from_entry(&tombstoned), 10)
            .error_code,
        Some(WorkspaceErrorCode::EntryNotFound)
    );

    let quota_id = digest(b"quota");
    let policy = WorkspaceStore::new(WORKSPACE_DIR, MemoryFiles::default());
    policy
        .save(&WorkspaceState {
            policy: WorkspacePolicy {
                max_total_bytes: 1,
                max_entry_bytes: 1,
                ..WorkspacePolicy::default()
            },
            ..WorkspaceState::default()
        })
        .expect("save policy");
    let quota_transfer = WorkspaceTransferEngine::new(policy);
    let quota = entry(&quota_id, 2, 10);
    assert_eq!(
        quota_transfer
            .begin(&WorkspaceWire::args_from_entry(&quota), 10)
            .error_code,
        Some(WorkspaceErrorCode::QuotaExceeded)
    );
}

#[test]
fn lazy_fetch_keeps_only_remote_index_entry() {
    let files = MemoryFiles::default();
    let store = WorkspaceStore::new(WORKSPACE_DIR, files);
    store
        .save(&WorkspaceState {
            policy: WorkspacePolicy {
                lazy_fetch_threshold_bytes: 4,
                ..WorkspacePolicy::default()
            },
            ..WorkspaceState::default()
        })
        .expect("save policy");
    let transfer = WorkspaceTransferEngine::new(store);
    let id = digest(b"large");
    let begin = transfer.begin(&WorkspaceWire::args_from_entry(&entry(&id, 5, 10)), 10);
    assert!(begin.accepted);
    assert!(begin.task_id.is_none());
    assert_eq!(
        transfer.store().load().entries[0].availability,
        WorkspaceAvailability::Remote
    );
}

//! Verified directory resume ranges.

use super::super::{TRANSFER_CHUNK_SIZE, TransferError, TransferErrorCode, blake3_hex};
use super::conflict::{DirectoryConflictAction, DirectoryConflictPlan};
use super::manifest::{DirectoryEntry, DirectoryEntryKind, DirectoryManifest};
use covio_platform::FileStore;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

/// One durable chunk checkpoint for a directory file entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryChunkCheckpoint {
    /// Source path relative to the transfer root.
    pub relative_path: String,
    /// Zero-based chunk index within the file.
    pub chunk_index: u64,
    /// Absolute byte offset within the file.
    pub offset: u64,
    /// Chunk payload length.
    pub length: u32,
    /// Lowercase BLAKE3 payload digest.
    pub blake3: String,
}

/// Verified resume state for one file entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryEntryResume {
    /// Source path relative to the transfer root.
    pub relative_path: String,
    /// Final path relative to the transfer root.
    pub target_relative_path: String,
    /// Planned conflict action.
    pub action: DirectoryConflictAction,
    /// Durable verified byte count.
    pub verified_bytes: u64,
    /// Total file size.
    pub total_bytes: u64,
    /// Hidden unverified bytes that were removed before resume.
    pub discarded_tail_bytes: u64,
    /// Same-volume staging path.
    pub staging_path: PathBuf,
}

/// Verified resume state for one directory transfer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryResumePlan {
    /// Transfer identifier.
    pub transfer_id: String,
    /// File entries that can resume.
    pub entries: Vec<DirectoryEntryResume>,
    /// Sum of verified bytes across file entries.
    pub verified_bytes: u64,
}

impl DirectoryResumePlan {
    /// Returns one entry resume state.
    #[must_use]
    pub fn entry(&self, relative_path: &str) -> Option<&DirectoryEntryResume> {
        self.entries
            .iter()
            .find(|entry| entry.relative_path == relative_path)
    }
}

/// Verifies every durable chunk range, then removes bytes beyond the verified prefix.
pub fn verify_directory_resume<F: FileStore>(
    files: &F,
    manifest: &DirectoryManifest,
    plan: &DirectoryConflictPlan,
    checkpoints: &[DirectoryChunkCheckpoint],
    staging_root: &Path,
) -> Result<DirectoryResumePlan, TransferError> {
    manifest.validate()?;
    if plan.root_name != manifest.root_name {
        return Err(invalid_checkpoint(
            "directory plan does not match the manifest",
        ));
    }
    let entries = manifest
        .entries
        .iter()
        .filter(|entry| entry.kind == DirectoryEntryKind::File)
        .map(|entry| (entry.relative_path.as_str(), entry))
        .collect::<HashMap<_, _>>();
    let mut checkpoints_by_path: HashMap<&str, Vec<&DirectoryChunkCheckpoint>> = HashMap::new();
    for checkpoint in checkpoints {
        let path = checkpoint.relative_path.as_str();
        if !entries.contains_key(path) {
            return Err(invalid_checkpoint("checkpoint references an unknown file"));
        }
        checkpoints_by_path
            .entry(path)
            .or_default()
            .push(checkpoint);
    }

    files
        .create_dir_all(staging_root)
        .map_err(TransferError::from_platform)?;
    let mut resumed = Vec::new();
    let mut total_verified = 0_u64;
    for planned in &plan.entries {
        if planned.entry.kind != DirectoryEntryKind::File
            || planned.action == DirectoryConflictAction::Skip
        {
            continue;
        }
        let entry = entries
            .get(planned.entry.relative_path.as_str())
            .copied()
            .ok_or_else(|| invalid_checkpoint("plan references an unknown file"))?;
        let staging_path = staging_path_for(staging_root, &entry.relative_path);
        let mut ranges = checkpoints_by_path
            .remove(entry.relative_path.as_str())
            .unwrap_or_default();
        ranges.sort_by_key(|checkpoint| checkpoint.chunk_index);
        let (verified_bytes, discarded_tail_bytes) =
            verify_entry_ranges(files, entry, &staging_path, &ranges)?;
        total_verified = total_verified
            .checked_add(verified_bytes)
            .ok_or_else(|| invalid_checkpoint("verified byte count overflow"))?;
        resumed.push(DirectoryEntryResume {
            relative_path: entry.relative_path.clone(),
            target_relative_path: planned.target_relative_path.clone(),
            action: planned.action,
            verified_bytes,
            total_bytes: entry.size,
            discarded_tail_bytes,
            staging_path,
        });
    }
    if !checkpoints_by_path.is_empty() {
        return Err(invalid_checkpoint("checkpoint references a skipped file"));
    }
    Ok(DirectoryResumePlan {
        transfer_id: manifest.transfer_id.clone(),
        entries: resumed,
        verified_bytes: total_verified,
    })
}

/// Returns the deterministic staging path for one source path.
#[must_use]
pub fn staging_path_for(staging_root: &Path, relative_path: &str) -> PathBuf {
    staging_root.join(format!("{}.part", blake3_hex(relative_path.as_bytes())))
}

fn verify_entry_ranges<F: FileStore>(
    files: &F,
    entry: &DirectoryEntry,
    staging_path: &Path,
    ranges: &[&DirectoryChunkCheckpoint],
) -> Result<(u64, u64), TransferError> {
    let mut expected_offset = 0_u64;
    let mut seen_indexes = HashSet::new();
    for range in ranges {
        if !seen_indexes.insert(range.chunk_index) {
            return Err(invalid_checkpoint("duplicate chunk index"));
        }
        if range.chunk_index != expected_offset / u64::from(TRANSFER_CHUNK_SIZE)
            || range.offset != expected_offset
        {
            return Err(invalid_checkpoint("chunk checkpoints are not contiguous"));
        }
        if expected_offset >= entry.size {
            return Err(invalid_checkpoint("verified range exceeds the file size"));
        }
        let expected_length = (entry.size - expected_offset).min(u64::from(TRANSFER_CHUNK_SIZE));
        if expected_length == 0 || u64::from(range.length) != expected_length {
            return Err(invalid_checkpoint("chunk length is invalid"));
        }
        let length = usize::try_from(range.length)
            .map_err(|_| invalid_checkpoint("chunk length is invalid"))?;
        let bytes = files
            .read_range(staging_path, range.offset, length)
            .map_err(TransferError::from_platform)?
            .ok_or_else(|| invalid_checkpoint("staging file is missing"))?;
        if bytes.len() != length || blake3_hex(&bytes) != range.blake3 {
            return Err(invalid_checkpoint("durable chunk checksum is invalid"));
        }
        expected_offset = expected_offset
            .checked_add(u64::from(range.length))
            .ok_or_else(|| invalid_checkpoint("chunk offset overflow"))?;
    }
    if expected_offset > entry.size {
        return Err(invalid_checkpoint("verified range exceeds the file size"));
    }
    let actual_size = files
        .metadata_size(staging_path)
        .map_err(TransferError::from_platform)?;
    let discarded_tail_bytes = match actual_size {
        Some(size) if size < expected_offset => {
            return Err(invalid_checkpoint(
                "staging file is shorter than its checkpoint",
            ));
        }
        Some(size) => size - expected_offset,
        None if expected_offset == 0 => 0,
        None => return Err(invalid_checkpoint("staging file is missing")),
    };
    if actual_size.is_some_and(|size| size != expected_offset) {
        files
            .truncate(staging_path, expected_offset)
            .map_err(TransferError::from_platform)?;
    }
    if actual_size.is_none() {
        files
            .write_atomic(staging_path, b"")
            .map_err(TransferError::from_platform)?;
    }
    Ok((expected_offset, discarded_tail_bytes))
}

fn invalid_checkpoint(message: &'static str) -> TransferError {
    TransferError::new(TransferErrorCode::ResumeCheckpointInvalid, message, false)
}

#[cfg(test)]
mod tests {
    use super::super::conflict::{DirectoryConflictPolicy, plan_directory_conflicts};
    use super::super::manifest::DirectoryMetadata;
    use super::*;
    use covio_platform::StdFileStore;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("clock")
                .as_nanos();
            let sequence = NEXT_TEMP.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "covio-directory-resume-{}-{nonce}-{sequence}",
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

    fn manifest(bytes: &[u8]) -> DirectoryManifest {
        DirectoryManifest::from_entries(
            "tr-recovery-1",
            "device-sender",
            "root",
            DirectoryMetadata::default(),
            vec![
                DirectoryEntry::directory("nested", DirectoryMetadata::default()),
                DirectoryEntry::file(
                    "nested/large.bin",
                    bytes.len() as u64,
                    blake3_hex(bytes),
                    DirectoryMetadata::default(),
                ),
            ],
            10,
            20,
        )
        .expect("manifest")
    }

    #[test]
    fn resume_trusts_only_verified_prefix_and_truncates_tail() {
        let temporary = TempDir::new();
        let first = vec![7_u8; TRANSFER_CHUNK_SIZE as usize];
        let second = vec![9_u8; 20];
        let mut bytes = first.clone();
        bytes.extend_from_slice(&second);
        let manifest = manifest(&bytes);
        let plan = plan_directory_conflicts(&manifest, &[], DirectoryConflictPolicy::KeepBoth)
            .expect("plan");
        let staging_root = temporary.0.join("staging");
        let files = StdFileStore::new();
        std::fs::create_dir_all(&staging_root).expect("staging directory");
        let staging = staging_path_for(&staging_root, "nested/large.bin");
        let mut staged = first.clone();
        staged.extend_from_slice(b"unverified tail");
        files
            .write_atomic(&staging, &staged)
            .expect("staging write");
        let checkpoint = DirectoryChunkCheckpoint {
            relative_path: "nested/large.bin".to_owned(),
            chunk_index: 0,
            offset: 0,
            length: TRANSFER_CHUNK_SIZE,
            blake3: blake3_hex(&first),
        };
        let resume =
            verify_directory_resume(&files, &manifest, &plan, &[checkpoint], &staging_root)
                .expect("resume");
        let entry = resume.entry("nested/large.bin").expect("entry");
        assert_eq!(entry.verified_bytes, u64::from(TRANSFER_CHUNK_SIZE));
        assert_eq!(entry.discarded_tail_bytes, 15);
        assert_eq!(
            files.metadata_size(&staging).expect("size"),
            Some(u64::from(TRANSFER_CHUNK_SIZE))
        );
    }

    #[test]
    fn corrupt_checkpoint_is_not_trusted() {
        let temporary = TempDir::new();
        let bytes = b"verified payload";
        let manifest = manifest(bytes);
        let plan = plan_directory_conflicts(&manifest, &[], DirectoryConflictPolicy::KeepBoth)
            .expect("plan");
        let staging_root = temporary.0.join("staging");
        let files = StdFileStore::new();
        std::fs::create_dir_all(&staging_root).expect("staging directory");
        files
            .write_atomic(
                &staging_path_for(&staging_root, "nested/large.bin"),
                b"corrupt payload!",
            )
            .expect("staging write");
        let checkpoint = DirectoryChunkCheckpoint {
            relative_path: "nested/large.bin".to_owned(),
            chunk_index: 0,
            offset: 0,
            length: bytes.len() as u32,
            blake3: blake3_hex(bytes),
        };
        assert_eq!(
            verify_directory_resume(&files, &manifest, &plan, &[checkpoint], &staging_root,)
                .expect_err("corrupt checkpoint")
                .code(),
            TransferErrorCode::ResumeCheckpointInvalid
        );
    }
}

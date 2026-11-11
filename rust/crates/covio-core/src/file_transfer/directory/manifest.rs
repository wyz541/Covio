//! Directory manifests, metadata, and deterministic digests.

use super::super::{
    MAX_TRANSFER_BYTES, TRANSFER_CHUNK_SIZE, TRANSFER_PROTOCOL_VERSION, TransferError,
    TransferErrorCode, blake3_hex, decode_hex_32, random_hex, validate_identifier,
};
use super::path::{validate_component, validate_directory_path};
use covio_platform::{FileEntryKind, FileEntryMetadata, FileStore};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::path::Path;

/// Maximum number of entries in one directory manifest.
pub const MAX_DIRECTORY_ENTRIES: usize = 10_000;
/// Maximum total file bytes in one directory transfer.
pub const MAX_DIRECTORY_TOTAL_BYTES: u64 = 100 * 1024 * 1024 * 1024;

/// One manifest entry kind.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DirectoryEntryKind {
    /// A regular file.
    File,
    /// A directory, including an empty directory.
    Directory,
    /// A symbolic link. The first protocol version rejects this kind.
    Symlink,
}

/// Portable metadata retained by the first directory transfer version.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", default)]
pub struct DirectoryMetadata {
    /// Modification time in Unix milliseconds.
    pub modified_at_ms: i64,
    /// Whether the entry is read-only.
    pub readonly: bool,
    /// Whether the owner may execute the entry or traverse the directory.
    pub executable: bool,
}

/// One directory snapshot entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryEntry {
    /// NFC relative path with `/` separators.
    pub relative_path: String,
    /// Entry kind.
    pub kind: DirectoryEntryKind,
    /// File size in bytes. Directory entries use zero.
    pub size: u64,
    /// Lowercase BLAKE3 digest for file entries.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub blake3: Option<String>,
    /// Retained portable metadata.
    pub metadata: DirectoryMetadata,
}

impl DirectoryEntry {
    /// Creates a regular file entry.
    #[must_use]
    pub fn file(
        relative_path: impl Into<String>,
        size: u64,
        blake3: impl Into<String>,
        metadata: DirectoryMetadata,
    ) -> Self {
        Self {
            relative_path: relative_path.into(),
            kind: DirectoryEntryKind::File,
            size,
            blake3: Some(blake3.into()),
            metadata,
        }
    }

    /// Creates a directory entry.
    #[must_use]
    pub fn directory(relative_path: impl Into<String>, metadata: DirectoryMetadata) -> Self {
        Self {
            relative_path: relative_path.into(),
            kind: DirectoryEntryKind::Directory,
            size: 0,
            blake3: None,
            metadata,
        }
    }

    /// Returns the expected chunk count for a file entry.
    #[must_use]
    pub fn total_chunks(&self) -> u64 {
        match self.kind {
            DirectoryEntryKind::File => self.size.div_ceil(u64::from(TRANSFER_CHUNK_SIZE)),
            DirectoryEntryKind::Directory | DirectoryEntryKind::Symlink => 0,
        }
    }
}

/// One immutable directory snapshot.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryManifest {
    /// Manifest schema version.
    pub manifest_version: u16,
    /// Transfer identifier.
    pub transfer_id: String,
    /// Sender device identifier.
    pub sender_device_id: String,
    /// Destination root folder name.
    pub root_name: String,
    /// Retained metadata for the root folder.
    pub root_metadata: DirectoryMetadata,
    /// Sorted entries below the root folder.
    pub entries: Vec<DirectoryEntry>,
    /// Sum of file sizes.
    pub total_bytes: u64,
    /// Number of file entries.
    pub file_count: u32,
    /// Number of non-root directory entries.
    pub directory_count: u32,
    /// Manifest creation time in Unix milliseconds.
    pub created_at_ms: i64,
    /// Offer expiration time in Unix milliseconds.
    pub expires_at_ms: i64,
}

impl DirectoryManifest {
    /// Scans a source directory without following symbolic links.
    pub fn from_directory<F: FileStore>(
        files: &F,
        source: &Path,
        transfer_id: impl Into<String>,
        sender_device_id: impl Into<String>,
        now_ms: i64,
        ttl_ms: i64,
    ) -> Result<Self, TransferError> {
        let root_metadata = files
            .metadata(source)
            .map_err(TransferError::from_platform)?
            .ok_or_else(source_missing)?;
        if root_metadata.kind == FileEntryKind::Symlink {
            return Err(symlink_refused());
        }
        if root_metadata.kind != FileEntryKind::Directory {
            return Err(invalid_manifest("source root is not a directory"));
        }
        let root_name = source
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or_else(|| invalid_manifest("source root name is invalid"))?
            .to_owned();
        validate_component(&root_name)?;
        let mut entries = Vec::new();
        scan_directory(files, source, "", &mut entries)?;
        entries.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
        let expires_at_ms = now_ms.checked_add(ttl_ms).ok_or_else(|| {
            TransferError::invalid("directory transfer expiry is outside the supported range")
        })?;
        let manifest = Self::from_entries(
            transfer_id,
            sender_device_id,
            root_name,
            metadata_from_platform(&root_metadata),
            entries,
            now_ms,
            expires_at_ms,
        )?;
        Ok(manifest)
    }

    /// Creates a deterministic manifest from entries.
    pub fn from_entries(
        transfer_id: impl Into<String>,
        sender_device_id: impl Into<String>,
        root_name: impl Into<String>,
        root_metadata: DirectoryMetadata,
        mut entries: Vec<DirectoryEntry>,
        now_ms: i64,
        expires_at_ms: i64,
    ) -> Result<Self, TransferError> {
        entries.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
        let total_bytes = entries
            .iter()
            .try_fold(0_u64, |total, entry| total.checked_add(entry.size))
            .ok_or_else(|| invalid_manifest("directory size overflow"))?;
        let file_count = entries
            .iter()
            .filter(|entry| entry.kind == DirectoryEntryKind::File)
            .count();
        let directory_count = entries
            .iter()
            .filter(|entry| entry.kind == DirectoryEntryKind::Directory)
            .count();
        let manifest = Self {
            manifest_version: TRANSFER_PROTOCOL_VERSION,
            transfer_id: transfer_id.into(),
            sender_device_id: sender_device_id.into(),
            root_name: root_name.into(),
            root_metadata,
            entries,
            total_bytes,
            file_count: u32::try_from(file_count)
                .map_err(|_| invalid_manifest("directory file count is too large"))?,
            directory_count: u32::try_from(directory_count)
                .map_err(|_| invalid_manifest("directory entry count is too large"))?,
            created_at_ms: now_ms,
            expires_at_ms,
        };
        manifest.validate()?;
        Ok(manifest)
    }

    /// Validates path, hierarchy, metadata, counts, and limits.
    pub fn validate(&self) -> Result<(), TransferError> {
        if self.manifest_version != TRANSFER_PROTOCOL_VERSION {
            return Err(TransferError::new(
                TransferErrorCode::ProtocolVersionUnsupported,
                "directory manifest protocol version is unsupported",
                false,
            ));
        }
        validate_identifier("transfer id", &self.transfer_id)?;
        if self.sender_device_id.trim().is_empty() {
            return Err(invalid_manifest("sender device id is empty"));
        }
        validate_component(&self.root_name)?;
        if self.entries.len() > MAX_DIRECTORY_ENTRIES {
            return Err(invalid_manifest("directory manifest has too many entries"));
        }
        if self.expires_at_ms <= self.created_at_ms {
            return Err(invalid_manifest("directory manifest expiry is invalid"));
        }

        let mut total_bytes = 0_u64;
        let mut file_count = 0_u32;
        let mut directory_count = 0_u32;
        let mut case_keys = HashSet::new();
        let mut kinds = HashMap::new();
        let mut previous: Option<&str> = None;
        for entry in &self.entries {
            validate_directory_path(&entry.relative_path)?;
            if previous.is_some_and(|path| path >= entry.relative_path.as_str()) {
                return Err(invalid_manifest("directory entries are not sorted"));
            }
            previous = Some(&entry.relative_path);
            let case_key = super::path::path_collision_key(&entry.relative_path);
            if !case_keys.insert(case_key.clone()) {
                return Err(TransferError::new(
                    TransferErrorCode::PathCollision,
                    "directory entry paths collide",
                    false,
                ));
            }
            if let Some((parent, _)) = entry.relative_path.rsplit_once('/') {
                let parent_key = super::path::path_collision_key(parent);
                if kinds.get(&parent_key) != Some(&DirectoryEntryKind::Directory) {
                    return Err(invalid_manifest(
                        "directory entry parent is missing or not a directory",
                    ));
                }
            }
            validate_metadata(&entry.metadata)?;
            match entry.kind {
                DirectoryEntryKind::File => {
                    if entry.blake3.as_deref().is_none() {
                        return Err(invalid_manifest("file entry digest is missing"));
                    }
                    if let Some(digest) = entry.blake3.as_deref() {
                        decode_hex_32(digest, "file BLAKE3 digest")?;
                    }
                    if entry.size > MAX_TRANSFER_BYTES {
                        return Err(invalid_manifest("file entry exceeds the transfer limit"));
                    }
                    total_bytes = total_bytes
                        .checked_add(entry.size)
                        .ok_or_else(|| invalid_manifest("directory size overflow"))?;
                    file_count = file_count
                        .checked_add(1)
                        .ok_or_else(|| invalid_manifest("directory file count overflow"))?;
                }
                DirectoryEntryKind::Directory => {
                    if entry.size != 0 || entry.blake3.is_some() {
                        return Err(invalid_manifest("directory entry carries file content"));
                    }
                    directory_count = directory_count
                        .checked_add(1)
                        .ok_or_else(|| invalid_manifest("directory entry count overflow"))?;
                }
                DirectoryEntryKind::Symlink => return Err(symlink_refused()),
            }
            kinds.insert(case_key, entry.kind);
        }
        if total_bytes != self.total_bytes
            || file_count != self.file_count
            || directory_count != self.directory_count
        {
            return Err(invalid_manifest(
                "directory manifest counts do not match entries",
            ));
        }
        if total_bytes > MAX_DIRECTORY_TOTAL_BYTES {
            return Err(invalid_manifest("directory exceeds the transfer limit"));
        }
        validate_metadata(&self.root_metadata)?;
        Ok(())
    }

    /// Returns the canonical CBOR manifest digest.
    pub fn digest(&self) -> Result<String, TransferError> {
        self.validate()?;
        let mut encoded = Vec::new();
        ciborium::into_writer(self, &mut encoded)
            .map_err(|_| TransferError::internal("directory manifest encoding failed"))?;
        Ok(blake3_hex(&encoded))
    }

    /// Encodes the manifest as CBOR.
    pub fn to_cbor(&self) -> Result<Vec<u8>, TransferError> {
        self.validate()?;
        let mut encoded = Vec::new();
        ciborium::into_writer(self, &mut encoded)
            .map_err(|_| TransferError::internal("directory manifest encoding failed"))?;
        Ok(encoded)
    }

    /// Decodes and validates a CBOR manifest.
    pub fn from_cbor(bytes: &[u8]) -> Result<Self, TransferError> {
        let manifest: Self = ciborium::from_reader(bytes).map_err(|_| {
            TransferError::new(
                TransferErrorCode::ManifestInvalid,
                "directory manifest decoding failed",
                false,
            )
        })?;
        manifest.validate()?;
        Ok(manifest)
    }

    /// Returns a receiver-visible summary.
    #[must_use]
    pub fn summary(&self) -> DirectoryTransferSummary {
        DirectoryTransferSummary {
            transfer_id: self.transfer_id.clone(),
            sender_device_id: self.sender_device_id.clone(),
            root_name: self.root_name.clone(),
            entry_count: self.entries.len(),
            file_count: self.file_count,
            directory_count: self.directory_count,
            total_bytes: self.total_bytes,
            expires_at_ms: self.expires_at_ms,
        }
    }
}

/// Receiver-visible directory summary.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryTransferSummary {
    /// Transfer identifier.
    pub transfer_id: String,
    /// Sending device identifier.
    pub sender_device_id: String,
    /// Root folder name.
    pub root_name: String,
    /// Total manifest entry count.
    pub entry_count: usize,
    /// File entry count.
    pub file_count: u32,
    /// Directory entry count.
    pub directory_count: u32,
    /// Total file bytes.
    pub total_bytes: u64,
    /// Offer expiration time in Unix milliseconds.
    pub expires_at_ms: i64,
}

/// Sender offer for one directory snapshot.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryTransferOffer {
    /// Transfer protocol version.
    pub protocol_version: u16,
    /// Unique offer identifier.
    pub offer_id: String,
    /// Directory manifest.
    pub manifest: DirectoryManifest,
    /// Canonical manifest digest.
    pub manifest_hash: String,
}

impl DirectoryTransferOffer {
    /// Creates an offer from a validated manifest.
    pub fn new(manifest: DirectoryManifest) -> Result<Self, TransferError> {
        manifest.validate()?;
        let manifest_hash = manifest.digest()?;
        Ok(Self {
            protocol_version: TRANSFER_PROTOCOL_VERSION,
            offer_id: random_hex(16)?,
            manifest,
            manifest_hash,
        })
    }

    /// Validates the offer and its manifest digest.
    pub fn validate(&self) -> Result<(), TransferError> {
        if self.protocol_version != TRANSFER_PROTOCOL_VERSION {
            return Err(TransferError::new(
                TransferErrorCode::ProtocolVersionUnsupported,
                "directory transfer protocol version is unsupported",
                false,
            ));
        }
        validate_identifier("offer id", &self.offer_id)?;
        self.manifest.validate()?;
        if self.manifest.digest()? != self.manifest_hash {
            return Err(invalid_manifest(
                "directory manifest digest does not match the offer",
            ));
        }
        Ok(())
    }

    /// Returns the receiver-visible summary.
    #[must_use]
    pub fn summary(&self) -> DirectoryTransferSummary {
        self.manifest.summary()
    }

    /// Rejects an expired offer.
    pub fn ensure_live(&self, now_ms: i64) -> Result<(), TransferError> {
        if now_ms > self.manifest.expires_at_ms {
            return Err(TransferError::new(
                TransferErrorCode::TransferOfferExpired,
                "directory transfer offer has expired",
                false,
            ));
        }
        Ok(())
    }
}

fn scan_directory<F: FileStore>(
    files: &F,
    directory: &Path,
    prefix: &str,
    entries: &mut Vec<DirectoryEntry>,
) -> Result<(), TransferError> {
    let names = files
        .directory_entries(directory)
        .map_err(TransferError::from_platform)?;
    for name in names {
        validate_component(&name)?;
        let relative_path = if prefix.is_empty() {
            name.clone()
        } else {
            format!("{prefix}/{name}")
        };
        let source_path = directory.join(&name);
        let metadata = files
            .metadata(&source_path)
            .map_err(TransferError::from_platform)?
            .ok_or_else(source_changed)?;
        let entry_metadata = metadata_from_platform(&metadata);
        match metadata.kind {
            FileEntryKind::File => {
                let (size, digest) = digest_file(files, &source_path, &metadata)?;
                entries.push(DirectoryEntry::file(
                    relative_path,
                    size,
                    digest,
                    entry_metadata,
                ));
            }
            FileEntryKind::Directory => {
                entries.push(DirectoryEntry::directory(
                    relative_path.clone(),
                    entry_metadata,
                ));
                scan_directory(files, &source_path, &relative_path, entries)?;
            }
            FileEntryKind::Symlink => return Err(symlink_refused()),
            FileEntryKind::Other => {
                return Err(TransferError::new(
                    TransferErrorCode::UnsupportedEntryKind,
                    "source contains an unsupported filesystem entry",
                    false,
                ));
            }
        }
        if entries.len() > MAX_DIRECTORY_ENTRIES {
            return Err(invalid_manifest("directory manifest has too many entries"));
        }
    }
    Ok(())
}

fn digest_file<F: FileStore>(
    files: &F,
    path: &Path,
    before: &FileEntryMetadata,
) -> Result<(u64, String), TransferError> {
    if before.size > MAX_TRANSFER_BYTES {
        return Err(invalid_manifest("source file exceeds the transfer limit"));
    }
    let mut hasher = blake3::Hasher::new();
    let mut offset = 0_u64;
    while offset < before.size {
        let length = usize::try_from((before.size - offset).min(u64::from(TRANSFER_CHUNK_SIZE)))
            .map_err(|_| TransferError::internal("directory chunk length overflow"))?;
        let bytes = files
            .read_range(path, offset, length)
            .map_err(TransferError::from_platform)?
            .ok_or_else(source_changed)?;
        if bytes.len() != length {
            return Err(source_changed());
        }
        hasher.update(&bytes);
        offset = offset
            .checked_add(length as u64)
            .ok_or_else(|| TransferError::internal("directory source offset overflow"))?;
    }
    let after = files
        .metadata(path)
        .map_err(TransferError::from_platform)?
        .ok_or_else(source_changed)?;
    if after.kind != FileEntryKind::File
        || after.size != before.size
        || after.modified_at_ms != before.modified_at_ms
    {
        return Err(source_changed());
    }
    Ok((before.size, hasher.finalize().to_hex().to_string()))
}

fn metadata_from_platform(metadata: &FileEntryMetadata) -> DirectoryMetadata {
    DirectoryMetadata {
        modified_at_ms: metadata.modified_at_ms.unwrap_or_default().max(0),
        readonly: metadata.readonly,
        executable: metadata.executable,
    }
}

fn validate_metadata(metadata: &DirectoryMetadata) -> Result<(), TransferError> {
    if metadata.modified_at_ms < 0 {
        return Err(invalid_manifest("entry modification time is invalid"));
    }
    Ok(())
}

fn source_missing() -> TransferError {
    TransferError::new(
        TransferErrorCode::SourceChanged,
        "directory source is missing",
        true,
    )
}

fn source_changed() -> TransferError {
    TransferError::new(
        TransferErrorCode::SourceChanged,
        "directory source changed during manifest creation",
        true,
    )
}

fn symlink_refused() -> TransferError {
    TransferError::new(
        TransferErrorCode::SymlinkRefused,
        "symbolic links are not supported",
        false,
    )
}

fn invalid_manifest(message: &'static str) -> TransferError {
    TransferError::new(TransferErrorCode::ManifestInvalid, message, false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::file_transfer::TRANSFER_OFFER_TTL_MS;

    fn metadata() -> DirectoryMetadata {
        DirectoryMetadata {
            modified_at_ms: 1_800_000_000_000,
            readonly: false,
            executable: false,
        }
    }

    fn valid_manifest() -> DirectoryManifest {
        DirectoryManifest::from_entries(
            "tr-directory-1",
            "device-sender",
            "photos",
            metadata(),
            vec![
                DirectoryEntry::directory("empty", metadata()),
                DirectoryEntry::directory("nested", metadata()),
                DirectoryEntry::file("nested/photo.jpg", 3, blake3_hex(b"abc"), metadata()),
            ],
            10,
            1_000,
        )
        .expect("manifest")
    }

    #[test]
    fn manifest_round_trip_preserves_empty_directories_and_metadata() {
        let manifest = valid_manifest();
        assert_eq!(manifest.file_count, 1);
        assert_eq!(manifest.directory_count, 2);
        assert_eq!(manifest.total_bytes, 3);
        let encoded = manifest.to_cbor().expect("encode");
        assert_eq!(
            DirectoryManifest::from_cbor(&encoded).expect("decode"),
            manifest
        );
        assert_eq!(
            DirectoryTransferOffer::new(manifest)
                .expect("offer")
                .summary()
                .directory_count,
            2
        );
    }

    #[test]
    fn manifest_rejects_missing_parent_duplicate_and_case_collision() {
        let missing_parent =
            DirectoryEntry::file("missing/file.txt", 0, blake3_hex(b""), metadata());
        assert_eq!(
            DirectoryManifest::from_entries(
                "tr-directory-2",
                "device-sender",
                "root",
                metadata(),
                vec![missing_parent],
                10,
                20,
            )
            .expect_err("missing parent")
            .code(),
            TransferErrorCode::ManifestInvalid
        );

        let files = vec![
            DirectoryEntry::file("Readme.txt", 0, blake3_hex(b""), metadata()),
            DirectoryEntry::file("readme.TXT", 0, blake3_hex(b""), metadata()),
        ];
        assert_eq!(
            DirectoryManifest::from_entries(
                "tr-directory-3",
                "device-sender",
                "root",
                metadata(),
                files,
                10,
                20,
            )
            .expect_err("case collision")
            .code(),
            TransferErrorCode::PathCollision
        );
    }

    #[test]
    fn manifest_rejects_symlink_and_corrupt_cbor() {
        let manifest = valid_manifest();
        let mut encoded = manifest.to_cbor().expect("encode");
        encoded.truncate(encoded.len() / 2);
        assert_eq!(
            DirectoryManifest::from_cbor(&encoded)
                .expect_err("corrupt manifest")
                .code(),
            TransferErrorCode::ManifestInvalid
        );

        let symlink = DirectoryEntry {
            relative_path: "link".to_owned(),
            kind: DirectoryEntryKind::Symlink,
            size: 0,
            blake3: None,
            metadata: metadata(),
        };
        assert_eq!(
            DirectoryManifest::from_entries(
                "tr-directory-4",
                "device-sender",
                "root",
                metadata(),
                vec![symlink],
                10,
                20,
            )
            .expect_err("symlink")
            .code(),
            TransferErrorCode::SymlinkRefused
        );
    }

    #[test]
    fn default_offer_ttl_is_usable() {
        let manifest = DirectoryManifest::from_entries(
            "tr-directory-5",
            "device-sender",
            "root",
            metadata(),
            Vec::new(),
            10,
            10 + TRANSFER_OFFER_TTL_MS,
        )
        .expect("manifest");
        assert!(DirectoryTransferOffer::new(manifest).is_ok());
    }
}

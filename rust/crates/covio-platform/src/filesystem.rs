//! Standard filesystem implementation of the bounded file capability.

use crate::{FileStore, PlatformError};
use atomic_write_file::AtomicWriteFile;
use std::fs::{self, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

/// Native standard-filesystem adapter.
#[derive(Debug, Clone, Copy, Default)]
pub struct StdFileStore;

impl StdFileStore {
    /// Creates a standard filesystem adapter.
    #[must_use]
    pub const fn new() -> Self {
        Self
    }
}

impl FileStore for StdFileStore {
    fn read(&self, path: &Path) -> Result<Option<Vec<u8>>, PlatformError> {
        match fs::read(path) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(_) => Err(io_error()),
        }
    }

    fn exists(&self, path: &Path) -> Result<bool, PlatformError> {
        match fs::metadata(path) {
            Ok(_) => Ok(true),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
            Err(_) => Err(io_error()),
        }
    }

    fn metadata_size(&self, path: &Path) -> Result<Option<u64>, PlatformError> {
        match fs::metadata(path) {
            Ok(metadata) => Ok(Some(metadata.len())),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(_) => Err(io_error()),
        }
    }

    fn read_range(
        &self,
        path: &Path,
        offset: u64,
        length: usize,
    ) -> Result<Option<Vec<u8>>, PlatformError> {
        let mut file = match fs::File::open(path) {
            Ok(file) => file,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(_) => return Err(io_error()),
        };
        file.seek(SeekFrom::Start(offset)).map_err(|_| io_error())?;
        let mut bytes = vec![0; length];
        let mut received = 0;
        while received < length {
            let count = file.read(&mut bytes[received..]).map_err(|_| io_error())?;
            if count == 0 {
                break;
            }
            received += count;
        }
        bytes.truncate(received);
        Ok(Some(bytes))
    }

    fn create_dir_all(&self, path: &Path) -> Result<(), PlatformError> {
        fs::create_dir_all(path).map_err(|_| io_error())
    }

    fn write_atomic(&self, path: &Path, contents: &[u8]) -> Result<(), PlatformError> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|_| io_error())?;
        }
        let mut file = AtomicWriteFile::options()
            .open(path)
            .map_err(|_| io_error())?;
        file.write_all(contents).map_err(|_| io_error())?;
        file.commit().map_err(|_| io_error())
    }

    fn append(&self, path: &Path, contents: &[u8]) -> Result<u64, PlatformError> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|_| io_error())?;
        }
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .map_err(|_| io_error())?;
        file.write_all(contents).map_err(|_| io_error())?;
        file.sync_all().map_err(|_| io_error())?;
        Ok(file.metadata().map_err(|_| io_error())?.len())
    }

    fn atomic_move(&self, source: &Path, target: &Path) -> Result<(), PlatformError> {
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent).map_err(|_| io_error())?;
        }
        fs::rename(source, target).map_err(|_| io_error())
    }

    fn remove_file(&self, path: &Path) -> Result<bool, PlatformError> {
        match fs::remove_file(path) {
            Ok(()) => Ok(true),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
            Err(_) => Err(io_error()),
        }
    }

    fn remove_tree(&self, path: &Path) -> Result<(), PlatformError> {
        match fs::remove_dir_all(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(_) => Err(io_error()),
        }
    }
}

fn io_error() -> PlatformError {
    PlatformError::io("filesystem operation failed", true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static NEXT_TEMPORARY_DIRECTORY: AtomicU64 = AtomicU64::new(0);

    fn temporary_directory() -> std::path::PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let sequence = NEXT_TEMPORARY_DIRECTORY.fetch_add(1, Ordering::Relaxed);
        std::env::temp_dir().join(format!(
            "covio-std-files-{}-{nonce}-{sequence}",
            std::process::id()
        ))
    }

    #[test]
    fn read_write_range_append_and_remove_round_trip() {
        let root = temporary_directory();
        let store = StdFileStore::new();
        let file = root.join("state.json");
        store.create_dir_all(&root).expect("directory");
        assert_eq!(store.read(&file).expect("read missing"), None);
        store.write_atomic(&file, b"abcdef").expect("write");
        assert_eq!(store.read(&file).expect("read"), Some(b"abcdef".to_vec()));
        store.write_atomic(&file, b"replacement").expect("replace");
        assert_eq!(
            store.read(&file).expect("read replaced"),
            Some(b"replacement".to_vec())
        );
        assert_eq!(store.metadata_size(&file).expect("size"), Some(11));
        assert_eq!(
            store.read_range(&file, 2, 3).expect("range"),
            Some(b"pla".to_vec())
        );
        assert_eq!(store.append(&file, b"g").expect("append"), 12);
        let target = root.join("moved.json");
        store.atomic_move(&file, &target).expect("move");
        assert!(!store.exists(&file).expect("source missing"));
        assert!(store.remove_file(&target).expect("remove"));
        assert!(!store.remove_file(&target).expect("remove missing"));
        store.remove_tree(&root).expect("remove tree");
    }

    #[test]
    fn write_creates_parent_and_leaves_no_temporary_file() {
        let root = temporary_directory();
        let store = StdFileStore::new();
        let file = root.join("nested/state.json");
        store.write_atomic(&file, b"value").expect("write");
        assert_eq!(store.read(&file).expect("read"), Some(b"value".to_vec()));
        assert!(
            !store
                .exists(&crate::temporary_path(&file))
                .expect("temporary check")
        );
        store.remove_tree(&root).expect("cleanup");
    }
}

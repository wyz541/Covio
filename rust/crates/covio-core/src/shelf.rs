//! Screenshot shelf models, normalization, and durable storage.

use crate::CoreError;
use crate::path_policy::canonical_path;
use covio_platform::{FileStore, temporary_path};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

/// Maximum screenshot entries retained by the shelf.
pub const MAX_SHELF_ITEMS: usize = 12;

/// One indexed screenshot path.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ShelfItem {
    /// Original screenshot path.
    pub path: String,
    /// Unix timestamp when the item entered the shelf.
    pub added_at_epoch_seconds: i64,
}

impl ShelfItem {
    /// Returns a normalized copy.
    #[must_use]
    pub fn normalized(&self) -> Self {
        Self {
            path: self.path.trim().to_owned(),
            added_at_epoch_seconds: self.added_at_epoch_seconds.max(0),
        }
    }
}

/// Screenshot preference snapshot retained for legacy restoration.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ScreenshotInboxSnapshot {
    /// Legacy screenshot location setting.
    pub location: Option<String>,
    /// Legacy location-screenshot setting.
    pub location_screenshot: Option<String>,
    /// Legacy show-thumbnail setting.
    pub show_thumbnail: Option<bool>,
}

/// Persisted shelf state.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ShelfStoreState {
    /// Screenshot entries.
    pub items: Vec<ShelfItem>,
    /// Whether the shelf is revealed.
    pub revealed: bool,
    /// Legacy screenshot preference snapshot.
    pub preference_snapshot: Option<ScreenshotInboxSnapshot>,
}

impl Default for ShelfStoreState {
    fn default() -> Self {
        Self {
            items: Vec::new(),
            revealed: true,
            preference_snapshot: None,
        }
    }
}

/// Shelf repository backed by a filesystem capability.
#[derive(Debug, Clone)]
pub struct ShelfStore<F> {
    path: PathBuf,
    files: F,
}

impl<F: FileStore> ShelfStore<F> {
    /// Creates a shelf store for one path.
    #[must_use]
    pub fn new(path: impl Into<PathBuf>, files: F) -> Self {
        Self {
            path: path.into(),
            files,
        }
    }

    /// Returns the shelf file path.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Loads and normalizes shelf state without failing the product path.
    #[must_use]
    pub fn load(&self) -> ShelfStoreState {
        let Some(bytes) = self.files.read(&self.path).ok().flatten() else {
            return ShelfStoreState::default();
        };
        let Ok(state) = serde_json::from_slice::<ShelfStoreState>(&bytes) else {
            return ShelfStoreState::default();
        };
        self.normalize(state)
    }

    /// Saves normalized shelf state.
    pub fn save(&self, state: &ShelfStoreState) -> Result<ShelfStoreState, CoreError> {
        let normalized = self.normalize(state.clone());
        if let Some(parent) = self.path.parent() {
            self.files.create_dir_all(parent).map_err(CoreError::from)?;
        }
        let bytes = serde_json::to_vec_pretty(&normalized).map_err(|_| {
            CoreError::new(crate::CoreErrorCode::Internal, "shelf serialization failed")
        })?;
        self.files
            .write_atomic(&self.path, &bytes)
            .map_err(CoreError::from)?;
        Ok(normalized)
    }

    /// Removes the shelf file and its compatibility temporary file.
    pub fn clear(&self) -> Result<bool, CoreError> {
        let target = self.files.remove_file(&self.path);
        let temporary = self.files.remove_file(&temporary_path(&self.path));
        match (target, temporary) {
            (Ok(target), Ok(temporary)) => Ok(target || temporary),
            (Err(error), _) | (_, Err(error)) => Err(error.into()),
        }
    }

    fn normalize(&self, mut state: ShelfStoreState) -> ShelfStoreState {
        state.items = normalize_items(state.items, MAX_SHELF_ITEMS, |path| {
            self.files.exists(Path::new(path)).unwrap_or(false)
        });
        state
    }
}

/// Normalizes shelf items with the existing order, dedupe, existence, and limit rules.
#[must_use]
pub fn normalize_items(
    items: Vec<ShelfItem>,
    limit: usize,
    mut exists: impl FnMut(&str) -> bool,
) -> Vec<ShelfItem> {
    let mut seen = HashSet::new();
    let mut kept = Vec::with_capacity(items.len());
    for item in items.into_iter().map(|item| item.normalized()) {
        if item.path.is_empty() || !seen.insert(canonical_path(&item.path)) {
            continue;
        }
        if !exists(&item.path) {
            continue;
        }
        kept.push(item);
    }
    if kept.len() > limit {
        kept.split_off(kept.len() - limit)
    } else {
        kept
    }
}

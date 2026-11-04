//! Clipboard models, retention rules, paste stack, and durable storage.

use crate::CoreError;
use crate::path_policy::canonical_path;
use covio_platform::{FileStore, temporary_path};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

const SECONDS_PER_DAY: i64 = 24 * 60 * 60;

/// Clipboard entry kind.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ClipKind {
    /// Plain text.
    #[default]
    Text,
    /// HTTP or HTTPS link.
    Link,
    /// Image stored as a file.
    Image,
    /// CSS color value.
    Color,
    /// File list stored as files.
    Files,
}

/// One clipboard history item.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ClipItem {
    /// Stable item id.
    pub id: String,
    /// Content kind.
    pub kind: ClipKind,
    /// Text value or newline-separated file paths.
    pub text: String,
    /// First file path for image or file items.
    pub file_path: String,
    /// Content size in bytes.
    pub byte_size: i64,
    /// Creation timestamp in Unix seconds.
    pub created_at_epoch_seconds: i64,
    /// Whether the item is pinned.
    pub pinned: bool,
    /// Source bundle identifier.
    pub source_bundle_id: String,
}

impl ClipItem {
    /// Returns a normalized copy.
    #[must_use]
    pub fn normalized(&self) -> Self {
        Self {
            id: self.id.trim().to_owned(),
            kind: self.kind,
            text: self.text.clone(),
            file_path: self.file_path.trim().to_owned(),
            byte_size: self.byte_size.max(0),
            created_at_epoch_seconds: self.created_at_epoch_seconds.max(0),
            pinned: self.pinned,
            source_bundle_id: self.source_bundle_id.clone(),
        }
    }

    /// Returns the identity used for duplicate removal.
    #[must_use]
    pub fn identity(&self) -> String {
        match self.kind {
            ClipKind::Image | ClipKind::Files => format!("f:{}", canonical_path(&self.file_path)),
            ClipKind::Text | ClipKind::Link | ClipKind::Color => {
                format!("t:{}", self.text.trim())
            }
        }
    }

    /// Returns whether the item contains usable content.
    #[must_use]
    pub fn is_usable(&self) -> bool {
        !self.text.trim().is_empty() || !self.file_path.trim().is_empty()
    }
}

/// Clipboard retention policy.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ClipPolicy {
    /// Maximum number of unpinned items.
    pub max_items: i32,
    /// Maximum age in days. Zero means no age limit.
    pub max_age_days: i32,
    /// Maximum total unpinned bytes.
    pub max_total_bytes: i64,
}

impl Default for ClipPolicy {
    fn default() -> Self {
        Self {
            max_items: 100,
            max_age_days: 7,
            max_total_bytes: 200 * 1024 * 1024,
        }
    }
}

impl ClipPolicy {
    /// Returns a normalized copy.
    #[must_use]
    pub fn normalized(&self) -> Self {
        Self {
            max_items: self.max_items.clamp(1, 1_000),
            max_age_days: self.max_age_days.clamp(0, 3_650),
            max_total_bytes: self.max_total_bytes.max(0),
        }
    }
}

/// Persisted clipboard state.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ClipboardState {
    /// Clipboard entries.
    pub items: Vec<ClipItem>,
    /// Ordered item ids for the paste stack.
    pub paste_stack: Vec<String>,
    /// Whether recording is paused.
    pub paused: bool,
    /// Retention policy.
    pub policy: ClipPolicy,
}

/// Clipboard repository backed by a filesystem capability.
#[derive(Debug, Clone)]
pub struct ClipboardStore<F> {
    path: PathBuf,
    files: F,
}

impl<F: FileStore> ClipboardStore<F> {
    /// Creates a clipboard store for one path.
    #[must_use]
    pub fn new(path: impl Into<PathBuf>, files: F) -> Self {
        Self {
            path: path.into(),
            files,
        }
    }

    /// Returns the clipboard file path.
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Loads clipboard state. Missing or invalid data returns defaults.
    #[must_use]
    pub fn load(&self) -> ClipboardState {
        self.files
            .read(&self.path)
            .ok()
            .flatten()
            .and_then(|bytes| serde_json::from_slice::<ClipboardState>(&bytes).ok())
            .unwrap_or_default()
    }

    /// Saves clipboard state.
    pub fn save(&self, state: &ClipboardState) -> Result<ClipboardState, CoreError> {
        if let Some(parent) = self.path.parent() {
            self.files.create_dir_all(parent).map_err(CoreError::from)?;
        }
        let bytes = serde_json::to_vec_pretty(state).map_err(|_| {
            CoreError::new(
                crate::CoreErrorCode::Internal,
                "clipboard serialization failed",
            )
        })?;
        self.files
            .write_atomic(&self.path, &bytes)
            .map_err(CoreError::from)?;
        Ok(state.clone())
    }

    /// Removes the clipboard file and its compatibility temporary file.
    pub fn clear(&self) -> Result<bool, CoreError> {
        let target = self.files.remove_file(&self.path);
        let temporary = self.files.remove_file(&temporary_path(&self.path));
        match (target, temporary) {
            (Ok(target), Ok(temporary)) => Ok(target || temporary),
            (Err(error), _) | (_, Err(error)) => Err(error.into()),
        }
    }
}

/// Classifies text by whole-value shape.
#[must_use]
pub fn classify(text: &str) -> ClipKind {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return ClipKind::Text;
    }
    if is_link(trimmed) {
        return ClipKind::Link;
    }
    if is_color(trimmed) {
        return ClipKind::Color;
    }
    ClipKind::Text
}

fn is_link(value: &str) -> bool {
    starts_with_ignore_ascii_case(value, "https://")
        .then(|| &value["https://".len()..])
        .or_else(|| {
            starts_with_ignore_ascii_case(value, "http://").then(|| &value["http://".len()..])
        })
        .is_some_and(|rest| !rest.is_empty() && !rest.chars().any(char::is_whitespace))
}

fn is_color(value: &str) -> bool {
    if let Some(hex) = value.strip_prefix('#') {
        return matches!(hex.len(), 3 | 4 | 6 | 8)
            && hex.bytes().all(|byte| byte.is_ascii_hexdigit());
    }
    ["rgb(", "rgba(", "hsl(", "hsla("]
        .iter()
        .any(|prefix| function_value(value, prefix))
}

fn function_value(value: &str, prefix: &str) -> bool {
    starts_with_ignore_ascii_case(value, prefix)
        && value.ends_with(')')
        && !value[prefix.len()..value.len() - 1].contains(')')
}

fn starts_with_ignore_ascii_case(value: &str, prefix: &str) -> bool {
    value
        .get(..prefix.len())
        .is_some_and(|candidate| candidate.eq_ignore_ascii_case(prefix))
}

/// Prunes clipboard items with the existing dedupe, age, count, and byte rules.
#[must_use]
pub fn prune(
    items: &[ClipItem],
    policy: &ClipPolicy,
    now_epoch_seconds: i64,
    mut exists: impl FnMut(&str) -> bool,
) -> Vec<ClipItem> {
    let rules = policy.normalized();
    let oldest_kept = if rules.max_age_days <= 0 {
        i64::MIN
    } else {
        now_epoch_seconds.saturating_sub(i64::from(rules.max_age_days) * SECONDS_PER_DAY)
    };
    let mut sorted = items.to_vec();
    sorted.sort_by(|left, right| {
        right
            .created_at_epoch_seconds
            .cmp(&left.created_at_epoch_seconds)
    });

    let mut seen = HashSet::new();
    let mut kept = Vec::new();
    for candidate in sorted.into_iter().map(|item| item.normalized()) {
        if !candidate.is_usable() || !seen.insert(candidate.identity()) {
            continue;
        }
        if !candidate.pinned && candidate.created_at_epoch_seconds < oldest_kept {
            continue;
        }
        if !has_content(&candidate, &mut exists) {
            continue;
        }
        kept.push(candidate);
    }

    let mut result = Vec::new();
    let mut total_bytes = 0_i64;
    let mut unpinned_count = 0_i32;
    for item in kept {
        if item.pinned {
            result.push(item);
            continue;
        }
        if unpinned_count >= rules.max_items {
            continue;
        }
        let Some(next_total) = total_bytes.checked_add(item.byte_size) else {
            continue;
        };
        if next_total > rules.max_total_bytes {
            continue;
        }
        total_bytes = next_total;
        unpinned_count += 1;
        result.push(item);
    }
    result
}

fn has_content(item: &ClipItem, exists: &mut impl FnMut(&str) -> bool) -> bool {
    match item.kind {
        ClipKind::Image | ClipKind::Files => {
            !item.file_path.trim().is_empty() && exists(&item.file_path)
        }
        ClipKind::Text | ClipKind::Link | ClipKind::Color => !item.text.trim().is_empty(),
    }
}

/// Removes the first live paste-stack item and returns it.
#[must_use]
pub fn next_paste(state: &ClipboardState) -> (ClipboardState, Option<ClipItem>) {
    let by_id: HashMap<&str, &ClipItem> = state
        .items
        .iter()
        .map(|item| (item.id.as_str(), item))
        .collect();
    let mut remaining = state.paste_stack.clone();
    while !remaining.is_empty() {
        let id = remaining.remove(0);
        if let Some(item) = by_id.get(id.as_str()) {
            let mut next = state.clone();
            next.paste_stack = remaining;
            return (next, Some((*item).clone()));
        }
    }
    let mut next = state.clone();
    next.paste_stack.clear();
    (next, None)
}

/// Pushes one id onto the paste stack, moving an existing id to the end.
#[must_use]
pub fn push_paste_stack(stack: &[String], id: &str) -> Vec<String> {
    let mut result: Vec<String> = stack
        .iter()
        .filter(|value| value.as_str() != id)
        .cloned()
        .collect();
    result.push(id.to_owned());
    result
}

/// Returns the files behind one clipboard item.
#[must_use]
pub fn import_paths(item: &ClipItem) -> Vec<String> {
    match item.kind {
        ClipKind::Image => {
            let path = item.file_path.trim();
            if path.is_empty() {
                Vec::new()
            } else {
                vec![path.to_owned()]
            }
        }
        ClipKind::Files => {
            let mut seen = HashSet::new();
            item.text
                .split('\n')
                .chain(std::iter::once(item.file_path.as_str()))
                .map(str::trim)
                .filter(|path| !path.is_empty())
                .filter(|path| seen.insert((*path).to_owned()))
                .map(str::to_owned)
                .collect()
        }
        ClipKind::Text | ClipKind::Link | ClipKind::Color => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(id: &str, value: &str, at: i64, pinned: bool) -> ClipItem {
        ClipItem {
            id: id.to_owned(),
            text: value.to_owned(),
            created_at_epoch_seconds: at,
            pinned,
            ..ClipItem::default()
        }
    }

    #[test]
    fn classification_uses_whole_values() {
        assert_eq!(classify("https://example.com/a?b=1"), ClipKind::Link);
        assert_eq!(classify("  HTTP://example.com  "), ClipKind::Link);
        assert_eq!(classify("#ff8800"), ClipKind::Color);
        assert_eq!(classify("#abc"), ClipKind::Color);
        assert_eq!(classify("rgba(1, 2, 3, 0.5)"), ClipKind::Color);
        assert_eq!(classify("看这个 https://example.com"), ClipKind::Text);
        assert_eq!(classify("#不 是颜色"), ClipKind::Text);
        assert_eq!(classify("   "), ClipKind::Text);
    }

    #[test]
    fn prune_keeps_newest_duplicate_and_respects_age() {
        let now = 10 * SECONDS_PER_DAY;
        let stale = now - 8 * SECONDS_PER_DAY;
        let items = vec![
            text("old", "same", now - 2, false),
            text("new", "same", now - 1, false),
            text("stale", "old", stale, false),
            text("pinned", "keep", stale, true),
        ];
        let kept = prune(&items, &ClipPolicy::default(), now, |_| true);
        assert_eq!(
            kept.into_iter().map(|item| item.id).collect::<Vec<_>>(),
            vec!["new", "pinned"]
        );
    }

    #[test]
    fn prune_counts_only_unpinned_items_and_bytes() {
        let mut items = (0..5)
            .map(|index| text(&format!("i{index}"), &format!("t{index}"), index, false))
            .collect::<Vec<_>>();
        items.push(text("pin", "p", 0, true));
        let policy = ClipPolicy {
            max_items: 2,
            ..ClipPolicy::default()
        };
        let kept = prune(&items, &policy, 100, |_| true);
        let ids = kept.into_iter().map(|item| item.id).collect::<HashSet<_>>();
        assert_eq!(
            ids,
            HashSet::from(["pin".to_owned(), "i4".to_owned(), "i3".to_owned()])
        );
    }

    #[test]
    fn prune_drops_missing_files_and_empty_items() {
        let items = vec![
            ClipItem {
                id: "gone".to_owned(),
                kind: ClipKind::Image,
                file_path: "/tmp/gone.png".to_owned(),
                ..ClipItem::default()
            },
            ClipItem {
                id: "here".to_owned(),
                kind: ClipKind::Image,
                file_path: "/tmp/here.png".to_owned(),
                ..ClipItem::default()
            },
            text("empty", "", 0, false),
            text("text", "kept", 0, false),
        ];
        let kept = prune(&items, &ClipPolicy::default(), 10, |path| {
            path.ends_with("here.png")
        });
        let ids = kept.into_iter().map(|item| item.id).collect::<HashSet<_>>();
        assert_eq!(ids, HashSet::from(["here".to_owned(), "text".to_owned()]));
    }

    #[test]
    fn paste_stack_skips_missing_items_and_moves_reused_ids() {
        let state = ClipboardState {
            items: vec![text("live", "x", 0, false)],
            paste_stack: vec!["gone".to_owned(), "live".to_owned()],
            ..ClipboardState::default()
        };
        let (remaining, item) = next_paste(&state);
        assert_eq!(item.map(|item| item.id), Some("live".to_owned()));
        assert!(remaining.paste_stack.is_empty());
        assert_eq!(
            push_paste_stack(&["a".to_owned(), "b".to_owned()], "a"),
            vec!["b".to_owned(), "a".to_owned()]
        );
    }

    #[test]
    fn import_paths_reads_files_and_deduplicates() {
        let image = ClipItem {
            kind: ClipKind::Image,
            file_path: "/tmp/a.png".to_owned(),
            ..ClipItem::default()
        };
        assert_eq!(import_paths(&image), vec!["/tmp/a.png"]);
        let files = ClipItem {
            kind: ClipKind::Files,
            text: "/tmp/a.png\n/tmp/b.png".to_owned(),
            file_path: "/tmp/a.png".to_owned(),
            ..ClipItem::default()
        };
        assert_eq!(import_paths(&files), vec!["/tmp/a.png", "/tmp/b.png"]);
        assert!(import_paths(&text("t", "hello", 0, false)).is_empty());
    }
}

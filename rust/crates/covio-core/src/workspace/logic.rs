//! Pure workspace rules.

use super::models::{
    WorkspaceAdmission, WorkspaceAvailability, WorkspaceEntry, WorkspaceKind, WorkspacePlan,
    WorkspacePolicy, WorkspaceTombstone,
};
use std::collections::{HashMap, HashSet};

const SECONDS_PER_DAY: i64 = 24 * 60 * 60;
const TEXT_NAME_MAX_CHARS: usize = 40;
const FALLBACK_TEXT_NAME: &str = "clipboard.txt";

/// Tombstone retention in days.
pub const TOMBSTONE_RETENTION_DAYS: i32 = 30;

/// Returns whether a string is a lowercase SHA-256 content id.
#[must_use]
pub fn is_valid_entry_id(value: &str) -> bool {
    let normalized = super::models::normalize_entry_id(value);
    normalized.len() == 64
        && normalized
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}

/// Returns live tombstones in original order, one per entry id.
#[must_use]
pub fn live_tombstones(
    tombstones: &[WorkspaceTombstone],
    now_epoch_seconds: i64,
) -> Vec<WorkspaceTombstone> {
    let cutoff = now_epoch_seconds
        .max(0)
        .saturating_sub(i64::from(TOMBSTONE_RETENTION_DAYS) * SECONDS_PER_DAY);
    let mut seen = HashSet::new();
    tombstones
        .iter()
        .map(WorkspaceTombstone::normalized)
        .filter(|tombstone| {
            is_valid_entry_id(&tombstone.entry_id)
                && tombstone.deleted_at_epoch_seconds >= cutoff
                && seen.insert(tombstone.entry_id.clone())
        })
        .collect()
}

/// Returns whether an entry id is tombstoned.
#[must_use]
pub fn is_tombstoned(
    entry_id: &str,
    tombstones: &[WorkspaceTombstone],
    now_epoch_seconds: i64,
) -> bool {
    let id = super::models::normalize_entry_id(entry_id);
    live_tombstones(tombstones, now_epoch_seconds)
        .iter()
        .any(|tombstone| tombstone.entry_id == id)
}

/// Adds or replaces one tombstone.
#[must_use]
pub fn with_tombstone(
    tombstones: &[WorkspaceTombstone],
    entry_id: &str,
    now_epoch_seconds: i64,
) -> Vec<WorkspaceTombstone> {
    let id = super::models::normalize_entry_id(entry_id);
    if !is_valid_entry_id(&id) {
        return tombstones.to_vec();
    }
    let mut result: Vec<_> = tombstones
        .iter()
        .filter(|tombstone| super::models::normalize_entry_id(&tombstone.entry_id) != id)
        .cloned()
        .collect();
    result.push(WorkspaceTombstone {
        entry_id: id,
        deleted_at_epoch_seconds: now_epoch_seconds.max(0),
    });
    result
}

/// Classifies a workspace entry by MIME type and file extension.
#[must_use]
pub fn classify(display_name: &str, content_type: &str) -> WorkspaceKind {
    let mime = content_type.trim().to_ascii_lowercase();
    if mime.starts_with("image/") {
        return WorkspaceKind::Image;
    }
    if mime.starts_with("audio/") {
        return WorkspaceKind::Audio;
    }
    if mime == "application/pdf" {
        return WorkspaceKind::Pdf;
    }
    if mime.starts_with("text/") {
        return WorkspaceKind::Text;
    }
    let extension = display_name
        .trim()
        .rsplit_once('.')
        .map_or("", |(_, extension)| extension)
        .to_ascii_lowercase();
    match extension.as_str() {
        "png" | "jpg" | "jpeg" | "gif" | "heic" | "heif" | "webp" | "tiff" | "tif" | "bmp" => {
            WorkspaceKind::Image
        }
        "mp3" | "m4a" | "aac" | "wav" | "flac" | "ogg" | "opus" | "aiff" => WorkspaceKind::Audio,
        "pdf" => WorkspaceKind::Pdf,
        "txt" | "md" | "csv" | "json" | "log" | "xml" | "yaml" | "yml" | "html" | "css" | "kt"
        | "swift" | "py" | "sh" => WorkspaceKind::Text,
        _ => WorkspaceKind::File,
    }
}

/// Suggests a bounded display name for workspace text.
#[must_use]
pub fn suggested_text_name(text: &str) -> String {
    let first_line = text
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .unwrap_or_default();
    let mut cleaned = String::with_capacity(first_line.len());
    for character in first_line.chars() {
        if is_iso_control(character) {
            continue;
        }
        cleaned.push(match character {
            '/' | '\\' | ':' => ' ',
            _ => character,
        });
    }
    let cleaned = cleaned.split_whitespace().collect::<Vec<_>>().join(" ");
    let cleaned = cleaned
        .chars()
        .take(TEXT_NAME_MAX_CHARS)
        .collect::<String>()
        .trim()
        .trim_end_matches('.')
        .to_owned();
    if cleaned.is_empty() {
        FALLBACK_TEXT_NAME.to_owned()
    } else {
        format!("{cleaned}.txt")
    }
}

const fn is_iso_control(character: char) -> bool {
    matches!(character, '\u{0000}'..='\u{001f}' | '\u{007f}'..='\u{009f}')
}

/// Returns an entry expiration time. Zero means no expiration.
#[must_use]
pub fn expiry_epoch_seconds(created_at_epoch_seconds: i64, policy: &WorkspacePolicy) -> i64 {
    let days = policy.normalized().retention_days;
    if days <= 0 {
        0
    } else {
        created_at_epoch_seconds
            .max(0)
            .saturating_add(i64::from(days) * SECONDS_PER_DAY)
    }
}

/// Decides whether a candidate can enter the workspace.
#[must_use]
pub fn admit(
    candidate: &WorkspaceEntry,
    entries: &[WorkspaceEntry],
    policy: &WorkspacePolicy,
) -> WorkspaceAdmission {
    let rules = policy.normalized();
    let entry = candidate.normalized();
    if !is_valid_entry_id(&entry.entry_id) {
        return WorkspaceAdmission::Invalid;
    }
    if entry.byte_size > rules.max_entry_bytes {
        return WorkspaceAdmission::TooLarge;
    }
    let existing = dedupe(entries);
    if existing.iter().any(|item| item.entry_id == entry.entry_id) {
        return WorkspaceAdmission::Duplicate;
    }
    let used = existing.iter().fold(0_i64, |total, item| {
        total.saturating_add(item.local_bytes())
    });
    if used.saturating_add(entry.local_bytes()) > rules.max_total_bytes {
        return WorkspaceAdmission::QuotaExceeded;
    }
    WorkspaceAdmission::Accepted
}

/// Merges duplicate content ids and drops invalid entries.
#[must_use]
pub fn dedupe(entries: &[WorkspaceEntry]) -> Vec<WorkspaceEntry> {
    let mut merged: Vec<WorkspaceEntry> = Vec::new();
    let mut positions: HashMap<String, usize> = HashMap::new();
    for candidate in entries.iter().map(WorkspaceEntry::normalized) {
        if !is_valid_entry_id(&candidate.entry_id) {
            continue;
        }
        let Some(&position) = positions.get(&candidate.entry_id) else {
            positions.insert(candidate.entry_id.clone(), merged.len());
            merged.push(candidate);
            continue;
        };
        let previous = &merged[position];
        let candidate_pinned = candidate.pinned;
        let (older, newer) =
            if previous.created_at_epoch_seconds <= candidate.created_at_epoch_seconds {
                (previous.clone(), candidate)
            } else {
                (candidate, previous.clone())
            };
        let availability = if previous.availability == WorkspaceAvailability::Local
            || newer.availability == WorkspaceAvailability::Local
            || older.availability == WorkspaceAvailability::Local
        {
            WorkspaceAvailability::Local
        } else {
            older.availability
        };
        let display_name = if older.display_name.is_empty() {
            newer.display_name.clone()
        } else {
            older.display_name.clone()
        };
        merged[position] = WorkspaceEntry {
            display_name,
            pinned: previous.pinned || candidate_pinned,
            availability,
            ..older
        };
    }
    merged
}

/// Returns display order: pinned first, then newest first.
#[must_use]
pub fn display_order(entries: &[WorkspaceEntry]) -> Vec<WorkspaceEntry> {
    let mut ordered = dedupe(entries);
    ordered.sort_by(|left, right| {
        right.pinned.cmp(&left.pinned).then_with(|| {
            right
                .created_at_epoch_seconds
                .cmp(&left.created_at_epoch_seconds)
        })
    });
    ordered
}

/// Applies expiry and quota rules.
#[must_use]
pub fn plan(
    entries: &[WorkspaceEntry],
    policy: &WorkspacePolicy,
    now_epoch_seconds: i64,
) -> WorkspacePlan {
    let rules = policy.normalized();
    let mut expired = Vec::new();
    let mut live = Vec::new();
    for entry in dedupe(entries) {
        if !entry.pinned
            && entry.expires_at_epoch_seconds > 0
            && entry.expires_at_epoch_seconds <= now_epoch_seconds
        {
            expired.push(entry);
        } else {
            live.push(entry);
        }
    }
    live.sort_by(|left, right| {
        right
            .created_at_epoch_seconds
            .cmp(&left.created_at_epoch_seconds)
    });
    let mut kept = Vec::new();
    let mut evicted = Vec::new();
    let mut total_bytes = 0_i64;
    for entry in live {
        if entry.pinned {
            total_bytes = total_bytes.saturating_add(entry.local_bytes());
            kept.push(entry);
            continue;
        }
        if entry.local_bytes() > rules.max_entry_bytes {
            evicted.push(entry);
            continue;
        }
        let next_total = total_bytes.saturating_add(entry.local_bytes());
        if next_total > rules.max_total_bytes {
            evicted.push(entry);
            continue;
        }
        total_bytes = next_total;
        kept.push(entry);
    }
    WorkspacePlan {
        kept,
        expired,
        evicted,
        total_bytes,
    }
}

/// Sums local bytes for normalized entries.
#[must_use]
pub fn total_local_bytes(entries: &[WorkspaceEntry]) -> i64 {
    dedupe(entries).iter().fold(0_i64, |total, entry| {
        total.saturating_add(entry.local_bytes())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn id(byte: char) -> String {
        std::iter::repeat_n(byte, 64).collect()
    }

    fn entry(id: &str, at: i64) -> WorkspaceEntry {
        WorkspaceEntry {
            entry_id: id.to_owned(),
            display_name: "a.txt".to_owned(),
            byte_size: 10,
            created_at_epoch_seconds: at,
            ..WorkspaceEntry::default()
        }
    }

    #[test]
    fn valid_ids_are_lowercase_sha256() {
        assert!(is_valid_entry_id(&id('a')));
        assert!(is_valid_entry_id(&id('A')));
        assert!(!is_valid_entry_id("abc"));
    }

    #[test]
    fn suggested_name_is_bounded_and_safe() {
        assert_eq!(suggested_text_name("  /a:b\\c?  "), "a b c?.txt");
        assert_eq!(suggested_text_name("\n\n"), "clipboard.txt");
        assert!(suggested_text_name(&"x".repeat(100)).len() <= 44);
    }

    #[test]
    fn classify_prefers_mime_then_extension() {
        assert_eq!(classify("photo.bin", "image/png"), WorkspaceKind::Image);
        assert_eq!(classify("book.PDF", ""), WorkspaceKind::Pdf);
        assert_eq!(classify("song.MP3", ""), WorkspaceKind::Audio);
        assert_eq!(classify("notes.md", ""), WorkspaceKind::Text);
        assert_eq!(classify("archive.bin", ""), WorkspaceKind::File);
    }

    #[test]
    fn dedupe_keeps_first_order_and_merges_flags() {
        let a = id('a');
        let b = id('b');
        let entries = vec![
            WorkspaceEntry {
                entry_id: a.clone(),
                display_name: String::new(),
                created_at_epoch_seconds: 2,
                availability: WorkspaceAvailability::Remote,
                ..WorkspaceEntry::default()
            },
            WorkspaceEntry {
                entry_id: b.clone(),
                created_at_epoch_seconds: 1,
                ..WorkspaceEntry::default()
            },
            WorkspaceEntry {
                entry_id: a,
                display_name: "name.txt".to_owned(),
                created_at_epoch_seconds: 1,
                pinned: true,
                ..WorkspaceEntry::default()
            },
        ];
        let merged = dedupe(&entries);
        assert_eq!(merged[0].entry_id, id('a'));
        assert_eq!(merged[0].display_name, "name.txt");
        assert!(merged[0].pinned);
        assert_eq!(merged[1].entry_id, b);
    }

    #[test]
    fn plan_expires_old_items_and_evicts_by_quota() {
        let a = id('a');
        let b = id('b');
        let c = id('c');
        let policy = WorkspacePolicy {
            max_total_bytes: 20,
            max_entry_bytes: 10,
            retention_days: 0,
            ..WorkspacePolicy::default()
        };
        let entries = vec![
            WorkspaceEntry {
                expires_at_epoch_seconds: 5,
                ..entry(&a, 1)
            },
            WorkspaceEntry {
                byte_size: 10,
                ..entry(&b, 1)
            },
            WorkspaceEntry {
                byte_size: 15,
                ..entry(&c, 2)
            },
            WorkspaceEntry {
                byte_size: 10,
                pinned: true,
                ..entry(&id('d'), 3)
            },
        ];
        let plan = plan(&entries, &policy, 10);
        assert_eq!(plan.expired[0].entry_id, a);
        assert_eq!(plan.evicted[0].entry_id, c);
        assert_eq!(plan.kept[0].entry_id, id('d'));
        assert_eq!(plan.kept[1].entry_id, b);
    }
}

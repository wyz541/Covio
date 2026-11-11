//! Destination conflict detection and naming plans.

use super::super::{TransferError, TransferErrorCode};
use super::manifest::{DirectoryEntry, DirectoryEntryKind, DirectoryManifest};
use super::path::{path_collision_key, validate_directory_path};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

/// Policy applied when a destination path already exists.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DirectoryConflictPolicy {
    /// Keep the existing path and assign a numbered name to the incoming entry.
    #[default]
    KeepBoth,
    /// Replace an existing file after validation.
    Replace,
    /// Skip the incoming file.
    Skip,
}

/// Destination entry kind used for conflict detection.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DestinationEntryKind {
    /// A regular file.
    File,
    /// A directory.
    Directory,
}

/// One existing destination entry relative to the transfer root.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DestinationEntry {
    /// Existing relative path.
    pub relative_path: String,
    /// Existing entry kind.
    pub kind: DestinationEntryKind,
}

/// Planned action for one manifest entry.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DirectoryConflictAction {
    /// Create a new file.
    CreateFile,
    /// Create a new directory.
    CreateDirectory,
    /// Merge into an existing directory.
    MergeDirectory,
    /// Create a file with a numbered name.
    KeepBoth,
    /// Replace the existing file after validation.
    Replace,
    /// Do not receive the file.
    Skip,
}

/// Durable completion state for one planned entry.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DirectoryEntryStatus {
    /// The entry has not committed yet.
    #[default]
    Pending,
    /// The file committed to its target path.
    Committed,
    /// The entry was skipped by policy.
    Skipped,
}

/// One planned manifest entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct PlannedDirectoryEntry {
    /// Source manifest entry.
    pub entry: DirectoryEntry,
    /// Final path relative to the transfer root.
    pub target_relative_path: String,
    /// Planned action.
    pub action: DirectoryConflictAction,
    /// Durable completion state.
    #[serde(default)]
    pub status: DirectoryEntryStatus,
}

/// Complete conflict plan for one directory manifest.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DirectoryConflictPlan {
    /// Root folder name.
    pub root_name: String,
    /// Policy used to build this plan.
    pub policy: DirectoryConflictPolicy,
    /// Planned entries in manifest order.
    pub entries: Vec<PlannedDirectoryEntry>,
}

impl DirectoryConflictPlan {
    /// Returns whether any path needs conflict handling.
    #[must_use]
    pub fn has_conflicts(&self) -> bool {
        self.entries.iter().any(|entry| {
            matches!(
                entry.action,
                DirectoryConflictAction::KeepBoth
                    | DirectoryConflictAction::Replace
                    | DirectoryConflictAction::Skip
            )
        })
    }

    /// Returns the skipped entry count.
    #[must_use]
    pub fn skipped_count(&self) -> usize {
        self.entries
            .iter()
            .filter(|entry| entry.action == DirectoryConflictAction::Skip)
            .count()
    }

    /// Returns a planned file entry by source path.
    #[must_use]
    pub fn file_entry(&self, relative_path: &str) -> Option<&PlannedDirectoryEntry> {
        self.entries.iter().find(|entry| {
            entry.entry.kind == DirectoryEntryKind::File
                && entry.entry.relative_path == relative_path
        })
    }
}

/// Builds a deterministic conflict plan from existing destination entries.
pub fn plan_directory_conflicts(
    manifest: &DirectoryManifest,
    existing: &[DestinationEntry],
    policy: DirectoryConflictPolicy,
) -> Result<DirectoryConflictPlan, TransferError> {
    manifest.validate()?;
    let mut exact = HashMap::new();
    let mut folded = HashMap::new();
    for entry in existing {
        validate_directory_path(&entry.relative_path)?;
        let key = path_collision_key(&entry.relative_path);
        if folded.insert(key, entry.kind).is_some() {
            return Err(path_collision());
        }
        exact.insert(entry.relative_path.clone(), entry.kind);
    }

    let mut reserved = folded;
    let manifest_keys = manifest
        .entries
        .iter()
        .map(|entry| path_collision_key(&entry.relative_path))
        .collect::<HashSet<_>>();
    let mut planned = Vec::with_capacity(manifest.entries.len());
    for entry in &manifest.entries {
        let exact_match = exact.get(&entry.relative_path).copied();
        let folded_match = reserved
            .get(&path_collision_key(&entry.relative_path))
            .copied();
        if exact_match.is_none() && folded_match.is_some() {
            return Err(path_collision());
        }
        let (target_relative_path, action) = match (entry.kind, exact_match) {
            (DirectoryEntryKind::Directory, None) => (
                entry.relative_path.clone(),
                DirectoryConflictAction::CreateDirectory,
            ),
            (DirectoryEntryKind::Directory, Some(DestinationEntryKind::Directory)) => (
                entry.relative_path.clone(),
                DirectoryConflictAction::MergeDirectory,
            ),
            (DirectoryEntryKind::Directory, Some(DestinationEntryKind::File))
            | (DirectoryEntryKind::File, Some(DestinationEntryKind::Directory)) => {
                return Err(path_collision());
            }
            (DirectoryEntryKind::File, None) => (
                entry.relative_path.clone(),
                DirectoryConflictAction::CreateFile,
            ),
            (DirectoryEntryKind::File, Some(DestinationEntryKind::File)) => match policy {
                DirectoryConflictPolicy::KeepBoth => {
                    let target =
                        unique_target_path(&entry.relative_path, &reserved, &manifest_keys)?;
                    reserved.insert(path_collision_key(&target), DestinationEntryKind::File);
                    (target, DirectoryConflictAction::KeepBoth)
                }
                DirectoryConflictPolicy::Replace => (
                    entry.relative_path.clone(),
                    DirectoryConflictAction::Replace,
                ),
                DirectoryConflictPolicy::Skip => {
                    (entry.relative_path.clone(), DirectoryConflictAction::Skip)
                }
            },
            (DirectoryEntryKind::Symlink, _) => {
                return Err(TransferError::new(
                    TransferErrorCode::SymlinkRefused,
                    "symbolic links are not supported",
                    false,
                ));
            }
        };
        planned.push(PlannedDirectoryEntry {
            entry: entry.clone(),
            target_relative_path,
            action,
            status: DirectoryEntryStatus::Pending,
        });
    }
    Ok(DirectoryConflictPlan {
        root_name: manifest.root_name.clone(),
        policy,
        entries: planned,
    })
}

fn unique_target_path(
    source_path: &str,
    reserved: &HashMap<String, DestinationEntryKind>,
    manifest_keys: &HashSet<String>,
) -> Result<String, TransferError> {
    let (parent, name) = source_path
        .rsplit_once('/')
        .map_or(("", source_path), |(parent, name)| (parent, name));
    let (stem, extension) = split_extension(name);
    for sequence in 1..=9_999_u32 {
        let candidate_name = if extension.is_empty() {
            format!("{stem} ({sequence})")
        } else {
            format!("{stem} ({sequence}).{extension}")
        };
        let candidate = if parent.is_empty() {
            candidate_name
        } else {
            format!("{parent}/{candidate_name}")
        };
        if validate_directory_path(&candidate).is_ok()
            && !reserved.contains_key(&path_collision_key(&candidate))
            && !manifest_keys.contains(&path_collision_key(&candidate))
        {
            return Ok(candidate);
        }
    }
    Err(path_collision())
}

fn split_extension(name: &str) -> (&str, &str) {
    match name.rsplit_once('.') {
        Some((stem, extension)) if !stem.is_empty() && !extension.is_empty() => (stem, extension),
        _ => (name, ""),
    }
}

fn path_collision() -> TransferError {
    TransferError::new(
        TransferErrorCode::PathCollision,
        "destination path collides with an existing or planned entry",
        false,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::file_transfer::blake3_hex;
    use crate::file_transfer::directory::manifest::DirectoryMetadata;

    fn metadata() -> DirectoryMetadata {
        DirectoryMetadata::default()
    }

    fn manifest() -> DirectoryManifest {
        DirectoryManifest::from_entries(
            "tr-conflict-1",
            "device-sender",
            "root",
            metadata(),
            vec![
                DirectoryEntry::directory("folder", metadata()),
                DirectoryEntry::file("folder/report.txt", 3, blake3_hex(b"new"), metadata()),
                DirectoryEntry::file("other.bin", 3, blake3_hex(b"new"), metadata()),
            ],
            10,
            20,
        )
        .expect("manifest")
    }

    #[test]
    fn keep_both_generates_a_unique_name_and_merges_directories() {
        let plan = plan_directory_conflicts(
            &manifest(),
            &[
                DestinationEntry {
                    relative_path: "folder".to_owned(),
                    kind: DestinationEntryKind::Directory,
                },
                DestinationEntry {
                    relative_path: "folder/report.txt".to_owned(),
                    kind: DestinationEntryKind::File,
                },
            ],
            DirectoryConflictPolicy::KeepBoth,
        )
        .expect("plan");
        assert_eq!(
            plan.entries[0].action,
            DirectoryConflictAction::MergeDirectory
        );
        assert_eq!(
            plan.entries[1].target_relative_path,
            "folder/report (1).txt"
        );
        assert_eq!(plan.entries[1].action, DirectoryConflictAction::KeepBoth);
        assert_eq!(plan.entries[2].action, DirectoryConflictAction::CreateFile);
    }

    #[test]
    fn replace_and_skip_only_apply_to_existing_files() {
        let existing = [DestinationEntry {
            relative_path: "folder/report.txt".to_owned(),
            kind: DestinationEntryKind::File,
        }];
        let replace =
            plan_directory_conflicts(&manifest(), &existing, DirectoryConflictPolicy::Replace)
                .expect("replace plan");
        assert_eq!(replace.entries[1].action, DirectoryConflictAction::Replace);
        let skip = plan_directory_conflicts(&manifest(), &existing, DirectoryConflictPolicy::Skip)
            .expect("skip plan");
        assert_eq!(skip.entries[1].action, DirectoryConflictAction::Skip);
        assert_eq!(skip.skipped_count(), 1);
        assert_eq!(skip.entries[2].action, DirectoryConflictAction::CreateFile);
    }

    #[test]
    fn case_and_kind_collisions_are_rejected() {
        assert_eq!(
            plan_directory_conflicts(
                &manifest(),
                &[DestinationEntry {
                    relative_path: "folder/REPORT.txt".to_owned(),
                    kind: DestinationEntryKind::File,
                }],
                DirectoryConflictPolicy::KeepBoth,
            )
            .expect_err("case collision")
            .code(),
            TransferErrorCode::PathCollision
        );
        assert_eq!(
            plan_directory_conflicts(
                &manifest(),
                &[DestinationEntry {
                    relative_path: "folder/report.txt".to_owned(),
                    kind: DestinationEntryKind::Directory,
                }],
                DirectoryConflictPolicy::KeepBoth,
            )
            .expect_err("kind collision")
            .code(),
            TransferErrorCode::PathCollision
        );
    }

    #[test]
    fn keep_both_preserves_hidden_names_and_skips_all_reserved_numbers() {
        let hidden = DirectoryManifest::from_entries(
            "tr-conflict-2",
            "device-sender",
            "root",
            metadata(),
            vec![DirectoryEntry::file(".env", 0, blake3_hex(b""), metadata())],
            10,
            20,
        )
        .expect("manifest");
        let plan = plan_directory_conflicts(
            &hidden,
            &[
                DestinationEntry {
                    relative_path: ".env".to_owned(),
                    kind: DestinationEntryKind::File,
                },
                DestinationEntry {
                    relative_path: ".env (1)".to_owned(),
                    kind: DestinationEntryKind::File,
                },
            ],
            DirectoryConflictPolicy::KeepBoth,
        )
        .expect("plan");
        assert_eq!(plan.entries[0].target_relative_path, ".env (2)");
    }

    #[test]
    fn keep_both_avoids_other_manifest_paths() {
        let manifest = DirectoryManifest::from_entries(
            "tr-conflict-3",
            "device-sender",
            "root",
            metadata(),
            vec![
                DirectoryEntry::file("report.txt", 3, blake3_hex(b"new"), metadata()),
                DirectoryEntry::file("report (1).txt", 3, blake3_hex(b"new"), metadata()),
            ],
            10,
            20,
        )
        .expect("manifest");
        let plan = plan_directory_conflicts(
            &manifest,
            &[DestinationEntry {
                relative_path: "report.txt".to_owned(),
                kind: DestinationEntryKind::File,
            }],
            DirectoryConflictPolicy::KeepBoth,
        )
        .expect("plan");
        assert_eq!(
            plan.file_entry("report.txt")
                .expect("conflict entry")
                .target_relative_path,
            "report (2).txt"
        );
    }
}

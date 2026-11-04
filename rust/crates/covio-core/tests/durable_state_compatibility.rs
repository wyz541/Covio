use covio_core::clipboard::{
    ClipItem, ClipKind, ClipPolicy, ClipboardState, ClipboardStore, classify, import_paths,
    next_paste, prune, push_paste_stack,
};
use covio_core::path_policy::accepts_shelf_file;
use covio_core::shelf::{ShelfItem, ShelfStore, ShelfStoreState};
use covio_platform::{FileStore, PlatformError};
use serde_json::Value;
use std::cell::RefCell;
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};
use std::rc::Rc;

const SHELF_PATH: &str = "/tmp/covio/shelf.json";
const CLIPBOARD_PATH: &str = "/tmp/covio/clipboard.json";
const SHELF_FIXTURE: &str = include_str!("fixtures/shelf-state.json");
const CLIPBOARD_FIXTURE: &str = include_str!("fixtures/clipboard-state.json");
const SCREENSHOT_TOKEN: &str = "__SCREENSHOT_PATH__";

#[derive(Default)]
struct MemoryInner {
    files: RefCell<BTreeMap<PathBuf, Vec<u8>>>,
    existing: RefCell<BTreeSet<PathBuf>>,
    fail_write: RefCell<bool>,
    atomic_writes: RefCell<Vec<PathBuf>>,
}

#[derive(Clone, Default)]
struct MemoryFiles(Rc<MemoryInner>);

impl MemoryFiles {
    fn with_file(path: &str, contents: &str) -> Self {
        let files = Self::default();
        files
            .0
            .files
            .borrow_mut()
            .insert(PathBuf::from(path), contents.as_bytes().to_vec());
        files.0.existing.borrow_mut().insert(PathBuf::from(path));
        files
    }

    fn add_existing(&self, path: &str) {
        self.0.existing.borrow_mut().insert(PathBuf::from(path));
    }

    fn set_fail_write(&self, fail: bool) {
        *self.0.fail_write.borrow_mut() = fail;
    }

    fn text(&self, path: &str) -> String {
        String::from_utf8(self.0.files.borrow()[&PathBuf::from(path)].clone()).expect("utf-8")
    }

    fn contains(&self, path: &str) -> bool {
        self.0.files.borrow().contains_key(&PathBuf::from(path))
    }
}

impl FileStore for MemoryFiles {
    fn read(&self, path: &Path) -> Result<Option<Vec<u8>>, PlatformError> {
        Ok(self.0.files.borrow().get(path).cloned())
    }

    fn exists(&self, path: &Path) -> Result<bool, PlatformError> {
        Ok(self.0.existing.borrow().contains(path))
    }

    fn create_dir_all(&self, _path: &Path) -> Result<(), PlatformError> {
        Ok(())
    }

    fn write_atomic(&self, path: &Path, contents: &[u8]) -> Result<(), PlatformError> {
        if *self.0.fail_write.borrow() {
            return Err(PlatformError::io("write failed", false));
        }
        self.0.atomic_writes.borrow_mut().push(path.to_path_buf());
        self.0
            .files
            .borrow_mut()
            .insert(path.to_path_buf(), contents.to_vec());
        Ok(())
    }

    fn remove_file(&self, path: &Path) -> Result<bool, PlatformError> {
        let removed = self.0.files.borrow_mut().remove(path).is_some();
        self.0.existing.borrow_mut().remove(path);
        Ok(removed)
    }

    fn remove_tree(&self, path: &Path) -> Result<(), PlatformError> {
        self.0
            .files
            .borrow_mut()
            .retain(|candidate, _| !candidate.starts_with(path));
        self.0
            .existing
            .borrow_mut()
            .retain(|candidate| !candidate.starts_with(path));
        Ok(())
    }
}

fn normalise_shelf_fixture(text: &str, screenshot_path: &str) -> Value {
    serde_json::from_str(&text.replace(SCREENSHOT_TOKEN, screenshot_path)).expect("shelf json")
}

#[test]
fn shelf_fixture_round_trips_and_preserves_legacy_snapshot() {
    let screenshot = "/tmp/covio/screenshot.png";
    let files = MemoryFiles::with_file(
        SHELF_PATH,
        &SHELF_FIXTURE.replace(SCREENSHOT_TOKEN, screenshot),
    );
    files.add_existing(screenshot);
    let store = ShelfStore::new(SHELF_PATH, files.clone());
    let loaded = store.load();
    assert_eq!(loaded.items.len(), 1);
    assert_eq!(loaded.items[0].path, screenshot);
    assert!(!loaded.revealed);
    assert_eq!(
        loaded
            .preference_snapshot
            .as_ref()
            .and_then(|snapshot| snapshot.show_thumbnail),
        Some(true)
    );
    store.save(&loaded).expect("save shelf");

    let actual: Value = serde_json::from_str(&files.text(SHELF_PATH)).expect("saved shelf");
    assert_eq!(actual, normalise_shelf_fixture(SHELF_FIXTURE, screenshot));
}

#[test]
fn shelf_normalization_dedupes_and_drops_missing_files() {
    let files = MemoryFiles::default();
    files.add_existing("/tmp/covio/a.png");
    let state = ShelfStoreState {
        items: vec![
            ShelfItem {
                path: "/tmp/covio/a.png".to_owned(),
                added_at_epoch_seconds: 1,
            },
            ShelfItem {
                path: "/tmp/covio/a.png".to_owned(),
                added_at_epoch_seconds: 2,
            },
            ShelfItem {
                path: "/tmp/covio/missing.png".to_owned(),
                added_at_epoch_seconds: 3,
            },
            ShelfItem {
                path: "/tmp/covio/new.png".to_owned(),
                added_at_epoch_seconds: 4,
            },
        ],
        revealed: true,
        preference_snapshot: None,
    };
    files.add_existing("/tmp/covio/new.png");
    let store = ShelfStore::new(SHELF_PATH, files);
    let saved = store.save(&state).expect("save");
    assert_eq!(
        saved
            .items
            .iter()
            .map(|item| item.path.as_str())
            .collect::<Vec<_>>(),
        vec!["/tmp/covio/a.png", "/tmp/covio/new.png"]
    );
}

#[test]
fn shelf_save_failure_is_typed_and_clear_removes_both_files() {
    let files = MemoryFiles::with_file(SHELF_PATH, SHELF_FIXTURE);
    files
        .0
        .files
        .borrow_mut()
        .insert(PathBuf::from(format!("{SHELF_PATH}.tmp")), b"{}".to_vec());
    files.set_fail_write(true);
    let store = ShelfStore::new(SHELF_PATH, files.clone());
    let error = store
        .save(&ShelfStoreState::default())
        .expect_err("write failure");
    assert_eq!(error.code(), covio_core::CoreErrorCode::Io);

    files.set_fail_write(false);
    assert!(store.clear().expect("clear"));
    assert!(!files.contains(SHELF_PATH));
    assert!(!files.contains(&format!("{SHELF_PATH}.tmp")));
}

#[test]
fn shelf_corruption_returns_default_state() {
    let files = MemoryFiles::with_file(SHELF_PATH, "{");
    let store = ShelfStore::new(SHELF_PATH, files);
    assert_eq!(store.load(), ShelfStoreState::default());
}

#[test]
fn clipboard_fixture_round_trips() {
    let files = MemoryFiles::with_file(CLIPBOARD_PATH, CLIPBOARD_FIXTURE);
    let store = ClipboardStore::new(CLIPBOARD_PATH, files.clone());
    let loaded = store.load();
    assert_eq!(loaded.items.len(), 2);
    assert!(loaded.paused);
    assert_eq!(loaded.policy.max_items, 3);
    store.save(&loaded).expect("save clipboard");

    let actual: Value = serde_json::from_str(&files.text(CLIPBOARD_PATH)).expect("saved clipboard");
    let expected: Value = serde_json::from_str(CLIPBOARD_FIXTURE).expect("clipboard fixture");
    assert_eq!(actual, expected);
}

#[test]
fn clipboard_corruption_returns_defaults_and_save_failure_is_typed() {
    let files = MemoryFiles::with_file(CLIPBOARD_PATH, "{");
    let store = ClipboardStore::new(CLIPBOARD_PATH, files.clone());
    assert_eq!(store.load(), ClipboardState::default());

    files.set_fail_write(true);
    let error = store
        .save(&ClipboardState::default())
        .expect_err("write failure");
    assert_eq!(error.code(), covio_core::CoreErrorCode::Io);
}

#[test]
fn clipboard_clear_removes_state_and_temporary_file() {
    let files = MemoryFiles::with_file(CLIPBOARD_PATH, CLIPBOARD_FIXTURE);
    files.0.files.borrow_mut().insert(
        PathBuf::from(format!("{CLIPBOARD_PATH}.tmp")),
        b"{}".to_vec(),
    );
    let store = ClipboardStore::new(CLIPBOARD_PATH, files.clone());
    assert!(store.clear().expect("clear"));
    assert!(!files.contains(CLIPBOARD_PATH));
    assert!(!files.contains(&format!("{CLIPBOARD_PATH}.tmp")));
}

#[test]
fn clipboard_logic_matches_the_kotlin_contract() {
    assert_eq!(classify("https://example.com"), ClipKind::Link);
    assert_eq!(classify("#abc"), ClipKind::Color);
    assert_eq!(classify("看这个 https://example.com"), ClipKind::Text);

    let image = ClipItem {
        id: "image".to_owned(),
        kind: ClipKind::Image,
        file_path: "/tmp/a.png".to_owned(),
        ..ClipItem::default()
    };
    assert_eq!(import_paths(&image), vec!["/tmp/a.png"]);

    let state = ClipboardState {
        items: vec![
            ClipItem {
                id: "live".to_owned(),
                text: "x".to_owned(),
                ..ClipItem::default()
            },
            image,
        ],
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

    let items = vec![
        ClipItem {
            id: "old".to_owned(),
            text: "same".to_owned(),
            created_at_epoch_seconds: 10,
            ..ClipItem::default()
        },
        ClipItem {
            id: "new".to_owned(),
            text: "same".to_owned(),
            created_at_epoch_seconds: 20,
            ..ClipItem::default()
        },
    ];
    let kept = prune(
        &items,
        &ClipPolicy {
            max_age_days: 0,
            ..ClipPolicy::default()
        },
        20,
        |_| true,
    );
    assert_eq!(
        kept.iter().map(|item| item.id.as_str()).collect::<Vec<_>>(),
        vec!["new"]
    );
}

#[test]
fn screenshot_acceptance_checks_path_segments() {
    assert!(accepts_shelf_file(
        "/tmp/screenshots/a.PNG",
        "/tmp/screenshots",
        |_| false
    ));
    assert!(!accepts_shelf_file(
        "/tmp/screenshots-backup/a.PNG",
        "/tmp/screenshots",
        |_| false
    ));
}

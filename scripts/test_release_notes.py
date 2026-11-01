import importlib.util
import pathlib
import sys
import unittest


SCRIPT = pathlib.Path(__file__).with_name("release_notes.py")
SPEC = importlib.util.spec_from_file_location("release_notes", SCRIPT)
assert SPEC and SPEC.loader
notes = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = notes
SPEC.loader.exec_module(notes)


NOTES = """# Covio 0.6.0（内测 build 14）

Covio 0.6.0 是内测版。

## 安装包

本版提供 `Covio-0.6.0.dmg`。

## 从 build 13 到 build 14 的变化

### 风扇

- 旧内容。

## 验证

- 旧验证。

## 安装

1. 打开 `Covio-0.6.0.dmg`。
"""

README = """## Download (internal test)

Covio 0.6.0-internal.14 is the current internal build.

- [Default DMG](https://github.com/o/r/releases/download/v0.6.0-internal.14/Covio-0.6.0.dmg)
- [Transactional PKG](https://github.com/o/r/releases/download/v0.6.0-internal.14/Covio-0.6.0.pkg)
- [Release page](https://github.com/o/r/releases/tag/v0.6.0-internal.14)
- [Checksums](https://github.com/o/r/releases/download/v0.6.0-internal.14/checksums.txt)
- [Covio 0.6.0 internal build 13](https://github.com/o/r/releases/tag/v0.6.0-internal.13) is the previous internal test.
- [Covio 0.6.0 internal build 12](https://github.com/o/r/releases/tag/v0.6.0-internal.12) is an older internal test.

Install steps:
"""


class ReleaseNotesTests(unittest.TestCase):
    previous = notes.InternalTag("0.6.0", 14)
    current = notes.InternalTag("0.6.0", 15)

    def test_parse_tag(self):
        self.assertEqual(notes.parse_tag("v0.6.0-internal.14"), self.previous)
        with self.assertRaises(notes.NotesError):
            notes.parse_tag("v0.6.0")

    def test_merged_pull_requests_skip_release_branches(self):
        log = "\x1e".join(
            [
                "Merge pull request #511 from o/task/signing-510\x1fDisable hardened runtime\n\n",
                "Merge pull request #509 from o/release/0.6.0-internal.14\x1fPrepare build 14\n",
                "Add the pane (#429)\x1f\n",
                "Fix a typo\x1f\n",
                "",
            ]
        )
        self.assertEqual(
            notes.merged_pull_requests(log),
            [
                notes.PullRequest(511, "Disable hardened runtime"),
                notes.PullRequest(429, "Add the pane"),
            ],
        )

    def test_merge_without_body_uses_branch(self):
        log = "Merge pull request #7 from o/task/fan\x1f\x1e"
        self.assertEqual(notes.merged_pull_requests(log), [notes.PullRequest(7, "task/fan")])

    def test_draft_notes_replaces_heading_changes_and_verification(self):
        pulls = [notes.PullRequest(512, "Expand advanced settings")]
        text = notes.draft_notes(NOTES, self.previous, self.current, pulls)
        self.assertTrue(text.startswith("# Covio 0.6.0（内测 build 15）\n"))
        self.assertIn("## 从 build 14 到 build 15 的变化", text)
        self.assertIn("- Expand advanced settings（#512）", text)
        self.assertNotIn("旧内容", text)
        self.assertNotIn("旧验证", text)
        self.assertEqual(text.count(notes.TODO_MARKER), 2)
        self.assertIn("## 安装\n", text)

    def test_draft_notes_renames_version(self):
        current = notes.InternalTag("0.7.0", 1)
        text = notes.draft_notes(NOTES, self.previous, current, [])
        self.assertNotIn("0.6.0", text)
        self.assertIn("`Covio-0.7.0.dmg`", text)
        self.assertIn("- 无已合并的 PR。", text)

    def test_draft_notes_requires_changes_section(self):
        with self.assertRaises(notes.NotesError):
            notes.draft_notes("# Covio\n\n## 验证\n", self.previous, self.current, [])

    def test_update_readme_moves_links(self):
        text = notes.update_readme(README, self.previous, self.current)
        self.assertIn("Covio 0.6.0-internal.15 is the current internal build.", text)
        self.assertIn("/download/v0.6.0-internal.15/Covio-0.6.0.dmg", text)
        self.assertIn("/tag/v0.6.0-internal.15)", text)
        self.assertNotIn("/download/v0.6.0-internal.14/", text)
        self.assertIn(
            "- [Covio 0.6.0 internal build 14](https://github.com/o/r/releases/tag/v0.6.0-internal.14)"
            " is the previous internal test.",
            text,
        )
        self.assertIn("internal build 13](https://github.com/o/r/releases/tag/v0.6.0-internal.13)"
                      " is an older internal test.", text)
        self.assertEqual(text.count("is the previous internal test."), 1)

    def test_check_notes(self):
        draft = notes.draft_notes(NOTES, self.previous, self.current, [])
        errors = notes.check_notes(draft, self.current)
        self.assertEqual(len(errors), 1)
        self.assertIn(notes.TODO_MARKER, errors[0])
        final = draft.replace(f"<!-- {notes.TODO_MARKER}", "<!-- done")
        self.assertEqual(notes.check_notes(final, self.current), [])
        self.assertEqual(len(notes.check_notes(final, notes.InternalTag("0.6.0", 16))), 1)


if __name__ == "__main__":
    unittest.main()

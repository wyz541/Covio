import contextlib
import importlib.util
import io
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest


SCRIPT = pathlib.Path(__file__).with_name("build_cache.py")
SPEC = importlib.util.spec_from_file_location("build_cache", SCRIPT)
assert SPEC and SPEC.loader
build_cache = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = build_cache
SPEC.loader.exec_module(build_cache)


class BuildCacheTests(unittest.TestCase):
    def setUp(self):
        self._temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self._temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self._git(self.repo, "init", "-q")
        self._git(self.repo, "config", "user.name", "test")
        self._git(self.repo, "config", "user.email", "test@example.com")
        (self.repo / "README.md").write_text("fixture\n", encoding="utf-8")
        self._git(self.repo, "add", "README.md")
        self._git(self.repo, "commit", "-qm", "fixture")
        self.cache_root = self.root / "cache"
        self._old_cache_root = os.environ.get("COVIO_DEBUG_DERIVED_DATA_ROOT")
        os.environ["COVIO_DEBUG_DERIVED_DATA_ROOT"] = str(self.cache_root)
        self._original_stale_registrations = build_cache.stale_launchservices_registrations
        build_cache.stale_launchservices_registrations = lambda: []

    def tearDown(self):
        build_cache.stale_launchservices_registrations = self._original_stale_registrations
        if self._old_cache_root is None:
            os.environ.pop("COVIO_DEBUG_DERIVED_DATA_ROOT", None)
        else:
            os.environ["COVIO_DEBUG_DERIVED_DATA_ROOT"] = self._old_cache_root
        self._temporary.cleanup()

    @staticmethod
    def _git(root, *args):
        subprocess.run(
            ["git", "-C", str(root), *args],
            check=True,
            capture_output=True,
            text=True,
        )

    def _add_worktree(self, name):
        path = self.root / name
        self._git(self.repo, "worktree", "add", "-q", "-b", name, str(path))
        return path

    def _age_entry(self, path, days):
        timestamp = time.time() - days * 86400
        os.utime(path / build_cache.LAST_USED_NAME, (timestamp, timestamp))

    def test_prepare_uses_stable_worktree_specific_paths(self):
        linked = self._add_worktree("linked")
        main_cache = build_cache.prepare_cache(self.repo)
        linked_cache = build_cache.prepare_cache(linked)

        self.assertNotEqual(main_cache, linked_cache)
        self.assertEqual(main_cache, build_cache.prepare_cache(self.repo))
        self.assertTrue((self.cache_root / build_cache.MARKER_NAME).is_file())
        self.assertEqual(
            (main_cache / build_cache.METADATA_NAME).read_text(encoding="utf-8").strip(),
            str(self.repo.resolve()),
        )
        self.assertTrue((main_cache / build_cache.LAST_USED_NAME).is_file())

    def test_cleanup_deletes_missing_worktree_after_apply(self):
        build_cache.prepare_cache(self.repo)
        missing = self.cache_root / "missing-worktree"
        (missing / "Build" / "Products" / "Debug" / "Covio.app").mkdir(parents=True)
        (missing / "Build" / "Products" / "Debug" / "Covio.app" / "payload").write_text(
            "x", encoding="utf-8"
        )
        (missing / build_cache.METADATA_NAME).write_text(
            str(self.root / "gone") + "\n", encoding="utf-8"
        )
        (missing / build_cache.LAST_USED_NAME).touch()

        plan = build_cache.make_plan(self.repo, 4, 7, 8.0)
        self.assertIn(missing.resolve(), {entry.path for entry in plan.to_delete})
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(build_cache.apply_plan(plan, apply=False), 0)
        self.assertTrue(missing.exists())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(build_cache.apply_plan(plan, apply=True), 0)
        self.assertFalse(missing.exists())

    def test_cleanup_keeps_current_and_dirty_worktrees(self):
        linked = self._add_worktree("dirty")
        old = self._add_worktree("old")
        main_cache = build_cache.prepare_cache(self.repo)
        linked_cache = build_cache.prepare_cache(linked)
        old_cache = build_cache.prepare_cache(old)

        (linked / "README.md").write_text("dirty\n", encoding="utf-8")
        for entry in (main_cache, linked_cache, old_cache):
            self._age_entry(entry, 9)

        plan = build_cache.make_plan(self.repo, 4, 7, 8.0)
        deleting = {entry.path for entry in plan.to_delete}
        self.assertNotIn(main_cache, deleting)
        self.assertNotIn(linked_cache, deleting)
        self.assertIn(old_cache, deleting)

    def test_cleanup_keeps_cache_used_by_an_active_build(self):
        old = self._add_worktree("active")
        old_cache = build_cache.prepare_cache(old)
        self._age_entry(old_cache, 9)

        original = build_cache.entry_in_use
        build_cache.entry_in_use = lambda path, active: path.resolve() == old_cache.resolve()
        try:
            plan = build_cache.make_plan(self.repo, 4, 7, 8.0)
        finally:
            build_cache.entry_in_use = original

        self.assertNotIn(old_cache, {entry.path for entry in plan.to_delete})

    def test_cleanup_prunes_stale_launchservices_registration(self):
        stale = self.root / "gone" / "Covio.app"
        build_cache.stale_launchservices_registrations = lambda: [stale]
        plan = build_cache.make_plan(self.repo, 4, 7, 8.0)
        self.assertIn(stale, plan.stale_registrations)

        original_unregister = build_cache.unregister_apps
        removed = []
        build_cache.unregister_apps = lambda paths: removed.extend(paths)
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(build_cache.apply_plan(plan, apply=False), 0)
            self.assertEqual(removed, [])
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(build_cache.apply_plan(plan, apply=True), 0)
        finally:
            build_cache.unregister_apps = original_unregister
        self.assertEqual(removed, [stale])

    def test_protected_entries_report_budget_overflow(self):
        main_cache = build_cache.prepare_cache(self.repo)
        (main_cache / "large.bin").write_bytes(b"x" * 2_000_000)

        plan = build_cache.make_plan(self.repo, 4, 7, 0.001)
        self.assertTrue(plan.errors)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(
            io.StringIO()
        ):
            self.assertEqual(build_cache.apply_plan(plan, apply=False), 1)

    def test_entry_limit_only_deletes_clean_non_current_entries(self):
        linked = self._add_worktree("linked")
        extra = self._add_worktree("extra")
        main_cache = build_cache.prepare_cache(self.repo)
        linked_cache = build_cache.prepare_cache(linked)
        extra_cache = build_cache.prepare_cache(extra)

        (linked / "README.md").write_text("dirty\n", encoding="utf-8")
        self._age_entry(main_cache, 1)
        self._age_entry(linked_cache, 2)
        self._age_entry(extra_cache, 3)

        plan = build_cache.make_plan(self.repo, 1, 7, 8.0)
        deleting = {entry.path for entry in plan.to_delete}
        self.assertNotIn(main_cache, deleting)
        self.assertNotIn(linked_cache, deleting)
        self.assertIn(extra_cache, deleting)


if __name__ == "__main__":
    unittest.main()

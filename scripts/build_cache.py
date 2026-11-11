#!/usr/bin/env python3
"""Manage the local Covio Xcode DerivedData cache.

The cache is outside Git worktrees. Each worktree gets a stable subdirectory.
The cleanup command is a dry run unless --apply is provided.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set

DEFAULT_MAX_ENTRIES = 4
DEFAULT_MAX_AGE_DAYS = 7
DEFAULT_MAX_GIB = 8.0
MARKER_NAME = ".metadata_never_index"
METADATA_NAME = "worktree-path"
LAST_USED_NAME = ".last-used"
LSREGISTER = Path(
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
    "LaunchServices.framework/Support/lsregister"
)


@dataclass
class CacheEntry:
    path: Path
    worktree: Optional[Path]
    last_used: float
    size_bytes: int
    missing: bool
    dirty: Optional[bool]
    in_use: bool
    current: bool
    reasons: Set[str] = field(default_factory=set)

    @property
    def age_days(self) -> float:
        return max(0.0, (time.time() - self.last_used) / 86400.0)


@dataclass
class CleanupPlan:
    root: Path
    entries: List[CacheEntry]
    to_delete: List[CacheEntry]
    stale_registrations: List[Path]
    errors: List[str]

    @property
    def total_bytes(self) -> int:
        return sum(entry.size_bytes for entry in self.entries)

    @property
    def delete_bytes(self) -> int:
        return sum(entry.size_bytes for entry in self.to_delete)


def run_git(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        capture_output=True,
        text=True,
        errors="replace",
    )


def worktree_root(root: Path) -> Path:
    result = run_git(root, "rev-parse", "--show-toplevel")
    if result.returncode == 0 and result.stdout.strip():
        return Path(result.stdout.strip()).resolve()
    return root.resolve()


def cache_root(root: Path) -> Path:
    configured = os.environ.get("COVIO_DEBUG_DERIVED_DATA_ROOT", "").strip()
    if configured:
        path = Path(configured).expanduser()
        if not path.is_absolute():
            path = root / path
        return path.resolve()
    return (Path.home() / "Library" / "Caches" / "Covio" / "DerivedData").resolve()


def worktree_key(path: Path) -> str:
    return hashlib.sha256(str(path.resolve()).encode("utf-8")).hexdigest()[:16]


def cache_path(root: Path) -> Path:
    return cache_root(root) / worktree_key(worktree_root(root))


def prepare_cache(root: Path) -> Path:
    root = root.resolve()
    tree = worktree_root(root)
    destination = cache_path(root)
    destination.parent.mkdir(parents=True, exist_ok=True)
    (destination.parent / MARKER_NAME).touch(exist_ok=True)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / METADATA_NAME).write_text(str(tree) + "\n", encoding="utf-8")
    (destination / LAST_USED_NAME).touch()
    return destination


def directory_size(path: Path) -> int:
    result = subprocess.run(
        ["du", "-sk", str(path)],
        capture_output=True,
        text=True,
        errors="replace",
    )
    if result.returncode == 0 and result.stdout:
        try:
            return int(result.stdout.split("\t", 1)[0]) * 1024
        except ValueError:
            pass
    total = 0
    for current, dirs, files in os.walk(path, followlinks=False):
        for name in files:
            candidate = Path(current) / name
            try:
                if not candidate.is_symlink():
                    total += candidate.stat().st_size
            except OSError:
                pass
    return total


def read_worktree(entry: Path) -> Optional[Path]:
    metadata = entry / METADATA_NAME
    try:
        value = metadata.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    return Path(value).resolve() if value else None


def worktree_is_dirty(path: Optional[Path]) -> Optional[bool]:
    if path is None or not path.exists():
        return None
    result = run_git(path, "status", "--porcelain", "--untracked-files=normal")
    if result.returncode != 0:
        return None
    return bool(result.stdout.strip())


def active_builds() -> List[str]:
    try:
        result = subprocess.run(
            ["ps", "-axo", "command="],
            capture_output=True,
            text=True,
            errors="replace",
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    return [
        line for line in result.stdout.splitlines() if "xcodebuild" in line
    ]


def entry_in_use(path: Path, active: Sequence[str]) -> bool:
    marker = str(path)
    return any(marker in line for line in active)


def load_entries(root: Path, active: Sequence[str]) -> List[CacheEntry]:
    cache = cache_root(root)
    current = cache_path(root)
    if not cache.is_dir():
        return []
    entries: List[CacheEntry] = []
    for candidate in cache.iterdir():
        if candidate.is_symlink() or not candidate.is_dir():
            continue
        if not (candidate / METADATA_NAME).is_file():
            continue
        tree = read_worktree(candidate)
        last_used_path = candidate / LAST_USED_NAME
        try:
            last_used = last_used_path.stat().st_mtime
        except OSError:
            last_used = candidate.stat().st_mtime
        missing = tree is None or not tree.exists()
        dirty = None if missing else worktree_is_dirty(tree)
        entries.append(
            CacheEntry(
                path=candidate,
                worktree=tree,
                last_used=last_used,
                size_bytes=directory_size(candidate),
                missing=missing,
                dirty=dirty,
                in_use=entry_in_use(candidate, active),
                current=candidate.resolve() == current.resolve(),
            )
        )
    return sorted(entries, key=lambda item: item.last_used, reverse=True)


def launchservices_registrations() -> List[Path]:
    if platform.system() != "Darwin" or not LSREGISTER.is_file():
        return []
    result = subprocess.run(
        [str(LSREGISTER), "-dump"],
        capture_output=True,
        text=True,
        errors="replace",
        check=False,
    )
    paths: Set[Path] = set()
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if not stripped.startswith("path:"):
            continue
        value = stripped[len("path:") :].strip().rsplit(" (0x", 1)[0]
        if value.endswith("/Covio.app"):
            paths.add(Path(value))
    return sorted(paths)


def stale_launchservices_registrations() -> List[Path]:
    return [path for path in launchservices_registrations() if not path.is_dir()]


def make_plan(
    root: Path,
    max_entries: int,
    max_age_days: int,
    max_gib: float,
) -> CleanupPlan:
    active = active_builds()
    entries = load_entries(root, active)
    to_delete: Dict[Path, CacheEntry] = {}
    errors: List[str] = []

    for entry in entries:
        if entry.current:
            entry.reasons.add("current worktree")
        elif entry.in_use:
            entry.reasons.add("build in use")
        elif entry.missing:
            entry.reasons.add("worktree missing")
            to_delete[entry.path] = entry
        elif entry.dirty is None:
            entry.reasons.add("worktree status unknown")
        elif entry.dirty:
            entry.reasons.add("worktree dirty")
        elif entry.age_days > max_age_days:
            entry.reasons.add("older than retention")
            to_delete[entry.path] = entry
        else:
            entry.reasons.add("retained")

    existing = [entry for entry in entries if not entry.missing]
    for index, entry in enumerate(existing):
        if index < max_entries:
            continue
        if entry.current:
            continue
        if entry.in_use or entry.dirty is True or entry.dirty is None:
            continue
        entry.reasons.add("beyond newest entry limit")
        to_delete[entry.path] = entry

    limit_bytes = int(max_gib * 1024 ** 3)
    remaining = sum(
        entry.size_bytes for entry in entries if entry.path not in to_delete
    )
    if remaining > limit_bytes:
        candidates = [
            entry
            for entry in sorted(entries, key=lambda item: item.last_used)
            if entry.path not in to_delete
            and not entry.current
            and not entry.in_use
            and not entry.missing
            and entry.dirty is False
        ]
        for entry in candidates:
            if remaining <= limit_bytes:
                break
            entry.reasons.add("total size budget")
            to_delete[entry.path] = entry
            remaining -= entry.size_bytes
    if remaining > limit_bytes:
        errors.append(
            "Protected entries still exceed the size budget. "
            "Inspect the dirty worktrees listed below."
        )

    return CleanupPlan(
        root=cache_root(root),
        entries=entries,
        to_delete=sorted(to_delete.values(), key=lambda item: item.path.name),
        stale_registrations=stale_launchservices_registrations(),
        errors=errors,
    )


def format_bytes(value: int) -> str:
    if value >= 1024 ** 3:
        return f"{value / 1024 ** 3:.2f} GiB"
    if value >= 1024 ** 2:
        return f"{value / 1024 ** 2:.1f} MiB"
    return f"{value / 1024:.1f} KiB"


def print_plan(plan: CleanupPlan) -> None:
    print(f"cache root: {plan.root}")
    print(f"entries: {len(plan.entries)} ({format_bytes(plan.total_bytes)})")
    print(
        f"delete: {len(plan.to_delete)} "
        f"({format_bytes(plan.delete_bytes)})"
    )
    print(f"stale LaunchServices entries: {len(plan.stale_registrations)}")
    if not plan.entries and not plan.stale_registrations:
        return
    print()
    print(f"{'ACTION':7} {'SIZE':>10} {'AGE':>6}  CACHE / WORKTREE")
    deleting = {entry.path for entry in plan.to_delete}
    for entry in plan.entries:
        action = "DELETE" if entry.path in deleting else "KEEP"
        tree = str(entry.worktree) if entry.worktree else "<unknown>"
        reason = ", ".join(sorted(entry.reasons)) or "retained"
        print(
            f"{action:7} {format_bytes(entry.size_bytes):>10} "
            f"{entry.age_days:6.1f}d  {entry.path.name} / {tree}"
        )
        print(f"        reason: {reason}")
    for path in plan.stale_registrations:
        print(f"PRUNE   stale LaunchServices entry: {path}")
    if plan.errors:
        print()
        for error in plan.errors:
            print(f"warning: {error}", file=sys.stderr)


def covio_apps(entry: Path) -> Iterable[Path]:
    for current, dirs, _files in os.walk(entry, followlinks=False):
        current_path = Path(current)
        for name in list(dirs):
            if name == "Covio.app":
                yield current_path / name
                dirs.remove(name)


def unregister_apps(paths: Iterable[Path]) -> None:
    if platform.system() != "Darwin" or not LSREGISTER.is_file():
        return
    for path in paths:
        subprocess.run(
            [str(LSREGISTER), "-u", str(path)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def apply_plan(plan: CleanupPlan, apply: bool) -> int:
    exit_code = 1 if plan.errors else 0
    print_plan(plan)
    if not plan.to_delete and not plan.stale_registrations:
        print("\nNo cache entries or stale LaunchServices entries need deletion.")
        return exit_code
    if not apply:
        print("\nDry run only. Re-run with --apply to delete these entries.")
        return exit_code
    failures = 0
    for path in plan.stale_registrations:
        unregister_apps([path])
        print(f"removed stale LaunchServices entry: {path}")
    for entry in plan.to_delete:
        if entry.path.parent.resolve() != plan.root.resolve():
            print(
                f"error: refusing to delete outside cache root: {entry.path}",
                file=sys.stderr,
            )
            failures += 1
            continue
        unregister_apps(covio_apps(entry.path))
        try:
            shutil.rmtree(entry.path)
            print(f"deleted {entry.path}")
        except OSError as error:
            print(f"error: cannot delete {entry.path}: {error}", file=sys.stderr)
            failures += 1
    return 1 if failures else exit_code


def command_prepare(root: Path, _args: Sequence[str]) -> int:
    print(prepare_cache(root))
    return 0


def command_status(root: Path, _args: Sequence[str]) -> int:
    plan = make_plan(root, DEFAULT_MAX_ENTRIES, DEFAULT_MAX_AGE_DAYS, DEFAULT_MAX_GIB)
    print_plan(plan)
    return 1 if plan.errors else 0


def command_clean(root: Path, args: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="build_cache.py clean")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--max-entries", type=int, default=DEFAULT_MAX_ENTRIES)
    parser.add_argument("--max-age-days", type=int, default=DEFAULT_MAX_AGE_DAYS)
    parser.add_argument("--max-gib", type=float, default=DEFAULT_MAX_GIB)
    parsed = parser.parse_args(args)
    if parsed.max_entries < 1:
        parser.error("--max-entries must be at least 1")
    if parsed.max_age_days < 1:
        parser.error("--max-age-days must be at least 1")
    if parsed.max_gib <= 0:
        parser.error("--max-gib must be positive")
    plan = make_plan(
        root,
        max_entries=parsed.max_entries,
        max_age_days=parsed.max_age_days,
        max_gib=parsed.max_gib,
    )
    return apply_plan(plan, parsed.apply)


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["prepare", "status", "clean"])
    parser.add_argument("root", type=Path)
    args, rest = parser.parse_known_args(argv)
    root = args.root.resolve()
    if args.command == "prepare":
        return command_prepare(root, rest)
    if args.command == "status":
        return command_status(root, rest)
    return command_clean(root, rest)


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        raise SystemExit(130)

#!/usr/bin/env python3
"""内测发布说明的草稿与检查。

`scripts/covio release prepare` 用 `draft` 改写 RELEASE_NOTES.md 与 README.md。
`scripts/covio release draft` 用 `check` 拒绝仍有占位标记的说明。

草稿只列出已合并 PR 的标题。维护者按用户可见的变化重写，再删除占位标记。
"""

from __future__ import annotations

import argparse
import dataclasses
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TODO_MARKER = "TODO(release)"
MERGE_SUBJECT = re.compile(r"^Merge pull request #(\d+) from [^/\s]+/(\S+)$")
SQUASH_SUBJECT = re.compile(r"^(.*\S)\s+\(#(\d+)\)$")
TAG = re.compile(r"^v(\d+\.\d+\.\d+)-internal\.(\d+)$")


class NotesError(Exception):
    pass


@dataclasses.dataclass(frozen=True)
class PullRequest:
    number: int
    title: str


@dataclasses.dataclass(frozen=True)
class InternalTag:
    version: str
    build: int

    @property
    def name(self) -> str:
        return f"v{self.version}-internal.{self.build}"


def parse_tag(tag: str) -> InternalTag:
    match = TAG.fullmatch(tag)
    if not match:
        raise NotesError(f"not an internal release tag: {tag}")
    return InternalTag(match.group(1), int(match.group(2)))


def merged_pull_requests(log: str) -> list[PullRequest]:
    """从 `git log --first-parent --format=%s%x1f%b%x1e` 的输出读出 PR。

    release/ 分支是上一次发布准备，不算本版变化。
    """
    pulls: list[PullRequest] = []
    for record in log.split("\x1e"):
        record = record.strip("\n")
        if not record:
            continue
        subject, _, body = record.partition("\x1f")
        merge = MERGE_SUBJECT.fullmatch(subject.strip())
        if merge:
            if merge.group(2).startswith("release/"):
                continue
            title = next((line.strip() for line in body.splitlines() if line.strip()), "")
            pulls.append(PullRequest(int(merge.group(1)), title or merge.group(2)))
            continue
        squash = SQUASH_SUBJECT.fullmatch(subject.strip())
        if squash:
            pulls.append(PullRequest(int(squash.group(2)), squash.group(1)))
    return pulls


def _replace_section(text: str, heading_prefix: str, new_section: str) -> str:
    lines = text.splitlines(keepends=True)
    start = next(
        (index for index, line in enumerate(lines) if line.startswith(heading_prefix)),
        None,
    )
    if start is None:
        raise NotesError(f"RELEASE_NOTES.md has no section starting with {heading_prefix!r}")
    end = next(
        (index for index in range(start + 1, len(lines)) if lines[index].startswith("## ")),
        len(lines),
    )
    return "".join(lines[:start]) + new_section + "".join(lines[end:])


def draft_notes(text: str, previous: InternalTag, current: InternalTag, pulls: list[PullRequest]) -> str:
    lines = text.splitlines(keepends=True)
    if not lines or not lines[0].startswith("# "):
        raise NotesError("RELEASE_NOTES.md must start with a level-1 heading")
    lines[0] = f"# Covio {current.version}（内测 build {current.build}）\n"
    text = "".join(lines)
    if previous.version != current.version:
        text = text.replace(previous.version, current.version)

    items = [f"- {pull.title}（#{pull.number}）" for pull in pulls] or ["- 无已合并的 PR。"]
    changes = "\n".join(
        [
            f"## 从 build {previous.build} 到 build {current.build} 的变化",
            "",
            f"<!-- {TODO_MARKER}: 按用户可见的变化重写本节，然后删除本注释。 -->",
            "",
            *items,
            "",
            "",
        ]
    )
    text = _replace_section(text, "## 从 build ", changes)
    verification = "\n".join(
        [
            "## 验证",
            "",
            f"<!-- {TODO_MARKER}: 填写本版的测试结果与真机验收，然后删除本注释。 -->",
            "",
            "",
        ]
    )
    return _replace_section(text, "## 验证", verification)


def update_readme(text: str, previous: InternalTag, current: InternalTag) -> str:
    current_line = re.compile(r"^Covio \S+-internal\.\d+ is the current internal build\.$", re.M)
    if not current_line.search(text):
        raise NotesError("README.md has no 'is the current internal build.' line")
    text = current_line.sub(
        f"Covio {current.version}-internal.{current.build} is the current internal build.", text
    )

    repository = re.search(r"https://github\.com/([^/\s]+/[^/\s]+)/releases/", text)
    if not repository:
        raise NotesError("README.md has no GitHub release link")
    base = f"https://github.com/{repository.group(1)}/releases"

    lines = text.splitlines(keepends=True)
    download_prefixes = ("- [Default DMG]", "- [Transactional PKG]", "- [Release page]", "- [Checksums]")
    checksums_index = None
    for index, line in enumerate(lines):
        if line.startswith(download_prefixes):
            line = line.replace(f"/{previous.name}/", f"/{current.name}/")
            line = line.replace(f"/{previous.name})", f"/{current.name})")
            line = line.replace(f"Covio-{previous.version}.", f"Covio-{current.version}.")
            lines[index] = line
            if line.startswith("- [Checksums]"):
                checksums_index = index
    if checksums_index is None:
        raise NotesError("README.md has no '- [Checksums]' download line")

    following = checksums_index + 1
    if following < len(lines) and lines[following].rstrip().endswith("is the previous internal test."):
        lines[following] = lines[following].replace(
            "is the previous internal test.", "is an older internal test."
        )
    lines.insert(
        following,
        f"- [Covio {previous.version} internal build {previous.build}]"
        f"({base}/tag/{previous.name}) is the previous internal test.\n",
    )
    return "".join(lines)


def check_notes(text: str, current: InternalTag) -> list[str]:
    errors: list[str] = []
    expected = f"# Covio {current.version}（内测 build {current.build}）"
    first = text.splitlines()[0] if text else ""
    if first != expected:
        errors.append(f"RELEASE_NOTES.md heading is {first!r}, expected {expected!r}")
    if TODO_MARKER in text:
        errors.append(f"RELEASE_NOTES.md still contains {TODO_MARKER}")
    return errors


def _git_log(root: pathlib.Path, previous: InternalTag, head: str) -> str:
    return subprocess.check_output(
        [
            "git", "-C", str(root), "log", "--first-parent",
            "--format=%s%x1f%b%x1e", f"{previous.name}..{head}",
        ],
        text=True,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    draft = sub.add_parser("draft")
    draft.add_argument("--root", type=pathlib.Path, default=ROOT)
    draft.add_argument("--previous-tag", required=True)
    draft.add_argument("--current-tag", required=True)
    draft.add_argument("--head", default="HEAD")

    check = sub.add_parser("check")
    check.add_argument("--notes", type=pathlib.Path, required=True)
    check.add_argument("--current-tag", required=True)

    args = parser.parse_args(argv)
    try:
        current = parse_tag(args.current_tag)
        if args.command == "draft":
            previous = parse_tag(args.previous_tag)
            pulls = merged_pull_requests(_git_log(args.root, previous, args.head))
            notes_path = args.root / "RELEASE_NOTES.md"
            readme_path = args.root / "README.md"
            notes_path.write_text(
                draft_notes(notes_path.read_text(encoding="utf-8"), previous, current, pulls),
                encoding="utf-8",
            )
            readme_path.write_text(
                update_readme(readme_path.read_text(encoding="utf-8"), previous, current),
                encoding="utf-8",
            )
            print(f"drafted notes for {current.name} from {len(pulls)} pull requests")
            return 0
        if args.command == "check":
            errors = check_notes(args.notes.read_text(encoding="utf-8"), current)
            for error in errors:
                print(error, file=sys.stderr)
            if errors:
                return 1
            print("release notes are ready")
            return 0
    except (NotesError, OSError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""校验精简后的 Issue、PR 和流程文档。"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / ".github" / "ISSUE_TEMPLATE"
WORKFLOW = ROOT / "docs" / "process" / "workflow.md"
AGENTS = ROOT / "AGENTS.md"
PR_TEMPLATE = ROOT / ".github" / "pull_request_template.md"
PREVIEWS = ROOT / "docs" / "design" / "previews" / "README.md"
ADR = ROOT / "docs" / "adr" / "adr-0028-slim-issue-workflow.md"
WORKFLOWS = ROOT / ".github" / "workflows"
CI = WORKFLOWS / "ci.yml"
LOCAL_MACOS = ROOT / "docs" / "process" / "macos-validation.md"

errors: list[str] = []


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def require(path: Path, fragments: tuple[str, ...]) -> None:
    content = text(path)
    for fragment in fragments:
        if fragment not in content:
            errors.append(f"{path.relative_to(ROOT)} 缺少：{fragment}")


def forbid(path: Path, fragments: tuple[str, ...]) -> None:
    content = text(path)
    for fragment in fragments:
        if fragment in content:
            errors.append(f"{path.relative_to(ROOT)} 不应包含：{fragment}")


def required_fields(path: Path) -> int:
    return len(re.findall(r"^\s+required:\s+true\s*$", text(path), re.MULTILINE))


def main() -> int:
    expected_fields = {
        "bug.yml": 3,
        "task.yml": 2,
        "feature.yml": 2,
        "research.yml": 3,
        "verify.yml": 2,
    }

    for name, expected in expected_fields.items():
        path = TEMPLATES / name
        if not path.exists():
            errors.append(f"缺少模板：{name}")
            continue
        if required_fields(path) != expected:
            errors.append(
                f"{name} 必填字段应为 {expected} 个，实际为 {required_fields(path)} 个"
            )
        forbid(path, ("decision: pending", "label: Size", "label: Start date"))

    template_lines = sum(
        len(text(path).splitlines())
        for path in sorted(TEMPLATES.glob("*.yml"))
    )
    if template_lines > 300:
        errors.append(f"Issue 模板共 {template_lines} 行，上限是 300 行")

    workflow_text = text(WORKFLOW)
    if len(workflow_text.splitlines()) > 180:
        errors.append("工作流超过 180 行")
    require(
        WORKFLOW,
        (
            "## 2. 三条路径",
            "Discussion 是可选入口",
            "Research 可以独立存在",
            "### 4.4 Verify 例外",
            "原生 sub-issue、`blocked by` 和 linked PR 是关系的唯一来源",
            "`Size`、`Start date` 和 `Estimate` 是历史字段",
            "局部 UI 改动",
            "普通 PR 不填写 `Design preview`",
        ),
    )
    forbid(
        WORKFLOW,
        (
            "每周检查",
            "decision: pending",
            "S1",
            "S2",
            "S3",
            "S4",
            "S5",
            "S6",
            "S7",
        ),
    )

    if len(text(AGENTS).splitlines()) > 100:
        errors.append("AGENTS.md 超过 100 行")
    require(
        AGENTS,
        (
            "明确 Bug 或小任务直接创建 Issue",
            "Research 可以独立存在",
            "Verify 只用于",
            "不要写决策占位符",
            "不要使用人工周检清单",
            "局部 UI 改动",
        ),
    )
    forbid(AGENTS, ("S1", "S2", "S3", "S4", "S5", "S6", "S7"))

    if len(text(PR_TEMPLATE).splitlines()) > 50:
        errors.append("PR 模板超过 50 行")
    require(
        PR_TEMPLATE,
        (
            "## What changed",
            "## Proof",
            "## Visual verification",
            "## Risk",
            "Local UI change",
            "Release candidate",
            "Closes #",
        ),
    )
    forbid(PR_TEMPLATE, ("## Design preview", "**亮色**", "**深色**"))

    require(
        PREVIEWS,
        (
            "证据分级",
            "局部 UI",
            "外观、导航或材质",
            "发布候选",
        ),
    )
    require(
        ADR,
        (
            "- Status：accepted",
            "- Supersedes：ADR-0023、ADR-0024（Discussion promotion model）",
            "## 决策",
        ),
    )

    require(
        CI,
        (
            "pull_request:",
            "runs-on: ubuntu-latest",
            "cancel-in-progress: true",
            "python3 -I scripts/verify-kmp-removal.py",
        ),
    )
    forbid(
        CI,
        (
            "  push:",
            "macos-release.yml",
            "setup-java",
            "kotlin test",
            "kmpDomain",
        ),
    )

    for path in sorted(WORKFLOWS.glob("*.yml")):
        if re.search(r"runs-on:\s*\[?[^\n]*macos", text(path), re.IGNORECASE):
            errors.append(f"{path.relative_to(ROOT)} 不得使用 macOS runner")

    require(
        LOCAL_MACOS,
        (
            "GitHub Actions 不运行 macOS 检查",
            "bash scripts/test-all.sh",
            "scripts/verify-agent-bundle.sh",
            "scripts/verify-file-naming-bundle.sh",
        ),
    )

    if errors:
        for error in errors:
            print(f"工作流校验失败：{error}", file=sys.stderr)
        print(f"{len(errors)} 条问题。", file=sys.stderr)
        return 1

    print("工作流校验通过：流程、无 KMP 产品路径和本地 macOS 验收边界正确。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

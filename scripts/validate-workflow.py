#!/usr/bin/env python3
"""校验精简后的 Issue、PR 和流程文档。"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / ".github" / "ISSUE_TEMPLATE"
WORKFLOW = ROOT / "docs" / "process" / "workflow.md"
INTERACTION_CONTRACT = ROOT / "docs" / "process" / "interaction-contract.md"
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
    if len(workflow_text.splitlines()) > 195:
        errors.append("工作流超过 195 行")
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
            "## 8. 跨平台交互合同",
            "[跨平台交互合同工作流](interaction-contract.md)",
            "Windows 不得独立定义共享值",
            "`Contract impact`",
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

    if len(text(AGENTS).splitlines()) > 115:
        errors.append("AGENTS.md 超过 115 行")
    require(
        AGENTS,
        (
            "明确 Bug 或小任务直接创建 Issue",
            "Research 可以独立存在",
            "Verify 只用于",
            "不要写决策占位符",
            "不要使用人工周检清单",
            "局部 UI 改动",
            "## 6. 跨平台交互合同",
            "macOS 是共享交互、动效和外观的唯一设计来源",
            "macOS 用类型化 Swift 合同定义共享行为",
            "JSON 合同由 macOS Swift 合同确定性导出",
            "Windows 只消费生成的 Rust 合同",
            "Windows 不得独立定义共享触发、几何、动效或状态转换参数",
            "禁止手改合同生成物",
            "`Contract impact`",
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
            "Contract impact:",
            "macOS Swift source updated",
            "Exported JSON regenerated",
            "Windows generated consumer refreshed",
            "Conformance tests updated",
            "Closes #",
        ),
    )
    forbid(PR_TEMPLATE, ("## Design preview", "**亮色**", "**深色**"))

    if len(text(INTERACTION_CONTRACT).splitlines()) > 160:
        errors.append("跨平台交互合同工作流超过 160 行")

    require(
        INTERACTION_CONTRACT,
        (
            "**结论：macOS 是共享交互与动效的唯一设计来源。Windows 只消费生成产物。**",
            "JSON 合同是导出物",
            "生成的 Rust 是导出物",
            "Windows 不得静默增加视觉调整",
            "`Contract impact`",
            "任一项不满足时，PR 不得转为 ready 或合并",
            "迁移期仍禁止 Windows 单独定义共享值",
        ),
    )

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
            "predicate-quantifier: some-with-excludes",
            "docs/design/previews/**",
            "docs/research/**",
            "guide/**",
            "windows-x64:",
            "windows-arm64:",
            "windows-package:",
            "needs.portable.outputs.full == 'true'",
            "needs.portable.outputs.windows == 'true'",
            "needs.portable.outputs.windows_arm == 'true'",
            "needs.portable.outputs.installer == 'true'",
            "startsWith(github.head_ref, 'release/')",
            "!macosApp/**",
            "!docs/**",
            "!guide/**",
            "!rust/**",
            "!assets/windows/**",
            "!installer/windows/**",
            "!scripts/*macos*",
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
            "windows-host:",
            "matrix.runner",
            '      - "docs/**"',
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

    print("工作流校验通过：流程、按路径运行的托管门禁和本地 macOS 验收边界正确。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

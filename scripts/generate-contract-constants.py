#!/usr/bin/env python3
"""从设计合同生成 Swift 与 Rust 常量。

macOS 与 iOS 的 Apple 设计是文案与设计令牌的权威。
`docs/covio-design-contract.json` 是机器可读投影。
手抄到 Swift 或 Rust 会漂移，所以这个脚本把三份都生成出来：

    macosApp/src/Design/ContractCopy.swift          文案
    macosApp/src/Design/ContractTokens.swift        Swift 颜色、尺寸与动效
    rust/crates/covio-core/src/contract_motion.rs   Rust 动效

用法：
    python3 scripts/generate-contract-constants.py           写入文件
    python3 scripts/generate-contract-constants.py --check   只比对，不写

`DesignContractTests` 会读合同逐条比对生成结果，
所以忘跑脚本会被测试拦下。
"""

import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "docs" / "covio-design-contract.json"
COPY_OUT = ROOT / "macosApp" / "src" / "Design" / "ContractCopy.swift"
TOKENS_OUT = ROOT / "macosApp" / "src" / "Design" / "ContractTokens.swift"
RUST_MOTION_OUT = ROOT / "rust" / "crates" / "covio-core" / "src" / "contract_motion.rs"

HEADER = """// 本文件由 scripts/generate-contract-constants.py 生成。不要手改。
// 权威是 macOS/iOS Apple design。
// docs/covio-design-contract.json 是机器可读投影。
// 改合同后重跑脚本：python3 scripts/generate-contract-constants.py
"""


def identifier(key: str) -> str:
    """`copy/overview/helper/installed` -> `copyOverviewHelperInstalled`。"""
    parts = re.split(r"[/\-]", key)
    name = parts[0] + "".join(part[:1].upper() + part[1:] for part in parts[1:])
    return re.sub(r"[^0-9A-Za-z_]", "", name)


def swift_string(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'

def rust_identifier(key: str) -> str:
    """Convert a motion token key into a stable Rust constant name."""
    parts = re.split(r"[/\-]", key)
    if parts[:2] == ["token", "motion"]:
        parts = parts[2:]
    return "_".join(part.upper() for part in parts)


def rust_duration(value: float) -> str:
    """Render a millisecond value as a Rust Duration expression."""
    if float(value).is_integer():
        return f"Duration::from_millis({int(value)})"
    return f"Duration::from_micros({round(float(value) * 1000)})"


def generate_copy(contract: dict) -> str:
    entries = contract["copy"]
    lines = [HEADER, "import Foundation", ""]
    lines.append("/// 设计合同 `copy` 段的全部文案。")
    lines.append("///")
    lines.append("/// 键名就是合同里的键路径。`DesignContractTests` 逐条比对，")
    lines.append("/// 所以这里的值不能手改。")
    lines.append("enum ContractCopy {")

    names = []
    for key in sorted(entries):
        value = entries[key]
        name = identifier(key)
        names.append(name)
        lines.append(f"    /// `{key}`")
        lines.append(
            f"    static let {name} = LocalizedCopy("
            f"key: {swift_string(key)}, "
            f"en: {swift_string(value['en'])}, "
            f"zhHans: {swift_string(value['zh-Hans'])})"
        )
    lines.append("")
    lines.append("    /// 全部条目。供测试遍历。")
    lines.append("    static let all: [LocalizedCopy] = [")
    for name in names:
        lines.append(f"        {name},")
    lines.append("    ]")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def generate_tokens(contract: dict) -> str:
    tokens = {
        key: value
        for key, value in contract["tokens"].items()
        if not key.startswith("token/art/")
    }
    colors = {k: v for k, v in tokens.items() if v["type"] == "color"}
    dimensions = {k: v for k, v in tokens.items() if v["type"] == "dimension"}
    motion = {k: v for k, v in tokens.items() if v["type"] == "duration"}

    lines = [HEADER, "import CoreGraphics", "import Foundation", ""]
    lines.append("/// 设计合同里的一枚颜色令牌。")
    lines.append("///")
    lines.append("/// 值是合同里的十六进制字符串，浅色与深色各一份。")
    lines.append("/// `MacTheme` 负责把它转成随外观变化的颜色。")
    lines.append("struct ContractColor: Sendable, Equatable {")
    lines.append("    let key: String")
    lines.append("    let lightHex: String")
    lines.append("    let darkHex: String")
    lines.append("}")
    lines.append("")
    lines.append("/// 设计合同 `tokens` 段里的颜色。`token/art/*` 是插图用的装饰色，不在这里。")
    lines.append("enum ContractColors {")
    names = []
    for key in sorted(colors):
        value = colors[key]
        name = identifier(key)
        names.append(name)
        lines.append(f"    /// `{key}` — {value.get('purpose', '')}")
        lines.append(
            f"    static let {name} = ContractColor("
            f"key: {swift_string(key)}, "
            f"lightHex: {swift_string(value['light'])}, "
            f"darkHex: {swift_string(value['dark'])})"
        )
    lines.append("")
    lines.append("    static let all: [ContractColor] = [")
    for name in names:
        lines.append(f"        {name},")
    lines.append("    ]")
    lines.append("}")
    lines.append("")

    lines.append("/// 设计合同 `tokens` 段里的尺寸。半径、间距、材质不透明度。")
    lines.append("enum ContractDimensions {")
    names = []
    for key in sorted(dimensions):
        value = dimensions[key]
        name = identifier(key)
        names.append(name)
        lines.append(f"    /// `{key}` — {value.get('purpose', '')}")
        lines.append(f"    static let {name}: CGFloat = {value['light']}")
    lines.append("")
    lines.append("    /// 键名与取值的对照。供测试遍历。")
    lines.append("    static let all: [String: CGFloat] = [")
    for key in sorted(dimensions):
        lines.append(f"        {swift_string(key)}: {identifier(key)},")
    lines.append("    ]")
    lines.append("}")
    lines.append("")

    lines.append("/// 设计合同 `tokens` 段里的一枚动效令牌。")
    lines.append("///")
    lines.append("/// 时长单位是秒，与 `TimeInterval` 一致。合同里写的是毫秒。")
    lines.append("/// `curve` 是曲线的中文描述。")
    lines.append("/// `reducedSeconds` 只在合同写了 `reducedMotionMs` 时有值。")
    lines.append("struct ContractMotionToken: Sendable, Equatable {")
    lines.append("    let key: String")
    lines.append("    let seconds: TimeInterval")
    lines.append("    let minSeconds: TimeInterval")
    lines.append("    let maxSeconds: TimeInterval")
    lines.append("    let reducedSeconds: TimeInterval?")
    lines.append("    let curve: String")
    lines.append("}")
    lines.append("")
    lines.append("/// 设计合同 `tokens` 段里的动效时长。")
    lines.append("enum ContractMotion {")
    names = []
    for key in sorted(motion):
        value = motion[key]
        name = identifier(key)
        names.append(name)
        reduced = value.get("reducedMotionMs")
        reduced_text = "nil" if reduced is None else f"{reduced / 1000}"
        lines.append(f"    /// `{key}` — {value.get('purpose', '')}")
        lines.append(
            f"    static let {name} = ContractMotionToken("
            f"key: {swift_string(key)}, "
            f"seconds: {value['durationMs'] / 1000}, "
            f"minSeconds: {value['minMs'] / 1000}, "
            f"maxSeconds: {value['maxMs'] / 1000}, "
            f"reducedSeconds: {reduced_text}, "
            f"curve: {swift_string(value['curve'])})"
        )
    lines.append("")
    lines.append("    /// 全部条目。供测试遍历。")
    lines.append("    static let all: [ContractMotionToken] = [")
    for name in names:
        lines.append(f"        {name},")
    lines.append("    ]")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def generate_rust_motion(contract: dict) -> str:
    motion = {
        key: value
        for key, value in contract["tokens"].items()
        if value["type"] == "duration"
    }

    lines = [
        "// This file is generated by scripts/generate-contract-constants.py. Do not edit it by hand.",
        "// Source of truth: macOS/iOS Apple design.",
        "// docs/covio-design-contract.json is the machine-readable projection.",
        "",
        "use std::time::Duration;",
        "",
        "// Motion durations generated from the shared design contract.",
        "",
    ]
    names = []
    for key in sorted(motion):
        value = motion[key]
        name = rust_identifier(key)
        names.append((key, name))
        lines.append(f"/// `{key}`: {value.get('purpose', '')}")
        lines.append(f"pub const {name}: Duration = {rust_duration(value['durationMs'])};")
        lines.append("")

    lines.append("/// Motion tokens paired with their contract keys.")
    lines.append(
        f"pub const MOTION_DURATIONS: [(&str, Duration); {len(names)}] = ["
    )
    for key, name in names:
        lines.append(f'    ("{key}", {name}),')
    lines.append("];")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="不写文件，只报告是否有差异")
    args = parser.parse_args()

    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    outputs = {
        COPY_OUT: generate_copy(contract),
        TOKENS_OUT: generate_tokens(contract),
        RUST_MOTION_OUT: generate_rust_motion(contract),
    }

    if args.check:
        stale = [
            path
            for path, text in outputs.items()
            if not path.exists() or path.read_text(encoding="utf-8") != text
        ]
        if stale:
            for path in stale:
                print(f"stale: {path.relative_to(ROOT)}", file=sys.stderr)
            print(
                "重跑 python3 scripts/generate-contract-constants.py 重新生成。",
                file=sys.stderr,
            )
            return 1
        print(f"合同常量是最新的：{len(outputs)} 个文件，{len(contract['copy'])} 条文案。")
        return 0

    for path, text in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

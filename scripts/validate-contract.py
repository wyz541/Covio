#!/usr/bin/env python3
"""校验设计合同的结构与跨段一致性。

schema 管得住形状，管不住跨段的一致性。这个脚本补上 schema 表达不了的那些规则：

1. macOS 下每个组件必须有 `swiftMapping`。
   schema 的 `required` 是全局的，写不出「只在某个平台必填」。
2. `platformMapping[*].swiftRuntimeTarget` 必须与对应组件的 `swiftMapping.target` 一致。
3. `copy` 段的每个键都要被某个 `states` 条目或组件引用，反向也要成立。
4. `tokens` 段的键前缀必须在允许的集合里。
5. `metadata.counts` 的数字要与合同的真实长度一致。
6. macOS 宿主的源码里不许手写文案，只许读生成的 `ContractCopy`。
7. 合同不得保留 Compose 或 Kotlin 产品映射。

用法：
    python3 scripts/validate-contract.py            校验，失败退出码 1
不使用第三方库，只用标准库。

**注意：** 这个脚本不做 JSON Schema 校验。完整的 Draft 2020-12 校验交给
`.git/covio-figma/` 里的工具链。这里只补跨段规则。
"""

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "docs" / "covio-design-contract.json"

# 运行时会读合同的平台。每个平台都有自己的必填项。
PLATFORMS = ("macos",)

# 宿主源码里允许出现 `LocalizedCopy(` 的文件，相对仓库根。
# 前者是生成文件，后者定义类型本身。两个都不写产品文案。
COPY_LITERAL_ALLOWED = (
    "macosApp/src/Design/ContractCopy.swift",
    "macosApp/src/Design/LocalizedCopy.swift",
)

TOKEN_PREFIXES = ("token/art/", "token/color/", "token/radius/", "token/size/",
                  "token/space/", "token/material/", "token/motion/")

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def check_swift_mapping(contract: dict) -> None:
    """规则 1 与 2：macOS 的落点必须写全，且两处说法要一致。"""
    components = contract.get("components", {})
    if not components:
        fail("components 是空的")

    for key, component in components.items():
        mapping = component.get("swiftMapping")
        if not isinstance(mapping, dict):
            fail(f"{key} 缺 swiftMapping。macOS 下每个组件都要有 Swift 落点")
            continue
        for field in ("target", "behavior"):
            if not mapping.get(field):
                fail(f"{key}.swiftMapping.{field} 是空的")

    platform = contract.get("platformMapping", {})
    if not platform:
        fail("platformMapping 是空的")

    for key, entry in platform.items():
        target = entry.get("swiftRuntimeTarget")
        if not target:
            fail(f"{key} 缺 swiftRuntimeTarget")
            continue
        if not key.startswith("platform/component/"):
            continue
        component_key = key[len("platform/"):]
        expected = components.get(component_key, {}).get("swiftMapping", {}).get("target")
        if expected is not None and target != expected:
            fail(f"{key}.swiftRuntimeTarget 是 {target!r}，{component_key} 的落点是 {expected!r}")


def check_states(contract: dict) -> None:
    """状态机映射表要指向真实文件。写错路径的映射等于没写。"""
    mapping = contract.get("states", {}).get("swiftRuntimeMapping")
    if not isinstance(mapping, dict):
        fail("states 缺 swiftRuntimeMapping")
        return

    for key, entry in mapping.items():
        path = entry.get("path")
        if not path:
            fail(f"states.swiftRuntimeMapping.{key} 缺 path")
            continue
        if not (ROOT / path).exists():
            fail(f"states.swiftRuntimeMapping.{key}.path 指向的文件不存在：{path}")
        if not entry.get("target"):
            fail(f"states.swiftRuntimeMapping.{key} 缺 target")
        if not entry.get("behavior"):
            fail(f"states.swiftRuntimeMapping.{key} 缺 behavior")


def referenced_copy_keys(contract: dict) -> set[str]:
    """扫出所有被引用的文案键。

    引用可能出现在任何一层，所以直接递归找 `copyKey` 与 `contractKey` 之外的
    `copy/` 前缀字符串。用递归而不用枚举，是为了加了新段之后不用改这里。
    """
    found: set[str] = set()

    def walk(node) -> None:
        if isinstance(node, dict):
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)
        elif isinstance(node, str) and node.startswith("copy/"):
            found.add(node)

    walk(contract)
    return found


def check_copy(contract: dict) -> None:
    """规则 3：合同内部引用的文案键必须存在。

    只查这一个方向。反方向查不了：`copy` 段的键主要由代码引用
    （生成的 `ContractCopy.swift`），合同里没有引用点。
    代码那一侧由规则 6 与 `ContractConstantsTests` 保证。
    """
    copy = contract.get("copy", {})
    if not copy:
        fail("copy 是空的")
        return

    for key, entry in copy.items():
        if not key.startswith("copy/"):
            fail(f"{key} 不以 copy/ 开头")
        for field in ("en", "zh-Hans"):
            if not entry.get(field):
                fail(f"{key}.{field} 是空的")

    for key in sorted(referenced_copy_keys(contract) - set(copy)):
        fail(f"{key} 被引用了，但 copy 段里没有这个键")


def check_tokens(contract: dict) -> None:
    """规则 4：令牌的键前缀与前缀对应的形状。"""
    tokens = contract.get("tokens", {})
    if not tokens:
        fail("tokens 是空的")
        return

    for key, token in tokens.items():
        if not key.startswith(TOKEN_PREFIXES):
            fail(f"{key} 的前缀不在允许的集合里：{TOKEN_PREFIXES}")
            continue
        kind = token.get("type")
        if key.startswith("token/motion/"):
            if kind != "duration":
                fail(f"{key} 是动效令牌，type 应为 duration，实际是 {kind!r}")
                continue
            for field in ("durationMs", "minMs", "maxMs", "curve", "purpose"):
                if token.get(field) is None:
                    fail(f"{key} 缺 {field}")
            low, value, high = token.get("minMs"), token.get("durationMs"), token.get("maxMs")
            if None not in (low, value, high) and not low <= value <= high:
                fail(f"{key} 的范围不成立：minMs={low} durationMs={value} maxMs={high}")
            reduced = token.get("reducedMotionMs")
            if reduced is not None and value is not None and reduced > value:
                fail(f"{key} 的 reducedMotionMs={reduced} 比 durationMs={value} 还长")
        else:
            if kind not in ("color", "dimension"):
                fail(f"{key} 的 type 应为 color 或 dimension，实际是 {kind!r}")
                continue
            for field in ("light", "dark", "purpose"):
                if token.get(field) is None:
                    fail(f"{key} 缺 {field}")


def check_counts(contract: dict) -> None:
    """规则 5：能从合同算出来的计数要与合同写的数字一致。

    只查 `componentSets`。其余计数（`pages`、`boards`、`textNodes`、
    `variables` 等）是 Figma 侧的数字，合同里算不出来。
    `variables` 是 Figma 变量的条数，动效令牌没有 Figma 变量，所以两者不相等。
    """
    counts = contract.get("metadata", {}).get("counts")
    if not isinstance(counts, dict):
        fail("metadata 缺 counts")
        return

    actual = len(contract.get("components", {}))
    if "componentSets" in counts and counts["componentSets"] != actual:
        fail(f"metadata.counts.componentSets 是 {counts['componentSets']}，实际是 {actual}")


def check_no_hand_written_copy() -> None:
    """规则 6：宿主源码里不许手写文案。

    文案只有一个来源：合同。生成文件与 `LocalizedCopy.swift`（类型定义）之外
    出现 `LocalizedCopy(` 就说明有人绕过了合同，改文案时两边会漂移。

    同一份检查也在 `macosApp/test/CopySingleSourceTests.swift` 里。
    """
    for path in sorted((ROOT / "macosApp").rglob("*.swift")):
        relative = path.relative_to(ROOT).as_posix()
        if relative in COPY_LITERAL_ALLOWED:
            continue
        text = path.read_text(encoding="utf-8")
        for number, line in enumerate(text.splitlines(), 1):
            if "LocalizedCopy(" in line:
                fail(f"{relative}:{number} 手写了文案。文案要读 ContractCopy")


def check_legacy_product_mappings_absent(contract: dict) -> None:
    """规则 7：已删除的 Kotlin 产品路径不能继续出现在合同里。"""
    metadata = contract.get("metadata", {})
    if "kotlinInterfaces" in metadata:
        fail("metadata.kotlinInterfaces 已删除，不能再声明 Kotlin 产品接口")

    for key, component in contract.get("components", {}).items():
        if "composeMapping" in component:
            fail(f"{key}.composeMapping 已删除，不能再声明 Compose 落点")


def main() -> int:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))

    check_swift_mapping(contract)
    check_states(contract)
    check_copy(contract)
    check_tokens(contract)
    check_counts(contract)
    check_no_hand_written_copy()
    check_legacy_product_mappings_absent(contract)

    if errors:
        for message in errors:
            print(f"合同校验失败：{message}", file=sys.stderr)
        print(f"{len(errors)} 条问题。", file=sys.stderr)
        return 1

    print(
        f"合同校验通过：{len(contract['components'])} 个组件，"
        f"{len(contract['platformMapping'])} 条平台映射，"
        f"{len(contract['copy'])} 条文案，"
        f"{len(contract['tokens'])} 枚令牌。"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

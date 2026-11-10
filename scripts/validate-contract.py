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
7. 平台字体、排版、语义角色、焦序、覆盖和验收 ID 必须互相引用真实键。
8. 已删除的 KMP shared module 和组件级 Compose 映射不能恢复。

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
SCHEMA = ROOT / "docs" / "covio-design-contract.schema.json"

# 合同覆盖的平台。Apple 是设计权威，Windows 是第一版 Compose 目标。
PLATFORMS = {"macos", "ios", "windows", "android"}

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


def check_schema_version(contract: dict) -> None:
    """合同版本必须与 schema 固定版本一致。"""
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    expected = schema.get("properties", {}).get("schemaVersion", {}).get("const")
    actual = contract.get("schemaVersion")
    if actual != expected:
        fail(f"schemaVersion 是 {actual!r}，schema 要求 {expected!r}")
    for key in schema.get("required", []):
        if key not in contract:
            fail(f"合同缺 schema 必需段：{key}")


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
    """规则 8：已删除的 Kotlin 产品路径不能继续出现在合同里。"""
    metadata = contract.get("metadata", {})
    if "kotlinInterfaces" in metadata:
        fail("metadata.kotlinInterfaces 已删除，不能再声明 Kotlin 产品接口")

    for key, component in contract.get("components", {}).items():
        if "composeMapping" in component:
            fail(f"{key}.composeMapping 已删除，不能再声明 Compose 落点")


def contract_keys(contract: dict) -> set[str]:
    """收集合同里所有带段前缀的稳定键。"""
    found: set[str] = set()

    def walk(node) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if "/" in key:
                    found.add(key)
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(contract)
    return found


def check_platform_fonts(contract: dict) -> None:
    """规则 7：每个平台都要有唯一字体映射。"""
    fonts = contract.get("platformFonts")
    if not isinstance(fonts, dict) or not fonts:
        fail("platformFonts 是空的")
        return

    seen: dict[tuple[str, str], str] = {}
    for key, entry in fonts.items():
        if not key.startswith("font/"):
            fail(f"{key} 不以 font/ 开头")
        platforms = entry.get("platforms", [])
        role = entry.get("role")
        for platform in platforms:
            if platform not in PLATFORMS:
                fail(f"{key} 声明未知平台 {platform}")
                continue
            pair = (platform, role)
            if pair in seen:
                fail(f"{platform} 的 {role} 字体重复：{seen[pair]} 与 {key}")
            seen[pair] = key
        if not entry.get("family") or not entry.get("usage"):
            fail(f"{key} 缺 family 或 usage")

    required = {
        ("macos", "interface"): "SF Pro",
        ("ios", "interface"): "SF Pro",
        ("windows", "interface"): "Segoe UI Variable",
        ("android", "interface"): "Roboto",
    }
    for pair, family in required.items():
        key = seen.get(pair)
        if key is None:
            fail(f"缺平台字体映射：{pair[0]} {pair[1]}")
            continue
        entry = fonts[key]
        if entry.get("family") != family:
            fail(f"{key}.family 是 {entry.get('family')!r}，应为 {family!r}")
        if pair[0] == "windows" and "SF Pro" in entry.get("family", ""):
            fail("Windows 不得使用 SF Pro")

    windows = fonts.get(seen.get(("windows", "interface"), ""), {})
    if windows:
        files = windows.get("fileNames", [])
        if not files or files[0] != "SegUIVar.ttf":
            fail("Windows 字体首选文件应为 SegUIVar.ttf")
        if "Segoe UI" not in windows.get("fallbackFamilies", []):
            fail("Windows 字体必须声明 Segoe UI 回退")
    android = fonts.get(seen.get(("android", "interface"), ""), {})
    if android and android.get("status") != "deferred":
        fail("Android 字体在第一版必须标记 deferred")


def check_typography(contract: dict) -> None:
    """规则 7：排版令牌必须有可用字号、行高和字体角色。"""
    typography = contract.get("typography")
    if not isinstance(typography, dict) or not typography:
        fail("typography 是空的")
        return

    fonts = contract.get("platformFonts", {})
    roles = {
        entry.get("role")
        for entry in fonts.values()
        if "windows" in entry.get("platforms", [])
    }
    for key, entry in typography.items():
        if not key.startswith("typography/"):
            fail(f"{key} 不以 typography/ 开头")
        size = entry.get("size")
        line_height = entry.get("lineHeight")
        if not isinstance(size, (int, float)) or size <= 0:
            fail(f"{key}.size 必须大于 0")
        if not isinstance(line_height, (int, float)) or line_height < size:
            fail(f"{key}.lineHeight 必须不小于 size")
        if entry.get("fontRole") not in roles:
            fail(f"{key}.fontRole={entry.get('fontRole')!r} 没有 Windows 字体映射")
        if entry.get("weight") not in ("regular", "medium", "semibold", "bold"):
            fail(f"{key}.weight 不支持：{entry.get('weight')!r}")


def check_semantic_roles(contract: dict) -> None:
    """规则 7：语义角色必须引用真实令牌、排版和验收项。"""
    roles = contract.get("semanticRoles")
    if not isinstance(roles, dict) or not roles:
        fail("semanticRoles 是空的")
        return

    tokens = contract.get("tokens", {})
    typography = contract.get("typography", {})
    acceptance = contract.get("acceptanceCriteria", {})
    categories = {"text", "surface", "action", "status", "focus", "navigation"}
    for key, entry in roles.items():
        if not key.startswith("role/"):
            fail(f"{key} 不以 role/ 开头")
        if entry.get("category") not in categories:
            fail(f"{key}.category 不支持：{entry.get('category')!r}")
        for token_key in entry.get("tokenKeys", []):
            if token_key not in tokens:
                fail(f"{key}.tokenKeys 引用了不存在的 {token_key}")
        typography_key = entry.get("typographyKey")
        if typography_key and typography_key not in typography:
            fail(f"{key}.typographyKey 引用了不存在的 {typography_key}")
        for acceptance_id in entry.get("acceptanceIds", []):
            if acceptance_id not in acceptance:
                fail(f"{key}.acceptanceIds 引用了不存在的 {acceptance_id}")
        if not entry.get("accessibilityRole") or not entry.get("behavior"):
            fail(f"{key} 缺 accessibilityRole 或 behavior")

    required = {
        "role/text/primary",
        "role/surface/canvas",
        "role/action/primary",
        "role/status/error",
        "role/focus/ring",
    }
    for key in sorted(required - set(roles)):
        fail(f"缺必需语义角色：{key}")


def check_focus_order(contract: dict) -> None:
    """规则 7：焦序必须连续、可定位且引用真实组件。"""
    focus = contract.get("focusOrder")
    if not isinstance(focus, dict) or not focus:
        fail("focusOrder 是空的")
        return

    components = contract.get("components", {})
    acceptance = contract.get("acceptanceCriteria", {})
    step_ids: set[str] = set()
    has_trap = False
    for key, entry in focus.items():
        if not key.startswith("focus/"):
            fail(f"{key} 不以 focus/ 开头")
        steps = entry.get("steps", [])
        if not steps:
            fail(f"{key} 没有焦点步骤")
            continue
        orders = [step.get("order") for step in steps]
        if orders != list(range(1, len(steps) + 1)):
            fail(f"{key} 的 order 必须从 1 连续排列：{orders}")
        for step in steps:
            step_id = step.get("id", "")
            if not step_id.startswith("focus/") or step_id in step_ids:
                fail(f"{key} 的焦点步骤 ID 无效或重复：{step_id!r}")
            step_ids.add(step_id)
            if step.get("componentKey") not in components:
                fail(f"{step_id}.componentKey 引用了不存在的 {step.get('componentKey')}")
            if not step.get("elementKey") or not step.get("behavior"):
                fail(f"{step_id} 缺 elementKey 或 behavior")
        if entry.get("trapFocus"):
            has_trap = True
            if not entry.get("restoreFocus"):
                fail(f"{key} 捕获焦点时必须恢复焦点")
        for acceptance_id in entry.get("acceptanceIds", []):
            if acceptance_id not in acceptance:
                fail(f"{key}.acceptanceIds 引用了不存在的 {acceptance_id}")

    if not has_trap:
        fail("focusOrder 至少需要一个捕获并恢复焦点的模态作用域")


def check_platform_overrides(contract: dict) -> None:
    """规则 7：平台覆盖必须可追溯到合同键、文件证据和 Issue。"""
    overrides = contract.get("platformOverrides")
    if not isinstance(overrides, dict) or not overrides:
        fail("platformOverrides 是空的")
        return

    keys = contract_keys(contract)
    acceptance = contract.get("acceptanceCriteria", {})
    for key, entry in overrides.items():
        if not key.startswith("override/"):
            fail(f"{key} 不以 override/ 开头")
        if entry.get("platform") not in PLATFORMS:
            fail(f"{key}.platform 不支持：{entry.get('platform')!r}")
        if entry.get("contractKey") not in keys:
            fail(f"{key}.contractKey 引用了不存在的 {entry.get('contractKey')}")
        if entry.get("status") not in ("required", "deferred"):
            fail(f"{key}.status 不支持：{entry.get('status')!r}")
        if not isinstance(entry.get("issue"), int) or entry.get("issue", 0) <= 0:
            fail(f"{key}.issue 必须是正整数")
        evidence = entry.get("evidence", [])
        if not evidence:
            fail(f"{key} 没有证据")
        for path in evidence:
            if not (ROOT / path).exists():
                fail(f"{key}.evidence 指向的文件不存在：{path}")
        for acceptance_id in entry.get("acceptanceIds", []):
            if acceptance_id not in acceptance:
                fail(f"{key}.acceptanceIds 引用了不存在的 {acceptance_id}")

    for required in ("override/windows/interface-font", "override/windows/material"):
        if required not in overrides:
            fail(f"缺必需平台覆盖：{required}")


def check_acceptance_criteria(contract: dict) -> None:
    """规则 7：验收 ID 必须唯一，且引用真实合同键。"""
    criteria = contract.get("acceptanceCriteria")
    if not isinstance(criteria, dict) or not criteria:
        fail("acceptanceCriteria 是空的")
        return

    keys = contract_keys(contract)
    kinds: set[str] = set()
    for key, entry in criteria.items():
        if not key.startswith("acceptance/"):
            fail(f"{key} 不以 acceptance/ 开头")
        kind = entry.get("kind")
        if kind not in ("visual", "behavior"):
            fail(f"{key}.kind 不支持：{kind!r}")
        else:
            kinds.add(kind)
        platforms = entry.get("platforms", [])
        if not platforms:
            fail(f"{key} 没有平台")
        for platform in platforms:
            if platform not in PLATFORMS:
                fail(f"{key} 声明未知平台 {platform}")
        for contract_key in entry.get("contractKeys", []):
            if contract_key not in keys:
                fail(f"{key}.contractKeys 引用了不存在的 {contract_key}")
        if not entry.get("criteria") or not entry.get("evidence"):
            fail(f"{key} 缺 criteria 或 evidence")

    if kinds != {"visual", "behavior"}:
        fail(f"验收项必须同时包含 visual 和 behavior，实际是 {sorted(kinds)}")


def main() -> int:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))

    check_swift_mapping(contract)
    check_states(contract)
    check_copy(contract)
    check_tokens(contract)
    check_counts(contract)
    check_schema_version(contract)
    check_no_hand_written_copy()
    check_platform_fonts(contract)
    check_typography(contract)
    check_semantic_roles(contract)
    check_focus_order(contract)
    check_platform_overrides(contract)
    check_acceptance_criteria(contract)
    check_legacy_product_mappings_absent(contract)

    if errors:
        for message in errors:
            print(f"合同校验失败：{message}", file=sys.stderr)
        print(f"{len(errors)} 条问题。", file=sys.stderr)
        return 1

    print(
        f"合同校验通过：{len(contract['components'])} 个组件，"
        f"{len(contract['platformMapping'])} 条平台映射，"
        f"{len(contract['platformFonts'])} 个平台字体，"
        f"{len(contract['acceptanceCriteria'])} 个验收项，"
        f"{len(contract['copy'])} 条文案，"
        f"{len(contract['tokens'])} 枚令牌。"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

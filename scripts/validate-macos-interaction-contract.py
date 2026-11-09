#!/usr/bin/env python3
"""Validate the macOS interaction contract and its deterministic JSON export."""

from collections import OrderedDict
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "docs" / "macos-interaction-contract.json"
SCHEMA = ROOT / "docs" / "macos-interaction-contract.schema.json"
DESIGN_CONTRACT = ROOT / "docs" / "covio-design-contract.json"

WINDOWS_OVERRIDE_FIELDS = {
    "trigger.cooldownMs",
    "trigger.dwellMs",
    "trigger.geometry.centeredHalfWidthPercent",
    "trigger.geometry.topEdgeThicknessPixels",
}

REQUIRED_WINDOWS_OVERRIDE_FIELDS = WINDOWS_OVERRIDE_FIELDS

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def load(path: Path):
    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=OrderedDict,
    )


def resolve_ref(root: dict, ref: str):
    if not ref.startswith("#/"):
        fail(f"unsupported schema reference: {ref}")
        return {}
    node = root
    for part in ref[2:].split("/"):
        node = node.get(part, {})
    return node


def is_type(value, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    fail(f"unsupported schema type: {expected}")
    return True


def validate(instance, schema: dict, root: dict, path: str = "$") -> None:
    if "$ref" in schema:
        validate(instance, resolve_ref(root, schema["$ref"]), root, path)
        return

    if "const" in schema and instance != schema["const"]:
        fail(f"{path}: expected {schema['const']!r}, got {instance!r}")
    if "enum" in schema and instance not in schema["enum"]:
        fail(f"{path}: {instance!r} is not one of {schema['enum']!r}")

    expected_type = schema.get("type")
    if expected_type and not is_type(instance, expected_type):
        fail(f"{path}: expected {expected_type}, got {type(instance).__name__}")
        return

    if isinstance(instance, dict):
        required = schema.get("required", [])
        for key in required:
            if key not in instance:
                fail(f"{path}: missing required key {key!r}")
        properties = schema.get("properties", {})
        for key, value in instance.items():
            child_path = f"{path}.{key}"
            if key in properties:
                validate(value, properties[key], root, child_path)
            elif schema.get("additionalProperties") is False:
                fail(f"{child_path}: unexpected key")

    if isinstance(instance, list):
        minimum = schema.get("minItems")
        if minimum is not None and len(instance) < minimum:
            fail(f"{path}: needs at least {minimum} items")
        if schema.get("uniqueItems"):
            encoded = [json.dumps(item, sort_keys=True) for item in instance]
            if len(encoded) != len(set(encoded)):
                fail(f"{path}: duplicate items")
        item_schema = schema.get("items")
        if item_schema:
            for index, value in enumerate(instance):
                validate(value, item_schema, root, f"{path}[{index}]")

    if isinstance(instance, str):
        minimum = schema.get("minLength")
        if minimum is not None and len(instance) < minimum:
            fail(f"{path}: needs at least {minimum} characters")
        pattern = schema.get("pattern")
        if pattern and re.search(pattern, instance) is None:
            fail(f"{path}: does not match {pattern!r}")

    if isinstance(instance, (int, float)) and not isinstance(instance, bool):
        minimum = schema.get("minimum")
        if minimum is not None and instance < minimum:
            fail(f"{path}: {instance} is below {minimum}")
        exclusive = schema.get("exclusiveMinimum")
        if exclusive is not None and instance <= exclusive:
            fail(f"{path}: {instance} must be greater than {exclusive}")
        maximum = schema.get("maximum")
        if maximum is not None and instance > maximum:
            fail(f"{path}: {instance} is above {maximum}")


def check_sorted_keys(node, path: str = "$") -> None:
    if isinstance(node, dict):
        keys = list(node.keys())
        if keys != sorted(keys):
            fail(f"{path}: object keys are not sorted")
        for key, value in node.items():
            check_sorted_keys(value, f"{path}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            check_sorted_keys(value, f"{path}[{index}]")


def design_token(contract: dict, key: str) -> dict:
    token = contract.get("tokens", {}).get(key)
    if not isinstance(token, dict):
        fail(f"design contract is missing {key}")
        return {}
    return token


def check_design_contract_parity(contract: dict, design: dict) -> None:
    checks = (
        (
            "trigger.pointerExitCollapseMs",
            contract["trigger"]["pointerExitCollapseMs"],
            design_token(design, "token/motion/pointer-exit-collapse").get("durationMs"),
        ),
        (
            "reveal.durationMs",
            contract["reveal"]["durationMs"],
            design_token(design, "token/motion/hub-expand").get("durationMs"),
        ),
        (
            "conceal.durationMs",
            contract["conceal"]["durationMs"],
            design_token(design, "token/motion/hub-collapse").get("durationMs"),
        ),
        (
            "reducedMotion.durationMs",
            contract["reducedMotion"]["durationMs"],
            design_token(design, "token/motion/reduced-motion").get("durationMs"),
        ),
        (
            "geometry.panelWidthPoints",
            contract["geometry"]["panelWidthPoints"],
            design.get("components", {})
            .get("component/tab-bar", {})
            .get("nativeSize", {})
            .get("width"),
        ),
        (
            "geometry.panelCornerRadiusPoints",
            contract["geometry"]["panelCornerRadiusPoints"],
            design_token(design, "token/radius/panel").get("light"),
        ),
    )
    for field, actual, expected in checks:
        if actual != expected:
            fail(f"{field}: interaction contract has {actual!r}, design contract has {expected!r}")


def check_behavior(contract: dict) -> None:
    if contract["reveal"]["direction"] != "topToBottom":
        fail("reveal.direction must be topToBottom")
    if contract["conceal"]["direction"] != "bottomToTop":
        fail("conceal.direction must be bottomToTop")
    reveal_easing = contract["reveal"]["easing"]
    if reveal_easing["type"] != "spring":
        fail("reveal.easing.type must be spring")
    for key in ("responseSeconds", "dampingFraction"):
        if key not in reveal_easing:
            fail(f"reveal.easing is missing {key}")
    if contract["conceal"]["easing"]["type"] != "easeOut":
        fail("conceal.easing.type must be easeOut")

    overrides = contract["platformOverrides"]
    override_ids = [entry["id"] for entry in overrides]
    if len(override_ids) != len(set(override_ids)):
        fail("platformOverrides contains duplicate ids")
    override_field_list = [entry["field"] for entry in overrides]
    override_fields = set(override_field_list)
    if len(override_fields) != len(override_field_list):
        fail("platformOverrides contains duplicate fields")
    unknown_fields = override_fields - WINDOWS_OVERRIDE_FIELDS
    if unknown_fields:
        fail(f"platformOverrides contains unknown fields: {sorted(unknown_fields)}")
    missing_fields = REQUIRED_WINDOWS_OVERRIDE_FIELDS - override_fields
    if missing_fields:
        fail(f"platformOverrides is missing Windows fields: {sorted(missing_fields)}")
    for entry in overrides:
        field = entry["field"]
        value = entry["value"]
        if field in {"trigger.dwellMs", "trigger.cooldownMs"} and value < 0:
            fail(f"{field} must not be negative")
        if field == "trigger.geometry.centeredHalfWidthPercent" and not 0 < value <= 50:
            fail(f"{field} must be in (0, 50]")
        if field == "trigger.geometry.topEdgeThicknessPixels" and value <= 0:
            fail(f"{field} must be positive")


def main() -> int:
    contract = load(CONTRACT)
    schema = load(SCHEMA)
    design = load(DESIGN_CONTRACT)

    validate(contract, schema, schema)
    valid_shape = not errors
    check_sorted_keys(contract)
    contract_text = CONTRACT.read_text(encoding="utf-8")
    if not contract_text.endswith("\n"):
        fail("contract JSON must end with a newline")
    if re.search(r'^\s*"[^"]+":', contract_text, re.MULTILINE):
        fail("contract JSON must use Swift JSONEncoder spacing around colons")

    if valid_shape and isinstance(contract, dict):
        check_behavior(contract)
        check_design_contract_parity(contract, design)

    if errors:
        for error in errors:
            print(f"interaction contract error: {error}", file=sys.stderr)
        return 1

    print("macOS interaction contract validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

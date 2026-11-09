#!/usr/bin/env python3
"""Generate shared Workbench interaction conformance vectors from the contract."""

import argparse
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "docs" / "macos-interaction-contract.json"
OUTPUT = ROOT / "docs" / "macos-interaction-contract.vectors.json"

SAMPLES = (0.0, 0.25, 0.5, 0.75, 1.0)
TOLERANCE = 0.002
DISPLAY = {"height": 1440.0, "left": 0.0, "top": 0.0, "width": 2560.0}
REQUIRED_CONTRACT_KEYS = {
    "contractId",
    "conceal.direction",
    "conceal.durationMs",
    "conceal.easing",
    "geometry.panelCornerRadiusPoints",
    "geometry.panelWidthPoints",
    "platformOverrides",
    "reducedMotion.durationMs",
    "reducedMotion.effect",
    "reveal.direction",
    "reveal.durationMs",
    "reveal.easing",
    "schemaVersion",
    "trigger.cooldownMs",
    "trigger.dwellMs",
    "trigger.geometry.alignment",
    "trigger.geometry.centeredHalfWidthPercent",
    "trigger.geometry.displaySelection",
    "trigger.geometry.notchedDisplay",
    "trigger.geometry.notchlessDisplay",
    "trigger.geometry.notchlessHeightPoints",
    "trigger.geometry.notchlessWidthPoints",
    "trigger.geometry.topEdgeThicknessPixels",
    "trigger.pointerExitCollapseMs",
}
EXPECTED_OBJECT_KEYS = {
    "root": {
        "conceal",
        "contractId",
        "geometry",
        "platformOverrides",
        "reducedMotion",
        "reveal",
        "schemaVersion",
        "trigger",
    },
    "trigger": {"cooldownMs", "dwellMs", "geometry", "pointerExitCollapseMs"},
    "trigger.geometry": {
        "alignment",
        "displaySelection",
        "notchedDisplay",
        "notchlessDisplay",
        "notchlessHeightPoints",
        "notchlessWidthPoints",
    },
    "transition": {"direction", "durationMs", "easing"},
    "geometry": {"panelCornerRadiusPoints", "panelWidthPoints"},
    "reducedMotion": {"durationMs", "effect"},
    "override": {"evidence", "field", "id", "platform", "reason", "value"},
}

PREVIEW = "docs/design/previews/719-windows-contract-parity/README.md"
EVIDENCE = {
    "contract": ["docs/macos-interaction-contract.json", "docs/macos-interaction-contract.schema.json"],
    "trigger": ["docs/design/windows-triggers.md", "rust/apps/covio-windows/src/top_edge.rs"],
    "runtime": [
        "rust/crates/covio-core/src/workbench_interaction_runtime.rs",
        "rust/apps/covio-windows/src/top_edge.rs",
    ],
    "geometry": ["rust/apps/covio-windows/src/visuals.rs", PREVIEW],
}


def validate_contract_shape(contract: dict) -> None:
    checks = (
        ("root", set(contract)),
        ("trigger", set(contract["trigger"])),
        ("trigger.geometry", set(contract["trigger"]["geometry"])),
        ("reveal", set(contract["reveal"])),
        ("conceal", set(contract["conceal"])),
        ("reveal.easing", set(contract["reveal"]["easing"])),
        ("conceal.easing", set(contract["conceal"]["easing"])),
        ("geometry", set(contract["geometry"])),
        ("reducedMotion", set(contract["reducedMotion"])),
    )
    expected = dict(EXPECTED_OBJECT_KEYS)
    expected["reveal"] = expected["transition"]
    expected["conceal"] = expected["transition"]
    expected["reveal.easing"] = {"dampingFraction", "responseSeconds", "type"}
    expected["conceal.easing"] = {"type"}
    for name, actual in checks:
        if actual != expected[name]:
            raise ValueError(
                f"contract shape changed at {name}: expected {sorted(expected[name])}, "
                f"got {sorted(actual)}"
            )
    for entry in contract["platformOverrides"]:
        if set(entry) != EXPECTED_OBJECT_KEYS["override"]:
            raise ValueError("platform override shape changed; update vector coverage")


def override_value(contract: dict, field: str) -> float:
    for entry in contract["platformOverrides"]:
        if entry["field"] == field:
            return float(entry["value"])
    raise ValueError(f"missing Windows override: {field}")


def spring_progress(response_seconds: float, damping_fraction: float, time: float) -> float:
    angular_frequency = 2 * math.pi / response_seconds
    decay = math.exp(-damping_fraction * angular_frequency * time)
    if damping_fraction < 1:
        damped_frequency = angular_frequency * math.sqrt(1 - damping_fraction**2)
        cosine = math.cos(damped_frequency * time)
        sine = math.sin(damped_frequency * time)
        return 1 - decay * (
            cosine + damping_fraction * angular_frequency / damped_frequency * sine
        )
    return 1 - decay * (1 + angular_frequency * time)


def easing_progress(easing: dict, duration_seconds: float, normalized_time: float) -> float:
    time = min(max(normalized_time, 0.0), 1.0)
    if time <= 0:
        return 0.0
    if time >= 1:
        return 1.0
    if easing["type"] == "easeOut":
        return 1 - (1 - time) ** 3
    if easing["type"] == "spring":
        return spring_progress(
            float(easing["responseSeconds"]),
            float(easing["dampingFraction"]),
            time * duration_seconds,
        )
    raise ValueError(f"unsupported easing: {easing['type']}")


def expected_contract_keys(contract: dict) -> set[str]:
    keys = set(REQUIRED_CONTRACT_KEYS)
    for entry in contract["platformOverrides"]:
        keys.add(entry["field"])
    return keys


def evidence_for(key: str) -> list[str]:
    if key in {"contractId", "schemaVersion", "platformOverrides"}:
        paths = EVIDENCE["contract"]
    elif key.startswith("trigger."):
        paths = EVIDENCE["trigger"] + EVIDENCE["runtime"]
    elif key.startswith("geometry."):
        paths = EVIDENCE["geometry"]
    else:
        paths = EVIDENCE["runtime"] + [PREVIEW]
    return sorted(set(paths))


def trigger_vectors(contract: dict) -> dict:
    half_width = override_value(contract, "trigger.geometry.centeredHalfWidthPercent")
    thickness = override_value(contract, "trigger.geometry.topEdgeThicknessPixels")
    left = DISPLAY["left"] + DISPLAY["width"] * (50 - half_width) / 100
    right = DISPLAY["left"] + DISPLAY["width"] * (50 + half_width) / 100
    bottom = DISPLAY["top"] + min(thickness, DISPLAY["height"])
    center = (left + right) / 2
    return {
        "bounds": {"bottom": bottom, "left": left, "right": right, "top": DISPLAY["top"]},
        "display": DISPLAY,
        "points": [
            {"inside": False, "x": left - 1, "y": 0.0},
            {"inside": True, "x": left, "y": 0.0},
            {"inside": True, "x": center, "y": bottom - 1},
            {"inside": False, "x": center, "y": bottom},
            {"inside": True, "x": right - 1, "y": 0.0},
            {"inside": False, "x": right, "y": 0.0},
        ],
    }


def transition_vectors(contract: dict) -> list[dict]:
    vectors = []
    for key in ("reveal", "conceal"):
        transition = contract[key]
        duration_seconds = float(transition["durationMs"]) / 1000
        vectors.append(
            {
                "contractKey": key,
                "durationMs": transition["durationMs"],
                "easing": transition["easing"],
                "samples": [
                    {
                        "progress": round(
                            easing_progress(transition["easing"], duration_seconds, time),
                            6,
                        ),
                        "time": time,
                    }
                    for time in SAMPLES
                ],
            }
        )
    return vectors


def generate(contract: dict) -> dict:
    validate_contract_shape(contract)
    actual_keys = expected_contract_keys(contract)
    missing = REQUIRED_CONTRACT_KEYS - actual_keys
    if missing:
        raise ValueError(f"vector coverage is missing contract keys: {sorted(missing)}")
    keys = sorted(actual_keys)
    for key in keys:
        for path in evidence_for(key):
            if not (ROOT / path).exists():
                raise ValueError(f"missing evidence path for {key}: {path}")

    return {
        "contractId": contract["contractId"],
        "contractSchemaVersion": contract["schemaVersion"],
        "easing": {
            "tolerance": TOLERANCE,
            "transitions": transition_vectors(contract),
        },
        "evidence": [
            {"contractKey": key, "paths": evidence_for(key)} for key in keys
        ],
        "geometry": contract["geometry"],
        "platform": "windows",
        "platformMappings": [
            {"field": entry["field"], "value": entry["value"]}
            for entry in sorted(contract["platformOverrides"], key=lambda item: item["field"])
        ],
        "reducedMotion": contract["reducedMotion"],
        "stateTransitions": [
            {
                "contractKey": "reveal",
                "direction": contract["reveal"]["direction"],
                "from": "hidden",
                "to": "visible",
            },
            {
                "contractKey": "conceal",
                "direction": contract["conceal"]["direction"],
                "from": "visible",
                "to": "hidden",
            },
        ],
        "testedContractKeys": keys,
        "trigger": trigger_vectors(contract),
        "vectorVersion": "1.0.0",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    generated = json.dumps(generate(contract), indent=2, sort_keys=True) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != generated:
            print(f"stale: {OUTPUT.relative_to(ROOT)}", file=sys.stderr)
            print(
                "Run python3 scripts/generate-workbench-interaction-vectors.py.",
                file=sys.stderr,
            )
            return 1
        print("Workbench interaction vectors are current.")
        return 0

    OUTPUT.write_text(generated, encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

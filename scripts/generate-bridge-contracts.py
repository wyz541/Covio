#!/usr/bin/env python3
"""Generate the Covio C bridge header and JNI declarations from one contract."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "rust" / "crates" / "covio-ffi" / "bridge" / "bridge_contract.json"
C_HEADER = ROOT / "rust" / "crates" / "covio-ffi" / "include" / "covio_bridge.generated.h"
JNI_HEADER = (
    ROOT / "rust" / "crates" / "covio-ffi" / "include" / "covio_bridge_jni.generated.h"
)
FFI_SOURCE = ROOT / "rust" / "crates" / "covio-ffi" / "src" / "lib.rs"
FFI_C_HEADER = ROOT / "rust" / "crates" / "covio-ffi" / "include" / "covio_ffi.h"

REQUIRED_C_FUNCTIONS = {
    "covio_ffi_abi_version",
    "covio_bridge_protocol_version",
    "covio_handle_create",
    "covio_handle_release",
    "covio_handle_dispatch",
    "covio_handle_cancel",
    "covio_handle_shutdown",
    "covio_handle_lifecycle",
    "covio_handle_active_request_count",
    "covio_owned_bytes_free",
    "covio_error_free",
}
REQUIRED_JNI_FUNCTIONS = {
    "covio_jni_abi_version",
    "covio_jni_protocol_version",
    "covio_jni_handle_create",
    "covio_jni_handle_configure",
    "covio_jni_handle_release",
    "covio_jni_handle_dispatch",
    "covio_jni_handle_cancel",
    "covio_jni_handle_shutdown",
    "covio_jni_handle_next_event",
    "covio_jni_handle_lifecycle",
    "covio_jni_handle_active_request_count",
}
SOURCE_FUNCTION = re.compile(
    r'pub\s+(?:unsafe\s+)?extern\s+"C"\s+fn\s+'
    r'(covio_(?:ffi_abi_version|bridge_protocol_version|handle_[A-Za-z0-9_]+|owned_bytes_free|error_free))\s*\('
)


def fail(message: str) -> None:
    raise SystemExit(f"bridge contract generation failed: {message}")


def load_contract() -> dict:
    try:
        contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(str(error))
    if contract.get("schemaVersion") != 1:
        fail("schemaVersion must be 1")
    for key in ("abiVersion", "protocolVersion", "defaultMaxControlBytes"):
        if not isinstance(contract.get(key), int) or contract[key] <= 0:
            fail(f"{key} must be a positive integer")
    if contract.get("contentTransport") != "opaque_handle_or_stream":
        fail("contentTransport must be opaque_handle_or_stream")
    validate_named_values(contract, "statusCodes")
    validate_named_values(contract, "lifecycle")
    validate_named_values(contract, "cancelReasons")
    validate_functions(contract)
    header = FFI_C_HEADER.read_text(encoding="utf-8")
    if '#include "covio_bridge.generated.h"' not in header:
        fail("covio_ffi.h must include covio_bridge.generated.h")
    return contract


def validate_named_values(contract: dict, key: str) -> None:
    entries = contract.get(key)
    if not isinstance(entries, list) or not entries:
        fail(f"{key} must be a non-empty list")
    names: set[str] = set()
    c_names: set[str] = set()
    values: set[int] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            fail(f"{key} entries must be objects")
        name = entry.get("name")
        c_name = entry.get("cName")
        value = entry.get("value")
        if not isinstance(name, str) or not name:
            fail(f"{key} contains an invalid name")
        if not isinstance(c_name, str) or not c_name.startswith("COVIO_"):
            fail(f"{key}.{name} has an invalid cName")
        if not isinstance(value, int) or value < 0:
            fail(f"{key}.{name} has an invalid value")
        if name in names or c_name in c_names or value in values:
            fail(f"{key} contains a duplicate name, cName, or value")
        names.add(name)
        c_names.add(c_name)
        values.add(value)
    if values != set(range(len(entries))):
        fail(f"{key} values must be contiguous from zero")


def validate_functions(contract: dict) -> None:
    c_functions = contract.get("cFunctions")
    jni_functions = contract.get("jniFunctions")
    if not isinstance(c_functions, list) or not isinstance(jni_functions, list):
        fail("cFunctions and jniFunctions must be lists")
    validate_function_list(c_functions, "covio_", required=REQUIRED_C_FUNCTIONS)
    validate_function_list(jni_functions, "covio_jni_", required=REQUIRED_JNI_FUNCTIONS)
    if {entry["name"] for entry in c_functions} != REQUIRED_C_FUNCTIONS:
        fail("cFunctions must match the required bridge surface")
    if {entry["name"] for entry in jni_functions} != REQUIRED_JNI_FUNCTIONS:
        fail("jniFunctions must match the required bridge surface")
    source = FFI_SOURCE.read_text(encoding="utf-8")
    source_functions = set(SOURCE_FUNCTION.findall(source))
    if source_functions != REQUIRED_C_FUNCTIONS:
        missing = sorted(REQUIRED_C_FUNCTIONS - source_functions)
        extra = sorted(source_functions - REQUIRED_C_FUNCTIONS)
        fail(f"Rust bridge surface drift: missing={missing}, extra={extra}")


def validate_function_list(entries: list, prefix: str, required: set[str]) -> None:
    names: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            fail("function entries must be objects")
        name = entry.get("name")
        return_type = entry.get("returnType")
        parameters = entry.get("parameters")
        if not isinstance(name, str) or not name.startswith(prefix):
            fail(f"invalid function name: {name!r}")
        if name in names:
            fail(f"duplicate function name: {name}")
        if not isinstance(return_type, str) or not return_type:
            fail(f"{name} has no returnType")
        if not isinstance(parameters, list):
            fail(f"{name}.parameters must be a list")
        parameter_names: set[str] = set()
        for parameter in parameters:
            if not isinstance(parameter, dict):
                fail(f"{name} contains an invalid parameter")
            parameter_name = parameter.get("name")
            parameter_type = parameter.get("type")
            if not isinstance(parameter_name, str) or not parameter_name:
                fail(f"{name} contains a parameter without a name")
            if not isinstance(parameter_type, str) or not parameter_type:
                fail(f"{name}.{parameter_name} has no type")
            if parameter_name in parameter_names:
                fail(f"{name} contains duplicate parameter {parameter_name}")
            parameter_names.add(parameter_name)
        names.add(name)
    if not required.issubset(names):
        fail(f"missing required functions: {sorted(required - names)}")


def c_parameters(entry: dict) -> str:
    parameters = entry["parameters"]
    if not parameters:
        return "void"
    return ",\n    ".join(f'{parameter["type"]} {parameter["name"]}' for parameter in parameters)


def jni_parameters(entry: dict) -> str:
    parameters = ["JNIEnv *env", "jclass clazz"]
    parameters.extend(f'{parameter["type"]} {parameter["name"]}' for parameter in entry["parameters"])
    return ",\n    ".join(parameters)


def render_c_header(contract: dict) -> str:
    lines = [
        "/* Generated by scripts/generate-bridge-contracts.py. Do not edit by hand. */",
        "/* Source: rust/crates/covio-ffi/bridge/bridge_contract.json */",
        "#ifndef COVIO_BRIDGE_GENERATED_H",
        "#define COVIO_BRIDGE_GENERATED_H",
        "",
        "#include <stdbool.h>",
        "#include <stddef.h>",
        "#include <stdint.h>",
        "",
        f'#define COVIO_FFI_ABI_VERSION {contract["abiVersion"]}u',
        f'#define COVIO_BRIDGE_PROTOCOL_VERSION {contract["protocolVersion"]}u',
        f'#define COVIO_BRIDGE_DEFAULT_MAX_CONTROL_BYTES {contract["defaultMaxControlBytes"]}u',
        "#define COVIO_BRIDGE_CONTENT_TRANSPORT_HANDLE_OR_STREAM 1",
        "",
    ]
    for key, enum_name, type_name in (
        ("statusCodes", "CovioStatusCode", "CovioStatusCode"),
        ("lifecycle", "CovioLifecycle", "CovioLifecycle"),
        ("cancelReasons", "CovioCancelReason", "CovioCancelReason"),
    ):
        lines.append(f"typedef enum {enum_name} {{")
        for entry in contract[key]:
            lines.append(f'    {entry["cName"]} = {entry["value"]},')
        lines.append(f"}} {type_name};")
        lines.append("")
    lines.extend(
        [
            "typedef struct CovioOwnedBytes {",
            "    uint8_t *data;",
            "    size_t len;",
            "    size_t capacity;",
            "} CovioOwnedBytes;",
            "",
            "typedef struct CovioError {",
            "    uint32_t code;",
            "    CovioOwnedBytes message;",
            "} CovioError;",
            "",
            "typedef void (*CovioEventCallback)(",
            "    void *context,",
            "    const uint8_t *data,",
            "    size_t len",
            ");",
            "",
            "typedef struct CovioHandle CovioHandle;",
            "",
            "#ifdef __cplusplus",
            'extern "C" {',
            "#endif",
            "",
            "/* Bridge handles are single-threaded. Host callbacks must not re-enter them. */",
            "",
        ]
    )
    for entry in contract["cFunctions"]:
        lines.extend(
            [
                f'{entry["returnType"]} {entry["name"]}(',
                f"    {c_parameters(entry)}",
                ");",
                "",
            ]
        )
    lines.extend(["#ifdef __cplusplus", "}", "#endif", "", "#endif", ""])
    return "\n".join(lines)


def render_jni_header(contract: dict) -> str:
    lines = [
        "/* Generated by scripts/generate-bridge-contracts.py. Do not edit by hand. */",
        "/* Source: rust/crates/covio-ffi/bridge/bridge_contract.json */",
        "/*",
        " * Kotlin hosts may bind these C JNI entry points with RegisterNatives.",
        " * Control messages only cross this boundary. File content must use",
        " * an opaque handle or stream.",
        " */",
        "#ifndef COVIO_BRIDGE_JNI_GENERATED_H",
        "#define COVIO_BRIDGE_JNI_GENERATED_H",
        "",
        "#include <jni.h>",
        '#include "covio_bridge.generated.h"',
        "",
        "#ifdef __cplusplus",
        'extern "C" {',
        "#endif",
        "",
    ]
    for entry in contract["jniFunctions"]:
        lines.extend(
            [
                f'JNIEXPORT {entry["returnType"]} JNICALL {entry["name"]}(',
                f"    {jni_parameters(entry)}",
                ");",
                "",
            ]
        )
    lines.extend(["#ifdef __cplusplus", "}", "#endif", "", "#endif", ""])
    return "\n".join(lines)


def write_or_check(path: Path, expected: str, check: bool) -> bool:
    actual = path.read_text(encoding="utf-8") if path.exists() else None
    if check:
        if actual != expected:
            print(f"stale: {path.relative_to(ROOT)}", file=sys.stderr)
            return False
        return True
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(expected, encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    contract = load_contract()
    expected_c = render_c_header(contract)
    expected_jni = render_jni_header(contract)
    current = write_or_check(C_HEADER, expected_c, args.check)
    current = write_or_check(JNI_HEADER, expected_jni, args.check) and current
    if args.check and current:
        print("bridge contracts are current")
    return 0 if current else 1


if __name__ == "__main__":
    raise SystemExit(main())
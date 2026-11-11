#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/rust-macos-ffi/debug"

bash "$ROOT/scripts/build-rust-macos-ffi.sh" debug
[[ -L "$OUTPUT_DIR/lib/libcovio_ffi.dylib" ]]
python3 -I - "$OUTPUT_DIR/lib/libcovio_ffi.a" 26.0 <<'PY_MINOS'
import re
import subprocess
import sys

archive = sys.argv[1]
expected = tuple(int(part) for part in sys.argv[2].split("."))
output = subprocess.run(
    ["otool", "-l", archive],
    check=True,
    capture_output=True,
    text=True,
).stdout
versions = {
    tuple(int(part) for part in match.group(1).split("."))
    for match in re.finditer(r"^\s*minos\s+(\d+(?:\.\d+)*)$", output, re.MULTILINE)
}
too_new = sorted(version for version in versions if version > expected)
if too_new:
    print(f"Rust archive contains objects newer than macOS {sys.argv[2]}: {too_new}", file=sys.stderr)
    raise SystemExit(1)
print(f"Rust archive deployment versions: {sorted(versions)}")
PY_MINOS
otool -D "$OUTPUT_DIR/lib/libcovio_ffi.1.dylib" | grep -F '@rpath/libcovio_ffi.1.dylib' >/dev/null
nm -gU "$OUTPUT_DIR/lib/libcovio_ffi.1.dylib" | grep -F '_covio_handle_create' >/dev/null
nm -gU "$OUTPUT_DIR/lib/libcovio_ffi.1.dylib" | grep -F '_covio_agent_token_read' >/dev/null
nm -gU "$OUTPUT_DIR/lib/libcovio_ffi.1.dylib" | grep -F '_covio_agent_token_write' >/dev/null
nm -gU "$OUTPUT_DIR/lib/libcovio_ffi.1.dylib" | grep -F '_covio_agent_token_delete' >/dev/null
nm -gU "$OUTPUT_DIR/lib/libcovio_ffi.1.dylib" | grep -F '_covio_agent_token_reset' >/dev/null
xcrun swiftc \
  -I "$OUTPUT_DIR/include" \
  -L "$OUTPUT_DIR/lib" \
  -lcovio_ffi \
  -Xlinker -rpath \
  -Xlinker "$OUTPUT_DIR/lib" \
  "$ROOT/rust/crates/covio-ffi/tests/swift_smoke.swift" \
  -o "$OUTPUT_DIR/covio-ffi-smoke"
SMOKE_VAULT_SERVICE="com.wyz.covio.credentials.swift-smoke.$(uuidgen | tr -d '-')"
COVIO_AGENT_VAULT_SERVICE="$SMOKE_VAULT_SERVICE" \
  DYLD_LIBRARY_PATH="$OUTPUT_DIR/lib" \
  "$OUTPUT_DIR/covio-ffi-smoke"

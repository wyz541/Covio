#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/rust-macos-ffi/debug"

bash "$ROOT/scripts/build-rust-macos-ffi.sh" debug
[[ -L "$OUTPUT_DIR/lib/libcovio_ffi.dylib" ]]
otool -D "$OUTPUT_DIR/lib/libcovio_ffi.1.dylib" | grep -F '@rpath/libcovio_ffi.1.dylib' >/dev/null
nm -gU "$OUTPUT_DIR/lib/libcovio_ffi.1.dylib" | grep -F '_covio_handle_create' >/dev/null
nm -gU "$OUTPUT_DIR/lib/libcovio_ffi.1.dylib" | grep -F '_covio_keychain_read' >/dev/null
xcrun swiftc \
  -I "$OUTPUT_DIR/include" \
  -L "$OUTPUT_DIR/lib" \
  -lcovio_ffi \
  -Xlinker -rpath \
  -Xlinker "$OUTPUT_DIR/lib" \
  "$ROOT/rust/crates/covio-ffi/tests/swift_smoke.swift" \
  -o "$OUTPUT_DIR/covio-ffi-smoke"
DYLD_LIBRARY_PATH="$OUTPUT_DIR/lib" "$OUTPUT_DIR/covio-ffi-smoke"

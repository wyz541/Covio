#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-debug}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'macOS is required to build the Covio C ABI.\n' >&2
  exit 1
fi

if ! command -v cargo >/dev/null 2>&1; then
  if [[ -x "$HOME/tools/cargo/bin/cargo" ]]; then
    export CARGO_HOME="${CARGO_HOME:-$HOME/tools/cargo}"
    export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/tools/rustup}"
    export PATH="$CARGO_HOME/bin:$PATH"
  else
    printf 'cargo is required. Install Rust or add cargo to PATH.\n' >&2
    exit 1
  fi
fi

cd "$ROOT/rust"
case "$PROFILE" in
  debug)
    cargo build -p covio-ffi
    ;;
  release)
    cargo build -p covio-ffi --release
    ;;
  *)
    printf 'Usage: %s [debug|release]\n' "$0" >&2
    exit 2
    ;;
esac

TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/rust/target}"
OUTPUT_DIR="$ROOT/build/rust-macos-ffi/$PROFILE"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/include" "$OUTPUT_DIR/lib"

cp "$ROOT/rust/crates/covio-ffi/include/covio_ffi.h" "$OUTPUT_DIR/include/"
cp "$ROOT/rust/crates/covio-ffi/include/module.modulemap" "$OUTPUT_DIR/include/"
cp "$TARGET_DIR/$PROFILE/libcovio_ffi.dylib" "$OUTPUT_DIR/lib/libcovio_ffi.1.dylib"
ln -s libcovio_ffi.1.dylib "$OUTPUT_DIR/lib/libcovio_ffi.dylib"
cp "$TARGET_DIR/$PROFILE/libcovio_ffi.a" "$OUTPUT_DIR/lib/libcovio_ffi.a"
install_name_tool -id @rpath/libcovio_ffi.1.dylib "$OUTPUT_DIR/lib/libcovio_ffi.1.dylib"

printf 'Built Covio C ABI: %s\n' "$OUTPUT_DIR"

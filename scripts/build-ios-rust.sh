#!/bin/bash
set -euo pipefail

# 为当前 Xcode 目标架构构建 covio-ffi 静态库。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUST_ROOT="$ROOT/rust"
PLATFORM_NAME="${PLATFORM_NAME:-iphonesimulator}"
CONFIGURATION="${CONFIGURATION:-Debug}"
ARCHS="${ARCHS:-}"
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-$ROOT/build/ios-rust}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This script requires macOS with Xcode.\n' >&2
  exit 1
fi

if ! command -v cargo >/dev/null 2>&1 && [[ -x "$HOME/.cargo/bin/cargo" ]]; then
  export PATH="$HOME/.cargo/bin:$PATH"
fi
if ! command -v cargo >/dev/null 2>&1; then
  printf 'Missing cargo. Install a Rust toolchain.\n' >&2
  exit 1
fi

case "$PLATFORM_NAME" in
  iphoneos)
    SDK_NAME=iphoneos
    DEFAULT_ARCHS=arm64
    ;;
  iphonesimulator)
    SDK_NAME=iphonesimulator
    DEFAULT_ARCHS=arm64
    ;;
  *)
    printf 'Unsupported iOS platform: %s\n' "$PLATFORM_NAME" >&2
    exit 1
    ;;
esac

if [[ -z "${ARCHS:-}" ]]; then
  ARCHS="$DEFAULT_ARCHS"
fi

SDKROOT="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
export SDKROOT
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-17.0}"

if [[ "$CONFIGURATION" == "Debug" ]]; then
  CARGO_PROFILE_DIR=debug
else
  CARGO_PROFILE_DIR=release
fi

mkdir -p "$BUILT_PRODUCTS_DIR"
LIBRARIES=()

for ARCH in $ARCHS; do
  case "$PLATFORM_NAME:$ARCH" in
    iphoneos:arm64) TARGET=aarch64-apple-ios ;;
    iphonesimulator:arm64) TARGET=aarch64-apple-ios-sim ;;
    iphonesimulator:x86_64) TARGET=x86_64-apple-ios ;;
    *)
      printf 'Unsupported iOS architecture: %s %s\n' "$PLATFORM_NAME" "$ARCH" >&2
      exit 1
      ;;
  esac

  if ! rustup target list --installed | grep -qx "$TARGET"; then
    rustup target add "$TARGET"
  fi

  CLANG="$(xcrun --sdk "$SDK_NAME" --find clang)"
  TARGET_ENV="${TARGET//-/_}"
  TARGET_UPPER="$(printf '%s' "$TARGET_ENV" | tr '[:lower:]' '[:upper:]')"
  export "CC_${TARGET_ENV}=$CLANG"
  export "CARGO_TARGET_${TARGET_UPPER}_LINKER=$CLANG"

  if [[ "$CONFIGURATION" == "Debug" ]]; then
    cargo build \
      --manifest-path "$RUST_ROOT/Cargo.toml" \
      --locked \
      -p covio-ffi \
      --target "$TARGET"
  else
    cargo build \
      --manifest-path "$RUST_ROOT/Cargo.toml" \
      --locked \
      -p covio-ffi \
      --target "$TARGET" \
      --release
  fi
  LIBRARIES+=("$RUST_ROOT/target/$TARGET/$CARGO_PROFILE_DIR/libcovio_ffi.a")
done

OUTPUT="$BUILT_PRODUCTS_DIR/libcovio_ffi.a"
if [[ "${#LIBRARIES[@]}" -eq 1 ]]; then
  cp "${LIBRARIES[0]}" "$OUTPUT"
else
  xcrun lipo -create "${LIBRARIES[@]}" -output "$OUTPUT"
fi

printf 'Built %s\n' "$OUTPUT"

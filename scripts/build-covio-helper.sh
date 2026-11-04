#!/bin/bash
set -euo pipefail

# 构建独立的最小 root helper。Rust core 使用静态库链接，
# 因此 CovioHelper 不依赖 app bundle 内的动态库或可变资源。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
OUT_DIR="$ROOT/build/helper"
INFO_DIR="$ROOT/build/helper-metadata"
OUTPUT="$OUT_DIR/CovioHelper"
RUST_FFI_DIR="$ROOT/build/rust-macos-ffi/$CONFIGURATION"
HELPER_INFO_SOURCE="$ROOT/macosApp/helper/Info.plist"
HELPER_INFO="$INFO_DIR/Info.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
TARGET="arm64-apple-macos26.0"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  printf 'This script requires an Apple Silicon Mac.\n' >&2
  exit 1
fi
bash "$ROOT/scripts/build-rust-macos-ffi.sh" "$CONFIGURATION"

VERSION="${COVIO_CLIENT_VERSION:-$(python3 -I "$ROOT/scripts/release_manifest.py" value clientVersion)}"
PRODUCT_VERSION="${COVIO_PRODUCT_VERSION:-$(python3 -I "$ROOT/scripts/release_manifest.py" value productVersion)}"
BUILD_NUMBER="${CURRENT_PROJECT_VERSION:-$(python3 -I "$ROOT/scripts/release_manifest.py" value buildNumber)}"
CHANNEL="${COVIO_RELEASE_CHANNEL:-$(python3 -I "$ROOT/scripts/release_manifest.py" value channel)}"
COMMIT="${COVIO_GIT_COMMIT:-$(git -C "$ROOT" rev-parse HEAD)}"
RELEASE_ID="${COVIO_RELEASE_ID:-$VERSION-g$COMMIT}"
PROTOCOL_VERSION="${COVIO_HELPER_PROTOCOL_VERSION:-$(python3 -I "$ROOT/scripts/release_manifest.py" value helperProtocolVersion)}"

mkdir -p "$OUT_DIR" "$INFO_DIR"
if [[ -e "$OUT_DIR/Info.plist" ]]; then
  unlink "$OUT_DIR/Info.plist"
fi
/usr/bin/ditto "$HELPER_INFO_SOURCE" "$HELPER_INFO"
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $PRODUCT_VERSION" "$HELPER_INFO"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$HELPER_INFO"
"$PLIST_BUDDY" -c "Set :CovioClientVersion $VERSION" "$HELPER_INFO"
"$PLIST_BUDDY" -c "Set :CovioProductVersion $PRODUCT_VERSION" "$HELPER_INFO"
"$PLIST_BUDDY" -c "Set :CovioReleaseChannel $CHANNEL" "$HELPER_INFO"
"$PLIST_BUDDY" -c "Set :CovioGitCommit $COMMIT" "$HELPER_INFO"
"$PLIST_BUDDY" -c "Set :CovioReleaseId $RELEASE_ID" "$HELPER_INFO"
"$PLIST_BUDDY" -c "Set :CovioHelperProtocolVersion $PROTOCOL_VERSION" "$HELPER_INFO"

SOURCES=(
  "$ROOT/macosApp/helper/CovioHelperMain.swift"
  "$ROOT/macosApp/helper/CovioHelperRuntime.swift"
  "$ROOT/macosApp/src/Core/CovioCoreBridge.swift"
  "$ROOT/macosApp/src/Core/CovioCoreModels.swift"
  "$ROOT/macosApp/src/Core/CovioCoreServices.swift"
  "$ROOT/macosApp/src/Core/CovioHelper.swift"
  "$ROOT/macosApp/src/Design/GeneratedReleaseIdentity.swift"
  "$ROOT/macosApp/src/Design/LocalizedCopy.swift"
  "$ROOT/macosApp/src/Platform/ChargeLimitActiveDischarge.swift"
  "$ROOT/macosApp/src/Platform/ChargeLimitHelperCommandHandler.swift"
  "$ROOT/macosApp/src/Platform/ChargeLimitMCL.swift"
  "$ROOT/macosApp/src/Platform/ChargeLimitRuntime.swift"
  "$ROOT/macosApp/src/Platform/ExternalDisplayReader.swift"
  "$ROOT/macosApp/src/Platform/HelperLeaseCoordinator.swift"
  "$ROOT/macosApp/src/Platform/HelperProtocol.swift"
  "$ROOT/macosApp/src/Platform/HelperReleaseIdentity.swift"
  "$ROOT/macosApp/src/Platform/HelperServer.swift"
  "$ROOT/macosApp/src/Platform/HelperSignature.swift"
  "$ROOT/macosApp/src/Platform/HelperSocket.swift"
  "$ROOT/macosApp/src/Platform/HelperXPCProtocol.swift"
  "$ROOT/macosApp/src/Platform/MacChargeLimitPowerReader.swift"
  "$ROOT/macosApp/src/Platform/PmsetReader.swift"
  "$ROOT/macosApp/src/Platform/PowerUIChargeClient.swift"
  "$ROOT/macosApp/src/Platform/SMC/SMCAccess.swift"
  "$ROOT/macosApp/src/Platform/SMC/SMCFanHardware.swift"
  "$ROOT/macosApp/src/Platform/SMC/StatsFanControl.swift"
  "$ROOT/macosApp/src/Hub/Monitor/Fan/FanControlRuntime.swift"
  "$ROOT/macosApp/src/Hub/Monitor/Fan/MonitorFanModels.swift"
)

SWIFT_FLAGS=(
  -sdk "$(xcrun --sdk macosx --show-sdk-path)"
  -target "$TARGET"
  -swift-version 6
  -parse-as-library
  -module-name CovioHelper
  -I "$RUST_FFI_DIR/include"
  "$RUST_FFI_DIR/lib/libcovio_ffi.a"
  -framework Security
  -framework IOKit
  -framework CoreFoundation
  -framework CoreGraphics
  -Xlinker -sectcreate
  -Xlinker __TEXT
  -Xlinker __info_plist
  -Xlinker "$HELPER_INFO"
)
if [[ "$CONFIGURATION" == "Release" ]]; then
  SWIFT_FLAGS+=(-O)
else
  SWIFT_FLAGS+=(-Onone -g)
fi

printf 'Building CovioHelper [%s]...\n' "$CONFIGURATION"
xcrun swiftc "${SWIFT_FLAGS[@]}" "${SOURCES[@]}" -o "$OUTPUT"

IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
fi
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [[ "$CONFIGURATION" == "Release" && "$IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
fi
/usr/bin/codesign "${SIGN_FLAGS[@]}" "$OUTPUT"
/usr/bin/codesign --verify --strict "$OUTPUT"

if /usr/bin/otool -L "$OUTPUT" | grep -Fq 'kmpDomain.framework'; then
  printf 'CovioHelper must not load a Kotlin framework.\n' >&2
  exit 1
fi

printf 'Built %s\n' "$OUTPUT"
file "$OUTPUT"

#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
OUT_DIR="${COVIO_UPDATER_OUT_DIR:-$ROOT/build/updater}"
ENGINE="$OUT_DIR/CovioUpdater"
LAUNCHER="$OUT_DIR/CovioUpdaterLauncher"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macos26.0"
IDENTITY="${CODE_SIGN_IDENTITY:--}"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  printf 'This script requires an Apple Silicon Mac.\n' >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

ENGINE_SOURCES=(
  "$ROOT/macosApp/updater/CovioUpdaterMain.swift"
  "$ROOT/macosApp/src/Design/GeneratedReleaseIdentity.swift"
  "$ROOT/macosApp/src/Updater/CovioUpdaterService.swift"
  "$ROOT/macosApp/src/Updater/CovioUpdaterXPCProtocol.swift"
  "$ROOT/macosApp/src/Updater/UpdateManifest.swift"
  "$ROOT/macosApp/src/Updater/UpdaterContract.swift"
  "$ROOT/macosApp/src/Updater/UpdaterPaths.swift"
  "$ROOT/macosApp/src/Updater/UpdaterState.swift"
)
LAUNCHER_SOURCES=(
  "$ROOT/macosApp/updater/CovioUpdaterLauncher.swift"
  "$ROOT/macosApp/src/Updater/UpdaterContract.swift"
  "$ROOT/macosApp/src/Updater/UpdaterPaths.swift"
  "$ROOT/macosApp/src/Updater/UpdaterState.swift"
)
SWIFT_FLAGS=(
  -sdk "$SDK"
  -target "$TARGET"
  -swift-version 6
  -parse-as-library
  -module-cache-path "$ROOT/build/swift-module-cache"
)
if [[ "$CONFIGURATION" == "Release" ]]; then
  SWIFT_FLAGS+=(-O)
else
  SWIFT_FLAGS+=(-Onone -g)
fi

sign() {
  local path="$1"
  local identifier="$2"
  local flags=(--force --identifier "$identifier" --sign "$IDENTITY")
  if [[ "$CONFIGURATION" == "Release" && "$IDENTITY" != "-" ]]; then
    flags+=(--options runtime --timestamp)
  fi
  /usr/bin/codesign "${flags[@]}" "$path"
  /usr/bin/codesign --verify --strict "$path"
}

printf 'Building CovioUpdater [%s]...\n' "$CONFIGURATION"
xcrun swiftc \
  "${SWIFT_FLAGS[@]}" \
  -module-name CovioUpdater \
  "${ENGINE_SOURCES[@]}" \
  -o "$ENGINE"
sign "$ENGINE" "com.wyz.covio.updater"

printf 'Building CovioUpdaterLauncher [%s]...\n' "$CONFIGURATION"
xcrun swiftc \
  "${SWIFT_FLAGS[@]}" \
  -module-name CovioUpdaterLauncher \
  "${LAUNCHER_SOURCES[@]}" \
  -o "$LAUNCHER"
sign "$LAUNCHER" "com.wyz.covio.updater.launcher"

printf 'Built %s\n' "$ENGINE"
printf 'Built %s\n' "$LAUNCHER"
file "$ENGINE" "$LAUNCHER"

#!/bin/bash
set -euo pipefail

# Build the Windows x64 application and its current-user Inno Setup installer.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/installer/windows/Covio.iss"
ICON="$ROOT/assets/windows/Covio.ico"
OUTPUT_DIR="${COVIO_WINDOWS_OUTPUT_DIR:-$ROOT/build/windows-package}"
TARGET="${COVIO_WINDOWS_TARGET:-}"
PRODUCT_VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value productVersion)"
CLIENT_VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value clientVersion)"
APP_VERSION="${COVIO_WINDOWS_APP_VERSION:-$CLIENT_VERSION}"
BUILD_NUMBER="${COVIO_WINDOWS_BUILD_NUMBER:-$(python3 -I "$ROOT/scripts/release_manifest.py" value buildNumber)}"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
RELEASE_ID="${COVIO_WINDOWS_RELEASE_ID:-$(python3 -I "$ROOT/scripts/release_manifest.py" release-id --commit "$COMMIT")}"
INSTALLER_VERSION="$PRODUCT_VERSION.$BUILD_NUMBER"
OUTPUT_BASENAME="Covio-$INSTALLER_VERSION-setup"
TARGET_DIR="$ROOT/rust/target"

if [[ "${OS:-}" != "Windows_NT" ]]; then
  printf 'This script requires Windows.\n' >&2
  exit 1
fi

if ! command -v cargo >/dev/null 2>&1; then
  printf 'cargo is required. Install Rust or add cargo to PATH.\n' >&2
  exit 1
fi

if [[ ! -f "$ICON" ]]; then
  printf 'Missing Windows icon: %s\n' "$ICON" >&2
  exit 1
fi

if [[ ! -f "$SCRIPT" ]]; then
  printf 'Missing Inno Setup script: %s\n' "$SCRIPT" >&2
  exit 1
fi

ISCC="${COVIO_INNO_SETUP_ISCC:-}"
if [[ -z "$ISCC" ]]; then
  for candidate in \
    "$(command -v ISCC.exe 2>/dev/null || true)" \
    "$(command -v iscc.exe 2>/dev/null || true)" \
    "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
    "/c/Program Files/Inno Setup 6/ISCC.exe"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      ISCC="$candidate"
      break
    fi
  done
fi
if [[ -z "$ISCC" || ! -x "$ISCC" ]]; then
  printf 'Inno Setup ISCC.exe is required.\n' >&2
  exit 1
fi

cd "$ROOT/rust"
if [[ -n "$TARGET" ]]; then
  COVIO_RELEASE_ID="$RELEASE_ID" cargo build -p covio-windows --release --target "$TARGET"
  SOURCE_EXE="$TARGET_DIR/$TARGET/release/covio-windows.exe"
else
  COVIO_RELEASE_ID="$RELEASE_ID" cargo build -p covio-windows --release
  SOURCE_EXE="$TARGET_DIR/release/covio-windows.exe"
fi

if [[ ! -f "$SOURCE_EXE" ]]; then
  printf 'Windows executable is missing: %s\n' "$SOURCE_EXE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
find "$OUTPUT_DIR" -mindepth 1 -depth -delete
BUILD_INFO="$OUTPUT_DIR/build-info.txt"
printf 'releaseId=%s\nclientVersion=%s\nproductVersion=%s\nbuildNumber=%s\ncommit=%s\n' \
  "$RELEASE_ID" "$APP_VERSION" "$PRODUCT_VERSION" "$BUILD_NUMBER" "$COMMIT" >"$BUILD_INFO"

win_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

SOURCE_WIN="$(win_path "$SOURCE_EXE")"
ICON_WIN="$(win_path "$ICON")"
BUILD_INFO_WIN="$(win_path "$BUILD_INFO")"
OUTPUT_WIN="$(win_path "$OUTPUT_DIR")"
SCRIPT_WIN="$(win_path "$SCRIPT")"

MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$ISCC" \
  "/DAppVersion=$APP_VERSION" \
  "/DInstallerVersion=$INSTALLER_VERSION" \
  "/DSourceExe=$SOURCE_WIN" \
  "/DIconFile=$ICON_WIN" \
  "/DVersionFile=$BUILD_INFO_WIN" \
  "/DOutputDir=$OUTPUT_WIN" \
  "/DOutputBaseFilename=$OUTPUT_BASENAME" \
  "$SCRIPT_WIN"

INSTALLER="$OUTPUT_DIR/$OUTPUT_BASENAME.exe"
if [[ ! -s "$INSTALLER" ]]; then
  printf 'Windows installer is missing: %s\n' "$INSTALLER" >&2
  exit 1
fi
SHA256="$(sha256sum "$INSTALLER" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$(basename "$INSTALLER")" >"$INSTALLER.sha256"
python3 -I - "$OUTPUT_DIR/windows-package.json" "$INSTALLER" "$SHA256" "$RELEASE_ID" "$APP_VERSION" "$BUILD_NUMBER" "$COMMIT" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
installer = pathlib.Path(sys.argv[2])
payload = {
    "schemaVersion": 1,
    "artifact": installer.name,
    "sha256": sys.argv[3],
    "releaseId": sys.argv[4],
    "clientVersion": sys.argv[5],
    "buildNumber": int(sys.argv[6]),
    "gitCommit": sys.argv[7],
    "target": "x86_64-pc-windows-msvc",
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

printf 'Windows installer: %s\n' "$INSTALLER"
printf 'SHA-256: %s\n' "$SHA256"

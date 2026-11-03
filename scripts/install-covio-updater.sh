#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="${1:-}"
UPDATER_DIR="${COVIO_UPDATER_OUT_DIR:-$ROOT/build/updater-release}"
ENGINE="$UPDATER_DIR/CovioUpdater"
LAUNCHER="$UPDATER_DIR/CovioUpdaterLauncher"
PLIST="$ROOT/macosApp/daemons/com.wyz.covio.updater.plist"

if [[ -z "$APP_BUNDLE" || ! -d "$APP_BUNDLE" ]]; then
  printf 'Usage: %s <Covio.app>\n' "$0" >&2
  exit 1
fi
if [[ ! -x "$ENGINE" || ! -x "$LAUNCHER" || ! -f "$PLIST" ]]; then
  printf 'Missing built updater files in %s\n' "$UPDATER_DIR" >&2
  exit 1
fi

MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
DAEMON_DIR="$APP_BUNDLE/Contents/Library/LaunchDaemons"
mkdir -p "$MACOS_DIR" "$DAEMON_DIR"
/usr/bin/ditto "$ENGINE" "$MACOS_DIR/CovioUpdater"
/usr/bin/ditto "$LAUNCHER" "$MACOS_DIR/CovioUpdaterLauncher"
/usr/bin/ditto "$PLIST" "$DAEMON_DIR/com.wyz.covio.updater.plist"
chmod 0755 "$MACOS_DIR/CovioUpdater" "$MACOS_DIR/CovioUpdaterLauncher"
chmod 0644 "$DAEMON_DIR/com.wyz.covio.updater.plist"

/usr/bin/codesign --verify --strict "$MACOS_DIR/CovioUpdater"
/usr/bin/codesign --verify --strict "$MACOS_DIR/CovioUpdaterLauncher"
/usr/bin/plutil -lint "$DAEMON_DIR/com.wyz.covio.updater.plist" >/dev/null

printf 'Installed updater into %s\n' "$APP_BUNDLE"

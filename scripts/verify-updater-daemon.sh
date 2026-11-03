#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/xcode-dd/Build/Products/Debug/Covio.app}"
ENGINE="$APP/Contents/MacOS/CovioUpdater"
LAUNCHER="$APP/Contents/MacOS/CovioUpdaterLauncher"
DAEMON="$APP/Contents/Library/LaunchDaemons/com.wyz.covio.updater.plist"
INFO="$APP/Contents/Info.plist"

fail() {
  printf 'updater daemon verification failed: %s\n' "$1" >&2
  exit 1
}

[[ -d "$APP" ]] || fail "missing app: $APP"
[[ -x "$ENGINE" ]] || fail "missing updater engine"
[[ -x "$LAUNCHER" ]] || fail "missing updater launcher"
[[ -f "$DAEMON" ]] || fail "missing updater daemon plist"
[[ -f "$INFO" ]] || fail "missing app Info.plist"

plutil -lint "$DAEMON" >/dev/null || fail "invalid updater daemon plist"
python3 -I - "$DAEMON" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    plist = plistlib.load(stream)
expected = {
    "Label": "com.wyz.covio.updater",
    "ProgramArguments": [
        "/Library/Application Support/Covio/Updater/bin/CovioUpdaterLauncher"
    ],
    "RunAtLoad": True,
    "KeepAlive": True,
    "ProcessType": "Background",
    "ThrottleInterval": 10,
}
for key, value in expected.items():
    if plist.get(key) != value:
        raise SystemExit(f"invalid {key}: {plist.get(key)!r}")
if plist.get("MachServices", {}).get("com.wyz.covio.updater.xpc") is not True:
    raise SystemExit("missing updater Mach service")
PY

for binary in "$ENGINE" "$LAUNCHER"; do
  codesign --verify --strict "$binary" >/dev/null 2>&1 || fail "invalid signature: $binary"
  [[ "$(lipo -archs "$binary")" == "arm64" ]] || fail "updater binary is not arm64"
done
for binary in "$ENGINE" "$LAUNCHER"; do
  identifier="$(codesign -d --verbose=2 "$binary" 2>&1 | sed -n 's/^Identifier=//p' | head -1)"
  case "$binary" in
    *CovioUpdaterLauncher) expected="com.wyz.covio.updater.launcher" ;;
    *) expected="com.wyz.covio.updater" ;;
  esac
  [[ "$identifier" == "$expected" ]] || fail "unexpected updater identifier: $identifier"
done

release_id="$(plutil -extract CovioReleaseId raw -o - "$INFO")"
COVIO_UPDATER_TEST_MODE=1 \
COVIO_UPDATER_ROOT="$ROOT/build/updater-verify-root" \
COVIO_UPDATER_RELEASE_ID="$release_id" \
"$ENGINE" --selftest >/dev/null
"$LAUNCHER" --selftest

printf 'updater daemon verification passed\n'

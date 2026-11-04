#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/covio-macos-boundary-test.XXXXXX")"
APP="$TEMP_ROOT/Covio.app"
REPORT="$TEMP_ROOT/report.txt"

cleanup() {
  find "$TEMP_ROOT" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$APP/Contents/MacOS"
cp /usr/bin/true "$APP/Contents/MacOS/Covio"
chmod 0755 "$APP/Contents/MacOS/Covio"
cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Covio</string>
  <key>CFBundleIdentifier</key>
  <string>com.wyz.covio.boundary-test</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>
PLIST
/usr/bin/codesign --force --sign - "$APP" >/dev/null 2>&1

bash "$ROOT/scripts/verify-macos-artifact.sh" "$APP" "" "" "$REPORT" >/dev/null
grep -q '^result=pass$' "$REPORT"

mkdir -p "$APP/Contents/Frameworks/kmpDomain.framework"
if bash "$ROOT/scripts/verify-macos-artifact.sh" "$APP" "" "" "$REPORT" >/dev/null 2>&1; then
  printf 'Boundary test accepted a KMP framework.\n' >&2
  exit 1
fi
find "$APP/Contents/Frameworks" -depth -delete

mkdir -p "$APP/Contents/Resources"
touch "$APP/Contents/Resources/runtime.jar"
if bash "$ROOT/scripts/verify-macos-artifact.sh" "$APP" "" "" "$REPORT" >/dev/null 2>&1; then
  printf 'Boundary test accepted a JVM archive.\n' >&2
  exit 1
fi

printf 'macOS artifact boundary tests passed.\n'

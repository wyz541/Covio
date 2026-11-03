#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/covio-updater-test.XXXXXX")"
cleanup() {
  if [[ -d "$TEST_ROOT" ]]; then
    find "$TEST_ROOT" -depth -delete
  fi
}
trap cleanup EXIT

bash "$ROOT/scripts/build-covio-updater.sh"
ENGINE="$ROOT/build/updater/CovioUpdater"
LAUNCHER="$ROOT/build/updater/CovioUpdaterLauncher"
VALID="0.0.2.0-g$(printf 'a%.0s' {1..40})"
BAD="0.0.1.9-g$(printf 'b%.0s' {1..40})"
WRONG="0.0.2.0-g$(printf 'c%.0s' {1..40})"

printf '%s\n' 'case: engine selftest returns a fixed status'
STATUS="$(
  COVIO_UPDATER_ROOT="$TEST_ROOT/engine" \
  COVIO_UPDATER_RELEASE_ID="$VALID" \
  "$ENGINE" --selftest
)"
STATUS="$STATUS" python3 -I - "$VALID" <<'PY'
import json
import os
import sys
value = json.loads(os.environ["STATUS"])
assert value["releaseId"] == sys.argv[1]
assert value["state"] == "idle"
assert value["updaterProtocolVersion"] == 1
PY

printf '%s\n' 'case: launcher release ID checks'
"$LAUNCHER" --selftest

printf '%s\n' 'case: launcher rolls back to the previous engine after bad health'
mkdir -p "$TEST_ROOT/runtime/versions/$BAD" "$TEST_ROOT/runtime/versions/$VALID"
MOCK="$TEST_ROOT/mock-engine.sh"
cat > "$MOCK" <<'MOCK'
#!/bin/bash
set -euo pipefail
ROOT="${COVIO_UPDATER_ROOT:?}"
RELEASE="${COVIO_UPDATER_RELEASE_ID:?}"
if [[ "$RELEASE" == "${COVIO_UPDATER_TEST_BAD_RELEASE:?}" ]]; then
  HEALTH_RELEASE="${COVIO_UPDATER_TEST_WRONG_RELEASE:?}"
else
  HEALTH_RELEASE="$RELEASE"
fi
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$ROOT/health.json.tmp" <<JSON
{"createdAt":"$NOW","processIdentifier":$$,"releaseId":"$HEALTH_RELEASE","schemaVersion":1}
JSON
mv "$ROOT/health.json.tmp" "$ROOT/health.json"
sleep 2
MOCK
chmod 0755 "$MOCK"
ditto "$MOCK" "$TEST_ROOT/runtime/versions/$BAD/CovioUpdater"
ditto "$MOCK" "$TEST_ROOT/runtime/versions/$VALID/CovioUpdater"
chmod 0755 "$TEST_ROOT/runtime/versions/$BAD/CovioUpdater" "$TEST_ROOT/runtime/versions/$VALID/CovioUpdater"
printf '%s\n' "$BAD" > "$TEST_ROOT/runtime/current"
printf '%s\n' "$VALID" > "$TEST_ROOT/runtime/previous"
LAUNCHER_LOG="$TEST_ROOT/launcher.log"
COVIO_UPDATER_ROOT="$TEST_ROOT/runtime" \
COVIO_UPDATER_TEST_SKIP_VALIDATION=1 \
COVIO_UPDATER_TEST_EXIT_AFTER_HEALTHY=1 \
COVIO_UPDATER_TEST_BAD_RELEASE="$BAD" \
COVIO_UPDATER_TEST_WRONG_RELEASE="$WRONG" \
COVIO_UPDATER_HEALTH_TIMEOUT_MS=300 \
"$LAUNCHER" 2>"$LAUNCHER_LOG"
test "$(tr -d '[:space:]' < "$TEST_ROOT/runtime/current")" = "$VALID"
grep -Fq "rolled back to $VALID" "$LAUNCHER_LOG"

printf '%s\n' 'case: packaged updater layout is signed and fixed'
RELEASE_OUT="$TEST_ROOT/updater-release"
CONFIGURATION=Release CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
  COVIO_UPDATER_OUT_DIR="$RELEASE_OUT" \
  bash "$ROOT/scripts/build-covio-updater.sh" >/dev/null
PACKAGE_APP="$TEST_ROOT/packaged/Covio.app"
mkdir -p "$PACKAGE_APP/Contents"
plutil -create xml1 "$PACKAGE_APP/Contents/Info.plist" >/dev/null
plutil -insert CovioReleaseId -string "$VALID" "$PACKAGE_APP/Contents/Info.plist" >/dev/null
COVIO_UPDATER_OUT_DIR="$RELEASE_OUT" \
  bash "$ROOT/scripts/install-covio-updater.sh" "$PACKAGE_APP" >/dev/null
bash "$ROOT/scripts/verify-updater-daemon.sh" "$PACKAGE_APP" >/dev/null

printf '%s\n' 'case: LaunchDaemon uses the immutable launcher'
PLIST="$ROOT/macosApp/daemons/com.wyz.covio.updater.plist"
plutil -lint "$PLIST" >/dev/null
python3 -I - "$PLIST" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    value = plistlib.load(handle)
assert value["Label"] == "com.wyz.covio.updater"
assert value["MachServices"]["com.wyz.covio.updater.xpc"] is True
assert value["ProgramArguments"] == [
    "/Library/Application Support/Covio/Updater/bin/CovioUpdaterLauncher"
]
assert value["RunAtLoad"] is True
assert value["KeepAlive"] is True
assert value["ThrottleInterval"] == 10
PY

printf 'updater service tests passed\n'

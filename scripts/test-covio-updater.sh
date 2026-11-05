#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/covio-updater-test.XXXXXX")"
ACTIVE_XPC_LABEL=""
cleanup() {
  if [[ -n "$ACTIVE_XPC_LABEL" ]]; then
    launchctl bootout "gui/$(id -u)/$ACTIVE_XPC_LABEL" >/dev/null 2>&1 || true
  fi
  if [[ -d "$TEST_ROOT" ]]; then
    find "$TEST_ROOT" -depth -delete
  fi
}
trap cleanup EXIT

bash "$ROOT/scripts/build-covio-updater.sh"
ENGINE="$ROOT/build/updater/CovioUpdater"
LAUNCHER="$ROOT/build/updater/CovioUpdaterLauncher"
VALID="0.6.0-internal.24-g$(printf 'a%.0s' {1..40})"
BAD="0.6.0-internal.23-g$(printf 'b%.0s' {1..40})"
WRONG="0.6.0-internal.24-g$(printf 'c%.0s' {1..40})"

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

printf '%s\n' 'case: launcher preflight failure rolls back to the previous engine'
mkdir -p "$TEST_ROOT/runtime/versions/$BAD" "$TEST_ROOT/runtime/versions/$VALID"
MOCK="$TEST_ROOT/mock-engine.sh"
cat > "$MOCK" <<'MOCK'
#!/bin/bash
set -euo pipefail
RELEASE="${COVIO_UPDATER_RELEASE_ID:?}"
if [[ "$RELEASE" == "${COVIO_UPDATER_TEST_BAD_RELEASE:?}" ]]; then
  exit 1
fi
if [[ "${1:-}" == "--selftest" ]]; then
  printf '{"schemaVersion":1,"updaterProtocolVersion":1,"releaseId":"%s","state":"idle","automaticUpdatesEnabled":false,"lastCheckAt":null,"availableVersion":null,"message":null}\n' "$RELEASE"
  exit 0
fi
sleep 1
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
COVIO_UPDATER_TEST_BAD_RELEASE="$BAD" \
COVIO_UPDATER_HEALTH_TIMEOUT_MS=300 \
"$LAUNCHER" 2>"$LAUNCHER_LOG"
test "$(tr -d '[:space:]' < "$TEST_ROOT/runtime/current")" = "$VALID"
grep -Fq "rolled back to $VALID" "$LAUNCHER_LOG"

printf '%s\n' 'case: launchd job exposes updater XPC through the exec path'
XPC_ROOT="$TEST_ROOT/xpc-runtime"
mkdir -p "$XPC_ROOT/versions/$VALID"
cp "$ENGINE" "$XPC_ROOT/versions/$VALID/CovioUpdater"
chmod 0755 "$XPC_ROOT/versions/$VALID/CovioUpdater"
printf '%s\n' "$VALID" > "$XPC_ROOT/current"
printf '%s\n' 'identifier "com.wyz.covio"' > "$XPC_ROOT/updater-client-requirement"
printf '%s\n' 'identifier "com.wyz.covio.updater"' > "$XPC_ROOT/updater-requirement"
XPC_SERVICE="com.wyz.covio.updater.xpctest.$$"
XPC_LABEL="com.wyz.covio.updater.xpctest.$$"
XPC_PLIST="$TEST_ROOT/$XPC_LABEL.plist"
XPC_CLIENT="$TEST_ROOT/xpc-client"
cat > "$TEST_ROOT/xpc-client.swift" <<'CLIENT'
import Foundation

@objc protocol CovioUpdaterXPCProtocol {
    func getStatus(withReply reply: @escaping (Data) -> Void)
}

func finish(_ code: Int32, _ message: String) -> Never {
    print(message)
    fflush(stdout)
    exit(code)
}

let environment = ProcessInfo.processInfo.environment
let serviceName = environment["COVIO_XPC_TEST_SERVICE"]!
let connection = NSXPCConnection(machServiceName: serviceName, options: [])
connection.remoteObjectInterface = NSXPCInterface(with: CovioUpdaterXPCProtocol.self)
connection.setCodeSigningRequirement(environment["COVIO_XPC_TEST_SERVER_REQUIREMENT"]!)
connection.resume()
guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
    finish(4, "client error: \(error)")
}) as? CovioUpdaterXPCProtocol else {
    finish(5, "client proxy unavailable")
}
proxy.getStatus { data in
    finish(0, String(decoding: data, as: UTF8.self))
}
DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
    finish(2, "client timeout")
}
RunLoop.main.run()
CLIENT
xcrun swiftc "$TEST_ROOT/xpc-client.swift" -o "$XPC_CLIENT"
codesign --force --sign - --identifier com.wyz.covio "$XPC_CLIENT"
cat > "$XPC_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$XPC_LABEL</string>
<key>ProgramArguments</key><array><string>$LAUNCHER</string></array>
<key>MachServices</key><dict><key>$XPC_SERVICE</key><true/></dict>
<key>EnvironmentVariables</key><dict>
<key>COVIO_UPDATER_ROOT</key><string>$XPC_ROOT</string>
<key>COVIO_UPDATER_TEST_SKIP_VALIDATION</key><string>1</string>
<key>COVIO_UPDATER_DISABLE_SCHEDULER</key><string>1</string>
<key>COVIO_UPDATER_XPC_SERVICE_NAME</key><string>$XPC_SERVICE</string>
<key>COVIO_UPDATER_STABILITY_DELAY_SECONDS</key><string>1</string>
<key>COVIO_UPDATER_HEALTH_TIMEOUT_MS</key><string>3000</string>
</dict>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>2</integer>
</dict></plist>
EOF
ACTIVE_XPC_LABEL="$XPC_LABEL"
launchctl bootstrap "gui/$(id -u)" "$XPC_PLIST"
for _ in $(seq 1 50); do
  [[ -f "$XPC_ROOT/health.json" ]] && break
  sleep 0.1
done
[[ -f "$XPC_ROOT/health.json" ]]
XPC_STATUS="$(
  COVIO_XPC_TEST_SERVICE="$XPC_SERVICE" \
  COVIO_XPC_TEST_SERVER_REQUIREMENT="$(cat "$XPC_ROOT/updater-requirement")" \
  "$XPC_CLIENT"
)"
XPC_STATUS="$XPC_STATUS" python3 -I - "$VALID" <<'PY'
import json
import os
import sys
value = json.loads(os.environ["XPC_STATUS"])
assert value["releaseId"] == sys.argv[1]
assert value["state"] == "idle"
assert value["updaterProtocolVersion"] == 1
PY
launchctl bootout "gui/$(id -u)/$XPC_LABEL"
ACTIVE_XPC_LABEL=""

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

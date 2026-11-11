#!/bin/bash
set -euo pipefail

# 在本地 Apple Silicon Mac 的 iOS 模拟器运行 Swift 和 C ABI 测试。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/ios-xcode-dd"
PROJECT="$ROOT/iosApp/Covio.xcodeproj"
SCHEME="Covio"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This script requires macOS with Xcode.\n' >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  printf 'Missing xcodebuild. Install Xcode.\n' >&2
  exit 1
fi

if [[ -n "${IOS_TEST_DESTINATION:-}" ]]; then
  DESTINATION="$IOS_TEST_DESTINATION"
else
  DEVICE_ID="$(
    xcrun simctl list devices available --json |
      python3 -c 'import json,sys; data=json.load(sys.stdin)["devices"]; ids=[d["udid"] for runtime in data.values() for d in runtime if d.get("isAvailable") and d.get("name", "").startswith("iPhone")]; print(ids[-1] if ids else "")'
  )"
  if [[ -z "$DEVICE_ID" ]]; then
    printf 'No available iPhone simulator found. Set IOS_TEST_DESTINATION.\n' >&2
    exit 1
  fi
  DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"
fi

cd "$ROOT"
plutil -lint "$PROJECT/project.pbxproj"
python3 -I "$ROOT/scripts/validate-ios-project.py"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "$DESTINATION" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  test

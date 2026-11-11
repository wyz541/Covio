#!/bin/bash
set -euo pipefail

# 构建 iOS SwiftUI 宿主。默认构建 Apple Silicon 模拟器目标。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$ROOT/build/ios-xcode-dd"
PROJECT="$ROOT/iosApp/Covio.xcodeproj"
SCHEME="Covio"
DESTINATION="${IOS_DESTINATION:-generic/platform=iOS Simulator}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This script requires macOS with Xcode.\n' >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  printf 'Missing xcodebuild. Install Xcode.\n' >&2
  exit 1
fi

cd "$ROOT"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "$DESTINATION" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  build

printf 'Built iOS app with configuration %s\n' "$CONFIGURATION"

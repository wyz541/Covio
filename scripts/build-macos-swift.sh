#!/bin/bash
set -euo pipefail

# 构建 macOS SwiftUI 宿主。
#
# Rust core 由 Xcode 工程里的 "Build Rust core" 脚本阶段产出。
# 本脚本负责调用 xcodebuild。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="$ROOT/build/xcode-dd"
PROJECT="$ROOT/macosApp/Covio.xcodeproj"
SCHEME="Covio"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This script requires macOS.\n' >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  printf 'Missing xcodebuild. Install Xcode.\n' >&2
  exit 1
fi

cd "$ROOT"

python3 -I "$ROOT/scripts/release_manifest.py" check
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
RELEASE_ID="$(python3 -I "$ROOT/scripts/release_manifest.py" release-id --commit "$COMMIT")"

# 本机有证书时把签名身份固定成证书。没有就保持工程默认的 ad-hoc。
# 不固定的话每次构建换一个 cdhash，系统会把新构建当成新应用重新要权限。
bash "$ROOT/scripts/setup-local-signing.sh"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  COVIO_GIT_COMMIT="$COMMIT" \
  COVIO_RELEASE_ID="$RELEASE_ID" \
  build

APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/Covio.app"
if [[ ! -d "$APP" ]]; then
  printf 'Missing app bundle: %s\n' "$APP" >&2
  exit 1
fi

SIGNING_BASELINE="$DERIVED_DATA/development-signing-$CONFIGURATION-build.json"
if [[ -f "$ROOT/macosApp/Signing.local.xcconfig" || -f "$SIGNING_BASELINE" ]]; then
  python3 -I "$ROOT/scripts/verify_macos_signing.py" \
    "$APP" \
    --require-stable \
    --baseline "$SIGNING_BASELINE"
else
  python3 -I "$ROOT/scripts/verify_macos_signing.py" "$APP"
fi

printf 'Built %s\n' "$APP"

#!/bin/bash
set -euo pipefail

# Build and export a signed iOS device IPA with the release identity.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
PROJECT="$ROOT/iosApp/Covio.xcodeproj"
SCHEME="Covio"
WORK_DIR="$ROOT/build/ios-release"
ARCHIVE_PATH="$WORK_DIR/Covio.xcarchive"
EXPORT_DIR="$WORK_DIR/export"
IPA_METADATA="$DIST/ios-package.json"
TEAM_ID="${COVIO_IOS_TEAM_ID:-}"
SIGNING_STYLE="${COVIO_IOS_SIGNING_STYLE:-automatic}"
EXPORT_METHOD="${COVIO_IOS_EXPORT_METHOD:-development}"
EXPORT_OPTIONS="${COVIO_IOS_EXPORT_OPTIONS_PLIST:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This script requires macOS with Xcode.\n' >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  printf 'Missing xcodebuild. Install Xcode.\n' >&2
  exit 1
fi
if [[ -z "$TEAM_ID" ]]; then
  printf 'Set COVIO_IOS_TEAM_ID to the Apple development team ID.\n' >&2
  exit 1
fi
if [[ "$SIGNING_STYLE" != "automatic" && "$SIGNING_STYLE" != "manual" ]]; then
  printf 'COVIO_IOS_SIGNING_STYLE must be automatic or manual.\n' >&2
  exit 1
fi
if [[ "$EXPORT_METHOD" != "development" && "$EXPORT_METHOD" != "ad-hoc" && "$EXPORT_METHOD" != "app-store" && "$EXPORT_METHOD" != "app-store-connect" ]]; then
  printf 'COVIO_IOS_EXPORT_METHOD must be development, ad-hoc, app-store or app-store-connect.\n' >&2
  exit 1
fi

cd "$ROOT"
python3 -I "$ROOT/scripts/release_manifest.py" check-clean
PRODUCT_VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value productVersion)"
VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value clientVersion)"
BUILD_NUMBER="$(python3 -I "$ROOT/scripts/release_manifest.py" value buildNumber)"
CHANNEL="$(python3 -I "$ROOT/scripts/release_manifest.py" value channel)"
PROTOCOL_VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value helperProtocolVersion)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
RELEASE_ID="$(python3 -I "$ROOT/scripts/release_manifest.py" release-id --commit "$COMMIT")"
IPA_NAME="Covio-$VERSION-ios-arm64.ipa"
IPA_PATH="$DIST/$IPA_NAME"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$EXPORT_DIR" "$DIST"
if [[ -z "$EXPORT_OPTIONS" ]]; then
  EXPORT_OPTIONS="$WORK_DIR/ExportOptions.plist"
  python3 -I - "$EXPORT_OPTIONS" "$EXPORT_METHOD" "$TEAM_ID" "$SIGNING_STYLE" <<'PY'
import plistlib
import sys

path, method, team, signing_style = sys.argv[1:]
options = {
    "method": method,
    "signingStyle": signing_style,
    "teamID": team,
    "destination": "export",
    "stripSwiftSymbols": True,
    "compileBitcode": False,
}
with open(path, "wb") as stream:
    plistlib.dump(options, stream)
PY
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$WORK_DIR/DerivedData" \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE="$SIGNING_STYLE" \
  MARKETING_VERSION="$PRODUCT_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  COVIO_CLIENT_VERSION="$VERSION" \
  COVIO_PRODUCT_VERSION="$PRODUCT_VERSION" \
  COVIO_RELEASE_CHANNEL="$CHANNEL" \
  COVIO_GIT_COMMIT="$COMMIT" \
  COVIO_RELEASE_ID="$RELEASE_ID" \
  COVIO_HELPER_PROTOCOL_VERSION="$PROTOCOL_VERSION" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

EXPORTED_IPAS=()
while IFS= read -r exported_ipa; do
  EXPORTED_IPAS+=("$exported_ipa")
done < <(find "$EXPORT_DIR" -maxdepth 1 -type f -name '*.ipa' -print)
if [[ "${#EXPORTED_IPAS[@]}" -ne 1 ]]; then
  printf 'Expected one exported IPA, found %s.\n' "${#EXPORTED_IPAS[@]}" >&2
  exit 1
fi
cp "${EXPORTED_IPAS[0]}" "$IPA_PATH"

VERIFY_DIR="$WORK_DIR/verify"
rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"
/usr/bin/ditto -x -k "$IPA_PATH" "$VERIFY_DIR"
APP_PATH="$(find "$VERIFY_DIR/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  printf 'The exported IPA has no Payload app bundle.\n' >&2
  exit 1
fi
if [[ ! -f "$APP_PATH/embedded.mobileprovision" ]]; then
  printf 'The exported app has no embedded provisioning profile.\n' >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
SIGNATURE_REPORT="$(/usr/bin/codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
if ! grep -q "TeamIdentifier=$TEAM_ID" <<<"$SIGNATURE_REPORT"; then
  printf 'The exported app signing team does not match COVIO_IOS_TEAM_ID.\n' >&2
  exit 1
fi
if ! grep -Eq 'Authority=Apple (Development|Distribution):' <<<"$SIGNATURE_REPORT"; then
  printf 'The exported app is not signed by Apple Development or Apple Distribution.\n' >&2
  exit 1
fi
python3 -I - "$APP_PATH/Info.plist" "$PRODUCT_VERSION" "$VERSION" "$BUILD_NUMBER" "$CHANNEL" "$COMMIT" "$RELEASE_ID" "$PROTOCOL_VERSION" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as stream:
    info = plistlib.load(stream)
expected = {
    "CFBundleIdentifier": "com.wyz.covio.ios",
    "CFBundleShortVersionString": sys.argv[2],
    "CFBundleVersion": sys.argv[4],
    "CovioClientVersion": sys.argv[3],
    "CovioProductVersion": sys.argv[2],
    "CovioReleaseChannel": sys.argv[5],
    "CovioGitCommit": sys.argv[6],
    "CovioReleaseId": sys.argv[7],
    "CovioHelperProtocolVersion": sys.argv[8],
}
for key, value in expected.items():
    if str(info.get(key)) != value:
        raise SystemExit(f"iOS Info.plist {key} is {info.get(key)!r}, expected {value!r}")
PY

python3 -I - "$IPA_METADATA" "$IPA_PATH" "$PRODUCT_VERSION" "$VERSION" "$BUILD_NUMBER" "$CHANNEL" "$COMMIT" "$RELEASE_ID" "$TEAM_ID" "$EXPORT_METHOD" <<'PY'
import hashlib
import json
import pathlib
import sys

metadata_path = pathlib.Path(sys.argv[1])
ipa = pathlib.Path(sys.argv[2])
digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
payload = {
    "schemaVersion": 1,
    "platform": "ios",
    "productVersion": sys.argv[3],
    "clientVersion": sys.argv[4],
    "buildNumber": int(sys.argv[5]),
    "channel": sys.argv[6],
    "gitCommit": sys.argv[7],
    "releaseId": sys.argv[8],
    "bundleIdentifier": "com.wyz.covio.ios",
    "artifact": {
        "name": ipa.name,
        "size": ipa.stat().st_size,
        "sha256": digest,
    },
    "signing": {
        "style": sys.argv[10],
        "teamIdentifier": sys.argv[9],
    },
}
metadata_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

printf 'iOS device IPA: %s\n' "$IPA_PATH"
printf 'iOS package metadata: %s\n' "$IPA_METADATA"

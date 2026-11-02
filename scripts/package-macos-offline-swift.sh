#!/bin/bash
set -euo pipefail

# 在默认瘦 app 上加入已校验模型，生成可选离线 DMG。
# 该脚本必须在 package-macos-swift.sh 之后运行。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="Covio"
OFFLINE_APP="$DIST/$APP_NAME-Offline.app"
APP_ID="com.wyz.covio"
MODEL_MANIFEST="$ROOT/macosApp/src/AutoNaming/FileNamingModelManifest.json"
MODEL_VERIFY="$ROOT/scripts/file_naming_model.py"
RELEASE_MANIFEST="$DIST/release-manifest.json"
FILE_NAMING_MODEL_DIR="${COVIO_FILE_NAMING_MODEL_DIR:-}"
RELEASE_SIGN_IDENTITY="${COVIO_CODE_SIGN_IDENTITY:-}"
DEVELOPMENT_TEAM="${COVIO_DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${COVIO_NOTARY_PROFILE:-}"
REQUIRE_STABLE_SIGNING="${COVIO_REQUIRE_STABLE_SIGNING:-0}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This script requires macOS.\n' >&2
  exit 1
fi
if [[ -z "$FILE_NAMING_MODEL_DIR" ]]; then
  printf 'Set COVIO_FILE_NAMING_MODEL_DIR to the verified local model directory.\n' >&2
  printf 'Run python3 scripts/file_naming_model.py download <directory> first.\n' >&2
  exit 1
fi
python3 -I "$MODEL_VERIFY" --manifest "$MODEL_MANIFEST" verify-directory "$FILE_NAMING_MODEL_DIR"

python3 -I "$ROOT/scripts/release_manifest.py" check-clean
VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value clientVersion)"
CHANNEL="$(python3 -I "$ROOT/scripts/release_manifest.py" value channel)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
INTERNAL_SIGNING_BASELINE="$ROOT/build/internal-signing-$APP_ID.json"
DEFAULT_DMG="$DIST/$APP_NAME-$VERSION.dmg"
DEFAULT_APP="$DIST/$APP_NAME.app"
OFFLINE_DMG="$DIST/$APP_NAME-Offline-$VERSION.dmg"
HELPER="$OFFLINE_APP/Contents/MacOS/CovioHelper"
RUNTIME_DIRECTORY="$(python3 -I - "$MODEL_MANIFEST" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    print(json.load(stream)["runtimeDirectory"])
PY
)"

if [[ ! -d "$DEFAULT_APP" || ! -f "$DEFAULT_DMG" || ! -f "$RELEASE_MANIFEST" ]]; then
  printf 'Run scripts/package-macos-swift.sh before offline packaging.\n' >&2
  exit 1
fi
python3 -I "$ROOT/scripts/release_manifest.py" verify-artifact \
  "$RELEASE_MANIFEST" \
  --helper "$DEFAULT_APP/Contents/MacOS/CovioHelper"

if [[ "$CHANNEL" == "internal" && -z "$RELEASE_SIGN_IDENTITY" ]]; then
  if LOCAL_IDENTITY="$(bash "$ROOT/scripts/setup-local-signing.sh" --print-identity 2>/dev/null)"; then
    RELEASE_SIGN_IDENTITY="$LOCAL_IDENTITY"
    printf 'Internal offline package signing identity: %s\n' "$RELEASE_SIGN_IDENTITY"
  elif [[ "$REQUIRE_STABLE_SIGNING" == "1" ]]; then
    printf 'Internal release packaging requires a stable local signing identity.\n' >&2
    printf 'Run bash scripts/setup-local-signing.sh and see docs/adr/adr-0005-local-code-signing.md.\n' >&2
    exit 1
  else
    printf 'No local signing identity; internal offline package will use ad-hoc signing.\n' >&2
  fi
fi
if [[ "$CHANNEL" == "internal" && "$REQUIRE_STABLE_SIGNING" == "1" && ( -z "$RELEASE_SIGN_IDENTITY" || "$RELEASE_SIGN_IDENTITY" == "-" ) ]]; then
  printf 'Internal release packaging requires a stable local signing identity.\n' >&2
  printf 'Run bash scripts/setup-local-signing.sh and see docs/adr/adr-0005-local-code-signing.md.\n' >&2
  exit 1
fi

release_codesign() {
  if [[ "$CHANNEL" == "public" ]]; then
    /usr/bin/codesign --options runtime "$@"
  else
    /usr/bin/codesign "$@"
  fi
}

if [[ "$CHANNEL" == "public" ]]; then
  if [[ -z "$RELEASE_SIGN_IDENTITY" || "$RELEASE_SIGN_IDENTITY" == "-" ]]; then
    printf 'Public packaging requires COVIO_CODE_SIGN_IDENTITY.\n' >&2
    exit 1
  fi
  if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    printf 'Public packaging requires COVIO_DEVELOPMENT_TEAM.\n' >&2
    exit 1
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    printf 'Public packaging requires COVIO_NOTARY_PROFILE.\n' >&2
    exit 1
  fi
fi

if [[ -d "$OFFLINE_APP" ]]; then
  find "$OFFLINE_APP" -depth -delete
fi
if [[ -e "$OFFLINE_DMG" ]]; then
  unlink "$OFFLINE_DMG"
fi
mkdir -p "$DIST"

/usr/bin/ditto "$DEFAULT_APP" "$OFFLINE_APP"
MODEL_RESOURCE="$OFFLINE_APP/Contents/Resources/$RUNTIME_DIRECTORY"
mkdir -p "$MODEL_RESOURCE"
/usr/bin/ditto "$FILE_NAMING_MODEL_DIR" "$MODEL_RESOURCE"
if ! cmp -s \
  "$MODEL_MANIFEST" \
  "$OFFLINE_APP/Contents/Resources/FileNamingModelManifest.json"; then
  printf 'Offline app model manifest differs from the source manifest.\n' >&2
  exit 1
fi
python3 -I "$MODEL_VERIFY" --manifest "$MODEL_MANIFEST" verify-directory "$MODEL_RESOURCE"

if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  release_codesign \
    --force \
    --timestamp \
    --sign "$RELEASE_SIGN_IDENTITY" \
    "$OFFLINE_APP"
else
  # The model changes the app resources, not the already signed helper.
  /usr/bin/codesign --force --sign - "$OFFLINE_APP"
fi
/usr/bin/codesign --verify --deep --strict "$OFFLINE_APP"

if [[ "$CHANNEL" == "internal" && -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  python3 -I "$ROOT/scripts/verify_macos_signing.py" \
    "$OFFLINE_APP" \
    --require-stable \
    --baseline "$INTERNAL_SIGNING_BASELINE"
fi

bash "$ROOT/scripts/verify-helper-daemon.sh" "$OFFLINE_APP" --require-manifest

notarize_and_staple() {
  local target="$1"
  local submit_path="$2"
  printf 'Submitting %s for notarization\n' "$target"
  /usr/bin/xcrun notarytool submit "$submit_path" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  /usr/bin/xcrun stapler staple "$target"
  /usr/bin/xcrun stapler validate "$target"
}

if [[ -n "$NOTARY_PROFILE" ]]; then
  OFFLINE_NOTARY_ZIP="$DIST/$APP_NAME-Offline-$VERSION-notary.zip"
  /usr/bin/ditto -c -k --keepParent "$OFFLINE_APP" "$OFFLINE_NOTARY_ZIP"
  notarize_and_staple "$OFFLINE_APP" "$OFFLINE_NOTARY_ZIP"
  unlink "$OFFLINE_NOTARY_ZIP"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto "$OFFLINE_APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
/usr/sbin/diskutil image create from \
  --format UDZO \
  --volumeName "$APP_NAME" \
  "$STAGE" \
  "$OFFLINE_DMG" >/dev/null
/usr/bin/hdiutil verify "$OFFLINE_DMG" >/dev/null

if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$RELEASE_SIGN_IDENTITY" "$OFFLINE_DMG"
  /usr/bin/codesign --verify --strict "$OFFLINE_DMG"
fi
if [[ -n "$NOTARY_PROFILE" ]]; then
  notarize_and_staple "$OFFLINE_DMG" "$OFFLINE_DMG"
fi

python3 -I "$ROOT/scripts/release_manifest.py" generate-artifact \
  --helper "$HELPER" \
  --default-dmg "$DEFAULT_DMG" \
  --offline-dmg "$OFFLINE_DMG" \
  --model-manifest "$MODEL_MANIFEST" \
  --output "$RELEASE_MANIFEST" \
  --commit "$COMMIT"

APP_BYTES="$(du -sk "$OFFLINE_APP" | awk '{print $1 * 1024}')"
DMG_BYTES="$(stat -f %z "$OFFLINE_DMG")"
printf 'Created %s\n' "$OFFLINE_APP"
printf 'App bytes: %s\n' "$APP_BYTES"
printf 'Created %s\n' "$OFFLINE_DMG"
printf 'DMG bytes: %s\n' "$DMG_BYTES"

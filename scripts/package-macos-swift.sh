#!/bin/bash
set -euo pipefail

# 打包 macOS SwiftUI 宿主为 DMG。
#
# 这条链路不经过 jpackage：发布物由 Xcode 归档产出，不再是 jar 加 app-image。
#
# 发布身份只有一个来源：release/release-manifest.json。
# 生成文件与工作树由 release_manifest.py 校验。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/release-cache.sh
source "$ROOT/scripts/release-cache.sh"
DIST="$ROOT/dist"
PROJECT="$ROOT/macosApp/Covio.xcodeproj"
SCHEME="Covio"
CONFIGURATION="Release"
DERIVED_DATA="$(release_derived_data_path "$ROOT")"
SOURCE_PACKAGES_DIR="$(release_source_packages_path "$ROOT")"
APP_NAME="Covio"
APP_ID="com.wyz.covio"
ICON="$ROOT/macosApp/src/Covio.icns"
APP_IMAGE="$DIST/$APP_NAME.app"
OFFLINE_APP="$DIST/$APP_NAME-Offline.app"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
RELEASE_SIGN_IDENTITY="${COVIO_CODE_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${COVIO_INSTALLER_SIGN_IDENTITY:-}"
DEVELOPMENT_TEAM="${COVIO_DEVELOPMENT_TEAM:-}"
NOTARY_PROFILE="${COVIO_NOTARY_PROFILE:-}"
REQUIRE_STABLE_SIGNING="${COVIO_REQUIRE_STABLE_SIGNING:-0}"
CLEANUP_PATHS=()
SECONDS=0
PHASE_START=0

phase_done() {
  local name="$1"
  local elapsed=$((SECONDS - PHASE_START))
  printf 'phase %-20s %4ss\n' "$name" "$elapsed"
  PHASE_START=$SECONDS
}

# Release worktrees share DerivedData and SwiftPM checkouts.
# One lock prevents concurrent packaging jobs from changing those caches.
mkdir -p "$(dirname "$DERIVED_DATA")" "$(dirname "$SOURCE_PACKAGES_DIR")"
CACHE_LOCK_PATH="$DERIVED_DATA.lock"
if ! /usr/bin/shlock -f "$CACHE_LOCK_PATH" -p $$; then
  printf 'Release build cache is in use: %s\n' "$DERIVED_DATA" >&2
  exit 1
fi
CLEANUP_PATHS+=("$CACHE_LOCK_PATH")

cleanup_temporary_paths() {
  local path
  for path in "${CLEANUP_PATHS[@]:-}"; do
    if [[ -n "$path" && -e "$path" ]]; then
      find "$path" -depth -delete
    fi
  done
}
trap cleanup_temporary_paths EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This script requires macOS.\n' >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  printf 'Missing xcodebuild. Install Xcode.\n' >&2
  exit 1
fi

if [[ ! -f "$ICON" ]]; then
  printf 'Missing icon: %s\n' "$ICON" >&2
  exit 1
fi
python3 -I "$ROOT/scripts/release_manifest.py" check-clean
VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value clientVersion)"
PRODUCT_VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value productVersion)"
BUILD_NUMBER="$(python3 -I "$ROOT/scripts/release_manifest.py" value buildNumber)"
CHANNEL="$(python3 -I "$ROOT/scripts/release_manifest.py" value channel)"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
RELEASE_ID="$(python3 -I "$ROOT/scripts/release_manifest.py" release-id --commit "$COMMIT")"
INTERNAL_SIGNING_BASELINE="$DERIVED_DATA/internal-signing-$APP_ID.json"
DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
APP_ZIP="$DIST/$APP_NAME-$VERSION.app.zip"
UPDATE_ZIP="$DIST/CovioUpdate-$VERSION.zip"
PKG_PATH="$DIST/$APP_NAME-$VERSION.pkg"
TRANSACTION_ID="client-$VERSION-${COMMIT:0:12}"
STAGED_APP_RELATIVE="Library/Application Support/Covio/Installer/staged/$APP_NAME.app"
STAGED_APP_PATH="/$STAGED_APP_RELATIVE"
OFFLINE_DMG="$DIST/$APP_NAME-Offline-$VERSION.dmg"
UPDATER_OUT_DIR="$ROOT/build/updater-release"

if [[ "$CHANNEL" == "internal" && -z "$RELEASE_SIGN_IDENTITY" ]]; then
  if LOCAL_IDENTITY="$(bash "$ROOT/scripts/setup-local-signing.sh" --print-identity 2>/dev/null)"; then
    RELEASE_SIGN_IDENTITY="$LOCAL_IDENTITY"
    printf 'Internal package signing identity: %s\n' "$RELEASE_SIGN_IDENTITY"
  elif [[ "$REQUIRE_STABLE_SIGNING" == "1" ]]; then
    printf 'Internal release packaging requires a stable local signing identity.\n' >&2
    printf 'Run bash scripts/setup-local-signing.sh and see docs/adr/adr-0005-local-code-signing.md.\n' >&2
    exit 1
  else
    printf 'No local signing identity; internal package will use ad-hoc signing.\n' >&2
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
  if [[ -z "$INSTALLER_SIGN_IDENTITY" ]]; then
    printf 'Public packaging requires COVIO_INSTALLER_SIGN_IDENTITY.\n' >&2
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

if [[ -d "$APP_IMAGE" ]]; then
  find "$APP_IMAGE" -depth -delete
fi
if [[ -d "$OFFLINE_APP" ]]; then
  find "$OFFLINE_APP" -depth -delete
fi
for artifact in "$DMG_PATH" "$APP_ZIP" "$UPDATE_ZIP" "$PKG_PATH" "$OFFLINE_DMG"; do
  if [[ -e "$artifact" ]]; then
    unlink "$artifact"
  fi
done
mkdir -p "$DIST"

cd "$ROOT"

# ARCHS 在工程里也写死为 arm64：Rust core 和 helper 都只产出 arm64。
# 这里再传一次，任何人从命令行归档都得到同样的结果。
XCODE_SIGN_ARGS=()
if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  XCODE_SIGN_ARGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$RELEASE_SIGN_IDENTITY"
  )
  if [[ -n "$DEVELOPMENT_TEAM" ]]; then
    XCODE_SIGN_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")
  fi
else
  XCODE_SIGN_ARGS+=(CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY=-)
fi

phase_done "setup"

XCODE_COMMON_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA"
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR"
  -skipMacroValidation
  -skipPackagePluginValidation
  -destination 'generic/platform=macOS'
  ARCHS=arm64
  ONLY_ACTIVE_ARCH=NO
)

printf 'Release DerivedData: %s\n' "$DERIVED_DATA"
printf 'SwiftPM cache:       %s\n' "$SOURCE_PACKAGES_DIR"

xcodebuild "${XCODE_COMMON_ARGS[@]}" -resolvePackageDependencies
phase_done "package resolve"

xcodebuild \
  "${XCODE_COMMON_ARGS[@]}" \
  MARKETING_VERSION="$PRODUCT_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  COVIO_CLIENT_VERSION="$VERSION" \
  COVIO_PRODUCT_VERSION="$PRODUCT_VERSION" \
  COVIO_GIT_COMMIT="$COMMIT" \
  COVIO_RELEASE_ID="$RELEASE_ID" \
  "${XCODE_SIGN_ARGS[@]}" \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
  printf 'Release build has no app bundle: %s\n' "$BUILT_APP" >&2
  exit 1
fi

# ditto 保留符号链接与扩展属性。cp -R 会丢掉 framework 里的版本链接。
/usr/bin/ditto "$BUILT_APP" "$APP_IMAGE"
phase_done "xcode build"

CONFIGURATION=Release \
CODE_SIGN_IDENTITY="$RELEASE_SIGN_IDENTITY" \
COVIO_UPDATER_OUT_DIR="$UPDATER_OUT_DIR" \
bash "$ROOT/scripts/build-covio-updater.sh"
COVIO_UPDATER_OUT_DIR="$UPDATER_OUT_DIR" \
bash "$ROOT/scripts/install-covio-updater.sh" "$APP_IMAGE"
phase_done "updater"

# 默认包只携带模型清单和许可证。模型权重由离线包或首次使用下载提供。
for model_manifest in "$ROOT"/macosApp/src/AutoNaming/FileNamingModelManifest*.json; do
  manifest_name="$(basename "$model_manifest")"
  if ! cmp -s "$model_manifest" "$APP_IMAGE/Contents/Resources/$manifest_name"; then
    printf 'Model manifest is missing or differs from its source: %s\n' "$manifest_name" >&2
    exit 1
  fi
done
if [[ -n "$(find "$APP_IMAGE/Contents/Resources/Models" -name '*.safetensors' -type f -print -quit 2>/dev/null)" ]]; then
  printf 'Default app bundle must not contain model weights.\n' >&2
  exit 1
fi

NOTICES_DIR="$APP_IMAGE/Contents/Resources/ThirdPartyNotices"
mkdir -p "$NOTICES_DIR/licenses" "$NOTICES_DIR/model"
/usr/bin/ditto "$ROOT/LICENSE" "$APP_IMAGE/Contents/Resources/LICENSE"
/usr/bin/ditto "$ROOT/THIRD_PARTY_NOTICES.md" "$NOTICES_DIR/THIRD_PARTY_NOTICES.md"
/usr/bin/ditto "$ROOT/third_party/licenses" "$NOTICES_DIR/licenses"
for model_notice_name in \
  Qwen3-VL-2B-Instruct \
  Qwen3-VL-4B-Instruct \
  Qwen3-VL-8B-Instruct \
  Qwen3-VL-30B-A3B-Instruct
do
  model_notice="$ROOT/third_party/models/$model_notice_name"
  if [[ ! -d "$model_notice" ]]; then
    printf 'Missing model notice directory: %s\n' "$model_notice_name" >&2
    exit 1
  fi
  if [[ ! -f "$model_notice/LICENSE" || ! -f "$model_notice/NOTICE" ]]; then
    printf 'Model notice directory is incomplete: %s\n' "$model_notice_name" >&2
    exit 1
  fi
  /usr/bin/ditto "$model_notice" "$NOTICES_DIR/model/$model_notice_name"
done

PLIST="$APP_IMAGE/Contents/Info.plist"
HELPER="$APP_IMAGE/Contents/MacOS/CovioHelper"
DAEMON_PLIST="$APP_IMAGE/Contents/Library/LaunchDaemons/com.wyz.covio.helper.plist"
UPDATER_ENGINE="$APP_IMAGE/Contents/MacOS/CovioUpdater"
UPDATER_LAUNCHER="$APP_IMAGE/Contents/MacOS/CovioUpdaterLauncher"
UPDATER_PLIST="$APP_IMAGE/Contents/Library/LaunchDaemons/com.wyz.covio.updater.plist"

read_plist() {
  "$PLIST_BUDDY" -c "Print :$1" "$PLIST" 2>/dev/null || true
}

# 包内的键只断言，不回写。
# 回写会造出第二个版本来源。
require_plist() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(read_plist "$key")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Bundle key %s is %s, expected %s. Check macosApp/src/Info.plist.\n' \
      "$key" "${actual:-<missing>}" "$expected" >&2
    exit 1
  fi
}

# 产品版本进入 MARKETING_VERSION。完整 SemVer 进入自定义版本身份。
require_plist CFBundleShortVersionString "$PRODUCT_VERSION"
require_plist CFBundleVersion "$BUILD_NUMBER"
require_plist CovioClientVersion "$VERSION"
require_plist CovioProductVersion "$PRODUCT_VERSION"
require_plist CovioReleaseChannel "$CHANNEL"
require_plist CovioGitCommit "$COMMIT"
require_plist CovioReleaseId "$RELEASE_ID"
require_plist CovioHelperProtocolVersion "$(python3 -I "$ROOT/scripts/release_manifest.py" value helperProtocolVersion)"
require_plist CovioInstallTransactionVersion "1"
require_plist CFBundleIdentifier "$APP_ID"
# 代理应用：只有菜单栏状态项与顶部热区，没有 Dock 图标。
require_plist LSUIElement "true"

# 最低系统版本由工程里的 MACOSX_DEPLOYMENT_TARGET 决定。这里只确认 Xcode 替换过。
if [[ -z "$(read_plist LSMinimumSystemVersion)" ]]; then
  printf 'LSMinimumSystemVersion is empty. Check macosApp/src/Info.plist.\n' >&2
  exit 1
fi

# 图标是工程资源。`macosApp/src` 是同步目录组，非源码文件自动进 Resources。
# 打包这一步只断言它真的进了包，不回写。
if [[ ! -f "$APP_IMAGE/Contents/Resources/$APP_NAME.icns" ]]; then
  printf 'Missing icon in bundle: %s\n' "$APP_IMAGE/Contents/Resources/$APP_NAME.icns" >&2
  exit 1
fi
require_plist CFBundleIconFile "$APP_NAME.icns"

if find "$APP_IMAGE" -name 'kmpDomain.framework' -print -quit | grep -q .; then
  printf 'KMP framework must not be embedded in the Rust-core app bundle.\n' >&2
  exit 1
fi

if [[ ! -x "$HELPER" || ! -f "$DAEMON_PLIST" ]]; then
  printf 'Missing bundled CovioHelper or daemon plist.\n' >&2
  exit 1
fi
if [[ ! -x "$UPDATER_ENGINE" || ! -x "$UPDATER_LAUNCHER" || ! -f "$UPDATER_PLIST" ]]; then
  printf 'Missing bundled CovioUpdater files.\n' >&2
  exit 1
fi

# 嵌套 helper、framework、updater 和 launcher 在归档或构建时已经单独签名。
# 这里只签 app 外层，避免 deep signing 覆盖 updater 和 launcher 的固定 identifier。
# 生成发布清单后再重签外层一次，使最终资源摘要进入 code seal。
if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  release_codesign \
    --force \
    --timestamp \
    --sign "$RELEASE_SIGN_IDENTITY" \
    "$APP_IMAGE"
else
  /usr/bin/codesign --force --sign - "$APP_IMAGE"
fi
/usr/bin/codesign --verify --deep --strict "$APP_IMAGE"

BUNDLED_MANIFEST="$APP_IMAGE/Contents/Resources/release-manifest.json"
python3 -I "$ROOT/scripts/release_manifest.py" generate-bundle-manifest \
  --helper "$HELPER" \
  --output "$BUNDLED_MANIFEST" \
  --commit "$COMMIT"

if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  release_codesign \
    --force \
    --timestamp \
    --sign "$RELEASE_SIGN_IDENTITY" \
    "$APP_IMAGE"
else
  /usr/bin/codesign --force --sign - "$APP_IMAGE"
fi
/usr/bin/codesign --verify --deep --strict "$APP_IMAGE"

if [[ "$CHANNEL" == "internal" && -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  python3 -I "$ROOT/scripts/verify_macos_signing.py" \
    "$APP_IMAGE" \
    --require-stable \
    --baseline "$INTERNAL_SIGNING_BASELINE"
fi
phase_done "bundle signing"

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
  APP_NOTARY_ZIP="$DIST/$APP_NAME-$VERSION-notary.zip"
  /usr/bin/ditto -c -k --keepParent "$APP_IMAGE" "$APP_NOTARY_ZIP"
  notarize_and_staple "$APP_IMAGE" "$APP_NOTARY_ZIP"
  unlink "$APP_NOTARY_ZIP"
fi

bash "$ROOT/scripts/verify-helper-daemon.sh" "$APP_IMAGE" --require-manifest
bash "$ROOT/scripts/verify-updater-daemon.sh" "$APP_IMAGE"
phase_done "daemon verification"

# app.zip lets the publish command download and verify the app and helper pair again.
/usr/bin/ditto -c -k --keepParent "$APP_IMAGE" "$APP_ZIP"
# Automatic updates use a fixed top-level Covio.app layout.
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_IMAGE" "$UPDATE_ZIP"
phase_done "archives"

# 镜像的根要同时有 app 与指向 /Applications 的链接，装的时候才能拖进去。
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/covio-dmg-stage.XXXXXX")"
CLEANUP_PATHS+=("$STAGE")
/usr/bin/ditto "$APP_IMAGE" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
if [[ -e "$DMG_PATH" ]]; then
  unlink "$DMG_PATH"
fi
# hdiutil create 在 macOS 27 上已废弃，改用 diskutil。
/usr/sbin/diskutil image create from \
  --format UDZO \
  --volumeName "$APP_NAME" \
  "$STAGE" \
  "$DMG_PATH" >/dev/null

if [[ ! -d "$APP_IMAGE" || ! -f "$DMG_PATH" ]]; then
  printf 'Packaging did not create the expected artifacts.\n' >&2
  exit 1
fi

/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$RELEASE_SIGN_IDENTITY" "$DMG_PATH"
  /usr/bin/codesign --verify --strict "$DMG_PATH"
fi
phase_done "dmg"

PKG_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/covio-pkg-root.XXXXXX")"
PKG_SCRIPTS="$(mktemp -d "${TMPDIR:-/tmp}/covio-pkg-scripts.XXXXXX")"
PKG_COMPONENT_PLIST="$(mktemp "${TMPDIR:-/tmp}/covio-pkg-components.XXXXXX")"
PKG_INFO_DIR="$(mktemp -d "${TMPDIR:-/tmp}/covio-pkg-info.XXXXXX")"
CLEANUP_PATHS+=("$PKG_ROOT" "$PKG_SCRIPTS" "$PKG_COMPONENT_PLIST" "$PKG_INFO_DIR")
TRANSACTION_BINARY="$PKG_ROOT/Library/Application Support/Covio/Installer/bin/CovioTransaction"
INSTALLER_PAYLOAD="$PKG_ROOT/Library/Application Support/Covio/Installer"
mkdir -p \
  "$(dirname "$TRANSACTION_BINARY")" \
  "$INSTALLER_PAYLOAD/staged"

/usr/bin/xcrun clang \
  -arch arm64 \
  -mmacosx-version-min=14.0 \
  -Wall -Wextra -Werror \
  "$ROOT/installer/atomic_swap.c" \
  -o "$TRANSACTION_BINARY"
if [[ -n "$RELEASE_SIGN_IDENTITY" && "$RELEASE_SIGN_IDENTITY" != "-" ]]; then
  release_codesign \
    --force \
    --timestamp \
    --sign "$RELEASE_SIGN_IDENTITY" \
    "$TRANSACTION_BINARY"
else
  /usr/bin/codesign --force --sign - "$TRANSACTION_BINARY"
fi
/usr/bin/ditto "$APP_IMAGE" "$PKG_ROOT/$STAGED_APP_RELATIVE"
/usr/bin/ditto "$ROOT/installer/transaction.sh" "$INSTALLER_PAYLOAD/transaction.sh"
/usr/bin/ditto "$ROOT/installer/recover.sh" "$INSTALLER_PAYLOAD/recover.sh"
/usr/bin/ditto "$ROOT/installer/install-update.sh" "$INSTALLER_PAYLOAD/install-update.sh"
chmod 0755 "$INSTALLER_PAYLOAD/recover.sh" "$INSTALLER_PAYLOAD/transaction.sh" "$INSTALLER_PAYLOAD/install-update.sh"

/usr/bin/ditto "$ROOT/installer/preinstall" "$PKG_SCRIPTS/preinstall"
/usr/bin/ditto "$ROOT/installer/postinstall" "$PKG_SCRIPTS/postinstall"
/usr/bin/ditto "$ROOT/installer/transaction.sh" "$PKG_SCRIPTS/transaction.sh"
chmod 0755 "$PKG_SCRIPTS/preinstall" "$PKG_SCRIPTS/postinstall"
HELPER_SHA256="$(/usr/bin/plutil -extract helperSHA256 raw -o - "$BUNDLED_MANIFEST")"
UPDATER_SHA256="$(/usr/bin/shasum -a 256 "$UPDATER_ENGINE" | awk '{print $1}')"
UPDATER_LAUNCHER_SHA256="$(/usr/bin/shasum -a 256 "$UPDATER_LAUNCHER" | awk '{print $1}')"
cat > "$PKG_SCRIPTS/transaction.env" <<EOF
TRANSACTION_ID='$TRANSACTION_ID'
EXPECTED_RELEASE_ID='$RELEASE_ID'
EXPECTED_CLIENT_VERSION='$VERSION'
EXPECTED_PRODUCT_VERSION='$PRODUCT_VERSION'
EXPECTED_BUILD_NUMBER='$BUILD_NUMBER'
EXPECTED_COMMIT='$COMMIT'
EXPECTED_PROTOCOL_VERSION='$(python3 -I "$ROOT/scripts/release_manifest.py" value helperProtocolVersion)'
EXPECTED_HELPER_SHA256='$HELPER_SHA256'
EXPECTED_UPDATER_SHA256='$UPDATER_SHA256'
EXPECTED_UPDATER_LAUNCHER_SHA256='$UPDATER_LAUNCHER_SHA256'
EXPECTED_CHANNEL='$CHANNEL'
STAGED_APP_PATH='$STAGED_APP_PATH'
EOF

# The app under Installer/staged is payload, not an installed bundle.
# An empty component plist prevents pkgbuild from relocating it to /Applications.
cat > "$PKG_COMPONENT_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array/>
</plist>
PLIST

PKG_SIGN_ARGS=()
if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
  PKG_SIGN_ARGS+=(--sign "$INSTALLER_SIGN_IDENTITY")
fi
if [[ -e "$PKG_PATH" ]]; then
  unlink "$PKG_PATH"
fi
PKG_COMMAND=(
  /usr/bin/pkgbuild
  --root "$PKG_ROOT"
  --component-plist "$PKG_COMPONENT_PLIST"
  --scripts "$PKG_SCRIPTS"
  --install-location "/"
  --identifier "$APP_ID.pkg"
  --version "$VERSION"
)
if [[ ${#PKG_SIGN_ARGS[@]} -gt 0 ]]; then
  PKG_COMMAND+=("${PKG_SIGN_ARGS[@]}")
fi
PKG_COMMAND+=("$PKG_PATH")
"${PKG_COMMAND[@]}"

/usr/sbin/pkgutil --expand "$PKG_PATH" "$PKG_INFO_DIR/Covio.pkg" >/dev/null
if /usr/bin/grep -q '<bundle path=' "$PKG_INFO_DIR/Covio.pkg/PackageInfo"; then
  printf 'PKG must treat the staged app as payload, not a relocatable bundle.\n' >&2
  exit 1
fi

PKG_PAYLOAD_FILES="$(/usr/sbin/pkgutil --payload-files "$PKG_PATH")"
if [[ "$PKG_PAYLOAD_FILES" != *"Library/Application Support/Covio/Installer/staged/$APP_NAME.app/Contents/MacOS/CovioHelper"* ]]; then
  printf 'PKG payload is missing the staged app helper.\n' >&2
  exit 1
fi
if [[ "$PKG_PAYLOAD_FILES" != *"Library/Application Support/Covio/Installer/staged/$APP_NAME.app/Contents/MacOS/CovioUpdater"* ||
      "$PKG_PAYLOAD_FILES" != *"Library/Application Support/Covio/Installer/staged/$APP_NAME.app/Contents/MacOS/CovioUpdaterLauncher"* ]]; then
  printf 'PKG payload is missing the staged updater files.\n' >&2
  exit 1
fi
if [[ "$PKG_PAYLOAD_FILES" != *"Library/Application Support/Covio/Installer/bin/CovioTransaction"* ]]; then
  printf 'PKG payload is missing the transaction executable.\n' >&2
  exit 1
fi
if [[ "$PKG_PAYLOAD_FILES" != *"Library/Application Support/Covio/Installer/install-update.sh"* ]]; then
  printf 'PKG payload is missing the updater transaction entrypoint.\n' >&2
  exit 1
fi
phase_done "pkg"

if [[ -n "$NOTARY_PROFILE" ]]; then
  notarize_and_staple "$DMG_PATH" "$DMG_PATH"
  if [[ ${#PKG_SIGN_ARGS[@]} -eq 0 ]]; then
    printf 'Public packaging requires a signed PKG before notarization.\n' >&2
    exit 1
  fi
  notarize_and_staple "$PKG_PATH" "$PKG_PATH"
fi
phase_done "notarization"

if [[ ! -f "$APP_ZIP" || ! -f "$UPDATE_ZIP" || ! -f "$PKG_PATH" ]]; then
  printf 'Packaging did not create the expected app zips or PKG.\n' >&2
  exit 1
fi

python3 -I "$ROOT/scripts/release_manifest.py" generate-artifact \
  --helper "$HELPER" \
  --default-dmg "$DMG_PATH" \
  --output "$DIST/release-manifest.json" \
  --commit "$COMMIT"
phase_done "artifact manifest"

APP_BYTES="$(du -sk "$APP_IMAGE" | awk '{print $1 * 1024}')"
DMG_BYTES="$(stat -f %z "$DMG_PATH")"
printf 'Created %s\n' "$APP_IMAGE"
printf 'App bytes: %s\n' "$APP_BYTES"
printf 'Created %s\n' "$DMG_PATH"
printf 'DMG bytes: %s\n' "$DMG_BYTES"
printf 'Created %s\n' "$APP_ZIP"
printf 'Created %s\n' "$UPDATE_ZIP"
printf 'Created %s\n' "$PKG_PATH"
printf 'Package total: %ss\n' "$SECONDS"

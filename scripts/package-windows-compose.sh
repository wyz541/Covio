#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${COVIO_COMPOSE_OUTPUT_DIR:-$ROOT/build/windows-compose-package}"
PRODUCT_VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value productVersion)"
CLIENT_VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value clientVersion)"
BUILD_NUMBER="$(python3 -I "$ROOT/scripts/release_manifest.py" value buildNumber)"
CHANNEL="$(python3 -I "$ROOT/scripts/release_manifest.py" value channel)"
APP_VERSION="${COVIO_COMPOSE_VERSION:-$PRODUCT_VERSION}"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
RELEASE_ID="$(python3 -I "$ROOT/scripts/release_manifest.py" release-id --commit "$COMMIT")"
NATIVE_DIR="$ROOT/composeApp/src/main/resources/native/windows-x64"
JAR="$ROOT/build/tasks/_composeApp_executableJarJvm/composeApp-jvm-executable.jar"
JAVA_HOME="${JAVA_HOME:-$(java -XshowSettings:properties -version 2>&1 | awk -F'= ' '/java.home =/{print $2; exit}')}"
if command -v cygpath >/dev/null 2>&1; then
  JAVA_HOME="$(cygpath -u "$JAVA_HOME")"
fi

if [[ "${OS:-}" != "Windows_NT" ]]; then
  printf 'This script requires Windows.\n' >&2
  exit 1
fi
if [[ ! -x "$JAVA_HOME/bin/jlink" || ! -x "$JAVA_HOME/bin/jpackage" ]]; then
  printf 'JDK 21 with jlink and jpackage is required.\n' >&2
  exit 1
fi
if [[ ! -f "$ROOT/rust/target/release/covio_jni.dll" ]]; then
  printf 'Build the JNI library first with scripts/test-windows-compose.sh.\n' >&2
  exit 1
fi

mkdir -p "$NATIVE_DIR"
cp "$ROOT/rust/target/release/covio_jni.dll" "$NATIVE_DIR/covio_jni.dll"
find "$OUTPUT_DIR" -mindepth 1 -depth -delete 2>/dev/null || true
mkdir -p "$OUTPUT_DIR/input" "$OUTPUT_DIR/app-image"

cd "$ROOT"
./kotlin task :composeApp:executableJarJvm
if [[ ! -s "$JAR" ]]; then
  printf 'Executable JAR is missing: %s\n' "$JAR" >&2
  exit 1
fi
if ! jar tf "$JAR" | grep -q 'native/windows-x64/covio_jni.dll'; then
  printf 'Executable JAR does not contain the Windows JNI library.\n' >&2
  exit 1
fi
cp "$JAR" "$OUTPUT_DIR/input/composeApp-jvm-executable.jar"

"$JAVA_HOME/bin/jlink" \
  --module-path "$JAVA_HOME/jmods" \
  --add-modules java.base,java.desktop,java.logging,java.management,java.naming,java.net.http,java.prefs,java.rmi,java.security.jgss,java.security.sasl,java.sql,jdk.crypto.ec,jdk.management,jdk.unsupported,jdk.accessibility \
  --strip-debug --no-man-pages --no-header-files --compress=zip-6 \
  --output "$OUTPUT_DIR/runtime"

"$JAVA_HOME/bin/jpackage" \
  --type app-image \
  --name Covio \
  --app-version "$APP_VERSION" \
  --vendor Covio \
  --input "$OUTPUT_DIR/input" \
  --main-jar composeApp-jvm-executable.jar \
  --main-class org.springframework.boot.loader.launch.JarLauncher \
  --java-options --enable-native-access=ALL-UNNAMED \
  --runtime-image "$OUTPUT_DIR/runtime" \
  --icon "$ROOT/assets/windows/Covio.ico" \
  --dest "$OUTPUT_DIR/app-image"

APP_DIR="$OUTPUT_DIR/app-image/Covio"
if [[ ! -d "$APP_DIR" ]]; then
  printf 'jpackage app image is missing: %s\n' "$APP_DIR" >&2
  exit 1
fi
pwsh -NoProfile -File "$ROOT/scripts/performance/windows_compose_headless_smoke.ps1" \
  -AppExecutable "$APP_DIR/Covio.exe" \
  -DataDirectory "$OUTPUT_DIR/headless-data"
PORTABLE_ZIP="$OUTPUT_DIR/Covio-$CLIENT_VERSION-windows-x64-portable.zip"
if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command "Compress-Archive -LiteralPath '$(cygpath -w "$APP_DIR")' -DestinationPath '$(cygpath -w "$PORTABLE_ZIP")' -Force"
elif command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -Command "Compress-Archive -LiteralPath '$(cygpath -w "$APP_DIR")' -DestinationPath '$(cygpath -w "$PORTABLE_ZIP")' -Force"
else
  printf 'PowerShell is required to create the portable ZIP.\n' >&2
  exit 1
fi
if [[ ! -s "$PORTABLE_ZIP" ]]; then
  printf 'Portable ZIP is missing: %s\n' "$PORTABLE_ZIP" >&2
  exit 1
fi

MSI=""
if [[ "${COVIO_COMPOSE_REQUIRE_MSI:-0}" == "1" ]]; then
  "$JAVA_HOME/bin/jpackage" \
    --type msi \
    --name Covio \
    --app-version "$APP_VERSION" \
    --vendor Covio \
    --input "$OUTPUT_DIR/input" \
    --main-jar composeApp-jvm-executable.jar \
    --main-class org.springframework.boot.loader.launch.JarLauncher \
    --java-options --enable-native-access=ALL-UNNAMED \
    --runtime-image "$OUTPUT_DIR/runtime" \
    --icon "$ROOT/assets/windows/Covio.ico" \
    --win-menu \
    --win-shortcut \
    --dest "$OUTPUT_DIR"
  MSI="$(find "$OUTPUT_DIR" -maxdepth 1 -name 'Covio-*.msi' -print -quit)"
  if [[ -z "$MSI" || ! -s "$MSI" ]]; then
    printf 'MSI package is missing.\n' >&2
    exit 1
  fi
  MSI_FINAL="$OUTPUT_DIR/Covio-$CLIENT_VERSION-windows-x64.msi"
  mv "$MSI" "$MSI_FINAL"
  MSI="$MSI_FINAL"
fi

SHA256="$(sha256sum "$PORTABLE_ZIP" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$(basename "$PORTABLE_ZIP")" >"$PORTABLE_ZIP.sha256"
MSG_SHA=""
if [[ -n "$MSI" ]]; then
  MSG_SHA="$(sha256sum "$MSI" | awk '{print $1}')"
  printf '%s  %s\n' "$MSG_SHA" "$(basename "$MSI")" >"$MSI.sha256"
fi
python3 -I - "$OUTPUT_DIR/compose-package.json" "$PORTABLE_ZIP" "$SHA256" "$MSI" "$MSG_SHA" "$PRODUCT_VERSION" "$CLIENT_VERSION" "$BUILD_NUMBER" "$CHANNEL" "$COMMIT" "$RELEASE_ID" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
portable = pathlib.Path(sys.argv[2])
msi = pathlib.Path(sys.argv[4]) if sys.argv[4] else None
payload = {
    "schemaVersion": 1,
    "platform": "windows",
    "productVersion": sys.argv[6],
    "clientVersion": sys.argv[7],
    "buildNumber": int(sys.argv[8]),
    "channel": sys.argv[9],
    "gitCommit": sys.argv[10],
    "releaseId": sys.argv[11],
    "runtime": "jlink",
    "packager": "jpackage",
    "artifacts": {
        "portable": {
            "name": portable.name,
            "size": portable.stat().st_size,
            "sha256": sys.argv[3],
        },
        "msi": None if msi is None else {
            "name": msi.name,
            "size": msi.stat().st_size,
            "sha256": sys.argv[5],
        },
    },
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

printf 'Compose portable ZIP: %s\n' "$PORTABLE_ZIP"
if [[ -n "$MSI" ]]; then printf 'Compose MSI: %s\n' "$MSI"; fi

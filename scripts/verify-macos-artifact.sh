#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/Covio.app}"
DMG="${2:-}"
PKG="${3:-}"
REPORT="${4:-$ROOT/dist/macos-artifact-boundary.txt}"
FORBIDDEN_NAMES='(kmpdomain\.framework|(^|/)(libjvm|jvm|kotlin|compose|jna)[^/]*|\.(jar|class|jmod|war)$)'
FORBIDDEN_LINKS='(^|[/@._-])(libjvm|jvm|kotlin|compose|jna)([./_-]|$)'
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/covio-macos-artifact.XXXXXX")"
MOUNT_POINT="$TEMP_ROOT/mount"
MOUNTED=0
APP_FILE_COUNT=0
MACHO_COUNT=0

cleanup() {
  if [[ "$MOUNTED" -eq 1 ]]; then
    /usr/bin/hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
  find "$TEMP_ROOT" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

fail() {
  printf 'macOS artifact boundary failed: %s\n' "$1" >&2
  exit 1
}

verify_app() {
  local app="$1"
  [[ -d "$app" ]] || fail "app bundle is missing"
  /usr/bin/codesign --verify --deep --strict "$app" >/dev/null 2>&1 || fail "code signature is invalid"

  local forbidden
  forbidden="$(find "$app" -print | grep -Ei "$FORBIDDEN_NAMES" | head -1 || true)"
  [[ -z "$forbidden" ]] || fail "forbidden file name: $forbidden"

  APP_FILE_COUNT="$(find "$app" -type f | wc -l | tr -d ' ')"
  while IFS= read -r -d '' file; do
    local description
    description="$(file -b "$file" 2>/dev/null || true)"
    [[ "$description" == *Mach-O* ]] || continue
    MACHO_COUNT=$((MACHO_COUNT + 1))
    local dependencies
    dependencies="$(/usr/bin/otool -L "$file" 2>/dev/null || true)"
    if printf '%s\n' "$dependencies" | grep -Eqi "$FORBIDDEN_LINKS"; then
      fail "forbidden dynamic dependency in ${file#"$app"/}"
    fi
  done < <(find "$app" -type f -print0)
}

verify_app "$APP"

if [[ -n "$DMG" ]]; then
  [[ -f "$DMG" ]] || fail "DMG is missing"
  /usr/bin/hdiutil verify "$DMG" >/dev/null
  mkdir -p "$MOUNT_POINT"
  /usr/bin/hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null
  MOUNTED=1
  verify_app "$MOUNT_POINT/Covio.app"
  /usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null
  MOUNTED=0
fi

if [[ -n "$PKG" ]]; then
  [[ -f "$PKG" ]] || fail "PKG is missing"
  if /usr/sbin/pkgutil --payload-files "$PKG" | grep -Eqi "$FORBIDDEN_NAMES"; then
    fail "PKG payload contains a forbidden path"
  fi
fi

mkdir -p "$(dirname "$REPORT")"
{
  printf 'artifact=%s\n' "$(basename "$APP")"
  printf 'forbidden=kmp,jvm,kotlin,compose,jna\n'
  printf 'appFiles=%s\n' "$APP_FILE_COUNT"
  printf 'machoFiles=%s\n' "$MACHO_COUNT"
  if [[ -n "$DMG" ]]; then
    printf 'dmg=%s\n' "$(basename "$DMG")"
    printf 'dmgSha256=%s\n' "$(/usr/bin/shasum -a 256 "$DMG" | awk '{print $1}')"
  fi
  if [[ -n "$PKG" ]]; then
    printf 'pkg=%s\n' "$(basename "$PKG")"
    printf 'pkgSha256=%s\n' "$(/usr/bin/shasum -a 256 "$PKG" | awk '{print $1}')"
  fi
  printf 'result=pass\n'
} >"$REPORT"

printf 'macOS artifact boundary passed: %s\n' "$APP"
printf 'Checked files: %s; Mach-O files: %s\n' "$APP_FILE_COUNT" "$MACHO_COUNT"

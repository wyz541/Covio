#!/bin/bash
set -euo pipefail

# 构建发布制品并上传为 Draft Release。这个脚本不能发布 Release。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
PIPELINE="$ROOT/scripts/release_pipeline.py"
NOTES_TEMPLATE="$ROOT/RELEASE_NOTES.md"
DRY_RUN=0
SKIP_PACKAGE=0
WITH_OFFLINE=0

usage() {
  printf 'Usage: %s [--dry-run] [--skip-package] [--with-offline]\n' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --skip-package) SKIP_PACKAGE=1 ;;
    --with-offline) WITH_OFFLINE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

VERSION="$(python3 -I "$ROOT/scripts/release_manifest.py" value clientVersion)"
CHANNEL="$(python3 -I "$ROOT/scripts/release_manifest.py" value channel)"
TAG="$(python3 -I "$PIPELINE" tag --root "$ROOT")"
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
VERIFY_SIGN_ARGS=()
if [[ "$CHANNEL" == "internal" ]]; then
  export COVIO_REQUIRE_STABLE_SIGNING=1
  VERIFY_SIGN_ARGS+=(--require-stable-signing)
fi
APP_ZIP="$DIST/Covio-$VERSION.app.zip"
DMG="$DIST/Covio-$VERSION.dmg"
PKG="$DIST/Covio-$VERSION.pkg"
MANIFEST="$DIST/release-manifest.json"
CHECKSUMS="$DIST/checksums.txt"
EVIDENCE="$DIST/release-evidence.json"
NOTES="$DIST/release-notes.generated.md"
OPERATION="$DIST/release-operation.json"

if [[ "$SKIP_PACKAGE" -ne 1 ]]; then
  bash "$ROOT/scripts/package-macos-swift.sh"
  if [[ "$WITH_OFFLINE" -eq 1 ]]; then
    bash "$ROOT/scripts/package-macos-offline-swift.sh"
  fi
fi

if [[ ! -f "$MANIFEST" ]]; then
  printf 'Missing artifact manifest: %s\n' "$MANIFEST" >&2
  printf 'Run scripts/package-macos-swift.sh first.\n' >&2
  exit 1
fi

OFFLINE_NAME="$(python3 -I - "$MANIFEST" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    offline = json.load(stream).get("installers", {}).get("offline")
print(offline.get("name", "") if isinstance(offline, dict) else "")
PY
)"
if [[ "$WITH_OFFLINE" -eq 1 && -z "$OFFLINE_NAME" ]]; then
  printf 'Offline packaging did not record an offline installer.\n' >&2
  exit 1
fi

python3 -I "$PIPELINE" checksums \
  --directory "$DIST" \
  --version "$VERSION"
python3 -I "$PIPELINE" verify \
  --directory "$DIST" \
  --channel "$CHANNEL" \
  --root "$ROOT" \
  --expected-commit "$COMMIT" \
  "${VERIFY_SIGN_ARGS[@]}" \
  --evidence "$EVIDENCE"
python3 -I "$PIPELINE" notes \
  --evidence "$EVIDENCE" \
  --template "$NOTES_TEMPLATE" \
  --output "$NOTES"

if [[ "$DRY_RUN" -eq 1 ]]; then
  REPO="${RELEASE_REPO:-owner/repo}"
else
  if ! command -v gh >/dev/null 2>&1; then
    printf 'Install the GitHub CLI first: brew install gh\n' >&2
    exit 1
  fi
  if ! gh auth status >/dev/null 2>&1; then
    printf 'Authenticate first: gh auth login\n' >&2
    exit 1
  fi
  REPO="${RELEASE_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
  if [[ -z "$REPO" ]]; then
    printf 'Could not resolve the GitHub repository.\n' >&2
    exit 1
  fi
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    printf 'Release already exists: %s\n' "$TAG" >&2
    exit 1
  fi
fi

python3 -I "$PIPELINE" operation \
  --evidence "$EVIDENCE" \
  --action create-draft \
  --repository "$REPO" \
  --tag "$TAG" \
  --output "$OPERATION"

TITLE="Covio $VERSION"
PRERELEASE=false
if [[ "$CHANNEL" == "internal" ]]; then
  TITLE="$TITLE (internal)"
  PRERELEASE=true
fi

ASSETS=("$APP_ZIP" "$DMG" "$PKG")
if [[ -n "$OFFLINE_NAME" ]]; then
  ASSETS+=("$DIST/$OFFLINE_NAME")
fi
ASSETS+=("$MANIFEST" "$CHECKSUMS" "$EVIDENCE" "$NOTES" "$OPERATION")
for asset in "${ASSETS[@]}"; do
  if [[ ! -f "$asset" ]]; then
    printf 'Missing release asset: %s\n' "$asset" >&2
    exit 1
  fi
done

COMMAND=(
  gh release create "$TAG" "${ASSETS[@]}"
  --repo "$REPO"
  --target "$COMMIT"
  --title "$TITLE"
  --notes-file "$NOTES"
  --draft
  --prerelease="$PRERELEASE"
  --latest=false
  --fail-on-no-commits
)

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'Draft release plan:\n'
  printf '  %q' "${COMMAND[0]}"
  printf ' %q' "${COMMAND[@]:1}"
  printf '\n'
  printf 'Draft only. A separate command is required to publish.\n'
  exit 0
fi

if ! "${COMMAND[@]}"; then
  printf 'Draft creation failed. Check for a retained Draft before retrying.\n' >&2
  exit 1
fi

printf 'Created Draft release %s in %s\n' "$TAG" "$REPO"
printf 'Publish with: bash scripts/publish-release.sh %s\n' "$TAG"

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
WINDOWS_PACKAGE_DIR="${COVIO_WINDOWS_COMPOSE_PACKAGE_DIR:-$ROOT/build/windows-compose-package}"
VERIFY_SIGN_ARGS=()
VERIFY_UNIFIED_ARGS=()
if [[ "$CHANNEL" == "internal" ]]; then
  export COVIO_REQUIRE_STABLE_SIGNING=1
  VERIFY_SIGN_ARGS+=(--require-stable-signing)
  VERIFY_UNIFIED_ARGS+=(--require-unified)
fi
UPDATE_ZIP="$DIST/CovioUpdate-$VERSION.zip"
APP_BUNDLE="$DIST/Covio.app"
MANIFEST="$DIST/release-manifest.json"
CHECKSUMS="$DIST/checksums.txt"
EVIDENCE="$DIST/release-evidence.json"
NOTES="$DIST/release-notes.generated.md"
OPERATION="$DIST/release-operation.json"
IOS_METADATA="$DIST/ios-package.json"
WINDOWS_METADATA="$DIST/compose-package.json"

if [[ "$SKIP_PACKAGE" -ne 1 ]]; then
  bash "$ROOT/scripts/package-macos-swift.sh"
  if [[ "$WITH_OFFLINE" -eq 1 ]]; then
    bash "$ROOT/scripts/package-macos-offline-swift.sh"
  fi
  if [[ "${COVIO_IOS_PACKAGE_SKIP:-0}" != "1" ]]; then
    bash "$ROOT/scripts/package-ios-swift.sh"
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

stage_windows_package() {
  if [[ ! -f "$WINDOWS_PACKAGE_DIR/compose-package.json" ]]; then
    printf 'Missing Windows Compose package metadata: %s\n' "$WINDOWS_PACKAGE_DIR/compose-package.json" >&2
    printf 'Download the Windows package CI artifact or set COVIO_WINDOWS_COMPOSE_PACKAGE_DIR.\n' >&2
    exit 1
  fi
  python3 -I - "$WINDOWS_PACKAGE_DIR" "$DIST" <<'PY'
import json
import pathlib
import shutil
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
metadata = json.loads((source / "compose-package.json").read_text(encoding="utf-8"))
artifacts = metadata.get("artifacts")
if not isinstance(artifacts, dict):
    raise SystemExit("compose-package.json has no artifacts object")
for kind in ("portable", "msi"):
    record = artifacts.get(kind)
    if not isinstance(record, dict) or not isinstance(record.get("name"), str):
        raise SystemExit(f"compose-package.json has no {kind} artifact")
    artifact = source / record["name"]
    if not artifact.is_file():
        raise SystemExit(f"missing Windows artifact: {artifact}")
    shutil.copy2(artifact, destination / artifact.name)
shutil.copy2(source / "compose-package.json", destination / "compose-package.json")
PY
}

if [[ "$CHANNEL" == "internal" ]]; then
  if [[ ! -f "$IOS_METADATA" ]]; then
    printf 'Missing iOS package metadata: %s\n' "$IOS_METADATA" >&2
    printf 'Run bash scripts/package-ios-swift.sh with an Apple signing identity.\n' >&2
    exit 1
  fi
  stage_windows_package
  python3 -I "$ROOT/scripts/release_manifest.py" attach-platforms \
    "$MANIFEST" \
    --helper "$APP_BUNDLE/Contents/MacOS/CovioHelper" \
    --ios-package "$IOS_METADATA" \
    --windows-package "$WINDOWS_METADATA"
fi

if [[ "$CHANNEL" == "internal" ]]; then
  UPDATE_KEY_ID="${COVIO_UPDATE_KEY_ID:-}"
  UPDATE_PRIVATE_KEY="${COVIO_UPDATE_PRIVATE_KEY_PATH:-}"
  UPDATE_KEYCHAIN_SERVICE="${COVIO_UPDATE_KEYCHAIN_SERVICE:-com.wyz.covio.update-signing}"
  UPDATE_SIGNER="${COVIO_UPDATE_SIGNER_PATH:-$ROOT/build/update-signing/CovioUpdateSigner}"
  if [[ -z "$UPDATE_KEY_ID" ]]; then
    UPDATE_KEY_ID="$(python3 -I - "$ROOT/release/update-public-keys.json" <<'PYKEY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    keys = json.load(stream).get("keys", [])
print(keys[0].get("keyId", "") if len(keys) == 1 else "")
PYKEY
)"
  fi
  if [[ -z "$UPDATE_KEY_ID" ]]; then
    printf 'Set COVIO_UPDATE_KEY_ID.\n' >&2
    exit 1
  fi
  KEY_SOURCE_ARGS=()
  if [[ -n "$UPDATE_PRIVATE_KEY" ]]; then
    if [[ ! -f "$UPDATE_PRIVATE_KEY" ]]; then
      printf 'Missing update private key: %s\n' "$UPDATE_PRIVATE_KEY" >&2
      exit 1
    fi
    if [[ "$(/usr/bin/stat -f '%Lp' "$UPDATE_PRIVATE_KEY")" != "600" ]]; then
      printf 'Update private key must have mode 0600.\n' >&2
      exit 1
    fi
    KEY_SOURCE_ARGS+=(--private-key "$UPDATE_PRIVATE_KEY")
  else
    if ! /usr/bin/security find-generic-password \
      -s "$UPDATE_KEYCHAIN_SERVICE" \
      -a "$UPDATE_KEY_ID" >/dev/null 2>&1
    then
      printf 'Missing update signing key in Keychain.\n' >&2
      printf 'Run bash scripts/setup-update-signing-key.sh %s\n' "$UPDATE_KEY_ID" >&2
      exit 1
    fi
    KEY_SOURCE_ARGS+=(--keychain-service "$UPDATE_KEYCHAIN_SERVICE")
  fi
  if [[ ! -x "$UPDATE_SIGNER" ]]; then
    bash "$ROOT/scripts/build-update-signature-tool.sh"
    UPDATE_SIGNER="$ROOT/build/update-signing/CovioUpdateSigner"
  fi
  python3 -I "$ROOT/scripts/update_manifest.py" generate \
    --release-manifest "$ROOT/release/release-manifest.json" \
    --archive "$UPDATE_ZIP" \
    --app-executable "$APP_BUNDLE/Contents/MacOS/Covio" \
    --helper "$APP_BUNDLE/Contents/MacOS/CovioHelper" \
    --updater "$APP_BUNDLE/Contents/MacOS/CovioUpdater" \
    --commit "$COMMIT" \
    --key-id "$UPDATE_KEY_ID" \
    --signer "$UPDATE_SIGNER" \
    "${KEY_SOURCE_ARGS[@]}" \
    --output-dir "$DIST"
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
  "${VERIFY_UNIFIED_ARGS[@]}" \
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

ASSETS=()
while IFS= read -r asset; do
  ASSETS+=("$asset")
done < <(
  python3 -I - "$DIST" "$VERSION" <<'PY'
import importlib.util
import pathlib
import sys

script = pathlib.Path(sys.argv[1]).parent / "scripts" / "release_pipeline.py"
spec = importlib.util.spec_from_file_location("release_pipeline", script)
assert spec and spec.loader
pipeline = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = pipeline
spec.loader.exec_module(pipeline)
directory = pathlib.Path(sys.argv[1])
for name in pipeline.release_asset_names(directory, sys.argv[2]):
    print(directory / name)
PY
)
ASSETS+=("$CHECKSUMS" "$EVIDENCE" "$NOTES" "$OPERATION")
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

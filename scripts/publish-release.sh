#!/bin/bash
set -euo pipefail

# 重新验证 Draft 的全部资产，然后显式提升为 Published Release。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIPELINE="$ROOT/scripts/release_pipeline.py"
DRY_RUN=0
TAG=""

usage() {
  printf 'Usage: %s [tag] [--dry-run]\n' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    -* ) usage >&2; exit 2 ;;
    *)
      if [[ -n "$TAG" ]]; then
        usage >&2
        exit 2
      fi
      TAG="$1"
      ;;
  esac
  shift
done
if [[ -z "$TAG" ]]; then
  TAG="$(python3 -I "$PIPELINE" tag --root "$ROOT")"
fi

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

RELEASE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/covio-publish.XXXXXX")"
trap 'rm -rf "$RELEASE_TMP"' EXIT
ASSET_DIR="${COVIO_RELEASE_ASSET_DIR:-$RELEASE_TMP/assets}"
mkdir -p "$ASSET_DIR"

gh release view "$TAG" \
  --repo "$REPO" \
  --json isDraft,isPrerelease,tagName \
  > "$RELEASE_TMP/release-info.json"

if [[ -z "${COVIO_RELEASE_ASSET_DIR:-}" ]]; then
  gh release download "$TAG" \
    --repo "$REPO" \
    --dir "$ASSET_DIR" \
    --clobber
fi
if [[ ! -f "$ASSET_DIR/release-manifest.json" ]]; then
  printf 'Draft has no release-manifest.json.\n' >&2
  exit 1
fi
if [[ ! -f "$ASSET_DIR/release-evidence.json" ]]; then
  printf 'Draft has no release-evidence.json.\n' >&2
  exit 1
fi

TARGET_COMMIT="$(python3 -I - "$ASSET_DIR/release-evidence.json" <<'PY'
import json
import re
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    commit = json.load(stream).get("gitCommit")
if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
    raise SystemExit("release evidence has no full lowercase gitCommit")
print(commit)
PY
)"
if ! git -C "$ROOT" cat-file -e "$TARGET_COMMIT^{commit}" 2>/dev/null; then
  git -C "$ROOT" fetch origin --tags
fi
if ! git -C "$ROOT" cat-file -e "$TARGET_COMMIT^{commit}" 2>/dev/null; then
  printf 'Cannot resolve release target commit: %s\n' "$TARGET_COMMIT" >&2
  exit 1
fi
git -C "$ROOT" show "$TARGET_COMMIT:release/release-manifest.json" \
  > "$RELEASE_TMP/source-release-manifest.json"

CHANNEL="$(python3 -I - "$ASSET_DIR/release-manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    print(json.load(stream)["channel"])
PY
)"
VERIFY_SIGN_ARGS=()
if [[ "$CHANNEL" == "internal" ]]; then
  VERIFY_SIGN_ARGS+=(--require-stable-signing)
  if [[ ! -x "$ROOT/build/update-signing/CovioUpdateSigner" ]]; then
    bash "$ROOT/scripts/build-update-signature-tool.sh"
  fi
fi
EVIDENCE_TAG="$(python3 -I - "$ASSET_DIR/release-evidence.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    print(json.load(stream)["tag"])
PY
)"
if [[ "$EVIDENCE_TAG" != "$TAG" ]]; then
  printf 'Release tag %s differs from evidence tag %s.\n' "$TAG" "$EVIDENCE_TAG" >&2
  exit 1
fi

python3 -I "$PIPELINE" verify \
  --directory "$ASSET_DIR" \
  --channel "$CHANNEL" \
  --source-manifest "$RELEASE_TMP/source-release-manifest.json" \
  --expected-commit "$TARGET_COMMIT" \
  "${VERIFY_SIGN_ARGS[@]}" \
  --evidence "$RELEASE_TMP/recomputed-release-evidence.json" \
  --compare-evidence "$ASSET_DIR/release-evidence.json"
python3 -I "$PIPELINE" promote-check \
  --release-info "$RELEASE_TMP/release-info.json" \
  --evidence "$RELEASE_TMP/recomputed-release-evidence.json" \
  --channel "$CHANNEL"

python3 -I "$PIPELINE" operation \
  --evidence "$RELEASE_TMP/recomputed-release-evidence.json" \
  --action publish \
  --repository "$REPO" \
  --tag "$TAG" \
  --output "$RELEASE_TMP/release-operation.json"

EDIT_COMMAND=(gh release edit "$TAG" --repo "$REPO" --draft=false)
if [[ "$CHANNEL" == "internal" ]]; then
  EDIT_COMMAND+=(--prerelease=true --latest=false)
else
  EDIT_COMMAND+=(--prerelease=false --latest)
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'Verified Draft %s. Publish plan:\n  ' "$TAG"
  printf '%q ' "${EDIT_COMMAND[@]}"
  printf '\n'
  exit 0
fi

if ! gh release upload "$TAG" "$RELEASE_TMP/release-operation.json" \
  --repo "$REPO" \
  --clobber; then
  printf 'Cannot attach the publish operation record. Draft remains unpublished.\n' >&2
  exit 1
fi
if ! "${EDIT_COMMAND[@]}"; then
  printf 'Publishing failed. Draft remains unpublished.\n' >&2
  exit 1
fi

gh release view "$TAG" \
  --repo "$REPO" \
  --json isDraft,isPrerelease,tagName \
  > "$RELEASE_TMP/published.json"
python3 -I - "$RELEASE_TMP/published.json" "$CHANNEL" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    info = json.load(stream)
if info.get("isDraft"):
    raise SystemExit("release is still a draft")
expected_prerelease = sys.argv[2] == "internal"
if bool(info.get("isPrerelease")) != expected_prerelease:
    raise SystemExit("published prerelease flag differs from channel")
PY

printf 'Published %s in %s\n' "$TAG" "$REPO"

#!/bin/bash
set -euo pipefail

# Export or verify the macOS-owned Workbench interaction contract.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACT="$ROOT/docs/macos-interaction-contract.json"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf "This script requires macOS.\n" >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  printf "Missing xcrun. Install Xcode.\n" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

xcrun swiftc \
  "$ROOT/macosApp/src/Design/WorkbenchInteractionContract.swift" \
  "$ROOT/scripts/export-macos-interaction-contract.swift" \
  -o "$TMP_DIR/export-macos-interaction-contract"

if [[ "${1:-}" == "--check" ]]; then
  "$TMP_DIR/export-macos-interaction-contract" --check --output "$CONTRACT"
else
  "$TMP_DIR/export-macos-interaction-contract" --output "$CONTRACT"
fi

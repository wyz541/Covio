#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build/update-signing}"
OUTPUT="$OUT_DIR/CovioUpdateSigner"
SOURCE="$ROOT/scripts/update_signature_tool.swift"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This script requires macOS.\n' >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
xcrun swiftc "$SOURCE" -o "$OUTPUT"
chmod 0755 "$OUTPUT"
"$OUTPUT" >/dev/null 2>&1 || true
printf 'Built %s\n' "$OUTPUT"

#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/covio-windows-boundary-test.XXXXXX")"
EXE="$TEMP_ROOT/covio-windows.exe"
REPORT="$TEMP_ROOT/report.txt"

cleanup() {
  find "$TEMP_ROOT" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

printf 'fake-pe' >"$EXE"
COVIO_WINDOWS_DEPENDENCY_TREE=$'covio-windows v0.1.0\nserde v1.0' \
  bash "$ROOT/scripts/verify-windows-artifact.sh" "$EXE" "$REPORT" >/dev/null
grep -q '^result=pass$' "$REPORT"

if COVIO_WINDOWS_DEPENDENCY_TREE='jna v0.1.0' \
  bash "$ROOT/scripts/verify-windows-artifact.sh" "$EXE" "$REPORT" >/dev/null 2>&1; then
  printf 'Boundary test accepted a JNA dependency.\n' >&2
  exit 1
fi

printf 'fake-pe' >"$TEMP_ROOT/kotlin-runtime.jar"
if COVIO_WINDOWS_DEPENDENCY_TREE='covio-windows v0.1.0' \
  bash "$ROOT/scripts/verify-windows-artifact.sh" "$EXE" "$REPORT" >/dev/null 2>&1; then
  printf 'Boundary test accepted a Kotlin artifact.\n' >&2
  exit 1
fi

printf 'Windows artifact boundary tests passed.\n'

#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="${1:-$ROOT/rust/target/release/covio-windows.exe}"
REPORT="${2:-$ROOT/build/windows-package/artifact-boundary.txt}"
TARGET="${COVIO_WINDOWS_TARGET:-}"
ARTIFACT_DIR="$(dirname "$EXE")"

if [[ ! -s "$EXE" ]]; then
  printf 'Windows executable is missing: %s\n' "$EXE" >&2
  exit 1
fi

TREE_ARGS=(-p covio-windows --edges normal --prefix none)
if [[ -n "$TARGET" ]]; then
  TREE_ARGS+=(--target "$TARGET")
fi
DEPENDENCIES="$(cargo tree --manifest-path "$ROOT/rust/Cargo.toml" "${TREE_ARGS[@]}")"
if printf '%s\n' "$DEPENDENCIES" | grep -Eqi '(^|[ /])(jna|kotlin|compose|jvm)(@|[ /]|$)'; then
  printf 'Forbidden JVM/Kotlin/Compose/JNA dependency found.\n' >&2
  exit 1
fi

FORBIDDEN_FILE="$(find "$ARTIFACT_DIR" -type f \( -iname '*.jar' -o -iname '*.class' -o -iname 'jna*' -o -iname '*kotlin*' -o -iname '*compose*' -o -iname 'jvm.dll' \) -print -quit)"
if [[ -n "$FORBIDDEN_FILE" ]]; then
  printf 'Forbidden runtime file found: %s\n' "$FORBIDDEN_FILE" >&2
  exit 1
fi

printf 'Windows artifact boundary passed: %s\n' "$EXE"
printf 'Dependency packages: %s\n' "$(printf '%s\n' "$DEPENDENCIES" | wc -l | tr -d ' ')"
mkdir -p "$(dirname "$REPORT")"
{
  printf 'artifact=%s\n' "$(basename "$EXE")"
  printf 'forbidden=jvm,kotlin,compose,jna\n'
  printf 'dependencyPackages=%s\n' "$(printf '%s\n' "$DEPENDENCIES" | wc -l | tr -d ' ')"
  printf 'result=pass\n'
} >"$REPORT"

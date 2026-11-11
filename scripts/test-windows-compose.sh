#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v cargo >/dev/null 2>&1; then
  if [[ -x "$HOME/tools/cargo/bin/cargo" ]]; then
    export CARGO_HOME="${CARGO_HOME:-$HOME/tools/cargo}"
    export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/tools/rustup}"
    export PATH="$CARGO_HOME/bin:$PATH"
  else
    printf 'cargo is required. Install Rust or add cargo to PATH.\n' >&2
    exit 1
  fi
fi

cd "$ROOT/rust"
cargo fmt --check --all
cargo clippy -p covio-jni --all-targets -- -D warnings
cargo test -p covio-jni --all-targets
cargo build -p covio-jni --release

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) JNI_LIBRARY="$ROOT/rust/target/release/covio_jni.dll" ;;
  Darwin) JNI_LIBRARY="$ROOT/rust/target/release/libcovio_jni.dylib" ;;
  *) JNI_LIBRARY="$ROOT/rust/target/release/libcovio_jni.so" ;;
esac
if [[ ! -s "$JNI_LIBRARY" ]]; then
  printf 'JNI library is missing: %s\n' "$JNI_LIBRARY" >&2
  exit 1
fi
if command -v cygpath >/dev/null 2>&1; then
  JNI_LIBRARY_ENV="$(cygpath -w "$JNI_LIBRARY")"
else
  JNI_LIBRARY_ENV="$JNI_LIBRARY"
fi

cd "$ROOT"
COVIO_JNI_LIBRARY="$JNI_LIBRARY_ENV" ./kotlin test
COVIO_JNI_LIBRARY="$JNI_LIBRARY_ENV" ./kotlin task :composeApp:executableJarJvm
python3 -I scripts/release_manifest.py check
python3 -I scripts/generate-contract-constants.py --check
python3 -I scripts/generate-bridge-contracts.py --check

if [[ "${OS:-}" == "Windows_NT" ]]; then
  screenshot_dir="$ROOT/build/windows-compose-screenshots"
  data_dir="$ROOT/build/windows-compose-smoke-data"
  mkdir -p "$screenshot_dir" "$data_dir"
  find "$screenshot_dir" -mindepth 1 -depth -delete
  find "$data_dir" -mindepth 1 -depth -delete

  to_windows_path() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
  }

  for theme in light dark; do
    screenshot="$(to_windows_path "$screenshot_dir/devices-$theme.png")"
    data_path="$(to_windows_path "$data_dir")"
    COVIO_JNI_LIBRARY="$JNI_LIBRARY_ENV" ./kotlin run --no-compose-hot-reload \
      --jvm-args=--enable-native-access=ALL-UNNAMED -- \
      --screenshot "$screenshot" --theme "$theme" --screen devices --data-dir "$data_path"
    test -s "$screenshot_dir/devices-$theme.png"
    test "$(stat -c%s "$screenshot_dir/devices-$theme.png")" -gt 20000
  done

  pairing_screenshot="$(to_windows_path "$screenshot_dir/pairing-light.png")"
  pairing_data="$(to_windows_path "$data_dir/pairing")"
  mkdir -p "$data_dir/pairing"
  COVIO_JNI_LIBRARY="$JNI_LIBRARY_ENV" ./kotlin run --no-compose-hot-reload \
    --jvm-args=--enable-native-access=ALL-UNNAMED -- \
    --screenshot "$pairing_screenshot" --theme light --screen pair --data-dir "$pairing_data"
  test -s "$screenshot_dir/pairing-light.png"
  test "$(stat -c%s "$screenshot_dir/pairing-light.png")" -gt 20000
fi

printf 'Windows Compose checks passed.\n'

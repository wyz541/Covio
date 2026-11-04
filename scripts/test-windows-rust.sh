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
cargo test -p covio-platform -p covio-windows --all-targets

if [[ "${OS:-}" == "Windows_NT" ]]; then
  cargo clippy -p covio-platform -p covio-windows --all-targets -- -D warnings
  cargo run -p covio-windows -- --capability-smoke
  cargo run -p covio-windows -- --headless-smoke
  cargo run -p covio-windows -- --single-instance-smoke

  smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/covio-windows-window-smoke.XXXXXX")"
  trap 'find "$smoke_dir" -depth -delete' EXIT
  cargo run -p covio-windows -- \
    --window-smoke --ui-scale 1.5 --window-position 0,0 --data-dir "$smoke_dir"

  crash_dir="$(mktemp -d "${TMPDIR:-/tmp}/covio-windows-crash-smoke.XXXXXX")"
  set +e
  cargo run -p covio-windows -- --crash-recovery-smoke --data-dir "$crash_dir"
  crash_status=$?
  set -e
  test "$crash_status" -eq 23
  cargo run -p covio-windows -- --headless-smoke --data-dir "$crash_dir"
  find "$crash_dir" -depth -delete

  screenshot_dir="$ROOT/build/windows-host-screenshots"
  light_screenshot="$screenshot_dir/workspace-light.png"
  dark_screenshot="$screenshot_dir/workspace-dark.png"
  mkdir -p "$screenshot_dir"
  light_screenshot_env_path="$light_screenshot"
  dark_screenshot_env_path="$dark_screenshot"
  if command -v cygpath >/dev/null 2>&1; then
    light_screenshot_env_path="$(cygpath -w "$light_screenshot_env_path")"
    dark_screenshot_env_path="$(cygpath -w "$dark_screenshot_env_path")"
  fi
  cargo run -p covio-windows -- \
    --screenshot "$light_screenshot_env_path" --theme light --view workspace \
    --seed-smoke-data --ui-scale 1.5 --data-dir "$smoke_dir"
  cargo run -p covio-windows -- \
    --screenshot "$dark_screenshot_env_path" --theme dark --view workspace \
    --seed-smoke-data --ui-scale 1.5 --data-dir "$smoke_dir"
  test -s "$light_screenshot"
  test -s "$dark_screenshot"
elif rustup target list --installed | grep -qx 'x86_64-pc-windows-gnu'; then
  cargo check -p covio-windows --target x86_64-pc-windows-gnu --all-targets
else
  printf 'Windows target is not installed; Windows type-check skipped.\n'
fi

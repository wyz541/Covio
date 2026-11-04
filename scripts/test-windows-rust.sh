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
cargo fmt --check -p covio-windows
cargo test -p covio-windows --all-targets

if [[ "${OS:-}" == "Windows_NT" ]]; then
  cargo clippy -p covio-windows --all-targets -- -D warnings
  cargo run -p covio-windows -- --headless-smoke
  cargo run -p covio-windows -- --single-instance-smoke

  smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/covio-windows-window-smoke.XXXXXX")"
  trap 'find "$smoke_dir" -depth -delete' EXIT
  cargo run -p covio-windows -- --window-smoke --data-dir "$smoke_dir"

  screenshot_path="$ROOT/build/covio-windows-host.png"
  screenshot_env_path="$screenshot_path"
  if command -v cygpath >/dev/null 2>&1; then
    screenshot_env_path="$(cygpath -w "$screenshot_env_path")"
  fi
  EFRAME_SCREENSHOT_TO="$screenshot_env_path" \
    cargo run -p covio-windows -- --data-dir "$smoke_dir"
  test -s "$screenshot_path"
elif rustup target list --installed | grep -qx 'x86_64-pc-windows-gnu'; then
  cargo check -p covio-windows --target x86_64-pc-windows-gnu --all-targets
else
  printf 'Windows target is not installed; Windows type-check skipped.\n'
fi

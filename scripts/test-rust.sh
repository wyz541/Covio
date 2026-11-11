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

# shellcheck source=scripts/rust-macos-env.sh
source "$ROOT/scripts/rust-macos-env.sh"
prepare_rust_macos_target "$ROOT"

cd "$ROOT/rust"
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo run -p covio-windows -- --headless-smoke
if [[ "$(uname -s)" == "Darwin" ]]; then
  bash "$ROOT/scripts/test-rust-macos-ffi.sh"
fi

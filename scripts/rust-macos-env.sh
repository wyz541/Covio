# shellcheck shell=bash

# Keep native Rust dependencies at the macOS app deployment target.
# Cargo does not rebuild blake3 when this environment value changes, so the
# stamp forces one targeted clean when the value changes.
prepare_rust_macos_target() {
  local root="$1"
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"

  local target_dir="${CARGO_TARGET_DIR:-$root/rust/target}"
  local stamp="$target_dir/.covio-macos-deployment-target"
  local previous=""
  [[ -f "$stamp" ]] && previous="$(cat "$stamp")"

  if [[ -d "$target_dir" && "$previous" != "$MACOSX_DEPLOYMENT_TARGET" ]]; then
    (cd "$root/rust" && cargo clean -p blake3)
  fi

  mkdir -p "$target_dir"
  printf '%s\n' "$MACOSX_DEPLOYMENT_TARGET" > "$stamp"
}

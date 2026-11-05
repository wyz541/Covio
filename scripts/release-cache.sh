# shellcheck shell=bash

# Shared Release cache paths.
# Call this file with `source`; it has no side effects.

release_primary_checkout() {
  local root="$1" common_dir
  common_dir="$(cd "$root" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
  dirname "$common_dir"
}

release_path_from_root() {
  local root="$1" value="$2"
  if [[ "$value" == /* ]]; then
    printf '%s\n' "$value"
  else
    printf '%s/%s\n' "$root" "$value"
  fi
}

release_derived_data_path() {
  local root="$1"
  if [[ -n "${COVIO_RELEASE_DERIVED_DATA:-}" ]]; then
    release_path_from_root "$root" "$COVIO_RELEASE_DERIVED_DATA"
  else
    printf '%s/build/release-xcode-cache\n' "$(release_primary_checkout "$root")"
  fi
}

release_source_packages_path() {
  local root="$1"
  if [[ -n "${COVIO_RELEASE_SOURCE_PACKAGES:-}" ]]; then
    release_path_from_root "$root" "$COVIO_RELEASE_SOURCE_PACKAGES"
  else
    printf '%s/build/release-source-packages\n' "$(release_primary_checkout "$root")"
  fi
}

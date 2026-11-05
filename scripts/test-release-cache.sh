#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/covio-release-cache.XXXXXX")"

cleanup() {
  find "$TEST_ROOT" -depth -delete
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local expected="$1" actual="$2" message="$3"
  [[ "$actual" == "$expected" ]] || fail "$message: expected '$expected', got '$actual'"
}

HELPER_REPO="$TEST_ROOT/helper-repo"
HELPER_LINKED="$TEST_ROOT/helper-linked"
mkdir -p "$HELPER_REPO"
git -C "$HELPER_REPO" init -q
git -C "$HELPER_REPO" config user.name test
git -C "$HELPER_REPO" config user.email test@example.com
printf 'fixture\n' >"$HELPER_REPO/README.md"
git -C "$HELPER_REPO" add README.md
git -C "$HELPER_REPO" commit -qm fixture
git -C "$HELPER_REPO" worktree add -q -b linked-test "$HELPER_LINKED"

# shellcheck source=scripts/release-cache.sh
source "$ROOT/scripts/release-cache.sh"
EXPECTED_HELPER_REPO="$(cd "$HELPER_REPO" && pwd -P)"
assert_equal "$EXPECTED_HELPER_REPO" "$(release_primary_checkout "$HELPER_LINKED")" "linked worktree primary checkout"
assert_equal "$EXPECTED_HELPER_REPO/build/release-xcode-cache" "$(release_derived_data_path "$HELPER_LINKED")" "DerivedData cache path"
assert_equal "$EXPECTED_HELPER_REPO/build/release-source-packages" "$(release_source_packages_path "$HELPER_LINKED")" "SwiftPM cache path"

if declare -F release_kmp_cache_path >/dev/null; then
  fail "KMP cache resolver still exists"
fi

printf 'Release cache tests passed.\n'

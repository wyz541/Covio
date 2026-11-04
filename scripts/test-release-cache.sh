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

assert_contains() {
  local text="$1" expected="$2" message="$3"
  [[ "$text" == *"$expected"* ]] || fail "$message: missing '$expected'"
}

# The shared path helper must resolve every linked worktree to the primary checkout.
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
assert_equal "$EXPECTED_HELPER_REPO/build/release-kmp-cache" "$(release_kmp_cache_path "$HELPER_LINKED")" "KMP cache path"

make_worktree() {
  local worktree="$1"
  mkdir -p \
    "$worktree/scripts" \
    "$worktree/kmpDomain/src"
  cp "$ROOT/scripts/build-kmp-framework.sh" "$worktree/scripts/build-kmp-framework.sh"
  printf 'modules:\n  - kmpDomain\n' >"$worktree/project.yaml"
  printf '[versions]\nkotlin = "test"\n' >"$worktree/libs.versions.toml"
  printf 'product:\n  type: kmp/lib\n' >"$worktree/kmpDomain/module.yaml"
  printf 'const val FIXTURE = 1\n' >"$worktree/kmpDomain/src/Fixture.kt"
  cp "$TEST_ROOT/kotlin" "$worktree/kotlin"
}

cat >"$TEST_ROOT/kotlin" <<'SH'
#!/bin/sh
set -eu

if [ "${1:-}" = "task" ]; then
  task_dir="build/tasks/_kmpDomain_compileMacosArm64${BUILD_TYPE}"
  mkdir -p "$task_dir"
  printf 'klib-%s\n' "${KLIB_VERSION:-v1}" >"$task_dir/kmpDomain.klib"
  exit 0
fi

if [ "${1:-}" = "show" ]; then
  printf 'com.example:example-macosarm64:1.0\n'
  exit 0
fi

exit 2
SH

cat >"$TEST_ROOT/konanc" <<'SH'
#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "-version" ]]; then
  printf 'konanc test 1.0\n'
  exit 0
fi

printf '%s\n' "$*" >>"$KONANC_CALL_LOG"
static=false
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -Xstatic-framework)
      static=true
      shift
      ;;
    -o)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$output" ]] || exit 2
if [[ "$static" == true && "${FAIL_STATIC:-0}" == "1" ]]; then
  printf 'forced static failure\n' >&2
  exit 7
fi

kind=dynamic
[[ "$static" == true ]] && kind=static
framework="$output.framework"
mkdir -p "$framework/Headers" "$framework.dSYM/Contents/Resources/DWARF"
printf '%s-%s\n' "${KLIB_VERSION:-v1}" "$kind" >"$framework/kmpDomain"
printf 'header-%s-%s\n' "${KLIB_VERSION:-v1}" "$kind" >"$framework/Headers/kmpDomain.h"
printf 'dsym-%s-%s\n' "${KLIB_VERSION:-v1}" "$kind" >"$framework.dSYM/Contents/Resources/DWARF/kmpDomain"
SH

mkdir -p "$TEST_ROOT/fake-java/bin"
cat >"$TEST_ROOT/fake-java/bin/java" <<'SH'
#!/bin/sh
printf 'java test 1.0\n' >&2
SH
chmod +x "$TEST_ROOT/kotlin" "$TEST_ROOT/konanc" "$TEST_ROOT/fake-java/bin/java"

SHARED_KOTLIN_CACHE="$TEST_ROOT/shared-kotlin-cache"
DEP_KLIB="$SHARED_KOTLIN_CACHE/.m2.cache/com/example/example-macosarm64/1.0/example-macosarm64-1.0.klib"
mkdir -p "$(dirname "$DEP_KLIB")"
printf 'dependency-v1\n' >"$DEP_KLIB"

SHARED_KMP_CACHE="$TEST_ROOT/shared-kmp-cache"
CALL_LOG="$TEST_ROOT/konanc.calls"
export KOTLIN_SHARED_CACHE_DIR="$SHARED_KOTLIN_CACHE"
export JAVA_HOME="$TEST_ROOT/fake-java"
export KONANC="$TEST_ROOT/konanc"
export KONANC_CALL_LOG="$CALL_LOG"
export COVIO_RELEASE_KMP_CACHE_DIR="$SHARED_KMP_CACHE"
export BUILD_TYPE=Release

WORKTREE_A="$TEST_ROOT/worktree-a"
WORKTREE_B="$TEST_ROOT/worktree-b"
make_worktree "$WORKTREE_A"
make_worktree "$WORKTREE_B"

run_build() {
  local worktree="$1" output="$2"
  if ! (cd "$worktree" && bash scripts/build-kmp-framework.sh) >"$output" 2>&1; then
    cat "$output" >&2
    return 1
  fi
}

run_build "$WORKTREE_A" "$TEST_ROOT/first.log"
assert_equal "2" "$(wc -l <"$CALL_LOG" | tr -d ' ')" "first build links dynamic and static frameworks"
[[ -f "$SHARED_KMP_CACHE/kmp-frameworks.stamp" ]] || fail "first build did not write the cache stamp"
[[ -L "$WORKTREE_A/build/kmp-framework" ]] || fail "first build did not link the public KMP cache"

run_build "$WORKTREE_A" "$TEST_ROOT/hit.log"
assert_equal "2" "$(wc -l <"$CALL_LOG" | tr -d ' ')" "second build reused both frameworks"
assert_contains "$(cat "$TEST_ROOT/hit.log")" "KMP cache hit" "cache hit output"

run_build "$WORKTREE_B" "$TEST_ROOT/shared-hit.log"
assert_equal "2" "$(wc -l <"$CALL_LOG" | tr -d ' ')" "clean worktree reused the shared framework cache"
assert_contains "$(cat "$TEST_ROOT/shared-hit.log")" "KMP cache hit" "shared cache hit output"

SHARED_DYNAMIC_BEFORE="$(shasum -a 256 "$WORKTREE_A/build/kmp-framework/kmpDomain.framework/kmpDomain" | awk '{print $1}')"
if ! (cd "$WORKTREE_A" && unset COVIO_RELEASE_KMP_CACHE_DIR && BUILD_TYPE=Debug bash scripts/build-kmp-framework.sh) >"$TEST_ROOT/debug.log" 2>&1; then
  cat "$TEST_ROOT/debug.log" >&2
  fail "local Debug build failed after a shared Release build"
fi
assert_equal "4" "$(wc -l <"$CALL_LOG" | tr -d ' ')" "Debug build replaced stale shared symlinks"
assert_equal "$SHARED_DYNAMIC_BEFORE" "$(shasum -a 256 "$SHARED_KMP_CACHE/kmp-framework/kmpDomain.framework/kmpDomain" | awk '{print $1}')" "Debug build did not write through the shared cache symlink"

run_build "$WORKTREE_A" "$TEST_ROOT/shared-hit-after-debug.log"
assert_equal "4" "$(wc -l <"$CALL_LOG" | tr -d ' ')" "Release cache remained valid after a Debug build"
assert_contains "$(cat "$TEST_ROOT/shared-hit-after-debug.log")" "KMP cache hit" "Release cache hit after Debug output"

printf 'source-v2\n' >>"$WORKTREE_A/kmpDomain/src/Fixture.kt"
run_build "$WORKTREE_A" "$TEST_ROOT/source-changed.log"
assert_equal "6" "$(wc -l <"$CALL_LOG" | tr -d ' ')" "source change invalidated the cache"

printf 'dependency-v2\n' >"$DEP_KLIB"
run_build "$WORKTREE_A" "$TEST_ROOT/dependency-changed.log"
assert_equal "8" "$(wc -l <"$CALL_LOG" | tr -d ' ')" "dependency change invalidated the cache"

find "$SHARED_KMP_CACHE/kmp-framework-static/kmpDomain.framework" -depth -delete
run_build "$WORKTREE_A" "$TEST_ROOT/missing-static.log"
assert_equal "10" "$(wc -l <"$CALL_LOG" | tr -d ' ')" "missing static framework invalidated the pair"

DYNAMIC_BEFORE="$(shasum -a 256 "$WORKTREE_A/build/kmp-framework/kmpDomain.framework/kmpDomain" | awk '{print $1}')"
STATIC_BEFORE="$(shasum -a 256 "$WORKTREE_A/build/kmp-framework-static/kmpDomain.framework/kmpDomain" | awk '{print $1}')"
printf 'source-v3\n' >>"$WORKTREE_A/kmpDomain/src/Fixture.kt"
if (cd "$WORKTREE_A" && FAIL_STATIC=1 bash scripts/build-kmp-framework.sh) >"$TEST_ROOT/failure.log" 2>&1; then
  fail "forced static link failure unexpectedly succeeded"
fi
assert_equal "$DYNAMIC_BEFORE" "$(shasum -a 256 "$WORKTREE_A/build/kmp-framework/kmpDomain.framework/kmpDomain" | awk '{print $1}')" "failed build preserved the old dynamic framework"
assert_equal "$STATIC_BEFORE" "$(shasum -a 256 "$WORKTREE_A/build/kmp-framework-static/kmpDomain.framework/kmpDomain" | awk '{print $1}')" "failed build preserved the old static framework"

printf 'Release cache tests passed.\n'

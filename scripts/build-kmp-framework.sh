#!/bin/bash
set -euo pipefail

# 产出 kmpDomain.framework，供 macosApp 的 Xcode 工程链接。
#
# 为什么不用 Amper 的 Xcode 集成：`kotlin tool xcode-integration` 只支持 iOS。
# 用 macOS 环境执行会报 `doesn't support ... sdk=macosx`。
# 证据见 docs/adr/adr-0001-macos-ui-swiftui.md 的实测 3。
# 若 Amper 将来支持 macOS SDK，删除本脚本，改用 xcode-integration。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE="kmpDomain"
PLATFORM="macosArm64"
# Amper 的任务名与产物目录把平台首字母大写：compileMacosArm64Debug。
# BSD sed 不支持 \U，用 cut 加 tr。
PLATFORM_ID="$(printf '%s' "$PLATFORM" | cut -c1 | tr '[:lower:]' '[:upper:]')$(printf '%s' "$PLATFORM" | cut -c2-)"
TARGET="macos_arm64"
BUILD_TYPE="${BUILD_TYPE:-Debug}"
SHARED_CACHE="${KOTLIN_SHARED_CACHE_DIR:-$HOME/Library/Caches/JetBrains/Kotlin}"
LOCAL_OUT_ROOT="$ROOT/build"
if [[ "$BUILD_TYPE" == "Release" && -n "${COVIO_RELEASE_KMP_CACHE_DIR:-}" ]]; then
  CACHE_OUT_ROOT="$COVIO_RELEASE_KMP_CACHE_DIR"
  if [[ "$CACHE_OUT_ROOT" != /* ]]; then
    CACHE_OUT_ROOT="$ROOT/$CACHE_OUT_ROOT"
  fi
else
  CACHE_OUT_ROOT="$LOCAL_OUT_ROOT"
fi
OUT_DIR="$CACHE_OUT_ROOT/kmp-framework"
FRAMEWORK="$OUT_DIR/$MODULE.framework"
STATIC_OUT_DIR="$CACHE_OUT_ROOT/kmp-framework-static"
STATIC_FRAMEWORK="$STATIC_OUT_DIR/$MODULE.framework"
PUBLIC_OUT_DIR="$LOCAL_OUT_ROOT/kmp-framework"
PUBLIC_STATIC_OUT_DIR="$LOCAL_OUT_ROOT/kmp-framework-static"
CACHE_STAMP="$CACHE_OUT_ROOT/kmp-frameworks.stamp"
KLIB="$ROOT/build/tasks/_${MODULE}_compile${PLATFORM_ID}${BUILD_TYPE}/${MODULE}.klib"
BUNDLE_ID="com.wyz.covio.$MODULE"
TEMP_PATHS=()

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  printf 'This script requires an Apple Silicon Mac.\n' >&2
  exit 1
fi

if [[ "$BUILD_TYPE" != "Debug" && "$BUILD_TYPE" != "Release" ]]; then
  printf 'BUILD_TYPE must be Debug or Release, got: %s\n' "$BUILD_TYPE" >&2
  exit 1
fi

remove_path() {
  local path="$1"
  if [[ -d "$path" && ! -L "$path" ]]; then
    find "$path" -depth -delete
  elif [[ -e "$path" || -L "$path" ]]; then
    unlink "$path"
  fi
}

remove_path_if_symlink() {
  local path="$1"
  if [[ -L "$path" ]]; then
    remove_path "$path"
  fi
}

cleanup_temporary_paths() {
  local path
  for path in "${TEMP_PATHS[@]:-}"; do
    if [[ -n "$path" && -e "$path" ]]; then
      find "$path" -depth -delete
    fi
  done
}
trap cleanup_temporary_paths EXIT

# konanc 的路径随 Amper 版本变化，必须发现，不能写死。
find_konanc() {
  if [[ -n "${KONANC:-}" ]]; then
    printf '%s\n' "$KONANC"
    return
  fi
  local -a found=()
  local p
  for p in "$SHARED_CACHE"/extract.cache/*-kotlin-native-prebuilt-*-macos-aarch64.*/bin/konanc \
           "$HOME"/.konan/kotlin-native-prebuilt-*/bin/konanc; do
    [[ -x "$p" ]] && found+=("$p")
  done
  if [[ ${#found[@]} -eq 0 ]]; then
    return 1
  fi
  # 多个发行版时取版本号最大的一个。
  printf '%s\n' "${found[@]}" \
    | while read -r path; do
        version="$(printf '%s' "$path" | sed -E 's|.*kotlin-native-prebuilt-([0-9][0-9.]*)[-/].*|\1|')"
        printf '%s %s\n' "$version" "$path"
      done \
    | sort -k1,1V \
    | tail -1 \
    | cut -d' ' -f2-
}

# Amper CLI 自带 JRE，konanc 需要一个 java 可执行文件。
find_java_home() {
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
    printf '%s\n' "$JAVA_HOME"
    return
  fi
  local p
  for p in "$SHARED_CACHE"/cli/zulu*/*/*/Contents/Home \
           "$SHARED_CACHE"/cli/*/*/Contents/Home; do
    if [[ -x "$p/bin/java" ]]; then
      printf '%s\n' "$p"
      return
    fi
  done
  if p="$(/usr/libexec/java_home 2>/dev/null)" && [[ -x "$p/bin/java" ]]; then
    printf '%s\n' "$p"
    return
  fi
  return 1
}

# Amper 已经解析好依赖。读它的解析结果，避免自己算传递依赖与版本。
# 直接扫 .m2.cache 会同时看到多个版本，选错版本。
resolve_dep_klibs() {
  local graph
  graph="$(cd "$ROOT" && /bin/sh ./kotlin show dependencies \
    -m "$MODULE" --platform-group=native --scope=compile 2>/dev/null)" || return 1
  printf '%s\n' "$graph" \
    | LC_ALL=C grep -oE "[A-Za-z0-9._-]+:[A-Za-z0-9._-]+-$(printf '%s' "$PLATFORM" | tr '[:upper:]' '[:lower:]'):[A-Za-z0-9._-]+" \
    | sort -u
}

klib_path_for() {
  local coord="$1"
  local group="${coord%%:*}"
  local rest="${coord#*:}"
  local artifact="${rest%%:*}"
  local version="${rest#*:}"
  local group_path
  group_path="$(printf '%s' "$group" | tr '.' '/')"
  printf '%s/%s/%s/%s/%s-%s.klib\n' \
    "$SHARED_CACHE/.m2.cache" "$group_path" "$artifact" "$version" "$artifact" "$version"
}

cd "$ROOT"
printf 'Compiling %s [%s %s]...\n' "$MODULE" "$PLATFORM" "$BUILD_TYPE"
# Amper 在这一步把 konanc 与它自带的 JRE 解压到共享缓存。
# 冷机器上这一步之前缓存是空的，所以下面两处发现必须排在它之后。
# 顺序写反会让 CI 与刚克隆的机器报「Cannot find konanc」。
/bin/sh ./kotlin task ":${MODULE}:compile${PLATFORM_ID}${BUILD_TYPE}"

KONANC_BIN="$(find_konanc)" || {
  printf 'Cannot find konanc. Looked under %s/extract.cache and ~/.konan.\n' "$SHARED_CACHE" >&2
  printf 'Set KONANC=/path/to/konanc.\n' >&2
  exit 1
}

JAVA_HOME_DIR="$(find_java_home)" || {
  printf 'Cannot find a Java runtime for konanc. Set JAVA_HOME.\n' >&2
  exit 1
}
export JAVA_HOME="$JAVA_HOME_DIR"

printf 'konanc: %s\n' "$KONANC_BIN"
printf 'java:   %s\n' "$JAVA_HOME/bin/java"

if [[ ! -f "$KLIB" ]]; then
  printf 'Missing klib: %s\n' "$KLIB" >&2
  exit 1
fi

LIB_ARGS=()
DEP_KLIB_PATHS=()
while read -r coord; do
  [[ -z "$coord" ]] && continue
  dep_klib="$(klib_path_for "$coord")"
  if [[ ! -f "$dep_klib" ]]; then
    printf 'Missing dependency klib for %s\n  expected at: %s\n' "$coord" "$dep_klib" >&2
    exit 1
  fi
  printf 'linking %s\n' "$coord"
  LIB_ARGS+=(-library "$dep_klib")
  DEP_KLIB_PATHS+=("$dep_klib")
done < <(resolve_dep_klibs)

LINK_FLAGS=(-produce framework -target "$TARGET" -Xbinary=bundleId="$BUNDLE_ID")
if [[ "$BUILD_TYPE" == "Release" ]]; then
  LINK_FLAGS+=(-opt)
else
  LINK_FLAGS+=(-g)
fi

artifact_hash() {
  local framework="$1"
  {
    shasum -a 256 "$framework/$MODULE" | awk '{print $1}'
    shasum -a 256 "$framework/Headers/$MODULE.h" | awk '{print $1}'
  } | shasum -a 256 | awk '{print $1}'
}

cache_fingerprint() {
  python3 -I - \
    "$ROOT" \
    "$BUILD_TYPE" \
    "$TARGET" \
    "$BUNDLE_ID" \
    "${LINK_FLAGS[*]}" \
    "$KONANC_BIN" \
    "$JAVA_HOME_DIR" \
    "${DEP_KLIB_PATHS[@]}" <<'PY'
import hashlib
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
build_type, target, bundle_id, link_flags = sys.argv[2:6]
konanc = sys.argv[6]
java_home = pathlib.Path(sys.argv[7])
dependencies = [pathlib.Path(value) for value in sys.argv[8:]]
digest = hashlib.sha256()


def add(label, value):
    encoded = value if isinstance(value, bytes) else value.encode("utf-8")
    digest.update(label.encode("utf-8"))
    digest.update(b"\0")
    digest.update(len(encoded).to_bytes(8, "big"))
    digest.update(encoded)


def add_file(label, path):
    add(label, path.read_bytes())


def command_output(command):
    result = subprocess.run(
        command,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    return f"exit={result.returncode}\n".encode("utf-8") + result.stdout


add("schema", "covio-kmp-framework-cache-v1")
add("buildType", build_type)
add("target", target)
add("bundleId", bundle_id)
add("linkFlags", link_flags)
add("konanc", command_output([konanc, "-version"]))
add("java", command_output([str(java_home / "bin" / "java"), "-version"]))

fixed_inputs = (
    root / "project.yaml",
    root / "libs.versions.toml",
    root / "kmpDomain" / "module.yaml",
    root / "scripts" / "build-kmp-framework.sh",
    root / "kotlin",
)
for path in fixed_inputs:
    add_file(path.relative_to(root).as_posix(), path)

source_root = root / "kmpDomain" / "src"
for path in sorted(item for item in source_root.rglob("*") if item.is_file()):
    add_file(path.relative_to(root).as_posix(), path)

for index, path in enumerate(dependencies):
    add_file(f"dependency-{index}", path)

print(digest.hexdigest())
PY
}

cache_is_valid() {
  local expected_fingerprint="$1"
  [[ -f "$CACHE_STAMP" ]] || return 1
  [[ -f "$FRAMEWORK/$MODULE" ]] || return 1
  [[ -f "$FRAMEWORK/Headers/$MODULE.h" ]] || return 1
  [[ -d "$FRAMEWORK.dSYM" ]] || return 1
  [[ -f "$STATIC_FRAMEWORK/$MODULE" ]] || return 1
  [[ -f "$STATIC_FRAMEWORK/Headers/$MODULE.h" ]] || return 1
  [[ "$(sed -n 's/^fingerprint=//p' "$CACHE_STAMP")" == "$expected_fingerprint" ]] || return 1
  [[ "$(sed -n 's/^dynamic=//p' "$CACHE_STAMP")" == "$(artifact_hash "$FRAMEWORK")" ]] || return 1
  [[ "$(sed -n 's/^static=//p' "$CACHE_STAMP")" == "$(artifact_hash "$STATIC_FRAMEWORK")" ]] || return 1
}

ensure_public_link() {
  local cache_dir="$1" public_dir="$2"
  [[ "$cache_dir" == "$public_dir" ]] && return 0
  if [[ -L "$public_dir" && "$(readlink "$public_dir")" == "$cache_dir" ]]; then
    return 0
  fi
  remove_path "$public_dir"
  ln -s "$cache_dir" "$public_dir"
}

replace_framework() {
  local source="$1" target="$2"
  remove_path "$target"
  remove_path "$target.dSYM"
  mv "$source" "$target"
  if [[ -d "$source.dSYM" ]]; then
    mv "$source.dSYM" "$target.dSYM"
  fi
}

write_cache_stamp() {
  local fingerprint="$1" temporary="$CACHE_STAMP.tmp.$$"
  TEMP_PATHS+=("$temporary")
  {
    printf 'schema=1\n'
    printf 'fingerprint=%s\n' "$fingerprint"
    printf 'dynamic=%s\n' "$(artifact_hash "$FRAMEWORK")"
    printf 'static=%s\n' "$(artifact_hash "$STATIC_FRAMEWORK")"
  } >"$temporary"
  mv "$temporary" "$CACHE_STAMP"
}

FINGERPRINT="$(cache_fingerprint)"
mkdir -p "$CACHE_OUT_ROOT"
if [[ "$CACHE_OUT_ROOT" != "$LOCAL_OUT_ROOT" ]]; then
  KMP_CACHE_LOCK="$CACHE_OUT_ROOT.lock"
  if ! /usr/bin/shlock -f "$KMP_CACHE_LOCK" -p $$; then
    printf 'KMP framework cache is in use: %s\n' "$CACHE_OUT_ROOT" >&2
    exit 1
  fi
  TEMP_PATHS+=("$KMP_CACHE_LOCK")
fi
remove_path_if_symlink "$OUT_DIR"
remove_path_if_symlink "$STATIC_OUT_DIR"
mkdir -p "$OUT_DIR" "$STATIC_OUT_DIR"

if cache_is_valid "$FINGERPRINT"; then
  ensure_public_link "$OUT_DIR" "$PUBLIC_OUT_DIR"
  ensure_public_link "$STATIC_OUT_DIR" "$PUBLIC_STATIC_OUT_DIR"
  printf 'KMP cache hit: %s [%s]\n' "$MODULE" "$BUILD_TYPE"
  exit 0
fi

DYNAMIC_TEMP_ROOT="$(mktemp -d "$CACHE_OUT_ROOT/.kmp-dynamic.XXXXXX")"
STATIC_TEMP_ROOT="$(mktemp -d "$CACHE_OUT_ROOT/.kmp-static.XXXXXX")"
TEMP_PATHS+=("$DYNAMIC_TEMP_ROOT" "$STATIC_TEMP_ROOT")

# -Xinclude 把 Amper 编好的 klib 当作源码处理。
# 只用 -library 会报 `you have not specified any compilation arguments`。
LINK_LOG="$OUT_DIR/link.log"
if ! "$KONANC_BIN" \
  "${LINK_FLAGS[@]}" \
  -Xinclude="$KLIB" \
  ${LIB_ARGS[@]+"${LIB_ARGS[@]}"} \
  -o "$DYNAMIC_TEMP_ROOT/$MODULE" \
  >"$LINK_LOG" 2>&1; then
  grep -v '^WARNING: ' "$LINK_LOG" >&2 || true
  printf 'konanc failed. Full log: %s\n' "$LINK_LOG" >&2
  exit 1
fi

if [[ ! -f "$DYNAMIC_TEMP_ROOT/$MODULE.framework/$MODULE" ]]; then
  printf 'Framework was not produced: %s\n' "$FRAMEWORK" >&2
  exit 1
fi

if [[ ! -f "$DYNAMIC_TEMP_ROOT/$MODULE.framework/Headers/$MODULE.h" ]]; then
  printf 'Framework has no header: %s/Headers/%s.h\n' "$FRAMEWORK" "$MODULE" >&2
  exit 1
fi

STATIC_LINK_LOG="$STATIC_OUT_DIR/link.log"
if ! "$KONANC_BIN" \
  "${LINK_FLAGS[@]}" \
  -Xstatic-framework \
  -Xinclude="$KLIB" \
  ${LIB_ARGS[@]+"${LIB_ARGS[@]}"} \
  -o "$STATIC_TEMP_ROOT/$MODULE" \
  >"$STATIC_LINK_LOG" 2>&1; then
  grep -v '^WARNING: ' "$STATIC_LINK_LOG" >&2 || true
  printf 'konanc static link failed. Full log: %s\n' "$STATIC_LINK_LOG" >&2
  exit 1
fi

if [[ ! -f "$STATIC_TEMP_ROOT/$MODULE.framework/$MODULE" ]]; then
  printf 'Static framework was not produced: %s\n' "$STATIC_FRAMEWORK" >&2
  exit 1
fi

if [[ ! -f "$STATIC_TEMP_ROOT/$MODULE.framework/Headers/$MODULE.h" ]]; then
  printf 'Static framework has no header: %s/Headers/%s.h\n' "$STATIC_FRAMEWORK" "$MODULE" >&2
  exit 1
fi

remove_path "$CACHE_STAMP"
replace_framework "$DYNAMIC_TEMP_ROOT/$MODULE.framework" "$FRAMEWORK"
replace_framework "$STATIC_TEMP_ROOT/$MODULE.framework" "$STATIC_FRAMEWORK"
ensure_public_link "$OUT_DIR" "$PUBLIC_OUT_DIR"
ensure_public_link "$STATIC_OUT_DIR" "$PUBLIC_STATIC_OUT_DIR"
write_cache_stamp "$FINGERPRINT"

printf 'Built %s\n' "$FRAMEWORK"
file "$FRAMEWORK/$MODULE"
printf 'Built %s\n' "$STATIC_FRAMEWORK"
file "$STATIC_FRAMEWORK/$MODULE"

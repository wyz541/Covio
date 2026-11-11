#!/bin/bash
set -euo pipefail

# 固定路径 CovioHelper 的本机验证。
#
# 做三件事：
#   1. 检查 app、固定 helper、LaunchDaemon plist 和 root-owned 元数据。
#   2. 检查 app 与运行中的 helper 发布身份完全一致。
#   3. 用 selftest 验证每一项断言真的会失败。
#
# 用法：
#   scripts/verify-helper-cutover.sh preflight   只读检查路径，不需要 root
#   scripts/verify-helper-cutover.sh verify      只读检查完整安装，不需要 root
#   scripts/verify-helper-cutover.sh selftest    在临时目录跑断言，不碰系统
#   scripts/verify-helper-cutover.sh all         重装 helper 并验证
#   scripts/verify-helper-cutover.sh uninstall   卸载，需要管理员授权
#
# **警告：** `all` 与 `uninstall` 会请求管理员授权。
# 安装期间特权控制会短暂失效。
# 运行前保存工作，并确认可以中断。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
if [[ -n "${COVIO_APP:-}" ]]; then
  APP="$COVIO_APP"
else
  DERIVED_DATA="$(python3 -I "$ROOT/scripts/build_cache.py" prepare "$ROOT")"
  APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/Covio.app"
fi
APP_BINARY="$APP/Contents/MacOS/Covio"
BUNDLED_HELPER="$APP/Contents/MacOS/CovioHelper"
HELPER_DIR="${COVIO_HELPER_DIR:-/Library/Application Support/Covio}"
HELPER_BINARY="${COVIO_HELPER_BINARY:-$HELPER_DIR/bin/CovioHelper}"
PLIST_PATH="${COVIO_HELPER_PLIST:-/Library/LaunchDaemons/com.wyz.covio.helper.plist}"
ALLOWED_UID_PATH="$HELPER_DIR/allowed_uid"
CLIENT_REQUIREMENT_PATH="$HELPER_DIR/client-requirement"
VERSION_PATH="$HELPER_DIR/version"
APP_PATH_FILE="$HELPER_DIR/Covio.app"
LABEL="${COVIO_HELPER_LABEL:-com.wyz.covio.helper}"
XPC_SERVICE="${COVIO_HELPER_XPC_SERVICE:-com.wyz.covio.helper.xpc}"
EXPECTED_HELPER_OWNER="${COVIO_EXPECT_HELPER_OWNER:-root:wheel}"
EXPECTED_PLIST_OWNER="${COVIO_EXPECT_PLIST_OWNER:-root:wheel}"
EXPECTED_METADATA_OWNER="${COVIO_EXPECT_METADATA_OWNER:-root:wheel}"
SKIP_LIVE_CHECKS="${COVIO_SKIP_LIVE_CHECKS:-0}"
SKIP_CODE_SIGNATURE="${COVIO_SKIP_CODE_SIGNATURE:-0}"
SKIP_BINARY_CHECKS="${COVIO_SKIP_BINARY_CHECKS:-0}"
SKIP_HANDSHAKE_CHECK="${COVIO_SKIP_HANDSHAKE_CHECK:-0}"
FAILURES=0

step() { printf '\n== %s ==\n' "$1"; }
info() { printf '  info  %s\n' "$1"; }
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  fail  %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

require_app() {
  [[ -d "$APP" ]] || { printf 'missing app: %s\n' "$APP" >&2; return 1; }
  [[ -x "$APP_BINARY" ]] || { printf 'missing app executable: %s\n' "$APP_BINARY" >&2; return 1; }
  [[ -x "$BUNDLED_HELPER" ]] || { printf 'missing bundled helper: %s\n' "$BUNDLED_HELPER" >&2; return 1; }
}

expected_version() {
  if [[ -n "${COVIO_EXPECT_VERSION:-}" ]]; then
    printf '%s\n' "$COVIO_EXPECT_VERSION"
    return
  fi
  python3 -I - "$ROOT/release/release-manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    print(json.load(stream)["clientVersion"])
PY
}

console_uid() {
  if [[ -n "${COVIO_EXPECT_UID:-}" ]]; then
    printf '%s\n' "$COVIO_EXPECT_UID"
    return
  fi
  local user
  user="$(/usr/bin/stat -f '%Su' /dev/console)"
  /usr/bin/id -u "$user"
}

check_owner_mode() {
  local path="$1" expected_owner="$2" expected_mode="$3" label="$4"
  local owner mode
  owner="$(/usr/bin/stat -f '%Su:%Sg' "$path" 2>/dev/null || true)"
  mode="$(/usr/bin/stat -f '%Lp' "$path" 2>/dev/null || true)"
  if [[ "$owner" == "$expected_owner" && "$mode" == "$expected_mode" ]]; then
    pass "$label owner=$owner mode=$mode"
  else
    fail "$label owner=$owner mode=$mode expected=$expected_owner/$expected_mode"
  fi
}

verify_plist() {
  /usr/bin/plutil -lint "$PLIST_PATH" >/dev/null || {
    fail "LaunchDaemon plist is invalid"
    return
  }
  if python3 -I - "$PLIST_PATH" "$LABEL" "$HELPER_BINARY" "$XPC_SERVICE" <<'PY'
import plistlib
import sys
path, label, helper, service = sys.argv[1:]
with open(path, "rb") as stream:
    plist = plistlib.load(stream)
checks = {
    "Label": plist.get("Label") == label,
    "ProgramArguments": plist.get("ProgramArguments") == [helper],
    "MachServices": plist.get("MachServices", {}).get(service) is True,
    "RunAtLoad": plist.get("RunAtLoad") is True,
    "KeepAlive": plist.get("KeepAlive") is True,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("invalid plist keys: " + ", ".join(failed))
PY
  then
    pass "LaunchDaemon plist points to $HELPER_BINARY and declares $XPC_SERVICE"
  else
    fail "LaunchDaemon plist keys are invalid"
  fi
}

verify_identities() {
  local app_identity helper_identity helper_sha
  app_identity="$("$APP_BINARY" --print-release-identity)" || {
    fail "app release identity probe failed"
    return
  }
  helper_identity="$("$HELPER_BINARY" --print-release-identity)" || {
    fail "helper release identity probe failed"
    return
  }
  helper_sha="$(/usr/bin/shasum -a 256 "$HELPER_BINARY" | awk '{print $1}')"
  if python3 -I - "$app_identity" "$helper_identity" "$helper_sha" <<'PY'
import json
import sys
app = json.loads(sys.argv[1])
helper = json.loads(sys.argv[2])
digest = sys.argv[3]
fields = (
    "releaseId",
    "clientVersion",
    "productVersion",
    "buildNumber",
    "gitCommit",
    "protocolVersion",
    "helperSHA256",
    "channel",
)
for field in fields:
    if app.get(field) != helper.get(field):
        raise SystemExit(f"{field} differs: app={app.get(field)!r} helper={helper.get(field)!r}")
if helper.get("helperSHA256") != digest:
    raise SystemExit("helperSHA256 does not match the fixed helper file")
PY
  then
    pass "fixed helper identity matches the app and file digest"
  else
    fail "fixed helper identity does not match the app or file digest"
  fi
}

cmd_preflight() {
  require_app
  printf 'app=%s\n' "$APP"
  printf 'bundled_helper=%s\n' "$BUNDLED_HELPER"
  printf 'helper=%s\n' "$HELPER_BINARY"
  printf 'launch_daemon=%s\n' "$PLIST_PATH"
  printf 'helper_exists=%s\n' "$([[ -x "$HELPER_BINARY" ]] && printf true || printf false)"
  printf 'plist_exists=%s\n' "$([[ -f "$PLIST_PATH" ]] && printf true || printf false)"
}

cmd_verify() {
  require_app
  step "固定路径"
  [[ -x "$HELPER_BINARY" ]] && pass "helper executable exists" || fail "helper executable is missing"
  [[ -f "$PLIST_PATH" ]] && pass "LaunchDaemon plist exists" || fail "LaunchDaemon plist is missing"
  [[ -f "$ALLOWED_UID_PATH" ]] && pass "allowed_uid exists" || fail "allowed_uid is missing"
  [[ -f "$CLIENT_REQUIREMENT_PATH" ]] && pass "client-requirement exists" || fail "client-requirement is missing"
  [[ -f "$VERSION_PATH" ]] && pass "version exists" || fail "version is missing"
  [[ -f "$APP_PATH_FILE" ]] && pass "app path marker exists" || fail "app path marker is missing"
  if [[ "$FAILURES" -ne 0 ]]; then
    printf '\nverify 有 %d 处不通过。\n' "$FAILURES" >&2
    return 1
  fi

  step "所有权与权限"
  check_owner_mode "$HELPER_DIR" "$EXPECTED_HELPER_OWNER" "755" "helper directory"
  check_owner_mode "$(dirname "$HELPER_BINARY")" "$EXPECTED_HELPER_OWNER" "755" "helper binary directory"
  check_owner_mode "$HELPER_BINARY" "$EXPECTED_HELPER_OWNER" "755" "helper binary"
  check_owner_mode "$PLIST_PATH" "$EXPECTED_PLIST_OWNER" "644" "LaunchDaemon plist"
  for file in "$ALLOWED_UID_PATH" "$CLIENT_REQUIREMENT_PATH" "$VERSION_PATH" "$APP_PATH_FILE"; do
    check_owner_mode "$file" "$EXPECTED_METADATA_OWNER" "644" "$(basename "$file")"
  done

  step "内容契约"
  local uid expected actual version
  uid="$(console_uid)"
  actual="$(cat "$ALLOWED_UID_PATH" 2>/dev/null || true)"
  [[ "$actual" == "$uid" ]] && pass "allowed_uid=$uid" || fail "allowed_uid=$actual expected=$uid"
  [[ -s "$CLIENT_REQUIREMENT_PATH" ]] && pass "client-requirement is not empty" || fail "client-requirement is empty"
  version="$(expected_version)"
  actual="$(cat "$VERSION_PATH" 2>/dev/null || true)"
  [[ "$actual" == "$version" ]] && pass "version=$version" || fail "version=$actual expected=$version"
  actual="$(cat "$APP_PATH_FILE" 2>/dev/null || true)"
  [[ "$actual" == "$BUNDLED_HELPER" ]] && pass "app path marker points to the bundled helper" || \
    fail "app path marker=$actual expected=$BUNDLED_HELPER"
  verify_plist

  step "代码与身份"
  if [[ "$SKIP_CODE_SIGNATURE" == "1" ]]; then
    info "skip code signature in selftest"
  else
    /usr/bin/codesign --verify --strict "$HELPER_BINARY" >/dev/null 2>&1 && \
      pass "helper signature is valid" || fail "helper signature is invalid"
  fi
  if [[ "$SKIP_BINARY_CHECKS" == "1" ]]; then
    info "skip Mach-O checks in selftest"
  else
    [[ "$(/usr/bin/lipo -archs "$HELPER_BINARY")" == "arm64" ]] && \
      pass "helper is arm64" || fail "helper must be arm64"
    if /usr/bin/otool -L "$HELPER_BINARY" | /usr/bin/grep -Eq 'kmpDomain|AppKit|SwiftUI|Vision|AVFoundation'; then
      fail "helper links an app-only dynamic framework"
    else
      pass "helper has no app-only dynamic dependency"
    fi
  fi
  if [[ "$FAILURES" -eq 0 ]]; then
    verify_identities
  fi

  step "运行状态"
  if [[ "$SKIP_LIVE_CHECKS" != "1" ]]; then
    if /bin/launchctl print "system/$LABEL" >/dev/null 2>&1; then
      pass "launchd service is loaded"
    else
      fail "launchd service is not loaded"
    fi
  else
    info "skip launchd check in selftest"
  fi
  if [[ "$SKIP_HANDSHAKE_CHECK" != "1" ]]; then
    if "$APP_BINARY" --verify-install-transaction >/dev/null 2>&1; then
      pass "app and running helper handshake is MATCH"
    else
      fail "app and running helper handshake is not MATCH"
    fi
  fi

  if [[ "$FAILURES" -eq 0 ]]; then
    printf '\nverify 通过。\n'
  else
    printf '\nverify 有 %d 处不通过。\n' "$FAILURES" >&2
    return 1
  fi
}

cmd_uninstall() {
  require_app
  if [[ ! -e "$PLIST_PATH" && ! -e "$HELPER_BINARY" ]]; then
    info "helper is already absent"
    return 0
  fi
  step "卸载 helper"
  printf '需要管理员授权。会弹出系统对话框。\n'
  "$APP_BINARY" --uninstall-helper
  [[ ! -e "$PLIST_PATH" && ! -e "$HELPER_BINARY" ]] || {
    fail "uninstall left fixed helper paths behind"
    return 1
  }
  pass "卸载完成"
}

cmd_all() {
  require_app
  printf '**警告：** 本命令会先卸载当前 helper，再安装本版 helper。\n'
  printf '特权控制会短暂失效。按回车继续，Ctrl-C 取消。\n'
  read -r _
  cmd_uninstall || return 1
  step "安装本版 helper"
  printf '需要管理员授权。会弹出系统对话框。\n'
  "$APP_BINARY" --install-helper || {
    fail "安装失败"
    return 1
  }
  pass "安装完成"
  FAILURES=0
  cmd_verify
}

cmd_selftest() {
  local sandbox
  sandbox="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/covio-local-helper-selftest.XXXXXX")"
  # shellcheck disable=SC2064
  trap "find '$sandbox' -depth -delete" EXIT

  local app="$sandbox/Covio.app"
  local app_binary="$app/Contents/MacOS/Covio"
  local bundled_helper="$app/Contents/MacOS/CovioHelper"
  local helper_dir="$sandbox/helper"
  local helper="$helper_dir/bin/CovioHelper"
  local plist="$sandbox/com.wyz.covio.helper.plist"
  local allowed_uid="$helper_dir/allowed_uid"
  local requirement="$helper_dir/client-requirement"
  local version_file="$helper_dir/version"
  local marker="$helper_dir/Covio.app"
  local version product_version build_number protocol commit release_id
  version="$(expected_version)"
  product_version="$(python3 -I - "$ROOT/release/release-manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    print(json.load(stream)["productVersion"])
PY
)"
  build_number="$(python3 -I - "$ROOT/release/release-manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    print(json.load(stream)["buildNumber"])
PY
)"
  protocol="$(python3 -I - "$ROOT/release/release-manifest.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    print(json.load(stream)["helperProtocolVersion"])
PY
)"
  commit="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  release_id="$version-g$commit"

  mkdir -p "$app/Contents/MacOS" "$helper_dir/bin"
  cat > "$app_binary" <<STUB
#!/bin/bash
helper_sha="\$(/usr/bin/shasum -a 256 "\$0" | /usr/bin/awk '{print \$1}')"
case "\${1:-}" in
  --print-release-identity)
    printf '%s\n' '{"releaseId":"$release_id","clientVersion":"$version","productVersion":"$product_version","buildNumber":"$build_number","gitCommit":"$commit","protocolVersion":"$protocol","helperSHA256":"'\$helper_sha'","channel":"internal"}'
    ;;
  --verify-install-transaction)
    [[ "\${COVIO_SELFTEST_VERIFY_RESULT:-1}" == "1" ]]
    ;;
  --install-helper|--uninstall-helper) exit 0 ;;
esac
STUB
  chmod 0755 "$app_binary"
  cp "$app_binary" "$bundled_helper"
  chmod 0755 "$bundled_helper"

  reset_fixture() {
    find "$helper_dir" -mindepth 1 -depth -delete
    mkdir -p "$helper_dir/bin"
    cp "$bundled_helper" "$helper"
    chmod 0755 "$helper"
    /usr/bin/id -u > "$allowed_uid"
    printf 'identifier "com.wyz.covio"\n' > "$requirement"
    printf '%s\n' "$version" > "$version_file"
    printf '%s\n' "$bundled_helper" > "$marker"
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$helper</string></array>
  <key>MachServices</key>
  <dict><key>$XPC_SERVICE</key><true/></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
PLIST
    chmod 0755 "$helper_dir" "$helper_dir/bin"
    chmod 0755 "$helper"
    chmod 0644 "$plist" "$allowed_uid" "$requirement" "$version_file" "$marker"
  }

  run_verify() {
    if [[ "${COVIO_SELFTEST_DEBUG:-0}" == "1" ]]; then
      COVIO_APP="$app" \
      COVIO_HELPER_DIR="$helper_dir" \
      COVIO_HELPER_BINARY="$helper" \
      COVIO_HELPER_PLIST="$plist" \
      COVIO_EXPECT_HELPER_OWNER="$(/usr/bin/id -un):$(/usr/bin/id -gn)" \
      COVIO_EXPECT_PLIST_OWNER="$(/usr/bin/id -un):$(/usr/bin/id -gn)" \
      COVIO_EXPECT_METADATA_OWNER="$(/usr/bin/id -un):$(/usr/bin/id -gn)" \
      COVIO_EXPECT_UID="$(/usr/bin/id -u)" \
      COVIO_EXPECT_VERSION="$version" \
      COVIO_SKIP_CODE_SIGNATURE=1 \
      COVIO_SKIP_BINARY_CHECKS=1 \
      COVIO_SKIP_LIVE_CHECKS=1 \
      COVIO_SELFTEST_VERIFY_RESULT="${SELFTEST_VERIFY_RESULT:-1}" \
        "$ROOT/scripts/verify-helper-cutover.sh" verify
      return
    fi
    COVIO_APP="$app" \
    COVIO_HELPER_DIR="$helper_dir" \
    COVIO_HELPER_BINARY="$helper" \
    COVIO_HELPER_PLIST="$plist" \
    COVIO_EXPECT_HELPER_OWNER="$(/usr/bin/id -un):$(/usr/bin/id -gn)" \
    COVIO_EXPECT_PLIST_OWNER="$(/usr/bin/id -un):$(/usr/bin/id -gn)" \
    COVIO_EXPECT_METADATA_OWNER="$(/usr/bin/id -un):$(/usr/bin/id -gn)" \
    COVIO_EXPECT_UID="$(/usr/bin/id -u)" \
    COVIO_EXPECT_VERSION="$version" \
    COVIO_SKIP_CODE_SIGNATURE=1 \
    COVIO_SKIP_BINARY_CHECKS=1 \
    COVIO_SKIP_LIVE_CHECKS=1 \
    COVIO_SELFTEST_VERIFY_RESULT="${SELFTEST_VERIFY_RESULT:-1}" \
      "$ROOT/scripts/verify-helper-cutover.sh" verify >/dev/null 2>&1
  }

  local sandbox_failures=0
  check_case() {
    local name="$1" expect="$2" mutate="$3"
    reset_fixture
    SELFTEST_VERIFY_RESULT=1
    eval "$mutate"
    local actual=ok
    run_verify || actual=broken
    if [[ "$actual" == "$expect" ]]; then
      pass "$name"
    else
      fail "$name expected=$expect actual=$actual"
      sandbox_failures=$((sandbox_failures + 1))
    fi
  }

  step "正确布局必须通过"
  check_case "完整固定路径布局" "ok" ":"
  step "逐项破坏必须被抓到"
  check_case "version 过期" "broken" "printf '0.0.1\n' > '$version_file'"
  check_case "allowed_uid 不是当前用户" "broken" "printf '99999\n' > '$allowed_uid'"
  check_case "固定 helper 缺失" "broken" "unlink '$helper'"
  check_case "app path marker 错误" "broken" "printf '/bin/false\n' > '$marker'"
  check_case "client requirement 为空" "broken" ": > '$requirement'"
  check_case "plist Label 错误" "broken" "/usr/bin/plutil -replace Label -string com.example.other '$plist'"
  check_case "ProgramArguments 错误" "broken" "/usr/bin/plutil -replace ProgramArguments.0 -string /bin/false '$plist'"
  check_case "MachServices 缺失" "broken" "/usr/bin/plutil -remove MachServices '$plist'"
  check_case "helper 权限过宽" "broken" "chmod 0777 '$helper'"
  check_case "plist 权限过宽" "broken" "chmod 0666 '$plist'"
  check_case "首次握手失败" "broken" "SELFTEST_VERIFY_RESULT=0"

  if [[ "$sandbox_failures" -eq 0 && "$FAILURES" -eq 0 ]]; then
    printf '\nselftest 通过。\n'
  else
    printf '\nselftest 有 %d 处不符合预期。\n' "$((sandbox_failures + FAILURES))" >&2
    return 1
  fi
}

usage() {
  /usr/bin/sed -n '3,24p' "$0"
  exit 1
}

case "${1:-}" in
  preflight) cmd_preflight ;;
  verify) cmd_verify ;;
  selftest) cmd_selftest ;;
  uninstall) cmd_uninstall ;;
  all) cmd_all ;;
  *) usage ;;
esac

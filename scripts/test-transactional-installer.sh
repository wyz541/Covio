#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/covio-installer-test.XXXXXX")"
cleanup_test_root() {
  if [[ "${COVIO_KEEP_TEST_ROOT:-0}" == "1" ]]; then
    printf 'Kept test root: %s\n' "$TEST_ROOT" >&2
    return
  fi
  find "$TEST_ROOT" -depth -delete
}
trap cleanup_test_root EXIT

fail() {
  printf 'transactional installer test failed: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"
  [[ "$actual" == "$expected" ]] || fail "$message (actual=$actual expected=$expected)"
}

assert_json() {
  local file="$1"
  local key="$2"
  local expected="$3"
  assert_eq "$(/usr/bin/plutil -extract "$key" raw -o - "$file")" "$expected" "$file $key"
}

assert_app_helper_record_match() {
  local app="$1"
  local expected_release_id="$2"
  assert_eq \
    "$(/usr/bin/plutil -extract CovioReleaseId raw -o - "$app/Contents/Info.plist")" \
    "$expected_release_id" \
    "app releaseId differs from the install transaction"
  assert_eq \
    "$(/usr/bin/plutil -extract releaseId raw -o - "$app/Contents/Resources/identity.json")" \
    "$expected_release_id" \
    "helper releaseId differs from the install transaction"
  assert_eq "$(/usr/bin/plutil -extract releaseId raw -o - "$TX_RECORD_PATH")" \
    "$expected_release_id" \
    "installed release record differs from the install transaction"
}

assert_updater_record_match() {
  local app="$1"
  local expected_release_id="$2"
  local current engine launcher updater_sha launcher_sha
  current="$(tr -d '[:space:]' < "$COVIO_TX_UPDATER_ROOT/current")"
  assert_eq "$current" "$expected_release_id" "updater current pointer differs"
  engine="$COVIO_TX_UPDATER_ROOT/versions/$expected_release_id/CovioUpdater"
  launcher="$COVIO_TX_UPDATER_ROOT/bin/CovioUpdaterLauncher"
  [[ -x "$engine" && -x "$launcher" ]] || fail "updater layout is incomplete"
  [[ -f "$COVIO_TX_UPDATER_LAUNCHD_PATH" ]] || fail "updater LaunchDaemon is missing"
  [[ -f "$COVIO_TX_UPDATER_ROOT/updater-client-requirement" ]] || fail "updater client requirement is missing"
  [[ -f "$COVIO_TX_UPDATER_ROOT/updater-requirement" ]] || fail "updater requirement is missing"
  updater_sha="$(/usr/bin/shasum -a 256 "$engine" | awk '{print $1}')"
  launcher_sha="$(/usr/bin/shasum -a 256 "$launcher" | awk '{print $1}')"
  assert_json "$TX_RECORD_PATH" updaterReleaseId "$expected_release_id"
  assert_json "$TX_RECORD_PATH" updaterProtocolVersion 1
  assert_json "$TX_RECORD_PATH" updaterSHA256 "$updater_sha"
  assert_json "$TX_RECORD_PATH" updaterLauncherSHA256 "$launcher_sha"
  assert_eq \
    "$(/usr/bin/plutil -extract CovioReleaseId raw -o - "$app/Contents/Info.plist")" \
    "$expected_release_id" \
    "app release ID differs from updater"
}

client_version_for_build() {
  local build="$1"
  local digits
  printf -v digits '%04d' "$build"
  printf '%s.%s.%s.%s' "${digits:0:1}" "${digits:1:1}" "${digits:2:1}" "${digits:3:1}"
}

release_id_for_build() {
  local build="$1"
  local commit="$2"
  local format="${3:-modern}"
  local client_version
  client_version="$(client_version_for_build "$build")"
  if [[ "$format" == "legacy" ]]; then
    printf '0.6.0+%s+%s' "$build" "$commit"
  else
    printf '%s-g%s' "$client_version" "$commit"
  fi
}

xcrun clang \
  -arch arm64 \
  -mmacosx-version-min=14.0 \
  -Wall -Wextra -Werror \
  "$ROOT/installer/atomic_swap.c" \
  -o "$TEST_ROOT/CovioTransaction"

FAKE_SOURCE="$TEST_ROOT/fake_covio.c"
cat > "$FAKE_SOURCE" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int bundle_root(char *output, size_t capacity, const char *executable) {
    const char *suffix = strstr(executable, "/Contents/MacOS/");
    if (suffix == NULL || (size_t)(suffix - executable) >= capacity) return 1;
    size_t length = (size_t)(suffix - executable);
    memcpy(output, executable, length);
    output[length] = '\0';
    return 0;
}

static int print_file(const char *path) {
    FILE *file = fopen(path, "r");
    if (file == NULL) return 1;
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), file) != NULL) fputs(buffer, stdout);
    fclose(file);
    return 0;
}

static int result_file(const char *bundle, const char *argument) {
    const char *name = argument + 2;
    char path[4096];
    snprintf(path, sizeof(path), "%s/Contents/Resources/%s.result", bundle, name);
    int value = 0;
    FILE *file = fopen(path, "r");
    if (file == NULL) return 0;
    if (fscanf(file, "%d", &value) != 1) value = 1;
    fclose(file);
    return value == 1 ? 0 : 1;
}

static int install_legacy_helper(const char *executable) {
    const char *helper = getenv("COVIO_TX_HELPER_PATH");
    const char *plist = getenv("COVIO_TX_LAUNCHD_PATH");
    if (helper == NULL || plist == NULL) return 1;
    char bundle[4096];
    char source[4096];
    char helper_dir[4096];
    char state_dir[4096];
    char plist_dir[4096];
    if (bundle_root(bundle, sizeof(bundle), executable) != 0) return 1;
    snprintf(source, sizeof(source), "%s/Contents/MacOS/CovioHelper", bundle);
    snprintf(helper_dir, sizeof(helper_dir), "%s", helper);
    snprintf(state_dir, sizeof(state_dir), "%s", helper);
    char *state_slash = strrchr(state_dir, '/');
    if (state_slash == NULL) return 1;
    *state_slash = '\0';
    state_slash = strrchr(state_dir, '/');
    if (state_slash == NULL) return 1;
    *state_slash = '\0';
    snprintf(plist_dir, sizeof(plist_dir), "%s", plist);
    char *slash = strrchr(helper_dir, '/');
    if (slash == NULL) return 1;
    *slash = '\0';
    slash = strrchr(plist_dir, '/');
    if (slash == NULL) return 1;
    *slash = '\0';
    char command[16000];
    snprintf(
        command,
        sizeof(command),
        "mkdir -p '%s' '%s' '%s' && cp '%s' '%s' && chmod 0755 '%s' && "
        "printf '%%s\n' 'test-requirement' > '%s/client-requirement' && "
        "printf '%%s\n' 'old' > '%s/version' && "
        "printf '%%s\n' '501' > '%s/allowed_uid' && "
        "printf '%%s\n' '%s' > '%s/Covio.app' && "
        "printf '%%s\n' '<plist><dict/></plist>' > '%s' && chmod 0644 '%s'",
        helper_dir,
        state_dir,
        plist_dir,
        source,
        helper,
        helper,
        state_dir,
        state_dir,
        state_dir,
        bundle,
        state_dir,
        plist,
        plist
    );
    return system(command) == 0 ? 0 : 1;
}

static int install_updater(const char *executable) {
    const char *root = getenv("COVIO_UPDATER_ROOT");
    const char *plist = getenv("COVIO_UPDATER_LAUNCHD_PATH");
    const char *release_id = getenv("COVIO_UPDATER_RELEASE_ID");
    if (root == NULL || plist == NULL || release_id == NULL) return 1;
    char bundle[4096];
    char plist_dir[4096];
    if (bundle_root(bundle, sizeof(bundle), executable) != 0) return 1;
    if (result_file(bundle, "--install-updater-as-root") != 0) return 1;
    snprintf(plist_dir, sizeof(plist_dir), "%s", plist);
    char *plist_slash = strrchr(plist_dir, '/');
    if (plist_slash == NULL) return 1;
    *plist_slash = '\0';
    char command[20000];
    snprintf(
        command,
        sizeof(command),
        "mkdir -p '%s/bin' '%s/versions/%s' '%s' && "
        "cp '%s/Contents/MacOS/CovioUpdater' '%s/versions/%s/CovioUpdater' && "
        "cp '%s/Contents/MacOS/CovioUpdaterLauncher' '%s/bin/CovioUpdaterLauncher' && "
        "cp '%s/Contents/Library/LaunchDaemons/com.wyz.covio.updater.plist' '%s' && "
        "printf '%%s\n' '%s' > '%s/current' && "
        "printf 'test-requirement\n' > '%s/updater-client-requirement' && "
        "printf 'test-requirement\n' > '%s/updater-requirement' && "
        "printf '{\"createdAt\":\"2026-11-04T00:00:00Z\",\"processIdentifier\":123,"
        "\"releaseId\":\"%s\",\"schemaVersion\":1}\n' > '%s/health.json' && "
        "chmod 0755 '%s/versions/%s/CovioUpdater' '%s/bin/CovioUpdaterLauncher' && "
        "chmod 0644 '%s'",
        root,
        root,
        release_id,
        plist_dir,
        bundle,
        root,
        release_id,
        bundle,
        root,
        bundle,
        plist,
        release_id,
        root,
        root,
        root,
        release_id,
        root,
        root,
        release_id,
        root,
        plist
    );
    return system(command) == 0 ? 0 : 1;
}

static int install_updater_engine(const char *executable) {
    const char *root = getenv("COVIO_UPDATER_ROOT");
    const char *old_release_id = getenv("COVIO_UPDATER_CURRENT_RELEASE_ID");
    const char *new_release_id = getenv("COVIO_UPDATER_NEW_RELEASE_ID");
    const char *expected_engine = getenv("COVIO_UPDATER_EXPECTED_SHA256");
    const char *expected_launcher = getenv("COVIO_UPDATER_EXPECTED_LAUNCHER_SHA256");
    if (root == NULL || old_release_id == NULL || new_release_id == NULL ||
        expected_engine == NULL || expected_launcher == NULL) {
        return 1;
    }
    char bundle[4096];
    if (bundle_root(bundle, sizeof(bundle), executable) != 0) return 1;
    if (result_file(bundle, "--install-updater-engine-as-root") != 0) return 1;
    char command[20000];
    snprintf(
        command,
        sizeof(command),
        "old=\"$(cat '%s/current')\" && test \"$old\" = '%s' && "
        "test \"$(shasum -a 256 '%s/bin/CovioUpdaterLauncher' | awk '{print $1}')\" = '%s' && "
        "test \"$(shasum -a 256 '%s/Contents/MacOS/CovioUpdater' | awk '{print $1}')\" = '%s' && "
        "mkdir -p '%s/versions/%s' && "
        "cp '%s/Contents/MacOS/CovioUpdater' '%s/versions/%s/CovioUpdater' && "
        "printf '%%s\\n' \"$old\" > '%s/previous' && "
        "printf '%%s\\n' '%s' > '%s/current' && "
        "chmod 0755 '%s/versions/%s/CovioUpdater'",
        root,
        old_release_id,
        root,
        expected_launcher,
        bundle,
        expected_engine,
        root,
        new_release_id,
        bundle,
        root,
        new_release_id,
        root,
        new_release_id,
        root,
        root,
        new_release_id
    );
    return system(command) == 0 ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char bundle[4096];
    if (bundle_root(bundle, sizeof(bundle), argv[0]) != 0) return 1;
    if (strcmp(argv[1], "--print-release-identity") == 0) {
        char path[4096];
        snprintf(path, sizeof(path), "%s/Contents/Resources/identity.json", bundle);
        return print_file(path);
    }
    if (strcmp(argv[1], "--helper-version") == 0) {
        char path[4096];
        snprintf(path, sizeof(path), "%s/Contents/Resources/version.txt", bundle);
        return print_file(path);
    }
    if (strcmp(argv[1], "--uninstall-helper") == 0) return 0;
    if (strcmp(argv[1], "--register-install-transaction-helper") == 0) return 0;
    if (strcmp(argv[1], "--install-updater-as-root") == 0) {
        return install_updater(argv[0]);
    }
    if (strcmp(argv[1], "--install-updater-engine-as-root") == 0) {
        return install_updater_engine(argv[0]);
    }
    if (strcmp(argv[1], "--install-legacy-helper-as-root") == 0) {
        return install_legacy_helper(argv[0]);
    }
    return result_file(bundle, argv[1]);
}
C

xcrun clang -arch arm64 -mmacosx-version-min=14.0 -Wall -Wextra -Werror \
  "$FAKE_SOURCE" -o "$TEST_ROOT/fake_covio"

build_app() {
  local app="$1"
  local product_version="$2"
  local build="$3"
  local commit="$4"
  local protocol="$5"
  local channel="$6"
  local verify_result="$7"
  local manifest_helper_sha="${8:-}"
  local transaction_version="${9:-1}"
  local prepare_result="${10:-1}"
  local install_mode="${11-legacy}"
  local identity_format="${12:-modern}"
  local updater_result="${13:-1}"
  local client_version release_id helper helper_sha manifest_sha info
  client_version="$(client_version_for_build "$build")"
  release_id="$(release_id_for_build "$build" "$commit" "$identity_format")"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" \
    "$app/Contents/Library/LaunchDaemons"
  cp "$TEST_ROOT/fake_covio" "$app/Contents/MacOS/Covio"
  cp "$TEST_ROOT/fake_covio" "$app/Contents/MacOS/CovioHelper"
  cp "$TEST_ROOT/fake_covio" "$app/Contents/MacOS/CovioUpdater"
  cp "$TEST_ROOT/fake_covio" "$app/Contents/MacOS/CovioUpdaterLauncher"
  cp "$ROOT/macosApp/daemons/com.wyz.covio.updater.plist" \
    "$app/Contents/Library/LaunchDaemons/com.wyz.covio.updater.plist"
  chmod 0755 "$app/Contents/MacOS/Covio" "$app/Contents/MacOS/CovioHelper" \
    "$app/Contents/MacOS/CovioUpdater" "$app/Contents/MacOS/CovioUpdaterLauncher"
  printf '%s\n' "$client_version" > "$app/Contents/Resources/version.txt"
  printf '%s\n' "$verify_result" > "$app/Contents/Resources/verify-install-transaction.result"
  printf '%s\n' "$prepare_result" > "$app/Contents/Resources/prepare-install-transaction.result"
  printf '1\n' > "$app/Contents/Resources/install-helper.result"
  printf '1\n' > "$app/Contents/Resources/install-legacy-helper-as-root.result"
  printf '%s\n' "$updater_result" > "$app/Contents/Resources/install-updater-as-root.result"
  helper="$app/Contents/MacOS/CovioHelper"
  /usr/bin/codesign --force --sign - "$helper" >/dev/null 2>&1
  helper_sha="$(/usr/bin/shasum -a 256 "$helper" | awk '{print $1}')"
  manifest_sha="${manifest_helper_sha:-$helper_sha}"
  if [[ "$identity_format" == "modern" ]]; then
    cat > "$app/Contents/Resources/identity.json" <<EOF
{"releaseId":"$release_id","clientVersion":"$client_version","productVersion":"$product_version","buildNumber":"$build","gitCommit":"$commit","protocolVersion":"$protocol","helperSHA256":"$helper_sha","channel":"$channel"}
EOF
    cat > "$app/Contents/Resources/release-manifest.json" <<EOF
{"schemaVersion":1,"releaseId":"$release_id","clientVersion":"$client_version","productVersion":"$product_version","buildNumber":$build,"gitCommit":"$commit","helperProtocolVersion":$protocol,"helperSHA256":"$manifest_sha","channel":"$channel"}
EOF
  else
    cat > "$app/Contents/Resources/identity.json" <<EOF
{"releaseId":"$release_id","productVersion":"$product_version","buildNumber":"$build","gitCommit":"$commit","protocolVersion":"$protocol","helperSHA256":"$helper_sha","channel":"$channel"}
EOF
    cat > "$app/Contents/Resources/release-manifest.json" <<EOF
{"schemaVersion":1,"releaseId":"$release_id","productVersion":"$product_version","buildNumber":$build,"gitCommit":"$commit","helperProtocolVersion":$protocol,"helperSHA256":"$manifest_sha","channel":"$channel"}
EOF
  fi
  info="$app/Contents/Info.plist"
  /usr/bin/plutil -create xml1 "$info" >/dev/null
  if [[ "$identity_format" == "modern" ]]; then
    /usr/bin/plutil -insert CFBundleShortVersionString -string "$client_version" "$info" >/dev/null
    /usr/bin/plutil -insert CovioClientVersion -string "$client_version" "$info" >/dev/null
    /usr/bin/plutil -insert CovioProductVersion -string "$product_version" "$info" >/dev/null
  else
    /usr/bin/plutil -insert CFBundleShortVersionString -string "$product_version" "$info" >/dev/null
  fi
  /usr/bin/plutil -insert CFBundleVersion -string "$build" "$info" >/dev/null
  /usr/bin/plutil -insert CovioReleaseId -string "$release_id" "$info" >/dev/null
  /usr/bin/plutil -insert CovioGitCommit -string "$commit" "$info" >/dev/null
  /usr/bin/plutil -insert CovioHelperProtocolVersion -string "$protocol" "$info" >/dev/null
  /usr/bin/plutil -insert CovioReleaseChannel -string "$channel" "$info" >/dev/null
  /usr/bin/plutil -insert CovioInstallTransactionVersion -string "$transaction_version" "$info" >/dev/null
  if [[ -n "$install_mode" ]]; then
    /usr/bin/plutil -insert CovioHelperInstallMode -string "$install_mode" "$info" >/dev/null
  fi
  /usr/bin/codesign --force --deep --sign - "$app" >/dev/null 2>&1
  /usr/bin/codesign --verify --deep --strict "$app"
}

OLD_COMMIT="1111111111111111111111111111111111111111"
NEW_COMMIT="2222222222222222222222222222222222222222"

setup_case() {
  CASE_ROOT="$TEST_ROOT/$1"
  export COVIO_TX_STATE_ROOT="$CASE_ROOT/state"
  export COVIO_TX_APPLICATIONS_ROOT="$CASE_ROOT/Applications"
  export COVIO_TX_ATOMIC_SWAP="$TEST_ROOT/CovioTransaction"
  export COVIO_TX_HELPER_PATH="$COVIO_TX_STATE_ROOT/bin/CovioHelper"
  export COVIO_TX_LAUNCHD_PATH="$CASE_ROOT/Library/LaunchDaemons/com.wyz.covio.helper.plist"
  export COVIO_TX_UPDATER_ROOT="$COVIO_TX_STATE_ROOT/Updater"
  export COVIO_TX_UPDATER_LAUNCHD_PATH="$CASE_ROOT/Library/LaunchDaemons/com.wyz.covio.updater.plist"
  export COVIO_TX_TEST_MODE=1
  export COVIO_TX_WAIT_ATTEMPTS=2
  mkdir -p "$COVIO_TX_APPLICATIONS_ROOT"
  TX_ENVIRONMENT_SOURCE="$CASE_ROOT/transaction.env"
  mkdir -p "$CASE_ROOT"
}

write_environment() {
  local new_app="$1"
  local update_mode="${2:-pkg}"
  local previous_release_id="${3:-}"
  local helper_sha updater_sha launcher_sha
  helper_sha="$(/usr/bin/plutil -extract helperSHA256 raw -o - \
    "$new_app/Contents/Resources/release-manifest.json")"
  updater_sha="$(/usr/bin/shasum -a 256 "$new_app/Contents/MacOS/CovioUpdater" | awk '{print $1}')"
  launcher_sha="$(/usr/bin/shasum -a 256 "$new_app/Contents/MacOS/CovioUpdaterLauncher" | awk '{print $1}')"
  cat > "$TX_ENVIRONMENT_SOURCE" <<EOF
TRANSACTION_ID='test-transaction'
EXPECTED_RELEASE_ID='$(/usr/bin/plutil -extract CovioReleaseId raw -o - "$new_app/Contents/Info.plist")'
EXPECTED_CLIENT_VERSION='$(/usr/bin/plutil -extract CovioClientVersion raw -o - "$new_app/Contents/Info.plist")'
EXPECTED_PRODUCT_VERSION='$(/usr/bin/plutil -extract CovioProductVersion raw -o - "$new_app/Contents/Info.plist")'
EXPECTED_BUILD_NUMBER='$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$new_app/Contents/Info.plist")'
EXPECTED_COMMIT='$(/usr/bin/plutil -extract CovioGitCommit raw -o - "$new_app/Contents/Info.plist")'
EXPECTED_PROTOCOL_VERSION='$(/usr/bin/plutil -extract CovioHelperProtocolVersion raw -o - "$new_app/Contents/Info.plist")'
EXPECTED_HELPER_SHA256='$helper_sha'
EXPECTED_UPDATER_SHA256='$updater_sha'
EXPECTED_UPDATER_LAUNCHER_SHA256='$launcher_sha'
EXPECTED_CHANNEL='internal'
UPDATE_MODE='$update_mode'
EXPECTED_PREVIOUS_RELEASE_ID='$previous_release_id'
STAGED_APP_PATH='$COVIO_TX_STATE_ROOT/Installer/staged/Covio.app'
EOF
}

# shellcheck source=../installer/transaction.sh
source "$ROOT/installer/transaction.sh"

prepare_case() {
  setup_case "$1"
  OLD_APP="$COVIO_TX_APPLICATIONS_ROOT/Covio.app"
  NEW_APP="$CASE_ROOT/new/Covio.app"
  build_app "$NEW_APP" "$2" "$3" "$4" 10 internal "${5:-1}" "${6:-}" "${7:-1}" \
    1 legacy "${10:-modern}" "${12:-1}"
  build_app "$OLD_APP" 0.6.0 15 "$OLD_COMMIT" 9 internal 1 "" 1 "${8:-1}" "${9-legacy}" legacy
  write_environment "$NEW_APP"
  covio_tx_load_environment "$TX_ENVIRONMENT_SOURCE"
  covio_tx_configure
}

prepare_automatic_case() {
  setup_case "$1"
  OLD_APP="$COVIO_TX_APPLICATIONS_ROOT/Covio.app"
  NEW_APP="$CASE_ROOT/new/Covio.app"
  build_app "$NEW_APP" 0.6.0 16 "$NEW_COMMIT" 10 internal 1 "" 1 legacy modern
  build_app "$OLD_APP" 0.6.0 15 "$OLD_COMMIT" 9 internal 1 "" 1 legacy modern
  write_environment "$NEW_APP"
  covio_tx_load_environment "$TX_ENVIRONMENT_SOURCE"
  covio_tx_configure
}

stage_new_app() {
  mkdir -p "$COVIO_TX_STATE_ROOT/Installer/staged"
  /usr/bin/ditto "$NEW_APP" "$TX_STAGED_APP"
}

seed_legacy_helper() {
  mkdir -p "$(dirname "$TX_HELPER_PATH")" "$(dirname "$TX_LAUNCHD_PATH")"
  printf 'old-helper\n' > "$TX_HELPER_PATH"
  chmod 0755 "$TX_HELPER_PATH"
  printf '<plist><dict><key>Version</key><string>old</string></dict></plist>\n' \
    > "$TX_LAUNCHD_PATH"
}

seed_installed_updater() {
  local app="$1"
  local release_id updater_sha launcher_sha build client_version
  release_id="$(/usr/bin/plutil -extract CovioReleaseId raw -o - "$app/Contents/Info.plist")"
  build="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$app/Contents/Info.plist")"
  client_version="$(client_version_for_build "$build")"
  COVIO_UPDATER_ROOT="$COVIO_TX_UPDATER_ROOT" \
  COVIO_UPDATER_LAUNCHD_PATH="$COVIO_TX_UPDATER_LAUNCHD_PATH" \
  COVIO_UPDATER_RELEASE_ID="$release_id" \
  COVIO_UPDATER_TEST_MODE=1 \
  COVIO_UPDATER_SKIP_LAUNCHD=1 \
    "$app/Contents/MacOS/Covio" --install-updater-as-root >/dev/null
  updater_sha="$(/usr/bin/shasum -a 256 "$COVIO_TX_UPDATER_ROOT/versions/$release_id/CovioUpdater" | awk '{print $1}')"
  launcher_sha="$(/usr/bin/shasum -a 256 "$COVIO_TX_UPDATER_ROOT/bin/CovioUpdaterLauncher" | awk '{print $1}')"
  cat > "$TX_RECORD_PATH" <<EOF
{"schemaVersion":2,"releaseId":"$release_id","clientVersion":"$client_version","productVersion":"0.6.0","buildNumber":$build,"gitCommit":"$OLD_COMMIT","helperProtocolVersion":9,"helperSHA256":"$(/usr/bin/plutil -extract helperSHA256 raw -o - "$app/Contents/Resources/release-manifest.json")","updaterReleaseId":"$release_id","updaterProtocolVersion":1,"updaterSHA256":"$updater_sha","updaterLauncherSHA256":"$launcher_sha","channel":"internal"}
EOF
}

seed_legacy_release_record() {
  local helper_sha
  helper_sha="$(/usr/bin/plutil -extract helperSHA256 raw -o - \
    "$OLD_APP/Contents/Resources/release-manifest.json")"
  mkdir -p "$COVIO_TX_STATE_ROOT"
  cat > "$TX_RECORD_PATH" <<EOF
{"schemaVersion":1,"releaseId":"0.6.0+15+$OLD_COMMIT","productVersion":"0.6.0","buildNumber":15,"gitCommit":"$OLD_COMMIT","helperProtocolVersion":9,"helperSHA256":"$helper_sha","channel":"internal"}
EOF
}

printf 'case: app quit probe targets only the installed app path\n'
FAKE_PGREP="$TEST_ROOT/fake-pgrep"
FAKE_PGREP_LOG="$TEST_ROOT/fake-pgrep.log"
cat > "$FAKE_PGREP" <<'PGGREP'
#!/bin/bash
printf '%s\n' "$*" > "$FAKE_PGREP_LOG"
exit 1
PGGREP
chmod 0755 "$FAKE_PGREP"
OLD_PGREP="$COVIO_TX_PGREP"
OLD_TEST_MODE="${TX_TEST_MODE:-1}"
TX_APP_PATH="$TEST_ROOT/Applications/Covio.app"
COVIO_TX_PGREP="$FAKE_PGREP"
TX_TEST_MODE=0
export FAKE_PGREP_LOG
covio_tx_quit_running_app
assert_eq "$(cat "$FAKE_PGREP_LOG")" "-f -x $TX_APP_PATH/Contents/MacOS/Covio" "app quit probe did not use the installed path"
COVIO_TX_PGREP="$OLD_PGREP"
TX_TEST_MODE="$OLD_TEST_MODE"

printf 'case: successful upgrade commits app, helper and record\n'
prepare_case success 0.6.0 16 "$NEW_COMMIT"
seed_legacy_helper
seed_legacy_release_record
covio_tx_prepare
stage_new_app
covio_tx_commit
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 16 "app was not upgraded"
assert_json "$TX_RECORD_PATH" schemaVersion 2
assert_json "$TX_RECORD_PATH" clientVersion 0.0.1.6
assert_json "$TX_RECORD_PATH" productVersion 0.6.0
assert_json "$TX_RECORD_PATH" releaseId "0.0.1.6-g$NEW_COMMIT"
assert_app_helper_record_match "$TX_APP_PATH" "0.0.1.6-g$NEW_COMMIT"
assert_updater_record_match "$TX_APP_PATH" "0.0.1.6-g$NEW_COMMIT"
assert_json "$TX_REPORT_PATH" result installed
assert_json "$TX_REPORT_PATH" source pkg
assert_json "$TX_REPORT_PATH" previousReleaseId "0.6.0+15+$OLD_COMMIT"
assert_eq "$(cat "$(cat "$TX_LAST_POINTER")/state")" committed "transaction was not committed"
[[ -x "$TX_HELPER_PATH" && -f "$TX_LAUNCHD_PATH" ]] || fail "fixed helper paths were not installed"
cmp -s "$TX_HELPER_PATH" "$TX_APP_PATH/Contents/MacOS/CovioHelper" || \
  fail "installed helper differs from the committed app"
assert_eq "$(cat "$TX_BACKUP_HELPER")" old-helper "previous helper was not backed up"
[[ -f "$TX_BACKUP_LAUNCHD" ]] || fail "previous LaunchDaemon was not backed up"

printf 'case: failed first handshake rolls back to the previous pair\n'
prepare_case handler-failure 0.6.0 17 "$NEW_COMMIT" 0
seed_legacy_helper
covio_tx_prepare
stage_new_app
if covio_tx_commit; then
  fail "handler failure unexpectedly committed"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 15 "app did not roll back"
assert_json "$TX_RECORD_PATH" releaseId "0.6.0+15+$OLD_COMMIT"
assert_app_helper_record_match "$TX_APP_PATH" "0.6.0+15+$OLD_COMMIT"
[[ ! -e "$COVIO_TX_UPDATER_ROOT" && ! -e "$COVIO_TX_UPDATER_LAUNCHD_PATH" ]] || \
  fail "rollback left updater files"
assert_json "$TX_REPORT_PATH" result rolled-back
assert_eq "$(/usr/bin/plutil -extract source raw -o - "$TX_REPORT_PATH")" pkg "rollback report source"
[[ -n "$(/usr/bin/plutil -extract rollbackReason raw -o - "$TX_REPORT_PATH")" ]] || \
  fail "rollback reason is empty"
[[ -x "$TX_HELPER_PATH" && -f "$TX_LAUNCHD_PATH" ]] || fail "rollback removed the fixed helper paths"
cmp -s "$TX_HELPER_PATH" "$TX_APP_PATH/Contents/MacOS/CovioHelper" || \
  fail "rollback helper differs from the restored app"
case "$(cat "$(cat "$TX_LAST_POINTER")/state")" in
  rolled-back|rollback-failed) ;;
  *) fail "rollback state was not recorded" ;;
esac

printf 'case: privileged state restore failure blocks the upgrade\n'
prepare_case restore-failure 0.6.0 18 "$NEW_COMMIT" 1 "" 1 0
if covio_tx_prepare; then
  fail "restore failure unexpectedly prepared the transaction"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 15 "app changed after restore failure"
assert_json "$TX_REPORT_PATH" result failed

printf 'case: downgrade is rejected before the bundle exchange\n'
prepare_case downgrade 0.6.0 14 "$NEW_COMMIT"
covio_tx_prepare
stage_new_app
if covio_tx_commit; then
  fail "downgrade unexpectedly committed"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 15 "downgrade changed the app"
assert_json "$TX_REPORT_PATH" result failed

printf 'case: helper digest mismatch is rejected\n'
prepare_case digest-mismatch 0.6.0 19 "$NEW_COMMIT" 1 "$(printf 'd%.0s' {1..64})"
covio_tx_prepare
stage_new_app
if covio_tx_commit; then
  fail "digest mismatch unexpectedly committed"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 15 "digest mismatch changed the app"
assert_json "$TX_REPORT_PATH" result failed

printf 'case: invalid signature is rejected\n'
prepare_case bad-signature 0.6.0 20 "$NEW_COMMIT"
covio_tx_prepare
stage_new_app
printf 'changed after signing\n' > "$TX_STAGED_APP/Contents/Resources/version.txt"
if covio_tx_commit; then
  fail "invalid signature unexpectedly committed"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 15 "invalid signature changed the app"
assert_json "$TX_REPORT_PATH" result failed

printf 'case: updater installation failure rolls back the transaction\n'
prepare_case updater-failure 0.6.0 26 "$NEW_COMMIT" 1 "" 1 "" legacy modern legacy 0
seed_legacy_helper
covio_tx_prepare
stage_new_app
if covio_tx_commit; then
  fail "updater failure unexpectedly committed"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 15 "updater failure changed the app"
[[ ! -e "$COVIO_TX_UPDATER_ROOT" && ! -e "$COVIO_TX_UPDATER_LAUNCHD_PATH" ]] || \
  fail "updater failure left updater files"
assert_json "$TX_REPORT_PATH" result rolled-back

printf 'case: automatic update replaces the app helper and engine but keeps the launcher\n'
prepare_automatic_case automatic
seed_legacy_helper
seed_installed_updater "$OLD_APP"
OLD_RELEASE_ID="$(tr -d '[:space:]' < "$COVIO_TX_UPDATER_ROOT/current")"
OLD_LAUNCHER_SHA="$(/usr/bin/shasum -a 256 "$COVIO_TX_UPDATER_ROOT/bin/CovioUpdaterLauncher" | awk '{print $1}')"
OLD_PLIST_SHA="$(/usr/bin/shasum -a 256 "$COVIO_TX_UPDATER_LAUNCHD_PATH" | awk '{print $1}')"
write_environment "$NEW_APP" automatic "$OLD_RELEASE_ID"
covio_tx_load_environment "$TX_ENVIRONMENT_SOURCE"
covio_tx_configure
printf '1\n' > "$NEW_APP/Contents/Resources/install-updater-engine-as-root.result"
/usr/bin/codesign --force --deep --sign - "$NEW_APP" >/dev/null 2>&1
/usr/bin/codesign --verify --deep --strict "$NEW_APP" >/dev/null 2>&1
covio_tx_prepare
stage_new_app
covio_tx_commit
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 16 "automatic update did not install the app"
assert_eq "$(tr -d '[:space:]' < "$COVIO_TX_UPDATER_ROOT/current")" "0.0.1.6-g$NEW_COMMIT" "automatic update current pointer differs"
assert_eq "$(tr -d '[:space:]' < "$COVIO_TX_UPDATER_ROOT/previous")" "$OLD_RELEASE_ID" "automatic update previous pointer differs"
assert_eq "$(/usr/bin/shasum -a 256 "$COVIO_TX_UPDATER_ROOT/bin/CovioUpdaterLauncher" | awk '{print $1}')" "$OLD_LAUNCHER_SHA" "automatic update replaced the launcher"
assert_eq "$(/usr/bin/shasum -a 256 "$COVIO_TX_UPDATER_LAUNCHD_PATH" | awk '{print $1}')" "$OLD_PLIST_SHA" "automatic update replaced the LaunchDaemon"
assert_json "$TX_RECORD_PATH" updaterLauncherSHA256 "$OLD_LAUNCHER_SHA"
assert_json "$TX_RECORD_PATH" releaseId "0.0.1.6-g$NEW_COMMIT"

printf 'case: interruption after bundle exchange is recoverable\n'
prepare_case interruption 0.6.0 21 "$NEW_COMMIT"
covio_tx_prepare
stage_new_app
if ! covio_tx_verify_new_app "$TX_STAGED_APP"; then
  fail "staged app verification failed before interruption probe"
fi
"$COVIO_TX_ATOMIC_SWAP" "$TX_APP_PATH" "$TX_STAGED_APP"
covio_tx_write_state app-installed
covio_tx_recover
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 15 "interrupted transaction did not recover"
assert_json "$TX_RECORD_PATH" releaseId "0.6.0+15+$OLD_COMMIT"

printf 'case: recovery config works before loading a transaction ID\n'
prepare_case recovery-entrypoint 0.6.0 22 "$NEW_COMMIT"
covio_tx_prepare
stage_new_app
if ! covio_tx_verify_new_app "$TX_STAGED_APP"; then
  fail "staged app verification failed before recovery-entrypoint probe"
fi
"$COVIO_TX_ATOMIC_SWAP" "$TX_APP_PATH" "$TX_STAGED_APP"
covio_tx_write_state app-installed
unset TRANSACTION_ID
covio_tx_configure "$COVIO_TX_STATE_ROOT" "$COVIO_TX_APPLICATIONS_ROOT"
covio_tx_recover
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 15 "recovery entrypoint did not restore the app"
assert_json "$TX_RECORD_PATH" releaseId "0.6.0+15+$OLD_COMMIT"

printf 'case: an unstarted transaction is archived before retry\n'
prepare_case unstarted-recovery 0.6.0 23 "$NEW_COMMIT"
STALE_ROOT="$TX_INSTALLER_ROOT/transactions/unstarted"
mkdir -p "$STALE_ROOT"
cp "$TX_ENVIRONMENT_SOURCE" "$STALE_ROOT/transaction.env"
printf '%s\n' "$STALE_ROOT" > "$TX_CURRENT_POINTER"
covio_tx_recover
[[ ! -e "$TX_CURRENT_POINTER" ]] || fail "recovery did not clear the unstarted transaction pointer"
find "$TX_INSTALLER_ROOT/transactions" -maxdepth 1 -name 'unstarted.history.*' -print -quit | grep -q . || \
  fail "recovery did not archive the unstarted transaction"
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 15 "unstarted recovery changed the installed app"
covio_tx_prepare
assert_eq "$(covio_tx_read_state)" prepared "retry did not prepare a new transaction"

printf 'case: an SMAppService rollback removes Legacy helper metadata\n'
prepare_case sm-rollback 0.6.0 17 "$NEW_COMMIT" 0 "" 1 1 ""
covio_tx_prepare
stage_new_app
if covio_tx_commit; then
  fail "SMAppService rollback unexpectedly committed"
fi
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 15 "app did not roll back to SMAppService"
assert_json "$TX_RECORD_PATH" releaseId "0.6.0+15+$OLD_COMMIT"
[[ ! -e "$TX_STATE_ROOT/client-requirement" && ! -e "$TX_STATE_ROOT/version" && \
   ! -e "$TX_STATE_ROOT/allowed_uid" && ! -e "$TX_STATE_ROOT/Covio.app" ]] || \
  fail "SMAppService rollback left Legacy helper metadata"

printf 'case: an SMAppService installation migrates to the Legacy helper\n'
prepare_case sm-migration 0.6.0 24 "$NEW_COMMIT" 1 "" 1 1 ""
covio_tx_prepare
stage_new_app
covio_tx_commit
assert_app_helper_record_match "$TX_APP_PATH" "0.0.2.4-g$NEW_COMMIT"
assert_updater_record_match "$TX_APP_PATH" "0.0.2.4-g$NEW_COMMIT"
[[ -x "$TX_HELPER_PATH" && -f "$TX_LAUNCHD_PATH" ]] || \
  fail "SMAppService migration did not create the Legacy helper"

printf 'case: clean install commits without a usable TMPDIR\n'
setup_case clean-install
NEW_APP="$CASE_ROOT/new/Covio.app"
build_app "$NEW_APP" 0.6.0 25 "$NEW_COMMIT" 10 internal 1 "" 1
write_environment "$NEW_APP"
covio_tx_load_environment "$TX_ENVIRONMENT_SOURCE"
covio_tx_configure
covio_tx_prepare
stage_new_app
TMPDIR="$CASE_ROOT/unavailable-tmp" covio_tx_commit
assert_eq "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$TX_APP_PATH/Contents/Info.plist")" 25 "clean install did not commit"
assert_json "$TX_RECORD_PATH" releaseId "0.0.2.5-g$NEW_COMMIT"
assert_app_helper_record_match "$TX_APP_PATH" "0.0.2.5-g$NEW_COMMIT"
assert_updater_record_match "$TX_APP_PATH" "0.0.2.5-g$NEW_COMMIT"
[[ -x "$TX_HELPER_PATH" && -f "$TX_LAUNCHD_PATH" ]] || fail "clean install did not create fixed helper paths"
assert_json "$TX_REPORT_PATH" result installed

printf 'transactional installer tests passed\n'

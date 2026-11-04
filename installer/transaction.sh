#!/bin/bash

# Covio 本机升级事务。这个文件只提供函数，由 preinstall、postinstall 和恢复命令加载。
#
# 事务边界是整个 Covio.app。helper 是 app bundle 的嵌套可执行文件，
# 因此原子交换 bundle 就是同时提交 app 与 helper，不会留下混合版本。

COVIO_TX_APP_NAME="Covio.app"
COVIO_TX_CODESIGN="${COVIO_TX_CODESIGN:-/usr/bin/codesign}"
COVIO_TX_DITTO="${COVIO_TX_DITTO:-/usr/bin/ditto}"
COVIO_TX_FIND="${COVIO_TX_FIND:-/usr/bin/find}"
COVIO_TX_INSTALL="${COVIO_TX_INSTALL:-/usr/bin/install}"
COVIO_TX_LAUNCHCTL="${COVIO_TX_LAUNCHCTL:-/bin/launchctl}"
COVIO_TX_LIPO="${COVIO_TX_LIPO:-/usr/bin/lipo}"
COVIO_TX_PGREP="${COVIO_TX_PGREP:-/usr/bin/pgrep}"
COVIO_TX_PLUTIL="${COVIO_TX_PLUTIL:-/usr/bin/plutil}"
COVIO_TX_SHASUM="${COVIO_TX_SHASUM:-/usr/bin/shasum}"
COVIO_TX_SPCTL="${COVIO_TX_SPCTL:-/usr/sbin/spctl}"
COVIO_TX_STAPLER="${COVIO_TX_STAPLER:-/usr/bin/xcrun}"
COVIO_TX_UNAME="${COVIO_TX_UNAME:-/usr/bin/uname}"
COVIO_TX_ID="${COVIO_TX_ID:-/usr/bin/id}"
COVIO_TX_UPDATER_PROTOCOL_VERSION="${COVIO_TX_UPDATER_PROTOCOL_VERSION:-1}"

covio_tx_load_environment() {
    local environment_file="$1"
    if [[ ! -f "$environment_file" ]]; then
        printf 'Missing transaction environment: %s\n' "$environment_file" >&2
        return 1
    fi
    # shellcheck disable=SC1090
    source "$environment_file"
    TX_UPDATE_MODE="${UPDATE_MODE:-pkg}"
    TX_REPORT_SOURCE="${COVIO_TX_REPORT_SOURCE:-pkg}"
    local key
    for key in \
        TRANSACTION_ID EXPECTED_RELEASE_ID EXPECTED_CLIENT_VERSION EXPECTED_PRODUCT_VERSION \
        EXPECTED_BUILD_NUMBER EXPECTED_COMMIT EXPECTED_PROTOCOL_VERSION \
        EXPECTED_HELPER_SHA256 EXPECTED_UPDATER_SHA256 \
        EXPECTED_UPDATER_LAUNCHER_SHA256 EXPECTED_CHANNEL
    do
        if [[ -z "${!key:-}" ]]; then
            printf 'Transaction environment is missing %s\n' "$key" >&2
            return 1
        fi
    done
    if [[ "$TX_UPDATE_MODE" != "pkg" && "$TX_UPDATE_MODE" != "automatic" ]]; then
        printf 'Invalid update mode: %s\n' "$TX_UPDATE_MODE" >&2
        return 1
    fi
}

covio_tx_configure() {
    local state_root="${1:-${COVIO_TX_STATE_ROOT:-/Library/Application Support/Covio}}"
    local applications_root="${2:-${COVIO_TX_APPLICATIONS_ROOT:-/Applications}}"
    local staged_app="${3:-}"
    TX_STATE_ROOT="$state_root"
    TX_APPLICATIONS_ROOT="$applications_root"
    TX_APP_PATH="$applications_root/$COVIO_TX_APP_NAME"
    TX_INSTALLER_ROOT="$state_root/Installer"
    if [[ -z "$staged_app" ]]; then
        staged_app="${STAGED_APP_PATH:-$TX_INSTALLER_ROOT/staged/$COVIO_TX_APP_NAME}"
    fi
    TX_STAGED_APP="$staged_app"
    # recover.sh configures paths before it loads the transaction environment.
    TX_TRANSACTION_ROOT="$TX_INSTALLER_ROOT/transactions/${TRANSACTION_ID:-recovery}"
    TX_BACKUP_APP="$TX_TRANSACTION_ROOT/previous/$COVIO_TX_APP_NAME"
    TX_CANDIDATE_APP="$TX_TRANSACTION_ROOT/candidate/$COVIO_TX_APP_NAME"
    TX_HELPER_PATH="${COVIO_TX_HELPER_PATH:-$state_root/bin/CovioHelper}"
    TX_LAUNCHD_PATH="${COVIO_TX_LAUNCHD_PATH:-/Library/LaunchDaemons/com.wyz.covio.helper.plist}"
    TX_UPDATER_ROOT="${COVIO_TX_UPDATER_ROOT:-$state_root/Updater}"
    TX_UPDATER_LAUNCHD_PATH="${COVIO_TX_UPDATER_LAUNCHD_PATH:-/Library/LaunchDaemons/com.wyz.covio.updater.plist}"
    TX_BACKUP_HELPER="$TX_TRANSACTION_ROOT/previous/CovioHelper"
    TX_BACKUP_LAUNCHD="$TX_TRANSACTION_ROOT/previous/com.wyz.covio.helper.plist"
    TX_BACKUP_HELPER_METADATA="$TX_TRANSACTION_ROOT/previous/helper-metadata"
    TX_BACKUP_UPDATER="$TX_TRANSACTION_ROOT/previous/Updater"
    TX_BACKUP_UPDATER_LAUNCHD="$TX_TRANSACTION_ROOT/previous/com.wyz.covio.updater.plist"
    TX_BACKUP_UPDATER_STATE="$TX_TRANSACTION_ROOT/previous/updater-present"
    TX_PREVIOUS_RECORD="$TX_TRANSACTION_ROOT/previous/installed-release.json"
    TX_STATE_FILE="$TX_TRANSACTION_ROOT/state"
    TX_LOG_FILE="$TX_TRANSACTION_ROOT/transaction.log"
    TX_ENVIRONMENT_FILE="$TX_TRANSACTION_ROOT/transaction.env"
    TX_CURRENT_POINTER="$TX_INSTALLER_ROOT/current-transaction"
    TX_LAST_POINTER="$TX_INSTALLER_ROOT/last-transaction"
    TX_RECORD_PATH="$state_root/installed-release.json"
    TX_REPORT_PATH="$state_root/install-report.json"
    TX_ATOMIC_SWAP="${COVIO_TX_ATOMIC_SWAP:-$TX_INSTALLER_ROOT/bin/CovioTransaction}"
    TX_TEST_MODE="${COVIO_TX_TEST_MODE:-0}"
}

covio_tx_require_root() {
    if [[ "$TX_TEST_MODE" == "1" ]]; then
        return 0
    fi
    if [[ "$("$COVIO_TX_ID" -u)" != "0" ]]; then
        printf 'Covio install transactions require root.\n' >&2
        return 1
    fi
}

covio_tx_log() {
    mkdir -p "$TX_TRANSACTION_ROOT"
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$TX_LOG_FILE" >&2
}

covio_tx_remove_tree() {
    local path="$1"
    if [[ -z "$path" || "$path" == "/" || ! -e "$path" ]]; then
        return 0
    fi
    "$COVIO_TX_FIND" "$path" -depth -delete
}

covio_tx_write_state() {
    local state="$1"
    mkdir -p "$TX_TRANSACTION_ROOT"
    printf '%s\n' "$state" > "$TX_STATE_FILE.tmp"
    sync
    mv "$TX_STATE_FILE.tmp" "$TX_STATE_FILE"
}

covio_tx_read_state() {
    if [[ -f "$TX_STATE_FILE" ]]; then
        cat "$TX_STATE_FILE"
    else
        printf 'missing\n'
    fi
}

covio_tx_point_to_transaction() {
    printf '%s\n' "$TX_TRANSACTION_ROOT" > "$TX_CURRENT_POINTER.tmp"
    mv "$TX_CURRENT_POINTER.tmp" "$TX_CURRENT_POINTER"
}

covio_tx_mark_last_transaction() {
    printf '%s\n' "$TX_TRANSACTION_ROOT" > "$TX_LAST_POINTER.tmp"
    mv "$TX_LAST_POINTER.tmp" "$TX_LAST_POINTER"
}

covio_tx_clear_current_transaction() {
    if [[ -e "$TX_CURRENT_POINTER" ]]; then
        unlink "$TX_CURRENT_POINTER"
    fi
}

covio_tx_archive_transaction_root() {
    local root="$1"
    local history_root="${root}.history.$(date +%s).$RANDOM"
    mv "$root" "$history_root"
    printf '%s\n' "$history_root" > "$TX_LAST_POINTER.tmp"
    mv "$TX_LAST_POINTER.tmp" "$TX_LAST_POINTER"
    printf 'Archived transaction %s as %s\n' "$root" "$history_root" >&2
}

covio_tx_plist_raw() {
    local file="$1"
    local key="$2"
    "$COVIO_TX_PLUTIL" -extract "$key" raw -o - "$file"
}

covio_tx_sha256() {
    "$COVIO_TX_SHASUM" -a 256 "$1" | awk '{print $1}'
}

covio_tx_identity_value() {
    local prefix="$1"
    local field="$2"
    local name="${prefix}_${field}"
    printf '%s' "${!name:-}"
}

covio_tx_plist_has_key() {
    local file="$1"
    local key="$2"
    "$COVIO_TX_PLUTIL" -extract "$key" raw -o - "$file" >/dev/null 2>&1
}

covio_tx_client_version_for_build() {
    local build="$1"
    local digits
    [[ "$build" =~ ^[1-9][0-9]{0,3}$ ]] || return 1
    printf -v digits '%04d' "$build"
    printf '%s.%s.%s.%s\n' \
        "${digits:0:1}" "${digits:1:1}" "${digits:2:1}" "${digits:3:1}"
}

covio_tx_semver_client_version() {
    local product_version="$1"
    local build="$2"
    local channel="$3"
    case "$channel" in
        internal) printf '%s-internal.%s\n' "$product_version" "$build" ;;
        public) printf '%s\n' "$product_version" ;;
        *) return 1 ;;
    esac
}

covio_tx_load_info_identity() {
    local app="$1"
    local prefix="$2"
    local info="$app/Contents/Info.plist"
    local helper="$app/Contents/MacOS/CovioHelper"
    local build
    if [[ ! -f "$info" || ! -x "$helper" ]]; then
        return 1
    fi
    build="$(covio_tx_plist_raw "$info" CFBundleVersion)"
    printf -v "${prefix}_BUILD_NUMBER" '%s' "$build"
    if covio_tx_plist_has_key "$info" CovioClientVersion; then
        printf -v "${prefix}_IDENTITY_FORMAT" '%s' modern
        printf -v "${prefix}_CLIENT_VERSION" '%s' "$(covio_tx_plist_raw "$info" CovioClientVersion)"
        printf -v "${prefix}_PRODUCT_VERSION" '%s' "$(covio_tx_plist_raw "$info" CovioProductVersion)"
    else
        printf -v "${prefix}_IDENTITY_FORMAT" '%s' legacy
        printf -v "${prefix}_CLIENT_VERSION" '%s' "$(covio_tx_client_version_for_build "$build")"
        printf -v "${prefix}_PRODUCT_VERSION" '%s' "$(covio_tx_plist_raw "$info" CFBundleShortVersionString)"
    fi
    printf -v "${prefix}_GIT_COMMIT" '%s' "$(covio_tx_plist_raw "$info" CovioGitCommit)"
    printf -v "${prefix}_RELEASE_ID" '%s' "$(covio_tx_plist_raw "$info" CovioReleaseId)"
    printf -v "${prefix}_PROTOCOL_VERSION" '%s' "$(covio_tx_plist_raw "$info" CovioHelperProtocolVersion)"
    printf -v "${prefix}_CHANNEL" '%s' "$(covio_tx_plist_raw "$info" CovioReleaseChannel)"
    printf -v "${prefix}_HELPER_SHA256" '%s' "$(covio_tx_sha256 "$helper")"
    if [[ -x "$app/Contents/MacOS/CovioUpdater" && -x "$app/Contents/MacOS/CovioUpdaterLauncher" ]]; then
        printf -v "${prefix}_UPDATER_SHA256" '%s' "$(covio_tx_sha256 "$app/Contents/MacOS/CovioUpdater")"
        printf -v "${prefix}_UPDATER_LAUNCHER_SHA256" '%s' "$(covio_tx_sha256 "$app/Contents/MacOS/CovioUpdaterLauncher")"
    else
        printf -v "${prefix}_UPDATER_SHA256" '%s' ""
        printf -v "${prefix}_UPDATER_LAUNCHER_SHA256" '%s' ""
    fi
    printf -v "${prefix}_TRANSACTION_VERSION" '%s' \
        "$("$COVIO_TX_PLUTIL" -extract CovioInstallTransactionVersion raw -o - "$info" 2>/dev/null || true)"
    printf -v "${prefix}_INSTALL_MODE" '%s' \
        "$("$COVIO_TX_PLUTIL" -extract CovioHelperInstallMode raw -o - "$info" 2>/dev/null || true)"
}

covio_tx_load_manifest_identity() {
    local file="$1"
    local prefix="$2"
    local build
    [[ -f "$file" ]] || return 1
    build="$(covio_tx_plist_raw "$file" buildNumber)"
    printf -v "${prefix}_BUILD_NUMBER" '%s' "$build"
    if covio_tx_plist_has_key "$file" clientVersion; then
        printf -v "${prefix}_IDENTITY_FORMAT" '%s' modern
        printf -v "${prefix}_CLIENT_VERSION" '%s' "$(covio_tx_plist_raw "$file" clientVersion)"
    else
        printf -v "${prefix}_IDENTITY_FORMAT" '%s' legacy
        printf -v "${prefix}_CLIENT_VERSION" '%s' "$(covio_tx_client_version_for_build "$build")"
    fi
    printf -v "${prefix}_PRODUCT_VERSION" '%s' "$(covio_tx_plist_raw "$file" productVersion)"
    printf -v "${prefix}_GIT_COMMIT" '%s' "$(covio_tx_plist_raw "$file" gitCommit)"
    printf -v "${prefix}_RELEASE_ID" '%s' "$(covio_tx_plist_raw "$file" releaseId)"
    printf -v "${prefix}_PROTOCOL_VERSION" '%s' "$(covio_tx_plist_raw "$file" helperProtocolVersion)"
    printf -v "${prefix}_CHANNEL" '%s' "$(covio_tx_plist_raw "$file" channel)"
    printf -v "${prefix}_HELPER_SHA256" '%s' "$(covio_tx_plist_raw "$file" helperSHA256)"
}

covio_tx_load_helper_identity() {
    local app="$1"
    local prefix="$2"
    local helper="$app/Contents/MacOS/CovioHelper"
    local output_file="$TX_TRANSACTION_ROOT/helper-identity-$prefix.json"
    local error_file="$TX_TRANSACTION_ROOT/helper-identity-$prefix.stderr"
    local build
    mkdir -p "$TX_TRANSACTION_ROOT"
    if "$helper" --print-release-identity >"$output_file" 2>"$error_file"; then
        :
    else
        local probe_status=$?
        local error_text
        error_text="$(tail -c 4096 "$error_file" 2>/dev/null || true)"
        covio_tx_log "Helper identity probe failed for $prefix: exit=$probe_status stderr=${error_text:-<empty>}"
        return 1
    fi
    if ! "$COVIO_TX_PLUTIL" -extract releaseId raw -o - "$output_file" >/dev/null 2>&1; then
        local output_text
        output_text="$(head -c 4096 "$output_file" 2>/dev/null || true)"
        covio_tx_log "Helper identity output is invalid for $prefix: ${output_text:-<empty>}"
        return 1
    fi
    build="$(covio_tx_plist_raw "$output_file" buildNumber)"
    printf -v "${prefix}_BUILD_NUMBER" '%s' "$build"
    if covio_tx_plist_has_key "$output_file" clientVersion; then
        printf -v "${prefix}_IDENTITY_FORMAT" '%s' modern
        printf -v "${prefix}_CLIENT_VERSION" '%s' "$(covio_tx_plist_raw "$output_file" clientVersion)"
    else
        printf -v "${prefix}_IDENTITY_FORMAT" '%s' legacy
        printf -v "${prefix}_CLIENT_VERSION" '%s' "$(covio_tx_client_version_for_build "$build")"
    fi
    printf -v "${prefix}_PRODUCT_VERSION" '%s' "$(covio_tx_plist_raw "$output_file" productVersion)"
    printf -v "${prefix}_GIT_COMMIT" '%s' "$(covio_tx_plist_raw "$output_file" gitCommit)"
    printf -v "${prefix}_RELEASE_ID" '%s' "$(covio_tx_plist_raw "$output_file" releaseId)"
    printf -v "${prefix}_PROTOCOL_VERSION" '%s' "$(covio_tx_plist_raw "$output_file" protocolVersion)"
    printf -v "${prefix}_CHANNEL" '%s' "$(covio_tx_plist_raw "$output_file" channel)"
    printf -v "${prefix}_HELPER_SHA256" '%s' "$(covio_tx_plist_raw "$output_file" helperSHA256)"
}

covio_tx_validate_prefix() {
    local prefix="$1"
    local format client_version expected_client_version version build commit release_id protocol channel helper_sha
    format="$(covio_tx_identity_value "$prefix" IDENTITY_FORMAT)"
    client_version="$(covio_tx_identity_value "$prefix" CLIENT_VERSION)"
    version="$(covio_tx_identity_value "$prefix" PRODUCT_VERSION)"
    build="$(covio_tx_identity_value "$prefix" BUILD_NUMBER)"
    commit="$(covio_tx_identity_value "$prefix" GIT_COMMIT)"
    release_id="$(covio_tx_identity_value "$prefix" RELEASE_ID)"
    protocol="$(covio_tx_identity_value "$prefix" PROTOCOL_VERSION)"
    channel="$(covio_tx_identity_value "$prefix" CHANNEL)"
    helper_sha="$(covio_tx_identity_value "$prefix" HELPER_SHA256)"
    [[ "$format" == "modern" || "$format" == "legacy" ]] || return 1
    [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || return 1
    [[ "$build" =~ ^[1-9][0-9]{0,3}$ ]] || return 1
    [[ "$channel" == "internal" || "$channel" == "public" ]] || return 1
    if [[ "$client_version" =~ ^[0-9]\.[0-9]\.[0-9]\.[0-9]$ ]]; then
        expected_client_version="$(covio_tx_client_version_for_build "$build")" || return 1
    else
        expected_client_version="$(covio_tx_semver_client_version "$version" "$build" "$channel")" || return 1
    fi
    [[ "$client_version" == "$expected_client_version" ]] || return 1
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || return 1
    [[ "$protocol" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ "$helper_sha" =~ ^[0-9a-f]{64}$ ]] || return 1
    if [[ -n "$(covio_tx_identity_value "$prefix" UPDATER_SHA256)" ]]; then
        [[ "$(covio_tx_identity_value "$prefix" UPDATER_SHA256)" =~ ^[0-9a-f]{64}$ ]] || return 1
        [[ "$(covio_tx_identity_value "$prefix" UPDATER_LAUNCHER_SHA256)" =~ ^[0-9a-f]{64}$ ]] || return 1
    fi
    if [[ "$format" == "modern" ]]; then
        [[ "$release_id" == "$client_version-g$commit" ]]
    else
        [[ "$release_id" == "$version+$build+$commit" ]]
    fi
}

covio_tx_validate_modern_prefix() {
    local prefix="$1"
    [[ "$(covio_tx_identity_value "$prefix" IDENTITY_FORMAT)" == "modern" ]] &&
        covio_tx_validate_prefix "$prefix"
}

covio_tx_prefixes_equal() {
    local left="$1"
    local right="$2"
    local field value
    for field in IDENTITY_FORMAT CLIENT_VERSION PRODUCT_VERSION BUILD_NUMBER GIT_COMMIT RELEASE_ID PROTOCOL_VERSION CHANNEL HELPER_SHA256
    do
        value="$(covio_tx_identity_value "$left" "$field")"
        if [[ "$value" != "$(covio_tx_identity_value "$right" "$field")" ]]; then
            return 1
        fi
    done
}

covio_tx_validate_expected_identity() {
    if [[ ! "$EXPECTED_PRODUCT_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ||
          ! "$EXPECTED_BUILD_NUMBER" =~ ^[1-9][0-9]{0,3}$ ||
          ! "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ||
          ! "$EXPECTED_PROTOCOL_VERSION" =~ ^[1-9][0-9]*$ ||
          ! "$EXPECTED_HELPER_SHA256" =~ ^[0-9a-f]{64}$ ||
          ! "$EXPECTED_UPDATER_SHA256" =~ ^[0-9a-f]{64}$ ||
          ! "$EXPECTED_UPDATER_LAUNCHER_SHA256" =~ ^[0-9a-f]{64}$ ||
          ( "$EXPECTED_CHANNEL" != "internal" && "$EXPECTED_CHANNEL" != "public" ) ]]; then
        covio_tx_log "Signed installer identity has invalid fields"
        return 1
    fi
    local expected_client_version
    expected_client_version="$(covio_tx_semver_client_version \
        "$EXPECTED_PRODUCT_VERSION" "$EXPECTED_BUILD_NUMBER" "$EXPECTED_CHANNEL")" || return 1
    if [[ "$EXPECTED_CLIENT_VERSION" != "$expected_client_version" ]]; then
        covio_tx_log "Expected clientVersion does not match product version, channel, or build"
        return 1
    fi
    if [[ "$EXPECTED_RELEASE_ID" != \
          "$EXPECTED_CLIENT_VERSION-g$EXPECTED_COMMIT" ]]; then
        covio_tx_log "Expected releaseId does not match its client version and commit"
        return 1
    fi
    if [[ -n "${NEW_HELPER_SHA256:-}" &&
          "$EXPECTED_HELPER_SHA256" != "$(covio_tx_identity_value NEW HELPER_SHA256)" ]]; then
        covio_tx_log "Expected helper digest differs from the staged app"
        return 1
    fi
}

covio_tx_install_record_file() {
    local source="$1"
    local destination="$2"
    if [[ "$TX_TEST_MODE" == "1" ]]; then
        cp "$source" "$destination"
        chmod 0644 "$destination"
    else
        "$COVIO_TX_INSTALL" -o root -g wheel -m 0644 "$source" "$destination"
    fi
}

covio_tx_verify_signatures() {
    local app="$1"
    local channel="$2"
    local helper="$app/Contents/MacOS/CovioHelper"
    if ! "$COVIO_TX_CODESIGN" --verify --deep --strict "$app" >/dev/null 2>&1; then
        covio_tx_log "App signature is invalid"
        return 1
    fi
    if ! "$COVIO_TX_CODESIGN" --verify --strict "$helper" >/dev/null 2>&1; then
        covio_tx_log "Helper signature is invalid"
        return 1
    fi
    [[ "$channel" == "public" ]] || return 0

    local app_report helper_report
    app_report="$("$COVIO_TX_CODESIGN" -dv --verbose=4 "$app" 2>&1)" || return 1
    helper_report="$("$COVIO_TX_CODESIGN" -dv --verbose=4 "$helper" 2>&1)" || return 1
    if [[ "$app_report" != *"Authority=Developer ID Application:"* ||
          "$helper_report" != *"Authority=Developer ID Application:"* ]]; then
        covio_tx_log "Public release requires Developer ID Application signatures"
        return 1
    fi
    if [[ "$app_report" != *"runtime"* || "$helper_report" != *"runtime"* ]]; then
        covio_tx_log "Public app and helper require hardened runtime"
        return 1
    fi
    if ! "$COVIO_TX_STAPLER" stapler validate "$app" >/dev/null 2>&1; then
        covio_tx_log "App notarization ticket is missing"
        return 1
    fi
    if ! "$COVIO_TX_SPCTL" -a -vv --type execute "$app" >/dev/null 2>&1; then
        covio_tx_log "Gatekeeper rejected the app"
        return 1
    fi
}

covio_tx_verify_old_app() {
    local app="$1"
    if ! covio_tx_load_info_identity "$app" OLD ||
       ! covio_tx_validate_prefix OLD; then
        covio_tx_log "Installed app identity is incomplete or invalid"
        return 1
    fi
    covio_tx_verify_signatures "$app" "$(covio_tx_identity_value OLD CHANNEL)" || return 1
    if ! covio_tx_load_helper_identity "$app" OLD_HELPER ||
       ! covio_tx_validate_prefix OLD_HELPER; then
        covio_tx_log "Installed helper identity cannot be read"
        return 1
    fi
    if ! covio_tx_prefixes_equal OLD OLD_HELPER; then
        covio_tx_log "Installed app and helper identities differ"
        return 1
    fi
}

covio_tx_verify_new_app() {
    local app="$1"
    local manifest="$app/Contents/Resources/release-manifest.json"
    if [[ ! -f "$manifest" ]]; then
        covio_tx_log "Staged app has no release manifest"
        return 1
    fi
    if [[ "$(covio_tx_plist_raw "$manifest" schemaVersion)" != "2" ]]; then
        covio_tx_log "Staged app bundle manifest schemaVersion must be 2"
        return 1
    fi
    if ! covio_tx_load_info_identity "$app" NEW ||
       ! covio_tx_validate_modern_prefix NEW; then
        covio_tx_log "Staged app identity is incomplete or invalid"
        return 1
    fi
    covio_tx_verify_signatures "$app" "$(covio_tx_identity_value NEW CHANNEL)" || return 1
    if ! covio_tx_load_manifest_identity "$manifest" NEW_MANIFEST ||
       ! covio_tx_validate_modern_prefix NEW_MANIFEST; then
        covio_tx_log "Staged release manifest is incomplete or invalid"
        return 1
    fi
    if ! covio_tx_load_helper_identity "$app" NEW_HELPER ||
       ! covio_tx_validate_modern_prefix NEW_HELPER; then
        covio_tx_log "Staged helper identity cannot be read"
        return 1
    fi
    if ! covio_tx_prefixes_equal NEW NEW_MANIFEST ||
       ! covio_tx_prefixes_equal NEW NEW_HELPER; then
        covio_tx_log "Staged app, manifest and helper identities differ"
        return 1
    fi
    if [[ "$(covio_tx_identity_value NEW CLIENT_VERSION)" != "$EXPECTED_CLIENT_VERSION" ||
          "$(covio_tx_identity_value NEW PRODUCT_VERSION)" != "$EXPECTED_PRODUCT_VERSION" ||
          "$(covio_tx_identity_value NEW BUILD_NUMBER)" != "$EXPECTED_BUILD_NUMBER" ||
          "$(covio_tx_identity_value NEW RELEASE_ID)" != "$EXPECTED_RELEASE_ID" ||
          "$(covio_tx_identity_value NEW GIT_COMMIT)" != "$EXPECTED_COMMIT" ||
          "$(covio_tx_identity_value NEW PROTOCOL_VERSION)" != "$EXPECTED_PROTOCOL_VERSION" ||
          "$(covio_tx_identity_value NEW HELPER_SHA256)" != "$EXPECTED_HELPER_SHA256" ||
          "$(covio_tx_identity_value NEW UPDATER_SHA256)" != "$EXPECTED_UPDATER_SHA256" ||
          ( "$TX_UPDATE_MODE" != "automatic" &&
            "$(covio_tx_identity_value NEW UPDATER_LAUNCHER_SHA256)" != "$EXPECTED_UPDATER_LAUNCHER_SHA256" ) ||
          "$(covio_tx_identity_value NEW CHANNEL)" != "$EXPECTED_CHANNEL" ]]; then
        covio_tx_log "Staged app differs from the signed installer identity"
        return 1
    fi
    local app_arch helper_arch
    app_arch="$("$COVIO_TX_LIPO" -archs "$app/Contents/MacOS/Covio")"
    helper_arch="$("$COVIO_TX_LIPO" -archs "$app/Contents/MacOS/CovioHelper")"
    if [[ "$app_arch" != "arm64" || "$helper_arch" != "arm64" ]]; then
        covio_tx_log "Staged app and helper must both be arm64"
        return 1
    fi
}

covio_tx_validate_upgrade_order() {
    local old_build new_build old_protocol new_protocol old_channel
    old_build="$(covio_tx_identity_value OLD BUILD_NUMBER)"
    new_build="$(covio_tx_identity_value NEW BUILD_NUMBER)"
    old_protocol="$(covio_tx_identity_value OLD PROTOCOL_VERSION)"
    new_protocol="$(covio_tx_identity_value NEW PROTOCOL_VERSION)"
    old_channel="$(covio_tx_identity_value OLD CHANNEL)"
    if (( new_build < old_build )); then
        covio_tx_log "Downgrade rejected: build $new_build is older than $old_build"
        return 1
    fi
    if (( new_build == old_build )) &&
       [[ "$(covio_tx_identity_value NEW RELEASE_ID)" != "$(covio_tx_identity_value OLD RELEASE_ID)" ]]; then
        covio_tx_log "A different release must use a higher build number"
        return 1
    fi
    if (( new_protocol < old_protocol )); then
        covio_tx_log "Helper protocol downgrade rejected"
        return 1
    fi
    if [[ "$old_channel" == "public" && "$EXPECTED_CHANNEL" == "internal" ]]; then
        covio_tx_log "A public installation cannot move to the internal channel"
        return 1
    fi
}

covio_tx_write_identity_record() {
    local prefix="$1"
    local output="$2"
    local temporary="$output.tmp.$$"
    "$COVIO_TX_PLUTIL" -create xml1 "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert schemaVersion -integer 2 "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert releaseId -string "$(covio_tx_identity_value "$prefix" RELEASE_ID)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert clientVersion -string "$(covio_tx_identity_value "$prefix" CLIENT_VERSION)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert productVersion -string "$(covio_tx_identity_value "$prefix" PRODUCT_VERSION)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert buildNumber -integer "$(covio_tx_identity_value "$prefix" BUILD_NUMBER)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert gitCommit -string "$(covio_tx_identity_value "$prefix" GIT_COMMIT)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert helperProtocolVersion -integer "$(covio_tx_identity_value "$prefix" PROTOCOL_VERSION)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert helperSHA256 -string "$(covio_tx_identity_value "$prefix" HELPER_SHA256)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert updaterReleaseId -string "$(covio_tx_identity_value "$prefix" RELEASE_ID)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert updaterProtocolVersion -integer "$COVIO_TX_UPDATER_PROTOCOL_VERSION" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert updaterSHA256 -string "$(covio_tx_identity_value "$prefix" UPDATER_SHA256)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert updaterLauncherSHA256 -string "$(covio_tx_identity_value "$prefix" UPDATER_LAUNCHER_SHA256)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert channel -string "$(covio_tx_identity_value "$prefix" CHANNEL)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -convert json -o "$output" "$temporary" >/dev/null
    chmod 0644 "$output"
    if [[ "$TX_TEST_MODE" != "1" ]]; then
        chown root:wheel "$output"
    fi
    unlink "$temporary"
}

covio_tx_current_record_matches_old() {
    [[ -f "$TX_RECORD_PATH" ]] || return 0
    if ! covio_tx_load_manifest_identity "$TX_RECORD_PATH" RECORD ||
       ! covio_tx_validate_prefix RECORD; then
        covio_tx_log "installed-release.json is invalid"
        return 1
    fi
    if [[ "$(covio_tx_identity_value RECORD RELEASE_ID)" != "$(covio_tx_identity_value OLD RELEASE_ID)" ]]; then
        covio_tx_log "installed-release.json does not match the installed app"
        return 1
    fi
}

covio_tx_console_user() {
    stat -f '%Su' /dev/console
}

covio_tx_run_as_user() {
    if [[ "$TX_TEST_MODE" == "1" ]]; then
        "$@"
        return
    fi
    local user uid
    user="$(covio_tx_console_user)"
    if [[ -z "$user" || "$user" == "root" || "$user" == "loginwindow" || "$user" == "_mbsetupuser" ]]; then
        covio_tx_log "No logged-in console user is available"
        return 1
    fi
    uid="$(id -u "$user")"
    /bin/launchctl asuser "$uid" /usr/bin/sudo -u "$user" -H "$@"
}

covio_tx_running_installed_app() {
    "$COVIO_TX_PGREP" -f -x "$TX_APP_PATH/Contents/MacOS/Covio" >/dev/null 2>&1
}

covio_tx_quit_running_app() {
    if [[ "$TX_TEST_MODE" == "1" ]]; then
        return 0
    fi
    covio_tx_running_installed_app || return 0
    covio_tx_log "Asking Covio to quit before the bundle exchange"
    covio_tx_run_as_user /usr/bin/osascript -e 'tell application id "com.wyz.covio" to quit' || return 1
    local attempt
    for attempt in $(seq 1 40); do
        covio_tx_running_installed_app || return 0
        sleep 0.25
    done
    covio_tx_log "Covio did not quit; upgrade stopped before changing the app"
    return 1
}

covio_tx_cleanup_legacy_sleep() {
    local owner_path="$TX_STATE_ROOT/sleep_owner"
    if [[ -f "$owner_path" && "$(cat "$owner_path")" == "covio-sleep-disabled-v2" ]]; then
        if ! /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1; then
            covio_tx_log "Cannot clear Covio SleepDisabled during legacy migration"
            return 1
        fi
        unlink "$owner_path"
    fi
}

covio_tx_console_uid() {
    if [[ "$TX_TEST_MODE" == "1" ]]; then
        "$COVIO_TX_ID" -u
        return
    fi
    local user
    user="$(covio_tx_console_user)"
    if [[ -z "$user" || "$user" == "root" || "$user" == "loginwindow" || "$user" == "_mbsetupuser" ]]; then
        covio_tx_log "No logged-in console user is available for the helper service"
        return 1
    fi
    "$COVIO_TX_ID" -u "$user"
}

covio_tx_bootout_local_helper() {
    if [[ "$TX_TEST_MODE" == "1" || ! -f "$TX_LAUNCHD_PATH" ]]; then
        return 0
    fi
    "$COVIO_TX_LAUNCHCTL" bootout system "$TX_LAUNCHD_PATH" >/dev/null 2>&1 || true
}

covio_tx_bootstrap_local_helper() {
    if [[ "$TX_TEST_MODE" == "1" ]]; then
        return 0
    fi
    "$COVIO_TX_LAUNCHCTL" bootstrap system "$TX_LAUNCHD_PATH"
}

covio_tx_remove_local_helper() {
    covio_tx_bootout_local_helper
    if [[ -e "$TX_HELPER_PATH" ]]; then
        unlink "$TX_HELPER_PATH"
    fi
    if [[ -e "$TX_LAUNCHD_PATH" ]]; then
        unlink "$TX_LAUNCHD_PATH"
    fi
    local name
    for name in allowed_uid client-requirement version Covio.app; do
        if [[ -e "$TX_STATE_ROOT/$name" ]]; then
            unlink "$TX_STATE_ROOT/$name"
        fi
    done
}

covio_tx_stop_updater_processes() {
    local name pid attempt remaining
    if [[ "$TX_TEST_MODE" == "1" ]]; then
        return 0
    fi
    for name in CovioUpdaterLauncher CovioUpdater; do
        for pid in $("$COVIO_TX_PGREP" -x "$name" 2>/dev/null || true); do
            covio_tx_log "Stopping stale $name process $pid"
            kill -TERM "$pid" >/dev/null 2>&1 || true
        done
    done
    for attempt in $(seq 1 20); do
        remaining=0
        for name in CovioUpdaterLauncher CovioUpdater; do
            if "$COVIO_TX_PGREP" -x "$name" >/dev/null 2>&1; then
                remaining=1
                break
            fi
        done
        [[ "$remaining" == "0" ]] && return 0
        sleep 0.1
    done
    for name in CovioUpdaterLauncher CovioUpdater; do
        /usr/bin/pkill -KILL -x "$name" >/dev/null 2>&1 || true
    done
}

covio_tx_bootout_local_updater() {
    if [[ "$TX_TEST_MODE" == "1" ]]; then
        return 0
    fi
    "$COVIO_TX_LAUNCHCTL" bootout system/com.wyz.covio.updater >/dev/null 2>&1 || true
    covio_tx_stop_updater_processes
}

covio_tx_backup_updater() {
    local present=0
    mkdir -p "$TX_TRANSACTION_ROOT/previous"
    if [[ -d "$TX_UPDATER_ROOT" ]]; then
        "$COVIO_TX_DITTO" "$TX_UPDATER_ROOT" "$TX_BACKUP_UPDATER" || return 1
        present=1
    fi
    if [[ -f "$TX_UPDATER_LAUNCHD_PATH" ]]; then
        "$COVIO_TX_DITTO" "$TX_UPDATER_LAUNCHD_PATH" "$TX_BACKUP_UPDATER_LAUNCHD" || return 1
        present=1
    fi
    if [[ "$present" == "1" ]]; then
        printf 'present
' > "$TX_BACKUP_UPDATER_STATE"
    else
        printf 'absent
' > "$TX_BACKUP_UPDATER_STATE"
    fi
}

covio_tx_restore_updater() {
    local state
    covio_tx_bootout_local_updater
    if [[ -d "$TX_UPDATER_ROOT" ]]; then
        covio_tx_remove_tree "$TX_UPDATER_ROOT"
    fi
    if [[ -e "$TX_UPDATER_LAUNCHD_PATH" ]]; then
        unlink "$TX_UPDATER_LAUNCHD_PATH"
    fi
    [[ -f "$TX_BACKUP_UPDATER_STATE" ]] || return 0
    state="$(cat "$TX_BACKUP_UPDATER_STATE")"
    if [[ "$state" == "absent" ]]; then
        return 0
    fi
    [[ "$state" == "present" && -d "$TX_BACKUP_UPDATER" ]] || return 1
    mkdir -p "$(dirname "$TX_UPDATER_ROOT")"
    "$COVIO_TX_DITTO" "$TX_BACKUP_UPDATER" "$TX_UPDATER_ROOT" || return 1
    if [[ -f "$TX_BACKUP_UPDATER_LAUNCHD" ]]; then
        mkdir -p "$(dirname "$TX_UPDATER_LAUNCHD_PATH")"
        "$COVIO_TX_DITTO" "$TX_BACKUP_UPDATER_LAUNCHD" "$TX_UPDATER_LAUNCHD_PATH" || return 1
        chmod 0644 "$TX_UPDATER_LAUNCHD_PATH"
        if [[ "$TX_TEST_MODE" != "1" ]]; then
            chown root:wheel "$TX_UPDATER_LAUNCHD_PATH"
            "$COVIO_TX_LAUNCHCTL" bootstrap system "$TX_UPDATER_LAUNCHD_PATH" >/dev/null 2>&1 || return 1
        fi
    fi
}

covio_tx_backup_helper_metadata() {
    local name
    mkdir -p "$TX_BACKUP_HELPER_METADATA"
    for name in allowed_uid client-requirement version Covio.app; do
        if [[ -f "$TX_STATE_ROOT/$name" ]] &&
           ! "$COVIO_TX_DITTO" "$TX_STATE_ROOT/$name" "$TX_BACKUP_HELPER_METADATA/$name"
        then
            return 1
        fi
    done
}

covio_tx_restore_helper_metadata() {
    local name source destination
    for name in allowed_uid client-requirement version Covio.app; do
        source="$TX_BACKUP_HELPER_METADATA/$name"
        destination="$TX_STATE_ROOT/$name"
        if [[ -f "$source" ]]; then
            "$COVIO_TX_DITTO" "$source" "$destination"
            chmod 0644 "$destination"
            if [[ "$TX_TEST_MODE" != "1" ]]; then
                chown root:wheel "$destination"
            fi
        elif [[ -e "$destination" ]]; then
            unlink "$destination"
        fi
    done
}

covio_tx_restore_helper_backup() {
    covio_tx_bootout_local_helper
    if [[ -f "$TX_BACKUP_HELPER" ]]; then
        mkdir -p "$(dirname "$TX_HELPER_PATH")"
        "$COVIO_TX_DITTO" "$TX_BACKUP_HELPER" "$TX_HELPER_PATH"
        chmod 0755 "$TX_HELPER_PATH"
        if [[ "$TX_TEST_MODE" != "1" ]]; then
            chown root:wheel "$TX_HELPER_PATH"
        fi
    elif [[ -e "$TX_HELPER_PATH" ]]; then
        unlink "$TX_HELPER_PATH"
    fi
    if [[ -f "$TX_BACKUP_LAUNCHD" ]]; then
        mkdir -p "$(dirname "$TX_LAUNCHD_PATH")"
        "$COVIO_TX_DITTO" "$TX_BACKUP_LAUNCHD" "$TX_LAUNCHD_PATH"
        chmod 0644 "$TX_LAUNCHD_PATH"
        if [[ "$TX_TEST_MODE" != "1" ]]; then
            chown root:wheel "$TX_LAUNCHD_PATH"
        fi
        covio_tx_bootstrap_local_helper
    elif [[ -e "$TX_LAUNCHD_PATH" ]]; then
        unlink "$TX_LAUNCHD_PATH"
    fi
    covio_tx_restore_helper_metadata
}

covio_tx_prepare_privileged_state() {
    local app="$1"
    local binary="$app/Contents/MacOS/Covio"
    local transaction_version install_mode
    transaction_version="$(covio_tx_identity_value OLD TRANSACTION_VERSION)"
    install_mode="$(covio_tx_identity_value OLD INSTALL_MODE)"
    if [[ "$transaction_version" == "1" ]]; then
        covio_tx_run_as_user "$binary" --prepare-install-transaction || {
            covio_tx_log "Privileged state restore failed; upgrade stopped"
            return 1
        }
        if [[ "$install_mode" != "legacy" ]]; then
            # build 2 及更早的事务版本使用 SMAppService。先注销旧服务，
            # 交换 bundle 后由新 helper 安装固定路径 LaunchDaemon。
            covio_tx_run_as_user "$binary" --uninstall-helper || {
                covio_tx_register_and_verify_helper "$app" OLD >/dev/null 2>&1 || true
                covio_tx_log "Cannot unregister the previous SMAppService helper"
                return 1
            }
            if ! covio_tx_cleanup_legacy_sleep; then
                covio_tx_register_and_verify_helper "$app" OLD >/dev/null 2>&1 || true
                covio_tx_log "Cannot clear stale SleepDisabled after service migration"
                return 1
            fi
        fi
    else
        covio_tx_run_as_user "$binary" --uninstall-helper || {
            covio_tx_register_and_verify_helper "$app" OLD >/dev/null 2>&1 || true
            covio_tx_log "Legacy helper restore failed; upgrade stopped"
            return 1
        }
        if ! covio_tx_cleanup_legacy_sleep; then
            covio_tx_register_and_verify_helper "$app" OLD >/dev/null 2>&1 || true
            return 1
        fi
    fi
}

covio_tx_write_report() {
    local result="$1"
    local reason="$2"
    local previous_release_id="${3:-}"
    local temporary="$TX_REPORT_PATH.tmp.$$"
    mkdir -p "$TX_STATE_ROOT"
    "$COVIO_TX_PLUTIL" -create xml1 "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert schemaVersion -integer 1 "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert source -string "$TX_REPORT_SOURCE" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert transactionId -string "$TRANSACTION_ID" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert releaseId -string "$EXPECTED_RELEASE_ID" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert previousReleaseId -string "$previous_release_id" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert result -string "$result" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert rollbackReason -string "$reason" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -insert recordedAt \
        -string "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$temporary" >/dev/null
    "$COVIO_TX_PLUTIL" -convert json -o "$TX_REPORT_PATH" "$temporary" >/dev/null
    chmod 0644 "$TX_REPORT_PATH"
    if [[ "$TX_TEST_MODE" != "1" ]]; then
        chown root:wheel "$TX_REPORT_PATH"
    fi
    unlink "$temporary"
}

covio_tx_prepare() {
    covio_tx_require_root || return 1
    unset NEW_HELPER_SHA256
    mkdir -p "$TX_INSTALLER_ROOT/transactions"
    if [[ -e "$TX_CURRENT_POINTER" ]]; then
        local existing_root existing_state
        existing_root="$(cat "$TX_CURRENT_POINTER")"
        existing_state="$(cat "$existing_root/state" 2>/dev/null || printf 'missing')"
        if [[ "$existing_state" == "missing" ]]; then
            printf 'Archiving unstarted transaction: %s\n' "$existing_root" >&2
            if [[ -d "$existing_root" ]]; then
                covio_tx_archive_transaction_root "$existing_root"
            fi
            unlink "$TX_CURRENT_POINTER"
        elif [[ "$existing_state" != "committed" && "$existing_state" != "rolled-back" ]]; then
            covio_tx_log "Unfinished transaction exists: $existing_root"
            return 1
        else
            unlink "$TX_CURRENT_POINTER"
        fi
    fi
    if [[ -e "$TX_STAGED_APP" && "$TX_UPDATE_MODE" != "automatic" ]]; then
        covio_tx_log "A stale staged app already exists"
        return 1
    fi
    if [[ -e "$TX_TRANSACTION_ROOT" ]]; then
        local last_root=""
        if [[ -f "$TX_LAST_POINTER" ]]; then
            last_root="$(cat "$TX_LAST_POINTER")"
        fi
        if [[ "$last_root" != "$TX_TRANSACTION_ROOT" ]]; then
            covio_tx_log "Stale transaction directory exists: $TX_TRANSACTION_ROOT"
            return 1
        fi
        covio_tx_archive_transaction_root "$TX_TRANSACTION_ROOT"
    fi
    mkdir -p "$TX_TRANSACTION_ROOT/previous" "$TX_TRANSACTION_ROOT/candidate"
    cp "$TX_ENVIRONMENT_SOURCE" "$TX_ENVIRONMENT_FILE"
    covio_tx_point_to_transaction
    covio_tx_write_report prepared "" ""

    if [[ ! -d "$TX_APP_PATH" ]]; then
        if [[ -e "$TX_RECORD_PATH" ]]; then
            covio_tx_write_report failed "installed release record exists without the app" ""
            return 1
        fi
        covio_tx_write_state prepared-new
        covio_tx_log "Prepared clean install transaction $TRANSACTION_ID"
        return 0
    fi

    covio_tx_verify_old_app "$TX_APP_PATH" || {
        covio_tx_write_report failed "installed app verification failed" ""
        return 1
    }
    if [[ "$TX_UPDATE_MODE" == "automatic" ]] && ! covio_tx_verify_installed_updater; then
        covio_tx_write_report failed "installed updater verification failed" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    fi
    covio_tx_current_record_matches_old || {
        covio_tx_write_report failed "installed release record mismatch" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    }
    covio_tx_validate_expected_identity || {
        covio_tx_write_report failed "signed installer identity is invalid" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    }
    covio_tx_quit_running_app || {
        covio_tx_write_report failed "running app did not quit" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    }
    covio_tx_prepare_privileged_state "$TX_APP_PATH" || {
        covio_tx_write_report failed "privileged state restore failed" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    }
    if ! "$COVIO_TX_DITTO" "$TX_APP_PATH" "$TX_BACKUP_APP"; then
        covio_tx_register_and_verify_helper "$TX_APP_PATH" OLD >/dev/null 2>&1 || true
        covio_tx_write_report failed "previous app backup failed" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    fi
    if ! covio_tx_verify_old_app "$TX_BACKUP_APP"; then
        covio_tx_register_and_verify_helper "$TX_APP_PATH" OLD >/dev/null 2>&1 || true
        covio_tx_write_report failed "previous app backup is not trusted" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    fi
    if [[ -f "$TX_HELPER_PATH" ]] && ! "$COVIO_TX_DITTO" "$TX_HELPER_PATH" "$TX_BACKUP_HELPER"; then
        covio_tx_register_and_verify_helper "$TX_APP_PATH" OLD >/dev/null 2>&1 || true
        covio_tx_write_report failed "previous helper backup failed" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    fi
    if [[ -f "$TX_LAUNCHD_PATH" ]] && ! "$COVIO_TX_DITTO" "$TX_LAUNCHD_PATH" "$TX_BACKUP_LAUNCHD"; then
        covio_tx_register_and_verify_helper "$TX_APP_PATH" OLD >/dev/null 2>&1 || true
        covio_tx_write_report failed "previous LaunchDaemon backup failed" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    fi
    if ! covio_tx_backup_helper_metadata; then
        covio_tx_register_and_verify_helper "$TX_APP_PATH" OLD >/dev/null 2>&1 || true
        covio_tx_write_report failed "previous helper metadata backup failed" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    fi
    if ! covio_tx_backup_updater; then
        covio_tx_register_and_verify_helper "$TX_APP_PATH" OLD >/dev/null 2>&1 || true
        covio_tx_write_report failed "previous updater backup failed" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    fi
    if ! covio_tx_write_identity_record OLD "$TX_PREVIOUS_RECORD"; then
        covio_tx_register_and_verify_helper "$TX_APP_PATH" OLD >/dev/null 2>&1 || true
        covio_tx_write_report failed "previous release record backup failed" \
            "$(covio_tx_identity_value OLD RELEASE_ID)"
        return 1
    fi
    covio_tx_write_state prepared
    covio_tx_log "Prepared upgrade transaction $TRANSACTION_ID"
}

covio_tx_wait_for_helper_match() {
    local app="$1"
    local binary="$app/Contents/MacOS/Covio"
    local transaction_version="$2"
    local expected_version="$3"
    local probe_output="$TX_TRANSACTION_ROOT/helper-probe.out"
    local probe_error="$TX_TRANSACTION_ROOT/helper-probe.err"
    local attempt status attempts="${COVIO_TX_WAIT_ATTEMPTS:-40}"
    mkdir -p "$TX_TRANSACTION_ROOT"
    for attempt in $(seq 1 "$attempts"); do
        if [[ "$transaction_version" == "1" ]]; then
            if covio_tx_run_as_user "$binary" --verify-install-transaction \
                >"$probe_output" 2>"$probe_error"
            then
                return 0
            fi
            status=$?
        else
            if covio_tx_run_as_user "$binary" --helper-version \
                >"$probe_output" 2>"$probe_error"
            then
                status=0
                if [[ "$(cat "$probe_output")" == "$expected_version" ]]; then
                    return 0
                fi
            else
                status=$?
            fi
        fi
        sleep 0.25
    done
    local output_text error_text
    output_text="$(tail -c 4096 "$probe_output" 2>/dev/null || true)"
    error_text="$(tail -c 4096 "$probe_error" 2>/dev/null || true)"
    covio_tx_log "Helper handshake did not match after $attempts attempts: exit=${status:-unknown} stdout=${output_text:-<empty>} stderr=${error_text:-<empty>}"
    return 1
}

covio_tx_register_and_verify_helper() {
    local app="$1"
    local prefix="$2"
    local binary="$app/Contents/MacOS/Covio"
    local transaction_version version install_mode uid register_output register_error status
    transaction_version="$(covio_tx_identity_value "$prefix" TRANSACTION_VERSION)"
    version="$(covio_tx_identity_value "$prefix" PRODUCT_VERSION)"
    install_mode="$(covio_tx_identity_value "$prefix" INSTALL_MODE)"
    register_output="$TX_TRANSACTION_ROOT/helper-register-$prefix.out"
    register_error="$TX_TRANSACTION_ROOT/helper-register-$prefix.err"
    mkdir -p "$TX_TRANSACTION_ROOT"
    covio_tx_log "Installing helper for $prefix: mode=${install_mode:-smappservice} transactionVersion=${transaction_version:-legacy}"
    if [[ "$install_mode" == "legacy" ]]; then
        uid="$(covio_tx_console_uid)" || return 1
        if "$binary" --install-legacy-helper-as-root "$uid" \
            >"$register_output" 2>"$register_error"
        then
            :
        else
            status=$?
            covio_tx_log "Fixed helper installation failed: exit=$status stderr=$(tail -c 4096 "$register_error" 2>/dev/null || true)"
            return 1
        fi
        if [[ ! -x "$TX_HELPER_PATH" || ! -f "$TX_LAUNCHD_PATH" ]]; then
            covio_tx_log "Legacy helper installation did not create the fixed paths"
            return 1
        fi
    elif [[ "$transaction_version" == "1" ]]; then
        if covio_tx_run_as_user "$binary" --register-install-transaction-helper \
            >"$register_output" 2>"$register_error"
        then
            :
        else
            status=$?
            covio_tx_log "SMAppService helper registration failed: exit=$status stderr=$(tail -c 4096 "$register_error" 2>/dev/null || true)"
            return 1
        fi
    else
        if covio_tx_run_as_user "$binary" --install-helper \
            >"$register_output" 2>"$register_error"
        then
            :
        else
            status=$?
            covio_tx_log "Legacy helper installer failed: exit=$status stderr=$(tail -c 4096 "$register_error" 2>/dev/null || true)"
            return 1
        fi
    fi
    covio_tx_log "Helper installation completed for $prefix; waiting for exact handshake"
    if ! covio_tx_wait_for_helper_match "$app" "$transaction_version" "$version"; then
        covio_tx_log "Exact helper handshake failed for $prefix"
        return 1
    fi
    covio_tx_log "Exact helper handshake matched for $prefix"
}

covio_tx_verify_installed_updater() {
    local current launcher engine record_release record_engine record_launcher launcher_sha engine_sha
    current="$(tr -d '[:space:]' < "$TX_UPDATER_ROOT/current" 2>/dev/null || true)"
    launcher="$TX_UPDATER_ROOT/bin/CovioUpdaterLauncher"
    engine="$TX_UPDATER_ROOT/versions/$current/CovioUpdater"
    [[ "$current" =~ ^((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-internal\.[1-9][0-9]*)?|[0-9]\.[0-9]\.[0-9]\.[0-9])-g[0-9a-f]{40}$ ]] || return 1
    [[ -x "$launcher" && -x "$engine" && -f "$TX_UPDATER_LAUNCHD_PATH" ]] || return 1
    [[ -f "$TX_RECORD_PATH" && -f "$TX_UPDATER_ROOT/updater-client-requirement" &&
       -f "$TX_UPDATER_ROOT/updater-requirement" ]] || return 1
    record_release="$("$COVIO_TX_PLUTIL" -extract releaseId raw -o - "$TX_RECORD_PATH" 2>/dev/null || true)"
    record_engine="$("$COVIO_TX_PLUTIL" -extract updaterSHA256 raw -o - "$TX_RECORD_PATH" 2>/dev/null || true)"
    record_launcher="$("$COVIO_TX_PLUTIL" -extract updaterLauncherSHA256 raw -o - "$TX_RECORD_PATH" 2>/dev/null || true)"
    [[ "$record_release" == "$current" && "$record_engine" =~ ^[0-9a-f]{64}$ &&
       "$record_launcher" =~ ^[0-9a-f]{64}$ ]] || return 1
    launcher_sha="$(covio_tx_sha256 "$launcher")"
    engine_sha="$(covio_tx_sha256 "$engine")"
    [[ "$launcher_sha" == "$record_launcher" && "$engine_sha" == "$record_engine" ]] || return 1
    [[ "$launcher_sha" == "$EXPECTED_UPDATER_LAUNCHER_SHA256" ]] || return 1
    if [[ "$TX_TEST_MODE" != "1" ]]; then
        "$COVIO_TX_CODESIGN" --verify --strict "$launcher" >/dev/null 2>&1 || return 1
        "$COVIO_TX_CODESIGN" --verify --strict "$engine" >/dev/null 2>&1 || return 1
        [[ "$("$COVIO_TX_CODESIGN" -d --verbose=2 "$launcher" 2>&1)" == *"Identifier=com.wyz.covio.updater.launcher"* ]] || return 1
        [[ "$("$COVIO_TX_CODESIGN" -d --verbose=2 "$engine" 2>&1)" == *"Identifier=com.wyz.covio.updater"* ]] || return 1
        [[ "$(stat -f '%u:%g' "$launcher")" == "0:0" ]] || return 1
        [[ "$(stat -f '%u:%g' "$engine")" == "0:0" ]] || return 1
    fi
    [[ -n "${EXPECTED_PREVIOUS_RELEASE_ID:-}" && "$current" == "$EXPECTED_PREVIOUS_RELEASE_ID" ]]
}

covio_tx_install_updater_file() {
    local source="$1"
    local destination="$2"
    local mode="$3"
    local temporary="$destination.tmp.$$"
    mkdir -p "$(dirname "$destination")" || return 1
    if [[ "$TX_TEST_MODE" == "1" ]]; then
        "$COVIO_TX_INSTALL" -m "$mode" "$source" "$temporary" || return 1
    else
        "$COVIO_TX_INSTALL" -m "$mode" -o root -g wheel "$source" "$temporary" || return 1
    fi
    mv "$temporary" "$destination"
}

covio_tx_write_updater_file() {
    local value="$1"
    local destination="$2"
    local temporary="$destination.tmp.$$"
    mkdir -p "$(dirname "$destination")" || return 1
    printf '%s\n' "$value" > "$temporary" || return 1
    chmod 0644 "$temporary" || return 1
    if [[ "$TX_TEST_MODE" != "1" ]]; then
        chown root:wheel "$temporary" || return 1
    fi
    sync
    mv "$temporary" "$destination"
}

covio_tx_codesign_requirement() {
    "$COVIO_TX_CODESIGN" -d -r- "$1" 2>&1 |
        sed -n -e 's/^# designated => //p' -e 's/^designated => //p' |
        tail -1
}

covio_tx_install_updater_from_verified_app() {
    local app="$1"
    local prefix="$2"
    local release_id source_engine source_launcher source_plist
    local client_requirement updater_requirement engine_sha launcher_sha version_directory
    release_id="$(covio_tx_identity_value "$prefix" RELEASE_ID)"
    source_engine="$app/Contents/MacOS/CovioUpdater"
    source_launcher="$app/Contents/MacOS/CovioUpdaterLauncher"
    source_plist="$app/Contents/Library/LaunchDaemons/com.wyz.covio.updater.plist"
    version_directory="$TX_UPDATER_ROOT/versions/$release_id"

    [[ -n "$release_id" && -x "$source_engine" && -x "$source_launcher" &&
       -f "$source_plist" ]] || {
        covio_tx_log "Verified app does not contain the updater layout"
        return 1
    }
    engine_sha="$(covio_tx_sha256 "$source_engine")"
    launcher_sha="$(covio_tx_sha256 "$source_launcher")"
    [[ "$engine_sha" == "$(covio_tx_identity_value "$prefix" UPDATER_SHA256)" &&
       "$launcher_sha" == "$(covio_tx_identity_value "$prefix" UPDATER_LAUNCHER_SHA256)" ]] || {
        covio_tx_log "Verified app updater digest is invalid"
        return 1
    }

    if [[ "$TX_TEST_MODE" != "1" ]]; then
        "$COVIO_TX_CODESIGN" --verify --strict "$source_engine" >/dev/null 2>&1 ||
            return 1
        "$COVIO_TX_CODESIGN" --verify --strict "$source_launcher" >/dev/null 2>&1 ||
            return 1
        [[ "$("$COVIO_TX_CODESIGN" -d --verbose=2 "$source_engine" 2>&1)" == \
           *"Identifier=com.wyz.covio.updater"* ]] || return 1
        [[ "$("$COVIO_TX_CODESIGN" -d --verbose=2 "$source_launcher" 2>&1)" == \
           *"Identifier=com.wyz.covio.updater.launcher"* ]] || return 1
    fi

    if [[ -s "$TX_STATE_ROOT/client-requirement" ]]; then
        client_requirement="$(cat "$TX_STATE_ROOT/client-requirement")"
    else
        client_requirement="$(covio_tx_codesign_requirement "$app/Contents/MacOS/Covio")"
    fi
    updater_requirement="$(covio_tx_codesign_requirement "$source_engine")"
    [[ -n "$client_requirement" && -n "$updater_requirement" ]] || {
        covio_tx_log "Verified app updater requirement is missing"
        return 1
    }

    covio_tx_install_updater_file "$source_launcher" \
        "$TX_UPDATER_ROOT/bin/CovioUpdaterLauncher" 0755 || return 1
    covio_tx_install_updater_file "$source_engine" \
        "$version_directory/CovioUpdater" 0755 || return 1
    covio_tx_write_updater_file "$client_requirement" \
        "$TX_UPDATER_ROOT/updater-client-requirement" || return 1
    covio_tx_write_updater_file "$updater_requirement" \
        "$TX_UPDATER_ROOT/updater-requirement" || return 1
    covio_tx_install_updater_file "$source_plist" \
        "$TX_UPDATER_LAUNCHD_PATH" 0644 || return 1
    covio_tx_write_updater_file "$release_id" "$TX_UPDATER_ROOT/current" || return 1

    chmod 0755 "$TX_UPDATER_ROOT" "$TX_UPDATER_ROOT/bin" \
        "$TX_UPDATER_ROOT/versions" "$version_directory" || return 1
    if [[ "$TX_TEST_MODE" != "1" ]]; then
        chown root:wheel "$TX_UPDATER_ROOT" "$TX_UPDATER_ROOT/bin" \
            "$TX_UPDATER_ROOT/versions" "$version_directory" || return 1
    fi
}

covio_tx_start_and_verify_updater() {
    local release_id="$1"
    local attempt health_release attempts="${COVIO_TX_WAIT_ATTEMPTS:-40}"
    if [[ "$TX_TEST_MODE" == "1" ]]; then
        return 0
    fi
    covio_tx_bootout_local_updater
    if ! "$COVIO_TX_LAUNCHCTL" bootstrap system "$TX_UPDATER_LAUNCHD_PATH"; then
        covio_tx_log "Cannot bootstrap CovioUpdater"
        return 1
    fi
    for attempt in $(seq 1 "$attempts"); do
        health_release="$("$COVIO_TX_PLUTIL" -extract releaseId raw -o - \
            "$TX_UPDATER_ROOT/health.json" 2>/dev/null || true)"
        if [[ "$health_release" == "$release_id" ]]; then
            return 0
        fi
        sleep 0.25
    done
    covio_tx_log "Updater health did not match after $attempts attempts: $(tail -c 4096 "$TX_UPDATER_ROOT/updater.log" 2>/dev/null || true)"
    return 1
}

covio_tx_register_and_verify_updater() {
    local app="$1"
    local prefix="$2"
    local binary="$app/Contents/MacOS/Covio"
    local output="$TX_TRANSACTION_ROOT/updater-install-$prefix.out"
    local error="$TX_TRANSACTION_ROOT/updater-install-$prefix.err"
    local uid current_release health_release status launcher_sha
    uid="$(covio_tx_console_uid)" || return 1
    mkdir -p "$TX_TRANSACTION_ROOT"
    covio_tx_log "Installing updater for $prefix"
    if [[ "$TX_UPDATE_MODE" == "automatic" ]]; then
        [[ "$EXPECTED_PREVIOUS_RELEASE_ID" =~ ^((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-internal\.[1-9][0-9]*)?|[0-9]\.[0-9]\.[0-9]\.[0-9])-g[0-9a-f]{40}$ ]] || return 1
        covio_tx_verify_installed_updater || return 1
        if ! COVIO_UPDATER_ROOT="$TX_UPDATER_ROOT" \
             COVIO_UPDATER_CURRENT_RELEASE_ID="$EXPECTED_PREVIOUS_RELEASE_ID" \
             COVIO_UPDATER_NEW_RELEASE_ID="$(covio_tx_identity_value "$prefix" RELEASE_ID)" \
             COVIO_UPDATER_EXPECTED_SHA256="$(covio_tx_identity_value "$prefix" UPDATER_SHA256)" \
             COVIO_UPDATER_EXPECTED_LAUNCHER_SHA256="$EXPECTED_UPDATER_LAUNCHER_SHA256" \
             COVIO_UPDATER_TEST_MODE="$TX_TEST_MODE" \
             COVIO_UPDATER_SKIP_LAUNCHD="$TX_TEST_MODE" \
             "$binary" --install-updater-engine-as-root \
             >"$output" 2>"$error"
        then
            status=$?
            covio_tx_log "Automatic updater engine installation failed: exit=$status stderr=$(tail -c 4096 "$error" 2>/dev/null || true)"
            return 1
        fi
        launcher_sha="$(covio_tx_sha256 "$TX_UPDATER_ROOT/bin/CovioUpdaterLauncher")"
        if [[ "$launcher_sha" != "$EXPECTED_UPDATER_LAUNCHER_SHA256" ]]; then
            covio_tx_log "Automatic update replaced the immutable launcher"
            return 1
        fi
        NEW_UPDATER_LAUNCHER_SHA256="$launcher_sha"
    else
        covio_tx_bootout_local_updater
        if ! COVIO_UPDATER_ROOT="$TX_UPDATER_ROOT" \
             COVIO_UPDATER_LAUNCHD_PATH="$TX_UPDATER_LAUNCHD_PATH" \
             COVIO_UPDATER_RELEASE_ID="$(covio_tx_identity_value "$prefix" RELEASE_ID)" \
             COVIO_UPDATER_TEST_MODE="$TX_TEST_MODE" \
             COVIO_UPDATER_SKIP_LAUNCHD=1 \
             "$binary" --install-updater-as-root \
             >"$output" 2>"$error"
        then
            status=$?
            covio_tx_log "Updater installation failed: exit=$status stderr=$(tail -c 4096 "$error" 2>/dev/null || true)"
            return 1
        fi
    fi
    current_release=""
    if [[ -f "$TX_UPDATER_ROOT/current" ]]; then
        current_release="$(tr -d '[:space:]' < "$TX_UPDATER_ROOT/current")"
    fi
    if [[ "$current_release" != "$(covio_tx_identity_value "$prefix" RELEASE_ID)" ||
          ! -x "$TX_UPDATER_ROOT/bin/CovioUpdaterLauncher" ||
          ! -x "$TX_UPDATER_ROOT/versions/$current_release/CovioUpdater" ||
          ! -f "$TX_UPDATER_LAUNCHD_PATH" ||
          ! -f "$TX_UPDATER_ROOT/updater-client-requirement" ||
          ! -f "$TX_UPDATER_ROOT/updater-requirement" ]]; then
        if [[ "$TX_UPDATE_MODE" != "pkg" ]]; then
            covio_tx_log "Automatic updater installation is incomplete"
            return 1
        fi
        covio_tx_log "Updater bootstrap did not create a complete layout; installing verified app files"
        covio_tx_install_updater_from_verified_app "$app" "$prefix" || return 1
        current_release="$(covio_tx_identity_value "$prefix" RELEASE_ID)"
    fi
    if [[ "$TX_UPDATE_MODE" == "pkg" ]] &&
       ! covio_tx_start_and_verify_updater "$current_release"; then
        return 1
    fi
    if [[ "$TX_TEST_MODE" != "1" ]]; then
        health_release="$("$COVIO_TX_PLUTIL" -extract releaseId raw -o - "$TX_UPDATER_ROOT/health.json" 2>/dev/null || true)"
        if [[ "$health_release" != "$current_release" ]]; then
            covio_tx_log "Updater health does not match current release"
            return 1
        fi
    fi
    covio_tx_log "Updater installation completed for $prefix"
}

covio_tx_write_installed_record() {
    local prefix="$1"
    covio_tx_write_identity_record "$prefix" "$TX_RECORD_PATH"
}

covio_tx_rollback() {
    local reason="$1"
    local old_release_id=""
    if [[ -f "$TX_STATE_FILE" ]]; then
        covio_tx_log "Rolling back transaction: $reason"
    fi
    if [[ -f "$TX_PREVIOUS_RECORD" ]]; then
        covio_tx_load_manifest_identity "$TX_PREVIOUS_RECORD" ROLLBACK_OLD >/dev/null 2>&1 || true
        old_release_id="$(covio_tx_identity_value ROLLBACK_OLD RELEASE_ID)"
    fi

    if [[ -d "$TX_BACKUP_APP" ]]; then
        covio_tx_quit_running_app || {
            covio_tx_write_state rollback-failed
            covio_tx_write_report rollback-failed "$reason; cannot stop installed app" "$old_release_id"
            return 1
        }
        local restore_parent="$TX_INSTALLER_ROOT/restore"
        covio_tx_remove_tree "$restore_parent"
        mkdir -p "$restore_parent"
        if ! "$COVIO_TX_DITTO" "$TX_BACKUP_APP" "$restore_parent/$COVIO_TX_APP_NAME"; then
            covio_tx_write_state rollback-failed
            covio_tx_write_report rollback-failed "$reason; cannot copy previous app" "$old_release_id"
            return 1
        fi
        if [[ -d "$TX_APP_PATH" ]]; then
            if ! "$TX_ATOMIC_SWAP" "$TX_APP_PATH" "$restore_parent/$COVIO_TX_APP_NAME"; then
                covio_tx_write_state rollback-failed
                covio_tx_write_report rollback-failed "$reason; atomic restore failed" "$old_release_id"
                return 1
            fi
        elif ! mv "$restore_parent/$COVIO_TX_APP_NAME" "$TX_APP_PATH"; then
            covio_tx_write_state rollback-failed
            covio_tx_write_report rollback-failed "$reason; cannot restore app path" "$old_release_id"
            return 1
        fi
        covio_tx_remove_tree "$restore_parent"
        if ! covio_tx_verify_old_app "$TX_APP_PATH"; then
            covio_tx_write_state rollback-failed
            covio_tx_write_report rollback-failed "$reason; restored app failed verification" "$old_release_id"
            return 1
        fi
        if [[ -f "$TX_PREVIOUS_RECORD" ]]; then
            covio_tx_install_record_file "$TX_PREVIOUS_RECORD" "$TX_RECORD_PATH"
        fi
        if ! covio_tx_restore_updater; then
            covio_tx_write_state rollback-failed
            covio_tx_write_report rollback-failed "$reason; updater restore failed" "$old_release_id"
            return 1
        fi
        if [[ "$(covio_tx_identity_value OLD INSTALL_MODE)" != "legacy" ]]; then
            covio_tx_remove_local_helper
        fi
        if ! covio_tx_register_and_verify_helper "$TX_APP_PATH" OLD; then
            covio_tx_restore_helper_backup || true
            if ! covio_tx_wait_for_helper_match \
                "$TX_APP_PATH" \
                "$(covio_tx_identity_value OLD TRANSACTION_VERSION)" \
                "$(covio_tx_identity_value OLD PRODUCT_VERSION)"
            then
                covio_tx_write_state rollback-failed
                covio_tx_write_report rollback-failed "$reason; previous helper did not match" "$old_release_id"
                return 1
            fi
        fi
        covio_tx_remove_tree "$TX_STAGED_APP"
        covio_tx_write_state rolled-back
        covio_tx_write_report rolled-back "$reason" "$old_release_id"
        covio_tx_mark_last_transaction
        covio_tx_clear_current_transaction
        covio_tx_log "Rollback completed at release $old_release_id"
        return 0
    fi

    covio_tx_quit_running_app || {
        covio_tx_write_state rollback-failed
        covio_tx_write_report rollback-failed "$reason; cannot stop installed app" ""
        return 1
    }
    if [[ -d "$TX_APP_PATH" ]]; then
        covio_tx_run_as_user "$TX_APP_PATH/Contents/MacOS/Covio" --uninstall-helper \
            >/dev/null 2>&1 || true
        covio_tx_remove_tree "$TX_APP_PATH"
    fi
    covio_tx_remove_local_helper
    covio_tx_restore_updater || true
    covio_tx_remove_tree "$TX_STAGED_APP"
    if [[ -e "$TX_RECORD_PATH" ]]; then
        unlink "$TX_RECORD_PATH"
    fi
    covio_tx_write_state rolled-back
    covio_tx_write_report rolled-back "$reason" ""
    covio_tx_mark_last_transaction
    covio_tx_clear_current_transaction
    covio_tx_log "Clean-install rollback completed"
}

covio_tx_commit() {
    covio_tx_require_root || return 1
    local state
    state="$(covio_tx_read_state)"
    if [[ "$state" != "prepared" && "$state" != "prepared-new" ]]; then
        covio_tx_log "Cannot commit from transaction state $state"
        return 1
    fi
    if ! covio_tx_verify_new_app "$TX_STAGED_APP"; then
        covio_tx_write_report failed "staged app verification failed" ""
        covio_tx_write_state failed
        return 1
    fi
    covio_tx_validate_expected_identity || {
        covio_tx_write_report failed "signed installer identity is invalid" ""
        covio_tx_write_state failed
        return 1
    }
    if [[ -d "$TX_APP_PATH" ]]; then
        if ! covio_tx_verify_old_app "$TX_BACKUP_APP"; then
            covio_tx_write_report failed "previous app backup failed verification" ""
            covio_tx_write_state failed
            return 1
        fi
        covio_tx_validate_upgrade_order || {
            covio_tx_write_report failed "downgrade or mixed release rejected" \
                "$(covio_tx_identity_value OLD RELEASE_ID)"
            covio_tx_write_state failed
            return 1
        }
    fi
    if ! "$COVIO_TX_DITTO" "$TX_STAGED_APP" "$TX_CANDIDATE_APP"; then
        covio_tx_rollback "cannot retain candidate app" || true
        return 1
    fi
    covio_tx_write_state swapping
    if [[ -d "$TX_APP_PATH" ]]; then
        if ! "$TX_ATOMIC_SWAP" "$TX_APP_PATH" "$TX_STAGED_APP"; then
            covio_tx_rollback "atomic app and helper exchange failed" || true
            return 1
        fi
    elif ! mv "$TX_STAGED_APP" "$TX_APP_PATH"; then
        covio_tx_rollback "cannot move app into Applications" || true
        return 1
    fi
    covio_tx_write_state app-installed
    if ! covio_tx_verify_new_app "$TX_APP_PATH"; then
        covio_tx_rollback "installed app verification failed" || true
        return 1
    fi
    if ! covio_tx_register_and_verify_helper "$TX_APP_PATH" NEW; then
        covio_tx_rollback "new helper registration or exact handshake failed" || true
        return 1
    fi
    if ! covio_tx_register_and_verify_updater "$TX_APP_PATH" NEW; then
        covio_tx_rollback "new updater installation or health check failed" || true
        return 1
    fi
    if ! covio_tx_write_installed_record NEW; then
        covio_tx_rollback "installed release record write failed" || true
        return 1
    fi
    covio_tx_write_state committed
    covio_tx_write_report installed "" "$(covio_tx_identity_value OLD RELEASE_ID)"
    covio_tx_mark_last_transaction
    covio_tx_clear_current_transaction
    covio_tx_remove_tree "$TX_STAGED_APP"
    covio_tx_remove_tree "$TX_CANDIDATE_APP"
    covio_tx_log "Committed release $EXPECTED_RELEASE_ID"
}

covio_tx_transaction_root_from_pointer() {
    local pointer="$1"
    if [[ ! -f "$pointer" ]]; then
        return 1
    fi
    cat "$pointer"
}

covio_tx_recover() {
    covio_tx_require_root || return 1
    local root state
    if ! root="$(covio_tx_transaction_root_from_pointer "$TX_CURRENT_POINTER")"; then
        root="$(covio_tx_transaction_root_from_pointer "$TX_LAST_POINTER")" || {
            covio_tx_log "No Covio install transaction is available to recover"
            return 1
        }
    fi
    if [[ ! -f "$root/transaction.env" ]]; then
        covio_tx_log "Transaction environment is missing: $root"
        return 1
    fi
    covio_tx_load_environment "$root/transaction.env" || return 1
    covio_tx_configure "$TX_STATE_ROOT" "$TX_APPLICATIONS_ROOT"
    state="$(covio_tx_read_state)"
    if [[ "$state" == "missing" ]]; then
        printf 'Archiving unstarted transaction during recovery: %s\n' "$root" >&2
        covio_tx_archive_transaction_root "$root"
        covio_tx_clear_current_transaction
        return 0
    fi
    if [[ "$state" == "committed" && "${1:-}" != "--manual-rollback" ]]; then
        printf 'The last transaction committed successfully. Use --manual-rollback to restore the previous release.\n' >&2
        return 2
    fi
    covio_tx_rollback "manual recovery from state $state"
}

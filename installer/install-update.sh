#!/bin/bash
set -euo pipefail

STATE_ROOT="${COVIO_TX_STATE_ROOT:-/Library/Application Support/Covio}"
INSTALLER_ROOT="$STATE_ROOT/Installer"
UPDATER_ROOT="$STATE_ROOT/Updater"
RESULT_PATH="$UPDATER_ROOT/update-result.json"
TX_DIR="${1:-}"
TARGET_RELEASE_ID=""
PREVIOUS_RELEASE_ID=""
TRANSACTION_ID=""
ROLLBACK_REASON=""

if [[ -z "$TX_DIR" || ! -d "$TX_DIR" ]]; then
    printf 'Missing updater transaction directory.\n' >&2
    exit 2
fi
TX_DIR="$(cd "$TX_DIR" && pwd -P)"
EXPECTED_PREFIX="$UPDATER_ROOT/transactions/"
if [[ "$TX_DIR" != "$EXPECTED_PREFIX"* ]]; then
    printf 'Updater transaction is outside the fixed directory.\n' >&2
    exit 2
fi
if [[ ! -f "$TX_DIR/transaction.env" ]]; then
    printf 'Missing updater transaction environment.\n' >&2
    exit 2
fi
if [[ ! -d "$TX_DIR/staging/Covio.app" ]]; then
    printf 'Missing staged Covio.app.\n' >&2
    exit 2
fi
STAGED_APP="$(cd "$TX_DIR/staging/Covio.app" && pwd -P)"
if [[ "$STAGED_APP" != "$TX_DIR/staging/Covio.app" ]]; then
    printf 'Staged app resolved outside its transaction.\n' >&2
    exit 2
fi
if [[ "${COVIO_TX_TEST_MODE:-0}" != "1" && "$(/usr/bin/id -u)" != "0" ]]; then
    printf 'Updater transactions require root.\n' >&2
    exit 2
fi

write_result() {
    local state="$1"
    local result="$2"
    local reason="$3"
    local temporary="$RESULT_PATH.tmp.$$"
    mkdir -p "$UPDATER_ROOT"
    /usr/bin/plutil -create xml1 "$temporary" >/dev/null
    /usr/bin/plutil -insert schemaVersion -integer 1 "$temporary" >/dev/null
    /usr/bin/plutil -insert state -string "$state" "$temporary" >/dev/null
    /usr/bin/plutil -insert transactionId -string "$TRANSACTION_ID" "$temporary" >/dev/null
    /usr/bin/plutil -insert targetReleaseId -string "$TARGET_RELEASE_ID" "$temporary" >/dev/null
    /usr/bin/plutil -insert previousReleaseId -string "$PREVIOUS_RELEASE_ID" "$temporary" >/dev/null
    /usr/bin/plutil -insert result -string "$result" "$temporary" >/dev/null
    /usr/bin/plutil -insert rollbackReason -string "$reason" "$temporary" >/dev/null
    /usr/bin/plutil -insert recordedAt -string "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$temporary" >/dev/null
    /usr/bin/plutil -convert json -o "$RESULT_PATH" "$temporary" >/dev/null
    chmod 0644 "$RESULT_PATH"
    if [[ "${COVIO_TX_TEST_MODE:-0}" != "1" ]]; then
        chown root:wheel "$RESULT_PATH"
    fi
    unlink "$temporary"
    sync
}

restart_updater() {
    if [[ "${COVIO_TX_TEST_MODE:-0}" == "1" || "${COVIO_UPDATER_SKIP_LAUNCHD:-0}" == "1" ]]; then
        return 0
    fi
    /bin/launchctl kickstart -k system/com.wyz.covio.updater >/dev/null 2>&1 || true
}

restart_app() {
    if [[ "${COVIO_TX_TEST_MODE:-0}" == "1" || "${COVIO_UPDATER_SKIP_APP_RESTART:-0}" == "1" ]]; then
        return 0
    fi
    local user uid
    user="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)"
    if [[ -z "$user" || "$user" == "root" || "$user" == "loginwindow" || "$user" == "_mbsetupuser" ]]; then
        return 0
    fi
    uid="$(/usr/bin/id -u "$user")" || return 0
    /bin/launchctl asuser "$uid" /usr/bin/open /Applications/Covio.app >/dev/null 2>&1 || true
}

finish() {
    local exit_code="$1"
    local state="$2"
    local result="$3"
    local reason="$4"
    write_result "$state" "$result" "$reason"
    restart_updater
    restart_app
    exit "$exit_code"
}

# shellcheck source=transaction.sh
source "$INSTALLER_ROOT/transaction.sh"
TX_ENVIRONMENT_SOURCE="$TX_DIR/transaction.env"
covio_tx_load_environment "$TX_ENVIRONMENT_SOURCE"
if [[ "$TX_UPDATE_MODE" != "automatic" ]]; then
    printf 'Updater transaction environment has the wrong mode.\n' >&2
    exit 2
fi
TARGET_RELEASE_ID="$EXPECTED_RELEASE_ID"
PREVIOUS_RELEASE_ID="${EXPECTED_PREVIOUS_RELEASE_ID:-}"
TRANSACTION_ID="${TRANSACTION_ID:-$(basename "$TX_DIR")}"
covio_tx_configure "$STATE_ROOT" "/Applications" "$STAGED_APP"

if ! covio_tx_prepare; then
    ROLLBACK_REASON="prepare failed before component exchange"
    finish 1 failed prepare-failed "$ROLLBACK_REASON"
fi
if ! covio_tx_commit; then
    ROLLBACK_REASON="component exchange failed and recovery was attempted"
    finish 1 failed install-failed "$ROLLBACK_REASON"
fi
finish 0 idle installed ""

#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/covio-update-installer-test.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT

fail() {
  printf 'update installer test failed: %s\n' "$1" >&2
  exit 1
}

STATE_ROOT="$TEST_ROOT/state"
UPDATER_ROOT="$STATE_ROOT/Updater"
TRANSACTION_ROOT="$UPDATER_ROOT/transactions/update-valid"
mkdir -p "$TRANSACTION_ROOT/staging" "$STATE_ROOT/Installer"

if COVIO_TX_STATE_ROOT="$STATE_ROOT" COVIO_TX_TEST_MODE=1 \
  bash "$ROOT/installer/install-update.sh" "$TEST_ROOT/outside" >/dev/null 2>&1
then
  fail "outside transaction was accepted"
fi

mkdir -p "$TEST_ROOT/outside-app"
ln -s "$TEST_ROOT/outside-app" "$TRANSACTION_ROOT/staging/Covio.app"
cat > "$TRANSACTION_ROOT/transaction.env" <<'EOF'
TRANSACTION_ID='update-valid'
UPDATE_MODE='automatic'
EXPECTED_RELEASE_ID='0.0.2.0-g2222222222222222222222222222222222222222'
EXPECTED_CLIENT_VERSION='0.0.2.0'
EXPECTED_PRODUCT_VERSION='0.6.0'
EXPECTED_BUILD_NUMBER='20'
EXPECTED_COMMIT='2222222222222222222222222222222222222222'
EXPECTED_PROTOCOL_VERSION='10'
EXPECTED_HELPER_SHA256='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
EXPECTED_UPDATER_SHA256='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
EXPECTED_UPDATER_LAUNCHER_SHA256='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
EXPECTED_PREVIOUS_RELEASE_ID='0.0.1.9-g1111111111111111111111111111111111111111'
EXPECTED_CHANNEL='internal'
EOF
if COVIO_TX_STATE_ROOT="$STATE_ROOT" COVIO_TX_TEST_MODE=1 \
  bash "$ROOT/installer/install-update.sh" "$TRANSACTION_ROOT" >/dev/null 2>&1
then
  fail "staged app symlink escape was accepted"
fi

printf 'update installer tests passed\n'

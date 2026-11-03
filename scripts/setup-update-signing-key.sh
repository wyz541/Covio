#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_ID="${1:-covio-internal-2026-01}"
SERVICE="${COVIO_UPDATE_KEYCHAIN_SERVICE:-com.wyz.covio.update-signing}"
SIGNER="$ROOT/build/update-signing/CovioUpdateSigner"
KEYS_FILE="$ROOT/release/update-public-keys.json"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/covio-update-key.XXXXXX")"
trap 'find "$TEMP_DIR" -depth -delete' EXIT
PRIVATE_KEY="$TEMP_DIR/private.json"
PUBLIC_KEY="$TEMP_DIR/public.json"

if /usr/bin/security find-generic-password -s "$SERVICE" -a "$KEY_ID" >/dev/null 2>&1; then
  printf 'Update signing key already exists: %s\n' "$KEY_ID" >&2
  exit 1
fi

if [[ ! -x "$SIGNER" ]]; then
  bash "$ROOT/scripts/build-update-signature-tool.sh"
fi
"$SIGNER" keygen \
  --key-id "$KEY_ID" \
  --private-key "$PRIVATE_KEY" \
  --public-key "$PUBLIC_KEY"
chmod 0600 "$PRIVATE_KEY"

/usr/bin/security add-generic-password \
  -U \
  -s "$SERVICE" \
  -a "$KEY_ID" \
  -T /usr/bin/security \
  -w "$(cat "$PRIVATE_KEY")" >/dev/null

python3 -I - "$KEYS_FILE" "$PUBLIC_KEY" <<'PY'
import json
import pathlib
import sys

keys_path = pathlib.Path(sys.argv[1])
public_path = pathlib.Path(sys.argv[2])
document = json.loads(keys_path.read_text(encoding="utf-8"))
public = json.loads(public_path.read_text(encoding="utf-8"))
if document.get("schemaVersion") != 1:
    raise SystemExit("update public key schemaVersion must be 1")
keys = document.get("keys")
if not isinstance(keys, list):
    raise SystemExit("update public keys must be an array")
key_id = public.get("keyId")
if not isinstance(key_id, str) or not key_id:
    raise SystemExit("generated public key ID is invalid")
if any(value.get("keyId") == key_id for value in keys if isinstance(value, dict)):
    raise SystemExit("update public key ID already exists")
keys.append({"keyId": key_id, "publicKey": public.get("publicKey")})
document["keys"] = sorted(keys, key=lambda value: value["keyId"])
keys_path.write_text(
    json.dumps(document, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY

python3 -I "$ROOT/scripts/generate-update-trust.py"
printf 'Stored update signing key in Keychain.\n'
printf '  Service: %s\n' "$SERVICE"
printf '  Account: %s\n' "$KEY_ID"
printf 'Updated %s\n' "$KEYS_FILE"

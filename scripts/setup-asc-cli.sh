#!/usr/bin/env bash
# Register App Store Connect API key with `asc` CLI from fastlane/.env values.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f fastlane/.env ]]; then
  echo "Missing fastlane/.env — run after copying fastlane/.env.example"
  exit 1
fi

# shellcheck disable=SC1091
source fastlane/.env

for var in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
  if [[ -z "${!var:-}" ]]; then
    echo "Set $var in fastlane/.env first."
    [[ "$var" == "ASC_ISSUER_ID" ]] && echo "  → App Store Connect → Users and Access → Integrations → API (Issuer ID at top)"
    exit 1
  fi
done

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "Key not found: $ASC_KEY_PATH"
  exit 1
fi

if ! command -v asc >/dev/null; then
  echo "Install asc: brew install asc"
  exit 1
fi

echo "Registering asc credentials (~/.asc/config.json)..."
asc auth login \
  --bypass-keychain \
  --name "calarm-asc" \
  --key-id "$ASC_KEY_ID" \
  --issuer-id "$ASC_ISSUER_ID" \
  --private-key "$ASC_KEY_PATH" \
  --network

echo
echo "Lookup CALarm app ID:"
asc apps list --bundle-id com.calarmapp.calarm --output table

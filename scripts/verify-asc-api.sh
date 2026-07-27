#!/usr/bin/env bash
# Verify App Store Connect API key (needs ASC_ISSUER_ID in fastlane/.env).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f fastlane/.env ]]; then
  echo "Missing fastlane/.env — copy from fastlane/.env.example"
  exit 1
fi

# shellcheck disable=SC1091
source fastlane/.env

missing=()
[[ -z "${ASC_KEY_ID:-}" ]] && missing+=("ASC_KEY_ID")
[[ -z "${ASC_ISSUER_ID:-}" ]] && missing+=("ASC_ISSUER_ID")
[[ -z "${ASC_KEY_PATH:-}" ]] && missing+=("ASC_KEY_PATH")
[[ -n "${ASC_KEY_PATH:-}" && ! -f "$ASC_KEY_PATH" ]] && missing+=("ASC_KEY_PATH file")

if ((${#missing[@]})); then
  echo "Fill in fastlane/.env:"
  printf '  - %s\n' "${missing[@]}"
  echo
  echo "Issuer ID: App Store Connect → Users and Access → Integrations → API (top of page)"
  exit 1
fi

echo "Testing API key against App Store Connect..."
if asc apps list --bundle-id com.calarmapp.calarm --limit 1 --output json >/dev/null 2>&1; then
  app_line=$(asc apps list --bundle-id com.calarmapp.calarm --output table 2>/dev/null | tail -n +4 | head -1)
  echo "API OK (asc) — $app_line"
  echo "ASC_APP_APPLE_ID=${ASC_APP_APPLE_ID:-6787163619} in fastlane/.env"
else
  echo "asc auth failed — run ./scripts/setup-asc-cli.sh"
  exit 1
fi

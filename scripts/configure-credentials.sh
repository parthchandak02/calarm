#!/usr/bin/env bash
# One-shot ASC credential setup. Updates fastlane/.env, registers asc, discovers app ID.
#
# Usage:
#   ./scripts/configure-credentials.sh <ISSUER_ID> [ASC_APP_APPLE_ID]
#
# Issuer ID: App Store Connect → Users and Access → Integrations → API (top of page)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/pipeline.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
load_app_config

ISSUER_ID="${1:-}"
APP_ID="${2:-}"

if [[ -z "$ISSUER_ID" ]]; then
  echo "Usage: $0 <ASC_ISSUER_ID> [ASC_APP_APPLE_ID]"
  echo ""
  echo "Get Issuer ID from:"
  echo "  https://appstoreconnect.apple.com/access/integrations/api"
  exit 1
fi

if [[ ! -f fastlane/.env ]]; then
  cp fastlane/.env.example fastlane/.env
fi

# Update or append ASC_ISSUER_ID
if grep -q '^ASC_ISSUER_ID=' fastlane/.env; then
  sed -i '' "s|^ASC_ISSUER_ID=.*|ASC_ISSUER_ID=${ISSUER_ID}|" fastlane/.env
else
  echo "ASC_ISSUER_ID=${ISSUER_ID}" >> fastlane/.env
fi

# Ensure key path/id if missing
if ! grep -q '^ASC_KEY_ID=' fastlane/.env || [[ -z "$(grep '^ASC_KEY_ID=' fastlane/.env | cut -d= -f2)" ]]; then
  if [[ -f "$HOME/Keys/AuthKey_XG7C686F45.p8" ]]; then
    sed -i '' 's|^ASC_KEY_ID=.*|ASC_KEY_ID=XG7C686F45|' fastlane/.env 2>/dev/null || echo "ASC_KEY_ID=XG7C686F45" >> fastlane/.env
    sed -i '' "s|^ASC_KEY_PATH=.*|ASC_KEY_PATH=$HOME/Keys/AuthKey_XG7C686F45.p8|" fastlane/.env 2>/dev/null || echo "ASC_KEY_PATH=$HOME/Keys/AuthKey_XG7C686F45.p8" >> fastlane/.env
  fi
fi

if [[ -n "$APP_ID" ]]; then
  if grep -q '^ASC_APP_APPLE_ID=' fastlane/.env; then
    sed -i '' "s|^ASC_APP_APPLE_ID=.*|ASC_APP_APPLE_ID=${APP_ID}|" fastlane/.env
  else
    echo "ASC_APP_APPLE_ID=${APP_ID}" >> fastlane/.env
  fi
fi

log_step "Register asc CLI"
"$SCRIPT_DIR/setup-asc-cli.sh"

log_step "Verify API + discover app ID"
# shellcheck disable=SC1091
source fastlane/.env

if [[ -z "${ASC_APP_APPLE_ID:-}" ]]; then
  discovered=$(asc apps list --bundle-id "$BUNDLE_ID" --output json 2>/dev/null | ruby -rjson -e '
    data = JSON.parse(STDIN.read) rescue nil
    apps = data.is_a?(Hash) ? (data["data"] || data["apps"] || []) : []
    id = apps.first.is_a?(Hash) ? (apps.first["id"] || apps.first.dig("attributes", "id")) : nil
    puts id if id
  ' 2>/dev/null || true)
  if [[ -n "$discovered" ]]; then
    sed -i '' "s|^ASC_APP_APPLE_ID=.*|ASC_APP_APPLE_ID=${discovered}|" fastlane/.env
    ok "Set ASC_APP_APPLE_ID=${discovered}"
  else
    warn "Could not auto-discover app ID — create app in ASC or run: bundle exec fastlane ios bootstrap_asc"
  fi
fi

log_step "Portal capabilities (Siri, etc.)"
"$SCRIPT_DIR/bootstrap-portal.sh" || true

log_step "Re-run doctor"
"$SCRIPT_DIR/ios-doctor.sh" || true

echo ""
echo "Credentials configured. If doctor still shows Siri blocker, enable Siri manually:"
echo "  https://developer.apple.com/account/resources/identifiers/list"
echo "  → ${BUNDLE_ID} → Capabilities → Siri → Save"

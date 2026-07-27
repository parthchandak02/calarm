#!/usr/bin/env bash
# Register bundle IDs and enable capabilities via asc (requires API key + Issuer ID).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/pipeline.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
load_app_config

if ! asc_env_ready; then
  warn "ASC credentials incomplete — skip portal bootstrap"
  exit 0
fi

asc_export_env

if ! asc apps list --limit 1 >/dev/null 2>&1; then
  warn "asc not authenticated — run ./scripts/setup-asc-cli.sh"
  exit 0
fi

log_step "Ensure bundle ID exists: ${BUNDLE_ID}"
if ! asc bundle-ids list --output json 2>/dev/null | ruby -rjson -e "
  data = JSON.parse(STDIN.read) rescue {}
  ids = (data['data'] || []).map { |r| r.dig('attributes', 'identifier') || r['identifier'] }
  exit(ids.include?(ENV['BID']) ? 0 : 1)
" BID="$BUNDLE_ID" 2>/dev/null; then
  asc bundle-ids create --identifier "$BUNDLE_ID" --name "$APP_DISPLAY_NAME" --platform IOS || warn "bundle-ids create failed (may already exist)"
fi

if [[ -n "${WIDGET_BUNDLE_ID:-}" ]]; then
  log_step "Ensure widget bundle ID: ${WIDGET_BUNDLE_ID}"
  if ! asc bundle-ids list --output json 2>/dev/null | ruby -rjson -e "
    data = JSON.parse(STDIN.read) rescue {}
    ids = (data['data'] || []).map { |r| r.dig('attributes', 'identifier') || r['identifier'] }
    exit(ids.include?(ENV['BID']) ? 0 : 1)
  " BID="$WIDGET_BUNDLE_ID" 2>/dev/null; then
    asc bundle-ids create --identifier "$WIDGET_BUNDLE_ID" --name "${APP_DISPLAY_NAME} Widget" --platform IOS || true
  fi
fi

if [[ -n "${REQUIRED_CAPABILITIES:-}" ]]; then
  IFS=',' read -ra CAPS <<< "$REQUIRED_CAPABILITIES"
  for cap in "${CAPS[@]}"; do
    cap="$(echo "$cap" | tr -d ' ')"
    [[ -z "$cap" ]] && continue
    log_step "Capability ${cap} on ${BUNDLE_ID}"
  if asc bundle-ids capabilities list --bundle "$BUNDLE_ID" --output json 2>/dev/null | ruby -rjson -e "
    data = JSON.parse(STDIN.read) rescue {}
    caps = (data['data'] || []).map { |r| r.dig('attributes', 'capabilityType') || r['capabilityType'] }
    exit(caps.map(&:upcase).include?(ENV['CAP'].upcase) ? 0 : 1)
  " CAP="$cap" 2>/dev/null; then
      ok "${cap} already enabled"
    else
        if asc bundle-ids capabilities add --bundle "$BUNDLE_ID" --capability "$cap" 2>/dev/null; then
        ok "Added ${cap}"
      else
        warn "Could not add ${cap} via API — enable manually in Developer portal"
      fi
    fi
  done
fi

ok "Portal bootstrap pass complete"

#!/usr/bin/env bash
# Add the latest uploaded build to Internal Testing so TestFlight updates immediately.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

if [[ -f fastlane/.env ]]; then
  # shellcheck disable=SC1091
  source fastlane/.env
fi

APP_ID="${ASC_APP_APPLE_ID:-}"
GROUP_ID="${ASC_INTERNAL_TESTING_GROUP_ID:-40b17ded-4450-44d4-8ac6-a046ced5a03e}"

if [[ -z "$APP_ID" ]]; then
  echo "WARN: ASC_APP_APPLE_ID not set — skip Internal Testing group assignment"
  exit 0
fi

if ! command -v asc >/dev/null 2>&1; then
  echo "WARN: asc CLI not installed — skip Internal Testing group assignment"
  exit 0
fi

echo "==> Adding latest build to Internal Testing group ($GROUP_ID)"
asc builds add-groups --app "$APP_ID" --latest --group "$GROUP_ID" --output table

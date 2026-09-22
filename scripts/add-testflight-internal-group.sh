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
GROUP_ID="${ASC_INTERNAL_TESTING_GROUP_ID:-<ASC_INTERNAL_TESTING_GROUP_ID>}"

if [[ -z "$APP_ID" ]]; then
  echo "WARN: ASC_APP_APPLE_ID not set — skip Internal Testing group assignment"
  exit 0
fi

if ! command -v asc >/dev/null 2>&1; then
  echo "WARN: asc CLI not installed — skip Internal Testing group assignment"
  exit 0
fi

# `--latest` resolves to the newest build App Store Connect has finished processing.
# Immediately after an upload that is still the *previous* build, so assigning without
# waiting silently re-adds an already-distributed build and leaves the new one stranded
# in READY_FOR_BETA_TESTING. Wait for the just-uploaded build to land first.
WANT_VERSION="${1:-}"
if [[ -z "$WANT_VERSION" ]]; then
  WANT_VERSION="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' Calarm.xcodeproj/project.pbxproj | head -n1)"
fi

if [[ -n "$WANT_VERSION" ]]; then
  echo "==> Waiting for build $WANT_VERSION to finish processing"
  for _ in $(seq 1 40); do
    if asc builds list --app "$APP_ID" --limit 1 --output json 2>/dev/null | grep -q "\"$WANT_VERSION\""; then
      echo "    build $WANT_VERSION is available"
      break
    fi
    sleep 15
  done
fi

echo "==> Adding latest build to Internal Testing group ($GROUP_ID)"
asc builds add-groups --app "$APP_ID" --latest --group "$GROUP_ID" --output table

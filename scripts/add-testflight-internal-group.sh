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
GROUP_ID="${ASC_INTERNAL_TESTING_GROUP_ID:-}"

if [[ -z "$GROUP_ID" ]]; then
  echo "ERROR: ASC_INTERNAL_TESTING_GROUP_ID not set in fastlane/.env (App Store Connect → TestFlight → Internal Testing → group URL)"
  exit 1
fi

if [[ -z "$APP_ID" ]]; then
  echo "WARN: ASC_APP_APPLE_ID not set — skip Internal Testing group assignment"
  exit 0
fi

if ! command -v asc >/dev/null 2>&1; then
  echo "WARN: asc CLI not installed — skip Internal Testing group assignment"
  exit 0
fi

# Assign the just-uploaded build by its own ID, never `--latest`. Right after an upload,
# "latest" is still the *previous* build: assigning it re-adds an already-distributed build
# and strands the new one in READY_FOR_BETA_TESTING. Apple's processing has taken hours, so
# wait up to 30 minutes, then fail loudly rather than guess.
export ASC_TIMEOUT="${ASC_TIMEOUT:-90s}"
WANT_VERSION="${1:-}"
if [[ -z "$WANT_VERSION" ]]; then
  WANT_VERSION="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' Calarm.xcodeproj/project.pbxproj | head -n1)"
fi

echo "==> Waiting for build $WANT_VERSION to finish processing"
BUILD_ID=""
for _ in $(seq 1 120); do
  BUILD_ID="$("$SCRIPT_DIR/asc-build-id.sh" "$WANT_VERSION" 2>/dev/null || true)"
  [[ -n "$BUILD_ID" ]] && break
  sleep 15
done
if [[ -z "$BUILD_ID" ]]; then
  echo "ERROR: build $WANT_VERSION is not VALID in App Store Connect after 30 minutes."
  echo "       Nothing was assigned. When Apple finishes processing, run:"
  echo "       ./scripts/add-testflight-internal-group.sh $WANT_VERSION"
  exit 1
fi

echo "==> Adding build $WANT_VERSION ($BUILD_ID) to Internal Testing group ($GROUP_ID)"
asc builds add-groups --build-id "$BUILD_ID" --group "$GROUP_ID" --output table

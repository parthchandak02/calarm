#!/usr/bin/env bash
# Prints the App Store Connect build ID for a CFBundleVersion once Apple has finished
# processing it (VALID). Exits non-zero if it is not there yet, or on an API error.
#
# App Store Connect drops leading zeros from each dotted part, so a build stamped
# 20260926.0204 is listed as 20260926.204. Compare the parts as numbers, never as strings:
# a string match never finds a build stamped before 10:00.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

want="${1:?usage: asc-build-id.sh <CFBundleVersion>}"
if [[ -z "${ASC_APP_APPLE_ID:-}" && -f "$ROOT/fastlane/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/fastlane/.env"
fi
app="${ASC_APP_APPLE_ID:?ASC_APP_APPLE_ID not set (fastlane/.env)}"
export ASC_TIMEOUT="${ASC_TIMEOUT:-90s}"

asc builds list --app "$app" --processing-state VALID --sort -uploadedDate --limit 20 --output json \
  | jq -er --arg v "$want" '
      ($v | split(".") | map(tonumber)) as $want
      | [.data[] | select((.attributes.version | split(".") | map(tonumber)) == $want)][0].id
      // empty'

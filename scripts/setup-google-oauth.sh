#!/usr/bin/env bash
# Wire Google Calendar sign-in into a local checkout. Run once per machine that builds
# CALarm, including macmini-remote, after placing the iOS OAuth client plist.
#
# The plist comes from Google Cloud console → Google Auth Platform → Clients → the iOS
# client for com.calarmapp.calarm (project useful-field-497119-k5) → Download plist.
#
#   ./scripts/setup-google-oauth.sh [path/to/client_….plist]
#
# Copies it to Calarm/GoogleService-Info.plist (gitignored) and writes
# Config/Google.local.xcconfig (gitignored), which Config/Calarm.xcconfig includes so
# Info.plist registers the sign-in callback URL scheme.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Calarm/GoogleService-Info.plist"
XCCONFIG="$ROOT/Config/Google.local.xcconfig"

if [[ $# -ge 1 ]]; then
  cp "$1" "$PLIST"
fi

if [[ ! -f "$PLIST" ]]; then
  echo "ERROR: $PLIST missing. Pass the downloaded client plist as the first argument." >&2
  exit 1
fi

read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }
CLIENT_ID="$(read_key CLIENT_ID)"
REVERSED="$(read_key REVERSED_CLIENT_ID)"
BUNDLE="$(read_key BUNDLE_ID)"

if [[ -z "$CLIENT_ID" || -z "$REVERSED" || "$CLIENT_ID" == REPLACE_* ]]; then
  echo "ERROR: $PLIST has no real CLIENT_ID / REVERSED_CLIENT_ID." >&2
  exit 1
fi
if [[ -n "$BUNDLE" && "$BUNDLE" != "com.calarmapp.calarm" ]]; then
  echo "ERROR: plist is for bundle $BUNDLE, not com.calarmapp.calarm." >&2
  exit 1
fi

printf 'GOOGLE_REVERSED_CLIENT_ID = %s\n' "$REVERSED" > "$XCCONFIG"
echo "ok Google sign-in configured (client ${CLIENT_ID%%-*}-…)"

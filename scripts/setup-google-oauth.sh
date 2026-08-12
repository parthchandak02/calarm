#!/usr/bin/env bash
# Configure Google Calendar OAuth for CALarm (Tier 1 device sync).
#
# Prerequisites:
#   - GCP project useful-field-497119-k5 (Calendar API already enabled)
#   - gcloud or Google Cloud Console access
#
# Steps:
#   1. Open https://console.cloud.google.com/apis/credentials?project=useful-field-497119-k5
#   2. Create Credentials → OAuth client ID → iOS
#   3. Bundle ID: com.calarmapp.calarm
#   4. Download plist OR copy CLIENT_ID + REVERSED_CLIENT_ID into Calarm/GoogleService-Info.plist
#   5. Add REVERSED_CLIENT_ID to Info.plist CFBundleURLTypes (see below)
#   6. OAuth consent screen → add test users for TestFlight/dev builds
#
# Copy the example plist:
#   cp Calarm/GoogleService-Info.plist.example Calarm/GoogleService-Info.plist
#   # edit CLIENT_ID and REVERSED_CLIENT_ID
#
# Add URL scheme to Info.plist under CFBundleURLTypes:
#   <string>YOUR_REVERSED_CLIENT_ID</string>
#
# Validate with gws (dev machine):
#   gws auth login
#   gws calendar +agenda --days 3
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Calarm/GoogleService-Info.plist"
EXAMPLE="$ROOT/Calarm/GoogleService-Info.plist.example"

if [[ ! -f "$PLIST" ]]; then
  cp "$EXAMPLE" "$PLIST"
  echo "Created $PLIST — edit CLIENT_ID and REVERSED_CLIENT_ID before building."
else
  echo "Found $PLIST"
fi

if command -v gws >/dev/null 2>&1; then
  echo ""
  echo "GWS auth status:"
  gws auth status 2>&1 | head -20 || true
fi

echo ""
echo "Next: add iOS OAuth client in GCP Console, update GoogleService-Info.plist, add URL scheme to Info.plist."

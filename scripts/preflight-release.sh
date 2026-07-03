#!/usr/bin/env bash
# Preflight checks before App Store / TestFlight upload.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

fail=0

check() {
  if eval "$2" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} $1"
  else
    echo -e "${RED}✗${NC} $1"
    fail=1
  fi
}

warn() {
  echo -e "${YELLOW}!${NC} $1"
}

echo "CALarm release preflight"
echo "========================"

check "Xcode selected" "xcodebuild -version"
check "Bundler available" "bundle --version"
check "fastlane/.env exists" "test -f fastlane/.env"

if [[ -f fastlane/.env ]]; then
  # shellcheck disable=SC1091
  source fastlane/.env
  check "ASC_KEY_ID set" "test -n \"${ASC_KEY_ID:-}\""
  check "ASC_ISSUER_ID set" "test -n \"${ASC_ISSUER_ID:-}\""
  check "ASC_KEY_PATH or ASC_KEY_CONTENT set" "test -n \"${ASC_KEY_PATH:-}\" || test -n \"${ASC_KEY_CONTENT:-}\""
  if [[ -n "${ASC_KEY_PATH:-}" ]]; then
    check "ASC_KEY_PATH file exists" "test -f \"$ASC_KEY_PATH\""
  fi
  if [[ -z "${ASC_APP_APPLE_ID:-}" ]]; then
    warn "ASC_APP_APPLE_ID not set — create app in ASC first or run: bundle exec fastlane ios bootstrap_asc"
  else
    check "ASC_APP_APPLE_ID set" "test -n \"$ASC_APP_APPLE_ID\""
  fi
else
  warn "Copy fastlane/.env.example → fastlane/.env and fill in API key values"
  fail=1
fi

check "ExportOptions.plist exists (local)" "test -f ExportOptions.plist"
if [[ ! -f ExportOptions.plist ]]; then
  warn "Copy ExportOptions.plist.example → ExportOptions.plist and set your team ID"
fi

check "Privacy manifest present" "test -f Calarm/PrivacyInfo.xcprivacy"
check "ITSAppUsesNonExemptEncryption in Info.plist" "grep -q ITSAppUsesNonExemptEncryption Calarm/Info.plist"

privacy_url="$(tr -d '[:space:]' < fastlane/metadata/en-US/privacy_url.txt)"
support_url="$(tr -d '[:space:]' < fastlane/metadata/en-US/support_url.txt)"
if [[ "$privacy_url" == *example.com* ]]; then
  warn "privacy_url.txt still uses example.com — enable GitHub Pages and verify URL"
fi
if [[ "$support_url" == *example.com* ]]; then
  warn "support_url.txt still uses example.com — enable GitHub Pages and verify URL"
fi

screenshot_count=$(find fastlane/screenshots/en-US -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$screenshot_count" -lt 1 ]]; then
  warn "No screenshots in fastlane/screenshots/en-US/ — required before App Store submit (TestFlight OK without)"
else
  echo -e "${GREEN}✓${NC} $screenshot_count screenshot(s) found"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo -e "${GREEN}Preflight passed.${NC} Next: ./release.sh or bundle exec fastlane ios upload_beta"
else
  echo -e "${RED}Preflight failed.${NC} Fix items above before uploading."
  exit 1
fi

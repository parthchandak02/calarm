#!/usr/bin/env bash
# Full pipeline health check — tools, credentials, signing, ASC connectivity.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/pipeline.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
load_app_config
load_asc_env
ensure_path_local_bin

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
fail_count=0
warn_count=0

check() {
  if eval "$2" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} $1"
  else
    echo -e "${RED}✗${NC} $1"
    fail_count=$((fail_count + 1))
  fi
}

warn_item() {
  echo -e "${YELLOW}!${NC} $1"
  warn_count=$((warn_count + 1))
}

echo "iOS Release Pipeline — Doctor"
echo "App: ${APP_DISPLAY_NAME} (${BUNDLE_ID})"
echo "=============================="

check "ios-app.config.sh" "test -f ios-app.config.sh"
check "Xcode" "xcodebuild -version"
check "Bundler" "bundle --version"
check "fastlane (bundle)" "bundle exec fastlane --version"
check "asc CLI" "command -v asc"
check "apple-docs-pp-cli" "command -v apple-docs-pp-cli"
check "ExportOptions.plist" "test -f ExportOptions.plist"
check "Privacy manifest" "test -f Calarm/PrivacyInfo.xcprivacy"
check "fastlane/.env exists" "test -f fastlane/.env"

if [[ -f fastlane/.env ]]; then
  check "ASC_KEY_ID" "test -n \"${ASC_KEY_ID:-}\""
  check "ASC_ISSUER_ID" "test -n \"${ASC_ISSUER_ID:-}\""
  check "ASC_KEY_PATH file" "test -f \"${ASC_KEY_PATH:-/missing}\""
  if [[ -n "${ASC_APP_APPLE_ID:-}" ]]; then
    check "ASC_APP_APPLE_ID" "test -n \"${ASC_APP_APPLE_ID}\""
  else
    warn_item "ASC_APP_APPLE_ID not set — run ./scripts/configure-credentials.sh after Issuer ID"
  fi
else
  warn_item "Copy fastlane/.env.example → fastlane/.env"
fi

if asc_env_ready && command -v asc >/dev/null; then
  asc_export_env
  if asc auth doctor >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} asc API authentication"
  else
  if asc apps list --limit 1 >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} asc API reachable"
  else
    warn_item "asc not authenticated — run ./scripts/setup-asc-cli.sh"
  fi
  fi
fi

echo ""
echo "Signing / build probe (Release)..."
if xcodebuild -project "$XCODE_PROJECT" -scheme "$XCODE_SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build 2>&1 | tee /tmp/calarm-doctor-build.log | tail -3 | grep -q "BUILD SUCCEEDED"; then
  echo -e "${GREEN}✓${NC} Release build succeeds"
else
  if grep -q "Siri capability" /tmp/calarm-doctor-build.log 2>/dev/null; then
    echo -e "${RED}✗${NC} Release build — Siri capability missing on App ID"
    echo "    Fix: enable Siri on ${BUNDLE_ID} in Developer portal"
    echo "    Or (with asc auth): ./scripts/bootstrap-portal.sh"
    fail_count=$((fail_count + 1))
  else
    echo -e "${RED}✗${NC} Release build failed — see /tmp/calarm-doctor-build.log"
    fail_count=$((fail_count + 1))
  fi
fi

screenshots=$(find fastlane/screenshots/en-US -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$screenshots" -ge 1 ]]; then
  echo -e "${GREEN}✓${NC} $screenshots screenshot(s) in fastlane/screenshots/en-US/"
else
  warn_item "No screenshots — ./scripts/generate-app-store-screenshots.sh"
fi

echo ""
if [[ $fail_count -eq 0 ]]; then
  echo -e "${GREEN}Doctor: ready to ship${NC} (warnings: $warn_count)"
  echo "Next: ./scripts/ship.sh beta"
else
  echo -e "${RED}Doctor: $fail_count blocker(s), $warn_count warning(s)${NC}"
  exit 1
fi

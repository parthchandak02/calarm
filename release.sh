#!/bin/bash
# Calarm — Release archive + App Store IPA export
# Does NOT upload. Run fastlane ios upload_beta after configuring fastlane/.env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT="Calarm.xcodeproj"
SCHEME="Calarm"
ARCHIVE_PATH="build/Calarm.xcarchive"
EXPORT_PATH="build/export"
EXPORT_OPTIONS="ExportOptions.plist"

echo "==> Cleaning prior release artifacts"
rm -rf build/Calarm.xcarchive build/export

echo "==> Archiving Release (generic iOS device)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo "==> Exporting App Store IPA"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

IPA=$(find "$EXPORT_PATH" -name "*.ipa" | head -n1)
if [[ -z "${IPA:-}" ]]; then
  echo "ERROR: No IPA found in $EXPORT_PATH"
  exit 1
fi

echo ""
echo "Success: $IPA"
echo ""
echo "Next steps:"
echo "  1. cp fastlane/.env.example fastlane/.env  # add ASC API key"
echo "  2. bundle install"
echo "  3. bundle exec fastlane ios upload_beta    # TestFlight"
echo ""
echo "Or validate/upload with Apple tools:"
echo "  xcrun altool --validate-app -f \"$IPA\" -t ios --apiKey \"\$ASC_KEY_ID\" --apiIssuer \"\$ASC_ISSUER_ID\""

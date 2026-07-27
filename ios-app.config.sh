# Per-app constants for the iOS release pipeline.
# Copy ios-app.config.sh.example → ios-app.config.sh when bootstrapping a new app.

APP_DISPLAY_NAME="CALarm"
APP_ASC_NAME="CALarm – Calendar Alarms"
BUNDLE_ID="com.calarmapp.calarm"
WIDGET_BUNDLE_ID="com.calarmapp.calarm.CalarmWidgetExtension"
UITESTS_BUNDLE_ID="com.calarmapp.calarm.UITests"

TEAM_ID="M49XY93NTP"
ASC_SKU="calarm-ios-001"
ASC_WIDGET_SKU="calarm-widget-001"

XCODE_PROJECT="Calarm.xcodeproj"
XCODE_SCHEME="Calarm"
IPA_NAME="Calarm.ipa"
ARCHIVE_NAME="Calarm.xcarchive"

# Capabilities required on the main App ID (portal / asc bundle-ids capabilities add)
REQUIRED_CAPABILITIES="SIRIKIT"

# GitHub Pages base (privacy/support URLs)
MARKETING_URL="https://parthchandak02.github.io/calarm/"
PRIVACY_URL="https://parthchandak02.github.io/calarm/privacy.html"
SUPPORT_URL="https://parthchandak02.github.io/calarm/support.html"

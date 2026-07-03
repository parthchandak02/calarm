# Calarm — App Store submission checklist

Last updated: 2026-06-30. Use with the `calarm-app-store-prep` subagent.

## Agent-completed (repo)

- [x] **Privacy manifest** — `Calarm/PrivacyInfo.xcprivacy` (UserDefaults CA92.1, calendar data collection, no tracking)
- [x] **Info.plist cleanup** — removed unused `UIBackgroundModes` and `BGTaskSchedulerPermittedIdentifiers` (no BGTask handlers in code)
- [x] **Permission strings** — accurate AlarmKit + calendar usage descriptions
- [x] **Export options** — `ExportOptions.plist` (`app-store-connect`, your team ID)
- [x] **Release script** — `release.sh` (Archive Release + export IPA)
- [x] **fastlane scaffold** — `Fastfile`, `Appfile`, `metadata/en-US/*`, `.env.example`
- [x] **Gemfile** — fastlane via Bundler
- [x] **Subagent** — `.cursor/agents/calarm-app-store-prep.md`
- [x] **Privacy policy outline** — `docs/app-store/PRIVACY_POLICY_OUTLINE.md`
- [x] **App icon** — 1024×1024 in `AppIcon.appiconset` (verify design before submit)

- [x] **App Intents wired** — stop/pause/resume call `AlarmManager`; snooze removed
- [x] **Widget scaffolds removed** — only Live Activity ships; emoji widget + timer control removed
- [x] **Calendar auth UX** — denied state opens Settings; refresh on foreground
- [x] **Dead code removed** — `ContentView`, timeline views, unused entitlements
- [x] **Info.plist trimmed** — no stale `NSUserActivityTypes`, `armv7`, or unimplemented capability flags
- [x] **Deploy script fixed** — device builds use `iphoneos` SDK; Wi-Fi devicectl install
- [ ] **App Store distribution signing** — archive currently uses *Apple Development*; for upload you need *Apple Distribution* / App Store profile (Xcode → Signing, or create app in ASC first)

## Human-only (you must do these)

### Account & App Store Connect

- [ ] **Apple Developer Program** — active paid membership ($99/yr) on your team
- [ ] **Create app record** — [App Store Connect](https://appstoreconnect.apple.com) → Apps → + → New App
  - Platform: iOS
  - Name: Calarm (or your chosen store name)
  - Primary language: English (U.S.)
  - Bundle ID: `pchandak.calarm` (register in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) if needed)
  - SKU: e.g. `calarm-ios-001`
- [ ] **Note numeric Apple ID** — shown in App URL; set as `ASC_APP_APPLE_ID` in `fastlane/.env`

### API key & signing

- [ ] **App Store Connect API key** — Users and Access → Integrations → App Store Connect API → Generate
  - Role: App Manager or Admin
  - Download `.p8` once → save outside repo
  - Copy Key ID + Issuer ID → `fastlane/.env` (from `fastlane/.env.example`)
- [ ] **Distribution signing** — Xcode → Calarm target → Signing & Capabilities → your Team, Automatic signing, Release uses Distribution profile
  - Optional: `fastlane match appstore` for team/CI signing (not configured yet)

### Legal & privacy URLs

- [ ] **Host privacy policy** — publish `docs/app-store/PRIVACY_POLICY_OUTLINE.md` as a public URL
- [ ] **Update metadata URLs** — replace placeholders in:
  - `fastlane/metadata/en-US/privacy_url.txt`
  - `fastlane/metadata/en-US/support_url.txt`
- [ ] **App Privacy questionnaire** — App Store Connect → App Privacy; answers must match `PrivacyInfo.xcprivacy`:
  - Data collected: Calendars — App Functionality — Not linked — Not used for tracking
  - No tracking

### Store listing assets

- [ ] **Screenshots** (required) — minimum iPhone 6.7" and 6.5" sets; capture on iOS 26 simulator or device
  - Suggested scenes: week schedule, event detail + alarm picker, settings/themes, Live Activity / Dynamic Island
  - Place in `fastlane/screenshots/en-US/` or upload in App Store Connect
- [ ] **Optional App Preview** — short screen recording
- [ ] **Review notes** — mention iOS 26 + AlarmKit requirement; calendar stays on-device; no login

### Build & upload

- [ ] **Bump version/build** if re-submitting — Xcode or `bundle exec fastlane ios bump_build`
- [ ] **Release archive** — `./release.sh` (or `bundle exec fastlane ios build_release`)
  - *Export step fails with "Error Downloading App Information" until the app record exists in App Store Connect*
- [ ] **TestFlight first** (recommended):
  ```bash
  cp fastlane/.env.example fastlane/.env   # fill in keys
  bundle install
  bundle exec fastlane ios upload_beta
  ```
- [ ] **Install TestFlight build** on your iPhone — verify calendar permission, alarms, Live Activities
- [ ] **Upload metadata** — `bundle exec fastlane ios upload_metadata` (after URLs are real)

### Submission

- [ ] **Select build** in App Store Connect → version → Build
- [ ] **Age rating** questionnaire
- [ ] **Export compliance** — typically "No" for standard HTTPS only; Calarm uses no custom encryption beyond Apple OS
- [ ] **Content rights** — confirm you own rights to app name/icon
- [ ] **Submit for Review** — or `bundle exec fastlane ios release submit:true` after screenshots are uploaded
- [ ] **Respond to App Review** if rejected

## Quick command reference

| Step | Command |
|------|---------|
| Archive + IPA | `./release.sh` |
| TestFlight upload | `bundle exec fastlane ios upload_beta` |
| Metadata only | `bundle exec fastlane ios upload_metadata` |
| Precheck metadata | `bundle exec fastlane ios precheck_metadata` |
| Full release | `bundle exec fastlane ios release submit:true` |

## Known review considerations

- **iOS 26 only** — limits audience; state clearly in description and review notes.
- **Calendar permission** — required for core functionality; app should show access prompt before empty state.
- **AlarmKit permission** — user must allow alarms in Settings if denied.
- **No background modes** — calendar refresh is in-app via `EKEventStoreChanged`; accurate and review-friendly.

## When ready

Say: **"Use the calarm-app-store-prep subagent to run a final preflight and upload to TestFlight."**

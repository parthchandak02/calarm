# CALarm — App Store publish playbook

Last updated: 2026-06-30. Read this end-to-end before your first upload.

This repo is **terminal-first** after a short one-time human setup. Everything after that is `./scripts/preflight-release.sh` → `./release.sh` → `bundle exec fastlane ios upload_beta`.

---

## What is already done (agent/repo)

| Item | Location |
|------|----------|
| Privacy manifest | `Calarm/PrivacyInfo.xcprivacy` |
| Permission strings + export compliance | `Calarm/Info.plist` |
| Release archive script | `release.sh` |
| fastlane lanes (build, TestFlight, metadata, submit) | `fastlane/Fastfile` |
| App metadata drafts | `fastlane/metadata/en-US/*` |
| Review notes for App Review | `fastlane/metadata/review_information/notes.txt` |
| Privacy + support pages (GitHub Pages ready) | `docs/privacy.html`, `docs/support.html` |
| Preflight + screenshot helpers | `scripts/preflight-release.sh`, `scripts/capture-screenshots.sh` |
| Bootstrap lane (create ASC app) | `bundle exec fastlane ios bootstrap_asc` |

---

## Phase 0 — Human only (one time, ~20–30 min)

### 0.1 Apple Developer Program
- Confirm **paid membership** is active on team `M49XY93NTP`.
- [developer.apple.com/account](https://developer.apple.com/account)

### 0.2 App Store Connect API key
1. [App Store Connect → Users and Access → Integrations → API](https://appstoreconnect.apple.com/access/integrations/api)
2. **+** → name e.g. `calarm-ci` → role **App Manager** (Admin if you want CLI bundle-ID registration via `asc`)
3. Download `.p8` **once** — store outside the repo (e.g. `~/Keys/AuthKey_XXXXX.p8`)
4. Copy Key ID + Issuer ID

```bash
cp fastlane/.env.example fastlane/.env
# Edit fastlane/.env:
#   APPLE_ID=your@email.com
#   ASC_KEY_ID=...
#   ASC_ISSUER_ID=...
#   ASC_KEY_PATH=/path/to/AuthKey_XXXXX.p8
```

### 0.3 Create the App Store Connect app record

**Option A — Terminal (Apple ID + 2FA, ~2 min)**

```bash
bundle install
bundle exec fastlane ios bootstrap_asc
```

This creates:
- `pchandak.calarm` (main app in ASC)
- `pchandak.calarm.CalarmWidgetExtension` (portal only)

Copy the printed numeric ID into `ASC_APP_APPLE_ID` in `fastlane/.env`.

**Option B — Browser (~2 min)** if `produce` fails (name taken, 2FA issues):

1. [App Store Connect → Apps → +](https://appstoreconnect.apple.com/apps)
2. Platform: iOS · Name: **CALarm** · Language: English (U.S.)
3. Bundle ID: `pchandak.calarm` · SKU: `calarm-ios-001`
4. Note the numeric Apple ID from the URL → `ASC_APP_APPLE_ID`

Register widget bundle ID in [Identifiers](https://developer.apple.com/account/resources/identifiers/list) if missing: `pchandak.calarm.CalarmWidgetExtension`.

### 0.4 Host privacy + support URLs

**GitHub Pages is enabled** on this repo (`main` → `/docs`).

- Privacy: https://parthchandak02.github.io/calarm/privacy.html
- Support: https://parthchandak02.github.io/calarm/support.html
- Landing: https://parthchandak02.github.io/calarm/

After pushing doc changes, wait 1–2 minutes for Pages to rebuild.

### 0.5 App Store Connect questionnaires (browser only)

In the CALarm app record:

1. **App Privacy** — must match `PrivacyInfo.xcprivacy`:
   - Data collected: **Calendars** · Not linked · Not used for tracking · App Functionality
   - Tracking: **No**
2. **Age rating** — complete the iOS 26 questionnaire (no mature content).
3. **Pricing** — Free (unless you add IAP later).

---

## Phase 1 — Signing (human, first time only)

Xcode → `Calarm.xcodeproj` → **Calarm** target → Signing & Capabilities:

- Team: your team
- **Automatically manage signing**: on
- Repeat for **CalarmWidgetExtension**

For Release/App Store upload, Xcode must create an **Apple Distribution** profile. If archive fails:

```bash
open Calarm.xcodeproj
# Product → Archive (once) to let Xcode resolve Distribution signing
```

Copy local export plist if missing:

```bash
cp ExportOptions.plist.example ExportOptions.plist
# Set teamID to your team (already M49XY93NTP in project)
```

---

## Phase 2 — Build + TestFlight (mostly terminal)

```bash
./scripts/preflight-release.sh
./release.sh
# or: bundle exec fastlane ios build_release

bundle exec fastlane ios upload_beta
```

**Validate without fastlane (optional):**

```bash
xcrun altool --validate-app -f build/export/Calarm.ipa -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

Install the TestFlight build on your iPhone. Verify:

- [ ] Calendar permission prompt
- [ ] Week schedule loads
- [ ] Multiple alarms per event
- [ ] Snooze in settings
- [ ] Live Activity / Dynamic Island for next alarm

---

## Phase 3 — Screenshots (automated, ~1 min)

See **[docs/app-store/SCREENSHOTS.md](SCREENSHOTS.md)** for full details.

```bash
./scripts/generate-app-store-screenshots.sh
```

Uses simulator + fictional demo data (`SCREENSHOT_MODE`) — no personal calendar content.

Upload metadata + screenshots:

```bash
bundle exec fastlane ios upload_metadata screenshots:true
```

---

## Phase 4 — Submit for review

```bash
bundle exec fastlane ios precheck_metadata
bundle exec fastlane ios release submit:true screenshots:true
```

Or in App Store Connect: select the TestFlight build → **Submit for Review**.

**Export compliance:** `ITSAppUsesNonExemptEncryption = false` is set in Info.plist — answer **No** to custom encryption in ASC if asked.

---

## Command cheat sheet

| Step | Command |
|------|---------|
| Preflight | `./scripts/preflight-release.sh` |
| Create ASC app | `bundle exec fastlane ios bootstrap_asc` |
| Archive + IPA | `./release.sh` |
| TestFlight | `bundle exec fastlane ios upload_beta` |
| Metadata | `bundle exec fastlane ios upload_metadata` |
| Metadata + screenshots | `bundle exec fastlane ios upload_metadata screenshots:true` |
| Precheck | `bundle exec fastlane ios precheck_metadata` |
| Submit | `bundle exec fastlane ios release submit:true screenshots:true` |
| Bump build | `bundle exec fastlane ios bump_build` |

---

## What cannot be automated (honest list)

| Task | Why |
|------|-----|
| Pay Apple Developer fee | Account holder |
| Download `.p8` API key | One-time, Apple UI |
| `bootstrap_asc` / create app | Apple ID 2FA or ASC UI (public API cannot create apps) |
| App Privacy questionnaire | No public API |
| Age rating (first time) | ASC UI wizard |
| Enable GitHub Pages | GitHub repo settings |
| Screenshots | **Automated** — `./scripts/generate-app-store-screenshots.sh` |
| First Distribution signing | Often needs Xcode GUI once |
| Respond to App Review | Human if rejected |

---

## iOS 26 / AlarmKit review notes

- Deployment target is **iOS 26.0** — state this in description and review notes (already in `review_information/notes.txt`).
- Reviewers need iOS 26 simulator or device.
- No login, no server — calendar stays on device.
- AlarmKit permission must degrade gracefully if denied.

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| Export “Error Downloading App Information” | App record does not exist in ASC yet — run `bootstrap_asc` or create in browser |
| Signing / Distribution failed | Xcode Signing & Capabilities → Team, then Archive once |
| `produce` name taken | Pick alternate ASC name (metadata name can differ slightly) |
| Privacy URL invalid | Enable GitHub Pages on `/docs`; URL must return 200 |
| Upload 401 | Check `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` in `fastlane/.env` |

---

## When you're ready

1. Complete **Phase 0** (API key, app record, GitHub Pages, questionnaires).
2. Run `./scripts/preflight-release.sh` — should pass.
3. Say: **“Upload CALarm to TestFlight”** and we can run the upload lane together.

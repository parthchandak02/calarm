# CALarm — App Store submission checklist

Last updated: 2026-06-30. **Start here:** [docs/app-store/PUBLISH_PLAYBOOK.md](docs/app-store/PUBLISH_PLAYBOOK.md)

## Agent-completed (repo)

- [x] **Privacy manifest** — `Calarm/PrivacyInfo.xcprivacy`
- [x] **Export compliance** — `ITSAppUsesNonExemptEncryption` = false in `Calarm/Info.plist`
- [x] **Permission strings** — AlarmKit + calendar usage descriptions
- [x] **Widget scaffolds removed** — only Live Activity extension ships
- [x] **Release script** — `release.sh` (Archive Release + export IPA)
- [x] **Export options example** — `ExportOptions.plist.example` (copy to `ExportOptions.plist` locally)
- [x] **fastlane** — `Fastfile`, `Deliverfile`, `Appfile`, `metadata/en-US/*`, review notes
- [x] **Bootstrap lane** — `bundle exec fastlane ios bootstrap_asc`
- [x] **Privacy + support pages** — `docs/privacy.html`, `docs/support.html` (GitHub Pages)
- [x] **Screenshot automation** — `SCREENSHOT_MODE` + `./scripts/generate-app-store-screenshots.sh` (see `docs/app-store/SCREENSHOTS.md`)
- [x] **GitHub Pages** — enabled (`main` → `/docs`); landing + privacy + support
- [x] **App Store screenshots (6.9")** — four PNGs in `fastlane/screenshots/en-US/`
- [x] **Publish playbook** — `docs/app-store/PUBLISH_PLAYBOOK.md`
- [x] **App icon** — 1024×1024 in `AppIcon.appiconset`

## Human-only (you must do these)

### One-time setup

- [ ] **Apple Developer Program** — active paid membership
- [ ] **API key** — create in ASC, save `.p8` outside repo, fill `fastlane/.env`
- [ ] **Create app record** — `bundle exec fastlane ios bootstrap_asc` OR App Store Connect UI
- [ ] **Set `ASC_APP_APPLE_ID`** in `fastlane/.env`
- [ ] **Verify GitHub Pages URLs** — https://parthchandak02.github.io/calarm/privacy.html (after deploy)
- [ ] **App Privacy questionnaire** — ASC (match `PrivacyInfo.xcprivacy`)
- [ ] **Age rating** — ASC questionnaire
- [ ] **Distribution signing** — Xcode Release archive once if export fails

### Per release

- [ ] **Regenerate screenshots** (if UI changed) — `./scripts/generate-app-store-screenshots.sh`
- [ ] **TestFlight QA** on physical iPhone
- [ ] **Submit for Review** — `bundle exec fastlane ios release submit:true screenshots:true`

## Quick commands

```bash
./scripts/preflight-release.sh
bundle exec fastlane ios bootstrap_asc      # first time only
./release.sh
bundle exec fastlane ios upload_beta
bundle exec fastlane ios upload_metadata screenshots:true
bundle exec fastlane ios release submit:true screenshots:true
```

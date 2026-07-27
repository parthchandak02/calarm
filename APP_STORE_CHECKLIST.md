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
- [x] **Ship pipeline** — `scripts/ship.sh`, `scripts/ios-doctor.sh`, `ios-app.config.sh`
- [x] **Multi-app bootstrap** — `pipeline/install-into-repo.sh`, `pipeline/BOOTSTRAP_NEW_APP.md`
- [x] **API key on disk** — `~/Keys/AuthKey_XG7C686F45.p8`, `fastlane/.env` (partial)
- [x] **asc + apple-docs CLIs** — installed (`brew install asc`, Printing Press)
- [x] **App icon** — 1024×1024 in `AppIcon.appiconset`

## Human-only (you must do these)

### One-time setup

- [ ] **Issuer ID in `fastlane/.env`** — run `./scripts/configure-credentials.sh <ISSUER_ID>` ([YOUR_ACTIONS.md](docs/app-store/YOUR_ACTIONS.md))
- [ ] **Siri capability** on `com.calarmapp.calarm` — portal or `./scripts/bootstrap-portal.sh`
- [ ] **Apple Developer Program** — active paid membership
- [x] **API key `.p8`** — `~/Keys/AuthKey_XG7C686F45.p8`
- [ ] **Set `ASC_APP_APPLE_ID`** — auto-filled by `configure-credentials.sh` or ASC URL
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
./scripts/configure-credentials.sh <ISSUER_ID>   # one-time after API key
./scripts/ship.sh doctor
./scripts/ship.sh beta                           # TestFlight
./scripts/ship.sh metadata
./scripts/ship.sh all
```

Legacy / granular:

```bash
./scripts/preflight-release.sh
bundle exec fastlane ios bootstrap_asc      # first time only
./release.sh
bundle exec fastlane ios upload_beta
bundle exec fastlane ios upload_metadata screenshots:true
bundle exec fastlane ios release submit:true screenshots:true
```

**New app?** See [pipeline/BOOTSTRAP_NEW_APP.md](pipeline/BOOTSTRAP_NEW_APP.md).

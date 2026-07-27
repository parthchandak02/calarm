# CALarm — terminal tools for Apple development

Three layers: **ship to App Store** (asc + fastlane), **Developer Portal cleanup** (spaceship), **framework docs** (apple-docs).

---

## Installed on this machine

| Tool | Install | Purpose |
|------|---------|---------|
| **asc** | `brew install asc` | App Store Connect API — apps, builds, TestFlight, metadata, signing |
| **apple-docs-pp-cli** | `npx -y @mvanhorn/printing-press-library install apple-docs` | Offline Apple framework docs (AlarmKit, App Intents, WidgetKit) |
| **fastlane** | `bundle install` in repo | Build/upload lanes already wired in `fastlane/Fastfile` |
| **spaceship** | via `bundle exec fastlane` | Developer Portal — delete stale App IDs (`scripts/cleanup-developer-identifiers.rb`) |

`apple-docs-pp-cli` is **documentation only** — it does not manage App Store Connect or certificates.

---

## One-time setup (after `fastlane/.env` has Issuer ID)

```bash
cd /Users/parthchandak/calarm

# 1. asc CLI auth (reads fastlane/.env)
./scripts/setup-asc-cli.sh

# 2. Verify fastlane API key
./scripts/verify-asc-api.sh

# 3. Find numeric app ID for .env
asc apps list --bundle-id com.calarmapp.calarm --output table
# → set ASC_APP_APPLE_ID in fastlane/.env
```

Ensure `~/.local/bin` is on your PATH for `apple-docs-pp-cli`:

```bash
export PATH="$HOME/.local/bin:$PATH"   # add to ~/.zshrc if missing
```

---

## What each tool is best for

### asc — App Store Connect (primary for shipping)

```bash
asc apps list --bundle-id com.calarmapp.calarm
asc builds list --app "$ASC_APP_APPLE_ID"
asc testflight builds list --app "$ASC_APP_APPLE_ID"
asc capabilities --area release --output table   # what ASC API supports vs web-only
```

Full publish flow (alternative to fastlane):

```bash
asc publish app --app "$ASC_APP_APPLE_ID" --ipa build/export/Calarm.ipa --version "1.0.0"
```

Metadata, copyright, review contact — see `asc versions`, `asc localizations`, `asc review`.

Skills for agents: `asc install-skills` or [app-store-connect-cli-skills](https://github.com/rorkai/app-store-connect-cli-skills).

### fastlane — already configured in this repo

```bash
./scripts/preflight-release.sh
bundle exec fastlane ios upload_beta      # TestFlight
bundle exec fastlane ios upload_metadata  # metadata from fastlane/metadata/
```

Uses the same `ASC_*` vars in `fastlane/.env`.

### apple-docs-pp-cli — framework reference (CALarm-specific)

```bash
apple-docs-pp-cli doc get alarmkit --shape min --agent
apple-docs-pp-cli doc get 'appintents/app-intent' --shape signature --agent
apple-docs-pp-cli grep LiveActivity --framework widgetkit --json
apple-docs-pp-cli deprecation-cliff --os iOS --version 26 --framework alarmkit --agent
```

Optional MCP for Cursor/Claude: install full package (not `--cli-only`):

```bash
npx -y @mvanhorn/printing-press-library install apple-docs
```

### spaceship — Developer Portal (not App Store Connect)

```bash
bundle exec ruby scripts/cleanup-developer-identifiers.rb plan
```

Apple ID + 2FA required. For deleting old `pchandak.*` / `XC*` App IDs.

---

## What Apple still has no good CLI for

| Task | Tool |
|------|------|
| Delete App IDs | spaceship (Ruby) or developer.apple.com |
| Enable Siri capability on App ID | developer.apple.com (or asc if Admin + supported) |
| App Privacy nutrition labels | App Store Connect **web UI only** |
| IPA binary upload | `fastlane`, `xcrun altool`, or Transporter |

---

## Recommended workflow for CALarm right now

1. Fill `ASC_ISSUER_ID` in `fastlane/.env`
2. `./scripts/setup-asc-cli.sh` → copy app ID into `ASC_APP_APPLE_ID`
3. Enable **Siri** on `com.calarmapp.calarm` in Developer portal
4. `bundle exec fastlane ios upload_beta`
5. Browser: attach build, App Privacy, Age Rating, Submit

Docs: [PUBLISH_PLAYBOOK.md](./PUBLISH_PLAYBOOK.md) · [IDENTIFIER_CLEANUP.md](./IDENTIFIER_CLEANUP.md)

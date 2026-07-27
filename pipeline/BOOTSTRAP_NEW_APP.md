# Bootstrapping a new Xcode app on this pipeline

Copy the **pipeline kit** from CALarm into any iOS repo. Same flow: config → credentials → portal → build → TestFlight → metadata.

## 1. Copy files into your new repo

From this repo:

```bash
NEW_APP=/path/to/MyNewApp

cp ios-app.config.sh.example "$NEW_APP/ios-app.config.sh"
cp -R scripts/lib "$NEW_APP/scripts/"
cp scripts/{ios-doctor,configure-credentials,bootstrap-portal,setup-asc-cli,verify-asc-api,ship,preflight-release}.sh "$NEW_APP/scripts/"
cp -R pipeline/template-fastlane "$NEW_APP/"  # optional — or copy fastlane/ manually
cp release.sh ExportOptions.plist.example "$NEW_APP/"
```

Or run:

```bash
./pipeline/install-into-repo.sh /path/to/MyNewApp
```

## 2. Edit `ios-app.config.sh`

Set bundle IDs, Xcode project/scheme, team ID, URLs.

## 3. One-time Apple setup (per developer account)

| Step | Who | Command / URL |
|------|-----|----------------|
| API key `.p8` | You | ASC → Integrations → API → download once → `~/Keys/` |
| Issuer ID | You | Same page (UUID at top) |
| App record in ASC | You or CLI | UI or `bundle exec fastlane ios bootstrap_asc` |
| Capabilities (Siri, etc.) | Auto or you | `./scripts/bootstrap-portal.sh` or Developer portal |

## 4. Wire credentials (one command)

```bash
./scripts/configure-credentials.sh <ISSUER_ID> [ASC_APP_APPLE_ID]
```

This updates `fastlane/.env`, registers `asc`, discovers app ID, tries portal capabilities.

## 5. Ship

```bash
./scripts/ship.sh doctor    # health check
./scripts/ship.sh beta      # build + TestFlight
./scripts/ship.sh metadata  # descriptions, URLs, screenshots
./scripts/ship.sh all         # beta + metadata
```

## Tool stack

| Tool | Role |
|------|------|
| `ios-app.config.sh` | Per-app constants (bundle ID, scheme, URLs) |
| `fastlane/.env` | Shared ASC API key (can reuse same `.p8` across your apps) |
| `asc` | App Store Connect CLI |
| `fastlane` | Build/upload lanes |
| `apple-docs-pp-cli` | Framework docs (optional) |
| `spaceship` | Developer Portal cleanup (optional) |

## Shared API key across apps

One App Store Connect API key works for **all** your apps on the same team. Only `ios-app.config.sh` and `ASC_APP_APPLE_ID` change per app.

## Human-only (no API)

- App Privacy nutrition labels
- Age Rating questionnaire  
- First-time Siri toggle if `asc bundle-ids capabilities add` fails (needs Admin role)

See [TERMINAL_TOOLS.md](../docs/app-store/TERMINAL_TOOLS.md).

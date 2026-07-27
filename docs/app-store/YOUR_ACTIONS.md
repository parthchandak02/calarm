# What only you can do (CALarm ship blockers)

**Status (2026-07-03):** Credentials configured. **TestFlight build 1.0 (1) uploaded and VALID.**

---

## Done automatically

- `ASC_ISSUER_ID` + `ASC_APP_APPLE_ID=6787163619` in `fastlane/.env`
- `asc` authenticated (`~/.asc/config.json`)
- Release build + IPA export
- App icon alpha channel fixed (ASC requirement)
- **TestFlight build uploaded** — processing complete (`VALID`)

---

## Your next steps (browser, ~15 min)

Cannot be done via API:

| Task | Where |
|------|--------|
| **Install from TestFlight** on your iPhone | TestFlight app |
| App Privacy questionnaire | ASC → App Privacy |
| Age Rating | ASC → Age Rating |
| Copyright `2026 Parth Chandak` | Version page |
| Review contact + notes | Version page |
| **Attach build 1.0 (1)** | Version page → Build |
| Submit for Review | Version page |

Optional terminal metadata push:
```bash
./scripts/ship.sh metadata
```

---

## Reusing this for your next Xcode app

```bash
./pipeline/install-into-repo.sh /path/to/OtherApp
# Edit ios-app.config.sh, add fastlane/, then:
./scripts/configure-credentials.sh <same-issuer-id>   # same API key works for all apps
```

One API key + Issuer ID works for **every app** on team `M49XY93NTP`.

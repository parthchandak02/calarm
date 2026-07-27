# Developer Portal identifier cleanup

Apple has **no official CLI** to delete App IDs. This repo uses **fastlane spaceship** (Ruby, ships with `bundle install`).

## Safe workflow

```bash
cd /Users/parthchandak/calarm
bundle install

# 1. List everything (Apple ID + 2FA prompt)
bundle exec ruby scripts/cleanup-developer-identifiers.rb list

# 2. See what would be removed
bundle exec ruby scripts/cleanup-developer-identifiers.rb plan

# 3. Delete only stale CALarm / Xcode junk IDs
bundle exec ruby scripts/cleanup-developer-identifiers.rb delete --confirm
```

## What the script keeps

| Bundle ID | Why |
|-----------|-----|
| `com.calarmapp.calarm` | CALarm main app |
| `com.calarmapp.calarm.CalarmWidgetExtension` | Live Activity widget |
| `*` | Wildcard (optional dev) |

## What it can auto-delete (if Apple allows)

Stale Xcode / old CALarm IDs, e.g. `pchandak.calarm`, `test.cal-tag-app`, `com.calendar-tags`, etc.

Deletion **fails** if a provisioning profile still references the ID — delete profiles first at [developer.apple.com → Profiles](https://developer.apple.com/account/resources/profiles/list).

## Manual review (NOT auto-deleted)

| Bundle ID | Why |
|-----------|-----|
| `cal.tag.app` | Separate app — delete only if abandoned |
| `cal.tag.app.OneSignalNotificationServiceExtension` | Its extension |

## Alternatives

| Tool | Notes |
|------|--------|
| [fastlane spaceship](https://github.com/fastlane/fastlane/tree/master/spaceship) | What this script uses |
| [asc CLI](https://github.com/asc/cli) (`brew install asc`) | App Store Connect API; bundle ID delete only for unused dev IDs |
| Apple Developer website | Manual delete per identifier |

**Do not** delete identifiers for apps still on the App Store or TestFlight.

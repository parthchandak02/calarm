# CALarm Cursor Skills

Project-scoped agent skills for the CALarm iOS repo. Invoke by name or let the agent match from description triggers.

| Skill | Use when |
|-------|----------|
| [calarm-alarmkit-reschedule](calarm-alarmkit-reschedule/SKILL.md) | Editing AlarmScheduler, ScheduleStore, snooze/cancel logic |
| [calarm-stacked-live-activities](calarm-stacked-live-activities/SKILL.md) | Multiple Dynamic Island cards, out-of-order timers |
| [calarm-device-deploy-verify](calarm-device-deploy-verify/SKILL.md) | USB/Wi-Fi deploy, stale build on device |
| [calarm-build-version-stamp](calarm-build-version-stamp/SKILL.md) | CFBundleVersion date format, Settings build display |
| [calarm-testflight-fastlane](calarm-testflight-fastlane/SKILL.md) | TestFlight upload, ASC API, fastlane lanes |
| [calarm-live-activity-deep-links](calarm-live-activity-deep-links/SKILL.md) | Island tap behavior, `calarm://` deep links |
| [calarm-occurrence-identity](calarm-occurrence-identity/SKILL.md) | Recurring events, per-occurrence IDs, preference migration |
| [calarm-trust-diagnostics](calarm-trust-diagnostics/SKILL.md) | Permission banners, test alarm, schedule failures |
| [calarm-release-pipeline](calarm-release-pipeline/SKILL.md) | ship.sh, ios-doctor, pipeline bootstrap |
| [calarm-app-icon-alpha](calarm-app-icon-alpha/SKILL.md) | App icon transparency rejection, logo processing |

## Agents (delegation)

- `.cursor/agents/calarm-ship-ready.md` — final-mile code audit + device deploy
- `.cursor/agents/calarm-app-store-prep.md` — metadata, fastlane, ASC checklist

Skills are narrow references; agents orchestrate broader release workflows.

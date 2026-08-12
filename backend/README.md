# CALarm Tier 2 — Google Calendar webhook relay (deferred)

This folder scaffolds the backend needed for **near-real-time** Google Calendar updates while CALarm is backgrounded.

Tier 1 (implemented in the iOS app) uses direct Google API polling on foreground. Tier 2 adds:

1. `POST /webhooks/google` — receive Calendar API `events.watch` pings
2. Per-user channel registry + daily renewal cron
3. `events.list(syncToken)` incremental sync on webhook
4. APNs silent push (`content-available: 1`) to wake the app

## GCP project

Reuse **`useful-field-497119-k5`** (Calendar API + Pub/Sub already enabled).

## Google APIs

- [Calendar push notifications](https://developers.google.com/workspace/calendar/api/guides/push) — `events.watch` with HTTPS callback
- [Incremental sync](https://developers.google.com/workspace/calendar/api/guides/sync) — `syncToken` after initial full sync per calendar

Note: the Workspace Events API (`gws events +subscribe`) does **not** support Calendar; use Calendar API watch.

## Suggested deployment

- **Cloudflare Worker** or **Cloud Run** for the webhook endpoint
- **Cloud Scheduler** for channel renewal (channels expire ~7 days)
- Store refresh tokens encrypted (KMS); never commit secrets

## iOS additions (not yet implemented)

- `UIBackgroundModes` → `remote-notification`
- Register for APNs; handle silent push → `GoogleCalendarService.fetchUpcomingEvents`
- Backend holds user refresh tokens with `access_type=offline`

## Local spike validation

```bash
gws auth login
gws calendar events watch --params '{"calendarId":"primary"}' \
  --json '{"id":"uuid","type":"web_hook","address":"https://YOUR_HTTPS/webhooks/google","token":"calarm"}'
```

See `scripts/setup-google-oauth.sh` for OAuth setup.

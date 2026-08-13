# Calarm Privacy Policy (outline — publish at your privacy URL)

Replace bracketed sections, host as a public HTTPS page, and set the URL in `fastlane/metadata/en-US/privacy_url.txt`.

---

## Privacy Policy for Calarm

**Last updated:** [DATE]

### Summary

Calarm is a calendar-aware alarm app for iOS 26. We do not sell your data. Calendar information and alarm preferences stay on your device. Optional Google Calendar sign-in fetches events directly from Google’s API; we do not operate a backend that stores your calendar.

### Information we access

**On-device calendar events**  
With your permission, Calarm reads upcoming calendar events from calendars on your device (EventKit) to display your schedule and schedule countdown alarms before each event. Calarm does not upload on-device calendar data to our servers.

**Optional Google Calendar**  
You may optionally connect a Google account in Settings. If you do:

- Calarm uses Google Sign-In to authenticate you with Google.
- Calarm requests read-only access to your Google Calendar and calls the Google Calendar API (`googleapis.com`) to list calendars and fetch events for display and alarm scheduling.
- Your Google account email is stored locally on your device so Settings can show which account is connected.
- OAuth tokens are stored securely by the Google Sign-In SDK (iOS Keychain). Enabled calendar choices and sync metadata are stored locally in app preferences.
- Disconnecting Google Calendar in Settings signs you out and removes locally stored Google preferences.

We do not receive or store your Google calendar data on any Calarm-operated server.

**Alarm preferences**  
Per-event alarm settings and your default alarm offset are stored locally on your device using iOS storage (UserDefaults).

**Alarms**  
Calarm uses Apple’s AlarmKit framework to schedule countdown alarms and Live Activities. Alarm scheduling is handled by iOS on your device.

### Information we do not collect

- We do not operate user accounts or a Calarm backend for your calendar data.
- We do not use third-party analytics or advertising SDKs.
- We do not track you across apps or websites.

### Data sharing

We do not share your personal information with third parties for our own purposes. When you connect Google Calendar, Google processes sign-in and calendar API requests under [Google’s Privacy Policy](https://policies.google.com/privacy). Apple processes App Store distribution and TestFlight under [Apple’s Privacy Policy](https://www.apple.com/legal/privacy/).

### Data retention

Data remains on your device until you delete the app, disconnect Google Calendar, or revoke calendar access in iOS Settings.

### Your choices

You can deny or revoke on-device calendar access in **Settings → Privacy & Security → Calendars → Calarm**. You can connect or disconnect Google Calendar in **Settings → Calarm**. You can manage alarm permissions in **Settings → Calarm**.

### Children

Calarm is not directed at children under 13.

### Changes

We may update this policy. The “Last updated” date will change when we do.

### Contact

Support: [YOUR EMAIL]  
[Optional mailing address]

---

## App Store Connect alignment

When completing the App Privacy questionnaire, declare:

| Data type | Linked to user | Tracking | Purpose |
|-----------|----------------|----------|---------|
| Calendars | No | No | App Functionality |
| Email Address | No | No | App Functionality |

Tracking: **No**

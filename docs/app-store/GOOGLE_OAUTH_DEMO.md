# Google OAuth demo video (data access verification)

**Done: CALarm's data access is verified.** Re-run this only if a scope is added or changed.

Google will not verify CALarm's `calendar.readonly` scope without an unlisted YouTube video
showing the sign-in flow and how the data is used. This is the playbook for recording it.
Run it on a Mac with RAM to spare, **not the Mac mini**, or skip the Mac entirely and record
on the iPhone (section 5).

## Where things stand

| | |
|---|---|
| Google Cloud project | `calarmapp-ios` (Calendar API only, no billing) |
| OAuth client | iOS client "CALarm iOS" for `com.calarmapp.calarm` |
| Consent screen | External, **In production**, branding verified (name, logo, domain) |
| Scope | `calendar.readonly` only; **verified** (submitted 2026-09-27, verified by 2026-10-03) |
| Homepage / privacy | `https://calarm.parthchandak.info/` · `/privacy.html` |
| Minimum code | `main` at or after the commit that added this file |
| Minimum TestFlight build | `20260927.1620` |

## Rules for the agent

- **Never type, read or store the owner's Google password.** The owner signs in by hand.
- **Never commit** `Calarm/GoogleService-Info.plist`, `Config/Google.local.xcconfig` or a
  downloaded `client_*.plist`. All are gitignored; keep it that way.
- The video must show the **"Google hasn't verified this app"** screen. Google requires it.
- The video shows real calendar titles. Ask the owner whether to use a spare Google account
  with made-up events before recording.
- Delete the simulator and the recording's intermediates afterwards.

## 1. Prepare the checkout

```bash
git clone https://github.com/parthchandak02/calarm.git 2>/dev/null || true
cd calarm && git checkout main && git pull --ff-only
git log -1 --oneline
xcodebuild -version                        # Xcode 26 or later
xcrun simctl list runtimes | grep "iOS 26" # an iOS 26 simulator runtime
```

Google sign-in is off on a fresh clone. The owner downloads the client plist from
[Google Auth Platform → Clients](https://console.cloud.google.com/auth/clients?project=calarmapp-ios)
→ "CALarm iOS" → Download plist, then:

```bash
./scripts/setup-google-oauth.sh ~/Downloads/client_*.plist
rm ~/Downloads/client_*.plist
```

It should print `ok Google sign-in configured (client 130545958463-…)`.

## 2. Build and boot a clean simulator

```bash
RUNTIME=$(xcrun simctl list runtimes | awk '/iOS 26/{print $NF}' | tail -1)
UDID=$(xcrun simctl create "CALarm Demo" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$RUNTIME")
xcrun simctl boot "$UDID"
xcodebuild build -project Calarm.xcodeproj -scheme Calarm -configuration Debug \
  -destination "id=$UDID" -derivedDataPath build/demo-sim -quiet
xcrun simctl install "$UDID" "$(find build/demo-sim -name Calarm.app -path '*iphonesimulator*' | head -1)"
xcrun simctl privacy "$UDID" grant calendar com.calarmapp.calarm
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100
xcrun simctl ui "$UDID" appearance dark
open -a Simulator --args -CurrentDeviceUDID "$UDID"
xcrun simctl launch "$UDID" com.calarmapp.calarm
```

Have the owner dismiss any first-run tips so the recording starts on a clean schedule.

## 3. Record

```bash
xcrun simctl io "$UDID" recordVideo --codec=h264 --force /tmp/calarm-demo-raw.mp4
```

If the account has granted CALarm access before, Google skips the unverified-app screen and
the full consent screen. Revoke it first at
[myaccount.google.com/connections](https://myaccount.google.com/connections) → CALarm →
Delete all connections, and Disconnect in the app.

Run it in the background. While it records, the owner does this, pausing about 3 seconds on
each Google screen:

1. Gear → **Calendars** → **Connect Google Calendar**.
2. Pick or sign in to the Google account (owner types it).
3. **"Google hasn't verified this app"** → pause → **Advanced** → **Go to CALarm**.
4. The CALarm consent screen (logo, calendar permission) → pause → tick the box if shown →
   **Allow**.
5. Back in the app: the Google calendar list, toggle one calendar off and on, close
   Settings, scroll the schedule, tap one event's square to arm it.

Stop with `pkill -INT -f "simctl io .* recordVideo"`. The file is only valid after SIGINT.

## 4. Edit

Trim dead time, add a 3-second title card (the app icon), export an MP4 YouTube accepts. Set `START` and
`END` (seconds) after watching the raw file.

```bash
START=2; END=95
SIZE=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
  -of csv=s=x:p=0 /tmp/calarm-demo-raw.mp4)
# Title card: the app icon centred on black (no fonts; Homebrew ffmpeg often lacks drawtext).
ffmpeg -y -f lavfi -i "color=c=black:s=${SIZE}:d=3:r=30" -i docs/assets/readme/icon.png \
  -filter_complex "[1:v]scale=420:-1[i];[0:v][i]overlay=(W-w)/2:(H-h)/2" \
  -c:v libx264 -pix_fmt yuv420p /tmp/calarm-title.mp4
ffmpeg -y -ss "$START" -to "$END" -i /tmp/calarm-demo-raw.mp4 -vf "fps=30,format=yuv420p" \
  -c:v libx264 -an /tmp/calarm-body.mp4
ffmpeg -y -i /tmp/calarm-title.mp4 -i /tmp/calarm-body.mp4 \
  -filter_complex "[0:v][1:v]concat=n=2:v=1:a=0[v]" -map "[v]" \
  -c:v libx264 -pix_fmt yuv420p -movflags +faststart ~/Desktop/calarm-oauth-demo.mp4
```

Watch `~/Desktop/calarm-oauth-demo.mp4` end to end before handing it over.

## 5. No Mac? Record on the iPhone

Install the latest TestFlight build, disconnect Google in Settings → Calendars, start
Screen Recording from Control Center, do the steps in section 3, stop, and upload straight
from Photos. No editing is required.

## 6. Submit

1. [studio.youtube.com](https://studio.youtube.com) → Create → Upload. Title
   `CALarm - Google Calendar OAuth demo`, visibility **Unlisted** (not Private). A vertical clip under a minute becomes a Short;
   submit it as `https://www.youtube.com/watch?v=<id>`, not the `/shorts/` link.
2. [Data Access](https://console.cloud.google.com/auth/scopes?project=calarmapp-ios) →
   paste the YouTube link. The justification box takes:

   > CALarm is an iOS app that turns calendar events into full-screen alarms so users don't
   > miss meetings. We use calendar.readonly to (1) list the user's calendars, including
   > ones shared with them, so they can choose which calendars create alarms, and (2) read
   > upcoming events (title, start and end time, location) from those calendars for the
   > next 8 days, then schedule alarms on the device with Apple's AlarmKit. The app never
   > creates, edits or deletes calendar data. Requests go directly from the user's iPhone to
   > the Google Calendar API. Event data is processed and stored only on the device; it is
   > never sent to our servers (we run none), shared, sold, or used for advertising.
   > calendar.readonly is the most limited single scope that covers both the calendar list
   > and events across all of the user's calendars, and it is read-only.

3. Save → **Verification Center** → **Prepare for verification** → **Submit**.

Google replies to parth.chandak02@gmail.com, usually within 3–5 business days. The likeliest
follow-up asks why not `calendar.calendarlist.readonly` + `calendar.events.readonly`;
switching is one line in `Calarm/Config/GoogleOAuthConfig.swift` plus a new build.

## 7. Clean up

```bash
xcrun simctl shutdown "$UDID"; xcrun simctl delete "$UDID"
rm -rf build/demo-sim /tmp/calarm-demo-raw.mp4 /tmp/calarm-title.mp4 /tmp/calarm-body.mp4
```

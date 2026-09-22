/**
 * Calarm calendar relay.
 *
 * Google Apps Script standing in for a server. A change to the calendar fires an
 * installable `onEventUpdated` trigger, this script works out what actually changed via
 * an incremental sync, and pushes to the phone through FCM.
 *
 * WHY THIS EXISTS, AND WHY IT BEATS THE OBVIOUS ALTERNATIVE
 *
 * The textbook answer is Google's `events.watch` webhook pointed at your own server.
 * That needs a CA-signed HTTPS endpoint on a domain registered in the Cloud console, and
 * the channel expires in about a week and must be re-created by a cron you also own.
 * This replaces all of it: Google maintains the subscription, there is no domain, no
 * channel renewal, and no compute bill.
 *
 * THE ONE THING THAT DOES NOT WORK, SO NOBODY TRIES IT AGAIN
 *
 * Apps Script cannot talk to APNs directly. APNs requires an ES256-signed JWT, and
 * `Utilities` offers only RSA-SHA1, RSA-SHA256 and HMAC -- there is no elliptic-curve
 * primitive anywhere in the runtime. Verified against the Utilities reference.
 * FCM is the way through, because Google service accounts authenticate with RS256, which
 * `Utilities.computeRsaSha256Signature` does do. FCM then owns the APNs hop.
 *
 * WHAT THE TRIGGER DOES AND DOES NOT TELL YOU
 *
 * The handler receives `{authMode, calendarId, triggerUid}` and nothing else. Google's
 * own words: "These triggers do not tell you which event changed or how it changed.
 * Instead, they indicate that your code needs to do an incremental sync operation."
 * Hence `syncToken`, below.
 *
 * SETUP, in order. Steps 2 and 3 are the only ones that cost anything.
 *
 *   1. Paste these files into a new project at script.google.com. Enable the Calendar
 *      advanced service (appsscript.json already declares it).
 *   2. Create a Firebase project, add the iOS app, upload an APNs auth key. This is the
 *      step that needs the paid Apple Developer Program, because the Push Notifications
 *      entitlement does not exist on a free personal team.
 *   3. Make a service account with the Firebase Cloud Messaging API Admin role, download
 *      its JSON key.
 *   4. Put FCM_PROJECT_ID, FCM_CLIENT_EMAIL and FCM_PRIVATE_KEY into Project Settings >
 *      Script Properties. Do not paste them into this file -- see the note on secrets.
 *   5. Run `setup()` once and grant the scopes it asks for.
 *   6. Deploy > New deployment > Web app, execute as me, access anyone. The app posts its
 *      FCM token to that URL once.
 *
 * OPERATIONAL TRAPS, all verified against Google's docs. Each of these is silent.
 *
 *   - **Never press "Deploy > New deployment" twice.** A new deployment gets a new ID and
 *     a new URL, and the shipped app keeps calling the old one. To publish a change use
 *     Deploy > Manage deployments > Edit > Version: New version > Deploy, which keeps the
 *     URL. This is the single easiest way to break a working install.
 *   - **Do not attach a standard Cloud project.** On its default project, Apps Script is
 *     exempt from the re-authentication frequency that kills OAuth refresh tokens after
 *     7 days in "Testing" status -- Google exempts it precisely because scripts run on
 *     triggers. Attach your own Cloud project with a Testing consent screen and you
 *     reintroduce that 7-day clock for no benefit.
 *   - **`doGet` cannot read request headers, ever.** Google declined the feature in 2023
 *     citing security, closing a request open since 2017. So the shared secret travels in
 *     the query string; there is no `Authorization` header option. Avoid the parameter
 *     names `c` and `sid`, which are reserved and return HTTP 405.
 *   - **Trigger runtime is capped at 90 min/day on a consumer account** (6 hr on
 *     Workspace), with no cap on how many times a trigger may fire. The hourly backstop
 *     plus change-driven fires sits far inside that; a one-minute time-driven poll would
 *     not, which is why the backstop is hourly.
 *   - **Failure emails cannot be switched off** without deactivating the trigger. The
 *     re-throw in `onCalendarChange` is deliberate: a script that swallows its errors is
 *     how "background sync silently stopped" happens, and that is the exact bug this
 *     whole exercise exists to kill. Expect mail if it breaks. That is the feature.
 *   - **Notifications are not fully reliable.** Google's own words about this delivery
 *     machinery: "Expect a small percentage of messages to get dropped." Hence the
 *     backstop trigger, and hence the client should still refresh on foreground.
 *
 * SECRETS. Everything sensitive lives in Script Properties, never in source. This file is
 * committed to the calarm repo; a private key in it would be in git history forever, and
 * that repo has already had one history purge for exactly this class of mistake.
 */

// ---------------------------------------------------------------- configuration

/** Which calendar to watch. 'primary' is the account's own calendar. */
var CALENDAR_ID = 'primary';

/** How far ahead the phone cares about. Matches calarm's own alarm horizon. */
var HORIZON_DAYS = 7;

/**
 * How far back the token-minting full sync reaches.
 *
 * `timeMin` is baked into the sync token as an absolute date and never moves until the
 * token is replaced, so this is a floor rather than a window. A week of history catches
 * an event edited today that started yesterday, without asking Google for years of past.
 */
var SYNC_FLOOR_DAYS = 7;

var PROP_SYNC_TOKEN = 'calarm.syncToken';
var PROP_DEVICE_TOKENS = 'calarm.deviceTokens';
var PROP_LAST_DIGEST = 'calarm.lastDigest';

// ---------------------------------------------------------------- setup

/**
 * Run once by hand. Idempotent: it removes its own previous trigger first, so running it
 * twice does not give you two triggers firing on every change.
 */
function setup() {
  removeTriggers_();

  ScriptApp.newTrigger('onCalendarChange')
    .forUserCalendar(Session.getEffectiveUser().getEmail())
    .onEventUpdated()
    .create();

  // A time-driven backstop. The calendar trigger is the fast path, but Google disables
  // triggers on scripts that throw repeatedly, and a disabled trigger fails silently --
  // there is no callback telling you that you have stopped being notified. This hourly
  // run means the worst case degrades to "an hour late" rather than "never again".
  ScriptApp.newTrigger('onCalendarChange')
    .timeBased()
    .everyHours(1)
    .create();

  PropertiesService.getScriptProperties().deleteProperty(PROP_SYNC_TOKEN);
  Logger.log('Triggers installed. Sync token cleared; the next run will full sync.');
}

function removeTriggers_() {
  ScriptApp.getProjectTriggers().forEach(function (trigger) {
    if (trigger.getHandlerFunction() === 'onCalendarChange') {
      ScriptApp.deleteTrigger(trigger);
    }
  });
}

// ---------------------------------------------------------------- the trigger

/**
 * Fires on any create, edit or delete in the watched calendar, and hourly as a backstop.
 *
 * `LockService` matters more than it looks. Editing a recurring series, or a few quick
 * edits in a row, fires this several times within seconds. Two concurrent runs would both
 * read the same sync token, both consume it, and one of the two resulting tokens would be
 * dropped -- which silently breaks incremental sync until the next 410.
 */
function onCalendarChange(e) {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(30 * 1000)) {
    Logger.log('Another run holds the lock; skipping. The winner covers this change.');
    return;
  }

  try {
    var changed = pullChanges_();
    if (!changed) {
      Logger.log('Sync produced no changes.');
      return;
    }

    var upcoming = readHorizon_();
    var digest = digestOf_(upcoming);

    // Only push when the *next week* actually looks different. Most calendar edits are
    // irrelevant to an alarm app: a description reworded, a colour changed, an event
    // moved next month. Pushing on every raw change would burn the phone's background
    // push budget on nothing.
    var properties = PropertiesService.getScriptProperties();
    if (digest === properties.getProperty(PROP_LAST_DIGEST)) {
      Logger.log('Calendar changed but the next ' + HORIZON_DAYS + ' days are unaffected.');
      return;
    }
    properties.setProperty(PROP_LAST_DIGEST, digest);

    notifyDevices_(upcoming);
  } catch (error) {
    // Logged loudly on purpose. A throw here is what gets the trigger disabled by Google,
    // and a disabled trigger is invisible from the outside.
    console.error('calarm relay failed: ' + error + '\n' + (error.stack || ''));
    throw error;
  } finally {
    lock.releaseLock();
  }
}

/**
 * Incremental sync. Returns true when the calendar reported any change at all.
 *
 * The parameter rules here are the same ones that were wrong in the iOS client, and they
 * are worth restating because they are easy to get wrong in both places. Google forbids
 * `timeMin`, `timeMax`, `orderBy`, `q`, `iCalUID`, `updatedMin` and the extended-property
 * filters on any request carrying a `syncToken`, and requires every *other* parameter to
 * match the request that minted the token. So the full sync below sets `timeMin` and
 * nothing else filter-like, and `singleEvents: false` -- with `true` and no `timeMax`,
 * Google expands every recurrence for all time and one daily standup becomes thousands
 * of rows.
 */
function pullChanges_() {
  var properties = PropertiesService.getScriptProperties();
  var syncToken = properties.getProperty(PROP_SYNC_TOKEN);

  var request = {
    singleEvents: false,
    showDeleted: true,
    maxResults: 2500
  };

  if (syncToken) {
    request.syncToken = syncToken;
  } else {
    request.timeMin = new Date(Date.now() - SYNC_FLOOR_DAYS * 86400000).toISOString();
  }

  var changedCount = 0;
  var pageToken = null;

  do {
    if (pageToken) {
      request.pageToken = pageToken;
    }

    var response;
    try {
      response = Calendar.Events.list(CALENDAR_ID, request);
    } catch (error) {
      // 410 GONE means the token is too old. Google's instruction is to discard local
      // state and full sync; dropping the token makes the next run do exactly that.
      if (String(error).indexOf('410') !== -1 || String(error).indexOf('Sync token') !== -1) {
        properties.deleteProperty(PROP_SYNC_TOKEN);
        Logger.log('Sync token expired. Cleared; next run will full sync.');
        return true;
      }
      throw error;
    }

    changedCount += (response.items || []).length;
    pageToken = response.nextPageToken;

    // `nextSyncToken` appears only on the final page. Storing a token from a middle page
    // would lose every change on the pages after it.
    if (response.nextSyncToken) {
      properties.setProperty(PROP_SYNC_TOKEN, response.nextSyncToken);
    }
  } while (pageToken);

  // A first full sync returns the whole calendar, which is not "a change" -- it is the
  // baseline. Report true anyway so the digest gets established on the first run.
  return changedCount > 0;
}

/** The expanded, bounded view the phone actually needs. */
function readHorizon_() {
  var now = new Date();
  var end = new Date(now.getTime() + HORIZON_DAYS * 86400000);

  var response = Calendar.Events.list(CALENDAR_ID, {
    timeMin: now.toISOString(),
    timeMax: end.toISOString(),
    singleEvents: true,
    orderBy: 'startTime',
    maxResults: 250
  });

  return (response.items || [])
    .filter(function (event) {
      return event.status !== 'cancelled' && event.start && event.start.dateTime;
    })
    .map(function (event) {
      return {
        id: event.id,
        title: event.summary || 'Untitled',
        start: event.start.dateTime,
        end: event.end && event.end.dateTime ? event.end.dateTime : event.start.dateTime,
        location: event.location || null,
        // Sent so the phone can tell "you are still expected" from "you declined".
        selfStatus: selfResponse_(event)
      };
    });
}

function selfResponse_(event) {
  var attendees = event.attendees || [];
  for (var i = 0; i < attendees.length; i++) {
    if (attendees[i].self) {
      return attendees[i].responseStatus || null;
    }
  }
  return null;
}

/**
 * A fingerprint of everything that would change an alarm.
 *
 * Deliberately excludes description, colour and location: none of those move an alarm, and
 * including them would push on edits that do not matter.
 */
function digestOf_(events) {
  var material = events.map(function (event) {
    return [event.id, event.start, event.title, event.selfStatus].join('~');
  }).join('|');

  var bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, material);
  return Utilities.base64Encode(bytes);
}

// ---------------------------------------------------------------- FCM

/**
 * Pushes to every registered device.
 *
 * Sent as a visible, time-sensitive alert rather than a silent `content-available` push.
 * That is deliberate: silent pushes are budgeted at roughly two or three an hour, are
 * dropped once the device's budget is spent, and are never delivered at all to an app the
 * user force-quit. A visible alert survives all three, and with `mutable-content` the
 * app's notification service extension still gets a moment of runtime to re-sync.
 *
 * No event titles go in the payload beyond the one headline. The push is rendered on a
 * locked screen and travels through Google's infrastructure; the phone already has the
 * calendar and can fetch detail itself.
 */
function notifyDevices_(upcoming) {
  var tokens = deviceTokens_();
  if (!tokens.length) {
    Logger.log('No devices registered; nothing to push. Deploy the web app and register.');
    return;
  }

  var accessToken = fcmAccessToken_();
  var projectId = requiredProperty_('FCM_PROJECT_ID');
  var next = upcoming.length ? upcoming[0] : null;

  tokens.forEach(function (deviceToken) {
    var message = {
      message: {
        token: deviceToken,
        notification: {
          title: 'Schedule changed',
          body: next
            ? 'Next up: ' + next.title + ' at ' + formatTime_(next.start)
            : 'Nothing in the next ' + HORIZON_DAYS + ' days.'
        },
        data: {
          kind: 'calendar-changed',
          // A hint, not the payload. The phone re-syncs and decides for itself.
          changedAt: new Date().toISOString(),
          upcomingCount: String(upcoming.length)
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'alert'
          },
          payload: {
            aps: {
              'mutable-content': 1,
              'interruption-level': 'time-sensitive',
              sound: 'default'
            }
          }
        }
      }
    };

    var response = UrlFetchApp.fetch(
      'https://fcm.googleapis.com/v1/projects/' + projectId + '/messages:send',
      {
        method: 'post',
        contentType: 'application/json',
        headers: { Authorization: 'Bearer ' + accessToken },
        payload: JSON.stringify(message),
        muteHttpExceptions: true
      }
    );

    var code = response.getResponseCode();
    if (code === 404 || code === 400) {
      // FCM reports a dead registration this way. Pruning matters because a stale token
      // is retried on every single change, forever, for a device that no longer exists.
      Logger.log('Dropping dead device token (HTTP ' + code + ').');
      forgetDevice_(deviceToken);
    } else if (code < 200 || code >= 300) {
      console.error('FCM push failed ' + code + ': ' + response.getContentText());
    }
  });
}

/**
 * Mints a service-account access token.
 *
 * Hand-rolled rather than pulling in the OAuth2 library, because the whole flow is
 * twenty lines and a vendored library is one more thing to keep current. RS256 is the
 * point here: service accounts sign with RSA, which this runtime can do, unlike the
 * ES256 that APNs would have demanded.
 */
function fcmAccessToken_() {
  var cache = CacheService.getScriptCache();
  var cached = cache.get('fcm.accessToken');
  if (cached) {
    return cached;
  }

  var clientEmail = requiredProperty_('FCM_CLIENT_EMAIL');
  // Script Properties collapse the PEM's newlines, so restore them before signing.
  var privateKey = requiredProperty_('FCM_PRIVATE_KEY').replace(/\\n/g, '\n');

  var now = Math.floor(Date.now() / 1000);
  var header = { alg: 'RS256', typ: 'JWT' };
  var claims = {
    iss: clientEmail,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600
  };

  var unsigned = Utilities.base64EncodeWebSafe(JSON.stringify(header)).replace(/=+$/, '') +
    '.' + Utilities.base64EncodeWebSafe(JSON.stringify(claims)).replace(/=+$/, '');
  var signature = Utilities.base64EncodeWebSafe(
    Utilities.computeRsaSha256Signature(unsigned, privateKey)
  ).replace(/=+$/, '');

  var response = UrlFetchApp.fetch('https://oauth2.googleapis.com/token', {
    method: 'post',
    payload: {
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: unsigned + '.' + signature
    },
    muteHttpExceptions: true
  });

  if (response.getResponseCode() !== 200) {
    throw new Error('Token exchange failed: ' + response.getContentText());
  }

  var token = JSON.parse(response.getContentText()).access_token;
  // Short of the real hour, so a token never expires mid-push.
  cache.put('fcm.accessToken', token, 3000);
  return token;
}

// ---------------------------------------------------------------- web app

/**
 * Device registration, and the reason this deployment is public.
 *
 * "Anyone" access is required because the phone has no Google credentials for this
 * script. The deployment URL is therefore a bearer secret: anyone holding it can register
 * a device or read the horizon. It is a 60-odd character unguessable path, but it is not
 * an authentication system, so `SHARED_SECRET` is checked on top. Set it in Script
 * Properties and ship the same value in the app.
 */
function doPost(request) {
  try {
    var body = JSON.parse(request.postData.contents);
    if (!secretOK_(body.secret)) {
      return json_({ ok: false, error: 'unauthorized' });
    }
    if (!body.token) {
      return json_({ ok: false, error: 'missing token' });
    }

    rememberDevice_(body.token);
    return json_({ ok: true, devices: deviceTokens_().length });
  } catch (error) {
    return json_({ ok: false, error: String(error) });
  }
}

/**
 * The horizon as JSON, which is the interesting fallback.
 *
 * If the app polls this instead of Google directly, it needs **no Google OAuth at all**:
 * no client ID, no consent screen, no verification, no 7-day refresh-token expiry, no
 * GoogleService-Info.plist, and no GoogleSignIn dependency. The script holds the only
 * credential. That is a large reduction in both app setup and moving parts, at the cost
 * of this script becoming a dependency of the app.
 */
function doGet(request) {
  if (!secretOK_(request.parameter.secret)) {
    return json_({ ok: false, error: 'unauthorized' });
  }

  return json_({
    ok: true,
    generatedAt: new Date().toISOString(),
    horizonDays: HORIZON_DAYS,
    events: readHorizon_()
  });
}

function secretOK_(candidate) {
  var expected = PropertiesService.getScriptProperties().getProperty('SHARED_SECRET');
  // Unset means unset: refuse rather than silently serving the calendar to the world.
  return !!expected && candidate === expected;
}

function json_(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}

// ---------------------------------------------------------------- properties

function deviceTokens_() {
  var raw = PropertiesService.getScriptProperties().getProperty(PROP_DEVICE_TOKENS);
  if (!raw) {
    return [];
  }
  try {
    return JSON.parse(raw);
  } catch (error) {
    return [];
  }
}

function rememberDevice_(token) {
  var tokens = deviceTokens_();
  if (tokens.indexOf(token) === -1) {
    tokens.push(token);
    PropertiesService.getScriptProperties()
      .setProperty(PROP_DEVICE_TOKENS, JSON.stringify(tokens));
  }
}

function forgetDevice_(token) {
  var tokens = deviceTokens_().filter(function (existing) {
    return existing !== token;
  });
  PropertiesService.getScriptProperties()
    .setProperty(PROP_DEVICE_TOKENS, JSON.stringify(tokens));
}

function requiredProperty_(key) {
  var value = PropertiesService.getScriptProperties().getProperty(key);
  if (!value) {
    throw new Error('Missing Script Property: ' + key);
  }
  return value;
}

function formatTime_(iso) {
  return Utilities.formatDate(
    new Date(iso),
    Session.getScriptTimeZone(),
    'h:mm a'
  );
}

// ---------------------------------------------------------------- diagnostics

/** Run by hand to prove the pipe works end to end before wiring the app. */
function selftest() {
  Logger.log('Calendar: ' + CALENDAR_ID);
  Logger.log('Triggers: ' + ScriptApp.getProjectTriggers().length);
  Logger.log('Devices: ' + deviceTokens_().length);
  Logger.log('Sync token stored: ' +
    !!PropertiesService.getScriptProperties().getProperty(PROP_SYNC_TOKEN));

  var upcoming = readHorizon_();
  Logger.log('Upcoming events: ' + upcoming.length);
  if (upcoming.length) {
    Logger.log('Next: ' + upcoming[0].title + ' at ' + upcoming[0].start);
  }

  try {
    fcmAccessToken_();
    Logger.log('FCM credentials: OK');
  } catch (error) {
    Logger.log('FCM credentials: ' + error);
  }
}

---
name: unity-push-local-notifications
description: 'Use when wiring push notifications and local scheduled notifications into a Unity F2P mobile game through Unity MCP — push notification, FCM, Firebase Messaging, APNs, Apple Push Notification, OneSignal, Airship, local notification, scheduled notification, Unity Mobile Notifications, com.unity.mobile.notifications, NotificationManager, AndroidNotificationCenter, iOSNotificationCenter, notification permission, channel, category, payload, deep link from notification, silent push, win-back, retention notification, energy refill notification. Unity 6+ / 6000.x, URP-only, new Input System only. NOT for in-game UI toasts (use unity-ugui), NOT for analytics-driven messaging campaigns (campaign tooling lives in MMP — pair with unity-analytics-events for open-event logging).'
---

# Unity Push & Local Notifications

## When to use
D1 / D7 retention in F2P depends on notifications. "Come back, your energy is full" lifts D1 retention 10-30%. D7 win-back ("we miss you, +500 gems") reactivates lapsed users who would otherwise stay churned. Without notifications, churned users stay churned. Wire local scheduling and at least one push provider before soft launch — adding it after live ops has begun loses you weeks of retention data.

## Permission flow
- **iOS**: must call `iOSNotificationCenter.RequestAuthorization` async; user sees the system dialog. Granted/denied is permanent (only changeable in Settings → app → Notifications).
- **Android 13+**: `POST_NOTIFICATIONS` is a runtime permission. Pre-13 is implicit-granted at install.
- **Strategy**: do NOT ask on first launch — grant rate is low. Wait for a contextual moment ("Want notifications when your gem chest is ready?"). One denial is forever; pre-prime with an in-game soft prompt before triggering the OS dialog so denials happen on your prompt, not the system one.

## Pick a service
- **Unity Mobile Notifications package** (`com.unity.mobile.notifications`) — local notifications + APNs/FCM push surfacing. Free, official. Required for local even if you also use a push vendor.
- **Firebase Cloud Messaging (FCM)** — cross-platform server push. Free unlimited. Pair with a Firebase project; routes to APNs on iOS under the hood.
- **OneSignal** — turn-key. Abstracts FCM + APNs + segmentation + time-zone scheduling + A/B subject lines. Easy but adds a vendor and a privacy disclosure.
- **Airship** — enterprise; overkill for indie.

Default stack: Unity Mobile Notifications (local) + FCM (push). Add OneSignal only if you don't want a backend that calls FCM Admin SDK.

## Local notifications (Unity package)
Schedule on app pause / on a server timestamp:
```csharp
var notification = new AndroidNotification {
    Title = "Energy full!",
    Text = "Tap to play",
    FireTime = System.DateTime.Now.AddHours(2),
    SmallIcon = "icon_small",
    LargeIcon = "icon_large",
    IntentData = "{\"deeplink\":\"play/home\"}"
};
AndroidNotificationCenter.SendNotification(notification, "default_channel");
```
iOS equivalent via `iOSNotificationCenter.ScheduleNotification(...)`. Both support repeating triggers, categories, and action buttons. Cancel scheduled local notifications on app foreground if the condition no longer holds (energy already spent).

## FCM (Android push)
- Add `com.google.firebase.messaging` via Firebase Unity SDK + a Firebase project.
- Get device token: `FirebaseMessaging.GetTokenAsync()` → upload to your backend, link to playerID.
- Refresh on `OnTokenRefresh` and re-upload — the token rotates.
- Server sends via Firebase Admin SDK → Google → device → app foreground/background handler.

## Server-side FCM dispatch (HTTP v1)

CRITICAL: the legacy FCM HTTP API (`https://fcm.googleapis.com/fcm/send` with `Authorization: key=<server_key>`) was sunset June 20, 2024. Any backend still on that path silently 404s — push delivery just stops. Migrate to HTTP v1.

- **Endpoint**: `POST https://fcm.googleapis.com/v1/projects/{project_id}/messages:send`
- **Auth**: OAuth2 access token minted from a service account JSON key. Scope: `https://www.googleapis.com/auth/firebase.messaging`. Tokens last ~1 hour; refresh before expiry from your backend (Google Auth libraries handle this — `google-auth-library` (Node), `google.oauth2.service_account.Credentials` (Python), `GoogleCredentials.fromStream` (Java)).
- **Header**: `Authorization: Bearer <access_token>` and `Content-Type: application/json`.
- **Payload shape**:

```json
{
  "message": {
    "token": "<device token>",
    "notification": { "title": "...", "body": "..." },
    "data": { "deeplink": "shop/coins" },
    "android": { "priority": "high" },
    "apns": { "payload": { "aps": { "content-available": 1 } } }
  }
}
```

- The old `https://fcm.googleapis.com/fcm/send` shape with `Authorization: key=<server_key>` is dead. If a backend you inherited still uses it, that is the bug — there is no "fall back" mode.

## APNs (iOS push)
- Generate an APNs key (.p8) in Apple Developer; upload to Firebase Console → Cloud Messaging.
- Same Firebase SDK on the client; Firebase routes through APNs under the hood.
- Request `RemoteNotification` capability in iOSNotificationCenter setup; declare push capability in Xcode (unity-build can stamp this).
- **Token-based vs cert-based auth.** Token-based (.p8) is the recommended path: one key per team, lasts indefinitely until revoked, signs JWTs your backend mints per request. Cert-based (.p12) expires yearly and forces a manual rotation cadence — avoid for new integrations.
- **Direct APNs HTTP/2** (if you bypass Firebase): `https://api.push.apple.com/3/device/<token>` (production) and `https://api.sandbox.push.apple.com/3/device/<token>` (sandbox). One .p8 key allows ~10 simultaneous HTTP/2 connections per Apple's quota; pool connections aggressively.

## Push token registration (idempotency)

Clients retry token uploads (boot, foreground after long background, `OnTokenRefresh`). Your backend keys the token row by `(userId, deviceId)` and updates the token in place — never insert a new row per upload. Without this you accumulate stale tokens per user and end up sending duplicate pushes (or worse, pushing to a device the user uninstalled). Cross-link `unity-iap` for the same idempotency pattern on receipts.

## OneSignal (turn-key option)
- Install `com.onesignal.unity`. Configure App ID in inspector.
- Auto-handles both platforms, segments, time-zone scheduling, A/B subject lines, and the dashboard for non-engineers to author campaigns.
- Best when you don't want to run your own backend for sending. Read the privacy implications — OneSignal sees device IDs and usage tags.

## Channels (Android 8+) and categories (iOS)
- **Android channel**: `default`, `marketing`, `gameplay`. Users can disable per-channel in system settings — group similar notifications so a marketing opt-out doesn't kill your gameplay reminders.
- Create channels at first launch (idempotent); set sound, vibration, importance per channel.
- **iOS categories**: define action buttons per category (`Play Now` / `Dismiss`). Register categories at startup before scheduling.

## Deep linking from notification
- Notification payload includes a custom data field, e.g. `{ "deeplink": "shop/coins" }`.
- On launch from a notification, read intent extras (Android `GetLastNotificationIntent`) / launch options (iOS `GetLastRespondedNotification`) → route to the correct scene via unity-scenes.
- Cold launch vs warm launch differ — handle both. Warm launch fires while app is alive; cold launch must defer routing until your boot scene finishes.

## Silent push
- Background data update without UI alert — refresh game state, deliver server config, prime caches.
- iOS: `content-available: 1` flag on the payload; system rate-limits delivery (don't rely on every silent push arriving).
- Android: `data-only` payload via FCM (no `notification` key, only `data`).
- Background app refresh disabled by user → silent push doesn't fire. Treat as best-effort.

## Common patterns
- **Energy / lives refill** — schedule local notification at refill time on `OnApplicationPause(true)`. Cancel on resume if already spent.
- **Daily login reminder** — D1 push with personalized reward preview ("Your 50 gems are waiting").
- **Win-back** — D3, D7, D14 server-side push to lapsed users with escalating incentives.
- **Limited offer** — server push when daily store rotates or a flash sale starts.
- **Live event** — server push on event start ("Tournament begins! Top 100 wins skin").
- Always include a deep link → tap goes to the relevant screen, not just the main menu. A win-back push that drops you on the title screen is wasted.

## Gotchas
- Permission denied = no notifications ever; can only re-prompt by sending the user to Settings. Pre-prime to avoid this.
- Local notifications may fire while app is foregrounded — handle gracefully (suppress or convert to in-game toast; don't show a duplicate banner).
- Background app refresh disabled = silent push doesn't fire; do not rely on silent push for required state.
- APNs key (.p8) does not expire, but the older APNs cert (.p12) flow does — yearly renewal. Prefer .p8.
- GDPR: marketing notifications without consent = problem in EU. Tie marketing channel/category enrolment to consent state from unity-consent-att-gdpr. Gameplay reminders (energy full) are typically fine without marketing consent.
- Aggressive push = uninstall. Cap to ~1/day per user, allow per-category opt-out, respect frequency caps server-side.
- Time zone: schedule by the player's local time, not UTC. Players in JP must get marketing at 9am their time, not 1am.
- Android notification icon: requires a monochrome white-on-transparent small icon; falls back to default app icon if missing and looks broken. Add in `res/drawable`.
- iOS quiet hours / Focus mode: the OS suppresses; respect this and don't try to bypass via critical alerts unless you actually qualify (you don't).
- FCM token rotates. Refresh and re-upload on `OnTokenRefresh`; stale tokens silently no-op server-side.
- AndroidManifest needs `POST_NOTIFICATIONS` permission entry for Android 13+; Info.plist needs `UIBackgroundModes` → `remote-notification` for silent push. Stamp via unity-build post-process.

## Verification
- Permission grant → token returned → backend has token mapped to playerID.
- Local notification scheduled → fires at expected time (test with a 30-second delay first).
- Server push sent (Firebase console → Send test message) → arrives within seconds → tap deep links correctly to the expected scene.
- Channel disabled in system settings → notifications in that channel don't appear; other channels still work.
- Cold-launch deep link routes correctly (force-quit, send push, tap from lock screen).
- Crashlytics (unity-crash-reporting) clean of notification-related exceptions.
- Open events logged to analytics (unity-analytics-events) with the campaign ID for attribution.

## Cross-links
- unity-consent-att-gdpr — gate marketing notifications on consent state.
- unity-scenes — deep-link routing from notification payload to the right scene.
- unity-analytics-events — log `notification_open` events with campaign ID and deep-link target.
- unity-build — Info.plist `UIBackgroundModes`, AndroidManifest `POST_NOTIFICATIONS`, push capability stamping.
- unity-best-practices — read console, batch_execute, render-pipeline detection still apply.

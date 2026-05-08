---
name: unity-analytics-events
description: Use when wiring analytics, attribution, and event taxonomy in a Unity F2P game through Unity MCP — anything involving analytics, Firebase Analytics, GameAnalytics, Unity Analytics, Adjust, AppsFlyer, Singular, Branch, attribution, install attribution, SKAdNetwork, SKAN, SKAN 4, conversion value, postback, custom event, log event, session start, session end, retention, D1, D7, D30, DAU, MAU, ARPU, ARPDAU, LTV, funnel, funnel event, economy event, currency, virtual currency, sink, source, IAP event, ad impression event, level start, level complete, tutorial complete, A/B variant exposure, event taxonomy, event schema, event batching, offline event queue. Unity 6 / 2023.2 LTS, URP-only, new Input System only. NOT for crash reporting (use unity-crash-reporting), NOT for A/B test variant assignment (use unity-ab-testing — though analytics LOGS variant exposure events).
---

# Unity Analytics & Attribution Events

## When to use
F2P depends on UA (User Acquisition) campaigns. Without attribution data you cannot measure ROAS (Return On Ad Spend), cannot optimize ad creatives, cannot justify spend. Without funnel events you do not know where players drop off in the tutorial. Wire analytics + attribution before any paid UA spend; retrofitting after launch loses you weeks of cohort data.

## Pick a stack
- **Firebase Analytics + Adjust or AppsFlyer** — most common F2P stack. Firebase is free with unlimited events; Adjust/AppsFlyer is paid attribution but cheap relative to UA spend.
- **GameAnalytics** — free, gaming-focused, decent for indies but limited segmentation.
- **Unity Analytics** (Unity Cloud Services) — was deprecated then re-introduced; usable but Firebase has more ecosystem.
- **Singular** — alternative to Adjust/AppsFlyer.

Default recommendation: Firebase Analytics for events + Adjust or AppsFlyer for install attribution. Wire both behind one `AnalyticsManager`.

## Firebase Analytics
Install `com.google.firebase.analytics`. Initialize once at boot:
```csharp
FirebaseApp.CheckAndFixDependenciesAsync().ContinueWithOnMainThread(t => {
    if (t.Result == DependencyStatus.Available) { /* ready */ }
});
```
Log events:
```csharp
FirebaseAnalytics.LogEvent("level_complete", new Parameter[] {
    new Parameter("level_index", 5),
    new Parameter("score", 1200)
});
```
Set user properties (limited slots; use for segmentation):
```csharp
FirebaseAnalytics.SetUserProperty("favorite_class", "rogue");
FirebaseAnalytics.SetUserId(playerGUID); // same as Crashlytics
```

## Adjust / AppsFlyer for attribution
- **Adjust** — `com.adjust.unity` package; init with App Token + environment (sandbox/production). Tracks installs, sessions, in-app events. Handles SKAN postbacks, deep links, cross-device.
- **AppsFlyer** — `com.appsflyer.unity` package; Dev Key + App ID. Strong UA attribution, broad ad-network integration.
Both auto-attribute install source from ad clicks. You log purchase + key events for ROAS computation; their dashboards join those to ad spend.

## Event taxonomy (CRITICAL — design before logging)
- Naming convention: `snake_case`, action-noun pairs (`level_complete`, `iap_started`, `ad_shown`, `tutorial_step_1_complete`).
- Document every event in a shared spreadsheet: name, parameters, when fired, why (which question it answers).
- Keep parameter names consistent across events: `level_index` (int), `score` (int), `currency_amount` (long), `currency_type` (string enum), `iap_sku` (string), `ad_placement` (string), `error_code` (string).
- **Reserved Firebase event names** — do not override: `app_open`, `screen_view`, `purchase`, `tutorial_begin`, `tutorial_complete`, `level_start`, `level_end`, `unlock_achievement`, `earn_virtual_currency`, `spend_virtual_currency`, `ad_impression`, `ad_click`, `ad_reward`.

## Standard events vs custom events
- Use Firebase's standard events when they fit (`level_start`, `purchase`, `earn_virtual_currency`, `spend_virtual_currency`) — they auto-populate Firebase's pre-built reports.
- Custom events for everything else; cap event-name count at ~500 distinct names (Firebase limit).
- Per event: cap 25 parameters; parameter-name length 40 chars; values up to 100 chars.

## Economy events (foundation for monetization)
- `earn_virtual_currency` — `source` (level_reward / quest_reward / iap / ad_reward), `currency_amount`, `currency_type`.
- `spend_virtual_currency` — `sink` (shop_item / energy / continue / unlock), `currency_amount`, `currency_type`, `item_id`.
- Daily aggregate: net flow per source/sink. Spot inflation (too much earned), broken sinks (nobody spends on X), or imbalanced rewards.

## Funnel events
- **Tutorial steps**: `tutorial_step_<n>_started` / `tutorial_step_<n>_completed`. Plot the dropoff curve.
- **Onboarding**: `app_install` (auto), `first_launch_complete`, `first_session_end`, `tutorial_complete`, `first_iap`.
- **Level**: `level_start` (level_index, retry_count), `level_complete` (duration, score), `level_fail` (death_reason).
- **Shop**: `shop_opened`, `shop_item_clicked`, `iap_started` (sku), `iap_completed` (sku, currency, price). Cross-link unity-iap.

## Session and retention
- Firebase auto-logs `session_start` / `session_end` (default 30s timeout — backgrounded longer than that starts a new session).
- Retention is computed from `app_open` + user_id; Firebase shows D1/D7/D30 in Audiences.
- DAU = unique user_ids per day; MAU = per month; DAU/MAU ratio = stickiness.

## SKAdNetwork / SKAN (iOS post-IDFA attribution)
- Apple's privacy-preserving attribution; ad networks send postbacks to your conversion endpoint.
- SKAN 4 (current spec) supports up to 3 postback windows + hierarchical conversion values + crowd anonymity tiers.
- Configure conversion value mapping: tutorial complete -> CV 1; first IAP -> CV 4; D7 retention -> CV 8. Postbacks arrive 24-48h later, batched.
- Most ad SDKs auto-handle SKAN; you set the conversion model in their dashboard.

## Batching and offline queue
- Firebase batches events automatically; flushes ~1 event/second or on app background.
- Custom analytics endpoint (internal events): batch locally, flush on background, retry with exponential backoff. Cross-link unity-persistence (offline queue file on `Application.persistentDataPath`).
- Do not log every frame — batch high-frequency events client-side, send aggregates.

## Common patterns
- **AnalyticsManager singleton** that wraps Firebase + Adjust + custom endpoint. All gameplay code calls `Analytics.Log("event_name", params)`. Future provider swaps stay scoped to one file.
- **Event-name constants** — central `AnalyticsEvents.cs` with `public const string LEVEL_COMPLETE = "level_complete";` to kill taxonomy drift.
- **Event schema validation** in dev builds: assert event name + parameters match the catalog. Cross-link unity-tests.
- **A/B variant exposure event** when player enters a feature (cross-link unity-ab-testing) — fires once per session per variant.
- **First-launch funnel** wired tightly: `app_install` -> `first_session_start` -> `tutorial_begin` -> `tutorial_step_1` ... -> `tutorial_complete` -> `level_1_start` -> `level_1_complete` -> `first_iap_offer_shown`. Each step is a chance to lose the player; instrument every one.

## Gotchas
- **GDPR/CCPA/ATT denial gates analytics**. Disable Firebase Analytics collection if user opts out: `FirebaseAnalytics.SetAnalyticsCollectionEnabled(false)`. Cross-link unity-consent-att-gdpr.
- Default Firebase retention is 14 months free; longer requires GA4 paid export to BigQuery.
- Reserved event names misused = data shows up in the wrong reports.
- Logging PII (email, name, IP) violates terms and GDPR. Use anonymous user_id (GUID).
- **Event taxonomy drift** — different team members log slightly different names (`level_done` vs `level_complete`). Centralize via constants or enum; review in code review.
- Editor + Editor-PlayMode events leak into production stream if not gated. Use `#if !UNITY_EDITOR` or set Firebase environment to debug. Same for Adjust sandbox vs production.
- Adjust/AppsFlyer SKAN setup misconfigured = bad attribution and lost UA optimization. Verify with their dashboard's SKAN tester before paid spend.
- Storing too many custom user properties hits per-user limits silently — events still log but extra properties drop.
- Logging from a thread other than main may crash native analytics SDKs — queue to main thread (`UnityMainThreadDispatcher` or similar).
- High-volume events (per-frame logging, debug spam) burn through your event quota and pollute dashboards. Sample or aggregate.

## Verification
- **Firebase DebugView** (real-time event stream): trigger event in app -> appears within seconds. Enable with `adb shell setprop debug.firebase.analytics.app <package>` on Android, or `-FIRDebugEnabled` launch arg on iOS.
- **Adjust testing console / AppsFlyer Live View**: simulated install -> install attributed within minutes.
- **Funnel report in Firebase**: drop-off rate sane (60-80% complete tutorial, 30-50% reach level 5). If 100% complete tutorial, you are missing the dropoff event; if 0% reach level 5, the event is misnamed.
- **SKAN postback received** in ad SDK dashboard 24-48h post-install. If none, conversion value is never being set or postback URL is wrong.
- **Event count per user is reasonable** (not 10k events/session — that is a bug, almost always a per-frame log).

Cross-link **unity-iap** (purchase events), **unity-ads-mediation** (ad impression / reward events), **unity-consent-att-gdpr** (opt-out gating), **unity-crash-reporting** (parallel custom keys + user_id), **unity-ab-testing** (variant exposure events), **unity-persistence** (offline event queue file), **unity-auth-account-linking** (anonymous user_id source), **unity-best-practices**.

---
name: unity-analytics-events
description: 'Use for Unity 6+ F2P analytics and attribution: Firebase/GameAnalytics/Unity Analytics, Adjust/AppsFlyer/SKAN, event taxonomy, funnels, retention, economy/IAP/ad events, variant exposure, batching/offline queues. Not crash reporting or A/B assignment.'
---

# Unity Analytics & Attribution Events

## When to use
F2P depends on UA campaigns. Without attribution: no ROAS measurement, no creative optimization, no spend justification. Without funnel events: no dropoff visibility. Wire analytics + attribution before any paid UA spend; retrofitting loses weeks of cohort data.

## Pick a stack
- **Firebase Analytics + Adjust or AppsFlyer** — most common F2P stack. Firebase free with unlimited events; Adjust/AppsFlyer paid attribution but cheap relative to UA spend.
- **GameAnalytics** — free, gaming-focused, decent for indies; limited segmentation.
- **Unity Analytics** (UGS) — was deprecated then re-introduced; usable but Firebase has more ecosystem.
- **Singular** — alternative to Adjust/AppsFlyer.

Default: Firebase Analytics + Adjust or AppsFlyer behind one `AnalyticsManager`.

## Firebase Analytics
Install `com.google.firebase.analytics`. Initialize at boot:
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
User properties (limited slots):
```csharp
FirebaseAnalytics.SetUserProperty("favorite_class", "rogue");
FirebaseAnalytics.SetUserId(playerGUID); // same as Crashlytics
```

## Adjust / AppsFlyer for attribution
- **Adjust** — `com.adjust.unity`; init with App Token + environment (sandbox/production). Tracks installs, sessions, in-app events. SKAN postbacks, deep links, cross-device.
- **AppsFlyer** — `com.appsflyer.unity`; Dev Key + App ID. Strong UA attribution, broad ad-network integration.

Both auto-attribute install source from ad clicks. You log purchase + key events for ROAS; their dashboards join those to ad spend.

## Event taxonomy (design before logging)
- Naming: `snake_case`, action-noun pairs (`level_complete`, `iap_started`, `ad_shown`, `tutorial_step_1_complete`).
- Document every event in a shared sheet: name, parameters, when fired, why.
- Consistent parameter names across events: `level_index` (int), `score` (int), `currency_amount` (long), `currency_type` (string enum), `iap_sku` (string), `ad_placement` (string), `error_code` (string).
- **Reserved Firebase event names** — do not override: `app_open`, `screen_view`, `purchase`, `tutorial_begin`, `tutorial_complete`, `level_start`, `level_end`, `unlock_achievement`, `earn_virtual_currency`, `spend_virtual_currency`, `ad_impression`, `ad_click`, `ad_reward`.

## Standard vs custom events
- Use Firebase standard events when they fit (`level_start`, `purchase`, `earn_virtual_currency`, `spend_virtual_currency`) — they auto-populate pre-built reports.
- Custom events for everything else; cap event-name count at ~500 distinct (Firebase limit).
- Per event: 25 parameters max; parameter-name length 40; values 100.

## Economy events
- `earn_virtual_currency` — `source` (level_reward / quest_reward / iap / ad_reward), `currency_amount`, `currency_type`.
- `spend_virtual_currency` — `sink` (shop_item / energy / continue / unlock), `currency_amount`, `currency_type`, `item_id`.
- Daily aggregate: net flow per source/sink. Spot inflation, broken sinks, imbalanced rewards.

## Funnel events
- **Tutorial steps**: `tutorial_step_<n>_started` / `tutorial_step_<n>_completed`. Plot dropoff.
- **Onboarding**: `app_install` (auto), `first_launch_complete`, `first_session_end`, `tutorial_complete`, `first_iap`.
- **Level**: `level_start` (level_index, retry_count), `level_complete` (duration, score), `level_fail` (death_reason).
- **Shop**: `shop_opened`, `shop_item_clicked`, `iap_started` (sku), `iap_completed` (sku, currency, price). See `unity-iap`.

## Session and retention
- Firebase auto-logs `session_start` / `session_end` (default 30s timeout).
- Retention computed from `app_open` + user_id; D1/D7/D30 in Audiences.
- DAU = unique user_ids/day; MAU = /month; DAU/MAU = stickiness.

## SKAdNetwork / SKAN (iOS post-IDFA)
- Apple's privacy-preserving attribution; ad networks send postbacks to your conversion endpoint.
- SKAN 4 (current) supports up to 3 postback windows + hierarchical conversion values + crowd anonymity tiers.
- Configure conversion mapping: tutorial complete → CV 1; first IAP → CV 4; D7 retention → CV 8. Postbacks 24-48h later, batched.
- Most ad SDKs auto-handle SKAN; set the conversion model in their dashboard.

## Batching and offline queue
- Firebase batches events automatically; flushes ~1/sec or on app background.
- Custom analytics endpoint: batch locally, flush on background, retry exponential backoff. Offline queue file on `Application.persistentDataPath` (`unity-persistence`).
- Don't log every frame — batch high-frequency events client-side, send aggregates.

## Common patterns
- **AnalyticsManager singleton** wrapping Firebase + Adjust + custom endpoint. All gameplay calls `Analytics.Log("event_name", params)`. Provider swaps stay scoped.
- **Event-name constants** — central `AnalyticsEvents.cs` with `public const string LEVEL_COMPLETE = "level_complete";` to kill drift.
- **Event schema validation** in dev builds: assert event name + parameters match catalog. See `unity-tests`.
- **A/B variant exposure event** when player enters a feature (`unity-ab-testing`) — fires once per session per variant.
- **First-launch funnel**: `app_install` → `first_session_start` → `tutorial_begin` → `tutorial_step_1` → ... → `tutorial_complete` → `level_1_start` → `level_1_complete` → `first_iap_offer_shown`. Instrument every step.

## Gotchas
- **GDPR/CCPA/ATT denial gates analytics**. Disable Firebase collection if user opts out: `FirebaseAnalytics.SetAnalyticsCollectionEnabled(false)`. See `unity-consent-att-gdpr`.
- Default Firebase retention 14 months free; longer requires GA4 paid export to BigQuery.
- Reserved event names misused = data shows in wrong reports.
- Logging PII (email, name, IP) violates terms + GDPR. Anonymous user_id (GUID).
- **Event taxonomy drift** — `level_done` vs `level_complete`. Centralize via constants/enum.
- Editor + PlayMode events leak into prod stream if not gated. `#if !UNITY_EDITOR` or set Firebase to debug. Same for Adjust sandbox vs production.
- Adjust/AppsFlyer SKAN misconfig = bad attribution. Verify with their SKAN tester before paid spend.
- Too many custom user properties hits per-user limits silently.
- Logging from non-main thread may crash native SDKs — queue to main (`UnityMainThreadDispatcher`).
- High-volume events (per-frame, debug spam) burn quota and pollute dashboards. Sample or aggregate.

## Verification
- **Firebase DebugView** (real-time): trigger event → appears in seconds. Enable: `adb shell setprop debug.firebase.analytics.app <package>` (Android) or `-FIRDebugEnabled` launch arg (iOS).
- **Adjust testing console / AppsFlyer Live View**: simulated install → attributed within minutes.
- **Funnel report** in Firebase: dropoff sane (60-80% complete tutorial, 30-50% reach level 5). 100% complete = missing dropoff event; 0% reach = misnamed event.
- **SKAN postback received** in ad SDK dashboard 24-48h post-install. None = conversion value not set or postback URL wrong.
- **Event count per user reasonable** (not 10k events/session — that's a per-frame log bug).

Cross-link **unity-iap** (purchase events), **unity-ads-mediation** (ad impression / reward), **unity-consent-att-gdpr** (opt-out gating), **unity-crash-reporting** (parallel custom keys + user_id), **unity-ab-testing** (variant exposure), **unity-persistence** (offline queue), **unity-auth-account-linking** (anonymous user_id source), **unity-best-practices**.

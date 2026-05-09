---
name: unity-remote-config-flags
description: 'Use for Unity 6+ server-driven config and feature flags: Firebase Remote Config, Unity Game Overrides/Cloud Code, killswitches, conditional values, segmentation, fetch/activate, defaults, hotfix flags, schemas, config exposure. Not metrics-based A/B assignment.'
---

# Unity Remote Config & Feature Flags

## When to use
Without remote config, every economy bug, broken feature, or pricing tweak requires a store update (1-7 day review). With it, fix in seconds. Wire before launch — cannot retrofit a killswitch after the bug ships. Every risky system gets a flag from day one.

## Pick a service
- **Firebase Remote Config** — free, deep Firebase integration, condition-based segmentation, audience targeting via Analytics user properties. Most common F2P. Pairs cleanly with Firebase A/B Testing (`unity-ab-testing`).
- **Unity Cloud Code + Game Overrides** — UGS-native; integrated with Unity Authentication. Pick if all-in on UGS.
- **Roll-your-own JSON-from-CDN** — simplest (publish JSON to Cloudflare R2, fetch on boot), no segmentation, no console UI. Fine for tiny indie titles, painful at scale.

Default: Firebase Remote Config behind a typed `Config` accessor.

## Firebase Remote Config integration
Install `com.google.firebase.remoteconfig` (matched to `com.google.firebase.app`). After Firebase init:
```csharp
var config = FirebaseRemoteConfig.DefaultInstance;
var defaults = new Dictionary<string, object> {
    { "iap_double_coins_enabled", false },
    { "ad_interstitial_cap_seconds", 60 },
    { "energy_max", 5 },
    { "boss_difficulty_multiplier", 1.0f },
    { "shop_layout_json", "{\"version\":1,\"items\":[]}" }
};
await config.SetDefaultsAsync(defaults);
await config.FetchAndActivateAsync();
```
Read:
```csharp
long energyMax       = config.GetValue("energy_max").LongValue;
double bossMult      = config.GetValue("boss_difficulty_multiplier").DoubleValue;
string shopJson      = config.GetValue("shop_layout_json").StringValue;
bool doubleCoins     = config.GetValue("iap_double_coins_enabled").BooleanValue;
byte[] blob          = config.GetValue("packed_payload").ByteArrayValue;
```

## Unity Cloud Code / Game Overrides
- Install `com.unity.services.remoteconfig`. Initialize Unity Services + sign in via Authentication.
- Push values via Unity Dashboard → Remote Config; segment by Game Override rules (audience, A/B, schedule).
- API:
```csharp
await RemoteConfigService.Instance.FetchConfigsAsync(new userAttributes(), new appAttributes());
int energy = RemoteConfigService.Instance.appConfig.GetInt("energy_max", 5);
```
- Game Overrides apply rule-based deltas (e.g. boost weekend XP for users in Europe).

## Default values + caching
- **Always ship in-app defaults.** First fetch fails (offline first run) → defaults apply, game works. Forgetting = NullReferenceException or zeroed economy on day one.
- Last fetched values cached locally; survive offline restart. Returning player sees their last successful fetch, not defaults.
- Minimum fetch interval: Firebase defaults to 12h (backend throttle). Override during dev:
```csharp
await config.FetchAsync(TimeSpan.Zero); // dev only — production stays at 12h
```

## Fetch + activate lifecycle
Two-step on purpose:
- `FetchAsync` downloads new values into staging; live values unchanged.
- `ActivateAsync` swaps staging into live. Lets you fetch silently in background and activate at safe boundaries (between rounds, on next scene load, foreground) — never mid-fight.

Boot:
```csharp
await config.SetDefaultsAsync(defaults);
await config.FetchAsync(TimeSpan.FromHours(12));
await config.ActivateAsync();
ConfigChanged?.Invoke();
```
Long-session: re-fetch every ~12h on background coroutine, defer activate to next safe transition.

## Segmentation and conditions
Firebase console → Remote Config → Conditions. Match by:
- App version (target only ≥1.2.3).
- Country / region (price localization, regulatory carve-outs).
- Language.
- User property — any property set via `FirebaseAnalytics.SetUserProperty`. Powers custom audience segmentation (whales, churned, tutorial-completed).
- Audience — Firebase Analytics audience definitions (e.g. "spent >$10 in 30d").
- Random percentile — bucket 0-100 for A/B splits (basis Firebase A/B Testing builds on).
- Platform — iOS / Android / Editor.

Different parameter values per condition; SDK returns matching variant per user.

## Killswitches
Every risky system gets a boolean flag from day one. Convention: `feature_<X>_enabled`.
```csharp
public static class Config {
    public static bool IapDoubleCoinsEnabled =>
        FirebaseRemoteConfig.DefaultInstance.GetValue("iap_double_coins_enabled").BooleanValue;
    public static bool NewBossEncounterEnabled =>
        FirebaseRemoteConfig.DefaultInstance.GetValue("feature_boss_v2_enabled").BooleanValue;
}

if (!Config.NewBossEncounterEnabled) {
    LoadLegacyBoss();
    return;
}
```
On a critical bug, flip to false in console → next user fetch disables the buggy path. Default `false`, flip to `true` once verified — fail closed.

## Common patterns
- **Typed accessor** — `Config` static class returning correct types with default fallbacks. Single source of truth; refactor-safe; testable.
- **OnConfigUpdated event** — Firebase 9.0+ exposes a real-time `OnConfigUpdated` when values change server-side. Subscribe to invalidate cached config-derived state.
- **Hotfix workflow** — ship buggy 1.2.0 → bug discovered → flip killswitch → users fetch within 12h → buggy path skipped → ship 1.2.1 at leisure.
- **Pricing experiments** — store sells 100 coins for $0.99; condition-target 5% to `coin_pack_sku = "coins_100_v2"` mapping to $1.99. Measure ARPDAU lift.
- **Tunable curves** — boss HP, energy regen, daily quest count. Designers tune in console.
- **JSON blobs** — `shop_layout_json` for entire screen layouts (offer order, banner copy, art keys). Re-skin without a build.
- **Config version exposure** — log `config_version` user property + `config_exposure` event so analytics can attribute KPI shifts to specific rollouts.

## Gotchas
- **Forgetting defaults** = NullReferenceException or zero values on offline first run. Defaults before any read.
- **Fetching too often** = Firebase throttles to 12h on production tier. `FetchAsync(TimeSpan.Zero)` works in dev but errors in prod.
- **Activating mid-gameplay** confuses players. Activate at safe boundaries.
- **Type coercion** — `GetValue("x").DoubleValue` on non-numeric string returns 0 silently; `BooleanValue` on non-bool returns false. Validate types match what console publishes.
- **Editor + production share Firebase backend** by default. Stage values via separate Firebase projects per environment (dev / staging / prod) and select the right `google-services.json` per build.
- **Cache survives uninstall** on iOS via Keychain backup in some configs. Returning user can resume with old config until next fetch.
- **Firebase A/B-managed parameters** — when an A/B is active, console-edited values don't apply to enrolled users (experiment owns them). Pause experiment first.
- **Boolean parsed from string** — value typed as `"true"` (string) returns `BooleanValue = false` in some SDK versions. Use JSON Boolean explicitly.
- **Real-time RC** raises `OnConfigUpdated` but values aren't auto-activated; still call `ActivateAsync()` at safe moment.
- **Defaults file vs dictionary** — both work; XML defaults file is gitignore-friendly and survives SDK upgrades better.

## Verification
- Boot offline (airplane mode) on fresh install → defaults apply, no nullrefs, game playable.
- Change a value in console → wait 12h or force-fetch in debug → value changes in-app.
- Killswitch test: flip flag → confirm code path skips on next fetch+activate.
- Conditions: target 1% by random percentile → spin up 10 test devices → roughly 1 device sees variant value (probabilistic).
- Log `config_version` user property + `config_fetched` event; confirm in Firebase Analytics within minutes.
- Offline behavior: fetch values, kill network, restart app → cached fetched values persist (not defaults).

Cross-link: unity-ab-testing (paired — A/B builds on Remote Config), unity-analytics-events (config-version exposure + user properties), unity-best-practices.

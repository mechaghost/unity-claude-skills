---
name: unity-remote-config-flags
description: Use when wiring server-driven runtime configuration and feature flags into a Unity F2P game through Unity MCP — anything involving remote config, Firebase Remote Config, Unity Cloud Code, Game Overrides, feature flag, killswitch, server-driven config, runtime config, config update, parameter override, conditional value, segmentation, audience, A/B parameter, default values, fetched values, fetch and activate, GameAnalytics Remote Config, in-app default, hotfix flag, feature toggle, config schema, parameter group, config version, config exposure. Unity 6 / 2023.2 LTS, URP-only, new Input System only. NOT for A/B test variant assignment with metrics analysis (use unity-ab-testing — though they pair on the same backend).
---

# Unity Remote Config & Feature Flags

## When to use
Live-ops survival without remote config = every economy bug, broken feature, or pricing tweak requires a store update (1-7 day review). With remote config, you fix in seconds. Wire it before launch — you cannot retrofit a killswitch after the bug ships. Every risky system (new IAP, new boss, new ad placement) gets a flag from day one.

## Pick a service
- **Firebase Remote Config** — free, deep Firebase integration, condition-based segmentation, audience targeting via Firebase Analytics user properties. Most common F2P choice. Pairs cleanly with Firebase A/B Testing (see unity-ab-testing).
- **Unity Cloud Code + Game Overrides** — Unity Gaming Services native; integrated with Unity Authentication; less common in F2P but improving. Pick if you are all-in on UGS.
- **Roll-your-own JSON-from-CDN** — simplest (publish a JSON to Cloudflare R2, fetch on boot), but no segmentation, no console UI, no audience targeting. Fine for tiny indie titles, painful at scale.

Default recommendation: Firebase Remote Config behind a typed `Config` accessor.

## Firebase Remote Config integration
Install `com.google.firebase.remoteconfig` (matched to your `com.google.firebase.app` version). After Firebase init succeeds:
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
Read values:
```csharp
long energyMax       = config.GetValue("energy_max").LongValue;
double bossMult      = config.GetValue("boss_difficulty_multiplier").DoubleValue;
string shopJson      = config.GetValue("shop_layout_json").StringValue;
bool doubleCoins     = config.GetValue("iap_double_coins_enabled").BooleanValue;
byte[] blob          = config.GetValue("packed_payload").ByteArrayValue;
```

## Unity Cloud Code / Game Overrides
- Install `com.unity.services.remoteconfig`. Initialize Unity Services + sign in via Authentication.
- Push values via the Unity Dashboard → Remote Config; segment by Game Override rules (audience, A/B, schedule).
- API:
```csharp
await RemoteConfigService.Instance.FetchConfigsAsync(new userAttributes(), new appAttributes());
int energy = RemoteConfigService.Instance.appConfig.GetInt("energy_max", 5);
```
- Game Overrides apply rule-based deltas (e.g. boost weekend XP for users in Europe).

## Default values + caching
- **Always ship in-app defaults.** If the very first fetch fails (offline first run), defaults apply and the game still functions. Forgetting defaults = NullReferenceException or zeroed economy on day one.
- Last fetched values are cached locally by the SDK; survive offline restart. A returning player who flew on a plane sees the values from their last successful fetch, not defaults.
- Minimum fetch interval: Firebase defaults to 12h (throttled by backend). Override during dev for live testing:
```csharp
await config.FetchAsync(TimeSpan.Zero); // dev only — production stays at 12h
```

## Fetch + activate lifecycle
Two-step on purpose:
- `FetchAsync` downloads new values into a staging buffer; live values do not change.
- `ActivateAsync` swaps staging into live values. Lets you fetch silently in the background and activate at a safe boundary (between rounds, on next scene load, on app foreground) — never mid-fight.

Typical boot flow:
```csharp
await config.SetDefaultsAsync(defaults);
await config.FetchAsync(TimeSpan.FromHours(12));
await config.ActivateAsync();
ConfigChanged?.Invoke();
```
Long-session flow: re-fetch every ~12h on a background coroutine, defer activate to next safe transition.

## Segmentation and conditions
Firebase console → Remote Config → Conditions tab. Match by:
- App version (target only ≥1.2.3; older clients keep old values).
- Country / region (price localization, regulatory carve-outs).
- Language.
- User property — any property you set via `FirebaseAnalytics.SetUserProperty`. Powers custom audience segmentation (whales, churned, tutorial-completed).
- Audience — Firebase Analytics audience definitions (e.g. "spent >$10 in 30d").
- Random percentile — bucket 0–100 for A/B splits (the basis Firebase A/B Testing builds on).
- Platform — iOS vs Android vs Editor.

Different parameter values per condition; the SDK returns the matching variant per user.

## Killswitches
Every risky system gets a boolean flag from day one. Naming convention: `feature_<X>_enabled`.
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
On a critical bug, flip to false in console → next user fetch disables the buggy code path while you prep the patch. Default the flag to `false` and flip to `true` once verified — fail closed.

## Common patterns
- **Typed accessor** — wrap reads in a `Config` static class returning correct types with default fallbacks. Single source of truth; refactor-safe; testable.
- **OnConfigUpdated event** — Firebase exposes a real-time `OnConfigUpdated` event when values change server-side (Firebase 9.0+ real-time RC). Subscribe to invalidate cached config-derived state (rebuild shop UI, recompute curves).
- **Hotfix workflow** — ship buggy 1.2.0 → bug discovered → flip killswitch in Firebase → users fetch within 12h → buggy code path skipped → prep + ship 1.2.1 at leisure.
- **Pricing experiments** — store sells 100 coins for $0.99 baseline; condition-target a 5% audience to a `coin_pack_sku = "coins_100_v2"` that maps to a $1.99 SKU. Measure ARPDAU lift.
- **Tunable curves** — boss HP, energy regen rate, daily quest count — all live in remote config. Designers tune in console without an engineer.
- **JSON blobs** — `shop_layout_json` returns a stringified JSON for entire screen layouts (offer order, banner copy, art keys). Re-skin the shop without a build.
- **Config version exposure** — log `config_version` user property + `config_exposure` event so analytics can attribute KPI shifts to specific config rollouts.

## Gotchas
- **Forgetting defaults** = NullReferenceException or zero values on offline first run. Set defaults before any read.
- **Fetching too often** = Firebase throttles to 12h minimum on production tier. `FetchAsync(TimeSpan.Zero)` works in dev but errors in prod.
- **Activating mid-gameplay** confuses players ("why did the boss just get harder?"). Activate at safe boundaries: app foreground, level select, after death.
- **Type coercion** — `GetValue("x").DoubleValue` on a non-numeric string returns 0 silently; `BooleanValue` on a non-bool returns false. Validate types match what the console publishes.
- **Editor + production builds share the same Firebase backend** by default. Stage values via separate Firebase projects per environment (dev / staging / prod) and select the right `google-services.json` per build target. Otherwise designers tweaking dev affect live users.
- **Cache survives uninstall** on iOS via Keychain backup in some configurations. Rare, but a returning user can resume with old config values until the next fetch.
- **Firebase A/B-managed parameters** — when an A/B test is active on a parameter, console-edited values do not apply to enrolled users (the experiment owns them). Pause the experiment first.
- **Boolean parsed from string** — value typed as `"true"` (string) in console returns `BooleanValue = false` in some SDK versions. Use the JSON Boolean type explicitly.
- **Real-time RC** raises `OnConfigUpdated` but values are not auto-activated; you still call `ActivateAsync()` at a safe moment.
- **Defaults file vs dictionary** — both work; the XML defaults file is gitignore-friendly and survives Firebase SDK upgrades better.

## Verification
- Boot offline (airplane mode) on a fresh install → defaults apply, no nullrefs, game playable.
- Change a value in Firebase console → wait 12h or force-fetch in a debug build → value changes in-app.
- Killswitch test: flip flag in console → confirm code path skips on next fetch+activate.
- Conditions: target only 1% audience by random percentile → spin up 10 test devices → verify roughly 1 device sees the variant value (probabilistic — sample more for tighter check).
- Log `config_version` user property and `config_fetched` analytics event; confirm Firebase Analytics receives them within minutes.
- Verify offline behavior: fetch values, kill network, restart app → cached fetched values persist (not defaults).

Cross-link: unity-ab-testing (paired — A/B testing builds on Remote Config), unity-analytics-events (log config-version exposure + user properties for segmentation), unity-best-practices.

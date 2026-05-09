---
name: unity-ads-mediation
description: 'Use for Unity 6+ mobile ad mediation: AppLovin MAX, LevelPlay/ironSource, AdMob, Unity Ads, rewarded/interstitial/banner/MREC/app-open ads, eCPM waterfalls/bidding, frequency caps, test ads, ATT/consent handoff. Not IAP or analytics. Do NOT use for ATT/GDPR consent dialogs; use unity-consent-att-gdpr.'
---

F2P revenue depends on ads. Mediation routes each request through a waterfall (or in-app bidding auction); higher eCPM wins. This skill covers integration plumbing only — consent, analytics, and remote-config tuning live in their own skills.

## When to use

- New F2P needing rewarded / interstitial / banner / MREC / app open.
- Migrating mediation platforms (Unity Ads-only → MAX).
- Diagnosing low fill, low eCPM, "ad not ready" bugs.
- Wiring rewarded callbacks (double-rewards / continue / free-chest).

NOT for IAP receipts, analytics taxonomy, or the ATT/GDPR dialog itself.

## Pick a mediation platform

Pick one — running two mediation SDKs in parallel makes them fight over auctions and tanks eCPM.

- **AppLovin MAX** — most-used in mobile F2P. Broad waterfall + in-app bidding. Default pick.
- **Unity LevelPlay** (formerly IronSource) — Unity-owned, deepest Editor integration, package via Package Manager. Pick if already on UGS.
- **Google AdMob** — weaker mediation ceiling but pairs natively with Firebase Analytics + UMP. Pick if Firebase is the analytics backbone.

Unity Ads alone (without LevelPlay) isn't real mediation — only use it as a network inside one of the above.

## Package install

- **AppLovin MAX** — download AppLovin Unity SDK Manager from dashboard, drop `.unitypackage`, install adapters per network through the Manager window. MAX manages adapter versions; do not hand-install adapter `.aar`/`.framework`.
- **Unity LevelPlay** — `com.unity.services.levelplay` via Package Manager. Configure mediation in LevelPlay dashboard; package fetches runtime adapters at build.
- **AdMob** — `com.google.ads.mobile` (Google Mobile Ads Unity plugin). Use External Dependency Manager (EDM4U): `Assets/Play Services Resolver/Android Resolver/Resolve` (Android) and CocoaPods (iOS).

All three need an iOS `SKAdNetworkIdentifier` list in `Info.plist` — each platform ships an injection tool. Run before every store build.

## MAX integration boilerplate

```csharp
public class AdsBootstrap : MonoBehaviour {
    void Start() {
        MaxSdk.SetSdkKey("YOUR_SDK_KEY");
        MaxSdk.SetUserId(GameUserId);                       // for S2S reward callbacks
        MaxSdkCallbacks.OnSdkInitializedEvent += OnSdkInit;
        MaxSdk.InitializeSdk();
    }

    void OnSdkInit(MaxSdkBase.SdkConfiguration cfg) {
        if (cfg.ConsentFlowUserGeography == MaxSdkBase.ConsentFlowUserGeography.Gdpr) {
            // GDPR user — consent flow handled by AppLovin or your own UMP wrapper.
        }
        AdsService.LoadInterstitial();
        AdsService.LoadRewarded();
        AdsService.LoadBanner();
        AdsService.LoadAppOpen();
    }
}
```

Init AFTER ATT prompt on iOS (see `unity-consent-att-gdpr`). LevelPlay: `IronSource.Agent.init(appKey, IronSourceAdUnits.REWARDED_VIDEO, ...)`. AdMob: `MobileAds.Initialize(initStatus => {...})`.

## Placements and ad formats

Name placements in the network dashboard (different placements = different waterfalls + analytics segmentation). Convention: `LevelComplete_Interstitial`, `Shop_Rewarded_Coins`, `Menu_Banner_Bottom`.

| Format | Use | Cap |
| --- | --- | --- |
| Rewarded | full-screen video, opt-in for reward; highest eCPM | none — opt-in |
| Interstitial | full-screen at level transitions | ≥60s |
| Banner | persistent 320x50 (or adaptive); lowest eCPM, lowest UX impact | hide in gameplay, show in menus |
| MREC | 300x250 in shop / settings / pause | reads as content; > banner eCPM |
| App Open | on launch / foreground from background | 1 per 4h; skip first launch + IAP/store-deeplink return |

## Frequency caps and pacing

Two layers required.

- **Client-side** — `if (Time.realtimeSinceStartup - _lastInterstitialTime > 60f) Show(...)`. Use `realtimeSinceStartup` so `Time.timeScale = 0` pauses don't break it. Persist via PlayerPrefs for hours-long cooldowns (app open).
- **Server-side via remote config** — pull `interstitial_cooldown_seconds`, `rewarded_daily_cap`, `app_open_cooldown_hours` from remote config. See `unity-remote-config-flags`.

Don't hard-cap rewarded — opt-in, capping costs money for no UX gain.

## Consent integration

Without consent, ads serve at low fill (no personalization) and low eCPM (50-80% drop EU/CA).

- **iOS ATT** — BEFORE first ad request. Apple rejects apps without it. See `unity-consent-att-gdpr`.
- **GDPR (EU)** — Google UMP (Funding Choices) or AppLovin's built-in flow. Pass consent string before init.
- **CCPA** — `MaxSdk.SetDoNotSell(true)` (or LevelPlay/AdMob equivalent) on opt-out.
- **GDPR-without-consent** — `MaxSdk.SetHasUserConsent(false)`. Personalized ads blocked; non-personalized at lower eCPM.
- **COPPA / child-directed** — `MaxSdk.SetIsAgeRestrictedUser(...)` was deprecated and removed in MAX 12+ (mid-2024). No per-call age-restricted toggle. Configure via **AppLovin dashboard privacy settings** (app-wide) and the **tagged-for-children flag in each mediation network's dashboard** (Meta, Google, Mintegral). Audience targeting via dashboard's Audiences tool. Combine with `SetDoNotSell(true)` and `SetHasUserConsent(false)` for under-13 users.

## Test mode

Enable test ads in dev builds — never ship.

- **MAX** — `MaxSdk.SetTestDeviceAdvertisingIdentifiers(new[]{"YOUR_GAID_OR_IDFA"});` then `MaxSdk.ShowMediationDebugger()` from a debug menu. Shows per-network "Ready"/"Not Ready" and integration errors.
- **LevelPlay** — `IronSource.Agent.setMetaData("is_test_suite","enable");` then `IronSource.Agent.launchTestSuite();`.
- **AdMob** — hard-coded test ad unit IDs (`ca-app-pub-3940256099942544/...`) per format. Swap for real IDs only on release.

Gate the swap with `#if DEVELOPMENT_BUILD || UNITY_EDITOR`. Shipping test IDs = $0 revenue, hard to detect post-launch.

## Reward callbacks

```csharp
MaxSdkCallbacks.Rewarded.OnAdReceivedRewardEvent += (adUnitId, reward) => {
    GrantReward(reward.Amount, reward.Label);              // grant here, not OnHidden
};
MaxSdkCallbacks.Rewarded.OnAdHiddenEvent      += (id, info) => LoadRewarded();
MaxSdkCallbacks.Rewarded.OnAdDisplayFailedEvent += (id, err, info) => LoadRewarded();
```

- Grant in `OnAdReceivedRewardEvent` — fires only when user watched to threshold.
- Pre-load next ad in `OnAdHiddenEvent` and `OnAdDisplayFailedEvent`.
- High-value rewards (premium currency, big gem packs) → enable **server-side validation** in network dashboard. Network calls your backend with signed payload; backend grants the reward.

## Common patterns

- **Pre-load on init + on close** — never call Show without `IsReady`.
- **Interstitial on level complete, 60s cooldown** — A/B via remote config.
- **Rewarded for opt-in** — "double rewards", "extra life", "free chest", "skip timer". Show button only when ad loaded.
- **Banner in menu, hidden in gameplay** — `MaxSdk.HideBanner(adUnitId)` on level start.
- **App Open with init guard** — static `_skipNextAppOpen` for first-launch / IAP-deeplink-return.
- **One AdsService MonoBehaviour singleton** — see `unity-patterns`. No `MaxSdk.*` calls scattered across gameplay.

## Gotchas

- **Aggressive interstitials kill retention.** A/B cap windows; start at 60s.
- **Forgetting to pre-load.** "Show Failed" fires, button does nothing. Pre-load on init + every close/fail.
- **Test mode shipped to production.** $0 revenue. Verify in store builds, not just TestFlight.
- **GDPR/CCPA missing.** Fines, EU/CA traffic ban. Use UMP / IAB TCF v2.2.
- **iOS ATT after first ad request.** Falls back to fingerprint-only; eCPM craters. ATT must precede SDK init.
- **AdMob policy violations** — clicking own ads in dev, buying installs from cheap traffic = permanent per-payee ban.
- **SDK size bloat.** Each adapter adds 1-3 MB. Prune unused networks per release.
- **WebGL / standalone PC.** Mobile mediation doesn't work there. Gate behind `#if UNITY_ANDROID || UNITY_IOS`.
- **Non-MainThread init.** All MAX/LevelPlay/AdMob calls must be on Unity main thread. Marshal from background callbacks.

## Verification

- **Mediation Debugger** on real device — every configured network shows "Ready". "Not Ready" + error = adapter version mismatch or missing dashboard config.
- **Test placement on real device with test mode** — ad displays, reward fires, next ad pre-loads. Logcat / Console clean of `ad_request_failed`.
- **eCPM dashboard** — traffic distributed across networks. Bidding networks visible in auction log.
- **Production day 1** — fill > 95%, eCPM by region matches genre benchmark. Crash-free rate stable; bad adapter combos cause native crashes.

## Cross-links

- **unity-consent-att-gdpr** — REQUIRED prerequisite. ATT/UMP before SDK init.
- **unity-analytics-events** — fire `ad_impression` / `ad_clicked` / `ad_reward_granted`.
- **unity-remote-config-flags** — frequency caps, placement on/off, A/B ad cadence.
- **unity-best-practices** — main-thread, console hygiene, build-time platform gating.
- **unity-iap** — separate revenue stream; never gate IAP behind ad walls.

---
name: unity-ads-mediation
description: Use when integrating mobile ad mediation in a F2P Unity game — anything involving ads, mobile ads, ad mediation, AppLovin, MAX, AppLovin MAX, IronSource, LevelPlay, Unity LevelPlay, AdMob, Google AdMob, Unity Ads, rewarded ad, interstitial, banner ad, MREC, app open ad, ad placement, eCPM, waterfall, in-app bidding, Adjust attribution, AppsFlyer, ad SDK, ad consent, ATT prompt, IDFA, GAID, frequency cap, ad cooldown, fill rate, mediation network, test ad, test mode. Unity 6 / 2023.2 LTS, URP-only, new Input System only. NOT for IAP (use unity-iap), NOT for analytics events (use unity-analytics-events), NOT for ATT/GDPR consent dialogs (use unity-consent-att-gdpr).
---

F2P games live or die on ad revenue. Mediation routes each ad request through a waterfall (or in-app bidding auction) of demand sources — higher eCPM wins. This skill covers the integration plumbing; consent, analytics, and remote-config tuning live in their dedicated skills.

## When to use

- New F2P project that needs rewarded / interstitial / banner / MREC / app open ads.
- Migrating between mediation platforms (e.g. Unity Ads-only to MAX).
- Diagnosing low fill rate, low eCPM, or "ad not ready" bugs.
- Wiring rewarded callbacks for double-rewards / continue / free-chest features.

Do NOT use for IAP receipts, analytics event taxonomy, or the ATT/GDPR consent dialog itself — load the matching skills.

## Pick a mediation platform

Three mainstream choices in 2026. Pick one and stick with it — running two mediation SDKs in parallel makes them fight over the same auctions and tanks eCPM.

- **AppLovin MAX** — most-used mediation in mobile F2P. Broad waterfall + in-app bidding. Default pick if you have no other constraints.
- **Unity LevelPlay** (formerly IronSource) — Unity-owned now, deepest Unity Editor integration, package via Package Manager. Pick when the team is already deep in UGS.
- **Google AdMob** — Google-owned, weaker mediation ceiling but pairs natively with Firebase Analytics + UMP consent. Pick when Firebase is already the analytics backbone.

Unity Ads alone (without LevelPlay) is not real mediation — only use it as a network inside one of the above.

## Package install (the three options)

- **AppLovin MAX** — download the AppLovin Unity SDK Manager from the dashboard, drop the `.unitypackage` in the project, and use the in-Editor Manager window to install adapters per network (Meta, Google, Mintegral, etc.). MAX manages adapter versions for you; do not hand-install adapter `.aar`/`.framework` files.
- **Unity LevelPlay** — `com.unity.services.levelplay` via Package Manager. Configure mediation in the LevelPlay dashboard, then the package fetches the runtime adapters at build time.
- **AdMob** — `com.google.ads.mobile` (the Google Mobile Ads Unity plugin). Use the External Dependency Manager (EDM4U) to resolve adapter dependencies on Android (`Assets/Play Services Resolver/Android Resolver/Resolve`) and iOS (CocoaPods).

All three need an iOS `SKAdNetworkIdentifier` list in `Info.plist` — each platform ships an automated tool to inject it. Run that tool before every store build.

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

Init must run AFTER the ATT prompt on iOS (see unity-consent-att-gdpr). LevelPlay and AdMob have analogous init flows — `IronSource.Agent.init(appKey, IronSourceAdUnits.REWARDED_VIDEO, ...)` and `MobileAds.Initialize(initStatus => {...})` respectively.

## Placements and ad formats

Name placements in the network dashboard, not in code — different placements = different waterfalls + analytics segmentation. Conventions: `LevelComplete_Interstitial`, `Shop_Rewarded_Coins`, `Menu_Banner_Bottom`.

- **Rewarded** — full-screen video, skippable from ~5s. User opts in for a reward (gems, lives, double XP). Highest eCPM. Always pre-load.
- **Interstitial** — full-screen at level transitions. Cap to 1 per 60s minimum or you destroy retention.
- **Banner** — persistent 320x50 (or adaptive) at top/bottom. Lowest eCPM, lowest UX impact. Hide during gameplay, show in menus.
- **MREC** — 300x250 medium rectangle. Embed in shop / settings / pause menu naturally; reads as content, eCPM higher than banner.
- **App Open** — shows on app launch / foreground from background. Cap to 1 per 4 hours. Skip on first launch (annoys new users) and on return-from-IAP / return-from-store-deeplink.

## Frequency caps and pacing

Two layers — both required.

- **Client-side** — `if (Time.realtimeSinceStartup - _lastInterstitialTime > 60f) Show(...)`. Use `realtimeSinceStartup` so `Time.timeScale = 0` pause screens don't break it. Persist `_lastInterstitialTime` across sessions via PlayerPrefs if your cooldown is hours-long (app open).
- **Server-side via remote config** — pull `interstitial_cooldown_seconds`, `rewarded_daily_cap`, `app_open_cooldown_hours` from remote config so you can tune live without a build. Cross-link unity-remote-config-flags.

Hard cap rewarded? Generally no — rewarded is opt-in, the user clicked the button. Capping it costs money for no UX gain.

## Consent integration

Without proper consent, ads serve at low fill (no personalization) and low eCPM (50-80% drop in EU/CA).

- **iOS ATT** — must show BEFORE first ad request. Apple rejects apps without proper ATT flow now. See unity-consent-att-gdpr.
- **GDPR (EU)** — use Google UMP (Funding Choices) or AppLovin's built-in consent flow. Pass the consent string to the SDK before init.
- **CCPA (California)** — pass the "do not sell" flag: `MaxSdk.SetDoNotSell(true)` (or LevelPlay/AdMob equivalents) when the user opts out.
- **GDPR-without-consent** — when an EU user declines consent, signal it: `MaxSdk.SetHasUserConsent(false)`. Personalized ads are blocked; ads still serve in non-personalized mode at lower eCPM.
- **COPPA / child-directed** — `MaxSdk.SetIsAgeRestrictedUser(...)` was deprecated and removed in AppLovin MAX 12+ (mid-2024). There is no per-call age-restricted toggle anymore. Configure child-directed status via the **AppLovin dashboard's privacy settings** (disables user-signal collection app-wide), and via the **tagged-for-children flag in each mediation network's dashboard config** (Meta, Google, Mintegral, etc.). Audience targeting is done via the dashboard's Audiences tool. Combine with `SetDoNotSell(true)` and `SetHasUserConsent(false)` for under-13 users where applicable.

## Test mode

Enable test ads in dev builds — never ship with them.

- **MAX** — `MaxSdk.SetTestDeviceAdvertisingIdentifiers(new[]{"YOUR_GAID_OR_IDFA"});` then call `MaxSdk.ShowMediationDebugger()` from a debug menu. Debugger shows per-network "Ready" / "Not Ready" status and any integration errors.
- **LevelPlay** — `IronSource.Agent.setMetaData("is_test_suite","enable");` then `IronSource.Agent.launchTestSuite();`.
- **AdMob** — hard-coded test ad unit IDs (`ca-app-pub-3940256099942544/...`) for each format. Swap for real IDs only on release builds.

Gate the swap with `#if DEVELOPMENT_BUILD || UNITY_EDITOR`. NEVER ship with test IDs — $0 revenue, hard to detect post-launch.

## Reward callbacks

```csharp
MaxSdkCallbacks.Rewarded.OnAdReceivedRewardEvent += (adUnitId, reward) => {
    GrantReward(reward.Amount, reward.Label);              // grant here, not OnHidden
};
MaxSdkCallbacks.Rewarded.OnAdHiddenEvent      += (id, info) => LoadRewarded();
MaxSdkCallbacks.Rewarded.OnAdDisplayFailedEvent += (id, err, info) => LoadRewarded();
```

- Grant in `OnAdReceivedRewardEvent` — fires only when the user actually watched to the reward threshold.
- Pre-load the next ad in `OnAdHiddenEvent` and `OnAdDisplayFailedEvent` so the next show is instant.
- For high-value rewards (premium currency, big gem packs), turn on **server-side validation** in the network dashboard. Network calls your backend with a signed payload, your backend grants the reward — protects against client-side fraud.

## Common patterns

- **Pre-load on init + on close** — ad ready when player needs it. Never call Show without checking `IsReady`.
- **Interstitial on level complete, 60s cooldown** — typical hyper-casual cadence; A/B test the window via remote config.
- **Rewarded for opt-in flows** — "double rewards", "extra life", "free chest", "skip timer". Only show the button when the ad is loaded.
- **Banner in menu, hidden in gameplay** — `MaxSdk.HideBanner(adUnitId)` on level start, `ShowBanner` on return to menu.
- **App Open with init guard** — a static `_skipNextAppOpen` flag set on first-launch / IAP-deeplink-return so the ad doesn't fire at the wrong moment.
- **One AdsService MonoBehaviour singleton** — cross-link unity-patterns. All ad-related code goes through it; no MaxSdk.* calls scattered across gameplay scripts.

## Gotchas

- **Aggressive interstitials kill retention.** A/B test cap windows; start at 60s and only shorten with data.
- **Forgetting to pre-load.** "Show Failed" callback fires, user clicks reward button, nothing happens. Always pre-load on init and on every close/fail.
- **Test mode shipped to production.** $0 revenue, sometimes invisible until first invoice. Verify in store builds, not just TestFlight.
- **GDPR/CCPA missing.** Fines, ban from EU/CA traffic. Use UMP / IAB TCF v2.2.
- **iOS ATT shown after first ad request.** Falls back to fingerprint-only attribution — eCPM craters. ATT must precede SDK init.
- **AdMob policy violations** — clicking your own ads in dev, buying installs from cheap traffic networks = account ban. The ban is permanent and per-payee.
- **SDK size bloat.** Each adapter adds 1-3 MB. Prune unused networks in the MAX/LevelPlay dashboard before each release.
- **WebGL / standalone PC.** No mobile ad mediation works there. Don't try; gate ad code behind `#if UNITY_ANDROID || UNITY_IOS`.
- **Initializing on a non-MainThread.** All MAX/LevelPlay/AdMob calls must be on the Unity main thread. Marshal from background callbacks.

## Verification

- **Mediation Debugger** — open it on a real device. Every configured network shows "Ready". Any "Not Ready" with an error message = adapter version mismatch or missing dashboard config.
- **Test placement on real device with test mode on** — ad displays, reward callback fires, next ad pre-loads. Check Logcat / Console for `ad_request_failed` errors; the log should be clean.
- **eCPM dashboard** — traffic distributed across networks, no single network at 100% (means others aren't bidding). Bidding networks should show in the auction log.
- **Production day 1** — fill rate >95%, eCPM by region matches benchmark for genre. Watch crash-free rate; bad adapter combos cause native crashes.

## Cross-links

- **unity-consent-att-gdpr** — REQUIRED prerequisite. ATT/UMP flow must complete before SDK init or eCPM craters.
- **unity-analytics-events** — fire `ad_impression` / `ad_clicked` / `ad_reward_granted` events for funnel analysis.
- **unity-remote-config-flags** — frequency caps, placement on/off, A/B test ad cadence without a build.
- **unity-best-practices** — main-thread rules, Editor console hygiene, build-time platform gating.
- **unity-iap** — separate revenue stream; never gate IAP behind ad walls.

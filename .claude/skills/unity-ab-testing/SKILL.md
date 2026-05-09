---
name: unity-ab-testing
description: 'Use for Unity 6+ F2P experiments: A/B or multivariate tests, sticky bucketing, holdouts, variant exposure, feature/monetization/balance treatments, Firebase/GameAnalytics/Optimizely/Statsig, metrics, sample size, significance. Not plain remote config or dashboards. URP-only, new Input System only.'
---

# Unity A/B Testing & Experiments

## When to use
Tune monetization (price, ad cap, IAP offers, energy refill), gameplay difficulty, onboarding, UI changes — and measure impact on retention, ARPDAU, conversion with statistical confidence. Wire once on top of remote config; every future balance change becomes data-driven.

## How A/B works
Split users into Control (existing) and one or more Treatment groups. Sticky-bucket each user (same variant across sessions). When the treatment affects what they saw or did, log an exposure event. Compare goal metrics (D7 retention, ARPDAU, conversion) — significant difference is your winner.

## Pick a service
- **Firebase A/B Testing** — built on Firebase Remote Config + Analytics. Free. Most common F2P. Define in Firebase Console → A/B Testing.
- **Statsig** — paid, more powerful stats engine, faster significance, feature gates + experiments + holdouts in one product.
- **Optimizely** — enterprise, expensive, overkill for indie / small studio.
- **GameAnalytics A/B** — basic, free if already on GameAnalytics. OK for early titles; weaker stats reporting.

Default: Firebase A/B Testing if already on Firebase Remote Config + Analytics (`unity-remote-config-flags`, `unity-analytics-events`). Move to Statsig once experiment volume justifies cost.

## Firebase A/B Testing setup
Firebase → A/B Testing → Create Experiment → Remote Config experiment.
- **Parameter** — one Remote Config key (e.g. `energy_max`).
- **Variants** — Control (current value), Variant A, Variant B (e.g. 5 / 7 / 10).
- **Audience** — subset (country, app version, custom audience) or 100% of users.
- **Activation event** — analytics event marking user "active in experiment" (`level_complete`, `iap_completed`, `tutorial_complete`).
- **Goal metrics** — pick from existing Analytics events. Firebase computes uplift + 95% CI.

SDK side identical to Remote Config — no separate "experiment SDK". Experiment routes the right variant value through `GetValue`:
```csharp
long energyMax = FirebaseRemoteConfig.DefaultInstance
    .GetValue("energy_max").LongValue;
```

## Sticky bucketing
Same user → same variant across every session for the experiment's lifetime. Firebase: deterministic hash of `(installation_id, experiment_id)`. Statsig: hashes `(stable_id, experiment_name)`.

Do NOT use `string.GetHashCode()`. Since .NET Core 2.1 / modern Mono, `string.GetHashCode()` is randomized per process under IL2CPP/Mono — different launches of the same build produce different values for the same input. `Mathf.Abs(userId.GetHashCode()) % 100` silently re-buckets users on every cold start and destroys your experiment.

Use deterministic crypto or non-crypto stable hash. SHA-256 is the standard; Unity 6 also ships `System.IO.Hashing` (xxHash) for faster non-crypto hashing.
```csharp
using System.Security.Cryptography;
using System.Text;
public static int Bucket(string userId, string experimentId, int buckets = 100) {
    using var sha = SHA256.Create();
    var bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(userId + ":" + experimentId));
    // Use first 4 bytes as a uint to avoid signed-mod issues
    uint v = (uint)(bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24);
    return (int)(v % (uint)buckets);
}
```

## Variant assignment
Read variant once at session start (or at the safe boundary the variant takes effect) and cache. Don't call `GetValue` every frame.
```csharp
string variant; // "control" | "treatment_a" | "treatment_b"

void OnSessionStart() {
    variant = FirebaseRemoteConfig.DefaultInstance
        .GetValue("checkout_variant").StringValue;
    if (string.IsNullOrEmpty(variant)) variant = "control";
}
```
Branch on cached string. Variant strings must match exactly between SDK code and console — typos silently route to default.

## Exposure events
Log `experiment_exposure` (or SDK-provided equivalent) the moment user actually encounters the treatment — saw new UI, was offered new price, faced new boss. Without exposure events you measure assignment, not impact.
```csharp
FirebaseAnalytics.LogEvent("experiment_exposure", new Parameter[] {
    new Parameter("experiment_id", "checkout_v2"),
    new Parameter("variant", variant)
});
```
Firebase A/B uses your activation event as implicit exposure gate; granular custom exposure event still useful for deeper funnel analysis.

## Holdouts
Global holdout group never sees ANY experiment changes — control across all experiments. Lets you measure cumulative experiment impact and detect "experiment overload" where many small wins net to a loss because users got confused. Reserve 5-10% as permanent holdout.

## Common experiment patterns
- **Onboarding tutorial step** — variant skips step 3; measure D1 retention + tutorial completion. Quick wins.
- **Pricing** — variant raises starter pack from $0.99 to $1.99; measure ARPDAU + IAP conversion. Local-currency price matters; verify per region.
- **Difficulty curve** — variant lowers boss HP 20%; measure D7 retention + completion + churn at boss.
- **Ad cap** — variant tightens interstitial cap from 60s to 90s; measure session length + ad revenue + D7. Cap is non-monotonic — too few = lost impressions, too many = churn.
- **UI** — variant moves shop button top-right; measure shop-open + IAP conversion. Tiny changes can move 5-10%.
- **Reward tuning** — variant doubles daily quest gold; measure session count + D7. Track economy events for inflation.

## Statistical pitfalls
- **Sample size** — F2P needs ~10k DAU per variant per metric for reliable D7 detection. Below that, run longer or accept wider CIs.
- **Multiple comparisons** — 5 metrics each at p<0.05 → 25% chance of false positive. Use Bonferroni (divide alpha by metric count) or pre-register a single primary metric.
- **Novelty effect** — UI/feature changes show short-term lift that fades. Run 7+ days minimum; ignore first 1-2 days of post-launch noise.
- **Survivorship bias** — measuring "users who got to checkout" self-selects. Measure all assigned users, not just treated subset.
- **Stopping early** — peeking and stopping when significant inflates false-positive rate. Predefine sample size or use sequential-test-aware tooling (Statsig, mSPRT).
- **Network effects** — multiplayer / leaderboard experiments leak between groups. A/B assumes independence.

## Gotchas
- **Mid-experiment changes** — editing audience, variant values, or activation event resets bucketing and invalidates results. Lock before launch; if must change, end and start fresh.
- **Overlapping experiments on same parameter** — Firebase prevents two A/B tests on same parameter; manual remote-config edits to a parameter under a live experiment are ignored for enrolled users.
- **Editor / dev builds** default to control. For QA, expose a debug menu that force-pins a variant.
- **Variant string mismatch** — SDK reads `treatment_a` but console publishes `Treatment A`; silent control fallback. Treat variant keys as enums; share via constants.
- **Stopping an experiment** doesn't immediately reset users; assigned values persist until next remote-config fetch + activate. Plan rollback.
- **GDPR / ATT denied users** — some attribution/analytics SDKs exclude these depending on consent. Firebase still buckets (uses installation_id, not IDFA) but goal metrics from analytics may exclude them.
- **Holdout drift** — long-running holdouts diverge from active population because they never see improvements. Refresh quarterly.
- **Defaults shipped in-app** — if shipped client default differs from experiment's "control" value, offline / first-fetch users see neither variant. Keep client defaults aligned with control.
- **Soft-launch markets** — Firebase A/B can target single country (e.g. Philippines, Canada). Validate before global; watch for market-specific behavior.

## Verification
- Firebase Console → A/B Testing → dashboard shows variant counts (balanced for 50/50), exposure %, primary-metric uplift, CI.
- In-app debug menu: force a variant for QA; confirm variant code path runs and visual / behavioral change appears.
- Exposure event arrives in Firebase Analytics within seconds (DebugView). Variant parameter matches SDK.
- Sample-size graph trends up; significance reaches 95% before calling a winner.
- Sticky bucketing: same device across reinstalls (same Firebase installation ID) returns same variant. Different test devices spread across variants per configured weights.
- Goal metrics: confirm Firebase wires the right Analytics events into experiment goals.

Cross-link: unity-remote-config-flags (foundation), unity-analytics-events (exposure + goal metrics), unity-iap (price experiments — local-currency, store catalog), unity-ads-mediation (ad cap / placement experiments), unity-best-practices.

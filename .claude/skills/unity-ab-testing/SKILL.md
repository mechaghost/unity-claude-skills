---
name: unity-ab-testing
description: 'Use when running A/B and multivariate experiments in a Unity F2P game through Unity MCP — anything involving A/B test, A/B testing, multivariate test, variant, variant assignment, holdout, control group, experiment, sticky bucketing, experiment exposure, variant key, treatment, control, randomization, hashing, deterministic bucketing, feature variant, monetization variant, balance test, Firebase A/B Testing, GameAnalytics experiments, Optimizely, Statsig, holdout group, exposure event, primary metric, goal metric, statistical significance, confidence interval, novelty effect, Bonferroni, sample size, experiment audience, experiment targeting. Unity 6+ / 6000.x, URP-only, new Input System only. NOT for plain remote config flags without metrics (use unity-remote-config-flags), NOT for analytics dashboards (use unity-analytics-events). They pair together.'
---

# Unity A/B Testing & Experiments

## When to use
Tune monetization (price, ad cap, IAP offers, energy refill rate), gameplay difficulty, onboarding, or UI changes — and measure the impact on retention, ARPDAU, and conversion with statistical confidence instead of guessing. Wire it once on top of remote config; every future balance change becomes data-driven.

## How A/B testing works
Split users into a Control group (existing behavior) and one or more Treatment groups (new behavior). Each user gets sticky-bucketed (same variant across sessions). When the treatment affects what the user actually saw or did, log an exposure event. Compare goal metrics (D7 retention, ARPDAU, conversion rate) between groups; a statistically significant difference is your winner.

## Pick a service
- **Firebase A/B Testing** — built on Firebase Remote Config + Firebase Analytics. Free. Most common F2P choice. Define experiments in Firebase Console → A/B Testing.
- **Statsig** — paid, more powerful stats engine, faster significance detection, supports feature gates + experiments + holdouts in one product.
- **Optimizely** — enterprise, expensive, overkill for indie / small studio.
- **GameAnalytics A/B** — basic, free if you are already using GameAnalytics. OK for early titles; weaker stats reporting than Firebase.

Default recommendation: Firebase A/B Testing if you already use Firebase Remote Config + Analytics (see unity-remote-config-flags, unity-analytics-events). Move to Statsig once experiment volume justifies cost.

## Firebase A/B Testing setup
Console flow: Firebase → A/B Testing → Create Experiment → Remote Config experiment.
- **Parameter** — pick one Remote Config key (e.g. `energy_max`).
- **Variants** — Control (current value), Variant A, Variant B (e.g. 5 / 7 / 10).
- **Audience** — target subset (country, app version, custom audience) or 100% of users.
- **Activation event** — analytics event that marks a user as "active in the experiment" (`level_complete`, `iap_completed`, `tutorial_complete`).
- **Goal metrics** — pick from existing Analytics events. Firebase computes uplift + 95% confidence interval.

SDK side is identical to Remote Config — there is no separate "experiment SDK". The experiment routes the right variant value through `GetValue`:
```csharp
long energyMax = FirebaseRemoteConfig.DefaultInstance
    .GetValue("energy_max").LongValue;
```

## Sticky bucketing
Same user → same variant across every session for the experiment's lifetime. Firebase handles this via deterministic hashing of `(installation_id, experiment_id)`; Statsig hashes `(stable_id, experiment_name)`.

Do NOT use `string.GetHashCode()` for sticky bucketing. Since .NET Core 2.1 and modern Mono, `string.GetHashCode()` is randomized per process under IL2CPP/Mono — different launches of the same build produce different hash values for the same input. A `Mathf.Abs(userId.GetHashCode()) % 100` shortcut will silently re-bucket users on every cold start and destroy your experiment.

Use a deterministic cryptographic or non-crypto stable hash. SHA-256 is the standard, ubiquitous choice; Unity 6 also ships `System.IO.Hashing` (xxHash) for faster non-crypto hashing. Roll-your-own:
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
Read the variant once at session start (or at the safe boundary the variant takes effect) and cache. Do not call `GetValue` every frame.
```csharp
string variant; // "control" | "treatment_a" | "treatment_b"

void OnSessionStart() {
    variant = FirebaseRemoteConfig.DefaultInstance
        .GetValue("checkout_variant").StringValue;
    if (string.IsNullOrEmpty(variant)) variant = "control";
}
```
Branch behavior on the cached string. Variant strings must match exactly between SDK code and the console — typos silently route to default.

## Exposure events
Log `experiment_exposure` (or the SDK-provided equivalent) the moment the user actually encounters the treatment — saw the new UI, was offered the new price, was matched against the new boss. Without exposure events you measure assignment, not impact: half the assigned users may never have hit the treated code path.
```csharp
FirebaseAnalytics.LogEvent("experiment_exposure", new Parameter[] {
    new Parameter("experiment_id", "checkout_v2"),
    new Parameter("variant", variant)
});
```
Firebase A/B uses your activation event as the implicit exposure gate; you still want a granular custom exposure event for any deeper funnel analysis.

## Holdouts
A global holdout group never sees ANY experiment changes — control across all experiments. Lets you measure cumulative experiment impact (positive or negative) and detect "experiment overload" where many small wins net to a loss because users got confused. Reserve 5–10% of users as a permanent holdout.

## Common experiment patterns
- **Onboarding tutorial step** — variant skips step 3 of the tutorial; measure D1 retention + tutorial completion rate. Quick wins live here.
- **Pricing** — variant raises starter pack from $0.99 to $1.99; measure ARPDAU + IAP conversion rate. Local-currency price matters; verify per region.
- **Difficulty curve** — variant lowers boss HP 20%; measure D7 retention + level completion rate + churn at that boss.
- **Ad cap** — variant tightens interstitial cap from 60s to 90s; measure session length + ad revenue + D7 retention. Cap is non-monotonic in revenue — too few = lost impressions, too many = churn.
- **UI** — variant moves the shop button to top-right; measure shop-open rate + IAP conversion. Tiny changes can move 5–10%.
- **Reward tuning** — variant doubles daily quest gold; measure session count + D7. Guard against inflation by also tracking economy events.

## Statistical pitfalls
- **Sample size** — low traffic = noisy. F2P needs roughly 10k DAU per variant per metric for reliable D7 detection. Below that, run longer (multiple weeks) or accept wider confidence intervals.
- **Multiple comparisons** — running 5 metrics each at p<0.05 → 25% chance of a false positive somewhere. Use Bonferroni correction (divide alpha by metric count) or pre-register a single primary metric.
- **Novelty effect** — UI/feature changes show short-term lift that fades as users habituate. Run experiments 7+ days minimum; ignore the first 1–2 days of post-launch noise.
- **Survivorship bias** — only measuring "users who got to checkout" self-selects. Always measure all assigned users for the goal metric, not just the treated subset.
- **Stopping early** — peeking at the dashboard and stopping when significant produces inflated false-positive rates. Predefine sample size or use sequential-test-aware tooling (Statsig, mSPRT) instead.
- **Network effects** — multiplayer / leaderboard experiments leak between groups. Pure A/B assumes independence; if Variant A players matchmake with Control players, results are biased.

## Gotchas
- **Mid-experiment changes** — editing the audience, variant values, or activation event resets bucketing and invalidates results. Lock the experiment definition before launch; if you must change something, end the experiment and start a fresh one.
- **Overlapping experiments on the same parameter** — Firebase prevents two A/B tests from owning the same parameter; manual remote-config edits to a parameter under a live experiment are ignored for enrolled users.
- **Editor / dev builds** — usually default to control. For QA, expose a debug menu that force-pins a variant via the SDK's `setForcedVariant`-equivalent or via `RemoteConfig.SetDefaultsAsync` overrides.
- **Variant string mismatch** — SDK reads `treatment_a` but console publishes `Treatment A`; silent control fallback. Treat variant keys as enums; share them via a constants file.
- **Stopping an experiment** does not immediately reset users; their assigned values persist until the next remote-config fetch + activate. Plan a rollback path.
- **GDPR / ATT denied users** — some attribution / analytics SDKs exclude these users from experiments depending on consent state. Verify Firebase still buckets them (it does; Firebase uses installation_id, not IDFA) but goal metrics derived from analytics may exclude them.
- **Holdout drift** — long-running holdouts diverge from the active population because holdouts never see any improvements. Refresh holdout cohorts every quarter.
- **Defaults shipped in-app** — if your shipped client default differs from the experiment's "control" value, offline / first-fetch users see neither variant. Keep client defaults aligned with control.
- **Soft-launch markets** — Firebase A/B can target a single country (e.g. Philippines, Canada). Use this to validate before global rollout, but watch for market-specific behavior that does not generalize.

## Verification
- Firebase Console → A/B Testing → experiment dashboard shows variant counts (should be balanced for a 50/50 split), exposure %, primary-metric uplift, and confidence interval.
- In-app debug menu: force a variant for QA; confirm the variant code path actually runs and the visual / behavioral change appears.
- Exposure event arrives in Firebase Analytics within seconds (DebugView). Variant parameter on the event matches what the SDK reports.
- Sample-size graph trends up over the experiment window; significance reaches 95% before you call a winner.
- Sticky bucketing check: same device across reinstalls (with same Firebase installation ID retained) returns the same variant. Different test devices spread across variants per the configured weights.
- Goal metrics: confirm Firebase wires the right Analytics events (level_complete, purchase, etc.) into the experiment goals; missing events = blank dashboard.

Cross-link: unity-remote-config-flags (foundation; experiments ride on top of remote config), unity-analytics-events (exposure events + goal metrics flow through analytics), unity-iap (price experiments — local-currency, store catalog), unity-ads-mediation (ad cap / placement experiments), unity-best-practices.

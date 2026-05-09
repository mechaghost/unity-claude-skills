---
name: unity-consent-att-gdpr
description: 'Use for Unity 6+ runtime privacy consent: iOS ATT/IDFA prompts, GDPR/CCPA UMP/CMP flows, COPPA age gates, TCF strings, consent SDK wiring, opt-out/data-deletion UX. Not PrivacyInfo.xcprivacy or Play Data Safety forms.'
---

# unity-consent-att-gdpr

ATT, GDPR/CCPA, COPPA. Missing or broken = no review pass.

## When to use

- Adding ATT prompt for iOS 14+ before any ad SDK or fingerprinting analytics.
- Wiring a CMP (UMP, AppLovin, IronSource, OneTrust, Sourcepoint) for EU/EEA/UK GDPR + California CCPA.
- COPPA age-gating for Family-category or under-13 audiences.
- In-app data deletion UI (Google Play 2024 + GDPR Article 17).
- Pre-submission audit of consent flow.

## Store-review blockers

- **Apple App Store Guideline 5.1.2**: tracking without ATT = rejection. `NSUserTrackingUsageDescription` Info.plist string mandatory if any SDK accesses IDFA.
- **Google Play Data Safety + EEA consent**: declared collection must match runtime; missing CMP in EEA can trigger policy strike.
- **GDPR (EU/EEA/UK)**: tracking EU users without consent = up to EUR 20M ceiling. Realistic indie risk: ad revenue clawback + store removal.
- **Dead Privacy Policy URL**: both stores reject. Reviewers click it.

## ATT (iOS 14+)

Required Info.plist key: `NSUserTrackingUsageDescription` — short string explaining purpose ("We use tracking to deliver more relevant ads"). Without it the ATT prompt never shows; Apple rejects.

Unity package: `com.unity.ads.ios-support` provides `Unity.Advertisement.IosSupport.ATTrackingStatusBinding` with async `RequestAuthorizationTracking()`.

Status enum:
- `NOT_DETERMINED` (0) — never asked.
- `RESTRICTED` (1) — parental controls / MDM.
- `DENIED` (2) — user said no.
- `AUTHORIZED` (3) — IDFA available.

```csharp
using Unity.Advertisement.IosSupport;

var status = ATTrackingStatusBinding.GetAuthorizationTrackingStatus();
if (status == ATTrackingStatusBinding.AuthorizationTrackingStatus.NOT_DETERMINED)
{
    ATTrackingStatusBinding.RequestAuthorizationTracking();
    // status updates after dialog dismiss; poll next frame or via coroutine.
}
```

**Timing**: BEFORE first ad SDK init and before fingerprinting analytics. Soft-prompt tutorial frame first ("we use tracking to keep ads relevant; tap Allow") is permitted if it doesn't pre-bias with reward language.

**Denied/Restricted**: ad SDKs fall back to SKAdNetwork (SKAN) for attribution. Verify SKAN config is live in network dashboards.

## GDPR/CCPA via UMP

Most ad networks bundle a UMP-compliant CMP. AppLovin MAX has built-in CMP, LevelPlay uses IronSource Consent Solution, AdMob ships Google UMP. See `unity-ads-mediation`.

**EU / EEA / UK**: must show consent form (Accept All / Reject All / Configure). Consent string (TCF v2.2) passed to ad networks. Rejected = limited / contextual ads only — eCPM drops 50-70% but ads still serve.

**CCPA (California)**: "Do Not Sell My Personal Information" toggle in settings. Opt-out signal sent via SDK API.

Show on first launch in EU. Geo-detect via ad SDK helper or device locale. Outside EU/CA, no dialog.

```csharp
using GoogleMobileAds.Ump.Api;

var parameters = new ConsentRequestParameters();
ConsentInformation.Update(parameters, error => {
    if (ConsentInformation.IsConsentFormAvailable())
        ConsentForm.Load((form, loadError) => form.Show(dismissError => { /* init ads */ }));
});
```

## IAB TCF v2.2 CMPs

Required since Sept 2023 for Google ads in EEA. CMP SDKs (OneTrust, Sourcepoint, Quantcast Choice) handle the v2.1 → v2.2 upgrade. Don't roll your own — use a vendor CMP.

## COPPA age-gating

Required for Family-category / US under-13 apps. First launch: age dialog ("Enter year of birth"). If under threshold (<13 US, varies by region):
- Disable behavioral ads (Tag For Child Directed Treatment = true).
- Disable analytics PII (no user ID, no email).
- Disable social features (chat, leaderboards with names).

Google Play Families is stricter — every third-party SDK must be COPPA-certified. Many ad networks won't serve traffic in this mode.

## Order of operations on first launch

1. Splash + boot scene (`unity-scenes`).
2. Region detect (ad SDK helper or device locale).
3. EU/EEA/UK: CMP consent form. Block boot until dismissed.
4. US (and family-eligible): COPPA age gate.
5. iOS only: ATT prompt. Apple recommends on first launch where ad value is established, NOT before user understands the app.
6. Initialize analytics + ad SDKs with consent string + ATT status.
7. Continue to main menu.

## Data deletion requests

GDPR Article 17 + CCPA + Google Play Data Deletion Policy 2024.

- **In-app**: Settings > "Delete my data" + email or web URL fallback.
- **Backend**: receive request, anonymize/delete user record, IAP receipts (legal retention varies — consult counsel; typically retain receipts for tax period), analytics events. Must process within 30 days.
- **Apple**: Privacy Policy URL must include data deletion contact.
- **Google Play (since 2024)**: in-app deletion OR a public web URL referenced in Play Console listing. Either is fine.

**No-backend fallback**: a public web form (Google Form, Tally, Typeform) emailing the team satisfies the Play listing requirement and Apple Privacy Policy reference. In-app deletion remains best practice.

## Common patterns

- **`ConsentManager` singleton**: tracks state, persists last-seen consent string in PlayerPrefs (`unity-persistence`), passes consent to ad SDKs on init.
- **Settings "Privacy" section**: re-show CMP, "Delete my data", Privacy Policy URL link, "Do Not Sell" toggle.
- **Region detection via ad SDK**: `MaxSdkUtils.GetSdkConfiguration().ConsentDialogState` or AdMob equivalent — simpler than rolling your own geo-IP.
- **Analytics gating**: every analytics call routes through `ConsentManager.IsAnalyticsAllowed()` (`unity-analytics-events`).

## Gotchas

- Forgetting `NSUserTrackingUsageDescription` = ATT never shows + Apple rejection. Add a post-build hook to assert it (`unity-build`, `OnPostprocessBuild`).
- ATT before user understands the app = 80%+ deny rate. Soft-prompt first.
- GDPR consent must be granular: Accept All and Reject All EQUALLY prominent. "Reject" cannot hide behind "Manage Settings".
- CCPA isn't optional even outside California in 2026 — most studios make "Do Not Sell" globally available (covers Colorado CPA, Virginia VCDPA, etc.).
- COPPA + Family: SDKs must be COPPA-certified; many ad networks won't serve in this mode. Plan revenue accordingly.
- Privacy Policy URL must be live and accurate. App Store reviewers click it. 404 = rejection. 200 with stale content = rejection.
- Storing consent in PlayerPrefs is fine; clearing PlayerPrefs / app uninstall resets consent — must re-prompt. Document for support.
- SKAN 4 is current spec. Networks need SKAN 4 conversion value mapping in their dashboard or attribution breaks silently.
- ATT can only be re-prompted via iOS Settings — once denied in-app, no programmatic re-prompt. Add "How to enable tracking" deep link to Settings.
- Editor returns mock ATT values — cannot validate timing in Editor. Test on fresh install on device.

## Verification

- **Editor**: ATT API returns mock; logic paths run but don't exercise iOS prompt.
- **iOS device, fresh install**: ATT prompt at right time → status changes from `NOT_DETERMINED` to `AUTHORIZED`/`DENIED`. Verify ad SDK logs new state.
- **EU device or VPN**: CMP form on first launch. Verify TCF string set in ad SDK.
- **LogAssert**: ad SDK logs consent state ("TCF string set", "ATT denied — using SKAN").
- **Post-build hook**: `OnPostprocessBuild` confirms `NSUserTrackingUsageDescription` in Info.plist before archive.
- **Privacy Policy URL**: HEAD returns 200, body mentions current app name + data deletion contact.
- **Settings flow**: re-open CMP, toggle "Do Not Sell", trigger "Delete my data" → end-to-end through backend.

## Cross-links

- **unity-privacy-manifests** — paired ASC requirement; PrivacyInfo.xcprivacy is a separate artifact.
- **unity-ads-mediation** — consent string + ATT status feed into ad SDKs.
- **unity-analytics-events** — consent gates every analytics call.
- **unity-build** — `OnPostprocessBuild` hook verifies Info.plist keys.
- **unity-persistence** — consent string + CCPA opt-out in PlayerPrefs.
- **unity-scenes** — boot scene blocks until consent flow completes.
- **unity-best-practices** — paradigm rules apply.

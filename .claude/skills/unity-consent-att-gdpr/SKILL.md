---
name: unity-consent-att-gdpr
description: Use when implementing privacy/consent compliance for store launch in Unity through Unity MCP — iOS ATT (App Tracking Transparency), GDPR/CCPA via UMP/CMP, COPPA age-gating, or any store-review blocker around tracking permissions and consent dialogs. Triggers — ATT, App Tracking Transparency, AppTrackingTransparency, IDFA, NSUserTrackingUsageDescription, IDFV, GDPR, CCPA, COPPA, age gate, age gating, consent, consent dialog, consent management platform, CMP, IAB TCF, TCF v2.2, UMP, User Messaging Platform, Google Funding Choices, AppLovin Consent, IronSource ATT, AdMob UMP, Apple ATT prompt, ATT request, request authorization, tracking authorization status, Authorized, Denied, NotDetermined, Restricted, privacy policy URL, data deletion request, opt out, Do Not Sell, Limit Ad Tracking, IDFA fingerprinting, SKAdNetwork, SKAN. Unity 6 / 2023.2 LTS, URP-only, new Input System only. NOT the same as Apple PrivacyInfo.xcprivacy manifest — use unity-privacy-manifests for that. They pair together but are different artifacts.
---

# unity-consent-att-gdpr

Privacy and consent compliance for store launch. ATT, GDPR/CCPA, COPPA. If any of these are missing or broken, the app will not pass review.

## When to use

- Adding ATT prompt for iOS 14+ before any ad SDK or fingerprinting analytics call.
- Wiring a Consent Management Platform (UMP, AppLovin, IronSource, OneTrust, Sourcepoint) for EU/EEA/UK GDPR + California CCPA.
- Adding COPPA age-gating for Family-category apps or apps with under-13 audience.
- Implementing in-app data deletion request UI (Google Play 2024 policy + GDPR Article 17).
- Pre-submission audit of consent flow before App Store / Play Console upload.

## Why this is a store-review blocker

- **Apple App Store Guideline 5.1.2**: tracking without ATT flow = rejection. `NSUserTrackingUsageDescription` Info.plist string is mandatory if any SDK in your build accesses IDFA.
- **Google Play Data Safety + EEA consent**: requires declared data collection matching runtime behavior; missing CMP in EEA can trigger policy strike.
- **GDPR (EU/EEA/UK)**: tracking EU users without consent = up to EUR 20M fine ceiling per violation (theoretical; realistic indie risk is ad revenue clawback + store removal).
- **Dead Privacy Policy URL**: both stores reject. Reviewers actually click it.

## ATT (iOS 14+)

Required Info.plist key: `NSUserTrackingUsageDescription` — short string explaining the tracking purpose ("We use tracking to deliver more relevant ads"). Without it the ATT prompt never shows and Apple rejects.

Unity package: `com.unity.ads.ios-support` provides `Unity.Advertisement.IosSupport.ATTrackingStatusBinding` with async `RequestAuthorizationTracking()`.

Status enum values:
- `NOT_DETERMINED` (0) — never asked.
- `RESTRICTED` (1) — parental controls / MDM blocks tracking.
- `DENIED` (2) — user said no.
- `AUTHORIZED` (3) — user said yes; IDFA available.

```csharp
using Unity.Advertisement.IosSupport;

var status = ATTrackingStatusBinding.GetAuthorizationTrackingStatus();
if (status == ATTrackingStatusBinding.AuthorizationTrackingStatus.NOT_DETERMINED)
{
    ATTrackingStatusBinding.RequestAuthorizationTracking();
    // status updates after dialog dismiss; poll next frame or via coroutine.
}
```

**Timing**: show ATT prompt BEFORE the first ad SDK init and before any analytics that fingerprints. Many studios run a "soft prompt" tutorial frame first ("we use tracking to keep ads relevant; tap Allow on the next dialog") — Apple permits this if it does not pre-bias the user with reward language.

**Denied / Restricted path**: ad SDKs fall back to SKAdNetwork (SKAN) for attribution — no IDFA. Most networks handle this automatically when they detect Denied; verify in their dashboard the SKAN config is live.

## GDPR/CCPA via UMP (Google User Messaging Platform / Funding Choices)

Most ad networks bundle a UMP-compliant CMP. AppLovin MAX has built-in CMP, LevelPlay uses IronSource Consent Solution, AdMob ships Google UMP. Cross-link unity-ads-mediation.

**EU / EEA / UK**: must show consent form (Accept All / Reject All / Configure). Consent string (TCF v2.2) is passed to ad networks. Rejected = limited / contextual ads only — eCPM drops 50-70% but ads still serve.

**CCPA (California)**: "Do Not Sell My Personal Information" toggle in settings. Opt-out signal sent to ad networks via SDK API.

Show on first launch in EU. Geo-detect via ad SDK helper or device locale (cheap fallback). Outside EU/CA, no dialog needed.

```csharp
using GoogleMobileAds.Ump.Api;

var parameters = new ConsentRequestParameters();
ConsentInformation.Update(parameters, error => {
    if (ConsentInformation.IsConsentFormAvailable())
        ConsentForm.Load((form, loadError) => form.Show(dismissError => { /* init ads */ }));
});
```

## IAB TCF v2.2 CMPs

Required since Sept 2023 for Google ads in EEA. Most CMP SDKs (OneTrust, Sourcepoint, Quantcast Choice) handle the v2.1 to v2.2 upgrade. If you roll your own consent UI, the consent string must match TCF v2.2 format — do not. Use a vendor CMP.

## COPPA age-gating

Required for apps targeting children (Family category, US under-13). On first launch, age dialog ("Enter year of birth"). If under threshold (<13 US, varies by region):
- Disable behavioral ads (set Tag For Child Directed Treatment = true in ad SDK).
- Disable analytics PII (no user ID, no email).
- Disable social features (chat, leaderboards with names).

Google Play Families program is stricter — every third-party SDK must be COPPA-certified, or the app cannot ship in Families. Many ad networks won't serve traffic in this mode.

## Order of operations on first launch

1. Splash + boot scene (cross-link unity-scenes).
2. Region detect (ad SDK helper or device locale).
3. EU/EEA/UK: show CMP consent form. Block boot until dismissed.
4. US (and family-eligible): COPPA age gate.
5. iOS only: ATT prompt. Apple recommends on the first launch where ad value is established, NOT before user understands the app.
6. Initialize analytics + ad SDKs with consent string and ATT status.
7. Continue to main menu.

## Data deletion requests

GDPR Article 17 + CCPA + Google Play Data Deletion Policy 2024.

- **In-app**: Settings > "Delete my data" button. Plus email or web URL fallback.
- **Backend**: receive deletion request, anonymize / delete user record, IAP receipts (legal retention requirements vary — consult counsel; typically retain receipts for tax period), analytics events. Service must process within 30 days.
- **Apple**: Privacy Policy URL must include data deletion contact.
- **Google Play (since 2024)**: app must offer in-app deletion OR a public web URL referenced in Play Console listing. Both are fine; pick one and document it.

## Common patterns

- **`ConsentManager` singleton**: tracks state, persists last-seen consent string in PlayerPrefs (cross-link unity-persistence), passes consent to ad SDKs on init.
- **Settings "Privacy" section**: re-show CMP, "Delete my data" button, link to Privacy Policy URL, "Do Not Sell" toggle (CCPA).
- **Region detection via ad SDK**: `MaxSdkUtils.GetSdkConfiguration().ConsentDialogState` or AdMob equivalent — simpler than rolling your own geo IP.
- **Analytics gating**: every analytics event call routes through `ConsentManager.IsAnalyticsAllowed()` check (cross-link unity-analytics-events).

## Gotchas

- Forgetting `NSUserTrackingUsageDescription` in Info.plist = ATT prompt never shows + Apple rejection. Add a post-build hook to assert it (cross-link unity-build, `OnPostprocessBuild`).
- Showing ATT before user understands the app = 80%+ deny rate. Soft-prompt first.
- GDPR consent must be granular: Accept All and Reject All buttons EQUALLY prominent. "Reject" cannot be hidden behind a "Manage Settings" submenu — that's a regulator finding waiting to happen.
- CCPA isn't optional even outside California in 2026 — most studios make "Do Not Sell" globally available in settings to stay safe across state-level laws (Colorado CPA, Virginia VCDPA, etc.).
- COPPA + Family category: SDKs must be COPPA-certified; many ad networks won't serve traffic in this mode. Plan revenue accordingly.
- Privacy Policy URL must be live and accurate. App Store reviewers click it. 404 = rejection. Status-200 with stale content (mentions a different app) = rejection.
- Storing consent in PlayerPrefs is fine; clearing PlayerPrefs (or app uninstall) resets consent — must re-prompt on next launch. Document this for support.
- SKAN versions: SKAN 4 is the current spec. Ad networks need SKAN 4 conversion value mapping configured in their dashboard or attribution breaks silently.
- ATT can only be re-prompted via iOS Settings — once the user denies in-app, you cannot re-prompt programmatically. Add a "How to enable tracking" deep link to Settings in your privacy screen.
- Editor returns mock ATT values — you cannot validate timing in the Editor. Always test on a fresh install on device.

## Verification

- **Editor**: ATT API returns mock value; logic paths run but do not exercise the iOS prompt.
- **iOS device, fresh install**: ATT prompt appears at the right time → status changes from `NOT_DETERMINED` to `AUTHORIZED` / `DENIED`. Verify ad SDK logs the new state.
- **EU device or VPN**: CMP form appears on first launch. Verify TCF string is set in ad SDK.
- **LogAssert**: ad SDK logs consent state ("TCF string set", "ATT denied — using SKAN"). Cross-link unity-tests.
- **Post-build hook**: `OnPostprocessBuild` confirms `NSUserTrackingUsageDescription` is present in Info.plist before archive (cross-link unity-build).
- **Privacy Policy URL**: HEAD request returns 200, body mentions current app name + data deletion contact.
- **Settings flow**: re-open CMP, toggle "Do Not Sell", trigger "Delete my data" → end-to-end through backend.

## Cross-links

- **unity-privacy-manifests** — paired requirement for App Store; PrivacyInfo.xcprivacy is a separate artifact.
- **unity-ads-mediation** — consent string and ATT status feed into ad SDKs.
- **unity-analytics-events** — consent gates every analytics call.
- **unity-build** — `OnPostprocessBuild` hook verifies Info.plist keys.
- **unity-persistence** — consent string and CCPA opt-out persist in PlayerPrefs.
- **unity-scenes** — boot scene blocks until consent flow completes.
- **unity-best-practices** — render pipeline / Input System / paradigm rules apply.

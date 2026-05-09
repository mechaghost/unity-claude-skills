---
name: unity-store-shipping-pipeline
description: 'Use for Unity 6+ store release work after .ipa/.aab exists: TestFlight, Play Console tracks, phased rollout, App Store/Play APIs, fastlane, metadata, screenshots, version codes, signing/provisioning, review, hotfixes. Not build mechanics, symbol upload, or secret storage.'
---

## When to use

Use for everything between signed artifact and live binary: TestFlight / Play tracks, metadata/screenshots, versioning, bundle IDs, store APIs, review, phased rollout. Cross-links: `unity-build`, `unity-vcs`, `unity-crash-reporting`, `unity-iap`, `unity-consent-att-gdpr`, `unity-privacy-manifests`, `unity-localization`.

## Why distinct from unity-build

`unity-build` makes artifacts. Store shipping handles portals, fastlane, signing, review, testers, and production rollout.

## Pre-launch checklist (week before)

- PrivacyInfo.xcprivacy + Play Data Safety form filled (`unity-privacy-manifests`).
- ATT prompt + GDPR/UMP flow tested live (`unity-consent-att-gdpr`).
- IAP products configured + sandbox-tested (`unity-iap`).
- Crashlytics/Sentry symbol upload working for IL2CPP (`unity-crash-reporting`).
- Analytics events firing in DebugView / live dashboards.
- Privacy Policy + Terms URLs live, accurate, reachable from listing.
- Screenshots, app icon, description in every required language.
- Localized strings audited for clipping and untranslated keys (`unity-localization`).
- Build signed with production certs + matching provisioning.
- `CFBundleShortVersionString` / `versionName` and `CFBundleVersion` / `versionCode` correct.

## TestFlight (iOS)

- **Internal Testing**: <=100 ASC members, no Apple review, appears after processing.
- **External Testing**: <=10,000 testers; first build/version needs Beta App Review.
- **Upload**: Xcode Organizer / Transporter, `xcodebuild -exportArchive` followed by Transporter or fastlane upload, or `fastlane pilot upload`.
- **Builds expire 90 days** after upload.
- **Feedback**: testers submit screenshots + comments per build from the TestFlight app.

## Play Store testing tracks (Android)

- **Internal Testing**: <=100 testers, no review, minutes.
- **Closed Testing**: invitation-only via list / Google Group. Review (~hours). Multiple closed tracks supported.
- **Open Testing**: public, requires review.
- **Pre-launch Report**: Firebase Test Lab devices, crashes, screenshots; required before Production.

## Phased / staged rollout

- **Apple phased release**: fixed 1 -> 2 -> 5 -> 10 -> 20 -> 50 -> 100% over 7 days.
- **Play Store staged rollout**: arbitrary percentages (1, 5, 10, 25, 50, 100) with manual control. Halt stops new users; partial rollback NOT supported — publish a fix.
- **Best**: 1-day soak at 1%, watch crash-free % > 99.5%, then ramp.

## App Store Connect API

JWT REST. Generate key in ASC > Users and Access > Keys. Download `.p8` once; store securely.

Use cases: upload builds, update metadata, manage TestFlight groups, query reviews, manage IAP status. fastlane consumes "App Store Connect API Key (JSON Key Format)" — a JSON wrapping `key_id`, `issuer_id`, `.p8` contents.

## Google Play Publisher API

Service account JSON from GCP plus Play Console API access permissions. Used for AAB upload, listings, tracks, reports; fastlane `supply --json_key`.

## fastlane integration

Use `fastlane/Fastfile` lanes:

- `lane :beta` — build + upload to TestFlight (iOS) or Internal Testing (Android).
- `lane :release` — build + upload to App Store / Play Store production.
- `lane :metadata` — sync `fastlane/screenshots/` and `fastlane/metadata/`.

Key actions:

- **match** (iOS): cert/profile management via private repo.
- **pilot** (iOS): TestFlight upload + tester invite management.
- **gym** (iOS): wraps `xcodebuild`.
- **snapshot** (iOS): screenshot automation via XCUITest.
- **supply** (Android): Play Store upload + metadata sync.
- **screengrab** (Android): screenshots via Espresso.

## Version code / build number arithmetic

- **Apple `CFBundleVersion`** (Build Number) — strictly increases per TestFlight upload. Doesn't matter to users.
- **Apple `CFBundleShortVersionString`** (Version) — semver shown to users (`1.2.3`). Bump per release.
- **Android `versionCode`** (int) — monotonic forever. Scheme: `<major><minor><patch><build>` (e.g. `1020315` = 1.2.3 build 15) or simple counter.
- **Android `versionName`** — display string (`"1.2.3"`).
- Automate from git: tag (`v1.2.3`) for version, `git rev-list --count HEAD` or CI run number for build.

## Bundle ID per environment

- Production: `com.studio.gamename`.
- Beta: `com.studio.gamename.beta` — separate app in Play Console / ASC. Side-by-side install with prod.
- Staging: `com.studio.gamename.staging` — internal QA.

Each environment gets separate signing, IAP catalog, Firebase/analytics, and crash project.

## Store metadata automation

Store metadata under `fastlane/metadata/<locale>/` (`description.txt`, `keywords.txt`, `release_notes.txt`, `name.txt`, `subtitle.txt`). Sync with `deliver` / `supply`.

One folder per locale (`en-US`, `de-DE`, `ja`, `zh-Hans`). Apple keywords: 100 chars, comma-separated, do not repeat brand.

## Screenshot and preview-video automation

Required device classes:

- **Apple**: iPhone 6.7", iPhone 6.5", iPhone 5.5", iPad Pro 12.9". (Apple scales largest provided down; explicit sets required for listed classes.)
- **Google Play**: phone (required), 7" tablet, 10" tablet (recommended).

Automate screenshots with `snapshot` / `screengrab`. Preview videos are 15-30s loops, usually recorded separately.

## Submission and review

- **Apple review**: 24-48h average; first submission slowest. Common: privacy info, broken IAP restore, purchase links outside StoreKit, missing Sign in with Apple.
- **Play review**: hours to days. Common: permission misuse, Data Safety mismatch, deceptive UI, broken back button.
- **Expedited review** (Apple): genuine emergencies (security, crash on launch). ~24h. Sparingly — abuse remembered.
- **Hotfix**: same flow. Phased can start at 100% if bug severe — accept higher blast radius.

## Common patterns

- **CI pipeline**: build → test → upload symbols → upload to TestFlight / Internal Testing → notify QA via Slack.
- **Manual approval gate** between staging upload and production submission.
- **Release notes** auto-generated from git commits since last tag (squash + conventional commits).
- **Tag releases**: `git tag v1.2.3`; tag should match store version for support/crash mapping.

## Live-ops boot-order checklist

First session boot order matters: wrong order causes IDFA-less attribution, missed crashes, consent violations, or RC racing auth.

```
1. Boot scene / Bootstrapper (`unity-scenes`).
2. Crashlytics/Sentry first (`unity-crash-reporting`).
3. Firebase/analytics SDK, no events yet (`unity-analytics-events`).
4. EU/EEA/UK consent form; block until dismissed (`unity-consent-att-gdpr`).
5. iOS ATT before tracked ad init.
6. Auth / anonymous sign-in (`unity-auth-account-linking`).
7. Remote Config fetch or defaults (`unity-remote-config-flags`).
8. Ad SDK with consent string (`unity-ads-mediation`).
9. IAP v5 connect/fetch products/fetch purchases (`unity-iap`).
10. Push SDK; request permission later (`unity-push-local-notifications`).
11. Now safe to log first analytics event ('first_session_start').
```

Hard rules: ATT before ad SDK init; Crashlytics first; Firebase before UMP; Auth before user-targeted Remote Config; block consent in EU/EEA/UK only.

## Gotchas

- **Apple signing certs lost** = cannot ship updates. Back up Apple Developer 2FA + signing certs to multiple secure locations. fastlane match in private repo is the canonical fix.
- **Android upload key lost** = cannot update Play listing. Play App Signing mitigates — Google holds app signing key, you upload an "upload key" they re-sign.
- **Submitting binary before metadata** = rejected.
- **IAP not "submitted for review" with binary** = IAP doesn't work for real users. IAP entry has its own review state.
- **Phased rollout is not a rollback**: halting only stops new users; recover already-rolled-out users by publishing a fix.
- **TestFlight 90-day expiry**: re-upload before deadline.
- **Build number not incremented** = Apple silent reject / Play marks duplicate.
- **Different `.p8` ASC API key per Mac** = fastlane breaks. Share canonical key via 1Password CLI or fastlane match-style encrypted repo.
- **Localized metadata mismatch** = rejection.
- **First Apple review** is slowest — don't schedule launch the day after first submission.

## Verification

- TestFlight build appears in TestFlight app within 10 min of upload + processing.
- Internal testers install and run on real devices.
- Pre-launch Report (Play) passes with no critical issues.
- Phased rollout: crash-free % > 99.5% during ramp; halt and investigate if it dips.
- First production day: monitor Crashlytics + analytics for ≥ first 6 hours.
- Store reviews appear on ASC / Play Console within 24-48h of public availability.

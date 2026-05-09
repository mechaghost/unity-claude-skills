---
name: unity-store-shipping-pipeline
description: 'Use when promoting a Unity build artifact (.ipa / .aab) into the App Store or Play Store — store shipping, App Store, Play Store, TestFlight, Play Console, internal testing, closed testing, open testing, phased rollout, staged rollout, App Store Connect API, Google Play Publisher API, fastlane, fastlane match, fastlane deliver, fastlane supply, fastlane pilot, fastlane gym, store metadata, store listing, screenshots, preview videos, app icon submission, App Store Connect screenshots, Play Console screenshots, version code, bundle version, build number, semver, signing, keystore, Apple provisioning, App Store Connect API key, P8 file, Google service account JSON, store submission, app review, Apple review, Play review, expedited review, hotfix release, patch release. Disambiguator — NOT for build pipeline mechanics (use unity-build), NOT for crash symbol upload (use unity-crash-reporting), NOT for keystore secret storage (use unity-vcs).'
---

## When to use

Anything that happens between a signed build artifact and the binary being live in front of paying users. Includes uploading to TestFlight or Play Internal Testing, configuring testing tracks, automating store metadata and screenshots, version-code arithmetic, bundle ID separation per environment, configuring App Store Connect / Google Play Publisher API access, and walking submissions through review and phased rollout. Read `unity-best-practices` first. Cross-link `unity-build` (for the build artifact itself), `unity-vcs` (keystore + fastlane match secret storage), `unity-crash-reporting` (symbol upload that must work before submission), `unity-iap` (sandbox testing flow), `unity-consent-att-gdpr` and `unity-privacy-manifests` (review blockers), `unity-localization` (localized store metadata).

## Why distinct from unity-build

`unity-build` produces an `.ipa` or `.aab`. Getting that artifact onto phones in front of testers, then in front of millions, is a multi-week, mostly non-Unity workflow involving Apple/Google portals, fastlane, signing infrastructure, and review processes. Different skill.

## Pre-launch checklist (week before launch)

- PrivacyInfo.xcprivacy + Play Data Safety form filled (`unity-privacy-manifests`).
- ATT prompt + GDPR/UMP consent flow tested live (`unity-consent-att-gdpr`).
- IAP products configured per platform + sandbox-tested (`unity-iap`).
- Crashlytics/Sentry symbol upload working for IL2CPP builds (`unity-crash-reporting`).
- Analytics events firing in DebugView / live dashboards.
- Privacy Policy + Terms of Service URLs live, accurate, and reachable from the listing.
- Screenshots, app icon, and description in every required language.
- Localized strings audited for clipping and untranslated keys (`unity-localization`).
- Build signed with production certs and matching provisioning.
- `CFBundleShortVersionString` / `versionName` and `CFBundleVersion` / `versionCode` correct.

## TestFlight (iOS)

- **Internal Testing**: up to 100 App Store Connect team members. No Apple review. Builds appear in the TestFlight app within ~10 min of processing.
- **External Testing**: up to 10,000 testers. First build per version requires Beta App Review (24-48h first time, much faster after). Public link available.
- **Build submission**: Xcode Organizer upload, `xcodebuild -exportArchive` + `xcrun altool` (deprecated) or `xcrun notarytool`, or `fastlane pilot upload`.
- **Builds expire 90 days** after upload — re-upload before deadline for ongoing tests.
- **Feedback**: testers can submit screenshots + comments per build directly from the TestFlight app.

## Play Store testing tracks (Android)

- **Internal Testing**: up to 100 testers, no review, available within minutes.
- **Closed Testing**: invitation-only via list or Google Group. Requires review (~hours). Multiple closed tracks supported for staged QA.
- **Open Testing**: public, requires review.
- **Pre-launch Report**: Firebase Test Lab runs your APK/AAB on real devices, collects crashes + screenshots. Required to pass before Production submission.

## Phased / staged rollout

- **Apple phased release**: fixed schedule 1% → 2% → 5% → 10% → 20% → 50% → 100% over 7 days. Pause if crash-free % drops.
- **Play Store staged rollout**: arbitrary percentages (e.g. 1%, 5%, 10%, 25%, 50%, 100%) with manual control. Halt rollout to stop new users; partial rollback is NOT supported — you must publish a fix.
- **Best practice**: 1-day soak at 1%, watch crash-free % stay >99.5%, then ramp.

## App Store Connect API

JWT-based REST API. Generate a key at App Store Connect > Users and Access > Keys. Download the `.p8` file once — Apple will not let you re-download it. Store securely (1Password, Vault, fastlane match-style git-crypt repo).

Use cases: upload builds, update metadata, manage TestFlight groups, query customer reviews, manage in-app purchase status. fastlane consumes the key in "App Store Connect API Key (JSON Key Format)" — a JSON wrapper containing `key_id`, `issuer_id`, and the `.p8` contents.

## Google Play Publisher API

Service account JSON key from Google Cloud Console + matching permissions in Play Console (Settings > API access). Use cases: upload AAB, update store listing, manage testing tracks, query financial reports. fastlane `supply` consumes it via `--json_key path/to/api.json`.

## fastlane integration

The standard tool. Install via `gem install fastlane` (Ruby). Per-platform `Fastfile` lives at `fastlane/Fastfile` and defines lanes:

- `lane :beta` — build + upload to TestFlight (iOS) or Internal Testing (Android).
- `lane :release` — build + upload to App Store / Play Store production.
- `lane :metadata` — sync screenshots and descriptions from `fastlane/screenshots/` and `fastlane/metadata/`.

Key actions:

- **match** (iOS): centralized cert + profile management via private git repo. Eliminates code-signing drift across machines and CI.
- **pilot** (iOS): TestFlight upload + tester invite list management.
- **gym** (iOS): build action wrapping `xcodebuild`.
- **snapshot** (iOS): screenshot automation via XCUITest.
- **supply** (Android): Play Store upload + metadata sync.
- **screengrab** (Android): screenshot automation via Espresso.

## Version code / build number arithmetic

- **Apple `CFBundleVersion`** (Build Number) — must strictly increase every TestFlight upload. Doesn't matter for users.
- **Apple `CFBundleShortVersionString`** (Version) — semver displayed to users (`1.2.3`). Bump per release.
- **Android `versionCode`** (int) — must monotonically increase forever. Common scheme: `<major><minor><patch><build>` (e.g. `1020315` = 1.2.3 build 15) or simple incrementing counter.
- **Android `versionName`** — display string (`"1.2.3"`).
- **Automate from git**: `git rev-list --count HEAD` for build number; tag (`v1.2.3`) for version. Set both on every CI build so a rebuild produces a new uploadable artifact.

## Bundle ID per environment

- Production: `com.studio.gamename`.
- Beta: `com.studio.gamename.beta` — registered as a separate app in Play Console / App Store Connect. Allows side-by-side install with prod.
- Staging: `com.studio.gamename.staging` — internal QA only.

Each gets its own keystore + signing identity, IAP catalog, Firebase project, and analytics property. Don't share Crashlytics or analytics across environments — it pollutes prod data with QA noise.

## Store metadata automation

`fastlane/metadata/<locale>/description.txt`, `keywords.txt`, `release_notes.txt`, `name.txt`, `subtitle.txt`. Edit in repo; `fastlane deliver` (iOS) or `fastlane supply` (Android) syncs to stores.

Localized: one folder per locale (`en-US`, `de-DE`, `ja`, `zh-Hans`, etc.). Apple keywords field has a 100-char total limit, comma-separated, and must NOT repeat the brand name (App Store Review Guidelines).

## Screenshot and preview-video automation

Required device classes:

- **Apple**: iPhone 6.7", iPhone 6.5", iPhone 5.5", iPad Pro 12.9". (Apple uses the largest provided size to scale for smaller devices, but explicit sets are required for the listed classes.)
- **Google Play**: phone (required), 7" tablet, 10" tablet (optional but recommended for tablet visibility).

Automate via fastlane `snapshot` / `screengrab`: a scripted UI walkthrough renders the same screens at every required size. Preview videos are 15-30s autoplay loops on the listing — heavy lift, usually one-off recorded with screen capture and edited externally.

## Submission and review

- **Apple review**: 24-48h average. First-ever submission for a new app is the slowest. Common rejections: missing privacy info, broken IAP restore button, IAP-circumventing references (links to web purchase flow), "purchase" or "subscribe" outside StoreKit, sign-in requirements without "Sign in with Apple".
- **Play review**: hours to days. Common: permission misuse, Data Safety form mismatch with actual collection, deceptive UI, broken back-button behavior on Android.
- **Expedited review** (Apple): for genuine emergencies (security, crash on launch). ~24h. Use sparingly — abuse will be remembered.
- **Hotfix release**: same flow. Phased rollout can start at 100% if the bug is severe enough — accept the higher blast-radius risk.

## Common patterns

- **CI pipeline**: build → test → upload symbols → upload to TestFlight / Internal Testing → notify QA via Slack webhook.
- **Manual approval gate** between staging upload and production submission.
- **Release notes** auto-generated from git commits since last tag (squash merges + conventional commits make this clean).
- **Tag releases**: `git tag v1.2.3` at the release commit; the tag string must match the App Store version exactly so support can map crash reports back to source.

## Live-ops boot-order checklist

The first session of a freshly installed F2P game has to wire up six-plus subsystems in a specific order. Get it wrong and you get IDFA-less attribution, lost crash reports, consent violations, or a remote-config fetch racing the auth handshake. Each step crosses into a different skill — this is the connective tissue.

```
1. Boot scene loads: bring up Bootstrapper GameObject. Cross-link unity-scenes.
2. Initialize Crashlytics/Sentry FIRST. Cross-link unity-crash-reporting. Catches bugs in everything that follows.
3. Initialize Firebase (or chosen analytics SDK) — but do NOT log events yet. Cross-link unity-analytics-events.
4. Show consent dialog if EU/EEA/UK user. UMP Form.show(). Block boot until dismissed. Cross-link unity-consent-att-gdpr.
5. iOS only: show ATT prompt. Apple recommends after user understands the app, before any tracked ad init. Cross-link unity-consent-att-gdpr.
6. Initialize Unity Authentication (or Firebase Auth) — anonymous sign-in if no linked credential. Cross-link unity-auth-account-linking.
7. Initialize Remote Config + fetch. Block boot or proceed with defaults if fetch fails. Cross-link unity-remote-config-flags.
8. Initialize ad SDK (AppLovin MAX / LevelPlay) with consent string from step 4. Cross-link unity-ads-mediation.
9. Initialize IAP v5: connect store, fetch products, fetch purchases/entitlements. Cross-link unity-iap.
10. Initialize push notifications (request permission contextually, NOT here). Cross-link unity-push-local-notifications.
11. Now safe to log first analytics event ('first_session_start').
```

Hard rules:

- **ATT BEFORE ad SDK init** — otherwise IDFA-less attribution forever; the ad SDK caches the IDFA absence at init.
- **Crashlytics FIRST** — catches everything else's init failures.
- **Firebase BEFORE consent** — the consent SDK (UMP) may use Firebase under the hood.
- **Auth BEFORE remote config** — remote config can target by user properties, which require an authenticated user.
- **Block on consent in EU/EEA/UK; non-blocking elsewhere.** Don't block a US user on a UMP form they'll never see.

## Gotchas

- **Apple signing certs lost** = cannot ship updates. Back up the Apple Developer account 2FA + signing certs to multiple secure locations. fastlane match in a private repo is the canonical fix.
- **Android upload key lost** = cannot update Play Store listing. Play App Signing mitigates this — Google holds the app signing key and you upload an "upload key" they re-sign with. Don't lose the upload key either.
- **Submitting binary before metadata is set** = rejected.
- **IAP configured but not "submitted for review" with the binary** = IAP doesn't work for real users. The IAP entry has its own review state distinct from the binary.
- **Phased rollout is not a rollback mechanism**: halting only stops new users from getting the build. To recover already-rolled-out users you must publish a fix.
- **TestFlight 90-day expiry**: re-upload before deadline or external testers lose access mid-test.
- **Build number not incremented** = upload silently rejected (Apple) or marked as duplicate (Play).
- **Different `.p8` ASC API key per Mac** = fastlane breaks unpredictably. Share the canonical key via 1Password CLI or a fastlane match-style encrypted repo.
- **Localized metadata mismatch** (English screenshot says "Tap to play"; German metadata describes a different feature) = rejection.
- **First Apple review for a new app** is the slowest; subsequent updates are much faster. Don't schedule launch the day after first submission.

## Verification

- TestFlight build appears in the Apple TestFlight app within 10 min of upload + processing.
- Internal testers can install and run on real devices.
- Pre-launch Report (Play) passes with no critical issues.
- Phased rollout: crash-free % stays >99.5% during ramp; halt and investigate if it dips.
- First production day: monitor Crashlytics + analytics dashboards continuously for at least the first ~6 hours.
- Store reviews start appearing on App Store Connect / Play Console within 24-48h of public availability.

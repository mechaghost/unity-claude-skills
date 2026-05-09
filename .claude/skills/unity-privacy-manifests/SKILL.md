---
name: unity-privacy-manifests
description: 'Use when authoring Apple PrivacyInfo.xcprivacy manifests or Google Play Data Safety declarations for a Unity iOS/Android build — PrivacyInfo, PrivacyInfo.xcprivacy, privacy manifest, Apple privacy manifest, iOS privacy manifest, required reason API, NSPrivacyAccessedAPITypes, NSPrivacyTracking, NSPrivacyTrackingDomains, NSPrivacyCollectedDataTypes, third-party SDK signature, Apple SDK signature, Play Data Safety, Google Play Data Safety, data safety form, data types collected, data sharing, data deletion, app privacy disclosure, App Privacy nutrition label, ITMS-91053, ITMS-91065, NSPrivacyAccessedAPICategoryFileTimestamp, NSPrivacyAccessedAPICategoryUserDefaults, NSPrivacyAccessedAPICategoryDiskSpace, NSPrivacyAccessedAPICategorySystemBootTime, NSPrivacyAccessedAPICategoryActiveKeyboards. Disambiguator — this is the static manifest/store-form work. NOT the runtime ATT/GDPR consent flow (use unity-consent-att-gdpr — they pair but are different). Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Any task that touches store-submission privacy paperwork: building or updating `PrivacyInfo.xcprivacy`, declaring Required Reason APIs, registering tracking domains, filling Google Play's Data Safety form, or chasing `ITMS-91053`/`ITMS-91065` rejections. Pair with `unity-consent-att-gdpr` for the *runtime* consent flow (ATT prompt, CMP/UMP, GDPR consent string) — they are separate but co-required: a missing manifest blocks upload, a missing ATT prompt silently breaks attribution. Cross-link `unity-build` for the post-build hook that registers `PrivacyInfo.xcprivacy` with the Xcode project, `unity-ads-mediation` (each ad SDK ships its own manifest), `unity-analytics-events`, `unity-best-practices`.

## Why this is a store-review blocker

Apple began **enforcing** PrivacyInfo manifests on **May 1, 2024**. Apps without a complete manifest, or with a manifest that contradicts actual API usage, get rejected at upload (`ITMS-91053: Missing API declaration`) or in review (`ITMS-91065: Missing signature`). Google Play's Data Safety form has been required since **July 2022**; misleading declarations get flagged by Google's SDK fingerprinting audits and can trigger forced re-review or removal. Both are static disclosures that travel with the binary/listing — different from runtime consent UI.

## Apple PrivacyInfo.xcprivacy structure

XML plist file. Must sit at the root of every framework/binary that needs one (the app's main target plus each third-party SDK). Top-level keys:

- `NSPrivacyTracking` (bool) — does the app/SDK track users (cross-app or cross-website tracking under Apple's definition)?
- `NSPrivacyTrackingDomains` (array of strings) — required if `NSPrivacyTracking` is true. Every domain that performs cross-app tracking must be listed here, or Apple silently blocks non-consented connections to it.
- `NSPrivacyCollectedDataTypes` (array of dicts) — every data type collected, why, and whether it's linked to the user.
- `NSPrivacyAccessedAPITypes` (array of dicts) — Required Reason APIs (the four categories below).

## The four Required Reason API categories

Apple's 2024 list. You must declare a reason code for *every* category your code (or any embedded code) hits.

- **NSPrivacyAccessedAPICategoryFileTimestamp** — `NSFileCreationDate`, `NSURLContentModificationDateKey`, `getattrlist`, `stat`. Reasons: `C617.1` inside container, `0A2A.1` track app's own file timestamps, `3B52.1` display to user, `8FFB.1` unaltered timestamps for syncing.
- **NSPrivacyAccessedAPICategoryUserDefaults** — `NSUserDefaults` (Unity's `PlayerPrefs` uses this on iOS). Reasons: `CA92.1` access only your own defaults, `1C8F.1` access defaults to display, `C56D.1` track app installation status, `AC6B.1` access app group defaults.
- **NSPrivacyAccessedAPICategoryDiskSpace** — `NSURLVolumeAvailableCapacityKey`, `statfs`, `statvfs`. Reasons: `85F4.1` warn user about low disk, `E174.1` check available space before write, `7D9E.1` recommend disk-cleanup UI.
- **NSPrivacyAccessedAPICategorySystemBootTime** — `mach_absolute_time`, `kern.boottime`, `systemUptime`. Reasons: `35F9.1` measure time intervals, `8FFB.1` system reliability.

Plus `NSPrivacyAccessedAPICategoryActiveKeyboards`, `NSPrivacyAccessedAPICategoryUserAgent` and others — full list at https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api.

## Tracking and Collected Data sections

```xml
<key>NSPrivacyTracking</key><true/>
<key>NSPrivacyTrackingDomains</key>
<array>
  <string>app-measurement.com</string>
  <string>googleads.g.doubleclick.net</string>
</array>
<key>NSPrivacyCollectedDataTypes</key>
<array>
  <dict>
    <key>NSPrivacyCollectedDataType</key>
    <string>NSPrivacyCollectedDataTypeAdvertisingData</string>
    <key>NSPrivacyCollectedDataTypeLinked</key><false/>
    <key>NSPrivacyCollectedDataTypeTracking</key><true/>
    <key>NSPrivacyCollectedDataTypePurposes</key>
    <array><string>NSPrivacyCollectedDataTypePurposeAdvertising</string></array>
  </dict>
</array>
```

`Linked` = tied to the user's identity; `Tracking` = used for cross-app tracking (requires ATT). Purposes: `Analytics`, `AppFunctionality`, `Advertising`, `ProductPersonalization`, `DeveloperAdvertising`, `Other`.

## Third-party SDK signature requirement

Every SDK on Apple's "commonly used SDKs" list must be **signed** AND ship its own `PrivacyInfo.xcprivacy`. Common offenders for Unity projects: Firebase, AppLovin MAX, ironSource / LevelPlay, AdMob (Google Mobile Ads), Adjust, AppsFlyer, OneSignal, Branch. Pull the latest list from https://developer.apple.com/support/third-party-SDK-requirements and update SDKs to versions that ship manifest + signature; older versions = rejection at review (`ITMS-91065`).

## Generating PrivacyInfo via post-build callback

Keep a checked-in template at `Assets/Plugins/iOS/PrivacyInfo.xcprivacy`. Unity copies plain `Plugins/iOS/` files into the Xcode project automatically, but the file still needs to be added to the **main target's Resources** so it ships at the bundle root. Use a post-build hook:

```csharp
using System.IO;
using UnityEditor;
using UnityEditor.Callbacks;
using UnityEditor.iOS.Xcode;

public static class PrivacyManifestPostBuild {
    [PostProcessBuild(callbackOrder: 100)]
    public static void OnPostprocessBuild(BuildTarget target, string path) {
        if (target != BuildTarget.iOS) return;
        var src = Path.Combine(Application.dataPath, "Plugins/iOS/PrivacyInfo.xcprivacy");
        var dst = Path.Combine(path, "PrivacyInfo.xcprivacy");
        File.Copy(src, dst, overwrite: true);

        var pbxPath = PBXProject.GetPBXProjectPath(path);
        var pbx = new PBXProject();
        pbx.ReadFromFile(pbxPath);
        var fileGuid = pbx.AddFile("PrivacyInfo.xcprivacy", "PrivacyInfo.xcprivacy");
        pbx.AddFileToBuild(pbx.GetUnityMainTargetGuid(), fileGuid);
        pbx.WriteToFile(pbxPath);
    }
}
```

See `unity-build` for the broader post-build pattern (Info.plist edits, capabilities, signing).

## Google Play Data Safety form

Play Console > App content > Data safety. Declare for each data type: collected? shared? optional or required? linked to user? used for tracking? deletable on request? Re-submit on every store listing update if practices change. Top-level categories: Personal info, Financial info, Health and fitness, Messages, Photos and videos, Audio, Files and docs, Calendar, Contacts, Location, Web browsing, App activity, App info and performance, Device or other identifiers.

## Mapping common Unity APIs to declarations

- **`PlayerPrefs`** → NSPrivacyAccessedAPICategoryUserDefaults, reason `CA92.1` (own defaults).
- **`File.WriteAllText` / `Application.persistentDataPath`** → NSPrivacyAccessedAPICategoryFileTimestamp `C617.1` + NSPrivacyAccessedAPICategoryDiskSpace `E174.1`.
- **`Time.realtimeSinceStartup` / `DateTime.Now`** for elapsed-time math → NSPrivacyAccessedAPICategorySystemBootTime `35F9.1`.
- **Unity Crashlytics / Firebase Crashlytics** → SDK ships its own manifest; you still declare `Diagnostics` collected data on the app's manifest if you forward crash data.
- **AdMob / AppLovin MAX / LevelPlay / Unity LevelPlay** → SDK ships own manifest + signature; you declare `AdvertisingData`, `DeviceID`, tracking domains, and add ATT prompt (see `unity-consent-att-gdpr`).
- **Firebase Analytics** → automatic SDK manifest + you declare Tracking and Collected Data (`UsageData`, `DeviceID`) on the app manifest.
- **Custom analytics endpoint** → declare your domain in `NSPrivacyTrackingDomains` if it performs tracking.

## Common patterns

- Maintain `Assets/Plugins/iOS/PrivacyInfo.xcprivacy` as a checked-in template; post-build copies it into the Xcode project root and registers it.
- Audit on every SDK upgrade — new SDK versions frequently add tracking domains or new data types.
- Keep a private `docs/data-flows.md` that lists every endpoint the app calls plus why; the Data Safety form is generated from this, not from memory.
- For builds-without-tracking (paid apps, kids titles), set `NSPrivacyTracking=false` and omit `NSPrivacyTrackingDomains` — but you still must declare Required Reason APIs.

## Gotchas

- Apple validates the manifest at upload; a mismatch between declared APIs and actual API usage = `ITMS-91053` rejection. Don't over-declare either — Apple flags unused declarations in newer Xcode validations.
- `NSPrivacyTracking=true` with no `NSUserTrackingUsageDescription` Info.plist key = silent failure: ATT prompt never shows, attribution falls back to fingerprint-only / SKAdNetwork.
- Older third-party SDKs without manifest sometimes upload fine but get flagged later in review (`ITMS-91065`). Bump SDKs *before* submission, not after rejection.
- Google Data Safety form auto-fails when your declared SDK list contradicts your declared data practices — Google audits via SDK fingerprinting on the AAB.
- Manifest is required even if you don't track. `NSPrivacyTracking=false` is a valid declaration, but you still must declare every Required Reason API your code touches (PlayerPrefs alone forces a UserDefaults entry).
- Game categories targeting children (Kids, Family) face stricter restrictions on the third-party SDKs you may embed and how `NSPrivacyCollectedDataTypeChildren` is declared.

## Verification

- Build to Xcode → confirm `PrivacyInfo.xcprivacy` appears under the **Unity-iPhone** target's *Build Phases > Copy Bundle Resources*.
- `plutil -p PrivacyInfo.xcprivacy` to validate XML; `plutil -lint PrivacyInfo.xcprivacy` for syntax.
- Upload to App Store Connect → wait for the "Privacy Manifest" diagnostic email; rejection text names the exact API or domain mismatch.
- `xcrun privacycheck <App.app>` (Xcode 16+) catches obvious mismatches locally before submission.
- Google Play Console > App content > Data safety → all declarations must match observed SDK behavior; the Pre-launch report flags privacy issues — check after every release.

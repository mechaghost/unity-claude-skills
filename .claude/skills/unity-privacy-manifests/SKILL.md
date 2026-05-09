---
name: unity-privacy-manifests
description: 'Use for Unity 6+ static privacy artifacts: Apple PrivacyInfo.xcprivacy, Required Reason APIs, NSPrivacy tracking/collected-data keys, third-party SDK signatures, Google Play Data Safety, nutrition labels, ITMS-91053/91065. Not runtime ATT/GDPR consent.'
---

## When to use

Anything touching store-submission privacy paperwork: building/updating `PrivacyInfo.xcprivacy`, declaring Required Reason APIs, registering tracking domains, filling Play's Data Safety form, chasing `ITMS-91053`/`ITMS-91065`. Pair with `unity-consent-att-gdpr` for *runtime* consent (ATT prompt, CMP/UMP, GDPR consent string) — separate but co-required: missing manifest blocks upload, missing ATT silently breaks attribution. Cross-link `unity-build` (post-build hook registers `PrivacyInfo.xcprivacy`), `unity-ads-mediation` (each ad SDK ships its own manifest), `unity-analytics-events`, `unity-best-practices`.

## Store-review blocker

Apple began **enforcing** PrivacyInfo manifests on **May 1, 2024**. Apps without complete manifest, or contradicting actual API usage, get rejected at upload (`ITMS-91053: Missing API declaration`) or in review (`ITMS-91065: Missing signature`). Google Play's Data Safety form has been required since **July 2022**; misleading declarations get flagged by SDK fingerprinting audits and can trigger forced re-review or removal. Both are static disclosures that travel with the binary/listing — different from runtime consent UI.

## Apple PrivacyInfo.xcprivacy structure

XML plist. Sits at root of every framework/binary that needs one (main target + each third-party SDK). Top-level keys:

- `NSPrivacyTracking` (bool) — tracks users (cross-app/cross-website per Apple)?
- `NSPrivacyTrackingDomains` (array) — required if `NSPrivacyTracking` true. Every cross-app tracking domain; otherwise Apple silently blocks non-consented connections.
- `NSPrivacyCollectedDataTypes` (array of dicts) — every data type collected, why, linked-to-user state.
- `NSPrivacyAccessedAPITypes` (array of dicts) — Required Reason APIs (four categories below).

## The four Required Reason API categories

Declare a reason code for *every* category your code (or any embedded code) hits.

- **NSPrivacyAccessedAPICategoryFileTimestamp** — `NSFileCreationDate`, `NSURLContentModificationDateKey`, `getattrlist`, `stat`. Reasons: `C617.1` inside container, `0A2A.1` track app's own file timestamps, `3B52.1` display to user, `8FFB.1` unaltered timestamps for syncing.
- **NSPrivacyAccessedAPICategoryUserDefaults** — `NSUserDefaults` (Unity's `PlayerPrefs` on iOS). Reasons: `CA92.1` access only your own defaults, `1C8F.1` access defaults to display, `C56D.1` track app installation status, `AC6B.1` access app group defaults.
- **NSPrivacyAccessedAPICategoryDiskSpace** — `NSURLVolumeAvailableCapacityKey`, `statfs`, `statvfs`. Reasons: `85F4.1` warn user about low disk, `E174.1` check available space before write, `7D9E.1` recommend disk-cleanup UI.
- **NSPrivacyAccessedAPICategorySystemBootTime** — `mach_absolute_time`, `kern.boottime`, `systemUptime`. Reasons: `35F9.1` measure time intervals, `8FFB.1` system reliability.

Plus `NSPrivacyAccessedAPICategoryActiveKeyboards`, `NSPrivacyAccessedAPICategoryUserAgent`, others — full list at https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api.

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

`Linked` = tied to user identity; `Tracking` = used for cross-app tracking (requires ATT). Purposes: `Analytics`, `AppFunctionality`, `Advertising`, `ProductPersonalization`, `DeveloperAdvertising`, `Other`.

## Third-party SDK signature requirement

Every SDK on Apple's "commonly used SDKs" list must be **signed** AND ship its own `PrivacyInfo.xcprivacy`. Common Unity offenders: Firebase, AppLovin MAX, ironSource / LevelPlay, AdMob, Adjust, AppsFlyer, OneSignal, Branch. Pull latest list from https://developer.apple.com/support/third-party-SDK-requirements and update SDKs to manifest+signature versions; older = `ITMS-91065` rejection.

## Generating PrivacyInfo via post-build callback

Keep a checked-in template at `Assets/Plugins/iOS/PrivacyInfo.xcprivacy`. Unity copies `Plugins/iOS/` into Xcode automatically, but the file still needs adding to the **main target's Resources** so it ships at bundle root:

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

See `unity-build` for broader post-build patterns (Info.plist, capabilities, signing).

## Google Play Data Safety form

Play Console > App content > Data safety. Per data type: collected? shared? optional/required? linked to user? used for tracking? deletable? Re-submit on every listing update if practices change. Top-level categories: Personal info, Financial info, Health and fitness, Messages, Photos and videos, Audio, Files and docs, Calendar, Contacts, Location, Web browsing, App activity, App info and performance, Device or other identifiers.

## Mapping common Unity APIs to declarations

- **`PlayerPrefs`** → NSPrivacyAccessedAPICategoryUserDefaults, `CA92.1`.
- **`File.WriteAllText` / `Application.persistentDataPath`** → FileTimestamp `C617.1` + DiskSpace `E174.1`.
- **`Time.realtimeSinceStartup` / `DateTime.Now`** for elapsed-time → SystemBootTime `35F9.1`.
- **Crashlytics / Firebase Crashlytics** → SDK ships own manifest; declare `Diagnostics` collected data on app manifest if forwarding crashes.
- **AdMob / AppLovin MAX / LevelPlay** → SDK ships own manifest + signature; declare `AdvertisingData`, `DeviceID`, tracking domains, ATT prompt (see `unity-consent-att-gdpr`).
- **Firebase Analytics** → automatic SDK manifest + declare Tracking and Collected Data (`UsageData`, `DeviceID`) on app manifest.
- **Custom analytics endpoint** → declare your domain in `NSPrivacyTrackingDomains` if it tracks.

## Common patterns

- Maintain `Assets/Plugins/iOS/PrivacyInfo.xcprivacy` as checked-in template; post-build copies + registers.
- Audit on every SDK upgrade — new versions add tracking domains / data types.
- Keep private `docs/data-flows.md` listing every endpoint + why; Data Safety form is generated from this, not from memory.
- For builds-without-tracking (paid, kids titles): `NSPrivacyTracking=false`, omit `NSPrivacyTrackingDomains` — but still declare Required Reason APIs.

## Gotchas

- Apple validates at upload; declared APIs vs actual usage mismatch = `ITMS-91053`. Don't over-declare either — newer Xcode validations flag unused declarations.
- `NSPrivacyTracking=true` with no `NSUserTrackingUsageDescription` = silent failure: ATT never shows, attribution falls back to fingerprint-only / SKAN.
- Older SDKs without manifest sometimes upload fine but get flagged later (`ITMS-91065`). Bump SDKs *before* submission.
- Play Data Safety auto-fails when declared SDK list contradicts data practices — Google audits via SDK fingerprinting on the AAB.
- Manifest required even if you don't track. `NSPrivacyTracking=false` is valid, but every Required Reason API your code touches still needs a declaration (PlayerPrefs alone = UserDefaults entry).
- Kids/Family categories face stricter SDK restrictions and `NSPrivacyCollectedDataTypeChildren` declaration.

## Verification

- Build to Xcode → confirm `PrivacyInfo.xcprivacy` under **Unity-iPhone** target's *Build Phases > Copy Bundle Resources*.
- `plutil -p PrivacyInfo.xcprivacy` validates XML; `plutil -lint PrivacyInfo.xcprivacy` checks syntax.
- Upload to ASC → wait for "Privacy Manifest" diagnostic email; rejection text names exact API/domain mismatch.
- `xcrun privacycheck <App.app>` (Xcode 16+) catches obvious mismatches locally.
- Play Console > App content > Data safety → declarations match observed SDK behavior; Pre-launch report flags privacy issues.

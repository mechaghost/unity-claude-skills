---
name: unity-crash-reporting
description: 'Use for Unity 6+ crash/non-fatal reporting: Crashlytics, Sentry, Bugsnag, Backtrace, Cloud Diagnostics, native/managed crashes, ANR/OOM, breadcrumbs/custom keys/user IDs, dSYM/IL2CPP/NDK/ProGuard/R8 symbol upload. Not analytics or profiling.'
---

## When to use

Game preparing for store submission, soft launch, or post-launch ops with no crash pipeline — or one where symbols aren't uploading. Read `unity-best-practices` first. Cross-link `unity-build` (post-build symbol upload), `unity-analytics-events` (parallel custom-keys pattern), `unity-auth-account-linking` (user-ID source), `unity-consent-att-gdpr` (opt-out wiring), `unity-profiling` (ANR root-cause).

## Why

Without a crash service, your only signal is bad reviews, support tickets, refunds — by which time the user is gone. With one: crash-free-users %, top crashes by frequency, symbolicated stacks, device/OS/locale distribution, breadcrumbs leading into the crash. Day-one essential.

## Pick a service

- **Firebase Crashlytics** — free, Google-owned, deep Android, Firebase Console UI. Default for Android-first F2P.
- **Sentry (Unity SDK)** — paid, free tier 5k events/month, best Unity integration (auto-captures `Debug.LogError`, `LogException`, native crashes), pairs crashes with perf + custom errors. Default if studio's already on Sentry.
- **Backtrace** — paid, console / mid-core focus, strongest minidump support.
- **Unity Cloud Diagnostics** — legacy, replaced by UCB offerings. Not recommended.

## Firebase Crashlytics integration

`com.google.firebase.crashlytics` + `com.google.firebase.app`.

Initialize in boot scene before any other system:

```csharp
await FirebaseApp.CheckAndFixDependenciesAsync();
Crashlytics.IsCrashlyticsCollectionEnabled = true;
```

```csharp
using UnityEngine.Diagnostics; // for Utils.ForceCrash + ForcedCrashCategory

Crashlytics.SetCustomKey("level", currentLevel);     // dashboard column
Crashlytics.SetUserId(playerGUID);                   // anonymous, NOT PII
Crashlytics.Log("entered shop");                     // last 64KB ships with crash
Crashlytics.LogException(new Exception("Test"));     // non-fatal
Utils.ForceCrash(ForcedCrashCategory.FatalError);    // verification only
```

## Sentry integration

Install the Sentry Unity SDK from Sentry's UPM package / current docs (for example the `getsentry/unity` package URL), not a Unity-registry `com.unity.sentry` package. Configure DSN in `Tools > Sentry > Configuration`. Sentry auto-captures `Debug.LogError`, `Debug.LogException`, native crashes — no global handler needed.

```csharp
SentrySdk.CaptureException(ex);
SentrySdk.AddBreadcrumb("clicked Play");
SentrySdk.ConfigureScope(s => s.SetTag("level", "boss"));
SentrySdk.ConfigureScope(s => s.User = new User { Id = playerGUID });
```

Sentry Unity SDK auto-uploads symbols on build via `SentryCli` integration — wire once in `Tools > Sentry`.

## IL2CPP symbol upload

IL2CPP compiles C# → C++ → native binary. Crash stacks come back as raw `libil2cpp.so` offsets. Symbolication requires uploading symbol files for every shipped build.

- **Android** — enable `Create symbols.zip = Public` in Build Settings. Unity emits `symbols.zip` next to AAB/APK with per-architecture `libil2cpp.sym` + `line-mappings.json`. Keep ProGuard / R8 `mapping.txt` for Java side. Upload via `firebase crashlytics:symbols:upload` or `sentry-cli debug-files upload`.
- **iOS** — Xcode emits `dSYM` per build. Bitcode-era `BCSymbolMap` deprecated by Apple in Xcode 14; modern builds skip. Upload via Firebase's Crashlytics run script in Xcode build phase, or `sentry-cli upload-dsym`.

Without successful symbol upload, every report shows `libil2cpp.so + 0x12345abc` — useless.

Automate in CI: post-build hook → run upload CLI → fail build on upload failure. See `unity-build`.

## Native vs managed crashes

- **Managed exceptions** — C# `throw`, `NullReferenceException`. Caught by Unity, shipped as non-fatal by default. Promote to fatal if uncaught at MonoBehaviour boundary.
- **Native crashes** — segfaults, NDK, plugin crashes. Caught by service's native handler. Symbolication via upload step.
- **ANR** — Android "Application Not Responding", main thread blocked >5s. Crashlytics tracks separately. Causes: sync IO on main thread, deadlocks, infinite loops. iOS has no equivalent system signal — use a watchdog timer for parity. See `unity-profiling`.
- **OOM kill** — system kills app for memory pressure with no callback. Crashlytics infers from session-end patterns.

## Custom keys, breadcrumbs, user IDs

- **Custom keys** — scene name, level, build flavor, A/B variant, last-purchased SKU. Indexed dashboard columns. Stay under 64 unique keys per app.
- **Breadcrumbs** — meaningful events ("Loaded scene Forest", "Player died", "IAP succeeded"). Last N events ship with each crash. Buffer 64KB; oldest truncated first.
- **User ID** — anonymous GUID linked to auth. Lets you pull "all crashes for user X" for support. Never PII.

## Non-fatal exceptions

```csharp
try { riskyThing(); }
catch (Exception e) { Crashlytics.LogException(e); }
```

Global handler so nothing slips through:

```csharp
Application.logMessageReceived += (msg, stack, type) => {
    if (type == LogType.Exception)
        Crashlytics.LogException(new Exception(msg + "\n" + stack));
};
```

Sentry's Unity SDK installs an equivalent automatically.

## ANR detection

Crashlytics' ANR module + Android system tracing covers Android once you ship the SDK. iOS has no system signal — heartbeat coroutine on main thread + watchdog on background thread that flags any gap > threshold (3-5s), then `LogException` a synthetic stall record.

## Common patterns

- Boot scene initializes Crashlytics/Sentry **first**.
- Wrap every third-party SDK init (IAP, ads, attribution, social) in try/catch + `LogException`. A flaky vendor SDK shouldn't crash your app.
- Set custom key on every scene transition.
- Set user ID after auth succeeds — see `unity-auth-account-linking`.
- CI: build → upload symbols → smoke tests → upload artifact. Fail build if symbol upload fails.

## Release-only crash runbook

Most common new-team failure: "works in Editor, crashes on device only in Release." Editor uses Mono with no managed stripping; release Android/iOS uses IL2CPP with `Managed Stripping Level = High` by default. Most release-only crashes are stripping casualties.

1. **Reproduce on a release build, not Editor.**
2. **First check: managed stripping.** Set `Player Settings > Other Settings > Managed Stripping Level = Low`. Rebuild. If crash disappears = stripping issue — add `link.xml` for stripped types rather than shipping Low. See `unity-build`.
3. **Common stripping victims** — `JsonUtility` on private fields without `[SerializeField]`, Newtonsoft.Json on dynamic types, reflection-based DI, Odin Inspector serialization, AssemblyDefinition reflection lookups.
4. **adb logcat (Android)** — `adb logcat -s Unity:* AndroidRuntime:E DEBUG:E`. Filter by bundle: `adb logcat --pid=$(adb shell pidof com.studio.game)`.
5. **iOS Console / Xcode device logs** — Xcode → Window → Devices and Simulators → device → View Device Logs. dSYM symbolication via Xcode Organizer.
6. **Crashlytics / Sentry** — confirm symbols uploaded (`unity-build` post-build hooks). If stack shows `libil2cpp.so + 0xABCD` without method names, symbol upload failed.
7. **Cross-platform divergence** — `#if UNITY_EDITOR` blocks touching Editor-only APIs in runtime = silent no-op in Editor, NullRef in build. Search for `using UnityEditor;` in runtime asmdefs (`unity-asmdef`).
8. **Memory pressure** — Android low-RAM may OOM-kill silently. Profile peak memory via Memory Profiler (`unity-profiling`).
9. **Permission missing** — `INTERNET` for `UnityWebRequest`; absent in custom `AndroidManifest.xml` = exception. Restore default or check `Player Settings > Android > Internet Access`.
10. **Last resort** — Development Build with Script Debugging, attach managed debugger.

## Gotchas

- Forgetting `Create symbols.zip` in Android Build Settings = no Android symbolication. Check before every release.
- `dSYM` stripped from Xcode archive in some Release configs; preserve via Archive scheme settings.
- Bitcode (deprecated Xcode 14) used to require `BCSymbolMap`; modern builds skip — don't waste time.
- Crashlytics under-reports the **first few crashes after release** — reports flush on next launch.
- Editor crashes never reach Crashlytics — must be a real device build.
- GDPR: crash collection without consent is a problem in EU. Wire `Crashlytics.IsCrashlyticsCollectionEnabled = false` (or Sentry equivalent) into consent UI. See `unity-consent-att-gdpr`.
- >64 unique custom keys per app may be silently truncated.
- Breadcrumbs over 64KB truncated from oldest first.
- `LogException` with non-Exception args silently drops in some SDK versions — always pass `Exception`.
- IL2CPP symbol files are large (50-200 MB per platform). Build artifact server, do not commit.

## Verification

- Force a crash on real device via hidden test menu (`Crashlytics.LogException(new Exception("Forced"))` or `Utils.ForceCrash`). Appears in dashboard within ~5 minutes.
- Open report — stack shows method names, not raw `libil2cpp.so` offsets. If not, symbol upload failed.
- Custom keys appear as filter dropdowns.
- User ID matches auth's player GUID.
- Breadcrumbs visible in crash detail.
- Crash-free users metric updates day-over-day after a real release.

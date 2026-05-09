---
name: unity-crash-reporting
description: Use when wiring crash and non-fatal exception reporting into a shipped Unity game — Firebase Crashlytics, Sentry, Sentry Unity, Bugsnag, Backtrace, Unity Cloud Diagnostics, dSYM, libil2cpp.sym, line-mappings.json, NDK symbols, ProGuard mapping, R8 mapping, Symbols.zip, BCSymbolMap, native crash, managed crash, exception logging, LogException, Application.logMessageReceived, Debug.LogException, non-fatal exception, breadcrumb, custom keys, user identifier, crash-free users, ANR, application not responding, OOM, out of memory, IL2CPP symbol upload. Unity 6 / 2023.2 LTS / URP-only / new Input System only. NOT for analytics events (use unity-analytics-events), NOT for performance profiling (use unity-profiling).
---

## When to use

Any time the game is being prepared for store submission, soft launch, or post-launch operations and there is no crash pipeline yet — or there is one but symbols are not uploading. Read `unity-best-practices` first. Cross-link `unity-build` for post-build symbol upload hooks, `unity-analytics-events` for the parallel custom-keys pattern, `unity-auth-account-linking` for the user-ID source, `unity-consent-att-gdpr` for opt-out wiring, and `unity-profiling` for the ANR root-cause hunt.

## Why post-launch is blind without this

Without a crash service your only signal that something is broken is bad reviews, support tickets, and refund requests — and by the time those arrive the user is already gone. With one wired up you get crash-free-users %, top crashes ranked by frequency, full symbolicated stacks, device/OS/locale distribution, and the breadcrumb trail leading into the crash. Day-one essential, not a polish item.

## Pick a service

- **Firebase Crashlytics** — free, Google-owned, deep Android integration, Firebase Console UI. Default pick for Android-first F2P.
- **Sentry (Sentry Unity SDK)** — paid, free tier of 5k events/month, best Unity integration of the bunch (auto-captures `Debug.LogError`, `LogException`, native crashes), pairs crashes with perf monitoring + custom errors. Default for studios already on Sentry.
- **Backtrace** — paid, console / mid-core focus, strongest minidump support for native crashes.
- **Unity Cloud Diagnostics** — legacy, replaced by Unity Cloud Build offerings. Not recommended for new work.

## Firebase Crashlytics integration

Install via Package Manager: `com.google.firebase.crashlytics` plus `com.google.firebase.app` (Firebase Unity SDK).

Initialize in your boot scene before any other system:

```csharp
await FirebaseApp.CheckAndFixDependenciesAsync();
Crashlytics.IsCrashlyticsCollectionEnabled = true;
```

Common API:

```csharp
using UnityEngine.Diagnostics; // for Utils.ForceCrash + ForcedCrashCategory

Crashlytics.SetCustomKey("level", currentLevel);     // dashboard column
Crashlytics.SetUserId(playerGUID);                   // anonymous, NOT PII
Crashlytics.Log("entered shop");                     // last 64KB ships with crash
Crashlytics.LogException(new Exception("Test"));     // non-fatal
Utils.ForceCrash(ForcedCrashCategory.FatalError);    // verification only
```

## Sentry integration

Install `com.unity.sentry` (Sentry Unity SDK) via Package Manager. Configure DSN in `Tools > Sentry > Configuration`. Sentry auto-captures `Debug.LogError`, `Debug.LogException`, and native crashes once enabled — no global handler needed.

```csharp
SentrySdk.CaptureException(ex);
SentrySdk.AddBreadcrumb("clicked Play");
SentrySdk.ConfigureScope(s => s.SetTag("level", "boss"));
SentrySdk.ConfigureScope(s => s.User = new User { Id = playerGUID });
```

Sentry Unity SDK auto-uploads symbols on build via the `SentryCli` integration — wire it once in `Tools > Sentry` and it survives across builds.

## IL2CPP symbol upload (the hard part)

IL2CPP compiles C# → C++ → native binary. Crash stacks come back as raw `libil2cpp.so` offsets, not method names. To symbolicate you have to upload the symbol files for every shipped build.

- **Android** — enable `Create symbols.zip = Public` in Build Settings. Unity emits `symbols.zip` next to the AAB/APK containing per-architecture `libil2cpp.sym` plus `line-mappings.json`. Also keep the ProGuard / R8 `mapping.txt` for the Java side. Upload to Crashlytics via `firebase crashlytics:symbols:upload`, or to Sentry via `sentry-cli debug-files upload`.
- **iOS** — Xcode emits a `dSYM` bundle per build. Bitcode-era builds also produced `BCSymbolMap` files (deprecated by Apple in Xcode 14, modern builds skip). Upload via Firebase's Crashlytics run script in the Xcode build phase, or to Sentry via `sentry-cli upload-dsym`.

Without a successful symbol upload, every report shows `libil2cpp.so + 0x12345abc` — useless.

Automate this in CI: post-build hook → run upload CLI → fail the build on upload failure. See `unity-build` for the post-build hook pattern.

## Native vs managed crashes

- **Managed exceptions** — C# `throw`, `NullReferenceException`, etc. Caught by Unity, shipped to Crashlytics/Sentry as non-fatal by default. Promote to fatal if uncaught at the MonoBehaviour boundary.
- **Native crashes** — segfaults, NDK crashes, plugin crashes. Caught by the service's native handler. Symbolication requires the upload step above.
- **ANR** — Android "Application Not Responding", main thread blocked >5s. Crashlytics tracks separately. Causes: synchronous IO on main thread, deadlocks, infinite loops. iOS has no equivalent system signal — use a watchdog timer pattern if you need parity. Cross-link `unity-profiling`.
- **OOM kill** — system kills app for memory pressure with no callback. Crashlytics infers from session-end patterns; treat suspicious session ends as suspected OOM.

## Custom keys, breadcrumbs, user IDs

- **Custom keys** — scene name, level, build flavor, A/B variant, last-purchased SKU. Indexed columns in the dashboard; powerful filters. Stay under 64 unique keys per app or older entries get dropped.
- **Breadcrumbs** — meaningful events ("Loaded scene Forest", "Player died", "IAP succeeded"). The last N events ship with each crash and are usually the difference between "can repro" and "shrug". Buffer is 64KB; oldest truncated first.
- **User ID** — anonymous GUID linked to your auth system. Lets you pull "all crashes for user X" when handling a support ticket. Never put PII (email, name, IP) in this field.

## Non-fatal exceptions

Wrap risky paths instead of swallowing exceptions:

```csharp
try { riskyThing(); }
catch (Exception e) { Crashlytics.LogException(e); }
```

Set up a global handler so nothing slips through:

```csharp
Application.logMessageReceived += (msg, stack, type) => {
    if (type == LogType.Exception)
        Crashlytics.LogException(new Exception(msg + "\n" + stack));
};
```

Sentry's Unity SDK installs an equivalent handler automatically.

## ANR detection

Crashlytics' ANR module plus Android system tracing covers Android out of the box once you ship the SDK. iOS has no equivalent system signal — if you need it, run a heartbeat coroutine on the main thread and a watchdog on a background thread that flags any gap longer than your threshold (3-5s), then `LogException` a synthetic stall record.

## Common patterns

- Boot scene initializes Crashlytics/Sentry **first**, before any other system. Catches bugs in your own initialization code.
- Wrap every third-party SDK init (IAP, ads, attribution, social) in try/catch + `LogException`. A flaky vendor SDK should never crash your app.
- Set a custom key on every scene transition.
- Set the user ID after auth succeeds — see `unity-auth-account-linking`.
- CI pipeline order: build → upload symbols → run smoke tests → upload artifact. Fail the build if symbol upload fails.

## Release-only crash runbook

The most common new-team failure mode: "it works in the Editor, crashes on device only in Release." Editor uses Mono with no managed stripping; release Android/iOS uses IL2CPP with `Managed Stripping Level = High` by default. Most release-only crashes are stripping casualties.

Decision tree:

1. **Reproduce on a release build, not the Editor.** Editor uses Mono, no stripping; release on Android/iOS uses IL2CPP plus High stripping by default.
2. **First check: managed stripping.** Set `Player Settings > Other Settings > Managed Stripping Level = Low`. Rebuild. If the crash disappears it's a stripping issue — add a `link.xml` for the stripped types rather than shipping Low. Cross-link `unity-build`.
3. **Common stripping victims** — `JsonUtility` on private fields without `[SerializeField]`, Newtonsoft.Json on dynamic types, reflection-based DI, Odin Inspector serialization, AssemblyDefinition reflection lookups.
4. **adb logcat (Android)** — `adb logcat -s Unity:* AndroidRuntime:E DEBUG:E` shows native crashes plus Unity logs. Filter to your bundle ID with `adb logcat --pid=$(adb shell pidof com.studio.game)`.
5. **iOS Console / Xcode device logs** — connect device, open Xcode → Window → Devices and Simulators → select device → View Device Logs. Filter by app name. dSYM symbolication via Xcode Organizer.
6. **Crashlytics / Sentry** — confirm symbols uploaded (cross-link `unity-build` post-build hooks). Reproduce; the symbolicated stack should reveal the failing method. If the stack shows `libil2cpp.so + 0xABCD` without method names, your symbol upload failed.
7. **Cross-platform divergence** — `#if UNITY_EDITOR` blocks that touch Editor-only APIs in runtime code = silent no-op in editor, NullRef in build. Search for `using UnityEditor;` in runtime asmdefs (cross-link `unity-asmdef`).
8. **Memory pressure** — Android low-RAM devices may OOM-kill the app silently. Profile peak memory via Memory Profiler (cross-link `unity-profiling`).
9. **Permission missing** — e.g. `INTERNET` permission needed for `UnityWebRequest`; absent in some custom `AndroidManifest.xml` = exception. Restore the default manifest or check `Player Settings > Android > Internet Access`.
10. **Last resort** — Development Build with Script Debugging enabled, attach managed debugger (cross-link `unity-build`). Slowest but catches what stripping-Low doesn't reveal.

Cross-link `unity-build` (managed stripping + link.xml), `unity-asmdef` (`using UnityEditor;` in runtime code), `unity-profiling` (Memory Profiler), `unity-tests` (PlayMode test on a device farm).

## Gotchas

- Forgetting `Create symbols.zip` in Android Build Settings = no Android symbolication, ever. Check this before every release.
- `dSYM` gets stripped from the Xcode archive in some Release configurations; preserve it via the Archive scheme settings.
- Bitcode (deprecated by Apple in Xcode 14) used to require `BCSymbolMap` upload; modern builds skip this — don't waste time on it for new projects.
- Crashlytics under-reports the **first few crashes after a release** because users haven't relaunched yet (reports flush on next launch). Don't panic on day-zero numbers.
- Editor crashes never reach Crashlytics — must be a real device build to verify.
- GDPR: crash collection without consent is a problem in the EU. Wire `Crashlytics.IsCrashlyticsCollectionEnabled = false` (or Sentry's equivalent) into your consent UI. See `unity-consent-att-gdpr`.
- Custom keys are indexed; >64 unique keys per app may be silently truncated.
- Breadcrumbs over 64KB are truncated from oldest first; don't use them as a log firehose.
- `LogException` with non-Exception args silently drops in some SDK versions — always pass an `Exception`.
- IL2CPP symbol files are large (50-200 MB per platform). Store them on a build artifact server, do not commit to git, pull at upload time.

## Verification

- Force a crash on a real device via a hidden test menu (`Crashlytics.LogException(new Exception("Forced"))` or `Utils.ForceCrash`). Confirm it appears in the dashboard within ~5 minutes.
- Open the report — stack trace shows method names, not raw `libil2cpp.so` offsets. If it doesn't, your symbol upload failed.
- Custom keys appear as filter dropdowns in the dashboard.
- The user ID on the report matches your auth system's player GUID.
- Breadcrumbs are visible in the crash detail view.
- Crash-free users metric updates day-over-day after a real release.

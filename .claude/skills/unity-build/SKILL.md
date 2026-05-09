---
name: unity-build
description: 'Use for Unity builds and platform targeting: Build Profiles, BuildPipeline.BuildPlayer, PlayerSettings, IL2CPP/Mono, stripping/link.xml, define symbols, BuildReport, post-build hooks, Android/iOS/WebGL/desktop signing and lifecycle. Unity 6+ / URP / new Input System.'
---

## When to use

Use for Player binaries, platform switches, PlayerSettings, IL2CPP/Mono, link.xml, scripted/CI builds, BuildReport, and platform gotchas. Cross-links: `unity-scenes`, `unity-persistence`, `unity-audio`, `unity-addressables`, `unity-asmdef`, `unity-ugui`, `unity-input-system`.

## Build pipeline overview

Unity 6 **Build Profiles** bundle platform, scenes, backend, defines, and overrides. GUI builds still funnel through `BuildPipeline.BuildPlayer`, so every build should be scriptable.

Use `File > Build Profiles` for manual switching. In CI, set `PlayerSettings`, `BuildSettings`, and `EditorBuildSettings.scenes` through editor APIs before `BuildPlayer`.

## PlayerSettings essentials

`Edit > Project Settings > Player`:

- **Identification** — Company Name, Product Name, Version (semver, user-visible), Bundle Identifier (`com.studio.game`), Build Number (Android `bundleVersionCode`, iOS `CFBundleVersion`).
- **Resolution and Presentation** — orientation (mobile), default resolution and Fullscreen Mode (desktop), splash screen.
- **Splash Image** — Show Unity Logo. Pro can disable; Personal cannot.
- **Other Settings** — Scripting Backend, API Compatibility (`.NET Standard 2.1`), Active Input Handling (`New` final; `Both` migration-only), architectures (Android/iOS ARM64).
- **Publishing Settings** (Android) — Keystore path, key alias, signing config, AAB vs APK toggle.
- **Capabilities** (iOS) — Push, IAP, Sign in with Apple, Game Center; each maps to an Xcode entitlement.
- **Icon** — per-platform icon sets; Android adaptive icons need foreground/background mipmap layers.

Prefer Project Settings APIs; hand-editing serialized settings is brittle.

## Build profiles (Unity 6)

`File > Build Profiles`. Create one profile per `(platform × stage)`:

- `Android-Dev`, `Android-Release`
- `iOS-Dev`, `iOS-Release`
- `WebGL-Staging`, `WebGL-Production`
- `Standalone-Win-Demo`, `Standalone-Win-Release`

Each profile owns scenes, defines, IL2CPP optimization, and overrides. Profile assets live under `Assets/Settings/Build Profiles/`; commit them.

## Scripting backend (IL2CPP vs Mono)

- **Mono** — JIT, fast iteration, useful for desktop/Android dev; not supported on iOS/modern consoles.
- **IL2CPP** — AOT C# -> C++ -> native. Required for iOS, Android Play Store AAB, consoles. Slower builds; no `Reflection.Emit`.

Default: IL2CPP for any shipping platform; Mono only for Editor and quick dev builds.

**Code Optimization**: `Debug` for iteration, `Release` for normal store builds, `Master` for final size/speed when harder symbolication is acceptable. This does not strip logs; use stripping settings and `[Conditional]` guards.

## Code stripping and link.xml

Managed Stripping Level (`Disabled`/`Low`/`Medium`/`High`) removes code not statically referenced. High commonly breaks reflection, Newtonsoft dynamic types, and private fields without `[SerializeField]`.

A `link.xml` in `Assets/` tells the linker not to strip listed types/assemblies:

```xml
<linker>
  <assembly fullname="MyAssembly">
    <type fullname="MyApp.Models.PlayerData" preserve="all"/>
  </assembly>
  <assembly fullname="Newtonsoft.Json" preserve="all"/>
</linker>
```

Device-only AOT / `MissingMethodException` usually means missing `link.xml`. Keep library snippets with the package install.

## Scripting Define Symbols

Set define symbols in Player Settings or Build Profile. Unity defines include `DEVELOPMENT_BUILD`, `UNITY_EDITOR`, `UNITY_IOS`, `UNITY_ANDROID`, `UNITY_WEBGL`, `UNITY_STANDALONE*`. Add project flags like `STEAM_BUILD`, `MOBILE_FREE`, `BETA_BRANCH`.

```csharp
#if UNITY_EDITOR || DEVELOPMENT_BUILD
    debugHud.SetActive(true);
#endif
```

## Development Build flags

Flags: `Development Build`, `Script Debugging`, `Wait For Managed Debugger`, `Deep Profiling`, `Autoconnect Profiler`. They slow runtime and enlarge binaries; never ship them.

## Scripted builds (BuildPipeline.BuildPlayer)

```csharp
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

public static class Builders
{
    [MenuItem("Build/Android Release")]
    public static void BuildAndroidRelease()
    {
        var opts = new BuildPlayerOptions
        {
            scenes = EditorBuildSettings.scenes
                .Where(s => s.enabled).Select(s => s.path).ToArray(),
            locationPathName = "Builds/Android/game.aab",
            target = BuildTarget.Android,
            options = BuildOptions.None,
        };

        var report = BuildPipeline.BuildPlayer(opts);
        if (report.summary.result != BuildResult.Succeeded)
        {
            Debug.LogError($"Build failed: {report.summary.totalErrors} errors");
            EditorApplication.Exit(1);
        }
    }
}
```

CI: `unity -batchmode -nographics -executeMethod Builders.BuildAndroidRelease -quit -logFile build.log`.

## Post-build callbacks

```csharp
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.Callbacks;

public class BuildHooks : IPreprocessBuildWithReport, IPostprocessBuildWithReport
{
    public int callbackOrder => 0;

    public void OnPreprocessBuild(BuildReport report)
    {
        // bump version from git tag, validate signing, etc.
    }

    public void OnPostprocessBuild(BuildReport report)
    {
        // upload symbols, archive BuildReport JSON, etc.
    }

    [PostProcessBuild(callbackOrder: 0)]
    public static void OnPostprocessBuildLegacy(BuildTarget target, string path)
    {
        // legacy hook — modify Info.plist, Xcode project, etc.
    }
}
```

Prefer `IPreprocessBuildWithReport` / `IPostprocessBuildWithReport` when you need `BuildReport`. Common hooks: store upload (`unity-store-shipping-pipeline`), symbol upload (`unity-crash-reporting`), privacy manifest generation (`unity-privacy-manifests`).

## BuildReport parsing

`BuildReport` gives result, size, errors/warnings, duration, per-step timing, and packed asset sizes. Use `summary.totalSize` + sorted `packedAssets[]` for size budgets and CI regressions (`unity-ci`).

For CI JSON, use a `[Serializable]` POCO; anonymous types serialize as `{}` in `JsonUtility`:

```csharp
[Serializable]
class BuildSummary {
    public string result;
    public long sizeBytes;
    public float durationSec;
}

var summary = new BuildSummary {
    result = report.summary.result.ToString(),
    sizeBytes = (long)report.summary.totalSize,
    durationSec = (float)(report.summary.buildEndedAt - report.summary.buildStartedAt).TotalSeconds
};
File.WriteAllText("Builds/last-report.json", JsonUtility.ToJson(summary, prettyPrint: true));
```

Need dictionaries/anonymous types? Use Newtonsoft with matching `link.xml`.

## Mobile platform gotchas

Full list: `references/mobile.md`. Essentials:

- **Frame rate** — mobile defaults to 30 fps. Set `Application.targetFrameRate = 60` (or `30`) at boot AND `QualitySettings.vSyncCount = 0` so target actually applies. 60 fps roughly doubles thermal load; most F2P titles target 30 with adaptive 60 on flagship devices.
- **App size budgets** — Google Play app bundles use compressed download-size limits: 200 MB base module, 200 MB per feature module, 1.5 GB per asset pack, 4 GB for install-time modules + asset packs. Legacy APK publishing capped at 100 MB. Apple App Store IPA cap is 4 GB binary, but smaller cellular downloads convert better. See `unity-addressables`.

Reference covers: render scale, thermal, texture/RAM tiers, audio voices, shader warmup, `OnApplicationPause`, `Screen.safeArea`, touch, orientation, particle ceilings, shadows.

## WebGL platform gotchas

`references/webgl.md`: no threads, IndexedDB + `FS.syncfs`, audio unlock, build size, memory cap, browser quirks, API blocklist.

Unity 6 also has a preview **Web** target. For production browser builds, ship WebGL2; WebGPU/URP remains experimental.

## Desktop gotchas

- **Code signing** — macOS notarization outside Mac App Store; Windows EV cert avoids SmartScreen warnings.
- **DPI scaling** — high-DPI displays render UI tiny if not opted in. Set `PlayerSettings.macRetinaSupport = true` for macOS; on Windows make sure the DPI-aware manifest is set (Player Settings → Resolution and Presentation).
- **Steam** — Steamworks.NET or Facepunch; call `SteamAPI.Init()` at boot.
- **Full-screen window** — `Screen.fullScreenMode = FullScreenMode.FullScreenWindow` (borderless) gives fewer alt-tab artifacts than `ExclusiveFullScreen`.
- **Apple Silicon** — build `Universal` (Intel64 + ARM64).

## App lifecycle

- `OnApplicationPause(bool)` — mobile background/foreground; save here.
- `OnApplicationFocus(bool)` — desktop alt-tab and mobile resume. Pause music, throttle update rate.
- `OnApplicationQuit()` — desktop close; unreliable for mobile saves.
- `Application.quitting` event — last chance before quit on platforms that fire it.
- `Application.runInBackground = true` — keep updating when window loses focus (desktop multiplayer, headless servers).

Pair with `unity-persistence` for save/flush implementation.

## Common patterns

- CI build: `unity -batchmode -nographics -executeMethod Builders.BuildAndroidRelease -quit -logFile build.log`.
- One build profile per `(platform × stage)`: `Android-Dev`, `Android-Release`, `iOS-Dev`, `iOS-Release`, `WebGL-Staging`, `WebGL-Production`.
- Pre-build: bump version from git tag (`git describe --tags`); post-build: upload symbols to crash service, archive `BuildReport` JSON, attach to release artifact.
- `link.xml` lives at `Assets/link.xml`, version-controlled, with a stanza per third-party reflective library.
- `DEVELOPMENT_BUILD` define guards an on-screen debug HUD and verbose logging.
- A `BootScene` minimal scene drives platform setup (`Application.targetFrameRate`, `Screen.orientation`, `Application.runInBackground`) before loading the first gameplay scene — see `unity-scenes`.

## Gotchas

- Forgetting to add a scene to the build list (or to active build profile) → `SceneManager.LoadScene` silently fails or loads wrong index. See `unity-scenes`.
- `High` stripping breaks `JsonUtility` on private fields → use `[SerializeField]` or add a `link.xml` entry.
- IL2CPP compile time is 5–15 min for non-trivial projects; cache the local IL2CPP toolchain (`%LOCALAPPDATA%/Unity/cache/il2cpp`) on CI runners.
- Android keystore lost = cannot update the Play Store listing. Back up keystore + password to multiple secure locations.
- iOS provisioning profile expires yearly; renew before submission or upload fails.
- Android Play builds above the base-module budget need Play Asset Delivery, feature modules, or Addressables remote groups. See `unity-addressables`.
- WebGL does not support `System.Diagnostics.Process`, `System.Net.Sockets` (use `UnityWebRequest`), or `BinaryFormatter`.
- Auto-reference assemblies in asmdef can balloon build time; prune unused references. See `unity-asmdef`.
- Active Input Handling left at `Input Manager (Old)` after installing the Input System package → new-Input-System code compiles but reads no devices at runtime. See `unity-input-system`.
- `Application.persistentDataPath` is platform-specific; never hardcode a path. See `unity-persistence`.

## Verification

1. Build first. Confirm `BuildReport.summary.result == BuildResult.Succeeded` and `summary.totalErrors == 0`.
2. Inspect `summary.totalSize` and `report.packedAssets` (sort descending) to spot bloat.
3. Test the actual artifact (`.exe`/`.app`/`.apk`/`.aab`/`.ipa`/`index.html`) on target hardware — Editor build is NOT the same.
4. Editor console clean of compile warnings and stripping notices during the build.
5. Test app lifecycle: alt-tab on desktop, home-button on mobile, browser tab switch on WebGL — verify save-on-pause works.
6. Mobile: run on the lowest-supported device. WebGL: test in Chrome + Safari + Firefox (Safari has the most divergent quirks).
7. After IL2CPP shipping builds, scan device logs for `MissingMethodException`/AOT errors → add to `link.xml` and rebuild.

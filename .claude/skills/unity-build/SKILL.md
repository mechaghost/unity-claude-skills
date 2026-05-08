---
name: unity-build
description: Use when shipping or platform-targeting a Unity project through Unity MCP — BuildPipeline.BuildPlayer, build profile, build settings, PlayerSettings, IL2CPP, Mono backend, code stripping, managed stripping, link.xml, scripting backend, target platform, target architecture, ARM64, Universal, switch platform, Android build, iOS build, WebGL build, mobile build, desktop build, BuildReport, post-build, OnPostprocessBuild, PostProcessBuildAttribute, build symbol, define symbol, scripting define, Development Build, Script Debugging, deep profiling, build size, app icon, splash screen, bundle ID, application identifier, version, build number, app version, signing, Android keystore, iOS provisioning, IPA, APK, AAB, app bundle, target frame rate, safe area, OnApplicationPause, OnApplicationFocus, app lifecycle, runInBackground, audio context unlock, IndexedDB, FS.syncfs.
---

## When to use

Any build or shipping task: producing a Player binary, switching platforms, configuring PlayerSettings, choosing IL2CPP vs Mono, writing link.xml, scripted/CI builds, post-build hooks, parsing BuildReport, or chasing platform-specific runtime gotchas (mobile lifecycle, WebGL audio unlock, desktop signing). Read `unity-best-practices` first for the project paradigm primer. Cross-link `unity-scenes` for the build scene list, `unity-persistence` for save-on-pause, `unity-audio` for audio unlock, `unity-addressables` for content delivery, `unity-asmdef` for build-time hygiene, `unity-ugui` for safe-area UI, and `unity-input-system` for touch-vs-mouse parity.

## Build pipeline overview

Unity 6 introduced **Build Profiles** (`File > Build Profiles`) which replace the older Build Settings dialog. A profile bundles `(platform, scenes, scripting backend, defines, settings overrides)` so you can switch between `Android-Release` and `WebGL-Staging` without re-importing assets every time. Profiles still funnel through `BuildPipeline.BuildPlayer` under the hood — anything you do in the GUI is reproducible in code.

Pick profiles via Unity MCP: `execute_menu_item` → `File/Build Profiles`, then `manage_build` to switch active profile and trigger the build. Use `manage_editor` to mutate `PlayerSettings`, `BuildSettings`, and `EditorBuildSettings.scenes` between profiles when CI must override values.

## PlayerSettings essentials

Under `Edit > Project Settings > Player`. Per-platform tabs:

- **Identification** — Company Name, Product Name, Version (semver, user-visible), Bundle Identifier (e.g. `com.studio.game`), Build Number (Android `bundleVersionCode`, iOS `CFBundleVersion`).
- **Resolution and Presentation** — orientation (mobile), default resolution and Fullscreen Mode (desktop), splash screen.
- **Splash Image** — Show Unity Logo. Pro can disable; Personal cannot.
- **Other Settings** — Scripting Backend (IL2CPP/Mono), Api Compatibility Level (`.NET Standard 2.1` is the default and what asmdef-driven projects expect), Active Input Handling (must be `Input System Package` or `Both` — see `unity-input-system`), Target Architectures (Android: ARM64 required for Play Store; iOS: ARM64).
- **Publishing Settings** (Android) — Keystore path, key alias, signing config, AAB vs APK toggle.
- **Capabilities** (iOS) — Push Notifications, In-App Purchase, Game Center, etc.
- **Icon** — per-platform icon sets; Android adaptive icons need foreground/background mipmap layers.

Mutate via `manage_editor` rather than hand-editing `ProjectSettings/ProjectSettings.asset` — the editor normalizes values and re-serializes meta.

## Build profiles (Unity 6)

`File > Build Profiles` opens the new editor. Create one profile per `(platform × stage)`:

- `Android-Dev`, `Android-Release`
- `iOS-Dev`, `iOS-Release`
- `WebGL-Staging`, `WebGL-Production`
- `Standalone-Win-Demo`, `Standalone-Win-Release`

Each profile holds its own scene list, scripting defines, IL2CPP optimization level, and asset import overrides. Activate via "Switch Profile" (assets re-import only when the platform actually changes). The profile asset is serialized under `Assets/Settings/Build Profiles/` so it commits to git.

## Scripting backend (IL2CPP vs Mono)

- **Mono** — JIT-compiled, fast Editor iteration, larger runtime, NOT supported on iOS or modern consoles. Useful for desktop / Android dev builds where iteration speed matters.
- **IL2CPP** — AOT compiles C# → C++ → native. Required for iOS, Android Play Store (AAB), and consoles. Slower builds, smaller runtime, harder to debug, **no `Reflection.Emit`** (impacts Json.NET dynamic, some IoC libs, Linq Expression compilation).

Default: IL2CPP for any shipping platform; Mono only for the Editor and quick dev builds.

**Code Optimization** (Unity 6): `Debug` / `Release` / `Master`.

- **Debug** — unoptimized, debugger-attachable, fastest iteration. Default for development.
- **Release** — IL2CPP optimized for runtime speed; the new shipping default. Preserves enough metadata to symbolicate crashes — pick this for store builds you intend to patch post-launch.
- **Master** — Release + LTO + dead-code elimination. Smallest binary, slowest build, hardest to symbolicate. Reserve for final store builds when post-launch patching is not on the table.

Code Optimization mode does NOT govern log stripping — that is controlled by managed-stripping settings (Player Settings > Other > Managed Stripping Level) and `[Conditional]` define guards in code. Picking Master alone will not strip `Debug.Log` calls.

## Code stripping and link.xml

`Player Settings > Other > Managed Stripping Level` — `Disabled` / `Low` / `Medium` / `High`. `High` strips everything not statically referenced, which breaks reflection, `JsonUtility` on private fields without `[SerializeField]`, Newtonsoft on dynamic types, and AssemblyDefinition reflection lookups.

A `link.xml` file in `Assets/` tells the linker not to strip listed types/assemblies:

```xml
<linker>
  <assembly fullname="MyAssembly">
    <type fullname="MyApp.Models.PlayerData" preserve="all"/>
  </assembly>
  <assembly fullname="Newtonsoft.Json" preserve="all"/>
</linker>
```

When IL2CPP throws AOT or `MissingMethodException` errors on device, the cause is almost always a missing `link.xml` entry. Maintain `link.xml` alongside Newtonsoft / Odin / DOTween installs — copy snippets from each library's docs.

## Scripting Define Symbols

`#if MOBILE_BUILD` etc. Set in Player Settings or per-build profile. Auto-defined: `DEVELOPMENT_BUILD`, `UNITY_EDITOR`, `UNITY_IOS`, `UNITY_ANDROID`, `UNITY_WEBGL`, `UNITY_STANDALONE`, `UNITY_STANDALONE_OSX`, `UNITY_STANDALONE_WIN`. Add custom defines for feature flags (`STEAM_BUILD`, `MOBILE_FREE`, `BETA_BRANCH`).

```csharp
#if UNITY_EDITOR || DEVELOPMENT_BUILD
    debugHud.SetActive(true);
#endif
```

## Development Build flags

In the build profile or `BuildOptions` flags: `Development Build`, `Script Debugging`, `Wait For Managed Debugger`, `Deep Profiling`, `Autoconnect Profiler`. Cost is larger binary plus slower runtime. Ship builds must NEVER carry these.

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

Use for CI: `unity -batchmode -nographics -executeMethod Builders.BuildAndroidRelease -quit -logFile build.log`. Create build scripts via `create_script` and trigger via `manage_build` or `execute_menu_item`.

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

Prefer the `IPreprocessBuildWithReport` / `IPostprocessBuildWithReport` interfaces over the legacy attribute when you need `BuildReport` access.

## BuildReport parsing

`BuildPipeline.BuildPlayer` returns a `BuildReport`. Inspect:

- `report.summary.result` — `Succeeded` / `Failed` / `Cancelled`.
- `report.summary.totalSize`, `totalErrors`, `totalWarnings`, `buildEndedAt - buildStartedAt`.
- `report.steps[]` — per-step duration, useful for finding slow asset imports.
- `report.packedAssets[]` — every shipped asset with its packed size; sort by size to find bloat.

Serialize a slim summary to JSON for CI dashboards:

```csharp
var json = JsonUtility.ToJson(new {
    result = report.summary.result.ToString(),
    sizeBytes = report.summary.totalSize,
    durationSec = (report.summary.buildEndedAt - report.summary.buildStartedAt).TotalSeconds,
});
File.WriteAllText("Builds/last-report.json", json);
```

## Mobile platform gotchas

See `references/mobile.md` for the full list. Two essentials worth surfacing here:

- **Frame rate** — mobile defaults to 30 fps. Set `Application.targetFrameRate = 60` (or `30`) at boot AND `QualitySettings.vSyncCount = 0` so the target actually applies. 60 fps roughly doubles thermal load; most F2P titles target 30 with adaptive 60 on flagship devices.
- **App size budgets** — Google Play base APK install footprint cap is 150 MB (anything larger needs AAB + Play Asset Delivery or Addressables remote groups). AAB total ceiling is 4 GB. Apple App Store IPA cap is 4 GB binary, but the cellular OTA download limit is 200 MB — over that, install conversion craters. Cross-link `unity-addressables`.

`references/mobile.md` covers the rest: `OnDemandRendering`, Adaptive Performance, texture/RAM tiers, audio voice counts, shader warmup, thermal throttling, `OnApplicationPause` save semantics, `Screen.safeArea`, touch input, orientation, particle ceilings, render-scale and shadow budgets.

## WebGL platform gotchas

See `references/webgl.md` for: no-threads constraint, IndexedDB persistence + `FS.syncfs`, audio context unlock, build-size budget, memory cap, browser quirks, and WebGL-specific API blocklist.

**Unity 6 Web vs WebGL** — Unity 6 introduced a separate **Web** build target alongside WebGL. As of Unity 6 LTS, Web is still in preview; **WebGL remains the production-ready target**. Prefer WebGL today; revisit Web when GA support lands. WebGPU support in URP is similarly experimental — ship WebGL2 for production browser builds.

## Desktop gotchas

- **Code signing** — macOS requires notarization for distribution outside the Mac App Store (`xcrun notarytool submit`). Windows builds need an EV cert for SmartScreen reputation; without one, Windows blocks the download with a SmartScreen warning until enough installs accumulate.
- **DPI scaling** — high-DPI displays render UI tiny if not opted in. Set `PlayerSettings.macRetinaSupport = true` for macOS; on Windows make sure the DPI-aware manifest is set (Player Settings → Resolution and Presentation).
- **Steam integration** — Steamworks.NET or Facepunch.Steamworks. Initialize via `SteamAPI.Init()` on boot; if Steam isn't running, prompt and `Application.Quit`.
- **Full-screen window** — `Screen.fullScreenMode = FullScreenMode.FullScreenWindow` (borderless) gives fewer alt-tab artifacts than `ExclusiveFullScreen`.
- **Apple Silicon** — `BuildTarget.StandaloneOSX` with architecture `Universal` (Intel64 + ARM64) for native M1+; Intel-only ships through Rosetta with measurable CPU cost.

## App lifecycle

- `OnApplicationPause(bool)` — fires on mobile background/foreground. Save here on mobile (the system can kill the app without `OnDestroy`).
- `OnApplicationFocus(bool)` — desktop alt-tab and mobile resume. Pause music, throttle update rate.
- `OnApplicationQuit()` — desktop close. Mobile may NOT call this when force-killed; do not rely on it for saving on mobile.
- `Application.quitting` event — last chance before quit on platforms that fire it.
- `Application.runInBackground = true` — keep updating when the window loses focus (desktop multiplayer, headless servers).

Pair with `unity-persistence` for the actual save/flush implementation.

## Common patterns

- CI build invoked via `unity -batchmode -nographics -executeMethod Builders.BuildAndroidRelease -quit -logFile build.log`.
- One build profile per `(platform × stage)`: `Android-Dev`, `Android-Release`, `iOS-Dev`, `iOS-Release`, `WebGL-Staging`, `WebGL-Production`.
- Pre-build: bump version from git tag (`git describe --tags`); post-build: upload symbols to crash service, archive `BuildReport` JSON, attach to release artifact.
- `link.xml` lives at `Assets/link.xml`, version-controlled, with a stanza per third-party reflective library.
- `DEVELOPMENT_BUILD` define guards an on-screen debug HUD and verbose logging.
- A `BootScene` minimal scene drives platform setup (`Application.targetFrameRate`, `Screen.orientation`, `Application.runInBackground`) before loading the first gameplay scene — see `unity-scenes`.

## Gotchas

- Forgetting to add a scene to the build list (or to the active build profile) → `SceneManager.LoadScene` silently fails or loads the wrong index. Cross-link `unity-scenes`.
- `High` stripping breaks `JsonUtility` on private fields → use `[SerializeField]` or add a `link.xml` entry.
- IL2CPP compile time is 5–15 min for non-trivial projects; cache the local IL2CPP toolchain (`%LOCALAPPDATA%/Unity/cache/il2cpp`) on CI runners.
- Android keystore lost = cannot update the Play Store listing. Back up keystore + password to multiple secure locations.
- iOS provisioning profile expires yearly; renew before submission or the upload fails.
- Build size > 150 MB on Android Play Store requires AAB + dynamic delivery or Play Asset Delivery; cross-link `unity-addressables` for runtime content.
- WebGL does not support `System.Diagnostics.Process`, `System.Net.Sockets` (use `UnityWebRequest`), or `BinaryFormatter`.
- Auto-reference assemblies in asmdef can balloon build time; prune unused references — cross-link `unity-asmdef`.
- Active Input Handling left at `Input Manager (Old)` after installing the Input System package → new-Input-System code compiles but reads no devices at runtime. Cross-link `unity-input-system`.
- `Application.persistentDataPath` is platform-specific; never hardcode a path. Cross-link `unity-persistence`.

## Verification

1. Build first. Confirm `BuildReport.summary.result == BuildResult.Succeeded` and `summary.totalErrors == 0`.
2. Inspect `summary.totalSize` and `report.packedAssets` (sort descending) to spot bloat.
3. Test the actual artifact (`.exe`/`.app`/`.apk`/`.aab`/`.ipa`/`index.html`) on target hardware — the Editor build is NOT the same.
4. `read_console` for compile warnings and stripping notices during the build.
5. Test app lifecycle: alt-tab on desktop, home-button on mobile, browser tab switch on WebGL — verify save-on-pause works.
6. Mobile: run on the lowest-supported device. WebGL: test in Chrome + Safari + Firefox (Safari has the most divergent quirks).
7. After IL2CPP shipping builds, scan device logs for `MissingMethodException` / AOT errors → add to `link.xml` and rebuild.

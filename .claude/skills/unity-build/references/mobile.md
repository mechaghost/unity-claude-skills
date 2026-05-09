# Mobile platform reference

Companion to `unity-build` covering Android + iOS runtime gotchas. Unity 6+, URP-only, new Input System only. Cross-link `unity-build/SKILL.md` (build pipeline), `unity-persistence` (save-on-pause), `unity-audio` (interruption), `unity-ugui` (safe-area UI), `unity-input-system` (touch), `unity-urp` (mobile rendering budgets), `unity-shuriken` (particle ceilings).

## Frame rate

Mobile defaults to **30 fps**. Set explicitly at boot:

```csharp
void Awake()
{
    Application.targetFrameRate = 60;   // or 30 on lower tiers
    QualitySettings.vSyncCount = 0;     // required — vSync overrides targetFrameRate
}
```

`vSyncCount > 0` makes the engine ignore `targetFrameRate` and sync to display refresh — set to 0 first. 60 fps on mobile roughly doubles thermal load vs 30; most F2P titles target 30 with adaptive 60 only on flagship devices. Pick a target per device tier and lock to it.

## OnDemandRendering

Render every Nth frame to halve GPU load on low-end devices while keeping UI responsive:

```csharp
using UnityEngine.Rendering;

OnDemandRendering.renderFrameInterval = 2; // render every other frame; UI still polls every frame
```

Pair with new Input System and UGUI — both stay responsive at full Update tick rate even when rendering is throttled.

## Adaptive Performance

Package: `com.unity.adaptiveperformance` (plus per-vendor provider, e.g. Samsung Android Provider). Reads device thermal/power state, exposes events when SoC starts throttling. Wire a quality-tier scaler that lowers render scale, disables bloom, drops shadow distance when `WarningLevel` rises. Fire-and-forget once configured.

## Texture memory budgets

| Tier | RAM | Texture budget | Format | Max size |
| --- | --- | --- | --- | --- |
| Low-end Android | 2 GB | ~200 MB | ASTC 6x6 | 1024 |
| Mid Android | 4 GB | ~400 MB | ASTC 6x6 | 2048 |
| High-end Android / iOS | 6+ GB | ~600-800 MB | ASTC 4x4 | 2048 |

ASTC is modern — supported on iOS (all current devices) and Android (GLES 3.1+/Vulkan, ~98% of market). Keep ETC2 as fallback in the Android override for ancient devices. UI textures: disable mipmaps to save 33% memory; mips matter only for 3D surfaces sampled at varying distance.

## App size budgets

- **Google Play (Android)** — app bundle limits based on compressed download: **200 MB** base module, **200 MB** per feature module, **1.5 GB** per asset pack, **4 GB** total for install-time modules + asset packs. Legacy APK publishing capped at **100 MB**. Apps above **200 MB** show a mobile-data size dialog. Split large content with Play Asset Delivery or Addressables remote groups (`unity-addressables`).
- **Apple App Store (iOS)** — IPA hard ceiling **4 GB** uncompressed. Keep first download small; large downloads hurt conversion. Stream large optional content via Addressables / on-demand resources.
- **Ad-mediation SDK weight** is consistently the largest single contributor to base-binary size after the Unity runtime — AppLovin MAX, IronSource LevelPlay, AdMob each pull 8-20 MB of native code plus per-network adapters. Audit linked SDKs before chasing texture size. See `unity-ads-mediation`.

## Audio voices

Default `Project Settings > Audio > Real Voice Count` is 32. Drop to **16-24 on mobile** — every active voice costs CPU and battery, the cap usually isn't audible. Configure per platform. See `unity-audio`.

## Shader variants and warmup

First-time-rendered shaders compile on the device (Metal on iOS, Vulkan/GLES on Android). First frame needing a previously-unseen variant stalls 100-300 ms — visible as a hitch. Mitigation: ship a `ShaderVariantCollection` and warm during a loading screen.

```csharp
public ShaderVariantCollection variants;

IEnumerator BootWarmup()
{
    yield return null; // let first frame finish
    variants.WarmUp(); // blocking, fine on a loading screen
}
```

Build the collection by checking `Save to asset` in `Project Settings > Graphics > Shader Loading > Track all shaders the player uses` while playing through the game in Editor.

## Battery and thermal throttling

Sustained 60 fps for 5+ minutes triggers iOS/Android thermal throttling — OS silently halves clock speed and 60 fps target starts missing. Strategies in order of cost:

1. Drop to 30 fps after a 60-fps "first-impression" warmup window.
2. Dynamic-resolution scale: lower URP `renderScale` from 1.0 → 0.7 when `Adaptive Performance` reports throttling.
3. Disable bloom / SSAO / heavy post on heat events.
4. Cap simulation: pause AI/particles in offscreen rooms.

`SystemInfo.batteryLevel` and `Application.lowMemory` are signals worth listening to.

## OnApplicationPause

```csharp
void OnApplicationPause(bool paused)
{
    if (paused)
        SaveSystem.FlushImmediate(); // see unity-persistence
}
```

iOS and Android **may kill the app from background without ever calling `OnApplicationQuit`**. `OnApplicationPause(true)` is the only reliable hook to flush state on mobile. See `unity-persistence`.

## Screen.safeArea

iPhone notches, Dynamic Island, Android cutouts, rounded corners eat the corners of the screen. UI must respect `Screen.safeArea`:

```csharp
[ExecuteAlways]
public class SafeAreaFitter : MonoBehaviour
{
    RectTransform _rt;
    Rect _last;

    void OnEnable() { _rt = GetComponent<RectTransform>(); Apply(); }
    void Update() { if (Screen.safeArea != _last) Apply(); }

    void Apply()
    {
        var safe = Screen.safeArea;
        var min = safe.position;
        var max = safe.position + safe.size;
        min.x /= Screen.width;  min.y /= Screen.height;
        max.x /= Screen.width;  max.y /= Screen.height;
        _rt.anchorMin = min;
        _rt.anchorMax = max;
        _last = safe;
    }
}
```

Drop on a HUD root RectTransform. See `unity-ugui` for broader Canvas pattern.

## Touch input

```csharp
using UnityEngine.InputSystem;

void Update()
{
    var touch = Touchscreen.current;
    if (touch == null) return;

    if (touch.primaryTouch.press.wasPressedThisFrame)
    {
        var pos = touch.primaryTouch.position.ReadValue();
        // ...
    }
}
```

Never call legacy `Input.touchCount`/`Input.GetTouch` on a new-Input-System project — silently reads zero. See `unity-input-system`.

## Permissions

Android 6+ and all iOS versions require runtime permission prompts for camera, microphone, location, push notifications, photo library. On Android, use `UnityEngine.Android.Permission.RequestUserPermission` with `PermissionCallbacks` and declare permissions in the Android manifest as needed. On iOS, fill in matching `NS<Permission>UsageDescription` strings in `PlayerSettings > iOS > Other Settings`. Missing iOS usage descriptions are an automatic App Store rejection.

Two permissions need their own dedicated skills because prompt copy, timing, and store-review surface are non-trivial:

- **Push notifications** — Android 13+ requires `POST_NOTIFICATIONS` runtime permission; iOS uses `UNUserNotificationCenter.requestAuthorization`. Both must be requested at the right onboarding moment (not at first launch). See `unity-push-local-notifications`.
- **Tracking (IDFA)** — `NSUserTrackingUsageDescription` plus the ATT prompt; required for any SDK that fingerprints the device for attribution. See `unity-consent-att-gdpr`.

## Orientation

`PlayerSettings > Resolution and Presentation > Default Orientation` for boot orientation. Override at runtime:

```csharp
Screen.orientation = ScreenOrientation.LandscapeLeft;
Screen.autorotateToPortrait = false;
Screen.autorotateToLandscapeLeft = true;
```

## Particle budget

Shuriken on mobile: **≤200 particles/system at peak**, hard-cap simultaneous emitters at **4-6**. Above that, frame-time and overdraw dominate. See `unity-shuriken` for tiered ceilings and `unity-vfx-graph` for GPU alternative.

## Render scale and post

- **Render scale** — 0.7-0.75 typical mobile. Pair with FSR1 or TAAU URP Renderer Feature for upscaled output.
- **Shadow distance** — ≤30 m. **Cascade count** — 1 on low-end, 2 on flagship. See `unity-urp`.
- Disable MSAA, SSAO, motion blur, depth of field on mobile profiles.

## Verification

Profile on the **lowest-supported device**, NOT in Editor — Editor frame times have no relationship to ARM SoC frame times. Use a remote profiler attached to a release-mode IL2CPP build (Development Build is ~30% slower than Release). Frame Debugger and Memory Profiler both work over the remote-profiler connection. See `unity-profiling`.

Once the artifact passes on-device verification, the upload flow (TestFlight, Play Console internal testing, phased rollout, fastlane) is owned by `unity-store-shipping-pipeline`.

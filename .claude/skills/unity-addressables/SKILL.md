---
name: unity-addressables
description: 'Use when working with Unity Addressables through Unity MCP — Addressables, AssetReference, AssetReferenceT, Addressables.LoadAssetAsync, Addressables.InstantiateAsync, Addressables.LoadSceneAsync, Addressables.Release, addressable group, label, content catalog, remote group, local group, build remote catalog, async asset loading, lazy load, Resources alternative, AsyncOperationHandle, asset bundle, content update, smart bundle compression, BuildPipelineProfile. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

Companion: `unity-scenes` (scene Addressables, additive loading), `unity-persistence` (data versioning across content updates), `unity-build` (CI hook for `BuildPlayerContent`).

## When to use

- Replace `Resources/` with async on-demand loading.
- Ship content updates (skins, levels, fixes) without an app store rebuild.
- Stream levels, localization packs, DLC from a CDN.
- Lazy-load prefabs/audio/sprites referenced by `AssetReference`.
- Diagnose leaked bundles or "asset not found" failures after a build.

## Why Addressables

- `Resources/` bakes every asset into the player at build, inflates startup memory, slows Editor imports as it grows. Discouraged since 2019.
- Direct `[SerializeField]` references load the entire dependency chain when the owner loads. Punitive for hub scenes pointing at every weapon/enemy/VFX.
- Raw AssetBundle API forces manual paths/dependencies/variants/catalogs. Addressables is the supported wrapper.
- Provides: async loads, address-based lookup, group-level packing/compression, remote bundles + content updates, refcounting, Editor play mode that skips bundle building.

## Package install

Add `com.unity.addressables` (pulls `com.unity.scriptablebuildpipeline`). After install, `Window > Asset Management > Addressables > Groups`; click **Create Addressables Settings** if prompted. Creates `Assets/AddressableAssetsData/` — commit it.

## Authoring (groups, labels, addresses)

- **Mark addressable** — tick "Addressable" in Inspector, or drag into Groups window. Address defaults to full path; rename to a stable key like `Enemies/Goblin`. Renaming the asset doesn't change the address; renaming the address breaks string lookups.
- **Groups** — bundle multiple addressables sharing download/memory behavior. Organize by content (`Levels`, `Audio`, `UI`, `Localization-EN`), not type. Schema (Content Packing & Loading) controls:
  - **Build Path / Load Path** — Local (StreamingAssets) or Remote (CDN URL).
  - **Bundle Mode** — Pack Together (one bundle per group), Pack Separately (per asset), Pack Together By Label.
  - **Compression** — `LZ4` (Default) for **mobile and runtime-decompressed groups**: ~5x faster decode than LZMA, slightly larger. `LZMA` is ~30% smaller but **CPU-bound on low-end Android** — mid-load hitches and cold-start stalls. Use LZMA only for **desktop** or **pre-warmed downloads** staged to disk and decompressed to LZ4 before play. Default new mobile groups to LZ4.
- **Labels** — string tags (`hat`, `weapon`, `level1`). Load all with `Addressables.LoadAssetsAsync<T>(label, callback)`. Cross groups; assets can have many.

Two addressables sharing an address = build error. Plan a namespace prefix scheme early.

## AssetReference fields

Typed references show only matching assets in the picker:

```csharp
[SerializeField] AssetReferenceGameObject enemyPrefab;
[SerializeField] AssetReferenceT<AudioClip> hitSfx;
[SerializeField] AssetReferenceSprite icon;
```

Prefer typed references over raw strings — survive renames, fail at compile time on type mismatch.

## Loading API

```csharp
AsyncOperationHandle<GameObject> handle =
    Addressables.LoadAssetAsync<GameObject>("Enemies/Goblin");

await handle.Task; // or `yield return handle;`

if (handle.Status == AsyncOperationStatus.Succeeded)
{
    var prefab = handle.Result;
    Instantiate(prefab);
}

Addressables.Release(handle); // critical
```

Via `AssetReference`:

```csharp
var go = await enemyPrefab.LoadAssetAsync<GameObject>().Task;
// later
enemyPrefab.ReleaseAsset();
```

By label:

```csharp
Addressables.LoadAssetsAsync<Sprite>("hat", sprite => cache.Add(sprite));
```

## Scene Addressables

Mark the scene addressable, then:

```csharp
var sceneHandle =
    Addressables.LoadSceneAsync(levelRef, LoadSceneMode.Additive);
await sceneHandle.Task;
SceneInstance instance = sceneHandle.Result;
// later
Addressables.UnloadSceneAsync(instance);
```

`SceneInstance` (not the `Scene` struct) is what unloads correctly — passing the underlying `Scene` to `SceneManager.UnloadSceneAsync` leaks the bundle. See `unity-scenes`.

## Instantiate vs Load

- `Addressables.InstantiateAsync(reference)` — loads if needed AND instantiates. Use `Addressables.ReleaseInstance(go)` to destroy AND decrement bundle refcount.
- `Addressables.LoadAssetAsync<GameObject>(reference)` then `Object.Instantiate(prefab)` — load once, instantiate many. Better for spawners. Release the handle on shutdown.

Mixing on the same prefab is fine — track which path each consumer uses for the right release call.

## Release / handle lifecycle

Every Load returns a handle that increments bundle refcount. Bundle stays loaded until every handle is released.

- Hold the handle as a field; release in `OnDestroy`.
- For `InstantiateAsync` results, store the GameObject and call `ReleaseInstance(go)`.
- For `AssetReference`, call `assetRef.ReleaseAsset()`.
- Leaked handle = bundle stuck for the session.

```csharp
AsyncOperationHandle<GameObject> _handle;

async void Start() {
    _handle = Addressables.LoadAssetAsync<GameObject>("Enemies/Goblin");
    var prefab = await _handle.Task;
}

void OnDestroy() {
    if (_handle.IsValid()) Addressables.Release(_handle);
}
```

## Memory model

- **Refcounting** — bundle stays loaded while any of its addressables is loaded. Releasing the last asset releases the bundle.
- **Pack Together** — one bundle per group; loading any asset pulls the whole bundle. Cheap inter-group refs; bad for huge groups when you need one asset.
- **Pack Separately** — one bundle per asset; lazy memory but more metadata, more files, slower discovery.
- **Pack Together By Label** — sweet spot for grouped content (`level1`, `language-en`).

Profile with Addressables Event Viewer (`Window > Asset Management > Addressables > Event Viewer`) and Memory Profiler.

## Content catalogs and remote

- **Catalog** — manifest mapping addresses to bundle locations. `catalog.json` (and `.bin`/`.hash`).
- **Local catalog** — ships in StreamingAssets.
- **Remote catalog** — hosted on CDN; on boot, player downloads `catalog.hash`, compares, pulls fresh catalog if changed.
- **Profiles** (`Window > Asset Management > Addressables > Profiles`) define `Local.BuildPath`, `Remote.LoadPath`, etc. per environment (Dev/Staging/Prod). Switch before each build.
- **Content updates** — `Build > Update a Previous Build`. Only changed bundles rebuild and upload. App version stays; catalog hash changes; old clients pick up new content next launch.

## Build pipeline

- **Manual** — `Groups > Build > New Build > Default Build Script`. Outputs to `Library/com.unity.addressables/aa/<platform>/`. Local bundles copied into StreamingAssets.
- **CI / scripted** — call `AddressableAssetSettings.BuildPlayerContent()` before `BuildPipeline.BuildPlayer`. Wire as `IPreprocessBuildWithReport` so it can't be forgotten.
- **Remote** — sync `RemoteBuildPath` to the CDN bucket. Player loads from `RemoteLoadPath` baked into the active profile at build.

See `unity-build` for CI hook.

```csharp
public class AddressablesPreBuild : IPreprocessBuildWithReport
{
    public int callbackOrder => 0;
    public void OnPreprocessBuild(BuildReport _) =>
        AddressableAssetSettings.BuildPlayerContent();
}
```

## Common patterns

- **Lazy enemy load** — `AssetReferenceGameObject` on a Spawner; `LoadAssetAsync` on first activation; cache prefab; instantiate per spawn; release on `OnDestroy`.
- **Level streaming** — `LoadSceneAsync(Additive)` for adjacent zones, `UnloadSceneAsync` once distant. Pair with a portal trigger to start the load early.
- **Hot-swap content** — push a remote content update; players get new VFX/textures/balance on next launch with no store update.
- **Localization packs** — group per language with a label; load only active language; reload on language change.
- **Boot warm-up** — `LoadAssetsAsync` on a `boot` label to preload critical menu assets during splash.

## Gotchas

- **Forgetting Release** — leaked memory; bundle stuck. Always pair Load with Release in `OnDestroy`.
- **Mixed direct + AssetReference** — prefab in both serialized scene AND `AssetReference` ships in both player and bundle. Pick one.
- **Android StreamingAssets** — path is `jar:file://` URI inside APK; `File.ReadAllText` chokes. Use `UnityWebRequest`. Addressables handles this — only an issue for adjacent code touching StreamingAssets.
- **Editor play mode** — Play Mode Script setting. "Use Asset Database (faster)" loads via AssetDatabase, no bundle build (fast iteration, no build verification). "Use Existing Build" requires a successful build first; tests the real path. Use the latter before shipping.
- **Remote bundles + offline** — load fails. Ship a fallback (cached default content, retry UI, "go online to update").
- **Duplicate addresses** — build error. Catch in CI by inspecting the build report.
- **Stale save data after content update** — older saves reference an addressable you renamed/deleted; lookup fails. Version save data and migrate dead references (`unity-persistence`).
- **Synchronous waits** — `handle.WaitForCompletion()` blocks main thread; defeats the purpose. Reserve for boot loads where a hitch is OK.

## Verification

- Console — search for "Addressable asset failed to load", "Operation failed: Asset not found", "RemoteProviderException", "Exception encountered in operation".
- Memory Profiler — capture in Play; bundle memory under the Addressables provider. Drift across scene loads = leaked handle.
- Play-mode round-trip — switch Groups to "Use Existing Build", run a fresh build, exercise every load path. Failures surface only here.
- Remote offline test — block the CDN URL and confirm graceful failure handling instead of soft-lock.
- Inspect catalog — open `Library/com.unity.addressables/aa/<platform>/catalog.json` after build. Every expected address should be present.
- Reflect on `AddressableAssetSettingsDefaultObject.Settings.groups` to confirm group composition.

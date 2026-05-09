---
name: unity-addressables
description: 'Use when working with Unity Addressables through Unity MCP — Addressables, AssetReference, AssetReferenceT, Addressables.LoadAssetAsync, Addressables.InstantiateAsync, Addressables.LoadSceneAsync, Addressables.Release, addressable group, label, content catalog, remote group, local group, build remote catalog, async asset loading, lazy load, Resources alternative, AsyncOperationHandle, asset bundle, content update, smart bundle compression, BuildPipelineProfile. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

Companion skills: `unity-scenes` (scene Addressables and additive loading), `unity-persistence` (data versioning across content updates), `unity-build` (CI build hook for `BuildPlayerContent`), `unity-best-practices` (foundational MCP rules).

## When to use

- Replacing a `Resources/` folder with async, on-demand loading.
- Shipping content updates (skins, levels, fixes) without an app store rebuild.
- Streaming levels, localization packs, or DLC from a CDN.
- Lazy-loading prefabs, audio, or sprites referenced by `AssetReference` fields.
- Diagnosing leaked bundles or "asset not found" failures after a build.

## Why Addressables (vs Resources / direct refs / asset bundles)

- `Resources/` folder bakes every asset into the player at build time and inflates startup memory; the asset database also slows down Editor imports as the folder grows. Unity has discouraged it since 2019.
- Direct `[SerializeField]` references load the entire dependency chain when the owning scene/prefab loads. Fine for small scenes; punitive for hub scenes that point at every weapon, enemy, and VFX.
- Raw AssetBundle API works but forces you to manage paths, dependencies, variants, and catalogs by hand. Addressables is the supported wrapper around AssetBundles + the Scriptable Build Pipeline.
- Addressables gives you: async loads, address-based lookup, group-level packing/compression, remote bundles + content updates, reference counting, and an Editor play mode that skips bundle building.

## Package install

Add `com.unity.addressables` via the package-manager capability. It pulls `com.unity.scriptablebuildpipeline` automatically. After install, open `Window > Asset Management > Addressables > Groups` and click **Create Addressables Settings** if prompted. This creates `Assets/AddressableAssetsData/` — commit it.

## Authoring (groups, labels, addresses)

- **Mark addressable** — tick "Addressable" in the Inspector, or drag the asset into the Groups window. Address defaults to the full asset path (`Assets/Prefabs/Goblin.prefab`); rename to a stable key like `Enemies/Goblin`. Renaming the asset later does NOT change the address; renaming the address breaks string lookups.
- **Groups** — a group bundles multiple addressables that share download/memory behavior. Organize by content (`Levels`, `Audio`, `UI`, `Localization-EN`), not by type. Each group has a Schema (Content Packing & Loading) controlling:
  - **Build Path / Load Path** — Local (StreamingAssets) or Remote (CDN URL).
  - **Bundle Mode** — Pack Together (one bundle per group), Pack Separately (one bundle per asset), or Pack Together By Label (one bundle per label within the group).
  - **Compression** — `LZ4` (Default) is correct for **mobile and runtime-decompressed groups**: fast, ~5x decode speed of LZMA, slightly larger file. `LZMA` produces ~30% smaller bundles but is **CPU-bound on low-end Android** — mid-load hitches and cold-start stalls are routine. Use LZMA only for **desktop** or for **pre-warmed downloads** that you stage to disk and decompress to LZ4 once before play. Default new mobile groups to LZ4.
- **Labels** — string tags applied to an addressable (`hat`, `weapon`, `level1`). Load all assets with a label via `Addressables.LoadAssetsAsync<T>(label, callback)`. Labels cross groups; an asset can have many.

Two addressables sharing the same address is a build error. Plan a namespace prefix scheme early.

## AssetReference fields

Typed references show only matching addressable assets in the Inspector picker:

```csharp
[SerializeField] AssetReferenceGameObject enemyPrefab;
[SerializeField] AssetReferenceT<AudioClip> hitSfx;
[SerializeField] AssetReferenceSprite icon;
```

Drag-drop or pick by address. Prefer typed references over raw string addresses — they survive renames and fail at compile time when the type is wrong.

## Loading API

```csharp
AsyncOperationHandle<GameObject> handle =
    Addressables.LoadAssetAsync<GameObject>("Enemies/Goblin");

await handle.Task; // or `yield return handle;` in a coroutine

if (handle.Status == AsyncOperationStatus.Succeeded)
{
    var prefab = handle.Result;
    Instantiate(prefab);
}

Addressables.Release(handle); // critical — see lifecycle section
```

Or via `AssetReference`:

```csharp
var go = await enemyPrefab.LoadAssetAsync<GameObject>().Task;
// later
enemyPrefab.ReleaseAsset();
```

For a label:

```csharp
Addressables.LoadAssetsAsync<Sprite>("hat", sprite => cache.Add(sprite));
```

## Scene Addressables

Mark the scene asset addressable, then:

```csharp
var sceneHandle =
    Addressables.LoadSceneAsync(levelRef, LoadSceneMode.Additive);
await sceneHandle.Task;
SceneInstance instance = sceneHandle.Result;
// ...later
Addressables.UnloadSceneAsync(instance);
```

`SceneInstance` (not the `Scene` struct) is what unloads correctly — passing the underlying `Scene` to `SceneManager.UnloadSceneAsync` leaks the bundle. Cross-link `unity-scenes` for streaming patterns.

## Instantiate vs Load

- `Addressables.InstantiateAsync(reference)` — loads if needed AND instantiates. Use `Addressables.ReleaseInstance(go)` to destroy AND decrement the bundle ref count.
- `Addressables.LoadAssetAsync<GameObject>(reference)` then a manual `UnityEngine.Object.Instantiate(prefab)` — load once, instantiate many. Better for spawners that fire frequently. Release the original handle when the spawner shuts down.

Mixing them on the same prefab is fine, but track which path each consumer uses so the right release call gets made.

## Release / handle lifecycle

Every `LoadAssetAsync` / `LoadSceneAsync` / `LoadAssetsAsync` returns a handle that increments a refcount on its bundle. The bundle stays in memory until every issued handle is released.

- Hold the handle as a field; release in `OnDestroy`.
- For `InstantiateAsync` results, store the GameObject and call `ReleaseInstance(go)` on destroy.
- For `AssetReference`, call `assetRef.ReleaseAsset()` (releases the handle the reference itself is holding).
- A leaked handle = a bundle stuck in memory for the lifetime of the player.

```csharp
AsyncOperationHandle<GameObject> _handle;

async void Start() {
    _handle = Addressables.LoadAssetAsync<GameObject>("Enemies/Goblin");
    var prefab = await _handle.Task;
    // use prefab
}

void OnDestroy() {
    if (_handle.IsValid()) Addressables.Release(_handle);
}
```

## Memory model

- **Reference counting** — a bundle stays loaded while any of its addressables is loaded. Releasing the last loaded asset releases the bundle.
- **Pack Together** — one bundle per group; loading any asset pulls the whole bundle into memory. Cheap inter-group references; bad if the group is huge and you only need one asset.
- **Pack Separately** — one bundle per asset; lazy memory but more bundle metadata, more files on disk, slower discovery.
- **Pack Together By Label** — sweet spot for grouped content like `level1` or `language-en`; load the level, get only that level's bundle.

Profile with the Addressables Event Viewer (`Window > Asset Management > Addressables > Event Viewer`) and the Memory Profiler.

## Content catalogs and remote

- The **catalog** is the manifest mapping addresses to bundle locations. It ships as `catalog.json` (and `.bin` / `.hash`).
- **Local catalog** ships inside the player at StreamingAssets.
- **Remote catalog** is hosted on a CDN; on boot the player downloads `catalog.hash`, compares, and pulls a fresh catalog if the hash changed.
- **Profiles** (`Window > Asset Management > Addressables > Profiles`) define `Local.BuildPath`, `Remote.LoadPath`, etc. per environment (Dev / Staging / Prod). Switch profile before each build.
- **Content updates** — instead of a full rebuild, run `Build > Update a Previous Build`. Only changed bundles are rebuilt and uploaded. The app version stays the same; the catalog hash changes; old clients pick up new content next launch.

## Build pipeline

- **Manual** — `Window > Asset Management > Addressables > Groups > Build > New Build > Default Build Script`. Outputs to `Library/com.unity.addressables/aa/<platform>/`. Local groups' bundles are copied into StreamingAssets for the player build to pick up.
- **CI / scripted** — call `AddressableAssetSettings.BuildPlayerContent()` before `BuildPipeline.BuildPlayer`. Wire it as an `IPreprocessBuildWithReport` so it cannot be forgotten.
- **Remote** — after the build, sync the `RemoteBuildPath` directory to the CDN bucket. The player loads from `RemoteLoadPath` baked into the active profile at build time.

Cross-link `unity-build` for the CI hook.

```csharp
public class AddressablesPreBuild : IPreprocessBuildWithReport
{
    public int callbackOrder => 0;
    public void OnPreprocessBuild(BuildReport _) =>
        AddressableAssetSettings.BuildPlayerContent();
}
```

## Common patterns

- **Lazy enemy load** — `AssetReferenceGameObject` on a Spawner; `LoadAssetAsync` on first activation; cache the prefab; instantiate per spawn; release on `OnDestroy`.
- **Level streaming** — `Addressables.LoadSceneAsync(LoadSceneMode.Additive)` for adjacent zones, `UnloadSceneAsync` once distant. Pair with a portal trigger to start the load early.
- **Hot-swap content** — push a remote content update with new VFX / textures / balance prefabs; players get them on next launch with no app store update.
- **Localization packs** — group per language with a label; load only the active language's bundle, switch by reload on language change.
- **Boot warm-up** — `LoadAssetsAsync` on a `boot` label to preload critical menu assets while the splash plays.

## Gotchas

- **Forgetting to Release** — leaked memory; bundle stuck for the session. Always pair Load with Release in `OnDestroy`.
- **Mixed direct + AssetReference** — if a prefab is both serialized directly into a scene AND referenced as an `AssetReference`, it goes into both the player and the bundle. Pick one.
- **Android StreamingAssets** — path is a `jar:file://` URI inside the APK; `File.ReadAllText` chokes. Use `UnityWebRequest` for raw reads. Addressables itself handles this — only an issue for adjacent code that touches StreamingAssets.
- **Editor play mode** — Groups window has a Play Mode Script setting. "Use Asset Database (faster)" loads via AssetDatabase with no bundle build (fast iteration, no build verification). "Use Existing Build" requires a successful Addressables build first and exercises the real bundle path. Test with the latter before shipping.
- **Remote bundles + offline player** — load fails. Ship a fallback (cached default content, retry UI, or a "go online to update" message). Do not assume connectivity.
- **Duplicate addresses** — two assets sharing the same address is a build error. Catch in CI by inspecting the build report.
- **Stale save data after content update** — older saves reference an addressable you renamed or deleted; lookup fails on load. Cross-link `unity-persistence`: version your save data and migrate dead references.
- **Synchronous waits** — `handle.WaitForCompletion()` exists but blocks the main thread; defeats the purpose of Addressables. Reserve for boot-time loads where a hitch is acceptable.

## Verification

- **Editor console** — search for "Addressable asset failed to load", "Operation failed: Asset not found", "RemoteProviderException", "Exception encountered in operation".
- **Memory Profiler** — capture in Play mode; bundle memory shows up under the Addressables provider. Drift across scene loads = leaked handle.
- **Play mode round-trip** — switch the Groups window to "Use Existing Build", run a fresh Addressables build, enter Play, exercise every load path. Failures surface only in this mode.
- **Remote offline test** — block the CDN URL (firewall or fake DNS) and confirm the offline fallback handles the load failure gracefully instead of soft-locking.
- **Inspect catalog** — open `Library/com.unity.addressables/aa/<platform>/catalog.json` after a build. Every expected address should be present; a missing entry means the asset slipped out of the addressable group.
- **Reflect on settings** — inspect `AddressableAssetSettingsDefaultObject.Settings.groups` to confirm group composition matches expectations after authoring changes.

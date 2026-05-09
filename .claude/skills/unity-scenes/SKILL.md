---
name: unity-scenes
description: 'Use when working with Unity scene loading, multi-scene editing, or persistence patterns through Unity MCP — SceneManager, LoadScene, LoadSceneAsync, additive scene, persistent scene, boot scene, scene transition, scene streaming, multi-scene editing, DontDestroyOnLoad, scene fade, scene reference, scene index, scene path, build settings scene list, scene unload, OnSceneLoaded, scene validation, async scene loading, level loading, level streaming. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

Companion skill: `unity-persistence` for save data; the boot scene pattern below pairs with the SaveManager singleton there. See `unity-best-practices` for foundational MCP rules and `unity-addressables` for scene loading via `AssetReference`.

## When to use

- Loading or unloading scenes at runtime via `SceneManager`.
- Building a boot scene that owns persistent managers (audio, save, game state).
- Streaming level chunks additively or running a persistent UI overlay scene.
- Diagnosing "works in editor, broken in build" scene errors.
- Setting up cross-scene communication or fade transitions.

## SceneManager API

`UnityEngine.SceneManagement.SceneManager` is the runtime entry point.

- `LoadScene(string name | int buildIndex, LoadSceneMode mode)` — synchronous, blocks the main thread until the scene loads. Use only on first boot or when a hitch is acceptable.
- `LoadSceneAsync(name | index, mode)` — returns an `AsyncOperation`. `.progress` ramps 0 to 0.9, then waits for activation. `.isDone` flips true after activation.
- `LoadSceneMode.Single` replaces all loaded scenes; `LoadSceneMode.Additive` layers on top.
- `UnloadSceneAsync(scene)` — destroys scene contents; only one Single-mode scene can exist at a time, but multiple additive scenes can be unloaded individually.
- `GetActiveScene()`, `SetActiveScene(scene)` — the active scene hosts lighting, skybox, and `Instantiate` parenting for new GameObjects without an explicit scene.
- `GetSceneByName`, `GetSceneByPath`, `GetSceneByBuildIndex` — query loaded scenes; check `.isLoaded` before using.
- `sceneLoaded`, `sceneUnloaded`, `activeSceneChanged` — events.

## Async loading and progress

`.progress` caps at 0.9 until you allow activation. Set `allowSceneActivation = false` to preload a scene without swapping in.

```csharp
public IEnumerator LoadLevel(string sceneName)
{
    var op = SceneManager.LoadSceneAsync(sceneName);
    op.allowSceneActivation = false;

    // Load to 0.9, then hold for fade or user input.
    while (op.progress < 0.9f) yield return null;

    yield return StartCoroutine(FadeOut());
    op.allowSceneActivation = true;

    while (!op.isDone) yield return null;
    yield return StartCoroutine(FadeIn());
}
```

## Additive loading and the boot scene pattern

Scene index 0 is the boot scene. It contains a single GameObject with persistent managers (Audio, Save, GameState, EventBus). On `Awake`, mark them `DontDestroyOnLoad` and load the next scene.

```csharp
public class Bootstrapper : MonoBehaviour
{
    [SerializeField] string firstScene = "MainMenu";

    void Awake()
    {
        DontDestroyOnLoad(gameObject);
        // Managers attached as components on this GameObject travel with it.
        SceneManager.LoadScene(firstScene, LoadSceneMode.Single);
    }
}
```

Future scenes assume managers exist; never `GameObject.Find("AudioManager")`. Use a static `AudioManager.Instance` set in the manager's own `Awake` (cross-link `unity-patterns` singleton).

For level streaming, the boot stays loaded, then a hub scene loads additively, then zone scenes load and unload around the player:

```csharp
yield return SceneManager.LoadSceneAsync("Hub", LoadSceneMode.Additive);
SceneManager.SetActiveScene(SceneManager.GetSceneByName("Hub"));
// Hub now hosts lighting and new instantiates.
```

## DontDestroyOnLoad managers

`DontDestroyOnLoad` only works on **root** GameObjects. Calling it on a child of a non-DDOL parent silently does nothing — Unity moves the root to a hidden DDOL scene, and a child cannot move while its parent stays.

If the boot scene reloads (e.g., user hits "New Game" and `LoadScene(0)`), the bootstrapper runs again and creates a duplicate manager. Guard with a singleton check. Use the canonical singleton pattern from `unity-patterns` for the manager scaffold. Boot-scene-specific guidance: declare each manager in scene index 0 so `Awake` order is predictable, gate the boot loader behind the singleton check on the bootstrapper itself, and avoid `DontDestroyOnLoad` on children — only the root survives.

## Scene references (the build settings trap)

**Scenes must be in Build Settings** (`File > Build Settings > Scenes In Build`) to be loadable by name in builds. In the Editor, full asset paths work for any scene; in builds, only listed scenes exist. This is the #1 "works in editor, broken in build" gotcha.

Hard-coding scene names as strings is fragile. Prefer one of:

- **`SceneAsset` field (Editor-only)** — typed reference in the inspector; store the scene path as a string at build time via a custom property drawer or `OnValidate`.
- **ScriptableObject scene reference asset** — wraps the path string; gameplay code reads from the SO.
- **Addressables** — scene assets become `AssetReference`. Load via `Addressables.LoadSceneAsync(reference, LoadSceneMode.Additive)`. Cross-link `unity-addressables`.

Add scenes through the build-settings editor — append the scene path (e.g. `Assets/Scenes/Level1.unity`) to `EditorBuildSettings.scenes`, or open `File > Build Settings` from the menu and edit there. Reflect on `EditorBuildSettings.scenes` afterwards to confirm.

## Cross-scene references

A MonoBehaviour in scene A cannot directly reference a GameObject in scene B at edit time — Unity has no way to serialize the link. Solutions:

- **ScriptableObject channel asset** — a `GameEventSO` with a `Raise()` method and a list of listeners. Scene B subscribes on `OnEnable`; scene A raises. Both reference the SO asset, not each other.
- **Addressables** — load assets by reference, look them up by handle.
- **Runtime lookup after both loaded** — `GameObject.FindWithTag` or a registry singleton populated on `Awake`.

The SO channel is the cleanest pattern; cross-link `unity-patterns` for event bus details.

## Multi-scene editing

Drag multiple scene assets into the Hierarchy to open them simultaneously in the Editor. Use cases:

- Split environment, lighting, and gameplay into separate scenes for team workflow (one merge conflict surface per layer).
- Author a base lighting scene that artists own, plus gameplay scenes that designers own.
- Test additive loads at edit time without entering Play mode.

Add scenes to the active editor session through the scene-management capability.

## Scene transitions and fades

A persistent UI canvas in the boot scene owns a full-screen black `Image`. Tween its alpha 0 to 1, trigger `LoadSceneAsync` with `allowSceneActivation = false`, wait for `.progress >= 0.9f`, set `allowSceneActivation = true`, fade back out.

```csharp
public class SceneTransition : MonoBehaviour
{
    [SerializeField] CanvasGroup fader;
    [SerializeField] float fadeDuration = 0.4f;

    public IEnumerator GoTo(string sceneName)
    {
        yield return Fade(0f, 1f);
        var op = SceneManager.LoadSceneAsync(sceneName);
        op.allowSceneActivation = false;
        while (op.progress < 0.9f) yield return null;
        op.allowSceneActivation = true;
        while (!op.isDone) yield return null;
        yield return Fade(1f, 0f);
    }

    IEnumerator Fade(float from, float to)
    {
        float t = 0f;
        while (t < fadeDuration)
        {
            t += Time.unscaledDeltaTime;
            fader.alpha = Mathf.Lerp(from, to, t / fadeDuration);
            yield return null;
        }
        fader.alpha = to;
    }
}
```

`Time.unscaledDeltaTime` so the fade survives a paused timescale.

## Common patterns

- **Pause overlay** — additively load `PauseMenu.unity` over gameplay, set `Time.timeScale = 0`, unload on resume.
- **Level select hub** — persistent boot + hub scene; selecting a level additively loads it, then unloads the hub or keeps it for back-out.
- **Persistent UI scene** — HUD / debug / chat in a single scene loaded once and never unloaded.
- **Debug HUD scene** — toggle-load via a hotkey for FPS counter, console, and dev tools.

## Gotchas

- Scene not in Build Settings — works in Editor, fails in build with "Scene 'X' couldn't be loaded because it has not been added to the build settings".
- `DontDestroyOnLoad` on a child has no effect; only roots survive.
- `GameObject.Find` calls in scene 0's `Awake` find nothing — other scenes have not loaded yet.
- `OnSceneLoaded` fires DURING the load callback chain; `SetActiveScene` ordering matters if you Instantiate during the event.
- `LoadSceneAsync` `.progress` caps at 0.9 until activation; do not wait for `>= 1f`.
- Scene parameters cannot carry data between scenes — use a persistent manager, ScriptableObject, or static field.
- Loading a Single-mode scene during an additive load callback can cascade-crash; queue and load on the next frame.
- `SceneManager.GetSceneByName` returns an invalid Scene struct if the scene is not loaded; check `.isLoaded`.

## Verification

- Editor console clean of "Scene 'X' couldn't be loaded", "DontDestroyOnLoad only work for root GameObjects", "ArgumentException: Scene to unload is invalid".
- Confirm the Build Settings scene list contains every scene loaded by name — inspect `EditorBuildSettings.scenes` directly.
- Play-mode test — enter Play, watch console, trigger a scene load, confirm `.progress` ramps 0 to 0.9 and managers persist after the load by querying for the singleton root.
- After a scripted boot test, querying for active GameObjects should return one and only one of each manager — duplicates indicate a missing singleton guard.

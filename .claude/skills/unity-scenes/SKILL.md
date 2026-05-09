---
name: unity-scenes
description: 'Use when working with Unity scene loading, multi-scene editing, or persistence patterns through Unity MCP — SceneManager, LoadScene, LoadSceneAsync, additive scene, persistent scene, boot scene, scene transition, scene streaming, multi-scene editing, DontDestroyOnLoad, scene fade, scene reference, scene index, scene path, build settings scene list, scene unload, OnSceneLoaded, scene validation, async scene loading, level loading, level streaming. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

Companion: `unity-persistence` (boot scene pairs with SaveManager singleton); `unity-addressables` for scene loading via `AssetReference`.

## When to use

- `SceneManager` runtime load/unload.
- Boot scene owning persistent managers (audio, save, game state).
- Streaming level chunks additively or running a persistent UI overlay.
- Diagnosing "works in editor, broken in build" scene errors.
- Cross-scene communication or fade transitions.

## SceneManager API

`UnityEngine.SceneManagement.SceneManager`:

- `LoadScene(string name | int buildIndex, LoadSceneMode mode)` — synchronous, blocks main thread. Use only on first boot or when a hitch is OK.
- `LoadSceneAsync(name | index, mode)` — returns `AsyncOperation`. `.progress` ramps 0→0.9, then waits for activation. `.isDone` flips after activation.
- `LoadSceneMode.Single` replaces all loaded scenes; `LoadSceneMode.Additive` layers on top.
- `UnloadSceneAsync(scene)` — destroys contents; only one Single-mode scene at a time, multiple additive scenes can be unloaded individually.
- `GetActiveScene()`, `SetActiveScene(scene)` — active scene hosts lighting, skybox, default `Instantiate` parenting.
- `GetSceneByName`, `GetSceneByPath`, `GetSceneByBuildIndex` — query loaded scenes; check `.isLoaded`.
- `sceneLoaded`, `sceneUnloaded`, `activeSceneChanged` — events.

## Async loading and progress

`.progress` caps at 0.9 until activation. Set `allowSceneActivation = false` to preload without swapping in.

```csharp
public IEnumerator LoadLevel(string sceneName)
{
    var op = SceneManager.LoadSceneAsync(sceneName);
    op.allowSceneActivation = false;

    while (op.progress < 0.9f) yield return null;

    yield return StartCoroutine(FadeOut());
    op.allowSceneActivation = true;

    while (!op.isDone) yield return null;
    yield return StartCoroutine(FadeIn());
}
```

## Additive loading and the boot scene pattern

Scene index 0 = boot. One GameObject with persistent managers (Audio, Save, GameState, EventBus). On `Awake`, mark `DontDestroyOnLoad` and load the next scene.

```csharp
public class Bootstrapper : MonoBehaviour
{
    [SerializeField] string firstScene = "MainMenu";

    void Awake()
    {
        DontDestroyOnLoad(gameObject);
        SceneManager.LoadScene(firstScene, LoadSceneMode.Single);
    }
}
```

Future scenes assume managers exist; never `GameObject.Find("AudioManager")`. Use a static `AudioManager.Instance` set in the manager's own `Awake` (`unity-patterns` singleton).

For level streaming, boot stays loaded, hub loads additively, zone scenes load/unload around the player:

```csharp
yield return SceneManager.LoadSceneAsync("Hub", LoadSceneMode.Additive);
SceneManager.SetActiveScene(SceneManager.GetSceneByName("Hub"));
```

## DontDestroyOnLoad managers

Only works on **root** GameObjects. On a child of a non-DDOL parent, silently does nothing — Unity moves the root to a hidden DDOL scene; a child can't move while its parent stays.

If boot reloads (user hits "New Game" → `LoadScene(0)`), the bootstrapper runs again and creates a duplicate. Guard with the singleton pattern from `unity-patterns`. Boot-specific: declare each manager in scene 0 so `Awake` order is predictable, gate the boot loader behind a singleton check, never `DontDestroyOnLoad` on children.

## Scene references (the build settings trap)

**Scenes must be in Build Settings** (`File > Build Settings > Scenes In Build`) to be loadable by name in builds. Editor accepts full asset paths for any scene; builds only know listed scenes. #1 "works in editor, broken in build" gotcha.

Hard-coding scene name strings is fragile. Prefer:

- **`SceneAsset` field (Editor-only)** — typed inspector reference; store path string at build via property drawer or `OnValidate`.
- **ScriptableObject scene reference asset** — wraps the path string.
- **Addressables** — `Addressables.LoadSceneAsync(reference, LoadSceneMode.Additive)`. See `unity-addressables`.

Add scenes via the build-settings editor — append the scene path to `EditorBuildSettings.scenes`, or `File > Build Settings`. Reflect on `EditorBuildSettings.scenes` to confirm.

## Cross-scene references

A MonoBehaviour in scene A can't directly reference a GameObject in scene B at edit time — no way to serialize the link. Solutions:

- **ScriptableObject channel asset** — `GameEventSO` with `Raise()` and listener list. Scene B subscribes `OnEnable`; scene A raises. Both reference the SO, not each other.
- **Addressables** — load by reference, look up by handle.
- **Runtime lookup after both loaded** — `GameObject.FindWithTag` or a registry singleton populated on `Awake`.

SO channel is cleanest; see `unity-patterns` for event bus details.

## Multi-scene editing

Drag multiple scene assets into the Hierarchy to open simultaneously. Use cases:

- Split environment, lighting, and gameplay into separate scenes for team workflow.
- Author a base lighting scene that artists own + gameplay scenes that designers own.
- Test additive loads at edit time without entering Play mode.

## Scene transitions and fades

Persistent UI canvas in boot owns a full-screen black `Image`. Tween alpha 0→1, `LoadSceneAsync` with `allowSceneActivation = false`, wait for `.progress >= 0.9f`, set `allowSceneActivation = true`, fade back out.

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

`Time.unscaledDeltaTime` so the fade survives paused timescale.

## Common patterns

- **Pause overlay** — additively load `PauseMenu.unity`, `Time.timeScale = 0`, unload on resume.
- **Level select hub** — persistent boot + hub; selecting a level additively loads it, then unloads hub or keeps for back-out.
- **Persistent UI scene** — HUD / debug / chat in a scene loaded once, never unloaded.
- **Debug HUD scene** — toggle-load via hotkey for FPS counter, console, dev tools.

## Gotchas

- Scene not in Build Settings — works in Editor, fails in build with "Scene 'X' couldn't be loaded because it has not been added to the build settings".
- `DontDestroyOnLoad` on a child has no effect.
- `GameObject.Find` in scene 0's `Awake` finds nothing — other scenes haven't loaded.
- `OnSceneLoaded` fires DURING load callback; `SetActiveScene` ordering matters if you Instantiate during the event.
- `LoadSceneAsync` `.progress` caps at 0.9 until activation; don't wait for `>= 1f`.
- Scene parameters can't carry data between scenes — use a persistent manager, ScriptableObject, or static field.
- Loading Single-mode during an additive load callback can cascade-crash; queue for next frame.
- `GetSceneByName` returns invalid Scene struct if not loaded; check `.isLoaded`.

## Verification

- Console clean of "Scene 'X' couldn't be loaded", "DontDestroyOnLoad only work for root GameObjects", "ArgumentException: Scene to unload is invalid".
- Confirm `EditorBuildSettings.scenes` contains every scene loaded by name.
- Play-mode test — enter Play, trigger scene load, confirm `.progress` ramps 0→0.9 and managers persist by querying for the singleton root.
- After scripted boot, querying for active GameObjects should return one and only one of each manager — duplicates = missing singleton guard.

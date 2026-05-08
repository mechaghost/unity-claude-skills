---
name: unity-patterns
description: Use for the scrappy day-one Unity patterns every indie project ends up needing through Unity MCP — object pool, pooling, ObjectPool, LinkedPool, singleton, MonoBehaviour singleton, persistent manager, DontDestroyOnLoad bootstrap, ScriptableObject event, SO event, GameEvent, runtime config, ScriptableObject runtime, FSM, finite state machine, state machine pattern, pause game, Time.timeScale, unscaled time, unscaledDeltaTime, WaitForSecondsRealtime, debug console, in-game console, cheat console, command pattern, observer pattern, event bus, coroutine sequencing, WaitForSeconds, WaitForFixedUpdate, WaitUntil, WaitWhile, UniTask, async/await Unity, deltaTime, SmoothDamp. Unity 6 / URP-only / new Input System only. For screenshot capture and 3D verification, use unity-3d-verification.
---

# Unity Patterns (indie day-one toolkit)

## When to use

Fire this skill when the user is reaching for the ubiquitous patterns that don't fit a single subsystem skill:

- pooling instantiated objects (bullets, enemies, damage numbers, particle bursts)
- persistent singletons / cross-scene managers (Audio, Save, GameState)
- decoupling systems via ScriptableObject events or runtime config
- finite state machine design for AI, UI flow, or game phase
- pausing the game without breaking UI tweens or music
- sequencing async logic with coroutines (cutscenes, intros, fades)
- capturing screenshots for marketing capsules or debug snapshots
- in-game cheat console for dev iteration

For dedicated subsystems, defer to: `unity-audio`, `unity-scenes`, `unity-persistence`, `unity-animation`, `unity-shuriken`, `unity-3d-verification`, `unity-best-practices`.

## MCP cheatsheet

`manage_components`, `manage_gameobject`, `manage_asset`, `manage_scene`, `manage_scriptable_object`, `find_gameobjects`, `read_console`, `unity_reflect`, `unity_docs`, `apply_text_edits`, `create_script`, `batch_execute`.

## Object pooling

Unity 6 ships `UnityEngine.Pool.ObjectPool<T>` — use it instead of rolling your own.

```csharp
using UnityEngine;
using UnityEngine.Pool;

public class BulletPool : MonoBehaviour {
    [SerializeField] Bullet prefab;
    ObjectPool<Bullet> pool;

    void Awake() {
        pool = new ObjectPool<Bullet>(
            createFunc:      () => Instantiate(prefab),
            actionOnGet:     b => b.gameObject.SetActive(true),
            actionOnRelease: b => b.gameObject.SetActive(false),
            actionOnDestroy: b => Destroy(b.gameObject),
            collectionCheck: false,
            defaultCapacity: 32,
            maxSize:         256);
    }

    public Bullet Get() => pool.Get();
    public void Release(Bullet b) => pool.Release(b);
}
```

- On Get: pull from pool, set active, reset state (velocity, lifetime, references).
- On Release: clear references, set inactive. NEVER `Destroy` — that defeats the pool.
- Pool ParticleSystems (cross-link `unity-shuriken`'s `Stop Action: Disable`), AudioSources, projectiles, enemies, damage numbers.
- `LinkedPool<T>` for low-allocation linked-list backing when you don't need indexed access.

## Singleton MonoBehaviour (canonical)

This is the canonical singleton pattern; `unity-scenes`' boot-scene flow and `unity-persistence`'s SaveManager both use it. Pattern for engine-bound persistent managers (Audio, Save, GameState, EventBus). For pure C# services prefer dependency injection.

```csharp
[DefaultExecutionOrder(-100)]
public class AudioManager : MonoBehaviour {
    public static AudioManager Instance { get; private set; }

    void Awake() {
        if (Instance != null && Instance != this) {
            Destroy(gameObject);
            return;
        }
        Instance = this;
        DontDestroyOnLoad(gameObject);
    }

    void OnDestroy() {
        if (Instance == this) Instance = null;
    }
}
```

- `[DefaultExecutionOrder(-100)]` pins `Awake` ahead of consumers so `Instance` is non-null when other components run their own `Awake`/`OnEnable`.
- **Bootstrap scene pattern**: place all singleton-bearing GameObjects in scene index 0; load main scene additively. Cross-link `unity-scenes`.
- Don't use `Object.FindAnyObjectByType<T>()` to lazy-init singletons — explicit Bootstrap scene is more deterministic and works under `[DefaultExecutionOrder(-100)]`.
- For testability, prefer DI (constructor params, plain C# services) over MonoBehaviour singletons. Reach for singletons only when the dependency is engine-bound (audio, scenes, input).

## ScriptableObject as runtime config

Replace public-static-data classes with SO assets. Designers edit values in the inspector; data is asset-versioned in git.

```csharp
[CreateAssetMenu(menuName = "Game/WeaponData")]
public class WeaponData : ScriptableObject {
    public int damage;
    public float fireRate;
    public AudioClip fireSfx;
    public GameObject muzzleFlashPrefab;
}
```

- Reference from MonoBehaviours by `[SerializeField]` field.
- Build a library of WeaponData assets per variant (Pistol.asset, SMG.asset, Shotgun.asset).
- SO data CHANGES at runtime do NOT persist across runs in builds — use `unity-persistence` for save data. Cross-link.

## ScriptableObject as event bus

Decouple raisers from listeners. Two assets cooperate: a `GameEvent` SO and a `GameEventListener` MonoBehaviour.

```csharp
[CreateAssetMenu(menuName = "Events/GameEvent")]
public class GameEvent : ScriptableObject {
    readonly List<GameEventListener> listeners = new();
    public void Raise() {
        for (int i = listeners.Count - 1; i >= 0; i--) listeners[i].OnRaised();
    }
    public void Register(GameEventListener l) => listeners.Add(l);
    public void Unregister(GameEventListener l) => listeners.Remove(l);
}

public class GameEventListener : MonoBehaviour {
    public GameEvent gameEvent;
    public UnityEvent response;
    void OnEnable()  => gameEvent.Register(this);
    void OnDisable() => gameEvent.Unregister(this);
    public void OnRaised() => response.Invoke();
}
```

- One GameEvent asset = one signal channel ("PlayerDied", "WaveCleared", "CheckpointReached"). Raisers know nothing about listeners.
- Generic variant `GameEvent<T>` carries a payload (damage amount, world position).
- Cross-link `unity-audio` (AudioManager subscribes to "PlayerDied"), `unity-persistence` (SaveManager subscribes to "CheckpointReached").

## Simple finite state machine

For ~5 states, an enum + switch in Update is fine and beats over-engineering:

```csharp
enum State { Idle, Patrol, Chase, Attack, Dead }
State state;

void Update() {
    switch (state) {
        case State.Idle:   Tick_Idle();   break;
        case State.Patrol: Tick_Patrol(); break;
        case State.Chase:  Tick_Chase();  break;
        case State.Attack: Tick_Attack(); break;
        case State.Dead: break;
    }
}

void TransitionTo(State next) {
    OnExit(state); state = next; OnEnter(state);
}
```

- For >10 states or hierarchical machines, consider Animator state machines (cross-link `unity-animation`), behavior trees (NodeCanvas / Behavior Designer), or a coded HFSM library.
- Avoid coroutine-based state machines that hard-block control flow inside states — they're hard to interrupt cleanly.

## Pause and unscaled time

- `Time.timeScale = 0f` pauses physics, Animator, particle systems, and any `Time.deltaTime`-driven script. Set to `1f` to resume.
- **Audio is NOT paused by `Time.timeScale`.** Use `AudioListener.pause = true` for full audio pause, OR `audioSource.ignoreListenerPause = true` to keep music/UI clicks playing through pause.
- **UI should still animate during pause.** Use `Time.unscaledDeltaTime` in tween code; set Animator `Update Mode` to `Unscaled Time` so menu animations survive `timeScale = 0`.
- **Coroutines yielding `WaitForSeconds(t)` use scaled time** (frozen at 0). Use `WaitForSecondsRealtime(t)` for unscaled timing.

```csharp
public static class GamePause {
    static int depth;
    public static void Push() {
        if (++depth == 1) { Time.timeScale = 0f; AudioListener.pause = true; }
    }
    public static void Pop() {
        if (--depth == 0) { Time.timeScale = 1f; AudioListener.pause = false; }
    }
}
```

A counted push/pop survives nested pauses (pause menu opened on top of dialog already paused).

## UnityEngine.Awaitable (Unity 6, first-party async-without-GC)

Unity 6 ships built-in allocation-free awaitables. This is the first-party answer to async sequencing without GC churn — reach for it before coroutines or UniTask on Unity 6 projects. UniTask is still the right call on older Unity versions or when you need its broader feature set (PlayerLoopTiming variants, `UniTaskTracker`, async LINQ).

Core API:

- `Awaitable.NextFrameAsync()` — resume next frame (replaces `yield return null`).
- `Awaitable.WaitForSecondsAsync(t)` — scaled-time delay, no per-call allocation.
- `Awaitable.EndOfFrameAsync()` — after rendering (replaces `WaitForEndOfFrame`).
- `Awaitable.FixedUpdateAsync()` — next physics step.
- `Awaitable.BackgroundThreadAsync()` / `MainThreadAsync()` — thread hopping.
- `MonoBehaviour.destroyCancellationToken` — cancels automatically when the component is destroyed; pass it everywhere to avoid leaked tasks across scene loads.

```csharp
async Awaitable IntroSequence() {
    var ct = destroyCancellationToken;
    await FadeFromBlack(1f, ct);
    await Awaitable.WaitForSecondsAsync(0.5f, ct);
    await PlayDialogue("Welcome.", ct);
    await Awaitable.EndOfFrameAsync(ct);
    SceneManager.LoadScene("Level1");
}

void Start() => _ = IntroSequence();
```

`Awaitable` methods return a pooled `Awaitable` — no `Task` allocation, no closure boxing. Cancellation throws `OperationCanceledException`; let it propagate or catch to clean up.

## Coroutine sequencing

Coroutines remain a fine choice for short-lived gameplay sequences and predate `Awaitable`:`IEnumerator`, `yield return null / new WaitForSeconds(t) / AsyncOperation / another coroutine`.

Common yield types: `null` (next frame), `WaitForSeconds(t)`, `WaitForFixedUpdate`, `WaitForEndOfFrame`, `WaitUntil(() => cond)`, `WaitWhile(() => cond)`. `StartCoroutine` returns a `Coroutine` handle; pass to `StopCoroutine`.

**Allocation hygiene.** `new WaitForSeconds(1f)` allocates 16 B per call. Cache instead:

```csharp
static readonly WaitForSeconds wait1s     = new WaitForSeconds(1f);
static readonly WaitForSeconds waitHalf   = new WaitForSeconds(0.5f);
static readonly WaitForFixedUpdate waitFx = new WaitForFixedUpdate();

IEnumerator Tick() {
    while (true) {
        DoWork();
        yield return wait1s;
    }
}
```

`WaitUntil(() => cond)` allocates a closure (~40 B) each time the coroutine enters that yield, plus the `WaitUntil` instance itself. For hot paths either capture state via a member-field predicate (no closure):

```csharp
WaitUntil _waitForLanding;
void Awake() => _waitForLanding = new WaitUntil(IsGrounded);
bool IsGrounded() => _grounded;

IEnumerator AfterLand() {
    yield return _waitForLanding;
    // ...
}
```

…or skip coroutines and `await Awaitable.NextFrameAsync()` in a loop checking the condition — same shape, zero allocs.

**Async/await alternative (older Unity, broader features):** install `com.cysharp.unitask` (UniTask, MIT) for allocation-free awaitables, `await UniTask.Delay`, `CancellationToken` integration with destroyed components, WebGL-friendly. On Unity 6, prefer `Awaitable` first.

```csharp
IEnumerator IntroSequence() {
    yield return FadeFromBlack(1f);
    yield return PlayDialogue("Welcome.");
    yield return WaitForInput();
    yield return FadeToBlack(0.5f);
    SceneManager.LoadScene("Level1");
}
```

Avoid coroutines on disabled GameObjects — they pause silently when the host disables. Run "fire and forget" sequences from a persistent manager GameObject, an `Awaitable`, or UniTask.

## Screenshot helpers

- **Marketing capsule**: `ScreenCapture.CaptureScreenshot(path, superSize: 4)` — 4× resolution capture for Steam capsules.
- **Debug snapshot**:
  ```csharp
  #if UNITY_EDITOR || DEVELOPMENT_BUILD
  if (Input.GetKeyDown(KeyCode.F12)) {
      ScreenCapture.CaptureScreenshot(
          $"shot_{System.DateTime.Now:yyyyMMdd_HHmmss}.png", 2);
  }
  #endif
  ```
- **Render-to-texture** (precise framing): camera → RenderTexture → readback. Use for verification (cross-link `unity-3d-verification`).
- **WebGL**: `ScreenCapture.CaptureScreenshot` writes to virtual filesystem; serve via JS or use `ScreenCapture.CaptureScreenshotAsTexture` + base64 download.

## In-game debug console

When not pulling in third-party (IngameDebugConsole, SRDebugger, Quantum Console):

- Roll a minimal one: a UGUI input field + scrollable Text. On submit, parse first token as command, dispatch to a `Dictionary<string, Action<string[]>>`.
- Gate behind `DEVELOPMENT_BUILD` define and a key-combo (Tilde, F1, three-finger tap on mobile).
- Common commands: `god`, `noclip`, `give <item>`, `tp <x> <y> <z>`, `kill all`, `setflag <name>`, `dumpsave`.
- Cheats also expose hard-to-test states quickly during dev — keep them, ship them stripped behind the define.

## Common patterns

- **DontDestroyOnLoad bootstrapper**: scene 0 has a Managers GameObject; `Awake` calls `DontDestroyOnLoad` on each manager and loads main scene additively. Cross-link `unity-scenes`.
- **Init order via `[DefaultExecutionOrder(-100)]`**: pin singleton `Awake`s early.
- **Lazy-found references**: never call `Object.FindAnyObjectByType<T>()` in `Update`; cache in `OnEnable`.
- **Cache `WaitForSeconds`**: `private static readonly WaitForSeconds wait1s = new WaitForSeconds(1f);` — every fresh `new WaitForSeconds(t)` is a 16-byte alloc that GCs.
- **`[SerializeField] private` fields > public fields** — inspector exposure without API surface.
- **`Mathf.SmoothDamp`** for camera follow and tweens that handle `deltaTime` correctly.
- **`Application.targetFrameRate = 60`** in a startup script — mobile defaults to 30; desktop defaults to vsync.

## Gotchas

- Singleton recreated on scene reload because someone forgot `DontDestroyOnLoad`. Always check `Instance != null` and Destroy duplicates.
- SO event bus with persistent (DDOL) listeners registering in `OnEnable` but not unregistering on quit can throw missing-reference errors during shutdown — clear in `OnApplicationQuit`.
- Coroutines tied to a GameObject pause when the GameObject disables — surprising for fire-and-forget sequences. Use a static MonoBehaviour helper or UniTask for global async.
- `Time.unscaledTime` resets to game-start clock; `Time.realtimeSinceStartup` is wallclock since process start. Different.
- Object pool capacity mis-tuned (too small) thrashes between Get/Release allocs. Profile and tune `defaultCapacity` and `maxSize`.
- `Time.timeScale = 0` does not pause AudioSource pitch tied to `Time.deltaTime`; pause via `AudioListener.pause` or per-source.
- SO config edits in Editor can leak into runtime saves if you mutate via reference; clone via `Instantiate(soAsset)` before mutating.
- Async/await without `Awaitable` or UniTask leaks tasks across scene loads. On Unity 6 always pass `MonoBehaviour.destroyCancellationToken` into `Awaitable` calls; on older Unity, UniTask provides equivalent cancellation tied to component destruction.
- `WaitUntil(() => cond)` and similar lambda-yield forms allocate ~40 B closures per coroutine entry; cache the `WaitUntil` with a method-group predicate or move to `Awaitable`.
- `ScreenCapture.CaptureScreenshot` writes async; reading the file immediately may fail. Use `CaptureScreenshotAsTexture` for sync access.

## Verification

- **Pools**: profile allocation count over 60s of typical usage; expect ~zero allocations after warm-up.
- **Singletons**: unload + reload main scene additively; confirm `Instance` survives, no duplicates in hierarchy.
- **SO events**: log on `Raise`; confirm all expected listeners fire and unregister on disable.
- **Pause**: pause for 5s, confirm Animator paused, music stopped (or playing if `ignoreListenerPause`), UI tweens still running.
- **Screenshots**: open the file; matches expected resolution (`superSize` multiplies width × height).
- `read_console` clean — no "Coroutine couldn't be started because the game object 'X' is inactive" warnings.

Cross-link: `unity-best-practices`, `unity-scenes`, `unity-persistence`, `unity-audio`, `unity-animation`, `unity-shuriken`, `unity-3d-verification`.

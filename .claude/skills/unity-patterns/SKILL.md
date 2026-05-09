---
name: unity-patterns
description: 'Use for day-one Unity patterns: ObjectPool/LinkedPool, MonoBehaviour singletons, DontDestroyOnLoad bootstraps, ScriptableObject runtime config/events, FSMs, pause/unscaled time, tweens, coroutines, Awaitable/UniTask, screenshots, and dev consoles. Unity 6+ / URP / new Input System.'
---

# Unity Patterns

Use for small cross-cutting patterns that do not belong to a subsystem skill. For dedicated audio, scenes, persistence, animation, particles, or verification, use the named sibling skill.

## Object pooling

Unity 6 ships `UnityEngine.Pool.ObjectPool<T>`; use it before writing a custom pool.

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

- Get: set active and reset state (velocity, lifetime, references).
- Release: clear references and set inactive. Never `Destroy`.
- Pool bullets, enemies, damage numbers, AudioSources, and ParticleSystems (`Stop Action: Disable`).
- Use `LinkedPool<T>` when indexed access is irrelevant.

## Singleton MonoBehaviour (canonical)

Use for engine-bound persistent managers (Audio, Save, GameState, EventBus). Prefer plain C# DI for pure services.

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

- `[DefaultExecutionOrder(-100)]` runs manager `Awake` before consumers.
- Bootstrap scene: scene index 0 owns managers, then loads gameplay additively (`unity-scenes`).
- Do not lazy-init with `Object.FindAnyObjectByType<T>()`; explicit boot order is deterministic.

## ScriptableObject as runtime config

Replace public-static data with asset-versioned SOs designers can edit.

```csharp
[CreateAssetMenu(menuName = "Game/WeaponData")]
public class WeaponData : ScriptableObject {
    public int damage;
    public float fireRate;
    public AudioClip fireSfx;
    public GameObject muzzleFlashPrefab;
}
```

- Reference SOs via `[SerializeField]`.
- Make one asset per variant (`Pistol.asset`, `SMG.asset`, `Shotgun.asset`).
- Runtime SO mutations do not persist in builds; use `unity-persistence` for saves.

## ScriptableObject as event bus

Decouple raisers from listeners with a `GameEvent` SO plus listener MonoBehaviours.

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

- One asset = one signal (`PlayerDied`, `WaveCleared`, `CheckpointReached`).
- Generic `GameEvent<T>` can carry payloads.
- Subscribers: audio reacts to death, persistence reacts to checkpoint, UI reacts to inventory.

## Simple finite state machine

For small machines, enum + switch beats framework overhead:

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

- >10 states or hierarchy: consider Animator (`unity-animation`), behavior trees, or an HFSM.
- Avoid coroutine states that block control flow; they are hard to interrupt.

## Tweens

Use tweens for short parametric motion: UI bounce, panel slides, camera shake, hit flashes, counters, fades. Animator-owned clips belong in `unity-animation`.

- **DOTween** — concise sequencing; allocation-free after warm-up.

  ```csharp
  transform.DOScale(1.2f, 0.15f).SetEase(Ease.OutBack)
           .OnComplete(() => transform.DOScale(1f, 0.1f));
  ```

- **No DOTween** — use `SmoothDamp` for following, or coroutine/`Awaitable` + `Lerp`/`SmoothStep` for one-shots.

  ```csharp
  Vector3 vel;
  void LateUpdate() {
      transform.position = Vector3.SmoothDamp(
          transform.position, target.position, ref vel, 0.15f);
  }
  ```

- Pause UI: DOTween `.SetUpdate(true)` or manual `Time.unscaledDeltaTime`.
- Kill tweens in `OnDestroy` (`tween.Kill()` / `DOTween.Kill(target)`) to avoid destroyed-target exceptions.

## Pause and unscaled time

- `Time.timeScale = 0f` pauses physics, Animator, particles, and `deltaTime` scripts.
- Audio ignores timeScale; use `AudioListener.pause` or per-source `ignoreListenerPause`.
- Pause UI needs `unscaledDeltaTime` or Animator `Update Mode = Unscaled Time`.
- `WaitForSeconds` freezes at timeScale 0; use `WaitForSecondsRealtime`.

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

Counted push/pop survives nested pauses.

## UnityEngine.Awaitable (Unity 6, first-party async-without-GC)

Unity 6 has allocation-free first-party awaitables. Prefer them before coroutines/UniTask unless you need UniTask's broader feature set.

- `Awaitable.NextFrameAsync()` — resume next frame (replaces `yield return null`).
- `Awaitable.WaitForSecondsAsync(t)` — scaled-time delay, no per-call allocation.
- `Awaitable.EndOfFrameAsync()` — after rendering (replaces `WaitForEndOfFrame`).
- `Awaitable.FixedUpdateAsync()` — next physics step.
- `Awaitable.BackgroundThreadAsync()`/`MainThreadAsync()` — thread hopping.
- `MonoBehaviour.destroyCancellationToken` — cancels automatically when component is destroyed; pass it everywhere to avoid leaked tasks across scene loads.

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

Pooled `Awaitable` means no `Task` allocation. Cancellation throws `OperationCanceledException`; let it propagate unless cleanup is needed.

## Coroutine sequencing

Coroutines remain fine for short sequences: `IEnumerator`, `yield return null`, `WaitForSeconds`, `AsyncOperation`, nested coroutine. `StartCoroutine` returns a handle for `StopCoroutine`.

Cache repeated yield instructions:

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

`WaitUntil(() => cond)` allocates a closure; use method-group predicates on hot paths:

```csharp
WaitUntil _waitForLanding;
void Awake() => _waitForLanding = new WaitUntil(IsGrounded);
bool IsGrounded() => _grounded;

IEnumerator AfterLand() {
    yield return _waitForLanding;
    // ...
}
```

Or use `await Awaitable.NextFrameAsync()` in a loop. Older Unity / broader async features: UniTask.

```csharp
IEnumerator IntroSequence() {
    yield return FadeFromBlack(1f);
    yield return PlayDialogue("Welcome.");
    yield return WaitForInput();
    yield return FadeToBlack(0.5f);
    SceneManager.LoadScene("Level1");
}
```

Avoid fire-and-forget coroutines on objects that may disable; use a persistent runner, `Awaitable`, or UniTask.

## Screenshot helpers

- **Marketing capsule**: `ScreenCapture.CaptureScreenshot(path, superSize: 4)`.
- **Debug snapshot** (this skill set is new-Input-System-only; legacy `Input` is forbidden):
  ```csharp
  using UnityEngine.InputSystem;

  #if UNITY_EDITOR || DEVELOPMENT_BUILD
  if (Keyboard.current != null && Keyboard.current.f12Key.wasPressedThisFrame) {
      ScreenCapture.CaptureScreenshot(
          $"shot_{System.DateTime.Now:yyyyMMdd_HHmmss}.png", 2);
  }
  #endif
  ```
- **Precise framing**: Camera -> RenderTexture -> readback (`unity-3d-verification`).
- **WebGL**: virtual filesystem; serve via JS or use `CaptureScreenshotAsTexture` + base64 download.

## In-game debug console

Install `IngameDebugConsole` or `Quantum Console`, or build UGUI InputField + `Dictionary<string, Action<string[]>>`. Gate behind `DEVELOPMENT_BUILD` and a deliberate key combo / gesture. Useful commands: `give`, `tp`, `setflag`, `dumpsave`.

## Common patterns

- **DontDestroyOnLoad bootstrapper**: scene 0 owns Managers, calls `DontDestroyOnLoad`, then loads gameplay additively.
- **Lazy-found references**: never call `Object.FindAnyObjectByType<T>()` in `Update`; cache in `OnEnable`.
- **`[SerializeField] private` fields > public fields** — inspector exposure without API surface.
- **`Application.targetFrameRate = 60`** in a startup script — mobile defaults to 30; desktop defaults to vsync.

## Gotchas

- Singleton recreated on scene reload because someone forgot `DontDestroyOnLoad`. Always check `Instance != null` and Destroy duplicates.
- SO event listeners must unregister; persistent listeners may also need `OnApplicationQuit` cleanup.
- Coroutines tied to a disabled GameObject pause silently.
- `Time.unscaledTime` resets to game-start clock; `Time.realtimeSinceStartup` is wallclock since process start. Different.
- Object pool capacity mis-tuned (too small) thrashes between Get/Release allocs. Profile and tune `defaultCapacity` and `maxSize`.
- `Time.timeScale = 0` does not pause AudioSource pitch tied to `Time.deltaTime`; pause via `AudioListener.pause` or per-source.
- SO config edits in Editor can leak into runtime saves if you mutate via reference; clone via `Instantiate(soAsset)` before mutating.
- Async without cancellation leaks across scene loads. Pass `destroyCancellationToken` to Unity 6 `Awaitable`; use UniTask cancellation on older Unity.
- `WaitUntil(() => cond)` and similar lambda-yield forms allocate ~40 B closures per coroutine entry; cache `WaitUntil` with method-group predicate or move to `Awaitable`.
- `ScreenCapture.CaptureScreenshot` writes async; reading the file immediately may fail. Use `CaptureScreenshotAsTexture` for sync access.

## Verification

- **Pools**: profile allocation count over 60s of typical usage; expect ~zero allocations after warm-up.
- **Singletons**: unload + reload main scene additively; confirm `Instance` survives, no duplicates in hierarchy.
- **SO events**: log on `Raise`; confirm all expected listeners fire and unregister on disable.
- **Pause**: pause for 5s, confirm Animator paused, music stopped (or playing if `ignoreListenerPause`), UI tweens still running.
- **Screenshots**: open the file; matches expected resolution (`superSize` multiplies width × height).
- Editor console clean — no "Coroutine couldn't be started because the game object 'X' is inactive" warnings.

Cross-link: `unity-best-practices`, `unity-scenes`, `unity-persistence`, `unity-audio`, `unity-animation`, `unity-shuriken`, `unity-3d-verification`.

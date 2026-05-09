# Timeline reference

Package: `com.unity.timeline`. Window: `Window > Sequencing > Timeline`. Asset extension: `.playable` (a `TimelineAsset`).

## PlayableDirector

Component on a scene GameObject; binds tracks in the Timeline asset to scene objects.

Fields:

- **Playable** — the TimelineAsset to play.
- **Update Method**:
  - `Game Time` (default) — uses `Time.deltaTime`. Affected by `Time.timeScale`.
  - `Unscaled Game Time` — ignores `Time.timeScale`. For pause-menu cutscenes.
  - `DSP Clock` — audio sample clock. When audio sync is critical.
  - `Manual` — call `director.Evaluate()` yourself.
- **Play On Awake** — auto-play on scene load.
- **Wrap Mode**:
  - `Hold` — clamp at end frame.
  - `Loop` — restart.
  - `None` — clear bindings on end (Animator stops driving).
- **Initial Time** — start offset.
- **Bindings** — each track's required scene object (Animator, AudioSource, signal receiver, etc.). Set in inspector or via `director.SetGenericBinding(track, obj)`.

Runtime API: `director.Play()`, `Stop()`, `Pause()`, `time`, `duration`, `played` event.

## Track types

| Track          | Binding type                  | Drives                                           |
| -------------- | ----------------------------- | ------------------------------------------------ |
| Activation     | GameObject                    | SetActive(true) across the clip range            |
| Animation      | Animator                      | AnimationClip(s) — overrides Animator graph      |
| Audio          | AudioSource                   | AudioClip(s)                                     |
| Cinemachine    | CinemachineBrain (or Camera)  | virtual camera blends                            |
| Signal         | any GO with SignalReceiver    | one-shot SignalAsset events at marker times     |
| Control        | GO with PlayableDirector or PS| nested Timeline / particle emit window           |
| Custom         | depends on PlayableAsset      | bespoke `ScriptPlayable<T>`                      |

## Animation track specifics

- Track Offsets:
  - **Apply Track Offset** — track has its own root offset (position a humanoid in the cutscene without moving the character GO).
  - **Apply Scene Offset** — clip plays in the bound Animator's current scene position.
  - **Auto** — heuristic; often wrong; pick explicitly.
- **Override Animator State** — track ignores the Animator Controller graph during playback.
- Recording — record button on the track keys transform values at the current playhead.

## Signals

1. Create a `SignalAsset` (`Assets > Create > Signal`).
2. On Timeline, add a Signal Track (or place a Signal Emitter on any track via right-click).
3. Drag SignalAsset onto the marker; set its time.
4. On the receiver GO, add `SignalReceiver`. Map `SignalAsset → UnityEvent`.

Use signals for "spawn enemies here", "fade music", "enable input", "show subtitle X" — anything that sits between cutscene timing and gameplay state.

## Edit-mode preview

Timeline previews scrub in edit mode without entering Play. Validate poses, audio sync, camera framing before runtime testing.

Caveat: AnimationEvents on clips embedded in Animation tracks fire only in Play mode, not during scrub.

## Common patterns

- **Boss intro** — Activation track shows boss model, Animation track plays intro, Cinemachine track frames camera, Audio track plays sting, Signal track at end fires "enable boss AI".
- **Door open scripted** — Animation track on door, Audio for hinge SFX, Signal at end to enable next room's nav mesh.
- **Title screen** — looping Timeline with Cinemachine track for slow camera dolly, Audio for ambient music.

## Cross-link

`unity-cinemachine` — most cinematic Timelines lean on Cinemachine track + virtual cameras with priority-based blends.

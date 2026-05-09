# Timeline reference

Package: `com.unity.timeline` (install via the package manager if absent).

Window: `Window > Sequencing > Timeline`.

Asset extension: `.playable` (technically a `TimelineAsset`).

## PlayableDirector

Component on a GameObject in the scene; binds tracks in the Timeline asset to scene objects.

Fields:

- **Playable** — the TimelineAsset to play.
- **Update Method**:
  - `Game Time` (default) — uses `Time.deltaTime`. Affected by `Time.timeScale`.
  - `Unscaled Game Time` — ignores `Time.timeScale`. Use for pause-menu cutscenes.
  - `DSP Clock` — audio sample clock. Use when audio sync is critical.
  - `Manual` — you call `director.Evaluate()` yourself.
- **Play On Awake** — auto-plays when scene loads.
- **Wrap Mode**:
  - `Hold` — clamp at end frame.
  - `Loop` — restart.
  - `None` — clear bindings on end (the Animator's Animator stops driving).
- **Initial Time** — start offset.
- **Bindings** — each track's required scene object (Animator, AudioSource, GameObject, signal receiver, etc.). Set in inspector or via `director.SetGenericBinding(track, obj)`.

Runtime API: `director.Play()`, `director.Stop()`, `director.Pause()`, `director.time`, `director.duration`, `director.played` event.

## Track types

| Track          | Binding type                  | Drives                                           |
| -------------- | ----------------------------- | ------------------------------------------------ |
| Activation     | GameObject                    | SetActive(true) across the clip range            |
| Animation      | Animator                      | AnimationClip(s) — overrides Animator graph      |
| Audio          | AudioSource                   | AudioClip(s)                                     |
| Cinemachine    | CinemachineBrain (or Camera)  | virtual camera blends                            |
| Signal         | (any GameObject with SignalReceiver) | one-shot SignalAsset events at marker times |
| Control        | GameObject (with PlayableDirector or ParticleSystem) | nested Timeline / particle emit window |
| Custom         | depends on the PlayableAsset  | bespoke `ScriptPlayable<T>` behavior             |

## Animation track specifics

- Track Offsets:
  - **Apply Track Offset** — track has its own root offset (use for positioning a humanoid in the cutscene without moving the character GameObject).
  - **Apply Scene Offset** — clip plays in the bound Animator's current scene position.
  - **Auto** — heuristic; often wrong; pick explicitly.
- **Override Animator State** — track ignores the Animator Controller graph during playback.
- Recording — record button on the track lets you key transform values at the current playhead.

## Signals

1. Create a `SignalAsset` (`Assets > Create > Signal`).
2. On a Timeline, add a Signal Track (or place a Signal Emitter on any track via right-click).
3. Drag the SignalAsset onto the marker; set its time.
4. On the receiver GameObject, add `SignalReceiver` component. Map `SignalAsset → UnityEvent`.

Use signals for: "spawn enemies here", "fade music", "enable input", "show subtitle X" — anything that sits between cutscene timing and gameplay state.

## Edit-mode preview

Timeline previews scrub in edit mode without entering Play. Drag the playhead to validate poses, audio sync, camera framing before runtime testing.

Caveat: AnimationEvents on clips embedded in Animation tracks fire only in Play mode, not during scrub.

## Common patterns

- **Boss intro** — Activation track shows boss model, Animation track plays intro anim, Cinemachine track frames the camera, Audio track plays sting, Signal track at end fires "enable boss AI".
- **Door open scripted** — Animation track on the door, Audio track for hinge SFX, Signal at end to enable the next room's nav mesh.
- **Title screen** — looping Timeline with Cinemachine track for slow camera dolly, Audio for ambient music.

## Cross-link

`unity-cinemachine` — most cinematic Timelines lean heavily on Cinemachine track + virtual cameras with priority-based blends.

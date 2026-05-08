---
name: unity-cinemachine
description: Use when authoring or tuning Unity Cinemachine cameras through Unity MCP — Cinemachine, CinemachineCamera, CinemachineVirtualCamera, virtual camera, vcam, CinemachineBrain, camera blend, follow target, look at target, dolly track, FreeLook, Free Look camera, third person camera, framing transposer, Position Composer, Rotation Composer, Cinemachine noise, screen shake, impulse, CinemachineImpulseSource, CinemachineImpulseListener, dolly cart, spline cart, CinemachineSplineCart, smart camera, priority, blend list, state-driven camera, Cinemachine Confiner, ClearShot. Unity 6 / Cinemachine 3.x, URP-only, new Input System only. For Animator state machines, AnimationEvents, blend trees, or non-camera Timeline tracks, use unity-animation.
---

## When to use

Any task that places a smart camera in the scene: third-person follow camera, top-down camera, FPS camera with smoothing, side-scroller camera with level bounds, cinematic dolly flythrough, screen shake on impact, multi-camera priority blends (gameplay vs menu vs aim), cutscene camera animation through Timeline, look-at character with dead zones / soft zones. If the user is hand-rolling `transform.position = ...` on the Main Camera every frame, suggest a CinemachineCamera instead unless they specifically need frame-locked control (e.g. a competitive FPS).

## Cinemachine 3.x vs legacy 2.x

Unity 6 ships **Cinemachine 3.x**. The architecture changed; most online tutorials are 2.x. Translate names mentally:

- 2.x `CinemachineVirtualCamera` (one component with inline Body/Aim modules) → 3.x **`CinemachineCamera`** (component) plus **separate sibling components** for procedural behavior.
- 2.x inline `Body = Framing Transposer` → 3.x add `CinemachinePositionComposer` component.
- 2.x inline `Aim = Composer` → 3.x add `CinemachineRotationComposer` component.
- 2.x `FreeLook` rig → 3.x `CinemachineOrbitalFollow` component (single CinemachineCamera, no 3-rig structure).
- 2.x `Collider` extension → 3.x `CinemachineDeoccluder`.
- 2.x `CinemachineDollyCart` → 3.x `CinemachineSplineCart`.

2.x is still supported for legacy projects but is frozen. Write all new content for 3.x. When `unity_reflect` shows a `CinemachineVirtualCamera` already in-scene, the project is on 2.x; do not mix paradigms.

## Package install

`manage_packages` add `com.unity.cinemachine`. Cinemachine 3.x also depends on `com.unity.splines` for SplineDolly. Once installed, Unity adds the `Cinemachine > ...` menu (use `execute_menu_item` to spawn a CinemachineCamera fast).

## CinemachineBrain

A `CinemachineBrain` component on the **Main Camera** is what actually moves the Camera transform. Without a Brain, CinemachineCameras present in the scene have no effect on the rendered view.

- **Default Blend** — how to transition between active vcams: `Cut`, `EaseInOut`, `EaseIn`, `EaseOut`, `Linear`, `Custom` (animation curve), with a `Time` in seconds.
- **Custom Blends** — slot for a `CinemachineBlenderSettings` asset that maps `(FromCam, ToCam)` pairs to specific curves and durations. If the asset is empty or unassigned, Default Blend wins.
- **Update Method** — `SmartUpdate` (recommended), `FixedUpdate` (use when Follow target is a Rigidbody to avoid jitter), `LateUpdate`, `ManualUpdate`.
- **Blend Update Method** — same options, applied to the blend interpolation specifically.
- **Show Debug Text** — overlays the active vcam name and blend percentage in Game view.

## CinemachineCamera anatomy (3.x)

A GameObject with a `CinemachineCamera` component:

- **Priority** — higher wins. Ties broken by most recent activation.
- **Standby Update** — how often inactive vcams update their internal state (`Always`, `RoundRobin`, `Never`). `Never` is cheap but jumps on activation.
- **Lens** — FOV, near/far clip, dutch angle, ortho size. Overrides Main Camera's lens while active.
- **Follow** — Transform the body components track for position.
- **LookAt** — Transform the aim components rotate toward.

Attach procedural components as **siblings** on the same GameObject:

- `CinemachineFollow` — fixed offset from Follow target. Damping per axis.
- `CinemachineHardLockToTarget` — pin position exactly on target.
- `CinemachineOrbitalFollow` — orbital horizontal/vertical input around target (replaces 2.x FreeLook).
- `CinemachineThirdPersonFollow` — over-the-shoulder follow with shoulder offset, camera distance, aim/strafe support.
- `CinemachinePositionComposer` — 2D framing: holds target at a screen-space position with **Dead Zone** (no movement) and **Soft Zone** (damped catch-up). Replaces 2.x Framing Transposer.
- `CinemachineRotationComposer` — rotates camera so LookAt target stays in dead/soft zone. Replaces 2.x Composer.
- `CinemachineHardLookAt` — strict aim, no damping.
- `CinemachineSplineDolly` — slides camera along a Unity `SplineContainer`. Auto-dolly options track Follow target along the spline.
- `CinemachineDeoccluder` — pulls camera in toward target when geometry blocks the shot (renamed from 2.x Collider).
- `CinemachineConfiner2D` / `CinemachineConfiner3D` — clamp camera position inside a polygon / 3D collider volume.

## Common camera presets

- **Third-person follow**: `CinemachineCamera` + `CinemachineThirdPersonFollow` (Follow = player root) + `CinemachineRotationComposer` (LookAt = head bone).
- **Top-down**: `CinemachineCamera` + `CinemachineFollow` (offset Y high, Z = 0) + `CinemachineHardLookAt` or `CinemachineRotationComposer`.
- **Side-scroller**: `CinemachineCamera` + `CinemachinePositionComposer` (screen X/Y dead zone) + `CinemachineConfiner2D` for level bounds.
- **First-person**: `CinemachineCamera` + `CinemachineHardLockToTarget` parented under the player head bone. Note: many FPS games hand-roll the camera since FPS demands frame-locked control with no smoothing — use Cinemachine here only if a small amount of camera character is desired.
- **Cinematic dolly**: `CinemachineCamera` + `CinemachineSplineDolly` referencing a `SplineContainer`. Drive position via Auto-Dolly, a `CinemachineSplineCart`, or a Timeline track.
- **Orbital character viewer**: `CinemachineCamera` + `CinemachineOrbitalFollow` for character select, inventory, photo mode.

## Blends and priorities

- Higher Priority wins. To swap cameras at runtime, raise the new camera's Priority above the current. The Brain interpolates per Default/Custom blend.
- `CinemachineBlenderSettings` asset: `Create > Cinemachine > Blender Settings`. Add per-pair entries naming the From and To vcams. Drop the asset on Brain's Custom Blends slot. Without that drop, the per-pair config does nothing.
- Special From/To names: `**ANY CAMERA**` matches any vcam.

## Noise and screen shake (Impulse)

- **Continuous shake** (handheld feel): add `CinemachineBasicMultiChannelPerlin` to the vcam, assign a `NoiseSettings` profile asset, set Amplitude/Frequency. Built-in `6D Shake` and `Handheld_normal_*` profiles ship with Cinemachine.
- **One-shot impacts** (Impulse system):
  1. Put `CinemachineImpulseSource` on the impactor (e.g. on the explosion prefab, the foot at footstep, the bullet impact).
  2. Add `CinemachineImpulseListener` to each receiving CinemachineCamera.
  3. Call `impulseSource.GenerateImpulseAt(position, velocity)` from gameplay code.
  4. Tune the source's Impulse Definition: shape (Bump/Recoil/Rumble), duration, dissipation distance, propagation speed, amplitude/frequency gain.
  5. **Channels** (bitmask): set Source's Channel and Listener's Channel Mask. Cameras only react to sources whose channel is in their mask — useful for splitting "small impact only" vs "big quake only" vs "player-only effects".

## Dolly tracks and carts

3.x uses Unity Splines (`com.unity.splines`):

1. Create a `SplineContainer` GameObject; edit knots in Scene view.
2. Add `CinemachineSplineDolly` to the vcam, reference the SplineContainer, set Camera Position 0..1 along the spline.
3. **Auto Dolly** modes: `None` (manual position), `FollowTargetOnSpline` (camera slides to closest spline point to Follow target), or `FixedSpeed`.
4. For driven motion, add a `CinemachineSplineCart` (as a separate GameObject) that animates a Position parameter along the same spline, then point a CinemachineCamera at the cart as Follow target.

## ClearShot and state-driven cameras

- **`CinemachineClearShot`** — a parent GameObject with multiple child CinemachineCameras. Picks the child with the best shot quality (no obstructions) using each child's `CinemachineDeoccluder` shot-quality evaluation. Useful for action where the player camera might wall-clip — provides three angles, picks whichever has line-of-sight.
- **`CinemachineStateDrivenCamera`** — bound to an Animator. Maps Animator states to child CinemachineCameras. When the Animator enters `Run`, the Run vcam activates; on `Idle`, the Idle vcam takes over. Cross-link `unity-animation` for the Animator side.

## Confiner

- **`CinemachineConfiner2D`** — references a `CompositeCollider2D` polygon (NOT individual Box/Polygon Colliders by themselves). Camera position is clamped to stay inside. Click **Bake** in the inspector after editing the collider; this caches the confiner shape including sub-shapes for runtime performance. Re-bake whenever the collider geometry changes.
- **`CinemachineConfiner3D`** — references any 3D Collider acting as a volume. No bake step.

## Timeline integration

- Add a Cinemachine track to a Timeline. Drag CinemachineCameras as clips. Gaps between clips = the prior clip continues; overlaps = blends, with the overlap duration controlling blend time. The Cinemachine track raises priority on the active clip's vcam through the Brain.
- Use Timeline for cinematic flythroughs, intro shots, and scripted boss-intro cameras. Cross-link `unity-animation`.

## Common patterns

- **Player camera with priority swap**: `PlayerCam` priority 10, `MenuCam` priority 5. On menu open, raise `MenuCam` to 20; Brain blends in. On close, drop back to 5.
- **Aim camera (ADS)**: second CinemachineCamera with tighter framing (lower FOV, closer offset). Toggle priority when the right-mouse Action fires.
- **Cinematic intro**: dolly camera plays via Timeline at scene start; on Timeline end, the gameplay vcam (priority 100 once enabled) wins and Brain blends.
- **Boss arena**: trigger volume raises `BossArenaCam` priority on enter, lowers on exit.
- **Hit shake**: damage handler calls `impulseSource.GenerateImpulse()` with a magnitude scaled to damage. All listening cameras get the shake.

## Gotchas

- Forgetting `CinemachineBrain` on Main Camera → cameras present, no visible effect. Always check this first.
- Multiple Brains in scene → undefined which one wins. One Brain per Camera; for split-screen, each Camera gets its own Brain with channel separation.
- Setting `Camera.transform` directly → Brain overwrites the next frame. Drive cameras through CinemachineCameras only.
- Following 2.x tutorials blindly: 3.x renamed and split components. `CinemachineVirtualCamera` does not exist in 3.x.
- Custom Blends asset edited but **not assigned** to Brain's Custom Blends slot → Default Blend used regardless.
- High `BasicMultiChannelPerlin` amplitude on continuous shake → motion sickness. Tune low; reserve big shakes for one-shot Impulse.
- `Update Method = FixedUpdate` is needed when Follow is a Rigidbody (else jitter), but desyncs from non-physics targets. Pick per-Brain to match the dominant target type, or split into two cameras with different update methods.
- `CinemachineConfiner2D` requires a `CompositeCollider2D` (not bare Box/Polygon Colliders), and the **Bake** step is mandatory at edit time.
- Cinemachine does not drive Canvas UI cameras. UI overlay rendering is separate.
- `CinemachineCamera.Priority` is an `int`; activation is non-deterministic when two cameras share the same value — give every vcam a unique priority.

## Verification

- Enter Play mode (only with user permission). Toggle the trigger that activates each vcam; confirm transitions match priority intent.
- Enable `Show Debug Text` on the Brain to see the active vcam name and blend percentage on screen.
- `read_console` for warnings: "CinemachineBrain has no Camera", "No active CinemachineCamera", missing Follow / LookAt.
- For cinematic Timeline shots, scrub the Timeline preview in Edit mode; Cinemachine respects scrub in-editor.
- After authoring a follow camera, cross-link `unity-3d-verification` for a 4-shot orthographic capture of the camera-target framing to confirm shoulder offset and dead-zone placement.
- Cross-link `unity-animation` for Timeline / StateDrivenCamera, `unity-best-practices` for the always-read-the-console / detect-pipeline-first rules.

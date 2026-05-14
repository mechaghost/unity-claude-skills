---
name: unity-cinemachine
description: 'Use for Unity 6+ Cinemachine 3.x cameras: CinemachineCamera/vcam/Brain, blends, follow/look-at, FreeLook/third-person framing, composers, noise/screen shake/Impulse, dolly/spline carts, Confiner, ClearShot, state-driven cameras. Not non-camera animation.'
---

## When to use

Smart camera in scene: third-person follow, top-down, FPS with smoothing, side-scroller with level bounds, cinematic dolly, screen shake on impact, multi-camera priority blends (gameplay vs menu vs aim), Timeline cutscenes, look-at character with dead/soft zones. If hand-rolling `transform.position = ...` on Main Camera every frame, suggest a CinemachineCamera unless frame-locked control is needed (competitive FPS).

## Cinemachine 3.x is the only supported version

Unity 6 ships **Cinemachine 3.x** — only version covered. 2.x is frozen upstream and not validated. Most blogs predate the 3.x split; use this rename table to translate:

- 2.x `CinemachineVirtualCamera` (one component, inline Body/Aim) → 3.x **`CinemachineCamera`** + **separate sibling components**.
- 2.x inline `Body = Framing Transposer` → 3.x `CinemachinePositionComposer`.
- 2.x inline `Aim = Composer` → 3.x `CinemachineRotationComposer`.
- 2.x `FreeLook` rig → 3.x `CinemachineOrbitalFollow` (single CinemachineCamera, no 3-rig).
- 2.x `Collider` → 3.x `CinemachineDeoccluder`.
- 2.x `CinemachineDollyCart` → 3.x `CinemachineSplineCart`.

If reflecting on the scene shows `CinemachineVirtualCamera`, project is on 2.x — stop and warn. Finish a 2.x→3.x upgrade (Window → Cinemachine → Upgrade Manager) first.

## Package install

`com.unity.cinemachine`. 3.x also depends on `com.unity.splines` for SplineDolly. After install, drive the `Cinemachine > ...` menu to spawn cameras fast.

## CinemachineBrain

A `CinemachineBrain` on the **Main Camera** is what actually moves the Camera transform. Without a Brain, CinemachineCameras have no effect.

- **Default Blend** — `Cut`, `EaseInOut`, `EaseIn`, `EaseOut`, `Linear`, `Custom` (animation curve), with `Time` in seconds.
- **Custom Blends** — slot for `CinemachineBlenderSettings` mapping `(FromCam, ToCam)` pairs to curves and durations. Empty/unassigned → Default Blend wins.
- **Update Method** — `SmartUpdate` (recommended, including Rigidbody targets), `FixedUpdate`, `LateUpdate`, `ManualUpdate`. For Rigidbody Follow targets, keep Brain on `SmartUpdate` and set `Rigidbody.interpolation = Interpolate` on the target — that's what kills jitter. Switching the Brain to `FixedUpdate` while interpolation is on can actually *introduce* jitter (camera samples on the physics step boundary while the visual is interpolated forward).
- **Blend Update Method** — same options for blend interpolation.
- **Show Debug Text** — overlays active vcam name + blend percentage.

## CinemachineCamera anatomy (3.x)

GameObject with `CinemachineCamera`:

- **Priority** — higher wins. Ties broken by most recent activation.
- **Standby Update** — how often inactive vcams update (`Always`, `RoundRobin`, `Never`). `Never` is cheap but jumps on activation.
- **Lens** — FOV, near/far clip, dutch angle, ortho size. Overrides Main Camera's lens while active.
- **Follow** — Transform body components track for position.
- **LookAt** — Transform aim components rotate toward.

Procedural components as **siblings**:

- `CinemachineFollow` — fixed offset from Follow target. Per-axis damping.
- `CinemachineHardLockToTarget` — pin position exactly on target.
- `CinemachineOrbitalFollow` — orbital horizontal/vertical input around target (replaces 2.x FreeLook).
- `CinemachineThirdPersonFollow` — over-the-shoulder follow with shoulder offset, distance, aim/strafe. **Character-tuned** (humanoid third-person, strafe shooters); don't use for vehicles — the shoulder offset and strafe behavior produce harsh, jittery framing. Use `CinemachineFollow` for vehicles.
- `CinemachinePositionComposer` — 2D framing: target at screen-space position with **Dead Zone** (no movement) + **Soft Zone** (damped catch-up). Replaces 2.x Framing Transposer.
- `CinemachineRotationComposer` — rotates camera so LookAt target stays in dead/soft zone. Replaces 2.x Composer.
- `CinemachineHardLookAt` — strict aim, no damping.
- `CinemachineSplineDolly` — slides camera along a `SplineContainer`. Auto-dolly options track Follow target along the spline.
- `CinemachineDeoccluder` — pulls camera toward target when geometry blocks the shot.
- `CinemachineConfiner2D` / `CinemachineConfiner3D` — clamp position inside a polygon / 3D collider.

## Common camera presets

- **Third-person follow**: `CinemachineCamera` + `CinemachineThirdPersonFollow` (Follow = player root) + `CinemachineRotationComposer` (LookAt = head bone).
- **Top-down**: `CinemachineCamera` + `CinemachineFollow` (offset Y high, Z=0) + `CinemachineHardLookAt` or `CinemachineRotationComposer`.
- **Side-scroller**: `CinemachineCamera` + `CinemachinePositionComposer` (screen X/Y dead zone) + `CinemachineConfiner2D` for level bounds.
- **First-person**: `CinemachineCamera` + `CinemachineHardLockToTarget` parented under player head bone. Many FPS games hand-roll the camera (frame-locked, no smoothing) — use Cinemachine here only for a small amount of camera character.
- **Cinematic dolly**: `CinemachineCamera` + `CinemachineSplineDolly` referencing a `SplineContainer`. Drive position via Auto-Dolly, `CinemachineSplineCart`, or Timeline track.
- **Orbital character viewer**: `CinemachineCamera` + `CinemachineOrbitalFollow` for character select, inventory, photo mode.
- **Vehicle chase**: `CinemachineCamera` + `CinemachineFollow` (offset above and behind, e.g. Y≈3, Z≈-7) + `CinemachineHardLookAt`. Target a `CameraLookTarget` empty parented to the vehicle, offset slightly above and ahead of center (the chassis pivot is usually too low). Set `CinemachineFollow.TrackerSettings.BindingMode = LockToTargetWithWorldUp` — `LazyFollow` drifts, `WorldSpace` locks to world axes and won't track the vehicle's heading. For a reverse camera, mirror Z offset and swap priority via script. Do **not** use `CinemachineThirdPersonFollow` (character-only) or `CinemachineRotationComposer` (its `ScreenPosition` fights `CinemachineFollow` when the camera is above the target — see Gotchas).

## Blends and priorities

- Higher Priority wins. To swap at runtime, raise the new camera's Priority. Brain interpolates per Default/Custom blend.
- `CinemachineBlenderSettings` asset: `Create > Cinemachine > Blender Settings`. Add per-pair entries naming From/To vcams. Drop on Brain's Custom Blends slot. Without that drop, per-pair config does nothing.
- Special From/To names: `**ANY CAMERA**` matches any vcam.

## Noise and screen shake (Impulse)

- **Continuous shake** (handheld feel): add `CinemachineBasicMultiChannelPerlin`, assign a `NoiseSettings` profile, set Amplitude/Frequency. Built-in `6D Shake` and `Handheld_normal_*` profiles ship with Cinemachine.
- **One-shot impacts** (Impulse system):
  1. `CinemachineImpulseSource` on the impactor (explosion prefab, foot at footstep, bullet impact).
  2. `CinemachineImpulseListener` on each receiving CinemachineCamera.
  3. Call `impulseSource.GenerateImpulseAt(position, velocity)` from gameplay code.
  4. Tune source's Impulse Definition: shape (Bump/Recoil/Rumble), duration, dissipation distance, propagation speed, amplitude/frequency gain.
  5. **Channels** (bitmask): set Source's Channel + Listener's Channel Mask. Cameras only react to sources in their mask — splits "small impact" vs "big quake" vs "player-only".

## Dolly tracks and carts

3.x uses Unity Splines (`com.unity.splines`):

1. Create `SplineContainer`; edit knots in Scene view.
2. `CinemachineSplineDolly` on the vcam, reference SplineContainer, set Camera Position 0..1.
3. **Auto Dolly**: `None` (manual), `FollowTargetOnSpline` (camera slides to closest spline point to Follow target), `FixedSpeed`.
4. For driven motion: `CinemachineSplineCart` (separate GO) animating along the same spline; vcam Follow = cart.

## ClearShot and state-driven cameras

- **`CinemachineClearShot`** — parent GO with multiple child CinemachineCameras. Picks the child with best shot quality (no obstructions) using each child's `CinemachineDeoccluder` shot-quality eval. Useful when player camera might wall-clip — provides three angles, picks line-of-sight winner.
- **`CinemachineStateDrivenCamera`** — bound to an Animator. Maps Animator states to child CinemachineCameras. `Run` state → Run vcam, `Idle` → Idle vcam. See `unity-animation`.

## Confiner

- **`CinemachineConfiner2D`** — references a `CompositeCollider2D` polygon (NOT bare Box/Polygon). Clamps position. Click **Bake** in inspector after editing collider; caches confiner shape including sub-shapes for runtime perf. Re-bake on geometry changes.
- **`CinemachineConfiner3D`** — any 3D Collider as volume. No bake step.

## Timeline integration

Add a Cinemachine track. Drag CinemachineCameras as clips. Gaps = prior clip continues; overlaps = blends with overlap duration controlling blend time. Cinemachine track raises priority on the active clip's vcam through the Brain.

Use Timeline for cinematic flythroughs, intro shots, scripted boss-intro cameras. See `unity-animation`.

## Common patterns

- **Player camera with priority swap**: `PlayerCam` priority 10, `MenuCam` priority 5. On menu open, raise `MenuCam` to 20; Brain blends in. On close, drop back to 5.
- **Aim camera (ADS)**: second CinemachineCamera with tighter framing (lower FOV, closer offset). Toggle priority on right-mouse.
- **Cinematic intro**: dolly camera plays via Timeline at scene start; on Timeline end, gameplay vcam (priority 100) wins.
- **Boss arena**: trigger volume raises `BossArenaCam` priority on enter, lowers on exit.
- **Hit shake**: damage handler calls `impulseSource.GenerateImpulse()` with magnitude scaled to damage. All listening cameras shake.

## Gotchas

- Forgetting `CinemachineBrain` on Main Camera → cameras present, no visible effect. Check first.
- Multiple Brains in scene → undefined which wins. One Brain per Camera; for split-screen, each Camera gets its own Brain with channel separation.
- Setting `Camera.transform` directly → Brain overwrites next frame. Drive cameras through CinemachineCameras only.
- Following 2.x tutorials: Unity 6 ships 3.x with renamed/split components. `CinemachineVirtualCamera` doesn't exist in 3.x — translate via rename table.
- Custom Blends asset edited but **not assigned** to Brain's Custom Blends slot → Default Blend used regardless.
- High `BasicMultiChannelPerlin` amplitude on continuous shake → motion sickness. Tune low; reserve big shakes for one-shot Impulse.
- `Update Method = FixedUpdate` is **not** the right fix for Rigidbody-follow jitter — set `Rigidbody.interpolation = Interpolate` on the target instead and keep the Brain on `SmartUpdate`. Switch the Brain to `FixedUpdate` only if you genuinely cannot enable Rigidbody interpolation; it desyncs from non-physics targets.
- Old hand-rolled camera scripts on the Main Camera (anything writing `transform.position`/`transform.rotation` in Update/LateUpdate) fight `CinemachineBrain` every frame, producing jitter that's easy to misdiagnose as a Cinemachine setting. Before adding the Brain, audit Main Camera for any such MonoBehaviour and remove or disable it — exactly one writer.
- `CinemachineFollow.TrackerSettings` is a struct exposed as a property *named the same as the type*. Writing `follow.TrackerSettings.BindingMode = ...` fails to compile because `TrackerSettings` resolves to the type, not the property. Copy the struct, mutate, reassign: `var t = follow.TrackerSettings; t.BindingMode = BindingMode.LockToTargetWithWorldUp; follow.TrackerSettings = t;` — or drive it via `SerializedObject`.
- `CinemachineRotationComposer.ScreenPosition` is unintuitive when the camera is above the target. Lowering screen-space Y (e.g. to put the subject in the lower third) tilts the camera *upward*, because the composer rotates so the target lands at that screen position. For follow cameras sitting above the target, prefer `CinemachineHardLookAt` — predictable, and it won't fight `CinemachineFollow`.
- `CinemachineConfiner2D` requires `CompositeCollider2D`; **Bake** is mandatory at edit time.
- Cinemachine doesn't drive Canvas UI cameras. UI overlay rendering is separate.
- `CinemachineCamera.Priority` is `int`; activation is non-deterministic when two share the same value — give every vcam a unique priority.

## Verification

- Enter Play mode (with user permission). Toggle the trigger activating each vcam; confirm transitions match priority.
- Enable `Show Debug Text` on the Brain to see active vcam name + blend percentage.
- Editor console clean of "CinemachineBrain has no Camera", "No active CinemachineCamera", missing Follow/LookAt warnings.
- Cinematic Timeline shots: scrub Timeline preview in Edit mode; Cinemachine respects scrub.
- Follow camera: cross-link `unity-3d-verification` for a 4-shot orthographic of camera-target framing to confirm shoulder offset and dead-zone placement.
- See `unity-animation` for Timeline / StateDrivenCamera, `unity-best-practices` for the always-read-the-console / detect-pipeline-first rules.

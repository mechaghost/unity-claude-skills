---
name: unity-animation
description: 'Use for Unity 6+ animation: Animator/AnimationClip/controllers, states/transitions/parameters/blend trees/layers/masks, root motion, AnimationEvents, generic/humanoid retargeting, Animation Rigging IK/constraints, Timeline/PlayableDirector/signals. Use Cinemachine for camera blends.'
---

## When to use

Character locomotion, attacks, Animator-driven UI, Timeline cutscenes, IK leg planting, humanoid retargeting, blend trees, layered upper/lower body, AnimationEvent wiring (footsteps, hitboxes). Animation Rigging constraints, Animator Override Controllers.

Pure transform tweens (UI fades, scale pops, slides) — Animator is overkill.

## Animator vs scripted

| Animator                       | Code / DOTween / coroutine        |
| ------------------------------ | --------------------------------- |
| Complex blends, state graphs   | Linear transform tween            |
| Layered upper/lower body, masks| Single-property fade/slide        |
| Root motion locomotion         | UI alpha/position over time       |
| Retargeted humanoid clips      | Camera/screen shake               |
| Authoring pipeline (FBX clips) | One-off effects, no asset deps    |

Animator overhead per object is non-trivial (graph eval, parameter map, transition checks every frame). Reserve for content-authored animation; tween library for code-driven motion.

## Animator Controller anatomy

A `.controller` asset holds:

- **State machines** (base layer + sub-state machines).
- **States** — AnimationClip, Blend Tree, or sub-state machine. Speed, Motion, Write Defaults, Foot IK (humanoid), Mirror, Cycle Offset, transitions.
- **Transitions** — directed edges with conditions, Has Exit Time, Transition Duration, Offset, Interruption Source, Can Transition To Self.
- **Parameters** — global Float / Int / Bool / Trigger.
- **Layers** — independent state machines blended into the final pose; layer 0 is base.

Create the controller and assign to `Animator.runtimeAnimatorController`. Edit graph topology with Animator/Timeline tooling.

## Generic vs Humanoid rigs

| Rig          | Use for                          | Retarget | IK  | Notes                                                  |
| ------------ | -------------------------------- | -------- | --- | ------------------------------------------------------ |
| **Humanoid** | bipedal characters               | yes      | yes | Avatar maps source bones to Unity standard skeleton    |
| **Generic**  | animals, vehicles, robots, props | no       | no  | Specify root bone for root motion                      |
| **Legacy**   | —                                | —        | —   | Ancient `Animation` component. Do not use.             |

Humanoid retargeting maps muscles, not raw bones — proportions shift between skeletons. Broken retarget (twisted limb, sunken hip): fix bone mappings in FBX importer Avatar > Configure.

Rig type on FBX importer Rig tab; create controller + Avatar as new assets.

## Parameters and transitions

Parameter types:

- **Float** — `SetFloat("Speed", v)`. Blend tree axes, speed scales.
- **Int** — `SetInteger("AttackId", n)`. Discrete state selection.
- **Bool** — `SetBool("IsGrounded", b)`. Sustained binary state.
- **Trigger** — `SetTrigger("Jump")`. Auto-resets after consumed. One-shot events.

Hot-path: cache parameter ids with `Animator.StringToHash("Speed")` and reuse the int.

Transition fields:
- **Conditions** — parameter comparisons. All must be true to fire.
- **Has Exit Time** — ON: only fires after source plays past N normalized time. OFF: fires when conditions met. Common cause of "trigger fires but transition delayed".
- **Transition Duration** — blend overlap (seconds or normalized).
- **Interruption Source** — whether higher-priority transitions can interrupt mid-blend.

Best practice: PascalCase parameter names, consistent transition naming, hand-drawn diagram for any controller >10 states.

## Blend trees

| Type                        | Use for                                           |
| --------------------------- | ------------------------------------------------- |
| **1D**                      | idle ↔ walk ↔ run on Speed                        |
| **2D Simple Directional**   | 8-way locomotion on (MoveX, MoveY)                |
| **2D Freeform Cartesian**   | stick-driven locomotion, irregular sample layout  |
| **2D Freeform Directional** | locomotion with strafe + back; samples on circle  |
| **Direct**                  | explicit per-clip blend weight; advanced (face)   |

Locomotion workhorse: 2D Freeform Cartesian on (MoveX, MoveZ) — sample idle (0,0), walk at cardinals, run at corners.

## Layers and avatar masks

- Layer 0 base; higher layers add or override.
- **Layer Weight** 0..1 controls influence: `animator.SetLayerWeight(1, 0.8f)`.
- **Blending Mode**: `Override` (replace) or `Additive` (add to base).
- **Avatar Mask** — per-bone include/exclude. Classic case: "Upper Body" mask on aim/shoot layer so it doesn't disturb leg locomotion.

Create AvatarMask, check bones in Humanoid/Transform tab, assign to layer.

## Root motion

Animator's **Apply Root Motion** makes animation drive Transform.

- **In-place anim + scripted movement** — preferred for player characters. More control over speed, deceleration, ground snap.
- **Root motion** — cinematic NPCs, ridable characters, mocap-heavy where the artist authored the locomotion curve.
- **`OnAnimatorMove()`** — callback on Animator's GameObject. Intercepts root motion to a Rigidbody or CharacterController instead of Transform. When this method exists, Apply Root Motion routes through it.

Anti-pattern: Apply Root Motion ON + `CharacterController.Move(scriptedDelta)` = double speed.

## AnimationEvent

Method-by-name call on a MonoBehaviour at clip times. Optional Float/Int/String/Object parameter.

- Hand-authored `.anim`: clip → Animation window → event marker icon at frame → function name.
- FBX-imported: FBX importer → Animation tab → expand clip → Events. NOT the `.anim` subasset.
- Receiver MUST be on the Animator's GameObject.

Common uses: footstep SFX (`unity-audio`), hitbox enable/disable on attack frames (`unity-physics`), projectile spawn, camera shake.

Unity logs `AnimationEvent has no receiver` when method missing/misspelled.

## IK and Animation Rigging

**Built-in Humanoid IK** — `OnAnimatorIK(int layer)` on a MonoBehaviour on the Animator's GameObject:

```csharp
void OnAnimatorIK(int layer) {
    animator.SetIKPositionWeight(AvatarIKGoal.LeftHand, ikWeight);
    animator.SetIKPosition(AvatarIKGoal.LeftHand, target.position);
    animator.SetIKRotationWeight(AvatarIKGoal.LeftHand, ikWeight);
    animator.SetIKRotation(AvatarIKGoal.LeftHand, target.rotation);
}
```

State must have **IK Pass** enabled (per-layer). Use sparingly — hand-on-railing, foot-on-step.

**Animation Rigging package** (`com.unity.animation.rigging`) — modern constraint-based overlay. Add a `Rig` component on a child of the Animator, then constraints under it:

| Constraint              | Use for                                       |
| ----------------------- | --------------------------------------------- |
| `TwoBoneIKConstraint`   | foot IK on knee, hand IK on elbow             |
| `MultiAimConstraint`    | aim chest/head at target                      |
| `ChainIKConstraint`     | tail / tentacle / spine that follows tip      |
| `OverrideTransform`     | force a bone to specific pose post-anim       |
| `BoneRenderer`          | debug gizmo — assign Skeleton bones array     |

Use for: aim layers, foot IK with terrain raycast, secondary-hand grip, prop attachment to a hand bone.

Bone Renderer: gizmo shows nothing if `Transforms` array is empty.

## AnimationClip authoring

- **FBX-imported** — rig + clip ranges on FBX importer Animation tab. Loop pose, root motion baking (Bake Into Pose for X/Y/Z position and rotation), avatar mask per clip.
- **Hand-authored** — `Window > Animation > Animation`, select GameObject, Record, change properties to keyframe. Creates `.anim` + Animator + controller if missing.

Hand-author: UI panels, props, simple gameplay timing curves. Import: any character animation — Maya/Blender + retarget to humanoid.

`Optimize Game Objects` (FBX importer Rig tab) strips bone Transforms at runtime — breaks `GetComponentsInChildren<Transform>()`. Whitelist needed bones in **Extra Transforms to Expose**.

See `references/clips-and-import.md` for FBX import fields.

## Animator Override Controller

Swaps individual clips while keeping graph (states, transitions, parameters, layers, masks) identical. One base "Humanoid" controller + per-character overrides swap attacks/idles — saves duplicating the graph.

Create Override Controller, set `Controller` field to base, replace clips. Assign as `Animator.runtimeAnimatorController`.

## Timeline

`com.unity.timeline`. `Window > Sequencing > Timeline`. Asset = `.playable`; played by a `PlayableDirector`.

Tracks:

| Track          | Drives                                              |
| -------------- | --------------------------------------------------- |
| Activation     | toggles a GameObject on/off across a range          |
| Animation      | drives an Animator (clips + writes Transform)       |
| Audio          | plays an AudioSource                                |
| Cinemachine    | blends between virtual cameras (`unity-cinemachine`)|
| Signal         | fires SignalReceiver UnityEvents at marked times    |
| Control        | nests a Timeline or controls a ParticleSystem       |
| Custom         | `ScriptPlayable<T>` — bespoke behavior              |

Signals: `SignalEmitter` on a track at a time; `SignalReceiver` on target GO maps `SignalAsset → UnityEvent`. Good for cutscene-driven gameplay.

Use for: cutscenes, intros, boss intros, level transitions. Edit-mode scrubbing previews before runtime.

See `references/timeline.md` for track binding + PlayableDirector wrap modes.

## Common patterns

- **Locomotion blend tree** — 2D Freeform Cartesian on (MoveX, MoveZ); SetFloat from movement controller in Update.
- **Attack combo** — Trigger per attack; states A→B→C with Has Exit Time on the back half, conditions on the front; AnimationEvent on hit frame enables damage collider.
- **Aim layer** — avatar-masked upper body layer, weight 1 when aiming; MultiAimConstraint on chest pointing at aim target.
- **UI panel pop-in** — Animator with Idle/In/Out, SetTrigger("Open")/SetTrigger("Close"). Or DOTween for code-driven (fewer assets, simpler).
- **Cutscene** — Timeline with Animation track on hero, Cinemachine track for camera blends, Audio track for music, Signal track for gameplay events.

## Gotchas

- **Animator overwrites transforms** in its update phase. Manual transform writes in `Update` are lost. Fix: `LateUpdate` (after Animator) or Animation Rigging constraints.
- **Stuck triggers** — `SetTrigger` called every frame stays set; use `ResetTrigger` to clear.
- **Has Exit Time delays** — transition ignores conditions until exit time elapses. Disable for responsive input-driven transitions.
- **Self-transition** ("Can Transition To Self") restarts the state — useful for replaying a one-shot, but easy to set unintentionally.
- **Write Defaults** (per state) — ON: properties not animated reset to default; OFF: retain prior layer values. Inconsistency causes intermittent bugs (bone snapping). Pick a project-wide setting and keep all states matching.
- **Apply Root Motion + scripted movement** = double movement. Pick one.
- **Optimize Game Objects** strips bone Transforms — bone-finding code returns null. Expose needed bones explicitly.
- **AnimationEvent on FBX-imported clip** must be edited via FBX importer's Events panel, NOT on the `.anim` subasset (changes to subasset are wiped on reimport).
- **Sub-state machines nested >2 deep** — code smell. Refactor into layers or separate controllers.
- **Animator on disabled GameObject** — parameters can be set but animation doesn't advance until enabled.

## Verification

1. Editor console clean of `Animator does not have parameter 'X'` and `AnimationEvent has no receiver`.
2. Animator window in Play mode (Window > Animation > Animator) — observe transitions, parameters, active state highlights.
3. Frame-step an attack combo (Pause + Step) — confirm hitbox AnimationEvent fires on intended frame.
4. 3D characters → `unity-3d-verification` (4-shot orthographic) at key poses for bone deformation + prop attachment.
5. Timeline: scrub preview in Edit mode before Play.
6. IK / Animation Rigging: enable Gizmos, confirm rig effector handles align with target.

Cross-links: `unity-cinemachine`, `unity-audio` (footsteps), `unity-physics` (hitbox), `unity-3d-verification`, `unity-best-practices`.

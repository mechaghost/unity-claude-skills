---
name: unity-animation
description: 'Use when working with Unity animation through Unity MCP — Animator, AnimationClip, Animator Controller, state machine, animation state, transition, parameter, blend tree, Animator parameter, layer, avatar mask, IK, OnAnimatorIK, root motion, AnimationEvent, .anim, .controller, animator override controller, generic vs humanoid, Mecanim, Animation Rigging, Rig component, Bone Renderer, Two Bone IK, Multi-Aim Constraint, Timeline, PlayableDirector, signal, signal receiver, animation track, Cinemachine track, Activation track, animation bake, retarget. Unity 6+ / URP / new Input System. For Cinemachine-track-driven cinematics or virtual-camera blends, use unity-cinemachine.'
---

## When to use

Any animation work: character locomotion, attacks, UI animations driven by Animator, cutscenes via Timeline, IK leg planting, retargeting clips between humanoid skeletons, blend trees, layered upper/lower body, or AnimationEvent wiring (footsteps, hitboxes). Also covers Animation Rigging constraints (aim, two-bone IK, prop attach) and Animator Override Controllers.

For pure transform tweens (UI fades, simple scale pops, code-driven slides) the Animator is overkill — see "Animator vs scripted" below.

## Animator vs scripted animation

| Use Animator                                          | Use code / DOTween / coroutine                |
| ----------------------------------------------------- | --------------------------------------------- |
| Complex blends and state graphs                       | Simple linear transform tween                 |
| Layered upper/lower body, masks                       | Single-property fade or slide                 |
| Root motion driving locomotion                        | UI alpha/position over time                   |
| Retargeted humanoid clips                             | Camera shake, screen shake                    |
| Authoring tool / artist pipeline (FBX clips)          | One-off effects with no asset dependencies    |

Animator overhead per object is non-trivial (graph evaluation, parameter map, transition checks every frame). Don't put one on every UI panel "for consistency" — use a tween library for code-driven motion and reserve Animator for content-authored animation.

## Animator Controller anatomy

A `.controller` asset contains:

- **State machines** (the base layer machine plus any sub-state machines).
- **States** — each holds an AnimationClip, a Blend Tree, or a sub-state machine. Has Speed, Motion, Write Defaults, Foot IK (humanoid), Mirror, Cycle Offset, transitions list.
- **Transitions** — directed edges between states with conditions, Has Exit Time, Transition Duration, Offset, Interruption Source, Can Transition To Self.
- **Parameters** — global values driving conditions: Float, Int, Bool, Trigger.
- **Layers** — independent state machines blended into the final pose; layer 0 is the base.

Add the controller via `manage_asset` (create as AnimatorController) and assign to the GameObject's `Animator.runtimeAnimatorController` via `manage_components`. Edit graph topology via `manage_animation`.

## Generic vs Humanoid rigs

| Rig          | Use for                          | Retargeting | Built-in IK | Notes                                                  |
| ------------ | -------------------------------- | ----------- | ----------- | ------------------------------------------------------ |
| **Humanoid** | bipedal characters (people, NPCs)| yes         | yes         | Avatar maps source bones to Unity's standard skeleton  |
| **Generic**  | animals, vehicles, robots, props | no          | no          | Specify root bone for root motion                      |
| **Legacy**   | —                                | —           | —           | Ancient `Animation` component. Do not use.             |

Humanoid retargeting maps muscles, not raw bones — proportions shift between skeletons. If a retarget looks broken (twisted limb, sunken hip), fix bone mappings in the FBX importer's Avatar > Configure window.

Set rig type on the FBX importer's Rig tab; create the controller and Avatar via `manage_asset`.

## Parameters and transitions

Parameter types:

- **Float** — `SetFloat("Speed", v)`. Use for blend tree axes, speed scales.
- **Int** — `SetInteger("AttackId", n)`. Use for discrete state selection.
- **Bool** — `SetBool("IsGrounded", b)`. Use for sustained binary state.
- **Trigger** — `SetTrigger("Jump")`. Auto-resets after consumed by a transition. Use for one-shot events.

Hot-path tip: cache parameter ids with `Animator.StringToHash("Speed")` once and reuse the int.

Transition fields:

- **Conditions** — parameter comparisons (Greater/Less for Float/Int, equals for Bool, "exists" for Trigger). All conditions must be true for the transition to fire.
- **Has Exit Time** — when on, transition only fires after the source state plays past N normalized time. When off, fires the moment conditions are met. Common cause of "my trigger fires but the transition doesn't happen until much later".
- **Transition Duration** — blend overlap (seconds or normalized).
- **Interruption Source** — controls whether higher-priority transitions can interrupt this one mid-blend.

Best practice: name parameters in PascalCase, name transitions consistently, and keep a hand-drawn diagram for any controller with >10 states.

## Blend trees

| Type                        | Use for                                            |
| --------------------------- | -------------------------------------------------- |
| **1D**                      | idle ↔ walk ↔ run on Speed                         |
| **2D Simple Directional**   | 8-way locomotion on (MoveX, MoveY)                 |
| **2D Freeform Cartesian**   | stick-driven locomotion, irregular sample layout   |
| **2D Freeform Directional** | locomotion with strafe + back; samples on a circle |
| **Direct**                  | explicit per-clip blend weight; advanced (face rigs)|

For locomotion, 2D Freeform Cartesian on (MoveX, MoveZ) is the workhorse — sample idle at (0,0), walk at the cardinals, run at the corners.

## Layers and avatar masks

- Layer 0 is the base; higher layers add or override.
- **Layer Weight** 0..1 controls layer influence. Set at runtime: `animator.SetLayerWeight(1, 0.8f)`.
- **Blending Mode**: `Override` (replace) or `Additive` (add to base).
- **Avatar Mask** — per-bone include/exclude. Classic case: an "Upper Body" mask on an aim/shoot layer so it doesn't disturb leg locomotion on layer 0.

Create the AvatarMask asset (`manage_asset`), check the bones to include in its Humanoid or Transform tab, then assign it to the layer in the Animator Controller.

## Root motion

The Animator's **Apply Root Motion** checkbox makes animation drive the GameObject's Transform position/rotation directly.

- **In-place anim + scripted movement** — preferred for player characters. More control over speed, deceleration, ground snap. Animator does not write transform.
- **Root motion** — correct for cinematic NPCs, ridable characters, mocap-heavy systems where the artist already authored the locomotion curve.
- **`OnAnimatorMove()`** — callback on a MonoBehaviour on the same GameObject as the Animator. Lets you intercept root motion and apply it to a Rigidbody or CharacterController instead of the Transform. When this method exists, Apply Root Motion's effect is routed through it.

Anti-pattern: Apply Root Motion on AND `CharacterController.Move(scriptedDelta)` — character moves at double speed.

## AnimationEvent

Embed events at specific times in a clip. They call a method by name on a MonoBehaviour with an optional Float, Int, String, or Object parameter.

- Edit on a hand-authored `.anim`: select the clip, open the Animation window, click the event marker icon at a frame, name the function.
- Edit on an FBX-imported clip: FBX importer > Animation tab > expand the clip > Events panel. NOT the `.anim` subasset.
- The receiver MonoBehaviour MUST be on the same GameObject as the Animator (or a parent visited by SendMessage upcall behavior — but rely on same-GO).

Common uses:

- Footstep SFX (cross-link `unity-audio` for the actual playback).
- Hitbox enable/disable on attack frames (cross-link `unity-physics` for the collider toggle).
- Projectile spawn frame.
- Camera shake trigger.

Verify wiring via `read_console` — Unity logs `AnimationEvent has no receiver` when the method is missing or misspelled.

## IK and Animation Rigging

**Built-in Humanoid IK** — `OnAnimatorIK(int layer)` on a MonoBehaviour on the Animator's GameObject. Inside, set goals:

```csharp
void OnAnimatorIK(int layer) {
    animator.SetIKPositionWeight(AvatarIKGoal.LeftHand, ikWeight);
    animator.SetIKPosition(AvatarIKGoal.LeftHand, target.position);
    animator.SetIKRotationWeight(AvatarIKGoal.LeftHand, ikWeight);
    animator.SetIKRotation(AvatarIKGoal.LeftHand, target.rotation);
}
```

The state must have **IK Pass** enabled (per-layer checkbox). Use sparingly — hand-on-railing, foot-on-step.

**Animation Rigging package** (`com.unity.animation.rigging`) — modern constraint-based rig overlay. Add a `Rig` component on a child of the Animator, then constraints under it:

| Constraint              | Use for                                       |
| ----------------------- | --------------------------------------------- |
| `TwoBoneIKConstraint`   | foot IK on a knee, hand IK on an elbow        |
| `MultiAimConstraint`    | aim chest/head at a target                    |
| `ChainIKConstraint`     | tail / tentacle / spine that follows a tip    |
| `OverrideTransform`     | force a bone to a specific pose post-anim     |
| `BoneRenderer`          | debug gizmo — assign Skeleton bones array     |

Install via `manage_packages`. Use Animation Rigging for: aim layers, foot IK with terrain raycast, secondary-hand grip on a weapon, prop attachment to a hand bone.

Bone Renderer requires manually populating its `Transforms` array; the gizmo shows nothing if empty.

## AnimationClip authoring

- **FBX-imported clips** — set rig and clip ranges on the FBX importer's Animation tab. Loop pose, root motion baking (Bake Into Pose for X/Y/Z position and rotation), avatar mask per clip.
- **Hand-authored** — `Window > Animation > Animation`, select a GameObject, hit Record, change properties to keyframe them. Creates a `.anim` and an Animator + controller if missing.

When to hand-author: UI panels, prop animations, simple gameplay timing curves. When to import from DCC: any character animation — author in Maya/Blender, retarget to your humanoid.

`Optimize Game Objects` (FBX importer Rig tab) strips bone Transforms from the hierarchy at runtime — breaks `GetComponentsInChildren<Transform>()` looking for bones. Whitelist needed bones in **Extra Transforms to Expose**.

See `references/clips-and-import.md` for full FBX import field reference.

## Animator Override Controller

A subclass of an Animator Controller that swaps individual clips while keeping the graph (states, transitions, parameters, layers, masks) identical.

Use case: one base "Humanoid" controller; per-character override controllers swap in character-specific attack/idle clips. Saves duplicating the entire controller graph per character.

Create via `manage_asset` (Animator Override Controller); set its `Controller` field to the base; replace clips in the override list. Assign as `Animator.runtimeAnimatorController`.

## Timeline

Package `com.unity.timeline`. Open via `Window > Sequencing > Timeline`. Asset is a `.playable` file; played at runtime by a `PlayableDirector` component on a GameObject.

Tracks:

| Track          | Drives                                              |
| -------------- | --------------------------------------------------- |
| Activation     | toggles a GameObject on/off across a range         |
| Animation      | drives an Animator (clips + writes Transform)       |
| Audio          | plays an AudioSource                                |
| Cinemachine    | blends between virtual cameras (cross-link `unity-cinemachine`) |
| Signal         | fires SignalReceiver UnityEvents at marked times    |
| Control        | nests a Timeline or controls a ParticleSystem       |
| Custom         | `ScriptPlayable<T>` — bespoke behavior              |

Signals: place a `SignalEmitter` on a track at a time; a `SignalReceiver` MonoBehaviour on a target GameObject maps `SignalAsset → UnityEvent`. Good for cutscene-driven gameplay (give item, change stat, trigger dialogue).

Use Timeline for: cutscenes, intro sequences, scripted boss intros, level transitions. Edit-mode scrubbing previews the result before runtime.

See `references/timeline.md` for track-binding and PlayableDirector wrap mode details.

## Common patterns

- **Locomotion blend tree** — 2D Freeform Cartesian on (MoveX, MoveZ); SetFloat from movement controller in Update.
- **Attack combo** — Trigger per attack; states A→B→C with Has Exit Time on the back half, conditions on the front; AnimationEvent on the hit frame enables the damage collider.
- **Aim layer** — avatar-masked upper body layer with weight 1 when aiming; MultiAimConstraint on chest pointing at aim target.
- **UI panel pop-in** — Animator with Idle/In/Out states; SetTrigger("Open")/SetTrigger("Close"). Or DOTween for code-driven (fewer asset files, simpler).
- **Cutscene** — Timeline with Animation track on hero, Cinemachine track for camera blends, Audio track for music, Signal track for gameplay events.

## Gotchas

- **Animator overwrites transforms** in its update phase. Manual transform writes in `Update` are lost. Fix: write in `LateUpdate` (runs after Animator) or use Animation Rigging constraints.
- **Stuck triggers** — `SetTrigger` called every frame stays set; use `ResetTrigger` to clear.
- **Has Exit Time delays** — transition ignores conditions until exit time elapses. Disable Has Exit Time for responsive input-driven transitions.
- **Self-transition** ("Can Transition To Self") restarts the state — useful for replaying a one-shot, but easy to set unintentionally.
- **Write Defaults** (per state) — when ON, properties not animated by this state reset to default; OFF, they retain prior layer values. Inconsistency across states causes intermittent bugs (e.g. a bone snapping). Pick a project-wide setting and keep all states matching.
- **Apply Root Motion + scripted movement** = double movement. Pick one.
- **Optimize Game Objects** strips bone Transforms — bone-finding code returns null. Expose the needed bones explicitly.
- **AnimationEvent on FBX-imported clip** must be edited via the FBX importer's Events panel, NOT on the `.anim` subasset (changes to the subasset are wiped on reimport).
- **Sub-state machines nested >2 deep** are a code smell — refactor into separate layers or controllers.
- **Animator on disabled GameObject** — parameters can be set but animation does not advance until enabled.

## Verification

1. `read_console` for `Animator does not have parameter 'X'` and `AnimationEvent has no receiver` — both indicate broken wiring.
2. Open the Animator window in Play mode (`execute_menu_item` Window/Animation/Animator) and observe state transitions in real time. Confirm parameters update and the active state highlights as expected.
3. Frame-step through an attack combo (Pause + Step in the toolbar) — confirm the hitbox AnimationEvent fires on the intended frame.
4. For 3D characters, invoke `unity-3d-verification` (4-shot orthographic) at key animation poses to confirm bone deformation and prop attachment look correct.
5. For Timeline cutscenes, scrub the timeline preview in Edit mode before testing in Play.
6. For IK / Animation Rigging, enable Gizmos, confirm the rig's effector handles align with the target during the constrained state.

Cross-links: `unity-cinemachine` (Timeline + camera blends), `unity-audio` (AnimationEvent footsteps), `unity-physics` (hitbox enable/disable), `unity-3d-verification`, `unity-best-practices`.

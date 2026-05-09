---
name: unity-3d-rotation
description: 'Use when rotating 3D GameObjects in Unity through Unity MCP — setting transform.rotation/eulerAngles/localRotation, look-at behavior, smooth slerp, character or turret aim, camera framing, gimbal-lock issues, Rigidbody MoveRotation, or any quaternion math on a 3D Transform. Do NOT use for SpriteRenderers (use unity-2d-rotation), RectTransforms under Canvas (use unity-ugui-rotation), or general UI/Canvas work (use unity-ugui). For Rigidbody-driven rotation prefer unity-3d-rotation; for general Rigidbody / collider / joint setup use unity-physics. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Any rotation on a 3D GameObject's Transform: cameras, characters, props, turrets, pickups. SpriteRenderer → `unity-2d-rotation`; RectTransform under Canvas → `unity-ugui-rotation`.

## Decision tree

1. Rigidbody attached and non-kinematic, OR want physics-correct kinematic motion? Use `Rigidbody.MoveRotation(Quaternion)` in FixedUpdate. Do NOT write `transform.rotation` directly — fights the simulation, breaks interpolation.
2. Animator driving this Transform? Animator overwrites in its update pass. Author the rotation in animation, use Animation Rigging constraints, or write in `LateUpdate` after the Animator.
3. Cinemachine virtual camera target? Rotate the VCam, not the `Camera`. Cinemachine drives Camera transform in LateUpdate.
4. Otherwise: prefer Quaternion (composition, slerp, no gimbal lock). Use Euler only for designer-facing inspector values or one-shot human-readable angles.
5. World vs local: `transform.rotation` = world; `transform.localRotation` = relative to parent. Children of rotated parents should use `localRotation` for object-relative aim.

Avoid setting `eulerAngles` repeatedly in a loop. Unity stores rotation as Quaternion and re-derives Euler on read; you can lose continuity (-90 reads back as 270) and lock yourself into ambiguous representations.

## Workflow

1. Locate target by name, tag, or component.
2. Decide world vs local space and Quaternion vs Euler from the decision tree.
3. One-shot: write `rotation` / `eulerAngles` / `localRotation` / `localEulerAngles`.
4. Continuous or computed: author a MonoBehaviour and attach.
5. Physics-driven: set Rigidbody fields, then `freezeRotation` / constraints / joint limits.
6. Editor console clean of null-ref or missing-component errors.
7. Verify visually.

## Common patterns

### Set absolute rotation (one-shot)

Write the field directly. Prefer Quaternion if you have one:

- Euler (degrees, world): set `eulerAngles` to `[0, 90, 0]` on `Turret`.
- Quaternion (xyzw, world): set `rotation` to `[0, 0.7071, 0, 0.7071]` on `Turret`.
- Local: set `localEulerAngles` to `[10, 0, 0]` on `Turret/Barrel`.

### Rotate by delta over time

```csharp
using UnityEngine;
public class SpinY : MonoBehaviour {
    public float degPerSec = 90f;
    void Update() {
        transform.Rotate(Vector3.up, degPerSec * Time.deltaTime, Space.Self);
    }
}
```

`Space.Self` = local axes; `Space.World` = world axes.

### Look at a target (instant)

```csharp
Vector3 dir = target.position - transform.position;
if (dir.sqrMagnitude > 1e-6f)
    transform.rotation = Quaternion.LookRotation(dir, Vector3.up);
```

### Look at a target (smooth)

```csharp
Quaternion desired = Quaternion.LookRotation(target.position - transform.position, Vector3.up);
transform.rotation = Quaternion.Slerp(transform.rotation, desired, Time.deltaTime * turnSpeed);
```

`Slerp` interpolates the shortest arc on the unit quaternion sphere — safe across the 180° boundary, unlike Euler `Lerp`.

### Constrained turret (yaw + pitch limits)

Decompose into yaw around world up + pitch around the turret's local right. Clamp pitch via signed angle from forward, never by clamping `eulerAngles.x` (wraps 359 → 0).

```csharp
Vector3 toTarget = target.position - transform.position;
Vector3 flat = Vector3.ProjectOnPlane(toTarget, Vector3.up);
Quaternion yaw = Quaternion.LookRotation(flat, Vector3.up);
float pitch = Vector3.SignedAngle(flat, toTarget, transform.right); // signed, -90..90
pitch = Mathf.Clamp(pitch, minPitch, maxPitch);
transform.rotation = yaw * Quaternion.AngleAxis(-pitch, Vector3.right);
```

### Rigidbody-driven rotation

```csharp
Rigidbody rb;
void FixedUpdate() {
    Quaternion delta = Quaternion.AngleAxis(yawSpeed * Time.fixedDeltaTime, Vector3.up);
    rb.MoveRotation(rb.rotation * delta);
}
```

Freeze axes via `Rigidbody.constraints` (`FreezeRotationX | FreezeRotationZ` for an upright character).

### Reading live quaternion math

Reflect on the live Transform to inspect Quaternion component-wise — useful when debugging slerp where the standard inspector hides raw values.

## Gotchas

- **Gimbal lock** — composing rotations by repeatedly adding to `eulerAngles` collapses two axes when pitch hits ±90°. Compose Quaternions (`q = qYaw * qPitch * qRoll`).
- **Euler readback** — `transform.eulerAngles` returns 0..360. Setting -90 reads back as 270. Compare via `Quaternion.Angle(a, b)`.
- **localRotation under non-uniform scale** — parent with non-uniform scale + rotated child = visible shear. Keep parent scale uniform, or insert an unscaled pivot child.
- **Animator overwrite** — humanoid and generic Animators write bound transforms every frame. Manual `Update` writes are lost. Use `LateUpdate`, IK callback, Animation Rigging, or bake rotation into clip.
- **Cinemachine** — Camera transform is owned by active VCam. Rotating Camera directly is silently overwritten. Rotate VCam transform or its `LookAt`/`Follow` targets.
- **Imported FBX axis** — Blender/Maya use right-handed; Unity is left-handed Y-up. Imported rigs often need a -90° X correction on the root, or re-import with correct axis settings.
- **Quaternion sign ambiguity** — `q` and `-q` are the same rotation. Component-wise compare misfires; use `Quaternion.Angle` or `Quaternion.Dot`.
- **Normalization drift** — long multiplication chains denormalize. After many composes, call `Quaternion.Normalize` or assign `rotation.normalized`.

## Verification

After any rotation change to a 3D GameObject → `unity-3d-verification` (4-shot orthographic). A wrong axis or 90° error often only shows up from one of the four views. Don't skip just because no console error appeared.

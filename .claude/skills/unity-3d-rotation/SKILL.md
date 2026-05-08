---
name: unity-3d-rotation
description: Use when rotating 3D GameObjects in Unity through Unity MCP — setting transform.rotation/eulerAngles/localRotation, look-at behavior, smooth slerp, character or turret aim, camera framing, gimbal-lock issues, Rigidbody MoveRotation, or any quaternion math on a 3D Transform. Do NOT use for SpriteRenderers (use unity-2d-rotation), RectTransforms under Canvas (use unity-ugui-rotation), or general UI/Canvas work (use unity-ugui).
---

## When to use

Any rotation on a 3D GameObject's Transform: cameras, characters, props, turrets, pickups. If the target is a SpriteRenderer use unity-2d-rotation; if it is a RectTransform under a Canvas use unity-ugui-rotation.

## Decision tree

1. Is a Rigidbody attached and is the body non-kinematic, or do you want physics-correct kinematic motion? Use `Rigidbody.MoveRotation(Quaternion)` in FixedUpdate. Do not write `transform.rotation` directly — it fights the simulation and breaks interpolation.
2. Is an Animator driving this Transform? Animator overwrites the Transform in its update pass. Either author the rotation in the animation, use Animation Rigging constraints, or write in `LateUpdate` after the Animator.
3. Is this a Cinemachine virtual camera target? Rotate the VCam, not the `Camera`. Cinemachine drives the Camera's transform in LateUpdate.
4. Otherwise: prefer Quaternion for math (composition, slerp, no gimbal lock). Use Euler only for designer-facing inspector values or one-shot human-readable angles.
5. World vs local: writing `transform.rotation` sets world orientation; `transform.localRotation` sets orientation relative to the parent. Children of rotated parents should use `localRotation` for object-relative aim.

Avoid setting `eulerAngles` repeatedly in a loop. Unity stores rotation as a Quaternion and re-derives Euler on read; you can lose continuity (e.g. -90 reads back as 270) and lock yourself into ambiguous representations.

## Workflow

1. `find_gameobjects` to locate the target by name, tag, or component.
2. Decide world vs local space and Quaternion vs Euler from the decision tree.
3. For one-shot rotations: `manage_gameobject` to write `rotation`, `eulerAngles`, `localRotation`, or `localEulerAngles`.
4. For continuous or computed rotations: `create_script` (or `script_apply_edits`) to attach a MonoBehaviour, then `manage_components` to add it to the GameObject.
5. For physics-driven rotation: `manage_components` to set Rigidbody fields, `manage_physics` for `freezeRotation` / constraints / joint limits.
6. Run `read_console` after applying to catch null-reference or missing-component errors.
7. Verify visually (see Verification).

## Common patterns

### Set absolute rotation (one-shot, editor or runtime)

`manage_gameobject` with a transform write. Either form works; prefer Quaternion if you have one in hand:

```
# Euler form (degrees, world space)
manage_gameobject(action="set_transform", target="Turret",
                  eulerAngles=[0, 90, 0])

# Quaternion form (xyzw, world space)
manage_gameobject(action="set_transform", target="Turret",
                  rotation=[0, 0.7071, 0, 0.7071])

# Local space
manage_gameobject(action="set_transform", target="Turret/Barrel",
                  localEulerAngles=[10, 0, 0])
```

### Rotate by delta over time (script)

```csharp
using UnityEngine;
public class SpinY : MonoBehaviour {
    public float degPerSec = 90f;
    void Update() {
        transform.Rotate(Vector3.up, degPerSec * Time.deltaTime, Space.Self);
    }
}
```

Create with `create_script`, attach with `manage_components`. `Space.Self` rotates around the object's local axes; `Space.World` rotates around world axes.

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

`Slerp` interpolates along the shortest arc on the unit quaternion sphere; safe across the 180-degree boundary, unlike Euler `Lerp`.

### Constrained turret (yaw + pitch limits)

Decompose into a yaw rotation around world up and a pitch rotation around the turret's local right. Clamp pitch using a signed angle from forward, never by clamping `eulerAngles.x` (which wraps 359 to 0).

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

Freeze axes through `manage_physics` setting `Rigidbody.constraints` (e.g. `FreezeRotationX | FreezeRotationZ` for an upright character).

### Reading live quaternion math

`unity_reflect` can read fields the standard tools do not expose, e.g. inspecting a Quaternion component-wise to debug a slerp.

## Gotchas

- **Gimbal lock**: composing rotations by repeatedly adding to `eulerAngles` can collapse two axes when pitch hits +/-90. Compose Quaternions (`q = qYaw * qPitch * qRoll`) instead.
- **Euler readback**: `transform.eulerAngles` returns 0..360. Setting -90 reads back as 270. Never compare Euler values directly across writes; compare via `Quaternion.Angle(a, b)`.
- **localRotation under non-uniform scale**: a parent with non-uniform scale plus a rotated child produces visible shear. Either keep parent scale uniform, or insert an unscaled pivot child.
- **Animator overwrite**: humanoid and generic Animators write the bound transforms every frame. Manual writes in `Update` are lost. Use `LateUpdate`, an `IK` callback, Animation Rigging, or bake the rotation into the clip.
- **Cinemachine**: the Camera's transform is owned by the active VCam. Rotating the Camera directly is silently overwritten. Rotate the VCam's transform or its `LookAt` / `Follow` targets.
- **Imported FBX axis**: Blender and Maya use right-handed coordinates with different up-axes; Unity is left-handed Y-up. Imported rigs often need a -90 X correction on the root, or a re-import with the correct axis settings.
- **Quaternion sign ambiguity**: `q` and `-q` represent the same rotation. Comparing component-wise will misfire; compare via `Quaternion.Angle` or `Quaternion.Dot`.
- **Normalization drift**: long chains of multiplications can denormalize. After many composes, call `Quaternion.Normalize` or assign `rotation.normalized`.

## Verification

After any rotation change to a 3D GameObject, invoke the `unity-3d-verification` skill to capture a 4-shot orthographic view (left, right, top, bottom) and visually confirm the orientation. A wrong axis or 90-degree error often only shows up from one of the four views. Do not skip the visual check just because no console error appeared.

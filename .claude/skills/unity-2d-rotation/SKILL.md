---
name: unity-2d-rotation
description: 'Use when rotating 2D content in Unity through Unity MCP — sprites, SpriteRenderers, Rigidbody2D-driven bodies, top-down or side-scroller facing, projectiles aimed via Atan2, spin animations, sprite flipping. Z-axis rotation only; sprite-up convention applies. Do NOT use for 3D Transform rotation (use unity-3d-rotation), or RectTransforms under Canvas (use unity-ugui-rotation). For Rigidbody2D-driven rotation use unity-2d-rotation; for general 2D physics / colliders / joints use unity-physics. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

The target is a SpriteRenderer, a Rigidbody2D, a 2D collider parent, or any object intended to live in the X/Y plane viewed by an orthographic 2D camera. If the object is a 3D mesh use unity-3d-rotation; if it is a RectTransform under a Canvas use unity-ugui-rotation.

## Decision tree

1. Z-axis only. Write `transform.eulerAngles = new Vector3(0, 0, deg)` or `transform.Rotate(0, 0, deg)`. Setting X or Y rotation tilts the sprite out of the camera plane and is almost always a bug.
2. Sign convention: counter-clockwise is positive when viewed from +Z (standard math). A 90-degree rotation moves the sprite's local +X toward +Y.
3. Is a Rigidbody2D attached? Write through `rb2d.rotation`, `rb2d.MoveRotation`, or `rb2d.angularVelocity`. Do not write `transform.eulerAngles` directly — it fights the simulation.
4. For left/right facing in a side-scroller, prefer `SpriteRenderer.flipX` over a 180-degree Y rotation. flipX is cheaper, keeps the sprite in the same sorting plane, and avoids back-face issues.
5. Sprite-up convention: a default Unity sprite's "up" is +Y. Sprites authored facing right (a typical projectile or arrow) need a -90-degree offset when computing facing from a direction vector.

## Workflow

1. `find_gameobjects` to locate the target.
2. Confirm whether a Rigidbody2D is attached (`unity_reflect` or `manage_components` get) — it changes which API to use.
3. For one-shot rotations: `manage_gameobject` writing `eulerAngles` with X=Y=0.
4. For continuous spin or aim: `create_script` for a small MonoBehaviour, attach via `manage_components`.
5. For physics-locked rotation: `manage_physics` to set `Rigidbody2D.freezeRotation` or constraints.
6. `read_console` for errors. Verify visually (see Verification).

## Common patterns

### Face a world point (sprite authored facing +Y)

```csharp
Vector2 dir = (Vector2)(target.position - transform.position);
float ang = Mathf.Atan2(dir.y, dir.x) * Mathf.Rad2Deg - 90f; // -90 because sprite-up is +Y
transform.eulerAngles = new Vector3(0, 0, ang);
```

If the sprite is authored facing +X (common for projectiles/arrows), drop the `- 90f`.

### Spin

```csharp
public float degPerSec = 180f;
void Update() { transform.Rotate(0, 0, degPerSec * Time.deltaTime); }
```

### Smooth rotate to a target angle

```csharp
float current = transform.eulerAngles.z;
float next = Mathf.LerpAngle(current, targetDeg, Time.deltaTime * turnSpeed);
transform.eulerAngles = new Vector3(0, 0, next);
```

Use `Mathf.LerpAngle`, not `Mathf.Lerp` — it handles the 360-to-0 wrap. Inputs and output are degrees; if you computed the target via `Atan2`, convert with `Mathf.Rad2Deg` first.

### Rigidbody2D set rotation

```csharp
Rigidbody2D rb;
void FixedUpdate() { rb.MoveRotation(targetDeg); } // degrees
```

For continuous spin without per-frame writes:

```csharp
rb.angularVelocity = degPerSec; // degrees per second
```

`angularVelocity` is degrees/sec on Rigidbody2D (unlike 3D Rigidbody which uses radians/sec).

### Lock physics rotation

```csharp
rb2d.freezeRotation = true;
// or
rb2d.constraints = RigidbodyConstraints2D.FreezeRotation;
```

Useful for character controllers so collisions do not spin the body.

### Sprite flipping vs 180-degree rotation

```csharp
spriteRenderer.flipX = movingLeft;
```

Prefer this over `transform.eulerAngles = new Vector3(0, 180, 0)`. Rotating around Y in 2D moves the sprite slightly out of plane (visible if the sprite has perspective camera or non-zero thickness in pixel-perfect setups) and can flip the back face away from the camera. flipX mirrors UVs only.

## Gotchas

- **Rigidbody2D fight**: writing `transform.eulerAngles` while a Rigidbody2D simulates causes jitter and missed contacts. Always go through `rb2d.rotation` / `MoveRotation` / `angularVelocity`.
- **LerpAngle vs Lerp**: `Mathf.Lerp(359, 1, 0.5)` returns 180; `Mathf.LerpAngle(359, 1, 0.5)` returns 0. Always LerpAngle for rotational interpolation.
- **Atan2 unit mismatch**: `Atan2` returns radians, `eulerAngles` is degrees, `LerpAngle` is degrees, `rb2d.rotation` is degrees. Forgetting `Mathf.Rad2Deg` produces a near-zero rotation that looks like nothing happened.
- **Sprite-up offset**: if facing math looks 90 degrees off, the sprite was probably authored facing the other axis. Adjust the constant offset in the Atan2 expression rather than rotating the sprite asset.
- **Tilemap rotation**: rotating a Tilemap rotates the entire grid, including chunk boundaries — usually wrong. Rotate child GameObjects (e.g. individual sprite decorations) instead.
- **Custom Axis sort mode**: if the scene's `Transparency Sort Mode` is Custom Axis, rotating a sprite changes which sprites it draws in front of. Stick to Default sort unless the project explicitly uses custom axis.
- **Order in Layer is unaffected by rotation**, but a rotated sprite's bounds expand — culling and screen-space effects (post-processing masks, 2D lights) may pick up the new bounds.
- **Animator overwrite**: an Animator clip that targets `m_LocalRotation` rewrites the rotation every frame. Either bake the spin into the clip or move the script write into `LateUpdate` after the Animator.
- **Hinge2D / DistanceJoint2D**: setting rotation directly while a joint is active can violate the joint constraint and explode the simulation. Apply torque or set `angularVelocity` instead.

## Verification

After rotating a 2D object, capture a single screenshot from the active 2D camera (the one whose culling mask includes the object) framing the target. Confirm visually that:

- The sprite faces the intended direction.
- The sprite did not tilt out of plane (X and Y rotation are zero).
- Sorting against neighboring sprites is unchanged unless intended.

The 4-shot orthographic capture from `unity-3d-verification` is overkill for flat 2D content; a single in-camera shot is sufficient. If the sprite is meant to face a moving target, take the screenshot at the moment the target is in view to validate the aim math.

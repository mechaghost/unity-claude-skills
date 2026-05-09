---
name: unity-2d-rotation
description: 'Use when rotating 2D content in Unity through Unity MCP — sprites, SpriteRenderers, Rigidbody2D-driven bodies, top-down or side-scroller facing, projectiles aimed via Atan2, spin animations, sprite flipping. Z-axis rotation only; sprite-up convention applies. Do NOT use for 3D Transform rotation (use unity-3d-rotation), or RectTransforms under Canvas (use unity-ugui-rotation). For Rigidbody2D-driven rotation use unity-2d-rotation; for general 2D physics / colliders / joints use unity-physics. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Target is a SpriteRenderer, Rigidbody2D, 2D collider parent, or any object in the X/Y plane viewed by an orthographic 2D camera. 3D mesh → `unity-3d-rotation`; RectTransform under Canvas → `unity-ugui-rotation`.

## Decision tree

1. Z-axis only. `transform.eulerAngles = new Vector3(0, 0, deg)` or `transform.Rotate(0, 0, deg)`. Setting X or Y tilts out of camera plane and is almost always a bug.
2. Sign: counter-clockwise positive viewed from +Z (standard math). 90° rotation moves sprite's local +X toward +Y.
3. Rigidbody2D attached? Write through `rb2d.rotation`, `rb2d.MoveRotation`, or `rb2d.angularVelocity`. Don't write `transform.eulerAngles` directly — fights the simulation.
4. Left/right facing in side-scroller: prefer `SpriteRenderer.flipX` over a 180° Y rotation. Cheaper, keeps sprite in same sorting plane, avoids back-face issues.
5. Sprite-up convention: default Unity sprite's "up" is +Y. Sprites authored facing right (typical projectile/arrow) need a -90° offset when computing facing from a direction vector.

## Workflow

1. Locate target.
2. Confirm whether Rigidbody2D attached (inspect live components) — changes which API.
3. One-shot: write `eulerAngles` with X=Y=0.
4. Continuous spin or aim: small MonoBehaviour and attach.
5. Physics-locked: `Rigidbody2D.freezeRotation` or constraints.
6. Editor console clean. Verify visually.

## Common patterns

### Face a world point (sprite authored facing +Y)

```csharp
Vector2 dir = (Vector2)(target.position - transform.position);
float ang = Mathf.Atan2(dir.y, dir.x) * Mathf.Rad2Deg - 90f; // -90 because sprite-up is +Y
transform.eulerAngles = new Vector3(0, 0, ang);
```

If sprite is authored facing +X (common for projectiles/arrows), drop the `- 90f`.

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

`Mathf.LerpAngle`, not `Lerp` — it handles the 360→0 wrap. Inputs/output in degrees; if target was computed via `Atan2`, convert with `Mathf.Rad2Deg` first.

### Rigidbody2D set rotation

```csharp
Rigidbody2D rb;
void FixedUpdate() { rb.MoveRotation(targetDeg); } // degrees
```

Continuous spin without per-frame writes:

```csharp
rb.angularVelocity = degPerSec; // degrees per second
```

`angularVelocity` is degrees/sec on Rigidbody2D (unlike 3D Rigidbody — radians/sec).

### Lock physics rotation

```csharp
rb2d.freezeRotation = true;
// or
rb2d.constraints = RigidbodyConstraints2D.FreezeRotation;
```

For character controllers so collisions don't spin the body.

### Sprite flipping vs 180° rotation

```csharp
spriteRenderer.flipX = movingLeft;
```

Prefer over `transform.eulerAngles = new Vector3(0, 180, 0)`. Y rotation in 2D moves sprite slightly out of plane (visible with perspective camera or non-zero thickness in pixel-perfect setups) and can flip the back face away. flipX mirrors UVs only.

## Gotchas

- **Rigidbody2D fight** — writing `transform.eulerAngles` while a Rigidbody2D simulates causes jitter and missed contacts. Go through `rb2d.rotation` / `MoveRotation` / `angularVelocity`.
- **LerpAngle vs Lerp** — `Mathf.Lerp(359, 1, 0.5)` returns 180; `Mathf.LerpAngle(359, 1, 0.5)` returns 0. Always LerpAngle for rotational interpolation.
- **Atan2 unit mismatch** — `Atan2` returns radians, `eulerAngles` is degrees, `LerpAngle` is degrees, `rb2d.rotation` is degrees. Forgetting `Mathf.Rad2Deg` produces a near-zero rotation that looks like nothing happened.
- **Sprite-up offset** — facing math 90° off = sprite authored facing the other axis. Adjust the constant offset in Atan2 rather than rotating the asset.
- **Tilemap rotation** — rotating a Tilemap rotates the entire grid including chunk boundaries — usually wrong. Rotate child GOs (sprite decorations) instead.
- **Custom Axis sort mode** — `Transparency Sort Mode` Custom Axis means rotating a sprite changes draw order. Stick to Default sort unless explicitly using custom axis.
- **Order in Layer is unaffected by rotation** — but a rotated sprite's bounds expand; culling and screen-space effects (post-process masks, 2D lights) may pick up new bounds.
- **Animator overwrite** — clip targeting `m_LocalRotation` rewrites every frame. Bake spin into clip or write in `LateUpdate`.
- **Hinge2D / DistanceJoint2D** — setting rotation directly while joint is active can violate the constraint and explode the simulation. Apply torque or set `angularVelocity`.

## Verification

Capture a single screenshot from the active 2D camera (the one whose culling mask includes the object) framing the target. Confirm:

- Sprite faces intended direction.
- No tilt out of plane (X and Y rotation zero).
- Sorting against neighbors unchanged unless intended.

The 4-shot orthographic from `unity-3d-verification` is overkill for flat 2D content; one in-camera shot is sufficient. If sprite is meant to face a moving target, capture at the moment the target is in view to validate aim math.

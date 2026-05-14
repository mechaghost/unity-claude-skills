---
name: unity-physics
description: 'Use for Unity 6+ physics: Rigidbody/Rigidbody2D, colliders/triggers, kinematic/dynamic bodies, forces/torque/MovePosition, raycasts/overlaps, joints, layer collision matrix, physics materials, FixedUpdate timing, collision/trigger callbacks. Use rotation skills for rotation-only work.'
---

## When to use

Bodies, colliders, joints, queries, materials, layer matrix, fixed timestep, collision/trigger callbacks. 3D (`Physics`, `Rigidbody`, `Collider`, `PhysicsMaterial`) and 2D (`Physics2D`, `Rigidbody2D`, `Collider2D`, `PhysicsMaterial2D`) are independent simulations — pick one per scene.

## 3D vs 2D fork

Names overlap; APIs and assets do not. A 3D Rigidbody never interacts with a Collider2D.

| Concept | 3D | 2D |
| --- | --- | --- |
| Body | `Rigidbody` | `Rigidbody2D` |
| Collider base | `Collider` | `Collider2D` |
| Mesh-shaped collider | `MeshCollider` | `PolygonCollider2D` |
| Fixed joint | `FixedJoint` | `FixedJoint2D` |
| Raycast | `Physics.Raycast` | `Physics2D.Raycast` |
| Material asset | `PhysicsMaterial` | `PhysicsMaterial2D` |
| Gravity | `Physics.gravity` (Vector3) | `Physics2D.gravity` (Vector2) |
| Layer matrix | 32 layers, Project Settings > Physics | same layers, Physics 2D panel |
| Hit struct | `RaycastHit` | `RaycastHit2D` (implicit-bool true on hit) |
| Force modes | `ForceMode` (4) | `ForceMode2D` (Force, Impulse) |

## Setting up a body

1. **Static** — Collider only, no Rigidbody. Cheapest. Never translate/rotate at runtime — rebuilds the static tree. If it must move, give it a kinematic Rigidbody.
2. **Dynamic** — `Rigidbody`, `isKinematic = false`. Default for players, enemies, props, projectiles.
3. **Kinematic** — `Rigidbody`, `isKinematic = true`. Ignores forces/gravity, fires callbacks and sweeps. Drive with `MovePosition`/`MoveRotation` from FixedUpdate. Platforms, scripted obstacles, character controllers.
4. **Trigger** — Collider with `isTrigger = true`. `OnTriggerEnter/Stay/Exit`, no physical response. **At least one** of the pair needs a Rigidbody (kinematic OK) or callbacks never fire.

Anti-pattern: Collider on a moving GameObject without a Rigidbody = static-tree rebuild every frame. Add a kinematic Rigidbody.

## Colliders

**3D primitives (cheap):** `BoxCollider`, `SphereCollider`, `CapsuleCollider`. **`MeshCollider`** — set `convex = true` if attached to a Rigidbody (non-convex + Rigidbody silently fails to collide). **`TerrainCollider`** for Terrain. **`WheelCollider`** has its own raycast suspension model — don't mix with regular stacks. See "Vehicles" section below.

**2D primitives:** `BoxCollider2D`, `CircleCollider2D`, `CapsuleCollider2D`. **`PolygonCollider2D`** auto-fits sprite outline (often too dense — simplify). **`EdgeCollider2D`** for one-sided lines. **`CompositeCollider2D`** merges children (or `TilemapCollider2D`) into one outline; set `usedByComposite = true` on each child, put Composite + Rigidbody2D (Static/Kinematic) on the parent.

**Compound colliders:** primitives parented under one Rigidbody act as one complex shape. Prefer over MeshCollider — faster, more stable, supports concave for dynamic bodies. For vehicles, a single flat `BoxCollider` on the body catches on every edge — build a compound of angled boxes: tilted front box for the approach angle, flat midsection, tilted rear box for the departure angle. Size to the visible body, not the wheels (wheels are `WheelCollider`s, not part of the body compound).

Edge cases: colliders <~0.01 units cause solver instability. For thin or fast bodies set `Rigidbody.collisionDetectionMode = Continuous` (or `ContinuousDynamic` if both sides move fast); leave walls on `Discrete`.

## Joints

Joints connect exactly two bodies. `connectedBody = null` → world. Anchors are local to each body.

| 3D joint | Use |
| --- | --- |
| `HingeJoint` | doors, wheels, levers — single rotational axis |
| `FixedJoint` | rigidly weld two bodies |
| `SpringJoint` | soft tether |
| `ConfigurableJoint` | general-purpose; preferred for advanced rigs |
| `CharacterJoint` | ragdoll limb (swing + twist limits) |

| 2D joint | Use |
| --- | --- |
| `HingeJoint2D` | rotational pivot, optional motor + limits |
| `FixedJoint2D` | rigid attach (stiff spring internally) |
| `SpringJoint2D` | dampened spring between anchors |
| `DistanceJoint2D` | fixed distance (rigid rod) |
| `FrictionJoint2D` | linear/angular friction |
| `RelativeJoint2D` | maintain relative position/orientation |
| `SliderJoint2D` | linear track / piston with optional motor |
| `TargetJoint2D` | drag a body toward a world-space target |
| `WheelJoint2D` | suspension + driven wheel for 2D vehicles |

Full fields, motor/limit setup, break-force tuning: `references/joints.md`.

## Vehicles (WheelCollider)

`WheelCollider` is a raycast-based suspension model, not a regular collider — it casts down from the wheel pivot through `suspensionDistance` and applies spring/damper forces along the suspension axis. Don't pair it with primitive colliders on the wheel GameObject; the chassis Rigidbody owns the dynamics.

**Body / Rigidbody setup:**

- Compound collider on the chassis (see Colliders → Compound) — *never* a flat `BoxCollider` flush with the ground; it snags on terrain seams.
- `Rigidbody.centerOfMass` — push down ~0.4–0.6 m below geometric center, or the vehicle flips on the first hard turn. Sanity-check by drawing a gizmo at `transform.TransformPoint(rb.centerOfMass)`.
- Chassis `mass` is the total vehicle mass (e.g. 1200 kg). Wheel `mass` is small (≈20 kg per wheel) and feeds into suspension dynamics.

**Suspension spring/damper:**

- Spring **must support static load** with headroom: `spring ≥ 1.5 × (chassisMass × 9.81) / numWheels`. Under-sprung wheels sit at full compression and the chassis drags on terrain.
- Damping ratio = `damper / (2 × sqrt(spring × massPerWheel))`. Target **0.8–0.95** for road cars. Under-damped pogos; over-damped feels glued.
- `targetPosition` — 0 = fully extended at rest, 1 = fully compressed. ~0.5 lets the wheel travel both directions from rest.
- `suspensionDistance` — total travel. Match the visible suspension geometry; too small clips, too large lets the chassis sink into the ground.
- `forceAppPointDistance` — where suspension force applies along the suspension axis. Above wheel center (positive); too low causes outward chassis roll on cornering.

**Ground colliders:**

- Use `MeshCollider` (non-convex; static, no Rigidbody) or `TerrainCollider`. Primitive `SphereCollider`s and small bumpy meshes produce steep contact normals that *launch* vehicles. Keep ground surfaces low-curvature.

**Friction curves** — `forwardFriction` and `sidewaysFriction` are `WheelFrictionCurve` **structs**. Subject to CS1612: cache, mutate, reassign:

```csharp
var f = wheel.sidewaysFriction;
f.extremumSlip = 0.4f;
f.asymptoteSlip = 0.8f;
f.stiffness = 3f;     // 2–5 for grippy road tires
wheel.sidewaysFriction = f;
```

**Physics material on the chassis** — `bounceCombine = Minimum`, low `bounciness`, or the vehicle pogos on every contact (see Physics materials section).

**MCP serialization** — `WheelCollider`s with mid-import non-finite transforms crash some Unity MCP servers via `Matrix4x4.ValidTRS()`. See `unity-best-practices` → "MCP serialization landmines". Use typed `GetComponent<WheelCollider>()` rather than generic component dumps.

## Forces and motion

Physics writes → `FixedUpdate`. Visual reads → `Update`/`LateUpdate`.

3D `Rigidbody.AddForce(Vector3, ForceMode)`:

- `Force` — continuous, mass-scaled, scaled by `fixedDeltaTime`. Default; thrust.
- `Acceleration` — continuous, mass-ignored.
- `Impulse` — instantaneous, mass-scaled. Jumps, hits, bullet kicks.
- `VelocityChange` — instantaneous, mass-ignored. Velocity delta directly.

Other 3D: `AddTorque`, `AddRelativeForce`, `AddForceAtPosition(force, worldPoint)` (induces torque), `AddExplosionForce(force, pos, radius, upMod, ForceMode)`.

```csharp
// Jump impulse, mass-scaled
rb.AddForce(Vector3.up * jumpImpulse, ForceMode.Impulse);

// Constant thrust
void FixedUpdate() {
    rb.AddForce(transform.forward * thrust, ForceMode.Force);
}

// Scripted kinematic move (isKinematic = true)
void FixedUpdate() {
    rb.MovePosition(rb.position + velocity * Time.fixedDeltaTime);
    rb.MoveRotation(rb.rotation * Quaternion.Euler(0, yawDeg, 0));
}
```

2D: `Rigidbody2D.AddForce(Vector2, ForceMode2D)`, `AddTorque(float)`, `AddForceAtPosition`, `AddRelativeForce`. `ForceMode2D` is `Force` or `Impulse` only — for instantaneous mass-ignored changes write `linearVelocity` directly.

Velocity field: Unity 6 uses `linearVelocity`/`angularVelocity`. Legacy `velocity` is deprecated and warns — rename when porting.

## Queries (raycasts and overlaps)

Full table and snippets: `references/queries.md`.

3D: `Physics.Raycast`, `RaycastAll`, `RaycastNonAlloc`, `Linecast`, `SphereCast`, `BoxCast`, `CapsuleCast`, `OverlapSphere`, `OverlapBox`, `CheckSphere`, `CheckBox`. Prefer `*NonAlloc` (or batched `RaycastCommand`) in hot paths — `RaycastAll` allocates per call.

2D: `Physics2D.Raycast`, `RaycastAll`, `Linecast`, `CircleCast`, `BoxCast`, `CapsuleCast`, `OverlapCircle`, `OverlapBox`, `OverlapPoint`, `OverlapArea`, `GetRayIntersection` (only way to ray-test 2D colliders from a 3D ray). 2D returns `RaycastHit2D` (struct, implicit-bool).

Without a layer mask, queries hit every collider including the caster and triggers:

```csharp
// Hit everything EXCEPT IgnoreRaycast and Player
int mask = ~((1 << LayerMask.NameToLayer("IgnoreRaycast"))
           | (1 << LayerMask.NameToLayer("Player")));
if (Physics.Raycast(origin, dir, out RaycastHit hit, maxDist, mask,
                    QueryTriggerInteraction.Ignore)) { /* ... */ }
```

Globals: `Physics.queriesHitTriggers` (default true), `Physics.queriesHitBackfaces` (default false). Override per call via `QueryTriggerInteraction`.

## Layers and collision matrix

32 layers (0–31). Layer 0 = `Default`. The matrix decides which pairs collide; toggle pairs off rather than scripting it. 3D and 2D matrices are independent.

Baseline: `Default` for static world, plus `Player`, `Enemy`, `Projectile`, `Trigger`, `IgnoreRaycast`. Disable Enemy↔Enemy if enemies pass through; Projectile↔OwnerFaction so a shooter doesn't self-hit.

Layer-based filtering goes through the matrix only. Setting fields on the Collider does not filter by layer.

## Physics materials

3D `PhysicsMaterial`: `dynamicFriction`, `staticFriction`, `bounciness`, `frictionCombine`, `bounceCombine` (Average, Minimum, Maximum, Multiply). Apply via `Collider.sharedMaterial` (preferred — no duplication) or `Collider.material` (auto-instantiates per collider).

2D `PhysicsMaterial2D`: `friction`, `bounciness`, `frictionCombine`, `bounceCombine` (same modes). No static/dynamic friction split.

3D and 2D assets are different file types — don't cross-assign.

Edits don't retroactively affect contacts already in progress; reassign `sharedMaterial` (or briefly disable/enable the collider) to refresh.

Unity 6 canonical types are `PhysicsMaterial` and `PhysicsMaterialCombine`. The pre-Unity-6 names `PhysicMaterial` and `PhysicMaterialCombine` (no `s`) are **removed**, not just deprecated — code or AI-generated snippets copied from pre-6 tutorials are hard compile errors, not warnings. Search-replace before pasting.

For grounded gameplay (vehicles, characters, props that shouldn't pogo on contact), set `bounceCombine = Minimum` so the lowest `bounciness` in any contact pair wins — a stray nonzero bounce on any surface with default `Average` makes the body bounce on every contact. `frictionCombine = Average` (default) is usually fine; switch to `Multiply` for stickier behavior or `Minimum` for ice-like surfaces.

## Fixed timestep and execution order

`Time.fixedDeltaTime` defaults to 0.02 s (50 Hz). Increase for small fast objects; cost is ~linear in steps/sec and stacks with collision work — don't casually drop to 0.005.

Per-frame: `FixedUpdate` (0+ times until sim catches up) → physics step → `OnCollision*`/`OnTrigger*` → `Update` → coroutines → `LateUpdate` → render.

- Forces, velocity writes, `MovePosition`/`MoveRotation` → `FixedUpdate`.
- Camera/UI reads of physics state → `LateUpdate`.
- `Rigidbody.interpolation = Interpolate` on bodies the camera tracks; `Extrapolate` only for predictable motion (visibly wrong on impacts). Default `None` is fine otherwise.
- `Physics.simulationMode` (formerly `autoSimulation`) defaults to `FixedUpdate`. Set `Script` to call `Physics.Simulate(dt)` manually — deterministic replay or editor tooling.

## Gotchas

- Non-uniform parent scale distorts child colliders (capsules/spheres especially). Keep physics roots uniform; scale visuals on a child.
- `MeshCollider` non-convex + Rigidbody = silently no collision. Set convex true or remove Rigidbody.
- Writing `transform.position` on a Rigidbody body teleports without sweep — clips through walls, misses events. Use `MovePosition` (sweeps) or `Rigidbody.position` (still teleports but stays in sync with sim).
- `OnTriggerEnter`/`OnCollisionEnter` need a Rigidbody on at least one side. Two static colliders never fire events.
- 2D and 3D physics are entirely separate worlds.
- `ContinuousDynamic` CCD is expensive — reserve for small fast bullets that must hit other moving things.
- `Rigidbody.freezeRotation` locks all three rotation axes; for finer control use `Rigidbody.constraints`.
- Layer filtering goes through the matrix. Manual `if (other.gameObject.layer == ...)` early-outs are not filtering.

## Verification

1. Console clean of warnings (non-convex MeshCollider, missing Rigidbody on trigger).
2. Sanity-cast a ray/overlap through the area; inspect hits. Missing collider = wrong layer mask or matrix.
3. Enable Gizmos in Game view to see collider outlines, capture a screenshot.
4. For 3D, run `unity-3d-verification` (4-shot orthographic) to confirm collider matches mesh.
5. For motion/stability, check Profiler "Physics" CPU module for step cost and count.

---
name: unity-physics
description: Use when working with Unity physics through Unity MCP — adding a Rigidbody/Rigidbody2D, configuring colliders or triggers, setting kinematic vs dynamic, freezing rotation, tweaking gravity, applying force or torque (AddForce, AddTorque, AddExplosionForce, MovePosition), raycasts and overlap queries, joints (3D or 2D), layer collision matrix edits, physics materials, FixedUpdate vs Update timing, or OnCollisionEnter/OnTriggerEnter callbacks. Covers both 3D and 2D physics; pick the fork that matches the scene. For rotation-specific tasks (Quaternion math, Atan2 facing, RectTransform pivot rotation) use unity-3d-rotation, unity-2d-rotation, or unity-ugui-rotation.
---

## When to use

Any task that touches Unity's physics simulation: bodies, colliders, joints, queries, materials, the layer matrix, fixed timestep, or collision/trigger callbacks. Covers both 3D (`Physics`, `Rigidbody`, `Collider`, `PhysicsMaterial`) and 2D (`Physics2D`, `Rigidbody2D`, `Collider2D`, `PhysicsMaterial2D`). 2D and 3D are independent simulations — pick one paradigm per scene.

## 3D vs 2D fork

Concepts share names; APIs and assets do not. Pick the column that matches the scene before doing anything.

| Concept                  | 3D                              | 2D                                  |
| ------------------------ | ------------------------------- | ----------------------------------- |
| Body                     | `Rigidbody`                     | `Rigidbody2D`                       |
| Collider base            | `Collider`                      | `Collider2D`                        |
| Mesh-shaped collider     | `MeshCollider`                  | `PolygonCollider2D`                 |
| Fixed joint              | `FixedJoint`                    | `FixedJoint2D`                      |
| Raycast                  | `Physics.Raycast`               | `Physics2D.Raycast`                 |
| Material asset           | `PhysicsMaterial`               | `PhysicsMaterial2D`                 |
| Gravity                  | `Physics.gravity` (Vector3)     | `Physics2D.gravity` (Vector2)       |
| Layer collision matrix   | shared 32 layers, separate UI panel under Project Settings > Physics | same layers, panel under Physics 2D |
| Hit struct               | `RaycastHit` (class-like struct)| `RaycastHit2D` (struct, implicit-bool true if hit) |
| Force modes              | `ForceMode` (4 values)          | `ForceMode2D` (Force, Impulse only) |

If the scene has a 3D Rigidbody and a Collider2D, they will not interact. Choose one.

## Setting up a body

Decision tree for any moving/colliding object:

1. **Static** — Collider only, no Rigidbody. Immovable world geometry. Cheapest. Do NOT translate or rotate it at runtime: Unity rebuilds the static collision tree and stalls. If it must move, give it a kinematic Rigidbody instead.
2. **Dynamic** — `Rigidbody` with `isKinematic = false`. Full simulation: gravity, forces, collision response. Default for players, enemies, props, projectiles unless overridden.
3. **Kinematic** — `Rigidbody` with `isKinematic = true`. Ignores forces and gravity, but participates in collision/trigger callbacks and sweeps. Drive it with `Rigidbody.MovePosition` / `MoveRotation` from FixedUpdate. Use for moving platforms, scripted obstacles, animated bodies, and any character controller that does its own movement math.
4. **Trigger** — any Collider with `isTrigger = true`. Fires `OnTriggerEnter/Stay/Exit`, no physical response. **At least one** of the two interacting objects must have a Rigidbody (kinematic is fine) or callbacks will not fire at all.

Anti-pattern: a Collider on a moving GameObject without any Rigidbody is a "static collider being moved" — Unity rebuilds the static tree every frame the transform changes. Fix: add a kinematic Rigidbody.

Add bodies and colliders via `manage_components` (component add/configure). Read or write transform via `manage_gameobject`. Wrap edits in undo via `manage_editor`.

## Colliders

**3D primitives (cheap):** `BoxCollider`, `SphereCollider`, `CapsuleCollider`. Prefer these. **`MeshCollider`** — set `convex = true` if attached to a Rigidbody (non-convex MeshColliders only work as static collision; pairing one with a dynamic Rigidbody silently fails to collide). **`TerrainCollider`** for Terrain. **`WheelCollider`** for vehicles (specialized — has its own suspension model, do not mix with regular collider stacks).

**2D primitives:** `BoxCollider2D`, `CircleCollider2D`, `CapsuleCollider2D`. **`PolygonCollider2D`** auto-fits a sprite outline (often too dense — simplify points). **`EdgeCollider2D`** for one-sided lines. **`CompositeCollider2D`** merges child colliders (or a `TilemapCollider2D`) into one efficient outline; on each child collider set `usedByComposite = true` and put the `CompositeCollider2D` plus a `Rigidbody2D` (Static or Kinematic) on the parent.

**Compound colliders:** several primitive colliders parented under one Rigidbody act as one body with a complex shape. Prefer this over MeshCollider whenever possible — faster, more stable, supports concave shapes for dynamic bodies.

Edge cases: colliders smaller than ~0.01 units cause solver instability. For very thin or very fast moving bodies set `Rigidbody.collisionDetectionMode = Continuous` (or `ContinuousDynamic` if both sides move fast); leave the wall on `Discrete`.

## Joints

Joints connect exactly two bodies. If `connectedBody` is null the second "body" is the world. Anchor positions are local to each body.

| 3D joint           | One-line use                                   |
| ------------------ | ---------------------------------------------- |
| `HingeJoint`       | doors, wheels, levers — single rotational axis |
| `FixedJoint`       | rigidly weld two bodies                        |
| `SpringJoint`      | soft tether / elastic connection               |
| `ConfigurableJoint`| do anything — preferred for advanced rigs      |
| `CharacterJoint`   | ragdoll limb (swing + twist limits)            |

| 2D joint            | One-line use                                  |
| ------------------- | --------------------------------------------- |
| `HingeJoint2D`      | rotational pivot, optional motor + limits     |
| `FixedJoint2D`      | rigid attach (uses a stiff spring internally) |
| `SpringJoint2D`     | dampened spring between two anchor points     |
| `DistanceJoint2D`   | maintain a fixed distance (rigid rod)         |
| `FrictionJoint2D`   | apply linear/angular friction between bodies  |
| `RelativeJoint2D`   | maintain a relative position/orientation      |
| `SliderJoint2D`     | linear track / piston with optional motor     |
| `TargetJoint2D`     | drag a body toward a world-space target       |
| `WheelJoint2D`      | suspension + driven wheel for 2D vehicles     |

For full configuration fields, motor/limit setup, and break-force tuning see `references/joints.md`. Add joints with `manage_physics` (action selects the joint type).

## Forces and motion

All physics writes belong in `FixedUpdate` (or in `manage_physics` actions that run on the next physics step). Reads for visuals belong in `Update`/`LateUpdate`.

3D `Rigidbody.AddForce(Vector3, ForceMode)` modes:

- `ForceMode.Force` — continuous force, scaled by mass and `fixedDeltaTime`. Default. Use for thrust-like effects.
- `ForceMode.Acceleration` — continuous, mass-ignored. Use when you want the same accel for all masses.
- `ForceMode.Impulse` — instantaneous, mass-scaled. Use for jumps, hits, bullet kicks.
- `ForceMode.VelocityChange` — instantaneous, mass-ignored. Use to set/add a velocity delta directly.

Other 3D entry points: `AddTorque(Vector3, ForceMode)`, `AddRelativeForce`, `AddForceAtPosition(force, worldPoint)` (also induces torque), `AddExplosionForce(force, explosionPos, radius, upwardsModifier, ForceMode)`.

```csharp
// Jump impulse, mass-scaled (impulse on a heavier body still feels equal-ish)
rb.AddForce(Vector3.up * jumpImpulse, ForceMode.Impulse);

// Constant thrust in FixedUpdate
void FixedUpdate() {
    rb.AddForce(transform.forward * thrust, ForceMode.Force);
}

// Scripted kinematic move (Rigidbody.isKinematic = true)
void FixedUpdate() {
    rb.MovePosition(rb.position + velocity * Time.fixedDeltaTime);
    rb.MoveRotation(rb.rotation * Quaternion.Euler(0, yawDeg, 0));
}
```

2D analogs: `Rigidbody2D.AddForce(Vector2, ForceMode2D)`, `AddTorque(float)`, `AddForceAtPosition`, `AddRelativeForce`. `ForceMode2D` has only `Force` and `Impulse` — there is no Acceleration / VelocityChange mode; for instantaneous mass-ignored changes write `linearVelocity` directly.

Velocity field rename: in Unity 6+ Rigidbody and Rigidbody2D expose `linearVelocity` (and `angularVelocity`); the older `velocity` is deprecated. Read and write whichever the project's Unity version exposes — check via `unity_reflect` if unsure.

For one-shot force application from tooling (no script), use `manage_physics` AddForce / AddTorque / AddExplosionForce actions.

## Queries (raycasts and overlaps)

Hot summary; full table and snippets in `references/queries.md`.

3D: `Physics.Raycast`, `RaycastAll`, `RaycastNonAlloc`, `Linecast`, `SphereCast`, `BoxCast`, `CapsuleCast`, `OverlapSphere`, `OverlapBox`, `CheckSphere`, `CheckBox`. Prefer the `*NonAlloc` (or `RaycastCommand` batched) variants in hot paths — `RaycastAll` allocates an array every call.

2D: `Physics2D.Raycast`, `RaycastAll`, `Linecast`, `CircleCast`, `BoxCast`, `CapsuleCast`, `OverlapCircle`, `OverlapBox`, `OverlapPoint`, `OverlapArea`, `GetRayIntersection` (the only way to ray-test 2D colliders projected from a 3D ray). 2D queries return `RaycastHit2D` (a struct that converts to `bool` true on hit).

Layer mask is critical — without one, queries hit every collider including the caster and triggers:

```csharp
// Hit everything EXCEPT IgnoreRaycast and Player layers
int mask = ~((1 << LayerMask.NameToLayer("IgnoreRaycast"))
           | (1 << LayerMask.NameToLayer("Player")));
if (Physics.Raycast(origin, dir, out RaycastHit hit, maxDist, mask,
                    QueryTriggerInteraction.Ignore)) { /* ... */ }
```

Globals: `Physics.queriesHitTriggers` (default true) and `Physics.queriesHitBackfaces` (default false). Override per call with the `QueryTriggerInteraction` argument.

For tooling-driven queries use `manage_physics` raycast / raycast_all / linecast / shapecast / overlap actions — these return hit GameObjects without authoring a script.

## Layers and collision matrix

Unity has exactly 32 layers (0–31). Layer 0 is `Default`. The collision matrix decides which pairs of layers can collide; toggle pairs off rather than putting collision logic in scripts. Edit via `manage_physics` (3D matrix) or the same action with the 2D variant — they are separate matrices.

Suggested baseline layout: `Default` for static world, plus dedicated layers for `Player`, `Enemy`, `Projectile`, `Trigger`, `IgnoreRaycast`. Then disable Enemy↔Enemy if enemies should pass through each other, Projectile↔OwnerFaction so a shooter doesn't hit themselves, etc.

Layer-based collision is configured ONLY through the matrix. Setting fields on the Collider does not filter by layer.

## Physics materials

3D `PhysicsMaterial` fields: `dynamicFriction`, `staticFriction`, `bounciness`, `frictionCombine`, `bounceCombine` (combine modes: Average, Minimum, Maximum, Multiply). Apply via `Collider.sharedMaterial` (preferred — does not duplicate the asset) or `Collider.material` (auto-instantiates a per-collider copy).

2D `PhysicsMaterial2D` fields (Unity 6 / 2023.2+): `friction`, `bounciness`, `frictionCombine`, `bounceCombine` (combine modes: Average, Minimum, Maximum, Multiply — same set as 3D). No static/dynamic friction split. Footnote: on Unity 2022 LTS the combine fields are not exposed and contacts always average — this skill set targets Unity 6, so the combine fields are available.

Create or edit material assets via `manage_material`. The 3D and 2D assets are different file types — do not assign one to the other's collider.

Edits to existing material fields do not retroactively affect contacts already in progress; reassign `Collider.sharedMaterial` (or briefly disable/enable the collider) to refresh.

Footnote: `PhysicMaterial` (no `s`) is the deprecated alias kept for back-compat with 2022 LTS — Unity 6 canonical is `PhysicsMaterial`.

## Fixed timestep and order of execution

`Time.fixedDeltaTime` defaults to 0.02 s (50 Hz). Increase the rate for small fast objects, but cost is roughly linear in steps per second and stacks with collision work — do not casually drop to 0.005.

Per-frame order: `FixedUpdate` (zero or more times per frame, until simulation catches up) → internal physics step → `OnCollisionEnter/Stay/Exit`, `OnTriggerEnter/Stay/Exit` → `Update` → coroutines → `LateUpdate` → rendering.

Rules that follow:

- All forces, velocity writes, and `MovePosition`/`MoveRotation` go in `FixedUpdate`.
- Visual reads of physics state (camera follow, UI) go in `LateUpdate`.
- Set `Rigidbody.interpolation = Interpolate` on bodies the camera tracks; `Extrapolate` only for predictable motion (it visibly wrongs on impacts). Default `None` is fine for non-tracked bodies.
- `Physics.simulationMode` (formerly `Physics.autoSimulation`) defaults to `FixedUpdate`. Setting it to `Script` lets you call `Physics.Simulate(dt)` manually — useful for deterministic replay or editor tooling.

## Gotchas

- Non-uniform scale on a parent transform distorts child colliders (especially capsules and spheres) — collisions become wrong without warning. Keep physics roots on uniform scale; put visual mesh on a scaled child.
- `MeshCollider` with `convex = false` paired with a Rigidbody silently does not collide. Either set convex true or remove the Rigidbody.
- Writing `transform.position` on a body with a Rigidbody teleports without a sweep — bodies clip through walls and miss collision events. Use `Rigidbody.MovePosition` (sweeps) or set `Rigidbody.position` directly (still teleports but stays in sync with the simulation).
- `OnTriggerEnter` (and `OnCollisionEnter`) require at least one Rigidbody on the pair. Two static colliders never produce events.
- 2D and 3D physics are entirely separate worlds — a `Rigidbody` does not collide with a `Collider2D`, ever.
- `ContinuousDynamic` CCD is expensive. Use `Continuous` on the moving body and leave walls on `Discrete`; reserve `ContinuousDynamic` for small fast bullets that must hit other moving things.
- `Rigidbody.freezeRotation` is a shortcut for locking all three rotation axes; for finer control use `Rigidbody.constraints` (per-axis position and rotation flags).
- The collision matrix is the only correct way to filter which layers collide. Do not add manual `if (other.gameObject.layer == ...)` early-outs in `OnCollisionEnter` and call it filtering.

## Verification

After any physics change, run a layered check:

1. `read_console` for warnings (non-convex MeshCollider, missing Rigidbody on trigger, etc.).
2. Sanity-cast a ray through the configured area with `manage_physics` raycast/overlap and inspect what was hit. If a collider doesn't show up, layer mask or matrix is wrong.
3. Enable Gizmos in the Game view to see collider outlines, then capture a screenshot.
4. For 3D, invoke the `unity-3d-verification` skill (4-shot orthographic) to confirm collider shapes line up with the visible mesh.
5. For motion or stability concerns use `manage_profiler` (Profiler / Frame Debugger) to confirm the physics step cost and step count are sane (look at the "Physics" CPU module).

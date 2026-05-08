# Queries reference

Detail companion to `SKILL.md` > Queries. Every shape-cast and overlap call exists in 3D (`Physics.*`) and 2D (`Physics2D.*`) variants; pick the one matching the scene paradigm. For tooling-driven (no-script) lookups call `manage_physics` with raycast / raycast_all / linecast / shapecast / overlap actions instead of authoring code.

## 3D queries

| API                    | Returns                  | Notes                                            |
| ---------------------- | ------------------------ | ------------------------------------------------ |
| `Physics.Raycast`      | bool, out `RaycastHit`   | Closest hit. Most common.                        |
| `Physics.RaycastAll`   | `RaycastHit[]` (alloc)   | All hits along the ray. Order is undefined — sort by `distance` if you need nearest-first. |
| `Physics.RaycastNonAlloc` | int (count)           | Fills a caller-owned buffer. Use in hot paths.   |
| `RaycastCommand.ScheduleBatch` | Job-System batch | Best for hundreds+ of casts per frame.          |
| `Physics.Linecast`     | bool, out `RaycastHit`   | Two world points instead of origin+direction.    |
| `Physics.SphereCast` / `BoxCast` / `CapsuleCast` | bool, out hit | Sweep a shape along the ray. Catches thin gaps that Raycast misses. Each has an `*All` and `*NonAlloc` variant. |
| `Physics.OverlapSphere` / `OverlapBox` / `OverlapCapsule` | `Collider[]` | All colliders intersecting the shape (no direction). |
| `Physics.CheckSphere` / `CheckBox` / `CheckCapsule` | bool | Cheaper "does anything overlap?" without returning hits. |
| `Physics.ComputePenetration` | bool, out direction/distance | Resolve overlap between two specific colliders — useful for character controllers. |

## 2D queries

| API                    | Returns                                        | Notes                                |
| ---------------------- | ---------------------------------------------- | ------------------------------------ |
| `Physics2D.Raycast`    | `RaycastHit2D` (struct, true on hit)           | Implicit-bool conversion: `if (hit) ...`. |
| `Physics2D.RaycastAll` | `RaycastHit2D[]`                               | Allocates.                           |
| `Physics2D.RaycastNonAlloc` | int (count) into caller buffer            | Hot-path version.                    |
| `Physics2D.Linecast`   | `RaycastHit2D`                                 |                                      |
| `Physics2D.CircleCast` / `BoxCast` / `CapsuleCast` | `RaycastHit2D` | Shape sweeps; each has `*All` / `*NonAlloc`. |
| `Physics2D.OverlapCircle` / `OverlapBox` / `OverlapCapsule` / `OverlapPoint` / `OverlapArea` | `Collider2D` | Each has `*All` and `*NonAlloc`.   |
| `Physics2D.GetRayIntersection` | `RaycastHit2D`                         | The only way to ray-test 2D colliders projected from a 3D camera ray. |

`RaycastHit2D` is a struct; comparing to `null` is wrong — use the implicit bool or `hit.collider != null`.

## Layer mask cookbook

```csharp
// Hit only the Enemy and Boss layers
int mask = (1 << LayerMask.NameToLayer("Enemy"))
         | (1 << LayerMask.NameToLayer("Boss"));

// Hit everything except Player and IgnoreRaycast
int mask = ~((1 << LayerMask.NameToLayer("Player"))
           | (1 << LayerMask.NameToLayer("IgnoreRaycast")));

// From an inspector-exposed LayerMask field
[SerializeField] LayerMask groundMask;
Physics.Raycast(origin, Vector3.down, out var hit, 1.5f, groundMask,
                QueryTriggerInteraction.Ignore);
```

`QueryTriggerInteraction` (3D arg, last position): `UseGlobal` (default — follows `Physics.queriesHitTriggers`), `Ignore`, `Collide`. The 2D APIs honor `Physics2D.queriesHitTriggers` globally and do not accept a per-call override on most overloads — set the global before the call if you need to flip it.

## Performance notes

- `*All` variants allocate every call. Either reuse via `*NonAlloc` with a preallocated array, or batch with `RaycastCommand` for very large fan-outs.
- `OverlapSphereNonAlloc` etc. exist; check the count return for buffer overflow.
- Avoid casting from inside the caster's own collider — the cast can self-hit. Either start the ray slightly outside, exclude the caster's layer, or temporarily disable the collider.
- `Physics.queriesHitBackfaces` defaults false; flip it on if you need to detect rays hitting reversed-normal geometry (rare; usually fix the mesh).
- Sphere/box/capsule casts with `maxDistance = 0` degenerate — pass a small positive distance even when you want a near-static check, or use the `Overlap*` family instead.

# Queries reference

Companion to `SKILL.md` > Queries. Every shape-cast and overlap exists in 3D (`Physics.*`) and 2D (`Physics2D.*`).

## 3D queries

| API | Returns | Notes |
| --- | --- | --- |
| `Physics.Raycast` | bool, out `RaycastHit` | Closest hit. Most common. |
| `Physics.RaycastAll` | `RaycastHit[]` (alloc) | All hits along ray. Order undefined — sort by `distance` for nearest-first. |
| `Physics.RaycastNonAlloc` | int (count) | Caller-owned buffer. Hot paths. |
| `RaycastCommand.ScheduleBatch` | Job-System batch | 100s+ casts per frame. |
| `Physics.Linecast` | bool, out `RaycastHit` | Two world points instead of origin+direction. |
| `Physics.SphereCast` / `BoxCast` / `CapsuleCast` | bool, out hit | Sweep a shape. Catches gaps Raycast misses. Each has `*All` and `*NonAlloc`. |
| `Physics.OverlapSphere` / `OverlapBox` / `OverlapCapsule` | `Collider[]` | All colliders intersecting the shape. |
| `Physics.CheckSphere` / `CheckBox` / `CheckCapsule` | bool | Cheaper "does anything overlap?". |
| `Physics.ComputePenetration` | bool, out direction/distance | Resolve overlap between two specific colliders — character controllers. |

## 2D queries

| API | Returns | Notes |
| --- | --- | --- |
| `Physics2D.Raycast` | `RaycastHit2D` (struct, true on hit) | `if (hit) ...` via implicit bool. |
| `Physics2D.RaycastAll` | `RaycastHit2D[]` | Allocates. |
| `Physics2D.RaycastNonAlloc` | int (count) into caller buffer | Hot path. |
| `Physics2D.Linecast` | `RaycastHit2D` | |
| `Physics2D.CircleCast` / `BoxCast` / `CapsuleCast` | `RaycastHit2D` | Each has `*All`/`*NonAlloc`. |
| `Physics2D.OverlapCircle` / `OverlapBox` / `OverlapCapsule` / `OverlapPoint` / `OverlapArea` | `Collider2D` | Each has `*All`/`*NonAlloc`. |
| `Physics2D.GetRayIntersection` | `RaycastHit2D` | Only way to ray-test 2D colliders from a 3D camera ray. |

`RaycastHit2D` is a struct; comparing to `null` is wrong — use implicit bool or `hit.collider != null`.

## Layer mask cookbook

```csharp
// Hit only Enemy and Boss
int mask = (1 << LayerMask.NameToLayer("Enemy"))
         | (1 << LayerMask.NameToLayer("Boss"));

// Hit everything except Player and IgnoreRaycast
int mask = ~((1 << LayerMask.NameToLayer("Player"))
           | (1 << LayerMask.NameToLayer("IgnoreRaycast")));

// Inspector-exposed LayerMask
[SerializeField] LayerMask groundMask;
Physics.Raycast(origin, Vector3.down, out var hit, 1.5f, groundMask,
                QueryTriggerInteraction.Ignore);
```

`QueryTriggerInteraction` (3D, last arg): `UseGlobal` (follows `Physics.queriesHitTriggers`), `Ignore`, `Collide`. 2D APIs honor `Physics2D.queriesHitTriggers` globally and don't accept per-call override on most overloads — flip the global if needed.

## Performance notes

- `*All` allocates per call. Use `*NonAlloc` with preallocated array, or `RaycastCommand` for large fan-outs.
- `OverlapSphereNonAlloc` etc. exist; check count return for buffer overflow.
- Don't cast from inside the caster's collider — self-hits. Start outside, exclude caster's layer, or briefly disable the collider.
- `Physics.queriesHitBackfaces` defaults false; flip on for reversed-normal geometry (rare; usually fix the mesh).
- Sphere/box/capsule casts with `maxDistance = 0` degenerate — pass a small positive distance or use `Overlap*`.

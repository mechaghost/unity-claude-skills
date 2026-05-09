---
name: unity-navmesh
description: 'Use when working with Unity AI navigation and pathfinding through Unity MCP — NavMesh, NavMeshAgent, NavMeshObstacle, NavMeshSurface, NavMeshLink, NavMesh Components, NavMesh Modifier, AI Navigation, com.unity.ai.navigation, pathfinding, agent radius, agent height, agent slope, area mask, area cost, off-mesh link, runtime bake, NavMeshHit, SamplePosition, CalculatePath, NavMesh.Raycast, agent stopping distance, agent acceleration, agent angular speed, navmesh bake, walkable area, jump links, drop links. Unity 6, URP-only, new Input System only.'
---

## When to use

AI movement / pathfinding: enemy patrol, follow-player, click-to-move, RTS units, NPC routes, jump-down ledges, doorways, procedural traversal.

## Modern AI Navigation package vs legacy

Use `com.unity.ai.navigation`. Component-based: `NavMeshSurface`, `NavMeshLink`, `NavMeshModifier`, `NavMeshModifierVolume`. Multiple surfaces, agent types, per-object area overrides without the static flag.

Legacy "Navigation Static" flag + `Window > AI > Navigation (Obsolete)` is deprecated — bakes live in scene rather than as assets, can't be parameterized, no runtime rebakes.

## Setup

1. Install `com.unity.ai.navigation`.
2. Add `NavMeshSurface` to a parent (level root).
3. Click **Bake**. Generates a NavMesh asset stored next to the scene; blue overlay in Scene view.

Procedural levels: skip editor bake, call `BuildNavMesh()` at runtime.

## NavMeshSurface (baking)

- **Agent Type** — from `Project Settings > AI > Navigation`. Each has its own bake parameters (radius, height, max slope, step height). Multi-agent (scout + tank) needs multiple types and one bake per type.
- **Collect Objects** — `All`/`Volume`/`Children`. `Children` is most predictable.
- **Include Layers** — which layers' colliders contribute.
- **Use Geometry** — `RenderMeshes` (visual mesh, more accurate, slower) or `PhysicsColliders` (matches physics — pick this so AI agrees with `Physics.Raycast`).
- **Bake** generates the asset; **Clear** removes it.

## Agents

Add `NavMeshAgent`. Key fields:

| Field | Purpose |
| --- | --- |
| Speed | Max move speed (m/s). |
| Angular Speed | Rotation speed (deg/s). |
| Acceleration | How fast it reaches Speed. |
| Stopping Distance | Distance from destination at which it stops. |
| Auto Braking | Slow as approaching destination (off for waypoints). |
| Radius / Height | Local-avoidance footprint; match agent type. |
| Avoidance Priority | Lower wins ties (0–99). Bosses 0, mooks 50. |
| Quality | Local-avoidance quality: None / Low / Med / High / Good. |

Drive: `agent.SetDestination(targetPos)`. Read: `agent.remainingDistance`, `hasPath`, `pathPending`, `velocity`, `isOnNavMesh`. Stop: `agent.isStopped = true` (preferred — keeps path) or `ResetPath()` (clears). Teleport: `agent.Warp(pos)` to stay snapped.

## Areas and costs

- 32 named areas in `Project Settings > AI > Navigation > Areas`. Defaults: `Walkable`, `Not Walkable`, `Jump`. Add `Water`, `Mud`, `Door` etc.
- Per-mesh: `NavMeshModifier` (override on this object) or `NavMeshModifierVolume` (override inside a box — mark water without modifying terrain).
- **Area Cost** — per-area float multiplier. `Walkable=1`, `Jump=2`, `Mud=3`. Pathfinder sums; higher = routes around.
- Agent **Area Mask** filters which areas the agent can use.

## Off-mesh links and NavMeshLink

Use `NavMeshLink` (modern); legacy `OffMeshLink` is replaced. Manually placed link between two points. Trigger jumps, drop-down ledges, ladders, doors.

- **Cost Override** + **Area Type** per link (typically `Jump`).
- **Auto Traverse Off-Mesh Link** on = linear slide; off = script the traversal (animation, IK, parabolic arc).
- Detect: `agent.isOnOffMeshLink`, then `agent.currentOffMeshLinkData`. Move yourself (animation, parabola). Call `agent.CompleteOffMeshLink()` when done.

## Obstacles vs carving

- **Static obstacles** baked into NavMesh — agents path around at no runtime cost.
- **Dynamic obstacles** (cart, door): `NavMeshObstacle`. Two modes:
  - **Avoidance only** (`Carve = false`) — local avoidance, baked NavMesh unaffected. Cheap. Moving NPCs/vehicles.
  - **`Carve = true`** — cuts a hole at runtime. Allows pathfinding around. Expensive. Doors and large blockers; never per-enemy.

## Runtime baking

`surface.BuildNavMesh()` (sync) or `surface.BuildNavMeshAsync()` (returns `AsyncOperation`).

Pattern: spawn geometry → `BuildNavMesh()` → spawn agents (after sampling). Budget 100–500 ms for medium levels — do during a load screen.

## Path queries (no agent required)

- `NavMesh.CalculatePath(from, to, areaMask, NavMeshPath path)` — `true` if complete; populates `path.corners`. UI previews, reachability.
- `NavMesh.SamplePosition(pos, out NavMeshHit hit, maxDistance, areaMask)` — nearest NavMesh point. Critical before spawning agents.
- `NavMesh.Raycast` — line-of-sight along the surface; stops at edges. "Can I see player without going around walls".
- `NavMesh.FindClosestEdge` — distance to nearest edge ("am I cornered").

## Common patterns

- **Patrol** — waypoint array; advance when `remainingDistance < threshold && !pathPending`.
- **Follow player** — `SetDestination(player.position)` every 0.2–0.5 s, not every frame. Each call re-paths.
- **Click-to-move** — camera raycast → `NavMesh.SamplePosition` to snap → `SetDestination(hit.position)`.
- **Spawning agents** — `SamplePosition(spawnHint, out hit, 5f, NavMesh.AllAreas)` then `Instantiate` at `hit.position`. Without sampling, off-ground spawns throw `Failed to create agent because there is no valid NavMesh`.
- **Jump links** — `NavMeshLink` with `Area = Jump`, high cost; disable Auto Traverse, play jump animation along a parabola, then `CompleteOffMeshLink()`.
- **Door** — `NavMeshObstacle` with `Carve`; toggle `obstacle.enabled` on state change.
- **Multi-floor** — single `NavMeshSurface` with stairs/ramps + `NavMeshLink` for jump-downs. Or one surface per floor (easier to rebake one).
- **Animator from NavMeshAgent**:
  ```csharp
  NavMeshAgent agent;
  Animator animator;
  static readonly int SpeedHash = Animator.StringToHash("Speed");
  void Update() {
      float normalizedSpeed = agent.velocity.magnitude / agent.speed;
      animator.SetFloat(SpeedHash, normalizedSpeed, 0.1f, Time.deltaTime);
  }
  ```
  For root-motion characters set `Apply Root Motion = false`; otherwise NavMeshAgent and Animator fight.

## Gotchas

- Agent not on a NavMesh = `SetDestination` silently no-ops. Check `agent.isOnNavMesh`. Fix: spawn after `SamplePosition`, or `agent.Warp(samplePos)`.
- Geometry not in **Include Layers** = no nav surface there.
- Slopes > **Max Slope** = not walkable; agents stop at edge.
- **Step Height** too small = agents fail single stairs.
- Multi-agent-type = bake per type. One bake doesn't serve multiple radii.
- Agent radius/height match visual. Too small = clips walls; too large = gaps in tight corridors.
- Carving is heavy. Never per-enemy — local avoidance handles agent-vs-agent.
- `agent.velocity` is the agent's velocity, NOT a Rigidbody. NavMeshAgents move the transform directly — no Rigidbody needed.
- `NavMeshAgent` + non-kinematic Rigidbody fight for the transform. Use one. If Rigidbody is required (trigger callbacks), make it kinematic.
- Off-mesh links with auto-traverse linearly tween — visually weak for jumps. Disable + script the arc.
- 2D: built-in NavMesh is 3D-only. Use `NavMeshPlus` fork, A* Pathfinding Project, or custom grid.

## Verification

- Scene view: enable AI Navigation overlay. Blue surface should cover walkable area cleanly with no holes under stairs/ramps.
- Console clean of `Failed to create agent because there is no valid NavMesh` and `SetDestination called on agent that is not on NavMesh`.
- In Play mode, `Debug.DrawLine` `agent.path.corners` segments to visualize.
- For procedural levels, time `BuildNavMesh` (`Stopwatch`); confirm it fits the load-screen budget.
- Smoke test: agent at spawn → set destination across level → arrives without warping or stalling.

## Related skills

- `unity-animation` — jump traversal animation during off-mesh-link.
- `unity-physics` — collider source when `Use Geometry = PhysicsColliders`; layer matrix.
- `unity-scenes` — per-scene NavMesh assets and additive scene loading.

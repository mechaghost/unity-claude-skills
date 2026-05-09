---
name: unity-navmesh
description: Use when working with Unity AI navigation and pathfinding through Unity MCP — NavMesh, NavMeshAgent, NavMeshObstacle, NavMeshSurface, NavMeshLink, NavMesh Components, NavMesh Modifier, AI Navigation, com.unity.ai.navigation, pathfinding, agent radius, agent height, agent slope, area mask, area cost, off-mesh link, runtime bake, NavMeshHit, SamplePosition, CalculatePath, NavMesh.Raycast, agent stopping distance, agent acceleration, agent angular speed, navmesh bake, walkable area, jump links, drop links. Unity 6, URP-only, new Input System only.
---

## When to use

Any AI movement or pathfinding work: enemy patrol, follow-the-player, click-to-move, RTS units, NPC routes, jump-down ledges, doorways, procedural-level traversal. If a GameObject needs to find its way around static or dynamic geometry without a custom pathfinder, NavMesh is the answer.

## Modern AI Navigation package vs legacy

Use the **AI Navigation package** (`com.unity.ai.navigation`). It adds the component-based workflow: `NavMeshSurface`, `NavMeshLink`, `NavMeshModifier`, `NavMeshModifierVolume`. Each scene/level can have multiple surfaces, multiple agent types, and per-object area overrides without touching the static flag.

The legacy "Navigation Static" flag plus `Window > AI > Navigation (Obsolete)` panel still exists in Unity 6 but is deprecated. Don't use it for new content — bakes live in the scene rather than as assets, can't be parameterized per-object cleanly, and don't support runtime rebakes.

Install: `manage_packages` add `com.unity.ai.navigation`. The component inspectors replace the old window.

## Setup

1. Install `com.unity.ai.navigation`.
2. Add a `NavMeshSurface` to a parent GameObject (typically the level root).
3. Click **Bake** on the surface inspector. Generates a NavMesh asset stored next to the scene; visualizes as a blue overlay in the Scene view.

For procedurally-spawned levels, skip the editor bake and call `BuildNavMesh()` at runtime (see Runtime baking).

## NavMeshSurface (baking)

- **Agent Type**: pick from `Project Settings > AI > Navigation`. Each agent type has its own bake parameters (radius, height, max slope, step height). Multi-agent games (small scout + large tank) need multiple agent types and one bake per type.
- **Collect Objects**: `All` / `Volume` / `Children`. `Children` is the most predictable — only descendants of the surface contribute.
- **Include Layers**: which layers' colliders contribute to the bake.
- **Use Geometry**: `RenderMeshes` (visual mesh, more accurate, slower) or `PhysicsColliders` (matches the physics world; usually what you want so AI agrees with `Physics.Raycast`).
- **Bake** generates the NavMesh asset; **Clear** removes it.

## Agents

Add a `NavMeshAgent` component. Key fields:

| Field             | Purpose                                              |
| ----------------- | ---------------------------------------------------- |
| Speed             | Max move speed (m/s).                                |
| Angular Speed     | Rotation speed (deg/s).                              |
| Acceleration      | How fast it reaches Speed.                           |
| Stopping Distance | Distance from destination at which it stops.         |
| Auto Braking      | Slow as approaching destination (off for waypoints). |
| Radius / Height   | Local-avoidance footprint; usually match agent type. |
| Avoidance Priority| Lower wins ties (0-99). Bosses 0, mooks 50.          |
| Quality           | Local-avoidance quality: None / Low / Med / High / Good. |

Drive: `agent.SetDestination(targetPos)` — kicks off pathfinding. Read state with `agent.remainingDistance`, `agent.hasPath`, `agent.pathPending`, `agent.velocity`, `agent.isOnNavMesh`. Stop with `agent.isStopped = true` (preferred — keeps the path) or `agent.ResetPath()` (clears it). Teleport with `agent.Warp(pos)` to stay snapped to the NavMesh.

## Areas and costs

- 32 named areas configured in `Project Settings > AI > Navigation > Areas`. Defaults: `Walkable`, `Not Walkable`, `Jump`. Add e.g. `Water`, `Mud`, `Door`.
- Apply per-mesh: `NavMeshModifier` (override area on this object) or `NavMeshModifierVolume` (override area inside a box volume — useful for marking water without modifying the terrain).
- **Area Cost**: per-area float multiplier. `Walkable=1`, `Jump=2`, `Mud=3`. Pathfinder sums costs along the path; higher cost biases the search to route around.
- Agent **Area Mask** filters which areas the agent can use (e.g. amphibious unit can use `Water`; ground unit cannot).

## Off-mesh links and NavMeshLink

Use `NavMeshLink` (modern) — the legacy `OffMeshLink` is replaced. Manually placed link between two points; agents traverse with `agent.isOnOffMeshLink`. Trigger jumps, drop-down ledges, ladders, doors.

- Set **Cost Override** and **Area Type** per link (typically `Jump` for jumps so it costs more than ground).
- **Auto Traverse Off-Mesh Link** (agent setting): if on, the agent slides linearly between endpoints. Disable to script the traversal — animation, IK, parabolic jump arc.
- Detect: `agent.isOnOffMeshLink == true`, then `OffMeshLinkData data = agent.currentOffMeshLinkData`. Move the agent yourself (animation, parabola). Call `agent.CompleteOffMeshLink()` when done.

## Obstacles vs carving

- **Static obstacles** baked into the NavMesh = part of the surface; agents path around them at no runtime cost.
- **Dynamic obstacles** (moving cart, opening door): add `NavMeshObstacle`. Two modes:
  - **Avoidance only** (`Carve = false`): agents avoid via local avoidance, but the baked NavMesh is unaffected. Cheap. Use for moving NPCs/vehicles.
  - **`Carve = true`**: dynamically cuts a hole in the NavMesh at runtime. Allows pathfinding around the obstacle. Expensive. Use for doors and large dynamic blockers; never per-enemy.

## Runtime baking

For procedural levels: `surface.BuildNavMesh()` rebuilds synchronously. Async via `surface.BuildNavMeshAsync()` (returns `AsyncOperation`).

Pattern: spawn level geometry → `BuildNavMesh()` → spawn AI agents (after sampling, see below). Cost scales with mesh complexity; budget 100-500ms for medium levels — do it during a load screen or on a background frame.

## Path queries (no agent required)

- `NavMesh.CalculatePath(from, to, areaMask, NavMeshPath path)` — returns `true` if a complete path exists; populates `path.corners`. Use for UI path previews or reachability tests.
- `NavMesh.SamplePosition(pos, out NavMeshHit hit, maxDistance, areaMask)` — find the nearest NavMesh point to a position. Critical before spawning agents.
- `NavMesh.Raycast` — line-of-sight along the NavMesh surface; stops at NavMesh edges. Good for "can I see the player without going around walls".
- `NavMesh.FindClosestEdge` — distance to nearest edge ("am I cornered" checks).

## Common patterns

- **Patrol**: array of waypoints; advance when `agent.remainingDistance < threshold && !agent.pathPending`.
- **Follow player**: re-issue `agent.SetDestination(player.position)` every 0.2-0.5s, not every frame. Each call triggers a re-path.
- **Click-to-move**: raycast from camera; on hit, `NavMesh.SamplePosition` to snap to NavMesh; `agent.SetDestination(hit.position)`.
- **Spawning agents**: `NavMesh.SamplePosition(spawnHint, out hit, 5f, NavMesh.AllAreas)` then `Instantiate` at `hit.position`. Without sampling, agents instantiated above ground throw `Failed to create agent because there is no valid NavMesh`.
- **Jump links**: `NavMeshLink` with `Area = Jump`, high cost so the pathfinder prefers ground; disable Auto Traverse and play a jump animation while moving the transform along a parabola, then `agent.CompleteOffMeshLink()`.
- **Door**: `NavMeshObstacle` on the door with `Carve` enabled; toggle `obstacle.enabled` (or the carve flag) when door state changes. Surrounding NavMesh updates automatically.
- **Multi-floor levels**: bake on a single `NavMeshSurface` with stairs/ramps included; use `NavMeshLink` for jump-downs between floors. Or one surface per floor connected by links — easier to rebake one floor.
- **Driving an Animator from a NavMeshAgent**:
  ```csharp
  // Read the agent's velocity each frame and feed it to a Speed parameter on the Animator.
  // Cache the Animator hash for zero-allocation SetFloat calls.
  NavMeshAgent agent;
  Animator animator;
  static readonly int SpeedHash = Animator.StringToHash("Speed");
  void Update() {
      // Normalize agent velocity to 0..1 against agent.speed for blend-tree compatibility.
      float normalizedSpeed = agent.velocity.magnitude / agent.speed;
      animator.SetFloat(SpeedHash, normalizedSpeed, 0.1f, Time.deltaTime); // damping smooths transitions
  }
  ```
  Note: `0.1f` damp time + Time.deltaTime smooths state transitions in the Animator's blend tree. For root-motion characters, set `Apply Root Motion = false` on the Animator and let NavMeshAgent drive position; otherwise the two fight.

## Gotchas

- Agent not on a NavMesh = `SetDestination` does nothing silently. Always check `agent.isOnNavMesh`. Fix: spawn after `SamplePosition`, or `agent.Warp(samplePos)`.
- Static collider geometry not in the bake's **Include Layers** = no nav surface where you expected it.
- Slopes steeper than the agent type's **Max Slope** are not walkable; agents stop at the edge.
- **Step Height** too small = agents fail to climb a single stair.
- Multiple agent types require a bake per type (`NavMeshSurface` per type, or one with explicit Agent Type override). One bake does not serve multiple radii.
- Agent radius/height should match the visual character. Too small = agents clip walls; too large = bake leaves gaps in tight corridors.
- Carving `NavMeshObstacle`s is performance-heavy. Avoid per-enemy carving — local avoidance handles agent-vs-agent.
- `agent.velocity` reads the agent's own velocity, NOT a Rigidbody. NavMeshAgents do not need a Rigidbody — the agent moves the transform directly.
- Mixing `NavMeshAgent` + `Rigidbody` (non-kinematic) = the two systems fight for the transform. Use one or the other; agents are non-physical. If a Rigidbody is required (e.g. to receive trigger callbacks), make it kinematic.
- Off-mesh links with auto-traverse linearly tween between endpoints — visually unconvincing for jumps. Disable Auto Traverse and script the arc.
- 2D games: built-in NavMesh is 3D-only. Use the community `NavMeshPlus` fork or roll a 2D pathfinder (A* Pathfinding Project, custom grid).

## Verification

- Scene view: enable the AI Navigation overlay (`View > AI Navigation` in Unity 6, or open the AI Navigation window). The blue surface should cover walkable area cleanly with no holes under stairs/ramps.
- `read_console` for `Failed to create agent because there is no valid NavMesh` and `SetDestination called on agent that is not on NavMesh` — both indicate the agent spawned off-mesh.
- In Play mode, draw `agent.path.corners` as `Debug.DrawLine` segments to visualize the active path.
- For procedural levels, time the runtime bake (`Stopwatch` around `BuildNavMesh`); ensure it fits the level-transition budget.
- Smoke test: place an agent at spawn, set a destination across the level, confirm it arrives without warping or stalling.

## Related skills

- `unity-animation` — jump traversal animation while off-mesh-link is active.
- `unity-physics` — collider geometry source when `Use Geometry = PhysicsColliders`; layer matrix interactions.
- `unity-scenes` — per-scene NavMesh assets and additive scene loading.
- `unity-best-practices` — read console after every bake, prefer `batch_execute`, pick one paradigm.

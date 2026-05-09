---
name: unity-dots-jobs-burst
description: 'Use when working with Unity''s data-oriented technology stack via Unity MCP — DOTS, ECS, Entities, com.unity.entities, com.unity.collections, com.unity.burst, Burst compiler, Job System, IJob, IJobParallelFor, IJobChunk, IJobEntity, NativeArray, NativeList, NativeHashMap, NativeReference, NativeSlice, Allocator, TempJob, Persistent, SystemBase, ISystem, EntityManager, EntityQuery, EntityCommandBuffer, ECB, IComponentData, IBufferElementData, tag component, archetype, chunk, ComponentSystemGroup, SimulationSystemGroup, hybrid GameObject ECS, BakingSystem, SubScene, EntityQueryDesc, ScheduleParallel, JobHandle, Complete, dependency chain, deterministic simulation, Burst-compatible, FunctionPointer, Unity.Mathematics, float3, quaternion, BlobAsset, NetCode for Entities. Unity 6+ / Entities 1.x. NOT for MonoBehaviour-based gameplay (use unity-physics, unity-animation, unity-patterns), NOT for general profiling (use unity-profiling).'
---

## When to use

Reach for DOTS when the workload is genuinely data-heavy: simulation with thousands of entities (RTS units, projectiles, swarm AI, particles you want CPU-driven), deterministic simulation (multiplayer rollback, replay), CPU-bound games where the GPU isn't the bottleneck, procedural worlds with many active objects. Cache locality plus Burst compilation gives 10-100x over MonoBehaviour for these workloads.

Do NOT use DOTS for: small-cast games (under ~100 active entities — MonoBehaviour is simpler and faster to iterate on), UI work, designer-tweaked content (DOTS workflows are programmer-heavy, weak Inspector story), or general "make it faster" without profiling first. Burst alone (no ECS) is a separate option for hot loops in regular code — see "Burst standalone" below.

## Mental model

ECS splits data and behavior. **Entities** are integer IDs. **Components** are pure data structs (`IComponentData`). **Systems** are functions that query entities by component combination and process them in tight loops. **Archetypes** group entities with the same set of components; **chunks** are 16KB blocks of contiguous archetype data — that contiguity is where the cache wins come from. Burst then compiles the system code to vectorized native instructions.

Translation table:
- GameObject -> Entity
- MonoBehaviour fields -> IComponentData struct
- Update() -> System.OnUpdate
- GetComponent<T> -> SystemAPI.GetComponent<T>(entity) or query
- Instantiate -> EntityManager.Instantiate or ECB.Instantiate
- Destroy -> EntityManager.DestroyEntity or ECB.DestroyEntity

## Package install

`com.unity.entities` brings in `com.unity.collections`, `com.unity.burst`, `com.unity.mathematics` automatically. For rendering entities: `com.unity.entities.graphics` (Hybrid Renderer / Entities Graphics). For networking: `com.unity.netcode` (Netcode for Entities — separate package and stack from Netcode for GameObjects). Editor windows live under `Window > Entities > Hierarchy / Components / Systems`.

Add via the package manager. Verify in the Editor console after install — Burst and Entities both emit version banners.

## Hello DOTS in 30 lines

```csharp
using Unity.Entities;
using Unity.Burst;
using Unity.Mathematics;
using Unity.Transforms;

public struct Velocity : IComponentData {
    public float3 value;
}

[BurstCompile]
public partial struct MoveSystem : ISystem {
    [BurstCompile]
    public void OnUpdate(ref SystemState state) {
        float dt = SystemAPI.Time.DeltaTime;
        foreach (var (xform, vel) in
                 SystemAPI.Query<RefRW<LocalTransform>, RefRO<Velocity>>()) {
            xform.ValueRW.Position += vel.ValueRO.value * dt;
        }
    }
}
```

Every entity with `LocalTransform` + `Velocity` moves each frame, Burst-compiled, single-threaded on the main thread. The `[BurstCompile]` attribute on both the struct and the method enables Burst — both are required.

## IComponentData / IBufferElementData / Tag components

- **IComponentData**: pure-data struct on an entity. Allowed types: `int`, `float`, `bool`, `float3`, `quaternion`, `Entity` references, fixed-size arrays via `FixedListN`, blittable structs. NO `string`, NO `class`, NO `List<T>`, NO managed references.
- **IBufferElementData**: dynamic per-entity buffer. Access via `EntityManager.GetBuffer<T>(entity)` or `SystemAPI.GetBuffer<T>(entity)`. Use for variable-size collections owned by an entity (unit's inventory, spline points, recent damage events).
- **Tag components**: `IComponentData` with no fields. Mark entities for queries: `public struct PlayerTag : IComponentData { }`. Cheap — no per-chunk storage cost beyond archetype membership.
- **Managed components** (`IComponentData` + `class`): supported but break Burst and prevent chunk parallelism. Use only for editor / debug bridges.

## EntityManager and EntityQuery

```csharp
Entity e = state.EntityManager.CreateEntity(typeof(LocalTransform), typeof(Velocity));
state.EntityManager.SetComponentData(e, LocalTransform.FromPosition(0, 1, 0));

EntityQuery q = SystemAPI.QueryBuilder()
    .WithAll<LocalTransform, Velocity>()
    .WithNone<DisabledTag>()
    .Build(ref state);
int count = q.CalculateEntityCount();
```

For read-modify loops, prefer the `SystemAPI.Query<...>()` enumerator (idiomatic in Entities 1.x) over hand-rolled `EntityQuery + ToEntityArray`. The enumerator is source-generated and avoids the temporary array.

## Systems: SystemBase vs ISystem

- **SystemBase** (managed `class`): supports managed types in `OnUpdate`, easier learning curve, cannot itself be Burst-compiled (the surrounding class isn't Burst-friendly even if the inner job is).
- **ISystem** (`partial struct`): unmanaged, fully Burst-compilable, modern recommendation in Entities 1.x. New code should default to ISystem.

System ordering attributes: `[UpdateBefore(typeof(OtherSystem))]`, `[UpdateAfter(...)]`, `[UpdateInGroup(typeof(SimulationSystemGroup))]`. Built-in groups: `InitializationSystemGroup` (frame start), `SimulationSystemGroup` (gameplay), `PresentationSystemGroup` (rendering prep, end of frame). Inspect actual order via `Window > Entities > Systems` — cyclic constraints are silently broken.

ISystem callbacks: `OnCreate(ref SystemState)`, `OnUpdate(ref SystemState)`, `OnDestroy(ref SystemState)`. Note: the destroy callback is `OnDestroy`, NOT `OnDestroyManager`.

## Jobs and dependencies

- **IJob**: single-threaded job, runs off the main thread.
- **IJobParallelFor**: split N items across worker threads with a batch size. Best when work is per-element with no shared state.
- **IJobChunk**: process a 16KB chunk at a time; access the entire chunk's components contiguously. ECS uses this internally.
- **IJobEntity**: ECS-aware job; source generators emit the `IJobChunk` boilerplate. Cleanest for ECS use cases.

Schedule and chain:

```csharp
JobHandle h1 = new MoveJob { dt = dt }.ScheduleParallel(query, state.Dependency);
JobHandle h2 = new BoundsJob { ... }.ScheduleParallel(query, h1);
state.Dependency = h2; // ECS completes for you at sync points
```

Always `Complete()` before main-thread reads of native data the job wrote, OR pass the handle through `state.Dependency` so ECS handles it. Forgetting either yields a race condition or a Safety System exception.

Hard rules: do not write to the same `NativeArray` index from parallel jobs; do not read managed types inside a Burst job (compile error); do not capture `this` references on classes.

## Burst standalone (without ECS)

`[BurstCompile]` on a `static` method and a `[BurstCompile]` delegate type lets you compile a function pointer callable from regular C#. Useful for hot loops in non-ECS code.

```csharp
[BurstCompile]
static int Sum(int a, int b) => a + b;

var fp = BurstCompiler.CompileFunctionPointer<DelegateType>(Sum);
int s = fp.Invoke(2, 3);
```

Caveats: only blittable params/returns, no managed allocations inside, function pointer is not garbage-collected. Less common than ECS use but valid for isolated hot paths (procedural mesh build, audio DSP).

## Native containers and allocators

- **NativeArray<T>**: fixed-size native array. The bread and butter.
- **NativeList<T>**: dynamic-size, growable.
- **NativeHashMap<K,V>**, **NativeParallelHashMap<K,V>** (parallel-safe variant): dictionary equivalents.
- **NativeReference<T>**: single-value box, often used to return a scalar from a job.
- **NativeSlice<T>**: window into an existing NativeArray, no copy.

Allocators:
- `Allocator.Temp`: per-frame, fastest, must not survive a frame.
- `Allocator.TempJob`: lifetime of one job (a few frames max).
- `Allocator.Persistent`: you `Dispose()` it. Mismatched allocator + lifetime triggers leak warnings.

Always `Dispose()` `Persistent` containers; a `using` statement scopes lifetime cleanly. `[NativeDisableParallelForRestriction]` lifts the safety check that blocks parallel write access — use only when you can prove the indices don't overlap.

## EntityCommandBuffer

Creating or destroying entities mid-system invalidates queries and breaks iteration. `EntityCommandBuffer` (ECB) queues those structural changes and plays them back at a safe sync point.

- `EntityCommandBuffer` (serial) for single-threaded code.
- `EntityCommandBuffer.ParallelWriter` for parallel jobs (pass a unique `sortKey` per element so playback is deterministic).
- Get an ECB from a system: `BeginSimulationEntityCommandBufferSystem.Singleton` or `EndSimulationEntityCommandBufferSystem.Singleton` via `SystemAPI.GetSingleton<...>().CreateCommandBuffer(state.WorldUnmanaged)`.

ECS plays the ECB back at the group boundary the system belongs to.

## SubScenes and Baking

Authoring lives in regular GameObjects inside a SubScene asset. Bakers convert GameObject components -> ECS components at import / build time.

```csharp
public class VelocityAuthoring : MonoBehaviour {
    public Vector3 value;
    class Baker : Baker<VelocityAuthoring> {
        public override void Bake(VelocityAuthoring src) {
            var e = GetEntity(TransformUsageFlags.Dynamic);
            AddComponent(e, new Velocity { value = src.value });
        }
    }
}
```

SubScenes lazy-load and stream — great for open worlds. Drag any scene under a SubScene in the hierarchy. Bake on save; runtime sees pure entity data with no GameObject overhead. Changing a Baker requires re-opening the SubScene to re-bake.

## Hybrid GameObject + ECS

Mix paradigms across features, not within one feature. Example: GameObject player controller + UI, ECS for 10000 enemies. Bridge with a singleton component:

```csharp
public struct PlayerInput : IComponentData { public float2 move; public bool fire; }
// MonoBehaviour writes: SystemAPI.SetSingleton(new PlayerInput { ... }) via a bootstrap world ref.
// ECS reads: var input = SystemAPI.GetSingleton<PlayerInput>();
```

Render entity meshes via `com.unity.entities.graphics` (Hybrid Renderer) alongside MeshRenderers. Avoid mixing within a single gameplay system — pick one paradigm per feature.

## Performance discipline

- Profile before optimizing. Cross-link `unity-profiling`. The Burst-Aware Profiler shows Burst-compiled methods inline.
- Cache friendliness: order components in a chunk by access pattern; small co-located components beat scattered access.
- Sync points (main thread waiting on jobs) are the enemy. System group boundaries are sync points; chain `state.Dependency` cleanly so ECS only syncs once per group.
- Burst Inspector: `Jobs > Burst > Open Burst Inspector` shows generated assembly. Look for SIMD ops (`vmovups`, `vmulps`, `vfmadd...`) — missing vectorization is a tell that a struct layout or branch is blocking it.
- `[BurstCompile(CompileSynchronously = true)]` forces compile-on-first-call (not interpret-then-compile). Use for benchmark stability; default async is fine for runtime.

## Common patterns

- **Spawn 10k bullets**: query for spawners, parallel job uses `ECB.ParallelWriter` to instantiate entities with `LocalTransform` + `Velocity`. Burst-compiled spawn job. Then a parallel `MoveSystem` updates positions next frame.
- **Boid flocking**: query for `Boid` tag + `LocalTransform`, parallel job reads neighbor positions (read-only via `[ReadOnly]`), computes flock force, writes to `Velocity`. Sync point after flocking, then movement.
- **Spatial hashing**: `NativeParallelMultiHashMap<int3, Entity>` keyed by grid cell; populate in parallel with `AsParallelWriter()`, query for neighbors O(1) by cell.
- **Hybrid input bridge**: MonoBehaviour reads new Input System (`Keyboard.current.spaceKey.wasPressedThisFrame`), writes to a singleton ECS component (`PlayerInput { float2 move; }`); ECS systems read the singleton each frame.

## Gotchas

- Managed types in `IComponentData` -> compile error or boxed allocations. Stick to blittable types.
- Iterating with `ToEntityArray` while structurally changing the world (creating/destroying) corrupts iteration. Use ECB and play back at the sync point.
- `Entity.Null` is the sentinel for "no reference" — check before access.
- Forgetting `Complete()` (or not threading `state.Dependency`) before reading job output -> race condition with garbled data.
- Burst caches per target platform; first build takes minutes. Subsequent builds incremental. Cache the Burst output directory in CI.
- `[UpdateBefore]` cycles are silently broken — use the Systems window to inspect actual order.
- ISystem destroy is `OnDestroy(ref SystemState)`, NOT `OnDestroyManager`.
- SubScene bakers run at import — change a Baker, re-open the SubScene to re-bake.
- `NativeArray.Reinterpret<T>()` views bytes as a different type with no copy. Fragile; prefer `NativeSlice` unless you genuinely need this.
- Mixing classic `MonoBehaviour.Update` (`Time.deltaTime`) with ECS time (`SystemAPI.Time.DeltaTime`) gives subtle drift — ECS time can be paused per-system group.
- DOTS adds compile time. On Macs the first Burst compile after a fresh checkout is 2-5 minutes. Plan CI around it.

## Verification

- `Window > Entities > Hierarchy` — entities visible per scene.
- `Window > Entities > Systems` — confirm system order matches `[UpdateBefore]`/`[UpdateAfter]`.
- Profiler with Burst markers: confirm jobs run on worker threads, not main thread (timeline view).
- Burst Inspector: spot SIMD instructions (`vmovups`, `vmulps`) — confirms Burst is actually vectorizing.
- Editor console clean of "ECS Safety", "leaked NativeArray", "JobHandle.Complete forgotten" warnings.

## Cross-links

- `unity-profiling` — Burst markers, Frame Debugger, Profile Analyzer.
- `unity-physics` — Unity Physics is the DOTS-based physics package, separate from PhysX/Box2D.
- `unity-input-system` — input bridges into ECS via singleton component.
- `unity-tests` — PlayMode tests for systems and jobs.
- `unity-best-practices` — foundational Unity MCP rules.

---
name: unity-dots-jobs-burst
description: 'Use for Unity 6+ DOTS/ECS/Jobs/Burst: Entities 1.x, ISystem/SystemBase, IComponentData, buffers/tags, EntityQuery, ECB, Native containers, allocators, JobHandle dependencies, SubScenes/Bakers, hybrid bridges, Burst standalone. Not ordinary MonoBehaviour gameplay.'
---

## When to use

Reach for DOTS when work is genuinely data-heavy: thousands of entities, deterministic simulation, CPU-bound procedural worlds. Cache locality + Burst can yield 10-100x over MonoBehaviour.

Do not use DOTS for small casts, UI, designer-heavy content, or generic "make it faster" work without profiling. Burst alone can optimize isolated hot loops.

## Mental model

ECS splits data and behavior. Entities are IDs, components are data structs, systems query component sets and process chunks (16 KB contiguous archetype blocks). Burst compiles hot loops to vectorized native code.

Translation table:
- GameObject -> Entity
- MonoBehaviour fields -> IComponentData struct
- Update() -> System.OnUpdate
- GetComponent<T> -> SystemAPI.GetComponent<T>(entity) or query
- Instantiate -> EntityManager.Instantiate or ECB.Instantiate
- Destroy -> EntityManager.DestroyEntity or ECB.DestroyEntity

## Package install

`com.unity.entities` pulls in Collections, Burst, and Mathematics. Add `com.unity.entities.graphics` for rendering, `com.unity.netcode` for Netcode for Entities. Inspect with `Window > Entities`.

Install via Package Manager; verify Burst/Entities version banners in console.

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

Every entity with `LocalTransform` + `Velocity` moves. Put `[BurstCompile]` on both system struct and method.

## IComponentData / IBufferElementData / Tag components

- **IComponentData**: pure blittable data (`int`, `float3`, `quaternion`, `Entity`, `FixedListN`). No `string`, class, `List<T>`, or managed refs.
- **IBufferElementData**: dynamic per-entity buffer, e.g. inventory, spline points, damage events.
- **Tag components**: `IComponentData` with no fields. Mark entities for queries: `public struct PlayerTag : IComponentData { }`. Cheap — no per-chunk storage cost beyond archetype membership.
- **Managed components**: allowed but break Burst/chunk parallelism; use only for editor/debug bridges.

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

For read-modify loops, prefer `SystemAPI.Query<...>()`; it is source-generated and avoids temp arrays.

## Systems: SystemBase vs ISystem

- **SystemBase**: managed class; easier, supports managed types, not Burst-compiled itself.
- **ISystem**: unmanaged partial struct, fully Burst-compatible. Default for new code.

Ordering: `[UpdateBefore]`, `[UpdateAfter]`, `[UpdateInGroup]`. Built-in groups: Initialization, Simulation, Presentation. Check actual order in Entities Systems; cycles are broken silently.

ISystem callbacks: `OnCreate`, `OnUpdate`, `OnDestroy`; not `OnDestroyManager`.

## Jobs and dependencies

- **IJob**: one off-main-thread job.
- **IJobParallelFor**: per-element parallel work.
- **IJobChunk**: chunk-level ECS access.
- **IJobEntity**: source-generated ECS job; cleanest for most ECS jobs.

Schedule and chain:

```csharp
JobHandle h1 = new MoveJob { dt = dt }.ScheduleParallel(query, state.Dependency);
JobHandle h2 = new BoundsJob { ... }.ScheduleParallel(query, h1);
state.Dependency = h2; // ECS completes for you at sync points
```

Before main-thread reads, `Complete()` or pass the handle through `state.Dependency`.

Hard rules: no shared-index writes, no managed reads in Burst jobs, no captured class `this`.

## Burst standalone (without ECS)

`[BurstCompile]` static methods can become function pointers for regular C# hot loops.

```csharp
[BurstCompile]
static int Sum(int a, int b) => a + b;

var fp = BurstCompiler.CompileFunctionPointer<DelegateType>(Sum);
int s = fp.Invoke(2, 3);
```

Caveats: blittable params/returns only, no managed allocation, no GC ownership of the pointer.

## Native containers and allocators

- **NativeArray<T>**: fixed-size native array.
- **NativeList<T>**: dynamic-size, growable.
- **NativeHashMap<K,V>**, **NativeParallelHashMap<K,V>** (parallel-safe): dictionary equivalents.
- **NativeReference<T>**: single-value box, often returns a scalar from a job.
- **NativeSlice<T>**: window into an existing NativeArray, no copy.

- `Allocator.Temp`: per-frame, fastest, must not survive a frame.
- `Allocator.TempJob`: lifetime of one job (a few frames max).
- `Allocator.Persistent`: you `Dispose()` it. Mismatched allocator + lifetime triggers leak warnings.

Always dispose `Persistent` containers. Use `[NativeDisableParallelForRestriction]` only when index writes cannot overlap.

## EntityCommandBuffer

Creating/destroying entities mid-iteration invalidates queries. ECB queues structural changes for safe playback.

- `EntityCommandBuffer` (serial) for single-threaded code.
- `EntityCommandBuffer.ParallelWriter` for parallel jobs (pass a unique `sortKey` per element so playback is deterministic).
- Get an ECB from begin/end simulation singleton via `SystemAPI.GetSingleton<...>().CreateCommandBuffer(state.WorldUnmanaged)`.

## SubScenes and Baking

Authoring lives in regular GameObjects inside a SubScene asset. Bakers convert GameObject components → ECS components at import/build time.

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

SubScenes stream and bake GameObject authoring into pure entity data. Changing a Baker requires re-opening/rebaking the SubScene.

## Hybrid GameObject + ECS

Mix paradigms across features, not inside one feature. Example: GameObject player/UI, ECS enemies. Bridge with singleton components:

```csharp
public struct PlayerInput : IComponentData { public float2 move; public bool fire; }
// MonoBehaviour writes: SystemAPI.SetSingleton(new PlayerInput { ... }) via a bootstrap world ref.
// ECS reads: var input = SystemAPI.GetSingleton<PlayerInput>();
```

Render entities through Entities Graphics alongside MeshRenderers.

## Performance discipline

- Profile first (`unity-profiling`).
- Keep accessed components small and co-located.
- Avoid sync points; chain `state.Dependency`.
- Burst Inspector: look for SIMD (`vmovups`, `vmulps`, `vfmadd`).
- `CompileSynchronously = true` only for benchmark stability.

## Common patterns

- **Spawn 10k bullets**: query for spawners, parallel job uses `ECB.ParallelWriter` to instantiate entities with `LocalTransform` + `Velocity`. Burst-compiled spawn job. Then a parallel `MoveSystem` updates positions next frame.
- **Boid flocking**: query for `Boid` tag + `LocalTransform`, parallel job reads neighbor positions (read-only via `[ReadOnly]`), computes flock force, writes to `Velocity`. Sync point after flocking, then movement.
- **Spatial hashing**: `NativeParallelMultiHashMap<int3, Entity>` keyed by grid cell; populate in parallel with `AsParallelWriter()`, query for neighbors O(1) by cell.
- **Hybrid input bridge**: MonoBehaviour reads new Input System (`Keyboard.current.spaceKey.wasPressedThisFrame`), writes to a singleton ECS component (`PlayerInput { float2 move; }`); ECS systems read the singleton each frame.

## Gotchas

- Managed types in `IComponentData` → compile error or boxed allocations. Stick to blittable types.
- Iterating with `ToEntityArray` while structurally changing the world (creating/destroying) corrupts iteration. Use ECB and play back at the sync point.
- `Entity.Null` is the sentinel for "no reference" — check before access.
- Forgetting `Complete()` (or not threading `state.Dependency`) before reading job output → race condition with garbled data.
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

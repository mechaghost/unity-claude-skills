---
name: unity-procgen
description: 'Use when generating Unity content procedurally through Unity MCP — procedural generation, procgen, world generation, random map, noise, Perlin noise, Mathf.PerlinNoise, Simplex noise, Unity.Mathematics.noise, snoise, fBm, fractal noise, octaves, lacunarity, heightmap generation, splatmap generation, procedural mesh, Mesh.SetVertices, Mesh.SetTriangles, MeshDataArray, marching cubes, voxel, voxel chunk, terrain chunk, infinite world, dungeon generation, BSP, room and corridor, drunkard walk, wave function collapse, WFC, cellular automata, prefab placement, Poisson disk, spatial hash, deterministic random, seed, Random.InitState, System.Random, Unity.Mathematics.Random, editor procgen, runtime procgen, level streaming. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Generating content with code rather than authoring it: terrain heightmaps, dungeon layouts, procedural meshes, vegetation/rock scatter, infinite worlds, level remixing, daily-seed runs, roguelite levels. Not for animation procedurals (`unity-animation` Rigging), not for VFX procedurals (`unity-vfx-graph`).

## Determinism first

Procedural content only reproduces if every random draw comes from a seeded source. Decide up front: deterministic (same seed → same world across machines/runs) or non-deterministic (visual variety only).

| Source | Deterministic? | Use for |
| --- | --- | --- |
| `UnityEngine.Random` | Global state — one shared sequence | Visual variety only; never for reproducible worlds |
| `System.Random` | Per-instance, CPU-only | Per-system reproducibility |
| `Unity.Mathematics.Random` | Per-instance, Burst-compatible | Job/Burst chunk generation |

Seed handling:

```csharp
var sysRng = new System.Random(seed);
var mathRng = new Unity.Mathematics.Random((uint)(seed | 1)); // 0 is invalid

// Derive per-chunk seeds — never share an RNG across chunks if you want
// chunk-local determinism regardless of generation order.
uint chunkSeed = (uint)HashCode.Combine(seed, chunkX, chunkZ);
var chunkRng = new Unity.Mathematics.Random(chunkSeed | 1);
```

Avoid `UnityEngine.Random.InitState` — global, leaks state to anything that calls `Random.*` (third-party packages included). Sets you up for breakage when a dependency adds a `Random.value` call.

## Noise

- **`Mathf.PerlinNoise(x, y)`** — built-in Perlin (gradient) noise, 2D only, returns 0..1. Cheap, but visible axis-aligned features and repetition at very large coords.
- **`Unity.Mathematics.noise.snoise`** — Simplex noise. Burst-friendly, true gradient noise, 2D/3D/4D. Range ~[-1, 1]. **Prefer for jobs and 3D sampling.**
- **`Unity.Mathematics.noise.cnoise`** — classic Perlin in `Unity.Mathematics`. Burst-friendly.
- **Fractal Brownian Motion (fBm)** — stack noise octaves at doubling frequency, halving amplitude. Gives natural-looking terrain detail.

```csharp
public static float fBm(float2 p, int octaves = 5, float lacunarity = 2f, float gain = 0.5f) {
    float a = 0.5f, sum = 0f;
    for (int i = 0; i < octaves; i++) {
        sum += a * noise.snoise(p);
        p *= lacunarity;
        a *= gain;
    }
    return sum;
}
```

`Mathf.PerlinNoise` has no built-in seed. To seed it, offset the sample domain by a seeded vector: `Mathf.PerlinNoise(x + seedOffsetX, y + seedOffsetY)`. Same trick for `snoise`/`cnoise`.

## Heightmap generation (feeds unity-terrain)

```csharp
int res = terrainData.heightmapResolution; // e.g. 1025
var heights = new float[res, res];
float scale = 0.005f;
for (int z = 0; z < res; z++)
for (int x = 0; x < res; x++) {
    float2 p = new float2(x, z) * scale + seedOffset;
    heights[z, x] = fBm(p, octaves: 5) * 0.5f + 0.5f; // remap [-1,1] → [0,1]
}
terrainData.SetHeights(0, 0, heights);
terrainData.SyncHeightmap(); // refresh TerrainCollider (see unity-terrain)
```

For full-resolution terrains, push the loop into `IJobParallelFor` with Burst — 10–100× faster on a desktop CPU. See `unity-dots-jobs-burst`.

Splatmaps from height/slope: build `float[,,] alpha` with per-layer weight based on Y/slope, then `SetAlphamaps(0, 0, alpha)`. Rows must sum to 1 (see `unity-terrain` → Terrain Layers).

## Procedural mesh

```csharp
var mesh = new Mesh { name = "ProcMesh" };
mesh.indexFormat = vertexCount > 65535
    ? UnityEngine.Rendering.IndexFormat.UInt32
    : UnityEngine.Rendering.IndexFormat.UInt16;

mesh.SetVertices(vertices);
mesh.SetTriangles(triangles, 0);
mesh.SetUVs(0, uvs);
mesh.RecalculateNormals();   // or set normals manually for perf
mesh.RecalculateBounds();

meshFilter.sharedMesh = mesh;
```

- Default index format is 16-bit. Flip to `UInt32` once `vertexCount > 65535`.
- For Burst/Job-built meshes, prefer `Mesh.AllocateWritableMeshData` + `Mesh.ApplyAndDisposeWritableMeshData` — avoids GC and lets the build run inside a job.
- `RecalculateNormals` is O(vertices) per call and doesn't smooth across UV seams. For smooth-shaded procedural meshes, weld duplicate vertices or compute normals manually.
- `MeshCollider` rebake (re-assigning `sharedMesh`) is expensive — don't rebake every frame.

## Voxel chunks

For Minecraft-style voxel worlds, the canonical structure:

- Fixed chunk size (16×16×256 typical). World partitioned into chunks identified by `(chunkX, chunkZ)`.
- Voxel data per chunk = deterministic function of `(seed, chunkX, chunkZ)`. No global state.
- Mesh each chunk's surface — greedy meshing, marching cubes, or surface nets.
- LOD: distant chunks render coarser meshes. Swap in/out by camera distance.
- Stream chunks in/out around the player; pool meshes (`unity-patterns` → ObjectPool).
- Jobs + Burst for voxel evaluation and meshing — single-thread is unviable at non-trivial scale. See `unity-dots-jobs-burst`.

## Dungeon / level generation patterns

| Pattern | Shape | Notes |
| --- | --- | --- |
| **BSP** (binary space partition) | Rooms in a grid | Recursively split a rect; place a room per cell; connect siblings via corridors. Tight, regular layouts. |
| **Room-and-corridor** | Discrete rooms | Pick non-overlapping rects; carve L-shaped or A*-routed corridors. Classic roguelite. |
| **Drunkard's walk** | Organic caves | Random walker carves connected open space. Cheap, organic. |
| **Cellular automata** | Caves | Iterative neighbor rules (Conway-style). Smooths into natural cave shapes. |
| **Wave Function Collapse** | Tile/voxel | Constraint propagation from a sample. High quality, slow; community packages available. |

Each pattern: deterministic seed in → `ScriptableObject` config (room min/max, corridor width, smoothing passes, etc.) → typed level graph or tilemap out.

Validate with a flood-fill reachability pass before returning; isolated rooms are the most common bug.

## Prefab placement

This section covers raw scatter math. For higher-level composition — placing buildings along roads, towns with lot subdivision, vegetation rules with exclusion masks, biome blending — see `unity-world-layout`.

Scattering rocks, trees, props:

- **Uniform random** — `Random.insideUnitCircle * radius` (or seeded equivalent). Cheap but clusters.
- **Poisson disk sampling** — guarantees minimum spacing. Natural-looking scatter.
- **Spatial hash / grid** — partition space into cells; query only neighbor cells for collision/overlap. Essential at scale.
- Snap Y to terrain: `terrain.SampleHeight(worldPos)` returns world-space Y directly — see `unity-terrain` → Runtime API.

For thousands of instances, `Instantiate(prefab, ...)` is too slow. Two routes:

- **Pool** with `ObjectPool`/`LinkedPool` (`unity-patterns`) — when each instance needs MonoBehaviour logic.
- **`Graphics.RenderMeshInstanced`** / `RenderMeshIndirect` — pure rendering, no GameObjects. Right for static decoration (rocks, grass clumps, distant trees).

## Job system + Burst

Procedural workloads (noise sampling, meshing, voxel evaluation, scatter) are embarrassingly parallel and arithmetic-heavy — ideal for `IJobParallelFor` + Burst. Rule of thumb: if a generation pass touches >10k elements, profile a Burst version. See `unity-dots-jobs-burst`.

Pattern: prepare `NativeArray<T>` inputs → schedule job → `Complete()` (or `JobHandle.IsCompleted` for fire-and-forget) → consume outputs → dispose. Don't dispose `NativeArray`s before `Complete()` — Unity will catch this with the safety system in Editor but ship code without those checks.

## Editor-time vs runtime generation

- **Editor-time**: bake content into the scene/asset, ship without the generator. Use Editor scripts; respect Undo (`unity-best-practices` → Respect Undo). Right for fixed worlds with hand-tweaked seeds. Forgetting `EditorUtility.SetDirty` + `AssetDatabase.SaveAssets` leaves changes in memory only — lost on Editor restart.
- **Runtime**: ship the generator + seed. Required for daily-seed/roguelite/open-world streaming. Watch frame budget — generate during load screens, behind cover, or in background jobs.

For hybrid (editor preview + runtime gen), share the generator core in a non-`MonoBehaviour` static class; call from both an `[InitializeOnLoad]` Editor tool and a runtime `MonoBehaviour`.

## Configs and seeds

Wrap generator parameters in a `ScriptableObject` (`unity-patterns` → SO config). Designers tweak in Inspector; the seed is just a serialized field. For player-facing "Seed: 12345" strings that should be stable across versions, hash the seed once into named sub-seeds — adding a new generator stage won't shift older seeds.

## Streaming with the rest of the world

Procedural chunks live in scenes (load via `unity-scenes` additive) or Addressable groups (`unity-addressables` for remote/lazy). For terrain-backed worlds, each chunk owns a Terrain + TerrainData and registers neighbors (`unity-terrain` → Multi-tile). For mesh-backed worlds, each chunk owns a procedurally built mesh + collider.

## Gotchas

- `UnityEngine.Random` is a global singleton. Anything else calling `Random.value` (Unity internals, third-party packages) advances your sequence and breaks reproducibility. Switch to `System.Random` / `Unity.Mathematics.Random` for anything you want stable.
- `Unity.Mathematics.Random` requires a nonzero seed — `new Random(0)` throws. OR-with-1 or hash to a nonzero `uint`.
- Floating-point ordering matters for cross-platform determinism. Summing 1000 noise samples in different orders gives bit-different results. For strict cross-platform determinism, accumulate in a deterministic order or use fixed-point.
- `Mathf.PerlinNoise` repeats at large coords and is axis-symmetric. Rotate the sample domain or add an extra-octave variation to mask the grid.
- `Mesh.RecalculateNormals` doesn't smooth across UV seams. For smooth procedural meshes, weld duplicate verts before recalculating, or compute normals manually.
- Editor-time generation that doesn't `EditorUtility.SetDirty` + `AssetDatabase.SaveAssets` looks correct in the running Editor and vanishes on restart.
- Spawning huge counts in `Start()` blocks the main thread (visible as a single-frame hitch on level load). Spread across frames via coroutine yielding, or move to jobs.
- `MeshCollider.sharedMesh = mesh` triggers a bake every time. For animated procedural surfaces, don't update the collider every frame — pick a lower update cadence, or use a simpler proxy collider.
- 16-bit index buffer is the default. Cross 65535 vertices without flipping to `UInt32` and you get silent geometry corruption.
- Burst jobs disposing `NativeArray` before `Complete()` corrupts memory silently in player builds. Always `Complete()` (or assign the handle as a dependency) before disposing.

## Verification

- Determinism: run the generator twice with the same seed, hash the output (heightmap floats, vertex positions, prefab placements). Identical hash = clean determinism. Different = a hidden non-deterministic source (likely `Random.value`, dictionary iteration order, multithreaded ordering).
- Frame budget: profile (`unity-profiling`) the generation pass. Confirm it fits the load-screen window or the streaming budget without GC spikes.
- For terrain heightmaps: see `unity-terrain` verification (multi-angle screenshots, drop a test rigidbody).
- For voxel/large meshes: check the Stats overlay — vertex count, triangle count, draw calls. Confirm `IndexFormat = UInt32` if crossing 65535.
- For dungeons: flood-fill from the start cell; confirm every walkable cell is reachable. No isolated rooms.
- For scatter: visual sanity-check with `unity-3d-verification` (4-shot orthographic) on a representative chunk — clustering, spacing, and ground-snap all visible from above + side.

## Related skills

- `unity-world-layout` — composition rules on top of these primitives (roads, settlements, vegetation rules, biome blending).
- `unity-terrain` — apply heightmaps and splatmaps to Unity Terrain; multi-tile streaming.
- `unity-dots-jobs-burst` — Burst-compiled noise, meshing, voxel jobs.
- `unity-scenes`, `unity-addressables` — chunk/tile streaming.
- `unity-patterns` — pooling, SO configs, FSMs for generator stages.
- `unity-physics` — `MeshCollider` for procedurally generated geometry; vehicle physics on procedural terrain.
- `unity-profiling` — generation-time budget verification.

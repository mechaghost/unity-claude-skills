---
name: unity-terrain
description: 'Use when working with Unity Terrain through Unity MCP — Terrain GameObject, TerrainData, heightmap, sculpt, paint texture, paint trees, paint details, alphamap, splatmap, terrain layer, TerrainLayer, com.unity.terrain-tools, Terrain Tools package, brush, sculpt brush, stamp, erosion, terrain neighbors, terrain holes, paint holes, TerrainCollider, terrain LOD, pixel error, base map distance, draw instanced, billboard, tree LOD, detail mesh, GPU instancing, tree colliders, SampleHeight, SetHeights, SetAlphamaps, SyncHeightmap, terrain streaming, large world terrain, multi-tile terrain, URP terrain shader. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Outdoor ground geometry: open-world levels, racing tracks, hiking sims, RTS maps, anywhere you need sculpted+textured+vegetated ground at scale. Not for tight interiors (model in DCC), not for 2D tilemaps (separate 2D workflow), not for caves/overhangs alone (Terrain is a heightmap — supplement with `MeshCollider` for true 3D structure).

## Terrain GameObject anatomy

A Terrain object pairs three things:

- `Terrain` component — renders the heightmap mesh, owns LOD/material/trees/detail meshes.
- `TerrainCollider` component — physics from the heightmap. See `unity-physics` → Vehicles for ground-collider choice when driving vehicles.
- `TerrainData` asset (`.asset` in `Assets/`) — source of truth: heightmap, alphamaps (splatmaps), terrain layers, tree instances, detail layers. Both `Terrain` and `TerrainCollider` reference the same asset.

Multiple Terrain objects can share one `TerrainData`. Editing the asset changes every Terrain referencing it — duplicate before independent sculpting.

## Heightmap

- **Heightmap Resolution** — must be `2^n + 1`: valid values 33, 65, 129, …, 4097. **1024 is invalid; 1025 is correct.** Higher = more detail + memory; 1025 covers most uses.
- **Terrain Width / Length** — world units (e.g. 1000 × 1000 m). Independent of heightmap resolution; spacing per heightmap sample = width / (res − 1).
- **Terrain Height** — max world Y in meters (default 600). Heightmap values are normalized 0..1, scaled by this.
- **`terrainData.SetHeights(int xBase, int zBase, float[,] heights)`** — write a sub-region, values 0..1. For large updates use `SetHeightsDelayLOD` + `ApplyDelayedHeightmapModification()` to defer LOD rebuild.
- **`terrain.SampleHeight(Vector3 worldPos)`** — read-only, returns the terrain surface Y at `worldPos` in **world space** (already includes the terrain's transform.position.y; don't add it again).

After runtime height changes, `TerrainCollider` does **not** auto-update — call `terrainData.SyncHeightmap()` (or briefly toggle the collider). Vehicles will float over the old surface otherwise.

**Import from DCC** — for heightmaps authored in World Machine, Gaea, Houdini, etc., use Terrain inspector → Terrain Settings → **Heightmap → Import Raw…** (16-bit grayscale RAW; width/height must match the terrain's heightmap resolution). Or read the bytes in script and call `SetHeights`. **Export Raw…** in the same menu round-trips for external editing.

## Terrain Layers (textures)

Unity 6 uses `TerrainLayer` assets (`Assets > Create > Terrain Layer`). Each layer has:

- **Diffuse**, **Normal Map**, **Mask Map** (URP convention: R=metallic, G=occlusion, B=height, A=smoothness).
- **Tile Size / Offset** in world units.
- **Specular / Metallic / Smoothness**.

Add layers via the Terrain inspector → Paint Texture. URP terrain shader supports up to **8 layers per terrain**; more needs a custom shader.

Splatmap (alphamap) data: per-pixel weight per layer, summing to 1. Read/write via `terrainData.GetAlphamaps` / `SetAlphamaps` — `float[z, x, layerIndex]`. **Rows must sum to 1** across layers, or you get black/missing patches.

## Painting workflow

In the Terrain inspector (Edit Terrain → brush row):

- **Raise/Lower Terrain** — sculpt up/down at brush.
- **Set Height** — flatten to target Y.
- **Smooth Height** — local average.
- **Stamp Terrain** — apply a height texture as a stamp.
- **Paint Holes** — mask triangles (caves, archways). Holes hide mesh and disable collision under the hole.
- **Paint Texture** — apply a Terrain Layer where the brush passes.
- **Paint Trees** — instance tree prefabs. Density/height/width variation, random rotation.
- **Paint Details** — grass billboards or short detail meshes.

`com.unity.terrain-tools` adds Erosion, Hydraulic, Thermal, Bridge, Clone brushes. Optional; basic painting works without it.

## Trees and detail meshes

- **Trees** — prefabs with `LODGroup` supported. Distance billboards via Terrain Settings → **Billboard Start**. For thousands of trees, the tree material must have **Enable GPU Instancing** on **and** Terrain Settings → **Draw Instanced** on.
- **Tree colliders** — prefab colliders are included in Terrain physics by default. Disable per-prefab to opt out.
- **Detail meshes / grass** — quad billboards (Grass Texture mode) or low-poly meshes (Detail Mesh mode). Density × patch resolution = instance count; budget aggressively, especially on mobile.
- **Detail Distance / Density** — Terrain Settings. Cut detail distance first when grass is a perf hit.

## Terrain Settings (gear tab)

- **Pixel Error** — LOD aggressiveness. 1 = highest detail, 200 = ugly. Default 5; raise for mobile.
- **Base Map Distance** — beyond this, terrain switches to a combined baked basemap instead of per-layer shader. Lower = perf win, visible transition seam.
- **Cast Shadows / Receive GI** — terrain shadow + GI participation.
- **Draw Instanced** — required for tree/detail GPU instancing.
- **Material** — terrain shader. URP project must use `Universal Render Pipeline/Terrain/Lit` (see `unity-urp`). Built-in/HDRP shaders show pink.

## Multi-tile terrain (large worlds)

Split the world into a grid of `Terrain` tiles, each with its own `TerrainData`. For seamless LOD across tiles:

- Place tiles edge-to-edge in world space (no overlap, no gap).
- Connect neighbors either via `Terrain.SetNeighbors(left, top, right, bottom)` per tile, or set matching **Grouping ID** and call `Terrain.SetConnectivityDirty()` so all `Terrain.allTerrains` auto-discover neighbors at runtime.
- Seam height-matching: the last heightmap row of one tile must equal the first row of its neighbor. Mismatched values produce visible cracks.

For streaming: load/unload tile scenes (one Terrain + TerrainData per scene) via `unity-scenes` (additive) or `unity-addressables` (remote). Tile-load budget belongs in the load-screen window or hidden behind motion blur on the next chunk.

## TerrainCollider

`TerrainCollider` uses the heightmap data stored in the `TerrainData` asset — fast, deterministic, but heightmap-flat (no overhangs, no caves). For true 3D structure under terrain (cave systems, archways), paint holes through the mesh and supplement with a `MeshCollider` for the underground geometry.

Vehicles specifically: see `unity-physics` → Vehicles. `WheelCollider` works correctly on `TerrainCollider`; avoid primitive `SphereCollider`s as ground since their contact normals launch vehicles.

## NavMesh on terrain

To bake `NavMeshSurface` over a terrain (`unity-navmesh`):

- **`Use Geometry = RenderMeshes`** — bakes from the terrain mesh directly. Most accurate; respects holes painted in the terrain. Trees baked as obstacles if they have colliders.
- **`Use Geometry = PhysicsColliders`** — bakes from `TerrainCollider` + tree/detail colliders. Faster, but slope/step interpretation can disagree with the visual surface on aggressive sculpting.
- Confirm the terrain layer is in **Include Layers** on the `NavMeshSurface`; otherwise the nav surface skips it silently.

## Runtime API (key entry points)

```csharp
var td = terrain.terrainData;

// Read a heightmap window as float[,]
int res = td.heightmapResolution;
float[,] heights = td.GetHeights(0, 0, res, res);

// Write a patch back
td.SetHeights(originX, originZ, modifiedPatch);

// Sample world-space Y at a position (already absolute; no offset needed)
float y = terrain.SampleHeight(worldPos);

// Splatmap write (rows must sum to 1)
float[,,] alpha = new float[w, h, td.alphamapLayers];
// ... fill weights ...
td.SetAlphamaps(0, 0, alpha);

// Sync collider after runtime height/hole changes:
td.SyncHeightmap();
```

For non-trivial procedural heightmaps and splatmaps, see `unity-procgen`.

## Gotchas

- `TerrainCollider` doesn't auto-refresh after runtime `SetHeights` / hole paint. Call `terrainData.SyncHeightmap()` or toggle the collider.
- Alphamap rows must sum to 1 across layers; otherwise black patches or "no-layer" gaps.
- Default URP material slot is wrong for terrain. Material must be `Universal Render Pipeline/Terrain/Lit` (or a custom URP terrain shader) — built-in shader renders pink.
- One `TerrainData` shared across multiple Terrains means edits apply everywhere. Duplicate the asset for independent edits.
- Tree GPU instancing needs **both** the tree material's Enable GPU Instancing **and** Terrain Settings → Draw Instanced on.
- Detail meshes don't cast shadows by default — turning shadows on tanks perf.
- Heightmap resolution must be `2^n + 1`. 1024 is invalid; pick 513, 1025, 2049, 4097.
- Trees painted on a terrain live in the `TerrainData`, not the scene hierarchy. They don't show in the Hierarchy panel and can't be lasso-selected.
- Terrain holes hide mesh but a stale `TerrainCollider` still reports ground; toggle the collider after hole paint.
- `Terrain.SampleHeight` returns Y in **world space already** — adding `terrain.transform.position.y` on top double-offsets and spawns objects high in the sky. Older tutorials (pre-Unity-2018) advise the extra offset; ignore them.
- Multi-tile worlds without `SetNeighbors` (or matching Grouping ID) show LOD seams between tiles even if heights match.

## Verification

- Game-view fly-through of the terrain bounds: no pink material, no missing seams between tiles, no grass-distance pop-in inside expected range.
- Console clean of `Cannot bake NavMesh because Terrain has no heightmap` (if combining with `unity-navmesh`).
- Drop a test object (Rigidbody primitive or `WheelCollider` rig) from height — should settle on the terrain surface without sinking, floating, or pogo-ing. If it pogos, check `bounceCombine` per `unity-physics`. If it sinks after runtime height changes, you forgot `SyncHeightmap()`.
- Multi-tile: enable Gizmos at a seam; verify continuous heights and matching neighbor LOD.
- Run `unity-3d-verification` (4-shot orthographic) on the terrain bounds for any 3D scene that ships with terrain — confirms silhouette from top + sides.

## Related skills

- `unity-world-layout` — composition rules for placing roads, settlements, vegetation, formations on terrain; biome and seam blending.
- `unity-physics` — `TerrainCollider`, vehicles on terrain, ground collider choice.
- `unity-procgen` — heightmap and splatmap generation, noise, runtime procedural terrain.
- `unity-urp`, `unity-shaders` — URP terrain shader, custom terrain materials.
- `unity-lighting` — baked GI / lightmap UVs on terrain.
- `unity-scenes`, `unity-addressables` — streaming multi-tile worlds.
- `unity-navmesh` — bake NavMesh on top of terrain geometry.

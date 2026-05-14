---
name: unity-world-layout
description: 'Use when composing a Unity 6 world — building placement, town/city/village layout, settlement generation, lot subdivision, foundation flattening, POI placement, Lloyd''s relaxation, Voronoi, road generation, road splines, com.unity.splines, SplineContainer, SplineExtrude, road network, intersections, on-road vs off-road, drivable surface, surface tagging, rocks, boulders, cliffs, natural formations, vegetation, foliage, forest, tree density, grass density, biome, biome blending, splatmap blending, height/slope rules, exclusion mask, terrain-asset blending, road shoulder blending, decal junction, triplanar cliff, terrain stamping, Terrain.RemoveTreeInstance, SetDetailLayer. Use this skill for the composition layer on top of unity-terrain (data) and unity-procgen (primitives). Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

You have terrain and a procgen toolkit; now you need a world that looks intentional. This skill is the composition discipline on top: rules for *where* things go and *how* they blend at seams. Triggers for natural-language requests like "place a town along the river road", "scatter rocks on the cliffs", "make the forest stop near the road", "blend the road into the terrain", "tag off-road vs on-road for the car".

Not for: raw scatter math (use `unity-procgen` → Prefab placement), Terrain API (use `unity-terrain`), camera framing the world (`unity-cinemachine`).

## Placement drivers

Every asset placement is a function of one or more world signals. Build a mask per signal, combine into a per-XZ probability, then sample. Common drivers:

| Driver | Source | Used for |
| --- | --- | --- |
| **Altitude** | `terrain.SampleHeight` | Snow above N, sand below M, treeline cutoff |
| **Slope** | `terrainData.GetSteepness(x, z)` | Rocks on steep, grass on shallow, roads avoid >15° |
| **Biome ID** | low-frequency noise → discrete IDs | Forest vs desert vs tundra rules |
| **Road proximity** | distance-to-spline | Exclusion buffer, density falloff |
| **Building proximity** | distance-to-footprint | Lot clearance for vegetation |
| **Water proximity** | distance to water mask | Sand/reed bands |
| **Noise mask** | second `snoise` layer | Density variation, break up grids |

**Exclusion masks** are the most-forgotten driver. A road carved through forest needs a clearance buffer where no tree spawns; a building lot needs a lawn radius free of rocks. Build masks as 2D `float[,]` or render-to-RT, sample at each candidate point, multiply into the placement probability.

## Roads

Roads are the spine that everything else hangs off — settlements snap to them, vegetation excludes around them, navmesh follows them. Author with `com.unity.splines` (`SplineContainer` + `BezierKnot`); sample with `SplineUtility.Evaluate(spline, t, out pos, out tangent, out up)`.

**Four implementation approaches:**

| Approach | Visual | Physics | When |
| --- | --- | --- | --- |
| **Splatmap-stamp only** | Texture only | Drives on terrain | Cheapest; dirt paths, game trails |
| **Heightmap-cut** | True embankment/cut | Drives on terrain | Highway cuts through hills; need real road-bed feel |
| **Separate mesh on top** | Curbs, lane markings, asphalt detail | Mesh collider over terrain collider | City streets, racing tracks |
| **Asset package** (Easy Roads 3D, Road Architect) | Mature intersections + crossfades | Either | When budget allows and intersections matter |

Most driving games combine: heightmap-cut for the road **bed**, separate mesh for the road **surface** sitting 5–20 cm above the carved heightmap (avoids z-fighting; the carve gives the embankment shape, the mesh gives the asphalt look).

**Mesh extrusion from a spline:**

```csharp
// Sample N segments along the spline, build a quad strip of width W.
for (int i = 0; i <= segments; i++) {
    float t = i / (float)segments;
    SplineUtility.Evaluate(spline, t, out float3 pos, out float3 tan, out float3 up);
    float3 right = math.normalize(math.cross(tan, up)) * halfWidth;
    verts.Add(pos - right); verts.Add(pos + right);
    uvs.Add(new float2(0, t * uvTile)); uvs.Add(new float2(1, t * uvTile));
}
// Then build triangle strip indices i, i+1, i+2 / i+1, i+3, i+2.
```

`SplineExtrude` component works for narrow tubes but is too constrained for proper road profiles (curbs, shoulders); roll your own for real roads.

**Heightmap-cut under a road spline:**

```csharp
for each spline sample (pos, tan):
    for each terrain cell within roadHalfWidth + shoulderFalloff of pos:
        float d = distanceFromSplineCenterline(cellWorldPos);
        if (d < halfWidth) target = pos.y / terrainHeight;          // road bed
        else                target = blend(currentHeight, pos.y, falloff(d));
        heights[z, x] = target;
terrainData.SetHeights(x0, z0, heights);
terrainData.SyncHeightmap(); // collider catches up — see unity-terrain
```

The shoulder falloff (`smoothstep` or cosine) is what hides the cut. Sharp transitions look like a glitch.

**Intersections** are the hard problem. For T/4-way junctions: detect spline crossings, trim incoming meshes back to the intersection radius, generate a hub mesh fitted to the four directions. Asset packages exist precisely because doing this well from scratch is weeks of work.

## On-road vs off-road surface tagging

Vehicles and AI need to know what they're driving on. Three tagging strategies:

1. **Layer-based** — road mesh on a `Road` layer; off-road = terrain on `Default`. Sample per-wheel via `Physics.Raycast` with a layer mask, swap `WheelCollider.forwardFriction`/`sidewaysFriction` (cross-link `unity-physics` → Vehicles).
2. **PhysicsMaterial-based** — different `PhysicsMaterial` on road vs terrain. Per-wheel raycast reads `hit.collider.sharedMaterial`; friction differs naturally without a tagging system. Less control over wheel curves.
3. **Splatmap-sampled** — wheel raycast hits the `TerrainCollider`; you can't distinguish layers from the collider alone, so sample `terrainData.GetAlphamaps(xPixel, zPixel, 1, 1)` to find which terrain layer dominates at that XZ. Slower; do off the per-frame hot path (every 0.1 s is fine for friction changes).

For AI navigation, bake separate `NavMeshSurface`s: one on the road mesh only (Walkable, Area = Road), one on terrain (Area = OffRoad, higher cost). Pathing then prefers roads but can deviate. See `unity-navmesh`.

## Settlements and buildings

**POI placement (Lloyd's relaxation)** distributes points evenly without grid artifacts:

1. Scatter N seed points uniformly in the bounds.
2. Compute the Voronoi diagram (or approximate via nearest-neighbor sampling on a grid).
3. Move each point to its cell's centroid.
4. Iterate 3–10 times. Points become evenly distributed but irregular.

Connect adjacent POIs to form the road graph; this is the *first* layout pass, before any building or terrain detail.

**Building-along-road snapping:** along each road spline, sample positions at building-spacing intervals; for each, raycast from the road centerline perpendicular outward to find the building's front edge; place the prefab with `transform.rotation = Quaternion.LookRotation(toRoad)` so the doorway faces the street. Stagger left/right alternation for natural variety.

**Lot subdivision** — given a polygon bounded by roads, BSP-split recursively until cells are house-sized (`unity-procgen` → Dungeon patterns has the BSP primitive; here you're slicing a town block, not a dungeon).

**Foundation flattening** is the step everyone forgets — buildings on un-flattened terrain float at one corner and bury at another. Pseudocode:

```csharp
Rect footprint = building.GetWorldFootprint();
Rect samplingRect = Expand(footprint, falloffMeters);
float[,] heights = terrainData.GetHeights(/* samplingRect in pixel coords */);
float targetH = building.transform.position.y / terrain.terrainData.size.y;
for each cell in heights:
    float distToFootprint = SignedDistance(cellWorldPos, footprint);
    float t = smoothstep(0, falloffMeters, -distToFootprint); // 1 inside, 0 outside
    heights[z, x] = math.lerp(heights[z, x], targetH, t);
terrainData.SetHeights(x0, z0, heights);
terrainData.SyncHeightmap(); // collider!
```

Order matters: flatten **before** placing the building, sync the collider, then `Instantiate` — otherwise the building's first physics tick reads stale ground.

## Natural formations

- **Rocks/boulders** — Poisson-disk scatter with size multiplier as a function of rarity (small common, big rare). Random Y rotation and small X/Z tilt make them look settled rather than placed. Sink each into terrain by 5–20% of its bounds so it reads as embedded.
- **Cliffs** — placement driven by slope mask: where `terrainData.GetSteepness(x, z) > 45°`, swap to a rocky cliff splatmap layer (see Blending). Optionally stamp a cliff-face mesh prop where slopes exceed the terrain's heightmap angular limit.
- **Boulder fields / debris** — clusters near cliffs, falling off with distance. Use a low-frequency noise mask to break up uniform fields into believable arrangements.
- **Outcrops** — small Y-bump on the heightmap (a few cells, smoothed) topped with a rock prop. Cheap way to add silhouette to flat areas.

## Vegetation

Vegetation lives on the Terrain as **trees** (instanced 3D meshes from prefabs) and **details** (grass billboards or short meshes). See `unity-terrain` for the underlying API.

**Density-driven scatter:**

```csharp
foreach (Vector2 candidate in PoissonDiskSample(radius: minTreeSpacing)) {
    if (terrain.SampleHeight(worldXZ) outside [altMin, altMax]) continue;
    if (terrainData.GetSteepness(x, z) > maxSlope) continue;
    if (BiomeAt(candidate) != Forest) continue;
    if (DistanceToNearestRoad(candidate) < roadClearance) continue;
    if (DistanceToNearestBuilding(candidate) < lotClearance) continue;
    if (Random.value > densityMask[x, z]) continue;
    PaintTree(treeIndex, candidate, scaleVariance, rotation);
}
terrainData.RefreshPrototypes(); // when tree prototypes changed
```

**Grass density** — `terrainData.SetDetailLayer(x, z, layerIndex, int[,] map)` writes per-pixel grass density (0..16). For thinning near roads: compute distance-to-road, fade density to 0 within `roadClearance + shoulder`. Update grass once after all roads are laid, not per-frame.

**Tree removal** for late-stage road carve or building placement:

```csharp
for (int i = terrainData.treeInstanceCount - 1; i >= 0; i--) {
    var t = terrainData.GetTreeInstance(i);
    Vector3 world = Vector3.Scale(t.position, terrainData.size) + terrain.transform.position;
    if (InsideExclusionZone(world)) RemoveTreeAt(i);
}
// Rebuild the tree array; SetTreeInstances and Flush.
```

Always paint vegetation **last** in the pipeline. Vegetation painted before roads/buildings means trees stuck in road surfaces and rooftops.

## Blending

This is the discipline that separates "procedurally generated" from "looks intentional."

**Splatmap blending — typical weight function per layer:**

```csharp
// Per (x, z) pixel; normalize across layers at the end.
float slope = terrainData.GetSteepness(x, z) / 90f;
float alt   = heights[z, x];        // 0..1
float n     = noise.snoise(...) * 0.5f + 0.5f; // break up sharp lines

w[Grass] = (1 - slope) * (1 - alt) * (1 - n * 0.3f);
w[Rock]  = slope;                                     // cliffs
w[Snow]  = math.smoothstep(0.7f, 0.9f, alt);          // peaks
w[Sand]  = math.smoothstep(0.0f, 0.1f, 0.1f - alt);   // beaches
w[Road]  = roadMask[x, z];                            // 1 inside road strip
// Normalize: rowSum = sum of all; if rowSum > 0 → each /= rowSum.
```

Sharp thresholds produce visible isolines. Always add a low-amplitude noise term (`* 0.05–0.2`) to the threshold so the boundary breathes.

**Road shoulder blending** — the splatmap weight for the road layer ramps from 1 at centerline to 0 at `halfWidth + shoulder`. Without this you get a hard edge that screams "stamp".

**Biome edges** — biome ID is discrete, but its splatmap contribution shouldn't be. At a biome boundary, sample both biomes' weights and lerp across a `biomeBlendBand` (typically 3–10 m). Same noise-perturbation trick prevents axis-aligned seams.

**Terrain-to-mesh seams** (building bases, road shoulders, prop bases):
- **URP Decal Projector** — drop a projected texture (dirt/grass-blend, gravel, scuff) onto terrain at the seam. Requires the URP renderer feature **Decal** enabled (see `unity-urp`).
- **Skirt geometry** — extend the building's base mesh 10–30 cm below terrain with a fade material, hiding any z-fighting at the foundation.
- **Vertex paint blending** — use a vertex-color channel on the prop's base to mask in a triplanar grass/dirt texture matching the surrounding terrain.

**Cliff faces** — terrain stretches its base texture across steep slopes, producing visible stretching. A **triplanar shader** (cross-link `unity-shaders`) on the rock layer samples three axes and blends by world normal, hiding the stretch. URP terrain shader doesn't do triplanar out of the box; either swap the terrain material for a triplanar custom variant, or place cliff mesh props on the steep mask.

**Vegetation density falloff** at biome edges — multiply tree density by a `1 - smoothstep(biomeBlendBand)` term so forest thins out toward desert rather than ending at a hard line.

## Common patterns

**Open-world driving level (order matters):**

1. Generate base heightmap (`unity-procgen` noise + biome mask).
2. Place POIs (Lloyd's relaxation, N iterations).
3. Build the road graph (connect adjacent POIs; avoid steep slopes by routing).
4. Carve heightmap under roads (cut + shoulder falloff). `SyncHeightmap`.
5. Generate road meshes on top of the carve (5–20 cm above the bed).
6. Tag road surface (layer + PhysicsMaterial) for vehicle friction.
7. Compute splatmap weights from height/slope/biome/road, normalize, `SetAlphamaps`.
8. Foundation-flatten under each building POI. `SyncHeightmap`. Instantiate buildings.
9. Place natural formations (rocks on steep mask, boulders near cliffs).
10. Place vegetation (trees + grass) with exclusion masks for roads + buildings.
11. Bake `NavMeshSurface`s (road = preferred area, off-road = high-cost).
12. Streaming: split into tiles via `unity-terrain` Multi-tile + `unity-addressables` for >1 km² worlds.

**Town along a river road:**

1. River = `SplineContainer`, route follows a Perlin valley (low-altitude noise contour).
2. Road parallel to river, offset 10–30 m, follows same spline with smoothing.
3. Buildings snap to road, doorways face street (perpendicular raycast).
4. Plaza node where the road widens (lot subdivision BSP on a hand-placed polygon).
5. Vegetation excluded from road + lots + 5 m river margin.

## Gotchas

- **Order of operations matters.** Painting vegetation before carving roads = trees in the road. Placing buildings before flattening = floating foundations. Build a fixed pipeline (Common patterns above) and stick to it.
- **Heightmap edits don't propagate to `TerrainCollider` automatically.** After every `SetHeights` (foundation flatten, road carve), call `terrainData.SyncHeightmap()`. Vehicles and dropped objects clip stale ground otherwise. See `unity-terrain` → Runtime API.
- **Splatmap rows must sum to 1.** Building per-layer weight then forgetting to normalize gives black or "no-layer" patches at runtime. See `unity-terrain` → Terrain Layers.
- **Sharp thresholds anywhere look procedural.** Slope/altitude/biome boundaries all need a noise-perturbed threshold or a falloff band to look intentional.
- **`SplineExtrude` is too narrow for roads.** It generates a tube; roads need a flat profile with curbs/shoulders. Build the mesh by hand from spline samples.
- **TerrainCollider raycasts don't tell you which terrain layer was hit.** You have to sample the splatmap at the hit XZ. Cache the splatmap reads if you query per frame.
- **Trees painted on a shared `TerrainData` affect every Terrain referencing it.** Duplicate `TerrainData` before per-tile editing (see `unity-terrain`).
- **Buildings instantiated before `SyncHeightmap`** read old ground in their first physics tick; physics-driven props can spawn embedded. Flatten → `SyncHeightmap` → wait one frame → `Instantiate`.
- **`Terrain.RemoveTreeInstance` shifts the array indices.** Iterate **backwards** when removing in a loop, or rebuild via `SetTreeInstances` with a filtered list.
- **Foundation flatten under a building with non-axis-aligned rotation** needs the rotated footprint, not the AABB. AABB-flattens are visible from above as oversized clearings.
- **Decals don't render unless** the URP renderer feature is on. Pink at first run = forgot to add it. See `unity-urp`.

## Verification

- Drive a `WheelCollider` vehicle (see `unity-physics` → Vehicles) along the full road network: no clipping into terrain at carves, no airborne segments at intersections, on-road friction noticeably different from off-road sampling.
- Top-down `unity-3d-verification` orthographic of a representative chunk: no trees on roads or in lots; settlements look organic (Lloyd's), not on a grid; biome transitions blend rather than snap.
- Splatmap visual check (Game view from above): no black patches, road shoulders fade, biome edges noise-perturbed.
- Cliff faces: no visible texture stretching (triplanar or cliff props).
- NavMesh bake (`unity-navmesh`): two surfaces visible (road = low cost, off-road = high cost); agent paths prefer roads but can deviate.
- Buildings: walk around each foundation in Game view — no z-fighting, no visible gaps where the building meets terrain.

## Related skills

- `unity-terrain` — heightmap/splatmap/tree APIs, `SyncHeightmap`, multi-tile.
- `unity-procgen` — noise, Poisson disk, BSP, deterministic RNG, mesh building.
- `unity-physics` — vehicle surface tagging, `WheelCollider` friction swaps.
- `unity-navmesh` — area costs, road-vs-off-road bake.
- `unity-shaders` — triplanar cliff shader, biome-blend shader.
- `unity-urp` — Decal renderer feature for junction decals.
- `unity-addressables`, `unity-scenes` — streaming chunks of world.
- `unity-cinemachine` — chase/ortho cameras to verify world composition in motion.

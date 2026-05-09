---
name: unity-lighting
description: 'Use for Unity 6+ URP lighting/GI: Light components, realtime/baked/mixed lighting, lightmaps, GPU/Progressive Lightmapper, Light/Reflection Probes, APV, ambient/skybox/fog, light/rendering layers, cookies, IES.'
---

# unity-lighting

URP-only. Unity 6. New Input System only.

## When to use

Light setup, GI bake, indoor/outdoor lighting, perf issues from lights, broken lightmaps, missing reflections, ambient wrong, fog setup, dynamic time-of-day, shadowmask blending, light cookie projection.

See: `unity-urp` (pipeline asset, light layers, fog enable), `unity-3d-verification`, `unity-profiling`, `unity-best-practices`.

## Lighting window

`Window > Rendering > Lighting`. Tabs: **Scene**, **Environment**, **Realtime Lightmaps**, **Baked Lightmaps**. Bake button bottom-right. Drag scenes into Scene tab for multi-scene lighting; each scene can hold its own Lighting Settings asset.

## Light components

- **Directional** — sun. Infinite parallel rays. Most scenes have one main. Cookies project patterns (cloud shadows).
- **Point** — radial. Distance attenuation.
- **Spot** — directional cone with Inner/Outer angle.
- **Area** — Rectangle / Disc. **Baked only** in URP.
- Mode: **Realtime** / **Mixed** (direct realtime, indirect baked) / **Baked**.
- **Indirect Multiplier** — boost/dampen GI bounce.
- **Bias / Normal Bias** — shadow acne control.

## Mixed lighting modes

Set in Lighting window → Scene → Mixed Lighting (or URP asset Quality settings).

- **Baked Indirect** — direct from realtime, indirect baked. Realtime shadows. Most flexible. Higher cost.
- **Subtractive** — direct + indirect baked. Shadows on dynamic objects only via main directional. Cheap, low quality. Historical mobile go-to.
- **Shadowmask** — direct realtime, indirect baked, shadows baked into shadowmask texture and blended with realtime up to a max distance. Best quality/cost ratio for desktop. Default in Unity 6 URP for Mixed.

## Lightmapping (the bake)

- **Lightmappers** — GPU (Progressive GPU) fast + capable GPU; CPU slower + broader compatibility.
- **Lightmap Resolution** — texels/world unit. ~40 indoor, ~10 outdoor.
- **Static flag** — Renderer must be marked Contribute GI to bake. Dynamic objects use Light Probes.
- **Lightmap UVs (UV2)** — imported FBX needs Generate Lightmap UVs ticked OR hand-authored UV2. Without it, unwrapping fails or wastes texture space.
- **Bake Backend** — Lighting → Scene → Lightmapping Settings. Generally GPU.
- **Direct/Indirect/Environment Samples** — more = less noise, longer bake. 32 / 512 / 256 typical.
- **Compress Lightmaps** — runtime memory savings; BC6H / RGBM.
- **Lightmap Padding** — gutter between charts; raise if seams.
- GI Cache: `Library/GiCache/`. Wipe via Lighting window if bakes go stale.

## Light probes

- `LightProbeGroup` defines points sampling baked GI. Dynamic objects sample trilinear-interpolated probe values for indirect lighting.
- Place densely where lighting changes (doorways, light-pool edges). Sparse = blocky/wrong indirect on moving characters.
- **Anchor Override** on Renderer controls which probe position the Renderer samples (default = bounds center). Set to a child for tall objects to sample at head height.
- **Adaptive Probe Volumes (APV)** — URP 17+ / Unity 6: auto-place probes from geometry; replaces manual LightProbeGroup. Recommended.
  - `ProbeVolume` GO sized over the area (multiple can overlap; union defines footprint).
  - Assign a Baking Set in `Lighting > Adaptive Probe Volumes`. Every scene contributing to the same baked GI must share one.
  - Per-scene state on `ProbeVolumePerSceneData`, added automatically; don't delete.
  - Enable APV in URP pipeline asset Lighting section, then bake.

## Reflection probes

- `ReflectionProbe` captures cubemap of surroundings; meshes within Box/Sphere influence sample.
- **Type**: Baked (edit-time), Custom (your cubemap), Realtime (rebakes per frame — expensive).
- **Box Projection** corrects parallax for box-shaped rooms.
- Dynamic skies/time-of-day need Realtime probes (or anchored Custom + script).

## Light layers (Rendering Layers)

- Toggle **Use Rendering Layers** in URP pipeline asset. Adds Rendering Layer Mask to Lights + Renderers.
- Light affects only Renderers whose mask intersects. Hero spotlight on player, exclude UI from world lighting, scope scene-specific lights. See `unity-urp`.

## Skybox and environment

Lighting → Environment.

- **Skybox Material** — Default-Skybox or custom.
- **Sun Source** — directional driving sky tinting on procedural skyboxes.
- **Environment Lighting Source** — Skybox / Gradient / Color. Sets ambient.
- **Environment Reflections Source** — Skybox (auto cubemap) / Custom.
- Dynamic time-of-day: Custom skybox material with shader-driven parameters; rebake reflections occasionally.

## Fog

- Lighting → Environment → Fog. Modes: Linear (Start/End), Exponential (density), Exponential Squared (denser).
- URP: enable Fog in URP asset Quality (14+). Per-camera override possible.
- Sparingly — hides culled objects + sets mood, but bakes wrong if applied at runtime to baked scenes.

## Light cookies

- 2D texture mask projected by a Light. Spotlights show window-blind shadows; Directional projects cloud shadows.
- Alpha-only black-white texture. Set Alpha Source to From Gray Scale on import.
- Point lights require a **cubemap** cookie, not 2D.

## Common scene recipes

- **Outdoor noon** — Directional (sun), Skybox = HDR Procedural, Environment Lighting = Skybox, Fog distant, Mixed mode = Shadowmask, Bake.
- **Outdoor sunset** — warm Directional with low angle, slight Bloom (`unity-urp`), Skybox tinted, Reflection Probes baked.
- **Indoor cave** — dark ambient (Color, dim), Point Lights as torches (Mixed Baked Indirect), Reflection Probe per chamber, fog density slight.
- **Mobile fast** — Subtractive mixed, single Directional, Reflection Probe disabled (small Cubemap instead), low Lightmap Resolution (10 outdoor / 20 indoor), no Realtime GI.
- **Stylized 2D** — see `unity-urp` 2D Renderer; 2D Lights instead of 3D.

## Bake performance

- GPU lightmapper >> CPU. Use it.
- Lower Lightmap Resolution where indirect is the only contribution; raise for fine direct shadows.
- Use APV instead of dense LightProbeGroups for runtime cost savings.
- Bake selected scenes only when iterating; clear GI Cache only on drastic geometry changes.
- Multi-scene editing: each scene holds own Lighting Settings; bakes per-scene.

## Gotchas

- Static flag missing → Renderer doesn't bake → object lit only by realtime. Tick Contribute GI + Receive GI = Lightmaps.
- Generate Lightmap UVs missing on FBX → black/garbled lightmaps. Re-import.
- Mixed mode without baking = looks Realtime + missing indirect. Always bake after switching to Mixed.
- Reflection Probes baked once → outdated when scene changes. Rebake.
- Setting environment lighting via script doesn't refresh static reflections; call `DynamicGI.UpdateEnvironment()`.
- Light cookies: Spot OK; Point requires cubemap, not 2D.
- Realtime point lights expensive in URP Forward; prefer baked + Shadowmask blend.
- Lightmap seam stitching only with the seam-stitching option; without it, baked seams visible.
- Shadowmask distance in URP asset caps blended-shadow range; past it only baked shadows show — moving characters lose realtime shadows.
- Project Settings → Graphics → Lightmap Modes determines which lightmap variants ship; mismatch with what you baked = pink/wrong at runtime.
- APV requires URP 17+ + a baked light setup; check enable flag in URP asset, confirm every contributing scene shares a Baking Set in `Lighting > Adaptive Probe Volumes`. Missing `ProbeVolumePerSceneData` = no APV data loaded.

## Verification

- Editor console clean of "Lightmap UVs missing" / "Generate Lightmap UVs" / "Could not find lightmap".
- Lighting window → Baked Lightmaps shows generated atlases — visually inspect for seams, dead space.
- Scene view → Draw Mode = Baked Lightmap to see lightmap contribution; Indirect for GI only; Shadowmask for shadowmask coverage.
- 3D scene changes → `unity-3d-verification` 4-shot at multiple times-of-day.
- Profile lighting cost: Profiler → Rendering shows shadow pass time + light culling. See `unity-profiling`.

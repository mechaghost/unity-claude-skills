---
name: unity-lighting
description: Use when working with Unity lighting and global illumination through Unity MCP — lighting, light, Light component, directional light, point light, spot light, area light, baked light, realtime light, mixed light, baked GI, realtime GI, GI cache, lightmap, lightmapper, GPU lightmapper, Progressive Lightmapper, light probe, light probe group, reflection probe, ambient lighting, environment lighting, skybox, fog, lighting window, Window Rendering Lighting, lightmap UV, UV2, lightmap resolution, mixed lighting mode, Baked Indirect, Subtractive, Shadowmask, light layer, rendering layer, GI, global illumination, lighting bake, light cookie, IES profile. Unity 6 / URP only / new Input System only.
---

# unity-lighting

URP-only. Unity 6. New Input System only.

MCP cheatsheet: manage_graphics, manage_components, manage_gameobject, manage_scene, manage_asset, manage_packages, manage_editor, manage_material, manage_camera, find_gameobjects, read_console, unity_reflect, unity_docs, apply_text_edits, create_script, batch_execute, execute_menu_item.

## When to use

Light setup, GI bake, indoor / outdoor lighting, performance issues from lights, broken lightmaps, missing reflections, ambient light wrong, fog setup, dynamic time-of-day, shadowmask blending, light cookie projection.

Cross-link: `unity-urp` (pipeline asset, light layers, fog enable), `unity-3d-verification`, `unity-profiling`, `unity-best-practices`.

## Lighting window

`Window > Rendering > Lighting`. Tabs: **Scene**, **Environment**, **Realtime Lightmaps**, **Baked Lightmaps**. Bake button bottom-right. Drag scenes into the Scene tab to manage multi-scene lighting; each scene can hold its own Lighting Settings asset.

## Light components

- **Directional** — sun. Infinite parallel rays. Most scenes have one main light. Cookies project patterns (e.g. cloud shadows).
- **Point** — radial. Position-based attenuation falls off with distance.
- **Spot** — directional cone with Inner / Outer angle.
- **Area** — Rectangle / Disc. **Baked only** in URP — cannot be realtime.
- Mode: **Realtime** (computed every frame), **Mixed** (direct realtime, indirect baked), **Baked** (everything baked into lightmaps).
- **Indirect Multiplier** — boost / dampen GI bounce contribution.
- **Bias / Normal Bias** — shadow acne control.

## Mixed lighting modes

Set in Lighting window > Scene > Mixed Lighting (or via the URP asset's Quality settings).

- **Baked Indirect** — direct from realtime lights, indirect baked. Realtime shadows. Most flexible. Higher cost.
- **Subtractive** — direct + indirect baked. Shadows on dynamic objects only via main directional. Cheap, low quality. Historical mobile go-to.
- **Shadowmask** — direct realtime, indirect baked, shadows baked into a shadowmask texture and blended with realtime shadows up to a max distance. Best quality / cost ratio for desktop. Default in Unity 6 URP for Mixed.

## Lightmapping (the bake)

- **Lightmappers**: GPU (Progressive GPU) — fast, requires capable GPU; CPU (Progressive CPU) — slower, broader compatibility.
- **Lightmap Resolution** — texels per world unit. ~40 indoor, ~10 outdoor typical. Higher = finer shadows, larger files.
- **Static flag**: a Renderer must be marked Contribute GI (Static flags > Contribute GI) to bake into lightmaps. Dynamic objects use Light Probes instead.
- **Lightmap UVs (UV2)**: imported FBX needs Generate Lightmap UVs ticked OR a hand-authored UV2 channel. Without it, lightmap unwrapping fails or wastes texture space.
- **Bake Backend**: Lighting window > Scene > Lightmapping Settings. Generally GPU.
- **Direct / Indirect / Environment Samples**: more = less noise, longer bake. 32 / 512 / 256 typical.
- **Compress Lightmaps** — runtime memory savings; uses BC6H / RGBM.
- **Lightmap Padding** — gutter between charts; raise if seeing seams.
- GI Cache lives under `Library/GiCache/`. Wipe via Lighting window if bakes go stale.

## Light probes

- GameObject with `LightProbeGroup`; defines points sampling the baked GI. Dynamic objects sample the trilinear-interpolated probe values at runtime for indirect lighting.
- Place probes densely where lighting changes (doorways, edges of light pools). Sparse probes = blocky / wrong indirect on moving characters.
- **Anchor Override** on Renderer — controls which probe position the Renderer samples (default = bounds center). Set to a specific child for tall objects to sample at head height.
- **Adaptive Probe Volumes (APV)** — URP 17+ / Unity 6: auto-place probes based on geometry; replaces manual LightProbeGroup. Strongly recommended. Concrete setup:
  - Add a `ProbeVolume` component to a GameObject sized over the area to cover (multiple volumes can overlap; the union defines the probe footprint).
  - Assign a Baking Set in `Lighting > Adaptive Probe Volumes` — every scene that contributes to the same baked GI must share a Baking Set.
  - Per-scene state is stored on a `ProbeVolumePerSceneData` component that Unity adds to the scene automatically when an APV is baked; do not delete it.
  - Enable APV in the URP pipeline asset's Lighting section, then bake from the Lighting window.

## Reflection probes

- GameObject with `ReflectionProbe`. Captures a cubemap of surroundings; meshes within Box / Sphere influence sample it for environment reflection.
- **Type**: Baked (cubemap baked at edit time), Custom (drag your own cubemap), Realtime (rebakes each frame — expensive).
- **Box Projection** corrects parallax for box-shaped rooms.
- Dynamic skies / time-of-day need Realtime probes (or anchored Custom + script).

## Light layers (Rendering Layers)

- Toggle **Use Rendering Layers** in the URP pipeline asset. Adds Rendering Layer Mask to Lights and Renderers.
- Light affects only Renderers whose Rendering Layer Mask intersects the Light's mask. Use to: light only the player with a hero spotlight, exclude UI from world lighting, scope scene-specific lights.
- See `unity-urp` for pipeline-asset toggles.

## Skybox and environment

Lighting window > Environment tab.

- **Skybox Material** — Default-Skybox or custom.
- **Sun Source** — directional light driving sky tinting on procedural skyboxes.
- **Environment Lighting Source**: Skybox / Gradient / Color. Sets ambient.
- **Environment Reflections Source**: Skybox (auto cubemap) / Custom cubemap.
- For dynamic time-of-day, use a Custom skybox material with shader-driven parameters; rebake reflections occasionally.

## Fog

- Lighting window > Environment > Fog.
- Modes: Linear (Start / End distances), Exponential (density), Exponential Squared (denser).
- URP: enable Fog in URP asset's Quality section (added in 14+). Per-camera override possible.
- Use sparingly — fog hides culled objects gracefully and sets mood, but bakes wrong if applied at runtime to baked scenes.

## Light cookies

- 2D texture mask projected by a Light. Spotlights show window-blind shadows; Directional projects cloud shadows.
- Format: alpha-only black-white texture. Set Alpha Source to From Gray Scale on import.
- Point lights require a **cubemap** cookie, not a 2D texture.

## Common scene recipes

- **Outdoor noon** — Directional Light (sun), Skybox = HDR Procedural, Environment Lighting = Skybox, Fog distant, Mixed mode = Shadowmask, Bake.
- **Outdoor sunset** — warm Directional with low angle, slight Bloom (see `unity-urp`), Skybox tinted, Reflection Probes baked.
- **Indoor cave** — dark ambient (Color, dim), Point Lights as torches (Mixed Baked Indirect for warm glow), Reflection Probe per chamber, fog density slight.
- **Mobile fast** — Subtractive mixed mode, single Directional, Reflection Probe disabled (small Cubemap instead), low Lightmap Resolution (10 outdoor / 20 indoor), no Realtime GI.
- **Stylized 2D** — see `unity-urp` 2D Renderer; 2D Lights instead of 3D.

## Bake performance

- GPU lightmapper >> CPU. Use it.
- Lower Lightmap Resolution where indirect is the only contribution; raise for fine direct shadows.
- Use Adaptive Probe Volumes instead of dense LightProbeGroups for runtime cost savings.
- Bake selected scenes only when iterating; clear GI Cache only when geometry changes drastically.
- Multi-scene editing: each scene holds its own Lighting Settings asset; bakes per-scene.

## Gotchas

- Static flag missing → Renderer doesn't bake → object lit only by realtime lights. Tick Contribute GI + Receive GI = Lightmaps.
- Generate Lightmap UVs missing on FBX → black / garbled lightmaps. Re-import the model.
- Mixed mode without baking = looks like Realtime + missing indirect. Always bake after switching to Mixed.
- Reflection Probes baked once → outdated when scene changes. Rebake in Lighting window.
- Setting environment lighting via script doesn't refresh static reflections; call `DynamicGI.UpdateEnvironment()` after changes.
- Light cookies on Spot lights work; on Point lights they require a cubemap, not 2D.
- Realtime point lights are expensive in URP Forward; prefer baked + Shadowmask blend.
- Lightmap seam stitching only with the seam-stitching option enabled; without it, baked seams visible.
- Shadowmask distance in URP asset caps blended-shadow range; past it only baked shadows show — moving characters lose realtime shadows.
- Project Settings > Graphics > Lightmap Modes determines which lightmap variants ship; mismatch with what you baked = pink / wrong at runtime.
- APV (Adaptive Probe Volumes) requires URP 17+ and a baked light setup; check the enable flag in the URP asset, and confirm every contributing scene shares a Baking Set assignment in `Lighting > Adaptive Probe Volumes`. Missing `ProbeVolumePerSceneData` on a scene = no APV data loaded for it.

## Verification

- `read_console` for "Lightmap UVs missing" / "Generate Lightmap UVs" / "Could not find lightmap" warnings.
- Lighting window > Baked Lightmaps tab shows the generated atlases — visually inspect for seams, dead space.
- Scene view > Draw Mode = Baked Lightmap to see lightmap contribution; Indirect for GI only; Shadowmask for shadowmask coverage.
- For 3D scene changes, verify via `unity-3d-verification` 4-shot at multiple times-of-day.
- Profile lighting cost: Profiler > Rendering module shows shadow pass time + light culling. See `unity-profiling`.

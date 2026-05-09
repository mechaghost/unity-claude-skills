---
name: unity-urp
description: 'Use when configuring Unity''s Universal Render Pipeline through Unity MCP — pipeline-asset and renderer-asset settings, post-processing volumes, camera stacks, renderer features, 2D Renderer / 2D Lights, light layer / rendering layer masks, migrating from Built-in to URP. This skill set is URP-only; HDRP is out of scope. Triggers — URP, Universal Render Pipeline, pipeline asset, renderer feature, volume, post-processing, bloom, vignette, depth of field, color grading, tonemapping, 2D renderer, SRP Batcher, HDR, MSAA, opaque texture, depth texture, light layer, rendering layer, camera stack, base camera, overlay camera, deferred forward, switch render pipeline.'
---

> **Policy:** This skill set assumes URP. Built-in and HDRP are not covered. Built-in→URP migration guidance is included because legacy asset imports routinely pull in Built-in materials; HDRP is out of scope.

## When to use

Any URP project setup or pipeline-level change: installing/upgrading the URP package, creating or editing a pipeline asset, editing a Universal Renderer asset, adding/removing renderer features (SSAO, decals, screen-space shadows, custom passes), configuring post-processing volumes (bloom, vignette, DOF, color grading, tonemapping), building a camera stack with overlays, toggling HDR / MSAA / depth texture / opaque texture, configuring 2D Lights / Light Blend Styles, light-layer or rendering-layer masking, migrating a project from Built-in to URP, or diagnosing URP-specific performance regressions.

For shader and material concerns (URP/Lit, Shader Graph compatibility, Built-in pink-shader fix), defer to `unity-shaders`. For verifying a 3D scene change, use `unity-3d-verification`.

## URP architecture

URP is configured at four nested layers. Knowing which layer holds a setting is most of the skill.

1. **Project settings.** `Project Settings > Graphics > Scriptable Render Pipeline Settings` assigns ONE pipeline asset as the global default. `Project Settings > Quality` lets each quality tier override that with a different pipeline asset (mobile-low vs desktop-high).
2. **Pipeline asset** (`UniversalRenderPipelineAsset`). Holds project-wide quality knobs: HDR, MSAA, render scale, shadow distance/cascades, additional-light mode, post-processing grading mode. References one or more **Renderer assets**, with one marked default.
3. **Renderer asset.** `UniversalRendererData` (3D) or `Renderer2DData` (2D). Holds the renderer features list, rendering path (Forward / Forward+ / Deferred), filtering layer masks, and decal/SSAO/screen-space-shadow settings.
4. **Camera + Volume system.** Each Camera picks a Renderer (or uses pipeline default), is Base or Overlay, and reads from the Volume system for post-processing. **Volume** components on GameObjects (Global or Local) reference **Volume Profile** assets that hold the actual post-process overrides.

Cameras can be stacked: a **Base** camera owns a render target; **Overlay** cameras render into it in order (UI on top, viewmodel weapon, etc.). Only the Base owns post-processing for the stack.

## Pipeline asset

Edit via `manage_asset` on the `.asset` file, or via `manage_graphics` (pipeline-settings actions).

- **General.** `Depth Texture` — enable when anything samples scene depth (soft particles, water, SSAO, distortion); costs a copy pass. `Opaque Texture` — enable for refraction / glass / heat-haze effects sampling the scene color; also a copy pass. `Terrain Holes`. `Force Render to Texture` (HDR pipeline path).
- **Quality.** `HDR` — enable for bloom and tonemapping; required for ACES. `MSAA` — Off / 2x / 4x / 8x; expensive on mobile and redundant if relying on FXAA/SMAA. `Render Scale` — 0.5–2.0; the simplest dynamic-resolution lever.
- **Lighting.** `Main Light` shadows on/off + resolution. `Additional Lights` — Disabled / Per Vertex / Per Pixel; Per Pixel is correct quality and the expensive option. `Cookie Atlas` size and format.
- **Shadows.** `Max Distance`, `Cascade Count` (1–4), `Soft Shadows` toggle, depth bias.
- **Post-processing.** `Grading Mode` — LDR (mobile) or HDR (desktop with HDR enabled). `LUT Size` — 16/32; 32 is film-grade.

## Universal Renderer asset

The renderer holds rendering-path and feature decisions. See `references/renderer-features.md` for the full feature catalog.

- **Rendering Path.** `Forward` (legacy, simple, per-object light cap), `Forward+` (modern default — many lights via tile-based binning, no per-object cap), `Deferred` (many-lights AAA scenes; transparent objects still go through forward, MSAA is unsupported, shader compatibility narrower).
- **Default Stencil State, Render Pass Strategy, Native RenderPass** (mobile tile-based GPUs benefit from Native RenderPass).
- **Renderer Features list.** Add/remove via the renderer asset inspector (or `manage_asset`). Built-ins: SSAO, Decal, Screen Space Shadows, Render Objects, Full Screen Pass.
- **Filtering.** `Opaque Layer Mask`, `Transparent Layer Mask` — restrict which scene layers this renderer draws. `Rendering Layer Mask` — light-layer filtering at the renderer level.

## Camera and camera stack

Edit cameras with `manage_camera` and `manage_components`.

- **Render Type.** `Base` — owns a render target, runs post-processing, draws the world. `Overlay` — composites onto a Base's target; appears in the Base's Camera Stack list. UI cameras, weapon viewmodels, minimap inserts are Overlays.
- **Renderer override.** A camera can pick a renderer asset other than the pipeline default (e.g. minimap uses a renderer with no SSAO, no decals).
- **Post Processing toggle.** Per camera. **Only enable on Base.** Overlay with PP on costs a redundant pass and double-grades.
- **Anti-aliasing.** None / FXAA (cheap) / SMAA (better edges, slightly costlier). `Stop NaN` for HDR safety. `Dithering` to break LDR banding.
- **Volume Mask** (layer mask) and **Volume Trigger** (transform). Camera only sees Volumes whose GameObject layer is in the mask, evaluated at the Trigger transform's position. Default Trigger is the camera itself.
- **Camera Stack list** lives on the Base Camera. Overlays render in list order after the Base.

## Volume system

See `references/post-processing.md` for the full effect catalog and recommended profiles.

- **Volume component.** `Mode = Global` (always applies, weighted by Priority) or `Local` (applies inside a `Collider` set to `isTrigger`, blended by distance). `Weight` 0–1, `Priority` (higher wins ties), `Blend Distance` (Local only).
- **Volume Profile asset.** Holds the actual overrides. Add overrides per effect; each override has a checkbox per parameter (only checked params apply). Edit via `manage_graphics` post-processing actions or by editing the `.asset` directly with `manage_asset`.
- **Authoring pattern.** One Global Volume with a "Default" profile sets the project look. Local Volumes layer on area-specific looks (cave: darker exposure + heavier vignette; underwater: blue color filter + chromatic aberration).
- **Common overrides:** Bloom, Tonemapping (Neutral / ACES), Color Adjustments, White Balance, Vignette, Depth of Field (Gaussian / Bokeh), Motion Blur, Film Grain, Lens Distortion, Chromatic Aberration, Channel Mixer, Shadows Midtones Highlights, Lift Gamma Gain, Split Toning.

## Lighting

- **Light types.** Directional, Point, Spot — Realtime / Mixed / Baked. Area (Rectangle, Disc) — Baked only.
- **Mixed sub-modes.** Baked Indirect, Subtractive, Shadowmask. Pick one per scene under Lighting Settings.
- **Light Layers (Rendering Layers).** Enable in the pipeline asset under Lighting. Each Light has a Rendering Layer mask; each Renderer (MeshRenderer etc.) has one too. A light only illuminates renderers whose mask intersects its mask. Use case: a key light for the player only, not the level.
- **Lightmapping.** `Window > Rendering > Lighting`. Bake via `manage_graphics` (light-baking action). Prefer the GPU lightmapper. Set Lightmap Resolution conservatively — bake times scale quadratically.
- **Reflection probes.** Baked or Realtime; Box or Sphere proxy. Renderer's Reflection Probes setting (Off / Blend Probes / Blend Probes And Skybox / Simple) controls how it samples.

## 2D Renderer

A separate renderer asset (`Renderer2DData`) — assign it to the pipeline asset (or to a specific camera) for 2D projects.

- **2D Lights.** Component types: Freeform, Sprite, Parametric, Point, Global. Add via `manage_components`.
- **Light Blend Styles.** Up to four channels on the 2D Renderer asset. Each style picks a blend mode (Multiply / Additive / Modulate) and mask channel. Lights and sprites both reference a blend style index.
- **Lit sprites.** Sprite materials must use `Sprite-Lit-Default` or a `Sprite Lit Shader Graph` to receive 2D lights. Default `Sprite-Default` is unlit and ignores 2D Lights entirely.
- **Normal / mask maps.** Authored in Sprite Editor's Secondary Textures pane (`_NormalMap`, `_MaskTex`).
- **Shadow Caster 2D.** Component on tilemaps / sprites to cast 2D shadows from 2D Lights that have shadows enabled.

## Renderer features

Built-in features (`UniversalRendererData` inspector → Add Renderer Feature):

- **SSAO** — screen-space ambient occlusion. Costly; off on mobile by default.
- **Screen Space Shadows** — Forward path, directional light only, replaces shadow sampling pass.
- **Decal** — projection decals (DBuffer or Screen Space). DBuffer needs `_CameraNormalsTexture` available.
- **Render Objects** — render selected layer / rendering-layer mask with a custom material/shader at a specific event in the frame. The workhorse for outline / silhouette / X-ray passes.
- **Full Screen Pass Renderer Feature** — apply a Shader Graph "Fullscreen" shader as a post-process before/after transparents.

Custom features: derive `ScriptableRendererFeature` and `ScriptableRenderPass` C# classes via `create_script` / `apply_text_edits`, then add to the renderer asset. See `references/renderer-features.md` for the skeleton and event-ordering rules.

## Switching pipelines

- **Built-in to URP.** This skill set targets URP, but legacy asset packages, Asset Store content, and older Unity templates routinely import Built-in shaders/materials — so this migration is the common case. Install URP via `manage_packages` (`com.unity.render-pipelines.universal`). Create the pipeline asset (`Assets > Create > Rendering > URP Asset (with Universal Renderer)`) — `manage_asset`. Assign under `Project Settings > Graphics`. Run `Edit > Rendering > Materials > Convert Selected/All Built-in Materials to URP` to remap Standard / Legacy shaders. Custom hand-written shaders need rewriting — see `unity-shaders`.
- **Per-quality overrides.** In `Project Settings > Quality`, each tier can point to a different pipeline asset; the global Graphics setting is only the fallback. Devs editing the wrong tier and seeing no change is a top miss.

## Performance

- HDR + MSAA + full PP stack each cost real ms. Mobile budget: LDR, FXAA, MSAA off, no SSAO, **render scale 0.7-0.75 with FSR1 / TAAU upscaling** (URP renderer feature), ≤1 shadow cascade, 1 directional light + a few baked.
- Mobile shadows: **shadow distance ≤30 m**, **1 cascade on low-end**, **2 on flagship**. Cascade count dominates shadow cost more than shadowmap resolution. Cross-link `unity-build` references/mobile.md for the broader mobile budget.
- SSAO is the single most expensive renderer feature; profile before shipping it.
- Shadow distance and cascade count dominate shadow cost more than shadowmap resolution.
- Depth Texture and Opaque Texture each add a copy pass — only enable if a feature uses them.
- Forward+ supports many lights without the per-object light cap, but tile binning has constant overhead; on scenes with ≤4 lights Forward can be cheaper.
- **SRP Batcher** requires SRP-compatible shaders. URP/Lit and Shader Graph qualify by default; old hand-written shaders may not. The shader inspector shows compatibility status; `read_console` surfaces incompatibility warnings.
- Use `manage_profiler`'s Frame Debugger to inspect the actual pass list — far more reliable than reasoning about renderer features.

## Common patterns

- **Cinematic.** HDR on, ACES tonemapping, Bloom intensity ~1.0 / threshold ~1.1 / scatter 0.7, Color Adjustments post-exposure +0.3, soft Vignette, light Film Grain.
- **Stylized 2D.** 2D Renderer + one Global 2D Light (low intensity ambient) + per-area Point / Freeform 2D Lights + Shadow Caster 2D on tilemap walls + normal maps on hero sprites.
- **Mobile budget.** LDR, FXAA, no SSAO, MSAA off, half-res post-process, render scale 0.7-0.75 with FSR1 / TAAU upscaling, 1 shadow cascade (2 on flagship), max distance ~30m.
- **Outline selected object.** Assign the object to a Rendering Layer; add a `Render Objects` renderer feature filtering on that layer with an outline material; run after opaques. No global script needed.

## Gotchas

- Built-in (or HDRP) shaders render pink in URP. Convert via `Edit > Rendering > Materials > Convert ... to URP`; for custom HLSL see `unity-shaders`.
- **Volume not affecting camera.** The Volume's GameObject layer isn't in the camera's `Volume Mask`. Or for Local Volumes: the Collider isn't a trigger, or the camera's `Volume Trigger` transform is outside the collider bounds.
- **Overlay camera with post-processing on** costs an extra full pass and may double-tonemap. Only Base owns PP.
- **SRP Batcher off** = an incompatible shader broke batching. Check `read_console` for SRP Batcher compatibility messages and the shader inspector's compatibility line.
- **Light Layers do nothing** unless `Rendering Layers` is enabled on the pipeline asset AND each Light AND each Renderer has its mask set.
- **Wrong pipeline asset edited.** Graphics-settings asset is fallback; per-Quality-tier assets override. Confirm which is active for the current quality level before tuning.
- **2D Lights have no effect** on sprites using `Sprite-Default`. Switch material to `Sprite-Lit-Default`.
- **Renderer assets are project-committed.** Adding a Renderer Feature edits the `.asset` file — multiple devs editing the same renderer asset is a merge nightmare. Treat renderer assets like config and review changes deliberately.
- **Camera stack overlays don't see base depth.** The depth texture available to overlays is a copy of the base's pre-stack render; depth-sampling shaders on overlay-rendered objects (e.g. weapon viewmodel sampling scene depth) will read stale or empty depth. Render those into the base instead, or skip depth-dependent effects on the overlay.
- **Deferred + transparents.** Transparents still render in forward inside a deferred renderer; some custom features expecting GBuffer access break on them.
- **MSAA in deferred** is unsupported. Use post-process AA (SMAA) on deferred.

## Verification

After any 3D pipeline change, run `unity-3d-verification` (4-shot orthographic) and capture a Game-view screenshot showing the active post-processing stack. After enabling or modifying a renderer feature, capture a Frame Debugger screenshot via `manage_profiler` to confirm the expected pass actually appears in the frame and in the right order. After switching pipelines or per-quality overrides, take screenshots of every quality tier the project ships — quality-tier overrides are the most-missed regression source.

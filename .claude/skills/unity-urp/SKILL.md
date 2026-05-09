---
name: unity-urp
description: 'Use for Unity 6+ URP configuration: pipeline/renderer assets, post-processing volumes, camera stacks, renderer features, 2D Renderer/Lights, render layers, SRP Batcher, HDR/MSAA/depth/opaque textures, Built-in-to-URP migration. HDRP out of scope.'
---

> **Policy:** URP only. Built-in and HDRP are not covered. Built-in→URP migration is included since legacy imports pull in Built-in materials; HDRP is out of scope.

## When to use

URP install/upgrade; pipeline asset; Universal Renderer asset; renderer features (SSAO, decals, screen-space shadows, custom passes); post-processing volumes (bloom, vignette, DOF, color grading, tonemapping); camera stack with overlays; HDR/MSAA/depth/opaque texture toggles; 2D Lights / Light Blend Styles; light/rendering-layer masking; Built-in → URP migration; URP-specific perf.

Materials/shaders → `unity-shaders`. 3D scene verify → `unity-3d-verification`.

## URP architecture

Four nested layers:

1. **Project settings** — `Project Settings > Graphics > Scriptable Render Pipeline Settings` assigns ONE pipeline asset as global default. `Project Settings > Quality` lets each tier override.
2. **Pipeline asset** (`UniversalRenderPipelineAsset`) — project-wide quality: HDR, MSAA, render scale, shadow distance/cascades, additional-light mode, PP grading. References one+ **Renderer assets** with one default.
3. **Renderer asset** — `UniversalRendererData` (3D) or `Renderer2DData` (2D). Features list, rendering path (Forward / Forward+ / Deferred), filtering layer masks, decal/SSAO/screen-space-shadow.
4. **Camera + Volume system** — each Camera picks a Renderer (or pipeline default), is Base or Overlay, reads from Volumes for PP. **Volume** components reference **Volume Profile** assets holding actual overrides.

Camera stacks: **Base** owns the render target; **Overlay** cameras render into it in order. Only Base owns PP.

## Pipeline asset

- **General.** `Depth Texture` — enable when sampling scene depth (soft particles, water, SSAO, distortion); costs a copy pass. `Opaque Texture` — for refraction/glass/heat-haze sampling scene color; copy pass. `Terrain Holes`. `Force Render to Texture`.
- **Quality.** `HDR` — required for bloom + ACES tonemapping. `MSAA` — Off / 2× / 4× / 8×; expensive on mobile, redundant if using FXAA/SMAA. `Render Scale` — 0.5–2.0; simplest dynamic-resolution lever.
- **Lighting.** `Main Light` shadows + resolution. `Additional Lights` — Disabled / Per Vertex / Per Pixel; Per Pixel is expensive correct quality. `Cookie Atlas` size/format.
- **Shadows.** `Max Distance`, `Cascade Count` (1–4), `Soft Shadows`, depth bias.
- **Post-processing.** `Grading Mode` — LDR (mobile) or HDR (desktop with HDR). `LUT Size` — 16/32; 32 is film-grade.

## Universal Renderer asset

See `references/renderer-features.md` for the full feature catalog.

- **Rendering Path.** `Forward` (default, simple, per-object light cap), `Forward+` (modern option for many lights via tile binning, no per-object cap), `Deferred` (many-lights AAA; transparents still go forward, MSAA unsupported, narrower shader compatibility).
- **Default Stencil State, Render Pass Strategy, Native RenderPass** (mobile tile-based GPUs benefit from Native RenderPass).
- **Renderer Features list.** Built-ins: SSAO, Decal, Screen Space Shadows, Render Objects, Full Screen Pass.
- **Filtering.** `Opaque Layer Mask`, `Transparent Layer Mask` — restrict scene layers. `Rendering Layer Mask` — light-layer filtering at renderer level.

## Camera and camera stack

- **Render Type.** `Base` — owns target, runs PP, draws world. `Overlay` — composites onto Base; appears in Base's Camera Stack. UI cameras, weapon viewmodels, minimap inserts are Overlays.
- **Renderer override.** Camera can pick a non-default renderer (minimap with no SSAO/decals).
- **Post Processing toggle.** Per camera. **Only enable on Base.** Overlay PP costs redundant pass + double-grades.
- **Anti-aliasing.** None / FXAA (cheap) / SMAA (better edges, slightly costlier). `Stop NaN` for HDR safety. `Dithering` for LDR banding.
- **Volume Mask** + **Volume Trigger** (transform). Camera sees only Volumes whose GO layer is in the mask, evaluated at Trigger position. Default Trigger is the camera.
- **Camera Stack list** on the Base. Overlays render in list order after Base.

## Volume system

See `references/post-processing.md` for the effect catalog and recommended profiles.

- **Volume component.** `Mode = Global` (always applies, weighted by Priority) or `Local` (inside an `isTrigger` `Collider`, distance-blended). `Weight` 0–1, `Priority` (higher wins ties), `Blend Distance` (Local).
- **Volume Profile asset.** Holds overrides; checkbox per parameter (only checked apply).
- **Authoring pattern.** One Global Volume "Default" sets project look. Local Volumes layer area-specific looks (cave: darker exposure + heavier vignette; underwater: blue color filter + chromatic aberration).
- **Common overrides:** Bloom, Tonemapping (Neutral/ACES), Color Adjustments, White Balance, Vignette, Depth of Field (Gaussian/Bokeh), Motion Blur, Film Grain, Lens Distortion, Chromatic Aberration, Channel Mixer, Shadows Midtones Highlights, Lift Gamma Gain, Split Toning.

## Lighting

- **Light types** — Directional, Point, Spot — Realtime / Mixed / Baked. Area (Rectangle, Disc) — Baked only.
- **Mixed sub-modes** — Baked Indirect, Subtractive, Shadowmask. Pick one per scene.
- **Light Layers (Rendering Layers)** — enable in pipeline asset Lighting. Light illuminates only Renderers whose mask intersects. Hero spotlight on player, not level.
- **Lightmapping** — `Window > Rendering > Lighting`. Bake from Lighting window. Prefer GPU lightmapper. Lightmap Resolution conservatively — bake times scale quadratically.
- **Reflection probes** — Baked or Realtime; Box or Sphere proxy. Renderer's Reflection Probes setting (Off / Blend Probes / Blend Probes And Skybox / Simple) controls sampling.

## 2D Renderer

Separate `Renderer2DData` — assign to pipeline asset (or specific camera).

- **2D Lights** — Freeform, Sprite, Parametric, Point, Global.
- **Light Blend Styles** — up to four channels on 2D Renderer asset. Each picks blend mode (Multiply / Additive / Modulate) + mask channel. Lights and sprites reference a blend style index.
- **Lit sprites** — `Sprite-Lit-Default` or `Sprite Lit Shader Graph`. Default `Sprite-Default` is unlit, ignores 2D Lights.
- **Normal/mask maps** — Sprite Editor Secondary Textures (`_NormalMap`, `_MaskTex`).
- **Shadow Caster 2D** — on tilemaps/sprites to cast 2D shadows from shadow-enabled 2D Lights.

## Renderer features

Built-ins (`UniversalRendererData` inspector → Add Renderer Feature):

- **SSAO** — screen-space AO. Costly; off on mobile by default.
- **Screen Space Shadows** — Forward path, directional only, replaces shadow sampling pass.
- **Decal** — projection decals (DBuffer or Screen Space). DBuffer needs `_CameraNormalsTexture`.
- **Render Objects** — render selected layer/rendering-layer with custom material/shader at chosen frame event. Workhorse for outline/silhouette/X-ray.
- **Full Screen Pass Renderer Feature** — apply a Shader Graph "Fullscreen" shader as PP before/after transparents.

Custom: derive `ScriptableRendererFeature` and `ScriptableRenderPass`. See `references/renderer-features.md` for skeleton + event ordering.

## Switching pipelines

- **Built-in to URP.** Common case from Asset Store / older templates. Install URP (`com.unity.render-pipelines.universal`). Create pipeline asset (`Assets > Create > Rendering > URP Asset (with Universal Renderer)`). Assign in `Project Settings > Graphics`. Run `Edit > Rendering > Materials > Convert Selected/All Built-in Materials to URP`. Custom HLSL needs rewriting → `unity-shaders`.
- **Per-quality overrides.** Each Quality tier can point to a different pipeline asset; Graphics setting is fallback. Editing the wrong tier and seeing no change is a top miss.

## Performance

- HDR + MSAA + full PP each cost real ms. Mobile budget: LDR, FXAA, MSAA off, no SSAO, **render scale 0.7–0.75 with FSR1/TAAU**, ≤1 shadow cascade, 1 directional + a few baked.
- Mobile shadows: **distance ≤30 m**, **1 cascade low-end / 2 flagship**. Cascade count dominates more than shadowmap resolution. See `unity-build` references/mobile.md.
- SSAO is the single most expensive feature; profile before shipping.
- Depth Texture + Opaque Texture each add a copy pass — only enable if used.
- Forward+ supports many lights without per-object cap, but tile binning has constant overhead; ≤4 lights, Forward can be cheaper.
- **SRP Batcher** requires SRP-compatible shaders. URP/Lit + Shader Graph qualify; old hand-written may not. Shader inspector shows status; console surfaces incompatibility.
- Frame Debugger inspects actual pass list — more reliable than reasoning about features.

## Common patterns

- **Cinematic.** HDR on, ACES tonemapping, Bloom intensity ~1.0 / threshold ~1.1 / scatter 0.7, Color Adjustments post-exposure +0.3, soft Vignette, light Film Grain.
- **Stylized 2D.** 2D Renderer + Global 2D Light (low ambient) + per-area Point/Freeform 2D Lights + Shadow Caster 2D on tilemap walls + normal maps on hero sprites.
- **Mobile budget.** LDR, FXAA, no SSAO, MSAA off, half-res post-process, render scale 0.7–0.75 with FSR1/TAAU, 1 shadow cascade (2 flagship), max distance ~30 m.
- **Outline selected object.** Assign to a Rendering Layer; add `Render Objects` filtering on that layer with outline material; run after opaques. No global script.

## Gotchas

- Built-in/HDRP shaders render pink in URP. Convert via `Edit > Rendering > Materials > Convert ... to URP`; custom HLSL → `unity-shaders`.
- **Volume not affecting camera.** Volume's GO layer not in camera's `Volume Mask`. Local Volumes: Collider not a trigger, or camera's `Volume Trigger` outside collider bounds.
- **Overlay camera with PP on** costs an extra full pass + may double-tonemap. Only Base owns PP.
- **SRP Batcher off** = incompatible shader broke batching. Check console + shader inspector compatibility line.
- **Light Layers do nothing** unless `Rendering Layers` is enabled on pipeline asset AND each Light + Renderer has its mask set.
- **Wrong pipeline asset edited.** Graphics-settings asset is fallback; per-Quality assets override. Confirm which is active before tuning.
- **2D Lights have no effect** on `Sprite-Default`. Switch to `Sprite-Lit-Default`.
- **Renderer assets are project-committed.** Adding a feature edits the `.asset` — multiple devs editing it = merge nightmare. Treat as config; review changes deliberately.
- **Camera stack overlays don't see base depth.** Overlay depth texture is a copy of base's pre-stack render; depth-sampling shaders on overlays read stale/empty depth. Render into base instead, or skip depth-dependent effects on overlay.
- **Deferred + transparents.** Transparents render in forward inside a deferred renderer; some custom features expecting GBuffer access break.
- **MSAA in deferred** is unsupported. Use SMAA on deferred.

## Verification

After any 3D pipeline change → `unity-3d-verification` (4-shot orthographic) + Game-view screenshot showing active PP stack. After enabling/modifying a renderer feature → Frame Debugger screenshot to confirm expected pass appears in the right order. After switching pipelines or per-quality overrides → screenshots of every quality tier shipped (quality-tier overrides are the most-missed regression).

---
name: unity-shaders
description: 'Use when working with Unity shaders, materials, or Shader Graph (trigger: shader, material, ShaderGraph, HLSL, ShaderLab, pink material, missing shader, normal map, render queue, blend mode, transparent, cutout, GPU instancing, batching, MaterialPropertyBlock, custom shader, surface shader, Lit shader, Unlit shader, _BaseColor, _BaseMap, dissolve, outline, fresnel, hologram, triplanar, vertex wave, SRP Batcher, shader keyword, shader variant)'
---

## When to use

Fires when the user creates or edits a Material, picks a shader, asks "why is this pink", authors normal maps, sets transparent/cutout/opaque blend modes, requests a custom shader or Shader Graph effect, tunes render queue, enables GPU instancing or static/dynamic batching, uses MaterialPropertyBlock, or debugs shader compile errors.

For URP pipeline asset, renderer features, and post-processing volume setup, defer to the `unity-urp` skill. This skill stops at the material/shader boundary.

## URP shader catalog

This skill set targets URP. Pick the URP shader that matches the surface; anything from outside this list (Built-in `Standard`, legacy `Particles/...`, HDRP shaders) renders pink in a URP project.

| Surface | Shader |
|---|---|
| Lit (PBR) | `Universal Render Pipeline/Lit` |
| Unlit | `Universal Render Pipeline/Unlit` |
| Lit, mobile-cheap (Blinn-Phong) | `Universal Render Pipeline/Simple Lit` |
| Particles, lit | `Universal Render Pipeline/Particles/Lit` |
| Particles, unlit | `Universal Render Pipeline/Particles/Unlit` |
| Sprites (2D Renderer, lit) | `Universal Render Pipeline/2D/Sprite-Lit-Default` |
| Decals | `Universal Render Pipeline/Decal` |
| Custom (any of the above) | Shader Graph with the URP target (Lit / Unlit / Sprite Lit / Sprite Unlit / Decal / Fullscreen subtargets) |

Shader Graph is the recommended authoring path — one asset, URP target, full property and keyword control. Drop to hand-written HLSL only when Shader Graph cannot express what you need (see Authoring choice section).

**Built-in to URP material conversion.** Importing legacy asset packages, free-store packs, or older project content typically pulls in materials referencing Built-in shaders (`Standard`, `Standard (Specular setup)`, `Unlit/Texture`, `Particles/Standard Unlit`, etc.). They render pink in URP. Convert with the menu command:

- `Edit > Rendering > Materials > Convert Selected Built-in Materials to URP`
- or `Edit > Rendering > Materials > Convert All Built-in Materials to URP`

Run after importing legacy assets or any time a fresh `Standard`/legacy material appears in the project. Custom hand-written Built-in shaders need to be rewritten by hand — the converter only remaps stock shaders.

## Authoring choice (ShaderGraph vs HLSL)

Default to Shader Graph. Drop to HLSL only when you hit a wall.

| | Shader Graph | Hand-written HLSL ShaderLab |
|---|---|---|
| Iteration | fast, live preview | slow, recompile per save |
| Multi-pass | one extra pass via Sub Target | unlimited |
| Custom lighting | limited | full |
| Stencil, geometry, tessellation | no | yes |
| Compute shaders | no (separate `.compute` file) | yes |
| Designer-friendly | yes | no |

Reuse logic with `Convert to Sub Graph` (right-click selected nodes). For a one-off chunk of HLSL inside a graph, drop a **Custom Function** node pointing at an `.hlsl` file or inline string.

## Materials and properties

A Material is a Shader plus a value table plus keyword toggles. Edit values with `manage_material`.

**Shared vs instance.** `Renderer.material` clones the asset on first access, allocating a new material per renderer and breaking SRP Batcher / static batching. `Renderer.sharedMaterial` reads and writes the asset itself. For per-object tweaks without cloning, use a `MaterialPropertyBlock`.

**URP vs Built-in property names.** The converter remaps these; manual code must use the right names.

| Built-in | URP / Shader Graph (Lit) |
|---|---|
| `_Color` | `_BaseColor` |
| `_MainTex` | `_BaseMap` |
| `_BumpMap` | `_BumpMap` (same) |
| `_BumpScale` | `_BumpScale` |
| `_Metallic` | `_Metallic` |
| `_Glossiness` | `_Smoothness` |
| `_EmissionColor` | `_EmissionColor` |
| `_Cutoff` | `_Cutoff` |

Always cache property IDs at runtime: `static readonly int BaseColor = Shader.PropertyToID("_BaseColor");`. String lookups every frame are wasted CPU.

## Shader Graph workflow

1. Create: `Project > Create > Shader Graph > URP > Lit Shader Graph` (or Unlit, Sprite Lit, etc — pick the URP subtarget that matches the surface).
2. Open: double-click the asset. The Master Stack on the right is the output; the Blackboard on the left holds properties.
3. Add a property: click `+` on the Blackboard, pick a type, set the **Reference** name to match what scripts expect (`_BaseColor` etc). Without an explicit Reference, Shader Graph generates a GUID-suffixed name and `Shader.PropertyToID` will fail at runtime.
4. Save: `Save Asset` button top-left, or Cmd/Ctrl-S inside the editor. Out-of-band file edits to the `.shadergraph` need `manage_asset` to refresh.
5. Vertex stage: connect to the **Position**, **Normal**, or **Tangent** ports on the Vertex block of the Master Stack for wave/foliage effects.

Common nodes: Sample Texture 2D, Tiling and Offset, UV, Time, Gradient Noise, Voronoi, Step, Smoothstep, Fresnel Effect, Normal From Texture, Lerp, Remap, Split, Combine.

For full effect recipes (outline, dissolve, hologram, triplanar, vertex wave, water) see the **Common patterns** section below.

## Hand-written HLSL skeleton

Minimal URP unlit shader. Pin includes to your installed URP package version (paths are stable across recent LTS but not guaranteed).

```hlsl
Shader "Custom/MyUnlit"
{
    Properties
    {
        _BaseMap   ("Base Map", 2D)    = "white" {}
        _BaseColor ("Base Color", Color) = (1,1,1,1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        LOD 100

        Pass
        {
            Name "ForwardUnlit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
            CBUFFER_END

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct A { float4 positionOS:POSITION; float2 uv:TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct V { float4 positionHCS:SV_POSITION; float2 uv:TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };

            V vert (A IN) {
                V OUT; UNITY_SETUP_INSTANCE_ID(IN); UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag (V IN) : SV_Target {
                UNITY_SETUP_INSTANCE_ID(IN);
                half4 c = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                return c * _BaseColor;
            }
            ENDHLSL
        }
    }
}
```

The `CBUFFER_START(UnityPerMaterial)` block is what makes the shader SRP Batcher compatible. Skip it and you lose the batcher silently. Frame Debugger flags incompatibility.

## MaterialPropertyBlock

Per-instance values without cloning the material. **MPB is NOT compatible with the SRP Batcher** — setting an MPB on a renderer drops that draw out of the SRP Batcher, and the Frame Debugger annotates such draws with reasons like `Node has different shader keywords` or `per-material data overridden`. MPB is compatible with GPU instancing (and required for `Graphics.DrawMeshInstanced` / `Graphics.RenderMeshInstanced`).

If you need per-instance variation while keeping SRP Batcher: use a `_BaseColor`-style property array on a single shared material, indexed by `unity_InstanceID` with GPU instancing — not MPB.

**Cache the block.** Allocating `new MaterialPropertyBlock()` per call costs ~80 B GC. Cache one shared instance and `Clear()` before each use:

```csharp
static readonly int BaseColorID = Shader.PropertyToID("_BaseColor");
static readonly MaterialPropertyBlock s_mpb = new();

void TintRed(Renderer r) {
    s_mpb.Clear();
    r.GetPropertyBlock(s_mpb);          // start from current overrides
    s_mpb.SetColor(BaseColorID, Color.red);
    r.SetPropertyBlock(s_mpb);
}
```

Pitfalls: `SetPropertyBlock(null)` clears all overrides; the block is cached on the renderer, so the `GetPropertyBlock` -> mutate -> `SetPropertyBlock` round-trip is the safe pattern; MPBs break dynamic batching and the SRP Batcher.

## Keywords and variants

Keywords toggle code paths: `_NORMALMAP`, `_METALLICSPECGLOSSMAP`, `_EMISSION`, `_ALPHATEST_ON`. Set at runtime with `Material.EnableKeyword("_NORMALMAP")` or via `manage_material` keyword toggles.

**Variant explosion.** Each `multi_compile` keyword doubles the variant count. A Lit shader with 12 keywords ships 4096 variants. Mitigations:

- Prefer `shader_feature` over `multi_compile` — only variants used by some material in the project are kept.
- Use **local keywords** (`shader_feature_local`, `multi_compile_local`) so each shader has its own keyword space; Shader Graph defaults to local.
- Strip aggressively in `IPreprocessShaders` for keywords that are demonstrably unused.

**Build-time stripping pitfall.** A `shader_feature` variant survives the build only if some material had the keyword enabled at build time. Runtime `EnableKeyword` for a variant that nothing used at build time silently falls back to a working but wrong variant. Fix: maintain a sentinel material in `Resources/` with the runtime-needed keywords toggled on, so the build keeps the variant.

## Shader variant stripping and warmup

**Build-time stripping with `IPreprocessShaders`.** Implement the interface in an `Editor/` script to drop variant combinations that no material in the project uses. Strip aggressively: every removed variant cuts shader binary size and player startup compile cost.

```csharp
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Rendering;
using UnityEngine.Rendering;
using System.Collections.Generic;

class StripUnusedVariants : IPreprocessShaders {
    public int callbackOrder => 0;
    static readonly ShaderKeyword s_unused = new ShaderKeyword("_DEPRECATED_FEATURE");

    public void OnProcessShader(Shader shader, ShaderSnippetData snippet, IList<ShaderCompilerData> data) {
        for (int i = data.Count - 1; i >= 0; i--) {
            if (data[i].shaderKeywordSet.IsEnabled(s_unused)) data.RemoveAt(i);
        }
    }
}
```

Cross-link `unity-build` for where this slots into the pipeline and `unity-profiling` (Frame Debugger) for counting variants actually used in a frame.

**Runtime warmup with `ShaderVariantCollection`.** Generate the collection in the editor (Project Settings -> Graphics, log shader variants while playing then `Save to asset`), include it in the build, and call `WarmUp()` during a loading scene before gameplay starts. This is essential on iOS Metal — without warmup, the first time each variant is rendered Metal compiles the pipeline state object on the GPU thread and stalls the frame for 100-300 ms (visible as first-encounter stutter the first time each enemy type, particle effect, or post-process volume appears).

```csharp
[SerializeField] ShaderVariantCollection warmupSet;

IEnumerator WarmUpAllShaders() {
    warmupSet.WarmUp();           // synchronous, runs while loading screen is visible
    yield return null;
}
```

**Mobile budget.** Aim for <500 variants per shader and total compiled shader binary <20 MB. Each `multi_compile` pragma doubles variant count; `shader_feature` only ships the combinations referenced by some material. Inspect `Library/ShaderCache/` after a build to gauge the binary size.

## Common patterns

- **Outline (rim).** Fresnel Effect node, multiply by emissive color, add to Master Stack Emission. 30 seconds in Shader Graph.
- **Dissolve.** Sample noise (Gradient Noise or texture) to a float, Step against a `_DissolveAmount` property, feed Step output to Alpha and the inverted edge band to Emission.
- **Hologram.** Fresnel + scrolling scanlines (`UV.y + Time * speed`, fed through Fraction and Step). Surface = Transparent, Blend = Alpha.
- **Triplanar.** Sample three planar projections (XY/YZ/XZ) of world position, blend by absolute world normal raised to a sharpness power. Use the built-in Triplanar node.
- **Vertex wave (foliage, water).** In the vertex stage, add `sin(Time + worldPos.x * freq) * amplitude` to Position.y. Mask by vertex color or UV2 so root vertices stay still.
- **Water.** Scene Depth node minus screen-space depth, drive shore foam mask via Step. Add scrolling normal map for ripples and Fresnel for edge brightening.

## Debugging pink / errors

- **Pink material.** The shader is missing or failed to compile. Check `read_console` for compile errors first. If it is "Shader 'X' not found", run the URP converter or assign a URP shader from the catalog above.
- **Wrong-pipeline shader.** Built-in `Standard` (or any legacy / HDRP shader pulled in by an imported package) on a URP project. Run `Edit > Rendering > Materials > Convert ... to URP`.
- **Compile error.** `read_console` shows the line and pass. Common causes: missing `#include`, undefined keyword sampler, mismatched CBUFFER, Shader Model too low for a node (raise with `#pragma target 4.5`).
- **Silent fallback.** Runtime keyword combination not in the build. Open Frame Debugger (`Window > Analysis > Frame Debugger`) and inspect the actual variant used.
- **Washed-out colors.** sRGB flag wrong on the texture. Albedo/color = sRGB on. Mask, normal, roughness, data textures = sRGB off. Toggle via `manage_texture`.
- **Blue/wrong normals.** Texture not flagged as Normal Map at import. Toggle `Texture Type = Normal Map` via `manage_texture`. URP also needs `_NORMALMAP` keyword enabled on the material.
- **Z-sort wrong.** Render queue mismatch. Opaque = 2000, AlphaTest = 2450, Transparent = 3000. Set via `manage_material` `renderQueue` or via Shader Graph `Surface = Opaque/Transparent`.
- **Transparent object disappears.** No depth write but writing to depth-required pass, or queue too low. Check Surface = Transparent and Alpha Clipping for cutout.

## Performance

- **Static batching.** Same material across renderers. MaterialPropertyBlock does not break it; cloning via `Renderer.material` does.
- **Dynamic batching.** Limited to small meshes, breaks on lightmap UVs and MPBs. Mostly superseded.
- **SRP Batcher (URP).** Replaces dynamic batching. Requires shaders to declare a `CBUFFER_START(UnityPerMaterial)` block with all per-material properties. Shader Graph and stock URP/Lit are compatible by default. Frame Debugger labels each draw call as compatible or not, with the reason. **MaterialPropertyBlock breaks the SRP Batcher** — any renderer with an MPB drops out of the batcher and renders as its own draw. For SRP-Batcher-compatible per-instance variation, declare an array property like `_BaseColor` indexed by `unity_InstanceID` and drive it through GPU instancing.
- **GPU instancing.** Per-instance variation without breaking batching. Add `#pragma multi_compile_instancing` to the shader, check `Enable GPU Instancing` on the material, drive per-instance values via MPB. Mutually exclusive with SRP Batcher per draw call — Unity picks the cheaper path.
- **Texture sampling.** Use compressed formats (BC7 for color/normal on desktop, ASTC on mobile). Enable mipmaps for anything not pixel-art UI; without them you get aliasing and worse cache behavior.
- **Branching.** Modern GPUs handle dynamic branches fine if all threads in a warp take the same path. Use `[branch]` for divergent conditions, `[flatten]` for tight ones. Avoid loops with non-constant bounds — they unroll badly or not at all.

## Verification

After any visible material change on a 3D object, hand off to the `unity-3d-verification` skill (4-shot orthographic) to confirm the surface looks right from all angles. Specifically check:

- pink material on any face (shader missing or pipeline mismatch)
- normal map artifacts (low-frequency lighting wrong on one axis = normals authored in wrong space, or `_NORMALMAP` keyword off)
- render queue sorting (transparent appearing behind opaque, foliage clipping foreground)
- GPU instancing: per-instance tints actually appearing (if every instance looks the same color, MPB or `multi_compile_instancing` is missing)
- emission/HDR clipping (bloom-driven effects clamping to white)

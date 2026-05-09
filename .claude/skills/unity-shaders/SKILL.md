---
name: unity-shaders
description: 'Use for Unity 6+ URP shaders/materials: Shader Graph, HLSL/ShaderLab, pink materials, normal maps, render queues, transparency/cutout, MaterialPropertyBlock, instancing, SRP Batcher, keywords, variants, dissolve/outline/fresnel/triplanar effects.'
---

## When to use

Use for materials, Shader Graph/HLSL, pink shaders, blend modes, queues, instancing/batching, MPBs, and compile errors. URP asset/renderer/post-processing work belongs in `unity-urp`.

## URP shader catalog

URP only. Built-in `Standard`, legacy `Particles/...`, and HDRP shaders render pink.

| Surface | Shader |
|---|---|
| Lit (PBR) | `Universal Render Pipeline/Lit` |
| Unlit | `Universal Render Pipeline/Unlit` |
| Lit, mobile-cheap (Blinn-Phong) | `Universal Render Pipeline/Simple Lit` |
| Particles, lit | `Universal Render Pipeline/Particles/Lit` |
| Particles, unlit | `Universal Render Pipeline/Particles/Unlit` |
| Sprites (2D Renderer, lit) | `Universal Render Pipeline/2D/Sprite-Lit-Default` |
| Decals | `Universal Render Pipeline/Decal` |
| Custom | Shader Graph with URP target (Lit / Unlit / Sprite Lit / Sprite Unlit / Decal / Fullscreen) |

Prefer Shader Graph; drop to HLSL for custom lighting, special passes, or unsupported graph features.

**Built-in -> URP material conversion.** Asset Store packages often import Built-in materials:

- `Edit > Rendering > Materials > Convert Selected Built-in Materials to URP`
- `Edit > Rendering > Materials > Convert All Built-in Materials to URP`

Converter remaps stock shaders only; custom Built-in shaders need rewrites.

## Authoring choice (ShaderGraph vs HLSL)

| | Shader Graph | HLSL ShaderLab |
|---|---|---|
| Iteration | fast, live preview | slow, recompile per save |
| Multi-pass | one extra pass via Sub Target | unlimited |
| Custom lighting | limited | full |
| Stencil, geometry, tessellation | no | yes |
| Compute shaders | no (separate `.compute`) | yes |
| Designer-friendly | yes | no |

Reuse with `Convert to Sub Graph` (right-click selected nodes). For inline HLSL, use a **Custom Function** node pointing at an `.hlsl` file or inline string.

## Materials and properties

Material = shader + values + keyword toggles.

**Shared vs instance.** `Renderer.material` clones; use `sharedMaterial` for asset edits and `MaterialPropertyBlock` for per-renderer values.

Manual code must use URP property names:

| Built-in | URP / Shader Graph (Lit) |
|---|---|
| `_Color` | `_BaseColor` |
| `_MainTex` | `_BaseMap` |
| `_BumpMap` | `_BumpMap` |
| `_BumpScale` | `_BumpScale` |
| `_Metallic` | `_Metallic` |
| `_Glossiness` | `_Smoothness` |
| `_EmissionColor` | `_EmissionColor` |
| `_Cutoff` | `_Cutoff` |

Cache property IDs: `static readonly int BaseColor = Shader.PropertyToID("_BaseColor");`.

## Shader Graph workflow

1. `Project > Create > Shader Graph > URP > Lit Shader Graph` (or Unlit, Sprite Lit, etc.).
2. Double-click to open. Master Stack (right) is output; Blackboard (left) holds properties.
3. `+` on Blackboard; set **Reference** name to match scripts (`_BaseColor` etc.). Without explicit Reference, Shader Graph generates a GUID-suffixed name and `Shader.PropertyToID` fails at runtime.
4. Save Asset button or Cmd/Ctrl-S. Out-of-band `.shadergraph` edits need an asset refresh.
5. Vertex stage: connect to Position/Normal/Tangent on Master Stack Vertex for wave/foliage.

Useful nodes: Sample Texture 2D, Tiling and Offset, UV, Time, Gradient Noise, Voronoi, Step/Smoothstep, Fresnel, Normal From Texture, Lerp, Remap.

## Hand-written HLSL skeleton

Minimal URP unlit; pin includes to installed URP version.

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

`CBUFFER_START(UnityPerMaterial)` is required for SRP Batcher compatibility; Frame Debugger explains misses.

## MaterialPropertyBlock

Per-instance values without material clones. MPB breaks SRP Batcher for that renderer, but works with GPU instancing and `DrawMeshInstanced` / `RenderMeshInstanced`.

To keep SRP Batcher, use a shared material plus an instanced array indexed by `unity_InstanceID`, not MPB.

Cache + `Clear()` the block; constructing per call allocates.

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

Pitfalls: `SetPropertyBlock(null)` clears overrides; safe pattern is `GetPropertyBlock -> mutate -> SetPropertyBlock`.

## Keywords and variants

Keywords toggle code paths (`_NORMALMAP`, `_EMISSION`, `_ALPHATEST_ON`). Set on the material asset or via `EnableKeyword`.

Each `multi_compile` doubles variants. Mitigate:

- Prefer `shader_feature` over `multi_compile` — only variants used by some material in the project are kept.
- **Local keywords** (`shader_feature_local`, `multi_compile_local`) — each shader has its own keyword space; Shader Graph defaults to local.
- Strip aggressively in `IPreprocessShaders`.

Runtime `EnableKeyword` needs a build-kept variant. Keep sentinel materials in `Resources/` for runtime-only combos.

## Variant stripping and warmup

**Build-time stripping (`IPreprocessShaders`).** Remove unused combos to cut binary size and startup compile cost.

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

See `unity-build`, `unity-profiling`.

**Runtime warmup (`ShaderVariantCollection`).** Log variants in editor, save collection, include in build, call `WarmUp()` in a loading scene. Important on iOS Metal to avoid first-use stalls.

```csharp
[SerializeField] ShaderVariantCollection warmupSet;

IEnumerator WarmUpAllShaders() {
    warmupSet.WarmUp();           // synchronous
    yield return null;
}
```

Mobile budget: target <500 variants/shader and total shader binary <20 MB. Inspect `Library/ShaderCache/` after build.

## Common patterns

- **Outline (rim).** Fresnel Effect node × emissive color → Master Stack Emission. 30 seconds in Shader Graph.
- **Dissolve.** Sample noise → Step against `_DissolveAmount`, feed Step output to Alpha and inverted edge band to Emission.
- **Hologram.** Fresnel + scrolling scanlines (`UV.y + Time * speed` through Fraction and Step). Surface = Transparent, Blend = Alpha.
- **Triplanar.** Three planar projections (XY/YZ/XZ) of world position blended by absolute world normal raised to a sharpness power. Built-in Triplanar node.
- **Vertex wave (foliage, water).** Vertex stage: add `sin(Time + worldPos.x * freq) * amplitude` to Position.y. Mask by vertex color or UV2 so root vertices stay still.
- **Water.** Scene Depth − screen-space depth → Step for shore foam. Scrolling normal map for ripples + Fresnel for edge brightening.

## Debugging pink / errors

- **Pink material** — shader missing or failed compile. Check Editor console first. If "Shader 'X' not found", run URP converter or assign a URP shader.
- **Wrong-pipeline shader** — Built-in `Standard` (or HDRP) on URP. Run `Edit > Rendering > Materials > Convert ... to URP`.
- **Compile error** — console shows line/pass. Common: missing `#include`, undefined sampler, mismatched CBUFFER, Shader Model too low.
- **Silent fallback** — runtime keyword combo not in build. Open Frame Debugger (`Window > Analysis > Frame Debugger`) and inspect the actual variant.
- **Washed-out colors** — sRGB flag wrong on texture. Albedo/color = sRGB on. Mask, normal, roughness, data textures = sRGB off.
- **Blue/wrong normals** — texture not flagged as Normal Map at import. Set `Texture Type = Normal Map`. URP also needs `_NORMALMAP` keyword on the material.
- **Z-sort wrong** — render queue mismatch. Opaque = 2000, AlphaTest = 2450, Transparent = 3000. Set `renderQueue` directly or via Shader Graph `Surface = Opaque/Transparent`.
- **Transparent disappears** — no depth write but writing to depth-required pass, or queue too low. Surface = Transparent, Alpha Clipping for cutout.

## Performance

- **Static batching.** Needs shared materials; `Renderer.material` clones break it.
- **Dynamic batching.** Limited to small meshes, breaks on lightmap UVs and MPBs. Mostly superseded.
- **SRP Batcher.** Needs `UnityPerMaterial` CBUFFER; MPB drops that renderer out.
- **GPU instancing.** Needs `#pragma multi_compile_instancing` + material checkbox; Unity chooses instancing or SRP Batcher per draw.
- **Texture sampling.** BC7 desktop, ASTC mobile; mipmaps on for non-pixel-art.
- **Branching.** OK when coherent; avoid non-constant loops.

## Verification

After visible material change on a 3D object → `unity-3d-verification` (4-shot orthographic). Check:

- Pink on any face (shader missing or pipeline mismatch).
- Normal map artifacts (low-frequency lighting wrong on one axis = wrong-space normals or `_NORMALMAP` off).
- Render queue sorting (transparent behind opaque, foliage clipping foreground).
- GPU instancing: per-instance tints actually appearing (every instance same color = MPB or `multi_compile_instancing` missing).
- Emission/HDR clipping (bloom-driven effects clamping to white).

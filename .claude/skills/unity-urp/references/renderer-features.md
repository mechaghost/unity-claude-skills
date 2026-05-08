# URP renderer features reference

Renderer features extend a Universal Renderer asset with extra render passes. Add them in the renderer asset inspector (`Add Renderer Feature`). Each feature is a `ScriptableRendererFeature` that injects one or more `ScriptableRenderPass` instances into the frame at a chosen event.

Edit renderer assets via `manage_asset`. Author custom feature/pass C# via `create_script` and `apply_text_edits`. Inspect actual frame ordering with `manage_profiler` Frame Debugger.

## Built-in features

### Screen Space Ambient Occlusion (SSAO)
Darkens crevices using scene depth (and optionally normals). Settings: Source (Depth / Depth+Normals), Intensity, Radius, Sample Count, Falloff.
- Depth+Normals is higher quality, requires `_CameraNormalsTexture` (extra pass).
- Off on mobile by default. Profile before shipping — typically the most expensive renderer feature.

### Decal Renderer Feature
Projection decals. Two techniques:
- **DBuffer** — writes into a buffer before opaque shading; lit correctly. Requires depth-and-normal prepass; not available on all platforms.
- **Screen Space** — projects after opaque pass; cheaper, less correct lighting on normal-mapped surfaces.
Surface Data toggles (Albedo / Normal / MAOS) control which channels decals can write.

### Screen Space Shadows
Forward path, directional light only. Replaces per-object shadow sampling with a screen-space pass. Largely superseded by Forward+; still useful for some legacy projects.

### Render Objects
The workhorse feature for custom passes without writing C#.
- **Filters.** Layer Mask, Render Queue (Opaque / Transparent), LightMode tags.
- **Override Material** — render the filtered objects with a different shader (outline pass, X-ray pass, depth-only).
- **Event** — `BeforeRenderingPrePasses`, `AfterRenderingPrePasses`, `BeforeRenderingOpaques`, `AfterRenderingOpaques`, `BeforeRenderingSkybox`, `AfterRenderingSkybox`, `BeforeRenderingTransparents`, `AfterRenderingTransparents`, `BeforeRenderingPostProcessing`, `AfterRenderingPostProcessing`.
- **Depth/Stencil overrides** — write/test for masking effects.

### Full Screen Pass Renderer Feature
Apply a Shader Graph "Fullscreen" shader as a post-process at a chosen event. Use cases: custom screen-space effects (rain, heat distortion, scan-lines) without writing C#.

## Writing a custom ScriptableRendererFeature

Unity 6 ships URP 17, which **defaults to the RenderGraph backend**. New custom passes MUST implement `RecordRenderGraph(RenderGraph, ContextContainer)` — the older `Execute(ScriptableRenderContext, ref RenderingData)` is deprecated under RenderGraph and is only invoked when the project explicitly opts into the "Compatibility Mode (Non-Render Graph)" toggle on the URP asset (or runs URP 14/15 on Unity 2022 LTS).

### Recommended path: RenderGraph (URP 17 / Unity 6+)

Skeleton, dropped into a C# file via `create_script`:

```csharp
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class MyOutlineFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Material outlineMaterial;
        public LayerMask layerMask = ~0;
    }

    public Settings settings = new Settings();
    private MyOutlinePass pass;

    public override void Create()
    {
        pass = new MyOutlinePass(settings);
        pass.renderPassEvent = settings.renderPassEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.outlineMaterial == null) return;
        renderer.EnqueuePass(pass);
    }
}

public class MyOutlinePass : ScriptableRenderPass
{
    private readonly MyOutlineFeature.Settings settings;
    private FilteringSettings filtering;
    private readonly ShaderTagId shaderTag = new ShaderTagId("UniversalForward");

    private class PassData
    {
        public RendererListHandle rendererList;
    }

    public MyOutlinePass(MyOutlineFeature.Settings s)
    {
        settings = s;
        filtering = new FilteringSettings(RenderQueueRange.opaque, settings.layerMask);
    }

    public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
    {
        var resourceData = frameData.Get<UniversalResourceData>();
        var renderingData = frameData.Get<UniversalRenderingData>();
        var cameraData = frameData.Get<UniversalCameraData>();
        var lightData = frameData.Get<UniversalLightData>();

        using var builder = renderGraph.AddRasterRenderPass<PassData>("MyOutlinePass", out var passData);

        var sortFlags = cameraData.defaultOpaqueSortFlags;
        var drawingSettings = RenderingUtils.CreateDrawingSettings(
            shaderTag, renderingData, cameraData, lightData, sortFlags);
        drawingSettings.overrideMaterial = settings.outlineMaterial;

        var rendererListParams = new RendererListParams(
            renderingData.cullResults, drawingSettings, filtering);
        passData.rendererList = renderGraph.CreateRendererList(rendererListParams);
        builder.UseRendererList(passData.rendererList);

        builder.SetRenderAttachment(resourceData.activeColorTexture, 0);
        builder.SetRenderAttachmentDepth(resourceData.activeDepthTexture);

        builder.SetRenderFunc((PassData data, RasterGraphContext ctx) =>
        {
            ctx.cmd.DrawRendererList(data.rendererList);
        });
    }
}
```

Key points:

- `RecordRenderGraph` registers reads/writes against textures owned by the graph (`UniversalResourceData.activeColorTexture` etc.) — the graph compiler decides actual GPU work. Do not call `context.ExecuteCommandBuffer` directly.
- `PassData` is a per-pass POCO captured by the render-func lambda; the graph allocates and pools it.
- `builder.UseRendererList` and `builder.SetRenderAttachment` declare data flow; without these the pass is culled or the resources are not in the right state when your render-func runs.

After saving, add the feature to the renderer asset (inspector → Add Renderer Feature → MyOutlineFeature) via `manage_asset`. The renderer asset `.asset` file gains a serialized reference — commit it.

### Compatibility / legacy non-RenderGraph path (URP 14/15, Unity 2022 LTS)

Only use this when the project is on Unity 2022 LTS, or has explicitly enabled "Compatibility Mode (Non-Render Graph)" on the URP asset for legacy reasons. New Unity 6 projects should not write `Execute`-based passes.

```csharp
public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
{
    var cmd = CommandBufferPool.Get("MyOutlinePass");
    var drawing = CreateDrawingSettings(shaderTag, ref renderingData, SortingCriteria.CommonOpaque);
    drawing.overrideMaterial = settings.outlineMaterial;
    context.ExecuteCommandBuffer(cmd);
    cmd.Clear();
    context.DrawRenderers(renderingData.cullResults, ref drawing, ref filtering);
    CommandBufferPool.Release(cmd);
}
```

Check `unity_docs` for the exact API signatures on the URP version installed.

## Render pass events — ordering cheatsheet

In frame execution order:

1. `BeforeRendering`
2. `BeforeRenderingShadows` / `AfterRenderingShadows`
3. `BeforeRenderingPrePasses` / `AfterRenderingPrePasses` — depth, normals
4. `BeforeRenderingGbuffer` / `AfterRenderingGbuffer` — deferred only
5. `BeforeRenderingOpaques` / `AfterRenderingOpaques`
6. `BeforeRenderingSkybox` / `AfterRenderingSkybox`
7. `BeforeRenderingTransparents` / `AfterRenderingTransparents`
8. `BeforeRenderingPostProcessing` / `AfterRenderingPostProcessing`
9. `AfterRendering`

Pick the event by what data must already exist when the pass runs (e.g. an outline that samples depth runs after opaques; a fog effect runs before transparents so transparents fog correctly).

## Common custom-feature patterns

- **Outline / silhouette.** Render Objects feature filtering by Rendering Layer with an outline-shader override material, event = `AfterRenderingTransparents`. Or two-pass: first pass writes stencil, second pass renders edges where stencil set.
- **X-ray through walls.** Render Objects on a "X-Ray" layer with a depth-test-disabled material at `AfterRenderingOpaques`.
- **Selection highlight.** Same as outline, but feature is enabled only while a selection exists; toggle via `feature.SetActive(bool)` at runtime.
- **Custom fog / atmospherics.** Full Screen Pass with a Shader Graph fullscreen shader sampling `_CameraDepthTexture`, event `BeforeRenderingTransparents`.
- **Pixelation / retro filter.** Full Screen Pass at `AfterRenderingPostProcessing` with a downsample/upsample shader.

## Gotchas

- Custom features need `Depth Texture` enabled on the pipeline asset if they sample `_CameraDepthTexture`. Same for `Opaque Texture` and `_CameraOpaqueTexture`.
- Renderer asset edits are project files — review carefully on PRs.
- A feature added to the default renderer affects every camera using that renderer. Use a separate renderer asset for cameras that should opt out (minimap, render-to-texture preview).
- Forward+ tile binning runs before `BeforeRenderingOpaques`; features at earlier events don't get accurate light data.
- Deferred path's GBuffer is only valid between `AfterRenderingGbuffer` and `AfterRenderingOpaques`; sampling it outside that window reads stale data.
- `RenderPassEvent` ties are broken by feature order in the renderer asset list — drag to reorder for deterministic stacking.

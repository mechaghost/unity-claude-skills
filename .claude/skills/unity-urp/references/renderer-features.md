# URP renderer features reference

Renderer features extend a Universal Renderer asset with extra passes. Add via renderer asset inspector. Each feature is a `ScriptableRendererFeature` injecting one+ `ScriptableRenderPass` at a chosen event.

## Built-in features

### Screen Space Ambient Occlusion (SSAO)
Darkens crevices using scene depth (optionally normals). Settings: Source (Depth / Depth+Normals), Intensity, Radius, Sample Count, Falloff.
- Depth+Normals is higher quality, needs `_CameraNormalsTexture` (extra pass).
- Off on mobile by default. Typically the most expensive feature — profile before shipping.

### Decal Renderer Feature
Projection decals.
- **DBuffer** — writes into a buffer before opaque shading; lit correctly. Needs depth+normal prepass; not all platforms.
- **Screen Space** — projects after opaque pass; cheaper, less correct on normal-mapped surfaces.

Surface Data toggles (Albedo / Normal / MAOS) control which channels decals write.

### Screen Space Shadows
Forward path, directional only. Replaces per-object shadow sampling with a screen-space pass. Largely superseded by Forward+.

### Render Objects
Workhorse for custom passes without C#.
- **Filters** — Layer Mask, Render Queue (Opaque/Transparent), LightMode tags.
- **Override Material** — render filtered objects with a different shader (outline, X-ray, depth-only).
- **Event** — `BeforeRendering[PrePasses|Opaques|Skybox|Transparents|PostProcessing]`, `AfterRendering[...]`.
- **Depth/Stencil overrides** — write/test for masking.

### Full Screen Pass Renderer Feature
Apply a Shader Graph "Fullscreen" shader as a PP at a chosen event. Rain, heat distortion, scan-lines without C#.

## Writing a custom ScriptableRendererFeature

Unity 6 ships URP 17, which **defaults to RenderGraph backend**. New custom passes MUST implement `RecordRenderGraph(RenderGraph, ContextContainer)`; the older `Execute(ScriptableRenderContext, ref RenderingData)` is deprecated and only invoked under "Compatibility Mode (Non-Render Graph)" on the URP asset. Do not enable that toggle in new Unity 6 projects.

### RenderGraph path (URP 17 / Unity 6 — only supported path)

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
- `RecordRenderGraph` registers reads/writes against graph-owned textures (`UniversalResourceData.activeColorTexture` etc.); the graph compiler decides actual GPU work. Don't call `context.ExecuteCommandBuffer` directly.
- `PassData` is a per-pass POCO captured by the render-func lambda; the graph allocates and pools.
- `builder.UseRendererList` and `builder.SetRenderAttachment` declare data flow; without them the pass is culled or resources aren't in the right state.

After saving, add the feature to the renderer asset (inspector → Add Renderer Feature). The `.asset` gains a serialized reference — commit it.

### Out of scope: legacy `Execute`-based passes

The pre-RenderGraph `Execute(ScriptableRenderContext, ref RenderingData)` runs only with "Compatibility Mode (Non-Render Graph)" enabled. Not supported here — disable and port to `RecordRenderGraph`.

## Render pass events — ordering cheatsheet

Frame execution order:

1. `BeforeRendering`
2. `BeforeRenderingShadows` / `AfterRenderingShadows`
3. `BeforeRenderingPrePasses` / `AfterRenderingPrePasses` — depth, normals
4. `BeforeRenderingGbuffer` / `AfterRenderingGbuffer` — deferred only
5. `BeforeRenderingOpaques` / `AfterRenderingOpaques`
6. `BeforeRenderingSkybox` / `AfterRenderingSkybox`
7. `BeforeRenderingTransparents` / `AfterRenderingTransparents`
8. `BeforeRenderingPostProcessing` / `AfterRenderingPostProcessing`
9. `AfterRendering`

Pick the event by what data must already exist (outline that samples depth runs after opaques; fog runs before transparents so transparents fog correctly).

## Common custom-feature patterns

- **Outline / silhouette.** Render Objects feature filtering by Rendering Layer with outline-shader override material, event = `AfterRenderingTransparents`. Or two-pass: first writes stencil, second renders edges where set.
- **X-ray through walls.** Render Objects on an "X-Ray" layer with depth-test-disabled material at `AfterRenderingOpaques`.
- **Selection highlight.** Same as outline; toggle via `feature.SetActive(bool)` at runtime.
- **Custom fog / atmospherics.** Full Screen Pass with a Shader Graph fullscreen shader sampling `_CameraDepthTexture`, event `BeforeRenderingTransparents`.
- **Pixelation / retro filter.** Full Screen Pass at `AfterRenderingPostProcessing` with downsample/upsample shader.

## Gotchas

- Custom features need `Depth Texture` enabled on the pipeline asset if they sample `_CameraDepthTexture`. Same for `Opaque Texture` / `_CameraOpaqueTexture`.
- Renderer asset edits are project files — review carefully on PRs.
- A feature added to the default renderer affects every camera using it. Use a separate renderer asset for opt-out cameras (minimap, RT preview).
- Forward+ tile binning runs before `BeforeRenderingOpaques`; earlier events don't get accurate light data.
- Deferred GBuffer is only valid between `AfterRenderingGbuffer` and `AfterRenderingOpaques`; sampling outside reads stale data.
- `RenderPassEvent` ties broken by feature order in the renderer asset list — drag to reorder for deterministic stacking.

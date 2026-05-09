---
name: unity-vfx-graph
description: 'Use when authoring or tuning Unity Visual Effect Graph through Unity MCP — high-particle-count effects, GPU-driven simulation, magic projectiles, energy fields, environmental swarms (snow, leaves, sparks at scale), data-driven VFX with SDFs / vector fields. Triggers — VFX Graph, Visual Effect Graph, Visual Effect component, GPU particles, com.unity.visualeffectgraph, .vfx, exposed property, particle system GPU, VFX context, Spawn context, Initialize context, Update context, Output context, Quad output, Mesh output, Lit output, Unlit output, attribute, sample texture, sample mesh, sample SDF, signed distance field, vector field, point cache, .vfxoperator, vfx event, large particle counts, hundreds of thousands of particles, magic effect, fire fountain, energy beam, snow storm, dissolve effect. Unity 6+ / URP-only / new Input System only. NOT for low-count gameplay particles — use unity-shuriken.'
---

## When to use

GPU-driven, large-count, or data-sampled effects: magic projectiles, energy fields, fire fountains, dissolves, snow storms, swarming environmental fx, anything that samples a Texture/Mesh/SDF/Vector Field/Point Cache for per-particle data. Skip for low-count gameplay particles (hit sparks, dust puffs, footsteps) and anything that needs `OnParticleCollision`/`OnParticleTrigger` — use `unity-shuriken`.

## VFX Graph vs Shuriken (decision)

| | Shuriken | VFX Graph |
| --- | --- | --- |
| Sim | CPU | GPU |
| Component | `ParticleSystem` | `VisualEffect` + `.vfx` asset |
| Comfortable count | up to ~5,000 | 5,000–1,000,000+ |
| Per-particle script callbacks | `OnParticleCollision` / `OnParticleTrigger` | none |
| Authoring | Inspector modules | Node graph (Shader-Graph-style) |
| Pipeline | Built-in / URP / HDRP | URP / HDRP only |

Pick VFX Graph when count > ~5000, or you need texture / SDF / mesh sampling, or you want graph-style data flow. Pick Shuriken when count is low, gameplay needs collision callbacks, or you want simple author-and-go. Cross-link `unity-shuriken`.

## Package install

Add `com.unity.visualeffectgraph` via the package manager. It adds the menu `Assets > Create > Visual Effects > Visual Effect Graph` and the `Visual Effect` component (`Component > Visual Effects > Visual Effect`).

## Asset anatomy and contexts

Open the `.vfx` asset to enter the graph editor. A graph contains one or more **Systems** (vertical strips of contexts). Each system is built from these contexts in order:

- **Spawn context** — runs on CPU. Emits Spawn Events at a Constant Rate, Periodic Burst, or Single Burst. Outputs `spawnCount` to the Initialize context. Custom event ports can be added (e.g. `OnPlay`, `OnStop`, `OnDeath`).
- **Initialize Particle context** — runs on GPU once per spawned particle. Sets initial Position, Velocity, Color, Size, Lifetime, custom attributes. Capacity (max particles) is configured here.
- **Update Particle context** — runs every frame on GPU per live particle. Integrates motion, applies forces, kills particles past lifetime, handles collisions.
- **Output Particle context** — renders particles. Output type (Quad / Lit Quad / Mesh / Strip / Triangle / Octagon / etc.) chosen at create time; configures shader, blend mode, UV mapping, sort.

You can chain multiple systems in one asset (e.g. base smoke + secondary embers), and feed events between them with the `GPU Event` block.

## Attributes

Per-particle data fields. Built-in: `position`, `velocity`, `color`, `size` / `scale.xyz`, `alpha`, `age`, `lifetime`, `rotation`, `angularVelocity`, `mass`, `targetPosition`, plus custom attributes you define on the Blackboard. Read in any context, written in Initialize / Update via `Set <Attribute>` blocks.

## Blocks and operators

- **Blocks** live INSIDE a context. Examples: `Set Velocity Random`, `Multiply Size by Curve over Lifetime`, `Apply Force`, `Kill if Out of AABB`, `Collide with Sphere`, `Set Bounds`.
- **Operators** live OUTSIDE contexts and produce values that feed block ports. Examples: `Random Float / Vector`, `Sample Curve`, `Sample Gradient`, `Sample Texture 2D / Texture3D`, `Sample Mesh`, `Periodic Total Time`, `Get Particle <Attribute>`.

## Output types

| Output | Use for |
| --- | --- |
| Quad | Cheapest billboard. Default for most fx. |
| Lit Quad | Receives URP lighting (normal + roughness). Snow / smoke / mist that should accept scene light. |
| Mesh | Particles as small meshes (debris, leaves, custom shapes). |
| Strip | Connected ribbon between particles (trails, lightning, beams). |
| Triangle / Octagon | Alternative billboard shapes (cheaper or higher-poly). |

Each output context exposes Material settings: Shader Graph asset (custom), Texture, Blend Mode (Alpha / Additive / Multiply / Premultiplied), UV Mode, Sort Mode.

## Exposed properties (driving from script)

In the graph's Blackboard, add a property (Float, Vector3, Color, Texture, etc.) and tick **Exposed**. Then from C#:

```csharp
using UnityEngine.VFX;

VisualEffect vfx;
vfx.SetFloat("Intensity", 0.7f);
vfx.SetVector3("WindDir", Vector3.right);
vfx.SetTexture("Mask", maskTexture);

// Cache IDs for hot paths:
static readonly int IntensityId = Shader.PropertyToID("Intensity");
vfx.SetFloat(IntensityId, 0.7f);
```

Exposed properties drive ANY graph value at runtime — emission rate, color, velocity scale, mask textures, target transforms.

## URP integration

VFX Graph requires SRP. This skill set is URP-only — confirm the project uses URP before authoring. Output contexts ship URP-compatible shader templates. URP Forward+ handles many lights well for Lit Quads; Deferred has caveats with transparent VFX. Cross-link `unity-urp` and `unity-shaders` (custom Shader Graph for outputs).

## Sampling textures and meshes

- **Sample Texture 2D / Cubemap** — masks, ramps, per-position lookup (e.g. wind flow texture).
- **Sample Mesh / Skinned Mesh** — emit particles from a mesh's surface (face / vertex / edge sampling). Character dissolves, explosion-from-mesh.
- **Sample SDF (Signed Distance Field)** — emit particles inside / outside an SDF and collide cheaply with it (volumetric collisions). Bake via `Window > Visual Effects > Utilities > SDF Bake Tool` from a mesh.
- **Sample Vector Field** — drive per-particle velocity from a 3D vector field texture. Smoke flow, magic spirals.
- **Sample Point Cache** — emit at positions from a baked point cache (star coordinates, leaf positions, custom layouts).

## Events and triggers

Spawn contexts accept named events. From C#: `vfx.SendEvent("OnDeath")` triggers a named event the graph defines on its Spawn context. Use to switch from continuous emission to one-shot bursts on game-state change. The default events are `OnPlay` and `OnStop` (also fired by `vfx.Play()` / `vfx.Stop()`).

## Common patterns

- **Magic projectile trail** — Strip output with Lifetime curve fading alpha; emission Rate over Distance; Lit so torches affect it.
- **Mesh dissolve** — Sample Mesh in Initialize so particles spawn at mesh surface; over Lifetime scale to 0 + drift via Vector Field; pair with a dissolve shader on the source mesh (`unity-shaders`).
- **Snow storm** — 50,000 Lit Quads, Box volume Initialize position, downward velocity + curl noise, billboard with snowflake texture, fade-out near ground via depth sample.
- **Sparks from grinder** — Strip output, short lifetime, Cone shape, Random Velocity Cone, gravity, Lit material.
- **Energy beam** — persistent Strip following two transforms (exposed `Vector3 Start` / `Vector3 End`), radial sub-emission for crackle.
- **Click VFX** — One-shot burst via `SendEvent` on click; Quad output with a lightning textured material.

## Performance

- GPU-bound. Bottleneck is usually fillrate (overdraw) on large alpha-blended quads. Reduce particle size or count if frame time spikes.
- Each VFX system has its own GPU dispatch — fewer systems with more particles is faster than many small systems.
- `Capacity` (Initialize context) sizes the GPU buffer. Allocate the smallest you need.
- Lit outputs cost more than Unlit (per-pixel lighting per particle). On mobile, halve quad sizes and prefer Unlit unless lighting is essential.
- Profile via Frame Debugger and the Profiler GPU module — cross-link `unity-profiling` and `unity-urp`.

## Gotchas

- **Built-in RP renders nothing.** VFX Graph requires URP/HDRP. This skill set is URP-only.
- **Pink output material** = wrong shader for the active pipeline. Re-create the output context with the URP template.
- **`.vfx` edits don't auto-recompile in Play mode.** Toggle the `VisualEffect` component or call `vfx.Reinit()`.
- **`SetFloat` on a non-exposed property silently fails.** Verify the **Exposed** checkbox in the Blackboard.
- **`Update Mode = Always`** keeps simulating offscreen. Turn off when the effect is camera-culled.
- **Bounds are explicit.** VFX Graph uses bounds set via `Set Bounds` block in Initialize/Update or the asset's Bounds Mode. Wrong bounds = effect culled while still visible. Author bounds large enough or compute them in-graph.
- **Sub-graphs / sub-systems can't reach attributes across system boundaries.** Pass via custom attributes only.
- **Editor preview ignores game state.** Lighting and post-process can look different in Play. Always verify in Play mode.
- **No per-particle MonoBehaviour callbacks.** For collision callbacks, use Shuriken (`unity-shuriken`).
- **URP vs HDRP operators differ.** Stay on URP-template operators; some HDRP-only nodes will throw errors on URP.

## Verification

- `Visual Effect` component visible in scene; Visual Effect Asset assigned; transform anchored where you expect emission.
- Editor console clean of `VFX shader compilation failed` / `Property not exposed` / `Bounds` warnings.
- Frame Debugger shows the VFX render pass at expected ordering (`unity-profiling`).
- Profiler GPU time for the VFX pass under target.
- For 3D scene effects, run `unity-3d-verification` (4-shot orthographic) at peak emission, plus a runtime simulate-and-pause to capture mid-effect.
- Cross-link `unity-best-practices` for the standard MCP loop (detect pipeline, read console, batch, verify visually).

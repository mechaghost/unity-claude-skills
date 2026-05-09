---
name: unity-vfx-graph
description: 'Use for Unity 6+ Visual Effect Graph: GPU particles, .vfx assets, Visual Effect components, Spawn/Initialize/Update/Output contexts, exposed properties, SDF/vector-field/mesh/texture sampling, large swarms, beams, fire, snow, magic effects. Not low-count Shuriken.'
---

## When to use

GPU-driven, large-count, or data-sampled effects: magic projectiles, energy fields, fire fountains, dissolves, snow storms, swarming fx, anything sampling Texture/Mesh/SDF/Vector Field/Point Cache. Skip for low-count gameplay particles (sparks, dust, footsteps) and anything needing `OnParticleCollision`/`OnParticleTrigger` — use `unity-shuriken`.

## VFX Graph vs Shuriken

| | Shuriken | VFX Graph |
| --- | --- | --- |
| Sim | CPU | GPU |
| Component | `ParticleSystem` | `VisualEffect` + `.vfx` |
| Comfortable count | up to ~5,000 | 5,000–1,000,000+ |
| Per-particle script callbacks | `OnParticleCollision` / `OnParticleTrigger` | none |
| Authoring | Inspector modules | Node graph |
| Pipeline | Built-in / URP / HDRP | URP / HDRP only |

VFX Graph when count > ~5000, or you need texture/SDF/mesh sampling, or graph-style data flow. Shuriken when count is low, gameplay needs collision callbacks, or simple author-and-go. See `unity-shuriken`.

## Package install

`com.unity.visualeffectgraph`. Adds `Assets > Create > Visual Effects > Visual Effect Graph` and `Component > Visual Effects > Visual Effect`.

## Asset anatomy and contexts

Open `.vfx` for editor. One+ **Systems** (vertical strips). Each system in order:

- **Spawn** — CPU. Emits Spawn Events at Constant Rate, Periodic Burst, or Single Burst. Outputs `spawnCount` to Initialize. Custom event ports (`OnPlay`, `OnStop`, `OnDeath`).
- **Initialize** — GPU, once per spawned particle. Sets initial Position, Velocity, Color, Size, Lifetime, custom attributes. Capacity (max particles) configured here.
- **Update** — GPU, every frame per live particle. Integrates motion, applies forces, kills past lifetime, handles collisions.
- **Output** — renders. Output type (Quad / Lit Quad / Mesh / Strip / Triangle / Octagon / etc.) chosen at create time; configures shader, blend mode, UV mapping, sort.

Chain multiple systems (base smoke + secondary embers); feed events between with `GPU Event`.

## Attributes

Per-particle data fields. Built-in: `position`, `velocity`, `color`, `size` / `scale.xyz`, `alpha`, `age`, `lifetime`, `rotation`, `angularVelocity`, `mass`, `targetPosition`. Custom via Blackboard. Read anywhere, written in Initialize/Update via `Set <Attribute>` blocks.

## Blocks and operators

- **Blocks** — INSIDE contexts: `Set Velocity Random`, `Multiply Size by Curve over Lifetime`, `Apply Force`, `Kill if Out of AABB`, `Collide with Sphere`, `Set Bounds`.
- **Operators** — OUTSIDE contexts, produce values for block ports: `Random Float/Vector`, `Sample Curve/Gradient/Texture 2D/Texture3D/Mesh`, `Periodic Total Time`, `Get Particle <Attribute>`.

## Output types

| Output | Use for |
| --- | --- |
| Quad | Cheapest billboard. Default. |
| Lit Quad | Receives URP lighting (normal + roughness). Snow / smoke / mist that should accept scene light. |
| Mesh | Particles as small meshes (debris, leaves, custom shapes). |
| Strip | Connected ribbon between particles (trails, lightning, beams). |
| Triangle / Octagon | Alternative billboard shapes (cheaper or higher-poly). |

Each output exposes Material settings: Shader Graph asset (custom), Texture, Blend Mode (Alpha / Additive / Multiply / Premultiplied), UV Mode, Sort Mode.

## Exposed properties (driving from script)

In Blackboard, add a property (Float, Vector3, Color, Texture, etc.) and tick **Exposed**. From C#:

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

Exposed properties drive ANY graph value at runtime.

## URP integration

Requires SRP. URP-only here. Output contexts ship URP-compatible templates. URP Forward+ handles many lights for Lit Quads; Deferred has caveats with transparent VFX. See `unity-urp`, `unity-shaders` (custom Shader Graph for outputs).

## Sampling

- **Texture 2D / Cubemap** — masks, ramps, per-position lookup (wind flow).
- **Mesh / Skinned Mesh** — emit from surface (face/vertex/edge). Character dissolves, explosion-from-mesh.
- **SDF** — emit inside/outside a signed distance field; cheap collisions. Bake via `Window > Visual Effects > Utilities > SDF Bake Tool`.
- **Vector Field** — drive per-particle velocity from a 3D vector field texture. Smoke flow, magic spirals.
- **Point Cache** — emit at positions from a baked point cache (star coords, leaf positions).

## Events

Spawn contexts accept named events. From C#: `vfx.SendEvent("OnDeath")` triggers a graph-defined event. Switch from continuous to one-shot bursts on game-state change. Defaults: `OnPlay`, `OnStop` (also fired by `vfx.Play()` / `vfx.Stop()`).

## Common patterns

- **Magic projectile trail** — Strip output with Lifetime curve fading alpha; Rate over Distance; Lit so torches affect it.
- **Mesh dissolve** — Sample Mesh in Initialize so particles spawn at surface; over Lifetime scale to 0 + drift via Vector Field; pair with a dissolve shader (`unity-shaders`).
- **Snow storm** — 50,000 Lit Quads, Box volume Initialize position, downward velocity + curl noise, snowflake billboard, fade near ground via depth sample.
- **Sparks from grinder** — Strip output, short lifetime, Cone shape, Random Velocity Cone, gravity, Lit material.
- **Energy beam** — persistent Strip following two transforms (exposed `Vector3 Start`/`End`), radial sub-emission for crackle.
- **Click VFX** — One-shot burst via `SendEvent` on click; Quad output with lightning material.

## Performance

- GPU-bound. Bottleneck usually fillrate (overdraw) on large alpha-blended quads. Reduce size/count if frame-time spikes.
- Each system has its own GPU dispatch — fewer systems with more particles beats many small systems.
- `Capacity` (Initialize) sizes the GPU buffer. Allocate the smallest you need.
- Lit costs more than Unlit. Mobile: halve quad sizes, prefer Unlit unless lighting is essential.
- Profile via Frame Debugger + Profiler GPU module. See `unity-profiling`, `unity-urp`.

## Gotchas

- **Built-in RP renders nothing.** Requires URP/HDRP. URP-only here.
- **Pink output material** = wrong shader for active pipeline. Re-create the output context with URP template.
- **`.vfx` edits don't auto-recompile in Play mode.** Toggle the `VisualEffect` component or call `vfx.Reinit()`.
- **`SetFloat` on a non-exposed property silently fails.** Verify the **Exposed** checkbox.
- **`Update Mode = Always`** keeps simulating offscreen. Turn off when camera-culled.
- **Bounds are explicit.** VFX Graph uses bounds set via `Set Bounds` block in Initialize/Update or asset's Bounds Mode. Wrong bounds = effect culled while still visible. Author bounds large enough or compute in-graph.
- **Sub-graphs / sub-systems can't reach attributes across system boundaries.** Pass via custom attributes only.
- **Editor preview ignores game state.** Lighting and PP can look different in Play. Verify in Play mode.
- **No per-particle MonoBehaviour callbacks.** For collision callbacks, use Shuriken.
- **URP vs HDRP operators differ.** Stay on URP-template operators; some HDRP-only nodes throw errors on URP.

## Verification

- `Visual Effect` component visible; Asset assigned; transform anchored where you expect emission.
- Editor console clean of `VFX shader compilation failed` / `Property not exposed` / `Bounds` warnings.
- Frame Debugger shows VFX pass at expected ordering (`unity-profiling`).
- Profiler GPU time for the VFX pass under target.
- 3D scene effects: `unity-3d-verification` (4-shot orthographic) at peak emission + runtime simulate-and-pause for mid-effect.

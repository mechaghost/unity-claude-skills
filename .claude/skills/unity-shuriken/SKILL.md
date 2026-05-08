---
name: unity-shuriken
description: Use when authoring or tuning Unity Shuriken particle effects through Unity MCP (trigger keywords ParticleSystem, particle, shuriken, emission, sub-emitter, particle effect, hit spark, explosion, smoke, fire, dust, muzzle flash, spark, magic projectile, weather, rain, snow, footstep dust, color over lifetime, rate over time, rate over distance, OnParticleCollision, OnParticleTrigger, in-volume / out-volume particle triggers, particle pooling, billboard, stretched particle, trail, texture sheet animation). Shuriken-specific — see VFX Graph (Visual Effect component) for the GPU pipeline; most modules below do not apply there. Do NOT use for >5000 GPU-driven particles or texture/SDF/mesh sampling — use unity-vfx-graph for that.
---

## When to use

Any task involving the built-in `ParticleSystem` MonoBehaviour: hit sparks, explosions, smoke columns, fire, dust kick-up, magic projectiles, weather (rain/snow), environmental ambience, rocket trails, muzzle flashes. Also applies to tuning emission, color/size over lifetime, sub-emitter chains, or wiring `OnParticleCollision` / `OnParticleTrigger` callbacks. If the user is editing a `Visual Effect` (VFX Graph) asset, that is a different system — most of this skill does not apply.

## Anatomy of a particle system

- A particle system is a GameObject with a `ParticleSystem` component plus an auto-added `ParticleSystemRenderer`. Sub-emitters are normally child GameObjects with their own `ParticleSystem`.
- Particles are simulated on the CPU and batched by material. The GameObject has a normal Transform; `Main.Simulation Space` decides whether already-spawned particles follow the emitter when the Transform moves:
  - `Local` — particles ride the emitter (handheld torch flame, attached aura).
  - `World` — particles stay where they were emitted (smoke trail behind a moving rocket).
  - `Custom` — particles follow a chosen Transform (e.g. parent rig that moves but not the emitter).
- Loop vs one-shot. `Main.Looping` on = continuous (smoke, fire). Off + `Main.Stop Action: Destroy` = one-shot prefab that removes itself after the last particle dies. Use `Disable` instead of `Destroy` when pooling.
- Build hierarchies under a clearly named anchor GameObject (e.g. `FX_Explosion_Large`) so `manage_gameobject` can spawn/parent the whole effect as a unit.

## Modules

Quick map of what each sub-module is for and the field most often tuned. Full field reference: `references/modules.md`.

- Main — duration, looping, start lifetime/speed/size/rotation/color, gravity modifier, simulation space, simulation speed, max particles, stop action.
- Emission — `Rate over Time` (particles/sec), `Rate over Distance` (particles per unit moved, ideal for trails), `Bursts` (count + cycles + interval).
- Shape — emitter shape: Sphere, Hemisphere, Cone, Box, Mesh, MeshRenderer, SkinnedMeshRenderer, Circle, Edge, Donut, Rectangle, Sprite, SpriteRenderer. Cone for muzzle flashes, Sphere for explosions, Edge for ground line emitters.
- Velocity over Lifetime, Limit Velocity over Lifetime, Inherit Velocity, Force over Lifetime — directional motion controls (drift, drag, attach to parent motion, wind).
- Color over Lifetime — gradient. Almost always end at alpha 0 so particles don't pop when they die.
- Color by Speed — tint as a function of speed (sparks brighten when fast).
- Size over Lifetime — curve. Smoke grows, sparks shrink.
- Size by Speed — size as a function of speed.
- Rotation over Lifetime, Rotation by Speed — spinning debris, tumbling embers.
- External Forces — receive Wind Zones / `ParticleSystemForceField`s.
- Noise — turbulence; the classic fire/smoke "wandering" look.
- Collision — `World` (per-particle physics, expensive, uses layers) or `Planes` (cheap, manual planes). Set `Send Collision Messages` to receive `OnParticleCollision(GameObject)`.
- Triggers — fire `OnParticleTrigger` when particles enter/exit/are inside listed colliders (in-volume / out-volume effects).
- Sub Emitters — spawn child systems on Birth / Collision / Death / Trigger. Foundation for compound effects.
- Texture Sheet Animation — flipbook through a sprite sheet (animated fire frames, explosion sequence).
- Lights — attach real-time Lights to a fraction of particles. Cap tightly; these are full real-time lights.
- Trails — ribbons attached to particles (sparks, missile contrails). Need a separate Trails material.
- Custom Data — feed per-particle data into a custom shader (`TEXCOORD0.zw`, `TEXCOORD1`).
- Renderer — `Render Mode` (Billboard, Stretched Billboard, Horizontal Billboard, Vertical Billboard, Mesh, None), Sort Mode, Sorting Layer, Order in Layer, custom material(s), trail material, mesh, GPU instancing.

## Materials and shaders

This skill set targets URP. Particles need a URP-compatible Particle shader (cross-reference `unity-urp` and `unity-shaders`):

- `Universal Render Pipeline/Particles/Lit`
- `Universal Render Pipeline/Particles/Unlit`
- Shader Graph with the URP "Lit Particles" or "Unlit Particles" target.

Legacy / Built-in particle shaders (e.g. `Particles/Standard Unlit`) on materials imported from non-URP packages render pink in URP — re-author or convert.

Blend mode picks the look:

- `Additive` — fire, sparks, light beams, energy. No alpha culling, brightens whatever is behind.
- `Alpha` — smoke, dust, water spray. Standard transparent compositing.
- `Premultiplied` — soft particles with internal masking, fog cards.

`Soft Particles` (smooth fade against intersecting geometry) requires the active camera to render a depth texture — confirm via `manage_camera` and pipeline settings (`manage_graphics`).

Author/swap materials with `manage_material`; for custom particle shaders use `manage_shader`. Texture sheets and atlases come in via `manage_texture` and `manage_asset`.

## Sub-emitters

Sub Emitters wire one ParticleSystem to spawn another on a lifecycle event. Canonical chain for a rocket:

1. Root `FX_Rocket` — main looping smoke, `Rate over Distance`, `Local` simulation space, attached to the rocket Transform.
2. On root `Death` — sub-emitter `FX_Explosion`: short Sphere burst, additive, `Looping` off, `Stop Action: Destroy`, `Lights` module on a small fraction.
3. On `FX_Explosion` `Death` — sub-emitter `FX_Smoke_Linger`: alpha smoke, `World` space, gravity slightly negative, color-over-lifetime fading to 0.

Wire via `manage_vfx` if the action is exposed. If not, fall back to `manage_components` to set the `ParticleSystem.SubEmittersModule` (its `subEmitters` list of `ParticleSystem` references and `ParticleSystemSubEmitterType`). For complex API access route through `unity_reflect` or generate a configurator script with `create_script`.

## Performance

Dominant cost is `Main.Max Particles` x simulation step x renderer overdraw. Tiered ceilings before VFX Graph becomes the better choice:

- **Mobile** — keep each system **<200 particles at peak**, **hard-cap simultaneous emitters at 4-6**. Above that, frame-time and overdraw dominate. Cross-link `unity-build` references/mobile.md.
- **Desktop** — **<2,000 particles per system** is fine on Shuriken; 2,000-5,000 is workable but hot.
- **>2,000 mobile / >5,000 desktop** — switch to VFX Graph (GPU-driven). Cross-link `unity-vfx-graph`.
- Collision module: prefer `Planes` over `World`; lower `Quality`; raise `Voxel Size`. Each `World` collision is a physics query.
- Lights module: cap to fewer than ~8 active particle lights at any time. They are real-time lights with full cost.
- Trails: every particle with a trail multiplies vertex/index count. Limit `Ratio` (fraction of particles with trails).
- Pooling: never `Instantiate`+`Destroy` per shot. Pre-spawn pooled effects, then `ps.Play()` / `ps.Stop()`. Combine with `Stop Action: Disable` and re-enable on dequeue.
- GPU instancing: enable on the renderer when `Render Mode = Mesh` with the same material across particles.
- Profile via `manage_profiler` and look at `ParticleSystem.Update`, `ParticleSystem.Render`, and `ParticleSystem.EndUpdateAll` markers.

Mobile-specific: large alpha-blended quads cause overdraw and thermal throttling. Smaller particles, lower alpha, or fewer overlapping layers. Stick to the **<200/system, 4-6 emitters** ceiling above; pool aggressively.

## Runtime control

Module accessors on `ParticleSystem` (`ps.main`, `ps.emission`, `ps.shape`, etc.) are **properties that return structs** — those structs hold handles into the native ParticleSystem data and write through when you mutate their fields. Because the property returns a struct *by value*, the C# compiler refuses to let you mutate fields on the temporary returned struct: writing `ps.main.startSpeed = 5f` is a **compile error** (CS1612: "Cannot modify the return value of '...' because it is not a variable"). Store the returned struct in a local first, then mutate; the writes go through to the underlying system:

```csharp
// Correct — local var is a variable, mutation compiles and writes through
var main = ps.main;
main.startSpeed = 5f;
main.startColor = Color.red;

var emission = ps.emission;
emission.rateOverTime = 50f;

// Compile error CS1612 — cannot modify a property's returned struct in place
// ps.main.startSpeed = 5f;
```

Start, stop, and clear:

```csharp
ps.Play();
ps.Stop(true, ParticleSystemStopBehavior.StopEmitting);        // let live particles finish
ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear); // instant clear
```

One-shot emission and end detection:

```csharp
ps.Emit(20); // immediate burst, ignores Rate
// Poll for completion (true = include children)
bool done = !ps.IsAlive(true);
```

Or set `Main.Stop Action: Callback` and implement `OnParticleSystemStopped()` on a MonoBehaviour on the same GameObject — fires once when emission has stopped and all particles have died.

Generate or edit such scripts with `create_script` / `apply_text_edits` and attach via `manage_components`. For batched configuration (many systems at once) use `batch_execute`.

## Common patterns

- Hit spark: Cone shape, additive material, `Start Lifetime` 0.15-0.25s, single Burst of 10-20, `Color over Lifetime` fading to alpha 0, `Size over Lifetime` shrinking, `Stretched Billboard` renderer for streaks.
- Smoke column: Cone aimed up, alpha-blend material, `Gravity Modifier` slightly negative (rises), `Color over Lifetime` fading out, `Size over Lifetime` growing, `World` simulation space, `Noise` module low frequency.
- Rocket trail: `Rate over Distance` (not `over Time`), `Local` simulation space, sub-emitter on `Death` = explosion, sub-emitter on explosion `Death` = lingering smoke.
- Footstep dust: Small Sphere/Hemisphere shape, `Rate over Distance` plus a small Burst on each step, ground-aligned `Horizontal Billboard`, fast fade.
- Rain: Box shape stretched along Z above the player, downward `Start Speed`, `Stretched Billboard` with high Length Scale, GPU instancing if mesh. Cap Max Particles tightly and parent to the camera (`Local` simulation space) so it follows.
- Magic projectile: Sphere shape on the projectile root, `Local` simulation space, additive trail; on `Death` sub-emitter for impact burst.

## Gotchas

- Module struct trap (above) — cache `var main = ps.main;` then mutate.
- Pink material in URP = Built-in / legacy particle shader on a URP project (commonly from imported asset packages). Reassign to a `Universal Render Pipeline/Particles/...` shader via `manage_material`.
- `World` vs `Local` mismatch is the single most common "particles drag behind", "clump up at origin", or "stick to the player" bug. Pick deliberately.
- `Play On Awake` is on by default. Disable for triggered/pooled effects, otherwise they fire once when spawned and leave the pool already-stopped.
- `Stop Action: Destroy` destroys the GameObject — fatal if the ParticleSystem is on a player or a persistent rig. Use `Disable` plus pooling.
- Sub-emitter prefab references can break across scenes. Either assign in the prefab inspector or wire at runtime via the `SubEmittersModule` API.
- Particles render in the transparent queue and do not write depth — they can z-fight with other transparent meshes. Tune `Sorting Fudge`, `Order in Layer`, or pin `Sort Mode`.
- 2D scenes: Transparency Sort Mode (`manage_graphics`) and `Pixels Per Unit` interact with particle sorting in non-obvious ways. Pin a custom sort axis if results are unstable.
- Trails inherit the particle's lifetime. Short particle = short trail. Lengthen `Start Lifetime` (or use `Lifetime` on the Trails module) instead of fighting it.
- `Looping` off + no `Stop Action` = the GameObject lingers forever. Always pair with `Destroy` or `Disable` (or pool it).
- Mobile thermal: large additive quads at high count overdraw the screen multiple times per frame.

## Verification

- After authoring, invoke `unity-3d-verification` (4-shot orthographic) to capture the effect at peak emission. For one-shot effects, simulate to a known peak frame first:

```csharp
// Editor or runtime: jump the system to t = 0.4s and freeze it
ps.Simulate(0.4f, true /* withChildren */, true /* restart */);
```

  Then capture; advance and capture again to sample the curve.
- Visually confirm:
  - `Color over Lifetime` ends at alpha 0 (no popping at death).
  - Cone/Shape orientation matches intent (gizmo arrow points where particles should go).
  - Emission rate roughly matches the design (count particles in a single captured frame).
  - No pink material; particles are not z-fighting with adjacent transparents.
- Run `manage_profiler` for any effect that may be hot. Look for `ParticleSystem.Update` / `ParticleSystem.Render` spikes.
- Check `read_console` after configuration changes for null references in sub-emitter slots or missing renderer materials.

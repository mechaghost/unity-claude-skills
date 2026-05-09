---
name: unity-shuriken
description: 'Use for Unity 6+ Shuriken/ParticleSystem effects: emission, sub-emitters, sparks, smoke, fire, dust, muzzle flashes, weather, trails, texture-sheet animation, collisions/triggers, pooling, billboards. Use VFX Graph for >5000 GPU particles or SDF/mesh/texture sampling.'
---

## When to use

Built-in `ParticleSystem` MonoBehaviour: hit sparks, explosions, smoke, fire, dust, magic projectiles, weather (rain/snow), ambience, rocket trails, muzzle flashes. Tuning emission, color/size over lifetime, sub-emitter chains, `OnParticleCollision` / `OnParticleTrigger`. For `Visual Effect` (VFX Graph) → `unity-vfx-graph`.

## Anatomy

- GameObject + `ParticleSystem` + auto-added `ParticleSystemRenderer`. Sub-emitters are child GOs with their own ParticleSystem.
- CPU-simulated, batched by material. `Main.Simulation Space` decides whether already-spawned particles follow the emitter:
  - `Local` — particles ride emitter (handheld torch, attached aura).
  - `World` — particles stay where emitted (smoke trail behind a moving rocket).
  - `Custom` — follow a chosen Transform.
- Loop vs one-shot. `Main.Looping` ON = continuous (smoke, fire). OFF + `Main.Stop Action: Destroy` = one-shot prefab that removes itself. Use `Disable` for pooling.
- Build hierarchies under a clearly named anchor (`FX_Explosion_Large`) so the whole effect spawns/reparents as a unit.

## Modules

Quick map. Full field reference: `references/modules.md`.

- Main — duration, looping, start lifetime/speed/size/rotation/color, gravity modifier, simulation space, simulation speed, max particles, stop action.
- Emission — `Rate over Time` (particles/sec), `Rate over Distance` (per unit moved — ideal for trails), `Bursts` (count + cycles + interval).
- Shape — Sphere, Hemisphere, Cone, Box, Mesh, MeshRenderer, SkinnedMeshRenderer, Circle, Edge, Donut, Rectangle, Sprite, SpriteRenderer. Cone for muzzle flashes, Sphere for explosions, Edge for ground line emitters.
- Velocity over Lifetime, Limit Velocity, Inherit Velocity, Force over Lifetime — directional motion (drift, drag, attach to parent motion, wind).
- Color over Lifetime — gradient. Almost always end at alpha 0 to avoid death pop.
- Color by Speed — sparks brighten when fast.
- Size over Lifetime — curve. Smoke grows, sparks shrink.
- Size by Speed.
- Rotation over Lifetime, Rotation by Speed — spinning debris, tumbling embers.
- External Forces — receive Wind Zones / `ParticleSystemForceField`s.
- Noise — turbulence; classic fire/smoke "wandering".
- Collision — `World` (per-particle physics, expensive, layers) or `Planes` (cheap, manual planes). `Send Collision Messages` enables `OnParticleCollision(GameObject)`.
- Triggers — `OnParticleTrigger` when particles enter/exit/are inside listed colliders.
- Sub Emitters — spawn child systems on Birth / Collision / Death / Trigger.
- Texture Sheet Animation — flipbook through a sprite sheet.
- Lights — attach real-time Lights to a fraction of particles. Cap tightly; full real-time light cost.
- Trails — ribbons attached to particles. Need a separate Trails material.
- Custom Data — feed per-particle data into a custom shader (`TEXCOORD0.zw`, `TEXCOORD1`).
- Renderer — Render Mode (Billboard / Stretched / Horizontal / Vertical / Mesh / None), Sort Mode, Sorting Layer, Order in Layer, materials, mesh, GPU instancing.

## Materials and shaders

URP-compatible Particle shader (see `unity-urp`, `unity-shaders`):

- `Universal Render Pipeline/Particles/Lit`
- `Universal Render Pipeline/Particles/Unlit`
- Shader Graph "Lit Particles" or "Unlit Particles" target.

Legacy/Built-in particle shaders (`Particles/Standard Unlit`) imported from non-URP packages render pink in URP — re-author or convert.

Blend mode picks the look:
- `Additive` — fire, sparks, light beams, energy. Brightens what's behind.
- `Alpha` — smoke, dust, water spray. Standard transparent compositing.
- `Premultiplied` — soft particles with internal masking, fog cards.

`Soft Particles` (smooth fade against intersecting geometry) requires the active camera to render a depth texture — confirm on Camera + Project Settings → Graphics.

## Sub-emitters

Wire one ParticleSystem to spawn another on a lifecycle event. Canonical rocket chain:

1. Root `FX_Rocket` — main looping smoke, `Rate over Distance`, `Local` space, attached to rocket Transform.
2. On root `Death` → `FX_Explosion`: short Sphere burst, additive, `Looping` off, `Stop Action: Destroy`, `Lights` module on a small fraction.
3. On `FX_Explosion` `Death` → `FX_Smoke_Linger`: alpha smoke, `World` space, gravity slightly negative, color-over-lifetime fading to 0.

Wire by setting `ParticleSystem.SubEmittersModule` on the parent — `subEmitters` list of `ParticleSystem` references and `ParticleSystemSubEmitterType`.

## Performance

Dominant cost: `Main.Max Particles` × simulation step × renderer overdraw. Tiered ceilings before VFX Graph wins:

- **Mobile** — **<200 particles/system at peak**, **hard-cap 4-6 simultaneous emitters**. See `unity-build` references/mobile.md.
- **Desktop** — **<2,000/system** fine; 2,000–5,000 workable but hot.
- **>2,000 mobile / >5,000 desktop** — switch to VFX Graph (GPU). See `unity-vfx-graph`.
- Collision: prefer `Planes` over `World`; lower `Quality`; raise `Voxel Size`. Each `World` collision is a physics query.
- Lights: cap to <~8 active particle lights at once.
- Trails: every particle with a trail multiplies vertex/index. Limit `Ratio`.
- Pooling: never `Instantiate`+`Destroy` per shot. Pre-spawn pooled effects, `ps.Play()` / `ps.Stop()`. Combine with `Stop Action: Disable`.
- GPU instancing: enable on renderer when `Render Mode = Mesh` with same material across particles.
- Profile: `ParticleSystem.Update`, `ParticleSystem.Render`, `ParticleSystem.EndUpdateAll` markers.

Mobile thermal: large alpha-blended quads cause overdraw and throttle. Smaller particles, lower alpha, fewer overlapping layers.

## Runtime control

Module accessors (`ps.main`, `ps.emission`, `ps.shape`, etc.) are **properties returning structs** holding handles into native ParticleSystem data. Direct mutation is a **compile error CS1612**. Cache to a local first:

```csharp
// Correct — local var compiles, writes through
var main = ps.main;
main.startSpeed = 5f;
main.startColor = Color.red;

var emission = ps.emission;
emission.rateOverTime = 50f;

// Compile error CS1612
// ps.main.startSpeed = 5f;
```

Start, stop, clear:

```csharp
ps.Play();
ps.Stop(true, ParticleSystemStopBehavior.StopEmitting);        // let live particles finish
ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear); // instant clear
```

One-shot + end detection:

```csharp
ps.Emit(20); // immediate burst, ignores Rate
bool done = !ps.IsAlive(true); // include children
```

Or set `Main.Stop Action: Callback` and implement `OnParticleSystemStopped()` on a MonoBehaviour on the same GO — fires once when emission stopped and all particles dead.

## Common patterns

- Hit spark: Cone, additive, `Start Lifetime` 0.15-0.25s, single Burst of 10-20, `Color over Lifetime` fading to alpha 0, `Size over Lifetime` shrinking, `Stretched Billboard` for streaks.
- Smoke column: Cone aimed up, alpha-blend, `Gravity Modifier` slightly negative, `Color over Lifetime` fading, `Size over Lifetime` growing, `World` space, `Noise` low frequency.
- Rocket trail: `Rate over Distance` (not Time), `Local` space, sub-emitter on `Death` = explosion, sub-emitter on explosion `Death` = lingering smoke.
- Footstep dust: Sphere/Hemisphere, `Rate over Distance` + small Burst on each step, ground-aligned `Horizontal Billboard`, fast fade.
- Rain: Box stretched along Z above player, downward `Start Speed`, `Stretched Billboard` with high Length Scale, GPU instancing if mesh. Cap Max Particles, parent to camera (`Local` space).
- Magic projectile: Sphere on projectile root, `Local` space, additive trail; on `Death` sub-emitter for impact burst.

## Gotchas

- Module struct trap (above) — cache `var main = ps.main;`.
- Pink material in URP = Built-in/legacy particle shader (commonly from imported packs). Reassign to `Universal Render Pipeline/Particles/...`.
- `World` vs `Local` mismatch is the #1 cause of "particles drag behind", "clump up at origin", or "stick to player". Pick deliberately.
- `Play On Awake` ON by default. Disable for pooled/triggered effects, or they fire once on spawn and leave the pool already-stopped.
- `Stop Action: Destroy` destroys the GameObject — fatal on a player/persistent rig. Use `Disable` + pooling.
- Sub-emitter prefab references break across scenes. Either assign in prefab inspector or wire at runtime via `SubEmittersModule`.
- Particles render in transparent queue and don't write depth — z-fight with other transparents. Tune `Sorting Fudge`, `Order in Layer`, `Sort Mode`.
- 2D scenes: Transparency Sort Mode + `Pixels Per Unit` interact non-obviously with sorting. Pin a custom sort axis if unstable.
- Trails inherit particle lifetime. Short particle = short trail. Lengthen `Start Lifetime` (or `Lifetime` on Trails module).
- `Looping` off + no `Stop Action` = GameObject lingers forever. Pair with `Destroy`/`Disable` (or pool).
- Mobile thermal: large additive quads at high count overdraw multiple times per frame.

## Verification

- After authoring → `unity-3d-verification` (4-shot orthographic) at peak emission. For one-shots, simulate to a known peak frame:

```csharp
ps.Simulate(0.4f, true /* withChildren */, true /* restart */);
```

- Visually confirm:
  - `Color over Lifetime` ends at alpha 0 (no death pop).
  - Cone/Shape orientation matches intent.
  - Emission rate matches design (count particles in a captured frame).
  - No pink material; no z-fighting with adjacent transparents.
- Profile any hot effect — `ParticleSystem.Update` / `ParticleSystem.Render` spikes.
- Editor console clean of null refs in sub-emitter slots, missing renderer materials.

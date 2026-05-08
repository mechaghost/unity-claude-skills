# Shuriken module reference

Field-level detail for each `ParticleSystem` sub-module. Names match the inspector and the C# `ParticleSystem.*Module` API used via `unity_reflect` or generated scripts.

## Main (`ParticleSystem.MainModule`)

- `Duration` — system run length in seconds (looping resets each cycle).
- `Looping` — repeat after Duration. Off = one-shot.
- `Prewarm` — only meaningful when `Looping` is on; system starts as if it had already been running one full Duration.
- `Start Delay` — seconds before first emission.
- `Start Lifetime` — per-particle lifespan. Curve / random-between-two for variance.
- `Start Speed` — initial speed along the Shape's emit direction.
- `3D Start Size` / `Start Size` — initial scale (xyz or scalar).
- `3D Start Rotation` / `Start Rotation` — initial orientation.
- `Flip Rotation` — fraction of particles that spin the opposite direction.
- `Start Color` — initial tint, multiplied with Color over Lifetime.
- `Gravity Modifier` — multiplier on `Physics.gravity` per particle. Negative = rises (smoke).
- `Simulation Space` — `Local`, `World`, `Custom`. See main file.
- `Simulation Speed` — playback rate scalar (slow-mo / fast-forward).
- `Delta Time` — `Scaled` (uses `Time.timeScale`) vs `Unscaled` (ignores pause). Unscaled for UI/menu effects.
- `Scaling Mode` — how the Transform scale affects size: `Hierarchy`, `Local`, `Shape`.
- `Play On Awake` — fire when enabled. Disable for pooled/triggered effects.
- `Emitter Velocity Mode` — `Transform` vs `Rigidbody`. `Rigidbody` is correct when `Inherit Velocity` is used on a physics-driven emitter.
- `Max Particles` — hard cap. Emission stops when reached.
- `Auto Random Seed` — off + fixed `Random Seed` for deterministic playback.
- `Stop Action` — `None`, `Disable`, `Destroy`, `Callback` (fires `OnParticleSystemStopped`).
- `Culling Mode` — `Automatic`, `Pause and Catch-up`, `Pause`, `Always Simulate`. `Pause` when off-screen saves CPU; `Always Simulate` is needed if particles must keep evolving while culled.
- `Ring Buffer Mode` — recycle oldest particles instead of waiting for them to die. Useful for endless ribbons.

## Emission (`ParticleSystem.EmissionModule`)

- `Rate over Time` — particles per second (curve/random supported).
- `Rate over Distance` — particles per world-unit moved by the emitter Transform. Use for trails — produces zero output when stationary.
- `Bursts` — list of `(time, count, cycles, interval, probability)`. Multiple bursts compose for layered explosions.

## Shape (`ParticleSystem.ShapeModule`)

- `Shape` — Sphere, Hemisphere, Cone, Donut, Box, Mesh, MeshRenderer, SkinnedMeshRenderer, Sprite, SpriteRenderer, Circle, Edge, Rectangle.
- `Angle` (Cone) — half-angle of the cone.
- `Radius`, `Radius Thickness` — shell vs filled volume; thickness 0 emits only on the surface.
- `Arc`, `Arc Mode` (Random / Loop / Ping-Pong / Burst-Spread), `Arc Spread`, `Arc Speed` — for partial circles or sweeping emitters.
- `Length` (Cone) — used by `ConeVolume` to emit inside a frustum.
- `Position`, `Rotation`, `Scale` — local offset/orientation/scale of the shape inside the GameObject.
- `Align to Direction` — rotate each particle to match its initial velocity (great for stretched debris).
- `Randomize Direction`, `Spherize Direction`, `Randomize Position` — soften deterministic emission.
- `Texture` — sample emission color/alpha from a 2D texture (mask emission to a logo/silhouette).

## Velocity over Lifetime, Limit Velocity, Inherit Velocity, Force over Lifetime

- `Velocity over Lifetime` — additive velocity in `Local`/`World`/`Custom` space; orbital fields make particles rotate around the emitter.
- `Limit Velocity over Lifetime` — speed cap with optional `Dampen` (drag); `Drag` field can apply per-particle drag and account for velocity by size/scale.
- `Inherit Velocity` — pull the emitter's motion into the particles. `Mode = Initial` (one-time) vs `Current` (continuous). Pair with `Main.Emitter Velocity Mode`.
- `Force over Lifetime` — constant force vector (wind, draft) in chosen space.

## Color and size

- `Color over Lifetime` — gradient evaluated by particle age. Almost always end at alpha 0.
- `Color by Speed` — color as a function of speed magnitude. Define `Speed Range`.
- `Size over Lifetime` — curve. Start small, grow, fade is a common smoke pattern.
- `Size by Speed` — size as a function of speed; useful for stretched motion blur fakes.

## Rotation

- `Rotation over Lifetime` — angular velocity per axis (degrees/sec).
- `Rotation by Speed` — angular velocity as a function of speed.

## External Forces

- `Multiplier` on global Wind Zones.
- `Influence Filter` — `Layer Mask` or explicit `List` of `ParticleSystemForceField`s. Use `List` to gate which fields affect this system.

## Noise

- `Strength`, `Frequency`, `Scroll Speed` — turbulence look.
- `Damping` — high frequencies dissipate as strength increases.
- `Octaves`, `Octave Multiplier`, `Octave Scale` — fractal complexity.
- `Quality` — `Low` (1D) / `Medium` (2D) / `High` (3D). Higher = more cost.
- `Remap` — reshape the noise output curve.
- `Position Amount`, `Rotation Amount`, `Size Amount` — apply noise to each channel independently.

## Collision (`ParticleSystem.CollisionModule`)

- `Type` — `Planes` (cheap, manual planes via Transforms) or `World` (per-particle physics queries).
- `Mode` — `3D` or `2D` (uses Physics2D).
- `Dampen`, `Bounce` — energy loss / restitution on hit.
- `Lifetime Loss` — fraction of remaining lifetime to remove on each hit.
- `Min Kill Speed`, `Max Kill Speed` — kill particles outside this band on collision.
- `Radius Scale` — particle collision radius multiplier.
- `Collides With` — physics layer mask.
- `Quality` — `High` / `Medium (Static Colliders)` / `Low`. Lower quality = larger voxel size, fewer queries.
- `Voxel Size` — coarse spatial bin for medium/low quality.
- `Send Collision Messages` — required for `OnParticleCollision(GameObject other)` on receivers.

```csharp
// Receiver MonoBehaviour on a hit target
void OnParticleCollision(GameObject emitter)
{
    var ps = emitter.GetComponent<ParticleSystem>();
    int count = ps.GetSafeCollisionEventSize();
    var events = new List<ParticleCollisionEvent>(count);
    int n = ps.GetCollisionEvents(gameObject, events);
    for (int i = 0; i < n; i++) { /* events[i].intersection, normal, velocity */ }
}
```

## Triggers (`ParticleSystem.TriggerModule`)

- Up to N collider references; events fired for `Inside`, `Outside`, `Enter`, `Exit` per collider.
- Each event is `Callback`, `Kill`, or `Ignore`.
- Receiver implements `OnParticleTrigger()` and reads via `ps.GetTriggerParticles(ParticleSystemTriggerEventType.*, list)`.

## Sub Emitters (`ParticleSystem.SubEmittersModule`)

- List entries: `(particleSystem, type, properties, emitProbability)` where `type` is `Birth`, `Collision`, `Death`, `Trigger`, `Manual`.
- `Properties` controls which properties (Color, Size, Rotation, Lifetime, Duration) the parent passes to the child.
- Children must be ParticleSystems on child GameObjects; reference them via the inspector or assign at runtime through `subEmitters.SetSubEmitterSystem(index, ps)`.

## Texture Sheet Animation

- `Mode` — `Grid` (rows x cols) or `Sprites` (list of Sprite assets, can be different sizes).
- `Tiles` — grid dimensions.
- `Animation` — `Whole Sheet` or `Single Row`.
- `Frame over Time` — curve mapping particle age to frame index.
- `Start Frame` — initial frame (random per particle if curve).
- `Cycles` — playbacks per particle lifetime.
- `Affected UV Channels` — apply to base map, secondary, etc.

## Lights

- `Light` — prefab of a Light component to clone.
- `Ratio` — fraction of particles that get a Light. Keep tiny.
- `Random Distribution`, `Use Particle Color`, `Size Affects Range`, `Size Affects Intensity`, `Range Multiplier`, `Intensity Multiplier`, `Maximum Lights` — tuning.

## Trails

- `Mode` — `Particles` (one trail per particle) or `Ribbon` (connect particles into ribbons by birth order).
- `Ratio` — fraction of particles with trails.
- `Lifetime` — trail length, scaled by particle lifetime if `Inherit Particle Color` etc. are set.
- `Minimum Vertex Distance` — segment density.
- `World Space` — bake trail vertices in world space (helps with fast-moving emitters).
- `Die With Particles` — drop trail when particle dies.
- `Texture Mode` — `Stretch`, `Tile`, `Distribute Per Segment`, `Repeat Per Segment`.
- `Size Affects Width`, `Size Affects Lifetime`, `Inherit Particle Color`, `Color over Lifetime`, `Width over Trail`, `Color over Trail`, `Generate Lighting Data`, `Shadow Bias`.
- Trails need a separate material on `ParticleSystemRenderer.trailMaterial`.

## Custom Data

- Two streams (`Custom1`, `Custom2`) of up to 4 floats each. Author per-particle data to feed a custom shader's `TEXCOORD0.zw` / `TEXCOORD1` (when configured in `Renderer.Custom Vertex Streams`).

## Renderer (`ParticleSystemRenderer`)

- `Render Mode`:
  - `Billboard` — always face camera.
  - `Stretched Billboard` — elongate along velocity. Tune `Camera Scale`, `Speed Scale`, `Length Scale`.
  - `Horizontal Billboard` — locked to XZ plane (ground decals).
  - `Vertical Billboard` — Y-up, rotates around Y only.
  - `Mesh` — render assigned mesh per particle (debris, leaves). Enable `GPU Instancing` if material supports it.
  - `None` — disable rendering (use Trails or Lights only).
- `Normal Direction` — billboard normal blend between view and surface.
- `Material` — main particle material; `Trail Material` for the Trails module.
- `Sort Mode` — `None`, `By Distance`, `Oldest in Front`, `Youngest in Front`.
- `Sorting Fudge` — bias to push the entire system in front of / behind other transparents.
- `Min/Max Particle Size` — clamp on screen.
- `Render Alignment` — `View`, `World`, `Local`, `Facing`, `Velocity`. Choose deliberately when stretched or in 2D.
- `Pivot` — rotation pivot offset per particle.
- `Visualize Pivot` — editor-only.
- `Masking` — interaction with Sprite Masks (2D).
- `Custom Vertex Streams` — wire Custom Data into shader inputs.
- `Cast Shadows`, `Receive Shadows`, `Motion Vectors`, `Sorting Layer ID`, `Order in Layer` — standard renderer fields.

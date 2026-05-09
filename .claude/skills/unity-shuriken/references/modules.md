# Shuriken module reference

Field-level detail per `ParticleSystem` sub-module. Names match the inspector and the `ParticleSystem.*Module` C# API.

## Main (`ParticleSystem.MainModule`)

- `Duration` — run length (s); looping resets each cycle.
- `Looping` — Off = one-shot.
- `Prewarm` — meaningful only with `Looping`; system starts as if it ran one full Duration.
- `Start Delay` — seconds before first emission.
- `Start Lifetime` — per-particle lifespan. Curve / random-between-two for variance.
- `Start Speed` — initial speed along Shape's emit direction.
- `3D Start Size` / `Start Size` — initial scale (xyz or scalar).
- `3D Start Rotation` / `Start Rotation` — initial orientation.
- `Flip Rotation` — fraction spinning opposite.
- `Start Color` — initial tint, multiplied with Color over Lifetime.
- `Gravity Modifier` — multiplier on `Physics.gravity` per particle. Negative = rises (smoke).
- `Simulation Space` — `Local` / `World` / `Custom`.
- `Simulation Speed` — playback rate scalar.
- `Delta Time` — `Scaled` / `Unscaled`. Unscaled for UI/menu.
- `Scaling Mode` — `Hierarchy` / `Local` / `Shape`.
- `Play On Awake` — disable for pooled/triggered.
- `Emitter Velocity Mode` — `Transform` vs `Rigidbody`. `Rigidbody` correct with `Inherit Velocity` on physics-driven emitter.
- `Max Particles` — hard cap; emission stops when reached.
- `Auto Random Seed` — off + fixed `Random Seed` = deterministic playback.
- `Stop Action` — `None` / `Disable` / `Destroy` / `Callback` (fires `OnParticleSystemStopped`).
- `Culling Mode` — `Automatic` / `Pause and Catch-up` / `Pause` / `Always Simulate`. `Pause` offscreen saves CPU; `Always Simulate` keeps evolving while culled.
- `Ring Buffer Mode` — recycle oldest particles instead of waiting for death. Endless ribbons.

## Emission (`ParticleSystem.EmissionModule`)

- `Rate over Time` — particles/sec (curve/random).
- `Rate over Distance` — particles per world-unit moved by emitter Transform. For trails — zero output when stationary.
- `Bursts` — list of `(time, count, cycles, interval, probability)`. Multiple bursts compose for layered explosions.

## Shape (`ParticleSystem.ShapeModule`)

- `Shape` — Sphere / Hemisphere / Cone / Donut / Box / Mesh / MeshRenderer / SkinnedMeshRenderer / Sprite / SpriteRenderer / Circle / Edge / Rectangle.
- `Angle` (Cone) — half-angle.
- `Radius`, `Radius Thickness` — shell vs filled volume; thickness 0 = surface only.
- `Arc`, `Arc Mode` (Random / Loop / Ping-Pong / Burst-Spread), `Arc Spread`, `Arc Speed` — partial circles or sweeping emitters.
- `Length` (Cone) — used by `ConeVolume` to emit inside a frustum.
- `Position`, `Rotation`, `Scale` — local offset/orientation/scale.
- `Align to Direction` — rotate each particle to match initial velocity (stretched debris).
- `Randomize Direction`, `Spherize Direction`, `Randomize Position` — soften deterministic emission.
- `Texture` — sample emission color/alpha from a 2D texture (mask to logo/silhouette).

## Velocity over Lifetime, Limit Velocity, Inherit Velocity, Force over Lifetime

- `Velocity over Lifetime` — additive velocity in `Local` / `World` / `Custom`; orbital fields rotate around emitter.
- `Limit Velocity over Lifetime` — speed cap with optional `Dampen`; `Drag` applies per-particle drag, accounting for velocity by size/scale.
- `Inherit Velocity` — pull emitter motion into particles. `Mode = Initial` (one-time) vs `Current` (continuous). Pair with `Main.Emitter Velocity Mode`.
- `Force over Lifetime` — constant force (wind, draft) in chosen space.

## Color and size

- `Color over Lifetime` — gradient by age. End at alpha 0.
- `Color by Speed` — color as function of speed. Define `Speed Range`.
- `Size over Lifetime` — curve. Smoke: start small, grow, fade.
- `Size by Speed` — size as function of speed (stretched motion-blur fakes).

## Rotation

- `Rotation over Lifetime` — angular velocity per axis (degrees/sec).
- `Rotation by Speed` — angular velocity as function of speed.

## External Forces

- `Multiplier` on global Wind Zones.
- `Influence Filter` — `Layer Mask` or explicit `List` of `ParticleSystemForceField`s. Use `List` to gate fields.

## Noise

- `Strength`, `Frequency`, `Scroll Speed` — turbulence look.
- `Damping` — high frequencies dissipate as strength rises.
- `Octaves`, `Octave Multiplier`, `Octave Scale` — fractal complexity.
- `Quality` — `Low` (1D) / `Medium` (2D) / `High` (3D). Higher = more cost.
- `Remap` — reshape noise output curve.
- `Position Amount`, `Rotation Amount`, `Size Amount` — apply noise per channel.

## Collision (`ParticleSystem.CollisionModule`)

- `Type` — `Planes` (cheap, manual planes via Transforms) or `World` (per-particle physics queries).
- `Mode` — `3D` or `2D` (Physics2D).
- `Dampen`, `Bounce` — energy loss / restitution on hit.
- `Lifetime Loss` — fraction of remaining lifetime to remove on each hit.
- `Min Kill Speed`, `Max Kill Speed` — kill particles outside band on collision.
- `Radius Scale` — particle collision radius multiplier.
- `Collides With` — physics layer mask.
- `Quality` — `High` / `Medium (Static Colliders)` / `Low`. Lower quality = larger voxel size, fewer queries.
- `Voxel Size` — coarse spatial bin for medium/low.
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

- Up to N collider references; events fired for `Inside` / `Outside` / `Enter` / `Exit` per collider.
- Each event: `Callback`, `Kill`, `Ignore`.
- Receiver implements `OnParticleTrigger()` and reads via `ps.GetTriggerParticles(ParticleSystemTriggerEventType.*, list)`.

## Sub Emitters (`ParticleSystem.SubEmittersModule`)

- List entries: `(particleSystem, type, properties, emitProbability)` where `type` is `Birth` / `Collision` / `Death` / `Trigger` / `Manual`.
- `Properties` controls which properties (Color, Size, Rotation, Lifetime, Duration) the parent passes to the child.
- Children must be ParticleSystems on child GameObjects; reference via inspector or runtime `subEmitters.SetSubEmitterSystem(index, ps)`.

## Texture Sheet Animation

- `Mode` — `Grid` (rows × cols) or `Sprites` (list of Sprite assets, can vary in size).
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
- `Ratio` — fraction with trails.
- `Lifetime` — trail length, scaled by particle lifetime if `Inherit Particle Color` etc. set.
- `Minimum Vertex Distance` — segment density.
- `World Space` — bake trail vertices in world space (helps fast-moving emitters).
- `Die With Particles` — drop trail when particle dies.
- `Texture Mode` — `Stretch` / `Tile` / `Distribute Per Segment` / `Repeat Per Segment`.
- `Size Affects Width`, `Size Affects Lifetime`, `Inherit Particle Color`, `Color over Lifetime`, `Width over Trail`, `Color over Trail`, `Generate Lighting Data`, `Shadow Bias`.
- Trails need a separate material on `ParticleSystemRenderer.trailMaterial`.

## Custom Data

Two streams (`Custom1`, `Custom2`), up to 4 floats each. Author per-particle data to feed a custom shader's `TEXCOORD0.zw` / `TEXCOORD1` (when configured in `Renderer.Custom Vertex Streams`).

## Renderer (`ParticleSystemRenderer`)

- `Render Mode`:
  - `Billboard` — face camera.
  - `Stretched Billboard` — elongate along velocity (`Camera Scale`, `Speed Scale`, `Length Scale`).
  - `Horizontal Billboard` — locked to XZ plane (ground decals).
  - `Vertical Billboard` — Y-up, rotates around Y only.
  - `Mesh` — assigned mesh per particle. Enable `GPU Instancing` when supported.
  - `None` — disable rendering (Trails or Lights only).
- `Normal Direction` — billboard normal blend between view and surface.
- `Material` — main; `Trail Material` for Trails.
- `Sort Mode` — `None` / `By Distance` / `Oldest in Front` / `Youngest in Front`.
- `Sorting Fudge` — bias system in front of/behind other transparents.
- `Min/Max Particle Size` — screen-space clamp.
- `Render Alignment` — `View` / `World` / `Local` / `Facing` / `Velocity`. Choose deliberately when stretched or 2D.
- `Pivot` — per-particle rotation pivot offset.
- `Visualize Pivot` — editor-only.
- `Masking` — Sprite Mask interaction (2D).
- `Custom Vertex Streams` — wire Custom Data into shader inputs.
- `Cast Shadows`, `Receive Shadows`, `Motion Vectors`, `Sorting Layer ID`, `Order in Layer` — standard renderer fields.

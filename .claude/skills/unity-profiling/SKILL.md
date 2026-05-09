---
name: unity-profiling
description: 'Use when measuring or optimizing Unity performance through Unity MCP — Unity Profiler, Profiler window, frame debugger, deep profile, profiler markers, ProfilerMarker, BeginSample, EndSample, GC.Alloc, allocations, memory profiler, Memory Profiler package, hierarchy view, timeline view, callstack, frame timing, FPS, MonoBehaviour callbacks, render passes, Player vs Editor profiler, remote profiler, attach to player, Frame Time, Profile Analyzer, performance regression. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Reach for this skill any time you are diagnosing frame spikes, GC churn, draw-call bloat, memory leaks, or general "the game feels slow" reports. The Profiler is THE source of truth for performance. An Editor profile is a ballpark; the truth is a Development Build profile on the lowest-supported target device.

## Profiler windows

Open `Window > Analysis > Profiler`. The top strip is a row of modules; the bottom pane is the per-frame detail.

- Hierarchy view (default in CPU Usage): tree of method calls per frame. Sort by Self ms, Total ms, GC Alloc, Calls. Click a row to see the callstack and per-marker children.
- Timeline view: visual swimlane of the main thread and worker threads. Easiest place to spot frame spikes, waiting on render thread, and thread contention.
- Raw Hierarchy: like Hierarchy but without merging samples — useful when one method shows up in many call paths.

Use Hierarchy to answer "what is expensive?" and Timeline to answer "where in the frame is the spike?"

## Profiler modules

- CPU Usage: scripts, physics, render, animation breakdown. Most time spent here.
- GPU Usage: per-pass GPU time. Less reliable in Editor; trustworthy on Player.
- Rendering: draw calls, batches, SetPass calls, triangles, vertices.
- Memory: total reserved, allocated, Mono heap, native, GC. Use the Memory Profiler package for object-graph snapshots.
- Physics / Physics 2D: contact count, solver iterations, kinematic vs dynamic body count.
- UI: canvas batching cost, Graphic dirties, layout rebuilds.
- Audio / Video / Network / Global Illumination: usually trivial; check when symptoms point there.

## Custom markers

Wrap any code path you want to measure:

```csharp
using Unity.Profiling;

static readonly ProfilerMarker s_aiUpdate = new ProfilerMarker("MyGame.AI.Update");

void Update() {
    using (s_aiUpdate.Auto()) {
        // expensive code
    }
}
```

Older API still works:

```csharp
Profiler.BeginSample("MyGame.Pathfinder.FindPath");
// ...
Profiler.EndSample();
```

Markers show up in Hierarchy and Timeline, survive IL2CPP stripping (where method names may differ), and let you isolate "my code" from "Unity engine code".

## Deep Profile

Toggle Deep Profile in the Profiler toolbar. Records every method call, including ones without explicit markers. Massive perf cost — frame time inflates 5-20x. Use briefly to find:

- Hidden allocations in untracked methods.
- Unmarked hot spots ("which of these 40 helpers is the slow one?").
- The full call graph leading to a known-expensive marker.

Never ship Deep Profile enabled. Don't trust absolute numbers in a deep profile — only relative comparisons within the same capture.

## Memory Profiler

Install `com.unity.memoryprofiler` via the package manager. Window > Analysis > Memory Profiler.

- Capture a snapshot at a known-good baseline (main menu, just-loaded level).
- Capture another after suspect activity (after several scene reloads).
- Diff the two snapshots — objects retained that should have been freed are leaks.
- Tree view shows the managed heap object graph; "All Tracked Memory" view shows native vs managed vs GFX.

Common findings: textures retained by stale references, scriptable objects pinned by static fields, event subscriptions never unsubscribed.

## Frame Debugger

`Window > Analysis > Frame Debugger`. Pause and step through every draw call in the current frame. Critical for diagnosing:

- Extra render passes (post-process bloom hidden cost, per-camera Volume Mask issues).
- Transparent overdraw — count overlapping translucent quads.
- Shadow pass cost.
- Unintended camera stack overlays.

Cross-link unity-urp for renderer-feature setup that often shows up here.

## Profile Analyzer

Install `com.unity.performance.profile-analyzer`. Compares two profile captures (e.g. before/after an optimization). Bar chart of marker time deltas and frame distribution. Use it to prove a fix actually moved the needle and to catch regressions.

## Profiling builds

Editor profile inflates everything; numbers from the Editor are not shipping numbers. For real numbers:

- Player Settings: Development Build + Autoconnect Profiler.
- Build to target device.
- Launch the Player. The Profiler picks it up via the Active Profiler dropdown.
- For mobile: USB tethering or local Wi-Fi; on iOS make sure the device and Editor share a network.

Cross-link unity-build for build settings discipline.

## Standalone Profiler

Launch the Profiler before the game and let it survive Editor restarts. `Window > Analysis > Profiler (Standalone Process)`. Connects to a running Player via the Active Profiler dropdown. Useful for long sessions or when the Editor itself is the thing you are profiling.

## Common patterns

- Find GC allocations: Hierarchy view, sort by GC Alloc descending. Common offenders: string concat in `Update`, LINQ on hot paths, `foreach` on `List<T>` in old Mono (fixed in modern .NET), boxing struct -> object, `Object.FindAnyObjectByType<T>()` per frame, `GetComponent<T>` per frame, lambda closures capturing locals.
- Render bottleneck: Frame Debugger; count SetPass calls (target <30 mobile, <100 desktop). High batches = lots of materials or broken SRP Batcher compatibility (cross-link unity-shaders).
- UI cost: Profiler UI module shows `Canvas.SendWillRenderCanvases` and `Canvas.BuildBatch` time. Move dynamic widgets to a nested Canvas so the static parent does not rebuild (cross-link unity-ugui).
- Physics cost: Profiler Physics module; reduce solver iterations, increase `Time.fixedDeltaTime` if simulation can tolerate it, simplify colliders, prefer primitives over mesh colliders (cross-link unity-physics).
- Audio cost: usually trivial unless using effects. Profiler Audio module. Cross-link unity-audio.
- Scripting cost: ProfilerMarker your own systems, then Hierarchy view to rank them. Optimize the top 1-2; ignore the rest until they matter.

## GC budget

Concrete targets, not "near zero". Measure in the Profiler Hierarchy view's `GC Alloc` column on a Development Build.

| Budget | GC per frame, per system | Action |
|---|---|---|
| Shipping target | 0 B (steady-state gameplay loop) | this is the bar |
| Yellow flag | <1 KB / frame | acceptable on desktop, audit on mobile |
| Red flag | >4 KB / frame | must fix before ship — guarantees Gen0 churn and hitches |

Common offenders and rough costs:

- `string` concatenation / `$"interp {x}"`: varies by length, always allocs. Use `StringBuilder` (cached) or pre-format static strings.
- `foreach` on `List<T>`: zero in modern Unity (.NET 4.x / Mono / IL2CPP). Older Mono allocated an enumerator — most Unity 6 code is fine.
- Boxing struct → object: ~24 B per box. Common with `object`-typed event payloads, `Dictionary<TKey, object>`, `string.Format` of value types.
- `new WaitForSeconds(t)`: 16 B every call. Cache as `static readonly`.
- Lambda capturing locals (`() => use(local)`): ~40 B closure object + delegate. `WaitUntil(() => cond)` allocates this every coroutine entry.
- `Mathf.Approximately(a, b)`: fine, no alloc.
- `LayerMask.NameToLayer("Enemy")` per call: probes a managed string→int dictionary every time. Cache the int once.

Canonical caching patterns:

```csharp
static readonly int s_speedHash      = Animator.StringToHash("Speed");
static readonly int s_baseColorID    = Shader.PropertyToID("_BaseColor");
static readonly WaitForSeconds s_w1  = new WaitForSeconds(1f);
static readonly int s_enemyMask      = LayerMask.GetMask("Enemy");
static readonly StringBuilder s_sb   = new StringBuilder(256);
```

`Animator.StringToHash` and `Shader.PropertyToID` are deterministic and cheap once cached — calling them in a `[SerializeField]` field initializer or a `static` field is the canonical shape. `LayerMask.GetMask(...)` returns the bitmask; cache the int and reuse for `Physics.Raycast` mask params.

## Gotchas

- Editor adds significant overhead. The Editor profile is for relative comparison and finding obvious offenders, not for "we hit 60fps" claims.
- "VSync" / "WaitForTargetFPS" appears as time spent — that is the Editor or Player waiting for refresh, not real cost. Disable VSync in the Game view to see actual frame budget.
- Deep Profile inflates frame time 5-20x; don't trust absolute numbers.
- `GC.Alloc` spikes are almost always script issues — string allocations, closures, collection growth, boxing. Strict no-GC budget for mobile means hunt every allocation.
- Profiler buffer caps at ~4MB by default; long sessions wrap. Increase Profiler buffer size in the toolbar if you need longer captures.
- IL2CPP method names may differ slightly from Editor (inlined / stripped). Custom ProfilerMarkers are the workaround — they always survive.
- Autoconnect Profiler relies on multicast discovery; on locked-down networks you may need to enter the Player's IP manually.
- The Editor's Game-view rendering can dominate frames if multiple Scene/Game windows are open — close extra views before profiling.

## Verification

- Capture a baseline profile before optimization; capture again after; diff via Profile Analyzer.
- Frame time consistently under target (16.6ms for 60fps, 33.3ms for 30fps) on lowest-supported hardware.
- GC.Alloc per frame meets the GC budget table — 0 B per system in steady-state gameplay; <1 KB yellow flag; >4 KB blocks ship.
- SetPass call count under platform budget (Frame Debugger or Rendering module).
- Editor console clean of "ParticleSystem update is taking too long", "Physics warning", "Canvas rebuild" runtime warnings.
- For optimizations claimed: a Profile Analyzer screenshot or numbers showing the named marker dropped.

## Cross-links

- unity-build — Development Build, Autoconnect Profiler, target-device builds.
- unity-shaders — SRP Batcher compatibility, draw call reduction.
- unity-ugui — canvas split strategy and rebuild costs.
- unity-physics — solver tuning and collider choice.
- unity-audio — audio module costs and effect chains.
- unity-best-practices — read-console and batch-related-calls discipline applies during profiling.

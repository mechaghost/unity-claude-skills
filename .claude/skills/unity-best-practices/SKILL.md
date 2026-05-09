---
name: unity-best-practices
description: 'Use ALWAYS before any Unity 6+ MCP work. Preflight: read console, detect Editor/project, render pipeline, input mode, physics dimension, batch when possible, respect Undo, avoid Play mode unless asked, verify 3D visually. Triggers: Unity Editor, GameObject, Component, MonoBehaviour, ScriptableObject, scene, prefab, asset, package, script, build, Project Settings, URP, HDRP, Built-in, asmdef, manifest.json, Play mode, Edit mode.'
---

Cross-cutting rules. Loaded with every domain skill.

## Tool-name policy

Skills name **capabilities**, not MCP tools. Unity MCP tool surfaces churn (`com.unity.ai.assistant`, CoplayDev, IvanMurzak, AnkleBreaker — all different catalogs and naming conventions, all versioned). Map each capability to whatever the connected server returns from `tools/list`.

Fallback ladder when a capability is missing:

1. Drive the equivalent Editor menu item.
2. Reflect over `UnityEditor` / `UnityEngine` directly.
3. Generate a small Editor script and let Unity run it.
4. Ask the user.

Same applies to batching — degrade to per-call when no batch endpoint exists.

## Preflight (run before any mutation)

Batch into one round-trip if supported, else sequential.

1. **Read the Editor console.** Red errors halt compilation; until cleared, edits no-op silently and tools report success on stale state.
2. **Pick the active Editor.** If multiple are running, target the right project before mutating.
3. **Refresh the AssetDatabase** if there were out-of-band file edits.
4. **Detect render pipeline** (see below).
5. **Detect input handling** (Old / New / Both). Unity 6 final state is New.
6. **Detect physics dimension.** 3D `Rigidbody` and 2D `Rigidbody2D` are separate worlds.
7. **Note Unity version** via `Application.unityVersion`. Targets **Unity 6 / 6000.x**. Older majors (2022 LTS, 2023.x) — warn user; APIs differ (e.g. `Rigidbody.velocity` is the deprecated form of `linearVelocity`) and skills are not validated against pre-6.

When handing off to a domain skill, print a one-line paradigm summary.

## Detect the project paradigm

Skill set assumes **Unity 6+, URP, new Input System**. Built-in / HDRP / legacy `Input` are out of scope (migration only). Warn before proceeding on unsupported paradigms.

- **Render pipeline** — read `UnityEngine.Rendering.GraphicsSettings.defaultRenderPipeline`.
  - `null` → Built-in. **Out of scope.** Recommend installing URP and running `Edit > Rendering > Materials > Convert All Built-in Materials to URP`. See `unity-urp`.
  - Type contains `Universal` → URP. Proceed.
  - Type contains `HD` → HDRP. **Out of scope.** Recommend switching to URP or a different toolchain.
  - Pink materials at runtime almost always = pipeline mismatch.
- **Input handling** — Project Settings → Player → Active Input Handling.
  - "New" → proceed (`unity-input-system`).
  - "Both" → migration only. Search for `Input.GetKey/GetAxis/GetButton/mousePosition/touchCount`, port, then switch to "New".
  - "Old" → out of scope as primary. Migration guidance only.
- **Physics dimension** — query the active scene for `Rigidbody` and `Rigidbody2D`. Mixing both is a red flag. See `unity-physics`.

## Rotation skill routing

Pick by the component holding the visual:

- `MeshRenderer` or bare Transform → `unity-3d-rotation`
- `SpriteRenderer` or `Rigidbody2D` → `unity-2d-rotation`
- `RectTransform` under Canvas → `unity-ugui-rotation`
- General Canvas UI work (anchors, layout, sorting, masks) → `unity-ugui`

## Capabilities a Unity MCP server should expose

Match each to the server's actual tool — these are roles, not names.

- **Scene/hierarchy:** create / mutate / delete GameObjects, add and configure components, query hierarchy, enter/exit/save Prefab Mode, load/unload scenes.
- **Editor/project:** read+write Project Settings and PlayerSettings, install/remove packages, refresh AssetDatabase, run Editor menu items, switch active Editor.
- **Assets:** create / import / move / delete materials, textures, shaders, ScriptableObjects, prefabs, scenes; edit asset properties.
- **Code:** create scripts, apply text edits, validate compilation.
- **Diagnostics:** read console, reflect over loaded types, query Unity docs, capture screenshots, profiler snapshots.
- **Tests:** run EditMode and PlayMode tests.
- **Throughput:** batch calls into one round-trip (server-specific).

When missing, use the fallback ladder under Tool-name policy.

## Read the console

The Editor console is the truth signal. Tools often report success while Unity errored.

- Read after every batch.
- Filter for: `Error`, `Exception`, `NullReferenceException`, `shader compile error`, `Layout is being rebuilt`, `InputSystem`, `SRP Batcher`, `Recompile required`, `Missing Prefab`.
- A red error stops compilation — until cleared, scripts don't recompile and many tools no-op.
- Missing-component / missing-script warnings = prior edit broke the scene.

## Batching

When ≥5 calls are knowable in advance (building a hierarchy, configuring a Volume profile, wiring a UGUI panel), group them into one round-trip if supported, then read the console once. Reported speedups for batched servers: 10–100×. Without batching, sequence them and still read once at the end.

## Respect Undo

Anything user-undoable must go through Undo:

- `Undo.RecordObject(target, "Description")` — value changes
- `Undo.RegisterCreatedObjectUndo` — new GameObjects/assets
- `Undo.DestroyObjectImmediate` — not `Object.DestroyImmediate`
- `Undo.AddComponent<T>(go)` — not `go.AddComponent<T>()`

Server-managed mutations usually handle this. Custom Editor scripts must do it explicitly.

## Stay out of Play mode

- Play mode wipes Edit-mode changes unless serialized.
- Use it ONLY for runtime testing the user asked for, or for PlayMode tests.
- Edit mode covers: component setup, screenshots, scene building, serialization, asset import, prefab work.
- Need runtime verification? Ask first.

## Asset paths and folders

- `Assets/` — version-controlled source. Anything Unity tracks lives here.
- `Library/` — cache, regenerated. Never check in. OK as temp screenshot output.
- `Packages/` — package-manager state. Edit `manifest.json` only via the package capability.
- `ProjectSettings/` — serialized settings (Graphics, Input, Quality, Tags, Layers). Prefer the editor.
- `.meta` — sibling-of-asset GUID. Never delete a `.meta` without the asset; never hand-edit a GUID.
- Forward slashes in asset paths.

## Layers, tags, naming

- 32 layers max. Layer 0 is Default for static world geometry.
- Tags don't compose — prefer components or layer membership for queries.
- Name GameObjects by role (`PlayerSpawn`, not `SpawnPoint (1)`). Strip `(Clone)` suffix when it matters for name lookups.

## Prefab over instance

- Edit the prefab asset, not a scene instance — overrides drift, multi-scene projects diverge.
- Apply or revert overrides explicitly.
- Variants for shared structure with role tweaks (`BasicEnemy` → `ArmoredEnemy`).
- Keep nesting shallow — deep nesting hurts merges.

## Verify visually

A success return is not a visual confirmation.

- Any 3D change → `unity-3d-verification` (4-shot orthographic).
- 2D content → one Game-view screenshot.
- UI → reference resolution + one off-target resolution (catches anchor breakage).
- Read the PNG. If you can't see what you intended, the change failed.

## Domain skill router

Full router: `references/router.md`.

| Task | Skill |
| --- | --- |
| Always-on primer + 3D verification | unity-best-practices, unity-3d-verification |
| Rendering / shaders / lighting / particles / VFX | unity-urp, unity-shaders, unity-lighting, unity-shuriken, unity-vfx-graph, unity-animation, unity-cinemachine |
| Gameplay (rotation / physics / navmesh) | unity-3d-rotation, unity-2d-rotation, unity-ugui-rotation, unity-physics, unity-navmesh |
| Input + UI + audio | unity-input-system, unity-ugui, unity-audio |
| Project hygiene + shipping | unity-scenes, unity-persistence, unity-build, unity-store-shipping-pipeline, unity-addressables, unity-asmdef, unity-vcs, unity-tests, unity-profiling, unity-ci |
| Live-ops + compliance | unity-iap, unity-ads-mediation, unity-consent-att-gdpr, unity-privacy-manifests, unity-crash-reporting, unity-analytics-events, unity-remote-config-flags, unity-ab-testing, unity-auth-account-linking, unity-cloud-save-conflict, unity-push-local-notifications, unity-localization, unity-anti-cheat-iap-fraud, unity-support-and-bug-capture |
| Day-one indie patterns | unity-patterns |

## Cross-cutting gotchas

- **Pink material** = pipeline/shader mismatch. Run URP material converter. See `unity-shaders`, `unity-urp`.
- **2D and 3D physics are separate worlds.** `Rigidbody` won't collide with `Collider2D`. Pick one per scene.
- **Legacy `Input.GetKey` returns nothing** under "Input System Package (New)". Don't mix.
- **Struct accessor mutation = CS1612.** Properties returning structs (`ParticleSystem.main/emission/shape`, AudioMixer params, some Volume helpers) must be cached locally before assignment: `var main = ps.main; main.startSpeed = 5f;` — direct `ps.main.startSpeed = 5f` is a compile error. RectTransform is a class, not subject to this.
- **`Renderer.material` clones on first access**, breaking SRP Batcher and leaking. Use `sharedMaterial` for asset edits, `MaterialPropertyBlock` for per-instance values.
- **`ScreenCapture.CaptureScreenshot` is async.** For sync capture, render a `Camera` to a `RenderTexture` and read pixels.
- **GUIDs are stable across renames.** Rename freely. Never hand-edit `.meta`.
- **Static colliders moved at runtime** = static-tree rebuild = perf cliff. Add a kinematic Rigidbody.
- **UGUI layout cycles** ("Layout is being rebuilt during a layout rebuild") = `ContentSizeFitter` on a parent driven by a layout-sized child. Break the cycle.
- **Stripped shader keywords** = pink at runtime. Touch a sentinel material with the keyword in `Resources/`.
- **`.inputactions` / Shader Graph saves** bypass the text-edit cache. Refresh AssetDatabase after.
- **Hierarchy lookup by string in hot paths** is slow. Cache at startup. (Runtime code only — Editor tooling is fine.)

## When you don't know

1. Unity docs.
2. Reflect on the live type.
3. Search `Library/PackageCache/com.unity.<pkg>/`.
4. Ask the user. Don't guess.

## Failure protocol

Tool returned success but change is invisible:

1. Read the console — compile errors, missing refs, shader errors.
2. Refresh AssetDatabase — most common cause.
3. Re-query the target — confirm persistence.
4. For generated assets (Input Actions, Shader Graph, URP renderer features), reopen — auto-generated C# may be stale.
5. Visual change? Capture a screenshot. See `unity-3d-verification`.
6. Still wrong? Revert and report. Don't stack speculative fixes.

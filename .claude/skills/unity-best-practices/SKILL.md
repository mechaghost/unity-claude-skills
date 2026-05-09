---
name: unity-best-practices
description: 'Use ALWAYS at the start of ANY Unity work through Unity MCP — before reading, modifying, or creating anything in a Unity project. Foundational rules: detect render pipeline, read the console, prefer batch_execute, respect Undo, never enter Play mode unprompted, pick one paradigm (Input System, render pipeline, physics dimension), verify visually with screenshots after 3D changes. Trigger keywords — Unity, Unity MCP, Unity Editor, GameObject, Component, MonoBehaviour, ScriptableObject, scene, prefab, asset, package, build, render pipeline, URP, HDRP, Built-in, Project Settings, scripting, Assembly Definition, Library, Assets folder, Packages folder, Play mode, Edit mode, asmdef, manifest.json, .unityproj.'
---

This skill loads alongside any domain-specific Unity skill. It encodes the cross-cutting rules. Violate them and every other skill produces wrong results.

## Always do this first

Before any modification — including the very first read — run this preflight in order. Use `batch_execute` to fold these into one round-trip when possible.

1. `read_console` — surface existing errors and warnings. A red error halts compilation; until it clears, MCP-side script reloads no-op silently and many tools return `success: true` against stale state.
2. `set_active_instance` if more than one Unity Editor is open. Pick the project the user actually means.
3. `refresh_unity` if there have been out-of-band file edits since the last MCP call (anything written by `apply_text_edits`, `create_script`, or your shell). Without a refresh, the editor is reading stale assets.
4. Detect the render pipeline. See `## Detect the project paradigm`.
5. Detect the input handling mode (Old / New / Both). Unity 6+ final state is New only; Both is migration mode.
6. Detect the physics dimension in the active scene (3D Rigidbody vs 2D Rigidbody2D — they are separate worlds).
7. Note the Unity version via `unity_reflect` on `Application.unityVersion`. This skill set targets **Unity 6 / 6000.x**. If the project is on an older major version (2022 LTS, 2023.x, etc.), warn the user — APIs differ (e.g. `Rigidbody.velocity` is the deprecated form of Unity 6's `linearVelocity`) and the skill set is not validated against pre-6 versions.

When you hand off to a domain skill, print a one-line paradigm summary so the receiving skill doesn't redo the work.

## Rotation routing decision tree

Rotation work is split across four sibling skills because the underlying APIs and pivot semantics diverge. Pick one before authoring code:

- Rotating a `Transform` on a GameObject with a MeshRenderer (or a bare transform) → `unity-3d-rotation`.
- Rotating a `SpriteRenderer`, or a GameObject driven by a `Rigidbody2D` → `unity-2d-rotation`.
- Rotating a `RectTransform` under a Canvas → `unity-ugui-rotation`.
- Building or styling Canvas UI more broadly (anchors, layout, sorting, masks) — not just rotating it → `unity-ugui`.

When in doubt, identify the component type that holds the visual (`MeshRenderer`, `SpriteRenderer`, `RectTransform`) and pick the matching skill.

## MCP tools available

This skill set assumes the following Unity MCP tools are exposed by the connected server. Names are canonical; group is informational.

- GameObject / scene: `manage_gameobject`, `manage_components`, `manage_prefabs`, `manage_scene`, `find_gameobjects`
- Editor / project: `manage_editor`, `manage_packages`, `manage_asset`, `set_active_instance`, `refresh_unity`, `execute_menu_item`, `execute_custom_tool`
- Rendering: `manage_camera`, `manage_graphics`, `manage_material`, `manage_shader`, `manage_texture`
- Specialized: `manage_physics`, `manage_animation`, `manage_vfx`, `manage_ui`, `manage_probuilder`, `manage_scriptable_object`, `manage_build`, `manage_tools`, `manage_profiler`
- Code: `apply_text_edits`, `script_apply_edits`, `create_script`, `delete_script`, `validate_script`
- Diagnostics: `read_console`, `debug_request_context`, `unity_reflect`, `unity_docs`
- Tests: `run_tests`, `get_test_job`
- Misc: `get_sha`, `batch_execute`

If a tool fails or is unavailable on the connected MCP server, fall back to `execute_menu_item`, `unity_reflect`, or generated scripts via `create_script`. Different MCP server forks expose different subsets.

## Detect the project paradigm

Run these checks once per session and cache the answer in your working notes.

> **Skill-set policy.** This skill set assumes **Unity 6+ / 6000.x**, **URP**, and the **new Input System** as the final project state. Built-in / HDRP and legacy `Input.GetKey/GetAxis` are out of scope except where explicitly called out as migration guidance. If detection finds the project on an unsupported paradigm, warn the user before proceeding.

- **Render pipeline** — `unity_reflect` on `UnityEngine.Rendering.GraphicsSettings.defaultRenderPipeline`.
  - `null` → Built-in. **Out of scope.** Warn the user that this skill set targets URP and recommend installing URP and running `Edit > Rendering > Materials > Convert All Built-in Materials to URP` before proceeding. See `unity-urp` for the migration steps.
  - type name contains `Universal` → URP. Proceed.
  - type name contains `HD` → HDRP. **Out of scope.** Warn the user that this skill set does not cover HDRP and recommend either switching the project to URP or using a different toolchain. Do not attempt HDRP-specific edits.
  Every shader, material, and particle decision hinges on this. Pink materials at runtime almost always mean a pipeline mismatch.
- **Input handling** — Project Settings → Player → Active Input Handling. Read via `manage_editor` or `unity_reflect` on `UnityEditor.PlayerSettings`.
  - "Input System Package (New)" → proceed; the `unity-input-system` skill applies.
  - "Both" → migration mode only. Proceed only for migration work, search for legacy `Input.GetKey/GetAxis/GetButton/mousePosition/touchCount` call sites, and finish by switching to "Input System Package (New)" once the legacy calls and old UI module are gone.
  - "Input Manager (Old)" → **out of scope** as the *primary* paradigm. Warn the user that this skill set assumes the new Input System; the only legacy support is migration guidance for code that calls `Input.GetKey/GetAxis/GetButton/mousePosition/touchCount`. Recommend switching Active Input Handling to "Both" only for a bounded migration, then to "Input System Package (New)" as the final state.
- **Physics dimension** — `find_gameobjects` with type filter for `Rigidbody` and again for `Rigidbody2D`. A scene mixing both is a red flag worth surfacing to the user. Cross-link `unity-physics`.

## Read the console

`read_console` is your primary truth signal. Many `manage_*` tools report tool-level success while the underlying Unity operation produced an error.

- Read after every batch of mutations.
- Filter for: `Error`, `Exception`, `NullReferenceException`, `shader compile error`, `Layout is being rebuilt`, `InputSystem`, `SRP Batcher`, `Recompile required`, `Missing Prefab`.
- A red error halts compilation. Until cleared, scripts do not recompile and many tools no-op silently.
- Warnings about missing components, missing scripts, and missing references are not noise — they usually mean a previous edit left the scene in a broken state.

## Use batch_execute

When the next 5 or more MCP calls are knowable in advance — building a hierarchy, configuring a Volume profile, attaching half a dozen components, wiring a UGUI panel — wrap them in `batch_execute`. The justinpbarnett docs claim 10–100x speedup. One round-trip beats fifty. Lay the calls out as a list, run them as a batch, then `read_console` once at the end.

## Respect Undo

Anything the user might want to undo from the Unity Editor MUST go through the appropriate Undo API before mutation:

- `Undo.RecordObject(target, "Description")` for value changes
- `Undo.RegisterCreatedObjectUndo` for new GameObjects and assets
- `Undo.DestroyObjectImmediate` instead of `Object.DestroyImmediate`
- `Undo.AddComponent<T>(go)` instead of `go.AddComponent<T>()`

Most `manage_*` tools handle this internally. When you write custom Editor scripts via `create_script`, do it explicitly. Without Undo, the user loses Cmd-Z and is rightly annoyed.

## Stay out of Play mode (unless asked)

- Entering Play mode wipes scene-level edits made in Edit mode unless they were serialized first.
- Many MCP servers expose a Play-mode toggle. Use it ONLY when the user explicitly asks for runtime testing, or when running Play-mode tests via `run_tests` / `get_test_job`.
- Edit mode is enough for: validating component setup, capturing screenshots, building scenes, verifying serialized data, asset import, prefab work.
- If you need runtime behavior verification, ask first.

## Asset paths and folders

- `Assets/` — source content under version control. Anything Unity should track and import lives here.
- `Library/` — cache, regenerated by Unity. Never check in. Acceptable as a temp output target for verification screenshots that should not pollute `Assets/`.
- `Packages/` — package manager state. Edit `Packages/manifest.json` only via `manage_packages`, never by hand.
- `ProjectSettings/` — serialized project settings (Graphics, Input, Quality, Tags, Layers). Hand-edit with care; prefer the editor or `manage_editor`.
- `.meta` files — every asset has a sibling `.meta` carrying a stable GUID. NEVER delete a `.meta` without deleting the matching asset. NEVER hand-edit a GUID — it breaks references everywhere in the project.
- Use forward slashes in asset paths. Unity normalizes; many tools do not.

## Layers, tags, and naming

- 32 layers maximum. Layer 0 (Default) is for static world geometry. Conventional layout: Default, TransparentFX, Ignore Raycast, Water, UI, plus project-specific (Player, Enemy, Projectile, Trigger).
- Tags are loose strings, useful for one-off identification. Prefer components or layer membership for queries — tags do not compose.
- Name GameObjects by role, not by asset (`PlayerSpawn`, not `SpawnPoint (1)`). Strip Unity's `(Clone)` suffix on instantiation when it matters for `find_gameobjects` lookups.

## Prefab over instance edits

- When editing a recurring entity, edit the PREFAB ASSET, not a scene instance. Instance edits create overrides that drift; multi-scene projects diverge silently.
- Use `manage_prefabs` to enter Prefab Mode, edit, save. Apply or revert overrides explicitly — do not let them accumulate.
- Use Prefab Variants for shared structure with role-specific tweaks (`BasicEnemy` → `ArmoredEnemy` variant).
- Nested prefabs are powerful but increase merge friction. Keep nesting shallow.

## Verify visually

DO NOT declare a 3D task done based on an MCP success return. The MCP layer reports tool execution, not visual correctness.

- After ANY 3D change, hand off to `unity-3d-verification` for the 4-shot orthographic capture (left, right, top, bottom).
- For 2D content, take one Game-view screenshot from the active 2D camera.
- For UI, capture at the project's reference resolution AND at one off-target resolution to catch anchor breakage.
- Read the captured PNG. If you cannot see what you intended, the change failed regardless of what the tool returned.

## Domain skill router

For most prompts, hand off to the matching skill below. Full 42-skill router with categories: see `references/router.md`.

| Common task | Skill |
| --- | --- |
| Always-on primer (this skill) + 4-shot 3D verification | unity-best-practices, unity-3d-verification |
| Rendering / shaders / lighting / particles / VFX | unity-urp, unity-shaders, unity-lighting, unity-shuriken, unity-vfx-graph, unity-animation, unity-cinemachine |
| Gameplay (rotation / physics / navmesh) | unity-3d-rotation, unity-2d-rotation, unity-ugui-rotation, unity-physics, unity-navmesh |
| Input + UI + audio | unity-input-system, unity-ugui, unity-audio |
| Project hygiene + shipping | unity-scenes, unity-persistence, unity-build, unity-store-shipping-pipeline, unity-addressables, unity-asmdef, unity-vcs, unity-tests, unity-profiling, unity-ci |
| Live-ops monetization + compliance | unity-iap, unity-ads-mediation, unity-consent-att-gdpr, unity-privacy-manifests, unity-crash-reporting, unity-analytics-events, unity-remote-config-flags, unity-ab-testing, unity-auth-account-linking, unity-cloud-save-conflict, unity-push-local-notifications, unity-localization, unity-anti-cheat-iap-fraud, unity-support-and-bug-capture |
| Day-one indie patterns (pooling/singleton/SO events/FSM/pause/tweens) | unity-patterns |

## Common cross-cutting gotchas

The highest-impact traps surfaced once here so every domain skill does not have to repeat them.

- **Pink material** almost always means render-pipeline / shader mismatch. Run the URP material converter; see `unity-shaders` and `unity-urp`.
- **2D and 3D physics are separate worlds.** A `Rigidbody` will not collide with a `Collider2D`, and vice versa. Pick one per scene.
- **Legacy `Input.GetKey` returns nothing** if Active Input Handling is "Input System Package (New)". Switch paradigm or switch handler mode — do not mix without intent.
- **Struct accessor mutation is a compile error (CS1612).** Some Unity APIs expose properties that return *structs* holding handles into native data — most prominently `ParticleSystem` modules (`ps.main`, `ps.emission`, `ps.shape`, ...), Volume profile component getters (e.g. `volume.profile.TryGet<Bloom>(...)` returns by ref, but other helpers return by value), and AudioMixer parameter accessors. Writing `ps.main.startSpeed = 5f;` directly is a C# compile error: `CS1612 Cannot modify the return value of '...' because it is not a variable` — you cannot mutate fields on a struct returned from a property. Fix: store the returned struct in a local first; the local is a variable and the struct's writes propagate through to the underlying system. `var main = ps.main; main.startSpeed = 5f;`. (RectTransform is a class with class-typed property accessors and is NOT subject to this trap.)
- **`Renderer.material` clones the material** on first access, breaking SRP Batcher and creating leaks. Use `sharedMaterial` for asset edits and `MaterialPropertyBlock` for per-instance values.
- **`ScreenCapture.CaptureScreenshot` writes async** and may not exist when the next call reads it. For synchronous capture, render a `Camera` to a `RenderTexture` and read pixels directly.
- **GUIDs are stable across renames.** Rename freely. Do not hand-edit `.meta` files; references are by GUID, not by path.
- **Static colliders moved at runtime** trigger a static-collision-tree rebuild — performance cliff. If the collider needs to move, add a kinematic Rigidbody.
- **UGUI layout cycles** ("Layout is being rebuilt during a layout rebuild") usually mean a `ContentSizeFitter` on a parent that is also being driven by a layout-sized child. Break the cycle.
- **Shader keywords stripped at build time** appear pink at runtime. Touch a sentinel material with the keyword enabled in a Resources folder so the variant is included.
- **Saving inside `.inputactions` or Shader Graph editor** writes to the asset directly and may bypass the `apply_text_edits` cache. Call `refresh_unity` after out-of-band edits.
- **`find_gameobjects` by string in hot paths** is slow. Cache the reference at startup. (Applies to runtime code Claude writes, not Editor tooling.)

## When you don't know

In order:

1. `unity_docs` — official documentation page for the API in question.
2. `unity_reflect` — inspect the live type's fields and methods in the loaded assemblies. Ground truth for "does this property exist in this version".
3. `find_in_file` over `Library/PackageCache/com.unity.<pkg>/...` — package source is often clearer than docs and matches the exact version installed.
4. Ask the user. Do not guess.

## Failure protocol

When an MCP tool returns success but the change is not visible:

1. `read_console` immediately. Look for compile errors, missing references, shader errors.
2. `refresh_unity` to force re-import. Out-of-band edits are the most common cause of phantom success.
3. Re-query the target via `manage_gameobject` or `find_gameobjects` to confirm the change actually persisted on the object you expected.
4. For generated assets (Input Actions, Shader Graph, URP renderer features), re-open the asset in the editor — auto-generated C# may be stale.
5. For visual changes, capture a screenshot. The MCP success was about the tool call, not the rendered result. See `unity-3d-verification`.
6. If still wrong, revert the last change and report what you saw to the user before trying again. Do not stack speculative fixes.

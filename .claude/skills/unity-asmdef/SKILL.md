---
name: unity-asmdef
description: 'Use when partitioning Unity C# code into Assembly Definition files via Unity MCP — anything involving asmdef, assembly definition, .asmdef, asmref, version define, define constraint, auto-referenced, override references, precompiled assembly, plugin DLL, hot reload, compilation time, iteration time, circular dependency, EditorOnly assembly, test assembly. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

Assembly Definitions partition C# into separate DLLs so only the changed asmdef and dependents recompile. Below ~10 min cold compile this is iteration tax; above that it's the biggest productivity lever.

## When to use

- Cold compile creeps past 10–15 s and every script edit hits everything.
- A feature folder needs to compile without dragging in another team's code.
- Editor-only tooling has leaked `using UnityEditor;` into runtime scripts and Player build fails.
- Tests need their own assembly with NUnit + TestRunner refs.
- A third-party DLL is pulling conflicting versions of `Newtonsoft.Json`.
- A package upgrade requires `#if PACKAGE_X_GTE_2_0` gating.

If only a handful of scripts and compile is sub-second, don't pre-shard. Empty asmdefs cost more than they save.

## What asmdef does

Unity normally compiles `Assets/` into monolithic predefined assemblies (`Assembly-CSharp.dll`, etc.). One edit = full recompile.

An `.asmdef` (JSON, anywhere under `Assets/` or `Packages/`) tells Unity: "compile every `.cs` from this folder downward into its own DLL" with explicit references. Edit a leaf script, only that DLL + dependents recompile.

Sweet spot: 5–20 asmdefs for a mid-size project. Each adds ~50–200 ms cold-compile overhead, but warm iteration drops dramatically with a shallow graph.

## File anatomy

`Studio.Combat.asmdef`:

```json
{
  "name": "Studio.Combat",
  "rootNamespace": "Studio.Combat",
  "references": ["Studio.Core", "Unity.InputSystem"],
  "includePlatforms": [],
  "excludePlatforms": [],
  "allowUnsafeCode": false,
  "overrideReferences": false,
  "precompiledReferences": [],
  "autoReferenced": true,
  "defineConstraints": [],
  "versionDefines": [
    {
      "name": "com.unity.inputsystem",
      "expression": "1.4.0",
      "define": "INPUT_SYSTEM_1_4"
    }
  ],
  "noEngineReferences": false
}
```

- `name` — DLL name, unique. Convention: `Company.Feature` or `Company.Feature.Editor`.
- `rootNamespace` — default namespace for new C# scripts.
- `references` — names (or GUIDs) of asmdef dependencies. Explicit; no transitive sugar.
- `includePlatforms`/`excludePlatforms` — empty = all. `["Editor"]` for editor-only.
- `allowUnsafeCode` — enables `unsafe` blocks.
- `overrideReferences` — `true` stops predefined assemblies auto-referencing this one's DLLs; you control via `precompiledReferences`.
- `precompiledReferences` — third-party DLL filenames (`Newtonsoft.Json.dll`) under `Assets/Plugins/`.
- `autoReferenced` — default `true`; `Assembly-CSharp` references this asmdef automatically. `false` to force opt-in.
- `defineConstraints` — only compile if ALL listed scripting-define symbols are set.
- `versionDefines` — define a symbol when a referenced package's version satisfies the expression.
- `noEngineReferences` — `true` skips `UnityEngine.*` (rare; pure utility libs).

## Folder layout patterns

**Feature folders** (game projects):

```
Assets/_Project/
  Core/           Studio.Core.asmdef
  Combat/         Studio.Combat.asmdef
    Editor/       Studio.Combat.Editor.asmdef
    Tests/        Studio.Combat.Tests.asmdef
  Inventory/      Studio.Inventory.asmdef
  UI/             Studio.UI.asmdef
  Boot/           Studio.Boot.asmdef
```

**Layered architecture** (larger / service-oriented):

```
Assets/_Project/
  Core/           Studio.Core.asmdef          (no deps)
  Domain/         Studio.Domain.asmdef        (refs Core)
  Services/       Studio.Services.asmdef      (refs Core, Domain)
  Presentation/   Studio.Presentation.asmdef  (refs Domain, Services)
```

Direction one-way: `Core <- Domain <- Services <- Presentation`. No upward refs. If `Domain` needs to call back into `Presentation`, invert with an interface defined in `Domain` and implemented in `Presentation`.

`Editor/` folders are auto-editor-only ONLY without an asmdef. With asmdefs, add a separate Editor asmdef excluding runtime platforms.

## Editor / Runtime / Test split

Three asmdefs per feature:

`Studio.Combat.asmdef` (runtime):
```json
{ "name": "Studio.Combat", "references": ["Studio.Core"] }
```

`Studio.Combat.Editor.asmdef` (under `Combat/Editor/`):
```json
{
  "name": "Studio.Combat.Editor",
  "references": ["Studio.Combat", "Studio.Core"],
  "includePlatforms": ["Editor"]
}
```

`Studio.Combat.Tests.asmdef` (under `Combat/Tests/`):
```json
{
  "name": "Studio.Combat.Tests",
  "references": [
    "Studio.Combat",
    "UnityEngine.TestRunner",
    "UnityEditor.TestRunner"
  ],
  "includePlatforms": ["Editor"],
  "overrideReferences": true,
  "precompiledReferences": ["nunit.framework.dll"],
  "defineConstraints": ["UNITY_INCLUDE_TESTS"]
}
```

The Tests asmdef must have **Test Assemblies** flag enabled in the inspector — wires NUnit and `[Test]` discovery. With `overrideReferences: true` + `nunit.framework.dll`, Unity surfaces NUnit attributes correctly. See `unity-tests`.

## References

Explicit. No transitive auto-include — if `A` refs `B` and `B` refs `C`, code in `A` can't see `C` types unless `A` also refs `C`.

Unity package asmdefs by name:
- `Unity.InputSystem`
- `Unity.RenderPipelines.Universal.Runtime`
- `Unity.TextMeshPro`
- `Unity.Mathematics`, `Unity.Burst`, `Unity.Collections`
- `UnityEngine.UI`

Common mistake: `using UnityEngine.InputSystem;` without referencing `Unity.InputSystem` — compiles in `Assembly-CSharp` (auto-referenced) but breaks the moment you put the script under a custom asmdef. Add the reference.

## Version defines and define constraints

**Version defines** gate code on a referenced package's version:

```json
"versionDefines": [
  { "name": "com.unity.inputsystem", "expression": "1.4.0", "define": "INPUT_SYSTEM_1_4" },
  { "name": "com.unity.render-pipelines.universal", "expression": "[14.0.0,17.0.0)", "define": "URP_14_TO_17" }
]
```

```csharp
#if INPUT_SYSTEM_1_4
    // post-1.4 API
#endif
```

Expression: semver ranges. `1.4.0` = `>= 1.4.0`, `[1.0,2.0)` = half-open.

**Define constraints** make the entire asmdef conditional:

```json
"defineConstraints": ["UNITY_EDITOR", "STUDIO_DEV_TOOLS"]
```

If both symbols aren't set, Unity skips the assembly. DLL doesn't exist at runtime.

## Auto-referenced and Override References

`autoReferenced: true` (default) — `Assembly-CSharp.dll` auto-references your asmdef. Loose scripts in `Assets/` (without their own asmdef) can use your types. `false` for force-opt-in utility libraries.

`overrideReferences: true` + `precompiledReferences` bundles a third-party DLL (`Newtonsoft.Json.dll`, `MessagePack.dll`) and prevents other assemblies from pulling a different version through the predefined-assembly side-channel.

## Common patterns

- **Boot assembly** — `Studio.Boot.asmdef` references everything else, contains the entry-point `MonoBehaviour`. Tree, not web.
- **Pure C# core** — `Studio.Core.asmdef` with `noEngineReferences: true` for serializable models, deterministic logic, testable-without-Unity code. Same DLL works in unit tests outside Editor.
- **Per-platform assemblies** — split mobile-only or console-only via `includePlatforms`.
- **Editor tooling assembly** — `Studio.EditorTools.asmdef` with `includePlatforms: ["Editor"]` for inspectors, importers, menu items.

## Diagnosing circular deps

Unity logs `Assembly with name 'X' has a cyclic reference` and refuses to compile.

1. **Extract shared types to a third assembly.** If `Combat` and `Inventory` both need `ItemId`, create `Studio.Domain` lower in the graph.
2. **Invert via interface.** If `Combat` needs to notify `UI` and `UI` already refs `Combat`, define `ICombatListener` in `Combat`, have `UI` implement it, inject at boot. Direction stays `UI -> Combat`.

Search every `.asmdef`'s `references` array — or use the Project view where Unity highlights the offender.

## Compilation cost

Each asmdef adds ~50–200 ms cold-compile overhead. 30 asmdefs of two scripts each is slower than 5 of twelve.

Sweet spot: 5–20 asmdefs. Profile with `CompileScripts` marker.

Warm iteration is the bigger win — editing one leaf script recompiles ~1 DLL instead of all `Assembly-CSharp`.

## Gotchas

- `using UnityEditor;` in a runtime asmdef compiles in Editor and fails Player build with "The type or namespace `UnityEditor` could not be found." Move into matching `.Editor` asmdef or wrap in `#if UNITY_EDITOR`.
- Test asmdef without **Test Assemblies** flag won't surface tests in Test Runner.
- Renaming an asmdef breaks every other asmdef referencing it by name. Use GUID refs (`GUID:` prefix from the `.asmdef.meta`) if reorganizing often.
- Adding a new asmdef to a folder that previously had none can orphan code that depended on `Assembly-CSharp` auto-referencing — add explicit `references`.
- `noEngineReferences: true` blocks `UnityEngine` — including `Vector3`, `Mathf`. Use `Unity.Mathematics` or `System.Numerics`.
- `.asmref` (assembly definition reference) lets a folder join an asmdef defined elsewhere without moving files; rarely needed.
- A plugin DLL under `Assets/Plugins/` is auto-referenced everywhere unless you wrap via `overrideReferences` on consumer asmdefs.

## Verification

- Console clean after each asmdef edit; cyclic-ref and missing-ref errors surface immediately.
- Search `using UnityEditor;` across runtime asmdef folders. Any hit must be `#if UNITY_EDITOR`-guarded or moved to an Editor asmdef.
- Edit one leaf script and observe the bottom-right recompile spinner — should name only the owning DLL + dependents.
- For tests, `Window > General > Test Runner` should list them.

## Cross-links

- `unity-tests` — full PlayMode/EditMode wiring atop the Tests asmdef.
- `unity-vcs` — commit `.asmdef` and `.asmdef.meta` (always commit both; never hand-edit GUIDs).

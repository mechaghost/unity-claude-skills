---
name: unity-asmdef
description: Use when partitioning Unity C# code into Assembly Definition files via Unity MCP — anything involving asmdef, assembly definition, .asmdef, asmref, version define, define constraint, auto-referenced, override references, precompiled assembly, plugin DLL, hot reload, compilation time, iteration time, circular dependency, EditorOnly assembly, test assembly. Unity 6 / 2023.2 LTS, URP-only, new Input System only.
---

# unity-asmdef

Assembly Definitions partition the project's C# into separate DLLs so only the changed asmdef and its dependents recompile. Below ~10 minutes of cold compile this is iteration-time tax; above that it becomes the single biggest productivity lever in the project.

## When to use

- Cold compile creeps past 10-15 seconds and every script edit hits everything.
- A feature folder needs to compile without dragging in another team's code.
- Editor-only tooling has leaked `using UnityEditor;` into runtime scripts and the Player build is failing.
- Tests need their own assembly with NUnit + TestRunner refs.
- A third-party DLL is pulling in conflicting versions of `Newtonsoft.Json` or similar.
- A package upgrade requires `#if PACKAGE_X_GTE_2_0` gating.

If you only have a handful of scripts and compile is sub-second, do not pre-shard. Empty asmdefs cost more than they save.

## What asmdef does

Unity normally compiles `Assets/` into a small set of monolithic predefined assemblies (`Assembly-CSharp.dll`, `Assembly-CSharp-Editor.dll`, etc.). One script edit = full recompile of that DLL.

An `.asmdef` file (JSON, in any folder under `Assets/` or `Packages/`) tells Unity: "compile every `.cs` from this folder downward into its own DLL." That DLL has explicit references to other asmdefs and Unity packages. Edit a script in a leaf assembly, only that DLL + anything depending on it recompiles.

Sweet spot for a mid-size project: 5-20 asmdefs. Each one adds ~50-200ms of cold compile overhead, but warm iteration drops dramatically once the dependency graph is shallow.

## File anatomy

`Studio.Combat.asmdef` (live next to the `.cs` files it owns):

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

Fields:
- `name` — DLL name, must be unique. Convention: `Company.Feature` or `Company.Feature.Editor`.
- `rootNamespace` — Unity will create new C# scripts in this namespace by default.
- `references` — names (or GUIDs) of other asmdefs this one depends on. Explicit; no transitive sugar.
- `includePlatforms` / `excludePlatforms` — empty = all. Use `["Editor"]` for editor-only, or exclude `WebGL` etc.
- `allowUnsafeCode` — enables `unsafe` blocks.
- `overrideReferences` — when `true`, predefined assemblies stop auto-referencing this one's DLLs; you control them via `precompiledReferences`.
- `precompiledReferences` — third-party DLL filenames (e.g. `Newtonsoft.Json.dll`) found under `Assets/Plugins/`.
- `autoReferenced` — when `true` (default), the predefined `Assembly-CSharp` references this asmdef automatically. Set `false` to force everyone to opt in.
- `defineConstraints` — only compile this asmdef when ALL listed scripting-define symbols are set (e.g. `["UNITY_EDITOR", "STUDIO_DEV_TOOLS"]`).
- `versionDefines` — define a symbol when a referenced package's version satisfies an expression.
- `noEngineReferences` — when `true`, no `UnityEngine.*` is auto-referenced (rare; pure utility libs).

## Folder layout patterns

Two layouts are common; pick one and stick with it.

**Feature folders** (recommended for game projects):

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

**Layered architecture** (recommended for larger or service-oriented codebases):

```
Assets/_Project/
  Core/           Studio.Core.asmdef          (no deps)
  Domain/         Studio.Domain.asmdef        (refs Core)
  Services/       Studio.Services.asmdef      (refs Core, Domain)
  Presentation/   Studio.Presentation.asmdef  (refs Domain, Services)
```

Direction is always one-way: `Core <- Domain <- Services <- Presentation`. No upward refs. If `Domain` needs to call back into `Presentation`, invert it with an interface defined in `Domain` and implemented in `Presentation`.

`Editor/` folders carry an automatic editor-only convention only when there is no asmdef. With asmdefs, you must add a separate Editor asmdef that excludes runtime platforms.

## Editor / Runtime / Test split

Gold-standard pattern, three asmdefs per feature:

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

The Tests asmdef must have the **Test Assemblies** flag enabled in the inspector — that flag is what wires NUnit and `[Test]` discovery. With `overrideReferences: true` plus the `nunit.framework.dll` precompiled reference, Unity surfaces NUnit attributes correctly. See unity-tests for full PlayMode/EditMode setup.

## References

References are explicit. There is no transitive auto-include — if `A` refs `B` and `B` refs `C`, code in `A` cannot see `C` types unless `A` also refs `C`.

Unity package asmdefs must be referenced by name, e.g.:
- `Unity.InputSystem` (com.unity.inputsystem)
- `Unity.RenderPipelines.Universal.Runtime` (URP)
- `Unity.TextMeshPro`
- `Unity.Mathematics`, `Unity.Burst`, `Unity.Collections`
- `UnityEngine.UI` (built-in UGUI)

A common mistake: adding `using UnityEngine.InputSystem;` without referencing `Unity.InputSystem` in the asmdef — it compiles in `Assembly-CSharp` (auto-referenced) but breaks the moment you put that script under a custom asmdef. Add the reference.

## Version defines and define constraints

**Version defines** gate code on a referenced package's version:

```json
"versionDefines": [
  { "name": "com.unity.inputsystem", "expression": "1.4.0", "define": "INPUT_SYSTEM_1_4" },
  { "name": "com.unity.render-pipelines.universal", "expression": "[14.0.0,17.0.0)", "define": "URP_14_TO_17" }
]
```

Then in code:
```csharp
#if INPUT_SYSTEM_1_4
    // Use the post-1.4 API
#endif
```

Expression syntax is the same as semver ranges: `1.4.0` means `>= 1.4.0`, `[1.0,2.0)` is half-open.

**Define constraints** make the entire asmdef conditional. Useful for dev-only tooling assemblies:

```json
"defineConstraints": ["UNITY_EDITOR", "STUDIO_DEV_TOOLS"]
```

If both symbols are not set, Unity skips the assembly entirely. The DLL will not exist at runtime.

## Auto-referenced and Override References

`autoReferenced: true` (the default) means `Assembly-CSharp.dll` automatically references your asmdef. Loose scripts in `Assets/` (without their own asmdef) can use your types. Set `false` for utility libraries you want to force-opt-in.

`overrideReferences: true` plus `precompiledReferences` is how you bundle a third-party DLL (e.g. `Newtonsoft.Json.dll`, `MessagePack.dll`) and prevent other assemblies from accidentally pulling in a different version through the predefined-assembly side-channel.

## Common patterns

- **Boot assembly**: `Studio.Boot.asmdef` references everything else and contains the entry-point `MonoBehaviour`. Keeps the dependency graph a tree, not a web.
- **Pure C# core**: `Studio.Core.asmdef` with `noEngineReferences: true` for serializable models, deterministic logic, anything testable without Unity. Same DLL works in unit tests outside the Editor.
- **Per-platform assemblies**: split mobile-only or console-only code via `includePlatforms`.
- **Editor tooling assembly**: one big `Studio.EditorTools.asmdef` with `includePlatforms: ["Editor"]` for inspectors, importers, and menu items.

## Diagnosing circular deps

Unity logs `Assembly with name 'X' has a cyclic reference` and refuses to compile.

Two fixes:

1. **Extract shared types to a third assembly.** If `Combat` and `Inventory` both need `ItemId`, create `Studio.Domain` lower in the graph and put `ItemId` there.
2. **Invert via interface.** If `Combat` needs to notify `UI` and `UI` already refs `Combat`, define `ICombatListener` in `Combat`, have `UI` implement it, and inject the listener into `Combat` at boot. Direction stays `UI -> Combat`.

To find the cycle, use `find_in_file` against every `.asmdef` under `Assets/` and grep the `references` arrays — or inspect the Project view, where Unity highlights the offending asmdef.

## Compilation cost

Each asmdef adds roughly 50-200ms of cold-compile overhead for the DLL boundary itself. So 30 asmdefs of two scripts each will compile slower than 5 asmdefs of twelve scripts each.

Sweet spot: 5-20 asmdefs for a mid-size project. Profile with the Unity profiler's CompileScripts marker if it matters.

Warm iteration is the bigger win — editing one leaf script with a healthy graph recompiles ~1 DLL instead of all of `Assembly-CSharp`.

## Gotchas

- `using UnityEditor;` in a runtime asmdef compiles fine in the Editor and fails the Player build with "The type or namespace `UnityEditor` could not be found." Move that code into the matching `.Editor` asmdef or wrap in `#if UNITY_EDITOR`.
- Test asmdef without the **Test Assemblies** flag won't surface tests in the Test Runner window.
- Renaming an asmdef breaks every other asmdef that referenced it by name. Use `references` by GUID (paste the asmdef's `.asmdef.meta` GUID prefixed with `GUID:`) if you reorganize often.
- Adding a new asmdef to a folder that previously had none can suddenly orphan code that depended on `Assembly-CSharp` auto-referencing types — fix by adding explicit `references`.
- `noEngineReferences: true` prevents `UnityEngine` types — that includes `Vector3` and `Mathf`. Use `Unity.Mathematics` or `System.Numerics` instead.
- `.asmref` (assembly definition reference) lets a folder join an asmdef defined elsewhere without moving files; rarely needed.
- A plugin DLL dropped under `Assets/Plugins/` is auto-referenced everywhere unless you wrap it via `overrideReferences` on consumer asmdefs.

## Verification

- `read_console` after each asmdef edit; cyclic-ref and missing-reference errors surface immediately.
- `find_in_file` for `using UnityEditor;` across every runtime asmdef folder. Any hit must be `#if UNITY_EDITOR`-guarded or moved to an Editor asmdef.
- Make a trivial edit to one leaf script and observe the recompile in the bottom-right spinner — it should name only the owning DLL plus its dependents.
- For the test-asmdef setup, open Window > General > Test Runner and confirm tests are listed.

## Cross-links

- See unity-tests for full PlayMode/EditMode test wiring on top of the `Tests` asmdef.
- See unity-vcs for committing `.asmdef` and `.asmdef.meta` files (always commit both; never hand-edit GUIDs).

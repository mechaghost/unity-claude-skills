---
name: unity-3d-verification
description: 'Use after creating or modifying a 3D GameObject in Unity via MCP (primitive, imported model, instantiated prefab, ProBuilder edit, transform/scale/rotation change, material swap) and before declaring the task done. Captures four orthographic screenshots (left, right, top, bottom) of the object, reads the PNGs, and visually verifies the result. Trigger keywords: verify a Unity object looks correct, 4-shot capture, orthographic screenshots, confirm 3D creation, check Unity GameObject visually. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Run after creating or mutating a 3D GameObject and before reporting "done". An MCP success only proves the call executed; it doesn't prove the object is scaled, oriented, materialed, or positioned correctly. Trigger on:

- Creating primitives (cube/sphere/etc).
- Importing or instantiating models and prefabs.
- ProBuilder shape creation or mesh edits.
- Any transform mutation: position, rotation, scale, parenting.
- Material or shader swaps.
- Adding/removing renderers, mesh filters, skinned mesh renderers.

Skip only when verifiably non-visual (rename, edit script asset, toggle inactive).

## Workflow

1. **Resolve bounds.**
   - `Renderer.bounds.center` and `Renderer.bounds.size` (world AABB).
   - No Renderer on root: recurse children, `Encapsulate` every child Renderer. Don't trust the root transform alone — children may extend past pivot.
   - `SkinnedMeshRenderer`: force `RecalculateBounds()` first; editor bounds can be stale until rig posed.
   - No renderers anywhere: abort, tell the user there's nothing to render.

2. **Compute camera framing.**
   - `extentsMax = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)`
   - `distance = extentsMax * 2.5`
   - `orthoSize = extentsMax * 1.2`
   - Clamp `near = 0.01`, `far = distance * 4` so the object never clips.

3. **Build the rig.**
   - `__Verification` GO at world origin (cleanup = one delete).
   - Child `__VerificationCamera` with `Camera`.
   - Configure: `orthographic = true`, `orthographicSize = orthoSize`, `clearFlags = SolidColor`, `backgroundColor = (0.15, 0.15, 0.18, 1)` (dark neutral so pink/magenta is unmistakable), `cullingMask = ~0`, `nearClipPlane = 0.01`, `farClipPlane = far`.
   - URP: ensure `UniversalAdditionalCameraData` on the camera. Confirm active pipeline is URP, add if missing.

4. **Capture four views.**
   - Each view: `transform.position = bounds.center + offset`, `transform.eulerAngles = euler` from the table.
   - Path: **`Assets/_Verification/<sanitizedName>_<view>.png`**. `Library/` is wiped by `Reimport All`. Add `Assets/_Verification/` to `.gitignore` if not committing (see `unity-vcs`). Fall back to `Library/Verification/...` only if the server sandboxes `Assets/` writes. Same scheme every run so shots overwrite + Read calls are predictable.
   - After each capture, Read the PNG. Actually look at the image — not just confirm it was written.

5. **Inspect.**
   - Walk the defect catalog per shot. Note plainly: "left view: chair facing +X, seat parallel to ground, four legs visible."
   - Any defect: fix the scene (re-issue the edit), rerun from step 1.

6. **Cleanup — always.**
   - Delete `__Verification`. Even on mid-way failure (treat as finally). Stranded cameras pollute scene saves.
   - Keep captured PNGs unless asked otherwise — useful artifacts.

## Camera setup math

Unity is left-handed, Y-up, +Z forward. `bounds.center` is world space. `offset` adds to center for camera position. `eulerAngles` in degrees.

```
view    | offset                  | eulerAngles      | image-up axis | image-right axis
--------+-------------------------+------------------+---------------+------------------
left    | (-distance, 0, 0)       | (0,  90, 0)      | +Y            | +Z
right   | (+distance, 0, 0)       | (0, 270, 0)      | +Y            | -Z
top     | (0, +distance, 0)       | (90,  0, 0)      | +Z (into)     | +X
bottom  | (0, -distance, 0)       | (270, 0, 0)      | -Z            | +X
```

Notes:
- "left view" — camera on -X side looking toward +X (you see object's left side).
- Top/bottom shots have no real "up"; the table lists which world axis points to image top so you can interpret asymmetric objects.
- If your object's logical forward is not +Z (imported FBX often default to -Z), views look mirrored. That's useful information — flag as a likely import-axis problem.

## Capture mechanism

Server-specific. Discover before assuming:

1. Enumerate the connected server's tools at session start. Match `/screenshot|capture|render|snapshot|view/i`. Use a dedicated capture tool if present.
2. Try a camera tool's `capture` / `render` / `screenshot` action — some servers fold capture into the camera tool.
3. Fall back to `Camera.Render()` into a `RenderTexture` + `Texture2D.EncodeToPNG`, via a custom-tool capability or a temporary editor script invoked through menu execution. Pseudocode:

   ```csharp
   var rt = new RenderTexture(1024, 1024, 24);
   cam.targetTexture = rt;
   cam.Render();
   RenderTexture.active = rt;
   var tex = new Texture2D(1024, 1024, TextureFormat.RGBA32, false);
   tex.ReadPixels(new Rect(0, 0, 1024, 1024), 0, 0);
   tex.Apply();
   File.WriteAllBytes(path, tex.EncodeToPNG());
   cam.targetTexture = null;
   RenderTexture.active = null;
   Object.DestroyImmediate(rt);
   Object.DestroyImmediate(tex);
   ```

   Prefer this over `ScreenCapture.CaptureScreenshot` (routes through Game view, depends on active user camera).

4. Last resort: drive `Window/General/Game` from Editor menu to focus Game view, then trigger Game-view capture menu — only if Game view's active camera is `__VerificationCamera`. Brittle; document if used.

Log the tool name used so the next run is faster.

## Common defects

- Pink/magenta — shader missing in active pipeline (URP/HDRP mismatch, Standard in URP).
- Back faces from a side that should show fronts — normals inverted, common on imported FBX with mirrored scale or `-1` axis bake.
- Object fills <10% of frame — scale too small, or wrong unit (cm imported as m).
- Object overflows frame — scale too large, or bounds calc missed a child making `extentsMax` too small.
- Off-center pivot — object visibly offset even though camera targets `bounds.center`. Renderer's mesh origin is not at transform pivot.
- Wrong rotation — top view shows a "side" silhouette, or chair legs point sideways. Usually a 90° axis swap from import.
- Z-fighting/clipping — flickery surfaces or missing chunks where geometry intersects another collider/mesh. Object placed inside existing geometry.
- Invisible from one+ views — culling mask excludes layer, renderer disabled, material has `Cull Front`/`Off`, or one-sided and you're behind it. Check `MeshRenderer.enabled`.
- Lightmap/lighting artifacts — pure black means no lights + ambient zero.
- Skinned mesh frozen in T-pose with limbs intersecting — bounds stale; rerun after `RecalculateBounds`.
- LOD0 missing — only low-poly silhouette visible; check `LODGroup` thresholds.
- Transparent/depth-sorted material rendering as opaque blocks — render queue or `ZWrite` misconfigured.

## Gotchas

- URP/HDRP need the verification camera to use the matching pipeline asset + additional-camera-data, or capture is solid black or magenta. Confirm pipeline first.
- `SkinnedMeshRenderer.bounds` can be stale in editor. Force `RecalculateBounds()`.
- Prefer `Renderer.bounds` (world AABB) over `Mesh.bounds` (local; ignores transform scale/rotation).
- Composite objects: `Encapsulate` every child renderer. Initialize `Bounds(center, Vector3.zero)` then `Encapsulate`; don't start from `default(Bounds)` — `(0,0,0)` pulls the box toward origin.
- Don't enter Play mode to verify. Pollutes scene state, fires `Awake`/`Start`, may instantiate runtime-only objects. Edit-mode `Camera.Render()` is sufficient.
- `ScreenCapture.CaptureScreenshot` requires Game view active + uses whatever camera is `MainCamera`-tagged. For deterministic offscreen, always `Camera.Render()` to a `RenderTexture`.
- Some servers sandbox file writes to `Assets/` only; `Library/` may be off-limits. `Library/` is also wiped by `Reimport All` — prefer `Assets/_Verification/` (with `.gitignore` entry). Check once and remember.
- UI element on `Canvas` Screen Space-Overlay won't appear in orthographic 3D capture. Switch canvas to World Space or capture as 2D screenshot — note in your report.
- `cullingMask = ~0` still misses objects on `Ignore Raycast`-style hidden layers some teams use; if a known object disappears, check layer.
- Batch camera moves + captures in one round-trip when the server supports batching; eight serial round-trips is noticeably slower.

## Cost / batching guidance

The 4-shot capture is heavy: 4 camera moves + 4 PNG writes + 4 PNG reads. For bulk ops the cost dominates the actual work.

- **Verify HERO and NOVEL changes only.** New prefab, hand-authored mesh, custom-shaded material, one-off ProBuilder edit — yes. Bulk re-imports of a known asset pack — no.
- **Batch >5 objects when supported.** Lay out all camera moves + captures (4/object → 20 PNGs for 5) into one batched round-trip. Issue all PNG `Read` calls in a single message so the harness fetches in parallel. Serial is the slow path.
- **Trusted-shape skip list.** Default URP primitives (`Cube`, `Sphere`, `Cylinder`, `Capsule`, `Plane`, `Quad`) with `Universal Render Pipeline/Lit` and no transform tricks always look right. Skip. Verify only with non-uniform scale, custom material, or non-default rotation.
- **Per-session budget.** At most 4 objects fully verified per session unless asked. Beyond that, a single Game-view screenshot framing the object is sufficient — escalate to 4-shot only if the single shot reveals a problem.

## After verification

- Report view by view in plain language. Example: "left: chair seat parallel to ground, four legs visible, oak material rendering correctly. right: same, mirrored. top: only three leg tops visible — back-left leg missing or rotated 90° out. bottom: confirms three legs, fourth rotated horizontally and embedded in floor."
- Any defect → don't declare success. Fix, rerun, re-inspect. Repeat until all four read clean.
- Only after all four views read clean may you report done. MCP success alone is not sufficient evidence.
- Always cleanup `__Verification` before your final response.

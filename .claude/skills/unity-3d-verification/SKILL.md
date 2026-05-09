---
name: unity-3d-verification
description: 'Use after creating or modifying a 3D GameObject in Unity via MCP (primitive, imported model, instantiated prefab, ProBuilder edit, transform/scale/rotation change, material swap) and before declaring the task done. Captures four orthographic screenshots (left, right, top, bottom) of the object, reads the PNGs, and visually verifies the result. Trigger keywords: verify a Unity object looks correct, 4-shot capture, orthographic screenshots, confirm 3D creation, check Unity GameObject visually. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Run this loop every time an MCP call has just created or mutated a 3D GameObject and the next thing you would otherwise do is tell the user "done." A successful MCP response only proves the call executed; it does not prove the object is scaled, oriented, materialed, or positioned correctly. Specifically trigger on:

- Creating primitives (`manage_gameobject` create cube/sphere/etc.).
- Importing or instantiating models and prefabs.
- ProBuilder shape creation or mesh edits (`manage_probuilder`).
- Any transform mutation: position, rotation, scale, parenting.
- Material or shader swaps (`manage_material`, `manage_shader`).
- Adding/removing renderers, mesh filters, skinned mesh renderers.

Skip only when the change is verifiably non-visual (e.g., renaming, editing a script asset, toggling an inactive object).

## Workflow

1. Resolve target bounds.
   - Read the GameObject with `manage_gameobject` (get transform + components). Look for a `Renderer` and use `Renderer.bounds.center` and `Renderer.bounds.size` (world space, axis-aligned).
   - If the root has no Renderer, recurse into children and `Encapsulate` every child Renderer's bounds. Do not trust the root transform alone — children may extend far past the parent pivot.
   - For a `SkinnedMeshRenderer`, call `RecalculateBounds()` via `unity_reflect` first; editor bounds can be stale until the rig is posed.
   - If everything fails (no renderers anywhere), abort verification and tell the user the object has nothing to render.

2. Compute camera framing.
   - `extentsMax = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)`
   - `distance = extentsMax * 2.5`
   - `orthoSize = extentsMax * 1.2`
   - Clamp `near = 0.01`, `far = distance * 4` so the object never clips.

3. Build a verification rig.
   - Create a root `__Verification` GameObject at world origin via `manage_gameobject` (so cleanup is one delete).
   - Under it, create `__VerificationCamera` with a `Camera` component via `manage_components`.
   - Configure the camera: `orthographic = true`, `orthographicSize = orthoSize`, `clearFlags = SolidColor`, `backgroundColor = (0.15, 0.15, 0.18, 1)` (dark neutral so pink/magenta materials are unmistakable), `cullingMask = ~0` (everything), `nearClipPlane = 0.01`, `farClipPlane = far`.
   - URP: ensure the camera has the `UniversalAdditionalCameraData` component. `manage_graphics` can confirm the active pipeline; `manage_components` adds it if missing. (This skill set is URP-only; HDRP is out of scope.)

4. Capture each of the four views.
   - For each view, set `transform.position = bounds.center + offset` and `transform.eulerAngles = euler` from the table in **Camera setup math** below.
   - Capture via the screenshot tool (see **Capture mechanism** below) to a deterministic project-relative path. **Prefer `Assets/_Verification/<sanitizedName>_<view>.png`** for persistence — `Library/` is wiped by `Reimport All` and any Library-only state forces a re-run of verification (recovery story: simply rerun the workflow). Add `Assets/_Verification/` to `.gitignore` if shots should not be committed (cross-link `unity-vcs` for the canonical Unity `.gitignore`, Force-Text serialization mode, and Visible-Meta-Files setup that all of this assumes). Fall back to `Library/Verification/...` only when `Assets/` writes are sandboxed by this fork. Use the same path scheme every run so old shots are overwritten and Read calls are predictable.
   - Immediately after each capture, call the Read tool on the PNG. You must actually look at the image — not just confirm it was written.

5. Inspect.
   - Walk through the defect catalog below for each of the four shots. Note in plain language what each view shows: "left view: a chair facing +X, seat parallel to ground, four legs visible."
   - If any defect is present, fix it (re-issue the relevant MCP call) and rerun the workflow from step 1. Do not patch the screenshot; patch the scene.

6. Cleanup — always.
   - Delete `__Verification` via `manage_gameobject`. Do this even if a step failed mid-way; treat it as a finally block. Stranded verification cameras pollute future scene saves.
   - Do not delete the captured PNGs unless the user asks; they are useful artifacts for the conversation.

## Camera setup math

Unity is left-handed, Y-up, +Z forward. `bounds.center` is world space. `offset` is added to `bounds.center` to get camera position. `eulerAngles` is in degrees.

```
view    | offset                  | eulerAngles      | image-up axis | image-right axis
--------+-------------------------+------------------+---------------+------------------
left    | (-distance, 0, 0)       | (0,  90, 0)      | +Y            | +Z
right   | (+distance, 0, 0)       | (0, 270, 0)      | +Y            | -Z
top     | (0, +distance, 0)       | (90,  0, 0)      | +Z (into)     | +X
bottom  | (0, -distance, 0)       | (270, 0, 0)      | -Z            | +X
```

Notes:
- "left view" means the camera sits on the -X side and looks toward +X — i.e., you see the object's left side.
- For top/bottom shots there is no real "up"; the table lists which world axis points toward the top of the rendered image so you can interpret asymmetric objects.
- If your object's logical forward is not +Z (imported FBX often default to -Z forward), the views will look mirrored. That is itself useful information — flag it as a likely import-axis problem.

## Capture mechanism

The exact screenshot tool name varies by Unity MCP fork. The upstream CoplayDev/unity-mcp server (justinpbarnett/unity-mcp now redirects there) lists `manage_camera`, `execute_menu_item`, `unity_reflect`, `create_script`, `apply_text_edits`, `execute_custom_tool`, and `batch_execute` as the relevant primitives but does not document a top-level `capture_screenshot` tool publicly. Discover before assuming:

1. Enumerate available MCP tools (the harness lists them at session start). Match against `/screenshot|capture|render|snapshot|view/i`. If a dedicated tool exists, use it.
2. If not, try `manage_camera` with an action like `capture`, `render`, or `screenshot` — some forks add it there.
3. If still nothing, fall back to `Camera.Render()` into a `RenderTexture` and `Texture2D.EncodeToPNG`, executed via `execute_custom_tool` or by writing a temporary editor script with `create_script` (or `apply_text_edits` to amend an existing one) and invoking it through `execute_menu_item`. Pseudocode for the fallback:

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

   Prefer this over `ScreenCapture.CaptureScreenshot`, which routes through the Game view and depends on whatever camera the user has active.

4. As a last resort, `execute_menu_item` with paths like `Window/General/Game` to focus the Game view, then a Game-view capture menu — but only if the Game view's active camera is your `__VerificationCamera`. This path is brittle; document it in your output if you had to use it.

Always log the tool name you actually used so the next run is faster.

## Common defects this catches

- Pink / magenta material — shader not present in the active render pipeline (URP/HDRP mismatch, or Standard shader in URP project). Visible from any view.
- Back faces visible from a side that should show front faces — normals inverted, common on imported FBX with mirrored scale or `-1` axis bake.
- Object fills less than ~10% of frame — scale far too small, or wrong unit (cm imported as m).
- Object overflows the frame — scale too large, or bounds calc missed a child making `extentsMax` too small.
- Off-center pivot — the object sits visibly offset from the image center even though the camera targets `bounds.center`. Means the renderer's mesh origin is not at the transform pivot; flag for the user.
- Wrong rotation — top view shows a "side" silhouette, or a chair's legs point sideways. Usually a 90 deg axis swap from import settings.
- Z-fighting / clipping — flickery surfaces or chunks missing where geometry intersects another collider/mesh. Indicates the new object was placed inside existing geometry.
- Invisible from one or more views — culling mask excludes the layer, renderer disabled, material has `Cull Front`/`Off`, or the object is one-sided and you are behind it. Cross-check with `manage_components` to see if `MeshRenderer.enabled` is true.
- Lightmap / lighting artifacts — pure black object means no lights and ambient is zero; not strictly a defect but worth noting.
- Skinned mesh frozen in T-pose with limbs intersecting — bounds were stale; rerun after `RecalculateBounds`.
- LOD0 missing — only a low-poly silhouette visible; check `LODGroup` thresholds.
- Transparent / depth-sorted material rendering as opaque blocks — render queue or `ZWrite` misconfigured.

## Gotchas

- URP and HDRP need the verification camera to use the matching pipeline asset and additional-camera-data component, or the capture will be solid black or magenta. Check `manage_graphics` before capturing.
- `SkinnedMeshRenderer.bounds` can be stale in the editor. Force `RecalculateBounds()` via `unity_reflect` before reading.
- Prefer `Renderer.bounds` (world AABB) over `Mesh.bounds` (local). The latter ignores transform scale and rotation.
- For composite objects, encapsulate every child renderer's bounds. A `Bounds` initialized to `(center, Vector3.zero)` and then `Encapsulate`d in a loop works; do not start from `default(Bounds)` since `(0,0,0)` will pull the box toward the origin.
- Do not enter Play mode to verify. It pollutes scene state, fires `Awake`/`Start`, and may instantiate runtime-only objects. Edit-mode capture via `Camera.Render()` is sufficient.
- `ScreenCapture.CaptureScreenshot` requires the Game view to be the active render target and respects whatever camera is tagged `MainCamera`. For deterministic offscreen capture, always go through `Camera.Render()` to a `RenderTexture`.
- Some forks of Unity MCP sandbox file writes to `Assets/` only; `Library/` may be off-limits. Conversely, `Library/` is wiped by `Reimport All`, so prefer `Assets/_Verification/` (with a `.gitignore` entry) for persistence. Check once and remember the path.
- If the object is a UI element on a `Canvas` in `Screen Space - Overlay` mode, orthographic 3D capture will not see it. Switch the canvas to `World Space` or capture the canvas as a 2D screenshot instead — note this in your report rather than silently producing four black PNGs.
- `cullingMask = ~0` still misses objects on the `Ignore Raycast`-style hidden layers some teams use; if a known object disappears, re-check the layer assignment via `manage_gameobject`.
- Batch your camera moves and captures via `batch_execute` when the fork supports it; eight serial MCP roundtrips is noticeably slower than one batch.

## Cost / batching guidance

The 4-shot capture is heavy: four camera moves, four PNG writes, four PNG reads. For bulk operations the cost dominates the actual work. Apply these rules:

- **Verify HERO and NOVEL changes only.** A new prefab, a hand-authored mesh, a custom-shaded material, a one-off ProBuilder edit — yes. Bulk re-imports of a known asset pack — no.
- **Batch >5 objects via `batch_execute`.** Lay out all camera moves and captures (4 per object → 20 PNGs for 5 objects) into a single `batch_execute` call so Unity does the work in one round-trip. Then issue all PNG `Read` tool calls in a single message so the harness fetches them in parallel. Serial captures + serial reads is the slow path.
- **Maintain a "trusted-shape" skip list.** Default URP primitives (`Cube`, `Sphere`, `Cylinder`, `Capsule`, `Plane`, `Quad`) rendered with `Universal Render Pipeline/Lit` and no transform tricks do not need verification — they always look right. Skip these. Verify only when they have non-uniform scale, a custom material, or a non-default rotation.
- **Per-session verification budget.** Aim for at most 4 objects fully verified (4-shot) per session unless the user explicitly asks for more. For everything beyond that budget, a single Game-view screenshot framing the object is sufficient evidence — only escalate to the 4-shot rig if the single shot reveals a problem.

## After verification

- Report what you saw, view by view, in plain language. Example: "left: chair seat parallel to ground, four legs visible, oak material rendering correctly. right: same, mirrored as expected. top: only three leg tops visible — the back-left leg appears to be missing or rotated 90 deg out. bottom: confirms three legs, fourth leg is rotated horizontally and embedded in the floor."
- If any view reveals a defect, do not declare success. Fix the defect, rerun the four-shot capture, and re-inspect. Repeat until all four views are clean.
- Only after all four views read clean may you tell the user the original task is done. The MCP success return alone is not sufficient evidence.
- Always cleanup `__Verification` before your final response, even if the user is going to keep the object.

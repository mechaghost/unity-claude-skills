---
name: unity-ugui-rotation
description: 'Use when rotating UGUI elements in Unity through Unity MCP — Image, Text, Button, Panel, or any RectTransform under a Canvas. Z-axis rotation around the RectTransform pivot, with caveats for anchors, layout groups, masks, and Canvas render modes. Do NOT use for general UGUI work like building HUDs/menus/layouts (use unity-ugui), 3D Transform rotation (use unity-3d-rotation), or SpriteRenderer rotation (use unity-2d-rotation). Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

The target is a RectTransform under a Canvas (Screen Space Overlay, Screen Space Camera, or World Space). If the target is a 3D Transform use unity-3d-rotation; if it is a 2D SpriteRenderer use unity-2d-rotation.

## Decision tree

1. Z-axis only. UI rotation is `localEulerAngles.z`. X/Y rotation tilts the rect out of the canvas plane and breaks both visuals and graphic raycasting.
2. **Anchors are layout, pivot is rotation.** A RectTransform rotates around its `pivot` (normalized 0..1 within the rect). Anchors only control how the rect resizes against the parent; they do not change the rotation point. Many devs confuse the two.
3. Use `localEulerAngles`, not `eulerAngles`. A World Space Canvas may itself be rotated in 3D; you want rotation relative to the Canvas, not the world.
4. Render mode matters:
   - **Screen Space Overlay**: rotation is purely 2D screen rotation; no perspective.
   - **Screen Space Camera**: rotation interacts with the render camera's FOV; rotated panels show foreshortening.
   - **World Space**: full 3D Transform; keep rotations on Z to avoid back-face culling making the canvas invisible at +/-90 degrees on X or Y.
5. If a parent has a layout group or content-size fitter, rotation will not be respected by the layout pass — see Gotchas.

## Workflow

1. `find_gameobjects` to locate the UI element by name or tag.
2. `manage_ui` to inspect or set RectTransform fields at edit time (anchors, pivot, anchored position, size delta).
3. Decide pivot location before rotating. For a needle, a slider handle, or a swing, set the pivot at the rotation point in the prefab — not at runtime.
4. For one-shot rotations: `manage_gameobject` writing `localEulerAngles` with X=Y=0.
5. For continuous or animated rotation: `create_script` for a MonoBehaviour, attach via `manage_components`.
6. Verify there is no `LayoutGroup`, `ContentSizeFitter`, `Mask`, or `RectMask2D` ancestor that will misbehave (see Gotchas).
7. `read_console`, then verify visually.

## Common patterns

### Set absolute rotation

```
manage_gameobject(action="set_transform", target="HUD/HealthIcon",
                  localEulerAngles=[0, 0, 45])
```

### Spin a loading icon

```csharp
using UnityEngine;
[RequireComponent(typeof(RectTransform))]
public class SpinUI : MonoBehaviour {
    public float degPerSec = -180f; // negative for clockwise spinner
    RectTransform rt;
    void Awake() { rt = (RectTransform)transform; }
    void Update() { rt.Rotate(0, 0, degPerSec * Time.deltaTime); }
}
```

### Tilt on hover

Use Animator with a state targeting `m_LocalRotation`, or DOTween, or a coroutine:

```csharp
IEnumerator TiltTo(float targetDeg, float dur) {
    float start = rt.localEulerAngles.z, t = 0f;
    while (t < dur) {
        t += Time.unscaledDeltaTime;
        float z = Mathf.LerpAngle(start, targetDeg, t / dur);
        rt.localEulerAngles = new Vector3(0, 0, z);
        yield return null;
    }
    rt.localEulerAngles = new Vector3(0, 0, targetDeg);
}
```

### Needle / gauge

Author the prefab with the needle's pivot at the base of the needle (e.g. pivot = (0.5, 0.0) for a vertical needle pointing up). Then map a value 0..1 to a clamped angle and write `localEulerAngles.z`:

```csharp
float ang = Mathf.Lerp(minAngle, maxAngle, Mathf.Clamp01(value));
needle.localEulerAngles = new Vector3(0, 0, ang);
```

If the pivot is at center (the default), the needle will swing from its midpoint and look wrong. Set pivot in the prefab; do not patch it at runtime.

### Changing pivot at runtime (when unavoidable)

Pivot is also the anchor point for `anchoredPosition`, so changing pivot moves the rect visually. Compensate:

```csharp
static void SetPivotKeepPosition(RectTransform rt, Vector2 newPivot) {
    Vector2 size = rt.rect.size;
    Vector2 deltaPivot = newPivot - rt.pivot;
    Vector2 deltaPos = new Vector2(deltaPivot.x * size.x, deltaPivot.y * size.y);
    rt.pivot = newPivot;
    rt.anchoredPosition += deltaPos;
}
```

### Editor-time vs runtime tools

- `manage_ui` — RectTransform fields (anchors, pivot, anchoredPosition, sizeDelta) at edit time.
- `manage_components` — attach the spin/tilt MonoBehaviour, set Animator references.
- `manage_animation` — author a tilt or spin animation clip to drive `m_LocalRotation`.
- `unity_reflect` — read live RectTransform corners (`GetWorldCorners`) when debugging clipping.

## Gotchas

- **LayoutGroup ignores rotation**: HorizontalLayoutGroup, VerticalLayoutGroup, and GridLayoutGroup compute child positions from unrotated rect sizes. A rotated child overlaps neighbors and the layout looks broken. Fixes: add a `LayoutElement` with `ignoreLayout = true` on the rotated child, place the rotated element outside the layout group, or wrap it in a non-rotated container that the layout sees.
- **ContentSizeFitter ignores rotation**: the fitter sizes the parent to the unrotated child bounds. A rotated child overflows. Same fix — wrap in a non-rotated container.
- **Mask / RectMask2D clips by unrotated rect**: a `Mask` clips children using its own rect's axis-aligned bounds (Mask uses stencil from the unrotated mesh; RectMask2D clips by the rect's local-space rectangle). Rotated children get clipped at the unrotated edges, not at the visual edges. Workarounds: rotate the mask itself, use a larger mask, or remove the mask for rotated content.
- **Pivot vs anchor confusion**: if rotating around the wrong point, the fix is almost always pivot, not anchor. Anchors define how the rect resizes when the parent resizes; pivot defines the rotation and scale center.
- **Pivot change shifts position**: setting `rt.pivot = newPivot` at runtime visually jumps the element because `anchoredPosition` is measured from the pivot. Use the compensation helper above, or set pivot in the prefab.
- **eulerAngles vs localEulerAngles**: a World Space Canvas may be rotated to face a 3D camera. Writing `eulerAngles` overrides that orientation. Always use `localEulerAngles` unless you specifically want world space.
- **Animator overwrite**: an Animator clip targeting `m_LocalRotation` rewrites the rect's rotation every frame. Script writes in `Update` are lost. Either drive rotation through the Animator (parameter-bound state), or write in `LateUpdate`.
- **Graphic raycaster on rotated UI**: clicks still hit the rotated rect's visible corners. `Image.alphaHitTestMinimumThreshold` itself handles rotation correctly — the test transforms the screen point through the inverse RectTransform-to-local matrix and samples the sprite UV, so a rotated Image's alpha mask follows the rotation. The real caveats are: (a) the source `Texture.isReadable` must be `true` (otherwise the alpha sample throws), (b) the sprite must be packed with **Tight Packing OFF** in its Sprite Atlas (or left unpacked) — Tight Packing rewrites UVs in a way the alpha test cannot follow, and (c) alpha threshold is sampled per-event, so cost scales with pointer event volume on large textures. Test interactively when in doubt.
- **Screen Space Camera + perspective**: a perspective render camera causes rotated panels to foreshorten. If panels look squashed, switch the canvas to Overlay or set the render camera to orthographic.
- **World Space back-face**: rotating a World Space canvas past 90 degrees on X or Y points its back at the camera; UI shaders default to no back-face rendering, so it disappears. Keep rotations on Z, or use a double-sided UI shader.

## Verification

After rotating a UGUI element, take a screenshot of the Game view (the camera that renders the Canvas, or the screen for Overlay canvases). Confirm:

- The element rotated around the intended point — pivot is correct.
- The element is not clipped by an ancestor `Mask` or `RectMask2D`.
- Sibling elements in any layout group are not overlapping or pushed out.
- For World Space canvases, the element is still facing the camera (not flipped to its back face).

The 4-shot orthographic capture from `unity-3d-verification` does not apply to UI; one Game-view screenshot from the canvas's render camera is the right check.

---
name: unity-ugui-rotation
description: 'Use when rotating UGUI elements in Unity through Unity MCP — Image, Text, Button, Panel, or any RectTransform under a Canvas. Z-axis rotation around the RectTransform pivot, with caveats for anchors, layout groups, masks, and Canvas render modes. Do NOT use for general UGUI work like building HUDs/menus/layouts (use unity-ugui), 3D Transform rotation (use unity-3d-rotation), or SpriteRenderer rotation (use unity-2d-rotation). Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Target is a RectTransform under a Canvas (Screen Space Overlay, Screen Space Camera, World Space). 3D Transform → `unity-3d-rotation`; 2D SpriteRenderer → `unity-2d-rotation`.

## Decision tree

1. Z-axis only. UI rotation is `localEulerAngles.z`. X/Y tilts the rect out of the canvas plane and breaks both visuals and graphic raycasting.
2. **Anchors are layout, pivot is rotation.** A RectTransform rotates around its `pivot` (0..1 in rect). Anchors only control how the rect resizes against the parent; they don't change the rotation point.
3. Use `localEulerAngles`, not `eulerAngles`. A World Space Canvas may itself be rotated in 3D; you want rotation relative to the Canvas.
4. Render mode matters:
   - **Screen Space Overlay** — pure 2D screen rotation; no perspective.
   - **Screen Space Camera** — interacts with render camera FOV; rotated panels show foreshortening.
   - **World Space** — full 3D Transform; keep rotations on Z to avoid back-face culling making the canvas invisible at ±90° on X or Y.
5. Parent has layout group or content-size fitter? Rotation will not be respected by the layout pass — see Gotchas.

## Workflow

1. Locate UI element by name or tag.
2. Inspect/set RectTransform fields at edit time (anchors, pivot, anchored position, size delta).
3. Decide pivot location BEFORE rotating. Needle, slider handle, swing — set pivot at the rotation point in the prefab, not at runtime.
4. One-shot: write `localEulerAngles` with X=Y=0.
5. Continuous/animated: author a MonoBehaviour and attach.
6. Verify no `LayoutGroup`, `ContentSizeFitter`, `Mask`, or `RectMask2D` ancestor will misbehave.
7. Editor console clean, then verify visually.

## Common patterns

### Set absolute rotation

Write `localEulerAngles` to `[0, 0, 45]` on the target RectTransform.

### Spin a loading icon

```csharp
using UnityEngine;
[RequireComponent(typeof(RectTransform))]
public class SpinUI : MonoBehaviour {
    public float degPerSec = -180f; // negative for clockwise
    RectTransform rt;
    void Awake() { rt = (RectTransform)transform; }
    void Update() { rt.Rotate(0, 0, degPerSec * Time.deltaTime); }
}
```

### Tilt on hover

Animator state targeting `m_LocalRotation`, DOTween, or coroutine:

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

Author the prefab with the needle's pivot at the base (e.g. pivot = `(0.5, 0.0)` for a vertical needle pointing up). Map a value 0..1 to clamped angle and write `localEulerAngles.z`:

```csharp
float ang = Mathf.Lerp(minAngle, maxAngle, Mathf.Clamp01(value));
needle.localEulerAngles = new Vector3(0, 0, ang);
```

Pivot at center (default) → needle swings from midpoint and looks wrong. Set pivot in the prefab; don't patch at runtime.

### Changing pivot at runtime (when unavoidable)

Pivot is also the anchor point for `anchoredPosition`, so changing it moves the rect visually. Compensate:

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

- UGUI tooling — RectTransform fields (anchors, pivot, anchoredPosition, sizeDelta) at edit time.
- Component editing — attach spin/tilt MonoBehaviour, set Animator references.
- Animator/Timeline — author tilt or spin clip driving `m_LocalRotation`.
- Reflection — read live RectTransform corners (`GetWorldCorners`) when debugging clipping.

## Gotchas

- **LayoutGroup ignores rotation** — Horizontal/Vertical/GridLayoutGroup compute child positions from unrotated rect sizes. Rotated child overlaps neighbors and layout looks broken. Fixes: `LayoutElement` with `ignoreLayout = true` on the rotated child, place it outside the layout group, or wrap in a non-rotated container the layout sees.
- **ContentSizeFitter ignores rotation** — fitter sizes parent to unrotated child bounds. Rotated child overflows. Same fix — wrap in a non-rotated container.
- **Mask / RectMask2D clips by unrotated rect** — Mask uses stencil from the unrotated mesh; RectMask2D clips by the rect's local-space rectangle. Rotated children get clipped at unrotated edges. Workarounds: rotate the mask itself, use a larger mask, or remove the mask for rotated content.
- **Pivot vs anchor confusion** — wrong rotation point = pivot, not anchor. Anchors define how rect resizes; pivot defines rotation/scale center.
- **Pivot change shifts position** — `rt.pivot = newPivot` at runtime visually jumps because `anchoredPosition` is measured from pivot. Use the helper above, or set pivot in the prefab.
- **eulerAngles vs localEulerAngles** — World Space Canvas may be rotated to face a 3D camera. Writing `eulerAngles` overrides that orientation. Use `localEulerAngles` unless you specifically want world space.
- **Animator overwrite** — clip targeting `m_LocalRotation` rewrites every frame. Drive rotation through Animator (parameter-bound state), or write in `LateUpdate`.
- **Graphic raycaster on rotated UI** — clicks still hit the rotated rect's visible corners. `Image.alphaHitTestMinimumThreshold` handles rotation correctly (test transforms screen point through inverse RectTransform-to-local matrix and samples sprite UV, so a rotated Image's alpha mask follows the rotation). Real caveats: (a) source `Texture.isReadable` must be `true` (else alpha sample throws), (b) sprite must be packed with **Tight Packing OFF** in its Sprite Atlas (or unpacked) — Tight Packing rewrites UVs in a way the alpha test cannot follow, (c) alpha threshold sampled per-event, so cost scales with pointer event volume on large textures. Test interactively when in doubt.
- **Screen Space Camera + perspective** — perspective render camera causes rotated panels to foreshorten. If panels look squashed, switch canvas to Overlay or set render camera to orthographic.
- **World Space back-face** — rotating past 90° on X or Y points the back at the camera; UI shaders default to no back-face rendering, so it disappears. Keep rotations on Z, or use a double-sided UI shader.

## Verification

Screenshot the Game view (camera that renders the Canvas, or screen for Overlay). Confirm:

- Element rotated around the intended point — pivot correct.
- Not clipped by an ancestor `Mask` or `RectMask2D`.
- Sibling elements in any layout group not overlapping or pushed out.
- World Space: element still facing the camera (not flipped to back face).

The 4-shot orthographic from `unity-3d-verification` doesn't apply to UI; one Game-view screenshot from the canvas's render camera is the right check.

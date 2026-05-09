---
name: unity-ugui
description: 'Use when authoring Unity UGUI through Unity MCP — Canvas, RectTransform, anchors, pivots, Image, Button, Toggle, Slider, ScrollRect, Dropdown, InputField, TextMeshPro, TMP_Text, HorizontalLayoutGroup, VerticalLayoutGroup, GridLayoutGroup, ContentSizeFitter, AspectRatioFitter, LayoutElement, EventSystem, Graphic Raycaster, Canvas Scaler, Mask, RectMask2D, Sorting Layer, Sorting Order, screen space UI, world space UI, HUD, menu, dialog, popup, tooltip, modal, safe area. See unity-ugui-rotation for rotating RectTransforms, unity-input-system for the new-Input-System EventSystem swap, and unity-3d-verification when world-space UI is sitting in a 3D scene.'
---

## UGUI vs UI Toolkit

This is UGUI (`UnityEngine.UI` + `TMPro`, GameObject-based Canvas/RectTransform). Unity 6 also includes **UI Toolkit** (UITK: `UIDocument`, `VisualElement`, USS, UXML).

- **UGUI for**: World Space canvases, Animator-driven UI states, custom per-Graphic shader effects (Image materials, `BaseMeshEffect`), TMP/DOTween/IAP-prefab ecosystem.
- **UITK for**: dense data-bound lists with virtualization, USS dashboards, editor windows, runtime UI without a world-space surface.

If the request is `UIDocument` / `VisualElement` / `UQuery` / USS / UXML, this is the wrong skill — note the mismatch.

## Companions

- Rotating a RectTransform → `unity-ugui-rotation`.
- New Input System EventSystem swap → `unity-input-system`.
- World Space canvas in a 3D scene → `unity-3d-verification` for camera shots.
- Layout group quirks → `references/layout.md`. Resolution → `references/canvas-scaler.md`. TMP atlases/fallbacks → `references/textmeshpro.md`.

## Canvas modes

- **Screen Space Overlay** — drawn last, no camera, ignores 3D depth. HUD default.
- **Screen Space Camera** — rendered by an assigned camera at fixed plane distance. Perspective foreshortens tilted UI; switch camera to ortho if not wanted.
- **World Space** — Canvas is a 3D plane. Author at native pixel size (e.g. 1920×1080) and scale the Transform; do NOT shrink `sizeDelta` to a few units (atlas blurs).
- One Canvas per render mode. Mixing Overlay + Camera in one hierarchy breaks sorting.

## RectTransform geometry

Four fields cooperate:

- **Anchors** (min/max, 0..1 in parent) — how the rect grows when parent resizes. `(0,0)-(0,0)` pins bottom-left, `(1,1)-(1,1)` pins top-right, `(0,0)-(1,1)` stretches.
- **Anchored Position** — offset from anchor reference to pivot. Stretched anchors swap to `Left`/`Right`/`Top`/`Bottom`.
- **Pivot** (0..1 in own rect) — local origin for position AND rotation.
- **Size Delta** — with non-stretched anchors IS rect pixel size. With stretched anchors IS offset from anchor rect: `sizeDelta.x = -(left + right)`. Inspector synthesizes Left/Right/Top/Bottom from `offsetMin`/`offsetMax`.

Quick rules:
- Centered fixed HUD: anchors `(0.5,0.5)-(0.5,0.5)`, pivot `(0.5,0.5)`, sizeDelta = pixel size.
- Full-screen panel: anchors `(0,0)-(1,1)`, all offsets `0`.
- Top banner: anchors `(0,1)-(1,1)`, pivot `(0.5,1)`, sizeDelta `(0, height)`.

Editor: Alt-click the anchors-preset menu sets anchors + position + pivot in one click.

Prefer `RectTransform.anchoredPosition` over `position` (world position bypasses anchors).

## Selectables and widgets

`Selectable` base for `Button`, `Toggle`, `Slider`, `Scrollbar`, `InputField`, `TMP_InputField`, `Dropdown`, `TMP_Dropdown`. `ScrollRect` is related but not a Selectable.

- **Transition**: None / Color Tint (cheapest, default) / Sprite Swap / Animation.
- **Navigation**: Automatic / Horizontal / Vertical / Explicit. Use Explicit for grid menus.
- **Button** — `onClick` UnityEvent: `button.onClick.AddListener(() => Debug.Log("clicked"));`
- **Slider** — `minValue`, `maxValue`, `value`, `wholeNumbers`, `direction`. No two-handle out of box.
- **ScrollRect** — needs `Viewport` (with `Mask`/`RectMask2D`), `Content` rect that moves, optional `Scrollbar`. Content same size as Viewport = nothing scrolls.
- **Dropdown / TMP_Dropdown** — `options` list (label+sprite), `onValueChanged(int index)`.

## Layout system

Three groups, two fitters, one per-child override:

- **Horizontal/VerticalLayoutGroup** — Padding, Spacing, Child Alignment, Control Child Size, Use Child Scale, Child Force Expand.
- **GridLayoutGroup** — fixed cell size. Constraint: Flexible / Fixed Column / Fixed Row Count.
- **ContentSizeFitter** — auto-resize rect from children. Horizontal/Vertical Fit: Unconstrained / Min / Preferred Size.
- **AspectRatioFitter** — locks ratio. Modes: Width Controls Height / Height Controls Width / Fit In Parent / Envelope Parent.
- **LayoutElement** — per-child min/preferred/flexible W/H overrides. `ignoreLayout = true` opts out (floating overlays inside a group).

Order: bottom-up preferred sizes → top-down sizing. CSF on a parent of a layout-driven child = "Layout is being rebuilt during a layout rebuild" cycle. Break by fixing a size. See `references/layout.md`.

## Text (TextMeshPro)

Use TMP for new UI — better atlas, MSDF, rich text, shader effects.

- Unity 6 folds TMP into `com.unity.ugui` — no separate package. First TMP component prompts to import TMP Essentials; accept. Default assets land at `Assets/TextMesh Pro/`; do not move.
- `TextMeshProUGUI` for Canvas UI; `TextMeshPro` (non-UGUI) for 3D world-space.
- Settings: `Window > TextMeshPro > Settings` → `TMP_Settings` asset under `Assets/TextMesh Pro/Resources/`.
- Legacy `Text` only autosizes via jagged `BestFit`. Migrate.

Atlas modes (Static vs Dynamic), fallbacks, SDF tuning, missing-glyph, rich-text tags, RTL/Arabic, `BaseMeshEffect`, material presets, dynamic-atlas recovery → `references/textmeshpro.md`.

## Localization handoff

Stops at layout/TMP boundary. Translation is `unity-localization`:

- User-facing strings, `LocalizedString` bindings, runtime language switch.
- TMP CJK/emoji fallback chains, RTL/Arabic shaping, locale-specific font assets.
- Smart Format plurals/genders, locale-aware date/number/currency.
- Per-locale asset variants via `LocalizedAsset`.

## Canvas Scaler and resolution

UI Scale Mode:
- **Constant Pixel Size** — 1 unit = 1 pixel. Editor-only; tiny on 4K.
- **Scale With Screen Size** — Reference Resolution + Match (Width/Height/0..1 blend). Default `(1920, 1080)` Match `0.5` for adaptive HUDs.
- **Constant Physical Size** — DPI-based. Niche (tablets where physical button size matters).

`Reference Pixels Per Unit` must match sprite import `Pixels Per Unit`. See `references/canvas-scaler.md` for mobile + safe area.

**Pixel Perfect** (`Canvas.pixelPerfect` / Canvas Scaler toggle) — snaps Graphic vertices to integer pixels post-scale. Eliminates sub-pixel filtering on aligned UI; introduces shimmer when animating fractional positions. OFF for tweened HUDs; ON for non-animating pixel-art.

## Sorting and rendering order

- One Canvas: hierarchy sibling order = render order. Top of list = behind, bottom = in front.
- Multiple Canvases: each has `Sort Order` (int) + `Sorting Layer`. Higher Sort Order = in front.
- Nested canvases break batching with parent + have their own Sort Order. Use for high-frequency-redraw widgets so they don't dirty the static canvas.
- World Space canvases sort by **Canvas `Sorting Order`** then **transparent queue + camera distance** — NOT like opaque meshes. Default UGUI shader is `ZWrite Off` in transparent queue: world-space UI doesn't write depth, sorts by distance, ties broken by `Sorting Order`. Mixed with 3D: UI draws over nearer transparents with lower `Sorting Order`, drawn over by closer opaques.

## Masks and clipping

- **RectMask2D** — cheap rectangular soft-edge clipping. Preferred for ScrollRect viewports.
- **Mask** (Image-based) — clips to a `MaskableGraphic` via stencil. Required: a `MaskableGraphic` on the same GO. Supports non-rectangular shapes via Image alpha.
- **Stencil 8-bit ceiling** — Unity reserves bits for nesting; only ~8 nested `Mask` layers before clipping silently fails. RectMask2D doesn't consume stencil — prefer when nesting deep.
- **`showMaskGraphic = false` does NOT save a draw call** — masking graphic still writes stencil; flag controls only color contribution.
- **`MaskableGraphic.maskable = false`** — escape hatch when a child shouldn't be clipped (tooltip overflowing a scroll view).
- Both break batching at the mask boundary. Keep masked content modest.
- Rotated masked content has caveats — see `unity-ugui-rotation`.

## EventSystem and input

One `EventSystem` per scene; UI input dies without it.

- **Standalone Input Module** — legacy (`Input.GetAxis`); out of scope. Replace with Input System UI Input Module on porting.
- **Input System UI Input Module** — only supported. Required because Active Input Handling = New. See `unity-input-system`.
- **Graphic Raycaster** required on every Canvas receiving pointer events. World Space also needs `Event Camera`.
- **GraphicRaycaster settings**:
  - `ignoreReversedGraphics` (default ON) — Graphics whose normal points away from camera are ignored. OFF for double-sided world-space UI.
  - `blockingObjects` — `None` / `TwoD` / `ThreeD` / `All`. Set ThreeD/All when 3D geometry should occlude clicks on world-space canvas.
  - `blockingMask` — layer filter on top of `blockingObjects`. Combine to allow only specific layers to occlude UI clicks.
- Pointer/drag handlers: `IPointerEnter/Exit/Click/Down/UpHandler`, `IBeginDrag/Drag/EndDragHandler`, `IInitializePotentialDragHandler` (press could become drag, before threshold), `IDropHandler` (target the pointer is over at drag end), `IScrollHandler`.
- Submit/select handlers (EventSystem nav, not mouse): `ISubmit/CancelHandler`, `IMoveHandler`, `ISelect/DeselectHandler`, `IUpdateSelectedHandler` (every frame while selected).

## Performance

- A Canvas re-batches when ANY Graphic changes (vertex, color, text). Animated widgets → own nested Canvas.
- An FPS counter on a busy HUD canvas re-batches the whole HUD every frame. Nested Canvas.
- **Nested Canvas cost model**: does NOT save draw calls (batching doesn't cross Canvas boundaries) — adds a draw call boundary. The win is **dirty-propagation isolation**: nested changes don't force parent rebuild, vice versa. Use for high-frequency widgets (timers, counters, gauges); accept the extra draw call.
- Set `Raycast Target = false` on every non-interactive Image/Text. Graphic raycaster is O(N) per pointer event over all `raycastTarget = true` Graphics. On a 200-Graphic canvas, switching 180 to false routinely halves frame time in `EventSystem.Update` during continuous pointer movement.
- `CanvasGroup.alpha = 0` + `interactable = false` + `blocksRaycasts = false` does NOT make a panel free. Graphics rebuild on field changes; pointer raycasts walk them unless `blocksRaycasts = false`. Win over `SetActive(false)` is avoiding `OnEnable`/`OnDisable` churn + show-time layout rebuild — use for frequent toggles. `SetActive(false)` for long-hidden panels.
- **`Image.Type = Filled`** re-tessellates mesh every frame `fillAmount` changes — #1 hot-path for radial cooldowns. 60 Hz cooldown wheel rebuilds 60×/sec AND dirties parent Canvas. Put on nested Canvas, prefer shader-driven radial fill (uv-angle vs `_FillAmount`) when many cooldowns animate.
- Coalesce with Sprite Atlases (`Window > 2D > Sprite Atlas`). **Variant atlases** — Master + child Variant at different scale (1.0 + 0.5) so quality tier swaps atlases without changing references. **Late binding** — `SpriteAtlasManager.atlasRequested` loads on demand (e.g. Addressables); cached for session. `SpriteAtlasManager.atlasRegistered` fires after registration. Use for localized art swaps and quality-tier swaps without baking every variant.
- **Canvas update phases**: `CanvasUpdateRegistry` runs `ICanvasElement.Rebuild(CanvasUpdate phase)` in five phases: PreLayout → Layout → PostLayout → PreRender → LatePreRender. Layout groups + CSF run in layout phases; Graphics rebuild meshes in PreRender. Hooks: `Canvas.willRenderCanvases` (after PreRender, before render), `Canvas.preWillRenderCanvases` (earlier) — useful for one-frame layout corrections. `LayoutRebuilder.ForceRebuildLayoutImmediate(rect)` walks parents to topmost driving rect, runs ONLY layout phase on that subtree; does NOT rebuild Graphics meshes (different from `Canvas.ForceUpdateCanvases()`, which fires the full registry on every Canvas).
- **`UnityEditor.UI.GraphicRebuildTracker`** (editor-only) profiles which Graphic dirties a Canvas. Enable during Profiler capture for Graphic-level rebuild causes.
- `Canvas.ForceUpdateCanvases()` is a sledgehammer; per-frame = thrash. Use only after a runtime UI batch when sizes must be read immediately.

## Common patterns

### Modal dialog
Full-screen Image semi-transparent fill (Raycast Target ON, swallows clicks), child Panel, close Button.

### Health bar (Image fill)
```csharp
public Image fill; // Image.Type = Filled, Fill Method = Horizontal
public void Set(float pct) { fill.fillAmount = Mathf.Clamp01(pct); }
```
Or two stacked Images (background + foreground rect with stretch anchor + tweened sizeDelta.x).

### Tabs
`ToggleGroup` + one `Toggle` per tab. Each tab's `onValueChanged` toggles content via `SetActive` or `CanvasGroup`.

### Pop-in
Animator on panel with Idle/In/Out states, parameter-driven. Or DOTween for code-driven.

### Safe area (notches)
```csharp
using UnityEngine;
[RequireComponent(typeof(RectTransform))]
public class SafeAreaFitter : MonoBehaviour {
    RectTransform rt;
    Rect lastSafeArea;
    void Awake() => rt = GetComponent<RectTransform>();
    void Update() {
        if (Screen.safeArea != lastSafeArea) {
            lastSafeArea = Screen.safeArea;
            ApplySafeArea(lastSafeArea);
        }
    }
    void ApplySafeArea(Rect area) {
        Vector2 anchorMin = area.position;
        Vector2 anchorMax = area.position + area.size;
        anchorMin.x /= Screen.width;
        anchorMin.y /= Screen.height;
        anchorMax.x /= Screen.width;
        anchorMax.y /= Screen.height;
        rt.anchorMin = anchorMin;
        rt.anchorMax = anchorMax;
    }
}
```
Attach to a top-level RectTransform wrapping HUD content. Deeper orientation handling in `references/canvas-scaler.md`.

### Tooltip near a 3D point
```csharp
Vector2 screen = RectTransformUtility.WorldToScreenPoint(uiCamera, worldPos);
RectTransformUtility.ScreenPointToLocalPointInRectangle(parentRect, screen, uiCamera, out Vector2 local);
tooltip.anchoredPosition = local;
```
Overlay canvases: pass `null` as camera.

### Long scroll list
Pool N visible items in a ScrollRect; reposition as user scrolls instead of instantiating thousands. LoopScrollRect-style asset, or roll your own with `Content.anchoredPosition` + recycle threshold.

## Gotchas

- **Anchors vs pivot** — anchors = how rect grows; pivot = local origin for position AND rotation. Wrong rotation point = pivot.
- **anchoredPosition vs position** — `RectTransform.position` (world) bypasses anchors. Use `anchoredPosition`.
- **World Space Canvas authoring** — small `sizeDelta` (e.g. 2 units) + 100× Transform scale = blurry text + broken atlas sampling. Author at native pixel size, scale the Transform.
- **Layout cycle warning** — "Layout is being rebuilt during a layout rebuild" = ContentSizeFitter on a parent driving children that drive its size. Fix one size somewhere.
- **Mixing input systems** — leftover Standalone Input Module + Input System UI Input Module = double-fire/swallow. Delete Standalone. See `unity-input-system`.
- **Missing Graphic Raycaster** = no clicks. World Space also needs `Event Camera`.
- **Legacy `Text`** — no clean autosize. Migrate to TMP.
- **TMP Essentials import** — first TMP component prompts; run, don't move `Assets/TextMesh Pro/`.
- **ScrollRect doesn't clip** — viewport missing `RectMask2D`/`Mask`, or Content's pivot/sizeDelta wrong on the scroll axis.
- **Rotated content under layout group, mask, or fitter** — those ignore rotation. See `unity-ugui-rotation`.

## Verification

- Game-view screenshot at reference resolution AND one off-target (e.g. 1920×1080 + 1080×1920 portrait) to catch anchor breakage.
- World-space canvases in 3D scenes → `unity-3d-verification` for 4-shot orthographic.
- Editor console clean of: layout cycle warnings, missing-EventSystem, TMP Essentials nags, Graphic Raycaster errors.
- Interactive flows: reflect on live components — `Selectable.interactable` matches intent, `Button.onClick` listener count > 0.

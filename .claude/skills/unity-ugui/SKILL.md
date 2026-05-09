---
name: unity-ugui
description: Use when authoring Unity UGUI through Unity MCP — Canvas, RectTransform, anchors, pivots, Image, Button, Toggle, Slider, ScrollRect, Dropdown, InputField, TextMeshPro, TMP_Text, HorizontalLayoutGroup, VerticalLayoutGroup, GridLayoutGroup, ContentSizeFitter, AspectRatioFitter, LayoutElement, EventSystem, Graphic Raycaster, Canvas Scaler, Mask, RectMask2D, Sorting Layer, Sorting Order, screen space UI, world space UI, HUD, menu, dialog, popup, tooltip, modal, safe area. See unity-ugui-rotation for rotating RectTransforms, unity-input-system for the new-Input-System EventSystem swap, and unity-3d-verification when world-space UI is sitting in a 3D scene.
---

## UGUI vs UI Toolkit

This skill is UGUI (the GameObject-based Canvas / RectTransform stack under `UnityEngine.UI` and `TMPro`). Unity also ships **UI Toolkit** (UITK, package `com.unity.ui`) — a retained-mode UI system based on `UIDocument`, `VisualElement`, USS stylesheets, and UXML. UITK is the future-direction system for editor tooling and, on 2022.2+, an increasingly viable choice for runtime UI. Pick **UGUI** for: World Space canvases, Animator-driven UI states, complex per-Graphic shader effects (custom Image materials, `BaseMeshEffect` chains), and anything that leans on the mature UGUI ecosystem (TMP, DOTween, Unity Ads/IAP prefabs, third-party scroll-pool assets). Pick **UITK** for: dense data-bound lists with virtualization, USS-styled dashboards, editor windows / inspectors, and runtime UI on 2022.2+ where you do not need a world-space surface. If the user describes a UITK problem (`UIDocument`, `VisualElement`, `UQuery`, USS, UXML), this skill is the wrong file — note the mismatch rather than forcing the request into UGUI.

## When to use

The user is building or editing UI under a Canvas: HUDs, menus, dialogs, popups, world-space signage, button hookup, layout containers, dropdown population, text rendering, anchoring/pivoting RectTransforms, sorting issues, masking, or fixing UI input that does not respond. Specialised companions:

- Rotating a RectTransform: see `unity-ugui-rotation`.
- Project uses the new Input System package: see `unity-input-system` for the EventSystem swap.
- World Space canvases sitting in a 3D scene that need camera verification: hand off to `unity-3d-verification`.

For deeper material see `references/layout.md` (layout group quirks) and `references/canvas-scaler.md` (resolution handling).

## Canvas modes

- **Screen Space Overlay**: drawn after everything, no camera needed, ignores 3D depth. Default for HUDs.
- **Screen Space Camera**: rendered by an assigned camera at a fixed plane distance. Other cameras can render on top. Perspective foreshortens tilted UI; switch the camera to orthographic if foreshortening is unwanted.
- **World Space**: Canvas is a 3D plane in the scene. For VR, in-world signage, diegetic UI. `RectTransform.sizeDelta` is the canvas size in world units; author at native pixel size (e.g. 1920x1080) and scale the Transform — do not shrink `sizeDelta` to a few units (atlas sampling goes blurry).
- One Canvas per render mode is the norm. Mixing Overlay and Camera in the same hierarchy without intent breaks sorting expectations.

## RectTransform geometry

The piece everyone gets wrong. Four fields cooperate:

- **Anchors (min/max, normalized 0..1 within parent rect)** define how the rect grows when the parent resizes. `(0,0)-(0,0)` pins to the parent's bottom-left corner, `(1,1)-(1,1)` pins to top-right, `(0,0)-(1,1)` stretches to fill.
- **Anchored Position** is the offset from the anchor reference point to the pivot. When anchors are stretched on an axis, the inspector swaps to `Left`/`Right`/`Top`/`Bottom` offsets on that axis.
- **Pivot (normalized 0..1 within own rect)** is the local origin used for both position and rotation. `(0.5,0.5)` = center, `(0,0)` = bottom-left, `(0.5,0)` = bottom-center.
- **Size Delta** with non-stretched anchors IS the rect size in pixels — what you author is what you get. With stretched anchors `sizeDelta` IS the offset from the anchor rect: `sizeDelta.x = -(left + right)`, `sizeDelta.y = -(top + bottom)`. The inspector synthesizes the `Left` / `Right` / `Top` / `Bottom` fields from `offsetMin` and `offsetMax`, which derive from `sizeDelta` and `pivot`. Setting Left/Right in the inspector writes back through to `sizeDelta`, not the other way round.

Quick rules:

- Centered HUD element of fixed size: anchors `(0.5, 0.5)-(0.5, 0.5)`, pivot `(0.5, 0.5)`, sizeDelta = pixel size.
- Full-screen panel: anchors `(0,0)-(1,1)`, all four offsets `0`.
- Top banner full-width with fixed height: anchors `(0,1)-(1,1)`, pivot `(0.5,1)`, sizeDelta `(0, height)`.

In the editor, Alt-click the anchors-preset menu to set anchors AND position AND pivot in one click — by far the fastest path for common configs.

Use `manage_ui` to set these fields at edit time. For one-off transform writes use `manage_gameobject`. Prefer `RectTransform.anchoredPosition` over `position`; world position ignores the anchor system.

## Selectables and widgets

`Selectable` is the shared base class for `Button`, `Toggle`, `Slider`, `Scrollbar`, `InputField` (legacy), `TMP_InputField`, `Dropdown`, `TMP_Dropdown`. `ScrollRect` is related but not a Selectable.

- **Transition**: None (no visual change), Color Tint (cheapest), Sprite Swap, Animation (Animator-driven). Color Tint is the default for HUD widgets; Animation when hover/press needs richer motion.
- **Navigation**: Automatic, Horizontal, Vertical, Explicit (manually wire select-on-up/down/left/right). Use Explicit for grid menus to avoid wrong picks.
- **Button**: `onClick` UnityEvent. Wire via `manage_components` (set persistent target/method) or in code:
  ```csharp
  button.onClick.AddListener(() => Debug.Log("clicked"));
  ```
- **Slider**: `minValue`, `maxValue`, `value`, `wholeNumbers`, `direction` (LeftToRight, BottomToTop, etc.). No two-handle slider out of the box.
- **ScrollRect**: needs a `Viewport` (with `Mask` or `RectMask2D`), a `Content` rect that moves, optional `Scrollbar` references. Content's RectTransform size drives whether scrolling happens; if Content is the same size as Viewport there is nothing to scroll.
- **Dropdown / TMP_Dropdown**: `options` list of label+sprite. `onValueChanged` fires with the selected `int` index.

## Layout system

Three layout groups, two fitters, one per-child override:

- **HorizontalLayoutGroup / VerticalLayoutGroup** lay children along an axis. Settings: Padding, Spacing, Child Alignment, Control Child Size (W/H), Use Child Scale, Child Force Expand.
- **GridLayoutGroup** tiles children with a fixed cell size. Constraint: Flexible / Fixed Column Count / Fixed Row Count.
- **ContentSizeFitter** auto-resizes the rect from children's preferred sizes. Horizontal Fit / Vertical Fit: Unconstrained / Min Size / Preferred Size.
- **AspectRatioFitter** locks an aspect ratio. Mode: Width Controls Height / Height Controls Width / Fit In Parent / Envelope Parent.
- **LayoutElement** overrides per-child min/preferred/flexible W/H. `ignoreLayout = true` opts a child out (use this for floating overlays that sit inside a layout group).

Order of operations: layout group asks children for preferred sizes, ContentSizeFitter resizes the parent from those, then the layout pass repeats. Circular driving (CSF on a parent of a layout group whose child has a layout-driven size) emits "Layout is being rebuilt during a layout rebuild" warnings — break the cycle by fixing one size somewhere. Deeper write-up in `references/layout.md`.

## Text (TextMeshPro)

Prefer TMP for any new UI — better atlas, MSDF rendering, rich text, and shader effects than legacy `Text`.

- In Unity 6, TextMeshPro is folded into `com.unity.ugui` — there is no separate `com.unity.textmeshpro` package to install. First use of any TMP component still prompts to import TMP Essentials; accept the import. The default font asset and settings land under `Assets/TextMesh Pro/`; do not move that folder.
- `TextMeshProUGUI` is for UI under a Canvas. `TextMeshPro` (non-UGUI) is for 3D world-space text on a MeshRenderer.
- TMP project settings live at `Window > TextMeshPro > Settings` and edit a `TMP_Settings` asset under `Assets/TextMesh Pro/Resources/`.
- Legacy `Text` only autosizes via `BestFit`, which is jagged at runtime resize. Migrate to TMP for any new UI.

Deeper material — atlas population modes (Static vs Dynamic), fallback chains, SDF tuning, missing-glyph behavior, the full rich-text tag list, RTL / Arabic shaping caveats, `BaseMeshEffect`, material presets, and recovery from poisoned dynamic atlases — lives in `references/textmeshpro.md`.

## Localization handoff

This skill stops at the layout / TMP-component boundary. Anything translation-related belongs to `unity-localization`:

- All user-facing strings, `LocalizedString` field bindings on UI components, language switching at runtime.
- TMP font fallback chains for CJK and emoji, RTL / Arabic shaping with the Arabic Text Plug-in, locale-specific font assets.
- Plural and gender rules via Smart Format, locale-aware date / number / currency formatting.
- Per-locale asset variants (sprites, layouts, audio) wired through `LocalizedAsset` and the Localization Tables system.

When the request crosses that boundary — multi-language UI, RTL menus, font fallback, plural copy — consult `unity-localization` and stay in this skill only for the underlying RectTransform / TMP / layout work the localized content sits in.

## Canvas Scaler and resolution

UI Scale Mode picks how pixel sizes map to physical screens:

- **Constant Pixel Size**: 1 UI unit = 1 pixel always. Editor authoring only — looks tiny on 4K screens.
- **Scale With Screen Size**: scale relative to a Reference Resolution. Match: Width / Height / 0..1 blend. Default to `(1920, 1080)` and `Match = 0.5` for adaptive HUDs.
- **Constant Physical Size**: scale by DPI. Niche; for tablets where physical button size matters.

Reference Pixels Per Unit pairs with sprite import `Pixels Per Unit` — mismatch produces wrong scale. See `references/canvas-scaler.md` for mobile patterns and safe-area handling.

**Pixel Perfect**: `Canvas.pixelPerfect` (and the Canvas Scaler's matching toggle) snaps Graphic vertices to integer pixel coordinates after the CanvasScaler scale factor is applied. This eliminates sub-pixel filtering on aligned UI sprites — useful for pixel-art HUDs — but introduces shimmer when UI animates fractional positions (the snap discretizes motion). Leave OFF for tweened HUDs; turn ON only for pixel-art canvases that do not animate.

## Sorting and rendering order

- Within one Canvas: sibling order in the hierarchy IS render order. Top of the list draws first (behind), bottom draws last (in front).
- Multiple Canvases: each has `Sort Order` (int) and `Sorting Layer`. Higher Sort Order renders later (in front).
- Nested canvases break batching with the parent and have their own Sort Order. Use a nested canvas for any high-frequency-redraw widget (a counter that ticks every frame, an FPS meter) so it does not dirty the static canvas.
- World Space canvases sort by **Canvas `Sorting Order`** first, then by the **transparent queue + camera distance** rules — NOT like opaque 3D meshes. The default UGUI shader has `ZWrite Off` and renders in the transparent queue, so a world-space UI plane will not write depth and will always sort against opaque geometry by distance, with ties broken by `Sorting Order`. When mixing UI with 3D geometry, expect the UI to draw on top of any nearer transparent surface that has a lower `Sorting Order`, and to be drawn over by opaque geometry that is closer to the camera.

## Masks and clipping

- **RectMask2D**: cheap, rectangular soft-edge clipping using the rect's bounds. Preferred for ScrollRect viewports.
- **Mask** (Image-based): clips to a `MaskableGraphic` (Image / RawImage / TMP_Text) via the stencil buffer. Required component on the same GameObject is a `MaskableGraphic` — Mask without one does nothing. Supports non-rectangular shapes through the Image alpha.
- **8-bit stencil ceiling**: the stencil buffer is 8 bits and Unity reserves bits for nesting depth. In practice only ~8 nested `Mask` layers work before stencil bits are exhausted and clipping silently fails. RectMask2D does not consume stencil bits, so prefer it when nesting deep.
- **`showMaskGraphic = false` does NOT save a draw call**: the masking graphic still has to render to the stencil buffer; the flag only controls whether its color contribution writes to the color buffer.
- **`MaskableGraphic.maskable = false`** is the escape hatch when a child Graphic should not be clipped by an ancestor `Mask` or `RectMask2D` (for example a tooltip that sits inside a clipped scroll view but visually overflows it).
- Both break batching at the mask boundary. Keep masked content modest.
- Rotated masked content has caveats — see `unity-ugui-rotation`.

## EventSystem and input

One `EventSystem` per scene; UI input does not work without it.

- **Standalone Input Module**: legacy. Reads via `Input.GetAxis("Horizontal")` etc.
- **Input System UI Input Module**: required when Project Settings > Active Input Handling is `New` (or `Both` with new preferred). Cross-link `unity-input-system` for the swap and the action asset wiring.
- **Graphic Raycaster** is required on every Canvas that should receive pointer events. World Space canvases also need an `Event Camera` reference, otherwise no clicks register.
- **GraphicRaycaster settings**:
  - `ignoreReversedGraphics`: when ON (default), Graphics whose normal points away from the camera (rotated past 90 degrees) are ignored. Turn OFF for double-sided world-space UI.
  - `blockingObjects`: which non-UI objects block raycasts before they reach the canvas — `None`, `TwoD` (2D colliders), `ThreeD` (3D colliders), `All`. Set to `ThreeD` or `All` when 3D world geometry should occlude clicks on a world-space canvas.
  - `blockingMask`: layer mask filter applied on top of `blockingObjects`. Combined with `blockingObjects = ThreeD`, this is how you let only specific layers (e.g. `Default`, `Walls`) occlude UI clicks while other 3D layers (e.g. effects, debug gizmos) pass through.
- Pointer events: implement on a MonoBehaviour attached to the UI element to receive callbacks. Pointer/drag handlers — `IPointerEnterHandler`, `IPointerExitHandler`, `IPointerClickHandler`, `IPointerDownHandler`, `IPointerUpHandler`, `IBeginDragHandler`, `IDragHandler`, `IEndDragHandler`, `IInitializePotentialDragHandler` (fires when a press could become a drag, before the threshold is crossed — use to prime drag state), `IDropHandler` (fires on the target the pointer is over when a drag ends), `IScrollHandler`. Submit/select handlers (driven by EventSystem navigation, not the mouse) — `ISubmitHandler`, `ICancelHandler`, `IMoveHandler`, `ISelectHandler`, `IDeselectHandler`, `IUpdateSelectedHandler` (fires every frame the GameObject is the EventSystem's selected object).

## Performance

- A Canvas re-batches whenever ANY of its Graphics changes (vertex, color, text). Animated widgets should live on their own nested Canvas so they do not dirty the static content.
- An FPS counter on a busy HUD canvas re-batches the entire HUD every frame. Put it on a nested Canvas of its own.
- **Nested Canvas cost model**: a nested Canvas does NOT save draw calls — it adds a draw call boundary, because batching does not cross Canvas boundaries. The actual win is **isolating dirty propagation**: changes inside the nested Canvas do not force the parent Canvas to rebuild its mesh, and vice versa. Use nested Canvases on high-frequency-redraw widgets (timers, counters, animated gauges) to keep the static parent clean, accepting the extra draw call as the cost of isolation.
- Set `Raycast Target = false` on every non-interactive Image and Text. The graphic raycaster is O(N) per pointer event over every Graphic with `raycastTarget = true` on the canvas. On a 200-Graphic canvas, switching the 180 non-interactive ones to `raycastTarget = false` routinely halves the frame time spent inside `EventSystem.Update` during continuous pointer movement (drag, hover, touch).
- Toggling visibility: `CanvasGroup.alpha = 0` + `interactable = false` + `blocksRaycasts = false` does NOT make the panel free. Graphics under it still rebuild geometry when their fields change, and pointer raycasts still walk them unless `blocksRaycasts = false` is set explicitly. The real win over `SetActive(false)` is avoiding `OnEnable`/`OnDisable` churn and the layout rebuild that fires on re-show — use it for panels you toggle frequently. Use `SetActive(false)` for panels that stay hidden long enough that the OnDisable path is cheaper than keeping the subtree resident.
- **`Image.Type = Filled`** re-tessellates the Image mesh every frame `fillAmount` changes — this is the #1 hot-path pitfall for radial cooldown UIs. A 60 Hz cooldown wheel rebuilds the mesh 60 times per second AND dirties the parent Canvas. Put filled cooldown wheels on their own nested Canvas, and prefer a shader-driven radial fill (uv-angle vs `_FillAmount`) when many cooldowns animate at once.
- Coalesce draws with sprite atlases (`Window > 2D > Sprite Atlas`). Authored atlases support **variant atlases** — a Master atlas with a child Variant that re-uses the same sprite list at a different scale (e.g. 1.0 master + 0.5 variant) so quality tier can swap atlases at runtime without changing references. **Late binding**: subscribe to `SpriteAtlasManager.atlasRequested` to load atlases on demand (e.g. from Addressables) when a sprite first resolves; the loaded atlas is then cached for the session. `SpriteAtlasManager.atlasRegistered` notifies after registration. Use this combo for localized art swaps and quality-tier sprite swap without baking every variant into the build.
- **Canvas update phases**: `CanvasUpdateRegistry` runs registered `ICanvasElement.Rebuild(CanvasUpdate phase)` callbacks in five phases each frame: **PreLayout → Layout → PostLayout → PreRender → LatePreRender**. Layout groups and ContentSizeFitter participate in the layout phases; Graphics rebuild meshes in PreRender. Hooks: `Canvas.willRenderCanvases` fires after PreRender / before render, `Canvas.preWillRenderCanvases` fires earlier — useful for one-frame layout corrections. `LayoutRebuilder.ForceRebuildLayoutImmediate(rect)` walks up the parents chain to find the topmost rect that drives the passed child and runs ONLY the layout phase on that subtree; it does NOT rebuild Graphics meshes and is not the same as `Canvas.ForceUpdateCanvases()`, which fires the full registry across every Canvas.
- **`GraphicRebuildTracker`** (editor-only, `UnityEditor.UI.GraphicRebuildTracker`) is the hook for profiling which Graphic dirties a Canvas. Enable it during a Profiler capture to see Graphic-level rebuild causes — far easier than guessing from Canvas.BuildBatch frame samples.
- `Canvas.ForceUpdateCanvases()` is a sledgehammer; calling every frame causes layout thrash. Only after a batch of runtime UI changes when sizes must be read immediately.

## Common patterns

### Modal dialog

Full-screen Image with semi-transparent fill (Raycast Target ON, swallows clicks behind), child Panel with content, close Button.

### Health bar (Image fill)

```csharp
public Image fill; // Image.Type = Filled, Fill Method = Horizontal
public void Set(float pct) { fill.fillAmount = Mathf.Clamp01(pct); }
```

Or two stacked Images (background + foreground rect with a stretch anchor and a tweened sizeDelta.x).

### Tabs

A `ToggleGroup` with one `Toggle` per tab. Each tab's `onValueChanged` toggles the matching content panel via `SetActive` or `CanvasGroup`.

### Pop-in

Animator on the panel with Idle/In/Out states, parameter-driven. Or DOTween for code-driven scale/alpha tweens.

### Safe area (notches)

Sample `Screen.safeArea` and rewrite a top RectTransform's anchors each frame or on orientation change.

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

Attach to a top-level RectTransform that wraps your HUD content. The reference file (`references/canvas-scaler.md`) can keep a deeper variant for orientation-change handling.

### Tooltip near a 3D point

Convert world to screen, then screen to local-rect:

```csharp
Vector2 screen = RectTransformUtility.WorldToScreenPoint(uiCamera, worldPos);
RectTransformUtility.ScreenPointToLocalPointInRectangle(parentRect, screen, uiCamera, out Vector2 local);
tooltip.anchoredPosition = local;
```

For Overlay canvases pass `null` as the camera.

### Long scroll list

Pool N visible items in a ScrollRect and reposition them as the user scrolls instead of instantiating thousands of children. Use a community asset (LoopScrollRect-style) or roll your own with `Content.anchoredPosition` + a recycle threshold.

## Gotchas

- **Anchors vs pivot**: anchors define how the rect grows with its parent; pivot defines the local origin for position AND rotation. If something rotates around the wrong point, fix the pivot, not the anchor.
- **anchoredPosition vs position**: writing `RectTransform.position` (world) bypasses the anchor system. Prefer `anchoredPosition` for UI math.
- **World Space Canvas authoring**: small `sizeDelta` (e.g. 2 units) plus a 100x Transform scale gives blurry text and broken atlas sampling. Author at native pixel size (1920x1080) and scale the Transform.
- **Layout cycle warning**: "Layout is being rebuilt during a layout rebuild" = ContentSizeFitter on a parent that drives children that drive its size. Break the cycle with a fixed size somewhere.
- **Mixing input systems**: Standalone Input Module + Input System package → events fire twice or not at all. Swap to Input System UI Input Module when adopting the new system; see `unity-input-system`.
- **Missing Graphic Raycaster** on a Canvas = no clicks. World Space additionally needs `Event Camera` set.
- **Legacy `Text`**: no clean autosize. Migrate to TMP for any new UI.
- **TMP Essentials import**: first use of any TMP component prompts an import. Run it; do not move the resulting `Assets/TextMesh Pro/` folder.
- **ScrollRect that does not clip**: viewport is missing a `RectMask2D` (or `Mask`), or Content's pivot/sizeDelta is not configured to drive the scroll axis.
- **Rotated content under a layout group, mask, or fitter**: see `unity-ugui-rotation` — those components ignore rotation.

## Verification

- Game-view screenshot at the project's reference resolution AND at one off-target resolution (e.g. 1920x1080 reference + a 1080x1920 portrait test) to catch anchor breakage.
- For world-space canvases sitting in a 3D scene, hand off to `unity-3d-verification` for the four-shot orthographic capture.
- Inspect `read_console` for: layout cycle warnings, missing-EventSystem warnings, TMP Essentials nags, Graphic Raycaster errors.
- For interactive flows, scripted check via `unity_reflect` to confirm `Selectable.interactable` matches intent and `Button.onClick` listener count is greater than zero.

# Layout system deep dive

The UGUI layout system has three actors: layout groups (place children), fitters (resize the rect from children), and per-child overrides (`LayoutElement`). Understanding the order of operations is the difference between layouts that work and layouts that thrash.

## Order of operations

Each layout pass walks the hierarchy bottom-up then top-down:

1. **Bottom-up**: every `ILayoutElement` reports its `minWidth`, `preferredWidth`, `flexibleWidth`, `minHeight`, `preferredHeight`, `flexibleHeight`. Layout groups aggregate children's reports into their own preferred size. Among UGUI Graphics only `TMP_Text` (TextMeshProUGUI) and the standalone `LayoutElement` component implement `ILayoutElement` natively. **`Image` does NOT implement `ILayoutElement`** — it contributes no preferred size to a layout group on its own. To make an Image drive layout sizing, attach a `LayoutElement` and set its `preferredWidth` / `preferredHeight` (an Image with `Type = Sprite` and `preserveAspect` only constrains its own visual aspect ratio inside whatever rect the layout assigns; it does not feed sizes upward).
2. **Top-down**: each `ILayoutController` (layout group, ContentSizeFitter, AspectRatioFitter) sets sizes and positions. Layout groups distribute available space along the axis using preferred + flexible. ContentSizeFitter resizes the rect to match the bottom-up preferred size. AspectRatioFitter constrains one axis from the other.

If the top-down pass changes a size that the bottom-up pass depends on, Unity emits "Layout is being rebuilt during a layout rebuild" — the cycle.

## Layout group settings

### HorizontalLayoutGroup / VerticalLayoutGroup

- **Padding** (Left/Right/Top/Bottom): pixel padding inside the parent rect.
- **Spacing**: pixels between children.
- **Child Alignment**: nine-cell anchor for children inside the parent.
- **Control Child Size (Width/Height)**: when ON, the layout group writes the child's size; when OFF, the child keeps its inspector size.
- **Use Child Scale**: account for `localScale` when measuring children. Off by default.
- **Child Force Expand (Width/Height)**: distribute remaining space across children even when their flexible weight is zero.

Common pitfall: Control Child Size OFF + Child Force Expand ON does nothing for that axis — the layout group cannot expand a child it does not control.

### GridLayoutGroup

- **Cell Size**: fixed `(width, height)` for every child.
- **Spacing**: gap between cells.
- **Start Corner / Start Axis**: where the grid begins and which axis fills first.
- **Constraint**: Flexible (auto-wrap based on parent width), Fixed Column Count, Fixed Row Count.

Grids do not consult child preferred sizes. Every child becomes `Cell Size`. If you need variable-size cells use a vertical layout of horizontal layouts instead.

## Fitters

### ContentSizeFitter

- **Horizontal Fit / Vertical Fit**: `Unconstrained` (do nothing on this axis), `Min Size` (resize to combined min), `Preferred Size` (resize to combined preferred).
- Drives the rect's `sizeDelta`. Anchors must NOT be stretched on the axis being fit, otherwise sizeDelta means something different and the result looks wrong. Use non-stretch anchors on the axis the fitter controls.

### AspectRatioFitter

- **Mode**:
  - **Width Controls Height**: rect's width is independent; height = width / aspectRatio.
  - **Height Controls Width**: opposite.
  - **Fit In Parent**: rect resizes to fit inside the parent at the given aspect, letterboxed.
  - **Envelope Parent**: rect resizes to cover the parent at the given aspect, cropped.
- **Aspect Ratio**: width / height, e.g. `1.7777` for 16:9.

## LayoutElement (per-child override)

Per-child overrides for `min`, `preferred`, `flexible` width and height. A negative value means "do not override; use the natural size". `Ignore Layout = true` removes this child from the layout group's calculations entirely (use for floating overlays inside a layout group).

```csharp
var le = child.gameObject.AddComponent<LayoutElement>();
le.preferredWidth = 200f;
le.flexibleWidth  = 0f; // do not stretch
le.ignoreLayout   = false;
```

## Fixing the cycle

The "Layout is being rebuilt during a layout rebuild" warning means the top-down pass changed a size that fed the bottom-up pass. Common causes and fixes:

- ContentSizeFitter on a parent of a HorizontalLayoutGroup whose child has Control Child Size ON and a flexibleWidth. The layout group expands the child to fill the parent; the parent then resizes to the child's preferred size; loop. Fix: set a fixed width on the parent OR turn off Force Expand OR remove the fitter.
- ContentSizeFitter on the same rect that has a layout group AND a child with `flexibleHeight > 0`. The flexible weight implies infinite height. Fix: set `flexibleHeight = 0` on children when the parent is fitted.
- Two AspectRatioFitters in a chain. Fix: only fit one axis in any single chain.

## Manual rebuild

If a script changes layout-affecting fields and reads sizes in the same frame, Unity has not yet rebuilt the layout. Force it:

```csharp
LayoutRebuilder.ForceRebuildLayoutImmediate(myRect);
```

Use sparingly. `Canvas.ForceUpdateCanvases()` is the bigger sledgehammer; it rebuilds every canvas and is expensive.

## Layout-friendly authoring

- Decide which axis is fixed and which is layout-driven, per rect. Mixed stretch + ContentSizeFitter on the same axis breaks.
- Wrap rotated or scaled children in a non-rotated/non-scaled parent that the layout group sees. Layout groups ignore rotation and (by default) scale. See `unity-ugui-rotation`.
- For floating popups inside a list, give them `LayoutElement.ignoreLayout = true` and position them with absolute `anchoredPosition`.
- Use `LayoutGroup.childControlSize = false` when children should keep authored sizes — saves layout cost on dense lists.

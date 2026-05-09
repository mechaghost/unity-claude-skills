# Layout system deep dive

Three actors: layout groups (place children), fitters (resize from children), `LayoutElement` (per-child overrides).

## Order of operations

Each pass walks bottom-up then top-down:

1. **Bottom-up**: every `ILayoutElement` reports min/preferred/flexible W/H. Layout groups aggregate. Among UGUI Graphics, only `TMP_Text` and `LayoutElement` implement `ILayoutElement` natively. **`Image` does NOT** — contributes no preferred size on its own. To make an Image drive layout, add a `LayoutElement` with `preferredWidth`/`preferredHeight`. (`Image.preserveAspect` only constrains its own visual aspect inside whatever rect the layout assigns; doesn't feed sizes upward.)
2. **Top-down**: each `ILayoutController` (layout group, ContentSizeFitter, AspectRatioFitter) sets sizes/positions. Layout groups distribute space using preferred + flexible. CSF resizes the rect to the bottom-up preferred. ARF constrains one axis from the other.

If top-down changes a size that bottom-up depends on → "Layout is being rebuilt during a layout rebuild".

## Layout group settings

### Horizontal/VerticalLayoutGroup

- **Padding** — pixel padding inside parent rect.
- **Spacing** — pixels between children.
- **Child Alignment** — nine-cell anchor.
- **Control Child Size (W/H)** — ON: layout writes child size; OFF: child keeps inspector size.
- **Use Child Scale** — account for `localScale` when measuring. Off by default.
- **Child Force Expand (W/H)** — distribute remaining space across children even when flexible weight is zero.

Common pitfall: Control Child Size OFF + Force Expand ON does nothing — group can't expand a child it doesn't control.

### GridLayoutGroup

- **Cell Size** — fixed `(width, height)` for every child.
- **Spacing** — gap between cells.
- **Start Corner / Start Axis** — where grid begins, which axis fills first.
- **Constraint** — Flexible (auto-wrap), Fixed Column Count, Fixed Row Count.

Grids ignore child preferred sizes. Every child = `Cell Size`. For variable cells, use a vertical layout of horizontal layouts.

## Fitters

### ContentSizeFitter

- **Horizontal/Vertical Fit** — `Unconstrained` / `Min Size` / `Preferred Size`.
- Drives `sizeDelta`. Anchors must NOT be stretched on the fit axis (stretched sizeDelta means something different). Use non-stretch anchors on the controlled axis.

### AspectRatioFitter

- **Mode**:
  - **Width Controls Height** — height = width / aspect.
  - **Height Controls Width** — opposite.
  - **Fit In Parent** — letterboxed inside parent at given aspect.
  - **Envelope Parent** — covers parent at given aspect, cropped.
- **Aspect Ratio** — width/height (e.g. `1.7777` for 16:9).

## LayoutElement (per-child override)

Per-child overrides for min/preferred/flexible W/H. Negative = "use natural size". `Ignore Layout = true` removes child from group calculations (floating overlays).

```csharp
var le = child.gameObject.AddComponent<LayoutElement>();
le.preferredWidth = 200f;
le.flexibleWidth  = 0f;
le.ignoreLayout   = false;
```

## Fixing the cycle

"Layout is being rebuilt during a layout rebuild" causes + fixes:

- **CSF on parent of HorizontalLayoutGroup with Control Child Size ON + flexibleWidth child** — group expands child to fill parent; parent resizes to child preferred; loop. Fix: fixed parent width, OR turn off Force Expand, OR remove fitter.
- **CSF on same rect as layout group + child with `flexibleHeight > 0`** — flexible weight implies infinite height. Fix: `flexibleHeight = 0` on children when parent is fitted.
- **Two AspectRatioFitters in a chain** — only fit one axis per chain.

## Manual rebuild

Script changes layout fields and reads sizes same frame:
```csharp
LayoutRebuilder.ForceRebuildLayoutImmediate(myRect);
```

Use sparingly. `Canvas.ForceUpdateCanvases()` is the bigger sledgehammer (rebuilds every canvas).

## Layout-friendly authoring

- Decide fixed vs layout-driven axis per rect. Mixed stretch + CSF on the same axis breaks.
- Wrap rotated/scaled children in a non-rotated/non-scaled parent that the group sees. Layout groups ignore rotation and (default) scale. See `unity-ugui-rotation`.
- Floating popups inside a list: `LayoutElement.ignoreLayout = true` + absolute `anchoredPosition`.
- `LayoutGroup.childControlSize = false` when children should keep authored sizes — saves layout cost on dense lists.

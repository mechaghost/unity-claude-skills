# Canvas Scaler and resolution handling

`CanvasScaler` is the bridge between authoring-time pixel sizes and runtime screens of every dimension. Pick the mode that matches the platform.

## UI Scale Mode

### Constant Pixel Size

1 UI unit = 1 screen pixel. The scaler does nothing. A button authored at 200 px is 200 px on every device.

- **When to use**: tools, debug HUDs, editor-only UIs.
- **When NOT to use**: shipping product on a screen pool that includes both 1080p and 4K — the UI looks tiny on the high-density screen.

### Scale With Screen Size

The most common choice. Pick a `Reference Resolution` and a `Match` mode:

- **Match = 0 (Width)**: scale uniformly so the reference width fills the screen width. Tall screens get extra vertical space. Use when the design is width-bounded (mobile portrait UI where the bottom can extend).
- **Match = 1 (Height)**: scale uniformly so the reference height fills the screen height. Wide screens get extra horizontal space. Use when the design is height-bounded (mobile landscape, console HUD where the top/bottom are fixed).
- **Match = 0..1 (Expand / Shrink blend)**: blend between width and height matching. `0.5` is a balanced default for a HUD that must adapt across both orientations.

Reference Resolution rule of thumb:

- Desktop: `(1920, 1080)`, Match `0.5`.
- Mobile portrait: `(1080, 1920)`, Match `0` (width-bound).
- Mobile landscape: `(1920, 1080)`, Match `1` (height-bound).
- Tablet: `(2048, 1536)` or `(1620, 2160)` depending on target devices.

### Constant Physical Size

Scale by DPI so a button is the same physical size on every device. Niche; use when tactile size matters (a tablet POS app where the user's finger must hit a 10 mm target).

## Reference Pixels Per Unit

This pairs with sprite import `Pixels Per Unit` (set via `manage_texture`). The two should match for sprites to render at their authored size. Mismatch produces wrong-scale UI sprites. The default is `100` on both sides.

## Mobile patterns

### Safe area (notches, rounded corners)

iOS notches and Android cutouts shrink the usable rect. `Screen.safeArea` returns a `Rect` in screen coordinates of the unobstructed area. Resample it on a top RectTransform:

```csharp
using UnityEngine;
[RequireComponent(typeof(RectTransform))]
public class SafeAreaFitter : MonoBehaviour {
    RectTransform rt;
    Rect lastSafe;
    Vector2Int lastScreen;

    void Awake() { rt = (RectTransform)transform; Apply(); }

    void Update() {
        var screen = new Vector2Int(Screen.width, Screen.height);
        if (Screen.safeArea != lastSafe || screen != lastScreen) Apply();
    }

    void Apply() {
        Rect safe = Screen.safeArea;
        Vector2 min = safe.position;
        Vector2 max = safe.position + safe.size;
        min.x /= Screen.width;  min.y /= Screen.height;
        max.x /= Screen.width;  max.y /= Screen.height;
        rt.anchorMin = min;
        rt.anchorMax = max;
        lastSafe = Screen.safeArea;
        lastScreen = new Vector2Int(Screen.width, Screen.height);
    }
}
```

Attach to a child of the root Canvas that contains all UI you want inside the safe area. Pin its `offsetMin` and `offsetMax` to zero in the inspector so the anchors fully drive its rect.

### Orientation changes

Subscribe to orientation changes by polling `Screen.orientation` in `Update`, or rebuild on `OnRectTransformDimensionsChange()` if you implement it on a UI MonoBehaviour. The `SafeAreaFitter` above already covers this since `Screen.safeArea` updates with orientation.

## DPI-aware authoring

For UI that must look identical across phone densities (a 1× iPhone vs a 3× iPhone), Scale With Screen Size handles the math. For tactile precision (banking app, accessibility-driven UI), switch to Constant Physical Size.

## World Space canvases

`CanvasScaler` on a World Space canvas only controls `Dynamic Pixels Per Unit` and `Reference Pixels Per Unit` — there is no resolution-matching mode because the canvas is a 3D plane. Author at native pixel size (1920x1080 or whatever the in-world signage requires) and scale the Transform; do NOT shrink `sizeDelta` to a few units (atlas sampling will look blurry).

Set `Dynamic Pixels Per Unit` higher (e.g. `10`) for World Space text that must remain crisp when the player walks close to it.

## Gotchas

- A Canvas with no `CanvasScaler` defaults to Constant Pixel Size — UI looks tiny on 4K. Add the component on the root Canvas.
- Reference Resolution + Match mismatch: a `1080x1920` reference with `Match = 1` on a landscape device gives a UI scaled to fit the height (1080), so the width is enormous. Match the orientation.
- Mixing Scale With Screen Size canvases with different reference resolutions in the same scene leads to elements jumping when reparented. Standardise on one reference resolution per project.
- `CanvasScaler.scaleFactor` is the runtime read of the current scale. Useful for debugging mismatched pixel-perfect art.

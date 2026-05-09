# Canvas Scaler and resolution handling

`CanvasScaler` bridges authoring pixel sizes and runtime screens.

## UI Scale Mode

### Constant Pixel Size

1 UI unit = 1 screen pixel. Scaler does nothing.

- **Use for**: tools, debug HUDs, editor-only UI.
- **Don't use for**: shipping on mixed 1080p + 4K — UI looks tiny on 4K.

### Scale With Screen Size

Most common. Pick `Reference Resolution` + `Match`:

- **Match = 0 (Width)** — reference width fills screen width. Tall screens get extra vertical. Use when width-bounded (mobile portrait).
- **Match = 1 (Height)** — reference height fills screen height. Wide screens get extra horizontal. Use when height-bounded (mobile landscape, console HUD with fixed top/bottom).
- **Match = 0..1 (blend)** — blend width/height. `0.5` balanced default for orientation-agnostic HUDs.

Reference Resolution rules:
- Desktop — `(1920, 1080)` Match `0.5`.
- Mobile portrait — `(1080, 1920)` Match `0`.
- Mobile landscape — `(1920, 1080)` Match `1`.
- Tablet — `(2048, 1536)` or `(1620, 2160)` per target.

### Constant Physical Size

Scale by DPI; same physical size everywhere. Niche (tablet POS where finger must hit a 10mm target).

## Reference Pixels Per Unit

Pairs with sprite import `Pixels Per Unit`. Must match for sprites to render at authored size. Default `100` both sides.

## Mobile patterns

### Safe area (notches, cutouts)

`Screen.safeArea` returns the unobstructed Rect. Resample on a top RectTransform:

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

Attach to a child of root Canvas containing all UI inside the safe area. Pin its `offsetMin`/`offsetMax` to zero so anchors fully drive the rect.

### Orientation changes

Poll `Screen.orientation` in `Update`, or rebuild on `OnRectTransformDimensionsChange()`. The fitter above already covers this — `Screen.safeArea` updates with orientation.

## DPI-aware authoring

Phones with different densities (1× iPhone vs 3× iPhone) — Scale With Screen Size handles it. Tactile precision (banking, accessibility) — Constant Physical Size.

## World Space canvases

`CanvasScaler` on World Space only controls `Dynamic Pixels Per Unit` and `Reference Pixels Per Unit` — no resolution-matching mode (canvas is a 3D plane). Author at native pixel size (1920×1080 or whatever the signage requires); scale the Transform. Do NOT shrink `sizeDelta` to a few units (atlas blurs).

Set `Dynamic Pixels Per Unit` higher (e.g. `10`) for World Space text that must stay crisp up close.

## Gotchas

- Canvas with no `CanvasScaler` defaults to Constant Pixel Size — UI tiny on 4K. Add the component on the root Canvas.
- Reference + Match mismatch — `1080×1920` reference with `Match = 1` on landscape gives UI fitted to height (1080), so width is enormous. Match the orientation.
- Mixing Scale With Screen Size canvases with different reference resolutions in one scene = elements jumping when reparented. One reference resolution per project.
- `CanvasScaler.scaleFactor` — runtime read of current scale. Useful for debugging mismatched pixel-perfect art.

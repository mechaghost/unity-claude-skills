# TextMeshPro deep dive

Production pain hits in three places: atlas population, fallback chains, missing-glyph handling.

## Atlas Population Mode

Set per `TMP_FontAsset` (Generation Settings).

- **Static** — atlas baked at build time from the Font Asset Creator character set. Glyphs outside the set render as missing-glyph. Cheap at runtime.
- **Dynamic** — atlas grows at runtime as glyphs are requested. First encounter rasterizes + rebuilds. Required for runtime-unknown text (player names, chat, dynamic localization).

Pick:
- **Static** — fixed-language games with curated copy.
- **Dynamic** — localized, UGC, chat, leaderboards with foreign names.

Dynamic atlas caveats:
- Each fresh glyph triggers a rasterization spike on first appearance.
- Atlas size is fixed at asset creation. When full, glyph requests fail silently → missing-glyph.
- TMP 3.0+ `multiAtlasTexture` ON allocates additional pages instead of failing. Leave ON in production.
- Bad state after editor crash → `TMP_FontAsset.ClearFontAssetData(setAtlasSizeToZero: false)`. `true` resets dimensions (use to shrink after a glyph flood).

## Fallback font chains

When the active asset can't render a glyph, TMP walks fallbacks.

- **Per-asset** — `m_FallbackFontAssetTable` (Inspector → Fallback Font Assets), top-down, that asset only.
- **Global** — `TMP_Settings.fallbackFontAssets`, tried after per-asset, every font in the project.

Critical for:
- **CJK** — primary Latin + CJK fallback (NotoSansCJK).
- **Emoji** — sprite-based emoji asset as fallback for inline sprite emoji.
- **Symbol coverage** — currency, math, niche punctuation.

Order matters. First asset containing the glyph wins. Specific atlases first (curated chat sprites) before broad ones (NotoSans).

## SDF settings rules of thumb

`Window > TextMeshPro > Font Asset Creator`:

- **Sampling Point Size** — `90` for typical UI. Lower starves SDF; higher wastes atlas.
- **Padding** — ~10% of sample size (`9` for `90`). Padding = SDF range; outlines/dilations cannot extend beyond it.
- **Atlas Resolution** — `1024` typical, `2048` for CJK. Avoid `4096+` (mobile UI texture caps).
- **Render Mode**:
  - `SDFAA_HINTED` — small UI sizes (10–18 pt body). Hinting snaps baselines for crisp small text.
  - `SDFAA` — larger sizes (20+ pt headers, world-space). No hinting artifacts when scaled.
  - `SDF` (no AA) — rarely right for screen UI; for shader effects doing their own AA.

## Missing-glyph behavior

When a glyph isn't in the asset OR any fallback, TMP renders the **missing-glyph character** (default `.notdef` square box).

- Override globally: `TMP_Settings.missingGlyphCharacter` (codepoint int, e.g. `'?'` (63), `'_'` (95)).
- Detect at runtime: `TMP_Text.HasCharacters(string text, out List<char> missing)`. Use to gate UI on whether the font can render player input.
- Dynamic atlases: missing-glyph means rasterizer rejected the codepoint (no glyph in font). More atlas pages won't fix — add a fallback containing the codepoint.

## Rich-text tags

Most-used:
- `<b>`, `<i>`, `<u>`, `<s>` — bold, italic, underline, strikethrough.
- `<color=#RRGGBB>` / `<color=red>` — color override; closes with `</color>`.
- `<size=24>` / `<size=+4>` / `<size=80%>` — point size.
- `<sprite=N>` / `<sprite name="x">` — inline sprites from assigned Sprite Asset.
- `<link=id>...</link>` — links text to id; query `TMP_Text.textInfo.linkInfo` from a click handler.

Layout/spacing:
- `<voffset=8>` — vertical offset (super/subscript).
- `<cspace=2em>` — character spacing.
- `<mspace=1em>` — monospace mode.
- `<line-height=120%>` — line-height override.
- `<line-indent=10%>` / `<indent=15%>` — paragraph indent.
- `<page>` — hard page break (with Page overflow mode).
- `<nobr>...</nobr>` — disable word-wrap.

Effects:
- `<gradient=name>` — apply a `TMP_ColorGradient` asset.
- `<style=name>` — apply a `TMP_Style` from `TMP_Settings.defaultStyleSheet`.
- `<mark=#FFFF0080>` — highlighter behind span.
- `<rotate=45>` — per-character rotation.
- `<lowercase>`, `<uppercase>`, `<smallcaps>`, `<allcaps>` — case transforms.

**Closing rules**: most close with `</tag>`. `<sprite=N>` and `<page>` are self-closing. `<style>` closes with `</style>`. Unclosed tags persist; mismatched closes silently ignored. Verify by reading `TMP_Text.textInfo.characterCount` against visible count when debugging.

## RTL and Arabic shaping

TMP supports RTL (`isRightToLeftText = true`), but **Arabic shaping is NOT native**. Arabic glyphs change form by word position (initial/medial/final/isolated) and TMP doesn't run OpenType shaping. Result: disconnected, isolated glyphs.

Production:
- **ArabicSupport** (open-source) — preprocesses input into pre-shaped Unicode before assigning to `text`.
- **RTLTMPro** — TMP fork handling shaping, ligatures, bidi for Arabic/Persian/Hebrew. Community standard.

Plan integration from day one if targeting RTL. Native TMP RTL isn't enough.

## BaseMeshEffect

`BaseMeshEffect` is the post-tessellation mesh-modification hook. Built-in subclasses: `Shadow`, `Outline`, `PositionAsUV1`. Use for drop shadows, multi-pass outlines, color gradients.

```csharp
using UnityEngine;
using UnityEngine.UI;

[RequireComponent(typeof(Graphic))]
public class HorizontalGradient : BaseMeshEffect {
    public Color left = Color.white;
    public Color right = Color.black;

    public override void ModifyMesh(VertexHelper vh) {
        if (!IsActive() || vh.currentVertCount == 0) return;
        var verts = new System.Collections.Generic.List<UIVertex>();
        vh.GetUIVertexStream(verts);
        // find min/max X, lerp color per vertex, write back
        // ...
        vh.Clear();
        vh.AddUIVertexTriangleStream(verts);
    }
}
```

Effects stack in component order. Multiple effects each get a turn; expensive ones compound the per-frame mesh rebuild — keep counts small on dynamic text.

## TMP material presets

Each `TMP_FontAsset` ships a default material; **material presets** add separate materials sharing the atlas with different shader features (Outline, Glow, Underlay, Bevel). Authored under the Font Asset folder; assigned via Inspector → Main Settings → Material Preset.

- One font asset, many visual styles (`Body`, `Body_Outlined`, `Title_Glow`).
- Presets share the SDF atlas — adding presets doesn't duplicate atlas memory.
- Each preset = distinct material = distinct draw call. Mixing many on one Canvas breaks batching.

Common shader features:
- **Outline** — Face/Outline color, thickness ≤ padding-in-SDF-units.
- **Underlay** — drop/soft shadow; offset, dilate, softness.
- **Glow** — inner/outer with color and offset.
- **Bevel** — faux-3D rim, expensive — sparingly.

## Recovering poisoned Dynamic atlases

Bad states after:
- Editor crash mid-rasterization (partial glyph data persists).
- OOM atlas growth on low-end devices.
- Repeated TTF reimport without clearing.

Recovery:
```csharp
TMP_FontAsset font = ...;
font.ClearFontAssetData(setAtlasSizeToZero: false);
```

After Clear, atlas re-populates on demand. Pair with a smoke-test text exercising the expected character set so the atlas re-warms before the player sees empty UI.

Build-time prevention: `multiAtlasTexture = true` on every Dynamic Font Asset; ship with generous initial atlas size (1024 min, 2048 CJK).

## TMP_Settings shortcuts

`Window > TextMeshPro > Settings` opens the project-wide `TMP_Settings` asset under `Assets/TextMesh Pro/Resources/`.

- `defaultFontAsset` — assigned when a `TMP_Text` is added without an explicit Font Asset.
- `fallbackFontAssets` — global fallback chain.
- `missingGlyphCharacter` — global override.
- `defaultStyleSheet` — `TMP_StyleSheet` defining reusable `<style=name>` tags.
- `defaultSpriteAsset` — used when `<sprite=N>` referenced without `name="x"` lookup.
- `enableRaycastTarget` — project default for `raycastTarget` on new TMP_Text. Set `false` for projects where most text is non-interactive.

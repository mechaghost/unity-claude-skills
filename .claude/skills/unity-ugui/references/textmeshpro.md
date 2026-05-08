# TextMeshPro deep dive

TMP is the recommended UGUI text path. Most production pain with TMP is in three places: atlas population, fallback chains, and missing-glyph handling. This file covers the settings worth knowing in order of how often they bite.

## Atlas Population Mode

The most important TMP setting for any localized or user-text-driven game. Set on each `TMP_FontAsset` (Inspector under Generation Settings).

- **Static**: the atlas is baked at build time from the character set you specified in the Font Asset Creator. Glyphs not in the baked set render as the missing-glyph box. Cheap at runtime, no surprises in profiler.
- **Dynamic**: the atlas grows at runtime as new glyphs are requested. Required for runtime-unknown text — player names, chat, dynamic localization. The first time a glyph is encountered, TMP rasterizes it into the atlas and the text rebuilds.

**When to use which**:

- Static — fixed-language games with curated copy. Build the atlas with the exact character set used in the game.
- Dynamic — localized games, UGC, chat, leaderboards with foreign player names, or any text source you do not control at build time.

**Dynamic atlas growth caveats**:

- Each fresh glyph triggers a rasterization spike on the frame it first appears.
- The atlas texture has a fixed size (set when you create the asset). When it fills up, glyph requests start failing silently and characters render as missing-glyph.
- TMP 3.0+ exposes `multiAtlasTexture` on the Font Asset — when ON, TMP allocates additional atlas pages instead of failing. Leave ON for any Dynamic atlas in a production build.
- If a Dynamic atlas gets into a bad state (corrupt entries from a failed rasterization, common after editor crashes), call `TMP_FontAsset.ClearFontAssetData(setAtlasSizeToZero: false)` to flush. `setAtlasSizeToZero: true` resets the atlas dimensions as well — useful when shrinking back after a temporary glyph flood.

## Fallback font chains

When the active Font Asset cannot render a requested glyph, TMP walks a fallback chain.

- **Per-asset fallback list**: each `TMP_FontAsset` has a `m_FallbackFontAssetTable` (visible in the inspector under Fallback Font Assets). Filled top-down for that specific asset.
- **Global fallback list**: `TMP_Settings.fallbackFontAssets` (inspector field on the `TMP_Settings` asset) — fallbacks tried after the per-asset list is exhausted, for every Font Asset in the project.

**Critical for**:

- **CJK** (Chinese, Japanese, Korean) — primary Latin atlas plus a CJK fallback (NotoSansCJK is the standard).
- **Emoji** — a sprite-based emoji asset added as a fallback so emoji codepoints render as sprites inline.
- **Symbol coverage** — currency, math symbols, niche punctuation that the primary font omits.

Order matters: the first asset in the chain that contains the glyph wins. Put the more specific atlases first (project-curated chat sprites) before broad ones (NotoSans).

## SDF settings rules of thumb

When generating a Font Asset via `Window > TextMeshPro > Font Asset Creator`:

- **Sampling Point Size**: `90` for typical UI atlases. Lower starves SDF resolution; higher wastes atlas space.
- **Padding**: ~10% of Sampling Point Size — `9` for a `90` sample size. Padding is the SDF range; too low clips outlines and dilations, too high wastes atlas pixels. Outlines and underlay shaders cannot extend beyond the padding.
- **Atlas Resolution**: `1024` for most fonts, `2048` for very large character sets (CJK). Avoid `4096+` — many mobile GPUs cap UI texture size and large atlases hurt streaming.
- **Render Mode**:
  - `SDFAA_HINTED` for small UI sizes (10–18 pt body text). Hinting snaps glyph baselines to pixels for crisper small text.
  - `SDFAA` for larger sizes (20+ pt headers, world-space). Smoother curves, no hinting artifacts when scaled.
  - `SDF` (no AA) is rarely the right answer for screen UI; reserved for shader effects that do their own AA.

## Missing-glyph behavior

When a glyph is not found in the active asset OR any fallback, TMP renders it as the **missing-glyph character** (default: a square box, the font's `.notdef`).

- Override globally with `TMP_Settings.missingGlyphCharacter` (codepoint integer; e.g. `'?'` (63) or `'_'` (95)).
- Detect at runtime with `TMP_Text.HasCharacters(string text, out List<char> missing)` — returns false if any character in the input is not renderable, fills the `missing` list. Use this to gate UI on whether the current font can render player input before showing it.
- For Dynamic atlases, missing-glyph means the rasterizer rejected the codepoint (font has no glyph for it) — adding more atlas pages will not fix it. Add a fallback font that contains the codepoint.

## Rich-text tags

Most-used:

- `<b>`, `<i>`, `<u>`, `<s>` — bold, italic, underline, strikethrough.
- `<color=#RRGGBB>` / `<color=#RRGGBBAA>` / `<color=red>` — color override; closes with `</color>`.
- `<size=24>` (absolute) / `<size=+4>` / `<size=80%>` — point size.
- `<sprite=N>` / `<sprite name="x">` / `<sprite index=0>` — inline sprites from the assigned Sprite Asset.
- `<link=id>...</link>` — links text to an `id`; query `TMP_Text.textInfo.linkInfo` from a click handler.

Layout / spacing:

- `<voffset=8>` — vertical offset (raise/lower text); useful for superscript/subscript.
- `<cspace=2em>` — character spacing override.
- `<mspace=1em>` — monospace mode (every character occupies the same advance).
- `<line-height=120%>` — line-height override on this line forward.
- `<line-indent=10%>` / `<indent=15%>` — paragraph indent.
- `<page>` — hard page break (when used with the Page text overflow mode).
- `<nobr>...</nobr>` — disable word-wrap inside the span.

Effects:

- `<gradient=name>` — apply a `TMP_ColorGradient` asset.
- `<style=name>` — apply a `TMP_Style` from the Default Style Sheet (`TMP_Settings.defaultStyleSheet`).
- `<mark=#FFFF0080>` — highlighter behind the span.
- `<rotate=45>` — rotate each character in the span.
- `<lowercase>`, `<uppercase>`, `<smallcaps>` — case transforms.
- `<allcaps>` — alias of uppercase.

**Closing-tag rules**: most tags close with `</tag>` (no value). `<color=red>X</color>`. Unclosed tags persist to end-of-string. `<sprite=N>` and `<page>` are self-closing — no closing form. `<style>` closes with `</style>`. Mismatched closes are silently ignored, which makes typos hard to spot — verify by reading `TMP_Text.textInfo.characterCount` against the visible character count when debugging.

## RTL and Arabic shaping

TMP supports right-to-left layout (set `isRightToLeftText = true` or use the inspector toggle), but **Arabic shaping is NOT done natively**. Arabic glyphs change form depending on word position (initial / medial / final / isolated), and TMP does not run an OpenType shaping pass to pick the right contextual form. The result: Arabic text renders with disconnected, isolated glyphs.

Production options:

- **ArabicSupport** (open-source) — preprocesses the input string into pre-shaped Unicode forms before assigning to `TMP_Text.text`.
- **RTLTMPro** — TMP-targeted fork that handles shaping, ligatures, and bidi for Arabic / Persian / Hebrew. The community standard for Arabic TMP UI.

If the project targets any RTL market, plan on integrating one of these from day one. Native TMP RTL alone is not enough.

## BaseMeshEffect

`BaseMeshEffect` is the TMP / UGUI extension hook for post-tessellation mesh modifications. Built-in subclasses: `Shadow`, `Outline`, `PositionAsUV1`. Critical for custom UI styling — drop shadows, multi-pass outlines, color gradients across a single Text.

Custom effect skeleton:

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

Effects stack in component order on the GameObject. Multiple `BaseMeshEffect` components on the same Graphic each get a turn; expensive ones compound the per-frame mesh rebuild cost — keep effect counts small on dynamic text.

## TMP material presets

A `TMP_FontAsset` ships with one default material, but you can add **material presets** — each is a separate material that shares the atlas but enables different shader features (Outline, Glow, Underlay, Bevel). Authored under the Font Asset folder; assigned via the Inspector's Main Settings > Material Preset dropdown on `TMP_Text`.

- Use presets to keep one font asset and many visual styles (e.g. `Body`, `Body_Outlined`, `Title_Glow`).
- Presets share the SDF atlas, so adding presets does not duplicate atlas memory.
- Each preset is a distinct material → distinct draw call. Mixing many presets on one Canvas breaks batching the same way mixing materials does on regular UI.

Common shader features worth toggling on the preset:

- **Outline** (Face / Outline color, thickness ≤ padding-in-SDF-units).
- **Underlay** (drop shadow / soft shadow; offset, dilate, softness).
- **Glow** (inner / outer with color and offset).
- **Bevel** (faux-3D rim, expensive — sparingly).

## Recovering from poisoned Dynamic atlases

Dynamic atlases get into bad states after:

- Editor crashes mid-rasterization — partial glyph data persists between sessions.
- Out-of-memory atlas growth on low-end devices.
- Repeated import / re-import of the source TTF without clearing the atlas.

Recovery sequence:

```csharp
// Clears all dynamically-added glyphs and the atlas texture.
TMP_FontAsset font = ...;
font.ClearFontAssetData(setAtlasSizeToZero: false);
```

After a `Clear`, the atlas re-populates on demand the next time text using this asset is rendered. Pair this with a smoke-test text that exercises the expected character set so the atlas re-warms before the player sees an empty UI.

For build-time prevention: set `multiAtlasTexture = true` on every Dynamic Font Asset, and ship with a generous initial atlas size (1024 minimum, 2048 for CJK).

## TMP_Settings shortcuts

`Window > TextMeshPro > Settings` opens the project-wide `TMP_Settings` asset under `Assets/TextMesh Pro/Resources/`. Worth knowing:

- `defaultFontAsset` — the asset assigned when a `TMP_Text` is first added without an explicit Font Asset.
- `fallbackFontAssets` — global fallback chain (covered above).
- `missingGlyphCharacter` — global override (covered above).
- `defaultStyleSheet` — `TMP_StyleSheet` asset that defines reusable `<style=name>` tags.
- `defaultSpriteAsset` — sprite asset used when `<sprite=N>` is referenced without a `name="x"` lookup.
- `enableRaycastTarget` (default for new TMP_Text) — the project default for `raycastTarget` on freshly added text. Set to `false` for projects where most text is non-interactive — avoids forgetting to toggle each instance.

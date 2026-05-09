---
name: unity-localization
description: 'Use when localizing a Unity game with the official Unity Localization package through Unity MCP — localization, l10n, i18n, internationalization, translation, locale, language, com.unity.localization, Unity Localization, LocalizationSettings, StringTable, AssetTable, LocalizedString, LocalizedAsset, smart string, plural, gender, RTL, right-to-left, Arabic, Hebrew, CJK, Chinese, Japanese, Korean, font fallback, language switch, locale switch, .po, .csv import, Smart Format, ICU. Disambiguator — NOT for store metadata localization (use unity-store-shipping-pipeline), NOT for legacy `Resources/Localization/` (use Unity Localization package). Unity 6+ / 6000.x, URP-only, new Input System only.'
---

Companion skills: `unity-ugui` (TMP font fallback setup), `unity-addressables` (lazy-load locale-specific bundles), `unity-persistence` (save chosen locale via PlayerPrefs), `unity-store-shipping-pipeline` (store listing localization), `unity-best-practices` (foundational MCP rules).

## When to use

- Adding multi-language support to a game that currently ships English-only.
- Authoring string tables, asset variants, or smart-format pluralization for an existing project.
- Wiring a settings UI that lets the player switch language at runtime.
- Diagnosing missing CJK glyphs, broken Arabic shaping, or `LocalizedString` fields that fail to update.

## Why localize

Shipping English-only caps your TAM hard. Spanish + Portuguese (BR) + Simplified Chinese + Japanese alone roughly doubles mobile install reach compared to EN-only, with low translation cost relative to the install lift. In Unity 6, `com.unity.localization` is the official, supported solution. The popular community asset (I2 Localization) is now legacy — start new projects on `com.unity.localization`.

## Package install

Add `com.unity.localization` via the package manager. After install, open `Window > Asset Management > Localization Tables` and `Edit > Project Settings > Localization`.

## Project setup

- Create a `LocalizationSettings` asset: `Assets > Create > Localization > Localization Settings`. Drag it into `Project Settings > Localization > Active Localization Settings`.
- Add Locales for each shipped language via `Assets > Create > Localization > Locale` — `en`, `es`, `pt-BR`, `fr`, `de`, `ja`, `zh-Hans`, `zh-Hant`, `ko`, `ar`, etc. Locales register themselves in `LocalizationSettings`.
- Set the default locale for both editor preview and runtime under `Project Settings > Localization > Locale Selectors`.

## String tables

- Create a `Localized String Table Collection`: `Assets > Create > Localization > String Table Collection`. One collection per logical group (`UI`, `Dialogue`, `Items`) — keeps merges and reviews scoped.
- Each collection contains one `StringTable` asset per locale, all sharing the same key set. Edit through the **Localization Tables** window: rows are keys, columns are locales.
- Use stable, scoped keys (`ui.title`, `dialog.greet.morning`). Renaming a key breaks every reference unless you also retag.

## Smart strings (Smart Format / ICU-style)

Unity Localization ships SmartFormat. Toggle "Smart" on a row to enable.

- Plural: `"You have {0:plural:no items|one item|{} items}"` — picks form by count.
- Gender: `"{0:gender:He|She|They} entered the room"`.
- Number formatting: `"{0:N0}"` renders `1,234,567` per locale.
- Date: `"{0:d}"` for locale-aware short date.
- Reference: https://github.com/axuno/SmartFormat

Smart Format syntax errors render the literal pattern silently — test every locale.

## Asset tables

- Asset Table Collections cover textures, audio, sprites, prefabs — different asset per locale. Use them for localized button images, voiced lines, region-specific icons.
- On a MonoBehaviour: `[SerializeField] LocalizedSprite icon;` — Inspector lets you pick the per-locale variant.
- Asset variants ship in the build by default. For 50MB Korean voice packs, route through Addressables (see Gotchas).

## Locale selection and detection

- Auto-detect on first launch via the default `SystemLocaleSelector` — maps `Application.systemLanguage` to the closest registered locale.
- User override (settings dropdown):

```csharp
var locales = LocalizationSettings.AvailableLocales.Locales;
LocalizationSettings.SelectedLocale = locales[index]; // refreshes all bound listeners
```

- Persist the choice via `PlayerPrefs` and restore in a boot scene before any UI binds (cross-link `unity-persistence`).

## Font fallback for CJK and Arabic

- A Latin TMP font asset has zero CJK glyphs. Without fallback, Japanese / Chinese / Korean text renders as empty boxes.
- Build separate font assets per script: `JP_Font.asset`, `CN_Hans_Font.asset`, `KR_Font.asset`. Add each to the **Fallback Font Asset List** on your primary Latin font asset (TMP Font Asset Inspector → Fallback Font Assets).
- At runtime, TMP walks the chain when the main atlas misses a glyph — extra cost is negligible if the atlas is warmed.
- Memory: a Simplified Chinese font with full glyph coverage is 30,000+ characters and routinely 30–50MB at static atlas sizes. Two ways to manage:
  - **Dynamic atlas mode** — TMP rasterizes glyphs as they appear. Small initial footprint, occasional first-use hitches. Default for mobile.
  - **Per-region builds** — ship CN/JP/KR fonts only in their store builds via Addressables groups gated by locale.
- See `unity-ugui` for TMP font asset creation and dynamic atlas tuning.

## RTL handling (Arabic / Hebrew)

- RTL requires both reading-direction reversal AND **contextual shaping** — Arabic letters change form by position (initial / medial / final / isolated).
- TMP does NOT do shaping natively. Pull in `RTLTMPro` (recommended, MIT) or `ArabicSupport` from the Asset Store. Without one, Arabic renders as disconnected, mirrored letters — unreadable.
- Layout: mirror the UI for RTL locales — anchors flip, text alignment flips, ScrollRect direction flips, page-turn arrows swap. Use RTL-aware layout groups or a `LocaleEvent` listener that flips `RectTransform.anchorMin/Max` on locale change.
- Test RTL **early**. Retrofitting an EN-first hierarchy is expensive — every screen needs review.

## Importing translations

- **CSV / Google Sheets** — `Localization Tables` window → `Import / Export`. Round-trip with translators using a shared sheet; Unity preserves keys and metadata.
- **.po (gettext)** — industry-standard format; most CAT tools and freelancers accept it.
- **XLIFF** — enterprise / TMS workflows (CrowdIn, Lokalise, POEditor, Phrase).
- Standard workflow: export → translator edits offline → import → in-engine review → ship.

## Common patterns

- `LocalizedString` field with auto-update:

```csharp
[SerializeField] LocalizedString welcome;
[SerializeField] TMP_Text label;
void OnEnable()  { welcome.StringChanged += OnWelcomeChanged; }
void OnDisable() { welcome.StringChanged -= OnWelcomeChanged; }
void OnWelcomeChanged(string s) => label.text = s;
```

- Pluralization with arguments:

```csharp
var args = new object[] { itemCount };
coinsLabel.text = coinsString.GetLocalizedString(args);
```

- Live language switch — assigning `LocalizationSettings.SelectedLocale` triggers `StringChanged` on every bound `LocalizedString` and reloads `LocalizedAsset` references.
- Translation keys as constants for refactor safety:

```csharp
static class L { public const string GameTitle = "ui.title"; }
```

## Gotchas

- **No fallback fonts** — CJK locales show blank boxes. CN especially needs 30k+ glyph coverage.
- **No RTL plugin** — Arabic looks like disconnected letters. TMP alone is not enough.
- **Translations stored in code** — unmaintainable across 10 locales. Always use string tables.
- **Smart Format syntax errors** — render the literal pattern silently. Validate per-locale.
- **`LocalizedString` semantics** — the field stores a *reference* (table + key), not the resolved value. Designing ScriptableObjects? Serialize `LocalizedString`, not `string`.
- **Asset variants ship every locale** — a 200MB voice-over set ships 5x in build. Route locale-specific assets through Addressables groups (cross-link `unity-addressables`).
- **System language regional misses** — `SystemLocaleSelector` does not always disambiguate `zh-Hans` vs `zh-Hant`, or `pt-BR` vs `pt-PT`. Provide a manual override on first launch.
- **Empty translations fall back silently** — QA must explicitly catch missing strings; configure "missing translation" log level in Localization settings.
- **Editor preview vs runtime drift** — editor locale may differ from build start locale. Add a debug menu to lock locale during QA.

## Verification

- Switch locale at runtime → every bound `LocalizedString` and `LocalizedAsset` updates without a scene reload.
- CJK locale → fallback chain renders glyphs; no boxes in any UI screen.
- Arabic locale → reads right-to-left with proper contextual shaping; mirrored layout.
- Smart Format → plural / gender / `{0:N0}` / `{0:d}` render correctly per locale.
- `LogAssert` clean — no "missing translation key" warnings (level configurable in Localization settings).
- Build size — verify per-locale CJK font additions show up in the build report; over budget? Move to Addressables.

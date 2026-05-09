# URP post-processing reference

Edit Volume Profile overrides through PP tooling or by editing the `.asset`. Checkbox per parameter — only ticked override; unticked inherit from lower-priority volumes or defaults.

## Effect catalog

- **Tonemapping** — HDR → LDR. Requires HDR + `Grading Mode = HDR`. **Neutral** safe default; **ACES** cinematic (pairs with bloom); **Custom (External LUT)** via Color Lookup.
- **Bloom** — HDR-only. Threshold gates pixels; intensity scales; scatter controls radius/softness. Cinematic: intensity 0.8–1.2, threshold 0.9–1.2, scatter 0.6–0.8. Mobile/stylized: lower intensity, higher threshold, or off. Dirt Texture + Dirt Intensity adds lens-dirt streaks.
- **Color Adjustments** — Post-exposure (EV stops), Contrast, Color Filter (multiply), Hue Shift, Saturation. First stop in any grade.
- **White Balance** — Temperature + Tint. Neutralize lighting bias before further grading.
- **Channel Mixer** — per-output-channel mix of RGB. Sepia, two-tone, false-color.
- **Lift Gamma Gain** — three-way: Lift (shadows), Gamma (mids), Gain (highlights). Color wheel + intensity each.
- **Shadows Midtones Highlights** — like Lift Gamma Gain with explicit shadow/highlight start/end ranges. More precise when boundaries matter.
- **Split Toning** — tint shadows one color, highlights another, with balance. Cheap moody look.
- **Color Curves** — per-channel + luma/sat/hue curves. Fine-grained finishing.
- **Color Lookup** — external LUT (Photoshop / DaVinci) blended by Contribution.
- **Vignette** — Center, Intensity, Smoothness, Roundness, Rounded toggle.
- **Depth of Field** — **Gaussian** cheap fixed-radius blur (mobile-friendly, Start/End); **Bokeh** physically-based, expensive.
- **Motion Blur** — camera (not per-object). Quality, Intensity, Clamp.
- **Film Grain** — Type (Thin1/Thin2/Medium1/Medium2/Large01/Large02/Custom) + Intensity + Response.
- **Lens Distortion** — Intensity, Center, X/Y multipliers, Scale.
- **Chromatic Aberration** — RGB offset at frame edges. 0.1–0.3 subtle; 0.5+ stylized.
- **Panini Projection** — wide-FOV correction; reduces stretching at FOV >70 near edges.
- **Lens Flare (SRP)** — component-based flares (`LensFlareComponentSRP`). Configured per-light; visibility participates in the PP stack.

## Recommended profile templates

### "Default desktop"
HDR on. Tonemapping = Neutral. Color Adjustments post-exposure 0. Vignette intensity 0.2 smoothness 0.4. No bloom. Project Global Volume baseline.

### "Cinematic"
HDR on. Tonemapping = ACES. Bloom intensity 1.0 / threshold 1.1 / scatter 0.7. Color Adjustments post-exposure +0.3, contrast +5, saturation +5. White Balance temp +5. Vignette intensity 0.25 smoothness 0.35. Film Grain Thin1 intensity 0.2.

### "Mobile"
HDR off. Grading Mode = LDR. Tonemapping = Neutral. No Bloom. Color Adjustments contrast +5 saturation +10. No Vignette (LDR banding risk). FXAA on the camera (not a volume override).

### "Cave / dark zone" (Local Volume)
Override post-exposure −1.5. Vignette intensity 0.5 smoothness 0.5. Color Adjustments color filter slight blue. Local Volume with trigger Collider matching cave bounds; Blend Distance ~3 m for smooth transition.

### "Underwater" (Local Volume)
Color Adjustments color filter blue-green. Chromatic Aberration intensity 0.4. Lens Distortion intensity −0.1 (slight pinch). Optional Vignette tint blue.

## Authoring tips

- Project Global Volume profile minimal — tonemapping + baseline grade. Layer specifics in Local Volumes.
- Higher Priority wins ties; stacked Local Volumes (cave in level in world): set Priority by specificity (world=0, level=10, cave=20).
- Uncheck individual parameters rather than deleting overrides — keeps inheritance obvious.
- After editing a profile, capture a Game-view screenshot for the reference library. Grading regressions are easy to miss without a baseline.
- A/B: duplicate profile, swap on Volume's `Profile` slot, screenshot, swap back. Faster than toggling overrides.

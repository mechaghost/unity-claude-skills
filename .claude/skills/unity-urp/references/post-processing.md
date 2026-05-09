# URP post-processing reference

Edit Volume Profile overrides through post-processing tooling or by editing the Volume Profile `.asset` directly. Each override has a checkbox per parameter — only ticked parameters override; unticked ones inherit from lower-priority volumes or defaults.

## Effect catalog

### Tonemapping
Maps HDR scene values into LDR display range. Requires HDR enabled on the pipeline asset and `Grading Mode = HDR`.
- **Neutral** — minimal hue shift, broad dynamic range; safe default.
- **ACES** — film-style contrast/saturation, deeper shadows. The cinematic default. Pairs with bloom.
- **Custom (External LUT)** — Color Lookup override drives the final color transform via a LUT texture.

### Bloom
HDR-only quality. Threshold gates which pixels bloom; intensity scales the result; scatter controls the radius/softness.
- Cinematic: intensity 0.8–1.2, threshold 0.9–1.2, scatter 0.6–0.8.
- Mobile / stylized: lower intensity, higher threshold, or off.
- Dirt Texture + Dirt Intensity adds lens-dirt streaks.

### Color Adjustments
Post-exposure (EV stops), Contrast, Color Filter (multiply), Hue Shift, Saturation. The first stop on any grading pass.

### White Balance
Temperature (warm/cool) and Tint (green/magenta). Use to neutralize the lighting model's bias before further grading.

### Channel Mixer
Per-output-channel mix of input RGB. Heavy color reinterpretation (sepia, two-tone, false-color).

### Lift Gamma Gain
Three-way grade — Lift (shadows), Gamma (midtones), Gain (highlights). Each with color wheel + intensity.

### Shadows Midtones Highlights
Similar three-way split with explicit shadow/highlight start/end ranges. More precise than Lift Gamma Gain when the boundaries matter.

### Split Toning
Tint shadows one color, highlights another, with a balance slider. Cheap moody look.

### Color Curves
Per-channel and luma/sat/hue curves. The fine-grained finishing tool.

### Color Lookup
Sample an external LUT texture (typically authored in Photoshop / DaVinci) and blend by Contribution.

### Vignette
Darkens (or color-tints) frame edges. Center, Intensity, Smoothness, Roundness, Rounded toggle.

### Depth of Field
- **Gaussian** — cheap, fixed-radius blur; mobile-friendly. Start/End range.
- **Bokeh** — physically-based aperture/focal-length/blade-count; far more expensive.

### Motion Blur
Camera motion blur (not per-object). Quality (Low/Med/High), Intensity, Clamp.

### Film Grain
Type (Thin1/Thin2/Medium1/Medium2/Large01/Large02/Custom) + Intensity + Response (luminance falloff).

### Lens Distortion
Barrel / pincushion warp. Intensity, Center, X/Y multipliers, Scale.

### Chromatic Aberration
RGB channel offset at frame edges. Intensity 0.1–0.3 is subtle; 0.5+ is stylized.

### Panini Projection
Wide-FOV correction; reduces the stretching that perspective FOV >70 produces near edges. Distance + Crop To Fit.

### Lens Flare (SRP)
Component-based lens flares (`LensFlareComponentSRP` on a light or transform). Configured per-light, not as a Volume override — but lens-flare visibility participates in the post-process stack.

## Recommended profile templates

### "Default desktop"
HDR on. Tonemapping = Neutral. Color Adjustments post-exposure 0. Vignette intensity 0.2 smoothness 0.4. No bloom. Used as the project Global Volume baseline.

### "Cinematic"
HDR on. Tonemapping = ACES. Bloom intensity 1.0 / threshold 1.1 / scatter 0.7. Color Adjustments post-exposure +0.3, contrast +5, saturation +5. White Balance temp +5. Vignette intensity 0.25 smoothness 0.35. Film Grain Thin1 intensity 0.2.

### "Mobile"
HDR off. Grading Mode = LDR. Tonemapping = Neutral. No Bloom. Color Adjustments contrast +5 saturation +10. No Vignette (banding risk on LDR). FXAA on the camera (not a volume override).

### "Cave / dark zone" (Local Volume)
Override post-exposure −1.5. Vignette intensity 0.5 smoothness 0.5. Color Adjustments color filter slight blue. Place a Local Volume with a trigger Collider matching the cave bounds; set Blend Distance ~3m for a smooth transition.

### "Underwater" (Local Volume)
Color Adjustments color filter blue-green. Chromatic Aberration intensity 0.4. Lens Distortion intensity −0.1 (slight pinch). Optional Vignette tint blue.

## Authoring tips

- Keep the project Global Volume profile minimal — just tonemapping + a baseline grade. Layer specifics in Local Volumes.
- Higher Priority wins ties; for stacked Local Volumes (cave inside a level inside a world), set Priority by specificity (world=0, level=10, cave=20).
- Toggle individual parameters off (uncheck) rather than deleting the override — keeps inheritance behavior obvious.
- After editing a profile, capture a Game-view screenshot for the project's reference shot library. Grading regressions are easy to miss without a baseline.
- For A/B comparisons, duplicate the profile, swap on the Volume's `Profile` slot, screenshot, swap back. Faster than toggling individual overrides.

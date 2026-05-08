---
name: unity-audio
description: Use when working with Unity audio through Unity MCP — AudioSource, AudioClip, AudioListener, AudioMixer, AudioMixerGroup, snapshot, exposed parameter, ducking, spatial blend, 3D sound, 2D sound, doppler, rolloff, audio settings, mute, volume slider, music, SFX, ambient loop, footstep, hit sound, OnAudioFilterRead, mobile audio, WebGL audio, audio context unlock, audio interruption, AudioSettings.outputSampleRate, audio compression, AudioImporter, .ogg, .wav, .mp3.
---

## When to use

Any audio task: playing SFX, looping music, building a mixer hierarchy, hooking a UI volume slider to a Group, ducking music under dialogue, wiring snapshots, importing AudioClips with the right compression, debugging multiple-AudioListener warnings, or chasing mobile/WebGL audio bugs (interruptions, context unlock, background mute). Read `unity-best-practices` first for the project paradigm primer; cross-link `unity-scenes` when audio crosses scene boundaries and `unity-animation` for AnimationEvent-driven SFX.

## AudioSource basics

`AudioSource` is the per-object playback component. Add via `manage_components`. Inspector fields and what they actually do:

- AudioClip — the asset to play. Required for `Play()` / loops; optional for `PlayOneShot(clip)`.
- Output — `AudioMixerGroup` to route through. Leave empty and audio bypasses the mixer (no Master volume control). Almost always set this.
- Mute / Bypass Effects / Bypass Listener Effects / Bypass Reverb Zones — debug and special-case toggles. Bypass Listener Effects is useful for UI clicks that should not be affected by an "underwater" listener filter.
- Play On Awake — fires `Play()` automatically. Disable for triggered/pooled SFX.
- Loop — restart at end. PlayOneShot ignores this.
- Priority (0-256, lower = more important). Unity caps simultaneous voices (default 32, see `Project Settings > Audio > Real Voice Count`); when capped, lowest-priority voices are virtualized.
- Volume (0-1), Pitch (-3 to 3), Stereo Pan (-1 to 1).
- Spatial Blend — 0 = pure 2D (UI/music), 1 = pure 3D (worldspace SFX). Curve-mappable.
- Reverb Zone Mix — how much AudioReverbZone affects this source.
- 3D Sound Settings — Doppler Level, Spread, Volume Rolloff (Logarithmic/Linear/Custom), Min Distance, Max Distance.

Code:

```csharp
audioSource.PlayOneShot(clip, volume); // fire-and-forget; multiple overlap cleanly
audioSource.Play();                    // for looping or stateful clips (music, ambience)
audioSource.Stop();                    // halts and rewinds
audioSource.Pause(); audioSource.UnPause();
```

`PlayOneShot` does NOT respect Loop and is NOT cut off by a subsequent `Play()` — the perfect tool for overlapping SFX (footsteps, hit sounds).

## AudioListener (one rule)

Exactly ONE `AudioListener` per scene. Default location: Main Camera (`manage_camera`). Two listeners spam the console with "There are 2 audio listeners in the scene…" and Unity arbitrarily uses the first found — audio routing changes are silently ignored.

Place on the player instead of the camera for top-down games (where camera sits high above), split-screen (per-player), or first-person where camera and player are the same anchor anyway. Use `manage_scene` to verify there is one and only one listener.

Note: `AudioListener.pause = true` halts ALL audio without touching `Time.timeScale`. `AudioListener.volume` is a final 0-1 multiplier on everything.

## AudioMixer architecture

Create with `manage_asset` — `Assets > Create > Audio > Audio Mixer`. A mixer asset holds an audio Group hierarchy; everything terminates at Master.

- AudioSources route via `Output` → AudioMixerGroup.
- Groups can route to a parent Group: typical layout is `Master → {Music, SFX, UI, Voice, Ambience}` and SFX may have children `SFX_Player`, `SFX_World`, `SFX_Enemy`.
- Per-Group effects: Lowpass, Highpass, Reverb, Compressor, Duck Volume, Send/Receive (sidechain). Add via the Mixer window's Effects panel; the underlying serialization is a child of the mixer asset.
- Multiple mixers per project are valid for layered routing — e.g. a `DialogueMixer` whose Master routes into the main mixer's Voice group.

## Exposed parameters and volume sliders

To control any mixer parameter from script (volumes, cutoff frequencies, send levels): in the Mixer window, right-click the parameter (Volume slider, effect knob) → "Expose '…' to script" → rename in the Exposed Parameters dropdown (top-right of the window) to a stable key like `MasterVolume`.

Mixer volume is in **decibels**: 0 dB = full, -80 dB = silence floor. Humans hear loudness logarithmically — multiplying a 0-1 slider value linearly into dB feels wrong (most of the perceptual range crammed into the bottom 20%). Convert:

```csharp
[SerializeField] AudioMixer mixer;

public void SetMasterVolume(float linear01) // from a UI Slider 0..1
{
    float dB = (linear01 > 0.0001f) ? Mathf.Log10(linear01) * 20f : -80f;
    mixer.SetFloat("MasterVolume", dB);
}
```

The clamp at `0.0001f` is mandatory — `Mathf.Log10(0)` is `-Infinity` and `SetFloat(-Infinity)` corrupts the parameter. Persist the linear value to PlayerPrefs (cross-link `unity-persistence` once it exists) and re-apply on Awake.

## Snapshots and ducking

Snapshots capture all mixer parameter values at a moment — they are named presets stored in the mixer asset. Use them for whole-mix state changes: `Normal`, `Underwater` (lowpass + reverb), `Menu` (music up, SFX down), `Combat` (compressor harder, music up).

```csharp
mixer.FindSnapshot("Combat").TransitionTo(0.5f); // 0.5s crossfade between snapshots
```

Ducking — make music dip when dialogue plays — has two implementations:

- Sidechain compressor: add a `Duck Volume` effect to the Music group; add a `Send` from the Voice group routed to that Duck Volume's sidechain input. Voice level above the Threshold attenuates Music in real time.
- Snapshot pair: `Normal` snapshot has Music at 0 dB; `Dialogue` has Music at -20 dB. `TransitionTo` on dialogue start/end. Simpler to author, less responsive than a real compressor.

## 3D vs 2D sound

`Spatial Blend` is the dial. 0 = 2D (no positioning, plays at full volume regardless of distance, panned as authored). 1 = 3D (rolloff curve, doppler, listener-relative pan).

- Music, UI, narration, stingers — Spatial Blend 0.
- World SFX (footsteps, gunshots, ambient props) — Spatial Blend 1.
- Logarithmic rolloff (default) is the realistic choice. Linear feels gamier — sound stays loud out to Max Distance then snaps off. Custom curves are useful for "always audible but localized" cues.
- Min Distance — full volume below this radius. Max Distance — silent past this (Logarithmic still tapers, Linear hits zero exactly).
- Doppler Level — set to 0 for fast-moving objects unless you specifically want pitched whoosh; at 1 you get comedic pitch shifts on projectiles.

## AudioClip import settings

Configure via `manage_asset` on each clip. The fields that matter:

- **Load Type**:
  - `Decompress On Load` — small clips, decoded once at load, low CPU at runtime, higher RAM. Default for short SFX.
  - `Compressed In Memory` — kept compressed, decoded each `Play()`. Save RAM at CPU cost; bad for high-frequency SFX.
  - `Streaming` — read from disk during playback. Use for music and long ambience (clip > ~200 KB). Streaming sources can NOT play in parallel with each other (one decoder per source).
- **Compression Format**:
  - `PCM` — uncompressed, fastest decode, biggest file. Reserve for tiny critical SFX.
  - `ADPCM` — fixed 4:1 ratio, very cheap decode, slight quality loss. Good for noisy/looping SFX.
  - `Vorbis` — variable bitrate, best for music/long clips. Quality 50-70 for most uses; 100 only for hero music.
- **Force To Mono** — enable for SFX. Halves memory; stereo on a single SFX is usually wasted.
- **Sample Rate Setting** — `Optimize Sample Rate` (auto, recommended), or `Override Sample Rate`: 22050 Hz for SFX, 44100 Hz for music. 48000 Hz only when source material warrants it.
- **Preload Audio Data** — load the asset header at scene load. Combine with non-streaming clips. Streaming + Preload = wasted memory.
- **Load In Background** — async load; used with Streaming.
- **Per-platform overrides** — open the platform tab (Standalone / iOS / Android / WebGL) and override compression more aggressively for mobile (Vorbis q40-50) and WebGL (always Vorbis — see WebGL gotchas).

## Music vs SFX patterns

- Music: Streaming load type, Vorbis q50-70, looping AudioSource on a `Music` group, crossfade between two AudioSources lerping volume. `ignoreListenerPause = true` so it survives pause menus.
- SFX: Decompress On Load, ADPCM or short Vorbis, output to `SFX` group. Use `PlayOneShot` so overlapping plays don't stomp.
- Footsteps / repeating impacts: pool a small array of AudioSources and round-robin them. Avoid `AudioSource.PlayClipAtPoint` in tight loops — it instantiates a temporary GameObject per call.

## Mobile gotchas

- Audio interruption (incoming call, Siri, Music app): `AudioSettings.OnAudioConfigurationChanged` fires. After interruption, music often needs to be restarted from `OnApplicationFocus(true)`.
- Background mute: by default Unity mutes audio when backgrounded. Set `Application.runInBackground = true` AND configure platform session (iOS `AVAudioSession.Category` via a plugin, Android `AudioFocus`).
- Sample rate cost — 44100 Hz on every clip adds up. Force SFX to 22050.
- DSP buffer size — `Project Settings > Audio > DSP Buffer Size` via `manage_editor`. `Best latency` for action games (lower buffer = lower latency, more CPU); `Default` for most; `Best performance` for low-end / battery-sensitive devices.
- Memory: streaming music + a dozen Compressed-In-Memory SFX is the right shape. PCM everywhere will OOM on low-end Android.

## WebGL gotchas

- Audio context unlock: browsers block audio until the user interacts (click/tap). First user input unlocks; until then `Play()` calls return silence. Build a "Click to Start" gate on the title screen.
- No threads: AudioClip decode runs on the main thread. Streaming long clips can stutter — for short SFX prefer Decompress On Load even if it costs RAM.
- Format: Unity WebGL plays OGG Vorbis. MP3 is sometimes excluded for licensing; do not rely on it. Force Vorbis on the WebGL platform tab.
- `AudioSource.timeSamples` precision varies between browsers. Don't rely on sample-accurate sync; use `time` and `clip.length` with a tolerance.

## Pause and time-scale interaction

- `Time.timeScale = 0` does NOT pause audio — audio runs on real time (`unscaledDeltaTime`).
- Pause everything: `AudioListener.pause = true`. Resume with `false`.
- Pause one source: `audioSource.Pause()` / `UnPause()`.
- Music and UI clicks should usually keep playing during pause menus — set `audioSource.ignoreListenerPause = true` on those sources.
- For physics-coupled audio (engine pitch by speed, wheel hum), drive `pitch` from a value updated in `FixedUpdate` / using `Time.fixedUnscaledDeltaTime` so it pauses cleanly with the game.

## Common patterns

- **Volume slider**: UI Slider (0-1) → log10-to-dB (formula above) → `mixer.SetFloat("MasterVolume", dB)`. Save linear 0-1 to PlayerPrefs `OnValueChanged`; load and apply on Awake. Repeat per group (Master / Music / SFX). See `references/audio-manager.md`.
- **AudioManager singleton**: a `DontDestroyOnLoad` GameObject with `PlaySFX(clip, position?)` / `PlayMusic(clip, fadeSec)` / `SetVolume(group, linear01)`. Pool 8-16 SFX AudioSources and round-robin them. Full pattern in `references/audio-manager.md`.
- **Spatial 3D one-shot**: instantiate a temporary GameObject at the impact point with an AudioSource (Spatial Blend 1, Output = SFX group), `PlayOneShot`, destroy after `clip.length`. Or `AudioSource.PlayClipAtPoint(clip, position)` — convenient but allocates per call. Pool if frequent.
- **Footstep system**: `AnimationEvent` on the foot-down keyframe calls `PlayFootstep(surfaceTag)`; surface tag indexes a sound bank ScriptableObject. Cross-link `unity-animation`.
- **Music crossfade**: two AudioSources A (current) and B (next). On track change, lerp A.volume → 0 and B.volume → 1 over ~1 s, `B.Play()` at start of lerp, `A.Stop()` when done. Snippet in `references/audio-manager.md`.
- **Ducking via snapshot**: author `Normal` and `Dialogue` snapshots (Music at 0 dB and -20 dB respectively); transition on dialogue start/end with `TransitionTo(0.3f)`.

## Gotchas

- Multiple AudioListeners — console spam, no audio routing changes (Unity uses the first found). Always exactly one. Common after additive scene loads (cross-link `unity-scenes`); strip listeners off non-primary scenes.
- `PlayOneShot` ignores AudioSource Loop and Play On Awake — by design, but surprises people. Also bypasses some 3D settings if the source has no clip assigned; assign a placeholder clip.
- `mixer.SetFloat` before the AudioMixer is loaded fails silently. Apply in `Awake` / `Start` after the mixer asset is referenced, not in field initializers.
- Linear-to-dB: `0` linear must clamp to `-80f` dB (Unity's silence floor). `Mathf.Log10(0) = -Infinity` will corrupt the parameter.
- Compressed In Memory clips pay decode CPU on every Play — bad for short, frequently-played SFX. Use Decompress On Load for those.
- Streaming clips can't play in parallel — one decoder per AudioSource, so two simultaneous Streaming plays = stutter or silence. Music is fine because it's typically a single source.
- `AudioSource.outputAudioMixerGroup` set in code overrides the Inspector value but resets when a prefab is re-instantiated. Set it on the prefab, not after spawn.
- Preload Audio Data + Streaming = memory bloat. Only Preload non-streaming clips.
- Pink-equivalent for audio: a missing AudioMixerGroup reference (mixer asset deleted/renamed) silently routes to Master and your group volume slider does nothing.
- AudioReverbZone is global to the listener — moving the listener through one affects every 3D source, not just sources inside the zone.

## Verification

- `read_console` immediately after configuration. Watch for "There are 2 audio listeners…", "AudioMixer parameter '…' not exposed", "Cannot find AudioMixerGroup", null clip warnings.
- Volume slider sanity: log the dB value as the slider moves. Should be roughly `-80` at 0, `-20` near 0.1, `-6` near 0.5, `0` at 1. If the curve feels flat or cliff-edged, the linear-to-dB conversion is wrong.
- Mixer routing visible: select an AudioSource and confirm `Output` is the intended Group; press Play (Edit mode is fine if `Edit > Project Settings > Audio > Disable Audio` is unchecked) and watch level meters move on the right Group.
- WebGL: build, open in a browser tab, confirm the first tap/click unlocks audio. Test in an incognito window to avoid cached gestures.
- `manage_profiler` — Audio module shows active sources, voices used, and memory. Voices capped at `Project Settings > Audio > Real Voice Count` (default 32). Ramping into the cap manifests as quiet sounds dropping.
- For 3D sources, walk past Min Distance and confirm rolloff curve matches intent. Doppler issues are most obvious on fast-moving projectiles — turn Doppler Level to 0 if unwanted pitch slides appear.
- After scene transitions (cross-link `unity-scenes`), re-check listener count and that music sources with `ignoreListenerPause` survived as intended.

---
name: unity-audio
description: 'Use when working with Unity audio through Unity MCP — AudioSource, AudioClip, AudioListener, AudioMixer, AudioMixerGroup, snapshot, exposed parameter, ducking, spatial blend, 3D sound, 2D sound, doppler, rolloff, audio settings, mute, volume slider, music, SFX, ambient loop, footstep, hit sound, OnAudioFilterRead, mobile audio, WebGL audio, audio context unlock, audio interruption, AudioSettings.outputSampleRate, audio compression, AudioImporter, .ogg, .wav, .mp3. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

SFX, looping music, mixer hierarchy, UI volume sliders, ducking, snapshots, AudioClip import, multiple-listener warnings, mobile/WebGL bugs (interruptions, context unlock, background mute).

## AudioSource basics

Per-object playback component. Inspector fields:

- **AudioClip** — required for `Play()`/loops; optional for `PlayOneShot(clip)`.
- **Output** — `AudioMixerGroup` to route through. Empty = bypass mixer (no Master volume control). Almost always set.
- **Mute / Bypass Effects / Bypass Listener Effects / Bypass Reverb Zones** — debug and special-case toggles. Bypass Listener Effects useful for UI clicks under an "underwater" listener filter.
- **Play On Awake** — fires `Play()` automatically. Disable for triggered/pooled SFX.
- **Loop** — restart at end. PlayOneShot ignores.
- **Priority** (0–256, lower = more important). Cap at `Project Settings > Audio > Real Voice Count` (default 32); excess voices virtualize. **Drop to 16–24 on mobile.**
- **Volume** (0–1), **Pitch** (-3 to 3), **Stereo Pan** (-1 to 1).
- **Spatial Blend** — 0 = pure 2D, 1 = pure 3D. Curve-mappable.
- **Reverb Zone Mix** — how much AudioReverbZone affects this source.
- **3D Sound Settings** — Doppler Level, Spread, Volume Rolloff (Logarithmic/Linear/Custom), Min/Max Distance.

```csharp
audioSource.PlayOneShot(clip, volume); // fire-and-forget; multiple overlap cleanly
audioSource.Play();                    // looping or stateful (music, ambience)
audioSource.Stop();                    // halts and rewinds
audioSource.Pause(); audioSource.UnPause();
```

`PlayOneShot` ignores Loop and is NOT cut off by a subsequent `Play()` — perfect for overlapping SFX (footsteps, hits).

## AudioListener (one rule)

Exactly ONE per scene. Default: Main Camera. Two listeners spam the console; Unity arbitrarily uses the first — routing changes silently ignored.

Place on the player for top-down (camera high above), split-screen (per-player), or first-person.

`AudioListener.pause = true` halts ALL audio without touching `Time.timeScale`. `AudioListener.volume` is a final 0–1 multiplier.

## AudioMixer architecture

`Assets > Create > Audio > Audio Mixer`. Group hierarchy terminates at Master.

- AudioSources route via `Output` → AudioMixerGroup.
- Groups route to a parent: typical `Master → {Music, SFX, UI, Voice, Ambience}`; SFX may have children `SFX_Player`, `SFX_World`, `SFX_Enemy`.
- Per-Group effects: Lowpass, Highpass, Reverb, Compressor, Duck Volume, Send/Receive (sidechain). Add via Effects panel.
- Multiple mixers per project are valid — e.g. a `DialogueMixer` whose Master routes into the main mixer's Voice group.

## Exposed parameters and volume sliders

In Mixer window, right-click parameter → "Expose '…' to script" → rename in Exposed Parameters dropdown to a stable key (`MasterVolume`).

Mixer volume is **decibels**: 0 dB = full, -80 dB = silence floor. Linear 0–1 into dB feels wrong — convert:

```csharp
[SerializeField] AudioMixer mixer;

public void SetMasterVolume(float linear01) // from a UI Slider 0..1
{
    float dB = (linear01 > 0.0001f) ? Mathf.Log10(linear01) * 20f : -80f;
    mixer.SetFloat("MasterVolume", dB);
}
```

The `0.0001f` clamp is mandatory — `Mathf.Log10(0) = -Infinity` corrupts the parameter. Persist linear value to PlayerPrefs and re-apply on Awake.

## Snapshots and ducking

Snapshots = named presets capturing all mixer parameter values. Use for whole-mix state changes: `Normal`, `Underwater`, `Menu`, `Combat`.

```csharp
mixer.FindSnapshot("Combat").TransitionTo(0.5f); // 0.5s crossfade
```

Ducking (music dips under dialogue):

- **Sidechain compressor** — `Duck Volume` effect on Music; `Send` from Voice to that Duck Volume's sidechain. Real-time response.
- **Snapshot pair** — `Normal` Music at 0 dB, `Dialogue` at -20 dB. `TransitionTo` on dialogue start/end. Simpler, less responsive.

## 3D vs 2D sound

`Spatial Blend`: 0 = 2D (no positioning, full volume regardless of distance). 1 = 3D (rolloff, doppler, listener-relative pan).

- Music, UI, narration, stingers — Spatial Blend 0.
- World SFX — Spatial Blend 1.
- Logarithmic rolloff (default) is realistic. Linear feels gamier — loud out to Max Distance then snaps off.
- Min Distance — full volume below this. Max Distance — silent past this (Logarithmic still tapers, Linear hits zero exactly).
- Doppler Level 0 for fast-moving objects unless you want pitch shift; at 1 you get comedic slides on projectiles.

## AudioClip import settings

- **Load Type**:
  - `Decompress On Load` — small clips, decoded once, low CPU, higher RAM. Default for short SFX.
  - `Compressed In Memory` — kept compressed, decoded each `Play()`. RAM saves at CPU cost; bad for high-frequency SFX.
  - `Streaming` — read from disk during playback. Music and long ambience (>~200 KB). Streaming sources can NOT play in parallel (one decoder per source).
- **Compression Format**:
  - `PCM` — uncompressed, fastest decode, biggest. Tiny critical SFX only.
  - `ADPCM` — fixed 4:1, very cheap decode, slight quality loss. Noisy/looping SFX.
  - `Vorbis` — variable bitrate, music/long clips. Quality 50–70 most uses; 100 only for hero music.
- **Force To Mono** — enable for SFX. Halves memory.
- **Sample Rate Setting** — `Optimize Sample Rate` (auto, recommended), or override: 22050 Hz SFX, 44100 Hz music, 48000 Hz only when source warrants.
- **Preload Audio Data** — load header at scene load. Combine with non-streaming. Streaming + Preload = wasted memory.
- **Load In Background** — async; used with Streaming.
- **Per-platform overrides** — open the platform tab; override more aggressively for mobile (Vorbis q40–50) and WebGL (always Vorbis).

## Music vs SFX patterns

- **Music** — Streaming, Vorbis q50–70, looping AudioSource on `Music` group, crossfade between two sources lerping volume. `ignoreListenerPause = true`.
- **SFX** — Decompress On Load, ADPCM or short Vorbis, output to `SFX` group. `PlayOneShot` to overlap.
- **Footsteps / repeating impacts** — pool a small array of AudioSources and round-robin. Avoid `AudioSource.PlayClipAtPoint` in tight loops — instantiates a temporary GameObject per call.

## Mobile gotchas

- Audio interruption (call, Siri, Music): `AudioSettings.OnAudioConfigurationChanged` fires. After interruption, music often needs restart from `OnApplicationFocus(true)`.
- Background mute: Unity mutes when backgrounded by default. Set `Application.runInBackground = true` AND configure platform session (iOS `AVAudioSession.Category` plugin, Android `AudioFocus`).
- Sample rate cost — force SFX to 22050.
- DSP buffer size (`Project Settings > Audio > DSP Buffer Size`) — `Best latency` for action games (lower buffer = lower latency, more CPU); `Default` most; `Best performance` low-end / battery.
- Streaming music + a dozen Compressed-In-Memory SFX is the right shape. PCM everywhere will OOM on low-end Android.

## WebGL gotchas

- Audio context unlock: browsers block audio until user input. First click/tap unlocks; until then `Play()` returns silence. Build a "Click to Start" gate.
- No threads: AudioClip decode runs on main thread. Streaming long clips can stutter — short SFX prefer Decompress On Load even at RAM cost.
- Format: WebGL plays OGG Vorbis. MP3 sometimes excluded for licensing — don't rely on it. Force Vorbis on the WebGL platform tab.
- `AudioSource.timeSamples` precision varies between browsers. Don't rely on sample-accurate sync; use `time` and `clip.length` with tolerance.

## Pause and time-scale

- `Time.timeScale = 0` does NOT pause audio — runs on real time (`unscaledDeltaTime`).
- Pause everything: `AudioListener.pause = true`. Resume with `false`.
- Pause one source: `audioSource.Pause()` / `UnPause()`.
- Music and UI clicks should keep playing during pause — set `audioSource.ignoreListenerPause = true`.
- Physics-coupled audio (engine pitch by speed) — drive `pitch` from a value updated in `FixedUpdate` so it pauses cleanly.

## Common patterns

- **Volume slider** — UI Slider (0–1) → log10-to-dB → `mixer.SetFloat`. Save linear 0–1 to PlayerPrefs `OnValueChanged`; apply on Awake. Repeat per group. See `references/audio-manager.md`.
- **AudioManager singleton** — `DontDestroyOnLoad` with `PlaySFX(clip, position?)` / `PlayMusic(clip, fadeSec)` / `SetVolume(group, linear01)`. Pool 8–16 SFX AudioSources, round-robin. Full pattern: `references/audio-manager.md`.
- **Spatial 3D one-shot** — temporary GameObject at impact point with AudioSource (Spatial Blend 1, Output = SFX), `PlayOneShot`, destroy after `clip.length`. Or `PlayClipAtPoint` — convenient but allocates. Pool if frequent.
- **Footstep system** — `AnimationEvent` on foot-down calls `PlayFootstep(surfaceTag)`; surface tag indexes a sound bank ScriptableObject. See `unity-animation`.
- **Music crossfade** — two AudioSources A (current) and B (next). On change, lerp A.volume → 0 and B.volume → 1 over ~1 s, `B.Play()` at start, `A.Stop()` when done. See `references/audio-manager.md`.
- **Ducking via snapshot** — `Normal` and `Dialogue` snapshots (Music at 0 dB and -20 dB); `TransitionTo(0.3f)` on dialogue start/end.

## Gotchas

- Multiple AudioListeners — console spam, routing changes ignored. Always exactly one. Common after additive scene loads (`unity-scenes`); strip listeners off non-primary scenes.
- `PlayOneShot` ignores Loop and Play On Awake. Bypasses some 3D settings if source has no clip — assign a placeholder.
- `mixer.SetFloat` before AudioMixer is loaded fails silently. Apply in `Awake`/`Start`, not field initializers.
- Linear-to-dB: clamp `0` linear to `-80f`. `Mathf.Log10(0) = -Infinity` corrupts the parameter.
- Compressed In Memory pays decode CPU on every Play — bad for short frequent SFX. Use Decompress On Load.
- Streaming clips can't play in parallel — one decoder per source.
- `AudioSource.outputAudioMixerGroup` set in code overrides Inspector but resets when a prefab re-instantiates. Set on the prefab.
- Preload Audio Data + Streaming = memory bloat. Only Preload non-streaming.
- Missing AudioMixerGroup reference (mixer asset deleted/renamed) silently routes to Master — group slider does nothing.
- AudioReverbZone is global to the listener — moving the listener through one affects every 3D source, not just inside-zone sources.

## Verification

- Console clean of "There are 2 audio listeners…", "AudioMixer parameter '…' not exposed", "Cannot find AudioMixerGroup", null clip warnings.
- Volume slider sanity: log dB as slider moves. Should be ~`-80` at 0, `-20` near 0.1, `-6` near 0.5, `0` at 1. Flat or cliff-edged = bad linear-to-dB conversion.
- Mixer routing visible: select AudioSource, confirm `Output` is intended Group; Play and watch level meters on the Group.
- WebGL: build, open browser tab, confirm first tap/click unlocks audio. Incognito to avoid cached gestures.
- Profiler Audio module shows active sources, voices, memory. Capped at `Real Voice Count` (default 32; 16–24 mobile). Ramping into the cap = quiet sounds drop.
- For 3D sources, walk past Min Distance and confirm rolloff matches intent. Doppler issues most obvious on fast projectiles — Doppler Level 0 if unwanted slides.
- After scene transitions (`unity-scenes`), re-check listener count and that `ignoreListenerPause` music survived.

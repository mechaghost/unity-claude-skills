# AudioManager and music crossfade

Reference patterns called out from SKILL.md. Drop these in via `create_script` and wire components with `manage_components`.

## Singleton AudioManager with pooled SFX

A `DontDestroyOnLoad` GameObject that survives scene loads (cross-link `unity-scenes`), exposes `PlaySFX` / `PlayMusic` / `SetVolume`, and round-robins through a small pool of AudioSources for SFX so overlapping plays don't stomp.

```csharp
using System.Collections;
using UnityEngine;
using UnityEngine.Audio;

[DefaultExecutionOrder(-100)]
public class AudioManager : MonoBehaviour
{
    public static AudioManager Instance { get; private set; }

    [Header("Mixer")]
    [SerializeField] AudioMixer mixer;
    [SerializeField] AudioMixerGroup sfxGroup;
    [SerializeField] AudioMixerGroup musicGroup;

    [Header("SFX pool")]
    [SerializeField, Min(1)] int sfxPoolSize = 12;
    AudioSource[] sfxPool;
    int sfxCursor;

    [Header("Music")]
    [SerializeField] float defaultCrossfade = 1f;
    AudioSource musicA, musicB;
    AudioSource currentMusic;

    void Awake()
    {
        if (Instance != null && Instance != this) { Destroy(gameObject); return; }
        Instance = this;
        DontDestroyOnLoad(gameObject);

        // SFX pool
        sfxPool = new AudioSource[sfxPoolSize];
        for (int i = 0; i < sfxPoolSize; i++)
        {
            var go = new GameObject($"SFX_{i}");
            go.transform.SetParent(transform);
            var src = go.AddComponent<AudioSource>();
            src.playOnAwake = false;
            src.outputAudioMixerGroup = sfxGroup;
            src.spatialBlend = 0f; // override per-call for 3D SFX
            sfxPool[i] = src;
        }

        // Two music sources for crossfade
        musicA = CreateMusicSource("Music_A");
        musicB = CreateMusicSource("Music_B");
        currentMusic = musicA;

        // Apply persisted volumes (cross-link unity-persistence once it exists)
        ApplyVolume("MasterVolume", PlayerPrefs.GetFloat("vol.master", 1f));
        ApplyVolume("MusicVolume",  PlayerPrefs.GetFloat("vol.music",  1f));
        ApplyVolume("SFXVolume",    PlayerPrefs.GetFloat("vol.sfx",    1f));
    }

    AudioSource CreateMusicSource(string name)
    {
        var go = new GameObject(name);
        go.transform.SetParent(transform);
        var src = go.AddComponent<AudioSource>();
        src.playOnAwake = false;
        src.loop = true;
        src.outputAudioMixerGroup = musicGroup;
        src.spatialBlend = 0f;
        src.ignoreListenerPause = true; // music keeps playing through pause menus
        return src;
    }

    // Fire-and-forget 2D SFX
    public void PlaySFX(AudioClip clip, float volume = 1f, float pitch = 1f)
    {
        if (clip == null) return;
        var src = sfxPool[sfxCursor];
        sfxCursor = (sfxCursor + 1) % sfxPool.Length;
        src.transform.position = Vector3.zero;
        src.spatialBlend = 0f;
        src.pitch = pitch;
        src.PlayOneShot(clip, volume);
    }

    // 3D SFX at a worldspace point
    public void PlaySFXAt(AudioClip clip, Vector3 position, float volume = 1f)
    {
        if (clip == null) return;
        var src = sfxPool[sfxCursor];
        sfxCursor = (sfxCursor + 1) % sfxPool.Length;
        src.transform.position = position;
        src.spatialBlend = 1f;
        src.pitch = 1f;
        src.PlayOneShot(clip, volume);
    }

    public void PlayMusic(AudioClip clip, float fadeSec = -1f)
    {
        if (clip == null || (currentMusic != null && currentMusic.clip == clip && currentMusic.isPlaying)) return;
        if (fadeSec < 0f) fadeSec = defaultCrossfade;
        StopAllCoroutines();
        StartCoroutine(CrossfadeTo(clip, fadeSec));
    }

    IEnumerator CrossfadeTo(AudioClip clip, float fadeSec)
    {
        var from = currentMusic;
        var to   = (currentMusic == musicA) ? musicB : musicA;
        to.clip = clip;
        to.volume = 0f;
        to.Play();

        float t = 0f;
        float fromStart = from.volume;
        while (t < fadeSec)
        {
            t += Time.unscaledDeltaTime; // immune to Time.timeScale and pause
            float k = (fadeSec <= 0f) ? 1f : Mathf.Clamp01(t / fadeSec);
            from.volume = Mathf.Lerp(fromStart, 0f, k);
            to.volume   = Mathf.Lerp(0f, 1f, k);
            yield return null;
        }
        from.Stop();
        from.clip = null;
        currentMusic = to;
    }

    // Linear 0..1 from a UI Slider
    public void SetVolume(string exposedParam, float linear01)
    {
        ApplyVolume(exposedParam, linear01);
        PlayerPrefs.SetFloat(PrefKey(exposedParam), linear01);
    }

    void ApplyVolume(string exposedParam, float linear01)
    {
        float dB = (linear01 > 0.0001f) ? Mathf.Log10(linear01) * 20f : -80f;
        mixer.SetFloat(exposedParam, dB);
    }

    static string PrefKey(string param) => "vol." + param.ToLowerInvariant().Replace("volume", "");
}
```

Wire-up checklist:

- Create the mixer asset and groups (`Master`, `Music`, `SFX`, optionally `UI` / `Voice`).
- Expose Volume on Master / Music / SFX as `MasterVolume` / `MusicVolume` / `SFXVolume`.
- Drop a single `AudioManager` GameObject in your bootstrap scene; assign mixer, sfxGroup, musicGroup in the Inspector.
- Confirm exactly one `AudioListener` in the scene (cross-link the AudioListener section of SKILL.md).

## UI volume slider hookup

```csharp
using UnityEngine;
using UnityEngine.UI;

public class VolumeSlider : MonoBehaviour
{
    [SerializeField] Slider slider;
    [SerializeField] string exposedParam = "MasterVolume";
    [SerializeField] string prefKey = "vol.master";

    void Start()
    {
        slider.value = PlayerPrefs.GetFloat(prefKey, 1f);
        slider.onValueChanged.AddListener(OnChanged);
        OnChanged(slider.value);
    }

    void OnChanged(float linear01)
    {
        AudioManager.Instance.SetVolume(exposedParam, linear01);
    }
}
```

## Footstep AnimationEvent hook

Driven by the animation clip's foot-down event (cross-link `unity-animation`). Surface tag picks from a sound bank ScriptableObject — keep clips short, ADPCM, Decompress On Load.

```csharp
using UnityEngine;

public class FootstepReceiver : MonoBehaviour
{
    [SerializeField] FootstepBank bank;       // ScriptableObject mapping tag -> AudioClip[]
    [SerializeField] LayerMask groundMask;
    [SerializeField] float probeDist = 1.2f;

    // Called from an AnimationEvent on the foot-down keyframe.
    public void PlayFootstep()
    {
        if (!Physics.Raycast(transform.position + Vector3.up * 0.1f, Vector3.down, out var hit, probeDist, groundMask)) return;
        var tag = hit.collider.tag;
        var clip = bank.PickFor(tag);
        if (clip != null) AudioManager.Instance.PlaySFXAt(clip, hit.point, 0.8f);
    }
}
```

## Snapshot ducking helper

```csharp
public class DialogueDucker : MonoBehaviour
{
    [SerializeField] AudioMixer mixer;
    [SerializeField] float duckTime = 0.3f;
    [SerializeField] float restoreTime = 0.6f;

    public void OnDialogueStart() => mixer.FindSnapshot("Dialogue").TransitionTo(duckTime);
    public void OnDialogueEnd()   => mixer.FindSnapshot("Normal").TransitionTo(restoreTime);
}
```

## Notes

- Crossfade uses `Time.unscaledDeltaTime` so it works through pause menus (`Time.timeScale = 0`). If you want music fading to honor a slow-motion bullet-time effect, switch to `Time.deltaTime`.
- The pool round-robin is intentionally dumb. For voice-stealing by priority, sort the pool each call by `isPlaying` and `time` remaining and reuse the oldest non-priority source first.
- `outputAudioMixerGroup` is set in code on each pooled source. If you spawn AudioSources from prefabs at runtime, set the group on the prefab — code-set groups don't survive prefab re-instantiation.
- Streaming clips (typically music) cannot play in parallel. The crossfade above plays two clips simultaneously for `fadeSec`, so set music import to a non-streaming Vorbis if your music tracks are short, OR accept a brief overlap risk on streaming and shorten the crossfade.

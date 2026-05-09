# WebGL platform reference

Companion to `unity-build` covering browser runtime gotchas. Unity 6, URP-only, new Input System only. Cross-link `unity-build/SKILL.md` (build pipeline), `unity-audio` (context unlock), `unity-addressables` (lazy content), `unity-persistence` (IndexedDB), `unity-input-system` (browser input quirks).

## Threading

Web builds do not support arbitrary managed C# threading because WebAssembly lacks the multithreaded garbage collection Unity would need. Practical consequences:

- `System.Threading.Thread` constructor crashes at runtime.
- `Task.Run` runs delegate **on the main thread**, synchronously inlined into the next yield point. Doesn't parallelize.
- `Parallel.For`/`Parallel.ForEach` execute serially on the main thread.
- Managed background loaders block the frame.

Plan async work through coroutines, `UnityWebRequestAsyncOperation`, or `Awaitable` (Unity 6) — those yield to the engine's main loop without blocking. See `unity-patterns` for async/coroutine patterns that survive WebGL.

Unity 6.4+ adds Web multithreading for compatible Burst-compiled C# jobs. Those jobs must stay inside the Burst/HPC# subset (blittable structs and `NativeContainer` data, no managed allocations or object references) and still schedule from the main thread. Non-Burst jobs and managed threads remain main-thread/unsupported on Web.

## IndexedDB persistence

`Application.persistentDataPath` returns `/idbfs/<hash>` — virtual filesystem backed by IndexedDB. Writes go to in-memory FS first; nothing persisted to IndexedDB until FS is synced.

- `Application.Quit()` triggers a flush automatically.
- For mid-session saves, call out to a JSLib hook:

```javascript
// Plugins/WebGL/SyncFs.jslib
mergeInto(LibraryManager.library, {
  SyncFs: function () {
    FS.syncfs(false, function (err) {
      if (err) console.error("FS.syncfs failed", err);
    });
  },
});
```

```csharp
public static class WebGLFs
{
    [System.Runtime.InteropServices.DllImport("__Internal")]
    public static extern void SyncFs();

    public static void Flush()
    {
#if UNITY_WEBGL && !UNITY_EDITOR
        SyncFs();
#endif
    }
}
```

Call `WebGLFs.Flush()` after every save write. Save-format design (atomic write + version field + JSON layout) is owned by `unity-persistence`.

## Audio context unlock

Browsers refuse audio playback until the page receives a user gesture (click, tap, key). Until then, `AudioSource.Play()` returns silently — no error, no audio.

Pattern: a "Click to Start" gate on the title screen calls a no-op `AudioSource.PlayOneShot(silentClip)` on the first input event. This satisfies the gesture requirement; subsequent music/SFX play normally. Mixer/snapshot/volume-slider plumbing wrapping this gate is owned by `unity-audio`.

## Build size

Initial WebGL load is the entire binary — no progressive download for the engine + first-scene payload. Aggressive size strategy:

- **Managed Stripping Level: High** — strips unused IL ruthlessly. Maintain `link.xml` for reflective code; see `unity-build/SKILL.md`.
- **ASTC textures** — modern browsers support ASTC; WebGL platform tab can override format per texture.
- **Brotli compression** in `Player Settings > Publishing Settings`. Smaller than gzip; supported by all evergreen browsers.
- **Decompression Fallback off** if hosting serves `.br` files with `Content-Encoding: br` headers. With it on, Unity ships a JS decoder (~150 KB) and the build doubles in disk size for the unused fallback path.
- **Lazy-load via Addressables remote groups** — split the giant first-scene payload by streaming non-critical content from a CDN after first frame renders.

See `unity-addressables`.

## Memory cap

`PlayerSettings > WebGL > Memory Size` (default 256 MB, max ~2 GB depending on browser). Mobile browsers cap lower — iOS Safari reliably drops the tab silently when WASM exceeds ~512 MB; Chrome on Android similarly. Mobile-WebGL targets should keep budget at 256-384 MB and lean on Addressables to swap content in and out.

The cap is a hard ceiling — once exceeded the tab dies with no Unity log line. Profile via Memory Profiler in a desktop build, then halve your assumption for mobile.

## No System.IO writes outside persistentDataPath

WebGL FS is sandboxed. Anything outside `Application.persistentDataPath` is read-only or absent:

- `Application.dataPath` — read-only, points at the streaming-assets bundle in the WASM filesystem.
- `Application.streamingAssetsPath` — read-only via `UnityWebRequest` only; no `File.ReadAllBytes`.
- Any absolute path (`C:/`, `/Users/`, etc.) — no concept of host filesystem.

`File.WriteAllText("save.json", ...)` works only when path resolves under `Application.persistentDataPath`.

## OGG only

Unity WebGL plays **OGG Vorbis** natively. MP3 sometimes excluded from builds for licensing reasons — don't rely on it. Force WebGL platform-tab compression to Vorbis on every clip. See `unity-audio`.

## AudioSource.timeSamples precision

Different browsers use different audio clocks. `AudioSource.timeSamples` is sample-accurate on Chrome/Firefox desktop, drifts on Safari, even less reliable on iOS Safari. Don't author rhythm-game-tier sync logic on `timeSamples`; use `AudioSource.time` plus a tolerance window.

## No Resources.Load async

`Resources.LoadAsync` exists in code, but on WebGL blocks the main thread (no worker to run on). `Resources` is also baked into the initial download — bad for size. Fix is the same on every platform: use Addressables, and on WebGL it pays double because remote groups are the only realistic content-streaming option. See `unity-addressables`.

## WebAssembly cache headers

Browsers cache `.wasm`, `.data`, `.framework.js`, `.loader.js` based on HTTP cache headers. Hosting must serve `.wasm` with `Content-Type: application/wasm` and a long `Cache-Control: max-age` plus immutable hashes in filenames (Unity already adds the hashes). Without the right MIME type, some browsers refuse to compile streaming WASM and fall back to byte-array load (slower). Without cache headers, the entire build re-downloads every visit.

## Browser quirks

- **Chrome / Edge** — best support, treat as development baseline.
- **Firefox** — generally stable; occasional WebGPU previews irrelevant to WebGL builds.
- **Safari (desktop)** — WebGL2 quirks around ETC2 texture support; audio context strict; IndexedDB has lower quota in private browsing.
- **iOS Safari** — strictest. WebGL2 supported but with rendering bugs around MSAA and HDR; audio context unlock requires a real user tap (not a synthesized event); memory dropped silently on tab background.

Test in Chrome, Safari (Mac), Firefox, and on actual iOS Safari before shipping.

## Unity 6 Web, WebGL, and WebGPU

Unity 6 browser builds use the **Web** platform in Build Profiles. For production, target Web with WebGL2 today; keep WebGPU for experiments or narrow audiences until browser and Unity support mature.

## WebGPU

URP has experimental WebGPU support in Unity 6. Desktop Chrome/Edge run it well; Safari and Firefox have partial coverage. Ship-ready only for very narrow audiences. Stick with WebGL2 for production WebGL builds.

## Verification

1. Build with Brotli + Decompression Fallback off; verify hosting serves `.br` with the right `Content-Encoding`.
2. Hard-reload (Cmd-Shift-R / Ctrl-F5) to bypass cache. Confirm load time matches expectations and `.wasm` is served as `application/wasm` (DevTools → Network → Type column).
3. First user click should unlock audio; verify SFX plays.
4. Save mid-session, hard-reload, confirm save persists (IndexedDB sync worked).
5. Test in Chrome, Safari, Firefox; on actual iOS Safari and Android Chrome (mobile browsers cap memory lower than desktop).
6. Profile WASM heap via Memory Profiler attached to a Development Build before assuming you fit under the 256-512 MB mobile ceiling.

See `unity-build/SKILL.md` for the broader build pipeline (build profiles, IL2CPP, link.xml, BuildReport).

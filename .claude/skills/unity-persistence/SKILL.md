---
name: unity-persistence
description: 'Use when working with Unity save data and persistence through Unity MCP — PlayerPrefs, JsonUtility, save data, save game, save slot, load game, persistentDataPath, dataPath, BinaryFormatter, Newtonsoft Json, JSON save, save file, cloud save, Steam Cloud, encrypted save, savefile path, application persistent data, ES3, Easy Save, atomic save, save slot UI, scriptable object save. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

Companion: `unity-scenes` (boot scene owns SaveManager), `unity-patterns` (singleton structure), `unity-build` (save format compat across builds).

## When to use

- Where to write save files on disk.
- SaveManager with slots, atomic writes, versioning.
- PlayerPrefs (settings) vs JSON (game data).
- Save corruption, lost-progress-on-update, per-platform path issues.
- Migrating off `BinaryFormatter`.

## Storage paths

| Path | Writable? | Use |
|---|---|---|
| `Application.persistentDataPath` | Yes, every platform | Save data, screenshots, cached downloads. Survives updates. |
| `Application.dataPath` | Read-only most platforms | Inspect bundle layout; don't write. |
| `Application.streamingAssetsPath` | Read-only, ships with build | Bundled config, level data, cutscenes. Not for saves. |
| `Application.temporaryCachePath` | Yes, OS may clear | Recoverable caches only. |

Per-platform:

- macOS — `~/Library/Application Support/<company>/<product>`
- Windows — `%userprofile%\AppData\LocalLow\<company>\<product>`
- iOS — sandboxed Documents directory; opt out of iCloud backup with `UnityEngine.iOS.Device.SetNoBackupFlag` if save is regenerable.
- Android — internal storage under app's data directory.
- WebGL — IndexedDB-backed virtual filesystem; flushes on `Application.Quit()`.

`<company>`/`<product>` come from Player Settings.

## PlayerPrefs (settings only)

SETTINGS ONLY — volume, graphics quality, last character, "show tutorial" flags. Never for game saves.

Limits:

- ~1 MB total per platform.
- Plaintext: Windows registry (`HKCU\Software\<company>\<product>`), macOS `.plist`, WebGL IndexedDB.
- No encryption, no slots, key-value only.

```csharp
PlayerPrefs.SetInt("musicVolume", 80);
PlayerPrefs.SetFloat("mouseSensitivity", 1.4f);
PlayerPrefs.SetString("language", "en");
int v = PlayerPrefs.GetInt("musicVolume", defaultValue: 100);
if (PlayerPrefs.HasKey("language")) { /* ... */ }
PlayerPrefs.DeleteKey("musicVolume");
PlayerPrefs.Save(); // forces flush — call on quit / pause
```

`PlayerPrefs.Save()` is implicit on a clean quit, but mobile apps are killed without one. Call explicitly on `OnApplicationPause(true)` and `Application.quitting`.

## JsonUtility for game saves

Built-in, fast, no allocation beyond the result string. Limits:

- Public fields or `[SerializeField]` private fields only.
- No `Dictionary<,>` — wrap as `List<KV>`.
- No polymorphism — base-class field with derived instance loses derived type.
- No null collections — deserialize to empty.
- No `object`-typed fields.

```csharp
[Serializable]
public class SaveData
{
    public int saveVersion = 1;
    public int level;
    public float playtime;
    public List<ItemSave> items = new();
    public Vector3 playerPosition;
}

string json = JsonUtility.ToJson(data, prettyPrint: true);
File.WriteAllText(path, json);

var loaded = JsonUtility.FromJson<SaveData>(File.ReadAllText(path));
```

Dictionary wrapper:

```csharp
[Serializable] public class StringIntKV { public string key; public int value; }
[Serializable] public class StringIntDict { public List<StringIntKV> entries = new(); }
```

For polymorphism or true dictionaries, install Newtonsoft.Json (`com.unity.nuget.newtonsoft-json`) — adds ~1 MB to build size.

## Atomic write pattern

Never write directly to the save path. Crash mid-write = corrupt save.

```csharp
public static void AtomicWrite(string path, string contents)
{
    string tmp = path + ".tmp";
    string bak = path + ".bak";
    File.WriteAllText(tmp, contents);

    if (File.Exists(path))
        File.Replace(tmp, path, bak); // atomic on Win/macOS/Linux
    else
        File.Move(tmp, path);
}
```

`File.Replace` is atomic on most OSes and keeps the previous save as `.bak`. Where unsupported, fall back to `File.Delete` + `File.Move`, accepting a tiny corruption window.

## Save slots

Directory per slot:

```
persistentDataPath/
  Slot1/
    save.json
    screenshot.png
    meta.json     // timestamp, playtime, level name, character name
  Slot2/
    ...
```

Load-game UI reads `meta.json` only — show all slots without parsing every full save. `Directory.GetDirectories(persistentDataPath, "Slot*")` enumerates.

```csharp
public static string SlotDir(int slot) =>
    Path.Combine(Application.persistentDataPath, $"Slot{slot}");

public static void EnsureSlot(int slot) =>
    Directory.CreateDirectory(SlotDir(slot));
```

## Cloud saves

See `unity-cloud-save-conflict` — owns conflict resolution, schema migration, cross-device handoff. This skill covers local on-device only.

iCloud key-value: there is no `UnityEngine.iOS.iCloudKVStore` API — that type does not exist. iCloud KV requires a native plugin (Voxel Busters' "iCloud Cloud Save") or custom Objective-C/Swift bridge calling `NSUbiquitousKeyValueStore`. Don't ship a hand-rolled bridge unless you understand the entitlement, container, and sync-notification surface.

## What NOT to use

- **`BinaryFormatter`** — deprecated by Microsoft, documented RCE security holes. Never. Legacy Unity tutorials use it; ignore them.
- **PlayerPrefs for game saves** — size limit, plaintext, no slots, slow on mobile.
- **`Resources/` for save data** — read-only at runtime, ships with build.
- **`DontDestroyOnLoad` GameObjects as source of truth** — vanish on app restart. Runtime cache only.
- **Hardcoded AES with a baked-in key** — players reverse the binary in minutes. Security theater. For real anti-cheat, validate on a server.

## Data versioning

Every save includes `int saveVersion`. On load, branch to migrate.

```csharp
public static SaveData Load(string path)
{
    string json = File.ReadAllText(path);
    var data = JsonUtility.FromJson<SaveData>(json);
    while (data.saveVersion < SaveData.CurrentVersion)
        data = Migrate(data);
    return data;
}

static SaveData Migrate(SaveData old)
{
    switch (old.saveVersion)
    {
        case 1: // v1 -> v2: split player position
            old.playerPosition = new Vector3(old.legacyX, old.legacyY, 0);
            old.saveVersion = 2;
            break;
        // ...
    }
    return old;
}
```

Ship with versioning from day one. Renaming a serialized field deserializes to default and silently loses progress.

## ScriptableObject as runtime config

For STATIC data (weapon stats, level definitions, enemy archetypes), SOs shipped in the build (Resources or direct references). Designers edit in Editor, build packages them.

NOT for save data — SO changes don't persist across runs in builds. Editor writes `.asset` files; builds load read-only copies.

## Common patterns

- **SaveManager singleton** — `DontDestroyOnLoad` from boot scene with `Save(int slot)`, `Load(int slot)`, `DeleteSlot(int slot)`. See `unity-scenes` (boot) and `unity-patterns` (singleton).
- **Settings save** — PlayerPrefs for volume/graphics/language. `SettingsManager` loads on `Awake`, applies (`AudioListener.volume`, `QualitySettings.SetQualityLevel`), saves on every change.
- **Auto-save on event** — subscribe to `CheckpointEventSO`; on raise, atomic write. Throttle — never every frame.
- **Quit save** — `Application.quitting += Save;` plus `OnApplicationPause(bool paused)` on mobile (mobile may kill app without `quitting`).

Use the singleton from `unity-patterns`. Register `Save(activeSlot)` on `Application.quitting` (and `OnApplicationPause(true)` on mobile) inside the manager's `Awake`, after the singleton guard.

```csharp
public class SaveManager : MonoBehaviour
{
    // singleton scaffold per unity-patterns
    public static SaveManager Instance { get; private set; }
    public SaveData Current { get; private set; } = new();
    int activeSlot = 1;

    void OnEnable()
    {
        Application.quitting += SaveActive;
    }

    void OnDisable() => Application.quitting -= SaveActive;

    void SaveActive() => Save(activeSlot);

    public void Save(int slot)
    {
        EnsureSlot(slot);
        string path = Path.Combine(SlotDir(slot), "save.json");
        AtomicWrite(path, JsonUtility.ToJson(Current, prettyPrint: true));
    }

    public bool Load(int slot)
    {
        string path = Path.Combine(SlotDir(slot), "save.json");
        if (!File.Exists(path)) return false;
        Current = JsonUtility.FromJson<SaveData>(File.ReadAllText(path));
        return true;
    }

    static string SlotDir(int slot) =>
        Path.Combine(Application.persistentDataPath, $"Slot{slot}");

    static void EnsureSlot(int slot) =>
        Directory.CreateDirectory(SlotDir(slot));

    static void AtomicWrite(string path, string contents)
    {
        string tmp = path + ".tmp";
        string bak = path + ".bak";
        File.WriteAllText(tmp, contents);

        if (File.Exists(path))
            File.Replace(tmp, path, bak);
        else
            File.Move(tmp, path);
    }
}
```

## Gotchas

- `JsonUtility` silently drops `Dictionary`, polymorphic, and `object`-typed fields — no warning.
- Direct write without atomic = corrupt save on crash.
- WebGL needs `FS.syncfs` flush; Unity handles on `Application.Quit()`, but force-closing the tab loses unflushed data.
- `File.WriteAllText` is synchronous — for huge saves (>1 MB) use a background thread or `Task.Run`. Not in WebGL — no threads.
- Save data in `Assets/Resources/` ships with the build, read-only at runtime.
- Hardcoded-key encryption is security theater. Use a server.
- Newtonsoft.Json adds ~1 MB; install only if `JsonUtility` can't meet the schema.
- iOS iCloud backup of large saves can cause App Store rejection — set `NoBackup` on regenerable caches.
- Path separators — always `Path.Combine`. Hardcoded `/` breaks Windows; `\` breaks everything else.

## Verification

- After save, read back and assert content matches and `saveVersion` present.
- Test on each target — `persistentDataPath` differs; iOS/Android sandboxing surfaces only at runtime.
- For atomic writes, kill mid-write (Force Quit / Task Manager / ADB kill) and confirm previous save survives via `.bak`.
- Console clean of `IOException`, `UnauthorizedAccessException`, `DirectoryNotFoundException`.
- On first boot, log `persistentDataPath` and confirm writable — `File.WriteAllText` to a probe file then delete.
- Settings round-trip: set slider, restart Play, confirm value loaded.

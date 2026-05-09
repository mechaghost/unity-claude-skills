---
name: unity-persistence
description: 'Use when working with Unity save data and persistence through Unity MCP — PlayerPrefs, JsonUtility, save data, save game, save slot, load game, persistentDataPath, dataPath, BinaryFormatter, Newtonsoft Json, JSON save, save file, cloud save, Steam Cloud, encrypted save, savefile path, application persistent data, ES3, Easy Save, atomic save, save slot UI, scriptable object save.'
---

Companion skill: `unity-scenes` for the boot scene that owns the SaveManager singleton; `unity-patterns` for singleton structure; `unity-build` for shipping save format compatibility across builds.

## When to use

- Choosing where to write save files on disk.
- Building a SaveManager with slots, atomic writes, and versioning.
- Deciding between PlayerPrefs (settings) and JSON (game data).
- Diagnosing save corruption, lost-progress-on-update, or per-platform path issues.
- Migrating off `BinaryFormatter` or other deprecated patterns.

## Storage paths

| Path | Writable? | Use |
|---|---|---|
| `Application.persistentDataPath` | Yes, every platform | Save data, screenshots, cached downloads. Survives app updates. |
| `Application.dataPath` | Read-only on most platforms | Inspect bundle layout; do not write. |
| `Application.streamingAssetsPath` | Read-only, ships with build | Bundled config, level data, cutscenes. Not for saves. |
| `Application.temporaryCachePath` | Yes, but OS may clear | Recoverable caches only. |

Per-platform actuals:

- macOS — `~/Library/Application Support/<company>/<product>`
- Windows — `%userprofile%\AppData\LocalLow\<company>\<product>`
- iOS — sandboxed Documents directory; opt out of iCloud backup with `UnityEngine.iOS.Device.SetNoBackupFlag` if save is regenerable.
- Android — internal storage under the app's data directory.
- WebGL — IndexedDB-backed virtual filesystem; Unity flushes on `Application.Quit()`.

`<company>` and `<product>` come from `Player Settings > Company Name / Product Name`.

## PlayerPrefs (settings only)

For SETTINGS ONLY — volume sliders, graphics quality, last-played character, "show tutorial" flags. Never for game saves.

Limits:

- ~1 MB total per platform.
- Plaintext on disk: Windows registry (`HKCU\Software\<company>\<product>`), macOS `.plist`, WebGL IndexedDB.
- No encryption, no slots, key-value only.

API:

```csharp
PlayerPrefs.SetInt("musicVolume", 80);
PlayerPrefs.SetFloat("mouseSensitivity", 1.4f);
PlayerPrefs.SetString("language", "en");
int v = PlayerPrefs.GetInt("musicVolume", defaultValue: 100);
if (PlayerPrefs.HasKey("language")) { /* ... */ }
PlayerPrefs.DeleteKey("musicVolume");
PlayerPrefs.Save(); // forces flush — call on quit / pause
```

`PlayerPrefs.Save()` is implicit on a clean quit, but mobile apps are often killed without one. Call it explicitly on `OnApplicationPause(true)` and `Application.quitting`.

## JsonUtility for game saves

Built-in, fast, no allocation beyond the result string. Limits:

- Serializes PUBLIC fields or `[SerializeField]` private fields only.
- No `Dictionary<,>` support — use a `List<KV>` wrapper.
- No polymorphism — base-class field with derived instance loses the derived type.
- No null collections — they deserialize to empty.
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

For Dictionary support, wrap:

```csharp
[Serializable] public class StringIntKV { public string key; public int value; }
[Serializable] public class StringIntDict { public List<StringIntKV> entries = new(); }
```

If you need polymorphism or true dictionaries, install Newtonsoft.Json via Package Manager (`com.unity.nuget.newtonsoft-json`) — adds ~1 MB to build size but handles both.

## Atomic write pattern

Never write directly to the save path. Crash mid-write equals corrupt save.

```csharp
public static void AtomicWrite(string path, string contents)
{
    string tmp = path + ".tmp";
    string bak = path + ".bak";
    File.WriteAllText(tmp, contents);

    if (File.Exists(path))
        File.Replace(tmp, path, bak); // atomic on Windows / macOS / Linux
    else
        File.Move(tmp, path);
}
```

`File.Replace` is atomic on most OSes and keeps the previous save as `.bak` for recovery. On platforms where `Replace` is not supported (rare), fall back to `File.Delete` then `File.Move`, accepting a tiny corruption window.

## Save slots

A directory per slot under `persistentDataPath`:

```
persistentDataPath/
  Slot1/
    save.json
    screenshot.png
    meta.json     // timestamp, playtime, level name, character name
  Slot2/
    ...
```

The load-game UI reads `meta.json` only — it can show all slots without parsing every full save. `Directory.GetDirectories(persistentDataPath, "Slot*")` enumerates.

```csharp
public static string SlotDir(int slot) =>
    Path.Combine(Application.persistentDataPath, $"Slot{slot}");

public static void EnsureSlot(int slot) =>
    Directory.CreateDirectory(SlotDir(slot));
```

## Cloud saves

Cloud saves (Steam Cloud, iCloud, Google Play Saved Games, Unity Cloud Save, Firebase) are covered in `unity-cloud-save-conflict`. That skill owns conflict resolution, schema migration, and cross-device handoff. This skill (`unity-persistence`) covers local on-device save only.

For iCloud key-value sync specifically: there is no `UnityEngine.iOS.iCloudKVStore` API — that type does not exist in any Unity version. iCloud KV requires either a native plugin (e.g. Voxel Busters' "iCloud Cloud Save" on the Asset Store) or a custom Objective-C/Swift bridge calling `NSUbiquitousKeyValueStore`. Do not ship a hand-rolled bridge unless you understand the entitlement, container, and sync-notification surface.

## What NOT to use

- **`BinaryFormatter`** — deprecated by Microsoft, has documented security holes (untrusted-input remote code execution). NEVER use for new code. Legacy Unity tutorials all use it; ignore them.
- **PlayerPrefs for game saves** — size limit, plaintext, no slots, slow on mobile.
- **`Resources/` for save data** — Resources is read-only at runtime in builds and ships with the build.
- **`DontDestroyOnLoad` GameObjects as the source of truth** — they vanish on app restart. They are a runtime cache of save data, not the save itself.
- **Hardcoded AES with a baked-in key** — players will reverse the binary in minutes. Security theater. If you need anti-cheat, validate on a server.

## Data versioning

Every save includes `int saveVersion`. On load, branch on version to migrate.

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
        case 1: // v1 -> v2: split player position into separate fields
            old.playerPosition = new Vector3(old.legacyX, old.legacyY, 0);
            old.saveVersion = 2;
            break;
        // ...
    }
    return old;
}
```

Ship with versioning from day one. Renaming a serialized field deserializes to default and silently loses progress — players notice, you do not.

## ScriptableObject as runtime config

For STATIC data (weapon stats, level definitions, enemy archetypes), ScriptableObjects shipped in the build (Resources or direct references) are the right home. Designers edit them in the Editor, the build packages them.

NOT for player save data — SO changes do not persist across runs in builds. The Editor writes to `.asset` files; builds load read-only copies into memory.

## Common patterns

- **SaveManager singleton** — `DontDestroyOnLoad` GameObject created in the boot scene with `Save(int slot)`, `Load(int slot)`, `DeleteSlot(int slot)`. Cross-link `unity-scenes` (boot scene) and `unity-patterns` (singleton).
- **Settings save** — PlayerPrefs for volume / graphics / language. A `SettingsManager` loads on `Awake`, applies (sets `AudioListener.volume`, `QualitySettings.SetQualityLevel`, etc.), and saves on every change.
- **Auto-save on event** — subscribe to a `CheckpointEventSO`; on raise, atomic write current `SaveData`. Throttle — never write every frame.
- **Quit save** — `Application.quitting += Save;` plus `OnApplicationPause(bool paused)` on mobile; mobile may kill the app without raising `quitting`.

Use the canonical singleton pattern from `unity-patterns` for the SaveManager bootstrap. Persistence-specific guidance: register `Save(activeSlot)` on `Application.quitting` (and `OnApplicationPause(true)` on mobile) inside the manager's `Awake`, after the singleton-instance guard. The persistence-specific surface (slot path, atomic write, JSON round-trip) is what this skill owns; the singleton scaffold lives in `unity-patterns`.

```csharp
public class SaveManager : MonoBehaviour
{
    // singleton scaffold per unity-patterns ([DefaultExecutionOrder(-100)] + Awake guard + DontDestroyOnLoad)
    public static SaveManager Instance { get; private set; }
    public SaveData Current { get; private set; } = new();
    int activeSlot = 1;

    void OnEnable()
    {
        // Persistence-specific: write on quit / pause
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

- `JsonUtility` silently drops `Dictionary` fields, polymorphic types, and `object`-typed fields — no warning, just missing data.
- Direct write without atomic pattern equals corrupt save on crash.
- WebGL writes need `FS.syncfs` flush; Unity handles this on `Application.Quit()`, but force-closing the tab loses unflushed data.
- `File.WriteAllText` is synchronous — for huge saves (>1 MB) move to a background thread or `Task.Run`. Not in WebGL — no threads.
- Save data inside `Assets/Resources/` ships with the build, read-only at runtime.
- Encryption with a hardcoded key is security theater. Players reverse it. Use a server for real anti-cheat.
- Newtonsoft.Json adds ~1 MB to the build; install via Package Manager only if `JsonUtility` cannot meet the schema.
- iOS iCloud backup of large save files can cause App Store rejection — set `NoBackup` on regenerable caches.
- Path separators — always use `Path.Combine`. Hardcoded `/` breaks Windows; hardcoded `\` breaks everything else.

## Verification

- After save, read the file back with `manage_asset` or `File.ReadAllText` and assert the content matches and `saveVersion` is present.
- Test on each target platform — `Application.persistentDataPath` differs; iOS / Android sandboxing surfaces only at runtime.
- For atomic writes, kill the app mid-write (Force Quit / Task Manager / ADB kill) and confirm the previous save survives via the `.bak` file.
- `read_console` for `IOException`, `UnauthorizedAccessException`, `DirectoryNotFoundException`.
- On first boot, log `Application.persistentDataPath` and confirm it is writable — `File.WriteAllText` to a probe file then delete.
- Verify settings round-trip: set a slider, restart Play mode, confirm the value loaded.

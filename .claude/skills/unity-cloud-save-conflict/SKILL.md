---
name: unity-cloud-save-conflict
description: 'Use when wiring cloud-save sync, schema migration, and conflict resolution in Unity through Unity MCP — cloud save, cloud sync, Steam Cloud, iCloud, Google Play Saved Games, Unity Cloud Save, Firebase Realtime Database, Firestore, save conflict, conflict resolution, last writer wins, vector clock, schema migration, cloud schema, save migration, save versioning, sync save, save merge, save reconcile, three-way merge, server timestamp. Complements unity-persistence (local saves) and unity-auth-account-linking (the user identity behind cloud saves). Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Any task that pushes save data off-device — Steam Cloud whitelist, iCloud key-value sync, Google Play Saved Games slot, Unity Cloud Save Data API, Firestore document writes — or any task that has to reconcile divergent state between two devices, two installs, or an old client reading a newer save format. Cross-link `unity-persistence` (the local-save layer + JsonUtility wrappers), `unity-auth-account-linking` (the `playerID` cloud saves are keyed to), `unity-iap` (entitlement sync), `unity-best-practices`.

## Why

Every modern game expects players to switch devices. New phone, new console gen, reinstall after a year away. Without cloud save, switching = losing progress = uninstall. With cloud save, retention and re-engagement go up — especially for F2P where the player invested in a soft-currency stash.

## Local-first vs cloud-first

- **Local-first**: write to disk immediately; sync to cloud asynchronously. App stays usable offline. Most single-player and casual games. Requires conflict resolution because two devices can write while offline.
- **Cloud-first**: every write goes to server; UI either waits or optimistically updates and rolls back on failure. Stronger consistency. Hostile to offline play. Right for competitive multiplayer / live-ops where the server is authoritative anyway.

Pick local-first unless you have a server-authoritative reason. Local-first is harder operationally (you must build merge logic) but the UX is better and you keep working without connectivity.

## Pick a service

- **Steam Cloud** — free with Steamworks. Whitelist file patterns in the Partner site; Steam auto-syncs them. PC-only. ~1 GB per user typical.
- **iCloud** — Apple-native. Small KV via `NSUbiquitousKeyValueStore` (1 MB total cap), files via CloudKit container + `NSURLUbiquitousItemKey`. iOS/macOS only. User must have iCloud Drive enabled.
- **Google Play Saved Games** — Android-only. `SavedGames` API via Google Play Games SDK; uploads byte arrays + cover image + description. Player can browse saves in the Play Games app.
- **Unity Cloud Save (UGS)** — cross-platform. Atomic key-value writes per `playerID`. Integrated with Unity Authentication (`unity-auth-account-linking`).
- **Firebase Realtime Database / Firestore** — cross-platform full DB. Use when you also need leaderboards, friends, or social state in the same store. Firestore is the modern pick.

Cross-platform sharing (Steam + iCloud + Play Games on the same account) only works through your own backend bridge — UGS or Firebase keyed to a linked account. The platform-native services don't talk to each other.

## Steam Cloud

1. Steamworks Partner site -> App Admin -> Cloud -> Auto-Cloud configuration.
2. Add file patterns (e.g., `save_*.json`) and choose root directory (`%USERPROFILE%/AppData/LocalLow/Studio/Game` for Windows).
3. Build with the Steamworks SDK; `Steamworks.SteamRemoteStorage` exposes quota + manual upload.
4. Listen for `RemoteStorageAppSyncedClient_t` to detect cloud-pulled changes. Steam will not auto-merge — if both PCs are offline and edit the same file, Steam keeps one and the player is asked which to keep on next launch via the Steam client UI.
5. Check `GetQuota()` before large writes; quota-exceeded fails silently in some cases.

## iCloud

- Small data (< 1 MB total): `NSUbiquitousKeyValueStore` — KV like PlayerPrefs but synced. Good for flags / current-save-slot pointer / settings.
- Larger: CloudKit container, `NSFileManager` + `URLForUbiquityContainerIdentifier`. Good for actual save blobs.
- Check `NSUbiquityIdentityToken` first — nil = user not signed in to iCloud, sync silently disabled. Design for graceful degradation: keep playing locally, surface a one-time "iCloud unavailable" toast.
- iOS-only via Unity native plugin or `UnityEngine.iOS.NotificationServices` (limited); most studios use a thin Objective-C bridge.

## Google Play Saved Games

```csharp
PlayGamesPlatform.Instance.SavedGame.OpenWithAutomaticConflictResolution(
    "save_slot_1",
    DataSource.ReadCacheOrNetwork,
    ConflictResolutionStrategy.UseLongestPlaytime,
    (status, metadata) => { /* read or write byte[] */ }
);
```

`ConflictResolutionStrategy` includes `UseOriginal`, `UseUnmerged`, `UseLongestPlaytime`, `UseMostRecentlySaved`. Or use `OpenWithManualConflictResolution(...)` and provide a callback that picks the winner — required when neither auto-strategy fits (e.g., merge currencies). Cover image + description show in the Play Games UI; keep them current.

## Unity Cloud Save (UGS)

```csharp
await CloudSaveService.Instance.Data.Player.SaveAsync(new Dictionary<string, object> {
    { "save_v3", JsonUtility.ToJson(state) },
    { "save_version", 3 }
});

var keys = new HashSet<string> { "save_v3", "save_version" };
var loaded = await CloudSaveService.Instance.Data.Player.LoadAsync(keys);
```

ETags via `SaveOptions(new WriteLockOptions { WriteLock = lastEtag })` give optimistic concurrency — if two devices race a write, the second gets a 412 and the client merges + retries. Atomic per-key, not across keys.

## Firebase

- **Realtime Database**: JSON tree, real-time listeners, conflicts resolved by last server timestamp. Good for low-latency multiplayer state.
- **Firestore**: documents + collections, server timestamps, transactions, Cloud Functions for server-authoritative merges. The right Firebase pick for save data.

```csharp
var docRef = FirebaseFirestore.DefaultInstance.Collection("saves").Document(playerID);
await docRef.SetAsync(new Dictionary<string, object> {
    { "state", JsonUtility.ToJson(state) },
    { "version", 3 },
    { "updatedAt", FieldValue.ServerTimestamp }
}, SetOptions.MergeAll);
```

## Conflict resolution strategies

- **Last-Writer-Wins (LWW)** — compare server timestamps; newer wins. Simplest; lossy. Acceptable for non-overlapping data (settings, cosmetic prefs).
- **Merge by domain** — per-field rules: `currency = MAX(local, cloud)`, `inventory = union`, `quest_progress = MAX(level, level)`, `unlocks = union`. Custom merger keyed to your save schema. Right answer for most F2P progression.
- **User-prompted** — show "Local: L5, 100 gems / Cloud: L7, 50 gems — pick one". Last resort but the only safe answer when MAX-merge would still lose meaningful state. Required UX when merge confidence is low.
- **Vector clocks** — detect true concurrent edits across devices. Each device increments its own counter on every write; on conflict you know which device made which change. Advanced; rarely needed for indie games.

Default to merge-by-domain with a user-prompt fallback for high-stakes fields.

## Schema migration

Save data must carry a version field at the root:

```csharp
[Serializable] public class SaveDataV3 {
    public int saveVersion = 3;
    public int level;
    public int gems;
    public List<string> unlockedSkins;
    public DateTime lastPlayed;
}
```

On load: branch on `saveVersion` -> migrate old -> save new format. Cross-link `unity-persistence` for the local-save migration patterns; cloud-save migration is the same shape but keyed off the cloud blob.

```csharp
var json = LoadJsonFromCloud();
var probe = JsonUtility.FromJson<VersionProbe>(json);
SaveDataV3 state = probe.saveVersion switch {
    1 => MigrateV1ToV3(JsonUtility.FromJson<SaveDataV1>(json)),
    2 => MigrateV2ToV3(JsonUtility.FromJson<SaveDataV2>(json)),
    3 => JsonUtility.FromJson<SaveDataV3>(json),
    _ => throw new InvalidDataException($"Unknown save version {probe.saveVersion}")
};
```

Cloud saves outlive client versions — a v2 client may load a v3 save (forward-compat) or refuse and prompt update. Decide on per-game basis. Forward-compat works if you only add fields (with sensible defaults); breaking changes need a forced update.

## Cross-device handoff

1. User installs on Phone B. App boots, anonymous auth or restores linked auth (`unity-auth-account-linking`).
2. Cloud save loaded under that `playerID`.
3. Local save is fresh (first install). Local replaced by cloud silently.
4. If cloud has no save, push initial local up. First-ever install starts fresh.
5. If both local AND cloud have data (e.g., user played offline before signing in), run conflict resolution. Don't silently overwrite either side.

## Common patterns

- **Save buffer** — write to local disk immediately on every meaningful event (level complete, IAP, settings change). Batch cloud sync every 30s and on `OnApplicationPause(true)` / `OnApplicationFocus(false)`. Reduces write count and battery drain.
- **Pre-write backup** — keep `save.json.bak` of the last cloud-confirmed state. Roll back on corrupted load. Lifesaver during schema-migration bugs.
- **Versioned struct + JsonUtility** — cross-link `unity-persistence`. Use the dictionary-wrapper pattern there since `JsonUtility` cannot serialize `Dictionary<>` directly.
- **Conflict UI** — a clear "Use cloud / Keep local / Cancel" dialog with timestamps and key stats ("Cloud: L7, 50 gems, played 2 days ago / Local: L5, 100 gems, played 1 hour ago"). Never auto-resolve when stats are close.

## Gotchas

- Cloud write succeeded but local write failed (rare but happens — disk full, OS kill mid-write) = local-cloud divergence on next read. Always update local first then push to cloud; the local write is the source of truth.
- iCloud silently fails for users not signed in. Check `NSUbiquityIdentityToken` first; surface degradation gracefully.
- Steam Cloud quota exceeded = silent partial sync. Trim old saves; Steam quota is per app, not per save file.
- Schema migration bugs lose progress permanently. Test migration on real save files harvested from beta testers; keep the pre-migration blob in `.bak` for at least one launch cycle.
- Last-Writer-Wins between two devices played offline = whoever syncs second wins. Player rage. Use merge-by-domain + user prompt.
- `JsonUtility` cannot deserialize `Dictionary` directly. Use the wrapper pattern from `unity-persistence`. Newtonsoft.Json works but adds payload size and an IL2CPP-stripping concern.
- Encryption-at-rest: cloud saves are accessible to the platform vendor (and sometimes to the player via file browsers, especially on PC). Don't trust cloud for anti-cheat — server-authoritative validation is the only real defense.
- Cross-platform save sharing (Steam Cloud + iCloud + Play Games) requires bridging through your own backend (UGS / Firebase). The native services don't talk.
- `OnApplicationPause` is your last reliable hook on mobile before the OS may kill the process. Sync cloud there; do not rely on `OnApplicationQuit`.

## Verification

- Save on Device A -> uninstall + reinstall on Device A -> cloud restores the last state.
- Save on Device A (linked account) -> install on Device B with the same account -> cloud loads, local replaced.
- Conflict scenario: take Device A and Device B both offline, edit on each, reconnect both -> conflict resolution UI fires (or merge-by-domain produces a sensible union state).
- Schema migration: save with v2 client -> upgrade to v3 client -> v3 reads the v2 save without progress loss; `.bak` is created.
- Quota / failure paths: simulate Steam quota full, iCloud signed-out, Play Games unavailable -> game keeps working locally with a single non-blocking warning.
- Cloud-only entitlement (e.g., subscription unlock) survives reinstall on a new device with the same `playerID`.

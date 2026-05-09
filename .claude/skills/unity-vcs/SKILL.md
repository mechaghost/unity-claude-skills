---
name: unity-vcs
description: 'Use when setting up or operating version control on a Unity project via Unity MCP — anything involving git, version control, .gitignore, Git LFS, scene merge, prefab merge, YAML merge, smart merge, UnityYAMLMerge, force text serialization, asset serialization mode, meta files, GUID, Visible Meta Files, EditorSettings, conflict resolution, .gitattributes, Plastic SCM, Perforce. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

Unity breaks version control via binary scenes, GUIDs in `.meta`, multi-GB binary asset histories, and YAML merges that look text-shaped but aren't line-mergeable.

## When to use

- New Unity repo: `.gitignore`, `.gitattributes`, EditorSettings before first commit.
- Teammate cloned and got pointer files where art should be — LFS not installed.
- Two people edited same scene and Git produced unfixable conflict.
- `Library/` got committed; repo is now huge.
- Prefab reference broke after rename/move.
- Considering Plastic SCM or Perforce for an art-heavy team.

## Critical EditorSettings

Non-negotiable. Set before first commit.

- **Asset Serialization mode**: `Force Text` (Edit > Project Settings > Editor > Asset Serialization). Without this, `.unity` and `.prefab` are binary and unmergeable.
- **Version Control mode**: `Visible Meta Files` (same panel). Ensures `.meta` files exist on disk.

Set `serializationMode = ForceText` and `externalVersionControl = Visible Meta Files`. Writes to `ProjectSettings/EditorSettings.asset` (commit it).

## .gitignore for Unity

```gitignore
# Unity-generated, never commit
[Ll]ibrary/
[Tt]emp/
[Oo]bj/
[Bb]uild/
[Bb]uilds/
[Ll]ogs/
[Uu]ser[Ss]ettings/
[Mm]emoryCaptures/

# Asset Store / package caches
[Aa]ssetStoreTools*/
.consulo/

# Visual Studio / Rider / generated solution
*.csproj
*.unityproj
*.sln
*.suo
*.tmp
*.user
*.userprefs
*.pidb
*.booproj
*.svd
*.pdb
*.mdb
*.opendb
*.VC.db
.vs/
.idea/
.vscode/

# OS
.DS_Store
Thumbs.db

# Build outputs
*.apk
*.aab
*.ipa
*.unitypackage
*.app

# Crashlytics
crashlytics-build.properties
```

Do **not** ignore: `Assets/`, `Packages/`, `ProjectSettings/`, any `*.meta`.

`UserSettings/` is per-user editor state — ignore. `Packages/manifest.json` and `Packages/packages-lock.json` must be committed.

## .gitattributes (LFS + line endings + merge driver)

```gitattributes
# Force consistent line endings
* text=auto eol=lf

# Unity YAML — text but not line-mergeable; mark for SmartMerge
*.unity   merge=unityyamlmerge eol=lf
*.prefab  merge=unityyamlmerge eol=lf
*.asset   merge=unityyamlmerge eol=lf
*.meta    merge=unityyamlmerge eol=lf
*.mat     merge=unityyamlmerge eol=lf
*.anim    merge=unityyamlmerge eol=lf
*.controller merge=unityyamlmerge eol=lf
*.physicMaterial merge=unityyamlmerge eol=lf
*.physicsMaterial2D merge=unityyamlmerge eol=lf

# LFS — binary art and audio
*.png  filter=lfs diff=lfs merge=lfs -text
*.jpg  filter=lfs diff=lfs merge=lfs -text
*.jpeg filter=lfs diff=lfs merge=lfs -text
*.psd  filter=lfs diff=lfs merge=lfs -text
*.tga  filter=lfs diff=lfs merge=lfs -text
*.tif  filter=lfs diff=lfs merge=lfs -text
*.tiff filter=lfs diff=lfs merge=lfs -text
*.exr  filter=lfs diff=lfs merge=lfs -text
*.hdr  filter=lfs diff=lfs merge=lfs -text
*.fbx  filter=lfs diff=lfs merge=lfs -text
*.obj  filter=lfs diff=lfs merge=lfs -text
*.blend filter=lfs diff=lfs merge=lfs -text
*.wav  filter=lfs diff=lfs merge=lfs -text
*.mp3  filter=lfs diff=lfs merge=lfs -text
*.ogg  filter=lfs diff=lfs merge=lfs -text
*.aif  filter=lfs diff=lfs merge=lfs -text
*.aiff filter=lfs diff=lfs merge=lfs -text
*.mp4  filter=lfs diff=lfs merge=lfs -text
*.mov  filter=lfs diff=lfs merge=lfs -text
*.webm filter=lfs diff=lfs merge=lfs -text
*.dll  filter=lfs diff=lfs merge=lfs -text
*.so   filter=lfs diff=lfs merge=lfs -text
*.dylib filter=lfs diff=lfs merge=lfs -text
*.bundle filter=lfs diff=lfs merge=lfs -text
*.unitypackage filter=lfs diff=lfs merge=lfs -text
*.zip  filter=lfs diff=lfs merge=lfs -text
```

`merge=unityyamlmerge` driver is defined in `.git/config` (next section). Without it, git falls back to default text merge.

You can mark `*.unity` and `*.prefab` as `binary` instead — disables git's line-by-line merge entirely and forces picking one side. Useful on small teams where you'd rather coordinate than merge.

## Git LFS setup

LFS replaces binary blobs with text pointers; bytes live on a separate LFS server.

```sh
brew install git-lfs                 # macOS; or git-lfs.com
git lfs install                      # once per machine
cd /path/to/repo
git lfs install --local              # writes .git/hooks
# .gitattributes already lists patterns; no extra `git lfs track` needed
git add .gitattributes
git commit -m "Add LFS .gitattributes"
```

Every collaborator must run `git lfs install` once. Without it, they clone pointer files (text stubs `version https://git-lfs.github.com/spec/v1\noid sha256:...`) instead of real binaries — Unity throws "The associated script cannot be loaded" or pink materials.

GitHub free tier: 1 GB storage, 1 GB/month bandwidth across LFS. Beyond, buy data packs or self-host (Gitea, GitLab, AWS S3 via `lfs-test-server`).

## Scene and prefab merging — UnityYAMLMerge / SmartMerge

`UnityYAMLMerge` (a.k.a. SmartMerge) understands `.unity` and `.prefab` YAML structure. Configure once per repo:

```sh
# macOS, Unity 6 default
git config merge.unityyamlmerge.name "Unity SmartMerge"
git config merge.unityyamlmerge.driver \
  '/Applications/Unity/Hub/Editor/<version>/Unity.app/Contents/Tools/UnityYAMLMerge merge -p %O %B %A %A'
git config merge.unityyamlmerge.recursive binary
```

Windows: `C:\Program Files\Unity\Hub\Editor\<version>\Editor\Data\Tools\UnityYAMLMerge.exe`.
Linux: `/opt/Unity/Editor/Data/Tools/UnityYAMLMerge`.

`<version>` changes per Unity install; use `git config --global` with a stable symlink if switching often.

After conflict, `git mergetool` resolves clean structural changes. Genuine same-property conflicts still need a human.

## .meta files — the GUID rule

Every asset under `Assets/` has a sibling `<file>.meta` with a GUID. Other assets and scripts reference by GUID, not path.

- **Always commit the `.meta`** alongside its asset. Same commit, every time.
- **Never delete a `.meta` without deleting the asset.** Silently breaks references project-wide.
- **Never hand-edit `guid:`.** Renames preserve GUID; delete-and-recreate generates a new one.
- **Move/rename in the Unity Editor**, not Finder/Explorer. Unity updates metadata; Finder doesn't.
- If a teammate force-pushed a tree where `.meta` files are missing, restore from history before the next commit.

Set Visible Meta Files (above) so `.meta` files exist on disk. Without it, hidden meta files live in `Library/` and never reach git.

## Branch hygiene

- **Scene ownership per sprint.** One person per scene per sprint or feature branch. Two people on `Boot.unity` is the most common unmergeable.
- **Prefab variants over base-prefab edits.** Variant adds a delta; base stays stable.
- **Small PRs**: <500 LOC code and <3 scene/prefab changes. Big mixed PRs are where SmartMerge gives up.
- **Merge from `main` into your branch frequently** to surface conflicts while small.
- **Lock binary files** via `git lfs lock <path>` for genuinely uncoordinatable art (hero model someone iterates on).

## Bootstrap pattern

Order matters — set serialization before the first scene saves.

1. `git lfs install` (once per machine, before anything else).
2. `git init` (or clone).
3. Drop in `.gitignore` and `.gitattributes`.
4. Open in Unity, Project Settings → Editor: `Asset Serialization = Force Text`, `Version Control = Visible Meta Files`.
5. `git add .gitignore .gitattributes ProjectSettings/ Packages/manifest.json Packages/packages-lock.json`
6. `git commit -m "Initial Unity project skeleton"`
7. Add `Assets/` and continue.

## Common patterns

- **Recovering a repo that committed `Library/`** — `git rm -r --cached Library/`, commit. Library regenerates locally.
- **Adding LFS late** — install LFS, update `.gitattributes`, `git lfs migrate import --include="*.png,*.fbx,..." --everything`. Rewrites history; coordinate and force-push.
- **Splitting a giant scene** into additive sub-scenes (boot + level + UI) for parallel editing. See `unity-scenes`.
- **Per-platform asset bundles** under `Assets/StreamingAssets/` should still be LFS-tracked.

## Gotchas

- `Library/` committed by accident — `git rm -r --cached Library/`, add to `.gitignore`. Bloat persists in history; `git filter-repo` for old repos.
- Force Text not set day one — early scenes are binary. Toggle, re-save each scene to convert.
- LFS not installed by teammate — pointer files. `git lfs install && git lfs pull`.
- `.gitattributes` added late — committed binaries still in regular git history. `git lfs migrate import` to rewrite.
- SmartMerge driver path baked into `.git/config` per Unity version — switching versions can leave the driver pointing at a missing path. Stable symlink or `setup-merge.sh` script.
- `*.meta` deleted manually outside Unity — Unity regenerates a new GUID, every reference goes pink. Restore from git.
- Embedded packages under `Packages/com.studio.foo/` need their own `.gitignore` if you keep package `Library` caches there.

**Plastic SCM** — Unity's first-party VCS (bundled in Hub as Unity Version Control / DevOps). Handles binary assets and locks better than git+LFS for art-heavy teams (50+ people, TB of textures), supports partial checkouts, integrates with Editor. Trade-off: smaller ecosystem, harder for engineers used to git CLI. Worth considering when art outnumbers engineering.

**Perforce** — AAA default. Centralized, scales to TB-sized depots, granular file locks, Unity integration via legacy P4Connect. Overkill for indie; near-mandatory for large studios.

## Verification

- `git status` shows clean tree, no `Library/` or `Temp/`.
- `git lfs ls-files` lists expected binaries; after a fresh clone confirms LFS pulled bytes (not pointers).
- Open a scene, move a GameObject, save, `git diff` — readable YAML, not binary noise.
- Branch test: `git checkout -b vcs-test`, edit a scene, commit, back to `main`, edit same scene differently, merge — SmartMerge should resolve cleanly when edits touch different GameObjects.
- Console clean after pulling — no "missing script" or "missing prefab" means GUIDs survived.

## Cross-links

- `unity-asmdef` — commit `.asmdef` and `.asmdef.meta` (always paired, GUID stable across renames).
- `unity-build` — CI runners must have `git lfs install` in bootstrap or build fails with pink materials and missing models.

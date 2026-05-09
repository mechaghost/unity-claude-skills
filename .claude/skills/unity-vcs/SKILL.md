---
name: unity-vcs
description: 'Use when setting up or operating version control on a Unity project via Unity MCP — anything involving git, version control, .gitignore, Git LFS, scene merge, prefab merge, YAML merge, smart merge, UnityYAMLMerge, force text serialization, asset serialization mode, meta files, GUID, Visible Meta Files, EditorSettings, conflict resolution, .gitattributes, Plastic SCM, Perforce. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

# unity-vcs

Unity projects break version control in specific ways: binary scenes, GUIDs in `.meta` files, multi-GB binary asset histories, and YAML merges that look text-shaped but aren't line-mergeable. This skill covers the bootstrap and the recovery patterns.

## When to use

- Starting a new Unity repo and need the right `.gitignore`, `.gitattributes`, and EditorSettings before the first commit.
- A teammate cloned and got pointer files where art should be — LFS not installed.
- Two people edited the same scene and Git produced a conflict that looks unfixable.
- `Library/` got committed by accident and the repo is now huge.
- A prefab reference broke after a rename or move.
- Considering Plastic SCM or Perforce for an art-heavy team.

## Critical EditorSettings

These are non-negotiable for any Unity project under git. Set them before the first commit.

- **Asset Serialization mode**: `Force Text` — Edit > Project Settings > Editor > Asset Serialization. Without this, `.unity` and `.prefab` files are binary and impossible to diff or merge.
- **Version Control mode**: `Visible Meta Files` — same panel. Ensures `.meta` files exist on disk for every asset (so git can see them).

Apply through Project Settings → Editor: set `serializationMode = ForceText` and `externalVersionControl = Visible Meta Files`. These write into `ProjectSettings/EditorSettings.asset`, which itself must be committed.

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

Do **not** ignore: `Assets/`, `Packages/`, `ProjectSettings/`, or any `*.meta` file.

`UserSettings/` is per-user editor state (layouts, recent scenes); ignore it. `Packages/manifest.json` and `Packages/packages-lock.json` must be committed.

## .gitattributes (LFS + line endings + merge driver)

```gitattributes
# Force consistent line endings on text
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

The `merge=unityyamlmerge` driver will be defined in `.git/config` (next section). Without that driver definition, git falls back to its default text merge for those files.

You can additionally mark `*.unity` and `*.prefab` as `binary` instead — that disables git's line-by-line merge entirely and forces the user to pick one side. Useful on small teams where you'd rather coordinate than merge.

## Git LFS setup

LFS replaces binary blobs in git history with text pointer files; the actual bytes live on a separate LFS server.

Bootstrap:

```sh
brew install git-lfs                 # macOS; or download from git-lfs.com
git lfs install                      # once per machine
cd /path/to/repo
git lfs install --local              # writes .git/hooks
# .gitattributes already lists patterns; no extra `git lfs track` needed
git add .gitattributes
git commit -m "Add LFS .gitattributes"
```

Every collaborator must run `git lfs install` once on their machine. Without it, they will clone pointer files (text stubs that look like `version https://git-lfs.github.com/spec/v1\noid sha256:...`) instead of the real binaries — Unity will throw "The associated script cannot be loaded" or pink materials.

GitHub free tier: 1 GB storage and 1 GB/month bandwidth across LFS. Beyond that, buy data packs or self-host (Gitea, GitLab, AWS S3 via `lfs-test-server`).

## Scene and prefab merging — UnityYAMLMerge / SmartMerge

Unity ships a CLI merge tool called `UnityYAMLMerge` (a.k.a. SmartMerge) that understands the YAML structure of `.unity` and `.prefab` files. Configure it once per repo:

```sh
# macOS, Unity 6 default install path
git config merge.unityyamlmerge.name "Unity SmartMerge"
git config merge.unityyamlmerge.driver \
  '/Applications/Unity/Hub/Editor/<version>/Unity.app/Contents/Tools/UnityYAMLMerge merge -p %O %B %A %A'
git config merge.unityyamlmerge.recursive binary
```

Windows path: `C:\Program Files\Unity\Hub\Editor\<version>\Editor\Data\Tools\UnityYAMLMerge.exe`.
Linux: `/opt/Unity/Editor/Data/Tools/UnityYAMLMerge`.

The `<version>` segment changes per-Unity-install; use `git config --global` with a stable symlink if you switch versions often.

After conflict, run `git mergetool` and SmartMerge will resolve clean structural changes (added GameObjects, edited components on different objects). Genuine same-property conflicts still need a human.

## .meta files — the GUID rule

Every asset under `Assets/` has a sibling `<file>.meta` with a generated GUID. Other assets and scripts reference the asset by GUID, not by path.

Rules:

- **Always commit the `.meta`** alongside its asset. Same commit, every time.
- **Never delete a `.meta` without deleting the asset.** Git will silently break references project-wide.
- **Never hand-edit the `guid:` line.** Renames preserve GUID; delete-and-recreate generates a new one and breaks all references.
- **Move/rename in the Unity Editor**, not in Finder/Explorer. Unity updates the metadata; Finder does not.
- If a teammate force-pushed a tree where `.meta` files are missing, restore from history before the next commit — once references break, they cascade.

Set Visible Meta Files (above) so `.meta` files actually exist on disk. Without it, hidden meta files live in `Library/` and never reach git.

## Branch hygiene

- **Scene ownership per sprint.** Designate one person per scene for the duration of a sprint or feature branch. Two people on `Boot.unity` is the most common cause of unmergeable conflicts.
- **Prefer prefab variants over base-prefab edits.** A variant adds a delta; the base prefab stays stable for everyone else.
- **Keep PRs small**: <500 LOC of code and <3 scene/prefab changes. Big mixed PRs are where SmartMerge gives up.
- **Merge from `main` into your branch frequently** to surface conflicts while they're small.
- **Lock binary files** via `git lfs lock <path>` for art that is genuinely uncoordinatable (e.g. a hero model someone is iterating on for the day).

## Bootstrap pattern

Order matters — set serialization before the first scene gets saved.

1. `git lfs install` (once per machine, before anything else).
2. `git init` (or clone).
3. Drop in `.gitignore` and `.gitattributes` from above.
4. Open the project in Unity, then under Project Settings → Editor set `Asset Serialization = Force Text` and `Version Control = Visible Meta Files`.
5. `git add .gitignore .gitattributes ProjectSettings/ Packages/manifest.json Packages/packages-lock.json`
6. `git commit -m "Initial Unity project skeleton"`
7. Add `Assets/` and continue.

## Common patterns

- **Recovering a repo that committed `Library/`**: `git rm -r --cached Library/`, then commit. Library regenerates locally.
- **Adding LFS late**: install LFS, update `.gitattributes`, then `git lfs migrate import --include="*.png,*.fbx,..." --everything`. Rewrites history; coordinate with the team and force-push.
- **Splitting a giant scene** into additive sub-scenes (boot + level + UI) so multiple people can edit in parallel. See unity-scenes.
- **Per-platform asset bundles** under `Assets/StreamingAssets/` should still be LFS-tracked.

## Gotchas

- `Library/` committed by accident — `git rm -r --cached Library/` and add to `.gitignore`. Massive repo bloat persists in history; consider `git filter-repo` for old repos.
- Force Text not set on day one — early scenes are binary. Toggle the setting; re-save each scene to convert.
- LFS not installed by a teammate — they will see pointer files (a few-line text stub) in place of binaries. Tell them `git lfs install && git lfs pull`.
- `.gitattributes` added late — existing committed binaries are still in regular git history. Run `git lfs migrate import` to rewrite.
- SmartMerge driver path baked into `.git/config` per Unity version — switching Unity versions on the same repo can leave the driver pointing at a path that no longer exists. Use a stable symlink or commit a `setup-merge.sh` script.
- `*.meta` deleted manually outside Unity — Unity regenerates a new GUID, every reference to that asset goes pink. Restore from git.
- Embedded packages under `Packages/com.studio.foo/` need their own `.gitignore` if you keep package `Library` caches there.

**Plastic SCM** is Unity's first-party VCS (now bundled in Unity Hub as Unity Version Control / DevOps). It handles binary assets and locks better than git+LFS for art-heavy teams (50+ people, terabytes of textures), supports partial checkouts, and integrates with the Editor. Trade-off: smaller ecosystem, harder for engineers used to git CLI. Worth considering when the art team outnumbers engineering.

**Perforce** is the AAA studio default. Centralized, scales to TB-sized depots, granular file locks, integrates with Unity via the legacy P4Connect plugin. Overkill for indie teams; near-mandatory for large studios.

## Verification

- `git status` shows a clean tree and no `Library/` or `Temp/` listed.
- `git lfs ls-files` lists all expected binaries; running it after a fresh clone confirms LFS pulled bytes (not pointers).
- Open a scene, move a GameObject, save, and run `git diff` — the diff should be readable YAML, not binary noise.
- Branch test: `git checkout -b vcs-test`, edit a scene, commit, switch back to `main`, edit the same scene differently, merge — SmartMerge should resolve cleanly when the two edits touch different GameObjects.
- Editor console clean after pulling — no "missing script" or "missing prefab" errors means GUIDs survived.

## Cross-links

- See unity-asmdef for committing `.asmdef` and `.asmdef.meta` files (always paired, GUID stable across renames).
- See unity-build — CI runners must have `git lfs install` in the bootstrap step or the build will fail with pink materials and missing models.

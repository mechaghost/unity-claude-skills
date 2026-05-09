---
name: unity-ci
description: 'Use when wiring CI/CD orchestration around a Unity project — CI, CD, CI/CD, continuous integration, continuous delivery, GitHub Actions, GameCI, game-ci, unity-builder, unity-test-runner, Unity Cloud Build, UCB, Jenkins, GitLab CI, Bitbucket Pipelines, headless build, batchmode, -batchmode, -executeMethod, -runTests, license activation, ULF, Unity license, return-license, build agent, build runner, build matrix, secrets management, GitHub Secrets, fastlane match, signing CI, P12, P8 secret, keystore CI, build cache, asset cache, Library cache, accelerator, Unity Accelerator, build report parsing, BuildReport, artifact upload, slack notification, build notification, .github/workflows, ci.yml. Unity 6+ / 6000.x / URP-only / new Input System only. NOT for build pipeline mechanics (use unity-build), NOT for store submission (use unity-store-shipping-pipeline), NOT for test authoring (use unity-tests).'
---

## When to use

Any time a Unity project needs to build outside a developer's local machine: setting up GitHub Actions / GameCI / Unity Cloud Build / Jenkins, activating Unity licenses on a runner, wiring keystores and signing certs into CI secrets, configuring a build matrix across platforms, caching `Library/`, hooking fastlane lanes after a build, parsing `BuildReport` in CI, or sending build notifications. Read `unity-best-practices` first. Cross-link `unity-build` (build pipeline mechanics), `unity-store-shipping-pipeline` (fastlane lanes + store APIs), `unity-tests` (test authoring), `unity-vcs` (LFS in CI, .gitignore, secrets hygiene), `unity-crash-reporting` (symbol upload as a CI step).

## Why distinct skill

`unity-build` knows how to call `BuildPipeline.BuildPlayer` and configure `PlayerSettings`. `unity-store-shipping-pipeline` knows fastlane lanes and store APIs. `unity-tests` knows how to author EditMode/PlayMode tests. The connective tissue — runner setup, license activation, secret handoff, cache strategy, matrix builds, notifications — has no home in those skills and is consistently the largest gap for teams setting up CI for the first time. This skill owns that tissue.

## Pick a runner

- **GitHub Actions + GameCI** (`game-ci/unity-builder`, `game-ci/unity-test-runner`) — most popular for indie / mid-size studios. Dockerized Unity images per version, free tier 2000 min/month for public repos, paid runners for self-hosted speed. Default pick.
- **Unity Cloud Build (UCB / Unity DevOps)** — hosted by Unity, simplest setup, integrates with Plastic SCM well; cost scales with build minutes. Good if your team already pays for Unity DevOps.
- **Self-hosted GitHub runners / Jenkins** — faster builds (Library cache stays warm), required for macOS/iOS at scale (~10+ Mac builds/day) because GitHub-hosted Mac minutes are 10x Linux pricing. Operational overhead is real.
- **GitLab CI / Bitbucket Pipelines** — similar Docker-image patterns to GameCI; less Unity ecosystem support. Use when your team is already committed to that platform.

## Unity license activation

The most-painful step for first-time CI setups.

- **Personal license** — free, machine-bound. Activate via `-username/-password` (legacy) or `-manualLicenseFile` (.ulf) for the current Unity Hub flow. GameCI handles this with `UNITY_EMAIL`, `UNITY_PASSWORD`, `UNITY_SERIAL` secrets.
- **Plus / Pro / Enterprise** — serial-based; activate at start of build, return at end (`-returnlicense`). Skipping the return = floating-license drift; eventually CI runs hit `no licenses available` and fail until you manually return seats.
- **Floating license server** (Enterprise only) — runner checks out license, returns on completion. Best for teams of >5 builders.

## GitHub Actions + GameCI

Boilerplate for an Android build job:

```yaml
jobs:
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { lfs: true }
      - uses: actions/cache@v4
        with:
          path: Library
          key: Library-${{ matrix.targetPlatform }}-${{ hashFiles('Assets/**', 'Packages/**', 'ProjectSettings/**') }}
          restore-keys: |
            Library-${{ matrix.targetPlatform }}-
            Library-
      - uses: game-ci/unity-builder@v4
        env:
          UNITY_EMAIL: ${{ secrets.UNITY_EMAIL }}
          UNITY_PASSWORD: ${{ secrets.UNITY_PASSWORD }}
          UNITY_SERIAL: ${{ secrets.UNITY_SERIAL }}
        with:
          targetPlatform: Android
          buildName: game.aab
          androidExportType: androidAppBundle
          androidKeystoreName: ${{ secrets.ANDROID_KEYSTORE_NAME }}
          androidKeystoreBase64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          androidKeystorePass: ${{ secrets.ANDROID_KEYSTORE_PASS }}
          androidKeyaliasName: ${{ secrets.ANDROID_KEYALIAS_NAME }}
          androidKeyaliasPass: ${{ secrets.ANDROID_KEYALIAS_PASS }}
      - uses: actions/upload-artifact@v4
        with: { name: build-android, path: build/Android }
```

## Build matrix per platform

Split jobs by `targetPlatform: [Android, iOS, WebGL, StandaloneWindows64, StandaloneOSX]`. Mac runners are required for iOS and StandaloneOSX. Each platform gets its own job and its own scoped secrets. Don't try to build everything in one job — failures in one target block all the others.

```yaml
strategy:
  fail-fast: false
  matrix:
    targetPlatform: [Android, iOS, WebGL, StandaloneWindows64]
```

## Test runs in CI

Run a separate job using `game-ci/unity-test-runner` with `testMode: editmode` and `testMode: playmode`. Headless flag form: `-batchmode -runTests -testPlatform editmode -testResults results.xml -quit`. Parse `results.xml` in CI; fail the build on any test failure. Cross-link `unity-tests` for what to put inside the tests.

```yaml
- uses: game-ci/unity-test-runner@v4
  with:
    testMode: editmode
    artifactsPath: artifacts/editmode
    githubToken: ${{ secrets.GITHUB_TOKEN }}
```

## Signing secrets management

- **iOS** — `.p12` cert + provisioning profile + App Store Connect API key (`.p8`). Store as base64-encoded GitHub secrets; decode at runtime on the runner.
- **Android** — keystore (`.jks`) base64-encoded; key alias + passwords as separate secrets.
- **fastlane match** (recommended for iOS) — a private git repo holds encrypted certs / profiles; `match` decrypts on the CI runner using a `MATCH_PASSWORD` secret. Eliminates code-signing drift across machines and CI. Cross-link `unity-store-shipping-pipeline`.
- **Never commit secrets**. Cross-link `unity-vcs` for `.gitignore` / `.gitattributes` rules that keep keystores and `.p12` files out of git.

### Generating and encoding secrets

```bash
# Android keystore -> base64 for GitHub Secrets
base64 -i my.keystore | pbcopy   # macOS
base64 -w 0 my.keystore           # Linux

# Decode in CI workflow:
echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > my.keystore

# iOS .p8 from App Store Connect:
# Users and Access > Keys > tap "+" > download once (irretrievable after).
# Then base64 -i AuthKey_XXX.p8 | pbcopy

# fastlane match Personal Access Token:
# GitHub > Settings > Developer settings > Personal access tokens > generate new (repo scope)
# Pass to fastlane as MATCH_PASSWORD env var.
```

**Unity Personal license activation**: GameCI Personal license workflow: leave `UNITY_SERIAL` blank or omit; GameCI auto-runs `-createManualActivationFile` on first run, generates `.alf`, you upload to license.unity3d.com, get a `.ulf` file, paste contents into a `UNITY_LICENSE` secret. Pro/Enterprise: set `UNITY_EMAIL`, `UNITY_PASSWORD`, `UNITY_SERIAL` directly.

## fastlane orchestration

After the Unity build step succeeds, call a fastlane lane to ship the artifact:

```yaml
- name: Upload to Play Internal
  run: bundle exec fastlane android beta
  env:
    SUPPLY_JSON_KEY_DATA: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
```

Lane definitions live in `fastlane/Fastfile`. Cross-link `unity-store-shipping-pipeline` for the lane content (`pilot`, `supply`, `match`, `deliver`, `gym`).

## Library / asset cache strategy

`Library/` rebuilds are 5-30 minutes per fresh build. Cache it.

- **GitHub Actions cache key**: `Library-${platform}-${hash(Assets, Packages, ProjectSettings)}`. The `restore-keys` fall through to the most-recent platform cache when an exact match isn't found.
- **What NOT to cache**: `Logs/`, `MemoryCaptures/`, `Builds/`, `UserSettings/`, `Temp/`. These pollute the cache and slow restores.
- **Cache poisoning warning** — if your hash key doesn't include a relevant input (e.g. a custom `.csproj.template`, a code generator script), `Library/` can drift from sources. Symptoms: "asset failed to import" on cached runs but works fresh. Bust the cache by changing the key prefix.

## Unity Accelerator

Shared cache server for asset import results. Speeds cold builds dramatically (5x+ for art-heavy projects). Self-hosted Docker container; configure via `Edit > Preferences > Asset Pipeline > Cache Server` (or its v2 equivalent in Unity 6). Worth it for teams of 3+, effectively required for any build farm.

## BuildReport parsing in CI

In your Editor build script, write the `BuildReport` to JSON. CI uploads the JSON as an artifact and posts a size summary to Slack — catch unintended size growth before ship rather than after a TestFlight upload.

```csharp
var report = BuildPipeline.BuildPlayer(opts);
var json = JsonUtility.ToJson(new BuildSummary {
    totalSize = report.summary.totalSize,
    totalErrors = report.summary.totalErrors,
    result = report.summary.result.ToString()
});
File.WriteAllText("build-report.json", json);
```

Cross-link `unity-build` for the full `BuildReport` schema.

## Notifications and dashboards

- **Slack / Discord webhook** on build success/failure with the `.aab` / `.ipa` download link.
- **PR comment** with test result summary via `dorny/test-reporter` or similar.
- **Daily digest** job posts crash-free %, build size delta, test coverage to a team channel. Cross-link `unity-crash-reporting`.

## Common patterns

- **PR builds** — dev-flavor build, run tests, post summary as a PR comment. Don't upload to TestFlight on PRs.
- **Main-merge builds** — prod-flavor build, run tests, upload to TestFlight + Play Internal Testing automatically.
- **Tag builds** (`v1.2.3`) — prod build, upload to App Store Connect / Play Store production track with phased rollout.
- **Nightly builds** — full clean `Library/`, run all tests including expensive ones, baseline crash test on a real device farm.

## Gotchas

- **`-quit` flag MUST be on the command line.** Without it, the Unity process hangs forever and the runner times out.
- **`-batchmode` + exception** throws a non-zero exit, but the next-line behavior depends on Unity version. Always check the exit code AND parse the log.
- **`Library/` cache should NOT include `Logs`, `MemoryCaptures`, `Builds`, `UserSettings`.** They pollute restores.
- **GitHub-hosted Mac runners cost 10x Linux minutes.** Minimize iOS jobs (only on main + tags, not PRs) or use self-hosted Macs.
- **License return on cancelled jobs** — catch SIGTERM in the runner cleanup step and run `-returnlicense` so a cancelled CI run doesn't burn a seat.
- **Unity version mismatch between local + CI** = different build outputs. Pin Unity version via the Editor / Unity.exe path or GameCI's `unityVersion` input.
- **LFS bandwidth on GitHub free tier** (1 GB/month) is tight for art-heavy projects. Either pay for an LFS Pack or self-host an LFS server. Cross-link `unity-vcs`.
- **Cache restore on the first PR build** can take 5-10 min just to download. Acceptable; still faster than rebuilding `Library/`.
- **Secrets logged to console = leaked.** GitHub auto-redacts known secrets, but custom env vars need explicit masking via `::add-mask::`.
- **Apple ASC API rate limits** (50 req/min) — fastlane retries with exponential backoff; don't tighten your job concurrency past the limit.
- **Build agents drift** (OS updates, Xcode versions). Pin runner image versions; bump deliberately, not implicitly.

## Verification

- First green build end-to-end: clean checkout → license activate → build → tests → artifact upload → return license.
- Cache hit on the second run: build time drops from ~25 min to ~5 min.
- A test failure correctly fails the job (verify by intentionally breaking one test).
- Artifact uploaded and downloadable from the run page.
- Secrets masked in logs (search for the literal value of one to confirm it's redacted).
- License returned (verify via Unity ID dashboard seat count after the run).
- PR builds run automatically; main-merge auto-deploys to TestFlight / Play Internal Testing.

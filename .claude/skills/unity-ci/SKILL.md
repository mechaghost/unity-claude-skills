---
name: unity-ci
description: 'Use for Unity 6+ CI/CD: GitHub Actions/GameCI/Unity Cloud Build/Jenkins/GitLab, batchmode builds/tests, license activation, secrets/signing, Library/cache/Accelerator, BuildReport parsing, artifacts, notifications. Not build scripts, store submission, or test authoring.'
---

## When to use

GitHub Actions / GameCI / Unity Cloud Build / Jenkins setup, Unity license activation on a runner, keystores and signing certs in CI secrets, build matrix across platforms, caching `Library/`, hooking fastlane lanes after a build, parsing `BuildReport`, build notifications. See `unity-build` (build mechanics), `unity-store-shipping-pipeline` (fastlane + store APIs), `unity-tests` (test authoring), `unity-vcs` (LFS in CI, secrets hygiene), `unity-crash-reporting` (symbol upload step).

## Pick a runner

- **GitHub Actions + GameCI** (`game-ci/unity-builder`, `game-ci/unity-test-runner`) — most popular for indie/mid. Dockerized Unity images per version, free tier 2000 min/month for public repos, paid/self-hosted runners for speed. Default pick.
- **Unity Cloud Build (UCB / Unity DevOps)** — hosted by Unity, simplest setup, integrates with Plastic SCM. Cost scales with build minutes. Good if already paying for Unity DevOps.
- **Self-hosted GitHub runners / Jenkins** — faster (warm Library cache), required for macOS/iOS at scale (~10+ Mac builds/day) — GitHub-hosted Mac is 10x Linux pricing. Operational overhead is real.
- **GitLab CI / Bitbucket Pipelines** — similar Docker patterns; less Unity ecosystem. Use when committed to that platform.

## Unity license activation

Most-painful step for first-time CI.

- **Personal license** — free, machine-bound. Activate via `-username/-password` (legacy) or `-manualLicenseFile` (.ulf). GameCI uses `UNITY_EMAIL`, `UNITY_PASSWORD`, `UNITY_SERIAL` secrets.
- **Plus / Pro / Enterprise** — serial-based; activate at start, return at end (`-returnlicense`). Skip the return = floating-license drift; CI eventually hits `no licenses available` until you manually return seats.
- **Floating license server** (Enterprise only) — runner checks out, returns on completion. Best for >5 builders.

## GitHub Actions + GameCI

Android build job:

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

Split jobs by `targetPlatform: [Android, iOS, WebGL, StandaloneWindows64, StandaloneOSX]`. Mac runners required for iOS and StandaloneOSX. Each platform gets its own job and scoped secrets. Don't build everything in one job — failures in one block all the others.

```yaml
strategy:
  fail-fast: false
  matrix:
    targetPlatform: [Android, iOS, WebGL, StandaloneWindows64]
```

## Test runs in CI

Separate job using `game-ci/unity-test-runner` with `testMode: editmode` and `testMode: playmode`. Headless: `-batchmode -runTests -testPlatform editmode -testResults results.xml -quit`. Parse `results.xml`; fail on any test failure. See `unity-tests`.

```yaml
- uses: game-ci/unity-test-runner@v4
  with:
    testMode: editmode
    artifactsPath: artifacts/editmode
    githubToken: ${{ secrets.GITHUB_TOKEN }}
```

## Signing secrets management

- **iOS** — `.p12` cert + provisioning profile + App Store Connect API key (`.p8`). Base64-encode as GitHub secrets; decode on the runner.
- **Android** — keystore (`.jks`) base64-encoded; key alias + passwords as separate secrets.
- **fastlane match** (recommended for iOS) — private git repo holds encrypted certs/profiles; `match` decrypts on CI using `MATCH_PASSWORD`. Eliminates code-signing drift. See `unity-store-shipping-pipeline`.
- **Never commit secrets**. See `unity-vcs` for `.gitignore`/`.gitattributes` rules.

### Generating and encoding secrets

```bash
# Android keystore -> base64 for GitHub Secrets
base64 -i my.keystore | pbcopy   # macOS
base64 -w 0 my.keystore           # Linux

# Decode in CI workflow:
echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > my.keystore

# iOS .p8 from App Store Connect:
# Users and Access > Keys > "+" > download once (irretrievable after).
# base64 -i AuthKey_XXX.p8 | pbcopy

# fastlane match Personal Access Token:
# GitHub > Settings > Developer settings > Personal access tokens > generate (repo scope)
# Pass to fastlane as MATCH_PASSWORD env var.
```

**Unity Personal license activation** — GameCI: leave `UNITY_SERIAL` blank or omit; GameCI auto-runs `-createManualActivationFile` first run, generates `.alf`, you upload to license.unity3d.com, get a `.ulf`, paste contents into a `UNITY_LICENSE` secret. Pro/Enterprise: set `UNITY_EMAIL`, `UNITY_PASSWORD`, `UNITY_SERIAL` directly.

## fastlane orchestration

After Unity build succeeds, call a fastlane lane to ship:

```yaml
- name: Upload to Play Internal
  run: bundle exec fastlane android beta
  env:
    SUPPLY_JSON_KEY_DATA: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
```

Lanes live in `fastlane/Fastfile`. See `unity-store-shipping-pipeline` for lane content (`pilot`, `supply`, `match`, `deliver`, `gym`).

## Library / asset cache strategy

`Library/` rebuilds take 5–30 min. Cache it.

- **GitHub Actions cache key**: `Library-${platform}-${hash(Assets, Packages, ProjectSettings)}`. `restore-keys` fall through to the most-recent platform cache.
- **Don't cache**: `Logs/`, `MemoryCaptures/`, `Builds/`, `UserSettings/`, `Temp/`.
- **Cache poisoning** — if hash key doesn't include a relevant input (custom `.csproj.template`, code generator), `Library/` drifts from sources. Symptom: "asset failed to import" on cached runs but works fresh. Bust by changing the key prefix.

## Unity Accelerator

Shared cache server for asset import results. 5x+ speedup on art-heavy projects. Self-hosted Docker; configure via `Edit > Preferences > Asset Pipeline > Cache Server`. Worth it for 3+ teams, effectively required for any build farm.

## BuildReport parsing in CI

Write `BuildReport` to JSON in your Editor build script. CI uploads as artifact and posts a size summary to Slack — catch unintended size growth before ship.

```csharp
var report = BuildPipeline.BuildPlayer(opts);
var json = JsonUtility.ToJson(new BuildSummary {
    totalSize = report.summary.totalSize,
    totalErrors = report.summary.totalErrors,
    result = report.summary.result.ToString()
});
File.WriteAllText("build-report.json", json);
```

Full schema: `unity-build`.

## Notifications and dashboards

- **Slack/Discord webhook** on build success/failure with `.aab`/`.ipa` link.
- **PR comment** with test result summary via `dorny/test-reporter`.
- **Daily digest** job posts crash-free %, build size delta, test coverage. See `unity-crash-reporting`.

## Common patterns

- **PR builds** — dev flavor, tests, summary PR comment. Don't upload to TestFlight on PRs.
- **Main-merge builds** — prod flavor, tests, auto-upload to TestFlight + Play Internal.
- **Tag builds** (`v1.2.3`) — prod build, upload to App Store Connect / Play Store production with phased rollout.
- **Nightly** — clean `Library/`, all tests including expensive, baseline crash test on a real device farm.

## Gotchas

- **`-quit` MUST be on command line.** Without it Unity hangs forever and the runner times out.
- **`-batchmode` + exception** throws non-zero exit, but next-line behavior varies by Unity version. Check exit code AND parse log.
- **`Library/` cache should NOT include `Logs`, `MemoryCaptures`, `Builds`, `UserSettings`.**
- **GitHub-hosted Mac runners cost 10x Linux minutes.** Minimize iOS jobs (main + tags only) or self-host Macs.
- **License return on cancelled jobs** — catch SIGTERM in cleanup step and run `-returnlicense` so cancelled runs don't burn a seat.
- **Unity version mismatch local vs CI** = different outputs. Pin via Editor path or GameCI `unityVersion` input.
- **LFS bandwidth on GitHub free tier** (1 GB/month) is tight for art-heavy projects. Pay for an LFS Pack or self-host. See `unity-vcs`.
- **First-PR cache restore** takes 5–10 min download. Acceptable; faster than rebuilding `Library/`.
- **Secrets logged to console = leaked.** GitHub auto-redacts known; custom env vars need explicit `::add-mask::`.
- **Apple ASC API rate limits** (50 req/min) — fastlane retries with backoff; don't tighten concurrency past the limit.
- **Build agents drift** (OS, Xcode). Pin runner image versions; bump deliberately.

## Verification

- First green end-to-end: clean checkout → license activate → build → tests → artifact upload → return license.
- Cache hit on second run: ~25 min → ~5 min.
- Test failure fails the job (intentionally break once to verify).
- Artifact downloadable from run page.
- Secrets masked in logs (grep for one to confirm redaction).
- License returned (Unity ID dashboard seat count).
- PR builds auto; main-merge auto-deploys to TestFlight / Play Internal.

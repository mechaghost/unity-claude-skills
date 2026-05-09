---
name: unity-tests
description: 'Use when authoring or running Unity tests through Unity MCP — Unity Test Framework, UTF, Test Runner, EditMode test, PlayMode test, NUnit, [Test], [UnityTest], [SetUp], [TearDown], [TestFixture], [TestCase], TestRunner, code coverage, run tests, test asmdef, Test Assemblies flag, mock, fake, integration test, scene test, performance test, IPrebuildSetup, IPostBuildCleanup, Coverage package. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Authoring automated tests, configuring a test asmdef, running tests from Test Runner, kicking a test job, wiring code coverage, hooking into CI. UTF is NUnit-based with Unity-specific affordances (`[UnityTest]` coroutines, PlayMode runs). Open via `Window > General > Test Runner`.

## Test framework setup

1. Create `Assets/Tests/EditMode/` or `Assets/Tests/PlayMode/`.
2. Add a Tests asmdef inside (see `unity-asmdef`).
3. Inspector: tick **Test Assemblies**. Auto-scopes the asmdef, hides from non-test builds.
4. Add precompiled references: `nunit.framework.dll`, `UnityEngine.TestRunner`, `UnityEditor.TestRunner` (Editor-only when included). Enable `Override References` in the inspector first — without it, the precompiled-references field is hidden and adding nunit/TestRunner fails silently. Canonical Tests asmdef JSON: `unity-asmdef`.
5. Reference the asmdef under test (`Game.Runtime`).
6. EditMode Tests asmdef — Editor platform only OR all platforms with Test Assemblies set.
7. PlayMode Tests asmdef — Standalone or Any Platform so it compiles into a built Player.

## EditMode vs PlayMode

- **EditMode** — runs in Editor without entering Play. Fast; pure logic — math, parsers, ScriptableObject behavior, serialization, validation.
- **PlayMode** — full runtime. Gameplay, MonoBehaviour callbacks (`Update`, `FixedUpdate`), physics, animation, UI, scene boots. Slower but exercises engine.

Use the cheapest tier that proves behavior. Most logic → EditMode; PlayMode for things that need the loop.

## Writing tests

```csharp
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using System.Collections;

public class CombatMathTests {
    [Test] public void Damage_Applies_Resistance() {
        int dmg = CombatMath.Apply(100, resistance: 0.25f);
        Assert.AreEqual(75, dmg);
    }

    [TestCase(0f, 100)]
    [TestCase(0.5f, 50)]
    [TestCase(1f, 0)]
    public void Damage_Scales(float resist, int expected) {
        Assert.AreEqual(expected, CombatMath.Apply(100, resist));
    }
}
```

Arrange-act-assert. Deterministic — no real time, RNG, or live network. Inject seams (interfaces, virtual clocks).

## Common assertions

- `Assert.AreEqual(expected, actual)` — value equality.
- `Assert.AreSame(expected, actual)` — reference equality.
- `Assert.IsTrue(cond)` / `Assert.IsFalse(cond)`.
- `Assert.IsNull(x)` / `Assert.IsNotNull(x)`.
- `Assert.That(value, Is.EqualTo(x).Within(epsilon))` — float tolerance.
- `CollectionAssert.AreEquivalent(a, b)` — order-insensitive.
- `Assert.Throws<ArgumentException>(() => Code())`.
- `LogAssert.Expect(LogType.Error, "regex or string")` before code that should log; otherwise stray errors fail.

## [UnityTest] coroutines

For time- or frame-based behavior:

```csharp
[UnityTest] public IEnumerator Player_Moves_Forward() {
    var go = new GameObject("Player");
    go.AddComponent<PlayerMovement>();
    yield return null;
    yield return new WaitForSeconds(1f);
    Assert.Greater(go.transform.position.z, 0f);
    Object.Destroy(go);
}
```

`yield return null` advances one frame. `WaitForFixedUpdate` advances physics. Avoid long `WaitForSeconds` — prefer `WaitUntil(() => cond)` with a timeout guard.

## Scene fixtures

```csharp
[UnityTest] public IEnumerator Level_Loads_And_Boots() {
    yield return SceneManager.LoadSceneAsync("TestLevel", LoadSceneMode.Single);
    var boss = Object.FindAnyObjectByType<Boss>();
    Assert.IsNotNull(boss);
}
```

Test scenes must be in Build Settings (`unity-scenes`), or load from a `TestSceneAsset` referenced via `[PrebuildSetup]`/`TestSceneManager` that adds before PlayMode and removes after.

**Object lookup**: Unity 6 deprecated `FindObjectOfType<T>()` and `FindObjectsOfType<T>()` with obsolescence warnings. Use `Object.FindAnyObjectByType<T>()` or `Object.FindFirstObjectByType<T>()` (singular) and `Object.FindObjectsByType<T>(FindObjectsSortMode.None)` (plural).

## MonoBehaviour testing

- Instantiate with `new GameObject().AddComponent<T>()` rather than spawning prefabs in EditMode tests; prefab refs in PlayMode are fine.
- Drive the loop with `yield return null` between frames.
- Snapshot via public fields, properties, or `[InternalsVisibleTo("Game.Tests")]` — not reflection.
- Always `Object.Destroy(go)` (or `DestroyImmediate` in EditMode) in `[TearDown]`.

## Mocks vs fakes

NSubstitute and Moq exist via NuGet but are uncommon in Unity (IL2CPP-friendliness varies). Prefer hand-rolled fakes:

```csharp
class FakeAudioService : IAudioService {
    public string lastPlayed;
    public void Play(string id) { lastPlayed = id; }
}
```

Inject via constructor, field, or `[Inject]`. Avoid singletons and statics in code under test — they leak across tests and force ordering. If unavoidable, expose a reset hook and call in `[SetUp]`.

## Code coverage

Install `com.unity.testtools.codecoverage`. `Window > Analysis > Code Coverage`:

- Enable Code Coverage in Settings.
- Generate HTML Report after run.
- Test asmdefs excluded by default. Use Included/Excluded Paths to scope (`+Game.Runtime,+Game.Combat`) and exclude generated code.

Report at `<project>/CodeCoverage/Report/index.html`. Track line and branch coverage; high on branching systems, lower on glue.

## CI integration

Headless:

```
unity -batchmode -nographics -runTests \
  -testPlatform editmode \
  -testResults artifacts/edit-results.xml \
  -projectPath . -logFile -
```

Repeat with `-testPlatform playmode`. Exit code is nonzero on red. Parse `*-results.xml` (NUnit3) in CI. The `game-ci/unity-test-runner` GitHub Action wraps this.

Through the test-runner capability: kick a job, poll for completion. For quick local smoke; use Test Runner window for iterative authoring.

## Common patterns

- Arrange-act-assert, one logical assertion per test.
- Data-driven via `[TestCase]` and `[TestCaseSource(nameof(Cases))]`.
- `[SetUp]`/`[TearDown]` per test.
- `[OneTimeSetUp]`/`[OneTimeTearDown]` per fixture for expensive resources.
- `[Category("Slow")]` to filter long tests.
- `[Ignore("reason")]` over commented-out tests.
- `[Order(n)]` last resort — order-dependent tests are a smell.

## Gotchas

- PlayMode tests share the Editor's loaded scenes — destroy GameObjects in `[TearDown]` or scenes in `[OneTimeTearDown]`, else leaks cascade.
- Static state (singletons, caches, static fields) leaks between tests. Reset in `[SetUp]`.
- `Time.timeScale` persists across tests — restore to 1f in `[TearDown]`.
- PlayMode tests can't run during a build; need Game view focusable.
- Tests in default `Assembly-CSharp` are second-class — always asmdef them.
- `LogAssert.NoUnexpectedReceived()` at end of test catches stray errors that would otherwise fail the next.
- Async/Task tests need `[UnityTest]` + `IEnumerator` adapters or `Task`-returning tests with the right UTF version — async void silently swallows failures.
- Coroutines that allocate (`new WaitForSeconds`) accumulate GC across many tests; cache or use plain frame yields.

## Verification

- Test Runner shows green (EditMode and PlayMode).
- Console clean — no stray errors during runs.
- Code Coverage HTML shows touched lines.
- CI fails on red test (verify by intentionally breaking once).
- Runner-capability runs: `passed`, `failures: 0`.

## Cross-links

- `unity-asmdef` — Test Assemblies flag and references.
- `unity-scenes` — PlayMode scene fixtures, Build Settings.
- `unity-build` — headless CI builds, Development Build profiling.

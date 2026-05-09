---
name: unity-tests
description: 'Use when authoring or running Unity tests through Unity MCP — Unity Test Framework, UTF, Test Runner, EditMode test, PlayMode test, NUnit, [Test], [UnityTest], [SetUp], [TearDown], [TestFixture], [TestCase], TestRunner, code coverage, run tests, test asmdef, Test Assemblies flag, mock, fake, integration test, scene test, performance test, IPrebuildSetup, IPostBuildCleanup, Coverage package. Unity 6+ / 6000.x, URP-only, new Input System only.'
---

## When to use

Reach for this skill any time you are writing automated tests in Unity, configuring a test asmdef, running tests from the Test Runner window, kicking a test job through MCP (`run_tests` / `get_test_job`), wiring code coverage, or hooking tests into CI. UTF is the official test framework; it is NUnit-based but adds Unity-specific affordances such as `[UnityTest]` coroutines and PlayMode runs. Open the runner via `Window > General > Test Runner`.

## Test framework setup

1. Create a folder like `Assets/Tests/EditMode/` or `Assets/Tests/PlayMode/`.
2. Add a Tests asmdef inside it (`manage_asset` create asmdef, see unity-asmdef).
3. In the asmdef inspector, check Test Assemblies. This automatically scopes the asmdef and hides it from non-test builds.
4. Add precompiled references: `nunit.framework.dll`, `UnityEngine.TestRunner`, `UnityEditor.TestRunner` (the Editor one only when the asmdef includes the Editor platform). **Note**: the `Override References` checkbox in the asmdef inspector must be enabled before the precompiled-references list field appears. Without that toggle, the field is hidden and adding nunit/TestRunner fails silently. For the canonical Tests asmdef JSON template see `unity-asmdef`.
5. Reference the asmdef under test (e.g. `Game.Runtime`).
6. EditMode Tests asmdef: include only Editor platform OR all platforms with the Test Assemblies flag set.
7. PlayMode Tests asmdef: include Standalone or Any Platform so it compiles into a built Player when needed.

## EditMode vs PlayMode

- EditMode tests run in the Editor without entering Play mode. They are fast and ideal for pure logic: math, parsers, ScriptableObject behavior, serialization, validation.
- PlayMode tests run with the full Unity runtime. Use them for gameplay, MonoBehaviour callbacks (`Update`, `FixedUpdate`), physics, animation, UI, and scene boots. They are slower but exercise the engine.
- Pick the cheapest tier that proves the behavior. Most logic should be EditMode; PlayMode is reserved for things that genuinely need the loop.

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

Layout each test arrange-act-assert. Keep tests deterministic — no real time, no real RNG, no live network. Inject seams (interfaces, virtual clocks) so tests can pin behavior.

## Common assertions

- `Assert.AreEqual(expected, actual)` — value equality.
- `Assert.AreSame(expected, actual)` — reference equality.
- `Assert.IsTrue(cond)` / `Assert.IsFalse(cond)`.
- `Assert.IsNull(x)` / `Assert.IsNotNull(x)`.
- `Assert.That(value, Is.EqualTo(x).Within(epsilon))` — float tolerance.
- `CollectionAssert.AreEquivalent(a, b)` — order-insensitive collection compare.
- `Assert.Throws<ArgumentException>(() => Code())` — exception assertions.
- `LogAssert.Expect(LogType.Error, "regex or string")` before code that should log; otherwise stray errors fail the test.

## [UnityTest] coroutines

Use for time- or frame-based behavior:

```csharp
[UnityTest] public IEnumerator Player_Moves_Forward() {
    var go = new GameObject("Player");
    go.AddComponent<PlayerMovement>();
    yield return null;                  // wait one frame
    yield return new WaitForSeconds(1f);
    Assert.Greater(go.transform.position.z, 0f);
    Object.Destroy(go);
}
```

`yield return null` advances one frame. `yield return new WaitForFixedUpdate()` advances physics. Avoid `WaitForSeconds` for long durations — prefer `WaitUntil(() => cond)` with a timeout guard.

## Scene fixtures

```csharp
[UnityTest] public IEnumerator Level_Loads_And_Boots() {
    yield return SceneManager.LoadSceneAsync("TestLevel", LoadSceneMode.Single);
    var boss = Object.FindAnyObjectByType<Boss>();
    Assert.IsNotNull(boss);
}
```

Test scenes must be in Build Settings (cross-link unity-scenes), or load from a `TestSceneAsset` referenced via a `[PrebuildSetup]` / `TestSceneManager` helper that adds the scene to the build list before PlayMode runs and removes it after.

**Object lookup APIs**: Unity 6 deprecated `FindObjectOfType<T>()` and `FindObjectsOfType<T>()` with editor obsolescence warnings on every call. Use `Object.FindAnyObjectByType<T>()` or `Object.FindFirstObjectByType<T>()` for the singular case, and `Object.FindObjectsByType<T>(FindObjectsSortMode.None)` for the plural case. The legacy names still compile but emit obsolescence warnings.

## MonoBehaviour testing

- Instantiate with `new GameObject().AddComponent<T>()` rather than spawning prefabs in EditMode tests; prefab references in PlayMode are fine.
- Drive the loop with `yield return null` between frames.
- Snapshot expected state via public fields, properties, or expose internals through `[InternalsVisibleTo("Game.Tests")]` rather than reflection.
- Always `Object.Destroy(go)` or `Object.DestroyImmediate(go)` (EditMode) in `[TearDown]`.

## Mocks vs fakes

NSubstitute and Moq exist via NuGet but are uncommon in Unity (and IL2CPP-friendliness varies). Idiomatic Unity testing prefers hand-rolled fakes:

```csharp
class FakeAudioService : IAudioService {
    public string lastPlayed;
    public void Play(string id) { lastPlayed = id; }
}
```

Inject via constructor, field, or `[Inject]` (if using a DI container). Avoid singletons and statics in code under test — they leak across tests and force ordering. If a singleton is unavoidable, expose a reset hook and call it in `[SetUp]`.

## Code coverage

Install `com.unity.testtools.codecoverage` (`manage_packages`). Open `Window > Analysis > Code Coverage`. Settings:

- Enable Code Coverage in Settings.
- Generate HTML Report after run.
- Test asmdefs are excluded by default. Use Included/Excluded Paths to scope to your runtime asmdefs (`+Game.Runtime,+Game.Combat`) and exclude generated code.

The report drops into `<project>/CodeCoverage/Report/index.html`. Track line coverage and branch coverage; aim for high coverage on systems with branching logic, lower on glue code.

## CI integration

Headless run:

```
unity -batchmode -nographics -runTests \
  -testPlatform editmode \
  -testResults artifacts/edit-results.xml \
  -projectPath . -logFile -
```

Repeat with `-testPlatform playmode`. Exit code is nonzero on red. Parse `*-results.xml` (NUnit3 schema) in CI. The `game-ci/unity-test-runner` GitHub Action wraps this and uploads results + coverage.

Through MCP: `run_tests` to kick a job, `get_test_job` to poll for completion. Use this for quick local smoke runs; use the Test Runner window for iterative authoring.

## Common patterns

- Arrange-act-assert layout, one logical assertion per test.
- Data-driven via `[TestCase]` and `[TestCaseSource(nameof(Cases))]`.
- `[SetUp]` / `[TearDown]` per test for shared init/cleanup.
- `[OneTimeSetUp]` / `[OneTimeTearDown]` per fixture for expensive resources.
- `[Category("Slow")]` to filter long tests out of the inner loop.
- `[Ignore("reason")]` rather than commented-out tests.
- `[Order(n)]` only as a last resort — order-dependent tests are a smell.

## Gotchas

- PlayMode tests share the running Editor's loaded scenes — destroy GameObjects in `[TearDown]` or scenes in `[OneTimeTearDown]`, otherwise leaks cascade.
- Static state (singletons, static caches, `MonoBehaviour` static fields) leaks between tests. Reset in `[SetUp]`.
- `Time.timeScale` modifications persist across tests — restore to 1f in `[TearDown]`.
- PlayMode tests cannot run during a build, and they need the Game view focusable.
- Tests in the default `Assembly-CSharp` are second-class — always asmdef them so they cleanly toggle and don't pollute Player builds.
- `LogAssert.NoUnexpectedReceived()` at end of test catches stray errors that would otherwise make the next test fail.
- Async/Task-based tests need `[UnityTest]` + `IEnumerator` adapters or `Task` returning tests with the right UTF version — async void will silently swallow failures.
- Coroutines that allocate (`new WaitForSeconds`) accumulate GC pressure across many tests; cache or use plain frame yields where possible.

## Verification

- Test Runner window shows green for the suite (EditMode and PlayMode).
- `read_console` clean — no stray errors or warnings during runs.
- Code Coverage HTML report shows touched lines for the system under test.
- CI build fails on a red test (verify by intentionally breaking one once).
- For MCP-driven runs: `get_test_job` returns `passed` and `failures: 0`.

## Cross-links

- unity-asmdef — required to set up Test Assemblies flag and references.
- unity-scenes — for PlayMode scene fixtures and Build Settings additions.
- unity-build — for headless CI builds and Development Build profiling.
- unity-best-practices — read-console / batch_execute discipline applies to test runs too.

# unity-claude-skills

A 43-skill Claude Code skill set for working in Unity through Unity MCP. Covers rendering, gameplay, input, UI, audio, physics, animation, persistence, build, store shipping, live-ops, CI, and DOTS.

Stack assumptions: **Unity 6+ / 6000.x, URP-only, new Input System only.** HDRP and the Built-in pipeline are out of scope; legacy `Input` is supported only in migration guidance.

## Install

Drop these skills into a Unity project's `.claude/` directory (project-local), or merge them into `~/.claude/` (user-global).

```bash
# Project-local (recommended): the skills live alongside the Unity project
cd /path/to/your-unity-project
git clone https://github.com/mechaghost/unity-claude-skills.git tmp-skills
mkdir -p .claude/skills
cp -r tmp-skills/.claude/skills/* .claude/skills/
rm -rf tmp-skills

# Or as a sparse subtree if you want to track upstream updates
git remote add unity-skills https://github.com/mechaghost/unity-claude-skills.git
git subtree add --prefix=.claude/skills/ unity-skills main --squash
```

You also need a Unity MCP server connected to your Claude Code session. The skills target Unity's **official Unity MCP**, shipped as part of the [`com.unity.ai.assistant`](https://docs.unity3d.com/Packages/com.unity.ai.assistant@latest/manual/integration/unity-mcp-landing.html) package. After installing the package via Unity Package Manager, point Claude Code at the relay binary the package drops at `~/.unity/relay/` (the docs walk through `claude mcp add unity-mcp ...` with the platform-specific binary), then accept the **Pending Connection** prompt in Unity's Project Settings the first time the client connects.

> **Tool-name compatibility.** The official Unity MCP advertises tools with a `Unity_PascalCase` naming convention (e.g. `Unity_ManageScene`, `Unity_ManageGameObject`, `Unity_ReadConsole`). Throughout the per-skill content you'll see references to lower-case shorthand like `manage_gameobject`, `read_console`, `apply_text_edits`, `batch_execute`, `unity_reflect`. Treat those as **role names**, not literal tool IDs — match them against whatever the connected Unity MCP server returns from `tools/list` at runtime. If your server doesn't expose a one-to-one equivalent for a given role (for example `batch_execute` is server-specific), fall back to issuing the underlying actions as separate calls.

## Source of truth

This repository is a Claude Code skill pack. The canonical, hand-edited skill tree is:

```text
.claude/skills/
```

Do not edit `.agents/skills/` as a second source of truth. If an `.agents/` tree exists locally, treat it as an optional generated export for agent runtimes that expect that layout. It is ignored by git to prevent drift between two copies of the same skills.

## How the skills work

Skills load on description match. `unity-best-practices` is written to fire on essentially any Unity-related prompt and acts as the always-loaded primer (paradigm detection, console reading, MCP tool inventory, failure protocol, router to all 43 skills).

Domain skills load when their trigger keywords appear in the user's prompt. The full router lives in [`.claude/skills/unity-best-practices/references/router.md`](.claude/skills/unity-best-practices/references/router.md).

## The 43 skills

### Foundations
| Skill | Use for |
| --- | --- |
| `unity-best-practices` | Always-on primer — paradigm detection, console-first discipline, MCP tool inventory, failure protocol, skill routing. |
| `unity-3d-verification` | 4-shot orthographic capture (left, right, top, bottom) before declaring a 3D change done. Includes batching budget for large scenes. |
| `unity-patterns` | Object pooling, singletons, ScriptableObject event bus, FSM, pause / unscaled time, tweens, screenshot helpers, debug console. |

### Rendering and visuals (URP-only)
| Skill | Use for |
| --- | --- |
| `unity-urp` | Pipeline asset, renderer features, post-processing volumes, camera stacks, 2D Renderer, light layers. |
| `unity-shaders` | Materials, Shader Graph, HLSL, MaterialPropertyBlock, SRP Batcher, variant stripping, iOS Metal warmup. |
| `unity-lighting` | Light components, Mixed lighting modes, lightmappers, Light Probes, Reflection Probes, APV, fog, skybox. |
| `unity-shuriken` | CPU particles (ParticleSystem). Use when count <5000. |
| `unity-vfx-graph` | GPU particles (Visual Effect Graph). Use when count >5000 or you need SDF/mesh sampling. |
| `unity-animation` | Animator, state machines, blend trees, IK, Animation Rigging, Timeline. |
| `unity-cinemachine` | Cinemachine 3.x cameras, blends, dolly, ClearShot, Confiner, Impulse. |

### Gameplay
| Skill | Use for |
| --- | --- |
| `unity-3d-rotation` | Quaternion / Euler / look-at math on 3D Transforms. |
| `unity-2d-rotation` | Z-axis rotation for sprites and Rigidbody2D. |
| `unity-ugui-rotation` | RectTransform pivot rotation under a Canvas. |
| `unity-physics` | Rigidbody, colliders, joints, queries, layer matrix, physics materials. Covers 3D and 2D. |
| `unity-navmesh` | NavMeshAgent, NavMeshSurface, NavMeshLink, off-mesh links, runtime baking. |

### Input and UI
| Skill | Use for |
| --- | --- |
| `unity-input-system` | New Input System: Action assets, control schemes, composites, PlayerInput, rebinding, migration from legacy `Input`. |
| `unity-ugui` | Canvas, RectTransform, Selectables, layout, EventSystem, TMP, masks, sorting. |
| `unity-audio` | AudioSource, AudioMixer, snapshots, ducking, mobile / WebGL audio context. |

### Project hygiene and shipping
| Skill | Use for |
| --- | --- |
| `unity-scenes` | SceneManager, additive loading, boot scene, scene transitions, cross-scene references. |
| `unity-persistence` | PlayerPrefs, JsonUtility, atomic save, save slots, save versioning. |
| `unity-cloud-save-conflict` | Cross-device sync, schema migration, conflict resolution (Steam Cloud, iCloud, Play Saved Games, UGS, Firebase). |
| `unity-build` | BuildPipeline, IL2CPP vs Mono, code stripping, link.xml, Build Profiles. References for mobile and WebGL. |
| `unity-store-shipping-pipeline` | TestFlight, Play Console, fastlane, App Store Connect API, phased rollout. Includes live-ops boot-order checklist. |
| `unity-addressables` | AssetReference, async load, content catalogs, remote groups, content updates. |
| `unity-asmdef` | Assembly Definitions, version defines, Editor / Runtime / Test split. |
| `unity-vcs` | Git, LFS, .gitignore, force-text serialization, UnityYAMLMerge / SmartMerge. |
| `unity-tests` | Unity Test Framework, EditMode / PlayMode, NUnit, code coverage, headless CI runs. |
| `unity-profiling` | Profiler, Frame Debugger, Memory Profiler, ProfilerMarker, GC budgets. |
| `unity-ci` | GitHub Actions / GameCI / Unity Cloud Build, license activation, signing secrets, fastlane orchestration. |

### Live-ops and compliance
| Skill | Use for |
| --- | --- |
| `unity-iap` | In-app purchases, App Store Server API, Google Play Developer API, idempotency, refund webhooks. |
| `unity-ads-mediation` | AppLovin MAX, LevelPlay, AdMob, frequency caps, consent integration. |
| `unity-consent-att-gdpr` | iOS ATT, GDPR / CCPA via UMP, COPPA age-gating, data deletion. |
| `unity-privacy-manifests` | Apple PrivacyInfo.xcprivacy (Required Reason APIs), Google Play Data Safety. |
| `unity-crash-reporting` | Crashlytics / Sentry, IL2CPP symbol upload, ANR detection, release-only crash runbook. |
| `unity-analytics-events` | Firebase Analytics, Adjust / AppsFlyer, SKAN, event taxonomy, funnels. |
| `unity-remote-config-flags` | Firebase Remote Config / Unity Game Overrides, killswitches, hotfix flags. |
| `unity-ab-testing` | Variant assignment, sticky bucketing (SHA-256, not GetHashCode), exposure events, holdouts. |
| `unity-auth-account-linking` | Anonymous auth, Apple Sign-In with nonce verification, Google Sign-In, JWT validation, refresh-token storage. |
| `unity-push-local-notifications` | FCM HTTP v1 with OAuth2, APNs, OneSignal, deep links, channels. |
| `unity-localization` | Unity Localization package, string tables, Smart Format, RTL, CJK font fallback. |
| `unity-anti-cheat-iap-fraud` | Server-authoritative state, receipt forgery defense, Play Integrity / App Attest, cert pinning. |
| `unity-support-and-bug-capture` | In-game bug reports, log + device + screenshot bundle, GDPR account deletion. |

### Performance
| Skill | Use for |
| --- | --- |
| `unity-dots-jobs-burst` | Entities (ECS), Jobs, Burst, Native containers, EntityCommandBuffer, SubScenes, hybrid mode. Use when entity count is in the thousands. |

## Repo structure

```
.claude/skills/
  <skill-name>/
    SKILL.md            # frontmatter (name, description with triggers + disambiguators) + body
    references/         # optional: deep catalogs / cookbooks / reference tables
      <topic>.md
```

Each skill is self-contained. Cross-links between skills are by name (`unity-physics`, `unity-iap`, etc.). Reference files hold deep cookbook content that the parent SKILL.md links into when relevant.

`.agents/` is not part of the source layout. Generate or copy it only as an export artifact when a downstream runtime needs it.

## Editorial conventions

- No emojis.
- Direct, imperative prose. No marketing fluff. No "this skill helps you..."
- Frontmatter `description` is one trigger paragraph plus explicit "Do NOT use for X" disambiguators where overlap exists.
- Code in C# fenced blocks. YAML, shell, XML, JSON, HLSL where appropriate.
- Stack: Unity 6+ / 6000.x, URP, new Input System. Anything older (2022 LTS, Built-in pipeline, legacy Input) appears only as migration guidance.

## What's not covered

By design:
- HDRP, Built-in render pipeline (out of scope).
- Legacy `Input` class (migration only).
- Console platforms (Switch, PS5, Xbox — NDA-gated).
- Specific gameplay genres (FPS controller, inventory, dialogue, quest systems — too project-specific).
- Terrain (niche for the mobile-F2P / indie focus).
- Multiplayer / Netcode (a candidate addition; not covered yet).
- AR / VR / XR (a candidate addition; not covered yet).
- Editor extensions / `[CustomEditor]` / asset post-processors (a candidate addition; not covered yet).

## Contributing

1. Pick or create a skill folder under `.claude/skills/`.
2. Frontmatter must include `name` (kebab-case, `unity-` prefix) and `description` (one sentence: "Use when ...", followed by trigger keywords inline, plus "Do NOT use for X" disambiguators if overlap with sibling skills).
3. No emojis. URP-only / new Input System only / Unity 6.
4. Cross-link siblings by skill name.
5. Code snippets must compile against Unity 6 with no obsolescence warnings.
6. End with a `## Verification` section that names what success looks like in MCP terms (`read_console`, manage_* checks, profiler markers, screenshot capture).

## License

MIT.

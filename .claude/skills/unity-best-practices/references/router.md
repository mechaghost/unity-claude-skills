# Domain skill router (full reference)

The deeper-dive routing table for all 43 skills in this set, grouped by category. The always-on `unity-best-practices` SKILL.md keeps a 6-row "Common cases" cheat-sheet that covers ~80% of routing without bloating every Unity prompt; reach for this file when the cheat-sheet's collapsed groupings aren't specific enough.

Hand off to the matching skill. `unity-best-practices` stays loaded alongside.

| Task | Skill |
| --- | --- |
| **Foundations** | |
| Always-on primer (this skill) | `unity-best-practices` |
| 4-shot 3D verification | `unity-3d-verification` |
| Day-one indie patterns (pooling, singleton, SO events, FSM, pause, tweens) | `unity-patterns` |
| **Rendering & visuals (URP-only)** | |
| URP pipeline asset / renderer features / volumes | `unity-urp` |
| Materials / shaders / Shader Graph | `unity-shaders` |
| Lighting bake / probes / APV | `unity-lighting` |
| Shuriken particles (CPU, <5000) | `unity-shuriken` |
| VFX Graph (GPU, >5000) | `unity-vfx-graph` |
| Animator / Timeline / IK / Animation Rigging | `unity-animation` |
| Cinemachine 3.x cameras | `unity-cinemachine` |
| **Gameplay** | |
| 3D rotation (Transform / Quaternion) | `unity-3d-rotation` |
| 2D rotation (SpriteRenderer / Rigidbody2D) | `unity-2d-rotation` |
| UI rotation (RectTransform) | `unity-ugui-rotation` |
| Physics (Rigidbody, colliders, joints, queries; 3D + 2D) | `unity-physics` |
| AI navigation / pathfinding | `unity-navmesh` |
| **Input & UI** | |
| New Input System | `unity-input-system` |
| UGUI / Canvas / TMP / layout | `unity-ugui` |
| **Audio** | |
| AudioSource / Mixer / snapshots | `unity-audio` |
| **Project hygiene & shipping** | |
| Scenes (SceneManager, additive, boot scene) | `unity-scenes` |
| Save data / persistence | `unity-persistence` |
| Cloud save sync + conflict resolution | `unity-cloud-save-conflict` |
| Build pipeline (IL2CPP, profiles, link.xml) | `unity-build` |
| Store shipping (TestFlight, Play Console, fastlane) | `unity-store-shipping-pipeline` |
| Addressables (lazy load, remote groups, content updates) | `unity-addressables` |
| Assembly Definitions | `unity-asmdef` |
| Version control (git, LFS, SmartMerge) | `unity-vcs` |
| Tests (UTF, EditMode/PlayMode, coverage) | `unity-tests` |
| Profiling (Profiler, Frame Debugger, GC budget) | `unity-profiling` |
| **Live-ops** | |
| In-app purchases | `unity-iap` |
| Ad mediation | `unity-ads-mediation` |
| Consent (ATT, GDPR/CCPA, COPPA) | `unity-consent-att-gdpr` |
| Privacy manifests (Apple PrivacyInfo, Play Data Safety) | `unity-privacy-manifests` |
| Crash reporting (Crashlytics/Sentry, IL2CPP symbols) | `unity-crash-reporting` |
| Analytics events (Firebase, Adjust/AppsFlyer, SKAN) | `unity-analytics-events` |
| Remote config / feature flags | `unity-remote-config-flags` |
| A/B testing | `unity-ab-testing` |
| Auth + account linking (anonymous, Apple/Google) | `unity-auth-account-linking` |
| Push + local notifications | `unity-push-local-notifications` |
| Localization | `unity-localization` |
| Anti-cheat / IAP fraud / tampering | `unity-anti-cheat-iap-fraud` |
| In-game bug reports + GDPR deletion | `unity-support-and-bug-capture` |
| **DevOps / CI** | |
| CI / build automation | `unity-ci` |

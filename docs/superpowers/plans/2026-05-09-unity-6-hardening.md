# Unity 6 Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the canonical `.claude/skills` tree valid to load and clearly targeted at Unity 6+ / 6000.x.

**Architecture:** Validate only `.claude/skills`, keep `.agents/` ignored as an export artifact, and enforce Unity 6+ terminology with a repo-local validator. Modernize high-risk guidance where old Unity APIs would mislead agents.

**Tech Stack:** Claude Code skills, Markdown, Ruby validation script.

---

### Task 1: Add Canonical Skill Validation

**Files:**
- Create: `scripts/validate_skills.rb`

- [x] **Step 1: Validate canonical skill count**

Check that `.claude/skills` contains 43 `SKILL.md` files.

- [x] **Step 2: Validate strict YAML frontmatter**

Parse every skill frontmatter with Ruby `YAML.safe_load`.

- [x] **Step 3: Block stale Unity/API terms**

Fail on the old Unity baseline wording, old Unity IAP v4 primary APIs, stale router counts, and stale CI status text.

### Task 2: Fix Loader And Baseline Issues

**Files:**
- Modify: `.claude/skills/*/SKILL.md`
- Modify: `README.md`

- [x] **Step 1: Quote frontmatter descriptions**

Convert description lines to valid YAML single-quoted strings.

- [x] **Step 2: Replace stale Unity baseline**

Replace the old mixed Unity 6 / yearly-LTS wording with `Unity 6+ / 6000.x`.

### Task 3: Update Unity 6+ Operating Policy

**Files:**
- Modify: `.claude/skills/unity-best-practices/SKILL.md`
- Modify: `.claude/skills/unity-input-system/SKILL.md`
- Modify: `.claude/skills/unity-build/SKILL.md`
- Modify: `.claude/skills/unity-build/references/mobile.md`
- Modify: `.claude/skills/unity-best-practices/references/router.md`

- [x] **Step 1: Make new Input System the final state**

Treat `Both` as migration-only and `Input System Package (New)` as the Unity 6+ final state.

- [x] **Step 2: Fix router count and CI status**

Update router wording from 42 to 43 skills and remove stale `unity-ci` forward-reference status.

- [x] **Step 3: Update Android size guidance**

Replace stale Play-size guidance with current app bundle, feature module, asset pack, total download, and legacy APK limits.

### Task 4: Rewrite IAP For Unity IAP v5

**Files:**
- Modify: `.claude/skills/unity-iap/SKILL.md`
- Modify: `.claude/skills/unity-iap/references/server-validation.md`
- Modify: `.claude/skills/unity-store-shipping-pipeline/SKILL.md`

- [x] **Step 1: Make IAP v5 primary**

Rewrite the skill around `StoreController`, `FetchProducts`, `FetchPurchases`, `PendingOrder`, and `ConfirmPurchase`.

- [x] **Step 2: Update server-validation flow**

Replace old pending-purchase language with IAP v5 pending-order confirmation flow.

- [x] **Step 3: Update live-ops boot order**

Change boot-order text to IAP v5 connect/fetch/entitlement flow.

### Task 5: Verify

**Files:**
- Inspect: `.claude/skills`, `README.md`, `scripts/validate_skills.rb`

- [x] **Step 1: Run validator**

Run `ruby scripts/validate_skills.rb`.

- [x] **Step 2: Scan for stale terms**

Run `rg` for the old Unity baseline wording, old IAP v4 primary APIs, stale router count, and stale Android size terms.

- [x] **Step 3: Confirm Unity 6+ feature coverage**

Scan for Build Profiles, RenderGraph, Awaitable, `destroyCancellationToken`, `linearVelocity`, `PhysicsMaterial`, Cinemachine 3.x, APV, and IAP v5 terms.

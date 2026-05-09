# Claude Skills Canonicalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `.claude/skills` the authoritative source of truth for this repository and keep `.agents/skills` out of normal tracked workflow.

**Architecture:** The repository remains a Claude Code skill pack. `.claude/skills` is the only hand-edited skill tree. `.agents/` is treated as an optional generated/export directory and is ignored by git unless a future task explicitly adds a sync/export workflow.

**Tech Stack:** Markdown documentation, git ignore rules, Claude Code skill layout.

---

### Task 1: Document The Canonical Tree

**Files:**
- Modify: `README.md`

- [x] **Step 1: Add source-of-truth policy**

Add a repository policy section stating that `.claude/skills` is authoritative and `.agents/skills` is not hand-edited.

- [x] **Step 2: Keep install instructions pointed at `.claude/skills`**

Confirm project-local install commands, subtree command, router link, repo structure, and contributing guidance all continue to use `.claude/skills`.

### Task 2: Ignore Generated Agent Exports

**Files:**
- Create: `.gitignore`

- [x] **Step 1: Ignore `.agents/`**

Add `.agents/` to `.gitignore` so local generated exports do not appear as ordinary repo changes.

### Task 3: Verify Scope

**Files:**
- Inspect: repository status and docs

- [x] **Step 1: Check git status**

Run `git status --short` and confirm only the intentional documentation and ignore-rule changes remain.

- [x] **Step 2: Confirm tracked skill tree remains untouched**

Run `git diff -- .claude/skills` and confirm there are no skill content changes in this canonicalization pass.

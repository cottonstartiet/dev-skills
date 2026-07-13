# Workflow Coverage Roadmap

- **Status:** Proposed
- **Date:** 2026-07-12
- **Scope:** The whole `dev-skills` repository (plugins + tools)

## 1. Purpose

`dev-skills` exists to make the developer inner loop seamless. This spec assesses how much of the
end-to-end developer workflow the repo covers today, identifies the gaps, and proposes a prioritized
roadmap of new plugins/tools to close them. It is the reference for deciding **what to build next**.

## 2. What the repo is today

A **GitHub Copilot CLI plugin marketplace** with two complementary delivery models:

- **Plugins (Copilot CLI skills)** — reusable prompts/workflows loaded on demand inside Copilot CLI.
  Indexed by [`.github/plugin/marketplace.json`](../.github/plugin/marketplace.json).
- **Tools (standalone PowerShell)** — plain scripts installed into the shell as short commands via
  the auto-discovering [`tools/install.ps1`](../tools/install.ps1); each has a `tool.json` manifest.

### Current inventory

| Component | Type | Command / Invoke | What it does |
|-----------|------|------------------|--------------|
| `codev` | Plugin (skill) | `/codev` | Guided four-stage workflow: **Understand → Plan → Implement → Review** with gates. |
| `deep-analysis` | Plugin (skill) | "analyze …", "architecture review" | Deep codebase analysis → self-contained light-theme **HTML report**. |
| `worktree` | Tool | `tr` | Create/inspect/branch/push/remove git worktrees on `users/<alias>/<name>` with guardrails. |
| `sync` | Tool | `sync` | Safely update the current branch (fast-forward default; `-Rebase`/`-Merge` opt-in; never force). |
| `prprep` | Tool | `prprep` | Draft a PR description + checklist from the diff. Does **not** create the PR or push. |
| `changelog` | Tool | `changelog` | Keep a Changelog-style output from Conventional Commits; dry-run unless `-Write`. |

## 3. Lifecycle coverage map

| Stage | Covered? | By |
|-------|----------|----|
| Branch / worktree setup | ✅ | `worktree` |
| Understand → Plan → Implement → Review | ✅ | `codev` |
| Codebase analysis | ✅ | `deep-analysis` |
| Keep branch current | ✅ | `sync` |
| PR description draft | ✅ | `prprep` |
| Changelog | ✅ | `changelog` |
| Onboarding / environment bootstrap | ❌ | — |
| Commit crafting (Conventional Commits) | ❌ | — |
| Test authoring / running / gap-finding | ❌ | — |
| CI / PR status monitoring & triage | ❌ | — |
| Debug / incident / log triage | ❌ | — |
| Release / version bump | ❌ | — |
| Dependency & security hygiene | ❌ | — |

**Assessment:** the *middle* of the inner loop is strong. The **edges — onboard → commit → verify →
ship → operate — are the gaps.**

## 4. Proposed additions

Each proposal is matched to the delivery model that fits it best (tool for deterministic,
scriptable actions; skill for reasoning over code/context).

### P1 — `commit` tool (`cm`) — highest leverage, smallest effort
- **Model:** Tool (mirrors `changelog`/`prprep`, which already parse diffs/commits).
- **What:** Review staged changes, generate a **Conventional Commit** message from the diff, and
  validate it against the repo's commit conventions. Dry-run/preview by default; never auto-push.
- **Why:** Fits exactly between `codev`'s Implement stage and `prprep`, removing the most frequent
  manual step in the loop.

### P2 — `testgen` skill — closes the biggest quality gap
- **Model:** Plugin (skill) — needs to reason about code and conventions.
- **What:** Detect the test framework, find untested changed code (via `git diff`), scaffold tests
  following repo conventions, and run the **smallest targeted** suite.
- **Why:** Natural companion invoked inside `codev`'s Implement stage; raises confidence before PR.

### P3 — `shipwatch` tool (`ship`) — closes the loop after `prprep`
- **Model:** Tool (wraps `gh`).
- **What:** Open the PR, then poll and summarize CI checks and review status until merge-ready.
  Keeps the existing **no auto-merge, human-confirmed** guardrails.
- **Why:** Turns `prprep` (drafts only) into an end-to-end path to a merge-ready PR.

### P4 — `onboard` skill — start of the loop
- **Model:** Plugin (skill).
- **What:** Bootstrap a fresh clone — detect stack, install deps, run the first build/test, and
  surface repo conventions (`.github/instructions/*`, `AGENTS.md`, `CONTRIBUTING.md`).
- **Why:** Makes day-one in any repo seamless.

### P5 — `release` tool (`rel`) — end of the loop
- **Model:** Tool (reuses `changelog`'s commit parsing).
- **What:** Compute the next semver from Conventional Commits, bump manifests, and tag. Dry-run by
  default, like `changelog`.
- **Why:** Completes the ship stage with versioning.

### P6 — `triage` skill — operational tail
- **Model:** Plugin (skill).
- **What:** Given a stack trace / failing test / log snippet, locate the culprit code and propose a
  fix.
- **Why:** Covers the debug/incident stage (relevant given this org's ops-oriented plugins).

## 5. Recommended build order

Build **`commit` → `testgen` → `shipwatch`** first. Together they convert `codev`'s output into a
merged, verified PR with almost no manual steps — the largest seamlessness win for the least effort —
and each reuses patterns already in the repo (diff parsing, Conventional Commits, human-confirmation
guardrails, the `tool.json` auto-discovery installer). `onboard`, `release`, and `triage` follow to
cover the outer edges of the lifecycle.

| Priority | Item | Model | Effort | Depends on / reuses |
|----------|------|-------|--------|---------------------|
| P1 | `commit` (`cm`) | Tool | Low | `changelog`/`prprep` diff & commit parsing |
| P2 | `testgen` | Skill | Medium | `codev` Implement stage |
| P3 | `shipwatch` (`ship`) | Tool | Medium | `prprep`, `gh` CLI |
| P4 | `onboard` | Skill | Medium | repo instruction files |
| P5 | `release` (`rel`) | Tool | Low–Med | `changelog` commit parsing |
| P6 | `triage` | Skill | Medium | — |

## 6. Guardrails to preserve

Any new component must honor the repo's existing safety conventions:

- **No destructive or remote action without explicit human confirmation** (see `worktree`/`prprep`).
- **No PR creation, merge, or deploy without a human in the loop.**
- **No secrets, no production access.**
- **Dry-run / preview by default** for anything that writes (see `changelog`).
- **Repo-agnostic skills** — work in any consuming repository.

## 7. Adding these (checklist)

- **New tool:** create `tools/<name>/` with `<name>.ps1` + `tool.json`, add tests under `tests/`, and
  a row in [`tools/README.md`](../tools/README.md) and the root `README.md`. The installer
  auto-discovers `tools/*/tool.json`.
- **New plugin:** create `plugins/<name>/` with `plugin.json`, `README.md`, and
  `skills/<name>/SKILL.md` (YAML front matter + workflow body); add it to
  [`.github/plugin/marketplace.json`](../.github/plugin/marketplace.json) and the Skill Index in the
  root `README.md`.

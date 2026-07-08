---
name: codev
description: "Guides a developer through a structured four-stage development workflow (Understand → Plan → Implement → Review) for coding tasks in this repo. Takes a task brief, brainstorms and clarifies requirements, hands off to built-in plan mode, drives the implementation, and runs a code review via the code-review-fleet skill. Trigger phrases: '/codev', 'codev', 'start a dev task', 'guide me through this task', 'help me build', 'work through this feature end to end'."
---

# codev — Guided Development Workflow

`codev` orchestrates a coding task from a rough brief to a reviewed implementation using four
explicit stages: **Understand → Plan → Implement → Review**. It is a lightweight conductor: it
delegates planning to the CLI's built-in **plan mode** and review to the existing
**code-review-fleet** skill, and keeps you moving through the stages with clear gates.

## What This Skill Does

- Accepts a brief of the task at hand and analyzes the next steps for implementation.
- **Understand**: asks focused clarifying questions and brainstorms requirements with you until the
  scope is clear.
- **Plan**: hands the refined requirements to the built-in plan mode (prompts you to run `/plan`).
- **Implement**: codev executes the approved plan by making code changes, asking questions when
  blocked, then presents a requirements-vs-implemented report. (If you chose autopilot or autopilot
  fleet in plan mode, codev will carry out that implementation here.)
- **Review**: drives a code review of the implemented changes through the `code-review-fleet` skill.
- Announces the current stage and confirms with you before advancing to the next one.

## What This Skill Does NOT Do

- Does **not** replace or re-implement the built-in plan mode — it prompts you to use it.
- Does **not** replace the `code-review-fleet` skill — it invokes it for the Review stage.
- Does **not** persist state across sessions. It runs as a single continuous conversation; there is
  no saved brief or stage marker. (Built-in plan mode still writes its own `plan.md` to the session
  folder — that is outside codev's control.)
- Does **not** create or merge pull requests, or deploy to any environment. It pushes to `origin`
  **only** via the `worktree` skill's guarded `push` (after explicit human confirmation).
- Does **not** access production resources or embed secrets.

## How to Invoke

- `/codev <brief>` — e.g. `/codev add a retry policy to the XSale fabric client`
- "codev: help me add a validation endpoint to XPackageCore"
- "start a dev task", "guide me through this feature end to end"

If invoked without a brief, ask the user for a one-to-two sentence description of the task before
starting Stage 1.

## Prerequisites

- A git working tree in this repository.
- The built-in plan mode (`/plan`) is available in the CLI.
- The `code-review-fleet` skill is available (`.github/skills/code-review-fleet/SKILL.md`).
- The `worktree` skill is available (`.github/skills/worktree/SKILL.md`) for worktree setup and push.

## Workflow Steps

codev progresses through four stages. **Always announce the stage you are entering**, and **never
advance to the next stage without an explicit gate check** (described per stage). Because there is no
persistence, keep the running context (brief, decisions, files touched) summarized in the
conversation so nothing is lost mid-flow.

### Stage 1 — Understand

**Goal:** turn a rough brief into clearly understood, agreed requirements.

**Worktree setup (do this before clarifying).** Coding work should happen on a dedicated
`users/<alias>/<name>` branch/worktree, not on `main`. Check the context by running the `worktree`
skill's `status` (`.github/skills/worktree/scripts/worktree.ps1 status`):
- **Already on a `users/<alias>/*` branch or a linked worktree** → use it; continue.
- **On `main`/`master` or the primary worktree** → offer `/worktree create <name>`. Because creating
  a worktree cannot move this running session's directory, print the new path and **ask the user to
  reopen/relaunch the CLI in that path**, then stop — do not continue implementing in the old tree.
- **Detached HEAD** → offer `/worktree branch <name>` to bind it to a branch before continuing.

1. Restate the user's brief in your own words so both sides share a starting point.
2. **If the user indicates that implementation has already begun**, inspect the working tree with
   `git status` and `git diff`, incorporate existing changes into the requirements summary, and note
   what has already been done versus what remains.
3. Explore the relevant code to ground the conversation (use `grep`, `glob`, `view`). Identify the
   service(s), layers, and existing patterns the task touches. Read the applicable
   `.github/instructions/*.instructions.md` and any service `docs/overview.md`.
4. Ask **focused clarifying questions** using `ask_user` — one question at a time, multiple-choice
   first. Cover scope boundaries (in/out), behavioral choices (defaults, limits, error handling),
   and edge cases where multiple reasonable approaches exist. Do not assume; when in doubt, ask.
5. As answers arrive, maintain a short, evolving **requirements summary** (what will be built, key
   decisions, explicit non-goals).
6. **Gate — advance only when requirements are clear.** Present the requirements summary and ask the
   user to confirm it is complete and correct. If it is not, keep clarifying. Only when the user
   confirms, move to Stage 2.

### Stage 2 — Plan

**Goal:** produce an implementation plan via the CLI's built-in plan mode.

1. Announce that requirements are clear and it is time to plan.
2. codev cannot itself trigger the `/plan` slash command. **Prompt the user to enter plan mode**,
   handing over the refined brief, e.g.:

   > Requirements look solid. To build the implementation plan, run:
   >
   > `/plan <one-line summary of the agreed requirements>`
   >
   > Plan mode will analyze the codebase, write `plan.md`, and then offer the standard
   > implementation options (interactive, autopilot, autopilot fleet). Pick one to start the build,
   > then come back to codev and say "continue" to run the Implement report and Review stages.

3. Yield control to built-in plan mode. Do not duplicate planning work inside codev.
4. When the user returns, ask: **"Have you already begun or completed the implementation via plan
   mode?"** 
   - If **yes** (e.g., they chose autopilot and plan mode ran code), skip the Implement work and jump
     to Stage 3's implementation report.
   - If **no** (they reviewed the plan but didn't start building), proceed to Stage 3 to execute the
     plan yourself.
5. Before entering Stage 3, verify that `plan.md` exists and is non-empty. If it is missing or
   empty, inform the user and return to Stage 2, prompting them to re-run `/plan` before continuing.

### Stage 3 — Implement

**Goal:** carry out the approved plan and report what was built.

1. Announce entry into the Implement stage.
2. **Execute the plan:** make surgical, complete code changes following repo conventions
   (`csharp.instructions.md`, `general-coding.instructions.md`, service-specific instructions).
   Ask questions with `ask_user` whenever you hit ambiguity or a blocker — do not guess on decisions
   that materially change the implementation.
3. **Run targeted validation:** use the **smallest targeted** build/test that covers the change
   (`dotnet build <project>`, `dotnet test --filter "FullyQualifiedName~ClassName"`).
4. **If targeted validation fails with compilation or test errors**, run a broader validation
   (`dotnet build <solution>` or full test suite) to surface dependencies across multiple projects.
   Present errors clearly to the user and pause for guidance.
5. **Once validation passes**, present an implementation report with these sections:
   - **Requirements** — the agreed requirements from Stage 1.
   - **What was implemented** — how each requirement was satisfied.
   - **Files changed** — list of files created/modified with a one-line note each.
   - **Validation** — build/test commands run and their results.
   - **Deviations & follow-ups** — anything that differs from the plan, plus known TODOs.
6. **Gate:** confirm with the user that the implementation matches intent before moving to Review.

### Stage 4 — Review

**Goal:** run a code review of the implemented changes.

1. Announce entry into the Review stage.
2. Invoke the **`code-review-fleet`** skill on the current changes. Follow that skill's flow: it
   extracts the diff, runs its parallel review agents, displays findings with severity, and lets the
   user apply fixes ("apply fix #N", "apply all fixes").
3. Surface the findings to the user and offer to apply fixes per the fleet skill's conventions.
4. If code-review-fleet findings are high in number or severity, suggest the user also run the
   built-in `/review` for an independent pass.
5. When findings are addressed (or the user chooses to stop), offer to push the branch via the
   `worktree` skill (`/worktree push`). Confirm with `ask_user` first, then invoke it with the branch
   name as confirmation (`... push -ConfirmBranch users/<alias>/<name>`). PR creation and deployment
   remain manual, human-driven steps.

## Stage Transition Rules

- Announce every stage entry; the user should always know which stage is active.
- Each stage has an explicit **gate** and must be confirmed before advancing:
  - Understand → Plan: user confirms the requirements summary.
  - Plan → Implement: user has run `/plan`, has a plan, and returns to codev.
  - Implement → Review: user confirms the implementation report matches intent.
- Users may move backward (e.g., Implement reveals a requirements gap → return to Understand). When
  this happens, re-run the affected stage's gate before advancing again.

## Failure & Stop Conditions

- **Ambiguous requirements** — stay in Understand and keep clarifying; do not advance to Plan.
- **No git repository / no working tree** — inform the user and stop.
- **Build or test failure during Implement** — present the errors and ask for guidance; do not
  report success or advance to Review until resolved or the user accepts the state.
- **No reviewable changes in Review** — inform the user and end gracefully (nothing to review).
- **`code-review-fleet` unavailable** — inform the user and suggest running the built-in `/review`
  or `git diff` manually.
- **Merge/PR/deploy request** — refuse; these are human-driven steps outside codev's scope. Pushing
  a `users/<alias>/*` branch is allowed **only** through the `worktree` skill's guarded, human-
  confirmed `push`.

## Rules Compliance

This skill follows:
- `.github/instructions/ai-tooling.instructions.md` — AI tooling contribution guidelines
- `.github/instructions/general-coding.instructions.md` — general coding principles
- `.github/instructions/csharp.instructions.md` — C# coding standards
- `.github/instructions/testing.instructions.md` — testing standards
- `.github/instructions/code-review.instructions.md` — code review standards
- `.github/instructions/security.instructions.md` — security & compliance rules

## Tool Justification

| Tool | Reason |
|------|--------|
| ask_user | Ask clarifying questions during Understand and gate checks between stages |
| grep / glob / view | Explore the codebase to ground requirements and locate implementation targets |
| edit / create | Apply code changes during the Implement stage |
| powershell | Run targeted `dotnet build` / `dotnet test` validation, and the `worktree` skill's `scripts/worktree.ps1` for worktree setup/push |
| task (code-review) | Used indirectly via the `code-review-fleet` skill during the Review stage |

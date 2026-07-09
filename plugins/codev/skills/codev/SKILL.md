---
name: codev
description: "Guides a developer through a structured four-stage development workflow (Understand → Plan → Implement → Review) for coding tasks. Takes a task brief, brainstorms and clarifies requirements, hands off to built-in plan mode, drives the implementation, and runs a code review. Trigger phrases: '/codev', 'codev', 'start a dev task', 'guide me through this task', 'help me build', 'work through this feature end to end'."
---

# codev — Guided Development Workflow

`codev` orchestrates a coding task from a rough brief to a reviewed implementation using four
explicit stages: **Understand → Plan → Implement → Review**. It is a lightweight conductor: it
delegates planning to the CLI's built-in **plan mode** and review to the built-in **`/review`**
agent, and keeps you moving through the stages with clear gates.

## What This Skill Does

- Accepts a brief of the task at hand and analyzes the next steps for implementation.
- **Understand**: asks focused clarifying questions and brainstorms requirements with you until the
  scope is clear.
- **Plan**: hands the refined requirements to the built-in plan mode (prompts you to run `/plan`).
- **Implement**: codev executes the approved plan by making code changes, asking questions when
  blocked, then presents a requirements-vs-implemented report. (If you chose autopilot or autopilot
  fleet in plan mode, codev will carry out that implementation here.)
- **Review**: drives a code review of the implemented changes through the built-in `/review`.
- Announces the current stage and confirms with you before advancing to the next one.

## What This Skill Does NOT Do

- Does **not** replace or re-implement the built-in plan mode — it prompts you to use it.
- Does **not** replace the built-in `/review` — it invokes it for the Review stage.
- Does **not** persist state across sessions. It runs as a single continuous conversation; there is
  no saved brief or stage marker. (Built-in plan mode still writes its own `plan.md` to the session
  folder — that is outside codev's control.)
- Does **not** create or merge pull requests, or deploy to any environment. It pushes to a remote
  **only** after explicit human confirmation (see Stage 4).
- Does **not** access production resources or embed secrets.

## How to Invoke

- `/codev <brief>` — e.g. `/codev add a retry policy to the fabric client`
- "codev: help me add a validation endpoint"
- "start a dev task", "guide me through this feature end to end"

If invoked without a brief, ask the user for a one-to-two sentence description of the task before
starting Stage 1.

## Prerequisites

- A git working tree in the repository you want to work in.
- The built-in plan mode (`/plan`) is available in the CLI.
- The built-in code review (`/review`) is available in the CLI.

## Workflow Steps

codev progresses through four stages. **Always announce the stage you are entering**, and **never
advance to the next stage without an explicit gate check** (described per stage). Because there is no
persistence, keep the running context (brief, decisions, files touched) summarized in the
conversation so nothing is lost mid-flow.

### Stage 1 — Understand

**Goal:** turn a rough brief into clearly understood, agreed requirements.

**Branch setup (do this before clarifying).** Coding work should happen on a dedicated feature
branch, not directly on `main`/`master`. Check the current context with `git status` and
`git branch --show-current`:
- **Already on a dedicated feature branch** (e.g. `users/<alias>/<name>` or similar) → use it;
  continue.
- **On `main`/`master`** → offer to create a feature branch with plain git before implementing,
  e.g. `git checkout -b users/<alias>/<name>`. Confirm the branch name with the user first.
- **Detached HEAD** → offer to create/switch to a branch (`git switch -c <name>`) before continuing.

1. Restate the user's brief in your own words so both sides share a starting point.
2. **If the user indicates that implementation has already begun**, inspect the working tree with
   `git status` and `git diff`, incorporate existing changes into the requirements summary, and note
   what has already been done versus what remains.
3. Explore the relevant code to ground the conversation (use `grep`, `glob`, `view`). Identify the
   components, layers, and existing patterns the task touches. Read any applicable repository
   conventions (e.g. `.github/instructions/*.instructions.md`, `AGENTS.md`, `CONTRIBUTING.md`, or a
   service `docs/overview.md`) if they exist.
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
2. **Execute the plan:** make surgical, complete code changes following the repository's conventions
   (any applicable coding, testing, and security instructions the repo defines). Ask questions with
   `ask_user` whenever you hit ambiguity or a blocker — do not guess on decisions that materially
   change the implementation.
3. **Run targeted validation:** use the **smallest targeted** build/test that covers the change,
   using the repository's own tooling (e.g. `dotnet build <project>`,
   `dotnet test --filter "FullyQualifiedName~ClassName"`, `npm test`, `pytest <path>`, etc.).
4. **If targeted validation fails with compilation or test errors**, run a broader validation (full
   project/solution build or wider test suite) to surface dependencies across multiple components.
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
2. Run the built-in **`/review`** on the current changes. If `/review` is unavailable, perform a
   manual self-review of the current diff (`git diff`) against the repository's code-review
   standards and report findings.
3. Surface the findings to the user with severity, and offer to apply fixes.
4. When findings are addressed (or the user chooses to stop), offer to push the branch. **Push only
   after explicit human confirmation:** confirm with `ask_user` first, then run a plain
   `git push -u origin <branch>`. PR creation and deployment remain manual, human-driven steps.

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
- **`/review` unavailable** — fall back to a manual `git diff` self-review and report findings.
- **Merge/PR/deploy request** — refuse; these are human-driven steps outside codev's scope. Pushing
  a branch is allowed **only** after explicit, human-confirmed approval.

## Tool Justification

| Tool | Reason |
|------|--------|
| ask_user | Ask clarifying questions during Understand and gate checks between stages |
| grep / glob / view | Explore the codebase to ground requirements and locate implementation targets |
| edit / create | Apply code changes during the Implement stage |
| shell (git / build / test) | Run git branch setup and human-confirmed push, and targeted build/test validation |

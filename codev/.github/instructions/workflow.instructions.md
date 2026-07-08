---
description: 'Default agentic development workflow for Xbox.Xbet.Service — Understand → Plan → Implement → Review'
applyTo: '**'
---

# Development Workflow

This is the **default workflow for all coding work in this repo**. Follow it even when the
[`codev`](../skills/codev/SKILL.md) skill is not invoked — codev is the guided, interactive
version of this same flow, and this instruction ensures the workflow shape is always applied.

The workflow has four stages: **Understand → Plan → Implement → Review**. Scale the ceremony
to the task (see below) — never skip the stages that matter for the change at hand.

**Interactive vs autonomous.** In interactive mode, gates are explicit user confirmations. In
autonomous/autopilot mode, gates are self-checks you perform and report in your response — do
not stop for confirmation unless requirements are materially ambiguous, or the next step is a
destructive or human-checkpoint action (see below).

## Scale to Complexity

- **Trivial change** (typo, comment, one-line fix, formatting, obvious rename): skip the Plan
  stage and formal gates. Make the change, run the smallest relevant validation, and do a quick
  self-check that it matches intent.
- **Non-trivial change** (new behavior, multi-file edits, new endpoints/business logic, changes
  that touch conventions or public contracts, anything ambiguous): run the **full four-stage
  workflow** with gates. When in doubt, treat the task as non-trivial.
- If a change initially classified as trivial is found during implementation to require
  multi-file edits or behavior changes, stop, reclassify it as non-trivial, and return to the
  Understand stage to run the full workflow from the beginning.

## The Four Stages

### 1. Understand
- Restate the task; if implementation has already begun, inspect `git status` / `git diff` first.
- Explore the relevant code and read the applicable `.github/instructions/*.instructions.md`
  and any service `docs/overview.md` to ground the work.
- Ask **focused clarifying questions** through the available interaction channel (e.g., the
  `ask_user` tool) — one at a time, multiple-choice first — on scope, behavior, defaults, and
  edge cases. In autonomous mode, proceed only when assumptions are low-risk and state them
  explicitly; otherwise stop and request clarification. Do not guess on decisions that change
  the design. This rule takes precedence over tooling availability guidance.
- **Gate:** requirements are clear (and, when interactive, confirmed) before planning.

### 2. Plan
- For non-trivial work, prefer the CLI's built-in **plan mode** (`/plan`) or the
  [`codev`](../skills/codev/SKILL.md) skill to produce `plan.md` before implementing. If slash
  commands or skills are unavailable (e.g., a plain autonomous run), write a concise
  implementation plan in the conversation and proceed once requirements are sufficiently clear.
  **Do not stall solely because `/plan` cannot be self-invoked when requirements are already
  sufficiently clear.**
- **Gate:** a clear, agreed plan exists before implementing.

### 3. Implement
- Make surgical, complete changes that follow repo conventions (`general-coding`, `csharp`,
  and service-specific instructions). Ask when blocked — don't guess.
- Run the **smallest targeted validation** that covers the change
  (`dotnet build <project>`, `dotnet test --filter "FullyQualifiedName~ClassName"`). Escalate to
  a broader build/test when the change touches shared code, public contracts, DI/startup wiring,
  or project files, or when targeted validation does not cover the risk.
- **Gate:** validation passes and the result matches the agreed intent before review.

### 4. Review
- Follow this fallback order for code review tooling:
  1. Run [`code-review-fleet`](../skills/code-review-fleet/SKILL.md) if available.
  2. Also run the built-in `/review` for an independent pass if available.
  3. If both are unavailable, perform a manual self-review of the current diff against
     `code-review.instructions.md` and report findings.
- Address findings (or record why they're deferred) before considering the task done.

## Stage & Transition Rules

- Announce the active stage for non-trivial work so the user always knows where things stand.
- Honor each stage's gate. In interactive mode, confirm before advancing; in autonomous mode,
  perform and report the gate check without pausing unless the next step depends on a user
  decision. For trivial changes, gate rigor is a quick self-check only. For non-trivial changes,
  gate rigor is the full gate as described per stage (explicit plan agreement, passing
  validation, completed review).
- Move backward when a later stage reveals a gap (e.g., Implement exposes a requirements hole →
  return to Understand), then re-run the affected gate before advancing again.

## Human Checkpoints (Non-Negotiable)

Never do these autonomously — stop for a human. The list below is illustrative, not exhaustive;
`agent-security.instructions.md` is authoritative:
If `agent-security.instructions.md` is not accessible, treat any action that is irreversible,
affects external systems, or changes access controls as a human checkpoint and stop.

- Do **not** push to `origin`, create or merge pull requests, or deploy to any environment
  (including staging).
- Do **not** access production resources, embed or rotate secrets, change CI/CD, RBAC, or
  security configuration, or perform other irreversible operations.

## Failure & Stop Conditions

- **Ambiguous requirements** — stay in Understand and keep clarifying; do not advance.
- **No git repository / working tree** — inform the user and stop.
- **Build or test failure** — present the errors and ask for guidance; do not report success or
  advance to Review until resolved or the user accepts the state.
- **Code-review tooling unavailable** — follow the fallback order in the Review stage.

## Cross-References

| Topic | See Also |
|-------|----------|
| Guided, interactive version of this workflow | `.github/skills/codev/SKILL.md` |
| Code review stage | `.github/skills/code-review-fleet/SKILL.md` |
| Core rules & compliance | `core-rules.instructions.md` |
| General coding principles | `general-coding.instructions.md` |
| C# standards | `csharp.instructions.md` |
| Testing standards | `testing.instructions.md` |
| Code review standards | `code-review.instructions.md` |
| Security & compliance | `security.instructions.md` |
| Agent security practices | `agent-security.instructions.md` |
| AI tooling contribution guidelines | `ai-tooling.instructions.md` |

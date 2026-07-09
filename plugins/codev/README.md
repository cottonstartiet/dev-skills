# codev

**Guided four-stage development workflow for GitHub Copilot CLI.**

codev takes a coding task from a rough brief to a reviewed implementation using four explicit,
gated stages:

1. **Understand** — restate the brief, explore the code, ask focused clarifying questions, and
   agree on requirements.
2. **Plan** — hand the refined requirements to the built-in plan mode (`/plan`).
3. **Implement** — execute the approved plan with surgical changes and targeted validation, then
   report requirements-vs-implemented.
4. **Review** — run the built-in `/review` on the changes and address findings.

codev is a lightweight conductor: it delegates planning to `/plan` and review to `/review`, and
keeps you moving through the stages with explicit gates. It does **not** persist state across
sessions, create/merge PRs, or deploy.

## How to Invoke

- `/codev <brief>` — e.g. `/codev add a retry policy to the fabric client`
- "codev: help me add a validation endpoint"
- "start a dev task", "guide me through this feature end to end"

If invoked without a brief, codev asks for a one-to-two sentence description before starting.

## Prerequisites

- A git working tree in the repository you want to work in.
- The built-in plan mode (`/plan`) and code review (`/review`) commands.

## Safety

- Branch creation uses plain git; codev works on a dedicated feature branch, not `main`/`master`.
- Pushing to a remote happens **only** after explicit human confirmation.
- PR creation and deployment remain manual, human-driven steps.

See [`skills/codev/SKILL.md`](skills/codev/SKILL.md) for the full stage-by-stage workflow.

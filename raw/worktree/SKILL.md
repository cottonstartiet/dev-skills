---
name: worktree
description: "Create, inspect, branch, push, and remove git worktrees for the Xbox.Xbet.Service monorepo using the users/<alias>/<name> branch convention."
tools: ['powershell', 'ask_user']
---

# worktree — Git Worktree Helper

`worktree` makes routine git-worktree actions easy and safe for developers using coding agents in
this repo. It wraps `git worktree` behind a single PowerShell script
(`scripts/worktree.ps1`) with focused subcommands and guardrails so worktrees are always created on
a proper `users/<alias>/<name>` branch (no more accidental detached HEADs), and destructive/remote
actions require explicit confirmation.

## What This Skill Does

- Creates a worktree **and** its branch in one step (`create`).
- Lists worktrees with branch / dirty / upstream state (`list`).
- Shows the current worktree's state and repairs detached HEAD (`status`, `branch`).
- Reports health across all worktrees, read-only (`health`).
- Pushes the current branch to origin **after explicit human confirmation** (`push`).
- Removes a worktree safely, never deleting the branch (`remove`).
- Lists worktree paths so you can open another one (`switch`).

## What This Skill Does NOT Do

- Does **not** create or merge pull requests, or deploy to any environment.
- Does **not** access production resources or embed secrets.
- Does **not** force-push, auto-push, or delete branches.
- Does **not** change your terminal's directory for you — creating a worktree cannot move a running
  shell; it prints the path for you to open.

## Prerequisites

- A git working tree in this repository and `git` on `PATH`.
- PowerShell 7+ (`pwsh`).
- `git config user.email` set (the branch alias is derived from its local-part).

## How to Invoke

- `/worktree create <name>` — e.g. `/worktree create wishlist-reorder-api`
- `/worktree status` / `/worktree list` / `/worktree health`
- `/worktree branch <name>` — fix a detached worktree
- `/worktree push` / `/worktree remove <name>` / `/worktree switch`
- "create a worktree for …", "clean up my worktrees", "push this branch"

The script lives at `scripts/worktree.ps1`. Invoke it from within the target worktree
(most commands act on the current/ambient repository):

```powershell
pwsh -NoProfile -File .github/skills/worktree/scripts/worktree.ps1 <command> [name] [options]
```

## Conventions

- **Branch:** `users/<alias>/<name>`, alias auto-detected from `git config user.email`
  (part before `@`, lower-cased).
- If the local-part of `user.email` contains characters that are invalid in a git branch name
  (for example spaces, tildes, or colons), surface a clear error naming the invalid characters
  and instruct the user to either fix their git config or manually specify a valid alias with
  `-Alias <alias>`.
- **Worktree path:** `<primaryWorktree>.worktrees\<name>` (derived from the primary worktree; on the
  standard setup this is `C:\work\Xbox.Xbet.Service.worktrees\<name>`). Override with
  `-WorktreesBase <path>` or the `WORKTREE_BASE` environment variable.

## Workflow (per subcommand)

| Command | Behavior |
|---------|----------|
| `create <name> [-BaseBranch main]` | Validates the name and branch ref; pre-checks branch/path/checkout collisions; **always pulls the latest base branch from origin first** (fast-forward only; non-fatal on failure); creates `users/<alias>/<name>` from the base branch; prints the new worktree path. |
| `list` | Table of all worktrees: name, branch (or `(detached)`), clean/dirty, ahead/behind. |
| `status` | Current worktree's branch, upstream, and dirty state; prints the `branch` command if detached. |
| `branch <name>` | For a **detached** current worktree only: creates/switches to `users/<alias>/<name>` at HEAD, preserving uncommitted changes. |
| `health` | Read-only report: detached, dirty, no-upstream, behind, prunable, locked worktrees, with suggested fixes. |
| `push [-ConfirmBranch <branch>]` | Guards: refuses detached/protected branches and non-`users/<alias>/*` branches, refuses force, checks upstream is `origin/<branch>`, warns on uncommitted; if upstream is not `origin/<branch>`, abort with an actionable error instructing the user to run `git branch --set-upstream-to=origin/<branch>` and do not invoke the script; requires the branch name as typed confirmation, then `git push -u origin <branch>`. |
| `remove <name> [-ConfirmName <name>]` | Guard order: 1) abort if target is the primary or currently active worktree; 2) abort if the worktree has any uncommitted changes (staged or unstaged) or untracked files that are not git-ignored; 3) if origin state cannot be determined, treat as having unpushed commits (fail-closed); 4) if the branch has commits not present on origin, require `-ConfirmName <name>`; 5) on success, remove the worktree directory but never delete the branch; 6) report any locked or prunable worktrees found during the operation. |
| `switch` | Lists worktrees and their absolute paths to open. |

### Agent confirmation for guarded actions

`push` and (when there is unpushed work) `remove` require confirmation. In an agent context, ask the
user with `ask_user` first, then pass the confirmation non-interactively:

- Push: `... push -ConfirmBranch users/<alias>/<name>`
- Remove with unpushed work: `... remove <name> -ConfirmName <name>`

The script only prompts interactively (`Read-Host`) at a real console; in automation it declines
rather than blocking, so it never hangs.

## Input / Output

- **Input:** subcommand, optional `<name>`, and options (`-BaseBranch`, `-WorktreesBase`,
  `-ConfirmBranch`, `-ConfirmName`).
- **Output:** human-readable status lines. Exit code `0` on success, `1` on any handled error or
  declined confirmation.

## Error Handling / Stop Conditions

- Missing `git user.email` → clear error asking the user to set it.
- Invalid names, base-branch/branch/path collisions, or an unregistered worktree → non-zero exit
  with an actionable message; no partial changes.
- No git repository → the underlying git command fails and the error is surfaced.
- Any push/remove that isn't explicitly confirmed → declined (exit `1`), never destructive.

## Testing

Pester tests run against throwaway temp repos (no network unless a local bare remote is created):

```powershell
pwsh -NoProfile -File .github/skills/worktree/tests/run-tests.ps1
```

## Tool Justification

| Tool | Reason |
|------|--------|
| powershell | Run `scripts/worktree.ps1` (the git-worktree operations). |
| ask_user | Confirm guarded `push`/`remove` actions before invoking the script with confirmation. |

## Rules Compliance

This skill follows:
- `.github/instructions/ai-tooling.instructions.md` — AI tooling contribution guidelines
- `.github/instructions/agent-security.instructions.md` — human checkpoints for push; no production access; no secrets
- `.github/instructions/commit-message.instructions.md` — branch/commit conventions
- `.github/instructions/general-coding.instructions.md` — general principles

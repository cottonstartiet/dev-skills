# worktree — Git Worktree Helper (`tr`)

A single PowerShell script that makes routine `git worktree` actions easy and safe. It wraps
`git worktree` behind focused subcommands with guardrails so worktrees are always created on a
proper `users/<alias>/<name>` branch (no more accidental detached HEADs), and destructive/remote
actions require explicit confirmation.

Once installed (see [Install](#install)) it is invoked as **`tr`**.

## What it does

- Creates a worktree **and** its branch in one step (`create`).
- Lists worktrees with branch / dirty / upstream state (`list`).
- Shows the current worktree's state and repairs a detached HEAD (`status`, `branch`).
- Reports health across all worktrees, read-only (`health`).
- Pushes the current branch to origin **after explicit confirmation** (`push`).
- Removes a worktree safely, never deleting the branch (`remove`).
- Lists worktree paths so you can open another one (`switch`).

It does **not** create/merge PRs, deploy, force-push, auto-push, or delete branches, and it never
changes your terminal's directory for you — it prints the path for you to open.

## Prerequisites

- A git working tree and `git` on `PATH`.
- PowerShell 7+ (`pwsh`).
- `git config user.email` set (the branch alias is derived from its local-part).

## Install

From the repository root:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool worktree
```

This adds a `tr` function to your PowerShell profile. Restart PowerShell (or run
`. $PROFILE.CurrentUserAllHosts`) and then use `tr` from any repository. To remove it:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool worktree -Uninstall
```

You can also run the script directly without installing:

```powershell
pwsh -NoProfile -File tools/worktree/worktree.ps1 <command> [name] [options]
```

## Commands

| Command | Behavior |
|---------|----------|
| `tr create <name> [-BaseBranch main]` | Validates the name/branch ref; pre-checks branch/path/checkout collisions; **pulls the latest base branch from origin first** (fast-forward only; non-fatal on failure); creates `users/<alias>/<name>` from the base branch; prints the new worktree path. |
| `tr list` | Table of all worktrees: name, branch (or `(detached)`), clean/dirty, ahead/behind. |
| `tr status` | Current worktree's branch, upstream, and dirty state; prints the `branch` hint if detached. |
| `tr branch <name>` | For a **detached** current worktree only: creates/switches to `users/<alias>/<name>` at HEAD, preserving uncommitted changes. |
| `tr health` | Read-only report: detached, dirty, no-upstream, behind, prunable, locked worktrees, with suggested fixes. |
| `tr push [-ConfirmBranch <branch>]` | Guards against detached/protected/non-`users/<alias>/*` branches and force pushes; requires the branch name as typed confirmation, then `git push -u origin <branch>`. |
| `tr remove <name> [-ConfirmName <name>]` | Refuses to remove the primary/active worktree or one with uncommitted changes; requires `-ConfirmName` if the branch has commits not on origin; removes the directory but never deletes the branch. |
| `tr switch` | Lists worktrees and their absolute paths to open. |

## Conventions

- **Branch:** `users/<alias>/<name>`, alias auto-detected from `git config user.email`
  (part before `@`, lower-cased).
- **Worktree path:** `<primaryWorktree>.worktrees\<name>`. Override with `-WorktreesBase <path>`
  or the `WORKTREE_BASE` environment variable.

## Confirmations

`push` and (when there is unpushed work) `remove` require typed confirmation. Pass it
non-interactively with `-ConfirmBranch <branch>` / `-ConfirmName <name>`. At a real console the
script prompts; in automation it declines rather than blocking, so it never hangs.

## Testing

Pester tests run against throwaway temp repos (no network unless a local bare remote is created):

```powershell
pwsh -NoProfile -File tools/worktree/tests/run-tests.ps1
```

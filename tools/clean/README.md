# clean — Git Branch Cleanup Helper (`clean`)

A standalone PowerShell script that reports stale local git branches and can prune the safe ones. A stale branch is either already merged into a base branch or tracks an upstream that is gone after `git fetch --prune`.

Once installed (see [Install](#install)) it is invoked as **`clean`**.

## What it does

- Runs `git fetch --prune` first (warns and continues if offline/no remote).
- Lists stale local branches in read-only mode by default (`clean` / `clean list`).
- Identifies branches merged into `-BaseBranch` (default `main`).
- Identifies branches whose tracked upstream is gone.
- Never deletes the current branch or protected branches (`main`, `master`, `develop`, `release`, `production`).
- Uses `git branch -d` for safe deletions.
- Uses `git branch -D` only with `-Force` and matching typed confirmation.

## Prerequisites

- A git working tree and `git` on `PATH`.
- PowerShell 7+ (`pwsh`).

## Install

From the repository root:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool clean
```

This adds a `clean` function to your PowerShell profile. Restart PowerShell (or run `. $PROFILE.CurrentUserAllHosts`) and then use `clean` from any repository. To remove it:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool clean -Uninstall
```

You can also run the script directly without installing:

```powershell
pwsh -NoProfile -File tools/clean/clean.ps1 <command> [options]
```

## Commands

| Command | Behavior |
|---------|----------|
| `clean` / `clean list [-BaseBranch main]` | Read-only report of stale local branches and skipped branches with reasons. |
| `clean delete [-BaseBranch main] [-Yes]` | Deletes safe stale branches with `git branch -d`; prompts per branch unless `-Yes` is passed. |
| `clean delete -Force -ConfirmName <branch>` | Force-deletes a stale branch with unmerged work using `git branch -D` only after typed confirmation. |
| `clean help` | Prints usage. |

`clean -Delete` is equivalent to `clean delete`.

## Confirmations

Safe deletions require per-branch confirmation unless `-Yes` is passed. Force deletion always requires the branch name as typed confirmation. Pass it non-interactively with `-ConfirmName <branch>`. At a real console the script prompts; in automation it declines rather than blocking, so it never hangs.

## Testing

Pester tests run against throwaway git repos:

```powershell
pwsh -NoProfile -File tools/clean/tests/run-tests.ps1
```

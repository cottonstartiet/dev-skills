# sync — Safe Current-Branch Updater (`sync`)

A standalone PowerShell CLI that previews and safely updates the **current** git
branch. It fetches origin first when available, reports ahead/behind state, and
applies only local branch updates. It never pushes, never force-updates, and
refuses unsafe states such as detached HEAD.

Once installed (see [Install](#install)) it is invoked as **`sync`**.

## What it does

- `sync` / `sync preview` shows a dry-run preview: current branch, upstream
  ahead/behind, base ahead/behind, dirty state, and selected mode.
- `sync run` fast-forwards the current branch to its upstream.
- `sync run -Rebase [-BaseBranch main]` rebases the current branch onto the base.
- `sync run -Merge [-BaseBranch main]` merges the base into the current branch.
- `sync run -Autostash` temporarily stashes uncommitted changes and restores them
  after the sync attempt.

It does **not** create PRs, deploy, force-push, push, or switch branches for you.

## Prerequisites

- A git working tree and `git` on `PATH`.
- PowerShell 7+ (`pwsh`).

## Install

From the repository root:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool sync
```

This adds a `sync` function to your PowerShell profile. Restart PowerShell (or
run `. $PROFILE.CurrentUserAllHosts`) and then use `sync` from any repository.
To remove it:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool sync -Uninstall
```

You can also run the script directly without installing:

```powershell
pwsh -NoProfile -File tools/sync/sync.ps1 <command> [options]
```

## Commands

| Command | Behavior |
|---------|----------|
| `sync` / `sync preview [-BaseBranch main]` | Fetches origin if available, then reports ahead/behind of the current branch vs upstream and base. No branch update is applied. |
| `sync run` | Fetches origin if available, then fast-forwards the current branch to its upstream (`git merge --ff-only @{u}`). |
| `sync run -Rebase [-BaseBranch main]` | Rebases the current branch onto the base branch (`origin/<base>` when available, otherwise local `<base>`). |
| `sync run -Merge [-BaseBranch main]` | Merges the base branch into the current branch. |
| `sync help` | Prints usage for `sync <command> [options]`. |

## Safety

- Refuses detached HEAD.
- Refuses dirty working trees in `run` mode unless `-Autostash` is supplied.
- Never pushes and never force-updates.
- Warns, but continues, when `git fetch origin` fails because the repo is
  offline or has no origin.
- Refuses rebase/merge modes while on protected branches such as `main`.

## Testing

Pester tests run against throwaway local git repos and local bare remotes only:

```powershell
pwsh -NoProfile -File tools/sync/tests/run-tests.ps1
```

# prprep — PR Description Prep

Draft a Markdown PR description and review checklist from the current branch diff.

Once installed (see [Install](#install)) it is invoked as **`prprep`**.

## What it does

- Compares the current branch to a base branch (default: `main`) using `merge-base`.
- Groups commits by Conventional Commit type (`feat`, `fix`, `docs`, `test`, etc.).
- Lists changed files with added/deleted line counts.
- Adds simple risk heuristics, including file count and whether test/spec files changed.
- Prints the draft to stdout and writes `PR_DESCRIPTION.md` at the repo root by default.

It **never creates a PR**, never pushes, and never changes branches or git state. The only write is
the Markdown draft file, and `-NoWrite` disables that.

## Prerequisites

- A git working tree and `git` on `PATH`.
- PowerShell 7+ (`pwsh`).

## Install

From the repository root:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool prprep
```

This adds a `prprep` function to your PowerShell profile. Restart PowerShell (or run
`. $PROFILE.CurrentUserAllHosts`) and then use `prprep` from any repository. To remove it:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool prprep -Uninstall
```

You can also run the script directly without installing:

```powershell
pwsh -NoProfile -File tools/prprep/prprep.ps1 [draft] [options]
```

## Commands

| Command | Behavior |
|---------|----------|
| `prprep draft [-BaseBranch main] [-Out <path>] [-NoWrite]` | Prints a PR description draft. By default also writes `PR_DESCRIPTION.md` at the repo root. |
| `prprep help` | Shows usage. |

## Options

- `-BaseBranch <branch>`: Base branch to compare against (default: `main`).
- `-Out <path>`: Change the output file target. Relative paths are resolved from the repo root.
- `-NoWrite`: Print only and do not write any file.

If the current branch is the base branch, or there are no commits ahead of the base, `prprep`
reports that clearly and exits successfully without writing a draft.

## Testing

Pester tests run against throwaway git repos:

```powershell
pwsh -NoProfile -File tools/prprep/tests/run-tests.ps1
```

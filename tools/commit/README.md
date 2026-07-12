# commit — Conventional Commit Helper (`commit`)

A standalone PowerShell CLI that composes a valid Conventional Commit message and
creates a **local** git commit. It never pushes, never creates branches, and by default
commits only changes that are already staged.

Once installed (see [Install](#install)) it is invoked as **`commit`**.

## What it does

- Builds headers in the form `<type>(<scope>)?(!)?: <subject>`.
- Supports optional commit body text.
- Supports breaking changes with `!` plus a `BREAKING CHANGE:` footer.
- Validates the Conventional Commit type and keeps the header at 72 characters or less.
- Refuses to run outside a git repo or when there is nothing staged.
- Optionally stages all changes first with `-AddAll`.

## Prerequisites

- A git working tree and `git` on `PATH`.
- PowerShell 7+ (`pwsh`).
- `git config user.email` and `git config user.name` set for commits.

## Install

From the repository root:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool commit
```

This adds a `commit` function to your PowerShell profile. Restart PowerShell (or run
`. $PROFILE.CurrentUserAllHosts`) and then use `commit` from any repository. To remove it:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool commit -Uninstall
```

You can also run the script directly without installing:

```powershell
pwsh -NoProfile -File tools/commit/commit.ps1 [create] -Type <type> -Subject <subject> [options]
```

## Commands

| Command | Behavior |
|---------|----------|
| `commit create -Type <type> -Subject <subject> [options]` | Builds and validates a Conventional Commit message, then runs `git commit` locally. |
| `commit help` | Prints usage and the valid type list. |

`create` is the default command, so `commit -Type fix -Subject "handle null profile"` works.

## Options

| Option | Behavior |
|--------|----------|
| `-Type <type>` | Required outside interactive use. Valid values: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `build`, `ci`, `style`, `revert`. |
| `-Scope <scope>` | Optional scope inserted as `(<scope>)`. |
| `-Subject <subject>` | Required outside interactive use. Must be non-empty; trailing periods are stripped; total header length must be 72 characters or less. |
| `-Body <body>` | Optional commit body. |
| `-Breaking` | Adds `!` to the header and a `BREAKING CHANGE:` footer. |
| `-BreakingDescription <text>` | Footer text for `-Breaking`; defaults to the subject when omitted. |
| `-AddAll` | Runs `git add -A` before checking for staged changes. |

## Examples

```powershell
commit -Type feat -Scope api -Subject "add user lookup"
commit -Type fix -Subject "handle missing profile" -Body "Return 404 instead of 500."
commit -Type refactor -Scope config -Subject "rename provider" -Breaking -BreakingDescription "Config key providerName replaces name."
commit -Type chore -Subject "update generated files" -AddAll
```

## Testing

Pester tests run against throwaway temp repos:

```powershell
pwsh -NoProfile -File tools/commit/tests/run-tests.ps1
```

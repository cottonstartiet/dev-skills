# changelog — Conventional Commits Changelog Generator

A standalone PowerShell CLI that generates a Keep a Changelog-style changelog block from Conventional Commits.

Once installed (see [Install](#install)) it is invoked as **`changelog`**.

## What it does

- Reads commits from the latest reachable tag to `HEAD` by default.
- Uses the whole reachable history when no tags exist.
- Supports explicit ranges with `-From <ref>` and `-To <ref>`.
- Groups Conventional Commit subjects into changelog sections:
  - `feat` → Added
  - `fix` → Fixed
  - `refactor`, `perf`, `build`, `ci`, `style`, `chore` → Changed
  - `docs` → Documentation
  - `revert` → Reverted
  - unparseable subjects → Other
- Surfaces `!` and `BREAKING CHANGE:` markers in a `BREAKING CHANGES` section.
- Prints the generated block by default and writes nothing.
- With `-Write`, prepends the generated block to `CHANGELOG.md` or `-Out <path>`.

It does **not** create tags, commits, pushes, pull requests, releases, or publish anything. The only write operation is `-Write`, which updates the changelog file.

## Prerequisites

- A git working tree and `git` on `PATH`.
- PowerShell 7+ (`pwsh`).
- Conventional Commit-style commit subjects for best results.

## Install

From the repository root:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool changelog
```

This adds a `changelog` function to your PowerShell profile. Restart PowerShell (or run
`. $PROFILE.CurrentUserAllHosts`) and then use `changelog` from any repository. To remove it:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool changelog -Uninstall
```

You can also run the script directly without installing:

```powershell
pwsh -NoProfile -File tools/changelog/changelog.ps1 generate [options]
```

## Commands

| Command | Behavior |
|---------|----------|
| `changelog generate [-From <ref>] [-To <ref>] [-Version <x>]` | Prints a generated changelog block to stdout. |
| `changelog generate -Write [-Out CHANGELOG.md] [-Version <x>]` | Prepends the generated block to a changelog file. |
| `changelog help` | Shows usage. |

## Examples

```powershell
changelog generate
changelog generate -Version 1.2.0
changelog generate -From v1.1.0 -To HEAD
changelog generate -Version 1.2.0 -Write
changelog generate -Version 1.2.0 -Write -Out docs\CHANGELOG.md
```

## Output

Without `-Version`, the heading is:

```markdown
## [Unreleased]
```

With `-Version 1.2.0`, the heading is:

```markdown
## [1.2.0] - yyyy-MM-dd
```

## Testing

Pester tests run against throwaway temp repos:

```powershell
pwsh -NoProfile -File tools/changelog/tests/run-tests.ps1
```

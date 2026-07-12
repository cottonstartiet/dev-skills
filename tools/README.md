# 🧰 Tools

Standalone command-line **tools** you can install into your shell. Unlike the [plugins](../plugins)
in this repo (which extend GitHub Copilot CLI), tools are plain PowerShell scripts you run directly
from your terminal as short commands.

## Available tools

| Tool | Command | What it does |
|------|---------|--------------|
| [**worktree**](worktree) | `tr` | Create, inspect, branch, push, and remove git worktrees safely, using a `users/<alias>/<name>` branch convention with guardrails on destructive/remote actions. |
| [**sync**](sync) | `sync` | Preview and safely update the current branch (fast-forward by default; `-Rebase`/`-Merge` opt-in; never force). |
| [**clean**](clean) | `clean` | Report and prune stale local branches (merged or gone-upstream); never deletes current/protected/unmerged work without confirmation. |
| [**commit**](commit) | `commit` | Compose and create a local Conventional Commit; validates the message and never pushes. |
| [**prprep**](prprep) | `prprep` | Draft a PR description + checklist from the diff. Does **not** create the PR or push. |
| [**changelog**](changelog) | `changelog` | Generate a Keep a Changelog-style changelog from Conventional Commits; dry-run unless `-Write`. |

## Installing tools

Run the installer from the repository root. With no arguments it shows an interactive menu of every
available tool and installs the one(s) you pick:

```powershell
pwsh -NoProfile -File tools/install.ps1
```

Installing a tool adds a small function to your PowerShell profile (`$PROFILE.CurrentUserAllHosts`)
so its command is available in every new session. Restart PowerShell (or run
`. $PROFILE.CurrentUserAllHosts`) afterwards.

Non-interactive usage:

```powershell
pwsh -NoProfile -File tools/install.ps1 -Tool worktree       # install one tool
pwsh -NoProfile -File tools/install.ps1 -All                 # install everything
pwsh -NoProfile -File tools/install.ps1 -Tool worktree -Uninstall   # remove a tool
pwsh -NoProfile -File tools/install.ps1 -All -Uninstall -Yes         # remove all, no prompt
```

| Flag | Purpose |
|------|---------|
| `-Tool <name>` | Act on a single tool (by name or command) instead of showing the menu. |
| `-All` | Act on every discovered tool. |
| `-Uninstall` | Remove the tool's command from your profile instead of installing. |
| `-Yes` | Skip confirmation prompts. |
| `-ProfilePath <path>` | Override the profile file to edit (mainly for testing). |

The installer is **idempotent** (re-installing replaces the managed block) and backs up your profile
to `<profile>.bak` before writing.

## Adding a new tool

1. Create `tools/<name>/` containing your script and a `tool.json` manifest:

   ```json
   {
     "name": "<name>",
     "command": "<short-command>",
     "script": "<script>.ps1",
     "version": "1.0.0",
     "summary": "One-line overview shown in the install menu.",
     "description": "Longer description."
   }
   ```

2. That's it — `install.ps1` auto-discovers any `tools/*/tool.json`, so the new tool appears in the
   menu automatically. `command` must be a valid command name and unique across tools.
3. Add a row to the **Available tools** table above (and to the repo `README.md`).

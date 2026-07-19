# dev-skills

A **GitHub Copilot CLI plugin marketplace** — a curated collection of developer-productivity
skills you can install into Copilot CLI to guide, analyze, and accelerate your engineering work.

Each plugin bundles one or more **skills** (reusable prompts/workflows Copilot loads on demand).
This repository is the marketplace: its [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json)
indexes every plugin so Copilot CLI can discover and install them.

It also ships standalone **[command-line tools](tools)** — PowerShell scripts you install into your
shell and run directly (see [Tools](#-tools)).

---

## 📚 Skill Index

| Skill | Plugin | What it does |
|-------|--------|--------------|
| [**codev**](plugins/codev) | `codev` | Guides a coding task end-to-end through a four-stage workflow — **Understand → Plan → Implement → Review** — with explicit gates between stages. |
| [**deep-analysis**](plugins/deep-analysis) | `deep-analysis` | Performs a deep codebase/architecture analysis from a prompt and produces a polished, self-contained **HTML report** of the findings. |
| [**explain-change**](plugins/explain-change) | `explain-change` | Turns a code change, diff, branch, or PR into a self-contained **interactive HTML explanation** — Background, Intuition (diagrams + toy examples), Code walkthrough, and a five-question interactive Quiz. |
| [**desktop-notify**](plugins/desktop-notify) | `desktop-notify` | *(Hook-based — no invoke phrase.)* Fires a native **desktop notification** when Copilot is waiting on you — a permission approval, an idle question/clarification, or a finished turn. Cross-platform, no dependencies, quiet while your terminal is focused. |

### codev — Guided Development Workflow

A lightweight conductor that takes a rough task brief all the way to a reviewed implementation:

1. **Understand** — restates the brief, explores the code, and asks focused clarifying questions
   until requirements are agreed. Sets up a dedicated feature branch first.
2. **Plan** — hands the refined requirements to the CLI's built-in plan mode (`/plan`).
3. **Implement** — executes the approved plan with surgical changes and the smallest targeted
   build/test validation, then reports requirements-vs-implemented.
4. **Review** — runs the built-in `/review` on the changes and helps address findings.

It announces each stage and won't advance without a gate check. It never creates/merges PRs or
deploys, and it only pushes to a remote after explicit human confirmation.
**Invoke:** `/codev <brief>`, "start a dev task", "guide me through this feature end to end".

### deep-analysis — Analysis & HTML Report

Understands your prompt, performs an extensive multi-faceted analysis (architecture, code quality,
dependencies, and — on request — a recommended implementation approach), asks clarifying questions
when the request is ambiguous, and generates a **light-theme, self-contained HTML report** grounded
in real files and code, then opens it in your browser.
**Invoke:** "analyze the auth flow in the payments service", "architecture review of this repo",
"produce an HTML report of the dependency graph".

### explain-change — Interactive Code-Change Explanation

Takes a change set — uncommitted work, a branch vs. its base, a commit range, or a PR — and
reconstructs its intent from the diff and surrounding code, then generates a single, self-contained
**interactive HTML page** that teaches what changed and why:

1. **Background** — a deep, skippable beginner primer, then a narrow background tied to the change.
2. **Intuition** — the core idea with toy data and reusable HTML diagrams (UI mocks + data-flow
   diagrams with example data).
3. **Code** — a logically grouped walkthrough of the actual changes, grounded in real files.
4. **Quiz** — five medium-difficulty, interactive multiple-choice questions with per-answer feedback.

It's read-only — it never creates/merges PRs, pushes, deploys, or edits source. The file is saved
outside the repo with a `YYYY-MM-DD-` prefix (kept out of version control) and opened in your browser.
**Invoke:** "explain this PR", "walk me through the diff on my branch", "explain PR #128".

### desktop-notify — Desktop Notifications When Copilot Waits

A **hook-based** plugin (no skill, no slash command) that fires a native **desktop notification**
whenever Copilot CLI is waiting on you, so you can step away and get pulled back the moment you're
needed. It notifies on three hook events:

- **permission** — a tool/command approval is pending,
- **idle** — Copilot is waiting for your next input, question, or clarification,
- **stop** — the current turn finished.

Notifications use each OS's built-in notifier (**no third-party dependencies**): Windows toast (with
a tray-balloon fallback), macOS `osascript`, and Linux `notify-send`. On Windows it **stays quiet
while your terminal is focused**, debounces duplicate/background events, and always fails quietly so
it can never block a Copilot turn. Configure via `COPILOT_NOTIFY_DEBOUNCE`, `COPILOT_NOTIFY_ALWAYS`,
and `COPILOT_NOTIFY_DEBUG`.
**Invoke:** none — it runs automatically in the background once installed.

---

## 🚀 Install as a Marketplace

Copilot CLI installs plugins from marketplaces — GitHub repositories containing a
`marketplace.json` catalog. Add this repository once, then install any plugin from it.

> All commands work both from your shell (`copilot plugin ...`) and inside an interactive Copilot
> CLI session (`/plugin ...`).

**1. Register the marketplace:**

```bash
copilot plugin marketplace add cottonstartiet/dev-skills
```

**2. Browse what's available:**

```bash
copilot plugin marketplace browse dev-skills
```

**3. Install a plugin** (`<plugin>@<marketplace>`):

```bash
copilot plugin install codev@dev-skills
copilot plugin install deep-analysis@dev-skills
```

**4. Verify it loaded** — start Copilot CLI and run `/env` (or `copilot plugin list`) to confirm
the plugin's skills are available. You can then trigger a skill by its phrases, e.g. `/codev`.

### Install without registering the marketplace

You can install a single plugin straight from this repo's subdirectory:

```bash
copilot plugin install cottonstartiet/dev-skills:plugins/codev
copilot plugin install cottonstartiet/dev-skills:plugins/deep-analysis
```

### Try a plugin locally (development)

Point Copilot CLI at a plugin directory without installing it:

```bash
copilot --plugin-dir ./plugins/codev
```

---

## 🔧 Managing Plugins

| Task | Command |
|------|---------|
| List registered marketplaces | `copilot plugin marketplace list` |
| Refresh marketplace catalogs | `copilot plugin marketplace update` |
| List installed plugins | `copilot plugin list` |
| Update a plugin | `copilot plugin update <name>` |
| Uninstall a plugin | `copilot plugin uninstall <name>` |
| Remove this marketplace | `copilot plugin marketplace remove dev-skills` |

---

## 🧰 Tools

Alongside the Copilot CLI plugins, this repo ships standalone **command-line tools** — plain
PowerShell scripts you install into your shell and run directly (no Copilot required). They live
under [`tools/`](tools) and are installed with a menu-driven installer.

| Tool | Command | What it does |
|------|---------|--------------|
| [**worktree**](tools/worktree) | `tr` | Create, inspect, branch, push, and remove git worktrees safely, using a `users/<alias>/<name>` branch convention with guardrails on destructive/remote actions. |
| [**sync**](tools/sync) | `sync` | Preview and safely update the current branch (fast-forward by default; `-Rebase`/`-Merge` opt-in; never force). |
| [**prprep**](tools/prprep) | `prprep` | Draft a PR description + checklist from the diff. Does **not** create the PR or push. |
| [**changelog**](tools/changelog) | `changelog` | Generate a Keep a Changelog-style changelog from Conventional Commits; dry-run unless `-Write`. |

**Install** (from the repo root) — run with no arguments for an interactive menu, or target a tool:

```powershell
pwsh -NoProfile -File tools/install.ps1              # interactive menu
pwsh -NoProfile -File tools/install.ps1 -Tool worktree
```

Installing adds a small function (e.g. `tr`) to your PowerShell profile so the command works in
every new session. Restart PowerShell afterwards. Uninstall with `-Uninstall`. See
[`tools/README.md`](tools/README.md) for all flags and how to add a new tool.

---

## 🗂️ Repository Layout

```
dev-skills/
├── .github/
│   └── plugin/
│       └── marketplace.json         # marketplace manifest — indexes every plugin
├── plugins/
│   ├── codev/                       # a plugin
│   │   ├── plugin.json              #   manifest (declares skills/agents)
│   │   ├── README.md
│   │   └── skills/
│   │       └── codev/
│   │           └── SKILL.md
│   └── deep-analysis/
│       ├── plugin.json
│       ├── README.md
│       └── skills/
│           └── deep-analysis/
│               └── SKILL.md
│   └── explain-change/
│       ├── plugin.json
│       ├── README.md
│       └── skills/
│           └── explain-change/
│               └── SKILL.md
│   └── desktop-notify/                 # a hook-based plugin (no skill)
│       ├── plugin.json                 #   manifest (declares "hooks")
│       ├── README.md
│       ├── hooks/
│       │   └── hooks.json              #   hook event -> command bindings
│       └── scripts/
│           ├── notify.js               #   cross-platform dispatcher
│           └── notify.ps1              #   Windows toast + focus detection
├── tools/                           # standalone CLI tools (installed into your shell)
│   ├── install.ps1                  #   menu-driven installer
│   ├── README.md
│   └── worktree/                    #   a tool
│       ├── tool.json                #     manifest (name, command, script)
│       ├── worktree.ps1
│       ├── README.md
│       └── tests/
├── raw/                             # staging area for skills not yet packaged
├── specs/                           # design specs & roadmap proposals (pre-implementation)
└── README.md
```

- **`.github/plugin/marketplace.json`** declares the marketplace `name` (`dev-skills`) and lists
  each plugin with its `source`, `version`, and `description`.
- Each **plugin** folder under `plugins/` has a `plugin.json` manifest (declaring its `skills`
  and/or `agents`), a `README.md`, and its skill content under `skills/<name>/SKILL.md`.
- Each **tool** folder under `tools/` has a `tool.json` manifest (declaring its `command` and
  `script`) and a `README.md`; `tools/install.ps1` discovers and installs them.
- **`raw/`** holds imported skills that have not yet been packaged into plugins.
- **`specs/`** holds design specs and roadmap proposals describing what we intend to build and why,
  before a plugin/tool is implemented (see [`specs/README.md`](specs/README.md)).

---

## ➕ Adding a New Plugin

1. Create `plugins/<name>/` containing:
   - `plugin.json` — `name`, `description`, `version`, `author`, `license`, `keywords`, and
     `"skills": ["skills/"]` (and/or `"agents": "agents/"`).
   - `README.md` — what the plugin does and how to invoke it.
   - `skills/<name>/SKILL.md` — the skill, with YAML front matter (`name`, `description`) and the
     workflow body. Keep it **repo-agnostic** so it works in any consuming repository.
2. Add an entry for the plugin to the `plugins` array in
   [`.github/plugin/marketplace.json`](.github/plugin/marketplace.json).
3. Add a row to the **Skill Index** above.
4. Validate that all manifests are valid JSON and that each plugin `source` path resolves.

---

## 📄 License

MIT

## 🔗 Learn More

- [About Copilot CLI plugins](https://docs.github.com/copilot/concepts/agents/copilot-cli/about-cli-plugins)
- [Plugins & marketplaces how-to](https://docs.github.com/copilot/how-tos/copilot-cli/customize-copilot/plugins-marketplace)

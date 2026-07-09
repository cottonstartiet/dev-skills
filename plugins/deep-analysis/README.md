# deep-analysis

**Deep codebase/architecture analysis with a polished HTML report, for GitHub Copilot CLI.**

deep-analysis understands your prompt, performs an extensive multi-faceted analysis of a codebase
or topic, asks clarifying questions when the request is ambiguous, and produces a professional,
self-contained **light-theme HTML report** — then opens it in your browser.

## What It Analyzes

- **Architecture & structure** — boundaries, layers, component relationships, patterns in use
- **Code quality & patterns** — conventions, anti-patterns, separation of concerns, error handling
- **Dependencies & integration** — internal service dependencies, external systems, shared libraries
- **Implementation approach** (on request) — recommended approach, change surface, risks, sequencing

Every finding is grounded in real files, classes, and code — never fabricated.

## How to Invoke

- "analyze the authentication flow in the payments service"
- "architecture review of this repo"
- "produce an HTML report of the dependency graph"
- "visualize", "report", "analyze", "explore and summarize"

## Output

A self-contained HTML report (inline CSS, no external dependencies) saved under
`.deep-analysis-reports/` in the workspace and launched in the default browser.

See [`skills/deep-analysis/SKILL.md`](skills/deep-analysis/SKILL.md) for the full procedure and
report template.

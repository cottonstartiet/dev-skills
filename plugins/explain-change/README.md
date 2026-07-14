# explain-change

**Interactive HTML explanations of a code change, diff, branch, or PR — for GitHub Copilot CLI.**

explain-change turns a change set into a single, self-contained **interactive HTML page** that
teaches the reader what changed and why. It reconstructs the intent from the diff and surrounding
code, then writes an engaging walkthrough with diagrams, concrete toy examples, and a quiz — and
opens it in your browser.

## What It Produces

A single HTML file (inline CSS + JavaScript, no external dependencies) with four sections:

- **Background** — a deep, skippable beginner primer on the relevant system, then a narrow
  background directly tied to the change.
- **Intuition** — the core idea explained with toy data and reusable HTML diagrams (UI mocks and
  data-flow diagrams with example data).
- **Code** — a high-level, logically grouped walkthrough of the actual changes, grounded in real
  files and symbols.
- **Quiz** — five medium-difficulty, interactive multiple-choice questions with per-answer feedback.

## What It Does Not Do

- Never creates, merges, approves, or comments on PRs
- Never pushes, deploys, or modifies the change under explanation
- Never edits source files — it only reads code and writes one HTML file to a temporary,
  out-of-repo, date-prefixed location

## How to Invoke

- "explain this PR" / `/explain-change this PR`
- "walk me through the diff on my branch"
- "explain PR #128"
- "explain the last 3 commits"

## Output

A self-contained HTML file saved outside the repository (so it stays out of version control), with a
`YYYY-MM-DD-` filename prefix, then launched in your default browser.

See [`skills/explain-change/SKILL.md`](skills/explain-change/SKILL.md) for the full procedure and
HTML template.

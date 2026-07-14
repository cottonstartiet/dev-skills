---
name: explain-change
description: "Produces a rich, interactive HTML explanation of a code change, diff, branch, or PR. Use when: explain this change, explain this diff, explain this branch, explain this PR, walk me through these changes, onboard me to this code, teach me what this PR does. Generates a single self-contained HTML page with Background, Intuition (diagrams + toy examples), a Code walkthrough, and an interactive multiple-choice Quiz, then opens it in the browser."
argument-hint: "What to explain (e.g., 'this PR', 'the diff on my branch', 'PR #128', 'the last 3 commits')"
tools: ['ask_user', 'shell', 'grep', 'glob', 'view']
---

# Explain-Change — Interactive Code-Change Explanation Skill

## Purpose

Turn a code change — a working diff, a branch, a range of commits, or a pull request — into a
**rich, interactive HTML explanation** that a reader can learn from. The output is a single
self-contained HTML file that walks through the *why* and *how* of the change, with diagrams,
concrete toy examples, and an interactive quiz to confirm understanding. Open it in the browser
when done.

This skill is inspired by the idea of "explaining a diff like a teacher would" — deep enough for a
newcomer, sharp enough for a reviewer.

## When to Use

- User asks to **explain** a change, diff, branch, or PR
- User wants to **walk through** or **understand** what a set of changes does and why
- User wants to **onboard** someone (or themselves) to unfamiliar changes
- User says "explain this PR", "walk me through this diff", "teach me what changed"

## What It Does NOT Do

- It does **not** create, merge, approve, or comment on PRs
- It does **not** push, deploy, or modify the change under explanation
- It does **not** modify source files — it only reads the code and writes one HTML file to a
  temporary, out-of-repo location
- It does **not** embed secrets or fetch content from untrusted third parties

## Prerequisites

- A resolvable change set: uncommitted work (`git diff`), a branch vs. its base, a commit range,
  or a PR number/URL (needs the `gh` CLI authenticated for PR lookups).
- Read access to the surrounding source so the Background and Code sections are grounded in real code.

## How to Invoke

- `/explain-change this PR`
- "explain the diff on my branch"
- "walk me through PR #128"
- "explain the last 3 commits"

## Procedure

### Phase 1 — Resolve the Change Set

1. Determine exactly what to explain. Prefer the smallest precise selector:
   - **Uncommitted work**: `git --no-pager diff` (and `git --no-pager diff --staged`).
   - **Branch vs. base**: `git --no-pager diff <base>...<head>` (default base is the repo's
     default branch, e.g. `origin/main`). Confirm the base with the user if ambiguous.
   - **Commit range / last N commits**: `git --no-pager diff <rangeStart>..<rangeEnd>`.
   - **Pull request**: use `gh pr view <n> --json title,body,baseRefName,headRefName,commits` and
     `gh pr diff <n>` to fetch the diff and description.
   - **Note on `gh` CLI**: If `gh` is unavailable or unauthenticated, inform the user with the
     message: "The GitHub CLI (`gh`) is required to fetch PR data. Please run `gh auth login`
     and try again, or provide the diff manually."
2. If the request is ambiguous (no obvious diff, unclear base, multiple candidate branches/PRs),
   use `ask_user` to clarify **before** doing any analysis. Ask one focused question at a time,
   e.g. "Which change should I explain?" with concrete choices (current branch vs. `main`,
   staged changes, a specific PR).
3. Capture the raw diff, the list of changed files, and any PR title/description as your source
   of truth. Everything in the report must trace back to this change set and the surrounding code.
4. **Large diff handling**: If the diff exceeds ~2000 lines or ~30 files, use `ask_user` to confirm
   scope — offer to focus on a specific subdirectory or subset of files rather than attempting a
   full walkthrough of everything. This prevents silent truncation or an unmanageably large HTML file.

### Phase 2 — Understand the Change in Context

Explore broadly enough to explain the change to someone who has never seen this codebase.

- **Read the diff fully**, file by file. Group hunks by intent, not just by file order.
- **Explore the surrounding code** the diff touches: the functions/classes being modified, their
  callers, the data structures involved, and any tests. Use `grep`/`glob`/`view` (and subagents
  for large searches) to gather concrete evidence — file paths, symbols, signatures, line numbers.
- **Reconstruct the intent**: What problem does this change solve? What was the behavior before,
  and after? What is the core mechanism that makes it work?
- Collect small, concrete **toy examples** (sample inputs/outputs, a request that used to fail and
  now succeeds) that you can use to illustrate the essence in the Intuition section.

> Ground everything in real code. Never fabricate file paths, symbols, or behavior. If something is
> genuinely unclear from the code, say so in the report rather than inventing an explanation.

### Phase 3 — Generate the Interactive HTML

Produce **one self-contained HTML file** (inline CSS and JavaScript, no external CDNs/frameworks).
It must be a single long, responsive page with a section header per section and a table of contents
at the top — **do not** use tabs for the top-level structure.

Write with clarity and flow: engaging, plain-language prose with smooth transitions between
sections (in the spirit of a great technical explainer). Prefer short paragraphs, concrete
examples, and callouts over dense walls of text.

The page must contain these sections, in order:

1. **Background** — Explain the existing system relevant to this change. Provide a **deep
   background for beginners** (clearly marked as skippable for those already familiar), then a
   **narrow background** directly relevant to the change. Broadly reference the surrounding code.
2. **Intuition** — Explain the *core intuition* of the change: the essence, not every detail. Use
   concrete toy data and lean on diagrams/figures liberally.
3. **Code** — A high-level walkthrough of the actual changes, grouped/ordered so they build on each
   other logically (not just file-by-file). Reference real files and symbols; show representative
   `<pre>` code/diff snippets.
4. **Quiz** — Exactly **five** interactive multiple-choice questions of *medium* difficulty:
   hard enough that you must understand the substance of the change to answer, but not trick
   questions. Each option, when clicked, reveals whether it was correct and gives feedback.

#### Diagram & formatting rules

- **No ASCII diagrams.** Build diagrams from simple HTML/CSS (boxes, arrows via borders, flex/grid).
  Use HTML lists for lists.
- Pick a **small number of reusable diagram families** and reuse them throughout, e.g.:
  - a **simplified UI mock** to show user-facing changes, and
  - a **system/data-flow diagram** showing components and the data passing between them —
    **always include example data** on the flows.
- Use **callouts** for key concepts/definitions and important edge cases.
- Every code block must be a `<pre>` tag (or a div with `white-space: pre-wrap` in its CSS), so the
  browser preserves newlines. **Before saving, scan every code block and confirm** its container CSS
  includes `white-space: pre` or `pre-wrap`.
- Basic responsive styling so it reads on a phone.

#### Interactive quiz behavior (JavaScript)

- Render each question with its options as clickable buttons.
- On click: mark the chosen option correct/incorrect, reveal a short feedback explanation for that
  choice, and lock all options for that question so the user cannot change their answer. Keep all
  logic inline in a `<script>` tag.
- Keep the JS dependency-free (vanilla `addEventListener`, no frameworks/CDNs).

#### Starter template

Use this light-theme scaffold as a starting point and expand it. Keep it self-contained.

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{TITLE}} — Change Explanation</title>
  <style>
    :root {
      --bg: #ffffff; --bg-alt: #f8f9fa; --bg-code: #f1f3f5;
      --text: #212529; --text-muted: #6c757d; --border: #dee2e6;
      --accent: #0d6efd; --accent-light: #e7f1ff;
      --success: #198754; --danger: #dc3545; --warning: #ffc107;
      --shadow: 0 1px 3px rgba(0,0,0,0.08);
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
      background: var(--bg-alt); color: var(--text); line-height: 1.7; padding: 2rem; }
    .container { max-width: 900px; margin: 0 auto; }
    header.page { background: var(--bg); border-radius: 12px; padding: 2rem 2.5rem;
      box-shadow: var(--shadow); margin-bottom: 1.5rem; border-left: 5px solid var(--accent); }
    header.page h1 { font-size: 1.8rem; margin-bottom: .25rem; }
    header.page .meta { color: var(--text-muted); font-size: .9rem; }
    section { background: var(--bg); border-radius: 10px; padding: 1.5rem 2rem;
      box-shadow: var(--shadow); margin-bottom: 1.25rem; }
    section h2 { font-size: 1.35rem; color: var(--accent); border-bottom: 2px solid var(--accent-light);
      padding-bottom: .5rem; margin-bottom: 1rem; }
    h3 { margin: 1.2rem 0 .5rem; }
    p { margin: .6rem 0; }
    .toc { list-style: none; } .toc li { padding: .25rem 0; }
    .toc a { color: var(--accent); text-decoration: none; } .toc a:hover { text-decoration: underline; }
    pre { background: var(--bg-code); border: 1px solid var(--border); border-radius: 6px;
      padding: 1rem; overflow-x: auto; font-size: .85rem; white-space: pre; margin: .75rem 0; }
    code { font-family: 'Cascadia Code', 'Consolas', monospace; }
    .callout { border-left: 4px solid var(--accent); background: var(--accent-light);
      padding: .75rem 1rem; border-radius: 0 6px 6px 0; margin: 1rem 0; }
    .callout.warn { border-left-color: var(--warning); background: #fff8e1; }
    .skippable { border-left: 4px solid var(--border); background: var(--bg-alt);
      padding: .75rem 1rem; border-radius: 0 6px 6px 0; margin: 1rem 0; font-size: .95rem; }
    /* Reusable diagram families */
    .flow { display: flex; flex-wrap: wrap; align-items: center; gap: .5rem; margin: 1rem 0; }
    .node { border: 1.5px solid var(--accent); border-radius: 8px; padding: .5rem .8rem;
      background: var(--accent-light); font-size: .85rem; text-align: center; }
    .arrow { color: var(--text-muted); font-size: 1.2rem; }
    .arrow .data { display: block; font-size: .7rem; color: var(--accent); }
    .ui-mock { border: 1px solid var(--border); border-radius: 8px; padding: 1rem;
      background: var(--bg-alt); margin: 1rem 0; }
    /* Quiz */
    .q { border: 1px solid var(--border); border-radius: 8px; padding: 1rem 1.25rem; margin: 1rem 0; }
    .q .stem { font-weight: 600; margin-bottom: .75rem; }
    .opt { display: block; width: 100%; text-align: left; padding: .6rem .8rem; margin: .4rem 0;
      border: 1px solid var(--border); border-radius: 6px; background: var(--bg); cursor: pointer;
      font: inherit; }
    .opt:hover { background: var(--accent-light); }
    .opt.correct { border-color: var(--success); background: #d1e7dd; }
    .opt.incorrect { border-color: var(--danger); background: #f8d7da; }
    .fb { font-size: .88rem; color: var(--text-muted); margin-top: .5rem; display: none; }
    .fb.show { display: block; }
    @media (max-width: 600px) { body { padding: 1rem; } section { padding: 1.25rem; } }
  </style>
</head>
<body>
<div class="container">
  <header class="page">
    <h1>{{TITLE}}</h1>
    <div class="meta">{{DATE}} &bull; {{CHANGE_SELECTOR}} &bull; {{N}} files changed</div>
  </header>

  <section id="toc">
    <h2>Contents</h2>
    <ul class="toc">
      <li><a href="#background">1. Background</a></li>
      <li><a href="#intuition">2. Intuition</a></li>
      <li><a href="#code">3. Code walkthrough</a></li>
      <li><a href="#quiz">4. Quiz</a></li>
    </ul>
  </section>

  <section id="background"><h2>1. Background</h2>
    <div class="skippable"><strong>New here?</strong> Read this. Already familiar? Skip to the narrow background below.</div>
    <!-- deep beginner background, then narrow change-relevant background -->
  </section>

  <section id="intuition"><h2>2. Intuition</h2>
    <!-- essence + toy example + reusable diagrams -->
    <div class="flow">
      <div class="node">Client</div>
      <div class="arrow">&rarr;<span class="data">{ id: 42 }</span></div>
      <div class="node">Service</div>
    </div>
  </section>

  <section id="code"><h2>3. Code walkthrough</h2>
    <!-- grouped, logical walkthrough with real files + <pre> snippets -->
  </section>

  <section id="quiz"><h2>4. Quiz</h2>
    <div id="quiz-root"></div>
  </section>
</div>

<script>
  // Fill QUIZ with five medium-difficulty questions grounded in the change.
  const QUIZ = [
    { stem: "{{QUESTION}}",
      options: [
        { text: "{{OPTION_A}}", correct: false, fb: "{{WHY_WRONG}}" },
        { text: "{{OPTION_B}}", correct: true,  fb: "{{WHY_RIGHT}}" }
      ] }
  ];
  const root = document.getElementById('quiz-root');
  QUIZ.forEach((q, qi) => {
    const wrap = document.createElement('div'); wrap.className = 'q';
    const stem = document.createElement('div'); stem.className = 'stem';
    stem.textContent = (qi + 1) + '. ' + q.stem; wrap.appendChild(stem);
    q.options.forEach(o => {
      const btn = document.createElement('button'); btn.className = 'opt'; btn.textContent = o.text;
      const fb = document.createElement('div'); fb.className = 'fb';
      btn.addEventListener('click', () => {
        btn.classList.add(o.correct ? 'correct' : 'incorrect');
        fb.textContent = (o.correct ? '✓ Correct. ' : '✗ Not quite. ') + o.fb;
        fb.classList.add('show');
      });
      wrap.appendChild(btn); wrap.appendChild(fb);
    });
    root.appendChild(wrap);
  });
</script>
</body>
</html>
```

### Phase 4 — Save (out of the repo) and Launch

1. Save the file to a **temporary location outside the code repository** so it stays out of version
   control. Prefix the filename with today's date in `YYYY-MM-DD-` format so files stay
   time-sorted, e.g. `2026-07-13-explain-payments-retry.html`.
   - Windows: `Join-Path $env:TEMP '2026-07-13-explain-<slug>.html'`
   - macOS/Linux: `/tmp/2026-07-13-explain-<slug>.html`
2. Before saving, re-scan every code block and confirm each `<pre>`/code container preserves
   newlines (`white-space: pre` or `pre-wrap`).
3. Open it in the default browser:
   - Windows: `Start-Process "<full_path>"`
   - macOS: `open "<full_path>"`
   - Linux: `xdg-open "<full_path>"`
4. Tell the user the report is ready and print the full path.

## Guidelines

- **Grounded in code**: every claim traces to the diff or the surrounding code you read.
- **Teach, don't dump**: explain the essence first, then the details; smooth transitions between sections.
- **Ask before assuming**: if the change set or base is ambiguous, use `ask_user` first.
- **Balanced**: note trade-offs and edge cases, not just what the change does.
- **Self-contained output**: inline CSS + JS only — no CDNs, no frameworks, no network calls.
- **Read-only**: never modify source files or the change under explanation; only write the one HTML file.

## Tool Justification

- `ask_user` — clarify the change set/base when ambiguous, and confirm scope.
- `shell` — run read-only `git`/`gh` to fetch the diff, changed files, and PR metadata; save and
  open the HTML file.
- `grep`, `glob`, `view` — explore surrounding code to build grounded Background and Code sections.

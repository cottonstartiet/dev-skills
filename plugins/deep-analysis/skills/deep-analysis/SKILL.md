---
name: deep-analysis
description: "Performs deep codebase, architecture, or general-purpose analysis from a user prompt and generates a polished light-theme HTML report. Use when: analyze codebase, architecture review, generate report, produce HTML analysis, explore and report, visualize findings, dependency analysis, code quality report, implementation approach, system overview. Asks clarifying questions when the request is ambiguous, then explores extensively before producing results."
argument-hint: "Describe what you want analyzed (e.g., 'analyze the authentication flow in the payments service')"
---

# Deep-Analysis — Analysis & HTML Report Skill

## Purpose

Understand the user's prompt, perform an extensive multi-faceted analysis of the codebase or topic, ask clarifying questions when needed, and produce a professional light-theme HTML report with the results. Launch the report in the browser when done.

## When to Use

- User asks to **analyze** code, architecture, dependencies, patterns, or quality
- User wants an **HTML report** of findings
- User requests an **architecture review** or **system overview**
- User wants to understand an **implementation approach** for a feature
- User says "visualize", "report", "analyze", "explore and summarize"

## Procedure

### Phase 1 — Understand the Request

1. Read the user's prompt carefully. Identify:
   - **Subject**: What should be analyzed? (a service, folder, feature, pattern, concept)
   - **Depth**: Quick overview or deep investigation?
   - **Angle**: Architecture? Code quality? Dependencies? Implementation approach? Security? Performance?
2. If the request is ambiguous or broad, use the `ask-questions` tool to clarify:
   - What specific area or service to focus on
   - What aspects matter most (architecture, code patterns, quality, security, performance)
   - Whether to include implementation recommendations
3. Establish a clear analysis plan before proceeding.

### Phase 2 — Extensive Analysis

Perform a thorough exploration. Use **subagents** (with `agentName: "Explore"`) for large-scale searches to keep the main conversation clean. Gather:

#### Architecture & Structure
- Identify the project/service boundaries, layers, and dependencies
- Map component relationships (controllers → business logic → repositories)
- Identify key interfaces, contracts, and data flow paths
- Note architectural patterns in use (Clean Architecture, CQRS, Event-Driven, etc.)

#### Code Quality & Patterns
- Identify recurring patterns, conventions, and idioms
- Note any anti-patterns or inconsistencies
- Check for separation of concerns, DI usage, error handling
- Review naming conventions and code organization

#### Dependencies & Integration
- Map internal service-to-service dependencies
- Identify external system integrations (databases, queues, APIs)
- Note shared libraries and cross-cutting concerns

#### Implementation Approach (if requested)
- Outline a recommended approach for the requested feature/change
- Identify affected components and the change surface area
- Call out risks, prerequisites, and sequencing concerns

Collect **concrete evidence**: file paths, class names, method signatures, line numbers, code snippets. Every finding must be grounded in actual code — never fabricate.

### Phase 3 — Generate HTML Report

Generate the report using the template structure below. The report must be:
- **Self-contained**: All CSS inline, no external dependencies
- **Light theme**: Clean white/gray background with professional typography
- **Responsive**: Readable on any screen size
- **Information-rich**: Tables, code snippets, collapsible sections where appropriate

#### Report Structure

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>[Analysis Title] — Deep-Analysis Report</title>
  <style>
    /* ===== Light Theme Styles ===== */
    :root {
      --bg: #ffffff;
      --bg-alt: #f8f9fa;
      --bg-code: #f1f3f5;
      --text: #212529;
      --text-muted: #6c757d;
      --border: #dee2e6;
      --accent: #0d6efd;
      --accent-light: #e7f1ff;
      --success: #198754;
      --warning: #ffc107;
      --danger: #dc3545;
      --info: #0dcaf0;
      --shadow: 0 1px 3px rgba(0,0,0,0.08);
    }
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      background: var(--bg-alt); color: var(--text); line-height: 1.6; padding: 2rem;
    }
    .container { max-width: 1100px; margin: 0 auto; }
    .report-header {
      background: var(--bg); border-radius: 12px; padding: 2rem 2.5rem;
      box-shadow: var(--shadow); margin-bottom: 1.5rem; border-left: 5px solid var(--accent);
    }
    .report-header h1 { font-size: 1.75rem; margin-bottom: 0.25rem; }
    .report-header .meta { color: var(--text-muted); font-size: 0.9rem; }
    .card {
      background: var(--bg); border-radius: 10px; padding: 1.5rem 2rem;
      box-shadow: var(--shadow); margin-bottom: 1.25rem;
    }
    .card h2 { font-size: 1.25rem; margin-bottom: 1rem; color: var(--accent); border-bottom: 2px solid var(--accent-light); padding-bottom: 0.5rem; }
    .card h3 { font-size: 1.05rem; margin: 1rem 0 0.5rem; }
    table { width: 100%; border-collapse: collapse; margin: 0.75rem 0; font-size: 0.92rem; }
    th, td { text-align: left; padding: 0.6rem 0.75rem; border-bottom: 1px solid var(--border); }
    th { background: var(--bg-alt); font-weight: 600; position: sticky; top: 0; }
    tr:hover { background: var(--accent-light); }
    pre { background: var(--bg-code); border-radius: 6px; padding: 1rem; overflow-x: auto; font-size: 0.85rem; margin: 0.75rem 0; border: 1px solid var(--border); }
    code { font-family: 'Cascadia Code', 'Fira Code', 'Consolas', monospace; }
    .badge {
      display: inline-block; padding: 0.15rem 0.6rem; border-radius: 999px;
      font-size: 0.78rem; font-weight: 600; text-transform: uppercase;
    }
    .badge-success { background: #d1e7dd; color: #0f5132; }
    .badge-warning { background: #fff3cd; color: #664d03; }
    .badge-danger  { background: #f8d7da; color: #842029; }
    .badge-info    { background: #cff4fc; color: #055160; }
    .finding {
      border-left: 4px solid var(--border); padding: 0.75rem 1rem;
      margin: 0.75rem 0; background: var(--bg-alt); border-radius: 0 6px 6px 0;
    }
    .finding.high    { border-left-color: var(--danger); }
    .finding.medium  { border-left-color: var(--warning); }
    .finding.low     { border-left-color: var(--info); }
    .finding .title  { font-weight: 600; margin-bottom: 0.25rem; }
    .finding .file   { font-size: 0.82rem; color: var(--text-muted); font-family: monospace; }
    details { margin: 0.5rem 0; }
    details summary { cursor: pointer; font-weight: 500; padding: 0.4rem 0; color: var(--accent); }
    details summary:hover { text-decoration: underline; }
    .toc { list-style: none; padding: 0; }
    .toc li { padding: 0.3rem 0; }
    .toc a { color: var(--accent); text-decoration: none; }
    .toc a:hover { text-decoration: underline; }
    .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
    .stat-box { text-align: center; padding: 1rem; background: var(--bg-alt); border-radius: 8px; }
    .stat-box .number { font-size: 2rem; font-weight: 700; color: var(--accent); }
    .stat-box .label  { font-size: 0.85rem; color: var(--text-muted); }
    @media (max-width: 700px) { .grid-2 { grid-template-columns: 1fr; } body { padding: 1rem; } }
    .footer { text-align: center; color: var(--text-muted); font-size: 0.8rem; margin-top: 2rem; padding-top: 1rem; border-top: 1px solid var(--border); }
  </style>
</head>
<body>
<div class="container">

  <!-- HEADER -->
  <div class="report-header">
    <h1>{{TITLE}}</h1>
    <div class="meta">Generated on {{DATE}} &bull; Scope: {{SCOPE}} &bull; Deep-Analysis Report</div>
  </div>

  <!-- TABLE OF CONTENTS -->
  <div class="card">
    <h2>Table of Contents</h2>
    <ul class="toc">
      <li><a href="#summary">Executive Summary</a></li>
      <li><a href="#findings">Key Findings</a></li>
      <li><a href="#details">Detailed Analysis</a></li>
      <li><a href="#recommendations">Recommendations</a></li>
    </ul>
  </div>

  <!-- EXECUTIVE SUMMARY -->
  <div class="card" id="summary">
    <h2>Executive Summary</h2>
    <p>{{SUMMARY_TEXT}}</p>
    <div class="grid-2" style="margin-top:1rem;">
      <!-- Stat boxes showing key metrics -->
      <div class="stat-box">
        <div class="number">{{METRIC_1_VALUE}}</div>
        <div class="label">{{METRIC_1_LABEL}}</div>
      </div>
      <div class="stat-box">
        <div class="number">{{METRIC_2_VALUE}}</div>
        <div class="label">{{METRIC_2_LABEL}}</div>
      </div>
    </div>
  </div>

  <!-- KEY FINDINGS -->
  <div class="card" id="findings">
    <h2>Key Findings</h2>
    <!-- Repeat finding blocks as needed. Use class: high / medium / low -->
    <div class="finding medium">
      <div class="title">{{FINDING_TITLE}}</div>
      <div class="file">{{FILE_PATH}}</div>
      <p>{{FINDING_DESCRIPTION}}</p>
    </div>
  </div>

  <!-- DETAILED ANALYSIS -->
  <div class="card" id="details">
    <h2>Detailed Analysis</h2>
    <!-- Use sub-sections, tables, code blocks, collapsible details as appropriate -->
    <h3>{{SECTION_TITLE}}</h3>
    <p>{{SECTION_CONTENT}}</p>
    <table>
      <thead><tr><th>Component</th><th>Type</th><th>Notes</th></tr></thead>
      <tbody>
        <tr><td>{{NAME}}</td><td>{{TYPE}}</td><td>{{NOTES}}</td></tr>
      </tbody>
    </table>
    <details>
      <summary>View code snippet</summary>
      <pre><code>{{CODE_SNIPPET}}</code></pre>
    </details>
  </div>

  <!-- RECOMMENDATIONS -->
  <div class="card" id="recommendations">
    <h2>Recommendations</h2>
    <ol>
      <li><strong>{{REC_TITLE}}</strong>: {{REC_DETAIL}}</li>
    </ol>
  </div>

  <div class="footer">Deep-Analysis Report &mdash; Generated by GitHub Copilot</div>
</div>
</body>
</html>
```

#### Customization Rules for the Template

- Replace all `{{...}}` placeholders with actual analysis data
- Add or remove stat boxes, finding blocks, table rows, and sections as needed
- Use severity badges: `<span class="badge badge-danger">High</span>`, `badge-warning` for Medium, `badge-info` for Low, `badge-success` for Good
- Add more `<details>` blocks for long code snippets to keep the report scannable
- Add more `<div class="card">` sections for additional analysis areas (e.g., Dependencies, Security, Performance)
- Keep the light theme CSS unchanged

### Phase 4 — Save and Launch

1. Save the HTML report to a temporary location:
   - Path: `{{workspace_root}}/.deep-analysis-reports/{{report-name}}.html`
   - Use a descriptive filename like `payments-service-architecture-review.html`
2. Launch the report in the default browser:
   - On Windows: `Start-Process "{{full_path_to_html}}"`
   - On macOS: `open "{{full_path_to_html}}"`
   - On Linux: `xdg-open "{{full_path_to_html}}"`
3. Confirm to the user that the report is ready and where it was saved.

## Guidelines

- **Grounded in code**: Every finding must reference real files, classes, or patterns found during analysis. Never fabricate file paths or code.
- **Ask before assuming**: If the user's request could go multiple directions, ask 1-3 targeted questions before starting analysis.
- **Use subagents for scale**: For large codebases, use the `Explore` subagent to search broadly, then read specific files yourself for detail.
- **Balanced output**: Don't just list problems — also highlight what's done well.
- **Proportional depth**: Scale the analysis depth to the scope. A single-service review needs less than a full-system audit.
- **No external dependencies in HTML**: The report must be fully self-contained with inline CSS. No CDN links, no JavaScript frameworks.
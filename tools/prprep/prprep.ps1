<#
.SYNOPSIS
    Draft a pull request description from the current branch diff.

.DESCRIPTION
    Summarizes commits and changed files from the current branch versus a base
    branch, then prints a Markdown PR description draft and optionally writes it
    to PR_DESCRIPTION.md at the repository root.

    Safety: prprep is read-only for git state. It never creates PRs, never
    pushes, and never changes branches. The only write it performs is the draft
    description file unless -NoWrite is used.

.EXAMPLE
    prprep draft
.EXAMPLE
    prprep draft -BaseBranch main -Out docs\PR.md
.EXAMPLE
    prprep draft -NoWrite
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('draft', 'help')]
    [string]$Command = 'draft',

    [string]$BaseBranch = 'main',

    [string]$Out,

    [switch]$NoWrite
)

$ErrorActionPreference = 'Stop'

$script:CommitTypes = @('feat', 'fix', 'docs', 'refactor', 'test', 'chore', 'perf', 'build', 'ci', 'style', 'revert')

# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

function Invoke-Git {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$GitArgs,
        [switch]$AllowFail
    )
    $output = & git @GitArgs 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFail) {
        throw "git $($GitArgs -join ' ') failed (exit $code): $output"
    }
    [pscustomobject]@{ ExitCode = $code; Output = ($output | Out-String).TrimEnd() }
}

function Write-Info { param([string]$Message) Write-Host $Message }
function Write-Ok { param([string]$Message) Write-Host "OK  $Message" -ForegroundColor Green }
function Write-Warn2 { param([string]$Message) Write-Host "WARN  $Message" -ForegroundColor Yellow }

function Fail {
    param([string]$Message)
    Write-Host "ERROR  $Message" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Repository helpers
# ---------------------------------------------------------------------------

function Get-RepoRoot {
    $r = Invoke-Git -GitArgs @('rev-parse', '--show-toplevel') -AllowFail
    if ($r.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($r.Output)) {
        Fail "Not inside a git repository."
    }
    ([System.IO.Path]::GetFullPath($r.Output)).Replace('/', '\').TrimEnd('\')
}

function Get-CurrentBranch {
    $r = Invoke-Git -GitArgs @('symbolic-ref', '--quiet', '--short', 'HEAD') -AllowFail
    if ($r.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($r.Output)) { return $r.Output }
    $null
}

function Resolve-BaseRef {
    param([Parameter(Mandatory)][string]$Branch)

    $local = Invoke-Git -GitArgs @('rev-parse', '--verify', '--quiet', "$Branch^{commit}") -AllowFail
    if ($local.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($local.Output)) { return $Branch }

    $remote = Invoke-Git -GitArgs @('rev-parse', '--verify', '--quiet', "origin/$Branch^{commit}") -AllowFail
    if ($remote.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($remote.Output)) { return "origin/$Branch" }

    Fail "Base branch '$Branch' does not exist locally or as 'origin/$Branch'. Fetch/checkout it first or pass -BaseBranch."
}

function ConvertTo-MarkdownSafe {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    $Value.Replace('|', '\|')
}

# ---------------------------------------------------------------------------
# Draft building
# ---------------------------------------------------------------------------

function Get-DraftTitle {
    param(
        [AllowNull()][string]$Branch,
        [Parameter(Mandatory)][object[]]$Commits
    )

    if (-not [string]::IsNullOrWhiteSpace($Branch)) {
        $leaf = (($Branch -split '/') | Select-Object -Last 1)
        if (-not [string]::IsNullOrWhiteSpace($leaf)) {
            $words = ($leaf -replace '[-_]+', ' ').Trim()
            if (-not [string]::IsNullOrWhiteSpace($words)) {
                return (Get-Culture).TextInfo.ToTitleCase($words.ToLowerInvariant())
            }
        }
    }

    if ($Commits.Count -gt 0) {
        $subject = [string]$Commits[0].Subject
        if ($subject -match '^[A-Za-z]+(\([^)]+\))?(!)?:\s*(.+)$') { return $Matches[3] }
        return $subject
    }

    'PR draft'
}

function Parse-CommitSubject {
    param([Parameter(Mandatory)][string]$Subject)

    if ($Subject -match '^(?<type>[A-Za-z]+)(\([^)]+\))?(!)?:\s*(?<desc>.+)$') {
        $type = $Matches['type'].ToLowerInvariant()
        if ($script:CommitTypes -contains $type) {
            return [pscustomobject]@{ Type = $type; Text = $Matches['desc'] }
        }
    }
    [pscustomobject]@{ Type = 'Other'; Text = $Subject }
}

function Get-Commits {
    param([Parameter(Mandatory)][string]$Range)

    $log = (Invoke-Git -GitArgs @('log', '--reverse', '--pretty=format:%H%x1f%s', $Range)).Output
    $commits = @()
    if ([string]::IsNullOrWhiteSpace($log)) { return $commits }

    foreach ($line in ($log -split "`n")) {
        $parts = $line -split ([char]0x1f), 2
        if ($parts.Count -lt 2) { continue }
        $parsed = Parse-CommitSubject -Subject $parts[1]
        $commits += [pscustomobject]@{
            Hash    = $parts[0]
            Short   = $parts[0].Substring(0, [Math]::Min(7, $parts[0].Length))
            Subject = $parts[1]
            Type    = $parsed.Type
            Text    = $parsed.Text
        }
    }
    $commits
}

function Get-ChangedFiles {
    param([Parameter(Mandatory)][string]$Range)

    $diff = (Invoke-Git -GitArgs @('diff', '--numstat', $Range)).Output
    $files = @()
    if ([string]::IsNullOrWhiteSpace($diff)) { return $files }

    foreach ($line in ($diff -split "`n")) {
        $parts = $line -split "`t", 3
        if ($parts.Count -lt 3) { continue }
        $files += [pscustomobject]@{
            Added   = $parts[0]
            Deleted = $parts[1]
            Path    = $parts[2]
        }
    }
    $files
}

function Get-IntSum {
    param([Parameter(Mandatory)][object[]]$Items, [Parameter(Mandatory)][string]$Property)

    $sum = 0
    foreach ($item in $Items) {
        $n = 0
        if ([int]::TryParse([string]$item.$Property, [ref]$n)) { $sum += $n }
    }
    $sum
}

function Test-IsTestPath {
    param([Parameter(Mandatory)][string]$Path)
    $Path -match '(?i)(test|spec|\.Tests\.)'
}

function New-PrDraft {
    param(
        [Parameter(Mandatory)][string]$BaseRef,
        [Parameter(Mandatory)][string]$MergeBase,
        [AllowNull()][string]$Branch,
        [Parameter(Mandatory)][object[]]$Commits,
        [Parameter(Mandatory)][object[]]$Files
    )

    $groups = [ordered]@{}
    foreach ($type in $script:CommitTypes) { $groups[$type] = @() }
    $groups['Other'] = @()
    foreach ($commit in $Commits) { $groups[$commit.Type] += $commit }

    $baseShort = (Invoke-Git -GitArgs @('rev-parse', '--short', $BaseRef)).Output
    $headShort = (Invoke-Git -GitArgs @('rev-parse', '--short', 'HEAD')).Output
    $mergeShort = (Invoke-Git -GitArgs @('rev-parse', '--short', $MergeBase)).Output
    $title = Get-DraftTitle -Branch $Branch -Commits $Commits
    $added = Get-IntSum -Items $Files -Property 'Added'
    $deleted = Get-IntSum -Items $Files -Property 'Deleted'
    $testFiles = @($Files | Where-Object { Test-IsTestPath -Path $_.Path })
    $docsOnly = ($Files.Count -gt 0 -and @($Files | Where-Object { $_.Path -notmatch '(?i)(^|/)(docs?)/|\.md$' }).Count -eq 0)

    $lines = @()
    $lines += "# $title"
    $lines += ""
    $lines += "## Summary"
    $lines += "- Base: ``$BaseRef`` ($baseShort)"
    $lines += "- Head: ``HEAD`` ($headShort)"
    $lines += "- Compare range: ``$mergeShort..HEAD``"
    $lines += "- Commits: $($Commits.Count)"
    $lines += "- Files changed: $($Files.Count) (+$added/-$deleted)"
    $lines += ""
    $lines += "## Changes"
    foreach ($key in $groups.Keys) {
        if ($groups[$key].Count -eq 0) { continue }
        $lines += "### $key"
        foreach ($commit in $groups[$key]) {
            $lines += "- $($commit.Text) (``$($commit.Short)``)"
        }
        $lines += ""
    }
    if (($groups.Keys | Where-Object { $groups[$_].Count -gt 0 } | Measure-Object).Count -eq 0) {
        $lines += "- No commit details found."
        $lines += ""
    }

    $lines += "## Files changed"
    if ($Files.Count -eq 0) {
        $lines += "- No file changes found in the commit range."
    }
    else {
        $lines += "| File | + | - |"
        $lines += "|---|---:|---:|"
        foreach ($file in $Files) {
            $path = ConvertTo-MarkdownSafe -Value $file.Path
            $lines += "| $path | $($file.Added) | $($file.Deleted) |"
        }
    }
    $lines += ""
    $lines += "## Testing/Checklist"
    $lines += "### Risk heuristics"
    $lines += "- Files changed: $($Files.Count)"
    $lines += "- Test/spec files touched: $(if ($testFiles.Count -gt 0) { "Yes ($($testFiles.Count))" } else { 'No' })"
    $lines += "- Large change (>20 files): $(if ($Files.Count -gt 20) { 'Yes' } else { 'No' })"
    $lines += "- Docs-only change: $(if ($docsOnly) { 'Yes' } else { 'No' })"
    $lines += ""
    $lines += "### Review checklist"
    $lines += "- [ ] Confirm the summary matches the intended scope."
    $lines += "- [ ] Review changed files and risk heuristics."
    $lines += "- [ ] Run relevant tests locally."
    $lines += "- [ ] Check for secrets or unexpected config changes."
    $lines += "- [ ] Confirm no PR was created by ``prprep``."

    ($lines -join "`n") + "`n"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

function Invoke-Draft {
    $repoRoot = Get-RepoRoot
    $currentBranch = Get-CurrentBranch
    $baseRef = Resolve-BaseRef -Branch $BaseBranch

    if ($currentBranch -eq $BaseBranch -or $currentBranch -eq $baseRef) {
        Write-Info "Current branch '$currentBranch' is the base branch '$BaseBranch'; no PR draft needed."
        return
    }

    $mergeBase = (Invoke-Git -GitArgs @('merge-base', 'HEAD', $baseRef)).Output
    if ([string]::IsNullOrWhiteSpace($mergeBase)) {
        Fail "Could not compute merge-base between HEAD and '$baseRef'."
    }

    $range = "$mergeBase..HEAD"
    $ahead = [int](Invoke-Git -GitArgs @('rev-list', '--count', $range)).Output
    if ($ahead -eq 0) {
        Write-Info "No commits ahead of '$BaseBranch'; no PR draft written."
        return
    }

    $commits = @(Get-Commits -Range $range)
    $files = @(Get-ChangedFiles -Range $range)
    $draft = New-PrDraft -BaseRef $baseRef -MergeBase $mergeBase -Branch $currentBranch -Commits $commits -Files $files

    Write-Info $draft

    if ($NoWrite) {
        Write-Ok "Printed PR draft only (-NoWrite); no file was written."
        return
    }

    $target = if ([string]::IsNullOrWhiteSpace($Out)) {
        Join-Path $repoRoot 'PR_DESCRIPTION.md'
    }
    elseif ([System.IO.Path]::IsPathRooted($Out)) {
        $Out
    }
    else {
        Join-Path $repoRoot $Out
    }

    $parent = Split-Path -Parent $target
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $target -Value $draft -Encoding utf8
    Write-Ok "Wrote PR draft to $target"
    Write-Info "Review checklist: summary, files changed, tests, secrets/config, and risk heuristics."
}

function Invoke-Help {
    Write-Info @"
prprep.ps1 - draft a PR description from the current branch diff

Usage: prprep [draft] [options]

Commands:
  draft                         Print a PR description draft and write PR_DESCRIPTION.md
  help                          Show this help

Options:
  -BaseBranch <branch>          Base branch to compare against (default: main)
  -Out <path>                   Write target (default: PR_DESCRIPTION.md at repo root)
  -NoWrite                      Print only; do not write a file

Safety:
  prprep never creates a PR, never pushes, and never changes git branches or state.
"@
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

switch ($Command) {
    'draft' { Invoke-Draft }
    default { Invoke-Help }
}

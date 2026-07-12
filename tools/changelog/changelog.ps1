<#
.SYNOPSIS
    Generate a changelog from Conventional Commits. Installed as the 'changelog' command.

.DESCRIPTION
    Builds a Keep a Changelog-style block from Conventional Commit subjects in git history.
    By default it prints the generated block to stdout and writes nothing. With -Write, it
    prepends the block to CHANGELOG.md (or -Out <path>) without tagging, committing,
    pushing, or publishing anything.

.EXAMPLE
    changelog generate
.EXAMPLE
    changelog generate -Version 1.2.0 -Write
.EXAMPLE
    changelog generate -From v1.1.0 -To HEAD -Out docs\CHANGELOG.md -Write
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('generate', 'help')]
    [string]$Command = 'generate',

    [string]$From,
    [string]$To = 'HEAD',
    [string]$Version,
    [switch]$Write,
    [string]$Out = 'CHANGELOG.md'
)

$ErrorActionPreference = 'Stop'

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
# Git history helpers
# ---------------------------------------------------------------------------

function Test-InGitRepository {
    $r = Invoke-Git -GitArgs @('rev-parse', '--is-inside-work-tree') -AllowFail
    if ($r.ExitCode -ne 0 -or $r.Output -ne 'true') {
        Fail 'Not inside a git working tree.'
    }
}

function Get-LatestTag {
    $r = Invoke-Git -GitArgs @('describe', '--tags', '--abbrev=0') -AllowFail
    if ($r.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($r.Output)) { return $r.Output.Trim() }
    $null
}

function Get-LogRangeArgs {
    $toRef = if ([string]::IsNullOrWhiteSpace($To)) { 'HEAD' } else { $To.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($From)) {
        return @("$($From.Trim())..$toRef")
    }

    $latestTag = Get-LatestTag
    if (-not [string]::IsNullOrWhiteSpace($latestTag)) {
        return @("$latestTag..$toRef")
    }

    # With no tags, include the whole reachable history up to -To/HEAD.
    @($toRef)
}

function Get-CommitBody {
    param([Parameter(Mandatory)][string]$Hash)
    (Invoke-Git -GitArgs @('show', '-s', '--format=%B', $Hash)).Output
}

function Get-CommitsForChangelog {
    $rangeArgs = @(Get-LogRangeArgs)
    $gitArgs = @('log') + $rangeArgs + @('--pretty=format:%H%x09%s')
    $r = Invoke-Git -GitArgs $gitArgs -AllowFail
    if ($r.ExitCode -ne 0) {
        Fail "Could not read git log for range '$($rangeArgs -join ' ')': $($r.Output)"
    }
    if ([string]::IsNullOrWhiteSpace($r.Output)) { return @() }

    $commits = @()
    foreach ($line in ($r.Output -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $tab = $line.IndexOf("`t")
        if ($tab -lt 1) { continue }
        $hash = $line.Substring(0, $tab)
        $subject = $line.Substring($tab + 1).Trim()
        $short = if ($hash.Length -ge 7) { $hash.Substring(0, 7) } else { $hash }
        $commits += [pscustomobject]@{
            Hash    = $hash
            Short   = $short
            Subject = $subject
            Body    = (Get-CommitBody -Hash $hash)
        }
    }
    $commits
}

# ---------------------------------------------------------------------------
# Conventional Commit parsing
# ---------------------------------------------------------------------------

function Get-SectionForType {
    param([Parameter(Mandatory)][string]$Type)
    switch ($Type.ToLowerInvariant()) {
        'feat' { 'Added'; break }
        'fix' { 'Fixed'; break }
        { $_ -in @('refactor', 'perf', 'build', 'ci', 'style', 'chore') } { 'Changed'; break }
        'docs' { 'Documentation'; break }
        'revert' { 'Reverted'; break }
        default { 'Other'; break }
    }
}

function Get-BreakingChangeNote {
    param(
        [Parameter(Mandatory)]$Commit,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][bool]$SubjectIsBreaking
    )

    $marker = [regex]::Match($Commit.Body, '(?ims)^BREAKING[ -]CHANGE:\s*(.+?)(?:\r?\n\r?\n|\z)')
    if ($marker.Success) {
        $noteLines = $marker.Groups[1].Value -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $note = ($noteLines -join ' ')
        if (-not [string]::IsNullOrWhiteSpace($note)) { return $note }
    }

    if ($SubjectIsBreaking) { return $Description }
    $null
}

function New-SectionMap {
    $map = [ordered]@{}
    foreach ($section in @('BREAKING CHANGES', 'Added', 'Fixed', 'Changed', 'Documentation', 'Reverted', 'Other')) {
        $map[$section] = [System.Collections.Generic.List[string]]::new()
    }
    $map
}

function Build-ChangelogBlock {
    $sections = New-SectionMap
    foreach ($commit in (Get-CommitsForChangelog)) {
        $subject = $commit.Subject
        $section = 'Other'
        $description = $subject
        $subjectBreaking = $false

        $m = [regex]::Match($subject, '^(?<type>[A-Za-z]+)(?:\([^)]+\))?(?<breaking>!)?:\s*(?<desc>.+)$')
        if ($m.Success) {
            $type = $m.Groups['type'].Value
            $section = Get-SectionForType -Type $type
            $description = $m.Groups['desc'].Value.Trim()
            $subjectBreaking = $m.Groups['breaking'].Success
        }

        $line = '- {0} (`{1}`)' -f $description, $commit.Short
        $sections[$section].Add($line) | Out-Null

        $breakingNote = Get-BreakingChangeNote -Commit $commit -Description $description -SubjectIsBreaking $subjectBreaking
        if (-not [string]::IsNullOrWhiteSpace($breakingNote)) {
            $sections['BREAKING CHANGES'].Add(('- {0} (`{1}`)' -f $breakingNote, $commit.Short)) | Out-Null
        }
    }

    $heading = if ([string]::IsNullOrWhiteSpace($Version)) {
        '## [Unreleased]'
    }
    else {
        '## [{0}] - {1}' -f $Version.Trim(), (Get-Date -Format 'yyyy-MM-dd')
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($heading) | Out-Null
    $lines.Add('') | Out-Null

    $wroteSection = $false
    foreach ($section in $sections.Keys) {
        if ($sections[$section].Count -eq 0) { continue }
        if ($wroteSection) { $lines.Add('') | Out-Null }
        $lines.Add("### $section") | Out-Null
        foreach ($entry in $sections[$section]) { $lines.Add($entry) | Out-Null }
        $wroteSection = $true
    }

    if (-not $wroteSection) { $lines.Add('_No changes._') | Out-Null }

    ($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
}

# ---------------------------------------------------------------------------
# File writing
# ---------------------------------------------------------------------------

function Resolve-OutPath {
    if ([System.IO.Path]::IsPathRooted($Out)) { return $Out }
    Join-Path (Get-Location) $Out
}

function New-StandardChangelogContent {
    param([Parameter(Mandatory)][string]$Block)
    "# Changelog`n`nAll notable changes to this project will be documented in this file.`n`n$($Block.TrimEnd())`n"
}

function Write-ChangelogFile {
    param([Parameter(Mandatory)][string]$Block)

    $target = Resolve-OutPath
    $parent = Split-Path -Parent $target
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    if (-not (Test-Path -LiteralPath $target)) {
        Set-Content -LiteralPath $target -Value (New-StandardChangelogContent -Block $Block) -NoNewline -Encoding utf8
        Write-Ok "Wrote changelog to $target"
        return
    }

    $existing = Get-Content -LiteralPath $target -Raw
    if ([string]::IsNullOrWhiteSpace($existing)) {
        $newContent = New-StandardChangelogContent -Block $Block
    }
    else {
        $entry = [regex]::Match($existing, '(?m)^## \[')
        if ($entry.Success) {
            $prefix = $existing.Substring(0, $entry.Index).TrimEnd()
            $suffix = $existing.Substring($entry.Index).TrimStart()
            $newContent = "$prefix`n`n$($Block.TrimEnd())`n`n$suffix"
        }
        else {
            $newContent = "$($existing.TrimEnd())`n`n$($Block.TrimEnd())`n"
        }
    }

    Set-Content -LiteralPath $target -Value ($newContent.TrimEnd() + "`n") -NoNewline -Encoding utf8
    Write-Ok "Wrote changelog to $target"
}

function Invoke-Generate {
    Test-InGitRepository
    $block = Build-ChangelogBlock
    if ($Write) { Write-ChangelogFile -Block $block }
    else { Write-Info $block.TrimEnd() }
}

function Invoke-Help {
    Write-Info @"
changelog.ps1 - Conventional Commits changelog generator (installed as 'changelog')

Usage: changelog [generate] [options]
       changelog help

Commands:
  generate                                  Generate a changelog block (default)
  help                                      Show this help

Options:
  -From <ref>                               Start after this ref (uses <from>..<to>)
  -To <ref>                                 End at this ref (default: HEAD)
  -Version <x>                              Use heading: ## [x] - yyyy-MM-dd
  -Write                                    Prepend to a changelog file instead of printing only
  -Out <path>                               Changelog file path for -Write (default: CHANGELOG.md)

Defaults:
  Without -From, the range starts after the latest reachable tag. If no tags exist,
  the whole reachable history is included. This tool never tags, commits, pushes, or publishes.
"@
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

switch ($Command) {
    'generate' { Invoke-Generate }
    default    { Invoke-Help }
}

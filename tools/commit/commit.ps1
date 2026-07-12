<#
.SYNOPSIS
    Conventional Commit helper. Installed as the 'commit' command.

.DESCRIPTION
    Builds a Conventional Commit message, validates it, and creates a local git
    commit from staged changes. It never pushes, never creates branches, and by
    default commits only what is already staged.

.EXAMPLE
    commit -Type feat -Scope api -Subject "add user lookup"
.EXAMPLE
    commit -Type fix -Subject "handle missing profile" -Body "Return 404 instead of 500."
.EXAMPLE
    commit -Type refactor -Scope config -Subject "rename provider" -Breaking -BreakingDescription "Config key providerName replaces name."
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('create', 'help')]
    [string]$Command = 'create',

    [string]$Type,
    [string]$Scope,
    [string]$Subject,
    [string]$Body,
    [switch]$Breaking,
    [string]$BreakingDescription,
    [switch]$AddAll
)

$ErrorActionPreference = 'Stop'

$script:ValidTypes = @('feat', 'fix', 'docs', 'refactor', 'test', 'chore', 'perf', 'build', 'ci', 'style', 'revert')

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

function Test-CanPrompt {
    try { return ((-not [Console]::IsInputRedirected) -and [Environment]::UserInteractive) }
    catch { return $false }
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

function Assert-GitRepo {
    $r = Invoke-Git -GitArgs @('rev-parse', '--is-inside-work-tree') -AllowFail
    if ($r.ExitCode -ne 0 -or $r.Output.Trim() -ne 'true') {
        Fail "Not inside a git working tree."
    }
}

function Resolve-CommitType {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { Fail "A commit -Type is required (valid types: $($script:ValidTypes -join ', '))." }
    $resolved = $Value.Trim()
    if ([System.Array]::IndexOf([string[]]$script:ValidTypes, $resolved) -lt 0) {
        Fail "Invalid commit type '$resolved'. Valid types: $($script:ValidTypes -join ', ')."
    }
    $resolved
}

function Resolve-Scope {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $resolved = $Value.Trim()
    if ($resolved -match '[\r\n]') { Fail "Scope must be a single line." }
    if ($resolved -match '[()]') { Fail "Scope must not contain parentheses." }
    $resolved
}

function Resolve-Subject {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { Fail "A non-empty -Subject is required." }
    $resolved = $Value.Trim()
    if ($resolved -match '[\r\n]') { Fail "Subject must be a single line." }
    if ($resolved.EndsWith('.')) {
        $resolved = $resolved.TrimEnd('.').TrimEnd()
        Write-Warn2 "Subject ended with a period; using: $resolved"
    }
    if ([string]::IsNullOrWhiteSpace($resolved)) { Fail "A non-empty -Subject is required." }
    $resolved
}

function New-CommitHeader {
    param(
        [Parameter(Mandatory)][string]$CommitType,
        [string]$CommitScope,
        [Parameter(Mandatory)][string]$CommitSubject,
        [bool]$IsBreaking
    )

    $prefix = if ($CommitScope) { "$CommitType($CommitScope)" } else { $CommitType }
    if ($IsBreaking) { $prefix = "$prefix!" }
    $header = "${prefix}: $CommitSubject"
    if ($header.Length -gt 72) {
        Fail "Commit header is $($header.Length) characters; maximum is 72. Shorten -Subject or -Scope."
    }
    $header
}

function Test-HasStagedChanges {
    $r = Invoke-Git -GitArgs @('diff', '--cached', '--quiet', '--exit-code') -AllowFail
    if ($r.ExitCode -eq 1) { return $true }
    if ($r.ExitCode -eq 0) { return $false }
    throw "git diff --cached failed (exit $($r.ExitCode)): $($r.Output)"
}

function Resolve-Inputs {
    $canPrompt = Test-CanPrompt
    $resolvedType = $Type
    $resolvedScope = $Scope
    $resolvedSubject = $Subject
    $resolvedBody = $Body
    $resolvedBreaking = $Breaking.IsPresent
    $resolvedBreakingDescription = $BreakingDescription

    if (([string]::IsNullOrWhiteSpace($resolvedType) -or [string]::IsNullOrWhiteSpace($resolvedSubject)) -and -not $canPrompt) {
        if ([string]::IsNullOrWhiteSpace($resolvedType)) {
            Fail "Missing -Type in non-interactive mode. Valid types: $($script:ValidTypes -join ', ')."
        }
        Fail "A non-empty -Subject is required in non-interactive mode."
    }

    if ([string]::IsNullOrWhiteSpace($resolvedType)) {
        Write-Info "Valid types: $($script:ValidTypes -join ', ')"
        do {
            $resolvedType = Read-Host "Type"
            if ([System.Array]::IndexOf([string[]]$script:ValidTypes, $resolvedType) -lt 0) {
                Write-Warn2 "Invalid type '$resolvedType'."
                $resolvedType = $null
            }
        } while ([string]::IsNullOrWhiteSpace($resolvedType))
    }

    if ([string]::IsNullOrWhiteSpace($resolvedScope) -and $canPrompt) {
        $resolvedScope = Read-Host "Scope (optional)"
    }
    if ([string]::IsNullOrWhiteSpace($resolvedSubject)) {
        if (-not $canPrompt) { Fail "A non-empty -Subject is required in non-interactive mode." }
        $resolvedSubject = Read-Host "Subject"
    }
    if ([string]::IsNullOrWhiteSpace($resolvedBody) -and $canPrompt) {
        $resolvedBody = Read-Host "Body (optional)"
    }
    if (-not $resolvedBreaking -and $canPrompt) {
        $answer = Read-Host "Breaking change? [y/N]"
        $resolvedBreaking = ($answer -match '^\s*y')
    }
    if ($resolvedBreaking -and [string]::IsNullOrWhiteSpace($resolvedBreakingDescription) -and $canPrompt) {
        $resolvedBreakingDescription = Read-Host "Breaking change description (optional)"
    }

    [pscustomobject]@{
        Type                = (Resolve-CommitType -Value $resolvedType)
        Scope               = (Resolve-Scope -Value $resolvedScope)
        Subject             = (Resolve-Subject -Value $resolvedSubject)
        Body                = if ([string]::IsNullOrWhiteSpace($resolvedBody)) { $null } else { $resolvedBody.Trim() }
        Breaking            = [bool]$resolvedBreaking
        BreakingDescription = if ([string]::IsNullOrWhiteSpace($resolvedBreakingDescription)) { $null } else { $resolvedBreakingDescription.Trim() }
    }
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

function Invoke-Create {
    Assert-GitRepo

    if (-not $Breaking -and -not [string]::IsNullOrWhiteSpace($BreakingDescription)) {
        Fail "-BreakingDescription requires -Breaking."
    }

    $input = Resolve-Inputs
    $header = New-CommitHeader -CommitType $input.Type -CommitScope $input.Scope -CommitSubject $input.Subject -IsBreaking $input.Breaking

    if ($AddAll) {
        Invoke-Git -GitArgs @('add', '-A') | Out-Null
    }
    if (-not (Test-HasStagedChanges)) {
        Fail "Nothing staged to commit. Stage changes first, or pass -AddAll."
    }

    $args = @('commit', '-m', $header)
    if ($input.Body) { $args += @('-m', $input.Body) }
    if ($input.Breaking) {
        $description = if ($input.BreakingDescription) { $input.BreakingDescription } else { $input.Subject }
        $args += @('-m', "BREAKING CHANGE: $description")
    }

    Invoke-Git -GitArgs $args | Out-Null
    Write-Ok "Committed: $header"
}

function Invoke-Help {
    Write-Info @"
commit.ps1 - Conventional Commit helper (installed as 'commit')

Usage: commit [create] -Type <type> -Subject <subject> [options]
       commit help

Commands:
  create                                      Build a Conventional Commit and commit locally
  help                                        Show this help

Options:
  -Type <type>                                Required in automation. One of: $($script:ValidTypes -join ', ')
  -Scope <scope>                              Optional commit scope
  -Subject <subject>                          Required in automation; header must be <= 72 chars
  -Body <body>                                Optional commit body
  -Breaking                                   Add ! to the header and a BREAKING CHANGE footer
  -BreakingDescription <text>                 Footer text; requires -Breaking
  -AddAll                                     Run git add -A before committing

Examples:
  commit -Type feat -Scope api -Subject "add user lookup"
  commit -Type fix -Subject "handle missing profile" -Body "Return 404 instead of 500."
  commit -Type refactor -Scope config -Subject "rename provider" -Breaking -BreakingDescription "Config key providerName replaces name."
"@
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

switch ($Command) {
    'create' { Invoke-Create }
    default  { Invoke-Help }
}

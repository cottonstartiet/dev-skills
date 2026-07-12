<#
.SYNOPSIS
    Git local branch cleanup helper. Installed as the 'clean' command.

.DESCRIPTION
    Reports and optionally prunes stale local git branches. A stale branch is one
    that is already merged into a base branch or whose configured upstream is
    gone after pruning remotes.

    Safety: read-only by default, never deletes the current branch or protected
    branches, uses safe deletion for merged branches, and requires explicit
    typed confirmation before force-deleting unmerged work.

.EXAMPLE
    clean
.EXAMPLE
    clean delete -Yes
.EXAMPLE
    clean delete -Force -ConfirmName users/alice/old-branch
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('list', 'delete', 'help')]
    [string]$Command = 'list',

    [string]$BaseBranch = 'main',

    [switch]$Delete,
    [switch]$Force,
    [switch]$Yes,

    # Typed confirmation for guarded operations. When it matches the branch name
    # the interactive prompt is skipped (enables automation & tests).
    [string]$ConfirmName
)

$ErrorActionPreference = 'Stop'

$script:ProtectedBranches = @('main', 'master', 'develop', 'release', 'production')

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

function Get-CanonicalPath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $full = (Get-Item -LiteralPath $Path -Force -ErrorAction Stop).FullName
    }
    catch {
        $full = [System.IO.Path]::GetFullPath($Path)
    }
    $full.Replace('/', '\').TrimEnd('\')
}

function Confirm-Typed {
    param([string]$Expected, [string]$Provided, [string]$PromptText)
    if (-not [string]::IsNullOrEmpty($Expected) -and $Provided -eq $Expected) { return $true }
    # Only prompt at a real interactive console; never block in automation / agent context.
    if ([Console]::IsInputRedirected) { return $false }
    try { $answer = Read-Host $PromptText } catch { return $false }
    return ($answer -eq $Expected)
}

# ---------------------------------------------------------------------------
# Repository / branch state helpers
# ---------------------------------------------------------------------------

function Assert-GitRepo {
    $inside = Invoke-Git -GitArgs @('rev-parse', '--is-inside-work-tree') -AllowFail
    if ($inside.ExitCode -ne 0 -or $inside.Output -ne 'true') {
        Fail 'clean must be run inside a git working tree.'
    }
}

function Test-LocalBranchExists {
    param([Parameter(Mandatory)][string]$Branch)
    (Invoke-Git -GitArgs @('show-ref', '--verify', '--quiet', "refs/heads/$Branch") -AllowFail).ExitCode -eq 0
}

function Test-RemoteRefExists {
    param([Parameter(Mandatory)][string]$Upstream)
    (Invoke-Git -GitArgs @('show-ref', '--verify', '--quiet', "refs/remotes/$Upstream") -AllowFail).ExitCode -eq 0
}

function Test-Ancestor {
    param([Parameter(Mandatory)][string]$Ancestor, [Parameter(Mandatory)][string]$Descendant)
    (Invoke-Git -GitArgs @('merge-base', '--is-ancestor', $Ancestor, $Descendant) -AllowFail).ExitCode -eq 0
}

function Get-RevListCount {
    param([Parameter(Mandatory)][string[]]$GitArgs)
    $r = Invoke-Git -GitArgs (@('rev-list', '--count') + $GitArgs) -AllowFail
    if ($r.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($r.Output)) { return 0 }
    [int]$r.Output
}

function Get-CurrentBranch {
    $head = Invoke-Git -GitArgs @('symbolic-ref', '--quiet', '--short', 'HEAD') -AllowFail
    if ($head.ExitCode -eq 0) { return $head.Output }
    $null
}

function Get-LocalBranches {
    $raw = (Invoke-Git -GitArgs @('for-each-ref', '--format=%(refname:short)%09%(upstream:short)%09%(upstream:track)', 'refs/heads')).Output
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    foreach ($line in ($raw -split "`n")) {
        $line = $line.TrimEnd()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t", 3
        [pscustomobject]@{
            Branch   = $parts[0]
            Upstream = if ($parts.Count -gt 1) { $parts[1] } else { '' }
            Track    = if ($parts.Count -gt 2) { $parts[2] } else { '' }
        }
    }
}

function Invoke-FetchPrune {
    Write-Info 'Fetching/pruning remotes ...'
    $r = Invoke-Git -GitArgs @('fetch', '--prune') -AllowFail
    if ($r.ExitCode -ne 0) {
        Write-Warn2 'Could not run git fetch --prune; continuing with local remote-tracking state (offline or no remote).'
    }
}

function Get-CleanPlan {
    Assert-GitRepo
    if (-not (Test-LocalBranchExists -Branch $BaseBranch)) {
        Fail "Base branch '$BaseBranch' does not exist locally. Fetch/checkout it first or pass -BaseBranch."
    }

    $current = Get-CurrentBranch
    $rows = @()
    foreach ($b in (Get-LocalBranches)) {
        $branch = $b.Branch
        if ($current -and $branch -eq $current) { continue }

        $isMerged = Test-Ancestor -Ancestor $branch -Descendant $BaseBranch
        $hasUpstream = -not [string]::IsNullOrWhiteSpace($b.Upstream)
        $upstreamGone = $false
        if ($hasUpstream) {
            $upstreamGone = ($b.Track -match '\[gone\]') -or (-not (Test-RemoteRefExists -Upstream $b.Upstream))
        }

        $reasons = @()
        if ($isMerged) { $reasons += 'merged' }
        if ($upstreamGone) { $reasons += 'gone-upstream' }
        if ($reasons.Count -eq 0) { continue }

        $aheadUpstream = 0
        if ($hasUpstream -and -not $upstreamGone) {
            $aheadUpstream = Get-RevListCount -GitArgs @("$($b.Upstream)..$branch")
        }

        $skipReasons = @()
        $protected = $script:ProtectedBranches -contains $branch
        if ($protected) { $skipReasons += 'protected branch' }
        if (-not $isMerged) { $skipReasons += "has commits not merged into $BaseBranch" }
        if ($aheadUpstream -gt 0) { $skipReasons += "has $aheadUpstream commit(s) ahead of upstream" }

        $unsafe = (-not $isMerged) -or ($aheadUpstream -gt 0)
        $rows += [pscustomobject]@{
            Branch       = $branch
            Reason       = ($reasons -join ', ')
            SkipReason   = ($skipReasons -join '; ')
            Protected    = $protected
            Unsafe       = $unsafe
            SafeToDelete = ($skipReasons.Count -eq 0)
        }
    }
    $rows
}

function Write-CleanPlan {
    param([Parameter(Mandatory)][object[]]$Plan, [switch]$Deleting)

    Write-Info "Branch cleanup report (base: $BaseBranch)"
    Write-Info '=================================='

    $safe = @($Plan | Where-Object { $_.SafeToDelete })
    $skipped = @($Plan | Where-Object { -not $_.SafeToDelete })

    if ($safe.Count -gt 0) {
        Write-Info ''
        Write-Info 'Safe stale local branches:'
        $safe | Select-Object Branch, Reason | Format-Table -AutoSize | Out-String | Write-Host
    }
    else {
        Write-Ok 'No safe stale local branches found.'
    }

    if ($skipped.Count -gt 0) {
        Write-Info ''
        Write-Warn2 'Skipped stale local branches:'
        $skipped | Select-Object Branch, Reason, SkipReason | Format-Table -AutoSize | Out-String | Write-Host
    }

    if (-not $Deleting) {
        Write-Info 'Read-only: no branches were deleted. Run ''clean delete -Yes'' to delete safe candidates.'
    }
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

function Invoke-List {
    Invoke-FetchPrune
    $plan = @(Get-CleanPlan)
    if ($plan.Count -eq 0) {
        Write-Ok "No stale local branches found for base '$BaseBranch'."
        return
    }
    Write-CleanPlan -Plan $plan
}

function Invoke-Delete {
    Invoke-FetchPrune
    $plan = @(Get-CleanPlan)
    if ($plan.Count -eq 0) {
        Write-Ok "No stale local branches found for base '$BaseBranch'."
        return
    }

    Write-CleanPlan -Plan $plan -Deleting

    $safe = @($plan | Where-Object { $_.SafeToDelete })
    $skipped = @($plan | Where-Object { -not $_.SafeToDelete })
    $blockedUnsafe = $false

    foreach ($row in $safe) {
        if (-not $Yes) {
            if (-not (Confirm-Typed -Expected $row.Branch -Provided $ConfirmName -PromptText "Type the branch name to confirm deleting '$($row.Branch)'")) {
                Fail "Delete cancelled (confirmation did not match branch name '$($row.Branch)')."
            }
        }
        Invoke-Git -GitArgs @('branch', '-d', $row.Branch) | Out-Null
        Write-Ok "Deleted '$($row.Branch)' ($($row.Reason))."
    }

    foreach ($row in $skipped) {
        if ($row.Protected) {
            Write-Warn2 "Skipped protected branch '$($row.Branch)'."
            continue
        }
        if ($row.Unsafe) {
            if (-not $Force) {
                Write-Warn2 "Skipped '$($row.Branch)': $($row.SkipReason). Use -Force with typed confirmation to delete it."
                $blockedUnsafe = $true
                continue
            }
            Write-Warn2 "Force delete requested for '$($row.Branch)': $($row.SkipReason)."
            if (-not (Confirm-Typed -Expected $row.Branch -Provided $ConfirmName -PromptText "Type the branch name to force delete '$($row.Branch)'")) {
                Fail "Force delete cancelled (confirmation did not match branch name '$($row.Branch)')."
            }
            Invoke-Git -GitArgs @('branch', '-D', $row.Branch) | Out-Null
            Write-Ok "Force deleted '$($row.Branch)' ($($row.Reason))."
        }
    }

    if ($blockedUnsafe) {
        Fail 'One or more stale branches were not deleted because they contain unmerged/unpushed work.'
    }
}

function Invoke-Help {
    Write-Info @"
clean.ps1 - git local branch cleanup helper (installed as 'clean')

Usage: clean [list|delete|help] [options]
       clean -Delete [options]

Commands:
  list                         Read-only report of stale local branches (default)
  delete                       Delete safe stale local branches with git branch -d
  help                         Show this help

Options:
  -BaseBranch <branch>         Base branch used for merged checks (default: main)
  -Delete                      Alias for the delete command
  -Yes                         Delete safe branches without per-branch prompts
  -Force                       Allow git branch -D for unmerged/gone branches after typed confirmation
  -ConfirmName <branch>        Typed confirmation branch name for automation/tests
"@
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

switch ($Command) {
    'help'   { Invoke-Help }
    'delete' { Invoke-Delete }
    default  { if ($Delete) { Invoke-Delete } else { Invoke-List } }
}

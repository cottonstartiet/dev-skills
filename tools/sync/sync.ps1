<#
.SYNOPSIS
    Safely update the current git branch. Installed as the 'sync' command.

.DESCRIPTION
    Previews or applies safe branch updates for the current git branch:
      preview | run | help

    Safety: fetches origin first (non-fatal if offline), refuses detached HEAD,
    never force-pushes, never pushes, and refuses to run with uncommitted changes
    unless -Autostash is specified.

.EXAMPLE
    sync
.EXAMPLE
    sync run
.EXAMPLE
    sync run -Rebase -BaseBranch main
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('preview', 'run', 'help')]
    [string]$Command = 'preview',

    [string]$BaseBranch = 'main',

    [switch]$Rebase,
    [switch]$Merge,
    [switch]$Autostash
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

function Fail {
    param([string]$Message)
    Write-Host "ERROR  $Message" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Repository state
# ---------------------------------------------------------------------------

function Invoke-FetchOrigin {
    Write-Info "Fetching origin ..."
    $r = Invoke-Git -GitArgs @('fetch', 'origin') -AllowFail
    if ($r.ExitCode -ne 0) {
        Write-Warn2 "Could not fetch origin; continuing with local refs (offline or no origin)."
    }
}

function Get-CurrentBranch {
    $r = Invoke-Git -GitArgs @('symbolic-ref', '--quiet', '--short', 'HEAD') -AllowFail
    if ($r.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($r.Output)) {
        Fail "HEAD is detached; sync requires a checked-out branch."
    }
    $r.Output
}

function Test-WorkingTreeDirty {
    ((Invoke-Git -GitArgs @('status', '--porcelain')).Output).Trim().Length -gt 0
}

function Test-RefExists {
    param([Parameter(Mandatory)][string]$Ref)
    (Invoke-Git -GitArgs @('rev-parse', '--verify', '--quiet', $Ref) -AllowFail).ExitCode -eq 0
}

function Resolve-BaseRef {
    if ([string]::IsNullOrWhiteSpace($BaseBranch)) { Fail "-BaseBranch must not be empty." }
    $remoteRef = "origin/$BaseBranch"
    if (Test-RefExists -Ref $remoteRef) { return $remoteRef }
    if (Test-RefExists -Ref $BaseBranch) { return $BaseBranch }
    Fail "Base branch '$BaseBranch' was not found locally or at origin/$BaseBranch."
}

function Get-UpstreamRef {
    $r = Invoke-Git -GitArgs @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}') -AllowFail
    if ($r.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($r.Output)) { return $r.Output }
    $null
}

function Get-AheadBehind {
    param([Parameter(Mandatory)][string]$RightRef)
    $r = Invoke-Git -GitArgs @('rev-list', '--left-right', '--count', "HEAD...$RightRef") -AllowFail
    if ($r.ExitCode -ne 0) { return [pscustomobject]@{ Ahead = $null; Behind = $null } }
    $parts = $r.Output -split '\s+'
    [pscustomobject]@{ Ahead = [int]$parts[0]; Behind = [int]$parts[1] }
}

function Get-SyncMode {
    if ($Rebase -and $Merge) { Fail "Choose only one apply mode: -Rebase or -Merge." }
    if ($Rebase) { return 'rebase' }
    if ($Merge) { return 'merge' }
    'ff-only'
}

function Get-SyncState {
    $branch = Get-CurrentBranch
    $baseRef = Resolve-BaseRef
    $upstream = Get-UpstreamRef
    $upCounts = if ($upstream) { Get-AheadBehind -RightRef $upstream } else { [pscustomobject]@{ Ahead = $null; Behind = $null } }
    $baseCounts = Get-AheadBehind -RightRef $baseRef
    [pscustomobject]@{
        Branch   = $branch
        BaseRef  = $baseRef
        Upstream = $upstream
        UpAhead  = $upCounts.Ahead
        UpBehind = $upCounts.Behind
        BaseAhead = $baseCounts.Ahead
        BaseBehind = $baseCounts.Behind
        Dirty    = Test-WorkingTreeDirty
        Mode     = Get-SyncMode
    }
}

function Write-SyncState {
    param([Parameter(Mandatory)][pscustomobject]$State)
    Write-Info "Branch:   $($State.Branch)"
    if ($State.Upstream) {
        Write-Info "Upstream: $($State.Upstream) (ahead $($State.UpAhead), behind $($State.UpBehind))"
    }
    else {
        Write-Info "Upstream: (none)"
    }
    Write-Info "Base:     $($State.BaseRef) (ahead $($State.BaseAhead), behind $($State.BaseBehind))"
    Write-Info ("Working tree: " + ($(if ($State.Dirty) { 'has uncommitted changes' } else { 'clean' })))
    Write-Info "Mode:     $($State.Mode)"
}

function Restore-Autostash {
    param([Parameter(Mandatory)][string]$FailureContext)
    $pop = Invoke-Git -GitArgs @('stash', 'pop', '--index') -AllowFail
    if ($pop.ExitCode -ne 0) {
        Fail "$FailureContext Autostash was created, but 'git stash pop --index' failed. Resolve it manually with 'git stash list'. Details: $($pop.Output)"
    }
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

function Invoke-Preview {
    Invoke-FetchOrigin
    $state = Get-SyncState
    Write-Info ""
    Write-Info "sync preview"
    Write-Info "============"
    Write-SyncState -State $state
    if ($state.Dirty) {
        Write-Warn2 "Run mode will refuse uncommitted changes unless -Autostash is used."
    }
    Write-Info ""
    Write-Info "Preview only. Apply with: sync run [options]"
}

function Invoke-Run {
    Invoke-FetchOrigin
    $state = Get-SyncState

    Write-Info ""
    Write-Info "sync run"
    Write-Info "========"
    Write-SyncState -State $state

    if ($state.Mode -eq 'ff-only' -and -not $state.Upstream) {
        Fail "Current branch '$($state.Branch)' has no upstream; cannot fast-forward. Set upstream or use -Rebase/-Merge with -BaseBranch."
    }
    if (($state.Mode -eq 'rebase' -or $state.Mode -eq 'merge') -and $script:ProtectedBranches -contains $state.Branch) {
        Fail "Refusing to $($state.Mode) while on protected branch '$($state.Branch)'. Use default fast-forward-only mode or switch to a feature branch."
    }
    if (($state.Mode -eq 'rebase' -or $state.Mode -eq 'merge') -and $state.Branch -eq $BaseBranch) {
        Fail "Refusing to $($state.Mode) branch '$($state.Branch)' onto itself."
    }
    if ($state.Dirty -and -not $Autostash) {
        Fail "Working tree has uncommitted changes. Commit/stash them first, or rerun with -Autostash."
    }

    $stashed = $false
    if ($state.Dirty -and $Autostash) {
        Write-Info "Autostashing uncommitted changes ..."
        Invoke-Git -GitArgs @('stash', 'push', '-u', '-m', "sync autostash $(Get-Date -Format o)") | Out-Null
        $stashed = $true
    }

    try {
        switch ($state.Mode) {
            'ff-only' {
                Write-Info "Fast-forwarding '$($state.Branch)' from '$($state.Upstream)' ..."
                Invoke-Git -GitArgs @('merge', '--ff-only', '@{u}') | Out-Null
                Write-Ok "Fast-forwarded '$($state.Branch)' from '$($state.Upstream)'."
            }
            'rebase' {
                Write-Info "Rebasing '$($state.Branch)' onto '$($state.BaseRef)' ..."
                Invoke-Git -GitArgs @('rebase', $state.BaseRef) | Out-Null
                Write-Ok "Rebased '$($state.Branch)' onto '$($state.BaseRef)'."
            }
            'merge' {
                Write-Info "Merging '$($state.BaseRef)' into '$($state.Branch)' ..."
                Invoke-Git -GitArgs @('merge', '--no-edit', $state.BaseRef) | Out-Null
                Write-Ok "Merged '$($state.BaseRef)' into '$($state.Branch)'."
            }
        }
    }
    catch {
        $message = $_.Exception.Message
        if ($stashed) { Restore-Autostash -FailureContext "Sync failed: $message" }
        Fail $message
    }

    if ($stashed) {
        Write-Info "Restoring autostash ..."
        Restore-Autostash -FailureContext "Sync succeeded, but restoring changes failed."
        Write-Ok "Autostash restored."
    }
}

function Invoke-Help {
    Write-Info @"
sync.ps1 - safe current-branch updater (installed as 'sync')

Usage: sync <command> [options]

Commands:
  preview                                  Show fetch + ahead/behind state (default)
  run                                      Apply an update to the current branch
  help                                     Show this help

Run modes:
  sync run                                Fast-forward current branch to its upstream
  sync run -Rebase [-BaseBranch main]      Rebase current branch onto base
  sync run -Merge  [-BaseBranch main]      Merge base into current branch

Options:
  -BaseBranch <branch>   Base branch for preview, -Rebase, and -Merge (default: main)
  -Autostash             Stash uncommitted changes before run and pop them afterward

Notes:
  Fetching origin is attempted first and only warns if offline.
  sync never pushes, never forces, and refuses detached HEAD.
"@
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

switch ($Command) {
    'preview' { Invoke-Preview }
    'run'     { Invoke-Run }
    default   { Invoke-Help }
}

<#
.SYNOPSIS
    Git worktree helper for the Xbox.Xbet.Service monorepo.

.DESCRIPTION
    Wraps common git-worktree actions behind a single dispatcher so developers
    (and coding agents) get consistent, safe worktree management:
      create | list | status | branch | health | push | remove | switch

    Conventions:
      - Branch names: users/<alias>/<name>  (alias from git user.email local-part)
      - Worktree path: <primaryWorktree>.worktrees\<name>

    Safety: never touches production, never embeds secrets, refuses force-push,
    never auto-deletes branches, and requires explicit typed confirmation before
    pushing to origin or removing a worktree with unpushed work.

.EXAMPLE
    pwsh -File worktree.ps1 create wishlist-reorder-api
.EXAMPLE
    pwsh -File worktree.ps1 status
.EXAMPLE
    pwsh -File worktree.ps1 push -ConfirmBranch users/aseemgaurav/wishlist-reorder-api
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('create', 'list', 'status', 'branch', 'health', 'push', 'remove', 'switch', 'help')]
    [string]$Command = 'help',

    [Parameter(Position = 1)]
    [string]$Name,

    [string]$BaseBranch = 'main',

    # Override for the worktrees base directory (nonstandard layouts / testing).
    [string]$WorktreesBase,

    # Typed confirmation for guarded operations (push/remove). When it matches the
    # required value the interactive prompt is skipped (enables automation & tests).
    [string]$ConfirmBranch,
    [string]$ConfirmName
)

$ErrorActionPreference = 'Stop'

# Protected branches that must never be created-onto, pushed from a worktree flow,
# or silently reused.
$script:ProtectedBranches = @('main', 'master', 'develop', 'release', 'production')
$script:ReservedNames = @('CON', 'PRN', 'AUX', 'NUL') +
    (1..9 | ForEach-Object { "COM$_" }) +
    (1..9 | ForEach-Object { "LPT$_" })

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

# Canonicalize a path for reliable comparison: expands Windows 8.3 short names
# (e.g. ASEEMG~1 -> aseemgaurav), normalizes separators, trims trailing slash.
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
# Repository / identity helpers
# ---------------------------------------------------------------------------

function Get-Alias {
    $email = (Invoke-Git -GitArgs @('config', 'user.email') -AllowFail).Output
    if ([string]::IsNullOrWhiteSpace($email)) {
        Fail "git user.email is not configured; cannot derive branch alias. Set it with: git config user.email <you>@microsoft.com"
    }
    $alias = ($email -split '@')[0].Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($alias)) {
        Fail "Could not derive an alias from git user.email '$email'."
    }
    $alias
}

# Returns the absolute path of the primary (main) worktree. Per git, the main
# working tree is always listed first by `git worktree list --porcelain`.
function Get-PrimaryWorktreePath {
    $porcelain = (Invoke-Git -GitArgs @('worktree', 'list', '--porcelain')).Output
    foreach ($line in ($porcelain -split "`n")) {
        if ($line -match '^worktree\s+(.+)$') {
            return (Get-CanonicalPath $Matches[1].Trim())
        }
    }
    throw "Unable to determine the primary worktree path."
}

function Get-WorktreesBase {
    if (-not [string]::IsNullOrWhiteSpace($WorktreesBase)) { return $WorktreesBase }
    if (-not [string]::IsNullOrWhiteSpace($env:WORKTREE_BASE)) { return $env:WORKTREE_BASE }
    $primary = Get-PrimaryWorktreePath
    "$($primary.TrimEnd('\', '/')).worktrees"
}

function Get-CurrentWorktreePath {
    Get-CanonicalPath (Invoke-Git -GitArgs @('rev-parse', '--show-toplevel')).Output
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

function Test-WorktreeName {
    param([Parameter(Mandatory)][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { Fail "A worktree <name> is required." }
    if ($Value -match '[\\/:*?"<>|]') { Fail "Name '$Value' contains an invalid path character." }
    if ($Value -match '\.\.') { Fail "Name '$Value' must not contain '..'." }
    if ($Value -match '[ .]$') { Fail "Name '$Value' must not end with a space or a dot." }
    if ($Value -notmatch '^[A-Za-z0-9._-]+$') {
        Fail "Name '$Value' is invalid. Use only letters, digits, '.', '_' and '-'."
    }
    if ($script:ReservedNames -contains $Value.ToUpperInvariant()) {
        Fail "Name '$Value' is a reserved Windows name."
    }
}

# Full branch name for a worktree, validated with git's own ref rules.
function Resolve-BranchName {
    param([Parameter(Mandatory)][string]$Value)
    Test-WorktreeName -Value $Value
    $alias = Get-Alias
    $branch = "users/$alias/$Value"
    $check = Invoke-Git -GitArgs @('check-ref-format', '--branch', $branch) -AllowFail
    if ($check.ExitCode -ne 0) { Fail "Derived branch '$branch' is not a valid git ref." }
    $branch
}

# ---------------------------------------------------------------------------
# Worktree state
# ---------------------------------------------------------------------------

function Get-WorktreeInventory {
    $porcelain = (Invoke-Git -GitArgs @('worktree', 'list', '--porcelain')).Output
    $items = @()
    $current = $null
    foreach ($line in ($porcelain -split "`n")) {
        $line = $line.TrimEnd()
        if ($line -match '^worktree\s+(.+)$') {
            if ($current) { $items += $current }
            $current = [ordered]@{ Path = $Matches[1].Trim(); Branch = $null; Detached = $false; Locked = $false; Prunable = $false }
        }
        elseif ($line -match '^branch\s+(.+)$') { $current.Branch = ($Matches[1] -replace '^refs/heads/', '') }
        elseif ($line -match '^detached$') { $current.Detached = $true }
        elseif ($line -match '^locked') { $current.Locked = $true }
        elseif ($line -match '^prunable') { $current.Prunable = $true }
    }
    if ($current) { $items += $current }
    $items | ForEach-Object { [pscustomobject]$_ }
}

# Rich state for a specific worktree path.
function Get-WorktreeState {
    param([Parameter(Mandatory)][string]$Path)
    $dirty = ((Invoke-Git -GitArgs @('-C', $Path, 'status', '--porcelain')).Output).Trim().Length -gt 0
    $head = (Invoke-Git -GitArgs @('-C', $Path, 'symbolic-ref', '--quiet', '--short', 'HEAD') -AllowFail)
    $branch = if ($head.ExitCode -eq 0) { $head.Output } else { $null }
    $upstream = $null; $ahead = $null; $behind = $null; $unpushed = $null
    if ($branch) {
        $up = Invoke-Git -GitArgs @('-C', $Path, 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}') -AllowFail
        if ($up.ExitCode -eq 0) {
            $upstream = $up.Output
            $counts = (Invoke-Git -GitArgs @('-C', $Path, 'rev-list', '--left-right', '--count', "$branch...@{u}")).Output
            $parts = $counts -split '\s+'
            $ahead = [int]$parts[0]; $behind = [int]$parts[1]
        }
        # Commits on this branch not contained in any origin ref. Fail-closed:
        # with no origin refs this counts all commits, so removal will be guarded.
        $notPushed = (Invoke-Git -GitArgs @('-C', $Path, 'rev-list', '--count', $branch, '--not', '--remotes=origin') -AllowFail)
        if ($notPushed.ExitCode -eq 0) { $unpushed = [int]$notPushed.Output }
    }
    [pscustomobject]@{
        Path     = $Path
        Branch   = $branch
        Detached = (-not $branch)
        Dirty    = $dirty
        Upstream = $upstream
        Ahead    = $ahead
        Behind   = $behind
        Unpushed = $unpushed
    }
}

function Test-BranchExistsLocal {
    param([string]$Branch)
    (Invoke-Git -GitArgs @('show-ref', '--verify', '--quiet', "refs/heads/$Branch") -AllowFail).ExitCode -eq 0
}
function Test-BranchExistsRemote {
    param([string]$Branch)
    (Invoke-Git -GitArgs @('show-ref', '--verify', '--quiet', "refs/remotes/origin/$Branch") -AllowFail).ExitCode -eq 0
}
function Get-BranchCheckoutPath {
    param([string]$Branch)
    (Get-WorktreeInventory | Where-Object { $_.Branch -eq $Branch } | Select-Object -First 1).Path
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
# Commands
# ---------------------------------------------------------------------------

# Bring the base branch up to date before branching off it. If it is checked out
# in a worktree, fast-forward it with 'git pull --ff-only'; otherwise fast-forward
# the local ref directly from origin. Network / non-fast-forward failures are
# non-fatal: warn and continue from whatever local state exists.
function Update-BaseBranch {
    param([Parameter(Mandatory)][string]$Branch)
    $checkout = Get-BranchCheckoutPath $Branch
    if ($checkout) {
        Write-Info "Pulling latest '$Branch' (checked out at $checkout) ..."
        $r = Invoke-Git -GitArgs @('-C', $checkout, 'pull', '--ff-only', 'origin', $Branch) -AllowFail
        if ($r.ExitCode -ne 0) {
            Write-Warn2 "Could not pull '$Branch'; continuing with the current local state."
        }
    }
    else {
        Write-Info "Fetching latest '$Branch' from origin ..."
        $r = Invoke-Git -GitArgs @('fetch', 'origin', "${Branch}:${Branch}") -AllowFail
        if ($r.ExitCode -ne 0) {
            Write-Warn2 "Could not fast-forward '$Branch' from origin; continuing with the current local state."
        }
    }
}

function Invoke-Create {
    $branch = Resolve-BranchName -Value $Name
    $baseDir = Get-WorktreesBase
    $path = Join-Path $baseDir $Name

    if (Test-BranchExistsLocal $branch) {
        $where = Get-BranchCheckoutPath $branch
        if ($where) { Fail "Branch '$branch' already exists and is checked out at: $where" }
        Fail "Branch '$branch' already exists locally. Use 'branch' or pick a different name."
    }
    if (Test-BranchExistsRemote $branch) {
        Fail "Branch '$branch' already exists on origin. Check it out manually or pick a different name."
    }
    if (Test-Path -LiteralPath $path) {
        Fail "Target path already exists: $path"
    }
    if (Get-WorktreeInventory | Where-Object { $_.Path -and ((Get-CanonicalPath $_.Path) -ieq (Get-CanonicalPath $path)) }) {
        Fail "A worktree is already registered at: $path"
    }

    Update-BaseBranch -Branch $BaseBranch

    if (-not (Test-BranchExistsLocal $BaseBranch)) {
        Fail "Base branch '$BaseBranch' does not exist locally. Fetch/checkout it first or pass -BaseBranch."
    }
    $baseCommit = (Invoke-Git -GitArgs @('rev-parse', '--short', $BaseBranch)).Output
    Write-Info "Creating worktree '$Name' -> branch '$branch' from $BaseBranch ($baseCommit)"

    Invoke-Git -GitArgs @('worktree', 'add', '-b', $branch, $path, $BaseBranch) | Out-Null

    Write-Ok "Worktree created."
    Write-Info ""
    Write-Info "  Branch: $branch"
    Write-Info "  Path:   $path"
    Write-Info ""
    Write-Info "Open a new terminal / relaunch the CLI in that path to work on it:"
    Write-Info "  cd `"$path`""
}

function Invoke-List {
    $rows = foreach ($wt in (Get-WorktreeInventory)) {
        $state = Get-WorktreeState -Path $wt.Path
        [pscustomobject]@{
            Name     = Split-Path $wt.Path -Leaf
            Branch   = if ($state.Detached) { '(detached)' } else { $state.Branch }
            Dirty    = if ($state.Dirty) { 'dirty' } else { 'clean' }
            Upstream = if ($state.Upstream) { "$($state.Ahead)/$($state.Behind)" } else { '-' }
            Path     = $wt.Path
        }
    }
    $rows | Format-Table -AutoSize | Out-String | Write-Host
}

function Invoke-Status {
    $path = Get-CurrentWorktreePath
    $state = Get-WorktreeState -Path $path
    Write-Info "Worktree: $path"
    if ($state.Detached) {
        Write-Warn2 "HEAD is DETACHED (no branch)."
        Write-Info "Bind it onto a branch with:"
        Write-Info "  pwsh -File worktree.ps1 branch <name>"
    }
    else {
        Write-Info "Branch:   $($state.Branch)"
        if ($state.Upstream) { Write-Info "Upstream: $($state.Upstream) (ahead $($state.Ahead), behind $($state.Behind))" }
        else { Write-Info "Upstream: (none - not pushed yet)" }
    }
    Write-Info ("Working tree: " + ($(if ($state.Dirty) { 'has uncommitted changes' } else { 'clean' })))
}

function Invoke-Branch {
    $path = Get-CurrentWorktreePath
    $state = Get-WorktreeState -Path $path
    if (-not $state.Detached) {
        Fail "Current worktree is already on branch '$($state.Branch)'. 'branch' only applies to a detached HEAD."
    }
    $branch = Resolve-BranchName -Value $Name
    if (Test-BranchExistsLocal $branch) {
        $where = Get-BranchCheckoutPath $branch
        if ($where) { Fail "Branch '$branch' already exists and is checked out at: $where" }
        Fail "Branch '$branch' already exists locally. Pick a different name."
    }
    # Create the branch at current HEAD and switch to it; uncommitted changes are preserved.
    Invoke-Git -GitArgs @('-C', $path, 'switch', '-c', $branch) | Out-Null
    Write-Ok "Bound detached HEAD onto branch '$branch' (uncommitted changes preserved)."
}

function Invoke-Health {
    Write-Info "Worktree health report"
    Write-Info "======================"
    $any = $false
    foreach ($wt in (Get-WorktreeInventory)) {
        $state = Get-WorktreeState -Path $wt.Path
        $issues = @()
        if ($state.Detached) { $issues += 'DETACHED (run: branch <name>)' }
        if ($state.Dirty) { $issues += 'uncommitted changes' }
        if ($wt.Prunable) { $issues += 'PRUNABLE / missing path (run: git worktree prune)' }
        if ($wt.Locked) { $issues += 'locked' }
        if (-not $state.Detached -and -not $state.Upstream -and ($script:ProtectedBranches -notcontains $state.Branch)) { $issues += 'no upstream (not pushed)' }
        if ($state.Behind -gt 0) { $issues += "behind upstream by $($state.Behind)" }
        if ($issues.Count -gt 0) {
            $any = $true
            Write-Warn2 ("{0}: {1}" -f (Split-Path $wt.Path -Leaf), ($issues -join '; '))
            Write-Info  "    $($wt.Path)"
        }
    }
    if (-not $any) { Write-Ok "All worktrees are healthy." }
}

function Invoke-Push {
    $path = Get-CurrentWorktreePath
    $state = Get-WorktreeState -Path $path

    if ($state.Detached) { Fail "HEAD is detached; nothing to push. Run 'branch <name>' first." }
    $branch = $state.Branch
    if ($script:ProtectedBranches -contains $branch) { Fail "Refusing to push protected branch '$branch'." }
    if ($branch -notmatch '^users/[^/]+/.+') { Fail "Refusing to push '$branch' - only 'users/<alias>/<name>' branches are allowed." }
    if ($state.Upstream -and $state.Upstream -ne "origin/$branch") {
        Fail "Upstream is '$($state.Upstream)', expected 'origin/$branch'. Resolve this manually."
    }
    if ($state.Dirty) { Write-Warn2 "Working tree has uncommitted changes; they will NOT be pushed." }

    Write-Info "About to run: git push -u origin $branch"
    if (-not (Confirm-Typed -Expected $branch -Provided $ConfirmBranch -PromptText "Type the branch name to confirm push")) {
        Fail "Push cancelled (confirmation did not match branch name)."
    }
    Invoke-Git -GitArgs @('-C', $path, 'push', '-u', 'origin', $branch) | Out-Null
    Write-Ok "Pushed '$branch' to origin."
}

function Invoke-Remove {
    Test-WorktreeName -Value $Name
    $baseDir = Get-WorktreesBase
    $path = Join-Path $baseDir $Name
    $targetCanon = Get-CanonicalPath $path

    $registered = Get-WorktreeInventory | Where-Object {
        $_.Path -and ((Get-CanonicalPath $_.Path) -ieq $targetCanon)
    } | Select-Object -First 1
    if (-not $registered) { Fail "No registered worktree found at: $path" }

    if ($targetCanon -ieq (Get-PrimaryWorktreePath)) { Fail "Refusing to remove the primary (main) worktree." }
    if ($targetCanon -ieq (Get-CurrentWorktreePath)) {
        Fail "Refusing to remove the worktree you are currently in. Switch elsewhere first."
    }
    if ($registered.Locked) { Fail "Worktree is locked. Unlock it manually (git worktree unlock) before removing." }

    $state = Get-WorktreeState -Path $path
    if ($state.Dirty) {
        Fail "Worktree has uncommitted changes. Commit, stash, or discard them manually before removing."
    }
    if ($state.Detached) {
        # A detached HEAD can hold commits reachable from no branch/remote; removing
        # would orphan them. Require typed confirmation (branch first to keep them safely).
        Write-Warn2 "Worktree is in DETACHED HEAD; any commits on it are not on a branch and would be orphaned."
        if (-not (Confirm-Typed -Expected $Name -Provided $ConfirmName -PromptText "This may discard commits. Bind it to a branch first, or type the worktree name to confirm removal")) {
            Fail "Removal cancelled (confirmation did not match name). Run 'branch' first to keep the work."
        }
    }
    elseif ($null -ne $state.Unpushed -and $state.Unpushed -gt 0) {
        Write-Warn2 "Worktree branch '$($state.Branch)' has $($state.Unpushed) commit(s) not known to origin."
        if (-not (Confirm-Typed -Expected $Name -Provided $ConfirmName -PromptText "This may discard unpushed work. Type the worktree name to confirm removal")) {
            Fail "Removal cancelled (confirmation did not match name)."
        }
    }

    Invoke-Git -GitArgs @('worktree', 'remove', $path) | Out-Null
    $branchNote = if ($state.Branch) { "Branch '$($state.Branch)' was left intact." } else { "(worktree was detached; no branch involved)" }
    Write-Ok "Removed worktree '$Name'. $branchNote"
}

function Invoke-Switch {
    Write-Info "Worktrees (open a new terminal in the desired path):"
    foreach ($wt in (Get-WorktreeInventory)) {
        $state = Get-WorktreeState -Path $wt.Path
        $b = if ($state.Detached) { '(detached)' } else { $state.Branch }
        Write-Info ("  {0,-28} {1}" -f $b, $wt.Path)
    }
}

function Invoke-Help {
    Write-Info @"
worktree.ps1 - git worktree helper

Usage: pwsh -File worktree.ps1 <command> [name] [options]

Commands:
  create <name> [-BaseBranch main]            Create worktree + branch (pulls latest base first)
  list                                        List worktrees with branch/dirty/upstream
  status                                       Show current worktree state (+ branch hint if detached)
  branch <name>                                Bind current detached worktree to users/<alias>/<name>
  health                                       Read-only health report across all worktrees
  push   [-ConfirmBranch <branch>]             Push current branch to origin (guarded, confirmed)
  remove <name> [-ConfirmName <name>]          Remove a worktree (guarded; never deletes the branch)
  switch                                       List worktree paths to open

Options:
  -WorktreesBase <path>   Override base dir (default: <primaryWorktree>.worktrees)
"@
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

switch ($Command) {
    'create' { Invoke-Create }
    'list'   { Invoke-List }
    'status' { Invoke-Status }
    'branch' { Invoke-Branch }
    'health' { Invoke-Health }
    'push'   { Invoke-Push }
    'remove' { Invoke-Remove }
    'switch' { Invoke-Switch }
    default  { Invoke-Help }
}

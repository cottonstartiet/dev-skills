#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for scripts/worktree.ps1.

    Each test builds a throwaway git repo in a temp directory (no network, no
    origin unless the test creates a local bare "remote"). The worktrees base is
    always overridden with -WorktreesBase so nothing touches the real repo.

    IMPORTANT: worktree.ps1 operates on the *ambient* git repository (the child
    process cwd). Every script invocation must therefore run with its working
    directory inside the temp repo — helpers below enforce this so tests never
    leak worktrees/branches into the real repository.
#>

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\worktree.ps1'

    function New-TempRepo {
        param([switch]$WithRemote)
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("wt-test-" + [guid]::NewGuid().ToString('N').Substring(0, 10))
        $main = Join-Path $root 'main'
        $base = Join-Path $root 'main.worktrees'
        New-Item -ItemType Directory -Force -Path $main | Out-Null
        Push-Location $main
        try {
            git init -b main -q
            git config user.email 'aseemgaurav@microsoft.com'
            git config user.name 'Test User'
            Set-Content -Path 'readme.md' -Value 'hello'
            git add -A
            git commit -q -m 'init'
            if ($WithRemote) {
                $remote = Join-Path $root 'origin.git'
                git init --bare -q $remote
                git remote add origin $remote
                git push -q -u origin main
            }
        }
        finally { Pop-Location }
        [pscustomobject]@{ Root = $root; Main = $main; Base = $base; Remote = (Join-Path $root 'origin.git') }
    }

    # Invoke worktree.ps1 with cwd set to $WorkingDir (defaults to the repo main
    # worktree). Returns captured output + exit code.
    function Invoke-Wt {
        param(
            [Parameter(Mandatory)] $Repo,
            [Parameter(Mandatory)][string[]] $WtArgs,
            [string] $WorkingDir
        )
        if (-not $WorkingDir) { $WorkingDir = $Repo.Main }
        Push-Location $WorkingDir
        try {
            $out = pwsh -NoProfile -File $script:ScriptPath @WtArgs -WorktreesBase $Repo.Base 2>&1 | Out-String
        }
        finally { Pop-Location }
        [pscustomobject]@{ Output = $out; Code = $LASTEXITCODE }
    }

    # Create a worktree as test setup (always from the temp repo).
    function New-WorktreeInRepo {
        param([Parameter(Mandatory)] $Repo, [Parameter(Mandatory)][string] $WtName)
        $r = Invoke-Wt -Repo $Repo -WtArgs @('create', $WtName)
        if ($r.Code -ne 0) { throw "setup create '$WtName' failed: $($r.Output)" }
        Join-Path $Repo.Base $WtName
    }

    function Remove-Repo { param($Repo) Remove-Item -Recurse -Force $Repo.Root -ErrorAction SilentlyContinue }
}

Describe 'worktree.ps1' {

    Context 'create' {
        It 'creates a worktree on a users/<alias>/<name> branch' {
            $repo = New-TempRepo
            try {
                $r = Invoke-Wt -Repo $repo -WtArgs @('create', 'feature-a')
                $r.Code | Should -Be 0
                $r.Output | Should -Match 'users/aseemgaurav/feature-a'
                (Test-Path (Join-Path $repo.Base 'feature-a')) | Should -BeTrue
                (git -C (Join-Path $repo.Base 'feature-a') rev-parse --abbrev-ref HEAD) | Should -Be 'users/aseemgaurav/feature-a'
            }
            finally { Remove-Repo $repo }
        }

        It 'rejects an invalid name with a path separator' {
            $repo = New-TempRepo
            try {
                $r = Invoke-Wt -Repo $repo -WtArgs @('create', 'bad/name')
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'invalid path character'
            }
            finally { Remove-Repo $repo }
        }

        It 'rejects a name containing ".."' {
            $repo = New-TempRepo
            try {
                $r = Invoke-Wt -Repo $repo -WtArgs @('create', 'a..b')
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'must not contain'
            }
            finally { Remove-Repo $repo }
        }

        It 'refuses when the branch already exists' {
            $repo = New-TempRepo
            try {
                New-WorktreeInRepo $repo 'dup' | Out-Null
                $r = Invoke-Wt -Repo $repo -WtArgs @('create', 'dup')
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'already exists'
            }
            finally { Remove-Repo $repo }
        }

        It 'refuses a missing base branch' {
            $repo = New-TempRepo
            try {
                $r = Invoke-Wt -Repo $repo -WtArgs @('create', 'feat', '-BaseBranch', 'nope')
                $r.Code | Should -Be 1
                $r.Output | Should -Match "Base branch 'nope' does not exist"
            }
            finally { Remove-Repo $repo }
        }

        It 'pulls the latest base branch from origin before creating' {
            $repo = New-TempRepo -WithRemote
            try {
                # Advance origin/main with a new commit, then rewind local main so it is stale.
                Push-Location $repo.Main
                try {
                    Set-Content -Path 'newfile.md' -Value 'latest'
                    git add -A
                    git commit -q -m 'advance'
                    git push -q origin main
                    git reset --hard HEAD~1 -q
                }
                finally { Pop-Location }

                $r = Invoke-Wt -Repo $repo -WtArgs @('create', 'feat-latest')
                $r.Code | Should -Be 0
                # The new worktree must contain the commit that only existed on origin.
                (Test-Path (Join-Path $repo.Base 'feat-latest\newfile.md')) | Should -BeTrue
            }
            finally { Remove-Repo $repo }
        }
    }

    Context 'alias detection' {
        It 'fails clearly when user.email is not set' {
            $repo = New-TempRepo
            $emptyCfg = Join-Path $repo.Root 'empty.gitconfig'
            Set-Content -Path $emptyCfg -Value ''
            $savedGlobal = $env:GIT_CONFIG_GLOBAL; $savedSystem = $env:GIT_CONFIG_SYSTEM
            try {
                Push-Location $repo.Main; git config --unset user.email; Pop-Location
                $env:GIT_CONFIG_GLOBAL = $emptyCfg
                $env:GIT_CONFIG_SYSTEM = $emptyCfg
                $r = Invoke-Wt -Repo $repo -WtArgs @('create', 'feat')
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'user.email is not configured'
            }
            finally {
                $env:GIT_CONFIG_GLOBAL = $savedGlobal; $env:GIT_CONFIG_SYSTEM = $savedSystem
                Remove-Repo $repo
            }
        }
    }

    Context 'branch' {
        It 'binds a detached worktree onto a users/<alias>/<name> branch' {
            $repo = New-TempRepo
            try {
                $commit = git -C $repo.Main rev-parse HEAD
                $det = Join-Path $repo.Base 'det'
                New-Item -ItemType Directory -Force -Path $repo.Base | Out-Null
                git -C $repo.Main worktree add --detach $det $commit -q
                $r = Invoke-Wt -Repo $repo -WtArgs @('branch', 'det') -WorkingDir $det
                $r.Code | Should -Be 0
                (git -C $det rev-parse --abbrev-ref HEAD) | Should -Be 'users/aseemgaurav/det'
            }
            finally { Remove-Repo $repo }
        }

        It 'refuses to bind when the worktree is already on a branch' {
            $repo = New-TempRepo
            try {
                $wt = New-WorktreeInRepo $repo 'onbranch'
                $r = Invoke-Wt -Repo $repo -WtArgs @('branch', 'onbranch') -WorkingDir $wt
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'only applies to a detached HEAD'
            }
            finally { Remove-Repo $repo }
        }
    }

    Context 'remove' {
        It 'refuses to remove a worktree with uncommitted changes' {
            $repo = New-TempRepo
            try {
                $wt = New-WorktreeInRepo $repo 'dirty'
                Set-Content -Path (Join-Path $wt 'new.txt') -Value 'x'
                $r = Invoke-Wt -Repo $repo -WtArgs @('remove', 'dirty')
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'uncommitted changes'
            }
            finally { Remove-Repo $repo }
        }

        It 'requires typed confirmation when the branch has unpushed commits' {
            $repo = New-TempRepo
            try {
                New-WorktreeInRepo $repo 'unp' | Out-Null
                $r = Invoke-Wt -Repo $repo -WtArgs @('remove', 'unp')
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'confirmation did not match'
            }
            finally { Remove-Repo $repo }
        }

        It 'removes a clean pushed worktree and keeps the branch' {
            $repo = New-TempRepo -WithRemote
            try {
                $wt = New-WorktreeInRepo $repo 'pushed'
                git -C $wt push -q -u origin users/aseemgaurav/pushed
                $r = Invoke-Wt -Repo $repo -WtArgs @('remove', 'pushed')
                $r.Code | Should -Be 0
                (Test-Path $wt) | Should -BeFalse
                (git -C $repo.Main branch --list users/aseemgaurav/pushed) | Should -Match 'users/aseemgaurav/pushed'
            }
            finally { Remove-Repo $repo }
        }

        It 'requires typed confirmation to remove a detached worktree (protects orphan commits)' {
            $repo = New-TempRepo
            try {
                $commit = git -C $repo.Main rev-parse HEAD
                $det = Join-Path $repo.Base 'detrm'
                New-Item -ItemType Directory -Force -Path $repo.Base | Out-Null
                git -C $repo.Main worktree add --detach $det $commit -q
                # Make a clean commit on the detached HEAD (orphan work).
                Set-Content -Path (Join-Path $det 'orphan.txt') -Value 'x'
                git -C $det add -A; git -C $det commit -q -m 'orphan work'
                # Without confirmation -> refused.
                $r1 = Invoke-Wt -Repo $repo -WtArgs @('remove', 'detrm')
                $r1.Code | Should -Be 1
                $r1.Output | Should -Match 'DETACHED'
                (Test-Path $det) | Should -BeTrue
                # With confirmation -> removed.
                $r2 = Invoke-Wt -Repo $repo -WtArgs @('remove', 'detrm', '-ConfirmName', 'detrm')
                $r2.Code | Should -Be 0
                (Test-Path $det) | Should -BeFalse
            }
            finally { Remove-Repo $repo }
        }

        It 'refuses to remove a non-existent worktree' {            $repo = New-TempRepo
            try {
                $r = Invoke-Wt -Repo $repo -WtArgs @('remove', 'ghost')
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'No registered worktree'
            }
            finally { Remove-Repo $repo }
        }
    }

    Context 'push guards' {
        It 'refuses to push a protected branch' {
            $repo = New-TempRepo -WithRemote
            try {
                $r = Invoke-Wt -Repo $repo -WtArgs @('push', '-ConfirmBranch', 'main')
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'protected branch'
            }
            finally { Remove-Repo $repo }
        }

        It 'pushes a users/<alias>/<name> branch after matching confirmation' {
            $repo = New-TempRepo -WithRemote
            try {
                $wt = New-WorktreeInRepo $repo 'tp'
                $r = Invoke-Wt -Repo $repo -WtArgs @('push', '-ConfirmBranch', 'users/aseemgaurav/tp') -WorkingDir $wt
                $r.Code | Should -Be 0
                $r.Output | Should -Match 'Pushed'
                (git -C $repo.Main ls-remote --heads origin users/aseemgaurav/tp) | Should -Match 'users/aseemgaurav/tp'
            }
            finally { Remove-Repo $repo }
        }

        It 'cancels the push when confirmation does not match' {
            $repo = New-TempRepo -WithRemote
            try {
                $wt = New-WorktreeInRepo $repo 'tp2'
                $r = Invoke-Wt -Repo $repo -WtArgs @('push', '-ConfirmBranch', 'wrong') -WorkingDir $wt
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'Push cancelled'
            }
            finally { Remove-Repo $repo }
        }
    }

    Context 'list / health' {
        It 'lists worktrees including newly created ones' {
            $repo = New-TempRepo
            try {
                New-WorktreeInRepo $repo 'l1' | Out-Null
                $r = Invoke-Wt -Repo $repo -WtArgs @('list')
                $r.Code | Should -Be 0
                $r.Output | Should -Match 'l1'
            }
            finally { Remove-Repo $repo }
        }

        It 'health reports a detached worktree' {
            $repo = New-TempRepo
            try {
                $commit = git -C $repo.Main rev-parse HEAD
                New-Item -ItemType Directory -Force -Path $repo.Base | Out-Null
                git -C $repo.Main worktree add --detach (Join-Path $repo.Base 'dd') $commit -q
                $r = Invoke-Wt -Repo $repo -WtArgs @('health')
                $r.Code | Should -Be 0
                $r.Output | Should -Match 'DETACHED'
            }
            finally { Remove-Repo $repo }
        }
    }
}

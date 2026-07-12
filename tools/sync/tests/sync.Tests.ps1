#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for sync.ps1.

    Each test builds a throwaway git repo under this tool's test scratch area
    (no network; origin is a local bare remote only when requested). sync.ps1
    operates on the ambient git repository, so every invocation sets cwd inside
    the throwaway repo.
#>

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'sync.ps1'
    $script:ScratchRoot = Join-Path $PSScriptRoot '.scratch'

    function New-TempRepo {
        param([switch]$WithRemote)
        $root = Join-Path $script:ScratchRoot ("sync-test-" + [guid]::NewGuid().ToString('N').Substring(0, 10))
        $main = Join-Path $root 'main'
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
        [pscustomobject]@{ Root = $root; Main = $main; Remote = (Join-Path $root 'origin.git') }
    }

    function Invoke-Sync {
        param(
            [Parameter(Mandatory)] $Repo,
            [Parameter(Mandatory)][string[]] $SyncArgs,
            [string] $WorkingDir
        )
        if (-not $WorkingDir) { $WorkingDir = $Repo.Main }
        Push-Location $WorkingDir
        try {
            $out = pwsh -NoProfile -File $script:ScriptPath @SyncArgs 2>&1 | Out-String
        }
        finally { Pop-Location }
        [pscustomobject]@{ Output = $out; Code = $LASTEXITCODE }
    }

    function Add-Commit {
        param(
            [Parameter(Mandatory)][string]$RepoPath,
            [Parameter(Mandatory)][string]$FileName,
            [Parameter(Mandatory)][string]$Value,
            [Parameter(Mandatory)][string]$Message
        )
        Set-Content -Path (Join-Path $RepoPath $FileName) -Value $Value
        git -C $RepoPath add -A
        git -C $RepoPath commit -q -m $Message
    }

    function New-RemoteClone {
        param([Parameter(Mandatory)] $Repo)
        $clone = Join-Path $Repo.Root ("remote-clone-" + [guid]::NewGuid().ToString('N').Substring(0, 6))
        git clone -q $Repo.Remote $clone
        git -C $clone config user.email 'aseemgaurav@microsoft.com'
        git -C $clone config user.name 'Test User'
        $clone
    }

    function Remove-Repo {
        param($Repo)
        Remove-Item -Recurse -Force $Repo.Root -ErrorAction SilentlyContinue
    }
}

Describe 'sync.ps1' {

    Context 'preview' {
        It 'reports ahead/behind for upstream and base' {
            $repo = New-TempRepo -WithRemote
            try {
                Push-Location $repo.Main
                try {
                    git switch -q -c feature
                    git push -q -u origin feature
                    Add-Commit -RepoPath $repo.Main -FileName 'local.txt' -Value 'local' -Message 'local feature'
                }
                finally { Pop-Location }

                $clone = New-RemoteClone $repo
                git -C $clone switch -q feature
                Add-Commit -RepoPath $clone -FileName 'remote-feature.txt' -Value 'remote' -Message 'remote feature'
                git -C $clone push -q origin feature
                git -C $clone switch -q main
                Add-Commit -RepoPath $clone -FileName 'remote-main.txt' -Value 'base' -Message 'remote base'
                git -C $clone push -q origin main

                $r = Invoke-Sync -Repo $repo -SyncArgs @('preview')
                $r.Code | Should -Be 0
                $r.Output | Should -Match 'Upstream: origin/feature \(ahead 1, behind 1\)'
                $r.Output | Should -Match 'Base:\s+origin/main \(ahead 1, behind 1\)'
                $r.Output | Should -Match 'Preview only'
            }
            finally { Remove-Repo $repo }
        }
    }

    Context 'run' {
        It 'fast-forwards when upstream is ahead' {
            $repo = New-TempRepo -WithRemote
            try {
                Push-Location $repo.Main
                try {
                    git switch -q -c feature
                    git push -q -u origin feature
                }
                finally { Pop-Location }

                $clone = New-RemoteClone $repo
                git -C $clone switch -q feature
                Add-Commit -RepoPath $clone -FileName 'remote.txt' -Value 'remote' -Message 'advance feature'
                git -C $clone push -q origin feature

                $r = Invoke-Sync -Repo $repo -SyncArgs @('run')
                $r.Code | Should -Be 0
                $r.Output | Should -Match 'Fast-forwarded'
                Test-Path (Join-Path $repo.Main 'remote.txt') | Should -BeTrue
                git -C $repo.Main rev-parse HEAD | Should -Be (git -C $repo.Main rev-parse origin/feature)
            }
            finally { Remove-Repo $repo }
        }

        It 'refuses detached HEAD' {
            $repo = New-TempRepo
            try {
                git -C $repo.Main switch --detach -q HEAD
                $r = Invoke-Sync -Repo $repo -SyncArgs @('run')
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'HEAD is detached'
            }
            finally { Remove-Repo $repo }
        }

        It 'refuses a dirty working tree without -Autostash' {
            $repo = New-TempRepo -WithRemote
            try {
                Set-Content -Path (Join-Path $repo.Main 'dirty.txt') -Value 'dirty'
                $r = Invoke-Sync -Repo $repo -SyncArgs @('run')
                $r.Code | Should -Be 1
                $r.Output | Should -Match 'uncommitted changes'
            }
            finally { Remove-Repo $repo }
        }

        It '-Autostash preserves uncommitted changes across a sync' {
            $repo = New-TempRepo -WithRemote
            try {
                Push-Location $repo.Main
                try {
                    git switch -q -c feature
                    git push -q -u origin feature
                }
                finally { Pop-Location }

                $clone = New-RemoteClone $repo
                git -C $clone switch -q feature
                Add-Commit -RepoPath $clone -FileName 'remote.txt' -Value 'remote' -Message 'advance feature'
                git -C $clone push -q origin feature

                Set-Content -Path (Join-Path $repo.Main 'local-uncommitted.txt') -Value 'keep me'
                $r = Invoke-Sync -Repo $repo -SyncArgs @('run', '-Autostash')
                $r.Code | Should -Be 0
                $r.Output | Should -Match 'Autostash restored'
                Test-Path (Join-Path $repo.Main 'remote.txt') | Should -BeTrue
                Get-Content -Path (Join-Path $repo.Main 'local-uncommitted.txt') | Should -Be 'keep me'
                git -C $repo.Main status --porcelain | Should -Match 'local-uncommitted.txt'
            }
            finally { Remove-Repo $repo }
        }

        It '-Rebase places local commits on top of base' {
            $repo = New-TempRepo -WithRemote
            try {
                Push-Location $repo.Main
                try {
                    git switch -q -c feature
                    Add-Commit -RepoPath $repo.Main -FileName 'feature.txt' -Value 'feature' -Message 'feature work'
                    git switch -q main
                    Add-Commit -RepoPath $repo.Main -FileName 'base.txt' -Value 'base' -Message 'base work'
                    git push -q origin main
                    git switch -q feature
                }
                finally { Pop-Location }

                $r = Invoke-Sync -Repo $repo -SyncArgs @('run', '-Rebase')
                $r.Code | Should -Be 0
                $r.Output | Should -Match 'Rebased'
                git -C $repo.Main rev-parse 'HEAD^' | Should -Be (git -C $repo.Main rev-parse origin/main)
                Test-Path (Join-Path $repo.Main 'feature.txt') | Should -BeTrue
                Test-Path (Join-Path $repo.Main 'base.txt') | Should -BeTrue
            }
            finally { Remove-Repo $repo }
        }
    }
}

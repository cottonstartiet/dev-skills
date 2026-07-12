#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for clean.ps1.

    Each test builds a throwaway git repo under this test folder (no network, no
    origin unless the test creates a local bare "remote"). clean.ps1 operates on
    the ambient git repository (the child process cwd), so every invocation runs
    with its working directory inside the throwaway repo.
#>

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'clean.ps1'
    $script:RunRoot = Join-Path $PSScriptRoot '.test-runs'
    New-Item -ItemType Directory -Force -Path $script:RunRoot | Out-Null

    function New-TempRepo {
        param([switch]$WithRemote)
        $root = Join-Path $script:RunRoot ("clean-test-" + [guid]::NewGuid().ToString('N').Substring(0, 10))
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

    function Invoke-Clean {
        param(
            [Parameter(Mandatory)] $Repo,
            [Parameter(Mandatory)][string[]] $CleanArgs,
            [string] $WorkingDir
        )
        if (-not $WorkingDir) { $WorkingDir = $Repo.Main }
        Push-Location $WorkingDir
        try {
            $out = pwsh -NoProfile -File $script:ScriptPath @CleanArgs 2>&1 | Out-String
        }
        finally { Pop-Location }
        [pscustomobject]@{ Output = $out; Code = $LASTEXITCODE }
    }

    function New-MergedBranch {
        param([Parameter(Mandatory)] $Repo, [Parameter(Mandatory)][string] $Branch)
        Push-Location $Repo.Main
        try {
            git switch -q -c $Branch
            Set-Content -Path "$Branch.txt" -Value $Branch
            git add -A
            git commit -q -m "add $Branch"
            git switch -q main
            git merge --no-ff -q $Branch -m "merge $Branch"
        }
        finally { Pop-Location }
    }

    function New-UnmergedBranch {
        param([Parameter(Mandatory)] $Repo, [Parameter(Mandatory)][string] $Branch)
        Push-Location $Repo.Main
        try {
            git switch -q -c $Branch
            Set-Content -Path "$Branch.txt" -Value $Branch
            git add -A
            git commit -q -m "add $Branch"
            git switch -q main
        }
        finally { Pop-Location }
    }

    function New-GoneUpstreamBranch {
        param([Parameter(Mandatory)] $Repo, [Parameter(Mandatory)][string] $Branch)
        Push-Location $Repo.Main
        try {
            git switch -q -c $Branch
            Set-Content -Path "$Branch.txt" -Value $Branch
            git add -A
            git commit -q -m "add $Branch"
            git push -q -u origin $Branch
            git switch -q main
            git push -q origin --delete $Branch
            git fetch -q --prune
        }
        finally { Pop-Location }
    }

    function Remove-Repo { param($Repo) Remove-Item -Recurse -Force $Repo.Root -ErrorAction SilentlyContinue }
}

AfterAll {
    Remove-Item -Recurse -Force $script:RunRoot -ErrorAction SilentlyContinue
}

Describe 'clean.ps1' {

    It 'lists a merged branch as a candidate' {
        $repo = New-TempRepo
        try {
            New-MergedBranch -Repo $repo -Branch 'feature-merged'
            $r = Invoke-Clean -Repo $repo -CleanArgs @('list')
            $r.Code | Should -Be 0
            $r.Output | Should -Match 'feature-merged'
            $r.Output | Should -Match 'merged'
        }
        finally { Remove-Repo $repo }
    }

    It 'does not list or delete the current branch' {
        $repo = New-TempRepo
        try {
            Push-Location $repo.Main
            try {
                git switch -q -c 'current-work'
                Set-Content -Path 'current.txt' -Value 'current'
                git add -A
                git commit -q -m 'current work'
            }
            finally { Pop-Location }

            $list = Invoke-Clean -Repo $repo -CleanArgs @('list')
            $list.Code | Should -Be 0
            $list.Output | Should -Not -Match 'current-work'

            $delete = Invoke-Clean -Repo $repo -CleanArgs @('delete', '-Yes')
            $delete.Code | Should -Be 0
            (git -C $repo.Main branch --list current-work) | Should -Match 'current-work'
        }
        finally { Remove-Repo $repo }
    }

    It 'never deletes a protected branch' {
        $repo = New-TempRepo
        try {
            git -C $repo.Main branch develop
            $r = Invoke-Clean -Repo $repo -CleanArgs @('delete', '-Yes')
            $r.Code | Should -Be 0
            $r.Output | Should -Match 'protected branch'
            (git -C $repo.Main branch --list develop) | Should -Match 'develop'
        }
        finally { Remove-Repo $repo }
    }

    It 'refuses to delete a branch with unmerged commits without Force' {
        $repo = New-TempRepo -WithRemote
        try {
            New-GoneUpstreamBranch -Repo $repo -Branch 'gone-unmerged'
            $r = Invoke-Clean -Repo $repo -CleanArgs @('delete', '-Yes')
            $r.Code | Should -Be 1
            $r.Output | Should -Match 'unmerged'
            (git -C $repo.Main branch --list gone-unmerged) | Should -Match 'gone-unmerged'
        }
        finally { Remove-Repo $repo }
    }

    It 'deletes a merged branch in delete mode with Yes and leaves other branches intact' {
        $repo = New-TempRepo
        try {
            New-MergedBranch -Repo $repo -Branch 'delete-me'
            New-UnmergedBranch -Repo $repo -Branch 'keep-me'
            $r = Invoke-Clean -Repo $repo -CleanArgs @('delete', '-Yes')
            $r.Code | Should -Be 0
            $r.Output | Should -Match "Deleted 'delete-me'"
            (git -C $repo.Main branch --list delete-me) | Should -BeNullOrEmpty
            (git -C $repo.Main branch --list keep-me) | Should -Match 'keep-me'
        }
        finally { Remove-Repo $repo }
    }

    It 'detects a gone-upstream branch' {
        $repo = New-TempRepo -WithRemote
        try {
            New-GoneUpstreamBranch -Repo $repo -Branch 'gone-branch'
            $r = Invoke-Clean -Repo $repo -CleanArgs @('list')
            $r.Code | Should -Be 0
            $r.Output | Should -Match 'gone-branch'
            $r.Output | Should -Match 'gone-upstream'
        }
        finally { Remove-Repo $repo }
    }
}

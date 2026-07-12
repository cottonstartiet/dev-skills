#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for prprep.ps1.

    Each test builds a throwaway git repo under this tool's test scratch
    directory. prprep.ps1 operates on the ambient git repository (the child
    process cwd), so every invocation runs with cwd inside the throwaway repo.
#>

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'prprep.ps1'
    $script:ScratchRoot = Join-Path $PSScriptRoot '.scratch'
    New-Item -ItemType Directory -Force -Path $script:ScratchRoot | Out-Null

    function New-TempRepo {
        param([switch]$WithRemote)
        $root = Join-Path $script:ScratchRoot ("pp-test-" + [guid]::NewGuid().ToString('N').Substring(0, 10))
        $main = Join-Path $root 'repo'
        New-Item -ItemType Directory -Force -Path $main | Out-Null
        Push-Location $main
        try {
            git init -b main -q
            git config user.email 'aseemgaurav@microsoft.com'
            git config user.name 'Test User'
            Set-Content -Path 'readme.md' -Value 'hello'
            git add -A
            git commit -q -m 'chore: initial commit'
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

    function Add-FeatureCommits {
        param([Parameter(Mandatory)] $Repo)
        Push-Location $Repo.Main
        try {
            git switch -c users/aseemgaurav/prprep-test -q
            New-Item -ItemType Directory -Force -Path 'src' | Out-Null
            Set-Content -Path 'src\feature.txt' -Value 'feature'
            git add -A
            git commit -q -m 'feat: add generated widget'

            Set-Content -Path 'src\bugfix.txt' -Value 'fix'
            git add -A
            git commit -q -m 'fix(parser): handle null input'
        }
        finally { Pop-Location }
    }

    function Invoke-Prprep {
        param(
            [Parameter(Mandatory)] $Repo,
            [Parameter(Mandatory)][string[]] $PrprepArgs,
            [string] $WorkingDir
        )
        if (-not $WorkingDir) { $WorkingDir = $Repo.Main }
        Push-Location $WorkingDir
        try {
            $out = pwsh -NoProfile -File $script:ScriptPath @PrprepArgs 2>&1 | Out-String
        }
        finally { Pop-Location }
        [pscustomobject]@{ Output = $out; Code = $LASTEXITCODE }
    }

    function Remove-Repo { param($Repo) Remove-Item -Recurse -Force $Repo.Root -ErrorAction SilentlyContinue }
}

AfterAll {
    Remove-Item -Recurse -Force $script:ScratchRoot -ErrorAction SilentlyContinue
}

Describe 'prprep.ps1' {

    It 'generates a draft that groups feat and fix commits and lists changed files' {
        $repo = New-TempRepo
        try {
            Add-FeatureCommits $repo
            $r = Invoke-Prprep -Repo $repo -PrprepArgs @('draft')
            $r.Code | Should -Be 0
            $r.Output | Should -Match '## Changes'
            $r.Output | Should -Match '### feat'
            $r.Output | Should -Match 'add generated widget'
            $r.Output | Should -Match '### fix'
            $r.Output | Should -Match 'handle null input'
            $r.Output | Should -Match 'src/feature.txt'
            $r.Output | Should -Match 'src/bugfix.txt'

            $defaultOut = Join-Path $repo.Main 'PR_DESCRIPTION.md'
            (Test-Path $defaultOut) | Should -BeTrue
            (Get-Content -LiteralPath $defaultOut -Raw) | Should -Match '## Testing/Checklist'
        }
        finally { Remove-Repo $repo }
    }

    It 'writes PR_DESCRIPTION.md by default and redirects with -Out' {
        $repo = New-TempRepo
        try {
            Add-FeatureCommits $repo
            $r = Invoke-Prprep -Repo $repo -PrprepArgs @('draft', '-Out', 'docs\PR.md')
            $r.Code | Should -Be 0
            (Test-Path (Join-Path $repo.Main 'docs\PR.md')) | Should -BeTrue
            (Test-Path (Join-Path $repo.Main 'PR_DESCRIPTION.md')) | Should -BeFalse
            (Get-Content -LiteralPath (Join-Path $repo.Main 'docs\PR.md') -Raw) | Should -Match '### feat'
        }
        finally { Remove-Repo $repo }
    }

    It '-NoWrite prints the draft but writes no file' {
        $repo = New-TempRepo
        try {
            Add-FeatureCommits $repo
            $r = Invoke-Prprep -Repo $repo -PrprepArgs @('draft', '-NoWrite')
            $r.Code | Should -Be 0
            $r.Output | Should -Match '### feat'
            $r.Output | Should -Match 'Printed PR draft only'
            (Test-Path (Join-Path $repo.Main 'PR_DESCRIPTION.md')) | Should -BeFalse
        }
        finally { Remove-Repo $repo }
    }

    It 'reports gracefully when the current branch is the base branch' {
        $repo = New-TempRepo
        try {
            $r = Invoke-Prprep -Repo $repo -PrprepArgs @('draft')
            $r.Code | Should -Be 0
            $r.Output | Should -Match 'base branch'
            (Test-Path (Join-Path $repo.Main 'PR_DESCRIPTION.md')) | Should -BeFalse
        }
        finally { Remove-Repo $repo }
    }

    It 'reports gracefully when there are no commits ahead of base' {
        $repo = New-TempRepo
        try {
            Push-Location $repo.Main
            try { git switch -c users/aseemgaurav/empty -q }
            finally { Pop-Location }

            $r = Invoke-Prprep -Repo $repo -PrprepArgs @('draft')
            $r.Code | Should -Be 0
            $r.Output | Should -Match 'No commits ahead'
            (Test-Path (Join-Path $repo.Main 'PR_DESCRIPTION.md')) | Should -BeFalse
        }
        finally { Remove-Repo $repo }
    }

    It 'never pushes or changes remote branch state' {
        $repo = New-TempRepo -WithRemote
        try {
            Add-FeatureCommits $repo
            $beforeRemote = git -C $repo.Main ls-remote --heads origin | Out-String
            $beforeBranch = git -C $repo.Main rev-parse --abbrev-ref HEAD
            $beforeHead = git -C $repo.Main rev-parse HEAD

            $r = Invoke-Prprep -Repo $repo -PrprepArgs @('draft', '-NoWrite')
            $r.Code | Should -Be 0

            $afterRemote = git -C $repo.Main ls-remote --heads origin | Out-String
            $afterBranch = git -C $repo.Main rev-parse --abbrev-ref HEAD
            $afterHead = git -C $repo.Main rev-parse HEAD

            $afterRemote | Should -Be $beforeRemote
            $afterRemote | Should -Not -Match 'users/aseemgaurav/prprep-test'
            $afterBranch | Should -Be $beforeBranch
            $afterHead | Should -Be $beforeHead
            (git -C $repo.Main status --porcelain) | Should -BeNullOrEmpty
        }
        finally { Remove-Repo $repo }
    }
}

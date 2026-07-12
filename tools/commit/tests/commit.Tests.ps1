#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for commit.ps1.

    Each test builds a throwaway git repo in a temp directory. commit.ps1 operates
    on the ambient git repository (the child process cwd), so every invocation
    runs with its working directory inside the temp repo.
#>

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'commit.ps1'

    function New-TempRepo {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("commit-test-" + [guid]::NewGuid().ToString('N').Substring(0, 10))
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
        }
        finally { Pop-Location }
        [pscustomobject]@{ Root = $root; Main = $main }
    }

    function Invoke-CommitTool {
        param(
            [Parameter(Mandatory)] $Repo,
            [Parameter(Mandatory)][string[]] $CommitArgs
        )
        Push-Location $Repo.Main
        try {
            $out = pwsh -NoProfile -File $script:ScriptPath @CommitArgs 2>&1 | Out-String
        }
        finally { Pop-Location }
        [pscustomobject]@{ Output = $out; Code = $LASTEXITCODE }
    }

    function Add-StagedChange {
        param(
            [Parameter(Mandatory)] $Repo,
            [string] $FileName = 'readme.md',
            [string] $Value = 'changed'
        )
        Set-Content -Path (Join-Path $Repo.Main $FileName) -Value $Value
        git -C $Repo.Main add -A
    }

    function Get-LastCommitMessage {
        param([Parameter(Mandatory)] $Repo)
        (git -C $Repo.Main log -1 --pretty=%B | Out-String).Trim()
    }

    function Remove-Repo { param($Repo) Remove-Item -Recurse -Force $Repo.Root -ErrorAction SilentlyContinue }
}

Describe 'commit.ps1' {

    It 'builds a correct scoped header and creates a commit' {
        $repo = New-TempRepo
        try {
            Add-StagedChange -Repo $repo -Value 'feature'
            $r = Invoke-CommitTool -Repo $repo -CommitArgs @('create', '-Type', 'feat', '-Scope', 'api', '-Subject', 'add user lookup')
            $r.Code | Should -Be 0
            $r.Output | Should -Match 'Committed: feat\(api\): add user lookup'
            (Get-LastCommitMessage -Repo $repo) | Should -Be 'feat(api): add user lookup'
        }
        finally { Remove-Repo $repo }
    }

    It 'adds breaking marker and BREAKING CHANGE footer' {
        $repo = New-TempRepo
        try {
            Add-StagedChange -Repo $repo -Value 'breaking'
            $r = Invoke-CommitTool -Repo $repo -CommitArgs @('create', '-Type', 'feat', '-Scope', 'config', '-Subject', 'rename provider', '-Breaking', '-BreakingDescription', 'providerName replaces name')
            $r.Code | Should -Be 0
            $message = Get-LastCommitMessage -Repo $repo
            $message | Should -Match '^feat\(config\)!: rename provider'
            $message | Should -Match 'BREAKING CHANGE: providerName replaces name'
        }
        finally { Remove-Repo $repo }
    }

    It 'rejects an invalid type' {
        $repo = New-TempRepo
        try {
            Add-StagedChange -Repo $repo -Value 'invalid'
            $r = Invoke-CommitTool -Repo $repo -CommitArgs @('create', '-Type', 'bug', '-Subject', 'handle issue')
            $r.Code | Should -Be 1
            $r.Output | Should -Match "Invalid commit type 'bug'"
        }
        finally { Remove-Repo $repo }
    }

    It 'rejects an over-length subject' {
        $repo = New-TempRepo
        try {
            Add-StagedChange -Repo $repo -Value 'long'
            $longSubject = 'this subject is intentionally far too long for the conventional commit header limit'
            $r = Invoke-CommitTool -Repo $repo -CommitArgs @('create', '-Type', 'feat', '-Subject', $longSubject)
            $r.Code | Should -Be 1
            $r.Output | Should -Match 'maximum is 72'
        }
        finally { Remove-Repo $repo }
    }

    It 'rejects an empty subject' {
        $repo = New-TempRepo
        try {
            Add-StagedChange -Repo $repo -Value 'empty'
            $r = Invoke-CommitTool -Repo $repo -CommitArgs @('create', '-Type', 'fix', '-Subject', '   ')
            $r.Code | Should -Be 1
            $r.Output | Should -Match 'non-empty -Subject'
        }
        finally { Remove-Repo $repo }
    }

    It 'fails fast (does not hang) when -Subject is omitted in non-interactive mode' {
        $repo = New-TempRepo
        try {
            Add-StagedChange -Repo $repo -Value 'nosubject'
            $r = Invoke-CommitTool -Repo $repo -CommitArgs @('create', '-Type', 'feat')
            $r.Code | Should -Be 1
            $r.Output | Should -Match 'non-empty -Subject'
        }
        finally { Remove-Repo $repo }
    }

    It 'fails cleanly when nothing is staged' {
        $repo = New-TempRepo
        try {
            $r = Invoke-CommitTool -Repo $repo -CommitArgs @('create', '-Type', 'chore', '-Subject', 'update metadata')
            $r.Code | Should -Be 1
            $r.Output | Should -Match 'Nothing staged to commit'
        }
        finally { Remove-Repo $repo }
    }

    It 'stages and commits untracked changes with AddAll' {
        $repo = New-TempRepo
        try {
            Set-Content -Path (Join-Path $repo.Main 'new-file.txt') -Value 'new'
            $r = Invoke-CommitTool -Repo $repo -CommitArgs @('create', '-Type', 'chore', '-Subject', 'add generated file', '-AddAll')
            $r.Code | Should -Be 0
            (Get-LastCommitMessage -Repo $repo) | Should -Be 'chore: add generated file'
            (git -C $repo.Main show --name-only --pretty= HEAD | Out-String) | Should -Match 'new-file.txt'
        }
        finally { Remove-Repo $repo }
    }
}

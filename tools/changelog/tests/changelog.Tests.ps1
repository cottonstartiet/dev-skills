#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Pester tests for changelog.ps1.

    Each test builds a throwaway git repo in a temp directory. changelog.ps1
    operates on the ambient git repository, so every invocation runs with cwd
    inside the temp repo.
#>

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'changelog.ps1'

    function New-TempRepo {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("cl-test-" + [guid]::NewGuid().ToString('N').Substring(0, 10))
        $main = Join-Path $root 'main'
        New-Item -ItemType Directory -Force -Path $main | Out-Null
        Push-Location $main
        try {
            git init -b main -q
            git config user.email 'aseemgaurav@microsoft.com'
            git config user.name 'Test User'
            Set-Content -Path 'readme.md' -Value 'hello'
            git add -A
            git commit -q -m 'chore: initial'
        }
        finally { Pop-Location }
        [pscustomobject]@{ Root = $root; Main = $main }
    }

    function Add-Commit {
        param(
            [Parameter(Mandatory)] $Repo,
            [Parameter(Mandatory)][string] $Message,
            [string] $Body
        )
        Push-Location $Repo.Main
        try {
            $file = "change-$([guid]::NewGuid().ToString('N').Substring(0, 10)).txt"
            Set-Content -Path $file -Value $Message
            git add -A
            if ([string]::IsNullOrWhiteSpace($Body)) {
                git commit -q -m $Message
            }
            else {
                git commit -q -m $Message -m $Body
            }
            git rev-parse HEAD
        }
        finally { Pop-Location }
    }

    function Add-Tag {
        param([Parameter(Mandatory)] $Repo, [Parameter(Mandatory)][string] $Name)
        Push-Location $Repo.Main
        try { git tag $Name }
        finally { Pop-Location }
    }

    function Invoke-Changelog {
        param(
            [Parameter(Mandatory)] $Repo,
            [string[]] $Args = @()
        )
        Push-Location $Repo.Main
        try {
            $out = pwsh -NoProfile -File $script:ScriptPath @Args 2>&1 | Out-String
        }
        finally { Pop-Location }
        [pscustomobject]@{ Output = $out; Code = $LASTEXITCODE }
    }

    function Remove-Repo { param($Repo) Remove-Item -Recurse -Force $Repo.Root -ErrorAction SilentlyContinue }
}

Describe 'changelog.ps1' {

    It 'groups Conventional Commits into the correct sections' {
        $repo = New-TempRepo
        try {
            Add-Tag -Repo $repo -Name 'v0.1.0'
            Add-Commit -Repo $repo -Message 'feat: add search' | Out-Null
            Add-Commit -Repo $repo -Message 'fix: repair cache' | Out-Null
            Add-Commit -Repo $repo -Message 'refactor: simplify parser' | Out-Null
            Add-Commit -Repo $repo -Message 'docs: document cli' | Out-Null
            Add-Commit -Repo $repo -Message 'revert: undo old behavior' | Out-Null
            Add-Commit -Repo $repo -Message 'not conventional' | Out-Null

            $r = Invoke-Changelog -Repo $repo -Args @('generate')

            $r.Code | Should -Be 0
            $r.Output | Should -Match '### Added'
            $r.Output | Should -Match 'add search'
            $r.Output | Should -Match '### Fixed'
            $r.Output | Should -Match 'repair cache'
            $r.Output | Should -Match '### Changed'
            $r.Output | Should -Match 'simplify parser'
            $r.Output | Should -Match '### Documentation'
            $r.Output | Should -Match 'document cli'
            $r.Output | Should -Match '### Reverted'
            $r.Output | Should -Match 'undo old behavior'
            $r.Output | Should -Match '### Other'
            $r.Output | Should -Match 'not conventional'
        }
        finally { Remove-Repo $repo }
    }

    It 'dry-run prints the block and does not create or modify CHANGELOG.md' {
        $repo = New-TempRepo
        try {
            Add-Tag -Repo $repo -Name 'v0.1.0'
            Add-Commit -Repo $repo -Message 'feat: add dry run' | Out-Null
            $path = Join-Path $repo.Main 'CHANGELOG.md'

            $r1 = Invoke-Changelog -Repo $repo -Args @('generate')
            $r1.Code | Should -Be 0
            $r1.Output | Should -Match 'add dry run'
            Test-Path -LiteralPath $path | Should -BeFalse

            Set-Content -LiteralPath $path -Value "# Changelog`n`nexisting`n" -NoNewline
            $before = Get-Content -LiteralPath $path -Raw
            $r2 = Invoke-Changelog -Repo $repo -Args @('generate')
            $r2.Code | Should -Be 0
            (Get-Content -LiteralPath $path -Raw) | Should -Be $before
        }
        finally { Remove-Repo $repo }
    }

    It '-Write creates CHANGELOG.md and a second -Write prepends above the previous entry' {
        $repo = New-TempRepo
        try {
            Add-Tag -Repo $repo -Name 'v0.1.0'
            Add-Commit -Repo $repo -Message 'feat: first release' | Out-Null
            $path = Join-Path $repo.Main 'CHANGELOG.md'

            $first = Invoke-Changelog -Repo $repo -Args @('generate', '-Version', '1.0.0', '-Write')
            $first.Code | Should -Be 0
            Test-Path -LiteralPath $path | Should -BeTrue
            $content1 = Get-Content -LiteralPath $path -Raw
            $content1 | Should -Match '# Changelog'
            $content1 | Should -Match '## \[1\.0\.0\] - \d{4}-\d{2}-\d{2}'
            $content1 | Should -Match 'first release'

            Add-Commit -Repo $repo -Message 'fix: second release' | Out-Null
            $second = Invoke-Changelog -Repo $repo -Args @('generate', '-Version', '1.1.0', '-Write')
            $second.Code | Should -Be 0
            $content2 = Get-Content -LiteralPath $path -Raw
            $content2.IndexOf('## [1.1.0]') | Should -BeLessThan $content2.IndexOf('## [1.0.0]')
            $content2 | Should -Match 'first release'
            $content2 | Should -Match 'second release'
        }
        finally { Remove-Repo $repo }
    }

    It '-Version sets the heading and omitted -Version yields Unreleased' {
        $repo = New-TempRepo
        try {
            Add-Tag -Repo $repo -Name 'v0.1.0'
            Add-Commit -Repo $repo -Message 'feat: heading check' | Out-Null

            $unreleased = Invoke-Changelog -Repo $repo -Args @('generate')
            $versioned = Invoke-Changelog -Repo $repo -Args @('generate', '-Version', '2.0.0')

            $unreleased.Code | Should -Be 0
            $versioned.Code | Should -Be 0
            $unreleased.Output | Should -Match '## \[Unreleased\]'
            $versioned.Output | Should -Match '## \[2\.0\.0\] - \d{4}-\d{2}-\d{2}'
        }
        finally { Remove-Repo $repo }
    }

    It 'default range starts after the latest tag' {
        $repo = New-TempRepo
        try {
            Add-Commit -Repo $repo -Message 'feat: old feature' | Out-Null
            Add-Tag -Repo $repo -Name 'v1.0.0'
            Add-Commit -Repo $repo -Message 'fix: new fix' | Out-Null

            $r = Invoke-Changelog -Repo $repo -Args @('generate')

            $r.Code | Should -Be 0
            $r.Output | Should -Match 'new fix'
            $r.Output | Should -Not -Match 'old feature'
            $r.Output | Should -Not -Match 'chore: initial'
        }
        finally { Remove-Repo $repo }
    }

    It 'surfaces breaking-change commits' {
        $repo = New-TempRepo
        try {
            Add-Tag -Repo $repo -Name 'v0.1.0'
            Add-Commit -Repo $repo -Message 'feat!: replace API' | Out-Null
            Add-Commit -Repo $repo -Message 'fix: update contract' -Body 'BREAKING CHANGE: contract now requires v2 clients' | Out-Null

            $r = Invoke-Changelog -Repo $repo -Args @('generate')

            $r.Code | Should -Be 0
            $r.Output | Should -Match '### BREAKING CHANGES'
            $r.Output | Should -Match 'replace API'
            $r.Output | Should -Match 'contract now requires v2 clients'
        }
        finally { Remove-Repo $repo }
    }
}

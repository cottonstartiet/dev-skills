<#
.SYNOPSIS
    Run all changelog skill Pester tests.
.EXAMPLE
    pwsh -NoProfile -File .\tests\run-tests.ps1
#>
[CmdletBinding()]
param([switch]$CI)

$ErrorActionPreference = 'Stop'
Import-Module Pester -MinimumVersion 5.0.0 -Force

$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Output.Verbosity = 'Detailed'
if ($CI) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = (Join-Path $PSScriptRoot 'testresults.xml')
}

Invoke-Pester -Configuration $config

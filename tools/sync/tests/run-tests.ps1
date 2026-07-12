#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Run all sync skill Pester tests.
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

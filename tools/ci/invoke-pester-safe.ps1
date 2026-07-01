[CmdletBinding()]
param(
    [string[]]$Path = @(".\tests"),
    [switch]$CI,
    [string]$Verbosity = "Detailed",
    [switch]$EnableTestRegistry,
    [string]$TestResultPath = ""
)

$ErrorActionPreference = "Stop"

function Get-PesterModulePath {
    $repoLocal = Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path "modules\Pester\5.7.1\Pester.psd1"
    if (Test-Path -LiteralPath $repoLocal) {
        return $repoLocal
    }

    $available = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
    if ($available) {
        return $available.Path
    }

    throw "Pester is not available. Run tools/ci/install-local-pester.ps1 or provide modules/Pester/5.7.1/Pester.psd1."
}

$pesterPath = Get-PesterModulePath
Import-Module $pesterPath -Force

$major = (Get-Module Pester | Sort-Object Version -Descending | Select-Object -First 1).Version.Major
if ($major -lt 5) {
    Invoke-Pester -Path $Path
    return
}

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Run.PassThru = $true
$config.Output.Verbosity = $Verbosity

if (-not $EnableTestRegistry) {
    $config.TestRegistry.Enabled = $false
}

if (-not [string]::IsNullOrWhiteSpace($TestResultPath)) {
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = $TestResultPath
}

$result = Invoke-Pester -Configuration $config

if ($result -and ($result.FailedCount + $result.FailedBlocksCount + $result.FailedContainersCount) -gt 0) {
    if ($CI) {
        exit 1
    }
    throw "Pester failed with $($result.FailedCount) failing test(s)."
}

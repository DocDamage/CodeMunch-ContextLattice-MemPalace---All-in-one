#requires -Version 5.1
<#
.SYNOPSIS
    Validates that README, PROGRESS, and release docs agree on version and metrics.
.DESCRIPTION
    Compares claimed values in README.md and PROGRESS.md against the single sources
    of truth (VERSION file, actual file counts) and exits with a non-zero code if drift
    is detected.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$drift = @()
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$progressPath = Join-Path $repoRoot "docs\implementation\PROGRESS.md"

# --- Truth sources ---
$version = (Get-Content (Join-Path $repoRoot "VERSION") -Raw).Trim()

$moduleCount = (Get-ChildItem -Path (Join-Path $repoRoot "module\LLMWorkflow") -Filter "*.ps1" -Recurse |
    Where-Object {
        $_.Name -notlike "*.Tests.ps1" -and
        $_.Name -notlike "*Test*.ps1" -and
        $_.FullName -notlike "*\templates\*" -and
        $_.FullName -notlike "*\LLMWorkflow\scripts\*"
    }).Count

$packCount = (Get-ChildItem -Path (Join-Path $repoRoot "packs\manifests") -Filter "*.json" |
    Where-Object {
        Test-Path (Join-Path (Join-Path $repoRoot "packs\registries") ($_.BaseName + ".sources.json"))
    }).Count

$parserCount = (Get-ChildItem -Path (Join-Path $repoRoot "module\LLMWorkflow\extraction") -Filter "*.ps1" |
    Where-Object { $_.Name -notlike "*Test*" }).Count

$goldenTaskCount = 0
$goldenTasksFile = Join-Path $repoRoot "module\LLMWorkflow\governance\GoldenTasks.ps1"
if (Test-Path $goldenTasksFile) {
    $content = Get-Content $goldenTasksFile -Raw
    # Count definitions of tasks
    $matches = [regex]::Matches($content, 'New-GoldenTask')
    $goldenTaskCount = $matches.Count
}

$readme = Get-Content (Join-Path $repoRoot "README.md") -Raw
$progress = Get-Content $progressPath -Raw
$releaseStatePath = Join-Path $repoRoot "docs\releases\RELEASE_STATE.md"
$releaseState = if (Test-Path $releaseStatePath) { Get-Content $releaseStatePath -Raw } else { "" }
$manifestPath = Join-Path $repoRoot "module\LLMWorkflow\LLMWorkflow.psd1"
$manifest = Import-PowerShellDataFile -Path $manifestPath

# --- Manifest checks ---
if ($manifest.ModuleVersion -ne $version) {
    $drift += "LLMWorkflow.psd1 ModuleVersion ($($manifest.ModuleVersion)) does not match VERSION ($version)"
}

# --- README checks ---
if ($readme -notmatch [regex]::Escape("version-$version")) {
    $drift += "README.md version badge does not match VERSION ($version)"
}
if ($readme -notmatch [regex]::Escape("PowerShell%20modules-$moduleCount")) {
    $drift += "README.md module badge does not match actual count ($moduleCount)"
}
if ($readme -notmatch [regex]::Escape("domain%20packs-$packCount")) {
    $drift += "README.md pack badge does not match actual count ($packCount)"
}

# --- PROGRESS checks ---
if ($progress -notmatch [regex]::Escape($version)) {
    $drift += "docs/implementation/PROGRESS.md does not contain VERSION ($version)"
}
else {
    $headerPattern = "\*\*Current Version:\*\*\s*" + [regex]::Escape($version)
    if ($progress -notmatch $headerPattern) {
        $drift += "docs/implementation/PROGRESS.md header version does not match VERSION ($version)"
    }
}

if ($progress -notmatch "\*\*PowerShell Modules:\*\*\s*$moduleCount") {
    $drift += "docs/implementation/PROGRESS.md module count ($moduleCount) not found."
}
if ($progress -notmatch "\*\*Domain Packs:\*\*\s*$packCount") {
    $drift += "docs/implementation/PROGRESS.md pack count ($packCount) not found."
}
if ($progress -notmatch "\*\*Extraction Parsers:\*\*\s*$parserCount") {
    $drift += "docs/implementation/PROGRESS.md parser count ($parserCount) not found."
}
if ($progress -notmatch "\*\*Golden Tasks:\*\*\s*$goldenTaskCount") {
    $drift += "docs/implementation/PROGRESS.md golden task count ($goldenTaskCount) not found."
}

# --- RELEASE_STATE checks ---
if ($releaseState) {
    if ($releaseState -notmatch "\*\*Declared Version:\*\*\s*``$version``") {
        $drift += "docs/releases/RELEASE_STATE.md version does not match VERSION ($version)"
    }
    # Using (?s) to match across multiple lines
    if ($releaseState -notmatch "(?s)- \*\*PowerShell Module\*\*:.*?Current count:\s*\*\*($moduleCount)\*\*") {
        $drift += "docs/releases/RELEASE_STATE.md module count ($moduleCount) not found."
    }
    if ($releaseState -notmatch "(?s)- \*\*Domain Pack\*\*:.*?Current count:\s*\*\*($packCount)\*\*") {
        $drift += "docs/releases/RELEASE_STATE.md pack count ($packCount) not found."
    }
    if ($releaseState -notmatch "(?s)- \*\*Golden Task\*\*:.*?Current count:\s*\*\*($goldenTaskCount)\*\*") {
        $drift += "docs/releases/RELEASE_STATE.md golden task count ($goldenTaskCount) not found."
    }
}

# --- Report ---
if ($drift.Count -gt 0) {
    Write-Host "::error title=Documentation Truth Drift::Documentation truth drift detected:" -ForegroundColor Red
    foreach ($item in $drift) {
        Write-Host "  - $item" -ForegroundColor Red
    }
    exit 1
}

Write-Host "Documentation truth validated successfully." -ForegroundColor Green
Write-Host "  Version: $version"
Write-Host "  Modules: $moduleCount"
Write-Host "  Packs:   $packCount"
Write-Host "  Parsers: $parserCount"
Write-Host "  Golden Tasks: $goldenTaskCount"

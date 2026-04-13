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

$readme = Get-Content (Join-Path $repoRoot "README.md") -Raw
$progress = Get-Content $progressPath -Raw

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
# Allow markdown bold formatting around the label
if ($progress -notmatch [regex]::Escape($version)) {
    $drift += "docs/implementation/PROGRESS.md does not contain VERSION ($version)"
}
else {
    # More specific: look for the version in the header block
    $headerBlock = ($progress -split "## Overall Status")[1]
    if ($headerBlock -and ($headerBlock -notmatch "\*\*Current Version:\*\*\s*$version")) {
        $drift += "docs/implementation/PROGRESS.md header version does not match VERSION ($version)"
    }
}

if ($progress -notmatch "\*\*PowerShell Modules:\*\*\s*$moduleCount") {
    $drift += "docs/implementation/PROGRESS.md module count does not match actual count ($moduleCount)"
}
if ($progress -notmatch "\*\*Domain Packs:\*\*\s*$packCount") {
    $drift += "docs/implementation/PROGRESS.md pack count does not match actual count ($packCount)"
}
if ($progress -notmatch "\*\*Extraction Parsers:\*\*\s*$parserCount") {
    $drift += "docs/implementation/PROGRESS.md parser count does not match actual count ($parserCount)"
}

# --- Report ---
if ($drift.Count -gt 0) {
    Write-Host "::error::Documentation truth drift detected:" -ForegroundColor Red
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

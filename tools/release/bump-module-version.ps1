[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Output "[release] $Message"
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Version must be SemVer core format: MAJOR.MINOR.PATCH"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$manifestPath = Join-Path $repoRoot "module\LLMWorkflow\LLMWorkflow.psd1"
$changelogPath = Join-Path $repoRoot "CHANGELOG.md"

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Missing manifest: $manifestPath"
}

$manifestText = Get-Content -LiteralPath $manifestPath -Raw
$currentVersion = $null
if ($manifestText -match "ModuleVersion\s*=\s*'([^']+)'") {
    $currentVersion = $matches[1]
}
if (-not $currentVersion) {
    throw "Could not read current ModuleVersion from manifest."
}

if ($currentVersion -eq $Version) {
    Write-Step "ModuleVersion already set to $Version. No changes needed."
    exit 0
}

$newManifestText = [regex]::Replace(
    $manifestText,
    "ModuleVersion\s*=\s*'[^']+'",
    "ModuleVersion = '$Version'"
)

if (-not $DryRun) {
    Set-Content -LiteralPath $manifestPath -Value $newManifestText -Encoding UTF8
}

Write-Step "Updated module version: $currentVersion -> $Version"

if (Test-Path -LiteralPath $changelogPath) {
    $today = Get-Date -Format "yyyy-MM-dd"
    $changelog = Get-Content -LiteralPath $changelogPath -Raw
    if ($changelog -notmatch [regex]::Escape("## [$Version] - $today")) {
        $releaseStub = @"

## [$Version] - $today

### Added
- TODO
"@
        if (-not $DryRun) {
            $changelog = $changelog -replace '(## \[Unreleased\]\r?\n)', "`$1$releaseStub"
            Set-Content -LiteralPath $changelogPath -Value $changelog -Encoding UTF8
        }
        Write-Step "Added CHANGELOG release stub for $Version."
    }
}

Write-Step "Next: review files, commit, and create tag v$Version."

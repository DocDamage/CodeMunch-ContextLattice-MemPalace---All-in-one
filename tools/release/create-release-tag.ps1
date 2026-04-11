[CmdletBinding()]
param(
    [string]$Version = "",
    [switch]$Push,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Output "[release] $Message"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location -LiteralPath $repoRoot

$manifestPath = Join-Path $repoRoot "module\LLMWorkflow\LLMWorkflow.psd1"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Missing manifest: $manifestPath"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $manifest = Import-PowerShellDataFile -Path $manifestPath
    $Version = [string]$manifest.ModuleVersion
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Resolved version '$Version' is not valid SemVer core format."
}

$tag = "v$Version"
$tagExists = (& git tag --list $tag).Trim()
if ($tagExists -and -not $Force) {
    throw "Tag $tag already exists. Use -Force to recreate."
}

if ($tagExists -and $Force) {
    & git tag -d $tag | Out-Null
}

$message = "Release $tag"
& git tag -a $tag -m $message
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create git tag $tag"
}

Write-Step "Created tag $tag"

if ($Push) {
    if ($Force) {
        & git push origin $tag --force
    } else {
        & git push origin $tag
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push tag $tag"
    }
    Write-Step "Pushed tag $tag to origin"
} else {
    Write-Step "Tag not pushed. Use -Push to publish."
}


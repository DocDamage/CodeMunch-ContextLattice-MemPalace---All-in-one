[CmdletBinding()]
param(
    [string]$ModuleVersion = "",
    [switch]$NoProfileUpdate
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Output "[llmworkflow-module] $Message"
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Set-Or-ReplaceProfileBlock {
    param(
        [string]$ProfilePath,
        [string]$BlockText,
        [string]$StartMarker,
        [string]$EndMarker
    )

    Ensure-Dir -Path (Split-Path -Parent $ProfilePath)
    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
    }

    $content = Get-Content -LiteralPath $ProfilePath -Raw
    if ($null -eq $content) {
        $content = ""
    }

    $pattern = [regex]::Escape($StartMarker) + ".*?" + [regex]::Escape($EndMarker)
    if ([regex]::IsMatch($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $updated = [regex]::Replace($content, $pattern, $BlockText, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    } else {
        if (-not [string]::IsNullOrWhiteSpace($content) -and -not $content.EndsWith("`r`n")) {
            $content += "`r`n"
        }
        $updated = $content + $BlockText + "`r`n"
    }

    Set-Content -LiteralPath $ProfilePath -Value $updated -Encoding UTF8
}

$repoRoot = $PSScriptRoot
$moduleSource = Join-Path $repoRoot "module\LLMWorkflow"
if (-not (Test-Path -LiteralPath $moduleSource)) {
    throw "Missing module source: $moduleSource"
}

if ([string]::IsNullOrWhiteSpace($ModuleVersion)) {
    $manifestSource = Join-Path $moduleSource "LLMWorkflow.psd1"
    $manifestData = Import-PowerShellDataFile -Path $manifestSource
    $ModuleVersion = [string]$manifestData.ModuleVersion
}

$candidatePaths = @($env:PSModulePath -split ';' | Where-Object { $_ -and $_ -like "$HOME*" })
if ($candidatePaths.Count -gt 0) {
    $moduleBase = $candidatePaths[0]
} else {
    $moduleBase = Join-Path $HOME "Documents\WindowsPowerShell\Modules"
}

$targetModulePath = Join-Path $moduleBase ("LLMWorkflow\" + $ModuleVersion)
if (Test-Path -LiteralPath $targetModulePath) {
    Remove-Item -LiteralPath $targetModulePath -Recurse -Force
}
Ensure-Dir -Path $targetModulePath

Copy-Item -Path (Join-Path $moduleSource "*") -Destination $targetModulePath -Recurse -Force

$manifestPath = Join-Path $targetModulePath "LLMWorkflow.psd1"
Import-Module $manifestPath -Force

Write-Step "Installed module to: $targetModulePath"

if (-not $NoProfileUpdate) {
    $startMarker = "# >>> llmworkflow-module >>>"
    $endMarker = "# <<< llmworkflow-module <<<"
    $profileBlock = @"
$startMarker
Import-Module LLMWorkflow -ErrorAction SilentlyContinue
$endMarker
"@
    Set-Or-ReplaceProfileBlock -ProfilePath $PROFILE -BlockText $profileBlock -StartMarker $startMarker -EndMarker $endMarker
    Write-Step "Updated profile: $PROFILE"
    Write-Step "Open a new shell, then run: Invoke-LLMWorkflowUp"
} else {
    Write-Step "Skipped profile update (--NoProfileUpdate)."
}

Write-Step "Available commands: Install-LLMWorkflow, Invoke-LLMWorkflowUp, llmup"

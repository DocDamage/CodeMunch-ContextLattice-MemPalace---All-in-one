[CmdletBinding()]
param(
    [string]$InstallRoot = "$HOME\.llm-workflow",
    [string]$ToolkitSource = "",
    [switch]$NoProfileUpdate,
    [string]$ProfilePath = $PROFILE,
    [switch]$SkipUserEnvPersist
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Output "[llm-workflow-install] $Message"
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

$sourceToolsRoot = ""
if (-not [string]::IsNullOrWhiteSpace($ToolkitSource)) {
    $sourceToolsRoot = (Resolve-Path -LiteralPath $ToolkitSource).Path
} else {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot "..\..")).Path
    $sourceToolsRoot = Join-Path $repoRoot "tools"
}

$requiredToolDirs = @("codemunch", "contextlattice", "memorybridge")
foreach ($name in $requiredToolDirs) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceToolsRoot $name))) {
        throw "Missing required source folder: $(Join-Path $sourceToolsRoot $name)"
    }
}

$installRootPath = [System.IO.Path]::GetFullPath($InstallRoot)
$templatesRoot = Join-Path $installRootPath "templates\tools"
$scriptsRoot = Join-Path $installRootPath "scripts"

Ensure-Dir -Path $installRootPath
Ensure-Dir -Path $templatesRoot
Ensure-Dir -Path $scriptsRoot

foreach ($name in $requiredToolDirs) {
    $src = Join-Path $sourceToolsRoot $name
    $dst = Join-Path $templatesRoot $name
    if (Test-Path -LiteralPath $dst) {
        Remove-Item -LiteralPath $dst -Recurse -Force
    }
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
    Write-Step "Installed template tools/$name"
}

$bootstrapSrc = Join-Path $sourceToolsRoot "workflow\bootstrap-llm-workflow.ps1"
$siblingBootstrapSrc = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "bootstrap-llm-workflow.ps1"
if (Test-Path -LiteralPath $siblingBootstrapSrc) {
    $bootstrapSrc = $siblingBootstrapSrc
}
$bootstrapDst = Join-Path $scriptsRoot "bootstrap-llm-workflow.ps1"
Copy-Item -LiteralPath $bootstrapSrc -Destination $bootstrapDst -Force

$launcherPath = Join-Path $installRootPath "llm-workflow-up.ps1"
@"
[CmdletBinding()]
param(
    [string]`$ProjectRoot = ".",
    [switch]`$SkipDependencyInstall,
    [switch]`$SkipContextVerify,
    [switch]`$SkipBridgeDryRun,
    [switch]`$SmokeTestContext,
    [switch]`$RequireSearchHit
)

`$scriptPath = Join-Path `$PSScriptRoot "scripts\bootstrap-llm-workflow.ps1"
`$invokeArgs = @{
    ProjectRoot = `$ProjectRoot
    ToolkitSource = "$templatesRoot"
}
if (`$SkipDependencyInstall) { `$invokeArgs["SkipDependencyInstall"] = `$true }
if (`$SkipContextVerify) { `$invokeArgs["SkipContextVerify"] = `$true }
if (`$SkipBridgeDryRun) { `$invokeArgs["SkipBridgeDryRun"] = `$true }
if (`$SmokeTestContext) { `$invokeArgs["SmokeTestContext"] = `$true }
if (`$RequireSearchHit) { `$invokeArgs["RequireSearchHit"] = `$true }
& `$scriptPath @invokeArgs
"@ | Set-Content -LiteralPath $launcherPath -Encoding UTF8

[System.Environment]::SetEnvironmentVariable("LLM_WORKFLOW_TOOLKIT_SOURCE", $templatesRoot, "Process")
if (-not $SkipUserEnvPersist) {
    [System.Environment]::SetEnvironmentVariable("LLM_WORKFLOW_TOOLKIT_SOURCE", $templatesRoot, "User")
    Write-Step "Set user env LLM_WORKFLOW_TOOLKIT_SOURCE=$templatesRoot"
} else {
    Write-Step "Skipped user env persist for LLM_WORKFLOW_TOOLKIT_SOURCE."
}

$startMarker = "# >>> llm-workflow >>>"
$endMarker = "# <<< llm-workflow <<<"
$profileBlock = @"
$startMarker
function llm-workflow-up {
    [CmdletBinding()]
    param(
        [string]`$ProjectRoot = ".",
        [switch]`$SkipDependencyInstall,
        [switch]`$SkipContextVerify,
        [switch]`$SkipBridgeDryRun,
        [switch]`$SmokeTestContext,
        [switch]`$RequireSearchHit
    )

    `$invokeArgs = @{
        ProjectRoot = `$ProjectRoot
    }
    if (`$SkipDependencyInstall) { `$invokeArgs["SkipDependencyInstall"] = `$true }
    if (`$SkipContextVerify) { `$invokeArgs["SkipContextVerify"] = `$true }
    if (`$SkipBridgeDryRun) { `$invokeArgs["SkipBridgeDryRun"] = `$true }
    if (`$SmokeTestContext) { `$invokeArgs["SmokeTestContext"] = `$true }
    if (`$RequireSearchHit) { `$invokeArgs["RequireSearchHit"] = `$true }
    & "$launcherPath" @invokeArgs
}
Set-Alias llmup llm-workflow-up -Scope Global
$endMarker
"@

Write-Step "Installed launcher: $launcherPath"
if (-not $NoProfileUpdate) {
    Set-Or-ReplaceProfileBlock -ProfilePath $ProfilePath -BlockText $profileBlock -StartMarker $startMarker -EndMarker $endMarker
    Write-Step "Updated PowerShell profile: $ProfilePath"
    Write-Step "Open a new shell, then run: llm-workflow-up"
} else {
    Write-Step "Skipped profile update (--NoProfileUpdate)."
}

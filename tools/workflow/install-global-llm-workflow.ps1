[CmdletBinding()]
param(
    [string]$InstallRoot = "$HOME\.llm-workflow"
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

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot "..\..")).Path
$sourceToolsRoot = Join-Path $repoRoot "tools"

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
$bootstrapDst = Join-Path $scriptsRoot "bootstrap-llm-workflow.ps1"
Copy-Item -LiteralPath $bootstrapSrc -Destination $bootstrapDst -Force
$checkSrc = Join-Path $sourceToolsRoot "workflow\check-llm-workflow.ps1"
$checkDst = Join-Path $scriptsRoot "check-llm-workflow.ps1"
if (Test-Path -LiteralPath $checkSrc) {
    Copy-Item -LiteralPath $checkSrc -Destination $checkDst -Force
}
$doctorSrc = Join-Path $sourceToolsRoot "workflow\doctor-llm-workflow.ps1"
$doctorDst = Join-Path $scriptsRoot "doctor-llm-workflow.ps1"
if (Test-Path -LiteralPath $doctorSrc) {
    Copy-Item -LiteralPath $doctorSrc -Destination $doctorDst -Force
}

$upLauncherPath = Join-Path $installRootPath "llm-workflow-up.ps1"
@"
[CmdletBinding()]
param(
    [string]`$ProjectRoot = ".",
    [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
    [string]`$Provider = "auto",
    [switch]`$SkipDependencyInstall,
    [switch]`$SkipProviderNormalize,
    [switch]`$SkipContextVerify,
    [switch]`$SkipBridgeDryRun,
    [switch]`$SmokeTestContext,
    [switch]`$RequireSearchHit,
    [switch]`$RunCodemunchIndex,
    [switch]`$CodemunchEmbed,
    [switch]`$DeepCheck,
    [switch]`$FailIfNoProviderKey,
    [switch]`$FailIfContextMissing,
    [int]`$ContextSearchAttempts = 20,
    [int]`$ContextSearchDelaySec = 1,
    [int]`$ContextTimeoutSec = 20
)

`$scriptPath = Join-Path `$PSScriptRoot "scripts\bootstrap-llm-workflow.ps1"
`$invokeArgs = @{
    ProjectRoot = `$ProjectRoot
    ToolkitSource = "$templatesRoot"
    Provider = `$Provider
}
if (`$SkipDependencyInstall) { `$invokeArgs["SkipDependencyInstall"] = `$true }
if (`$SkipProviderNormalize) { `$invokeArgs["SkipProviderNormalize"] = `$true }
if (`$SkipContextVerify) { `$invokeArgs["SkipContextVerify"] = `$true }
if (`$SkipBridgeDryRun) { `$invokeArgs["SkipBridgeDryRun"] = `$true }
if (`$SmokeTestContext) { `$invokeArgs["SmokeTestContext"] = `$true }
if (`$RequireSearchHit) { `$invokeArgs["RequireSearchHit"] = `$true }
if (`$RunCodemunchIndex) { `$invokeArgs["RunCodemunchIndex"] = `$true }
if (`$CodemunchEmbed) { `$invokeArgs["CodemunchEmbed"] = `$true }
if (`$DeepCheck) { `$invokeArgs["DeepCheck"] = `$true }
if (`$FailIfNoProviderKey) { `$invokeArgs["FailIfNoProviderKey"] = `$true }
if (`$FailIfContextMissing) { `$invokeArgs["FailIfContextMissing"] = `$true }
`$invokeArgs["ContextSearchAttempts"] = `$ContextSearchAttempts
`$invokeArgs["ContextSearchDelaySec"] = `$ContextSearchDelaySec
`$invokeArgs["ContextTimeoutSec"] = `$ContextTimeoutSec

& `$scriptPath @invokeArgs
"@ | Set-Content -LiteralPath $upLauncherPath -Encoding UTF8

$checkLauncherPath = Join-Path $installRootPath "llm-workflow-check.ps1"
@"
[CmdletBinding()]
param(
    [string]`$ProjectRoot = ".",
    [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
    [string]`$Provider = "auto",
    [switch]`$SkipDependencyInstall,
    [switch]`$SkipProviderNormalize,
    [int]`$ContextSearchAttempts = 90,
    [int]`$ContextSearchDelaySec = 2,
    [int]`$ContextTimeoutSec = 30
)

`$scriptPath = Join-Path `$PSScriptRoot "llm-workflow-up.ps1"
`$invokeArgs = @{
    ProjectRoot = `$ProjectRoot
    Provider = `$Provider
    DeepCheck = `$true
    RunCodemunchIndex = `$true
    CodemunchEmbed = `$true
    SmokeTestContext = `$true
    FailIfContextMissing = `$true
}
if (`$SkipDependencyInstall) { `$invokeArgs["SkipDependencyInstall"] = `$true }
if (`$SkipProviderNormalize) { `$invokeArgs["SkipProviderNormalize"] = `$true }
`$invokeArgs["ContextSearchAttempts"] = `$ContextSearchAttempts
`$invokeArgs["ContextSearchDelaySec"] = `$ContextSearchDelaySec
`$invokeArgs["ContextTimeoutSec"] = `$ContextTimeoutSec
& `$scriptPath @invokeArgs
"@ | Set-Content -LiteralPath $checkLauncherPath -Encoding UTF8

$doctorLauncherPath = Join-Path $installRootPath "llm-workflow-doctor.ps1"
@"
[CmdletBinding()]
param(
    [string]`$ProjectRoot = ".",
    [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
    [string]`$Provider = "auto",
    [switch]`$CheckContext,
    [int]`$TimeoutSec = 10,
    [switch]`$AsJson,
    [switch]`$Strict
)

`$scriptPath = Join-Path `$PSScriptRoot "scripts\doctor-llm-workflow.ps1"
`$invokeArgs = @{
    ProjectRoot = `$ProjectRoot
    Provider = `$Provider
    TimeoutSec = `$TimeoutSec
}
if (`$CheckContext) { `$invokeArgs["CheckContext"] = `$true }
if (`$AsJson) { `$invokeArgs["AsJson"] = `$true }
if (`$Strict) { `$invokeArgs["Strict"] = `$true }

& `$scriptPath @invokeArgs
"@ | Set-Content -LiteralPath $doctorLauncherPath -Encoding UTF8

[System.Environment]::SetEnvironmentVariable("LLM_WORKFLOW_TOOLKIT_SOURCE", $templatesRoot, "User")
[System.Environment]::SetEnvironmentVariable("LLM_WORKFLOW_TOOLKIT_SOURCE", $templatesRoot, "Process")
Write-Step "Set user env LLM_WORKFLOW_TOOLKIT_SOURCE=$templatesRoot"

$startMarker = "# >>> llm-workflow >>>"
$endMarker = "# <<< llm-workflow <<<"
$profileBlock = @"
$startMarker
function llm-workflow-up {
    [CmdletBinding()]
    param(
        [string]`$ProjectRoot = ".",
        [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
        [string]`$Provider = "auto",
        [switch]`$SkipDependencyInstall,
        [switch]`$SkipProviderNormalize,
        [switch]`$SkipContextVerify,
        [switch]`$SkipBridgeDryRun,
        [switch]`$SmokeTestContext,
        [switch]`$RequireSearchHit,
        [switch]`$RunCodemunchIndex,
        [switch]`$CodemunchEmbed,
        [switch]`$DeepCheck,
        [switch]`$FailIfNoProviderKey,
        [switch]`$FailIfContextMissing,
        [int]`$ContextSearchAttempts = 20,
        [int]`$ContextSearchDelaySec = 1,
        [int]`$ContextTimeoutSec = 20
    )

    `$invokeArgs = @{
        ProjectRoot = `$ProjectRoot
        Provider = `$Provider
    }
    if (`$SkipDependencyInstall) { `$invokeArgs["SkipDependencyInstall"] = `$true }
    if (`$SkipProviderNormalize) { `$invokeArgs["SkipProviderNormalize"] = `$true }
    if (`$SkipContextVerify) { `$invokeArgs["SkipContextVerify"] = `$true }
    if (`$SkipBridgeDryRun) { `$invokeArgs["SkipBridgeDryRun"] = `$true }
    if (`$SmokeTestContext) { `$invokeArgs["SmokeTestContext"] = `$true }
    if (`$RequireSearchHit) { `$invokeArgs["RequireSearchHit"] = `$true }
    if (`$RunCodemunchIndex) { `$invokeArgs["RunCodemunchIndex"] = `$true }
    if (`$CodemunchEmbed) { `$invokeArgs["CodemunchEmbed"] = `$true }
    if (`$DeepCheck) { `$invokeArgs["DeepCheck"] = `$true }
    if (`$FailIfNoProviderKey) { `$invokeArgs["FailIfNoProviderKey"] = `$true }
    if (`$FailIfContextMissing) { `$invokeArgs["FailIfContextMissing"] = `$true }
    `$invokeArgs["ContextSearchAttempts"] = `$ContextSearchAttempts
    `$invokeArgs["ContextSearchDelaySec"] = `$ContextSearchDelaySec
    `$invokeArgs["ContextTimeoutSec"] = `$ContextTimeoutSec
    & "$upLauncherPath" @invokeArgs
}

function llm-workflow-check {
    [CmdletBinding()]
    param(
        [string]`$ProjectRoot = ".",
        [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
        [string]`$Provider = "auto",
        [switch]`$SkipDependencyInstall,
        [switch]`$SkipProviderNormalize,
        [int]`$ContextSearchAttempts = 90,
        [int]`$ContextSearchDelaySec = 2,
        [int]`$ContextTimeoutSec = 30
    )

    `$invokeArgs = @{
        ProjectRoot = `$ProjectRoot
        Provider = `$Provider
    }
    if (`$SkipDependencyInstall) { `$invokeArgs["SkipDependencyInstall"] = `$true }
    if (`$SkipProviderNormalize) { `$invokeArgs["SkipProviderNormalize"] = `$true }
    `$invokeArgs["ContextSearchAttempts"] = `$ContextSearchAttempts
    `$invokeArgs["ContextSearchDelaySec"] = `$ContextSearchDelaySec
    `$invokeArgs["ContextTimeoutSec"] = `$ContextTimeoutSec
    & "$checkLauncherPath" @invokeArgs
}

function llm-workflow-doctor {
    [CmdletBinding()]
    param(
        [string]`$ProjectRoot = ".",
        [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
        [string]`$Provider = "auto",
        [switch]`$CheckContext,
        [int]`$TimeoutSec = 10,
        [switch]`$AsJson,
        [switch]`$Strict
    )

    `$invokeArgs = @{
        ProjectRoot = `$ProjectRoot
        Provider = `$Provider
        TimeoutSec = `$TimeoutSec
    }
    if (`$CheckContext) { `$invokeArgs["CheckContext"] = `$true }
    if (`$AsJson) { `$invokeArgs["AsJson"] = `$true }
    if (`$Strict) { `$invokeArgs["Strict"] = `$true }
    & "$doctorLauncherPath" @invokeArgs
}

Set-Alias llmup llm-workflow-up -Scope Global
Set-Alias llmcheck llm-workflow-check -Scope Global
Set-Alias llmdoctor llm-workflow-doctor -Scope Global
$endMarker
"@

Set-Or-ReplaceProfileBlock -ProfilePath $PROFILE -BlockText $profileBlock -StartMarker $startMarker -EndMarker $endMarker

Write-Step "Installed launcher: $upLauncherPath"
Write-Step "Installed launcher: $checkLauncherPath"
Write-Step "Installed launcher: $doctorLauncherPath"
Write-Step "Updated PowerShell profile: $PROFILE"
Write-Step "Open a new shell, then run: llm-workflow-up, llm-workflow-check, or llm-workflow-doctor"

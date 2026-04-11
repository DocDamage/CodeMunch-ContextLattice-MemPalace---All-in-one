Set-StrictMode -Version Latest

function Install-LLMWorkflow {
    [CmdletBinding()]
    param(
        [string]$InstallRoot = "$HOME\.llm-workflow",
        [switch]$NoProfileUpdate,
        [string]$ProfilePath = $PROFILE,
        [switch]$SkipUserEnvPersist
    )

    $scriptPath = Join-Path $PSScriptRoot "scripts\install-global-llm-workflow.ps1"
    $toolkitSource = Join-Path $PSScriptRoot "templates\tools"

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Missing script: $scriptPath"
    }
    if (-not (Test-Path -LiteralPath $toolkitSource)) {
        throw "Missing toolkit templates: $toolkitSource"
    }

    $invokeArgs = @{
        InstallRoot = $InstallRoot
        ToolkitSource = $toolkitSource
        ProfilePath = $ProfilePath
    }
    if ($NoProfileUpdate) {
        $invokeArgs["NoProfileUpdate"] = $true
    }
    if ($SkipUserEnvPersist) {
        $invokeArgs["SkipUserEnvPersist"] = $true
    }

    & $scriptPath @invokeArgs
}

function Invoke-LLMWorkflowUp {
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = ".",
        [switch]$SkipDependencyInstall,
        [switch]$SkipContextVerify,
        [switch]$SkipBridgeDryRun,
        [switch]$SmokeTestContext,
        [switch]$RequireSearchHit
    )

    $scriptPath = Join-Path $PSScriptRoot "scripts\bootstrap-llm-workflow.ps1"
    $toolkitSource = Join-Path $PSScriptRoot "templates\tools"

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Missing script: $scriptPath"
    }
    if (-not (Test-Path -LiteralPath $toolkitSource)) {
        throw "Missing toolkit templates: $toolkitSource"
    }

    $invokeArgs = @{
        ProjectRoot = $ProjectRoot
        ToolkitSource = $toolkitSource
    }
    if ($SkipDependencyInstall) {
        $invokeArgs["SkipDependencyInstall"] = $true
    }
    if ($SkipContextVerify) {
        $invokeArgs["SkipContextVerify"] = $true
    }
    if ($SkipBridgeDryRun) {
        $invokeArgs["SkipBridgeDryRun"] = $true
    }
    if ($SmokeTestContext) {
        $invokeArgs["SmokeTestContext"] = $true
    }
    if ($RequireSearchHit) {
        $invokeArgs["RequireSearchHit"] = $true
    }

    & $scriptPath @invokeArgs
}

Set-Alias -Name llmup -Value Invoke-LLMWorkflowUp

Export-ModuleMember -Function Install-LLMWorkflow, Invoke-LLMWorkflowUp -Alias llmup

[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [ValidateSet("auto", "openai", "kimi", "gemini", "glm")]
    [string]$Provider = "auto",
    [switch]$SkipDependencyInstall,
    [switch]$SkipProviderNormalize,
    [int]$ContextSearchAttempts = 90,
    [int]$ContextSearchDelaySec = 2,
    [int]$ContextTimeoutSec = 30
)

$ErrorActionPreference = "Stop"

$invokeArgs = @{
    ProjectRoot = $ProjectRoot
    Provider = $Provider
    DeepCheck = $true
    RunCodemunchIndex = $true
    CodemunchEmbed = $true
    SmokeTestContext = $true
    FailIfContextMissing = $true
    ContextSearchAttempts = $ContextSearchAttempts
    ContextSearchDelaySec = $ContextSearchDelaySec
    ContextTimeoutSec = $ContextTimeoutSec
}
if ($SkipDependencyInstall) {
    $invokeArgs["SkipDependencyInstall"] = $true
}
if ($SkipProviderNormalize) {
    $invokeArgs["SkipProviderNormalize"] = $true
}

& (Join-Path $PSScriptRoot "bootstrap-llm-workflow.ps1") @invokeArgs
if ($LASTEXITCODE -ne 0) {
    throw "llm workflow deep check failed with exit code $LASTEXITCODE"
}

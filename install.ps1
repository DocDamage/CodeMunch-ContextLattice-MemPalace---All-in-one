[CmdletBinding()]
param(
    [string]$InstallRoot = "$HOME\.llm-workflow"
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "tools" "workflow" "install-global-llm-workflow.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing installer script: $scriptPath"
}

& $scriptPath -InstallRoot $InstallRoot


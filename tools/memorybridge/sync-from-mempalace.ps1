param(
    [string]$ConfigPath = ".memorybridge/bridge.config.json",
    [string]$StatePath = ".memorybridge/sync-state.json",
    [string]$OrchestratorUrl = "",
    [string]$ApiKey = "",
    [string]$ApiKeyEnvVar = "",
    [string]$PalacePath = "",
    [string]$CollectionName = "",
    [string]$DefaultProjectName = "",
    [string]$TopicPrefix = "",
    [int]$Limit = 0,
    [int]$BatchSize = 250,
    [switch]$DryRun,
    [switch]$ForceResync,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "sync_mempalace_to_contextlattice.py"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing bridge script: $scriptPath"
}

$args = @(
    $scriptPath,
    "--config-file", $ConfigPath,
    "--state-file", $StatePath,
    "--batch-size", "$BatchSize"
)

if (-not [string]::IsNullOrWhiteSpace($OrchestratorUrl)) {
    $args += @("--orchestrator-url", $OrchestratorUrl)
}
if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
    $args += @("--api-key", $ApiKey)
}
if (-not [string]::IsNullOrWhiteSpace($ApiKeyEnvVar)) {
    $args += @("--api-key-env-var", $ApiKeyEnvVar)
}
if (-not [string]::IsNullOrWhiteSpace($PalacePath)) {
    $args += @("--palace-path", $PalacePath)
}
if (-not [string]::IsNullOrWhiteSpace($CollectionName)) {
    $args += @("--collection-name", $CollectionName)
}
if (-not [string]::IsNullOrWhiteSpace($DefaultProjectName)) {
    $args += @("--default-project-name", $DefaultProjectName)
}
if (-not [string]::IsNullOrWhiteSpace($TopicPrefix)) {
    $args += @("--topic-prefix", $TopicPrefix)
}
if ($Limit -gt 0) {
    $args += @("--limit", "$Limit")
}
if ($DryRun) {
    $args += "--dry-run"
}
if ($ForceResync) {
    $args += "--force-resync"
}
if ($Strict) {
    $args += "--strict"
}

& python @args
if ($LASTEXITCODE -ne 0) {
    throw "MemPalace -> ContextLattice sync failed with exit code $LASTEXITCODE."
}


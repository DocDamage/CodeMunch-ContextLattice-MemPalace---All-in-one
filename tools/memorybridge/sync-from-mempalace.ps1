[CmdletBinding()]
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
    [int]$PalaceIndex = -1,
    [int]$Limit = 0,
    [int]$BatchSize = 250,
    [int]$Workers = 4,
    [switch]$DryRun,
    [switch]$ForceResync,
    [switch]$Strict,
    [switch]$SemanticDiff,
    [double]$SimilarityThreshold = 0.95
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "sync_mempalace_to_contextlattice.py"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing bridge script: $scriptPath"
}

$pyArgs = @(
    $scriptPath,
    "--config-file", $ConfigPath,
    "--state-file", $StatePath,
    "--batch-size", "$BatchSize"
)

if (-not [string]::IsNullOrWhiteSpace($OrchestratorUrl)) {
    $pyArgs += @("--orchestrator-url", $OrchestratorUrl)
}
if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
    $pyArgs += @("--api-key", $ApiKey)
}
if (-not [string]::IsNullOrWhiteSpace($ApiKeyEnvVar)) {
    $pyArgs += @("--api-key-env-var", $ApiKeyEnvVar)
}
if (-not [string]::IsNullOrWhiteSpace($PalacePath)) {
    $pyArgs += @("--palace-path", $PalacePath)
}
if (-not [string]::IsNullOrWhiteSpace($CollectionName)) {
    $pyArgs += @("--collection-name", $CollectionName)
}
if (-not [string]::IsNullOrWhiteSpace($DefaultProjectName)) {
    $pyArgs += @("--default-project-name", $DefaultProjectName)
}
if (-not [string]::IsNullOrWhiteSpace($TopicPrefix)) {
    $pyArgs += @("--topic-prefix", $TopicPrefix)
}
if ($PalaceIndex -ge 0) {
    $pyArgs += @("--palace-index", "$PalaceIndex")
}
if ($Limit -gt 0) {
    $pyArgs += @("--limit", "$Limit")
}
if ($DryRun) {
    $pyArgs += "--dry-run"
}
if ($ForceResync) {
    $pyArgs += "--force-resync"
}
if ($Strict) {
    $pyArgs += "--strict"
}
if ($SemanticDiff) {
    $pyArgs += "--semantic-diff"
}
if ($SimilarityThreshold -ne 0.95) {
    $pyArgs += @("--similarity-threshold", "$SimilarityThreshold")
}
if ($Workers -ne 4) {
    $pyArgs += @("--workers", "$Workers")
}

& python @pyArgs
if ($LASTEXITCODE -ne 0) {
    throw "MemPalace -> ContextLattice sync failed with exit code $LASTEXITCODE."
}

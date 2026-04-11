param(
    [string]$ProjectRoot = "."
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$bridgeDir = Join-Path $root ".memorybridge"
if (-not (Test-Path -LiteralPath $bridgeDir)) {
    New-Item -ItemType Directory -Path $bridgeDir -Force | Out-Null
}

$defaultProject = Split-Path -Leaf $root

$samplePath = Join-Path $bridgeDir "bridge.config.sample.json"
if (-not (Test-Path -LiteralPath $samplePath)) {
@"
{
  "orchestratorUrl": "http://127.0.0.1:8075",
  "apiKeyEnvVar": "CONTEXTLATTICE_ORCHESTRATOR_API_KEY",
  "palacePath": "~/.mempalace/palace",
  "collectionName": "mempalace_drawers",
  "defaultProjectName": "$defaultProject",
  "topicPrefix": "mempalace",
  "wingProjectMap": {
    "default_wing": "$defaultProject"
  }
}
"@ | Set-Content -LiteralPath $samplePath -Encoding UTF8
}

$configPath = Join-Path $bridgeDir "bridge.config.json"
if (-not (Test-Path -LiteralPath $configPath)) {
    Copy-Item -LiteralPath $samplePath -Destination $configPath -Force
}

$statePath = Join-Path $bridgeDir "sync-state.json"
if (-not (Test-Path -LiteralPath $statePath)) {
@'
{
  "version": 1,
  "synced": {},
  "lastRunUtc": null
}
'@ | Set-Content -LiteralPath $statePath -Encoding UTF8
}

Write-Output "Bootstrapped memory bridge files:"
Write-Output " - $samplePath"
Write-Output " - $configPath"
Write-Output " - $statePath"


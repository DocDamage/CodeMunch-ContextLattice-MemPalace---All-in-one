[CmdletBinding()]
param(
    [string]$ProjectRoot = "."
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$ctxDir = Join-Path $root ".contextlattice"
if (-not (Test-Path -LiteralPath $ctxDir)) {
    New-Item -ItemType Directory -Path $ctxDir -Force | Out-Null
}

$schemaPath = Join-Path $ctxDir "orchestrator.env.schema.json"
if (-not (Test-Path -LiteralPath $schemaPath)) {
    $sourceSchema = Join-Path $PSScriptRoot "..\..\..\..\..\.contextlattice\orchestrator.env.schema.json"
    if (Test-Path -LiteralPath $sourceSchema) {
        Copy-Item -LiteralPath $sourceSchema -Destination $schemaPath -Force
    }
}

$projectName = Split-Path -Leaf $root
$envSamplePath = Join-Path $ctxDir "orchestrator.env.sample"
if (-not (Test-Path -LiteralPath $envSamplePath)) {
@"
# ContextLattice Orchestrator Configuration
# Schema: ./orchestrator.env.schema.json
CONTEXTLATTICE_ORCHESTRATOR_URL=http://127.0.0.1:8075
CONTEXTLATTICE_ORCHESTRATOR_API_KEY=replace-with-your-contextlattice-api-key
CONTEXTLATTICE_PROJECT_NAME=$projectName
"@ | Set-Content -LiteralPath $envSamplePath -Encoding UTF8
}

$mcpSamplePath = Join-Path $ctxDir "mcp.server.sample.json"
if (-not (Test-Path -LiteralPath $mcpSamplePath)) {
@'
{
  "mcpServers": {
    "memorymcp": {
      "type": "http",
      "serverUrl": "http://127.0.0.1:59081/mcp"
    }
  }
}
'@ | Set-Content -LiteralPath $mcpSamplePath -Encoding UTF8
}

Write-Output "Bootstrapped ContextLattice project files:"
Write-Output " - $schemaPath"
Write-Output " - $envSamplePath"
Write-Output " - $mcpSamplePath"


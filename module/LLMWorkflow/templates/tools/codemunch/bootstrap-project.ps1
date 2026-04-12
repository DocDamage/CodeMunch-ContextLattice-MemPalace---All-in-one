[CmdletBinding()]
param(
    [string]$ProjectRoot = "."
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$codemunchDir = Join-Path $root ".codemunch"
if (-not (Test-Path -LiteralPath $codemunchDir)) {
    New-Item -ItemType Directory -Path $codemunchDir -Force | Out-Null
}

$schemaPath = Join-Path $codemunchDir "index.defaults.schema.json"
if (-not (Test-Path -LiteralPath $schemaPath)) {
    $sourceSchema = Join-Path $PSScriptRoot "..\..\..\..\..\.codemunch\index.defaults.schema.json"
    if (Test-Path -LiteralPath $sourceSchema) {
        Copy-Item -LiteralPath $sourceSchema -Destination $schemaPath -Force
    }
}

$indexDefaultsPath = Join-Path $codemunchDir "index.defaults.json"
if (-not (Test-Path -LiteralPath $indexDefaultsPath)) {
    @'
{
  "$schema": "./index.defaults.schema.json",
  "include_patterns": [],
  "exclude_patterns": [
    ".git/*",
    "node_modules/*",
    "build/*",
    "dist/*",
    ".venv/*",
    "venv/*",
    ".cache/*"
  ]
}
'@ | Set-Content -LiteralPath $indexDefaultsPath -Encoding UTF8
}

$mcpSnippetPath = Join-Path $codemunchDir "mcp.server.sample.json"
if (-not (Test-Path -LiteralPath $mcpSnippetPath)) {
    @'
{
  "mcpServers": {
    "codemunch-pro": {
      "command": "codemunch-pro",
      "args": ["server", "--transport", "stdio"]
    }
  }
}
'@ | Set-Content -LiteralPath $mcpSnippetPath -Encoding UTF8
}

Write-Output "Bootstrapped codemunch project files:"
Write-Output " - $schemaPath"
Write-Output " - $indexDefaultsPath"
Write-Output " - $mcpSnippetPath"


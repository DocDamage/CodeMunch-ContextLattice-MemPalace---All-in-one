[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [switch]$Embed,
    [string[]]$IncludePattern = @(),
    [string[]]$ExcludePattern = @(
        ".git/*",
        "node_modules/*",
        "build/*",
        "dist/*",
        ".venv/*",
        "venv/*",
        ".cache/*"
    ),
    [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = "."
}
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path

$globalIndexCmd = Join-Path $env:LOCALAPPDATA "Programs\rom-tools\bin\codemunch-index.cmd"
$globalIndexEmbedCmd = Join-Path $env:LOCALAPPDATA "Programs\rom-tools\bin\codemunch-index-embed.cmd"

if ($PSBoundParameters.ContainsKey("IncludePattern") -and $IncludePattern.Count -gt 0) {
    Write-Warning "IncludePattern is managed by global wrapper defaults in this mode and will be ignored."
}
if ($PSBoundParameters.ContainsKey("ExcludePattern") -and $ExcludePattern.Count -gt 0) {
    Write-Warning "ExcludePattern is managed by global wrapper defaults in this mode and will be ignored."
}

if (Test-Path -LiteralPath $globalIndexCmd) {
    if ($Embed) {
        if (-not (Test-Path -LiteralPath $globalIndexEmbedCmd)) {
            throw "Global codemunch embed wrapper not found: $globalIndexEmbedCmd"
        }
        $result = & $globalIndexEmbedCmd $projectPath
    } else {
        $result = & $globalIndexCmd $projectPath
    }
} else {
    Write-Warning "Global codemunch wrappers not found under $($env:LOCALAPPDATA)\Programs\rom-tools\bin. Falling back to direct codemunch_pro indexing."
    $embedValue = if ($Embed) { "true" } else { "false" }
    $result = @'
import json
import sys

from codemunch_pro.server import _index_directory

project_path = sys.argv[1]
embed_flag = sys.argv[2].lower() in {"1", "true", "yes", "on"}
stats = _index_directory(project_path, include_patterns=None, exclude_patterns=None, embed=embed_flag)
print(json.dumps(stats, indent=2))
'@ | python - $projectPath $embedValue

    if ($LASTEXITCODE -ne 0) {
        throw "Fallback codemunch indexing failed. Ensure Python and codemunch-pro are installed and importable."
    }
}

if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
    $outResolved = if ([System.IO.Path]::IsPathRooted($OutFile)) {
        $OutFile
    } else {
        Join-Path $projectPath $OutFile
    }
    $outDir = Split-Path -Parent $outResolved
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    Set-Content -LiteralPath $outResolved -Value $result -Encoding UTF8
    Write-Output "Wrote: $outResolved"
}

$result

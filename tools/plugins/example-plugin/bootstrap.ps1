[CmdletBinding()]
param(
    [string]$ProjectRoot = ".",
    [hashtable]$Context = @{}
)

$ErrorActionPreference = "Stop"

function Write-PluginLog {
    param([string]$Message)
    Write-Output "[example-plugin] $Message"
}

Write-PluginLog "Starting example plugin bootstrap..."
Write-PluginLog "Project root: $ProjectRoot"

# Example: Create a marker file to show the plugin ran
$markerPath = Join-Path $ProjectRoot ".llm-workflow" "example-plugin-ran.marker"
$markerContent = @{
    timestamp = [DateTime]::UtcNow.ToString("o")
    plugin = "example-plugin"
    version = "1.0.0"
} | ConvertTo-Json

Set-Content -Path $markerPath -Value $markerContent -Encoding UTF8

Write-PluginLog "Example plugin bootstrap complete!"
Write-PluginLog "Marker file created at: $markerPath"

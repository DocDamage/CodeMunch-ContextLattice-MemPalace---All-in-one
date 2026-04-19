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

Write-PluginLog "Running example plugin health check..."

$checks = @()
$passed = 0
$failed = 0

# Check 1: Verify marker file exists
$markerPath = Join-Path $ProjectRoot ".llm-workflow" "example-plugin-ran.marker"
if (Test-Path -LiteralPath $markerPath) {
    $checks += [pscustomobject]@{
        name = "marker_file_exists"
        status = "pass"
        message = "Marker file found at $markerPath"
    }
    $passed++
} else {
    $checks += [pscustomobject]@{
        name = "marker_file_exists"
        status = "fail"
        message = "Marker file not found - bootstrap may not have run"
    }
    $failed++
}

# Check 2: Validate marker file content
if (Test-Path -LiteralPath $markerPath) {
    try {
        $content = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
        if ($content.plugin -eq "example-plugin") {
            $checks += [pscustomobject]@{
                name = "marker_file_valid"
                status = "pass"
                message = "Marker file contains valid plugin reference"
            }
            $passed++
        } else {
            $checks += [pscustomobject]@{
                name = "marker_file_valid"
                status = "fail"
                message = "Marker file has unexpected plugin name"
            }
            $failed++
        }
    } catch {
        $checks += [pscustomobject]@{
            name = "marker_file_valid"
            status = "fail"
            message = "Marker file is not valid JSON: $($_.Exception.Message)"
        }
        $failed++
    }
}

# Output results
Write-PluginLog "Checks complete: $passed passed, $failed failed"

foreach ($check in $checks) {
    $statusSymbol = if ($check.status -eq "pass") { "[OK]" } else { "[FAIL]" }
    Write-PluginLog "$statusSymbol $($check.name): $($check.message)"
}

# Return exit code based on results
if ($failed -gt 0) {
    exit 1
}

exit 0

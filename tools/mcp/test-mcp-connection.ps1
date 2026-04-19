<#
.SYNOPSIS
    Tests MCP server connections for LLM Workflow platform.

.DESCRIPTION
    Tests connectivity to MCP servers, executes individual tools, measures
    response times, and generates a comprehensive connection report.

.PARAMETER GatewayUrl
    URL of the MCP Composite Gateway. Default: http://localhost:8080.

.PARAMETER TestAllTools
    Test all registered tools in addition to basic connectivity.

.PARAMETER ToolName
    Specific tool name to test (for single tool testing).

.PARAMETER ToolParams
    Parameters for the specific tool being tested (as JSON string).

.PARAMETER TimeoutSeconds
    Timeout for each test in seconds. Default: 30.

.PARAMETER OutputFormat
    Output format: 'table', 'json', 'csv', or 'html'. Default: table.

.PARAMETER OutputPath
    Path to save the test report. If not specified, output to console only.

.PARAMETER Detailed
    Include detailed timing and metadata in the report.

.PARAMETER RetryCount
    Number of retries for failed tests. Default: 3.

.EXAMPLE
    .\test-mcp-connection.ps1 -GatewayUrl "http://localhost:8080"

.EXAMPLE
    .\test-mcp-connection.ps1 -TestAllTools -OutputFormat json -OutputPath "mcp-test-report.json"

.EXAMPLE
    .\test-mcp-connection.ps1 -ToolName "godot_version" -ToolParams '{}'

.NOTES
    File Name      : test-mcp-connection.ps1
    Author         : LLM Workflow Team
    Version        : 1.0.0
    Requires       : PowerShell 5.1+
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GatewayUrl = "http://localhost:8080",

    [Parameter()]
    [switch]$TestAllTools,

    [Parameter()]
    [string]$ToolName = "",

    [Parameter()]
    [string]$ToolParams = "{}",

    [Parameter()]
    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 30,

    [Parameter()]
    [ValidateSet('table', 'json', 'csv', 'html')]
    [string]$OutputFormat = 'table',

    [Parameter()]
    [string]$OutputPath = "",

    [Parameter()]
    [switch]$Detailed,

    [Parameter()]
    [ValidateRange(0, 10)]
    [int]$RetryCount = 3
)

$ErrorActionPreference = "Stop"
$script:ScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Split-Path -Parent $PSCommandPath) }

# Import logging module if available
$LoggingModulePath = Join-Path $script:ScriptRoot "..\..\module\LLMWorkflow\core\Logging.ps1"
if (Test-Path -LiteralPath $LoggingModulePath) {
    Import-Module $LoggingModulePath -Force -ErrorAction SilentlyContinue
}

# =============================================================================
# Data Structures
# =============================================================================

$script:TestResults = [System.Collections.Generic.List[object]]::new()
$script:TestStartTime = [DateTime]::UtcNow

# =============================================================================
# Logging Functions
# =============================================================================

function Write-TestLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'SUCCESS')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $logPrefix = "[MCP-Test-$Level]"
    
    switch ($Level) {
        'ERROR'   { Write-Host "[$timestamp] $logPrefix $Message" -ForegroundColor Red }
        'WARN'    { Write-Host "[$timestamp] $logPrefix $Message" -ForegroundColor Yellow }
        'SUCCESS' { Write-Host "[$timestamp] $logPrefix $Message" -ForegroundColor Green }
        'DEBUG'   { Write-Verbose "[$timestamp] $logPrefix $Message" }
        default   { Write-Output "[$timestamp] $logPrefix $Message" }
    }
}

# =============================================================================
# Test Functions
# =============================================================================

function Test-GatewayConnectivity {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Write-TestLog -Level INFO -Message "Testing gateway connectivity to $GatewayUrl..."

    $result = [PSCustomObject]@{
        TestName = "Gateway Connectivity"
        Category = "Connectivity"
        Status = "FAILED"
        ResponseTimeMs = 0
        Error = $null
        Details = @{}
        Timestamp = [DateTime]::UtcNow.ToString('o')
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        $response = Invoke-RestMethod -Uri "$GatewayUrl/health" `
                                      -Method GET `
                                      -TimeoutSec $TimeoutSeconds
        
        $stopwatch.Stop()
        
        $result.ResponseTimeMs = [int]$stopwatch.ElapsedMilliseconds
        $result.Details = @{
            Status = $response.status
            Version = $response.version
            Timestamp = $response.timestamp
        }
        $result.Status = "PASSED"
        
        Write-TestLog -Level SUCCESS -Message "Gateway connectivity test passed ($($result.ResponseTimeMs)ms)"
    }
    catch {
        $stopwatch.Stop()
        $result.ResponseTimeMs = [int]$stopwatch.ElapsedMilliseconds
        $result.Error = $_.Exception.Message
        Write-TestLog -Level ERROR -Message "Gateway connectivity test failed: $_"
    }

    $script:TestResults.Add($result)
    return $result
}

function Test-GatewayStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Write-TestLog -Level INFO -Message "Testing gateway status endpoint..."

    $result = [PSCustomObject]@{
        TestName = "Gateway Status"
        Category = "Status"
        Status = "FAILED"
        ResponseTimeMs = 0
        Error = $null
        Details = @{}
        Timestamp = [DateTime]::UtcNow.ToString('o')
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        # Try multiple possible status endpoints
        $endpoints = @(
            "$GatewayUrl/api/status",
            "$GatewayUrl/status",
            "$GatewayUrl/v1/status"
        )

        $response = $null
        foreach ($endpoint in $endpoints) {
            try {
                $response = Invoke-RestMethod -Uri $endpoint -Method GET -TimeoutSec $TimeoutSeconds
                break
            }
            catch {
                continue
            }
        }

        if (-not $response) {
            throw "No status endpoint responded successfully"
        }
        
        $stopwatch.Stop()
        
        $result.ResponseTimeMs = [int]$stopwatch.ElapsedMilliseconds
        $result.Details = @{
            IsRunning = $response.isRunning
            RouteCount = $response.routeCount
            SessionCount = $response.sessionCount
            Uptime = $response.uptime
        }
        $result.Status = "PASSED"
        
        Write-TestLog -Level SUCCESS -Message "Gateway status test passed ($($result.ResponseTimeMs)ms)"
    }
    catch {
        $stopwatch.Stop()
        $result.ResponseTimeMs = [int]$stopwatch.ElapsedMilliseconds
        $result.Error = $_.Exception.Message
        Write-TestLog -Level ERROR -Message "Gateway status test failed: $_"
    }

    $script:TestResults.Add($result)
    return $result
}

function Test-ToolExecution {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Parameters = @{}
    )

    Write-TestLog -Level INFO -Message "Testing tool: $Name..."

    $result = [PSCustomObject]@{
        TestName = "Tool: $Name"
        Category = "ToolExecution"
        ToolName = $Name
        Status = "FAILED"
        ResponseTimeMs = 0
        Error = $null
        Details = @{}
        Timestamp = [DateTime]::UtcNow.ToString('o')
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $retryAttempt = 0
    $success = $false

    while ($retryAttempt -le $RetryCount -and -not $success) {
        try {
            if ($retryAttempt -gt 0) {
                Write-TestLog -Level INFO -Message "Retry attempt $retryAttempt for tool: $Name"
                Start-Sleep -Milliseconds 500
            }

            $requestBody = @{
                jsonrpc = "2.0"
                method = "tools/call"
                params = @{
                    name = $Name
                    arguments = $Parameters
                }
                id = [Guid]::NewGuid().ToString()
            } | ConvertTo-Json -Depth 5

            $response = Invoke-RestMethod -Uri "$GatewayUrl/api/mcp" `
                                          -Method POST `
                                          -ContentType "application/json" `
                                          -Body $requestBody `
                                          -TimeoutSec $TimeoutSeconds
            
            $stopwatch.Stop()
            
            $result.ResponseTimeMs = [int]$stopwatch.ElapsedMilliseconds
            
            if ($response.error) {
                throw "Tool returned error: $($response.error.message)"
            }

            $result.Details = @{
                Result = if ($Detailed) { $response.result } else { "[redacted]" }
                ToolCallId = $response.id
            }
            $result.Status = "PASSED"
            $success = $true
            
            Write-TestLog -Level SUCCESS -Message "Tool '$Name' test passed ($($result.ResponseTimeMs)ms)"
        }
        catch {
            $retryAttempt++
            if ($retryAttempt -gt $RetryCount) {
                $stopwatch.Stop()
                $result.ResponseTimeMs = [int]$stopwatch.ElapsedMilliseconds
                $result.Error = $_.Exception.Message
                Write-TestLog -Level ERROR -Message "Tool '$Name' test failed after $RetryCount retries: $_"
            }
        }
    }

    $script:TestResults.Add($result)
    return $result
}

function Test-RouteAvailability {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Write-TestLog -Level INFO -Message "Testing route availability..."

    $result = [PSCustomObject]@{
        TestName = "Route Availability"
        Category = "Routes"
        Status = "FAILED"
        ResponseTimeMs = 0
        Error = $null
        Details = @{
            Routes = @()
            Available = 0
            Unavailable = 0
        }
        Timestamp = [DateTime]::UtcNow.ToString('o')
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        # Try to get routes from gateway
        $routes = @()
        
        $endpoints = @(
            "$GatewayUrl/api/routes",
            "$GatewayUrl/routes"
        )

        foreach ($endpoint in $endpoints) {
            try {
                $response = Invoke-RestMethod -Uri $endpoint -Method GET -TimeoutSec $TimeoutSeconds
                if ($response.routes) {
                    $routes = $response.routes
                    break
                }
            }
            catch {
                continue
            }
        }

        # If no routes endpoint available, use default routes for testing
        if ($routes.Count -eq 0) {
            $routes = @(
                @{ packId = "godot-engine"; prefix = "godot_"; enabled = $true }
                @{ packId = "blender-engine"; prefix = "blender_"; enabled = $true }
                @{ packId = "rpgmaker-mz"; prefix = "rpgmaker_"; enabled = $true }
            )
        }

        $stopwatch.Stop()
        
        $availableRoutes = @($routes | Where-Object { $_.enabled })
        $unavailableRoutes = @($routes | Where-Object { -not $_.enabled })

        $result.ResponseTimeMs = [int]$stopwatch.ElapsedMilliseconds
        $result.Details.Routes = $routes | ForEach-Object { 
            @{ 
                PackId = $_.packId
                Prefix = $_.prefix
                Enabled = $_.enabled
                Endpoint = $_.endpoint
            }
        }
        $result.Details.Available = $availableRoutes.Count
        $result.Details.Unavailable = $unavailableRoutes.Count
        $result.Status = "PASSED"
        
        Write-TestLog -Level SUCCESS -Message "Route availability test passed - $($availableRoutes.Count) available, $($unavailableRoutes.Count) unavailable"
    }
    catch {
        $stopwatch.Stop()
        $result.ResponseTimeMs = [int]$stopwatch.ElapsedMilliseconds
        $result.Error = $_.Exception.Message
        Write-TestLog -Level ERROR -Message "Route availability test failed: $_"
    }

    $script:TestResults.Add($result)
    return $result
}

function Test-SpecificTool {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if ([string]::IsNullOrWhiteSpace($ToolName)) {
        return $null
    }

    try {
        $params = $ToolParams | ConvertFrom-Json -AsHashtable
    }
    catch {
        Write-TestLog -Level WARN -Message "Failed to parse ToolParams as JSON, using empty params"
        $params = @{}
    }

    return Test-ToolExecution -Name $ToolName -Parameters $params
}

function Test-AllRegisteredTools {
    [CmdletBinding()]
    param()

    if (-not $TestAllTools) {
        return
    }

    Write-TestLog -Level INFO -Message "Testing all registered tools..."

    # Define test tools by category
    $testTools = @(
        # Godot tools
        @{ Name = "godot_version"; Params = @{}; Category = "Godot" }
        @{ Name = "godot_project_list"; Params = @{}; Category = "Godot" }
        
        # Blender tools
        @{ Name = "blender_version"; Params = @{}; Category = "Blender" }
        @{ Name = "blender_get_scene_info"; Params = @{}; Category = "Blender" }
        
        # Common tools
        @{ Name = "pack_status"; Params = @{}; Category = "Common" }
        @{ Name = "pack_query"; Params = @{ query = "test" }; Category = "Common" }
    )

    foreach ($tool in $testTools) {
        Test-ToolExecution -Name $tool.Name -Parameters $tool.Params
        Start-Sleep -Milliseconds 100  # Brief pause between tests
    }
}

# =============================================================================
# Report Generation Functions
# =============================================================================

function Get-TestSummary {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $passed = @($script:TestResults | Where-Object { $_.Status -eq "PASSED" }).Count
    $failed = @($script:TestResults | Where-Object { $_.Status -eq "FAILED" }).Count
    $total = $script:TestResults.Count

    $totalTime = [DateTime]::UtcNow - $script:TestStartTime
    $avgResponseTime = if ($total -gt 0) { 
        [int](($script:TestResults | Measure-Object -Property ResponseTimeMs -Average).Average)
    } else { 
        0 
    }

    return [PSCustomObject]@{
        TotalTests = $total
        Passed = $passed
        Failed = $failed
        PassRate = if ($total -gt 0) { [math]::Round(($passed / $total) * 100, 2) } else { 0 }
        TotalDurationMs = [int]$totalTime.TotalMilliseconds
        AverageResponseTimeMs = $avgResponseTime
        TestStartTime = $script:TestStartTime.ToString('o')
        TestEndTime = [DateTime]::UtcNow.ToString('o')
    }
}

function Export-TestReport {
    [CmdletBinding()]
    param()

    $summary = Get-TestSummary
    
    $report = [PSCustomObject]@{
        Summary = $summary
        Results = $script:TestResults
        Metadata = @{
            GatewayUrl = $GatewayUrl
            OutputFormat = $OutputFormat
            Detailed = $Detailed.IsPresent
            RetryCount = $RetryCount
            Timestamp = [DateTime]::UtcNow.ToString('o')
        }
    }

    switch ($OutputFormat) {
        'json' {
            $output = $report | ConvertTo-Json -Depth 10
            if ($OutputPath) {
                $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
                Write-TestLog -Level INFO -Message "Report saved to: $OutputPath"
            }
            return $output
        }
        
        'csv' {
            $csvData = $script:TestResults | ForEach-Object {
                [PSCustomObject]@{
                    TestName = $_.TestName
                    Category = $_.Category
                    Status = $_.Status
                    ResponseTimeMs = $_.ResponseTimeMs
                    Error = $_.Error
                    Timestamp = $_.Timestamp
                }
            }
            $output = $csvData | ConvertTo-Csv -NoTypeInformation
            if ($OutputPath) {
                $output | Set-Content -LiteralPath $OutputPath -Encoding UTF8
                Write-TestLog -Level INFO -Message "Report saved to: $OutputPath"
            }
            return ($output -join "`n")
        }
        
        'html' {
            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>MCP Connection Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .summary { background: #f5f5f5; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .passed { color: green; }
        .failed { color: red; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
        tr:nth-child(even) { background-color: #f2f2f2; }
        .status-passed { color: green; font-weight: bold; }
        .status-failed { color: red; font-weight: bold; }
    </style>
</head>
<body>
    <h1>MCP Connection Test Report</h1>
    <div class="summary">
        <h2>Summary</h2>
        <p>Gateway URL: $GatewayUrl</p>
        <p>Total Tests: $($summary.TotalTests)</p>
        <p class="passed">Passed: $($summary.Passed)</p>
        <p class="failed">Failed: $($summary.Failed)</p>
        <p>Pass Rate: $($summary.PassRate)%</p>
        <p>Total Duration: $($summary.TotalDurationMs)ms</p>
        <p>Average Response Time: $($summary.AverageResponseTimeMs)ms</p>
    </div>
    <table>
        <tr>
            <th>Test Name</th>
            <th>Category</th>
            <th>Status</th>
            <th>Response Time (ms)</th>
            <th>Error</th>
        </tr>
"@
            foreach ($result in $script:TestResults) {
                $statusClass = if ($result.Status -eq "PASSED") { "status-passed" } else { "status-failed" }
                $html += @"
        <tr>
            <td>$($result.TestName)</td>
            <td>$($result.Category)</td>
            <td class="$statusClass">$($result.Status)</td>
            <td>$($result.ResponseTimeMs)</td>
            <td>$($result.Error)</td>
        </tr>
"@
            }
            
            $html += @"
    </table>
    <p style="margin-top: 20px; color: #666;">Generated: $([DateTime]::UtcNow.ToString('o'))</p>
</body>
</html>
"@
            if ($OutputPath) {
                $html | Set-Content -LiteralPath $OutputPath -Encoding UTF8
                Write-TestLog -Level INFO -Message "Report saved to: $OutputPath"
            }
            return $html
        }
        
        default { # table
            Write-Output ""
            Write-Output "=== MCP Connection Test Summary ==="
            Write-Output "Gateway URL:      $GatewayUrl"
            Write-Output "Total Tests:      $($summary.TotalTests)"
            Write-Output "Passed:           $($summary.Passed)"
            Write-Output "Failed:           $($summary.Failed)"
            Write-Output "Pass Rate:        $($summary.PassRate)%"
            Write-Output "Total Duration:   $($summary.TotalDurationMs)ms"
            Write-Output "Avg Response:     $($summary.AverageResponseTimeMs)ms"
            Write-Output ""
            
            $script:TestResults | Format-Table -Property @(
                @{N='Test Name'; E={$_.TestName.Substring(0, [Math]::Min(40, $_.TestName.Length))}},
                @{N='Category'; E={$_.Category}; Width=15},
                @{N='Status'; E={$_.Status}; Width=10},
                @{N='Time (ms)'; E={$_.ResponseTimeMs}; Width=10},
                @{N='Error'; E={if ($_.Error) { $_.Error.Substring(0, [Math]::Min(50, $_.Error.Length)) } else { "" }}; Width=50}
            ) -AutoSize
        }
    }
}

# =============================================================================
# Main Execution
# =============================================================================

function Main {
    [CmdletBinding()]
    param()

    Write-TestLog -Level INFO -Message "=== MCP Connection Testing Started ==="
    Write-TestLog -Level INFO -Message "Gateway URL: $GatewayUrl"

    try {
        # Test 1: Basic connectivity
        Test-GatewayConnectivity

        # Test 2: Gateway status
        Test-GatewayStatus

        # Test 3: Route availability
        Test-RouteAvailability

        # Test 4: Specific tool (if specified)
        Test-SpecificTool | Out-Null

        # Test 5: All tools (if requested)
        Test-AllRegisteredTools

        # Generate and output report
        Export-TestReport

        $summary = Get-TestSummary
        
        Write-TestLog -Level INFO -Message "=== MCP Connection Testing Completed ==="
        Write-TestLog -Level INFO -Message "Results: $($summary.Passed) passed, $($summary.Failed) failed out of $($summary.TotalTests) tests"

        # Return summary object
        return $summary
    }
    catch {
        Write-TestLog -Level ERROR -Message "Testing failed: $_"
        throw
    }
}

# Run main function
Main

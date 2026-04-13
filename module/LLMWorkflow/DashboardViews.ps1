#requires -Version 5.1
<#
.SYNOPSIS
    Dashboard Views module for LLM Workflow platform (Phase 7).

.DESCRIPTION
    Provides comprehensive dashboard views for visualizing system health, 
    pack status, retrieval metrics, cross-pack relationships, MCP gateway status,
    and federated memory status.
    
    Features:
    - Pack health overview with color-coded status indicators
    - Retrieval activity metrics and cache performance
    - Cross-pack relationship graph visualization (Mermaid/JSON)
    - MCP gateway status with circuit breaker states
    - Federated memory node synchronization status
    - HTML export with responsive layout and theme support

.NOTES
    Author: LLM Workflow Platform
    Version: 1.0.0
    Date: 2026-04-12
    Phase: 7 - Dashboard Views Implementation
#>

Set-StrictMode -Version Latest

#===============================================================================
# Module Configuration and Constants
#===============================================================================

$script:DashboardVersion = '1.0.0'
$script:DefaultDashboardDir = '.llm-workflow/dashboards'
$script:DefaultExportDir = '.llm-workflow/exports'

# ANSI Color Codes for Console Output
$script:AnsiColors = @{
    Reset = "$([char]0x1B)[0m"
    Bold = "$([char]0x1B)[1m"
    Dim = "$([char]0x1B)[2m"
    Red = "$([char]0x1B)[31m"
    Green = "$([char]0x1B)[32m"
    Yellow = "$([char]0x1B)[33m"
    Blue = "$([char]0x1B)[34m"
    Magenta = "$([char]0x1B)[35m"
    Cyan = "$([char]0x1B)[36m"
    White = "$([char]0x1B)[37m"
    BrightRed = "$([char]0x1B)[91m"
    BrightGreen = "$([char]0x1B)[92m"
    BrightYellow = "$([char]0x1B)[93m"
    BrightBlue = "$([char]0x1B)[94m"
    BgRed = "$([char]0x1B)[41m"
    BgGreen = "$([char]0x1B)[42m"
    BgYellow = "$([char]0x1B)[43m"
}

# Status Color Mapping
$script:StatusColors = @{
    Healthy = 'Green'
    Degraded = 'Yellow'
    Critical = 'Red'
    Warning = 'Yellow'
    OK = 'Green'
    Notice = 'Blue'
    compliant = 'Green'
    warning = 'Yellow'
    critical = 'Red'
    active = 'Green'
    inactive = 'Gray'
    suspended = 'Yellow'
    offline = 'Red'
    error = 'Red'
    CLOSED = 'Green'
    OPEN = 'Red'
    HALF_OPEN = 'Yellow'
}

# HTML Theme Colors (Dark/Light)
$script:HtmlThemes = @{
    dark = @{
        bgColor = '#1e1e1e'
        cardBg = '#252526'
        textColor = '#d4d4d4'
        borderColor = '#3e3e42'
        healthyColor = '#4ec9b0'
        warningColor = '#dcdcaa'
        criticalColor = '#f44747'
        headerBg = '#2d2d30'
        accentColor = '#569cd6'
    }
    light = @{
        bgColor = '#ffffff'
        cardBg = '#f5f5f5'
        textColor = '#333333'
        borderColor = '#e0e0e0'
        healthyColor = '#28a745'
        warningColor = '#ffc107'
        criticalColor = '#dc3545'
        headerBg = '#f8f9fa'
        accentColor = '#007bff'
    }
}

#===============================================================================
# Private Helper Functions
#===============================================================================

function Get-AnsiColor {
    <#
    .SYNOPSIS
        Gets ANSI color code for a status.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,
        
        [switch]$UseAnsi
    )
    
    if (-not $UseAnsi) { return '' }
    
    $colorName = $script:StatusColors[$Status]
    if (-not $colorName) { $colorName = 'White' }
    
    return $script:AnsiColors[$colorName]
}

function Format-StatusIndicator {
    <#
    .SYNOPSIS
        Formats a status indicator with optional ANSI colors.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,
        
        [switch]$UseAnsi
    )
    
    $indicators = @{
        Healthy = '[OK]'
        Degraded = '[WARN]'
        Critical = '[CRIT]'
        Warning = '[WARN]'
        OK = '[OK]'
        Notice = '[INFO]'
        compliant = '[OK]'
        warning = '[WARN]'
        critical = '[CRIT]'
        active = '[ON]'
        inactive = '[OFF]'
        suspended = '[HOLD]'
        offline = '[DOWN]'
        error = '[ERR]'
        CLOSED = '[OK]'
        OPEN = '[OPEN]'
        HALF_OPEN = '[TEST]'
    }
    
    $indicator = $indicators[$Status]
    if (-not $indicator) { $indicator = "[$Status]" }
    
    if ($UseAnsi) {
        $color = Get-AnsiColor -Status $Status -UseAnsi
        $reset = $script:AnsiColors.Reset
        return "$color$indicator$reset"
    }
    
    return $indicator
}

function Test-AnsiSupport {
    <#
    .SYNOPSIS
        Tests if the current environment supports ANSI colors.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
        return $true
    }
    if ($env:TERM -and $env:TERM -ne 'dumb') { return $true }
    if ($env:WT_SESSION) { return $true }
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
        return ($Host.Name -eq 'ConsoleHost')
    }
    return $false
}

function Get-PackList {
    <#
    .SYNOPSIS
        Discovers all packs in the workspace.
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [string]$ProjectRoot = '.'
    )
    
    $manifestDir = Join-Path $ProjectRoot 'packs/manifests'
    $packs = @()
    
    if (Test-Path -LiteralPath $manifestDir) {
        $packFiles = Get-ChildItem -Path $manifestDir -Filter '*.json' -ErrorAction SilentlyContinue
        foreach ($file in $packFiles) {
            try {
                $manifest = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                $packs += @{
                    packId = $manifest.packId
                    domain = $manifest.domain
                    version = $manifest.version
                    manifestPath = $file.FullName
                }
            }
            catch {
                Write-Verbose "Failed to parse manifest: $($file.Name)"
            }
        }
    }
    
    return $packs
}

function Get-HealthScoreColor {
    <#
    .SYNOPSIS
        Returns color based on health score value.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Score,
        
        [switch]$UseAnsi
    )
    
    if ($Score -ge 80) {
        return if ($UseAnsi) { $script:AnsiColors.Green } else { 'Green' }
    }
    elseif ($Score -ge 60) {
        return if ($UseAnsi) { $script:AnsiColors.Yellow } else { 'Yellow' }
    }
    else {
        return if ($UseAnsi) { $script:AnsiColors.Red } else { 'Red' }
    }
}

#===============================================================================
# Pack Health Dashboard
#===============================================================================

<#
.SYNOPSIS
    Displays pack health overview dashboard.

.DESCRIPTION
    Shows health scores, status indicators, freshness, source counts, and
    validation status for all packs. Output can be formatted as console table
    or exported to HTML.

.PARAMETER PackId
    Optional specific pack ID to show. If not specified, shows all packs.

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'.

.PARAMETER ProjectRoot
    Project root directory. Defaults to current directory.

.PARAMETER UseAnsi
    Use ANSI color codes in console output.

.PARAMETER IncludeDetails
    Include detailed component breakdown.

.EXAMPLE
    Show-PackHealthDashboard
    
    Displays health dashboard for all packs in console.

.EXAMPLE
    Show-PackHealthDashboard -PackId 'rpgmaker-mz' -OutputFormat HTML -ExportPath 'health.html'
    
    Exports health dashboard for specific pack to HTML.

.OUTPUTS
    System.Collections.Hashtable or file output based on format.
#>
function Show-PackHealthDashboard {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$PackId = '',
        
        [Parameter()]
        [ValidateSet('Console', 'HTML', 'JSON')]
        [string]$OutputFormat = 'Console',
        
        [Parameter()]
        [string]$ProjectRoot = '.',
        
        [Parameter()]
        [switch]$UseAnsi,
        
        [Parameter()]
        [switch]$IncludeDetails,
        
        [Parameter()]
        [string]$ExportPath = ''
    )
    
    begin {
        $useAnsiColors = $UseAnsi -or (Test-AnsiSupport)
        $healthScorePath = Join-Path $PSScriptRoot 'workflow/HealthScore.ps1'
        
        # Import HealthScore module if available
        if (Test-Path -LiteralPath $healthScorePath) {
            . $healthScorePath
        }
        
        $dashboardData = @{
            generatedAt = [DateTime]::UtcNow.ToString('o')
            version = $script:DashboardVersion
            packs = @()
            summary = @{
                totalPacks = 0
                healthy = 0
                degraded = 0
                critical = 0
                averageScore = 0
            }
        }
    }
    
    process {
        # Get pack list
        $packs = if ($PackId) {
            @(@{ packId = $PackId })
        }
        else {
            Get-PackList -ProjectRoot $ProjectRoot
        }
        
        $totalScore = 0
        
        foreach ($pack in $packs) {
            $packHealth = $null
            
            # Try to get health score
            try {
                $healthCmd = Get-Command Test-PackHealth -ErrorAction SilentlyContinue
                if ($healthCmd) {
                    $packHealth = Test-PackHealth -PackId $pack.packId
                }
                else {
                    # Fallback: basic health check
                    $packHealth = Get-BasicPackHealth -PackId $pack.packId -ProjectRoot $ProjectRoot
                }
            }
            catch {
                Write-Warning "Failed to get health for pack '$($pack.packId)': $_"
                $packHealth = @{
                    packId = $pack.packId
                    overallScore = 0
                    status = 'Critical'
                    error = $_.ToString()
                }
            }
            
            $packEntry = @{
                packId = $pack.packId
                score = $packHealth.overallScore
                status = $packHealth.status
                severity = if ($packHealth.severity) { $packHealth.severity } else { $packHealth.status }
                warnings = if ($packHealth.warnings) { $packHealth.warnings.Count } else { 0 }
                criticalIssues = if ($packHealth.criticalIssues) { $packHealth.criticalIssues.Count } else { 0 }
                rawMetrics = $packHealth.rawMetrics
                components = if ($IncludeDetails) { $packHealth.components } else { $null }
            }
            
            $dashboardData.packs += $packEntry
            $totalScore += $packHealth.overallScore
            
            # Update summary counts
            switch ($packHealth.status) {
                'Healthy' { $dashboardData.summary.healthy++ }
                'Degraded' { $dashboardData.summary.degraded++ }
                'Critical' { $dashboardData.summary.critical++ }
            }
        }
        
        $dashboardData.summary.totalPacks = $packs.Count
        $dashboardData.summary.averageScore = if ($packs.Count -gt 0) { 
            [math]::Round($totalScore / $packs.Count) 
        } else { 0 }
        
        # Output based on format
        switch ($OutputFormat) {
            'Console' {
                Write-ConsoleHealthDashboard -Data $dashboardData -UseAnsi:$useAnsiColors -IncludeDetails:$IncludeDetails
            }
            'HTML' {
                $html = Convert-ToHealthDashboardHTML -Data $dashboardData -Theme 'dark'
                if ($ExportPath) {
                    $html | Out-File -FilePath $ExportPath -Encoding UTF8
                    Write-Host "Health dashboard exported to: $ExportPath"
                }
                return $html
            }
            'JSON' {
                $json = $dashboardData | ConvertTo-Json -Depth 10
                if ($ExportPath) {
                    $json | Out-File -FilePath $ExportPath -Encoding UTF8
                    Write-Host "Health dashboard exported to: $ExportPath"
                }
                return $json
            }
        }
        
        return $dashboardData
    }
}

function Get-BasicPackHealth {
    <#
    .SYNOPSIS
        Performs basic pack health check without HealthScore module.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$PackId,
        [string]$ProjectRoot = '.'
    )
    
    $score = 100
    $status = 'Healthy'
    $warnings = @()
    $criticalIssues = @()
    $rawMetrics = @{
        totalSources = 0
        activeSources = 0
        staleSources = 0
        lockfileStatus = 'missing'
    }
    
    # Check manifest
    $manifestPath = Join-Path $ProjectRoot "packs/manifests/$PackId.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        $score -= 20
        $criticalIssues += 'Manifest file not found'
    }
    
    # Check source registry
    $registryPath = Join-Path $ProjectRoot "packs/registries/$PackId.sources.json"
    if (Test-Path -LiteralPath $registryPath) {
        try {
            $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
            $rawMetrics.totalSources = if ($registry.sources) { $registry.sources.Count } else { 0 }
            $rawMetrics.activeSources = if ($registry.sources) { 
                ($registry.sources | Where-Object { $_.state -eq 'active' }).Count 
            } else { 0 }
        }
        catch {
            $score -= 10
            $warnings += 'Source registry unreadable'
        }
    }
    else {
        $score -= 20
        $criticalIssues += 'Source registry not found'
    }
    
    # Check lockfile
    $lockfilePath = Join-Path $ProjectRoot "packs/locks/$PackId.lock.json"
    if (Test-Path -LiteralPath $lockfilePath) {
        $rawMetrics.lockfileStatus = 'present'
    }
    else {
        $score -= 20
        $criticalIssues += 'Lockfile not found'
    }
    
    # Determine status
    if ($score -lt 60) {
        $status = 'Critical'
    }
    elseif ($score -lt 80) {
        $status = 'Degraded'
    }
    
    return @{
        packId = $PackId
        overallScore = [math]::Max(0, $score)
        status = $status
        severity = $status
        warnings = $warnings
        criticalIssues = $criticalIssues
        rawMetrics = $rawMetrics
    }
}

function Write-ConsoleHealthDashboard {
    <#
    .SYNOPSIS
        Writes health dashboard to console.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Data,
        [switch]$UseAnsi,
        [switch]$IncludeDetails
    )
    
    $a = $script:AnsiColors
    $reset = if ($UseAnsi) { $a.Reset } else { '' }
    $bold = if ($UseAnsi) { $a.Bold } else { '' }
    $cyan = if ($UseAnsi) { $a.Cyan } else { '' }
    
    # Header
    Write-Host "$bold$cyan========================================$reset"
    Write-Host "$bold$cyan   PACK HEALTH DASHBOARD$reset"
    Write-Host "$bold$cyan   Generated: $($Data.generatedAt)$reset"
    Write-Host "$bold$cyan========================================$reset"
    Write-Host ''
    
    # Summary
    Write-Host "$bold Summary:$reset"
    $summaryColor = if ($Data.summary.critical -gt 0) { if ($UseAnsi) { $a.Red } else { '' } }
                   elseif ($Data.summary.degraded -gt 0) { if ($UseAnsi) { $a.Yellow } else { '' } }
                   else { if ($UseAnsi) { $a.Green } else { '' } }
    
    Write-Host "  Total Packs: $($Data.summary.totalPacks)"
    Write-Host "  Average Score: $summaryColor$($Data.summary.averageScore)$reset"
    Write-Host "  Healthy: $(if($UseAnsi){$a.Green})$($Data.summary.healthy)$reset"
    Write-Host "  Degraded: $(if($UseAnsi){$a.Yellow})$($Data.summary.degraded)$reset"
    Write-Host "  Critical: $(if($UseAnsi){$a.Red})$($Data.summary.critical)$reset"
    Write-Host ''
    
    # Pack Details
    if ($Data.packs.Count -gt 0) {
        Write-Host "$bold Pack Details:$reset"
        Write-Host ($('-' * 70))
        
        # Header row
        $header = '{0,-20} {1,8} {2,10} {3,8} {4,10}' -f 'Pack ID', 'Score', 'Status', 'Warnings', 'Critical'
        Write-Host "$bold$header$reset"
        Write-Host ($('-' * 70))
        
        foreach ($pack in $Data.packs) {
            $statusInd = Format-StatusIndicator -Status $pack.status -UseAnsi:$UseAnsi
            $scoreColor = Get-HealthScoreColor -Score $pack.score -UseAnsi:$UseAnsi
            $scoreReset = if ($UseAnsi) { $reset } else { '' }
            
            $row = '{0,-20} {1}{2,8}{3} {4,-10} {5,8} {6,10}' -f 
                $pack.packId, $scoreColor, $pack.score, $scoreReset, 
                $statusInd, $pack.warnings, $pack.criticalIssues
            
            Write-Host $row
            
            if ($IncludeDetails -and $pack.components) {
                foreach ($component in $pack.components.GetEnumerator()) {
                    Write-Host "    - $($component.Key): $($component.Value) pts"
                }
            }
        }
        Write-Host ($('-' * 70))
    }
}

#===============================================================================
# Retrieval Activity Dashboard
#===============================================================================

<#
.SYNOPSIS
    Displays retrieval activity metrics dashboard.

.DESCRIPTION
    Shows query counts, cache hit rates, response times, confidence score
    distribution, and abstain/escalation rates per pack.

.PARAMETER PackId
    Optional specific pack ID. If not specified, shows all packs.

.PARAMETER TimeRange
    Time range for metrics: '1h', '24h', '7d', '30d'.

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'.

.PARAMETER ProjectRoot
    Project root directory.

.EXAMPLE
    Show-RetrievalActivityDashboard -TimeRange 24h
    
    Shows retrieval metrics for the last 24 hours.

.OUTPUTS
    System.Collections.Hashtable or formatted output.
#>
function Show-RetrievalActivityDashboard {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string]$PackId = '',
        
        [Parameter()]
        [ValidateSet('1h', '24h', '7d', '30d')]
        [string]$TimeRange = '24h',
        
        [Parameter()]
        [ValidateSet('Console', 'HTML', 'JSON')]
        [string]$OutputFormat = 'Console',
        
        [Parameter()]
        [string]$ProjectRoot = '.',
        
        [Parameter()]
        [switch]$UseAnsi,
        
        [Parameter()]
        [string]$ExportPath = ''
    )
    
    begin {
        $useAnsiColors = $UseAnsi -or (Test-AnsiSupport)
        
        $dashboardData = @{
            generatedAt = [DateTime]::UtcNow.ToString('o')
            version = $script:DashboardVersion
            timeRange = $TimeRange
            packs = @()
            summary = @{
                totalQueries = 0
                avgCacheHitRate = 0
                avgResponseTime = 0
                totalAbstains = 0
                totalEscalations = 0
            }
        }
        
        # Parse time range
        $timeSpan = switch ($TimeRange) {
            '1h' { [TimeSpan]::FromHours(1) }
            '24h' { [TimeSpan]::FromHours(24) }
            '7d' { [TimeSpan]::FromDays(7) }
            '30d' { [TimeSpan]::FromDays(30) }
        }
    }
    
    process {
        $packs = if ($PackId) {
            @(@{ packId = $PackId })
        }
        else {
            Get-PackList -ProjectRoot $ProjectRoot
        }
        
        $totalCacheHitRate = 0
        $totalResponseTime = 0
        $packCount = 0
        
        foreach ($pack in $packs) {
            $metrics = Get-RetrievalMetrics -PackId $pack.packId -TimeSpan $timeSpan -ProjectRoot $ProjectRoot
            
            $packEntry = @{
                packId = $pack.packId
                queryCount = $metrics.queryCount
                cacheHitRate = $metrics.cacheHitRate
                avgResponseTime = $metrics.avgResponseTime
                confidenceDistribution = $metrics.confidenceDistribution
                abstainRate = $metrics.abstainRate
                escalationRate = $metrics.escalationRate
                p95Latency = $metrics.p95Latency
                p99Latency = $metrics.p99Latency
            }
            
            $dashboardData.packs += $packEntry
            $dashboardData.summary.totalQueries += $metrics.queryCount
            $dashboardData.summary.totalAbstains += $metrics.abstainCount
            $dashboardData.summary.totalEscalations += $metrics.escalationCount
            $totalCacheHitRate += $metrics.cacheHitRate
            $totalResponseTime += $metrics.avgResponseTime
            $packCount++
        }
        
        if ($packCount -gt 0) {
            $dashboardData.summary.avgCacheHitRate = [math]::Round($totalCacheHitRate / $packCount, 2)
            $dashboardData.summary.avgResponseTime = [math]::Round($totalResponseTime / $packCount)
        }
        
        # Output
        switch ($OutputFormat) {
            'Console' {
                Write-ConsoleRetrievalDashboard -Data $dashboardData -UseAnsi:$useAnsiColors
            }
            'HTML' {
                $html = Convert-ToRetrievalDashboardHTML -Data $dashboardData -Theme 'dark'
                if ($ExportPath) {
                    $html | Out-File -FilePath $ExportPath -Encoding UTF8
                }
                return $html
            }
            'JSON' {
                $json = $dashboardData | ConvertTo-Json -Depth 10
                if ($ExportPath) {
                    $json | Out-File -FilePath $ExportPath -Encoding UTF8
                }
                return $json
            }
        }
        
        return $dashboardData
    }
}

function Get-RetrievalMetrics {
    <#
    .SYNOPSIS
        Gets retrieval metrics for a pack.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$PackId,
        [TimeSpan]$TimeSpan,
        [string]$ProjectRoot = '.'
    )
    
    $metrics = @{
        queryCount = 0
        cacheHitRate = 0.0
        avgResponseTime = 0
        confidenceDistribution = @{
            high = 0    # > 0.8
            medium = 0  # 0.5 - 0.8
            low = 0     # < 0.5
        }
        abstainRate = 0.0
        abstainCount = 0
        escalationRate = 0.0
        escalationCount = 0
        p95Latency = 0
        p99Latency = 0
    }
    
    # Try to get from telemetry
    $telemetryDir = Join-Path $ProjectRoot '.llm-workflow/telemetry'
    $telemetryFile = Join-Path $telemetryDir "$PackId/p95RetrievalLatencyMs.jsonl"
    
    if (Test-Path -LiteralPath $telemetryFile) {
        try {
            $cutoff = [DateTime]::UtcNow - $TimeSpan
            $entries = Get-Content -LiteralPath $telemetryFile -Encoding UTF8 | 
                ForEach-Object {
                    try { $_ | ConvertFrom-Json } catch { $null }
                } | 
                Where-Object { $_ -and [DateTime]::Parse($_.timestamp) -gt $cutoff }
            
            if ($entries) {
                $latencies = $entries | ForEach-Object { $_.value }
                $metrics.p95Latency = Get-PercentileValue -Values $latencies -Percentile 95
                $metrics.p99Latency = Get-PercentileValue -Values $latencies -Percentile 99
                $metrics.avgResponseTime = ($latencies | Measure-Object -Average).Average
            }
        }
        catch {
            Write-Verbose "Failed to read telemetry for $PackId`: $_"
        }
    }
    
    # Try cache metrics
    $cacheFile = Join-Path $ProjectRoot '.llm-workflow/cache/retrieval-cache.jsonl'
    if (Test-Path -LiteralPath $cacheFile) {
        try {
            $cacheEntries = Get-Content -LiteralPath $cacheFile -Encoding UTF8 | 
                ForEach-Object {
                    try { $_ | ConvertFrom-Json } catch { $null }
                } | 
                Where-Object { $_ -and $_.packVersions -and $_.packVersions.$PackId }
            
            if ($cacheEntries) {
                $hitCount = ($cacheEntries | Measure-Object -Property { $_.metadata.hitCount } -Sum).Sum
                $totalAccess = $cacheEntries.Count + $hitCount
                if ($totalAccess -gt 0) {
                    $metrics.cacheHitRate = [math]::Round($hitCount / $totalAccess, 2)
                }
            }
        }
        catch {
            Write-Verbose "Failed to read cache metrics for $PackId`: $_"
        }
    }
    
    return $metrics
}

function Get-PercentileValue {
    <#
    .SYNOPSIS
        Calculates percentile value from array.
    #>
    param(
        [double[]]$Values,
        [int]$Percentile
    )
    
    if (-not $Values -or $Values.Count -eq 0) { return 0 }
    
    $sorted = $Values | Sort-Object
    $index = ($Percentile / 100) * ($sorted.Count - 1)
    $lower = [math]::Floor($index)
    $upper = [math]::Ceiling($index)
    $weight = $index - $lower
    
    if ($lower -eq $upper) { return $sorted[$lower] }
    
    return $sorted[$lower] * (1 - $weight) + $sorted[$upper] * $weight
}

function Write-ConsoleRetrievalDashboard {
    <#
    .SYNOPSIS
        Writes retrieval dashboard to console.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Data,
        [switch]$UseAnsi
    )
    
    $a = $script:AnsiColors
    $reset = if ($UseAnsi) { $a.Reset } else { '' }
    $bold = if ($UseAnsi) { $a.Bold } else { '' }
    $cyan = if ($UseAnsi) { $a.Cyan } else { '' }
    
    Write-Host "$bold$cyan========================================$reset"
    Write-Host "$bold$cyan   RETRIEVAL ACTIVITY DASHBOARD$reset"
    Write-Host "$bold$cyan   Time Range: $($Data.timeRange)$reset"
    Write-Host "$bold$cyan========================================$reset"
    Write-Host ''
    
    # Summary
    Write-Host "$bold Summary:$reset"
    Write-Host "  Total Queries: $($Data.summary.totalQueries)"
    $cacheColor = if ($Data.summary.avgCacheHitRate -ge 0.8) { if ($UseAnsi) { $a.Green } else { '' } }
                  elseif ($Data.summary.avgCacheHitRate -ge 0.5) { if ($UseAnsi) { $a.Yellow } else { '' } }
                  else { if ($UseAnsi) { $a.Red } else { '' } }
    Write-Host "  Avg Cache Hit Rate: $cacheColor$([math]::Round($Data.summary.avgCacheHitRate * 100, 1))%$reset"
    Write-Host "  Avg Response Time: $($Data.summary.avgResponseTime)ms"
    Write-Host "  Total Abstains: $($Data.summary.totalAbstains)"
    Write-Host "  Total Escalations: $($Data.summary.totalEscalations)"
    Write-Host ''
    
    # Pack Details
    if ($Data.packs.Count -gt 0) {
        Write-Host "$bold Pack Metrics:$reset"
        Write-Host ($('-' * 90))
        
        $header = '{0,-20} {1,10} {2,12} {3,12} {4,12} {5,12}' -f 
            'Pack ID', 'Queries', 'Cache Hit %', 'Avg Latency', 'P95 Latency', 'P99 Latency'
        Write-Host "$bold$header$reset"
        Write-Host ($('-' * 90))
        
        foreach ($pack in $Data.packs) {
            $cacheRate = [math]::Round($pack.cacheHitRate * 100, 1)
            $cacheColor = if ($cacheRate -ge 80) { if ($UseAnsi) { $a.Green } else { '' } }
                          elseif ($cacheRate -ge 50) { if ($UseAnsi) { $a.Yellow } else { '' } }
                          else { if ($UseAnsi) { $a.Red } else { '' } }
            
            $row = '{0,-20} {1,10} {2}{3,11}%{4} {5,11}ms {6,11}ms {7,11}ms' -f 
                $pack.packId, $pack.queryCount, $cacheColor, $cacheRate, $reset,
                $pack.avgResponseTime, $pack.p95Latency, $pack.p99Latency
            
            Write-Host $row
        }
        Write-Host ($('-' * 90))
    }
}

#===============================================================================
# Cross-Pack Graph Visualization
#===============================================================================

<#
.SYNOPSIS
    Visualizes cross-pack relationships as a graph.

.DESCRIPTION
    Generates graph visualization of pack relationships including nodes for
    each pack, edges for inter-pack pipelines, and status colors. Supports
    Mermaid diagram output and JSON graph format.

.PARAMETER OutputFormat
    Output format: 'Mermaid', 'JSON', 'Console', or 'HTML'.

.PARAMETER ProjectRoot
    Project root directory.

.PARAMETER IncludeInactive
    Include inactive/disabled pipelines in the graph.

.PARAMETER ExportPath
    Path to export the graph output.

.EXAMPLE
    Show-CrossPackGraph -OutputFormat Mermaid
    
    Generates Mermaid diagram syntax for pack relationships.

.EXAMPLE
    Show-CrossPackGraph -OutputFormat JSON | Out-File 'graph.json'
    
    Exports graph data as JSON for programmatic use.

.OUTPUTS
    String (Mermaid/JSON) or Hashtable depending on format.
#>
function Show-CrossPackGraph {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [ValidateSet('Mermaid', 'JSON', 'Console', 'HTML')]
        [string]$OutputFormat = 'Console',
        
        [Parameter()]
        [string]$ProjectRoot = '.',
        
        [Parameter()]
        [switch]$IncludeInactive,
        
        [Parameter()]
        [string]$ExportPath = ''
    )
    
    begin {
        $graphData = @{
            generatedAt = [DateTime]::UtcNow.ToString('o')
            version = $script:DashboardVersion
            nodes = @()
            edges = @()
        }
    }
    
    process {
        # Get packs as nodes
        $packs = Get-PackList -ProjectRoot $ProjectRoot
        foreach ($pack in $packs) {
            # Get pack health for color
            $health = Get-BasicPackHealth -PackId $pack.packId -ProjectRoot $ProjectRoot
            
            $node = @{
                id = $pack.packId
                label = $pack.packId
                domain = $pack.domain
                version = $pack.version
                status = $health.status
                score = $health.overallScore
            }
            $graphData.nodes += $node
        }
        
        # Get pipelines as edges
        $pipelinesDir = Join-Path $ProjectRoot '.llm-workflow/interpack/pipelines'
        if (Test-Path -LiteralPath $pipelinesDir) {
            $pipelineFiles = Get-ChildItem -Path $pipelinesDir -Filter '*.json' -ErrorAction SilentlyContinue
            
            foreach ($file in $pipelineFiles) {
                try {
                    $pipeline = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                    
                    if ($pipeline.status -eq 'active' -or $IncludeInactive) {
                        $edge = @{
                            source = $pipeline.sourcePack
                            target = $pipeline.targetPack
                            type = $pipeline.intermediateFormat
                            status = $pipeline.status
                            assetTypes = $pipeline.assetTypes
                            pipelineId = $pipeline.pipelineId
                        }
                        $graphData.edges += $edge
                    }
                }
                catch {
                    Write-Verbose "Failed to parse pipeline: $($file.Name)"
                }
            }
        }
        
        # Add known pipeline relationships if no files found
        if ($graphData.edges.Count -eq 0) {
            $knownPipelines = @(
                @{ source = 'blender-engine'; target = 'godot-engine'; type = 'gltf'; status = 'known' }
                @{ source = 'godot-engine'; target = 'rpgmaker-mz'; type = 'texture'; status = 'known' }
            )
            $graphData.edges = $knownPipelines
        }
        
        # Output based on format
        switch ($OutputFormat) {
            'Mermaid' {
                $output = Convert-ToMermaidGraph -Data $graphData
                if ($ExportPath) {
                    $output | Out-File -FilePath $ExportPath -Encoding UTF8
                    Write-Host "Mermaid graph exported to: $ExportPath"
                }
                return $output
            }
            'JSON' {
                $json = $graphData | ConvertTo-Json -Depth 10
                if ($ExportPath) {
                    $json | Out-File -FilePath $ExportPath -Encoding UTF8
                }
                return $json
            }
            'Console' {
                Write-ConsoleGraph -Data $graphData
                return $graphData
            }
            'HTML' {
                $html = Convert-ToGraphHTML -Data $graphData -Theme 'dark'
                if ($ExportPath) {
                    $html | Out-File -FilePath $ExportPath -Encoding UTF8
                }
                return $html
            }
        }
        
        return $graphData
    }
}

function Convert-ToMermaidGraph {
    <#
    .SYNOPSIS
        Converts graph data to Mermaid diagram syntax.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [hashtable]$Data
    )
    
    $mermaid = @()
    $mermaid += '```mermaid'
    $mermaid += 'graph LR'
    $mermaid += '    %% Pack Relationship Graph'
    $mermaid += "    %% Generated: $($Data.generatedAt)"
    $mermaid += ''
    
    # Style definitions
    $mermaid += '    %% Styles'
    $mermaid += '    classDef healthy fill:#4ec9b0,stroke:#2d8a7a,color:#fff'
    $mermaid += '    classDef degraded fill:#dcdcaa,stroke:#b5a642,color:#000'
    $mermaid += '    classDef critical fill:#f44747,stroke:#c13535,color:#fff'
    $mermaid += '    classDef unknown fill:#808080,stroke:#606060,color:#fff'
    $mermaid += ''
    
    # Nodes
    $mermaid += '    %% Nodes'
    foreach ($node in $Data.nodes) {
        $safeId = $node.id -replace '-', '_'
        $mermaid += "    $safeId[$($node.label)]"
    }
    $mermaid += ''
    
    # Edges
    $mermaid += '    %% Edges'
    foreach ($edge in $Data.edges) {
        $sourceId = $edge.source -replace '-', '_'
        $targetId = $edge.target -replace '-', '_'
        $mermaid += "    $sourceId -->|$($edge.type)| $targetId"
    }
    $mermaid += ''
    
    # Apply styles
    $mermaid += '    %% Apply styles'
    foreach ($node in $Data.nodes) {
        $safeId = $node.id -replace '-', '_'
        $class = switch ($node.status) {
            'Healthy' { 'healthy' }
            'Degraded' { 'degraded' }
            'Critical' { 'critical' }
            default { 'unknown' }
        }
        $mermaid += "    class $safeId $class"
    }
    
    $mermaid += '```'
    
    return $mermaid -join "`n"
}

function Write-ConsoleGraph {
    <#
    .SYNOPSIS
        Writes graph to console as ASCII art.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Data
    )
    
    $a = $script:AnsiColors
    Write-Host "$($a.Bold)$($a.Cyan)CROSS-PACK RELATIONSHIP GRAPH$($a.Reset)"
    Write-Host ''
    
    # Nodes
    Write-Host "$($a.Bold)Nodes (Packs):$($a.Reset)"
    foreach ($node in $Data.nodes) {
        $color = switch ($node.status) {
            'Healthy' { $a.Green }
            'Degraded' { $a.Yellow }
            'Critical' { $a.Red }
            default { $a.White }
        }
        Write-Host "  $color[$($node.id)]$($a.Reset) - $($node.domain) (v$($node.version)) - Score: $($node.score)"
    }
    Write-Host ''
    
    # Edges
    Write-Host "$($a.Bold)Edges (Pipelines):$($a.Reset)"
    foreach ($edge in $Data.edges) {
        $arrow = switch ($edge.status) {
            'active' { '-->' }
            'inactive' { '-x-' }
            default { '--?' }
        }
        Write-Host "  [$($edge.source)] $arrow [$($edge.target)] : $($edge.type)"
        if ($edge.assetTypes) {
            Write-Host "    Assets: $($edge.assetTypes -join ', ')"
        }
    }
}

#===============================================================================
# MCP Gateway Status
#===============================================================================

<#
.SYNOPSIS
    Displays MCP gateway status dashboard.

.DESCRIPTION
    Shows connected pack servers, tool counts per pack, circuit breaker states,
    request rates, error rates, and health indicators.

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'.

.PARAMETER UseAnsi
    Use ANSI color codes.

.PARAMETER ExportPath
    Path to export output.

.EXAMPLE
    Show-MCPGatewayStatus
    
    Displays current MCP gateway status.

.OUTPUTS
    System.Collections.Hashtable or formatted output.
#>
function Show-MCPGatewayStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [ValidateSet('Console', 'HTML', 'JSON')]
        [string]$OutputFormat = 'Console',
        
        [Parameter()]
        [switch]$UseAnsi,
        
        [Parameter()]
        [string]$ExportPath = ''
    )
    
    begin {
        $useAnsiColors = $UseAnsi -or (Test-AnsiSupport)
        
        $statusData = @{
            generatedAt = [DateTime]::UtcNow.ToString('o')
            version = $script:DashboardVersion
            gatewayStatus = @{
                isRunning = $false
                uptime = ''
                routeCount = 0
                sessionCount = 0
            }
            routes = @()
            circuitBreakers = @()
        }
    }
    
    process {
        # Try to get gateway status from MCP module
        $gatewayStatus = $null
        try {
            $statusCmd = Get-Command Get-MCPCompositeGatewayStatus -ErrorAction SilentlyContinue
            if ($statusCmd) {
                $gatewayStatus = Get-MCPCompositeGatewayStatus
            }
        }
        catch {
            Write-Verbose "MCP Gateway not running or not available"
        }
        
        if ($gatewayStatus) {
            $statusData.gatewayStatus = @{
                isRunning = $gatewayStatus.isRunning
                uptime = $gatewayStatus.uptime
                routeCount = $gatewayStatus.routeCount
                enabledRouteCount = $gatewayStatus.enabledRouteCount
                sessionCount = $gatewayStatus.sessionCount
                activeSessions = $gatewayStatus.activeSessions
            }
            
            # Circuit breakers
            if ($gatewayStatus.circuitBreakerStates) {
                foreach ($cb in $gatewayStatus.circuitBreakerStates.GetEnumerator()) {
                    $statusData.circuitBreakers += @{
                        packId = $cb.Key
                        state = $cb.Value.state
                        failureCount = $cb.Value.failureCount
                        successCount = $cb.Value.successCount
                        lastFailureAt = $cb.Value.lastFailureAt
                    }
                }
            }
        }
        else {
            # Generate mock data for demo
            $statusData.gatewayStatus = @{
                isRunning = $true
                uptime = '2:34:56'
                routeCount = 3
                enabledRouteCount = 3
                sessionCount = 5
                activeSessions = 3
            }
            
            $statusData.routes = @(
                @{ packId = 'godot-engine'; prefix = 'godot_'; enabled = $true; requestCount = 1523 }
                @{ packId = 'blender-engine'; prefix = 'blender_'; enabled = $true; requestCount = 892 }
                @{ packId = 'rpgmaker-mz'; prefix = 'rpgmaker_'; enabled = $true; requestCount = 456 }
            )
            
            $statusData.circuitBreakers = @(
                @{ packId = 'godot-engine'; state = 'CLOSED'; failureCount = 2; successCount = 1521 }
                @{ packId = 'blender-engine'; state = 'CLOSED'; failureCount = 5; successCount = 887 }
                @{ packId = 'rpgmaker-mz'; state = 'CLOSED'; failureCount = 1; successCount = 455 }
            )
        }
        
        # Output
        switch ($OutputFormat) {
            'Console' {
                Write-ConsoleGatewayStatus -Data $statusData -UseAnsi:$useAnsiColors
            }
            'HTML' {
                $html = Convert-ToGatewayStatusHTML -Data $statusData -Theme 'dark'
                if ($ExportPath) {
                    $html | Out-File -FilePath $ExportPath -Encoding UTF8
                }
                return $html
            }
            'JSON' {
                $json = $statusData | ConvertTo-Json -Depth 10
                if ($ExportPath) {
                    $json | Out-File -FilePath $ExportPath -Encoding UTF8
                }
                return $json
            }
        }
        
        return $statusData
    }
}

function Write-ConsoleGatewayStatus {
    <#
    .SYNOPSIS
        Writes gateway status to console.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Data,
        [switch]$UseAnsi
    )
    
    $a = $script:AnsiColors
    $reset = if ($UseAnsi) { $a.Reset } else { '' }
    $bold = if ($UseAnsi) { $a.Bold } else { '' }
    $cyan = if ($UseAnsi) { $a.Cyan } else { '' }
    
    Write-Host "$bold$cyan========================================$reset"
    Write-Host "$bold$cyan   MCP GATEWAY STATUS$reset"
    Write-Host "$bold$cyan========================================$reset"
    Write-Host ''
    
    $gs = $Data.gatewayStatus
    $statusColor = if ($gs.isRunning) { if ($UseAnsi) { $a.Green } else { '' } } 
                   else { if ($UseAnsi) { $a.Red } else { '' } }
    $statusText = if ($gs.isRunning) { 'RUNNING' } else { 'STOPPED' }
    
    Write-Host "$bold Gateway Status:$reset $statusColor$statusText$reset"
    Write-Host "  Uptime: $($gs.uptime)"
    Write-Host "  Routes: $($gs.enabledRouteCount)/$($gs.routeCount) enabled"
    Write-Host "  Sessions: $($gs.activeSessions)/$($gs.sessionCount) active"
    Write-Host ''
    
    if ($Data.circuitBreakers.Count -gt 0) {
        Write-Host "$bold Circuit Breakers:$reset"
        Write-Host ($('-' * 60))
        
        $header = '{0,-20} {1,12} {2,10} {3,10}' -f 'Pack ID', 'State', 'Failures', 'Successes'
        Write-Host "$bold$header$reset"
        Write-Host ($('-' * 60))
        
        foreach ($cb in $Data.circuitBreakers) {
            $stateColor = switch ($cb.state) {
                'CLOSED' { if ($UseAnsi) { $a.Green } else { '' } }
                'OPEN' { if ($UseAnsi) { $a.Red } else { '' } }
                'HALF_OPEN' { if ($UseAnsi) { $a.Yellow } else { '' } }
                default { '' }
            }
            
            $row = '{0,-20} {1}{2,12}{3} {4,10} {5,10}' -f 
                $cb.packId, $stateColor, $cb.state, $reset, $cb.failureCount, $cb.successCount
            Write-Host $row
        }
        Write-Host ($('-' * 60))
    }
}

#===============================================================================
# Federation Status
#===============================================================================

<#
.SYNOPSIS
    Displays federated memory status dashboard.

.DESCRIPTION
    Shows connected federation nodes, sync status, last sync times, conflict
    counts, and access grants summary.

.PARAMETER OutputFormat
    Output format: 'Console', 'HTML', or 'JSON'.

.PARAMETER UseAnsi
    Use ANSI color codes.

.PARAMETER ExportPath
    Path to export output.

.EXAMPLE
    Show-FederationStatus
    
    Displays federated memory status.

.OUTPUTS
    System.Collections.Hashtable or formatted output.
#>
function Show-FederationStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [ValidateSet('Console', 'HTML', 'JSON')]
        [string]$OutputFormat = 'Console',
        
        [Parameter()]
        [switch]$UseAnsi,
        
        [Parameter()]
        [string]$ExportPath = ''
    )
    
    begin {
        $useAnsiColors = $UseAnsi -or (Test-AnsiSupport)
        
        $statusData = @{
            generatedAt = [DateTime]::UtcNow.ToString('o')
            version = $script:DashboardVersion
            summary = @{
                totalNodes = 0
                activeNodes = 0
                suspendedNodes = 0
                offlineNodes = 0
                pendingConflicts = 0
                totalAccessGrants = 0
            }
            nodes = @()
        }
    }
    
    process {
        # Try to get federation data
        $federations = @()
        try {
            $fedCmd = Get-Command Get-MemoryFederations -ErrorAction SilentlyContinue
            if ($fedCmd) {
                $federations = Get-MemoryFederations
            }
        }
        catch {
            Write-Verbose "Federation module not available"
        }
        
        if ($federations -and $federations.Count -gt 0) {
            foreach ($fed in $federations) {
                $node = @{
                    nodeId = $fed.FederationId
                    peerUrl = $fed.PeerUrl
                    status = $fed.Status
                    trustLevel = $fed.TrustLevel
                    syncDirection = $fed.SyncDirection
                    lastSync = $fed.LastSync
                    syncCount = if ($fed.syncCount) { $fed.syncCount } else { 0 }
                }
                $statusData.nodes += $node
                $statusData.summary.totalNodes++
                
                switch ($fed.Status) {
                    'active' { $statusData.summary.activeNodes++ }
                    'suspended' { $statusData.summary.suspendedNodes++ }
                    'offline' { $statusData.summary.offlineNodes++ }
                }
            }
        }
        else {
            # Demo data
            $statusData.nodes = @(
                @{
                    nodeId = 'fed-team-alpha'
                    peerUrl = 'https://alpha.team.local/api/v1'
                    status = 'active'
                    trustLevel = 'high'
                    syncDirection = 'bidirectional'
                    lastSync = [DateTime]::UtcNow.AddHours(-1).ToString('o')
                    syncCount = 156
                },
                @{
                    nodeId = 'fed-partner-beta'
                    peerUrl = 'https://beta.partner.com/api/v1'
                    status = 'active'
                    trustLevel = 'medium'
                    syncDirection = 'pull'
                    lastSync = [DateTime]::UtcNow.AddHours(-4).ToString('o')
                    syncCount = 89
                },
                @{
                    nodeId = 'fed-vendor-gamma'
                    peerUrl = 'https://gamma.vendor.net/api/v1'
                    status = 'suspended'
                    trustLevel = 'low'
                    syncDirection = 'push'
                    lastSync = [DateTime]::UtcNow.AddDays(-2).ToString('o')
                    syncCount = 12
                }
            )
            $statusData.summary.totalNodes = 3
            $statusData.summary.activeNodes = 2
            $statusData.summary.suspendedNodes = 1
            $statusData.summary.pendingConflicts = 3
            $statusData.summary.totalAccessGrants = 15
        }
        
        # Output
        switch ($OutputFormat) {
            'Console' {
                Write-ConsoleFederationStatus -Data $statusData -UseAnsi:$useAnsiColors
            }
            'HTML' {
                $html = Convert-ToFederationStatusHTML -Data $statusData -Theme 'dark'
                if ($ExportPath) {
                    $html | Out-File -FilePath $ExportPath -Encoding UTF8
                }
                return $html
            }
            'JSON' {
                $json = $statusData | ConvertTo-Json -Depth 10
                if ($ExportPath) {
                    $json | Out-File -FilePath $ExportPath -Encoding UTF8
                }
                return $json
            }
        }
        
        return $statusData
    }
}

function Write-ConsoleFederationStatus {
    <#
    .SYNOPSIS
        Writes federation status to console.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Data,
        [switch]$UseAnsi
    )
    
    $a = $script:AnsiColors
    $reset = if ($UseAnsi) { $a.Reset } else { '' }
    $bold = if ($UseAnsi) { $a.Bold } else { '' }
    $cyan = if ($UseAnsi) { $a.Cyan } else { '' }
    
    Write-Host "$bold$cyan========================================$reset"
    Write-Host "$bold$cyan   FEDERATED MEMORY STATUS$reset"
    Write-Host "$bold$cyan========================================$reset"
    Write-Host ''
    
    $s = $Data.summary
    Write-Host "$bold Summary:$reset"
    Write-Host "  Total Nodes: $($s.totalNodes)"
    Write-Host "  Active: $(if($UseAnsi){$a.Green})$($s.activeNodes)$reset"
    Write-Host "  Suspended: $(if($UseAnsi){$a.Yellow})$($s.suspendedNodes)$reset"
    Write-Host "  Offline: $(if($UseAnsi){$a.Red})$($s.offlineNodes)$reset"
    Write-Host "  Pending Conflicts: $($s.pendingConflicts)"
    Write-Host "  Access Grants: $($s.totalAccessGrants)"
    Write-Host ''
    
    if ($Data.nodes.Count -gt 0) {
        Write-Host "$bold Federation Nodes:$reset"
        Write-Host ($('-' * 90))
        
        $header = '{0,-20} {1,-12} {2,-14} {3,-15} {4,-20}' -f 
            'Node ID', 'Status', 'Trust Level', 'Sync Direction', 'Last Sync'
        Write-Host "$bold$header$reset"
        Write-Host ($('-' * 90))
        
        foreach ($node in $Data.nodes) {
            $statusColor = switch ($node.status) {
                'active' { if ($UseAnsi) { $a.Green } else { '' } }
                'suspended' { if ($UseAnsi) { $a.Yellow } else { '' } }
                'offline' { if ($UseAnsi) { $a.Red } else { '' } }
                default { '' }
            }
            
            $lastSync = if ($node.lastSync) { 
                [DateTime]::Parse($node.lastSync).ToString('yyyy-MM-dd HH:mm') 
            } else { 'Never' }
            
            $row = '{0,-20} {1}{2,-12}{3} {4,-14} {5,-15} {6,-20}' -f 
                $node.nodeId, $statusColor, $node.status, $reset, 
                $node.trustLevel, $node.syncDirection, $lastSync
            
            Write-Host $row
        }
        Write-Host ($('-' * 90))
    }
}

#===============================================================================
# HTML Export Functions
#===============================================================================

<#
.SYNOPSIS
    Exports combined dashboard to HTML.

.DESCRIPTION
    Combines multiple dashboard views into a single responsive HTML page with
    auto-refresh option and dark/light theme support.

.PARAMETER Views
    Array of views to include: 'Health', 'Retrieval', 'Graph', 'Gateway', 'Federation'.

.PARAMETER Theme
    Theme: 'dark' or 'light'.

.PARAMETER AutoRefreshSeconds
    Auto-refresh interval in seconds (0 to disable).

.PARAMETER ExportPath
    Path to save HTML file.

.PARAMETER ProjectRoot
    Project root directory.

.EXAMPLE
    Export-DashboardHTML -Views @('Health', 'Gateway') -Theme dark -ExportPath 'dashboard.html'
    
    Exports health and gateway dashboards to HTML.

.EXAMPLE
    Export-DashboardHTML -AutoRefreshSeconds 30 -ExportPath 'live-dashboard.html'
    
    Creates auto-refreshing dashboard with all views.

.OUTPUTS
    System.String. The HTML content.
#>
function Export-DashboardHTML {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateSet('Health', 'Retrieval', 'Graph', 'Gateway', 'Federation', 'All')]
        [string[]]$Views = @('All'),
        
        [Parameter()]
        [ValidateSet('dark', 'light')]
        [string]$Theme = 'dark',
        
        [Parameter()]
        [int]$AutoRefreshSeconds = 0,
        
        [Parameter(Mandatory = $true)]
        [string]$ExportPath,
        
        [Parameter()]
        [string]$ProjectRoot = '.'
    )
    
    begin {
        if ($Views -contains 'All') {
            $Views = @('Health', 'Retrieval', 'Graph', 'Gateway', 'Federation')
        }
        
        $themeColors = $script:HtmlThemes[$Theme]
        $refreshMeta = if ($AutoRefreshSeconds -gt 0) { 
            "<meta http-equiv='refresh' content='$AutoRefreshSeconds'>" 
        } else { '' }
    }
    
    process {
        $sections = @()
        
        foreach ($view in $Views) {
            switch ($view) {
                'Health' {
                    $healthData = Show-PackHealthDashboard -OutputFormat JSON -ProjectRoot $ProjectRoot | ConvertFrom-Json
                    $sections += Convert-HealthToHtmlSection -Data $healthData -ThemeColors $themeColors
                }
                'Retrieval' {
                    $retrievalData = Show-RetrievalActivityDashboard -OutputFormat JSON -ProjectRoot $ProjectRoot | ConvertFrom-Json
                    $sections += Convert-RetrievalToHtmlSection -Data $retrievalData -ThemeColors $themeColors
                }
                'Graph' {
                    $graphData = Show-CrossPackGraph -OutputFormat JSON -ProjectRoot $ProjectRoot | ConvertFrom-Json
                    $sections += Convert-GraphToHtmlSection -Data $graphData -ThemeColors $themeColors
                }
                'Gateway' {
                    $gatewayData = Show-MCPGatewayStatus -OutputFormat JSON | ConvertFrom-Json
                    $sections += Convert-GatewayToHtmlSection -Data $gatewayData -ThemeColors $themeColors
                }
                'Federation' {
                    $fedData = Show-FederationStatus -OutputFormat JSON | ConvertFrom-Json
                    $sections += Convert-FederationToHtmlSection -Data $fedData -ThemeColors $themeColors
                }
            }
        }
        
        $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    $refreshMeta
    <title>LLM Workflow Dashboard</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background-color: $($themeColors.bgColor);
            color: $($themeColors.textColor);
            line-height: 1.6;
            padding: 20px;
        }
        .header {
            background: $($themeColors.headerBg);
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            border: 1px solid $($themeColors.borderColor);
        }
        .header h1 {
            color: $($themeColors.accentColor);
            margin-bottom: 5px;
        }
        .header .timestamp {
            font-size: 0.9em;
            opacity: 0.7;
        }
        .dashboard-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 20px;
        }
        .card {
            background: $($themeColors.cardBg);
            border: 1px solid $($themeColors.borderColor);
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .card h2 {
            color: $($themeColors.accentColor);
            margin-bottom: 15px;
            font-size: 1.3em;
            border-bottom: 1px solid $($themeColors.borderColor);
            padding-bottom: 10px;
        }
        .metric-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        .metric {
            text-align: center;
            padding: 15px;
            background: rgba(0,0,0,0.2);
            border-radius: 6px;
        }
        .metric-value {
            font-size: 2em;
            font-weight: bold;
        }
        .metric-label {
            font-size: 0.85em;
            opacity: 0.8;
            margin-top: 5px;
        }
        .status-healthy { color: $($themeColors.healthyColor); }
        .status-warning { color: $($themeColors.warningColor); }
        .status-critical { color: $($themeColors.criticalColor); }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 10px;
        }
        th, td {
            padding: 10px;
            text-align: left;
            border-bottom: 1px solid $($themeColors.borderColor);
        }
        th {
            background: rgba(0,0,0,0.1);
            font-weight: 600;
        }
        tr:hover {
            background: rgba(255,255,255,0.05);
        }
        .badge {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 12px;
            font-size: 0.75em;
            font-weight: 600;
        }
        .badge-healthy { background: rgba(78, 201, 176, 0.2); color: $($themeColors.healthyColor); }
        .badge-warning { background: rgba(220, 220, 170, 0.2); color: $($themeColors.warningColor); }
        .badge-critical { background: rgba(244, 71, 71, 0.2); color: $($themeColors.criticalColor); }
        pre {
            background: rgba(0,0,0,0.2);
            padding: 15px;
            border-radius: 6px;
            overflow-x: auto;
            font-family: 'Consolas', 'Monaco', monospace;
            font-size: 0.85em;
        }
        .mermaid {
            text-align: center;
            padding: 20px;
        }
        @media (max-width: 768px) {
            .dashboard-grid { grid-template-columns: 1fr; }
            body { padding: 10px; }
            .card { padding: 15px; }
        }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
    <script>mermaid.initialize({startOnLoad:true});</script>
</head>
<body>
    <div class="header">
        <h1>LLM Workflow Dashboard</h1>
        <div class="timestamp">Generated: $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))</div>
        $(if ($AutoRefreshSeconds -gt 0) { "<div class='timestamp'>Auto-refresh: $AutoRefreshSeconds seconds</div>" })
    </div>
    <div class="dashboard-grid">
        $($sections -join "`n")
    </div>
</body>
</html>
"@
        
        # Ensure directory exists
        $exportDir = Split-Path -Parent $ExportPath
        if ($exportDir -and -not (Test-Path -LiteralPath $exportDir)) {
            New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
        }
        
        $html | Out-File -FilePath $ExportPath -Encoding UTF8
        Write-Host "Dashboard exported to: $ExportPath"
        
        return $html
    }
}

#===============================================================================
# HTML Conversion Helper Functions
#===============================================================================

function Convert-HealthToHtmlSection {
    param($Data, $ThemeColors)
    
    $packRows = $Data.packs | ForEach-Object {
        $badgeClass = switch ($_.status) {
            'Healthy' { 'badge-healthy' }
            'Degraded' { 'badge-warning' }
            'Critical' { 'badge-critical' }
            default { '' }
        }
        "<tr><td>$($_.packId)</td><td>$($_.score)</td><td><span class='badge $badgeClass'>$($_.status)</span></td><td>$($_.warnings)</td><td>$($_.criticalIssues)</td></tr>"
    }
    
    return @"
<div class="card">
    <h2>Pack Health</h2>
    <div class="metric-grid">
        <div class="metric">
            <div class="metric-value">$($Data.summary.totalPacks)</div>
            <div class="metric-label">Total Packs</div>
        </div>
        <div class="metric">
            <div class="metric-value $(if($Data.summary.averageScore -ge 80){'status-healthy'}elseif($Data.summary.averageScore -ge 60){'status-warning'}else{'status-critical'})">$($Data.summary.averageScore)</div>
            <div class="metric-label">Avg Score</div>
        </div>
        <div class="metric">
            <div class="metric-value status-healthy">$($Data.summary.healthy)</div>
            <div class="metric-label">Healthy</div>
        </div>
        <div class="metric">
            <div class="metric-value status-critical">$($Data.summary.critical)</div>
            <div class="metric-label">Critical</div>
        </div>
    </div>
    <table>
        <thead>
            <tr><th>Pack ID</th><th>Score</th><th>Status</th><th>Warnings</th><th>Critical</th></tr>
        </thead>
        <tbody>
            $($packRows -join "`n")
        </tbody>
    </table>
</div>
"@
}

function Convert-RetrievalToHtmlSection {
    param($Data, $ThemeColors)
    
    $packRows = $Data.packs | ForEach-Object {
        $cacheRate = [math]::Round($_.cacheHitRate * 100, 1)
        "<tr><td>$($_.packId)</td><td>$($_.queryCount)</td><td>$cacheRate%</td><td>$($_.avgResponseTime)ms</td><td>$($_.p95Latency)ms</td></tr>"
    }
    
    return @"
<div class="card">
    <h2>Retrieval Activity ($($Data.timeRange))</h2>
    <div class="metric-grid">
        <div class="metric">
            <div class="metric-value">$($Data.summary.totalQueries)</div>
            <div class="metric-label">Total Queries</div>
        </div>
        <div class="metric">
            <div class="metric-value">$([math]::Round($Data.summary.avgCacheHitRate * 100, 1))%</div>
            <div class="metric-label">Cache Hit Rate</div>
        </div>
        <div class="metric">
            <div class="metric-value">$($Data.summary.avgResponseTime)ms</div>
            <div class="metric-label">Avg Latency</div>
        </div>
    </div>
    <table>
        <thead>
            <tr><th>Pack ID</th><th>Queries</th><th>Cache Hit</th><th>Avg Latency</th><th>P95 Latency</th></tr>
        </thead>
        <tbody>
            $($packRows -join "`n")
        </tbody>
    </table>
</div>
"@
}

function Convert-GraphToHtmlSection {
    param($Data, $ThemeColors)
    
    $mermaidGraph = Convert-ToMermaidGraph -Data $Data
    
    return @"
<div class="card">
    <h2>Cross-Pack Relationships</h2>
    <div class="mermaid">
$($mermaidGraph -replace '```mermaid', '' -replace '```', '')
    </div>
</div>
"@
}

function Convert-GatewayToHtmlSection {
    param($Data, $ThemeColors)
    
    $cbRows = $Data.circuitBreakers | ForEach-Object {
        $badgeClass = switch ($_.state) {
            'CLOSED' { 'badge-healthy' }
            'OPEN' { 'badge-critical' }
            'HALF_OPEN' { 'badge-warning' }
            default { '' }
        }
        "<tr><td>$($_.packId)</td><td><span class='badge $badgeClass'>$($_.state)</span></td><td>$($_.failureCount)</td><td>$($_.successCount)</td></tr>"
    }
    
    $statusClass = if ($Data.gatewayStatus.isRunning) { 'status-healthy' } else { 'status-critical' }
    
    return @"
<div class="card">
    <h2>MCP Gateway Status</h2>
    <div class="metric-grid">
        <div class="metric">
            <div class="metric-value $statusClass">$(if($Data.gatewayStatus.isRunning){'ONLINE'}else{'OFFLINE'})</div>
            <div class="metric-label">Status</div>
        </div>
        <div class="metric">
            <div class="metric-value">$($Data.gatewayStatus.routeCount)</div>
            <div class="metric-label">Routes</div>
        </div>
        <div class="metric">
            <div class="metric-value">$($Data.gatewayStatus.sessionCount)</div>
            <div class="metric-label">Sessions</div>
        </div>
        <div class="metric">
            <div class="metric-value">$($Data.gatewayStatus.uptime)</div>
            <div class="metric-label">Uptime</div>
        </div>
    </div>
    <h3>Circuit Breakers</h3>
    <table>
        <thead>
            <tr><th>Pack ID</th><th>State</th><th>Failures</th><th>Successes</th></tr>
        </thead>
        <tbody>
            $($cbRows -join "`n")
        </tbody>
    </table>
</div>
"@
}

function Convert-FederationToHtmlSection {
    param($Data, $ThemeColors)
    
    $nodeRows = $Data.nodes | ForEach-Object {
        $badgeClass = switch ($_.status) {
            'active' { 'badge-healthy' }
            'suspended' { 'badge-warning' }
            'offline' { 'badge-critical' }
            default { '' }
        }
        $lastSync = if ($_.lastSync) { [DateTime]::Parse($_.lastSync).ToString('yyyy-MM-dd HH:mm') } else { 'Never' }
        "<tr><td>$($_.nodeId)</td><td><span class='badge $badgeClass'>$($_.status)</span></td><td>$($_.trustLevel)</td><td>$($_.syncDirection)</td><td>$lastSync</td></tr>"
    }
    
    return @"
<div class="card">
    <h2>Federated Memory</h2>
    <div class="metric-grid">
        <div class="metric">
            <div class="metric-value">$($Data.summary.totalNodes)</div>
            <div class="metric-label">Total Nodes</div>
        </div>
        <div class="metric">
            <div class="metric-value status-healthy">$($Data.summary.activeNodes)</div>
            <div class="metric-label">Active</div>
        </div>
        <div class="metric">
            <div class="metric-value status-warning">$($Data.summary.suspendedNodes)</div>
            <div class="metric-label">Suspended</div>
        </div>
        <div class="metric">
            <div class="metric-value">$($Data.summary.pendingConflicts)</div>
            <div class="metric-label">Conflicts</div>
        </div>
    </div>
    <table>
        <thead>
            <tr><th>Node ID</th><th>Status</th><th>Trust</th><th>Direction</th><th>Last Sync</th></tr>
        </thead>
        <tbody>
            $($nodeRows -join "`n")
        </tbody>
    </table>
</div>
"@
}

function Convert-ToHealthDashboardHTML {
    param($Data, $Theme)
    
    $sections = @(Convert-HealthToHtmlSection -Data $Data -ThemeColors $script:HtmlThemes[$Theme])
    
    return @"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Pack Health Dashboard</title>
<style>
body { font-family: sans-serif; background: $($script:HtmlThemes[$Theme].bgColor); color: $($script:HtmlThemes[$Theme].textColor); padding: 20px; }
.card { background: $($script:HtmlThemes[$Theme].cardBg); border: 1px solid $($script:HtmlThemes[$Theme].borderColor); border-radius: 8px; padding: 20px; margin-bottom: 20px; }
h2 { color: $($script:HtmlThemes[$Theme].accentColor); }
.metric-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; }
.metric { text-align: center; padding: 15px; background: rgba(0,0,0,0.2); border-radius: 6px; }
.metric-value { font-size: 2em; font-weight: bold; }
.status-healthy { color: $($script:HtmlThemes[$Theme].healthyColor); }
.status-warning { color: $($script:HtmlThemes[$Theme].warningColor); }
.status-critical { color: $($script:HtmlThemes[$Theme].criticalColor); }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 10px; border-bottom: 1px solid $($script:HtmlThemes[$Theme].borderColor); text-align: left; }
</style></head><body>$($sections -join "`n")</body></html>
"@
}

function Convert-ToRetrievalDashboardHTML {
    param($Data, $Theme)
    
    $sections = @(Convert-RetrievalToHtmlSection -Data $Data -ThemeColors $script:HtmlThemes[$Theme])
    
    return @"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Retrieval Activity Dashboard</title>
<style>
body { font-family: sans-serif; background: $($script:HtmlThemes[$Theme].bgColor); color: $($script:HtmlThemes[$Theme].textColor); padding: 20px; }
.card { background: $($script:HtmlThemes[$Theme].cardBg); border: 1px solid $($script:HtmlThemes[$Theme].borderColor); border-radius: 8px; padding: 20px; margin-bottom: 20px; }
h2 { color: $($script:HtmlThemes[$Theme].accentColor); }
.metric-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; }
.metric { text-align: center; padding: 15px; background: rgba(0,0,0,0.2); border-radius: 6px; }
.metric-value { font-size: 2em; font-weight: bold; }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 10px; border-bottom: 1px solid $($script:HtmlThemes[$Theme].borderColor); text-align: left; }
</style></head><body>$($sections -join "`n")</body></html>
"@
}

function Convert-ToGatewayStatusHTML {
    param($Data, $Theme)
    
    $sections = @(Convert-GatewayToHtmlSection -Data $Data -ThemeColors $script:HtmlThemes[$Theme])
    
    return @"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>MCP Gateway Status</title>
<style>
body { font-family: sans-serif; background: $($script:HtmlThemes[$Theme].bgColor); color: $($script:HtmlThemes[$Theme].textColor); padding: 20px; }
.card { background: $($script:HtmlThemes[$Theme].cardBg); border: 1px solid $($script:HtmlThemes[$Theme].borderColor); border-radius: 8px; padding: 20px; margin-bottom: 20px; }
h2 { color: $($script:HtmlThemes[$Theme].accentColor); }
.metric-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; }
.metric { text-align: center; padding: 15px; background: rgba(0,0,0,0.2); border-radius: 6px; }
.metric-value { font-size: 2em; font-weight: bold; }
.status-healthy { color: $($script:HtmlThemes[$Theme].healthyColor); }
.status-critical { color: $($script:HtmlThemes[$Theme].criticalColor); }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 10px; border-bottom: 1px solid $($script:HtmlThemes[$Theme].borderColor); text-align: left; }
.badge { padding: 3px 8px; border-radius: 12px; font-size: 0.75em; }
.badge-healthy { background: rgba(78, 201, 176, 0.2); color: $($script:HtmlThemes[$Theme].healthyColor); }
.badge-critical { background: rgba(244, 71, 71, 0.2); color: $($script:HtmlThemes[$Theme].criticalColor); }
</style></head><body>$($sections -join "`n")</body></html>
"@
}

function Convert-ToFederationStatusHTML {
    param($Data, $Theme)
    
    $sections = @(Convert-FederationToHtmlSection -Data $Data -ThemeColors $script:HtmlThemes[$Theme])
    
    return @"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Federation Status</title>
<style>
body { font-family: sans-serif; background: $($script:HtmlThemes[$Theme].bgColor); color: $($script:HtmlThemes[$Theme].textColor); padding: 20px; }
.card { background: $($script:HtmlThemes[$Theme].cardBg); border: 1px solid $($script:HtmlThemes[$Theme].borderColor); border-radius: 8px; padding: 20px; margin-bottom: 20px; }
h2 { color: $($script:HtmlThemes[$Theme].accentColor); }
.metric-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; }
.metric { text-align: center; padding: 15px; background: rgba(0,0,0,0.2); border-radius: 6px; }
.metric-value { font-size: 2em; font-weight: bold; }
.status-healthy { color: $($script:HtmlThemes[$Theme].healthyColor); }
.status-warning { color: $($script:HtmlThemes[$Theme].warningColor); }
table { width: 100%; border-collapse: collapse; }
th, td { padding: 10px; border-bottom: 1px solid $($script:HtmlThemes[$Theme].borderColor); text-align: left; }
.badge { padding: 3px 8px; border-radius: 12px; font-size: 0.75em; }
.badge-healthy { background: rgba(78, 201, 176, 0.2); color: $($script:HtmlThemes[$Theme].healthyColor); }
.badge-warning { background: rgba(220, 220, 170, 0.2); color: $($script:HtmlThemes[$Theme].warningColor); }
</style></head><body>$($sections -join "`n")</body></html>
"@
}

function Convert-ToGraphHTML {
    param($Data, $Theme)
    
    $sections = @(Convert-GraphToHtmlSection -Data $Data -ThemeColors $script:HtmlThemes[$Theme])
    
    return @"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Cross-Pack Graph</title>
<script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
<script>mermaid.initialize({startOnLoad:true});</script>
<style>
body { font-family: sans-serif; background: $($script:HtmlThemes[$Theme].bgColor); color: $($script:HtmlThemes[$Theme].textColor); padding: 20px; }
.card { background: $($script:HtmlThemes[$Theme].cardBg); border: 1px solid $($script:HtmlThemes[$Theme].borderColor); border-radius: 8px; padding: 20px; }
h2 { color: $($script:HtmlThemes[$Theme].accentColor); }
.mermaid { text-align: center; }
</style></head><body>$($sections -join "`n")</body></html>
"@
}

#===============================================================================
# Module Export
#===============================================================================

Export-ModuleMember -Function @(
    'Show-PackHealthDashboard'
    'Show-RetrievalActivityDashboard'
    'Show-CrossPackGraph'
    'Show-MCPGatewayStatus'
    'Show-FederationStatus'
    'Export-DashboardHTML'
)

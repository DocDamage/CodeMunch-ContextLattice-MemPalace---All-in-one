#requires -Version 5.1
<#
.SYNOPSIS
    Pack Service Level Objectives (SLOs) and Telemetry module for LLM Workflow platform.

.DESCRIPTION
    Implements Pack SLO tracking and telemetry collection per Section 18 of the canonical architecture.
    
    Provides:
    - SLO configuration management with targets and thresholds
    - Telemetry data collection and storage (JSON Lines format)
    - SLO compliance monitoring and violation detection
    - Pack health dashboard data generation
    - Trend analysis and percentile calculations (P95/P99)
    - Automatic telemetry rotation (30-day retention)
    
    Supported Telemetry Metrics:
    - buildSuccessRate: Percentage of successful pack builds
    - refreshLatencyMs: Time to refresh pack sources (milliseconds)
    - parserFailureRate: Rate of parser failures
    - extractionCoverage: Coverage of extraction targets
    - provenanceCoverage: Coverage of provenance information
    - answerGroundingRate: Rate of grounded answers
    - p95RetrievalLatencyMs: P95 latency of retrieval operations
    - feedbackCategoryCounts: Distribution of feedback categories

.NOTES
    File Name      : PackSLOs.ps1
    Author         : LLM Workflow Team
    Prerequisite   : PowerShell 5.1+
    Copyright      : (c) 2026 LLM Workflow Project
    License        : MIT
    Version        : 1.0.0
#>

Set-StrictMode -Version Latest

# Script-level constants
$script:TelemetryDirectory = ".llm-workflow/telemetry"
$script:SLOConfigDirectory = ".llm-workflow/config/slos"
$script:TelemetryRetentionDays = 30
$script:ViolationLogFile = ".llm-workflow/telemetry/violations.jsonl"

# Default SLO targets per Section 18.1
$script:DefaultSLOTargets = @{
    p95RetrievalLatencyMs = 1200
    answerGroundingRate = 0.95
    parserFailureRate = 0.02
    provenanceCoverage = 0.99
    goldenTaskPassRate = 0.90
    buildSuccessRate = 0.98
    extractionCoverage = 0.95
    refreshLatencyMs = 5000
}

# Default threshold configurations
$script:DefaultThresholds = @{
    p95RetrievalLatencyMs = @{ warning = 1000; critical = 2000 }
    answerGroundingRate = @{ warning = 0.90; critical = 0.80 }
    parserFailureRate = @{ warning = 0.05; critical = 0.10 }
    provenanceCoverage = @{ warning = 0.95; critical = 0.90 }
    goldenTaskPassRate = @{ warning = 0.85; critical = 0.75 }
    buildSuccessRate = @{ warning = 0.95; critical = 0.90 }
    extractionCoverage = @{ warning = 0.90; critical = 0.80 }
    refreshLatencyMs = @{ warning = 3000; critical = 10000 }
}

# Time range mappings
$script:TimeRangeMappings = @{
    '1h' = [TimeSpan]::FromHours(1)
    '24h' = [TimeSpan]::FromHours(24)
    '7d' = [TimeSpan]::FromDays(7)
    '30d' = [TimeSpan]::FromDays(30)
    '90d' = [TimeSpan]::FromDays(90)
}

# Predefined SLO configurations for standard packs
$script:PredefinedSLOs = @{
    'rpgmaker-mz' = @{
        packId = 'rpgmaker-mz'
        version = '1.0'
        targets = @{
            p95RetrievalLatencyMs = 1200
            answerGroundingRate = 0.95
            parserFailureRate = 0.02
            provenanceCoverage = 0.99
            goldenTaskPassRate = 0.90
            buildSuccessRate = 0.98
            extractionCoverage = 0.95
            refreshLatencyMs = 5000
        }
        thresholds = @{
            p95RetrievalLatencyMs = @{ warning = 1000; critical = 2000 }
            answerGroundingRate = @{ warning = 0.90; critical = 0.80 }
            parserFailureRate = @{ warning = 0.05; critical = 0.10 }
            provenanceCoverage = @{ warning = 0.95; critical = 0.90 }
        }
        reviewCadence = 'weekly'
        lastReviewed = '2026-04-12T00:00:00Z'
        owner = 'rpgmaker-team'
        description = 'RPG Maker MZ pack SLOs with emphasis on plugin extraction accuracy'
    }
    'godot-engine' = @{
        packId = 'godot-engine'
        version = '1.0'
        targets = @{
            p95RetrievalLatencyMs = 1500
            answerGroundingRate = 0.93
            parserFailureRate = 0.03
            provenanceCoverage = 0.98
            goldenTaskPassRate = 0.88
            buildSuccessRate = 0.97
            extractionCoverage = 0.92
            refreshLatencyMs = 6000
        }
        thresholds = @{
            p95RetrievalLatencyMs = @{ warning = 1200; critical = 2500 }
            answerGroundingRate = @{ warning = 0.88; critical = 0.78 }
            parserFailureRate = @{ warning = 0.06; critical = 0.12 }
            provenanceCoverage = @{ warning = 0.94; critical = 0.88 }
        }
        reviewCadence = 'weekly'
        lastReviewed = '2026-04-12T00:00:00Z'
        owner = 'godot-team'
        description = 'Godot Engine pack SLOs with multi-language parser support'
    }
    'blender-engine' = @{
        packId = 'blender-engine'
        version = '1.0'
        targets = @{
            p95RetrievalLatencyMs = 1800
            answerGroundingRate = 0.92
            parserFailureRate = 0.04
            provenanceCoverage = 0.97
            goldenTaskPassRate = 0.85
            buildSuccessRate = 0.96
            extractionCoverage = 0.90
            refreshLatencyMs = 8000
        }
        thresholds = @{
            p95RetrievalLatencyMs = @{ warning = 1500; critical = 3000 }
            answerGroundingRate = @{ warning = 0.87; critical = 0.75 }
            parserFailureRate = @{ warning = 0.07; critical = 0.15 }
            provenanceCoverage = @{ warning = 0.93; critical = 0.85 }
        }
        reviewCadence = 'bi-weekly'
        lastReviewed = '2026-04-12T00:00:00Z'
        owner = 'blender-team'
        description = 'Blender Engine pack SLOs with geometry nodes and shader complexity'
    }
}

<#
.SYNOPSIS
    Defines SLO configuration for a pack.

.DESCRIPTION
    Creates a new SLO configuration with specified targets, thresholds, and review cadence.
    The configuration is saved to .llm-workflow/config/slos/{PackId}.json.

.PARAMETER PackId
    The unique identifier for the pack (e.g., 'rpgmaker-mz').

.PARAMETER Targets
    Hashtable of SLO targets. Supported keys:
    - p95RetrievalLatencyMs: Target P95 retrieval latency in milliseconds
    - answerGroundingRate: Target rate of grounded answers (0.0-1.0)
    - parserFailureRate: Maximum acceptable parser failure rate (0.0-1.0)
    - provenanceCoverage: Target provenance coverage (0.0-1.0)
    - goldenTaskPassRate: Target golden task pass rate (0.0-1.0)
    - buildSuccessRate: Target build success rate (0.0-1.0)
    - extractionCoverage: Target extraction coverage (0.0-1.0)
    - refreshLatencyMs: Target refresh latency in milliseconds

.PARAMETER Thresholds
    Hashtable of warning and critical thresholds for each metric.
    Format: @{ metricName = @{ warning = value; critical = value } }

.PARAMETER ReviewCadence
    How often to review SLOs. Valid values: 'daily', 'weekly', 'bi-weekly', 'monthly'.

.PARAMETER Owner
    The team or individual responsible for this pack's SLOs.

.PARAMETER Description
    Optional description of the SLO configuration.

.PARAMETER Force
    If specified, overwrites existing SLO configuration.

.OUTPUTS
    System.Collections.Hashtable containing the created SLO configuration.

.EXAMPLE
    PS C:\> New-PackSLO -PackId "custom-pack" -Targets @{ p95RetrievalLatencyMs = 1000 } -ReviewCadence "weekly"
    
    Creates a basic SLO configuration with default thresholds.

.EXAMPLE
    PS C:\> $targets = @{ answerGroundingRate = 0.97; parserFailureRate = 0.01 }
    PS C:\> $thresholds = @{ answerGroundingRate = @{ warning = 0.95; critical = 0.90 } }
    PS C:\> New-PackSLO -PackId "high-accuracy-pack" -Targets $targets -Thresholds $thresholds -Owner "ai-team"
    
    Creates an SLO configuration with custom targets and thresholds.
#>
function New-PackSLO {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter()]
        [hashtable]$Targets = @{},

        [Parameter()]
        [hashtable]$Thresholds = @{},

        [Parameter()]
        [ValidateSet('daily', 'weekly', 'bi-weekly', 'monthly')]
        [string]$ReviewCadence = 'weekly',

        [Parameter()]
        [string]$Owner = 'unspecified',

        [Parameter()]
        [string]$Description = '',

        [Parameter()]
        [switch]$Force
    )

    begin {
        # Merge provided targets with defaults
        $mergedTargets = $script:DefaultSLOTargets.Clone()
        foreach ($key in $Targets.Keys) {
            if ($script:DefaultSLOTargets.ContainsKey($key)) {
                $mergedTargets[$key] = $Targets[$key]
            }
        }

        # Merge provided thresholds with defaults
        $mergedThresholds = @{}
        foreach ($key in $script:DefaultThresholds.Keys) {
            $mergedThresholds[$key] = $script:DefaultThresholds[$key].Clone()
        }
        foreach ($key in $Thresholds.Keys) {
            if ($mergedThresholds.ContainsKey($key) -and $Thresholds[$key] -is [hashtable]) {
                if ($Thresholds[$key].ContainsKey('warning')) {
                    $mergedThresholds[$key]['warning'] = $Thresholds[$key]['warning']
                }
                if ($Thresholds[$key].ContainsKey('critical')) {
                    $mergedThresholds[$key]['critical'] = $Thresholds[$key]['critical']
                }
            }
        }
    }

    process {
        $sloConfig = @{
            packId = $PackId
            version = '1.0'
            targets = $mergedTargets
            thresholds = $mergedThresholds
            reviewCadence = $ReviewCadence
            lastReviewed = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            owner = $Owner
            description = $Description
            createdUtc = [DateTime]::UtcNow.ToString('o')
        }

        # Ensure SLO directory exists
        if (-not (Test-Path -LiteralPath $script:SLOConfigDirectory)) {
            New-Item -ItemType Directory -Path $script:SLOConfigDirectory -Force | Out-Null
        }

        $sloPath = Join-Path $script:SLOConfigDirectory "$PackId.json"

        if ((Test-Path -LiteralPath $sloPath) -and -not $Force) {
            if (-not $PSCmdlet.ShouldProcess($sloPath, 'Overwrite existing SLO configuration')) {
                return (Get-Content -LiteralPath $sloPath -Raw | ConvertFrom-Json -AsHashtable)
            }
        }

        try {
            $json = $sloConfig | ConvertTo-Json -Depth 10 -Compress:$false
            Set-Content -Path $sloPath -Value $json -Force:$Force
            Write-Verbose "[PackSLOs] SLO configuration saved to: $sloPath"
        }
        catch {
            Write-Error "[PackSLOs] Failed to save SLO configuration: $_"
            return $null
        }

        return $sloConfig
    }
}

<#
.SYNOPSIS
    Records a telemetry data point for a pack.

.DESCRIPTION
    Appends a telemetry data point to the JSON Lines file for the specified pack and metric.
    Data is stored in .llm-workflow/telemetry/{packId}/{metricName}.jsonl
    
    Automatically handles:
    - Directory creation
    - Timestamp generation
    - JSON serialization with ASCII-safe encoding
    - Atomic file appends

.PARAMETER PackId
    The pack identifier.

.PARAMETER MetricName
    The name of the metric to record. Supported values:
    - buildSuccessRate, refreshLatencyMs, parserFailureRate
    - extractionCoverage, provenanceCoverage, answerGroundingRate
    - p95RetrievalLatencyMs, feedbackCategoryCounts
    - Or any custom metric name

.PARAMETER Value
    The numeric value to record.

.PARAMETER Dimensions
    Optional hashtable of additional context (e.g., @{ sourceId = 'abc'; operation = 'extract' }).

.PARAMETER RunId
    Optional run ID for correlation. Defaults to current run ID or 'unknown'.

.OUTPUTS
    System.Boolean. True if the telemetry was recorded successfully.

.EXAMPLE
    PS C:\> Record-Telemetry -PackId "rpgmaker-mz" -MetricName "refreshLatencyMs" -Value 2500 -Dimensions @{ sourceCount = 5 }
    
    Records a refresh latency measurement.

.EXAMPLE
    PS C:\> Record-Telemetry -PackId "godot-engine" -MetricName "buildSuccessRate" -Value 1.0 -Dimensions @{ buildId = "20260412-1"; durationMs = 45000 }
    
    Records a successful build event.
#>
function Record-Telemetry {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter(Mandatory = $true)]
        [string]$MetricName,

        [Parameter(Mandatory = $true)]
        [double]$Value,

        [Parameter()]
        [hashtable]$Dimensions = @{},

        [Parameter()]
        [string]$RunId = 'unknown'
    )

    process {
        try {
            # Get run ID if not provided
            if ($RunId -eq 'unknown') {
                try {
                    $runIdCmd = Get-Command Get-CurrentRunId -ErrorAction SilentlyContinue
                    if ($runIdCmd) {
                        $RunId = & $runIdCmd -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    $RunId = 'unknown'
                }
            }

            # Ensure telemetry directory exists
            $packTelemetryDir = Join-Path $script:TelemetryDirectory $PackId
            if (-not (Test-Path -LiteralPath $packTelemetryDir)) {
                New-Item -ItemType Directory -Path $packTelemetryDir -Force | Out-Null
            }

            # Build telemetry entry
            $entry = [ordered]@{
                timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                packId = $PackId
                metricName = $MetricName
                value = $Value
                runId = $RunId
                dimensions = $Dimensions
            }

            # Convert to JSON line
            $jsonLine = ($entry | ConvertTo-Json -Compress -Depth 5)
            
            # Ensure ASCII-safe output
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonLine)
            $safeLine = [System.Text.Encoding]::UTF8.GetString($bytes)

            # Write to file (append)
            $metricFile = Join-Path $packTelemetryDir "$MetricName.jsonl"
            $safeLine | Out-File -FilePath $metricFile -Encoding UTF8 -Append

            Write-Verbose "[PackSLOs] Recorded telemetry: $PackId/$MetricName = $Value"
            return $true
        }
        catch {
            Write-Warning "[PackSLOs] Failed to record telemetry: $_"
            return $false
        }
    }
}

<#
.SYNOPSIS
    Gets the current SLO status for a pack.

.DESCRIPTION
    Evaluates the current SLO status by comparing actual telemetry metrics
    against configured SLO targets for the specified time range.

.PARAMETER PackId
    The pack identifier.

.PARAMETER TimeRange
    Time range for evaluation. Valid values: '1h', '24h', '7d', '30d'.

.OUTPUTS
    System.Collections.Hashtable containing:
    - packId: The pack identifier
    - timeRange: Evaluated time range
    - evaluatedAt: Timestamp of evaluation
    - overallStatus: 'compliant', 'warning', or 'critical'
    - metrics: Hashtable of metric statuses
    - summary: Summary statistics

.EXAMPLE
    PS C:\> Get-PackSLOStatus -PackId "rpgmaker-mz" -TimeRange "24h"
    
    Gets SLO status for the last 24 hours.
#>
function Get-PackSLOStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter()]
        [ValidateSet('1h', '24h', '7d', '30d', '90d')]
        [string]$TimeRange = '24h'
    )

    process {
        # Load SLO configuration
        $sloConfig = Get-SLOConfigInternal -PackId $PackId
        if (-not $sloConfig) {
            Write-Warning "[PackSLOs] No SLO configuration found for pack: $PackId"
            return $null
        }

        # Calculate time window
        $timeSpan = $script:TimeRangeMappings[$TimeRange]
        $from = [DateTime]::UtcNow - $timeSpan
        $to = [DateTime]::UtcNow

        $metricStatuses = @{}
        $overallCompliant = $true
        $warningCount = 0
        $criticalCount = 0

        # Evaluate each metric with targets
        foreach ($metricName in $sloConfig.targets.Keys) {
            $target = $sloConfig.targets[$metricName]
            $threshold = $sloConfig.thresholds[$metricName]

            # Get actual metrics
            $actualValue = Get-TelemetryMetricsInternal -PackId $PackId -MetricName $metricName -From $from -To $to -Aggregation 'avg'
            
            if ($null -eq $actualValue) {
                $actualValue = 0
            }

            # Determine status
            $status = 'compliant'
            if ($threshold) {
                # For metrics where lower is better (latency, failure rate)
                $isLowerBetter = $metricName -match '(?i)(latency|failure|error)'
                
                if ($isLowerBetter) {
                    if ($threshold.critical -and $actualValue -gt $threshold.critical) {
                        $status = 'critical'
                        $criticalCount++
                        $overallCompliant = $false
                    }
                    elseif ($threshold.warning -and $actualValue -gt $threshold.warning) {
                        $status = 'warning'
                        $warningCount++
                        $overallCompliant = $false
                    }
                }
                else {
                    # For metrics where higher is better (rates, coverage)
                    if ($threshold.critical -and $actualValue -lt $threshold.critical) {
                        $status = 'critical'
                        $criticalCount++
                        $overallCompliant = $false
                    }
                    elseif ($threshold.warning -and $actualValue -lt $threshold.warning) {
                        $status = 'warning'
                        $warningCount++
                        $overallCompliant = $false
                    }
                }
            }

            $metricStatuses[$metricName] = @{
                target = $target
                actual = $actualValue
                status = $status
                threshold = $threshold
            }
        }

        $overallStatus = if ($criticalCount -gt 0) { 'critical' } elseif ($warningCount -gt 0) { 'warning' } else { 'compliant' }

        return @{
            packId = $PackId
            timeRange = $TimeRange
            evaluatedAt = [DateTime]::UtcNow.ToString('o')
            overallStatus = $overallStatus
            metrics = $metricStatuses
            summary = @{
                totalMetrics = $metricStatuses.Count
                compliant = ($metricStatuses.Values | Where-Object { $_.status -eq 'compliant' }).Count
                warning = $warningCount
                critical = $criticalCount
            }
        }
    }
}

<#
.SYNOPSIS
    Tests if a pack's SLOs are being met.

.DESCRIPTION
    Compares actual metrics against SLO configuration to determine compliance.
    Can be used for ad-hoc testing or in CI/CD pipelines.

.PARAMETER PackId
    The pack identifier.

.PARAMETER SLOConfig
    Optional SLO configuration. If not provided, loads from file or uses defaults.

.PARAMETER ActualMetrics
    Hashtable of actual metric values to test against targets.

.PARAMETER FailOnWarning
    If specified, treats warnings as failures.

.OUTPUTS
    System.Collections.Hashtable containing:
    - isCompliant: Boolean indicating overall compliance
    - violations: Array of SLO violations
    - summary: Summary of test results

.EXAMPLE
    PS C:\> $metrics = @{ p95RetrievalLatencyMs = 1100; answerGroundingRate = 0.96 }
    PS C:\> Test-SLOCompliance -PackId "rpgmaker-mz" -ActualMetrics $metrics
    
    Tests SLO compliance with provided metrics.
#>
function Test-SLOCompliance {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter()]
        [hashtable]$SLOConfig = $null,

        [Parameter(Mandatory = $true)]
        [hashtable]$ActualMetrics,

        [Parameter()]
        [switch]$FailOnWarning
    )

    process {
        # Load SLO config if not provided
        if (-not $SLOConfig) {
            $SLOConfig = Get-SLOConfigInternal -PackId $PackId
        }

        if (-not $SLOConfig) {
            # Use default SLOs
            $SLOConfig = @{
                targets = $script:DefaultSLOTargets
                thresholds = $script:DefaultThresholds
            }
        }

        $violations = @()
        $passedCount = 0
        $failedCount = 0

        foreach ($metricName in $SLOConfig.targets.Keys) {
            $target = $SLOConfig.targets[$metricName]
            $threshold = $SLOConfig.thresholds[$metricName]
            $actualValue = $ActualMetrics[$metricName]

            if ($null -eq $actualValue) {
                continue
            }

            # Determine if compliant
            $isLowerBetter = $metricName -match '(?i)(latency|failure|error)'
            $isCompliant = $true
            $severity = 'compliant'

            if ($isLowerBetter) {
                if ($target -and $actualValue -gt $target) {
                    $isCompliant = $false
                    $severity = 'violation'
                }
                if ($threshold -and $threshold.critical -and $actualValue -gt $threshold.critical) {
                    $severity = 'critical'
                }
                elseif ($threshold -and $threshold.warning -and $actualValue -gt $threshold.warning) {
                    $severity = 'warning'
                }
            }
            else {
                if ($target -and $actualValue -lt $target) {
                    $isCompliant = $false
                    $severity = 'violation'
                }
                if ($threshold -and $threshold.critical -and $actualValue -lt $threshold.critical) {
                    $severity = 'critical'
                }
                elseif ($threshold -and $threshold.warning -and $actualValue -lt $threshold.warning) {
                    $severity = 'warning'
                }
            }

            if (-not $isCompliant -or ($FailOnWarning -and $severity -ne 'compliant')) {
                $violations += @{
                    metricName = $metricName
                    expected = $target
                    actual = $actualValue
                    severity = $severity
                    diff = if ($isLowerBetter) { $actualValue - $target } else { $target - $actualValue }
                }
                $failedCount++
            }
            else {
                $passedCount++
            }
        }

        return @{
            packId = $PackId
            isCompliant = ($violations.Count -eq 0)
            violations = $violations
            summary = @{
                total = $passedCount + $failedCount
                passed = $passedCount
                failed = $failedCount
            }
            testedAt = [DateTime]::UtcNow.ToString('o')
        }
    }
}

<#
.SYNOPSIS
    Gets aggregated telemetry metrics for a pack.

.DESCRIPTION
    Retrieves and aggregates telemetry data for the specified metric and time range.
    Supports multiple aggregation functions including P95/P99 percentiles.

.PARAMETER PackId
    The pack identifier.

.PARAMETER MetricName
    The name of the metric to retrieve.

.PARAMETER From
    Start date/time for the query.

.PARAMETER To
    End date/time for the query.

.PARAMETER Aggregation
    Aggregation function: 'avg', 'p95', 'p99', 'sum', 'count', 'min', 'max'.

.OUTPUTS
    System.Double. The aggregated metric value, or $null if no data.

.EXAMPLE
    PS C:\> Get-TelemetryMetrics -PackId "rpgmaker-mz" -MetricName "refreshLatencyMs" -From (Get-Date).AddDays(-7) -To (Get-Date) -Aggregation "p95"
    
    Gets the P95 refresh latency over the last 7 days.

.EXAMPLE
    PS C:\> Get-TelemetryMetrics -PackId "godot-engine" -MetricName "buildSuccessRate" -From (Get-Date).AddHours(-24) -To (Get-Date) -Aggregation "avg"
    
    Gets the average build success rate over the last 24 hours.
#>
function Get-TelemetryMetrics {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter(Mandatory = $true)]
        [string]$MetricName,

        [Parameter(Mandatory = $true)]
        [DateTime]$From,

        [Parameter(Mandatory = $true)]
        [DateTime]$To,

        [Parameter()]
        [ValidateSet('avg', 'p95', 'p99', 'sum', 'count', 'min', 'max')]
        [string]$Aggregation = 'avg'
    )

    process {
        return Get-TelemetryMetricsInternal -PackId $PackId -MetricName $MetricName -From $From -To $To -Aggregation $Aggregation
    }
}

<#
.SYNOPSIS
    Internal function to get aggregated telemetry metrics.
#>
function Get-TelemetryMetricsInternal {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter(Mandatory = $true)]
        [string]$MetricName,

        [Parameter(Mandatory = $true)]
        [DateTime]$From,

        [Parameter(Mandatory = $true)]
        [DateTime]$To,

        [Parameter()]
        [string]$Aggregation = 'avg'
    )

    process {
        $metricFile = Join-Path $script:TelemetryDirectory "$PackId/$MetricName.jsonl"

        if (-not (Test-Path -LiteralPath $metricFile)) {
            return $null
        }

        try {
            # Read and filter entries
            $entries = @()
            $lines = Get-Content -LiteralPath $metricFile -Encoding UTF8

            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                try {
                    $entry = $line | ConvertFrom-Json
                    $entryTime = [DateTime]::Parse($entry.timestamp)

                    if ($entryTime -ge $From -and $entryTime -le $To) {
                        $entries += $entry.value
                    }
                }
                catch {
                    Write-Verbose "[PackSLOs] Failed to parse telemetry line: $_"
                }
            }

            if ($entries.Count -eq 0) {
                return $null
            }

            # Calculate aggregation
            switch ($Aggregation.ToLower()) {
                'avg' { return ($entries | Measure-Object -Average).Average }
                'sum' { return ($entries | Measure-Object -Sum).Sum }
                'count' { return $entries.Count }
                'min' { return ($entries | Measure-Object -Minimum).Minimum }
                'max' { return ($entries | Measure-Object -Maximum).Maximum }
                'p95' { return Get-Percentile -Values $entries -Percentile 95 }
                'p99' { return Get-Percentile -Values $entries -Percentile 99 }
                default { return ($entries | Measure-Object -Average).Average }
            }
        }
        catch {
            Write-Warning "[PackSLOs] Failed to read telemetry: $_"
            return $null
        }
    }
}

<#
.SYNOPSIS
    Calculates the specified percentile of a value array.
#>
function Get-Percentile {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory = $true)]
        [double[]]$Values,

        [Parameter(Mandatory = $true)]
        [int]$Percentile
    )

    process {
        $sorted = $Values | Sort-Object
        $count = $sorted.Count
        
        if ($count -eq 0) { return 0 }
        if ($count -eq 1) { return $sorted[0] }
        
        $index = ($Percentile / 100) * ($count - 1)
        $lower = [math]::Floor($index)
        $upper = [math]::Ceiling($index)
        $weight = $index - $lower
        
        if ($lower -eq $upper) {
            return $sorted[$lower]
        }
        
        return $sorted[$lower] * (1 - $weight) + $sorted[$upper] * $weight
    }
}

<#
.SYNOPSIS
    Gets pack health dashboard data.

.DESCRIPTION
    Generates comprehensive dashboard data for pack health monitoring,
    including all key metrics, SLO status, trends, and recent violations.

.PARAMETER PackId
    The pack identifier.

.OUTPUTS
    System.Collections.Hashtable containing dashboard data:
    - packId: Pack identifier
    - generatedAt: Timestamp
    - sloConfig: Current SLO configuration
    - currentMetrics: Current metric values (24h avg)
    - sloStatus: Current SLO compliance status
    - trends: Trend indicators for key metrics
    - recentViolations: Recent SLO violations
    - recommendations: Recommended actions

.EXAMPLE
    PS C:\> Get-PackHealthDashboard -PackId "rpgmaker-mz"
    
    Gets complete dashboard data for the RPG Maker MZ pack.
#>
function Get-PackHealthDashboard {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId
    )

    process {
        # Load SLO configuration
        $sloConfig = Get-SLOConfigInternal -PackId $PackId

        # Get current metrics (24h)
        $from = [DateTime]::UtcNow.AddHours(-24)
        $to = [DateTime]::UtcNow
        $currentMetrics = @{}

        if ($sloConfig -and $sloConfig.targets) {
            foreach ($metricName in $sloConfig.targets.Keys) {
                $value = Get-TelemetryMetricsInternal -PackId $PackId -MetricName $metricName -From $from -To $To -Aggregation 'avg'
                if ($null -ne $value) {
                    $currentMetrics[$metricName] = $value
                }
            }
        }

        # Get SLO status
        $sloStatus = Get-PackSLOStatus -PackId $PackId -TimeRange '24h'

        # Get trends (compare 24h vs previous 24h)
        $trends = Get-MetricTrends -PackId $PackId -SLOConfig $sloConfig

        # Get recent violations
        $recentViolations = Get-SLOViolations -PackId $PackId -TimeRange '24h' -Severity 'all'

        # Generate recommendations
        $recommendations = @()
        if ($sloStatus -and $sloStatus.summary.critical -gt 0) {
            $recommendations += "Address $($sloStatus.summary.critical) critical SLO violation(s) immediately"
        }
        if ($sloStatus -and $sloStatus.summary.warning -gt 0) {
            $recommendations += "Investigate $($sloStatus.summary.warning) warning-level metric(s)"
        }
        if ($trends['p95RetrievalLatencyMs'] -eq 'degrading') {
            $recommendations += 'Retrieval latency is trending upward - consider optimization'
        }
        if ($trends['answerGroundingRate'] -eq 'degrading') {
            $recommendations += 'Answer grounding rate declining - review extraction pipeline'
        }
        if ($recommendations.Count -eq 0) {
            $recommendations += 'Pack is performing within expected parameters'
        }

        return @{
            packId = $PackId
            generatedAt = [DateTime]::UtcNow.ToString('o')
            sloConfig = $sloConfig
            currentMetrics = $currentMetrics
            sloStatus = $sloStatus
            trends = $trends
            recentViolations = $recentViolations
            recommendations = $recommendations
        }
    }
}

<#
.SYNOPSIS
    Gets SLO violations for a pack.

.DESCRIPTION
    Retrieves SLO violations from the violation log for the specified pack,
    optionally filtered by time range and severity.

.PARAMETER PackId
    The pack identifier.

.PARAMETER TimeRange
    Time range for violations. Valid values: '1h', '24h', '7d', '30d'.

.PARAMETER Severity
    Filter by severity: 'warning', 'critical', or 'all'.

.OUTPUTS
    System.Object[]. Array of violation records.

.EXAMPLE
    PS C:\> Get-SLOViolations -PackId "rpgmaker-mz" -TimeRange "7d" -Severity "critical"
    
    Gets critical violations from the last 7 days.
#>
function Get-SLOViolations {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter()]
        [ValidateSet('1h', '24h', '7d', '30d', '90d')]
        [string]$TimeRange = '24h',

        [Parameter()]
        [ValidateSet('warning', 'critical', 'all')]
        [string]$Severity = 'all'
    )

    process {
        if (-not (Test-Path -LiteralPath $script:ViolationLogFile)) {
            return @()
        }

        $timeSpan = $script:TimeRangeMappings[$TimeRange]
        $cutoff = [DateTime]::UtcNow - $timeSpan

        try {
            $violations = @()
            $lines = Get-Content -LiteralPath $script:ViolationLogFile -Encoding UTF8

            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                try {
                    $entry = $line | ConvertFrom-Json
                    
                    # Filter by pack ID
                    if ($entry.packId -ne $PackId) { continue }
                    
                    # Filter by time
                    $entryTime = [DateTime]::Parse($entry.timestamp)
                    if ($entryTime -lt $cutoff) { continue }
                    
                    # Filter by severity
                    if ($Severity -ne 'all' -and $entry.severity -ne $Severity) { continue }
                    
                    $violations += $entry
                }
                catch {
                    Write-Verbose "[PackSLOs] Failed to parse violation line: $_"
                }
            }

            return $violations | Sort-Object timestamp -Descending
        }
        catch {
            Write-Warning "[PackSLOs] Failed to read violations: $_"
            return @()
        }
    }
}

<#
.SYNOPSIS
    Registers an SLO violation.

.DESCRIPTION
    Records an SLO violation to the violation log file for tracking
    and alerting purposes.

.PARAMETER PackId
    The pack identifier.

.PARAMETER MetricName
    The metric that violated SLO.

.PARAMETER ExpectedValue
    The expected/target value.

.PARAMETER ActualValue
    The actual value that caused the violation.

.PARAMETER Severity
    The severity level: 'warning' or 'critical'.

.PARAMETER RunId
    Optional run ID for correlation.

.OUTPUTS
    System.Boolean. True if the violation was registered successfully.

.EXAMPLE
    PS C:\> Register-SLOViolation -PackId "rpgmaker-mz" -MetricName "p95RetrievalLatencyMs" -ExpectedValue 1200 -ActualValue 2500 -Severity "critical"
    
    Registers a critical latency violation.
#>
function Register-SLOViolation {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter(Mandatory = $true)]
        [string]$MetricName,

        [Parameter(Mandatory = $true)]
        [double]$ExpectedValue,

        [Parameter(Mandatory = $true)]
        [double]$ActualValue,

        [Parameter(Mandatory = $true)]
        [ValidateSet('warning', 'critical')]
        [string]$Severity,

        [Parameter()]
        [string]$RunId = 'unknown'
    )

    process {
        try {
            # Ensure violation log directory exists
            $violationDir = Split-Path -Parent $script:ViolationLogFile
            if (-not (Test-Path -LiteralPath $violationDir)) {
                New-Item -ItemType Directory -Path $violationDir -Force | Out-Null
            }

            $violation = [ordered]@{
                timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                packId = $PackId
                metricName = $MetricName
                expectedValue = $ExpectedValue
                actualValue = $ActualValue
                severity = $Severity
                runId = $RunId
                diff = [math]::Abs($ActualValue - $ExpectedValue)
            }

            $jsonLine = ($violation | ConvertTo-Json -Compress)
            $jsonLine | Out-File -FilePath $script:ViolationLogFile -Encoding UTF8 -Append

            Write-Verbose "[PackSLOs] Registered $Severity violation for $PackId/$MetricName"
            return $true
        }
        catch {
            Write-Warning "[PackSLOs] Failed to register violation: $_"
            return $false
        }
    }
}

<#
.SYNOPSIS
    Gets a telemetry summary for a pack.

.DESCRIPTION
    Generates a comprehensive summary of telemetry data for the specified pack
    and time range, including all metrics, statistics, and key observations.

.PARAMETER PackId
    The pack identifier.

.PARAMETER TimeRange
    Time range for the summary. Valid values: '1h', '24h', '7d', '30d'.

.OUTPUTS
    System.Collections.Hashtable containing telemetry summary.

.EXAMPLE
    PS C:\> Get-TelemetrySummary -PackId "rpgmaker-mz" -TimeRange "7d"
    
    Gets a 7-day telemetry summary.
#>
function Get-TelemetrySummary {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter()]
        [ValidateSet('1h', '24h', '7d', '30d', '90d')]
        [string]$TimeRange = '24h'
    )

    process {
        $timeSpan = $script:TimeRangeMappings[$TimeRange]
        $from = [DateTime]::UtcNow - $timeSpan
        $to = [DateTime]::UtcNow

        # Get SLO config to know which metrics to summarize
        $sloConfig = Get-SLOConfigInternal -PackId $PackId
        $metricNames = if ($sloConfig -and $sloConfig.targets) { $sloConfig.targets.Keys } else { @() }

        $metricSummaries = @{}
        $totalDataPoints = 0

        foreach ($metricName in $metricNames) {
            $metricFile = Join-Path $script:TelemetryDirectory "$PackId/$MetricName.jsonl"
            
            if (-not (Test-Path -LiteralPath $metricFile)) {
                continue
            }

            try {
                $lines = Get-Content -LiteralPath $metricFile -Encoding UTF8
                $values = @()
                $dataPoints = 0

                foreach ($line in $lines) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }

                    try {
                        $entry = $line | ConvertFrom-Json
                        $entryTime = [DateTime]::Parse($entry.timestamp)

                        if ($entryTime -ge $from -and $entryTime -le $to) {
                            $values += $entry.value
                            $dataPoints++
                        }
                    }
                    catch {
                        Write-Verbose "[PackSLOs] Failed to parse line: $_"
                    }
                }

                if ($values.Count -gt 0) {
                    $stats = $values | Measure-Object -Average -Minimum -Maximum
                    
                    $metricSummaries[$metricName] = @{
                        count = $dataPoints
                        avg = $stats.Average
                        min = $stats.Minimum
                        max = $stats.Maximum
                        p95 = Get-Percentile -Values $values -Percentile 95
                        p99 = Get-Percentile -Values $values -Percentile 99
                    }
                    $totalDataPoints += $dataPoints
                }
            }
            catch {
                Write-Warning "[PackSLOs] Failed to summarize $metricName`: $_"
            }
        }

        return @{
            packId = $PackId
            timeRange = $TimeRange
            generatedAt = [DateTime]::UtcNow.ToString('o')
            totalDataPoints = $totalDataPoints
            metrics = $metricSummaries
            metricCount = $metricSummaries.Count
        }
    }
}

<#
.SYNOPSIS
    Exports a pack's SLO configuration to a file.

.DESCRIPTION
    Exports the SLO configuration for a pack to a JSON file for backup,
    sharing, or version control.

.PARAMETER PackId
    The pack identifier.

.PARAMETER OutputPath
    The path to write the SLO configuration. If not specified, uses
    .llm-workflow/exports/{PackId}-slo.json.

.OUTPUTS
    System.String. The path to the exported file.

.EXAMPLE
    PS C:\> Export-PackSLO -PackId "rpgmaker-mz" -OutputPath "exports/rpgmaker-slo.json"
    
    Exports the SLO configuration to the specified path.
#>
function Export-PackSLO {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9-]+$')]
        [string]$PackId,

        [Parameter()]
        [string]$OutputPath = ''
    )

    process {
        # Load SLO configuration
        $sloConfig = Get-SLOConfigInternal -PackId $PackId

        if (-not $sloConfig) {
            Write-Error "[PackSLOs] No SLO configuration found for pack: $PackId"
            return $null
        }

        # Set default output path
        if ([string]::IsNullOrEmpty($OutputPath)) {
            $exportDir = '.llm-workflow/exports'
            if (-not (Test-Path -LiteralPath $exportDir)) {
                New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
            }
            $timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')
            $OutputPath = Join-Path $exportDir "$PackId-slo-$timestamp.json"
        }

        # Ensure output directory exists
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path -LiteralPath $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        try {
            $exportData = @{
                schemaVersion = '1.0'
                exportedAt = [DateTime]::UtcNow.ToString('o')
                sloConfig = $sloConfig
            }

            $json = $exportData | ConvertTo-Json -Depth 10 -Compress:$false
            Set-Content -Path $OutputPath -Value $json -Force

            Write-Verbose "[PackSLOs] SLO configuration exported to: $OutputPath"
            return $OutputPath
        }
        catch {
            Write-Error "[PackSLOs] Failed to export SLO configuration: $_"
            return $null
        }
    }
}

<#
.SYNOPSIS
    Imports a pack's SLO configuration from a file.

.DESCRIPTION
    Imports an SLO configuration from a JSON file and optionally
    applies it to a pack.

.PARAMETER Path
    The path to the SLO configuration file to import.

.PARAMETER ApplyToPackId
    Optional pack ID to apply the imported configuration to.
    If not specified, uses the packId from the imported config.

.PARAMETER Force
    If specified, overwrites existing SLO configuration.

.OUTPUTS
    System.Collections.Hashtable. The imported SLO configuration.

.EXAMPLE
    PS C:\> Import-PackSLO -Path "exports/rpgmaker-slo.json" -ApplyToPackId "rpgmaker-mz-copy"
    
    Imports the SLO configuration and applies it to a different pack.
#>
function Import-PackSLO {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [string]$ApplyToPackId = '',

        [Parameter()]
        [switch]$Force
    )

    process {
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Error "[PackSLOs] Import file not found: $Path"
            return $null
        }

        try {
            $importData = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
            
            if (-not $importData.sloConfig) {
                Write-Error "[PackSLOs] Invalid SLO configuration file: missing sloConfig"
                return $null
            }

            $sloConfig = $importData.sloConfig

            # Apply to different pack if specified
            if (-not [string]::IsNullOrEmpty($ApplyToPackId)) {
                $sloConfig.packId = $ApplyToPackId
                $sloConfig.importedFrom = $importData.sloConfig.packId
            }

            # Save the imported configuration
            $targetPackId = $sloConfig.packId

            if ($PSCmdlet.ShouldProcess($targetPackId, 'Import SLO configuration')) {
                $result = New-PackSLO -PackId $targetPackId `
                    -Targets $sloConfig.targets `
                    -Thresholds $sloConfig.thresholds `
                    -ReviewCadence $sloConfig.reviewCadence `
                    -Owner $sloConfig.owner `
                    -Description $sloConfig.description `
                    -Force:$Force

                Write-Verbose "[PackSLOs] SLO configuration imported from: $Path"
                return $result
            }

            return $sloConfig
        }
        catch {
            Write-Error "[PackSLOs] Failed to import SLO configuration: $_"
            return $null
        }
    }
}

<#
.SYNOPSIS
    Internal function to get SLO configuration for a pack.
#>
function Get-SLOConfigInternal {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId
    )

    process {
        # Check for predefined SLOs
        if ($script:PredefinedSLOs.ContainsKey($PackId)) {
            return $script:PredefinedSLOs[$PackId]
        }

        # Check for saved SLO configuration
        $sloPath = Join-Path $script:SLOConfigDirectory "$PackId.json"
        if (Test-Path -LiteralPath $sloPath) {
            try {
                return Get-Content -LiteralPath $sloPath -Raw | ConvertFrom-Json -AsHashtable
            }
            catch {
                Write-Warning "[PackSLOs] Failed to load SLO config from $sloPath`: $_"
            }
        }

        # Return default configuration
        return @{
            packId = $PackId
            version = '1.0'
            targets = $script:DefaultSLOTargets.Clone()
            thresholds = $script:DefaultThresholds.Clone()
            reviewCadence = 'weekly'
            lastReviewed = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
            owner = 'unspecified'
            description = 'Default SLO configuration'
        }
    }
}

<#
.SYNOPSIS
    Internal function to get metric trends.
#>
function Get-MetricTrends {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackId,

        [Parameter()]
        [hashtable]$SLOConfig = $null
    )

    process {
        if (-not $SLOConfig -or -not $SLOConfig.targets) {
            return @{}
        }

        $trends = @{}
        $now = [DateTime]::UtcNow
        $recentFrom = $now.AddHours(-24)
        $previousFrom = $now.AddHours(-48)
        $previousTo = $now.AddHours(-24)

        foreach ($metricName in $SLOConfig.targets.Keys) {
            $recentValue = Get-TelemetryMetricsInternal -PackId $PackId -MetricName $metricName -From $recentFrom -To $now -Aggregation 'avg'
            $previousValue = Get-TelemetryMetricsInternal -PackId $PackId -MetricName $metricName -From $previousFrom -To $previousTo -Aggregation 'avg'

            if ($null -eq $recentValue -or $null -eq $previousValue) {
                $trends[$metricName] = 'unknown'
                continue
            }

            $diff = $recentValue - $previousValue
            $percentChange = if ($previousValue -ne 0) { ($diff / $previousValue) * 100 } else { 0 }

            # For metrics where lower is better
            $isLowerBetter = $metricName -match '(?i)(latency|failure|error)'

            if ([math]::Abs($percentChange) -lt 5) {
                $trends[$metricName] = 'stable'
            }
            elseif ($percentChange -gt 0) {
                $trends[$metricName] = if ($isLowerBetter) { 'degrading' } else { 'improving' }
            }
            else {
                $trends[$metricName] = if ($isLowerBetter) { 'improving' } else { 'degrading' }
            }
        }

        return $trends
    }
}

<#
.SYNOPSIS
    Rotates telemetry files older than the retention period.

.DESCRIPTION
    Removes telemetry data older than 30 days to manage disk usage.
    Should be run periodically as a maintenance task.

.PARAMETER DryRun
    If specified, shows what would be deleted without actually deleting.

.OUTPUTS
    System.Collections.Hashtable containing rotation results.

.EXAMPLE
    PS C:\> Invoke-TelemetryRotation -DryRun
    
    Shows what files would be rotated without deleting them.
#>
function Invoke-TelemetryRotation {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [switch]$DryRun
    )

    process {
        $cutoff = [DateTime]::UtcNow.AddDays(-$script:TelemetryRetentionDays)
        $deletedCount = 0
        $deletedSize = 0
        $errors = @()

        if (-not (Test-Path -LiteralPath $script:TelemetryDirectory)) {
            return @{
                rotatedFiles = 0
                freedBytes = 0
                cutoffDate = $cutoff.ToString('o')
                errors = @()
            }
        }

        # Get all JSONL files in telemetry directory
        $files = Get-ChildItem -Path $script:TelemetryDirectory -Recurse -Filter "*.jsonl" -ErrorAction SilentlyContinue

        foreach ($file in $files) {
            try {
                # Read file and filter old entries
                $lines = Get-Content -LiteralPath $file.FullName -Encoding UTF8
                $newLines = @()
                $removedCount = 0

                foreach ($line in $lines) {
                    if ([string]::IsNullOrWhiteSpace($line)) {
                        $newLines += $line
                        continue
                    }

                    try {
                        $entry = $line | ConvertFrom-Json
                        $entryTime = [DateTime]::Parse($entry.timestamp)

                        if ($entryTime -ge $cutoff) {
                            $newLines += $line
                        }
                        else {
                            $removedCount++
                        }
                    }
                    catch {
                        # Keep lines that can't be parsed
                        $newLines += $line
                    }
                }

                if ($removedCount -gt 0) {
                    $originalSize = $file.Length

                    if (-not $DryRun) {
                        if ($newLines.Count -eq 0) {
                            # Remove empty files
                            Remove-Item -LiteralPath $file.FullName -Force
                        }
                        else {
                            # Rewrite file with filtered content
                            $newLines | Set-Content -LiteralPath $file.FullName -Encoding UTF8 -Force
                        }
                    }

                    $deletedCount++
                    $newSize = if ($DryRun) { $originalSize * ($newLines.Count / $lines.Count) } else { (Get-Item $file.FullName).Length }
                    $deletedSize += $originalSize - $newSize
                }
            }
            catch {
                $errors += "Failed to process $($file.FullName): $_"
            }
        }

        return @{
            rotatedFiles = $deletedCount
            freedBytes = [math]::Round($deletedSize)
            cutoffDate = $cutoff.ToString('o')
            dryRun = $DryRun.IsPresent
            errors = $errors
        }
    }
}

# Export module members
Export-ModuleMember -Function @(
    'New-PackSLO',
    'Record-Telemetry',
    'Get-PackSLOStatus',
    'Test-SLOCompliance',
    'Get-TelemetryMetrics',
    'Get-PackHealthDashboard',
    'Get-SLOViolations',
    'Register-SLOViolation',
    'Get-TelemetrySummary',
    'Export-PackSLO',
    'Import-PackSLO',
    'Invoke-TelemetryRotation'
)
